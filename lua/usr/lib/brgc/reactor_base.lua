local computer = require("computer")
local component = require("component")
local oop = require("oop")
local config_api = require("brgc/config")
local reactorState = require("brgc/reactor_state")
local regulationState = require("brgc/regulation_state")
local calibration_ringbuffer = require("brgc/calibration_ringbuffer")
local polynomial = require("polynomial")

local reactorCalibrationMaxOutput = {0.01,0.02,0.05,0.1,0.15,0.2,0.25,0.3,0.35,0.4,0.5,0.6,0.7,0.75,0.8,0.9,1}

local reactor_base = {
	mAddress = nil,
	mComponent = nil,
	mPassive = nil,
	mRodNum = 0,
	mRodLevelState = nil,
	mRodLevel = 0,
	mRodTarget = 0,
	mRodOffset = 0,
	mOutputRateOpt = 0,
	mOutputRateMax = 0,
	mState = reactorState.OFFLINE,
	mRegulationState = regulationState.NONE,

	mReactorConfig = {
		rodLevelMin = 0,
		outputOpt = 0,
		outputPoly = nil,
		outputReversePoly = polynomial.make({0, 1}),
		regulationBehaviour = regulationState.GRID,
		disabled = false,
		PWMLevelOnline = 0.15,
		PWMLevelOffline = 0.8,
	},

	mReactorStats = {
		outputRateCurrent = 0,
		outputExtractionRate = 0,

		outputStoredCurrent = 0,
		outputStoredLast = 0,
		outputStoredRate = 0,
		outputCapacity = 0,

		temperatureFuelCurrent = 0,
		temperatureFuelLast = 0,
		temperatureFuelRate = 0,

		fuelLevel = 0,
		fuelRate = 0,

		tickLast = 0,
		timeDiff = 0
	},

	-- calibration stuff
	mCalibrationData = nil,
	mCalibrationStep = nil,
	mCalibrationTemperatureRingbuffer = nil,
	mCalibrationValueRingbuffer = nil,
	mCalibrationTemperatureDeviationRingbuffer = nil,
	mCalibrationValueDeviationRingbuffer = nil
}
oop.make(reactor_base)

function reactor_base:construct(address, config)
	checkArg(1, address, "string")
	checkArg(2, config, "table", "nil")

	self.mAddress = address
	self.mReactorConfig = config or { }
	self.mReactorStats = { }

	setmetatable(self.mReactorConfig, {__index = reactor_base.mReactorConfig})
	setmetatable(self.mReactorStats, {__index = reactor_base.mReactorStats})

	if config ~= nil then
		if type(config.outputPoly) == "table" and type(config.outputPoly.coefs) == "table" then
			self.mReactorConfig.outputPoly = polynomial.make(config.outputPoly.coefs)
		else
			self.mReactorConfig.outputPoly = nil
		end
		if type(config.outputReversePoly) == "table" and type(config.outputReversePoly.coefs) == "table" then
			self.mReactorConfig.outputReversePoly = polynomial.make(config.outputReversePoly.coefs)
		else
			self.mReactorConfig.outputReversePoly = nil
		end
	end
end

function reactor_base:connect()
	self.mComponent = component.proxy(self.mAddress)
	if self.mComponent == nil then
		return false
	end
	self.mPassive = not self.mComponent.isActivelyCooled()
	self.mRodNum = self.mComponent.getNumberOfControlRods()
	self:updateStats()

	if self.init and not self:isDisabled() then
		self:init()
	end

	return true
end

function reactor_base:isConnected()
	if not self.mComponent then
		return false
	elseif self.mComponent.mbIsConnected then
		-- New API
		local success, state = pcall(self.mComponent.mbIsConnected)

		return success and state
	elseif self.mComponent.getConnected then
		-- Old API
		local success, state = pcall(self.mComponent.getConnected)

		return success and state
	end

	-- Nothing of the above is true? Welp... we don't seem to be connected then!
	return false
end

function reactor_base:isReady()
	local isAssembled = true

	if self.mComponent.mbIsAssembled then
		local success, state = pcall(self.mComponent.mbIsAssembled)

		isAssembled = success and state
	end

	return isAssembled
end

function reactor_base:isActivelyCooled()
	return not self.mPassive
end

function reactor_base:isDisabled()
	return not not self.mReactorConfig.disabled
end

function reactor_base:getState()
	return self.mState
end

function reactor_base:getAddress()
	return self.mAddress
end

function reactor_base:getAddressShort()
	return string.sub(self.mAddress, 1, 3)
end

function reactor_base:getOutputOpt()
	return self.mReactorConfig.outputOpt
end

function reactor_base:getRegulationBehaviour()
	return self.mReactorConfig.regulationBehaviour
end

function reactor_base:setRegulationBehaviour(behaviour)
	assert(behaviour == regulationState.AUTO or behaviour == regulationState.PWM or behaviour == regulationState.LOAD or behaviour == regulationState.GRID, "Invalid behaviour")
	self.mReactorConfig.regulationBehaviour = behaviour
	config_api.setReactor(self:getAddress(), self.mReactorConfig)
end

function reactor_base:getRegulationBehaviour()
	return self.mReactorConfig.regulationBehaviour
end

function reactor_base:setDisabled(disabled)
	-- Don't update if nothing changed. Saves some i/o.
	if self.mReactorConfig.disabled ~= not not disabled then
		self.mReactorConfig.disabled = not not disabled
		config_api.setReactor(self:getAddress(), self.mReactorConfig)
	end
end

function reactor_base:getFuelStats()
	if self.mComponent.getFuelStats then
		return self.mComponent.getFuelStats()
	else
		return {
			fuelTemperature = self.mComponent.getFuelTemperature(),
			fuelAmount = self.mComponent.getFuelAmount(),
			wasteAmount = self.mComponent.getWasteAmount(),
			fuelCapacity = self.mComponent.getFuelAmountMax(),
			fuelConsumedLastTick = self.mComponent.getFuelConsumedLastTick()
		}
	end
end

function reactor_base:updateStats()
	-- If we're not connected, we can't do anything really.
	-- In order to avoid computing wierd stuff as soon as the reactor reconnects,
	-- we're going to reset the stats instead.
	if not self:isConnected() then
		self.mReactorStats = { }
		setmetatable(self.mReactorStats, {__index = reactor_base.mReactorStats})
		return false
	end

	local now = computer.uptime() * 20
	local timediff = now - self.mReactorStats.tickLast

	-- Did we advance at least one tick?
	if timediff <= 0 then
		-- We've already been called this tick. No need to do anything.
		-- This it NOT an optimization. Stuff will break if we go any further.
		return false
	end

	local outputStats = self:getOutputStats()
	local fuelStats = self:getFuelStats()

	-- Shift current stats to last stats
	self.mReactorStats.outputStoredLast = self.mReactorStats.outputStoredCurrent
	self.mReactorStats.temperatureFuelLast = self.mReactorStats.temperatureFuelCurrent

	-- Update output stats
	self.mReactorStats.outputRateCurrent = outputStats.outputProducedLastTick
	self.mReactorStats.outputStoredCurrent = outputStats.outputStored
	self.mReactorStats.outputCapacity = outputStats.outputCapacity

	-- Update fuel stats
	self.mReactorStats.temperatureFuelCurrent = fuelStats.fuelTemperature
	-- TODO: Once waste is returned by this, add that as well
	self.mReactorStats.fuelLevel = (fuelStats.fuelAmount + fuelStats.wasteAmount / 100) / fuelStats.fuelCapacity
	self.mReactorStats.fuelRate = fuelStats.fuelConsumedLastTick

	-- Update rates
	-- If tickLast is 0 then this is the first iteration and we can't compute any rates.
	if self.mReactorStats.tickLast > 0 then
		self.mReactorStats.outputStoredRate = ( self.mReactorStats.outputStoredCurrent - self.mReactorStats.outputStoredLast ) / timediff
		self.mReactorStats.outputExtractionRate = math.max( 0, self.mReactorStats.outputRateCurrent - self.mReactorStats.outputStoredRate )
		self.mReactorStats.temperatureFuelRate = ( self.mReactorStats.temperatureFuelCurrent - self.mReactorStats.temperatureFuelLast ) / timediff
	end

	self.mReactorStats.tickLast = now
	self.mReactorStats.timeDiff = timediff
	-- Fail for the first time so nobody can accidentally run the statemachine and crash.
	return (timediff ~= now)
end

-- Getters related to fuel temperature

function reactor_base:getFuelTemperature()
	return self.mReactorStats.temperatureFuelCurrent
end

function reactor_base:getNormalizedFuelTemperature()
	local fuelLevel = self:getFuelLevel()
	if fuelLevel == 0 then
		return 0
	else
		return self:getFuelTemperature() / fuelLevel
	end
end

function reactor_base:getFuelTemperatureRate()
	return self.mReactorStats.temperatureFuelRate
end

-- Getters related to fuel consumption

function reactor_base:getFuelConsumedLastTick()
	return self.mReactorStats.fuelRate
end

-- Getters related to the fuel tank

function reactor_base:getFuelLevel()
	return self.mReactorStats.fuelLevel
end

-- Getters related to the reactors output

function reactor_base:getOutputGenerationRate()
	return self.mReactorStats.outputRateCurrent
end

function reactor_base:getOutputGenerationRateMax()
	return self.mOutputRateMax
end

function reactor_base:getNormalizedOutputGenerationRate()
	local fuelLevel = self:getFuelLevel()
	if fuelLevel == 0 then
		return 0
	else
		return self:getOutputGenerationRate() / fuelLevel
	end
end

function reactor_base:getOutputExtractionRate()
	return self.mReactorStats.outputExtractionRate
end

function reactor_base:getOptimalOutputGenerationRate()
	return self.mOutputRateOpt
end

function reactor_base:getCurrentOptimalOutputGenerationRate()
	-- This is only an approximation. The correct value requires the fuel level
	-- to be multiplied with the rod level and then put through the polynome
	return self:getOptimalOutputGenerationRate() * self:getFuelLevel()
end

function reactor_base:getOutputStored()
	return self.mReactorStats.outputStoredCurrent
end

function reactor_base:getOutputStoredMax()
	return self.mReactorStats.outputCapacity
end

function reactor_base:getOutputStoredRate()
	return self.mReactorStats.outputStoredRate
end

function reactor_base:isCalibrated()
	return self:getOptimalOutputGenerationRate() ~= nil and self.mReactorConfig.outputPoly ~= nil
end

-- Rod logic

function reactor_base:setRodLevelRaw(rawlevel)
	if self.mComponent.setControlRodsLevels then
		self:setRodLevelRawAPI2(rawlevel)
	elseif self.mComponent.setAllControlRodLevels and self.mComponent.setControlRodLevel then
		self:setRodLevelRawAPI1(rawlevel)
	else
		error('Unable to find appropriate API function for setting control rods on reactor ' .. self.mAddress)
	end
end

function reactor_base:getRodIdxFromCenter(idx)
	checkArg(1, idx, "number")

	local centerRodIdx = math.floor(self.mRodNum / 2)
	local rodIdxOffset = math.ceil(idx / 2)

	if idx % 2 == 0 then
		rodIdxOffset = 0 - rodIdxOffset
	end

	local actualIdx = centerRodIdx + rodIdxOffset

	if actualIdx == self.mRodNum then
		actualIdx = 0
	elseif actualIdx == -1 then
		actualIdx = self.mRodNum - 1
	end

	assert(actualIdx >= 0 and actualIdx < self.mRodNum, "Detected bug in rod idx calculation")

	return actualIdx
end

function reactor_base:setRodLevelRawAPI1(rawlevel)
	checkArg(1, rawlevel, "number")

	local rodLevel
	local rodLevelMin = self.mReactorConfig.rodLevelMin or 0
	local rodExtraLevel
	local rodLevelState

	if rawlevel > self.mRodNum * (100-rodLevelMin) then
		rawlevel = self.mRodNum * (100-rodLevelMin)
	elseif rawlevel < 0 then
		rawlevel = 0
	end

	self.mRodLevel = math.floor(rawlevel+0.5)
	local roadLevelf = rodLevelMin + rawlevel / self.mRodNum
	rodLevel = math.floor(roadLevelf)
	rodExtraLevel = math.floor((roadLevelf - rodLevel) * self.mRodNum + 0.5)

	if rodLevel > 100 then
		rodLevel = 100
		rodExtraLevel = 0
	end

	rodLevelState = rodLevel * self.mRodNum + rodExtraLevel

	-- If the combined rod level did not change, there is no need to call into
	-- the reactor API. We can leave things as they were.
	if self.mRodLevelState ~= rodLevelState then
		self.mRodLevelState = rodLevelState

		-- In order to minimize the API calls required to set all rods, we
		-- first set all rods to the rod level the majority of the rods have to
		-- be set to and afterwards correct the other rod leves.
		if rodExtraLevel <= self.mRodNum / 2 then
			self.mComponent.setAllControlRodLevels(rodLevel)
			for i=0, rodExtraLevel-1 do
				self:setRodLevelDirectFromCenterAPI1(i, rodLevel+1)
			end
		else
			self.mComponent.setAllControlRodLevels(rodLevel+1)
			for i=rodExtraLevel, self.mRodNum-1 do
				self:setRodLevelDirectFromCenterAPI1(i, rodLevel)
			end
		end
	end
end

function reactor_base:setRodLevelDirectFromCenterAPI1(idx, level)
	checkArg(1, idx, "number")
	checkArg(2, level, "number")

	if level < 0 or level > 100 then
		return
	end

	self.mComponent.setControlRodLevel(self:getRodIdxFromCenter(idx), level)
end

function reactor_base:setRodLevelRawAPI2(rawlevel)
	checkArg(1, rawlevel, "number")

	local rodLevel
	local rodLevelMin = self.mReactorConfig.rodLevelMin or 0
	local rodExtraLevel
	local rodLevelState

	if rawlevel > self.mRodNum * (100-rodLevelMin) then
		rawlevel = self.mRodNum * (100-rodLevelMin)
	elseif rawlevel < 0 then
		rawlevel = 0
	end

	self.mRodLevel = math.floor(rawlevel+0.5)
	local roadLevelf = rodLevelMin + rawlevel / self.mRodNum
	rodLevel = math.floor(roadLevelf)
	rodExtraLevel = math.floor((roadLevelf - rodLevel) * self.mRodNum + 0.5)

	if rodLevel > 100 then
		rodLevel = 100
		rodExtraLevel = 0
	end

	rodLevelState = rodLevel * self.mRodNum + rodExtraLevel

	local rodLevels = {}

	-- If the combined rod level did not change, there is no need to call into
	-- the reactor API. We can leave things as they were.
	if self.mRodLevelState ~= rodLevelState then
		self.mRodLevelState = rodLevelState

		for i=0, rodExtraLevel-1 do
			rodLevels[self:getRodIdxFromCenter(i)] = rodLevel+1
		end
		for i=rodExtraLevel, self.mRodNum-1 do
			rodLevels[self:getRodIdxFromCenter(i)] = rodLevel
		end

		self.mComponent.setControlRodsLevels(rodLevels)
	end
end

function reactor_base:translateFromLinearOutput(level)
	checkArg(1, level, "number")
	return self.mReactorConfig.outputReversePoly:eval(self.mOutputRateMax * level)
end

function reactor_base:translateToLinearOutput(level)
	checkArg(1, level, "number")
	return self.mReactorConfig.outputPoly:eval(level) / self.mOutputRateMax
end

function reactor_base:setOutput(levelpercent, offset)
	checkArg(1, levelpercent, "number")
	checkArg(2, offset, "number", "nil")

	local rodLevelMin = self.mReactorConfig.rodLevelMin or 0
	if offset ~= nil then
		self.mRodOffset = 0-self.mRodNum*(100-rodLevelMin)*offset
	end
	self.mRodTarget = self.mRodNum*(100-rodLevelMin)*(1-levelpercent)
	self:setRodLevelRaw( self.mRodTarget + self.mRodOffset )
end

function reactor_base:setOutputOffset(offsetpercent)
	checkArg(1, offsetpercent, "number")

	local rodLevelMin = self.mReactorConfig.rodLevelMin or 0
	self.mRodOffset = 0-self.mRodNum*(100-rodLevelMin)*offsetpercent
	self:setRodLevelRaw( self.mRodTarget + self.mRodOffset )
end

function reactor_base:getOutputOffset()
	if self.mReactorConfig.rodLevelMin == 100 then
		return 0
	else
		return 0-self.mRodOffset/(100-self.mReactorConfig.rodLevelMin)/self.mRodNum
	end
end

function reactor_base:getOutput()
	return math.max(0, math.min(1, 1 - (self.mRodTarget + self.mRodOffset) / (100 - self.mReactorConfig.rodLevelMin) / self.mRodNum))
end

function reactor_base:setActive(active)
	checkArg(1, active, "boolean")

	self.mComponent.setActive(active)
end

function reactor_base:setOutputPolynomialCoefs(coefs)
	checkArg(1, coefs, "table", "nil")

	if coefs ~= nil then
		self.mReactorConfig.outputPoly = polynomial.make(coefs.coefs or coefs)
	end
end

function reactor_base:setOutputReversePolynomialCoefs(coefs)
	checkArg(1, coefs, "table", "nil")

	if coefs ~= nil then
		self.mReactorConfig.outputReversePoly = polynomial.make(coefs.coefs or coefs)
	end
end

function reactor_base:recalculateOpts()
	if self.mReactorConfig.outputPoly ~= nil and self.mReactorConfig.outputReversePoly ~= nil then
		self.mOutputRateMax = self.mReactorConfig.outputPoly:eval(1)
		self.mOutputRateOpt = self.mReactorConfig.outputPoly:eval(self.mReactorConfig.outputOpt)
	end
end

function reactor_base:setState(state)
	self.mState = state

	if state == reactorState.ERROR or state == reactorState.OFFLINE then
		self.mComponent.setActive(false)
	elseif state == reactorState.CALIBRATING then
		self.mCalibrationData = {}
		self.mCalibrationStep = 1
		self:setOutput(reactorCalibrationMaxOutput[1])
		self.mComponent.setActive(true)
	elseif state == reactorState.ONLINE then
		if not self:isCalibrated() then
			self:setState(reactorState.CALIBRATING)
		else
			self.mComponent.setActive(true)
		end
	else
		error("Invalid reactor state supplied: " + tostring(state))
	end
end

function reactor_base:recalibrate()
	self:setState(reactorState.OFFLINE)

	self.mReactorConfig = {
		regulationBehaviour = self.mReactorConfig.regulationBehaviour,
		disabled = self.mReactorConfig.disabled,
		PWMLevelOnline = self.mReactorConfig.PWMLevelOnline,
		PWMLevelOffline = self.mReactorConfig.PWMLevelOffline
	}
	self.mReactorStats = { }

	setmetatable(self.mReactorConfig, {__index = reactor_base.mReactorConfig})
	setmetatable(self.mReactorStats, {__index = reactor_base.mReactorStats})

	config_api.setReactor(self:getAddress(), self.mReactorConfig)
	self:setState(reactorState.ONLINE)
end

function reactor_base:initCalibrationBuffers()
	self.mCalibrationValueRingbuffer = calibration_ringbuffer(10)
	self.mCalibrationTemperatureRingbuffer = calibration_ringbuffer(10)
	self.mCalibrationValueDeviationRingbuffer = calibration_ringbuffer(10)
	self.mCalibrationTemperatureDeviationRingbuffer = calibration_ringbuffer(10)
end

function reactor_base:clearCalibrationBuffers()
	self.mCalibrationTemperatureRingbuffer = nil
	self.mCalibrationValueRingbuffer = nil
	self.mCalibrationTemperatureDeviationRingbuffer = nil
	self.mCalibrationValueDeviationRingbuffer = nil
end

function reactor_base:runCalibration()
	local calibValue = self:getNormalizedOutputGenerationRate()
	local calibTemp = self:getNormalizedFuelTemperature()

	if self.mCalibrationTemperatureRingbuffer == nil or self.mCalibrationValueRingbuffer == nil or self.mCalibrationTemperatureDeviationRingbuffer == nil or self.mCalibrationValueDeviationRingbuffer == nil then
		self:initCalibrationBuffers()
	end

	self.mCalibrationValueRingbuffer:push(calibValue)
	self.mCalibrationValueDeviationRingbuffer:push(self.mCalibrationValueRingbuffer:getStandardDeviation())

	self.mCalibrationTemperatureRingbuffer:push(calibTemp)
	self.mCalibrationTemperatureDeviationRingbuffer:push(self.mCalibrationTemperatureRingbuffer:getStandardDeviation())

	-- Scientific sure fire methods to find out if the reactor is in a stable
	-- condition. Both of these conditions need to be true for that to be the
	-- case.
	local nonMonotonic = not self.mCalibrationTemperatureRingbuffer:isMonotonic() and not self.mCalibrationValueRingbuffer:isMonotonic()
	local stable = not self.mCalibrationValueDeviationRingbuffer:isMonotonic() and not self.mCalibrationTemperatureDeviationRingbuffer:isMonotonic()

	-- Dirty hacks to allow faster calibration. Either one of these can replace
	-- the respective scientific calculation.
	local isCloseEnough = (math.abs(self.mCalibrationTemperatureRingbuffer:getAverage() - calibTemp) < self.mCalibrationTemperatureRingbuffer:getAverage() / 1000) and (self.mCalibrationTemperatureRingbuffer:count() == 10)
					or (math.abs(self.mCalibrationValueRingbuffer:getAverage() - calibValue) < self.mCalibrationValueRingbuffer:getAverage() / 1000) and (self.mCalibrationValueRingbuffer:count() == 10)
	local lowDeviation = self.mCalibrationTemperatureRingbuffer:getStandardDeviation() <= self.mCalibrationTemperatureRingbuffer:getAverage() / 1000
					and self.mCalibrationValueRingbuffer:getStandardDeviation() <= self.mCalibrationValueRingbuffer:getAverage() / 1000

	-- If you found this, congratulations ;)
	-- Here are some leftover debug prints that allow you to get an idea what's
	-- going on during reactor calibration.

--[[
	print(string.format( "temp avg: %.03f std: %.03f stable: %s",
		self.mCalibrationTemperatureRingbuffer:getAverage(),
		self.mCalibrationTemperatureRingbuffer:getStandardDeviation(),
		tostring(not self.mCalibrationTemperatureDeviationRingbuffer:isMonotonic())
	))
	print(string.format( "val  avg: %.03f std: %.03f stable: %s",
		self.mCalibrationValueRingbuffer:getAverage(),
		self.mCalibrationValueRingbuffer:getStandardDeviation(),
		tostring(not self.mCalibrationValueDeviationRingbuffer:isMonotonic())
	))
	print("nonMonotonic: " .. tostring(nonMonotonic) ..
		" lowDeviation: " .. tostring(lowDeviation) ..
		" stable: " .. tostring(stable) ..
		" isClose: " .. tostring(isCloseEnough)
	)
--]]
	if not self:isGood() then
		self:finalizeCalibration()
	elseif (nonMonotonic or isCloseEnough) and (lowDeviation or stable) then
		if calibValue ~= nil and reactorCalibrationMaxOutput[self.mCalibrationStep] ~= nil then
			if type(self.mCalibrationData) ~= "table" then
				self.mCalibrationData = { }
			end
			table.insert(self.mCalibrationData, {
				step = self.mCalibrationStep,
				load = reactorCalibrationMaxOutput[self.mCalibrationStep],
				value = self.mCalibrationValueRingbuffer:getAverage(),
				efficiency = self.mCalibrationValueRingbuffer:getAverage() / self:getFuelConsumedLastTick()
			})

--			print("----------")

			self.mCalibrationStep = self.mCalibrationStep + 1
			if reactorCalibrationMaxOutput[self.mCalibrationStep] ~= nil then
				self:initCalibrationBuffers()
				self:setOutput(reactorCalibrationMaxOutput[self.mCalibrationStep], 0)
			else
				self:clearCalibrationBuffers()
				self:finalizeCalibration()
			end
		else
			self:clearCalibrationBuffers()
			self:finalizeCalibration()
		end
	end
	self.mCalibrationValueLast = calibValue
end

function reactor_base:runStateMachine()
	-- Before we run anything we try to update the reactors stats.
	-- If this function fails the stats have either been cleared
	-- or they're incomplete so we return early.
	if not self:updateStats() then
		return
	end

	if self.mState == reactorState.CALIBRATING then
		self:runCalibration()
	elseif self.mState == reactorState.ONLINE then
		self:regulate()
	end
end

return reactor_base
