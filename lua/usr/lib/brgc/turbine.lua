local computer = require("computer")
local component = require("component")
local oop = require("oop")
local config_api = require("brgc/config")
local turbineState = require("brgc/turbine_state")


local gRPMDanger = 1950
local gRPMMax = 1850
local gRPMMin = 750
local gRPMSkipHigh = 1450
local gRPMSkipLow = 980
local gEnergyStoredMax = 1000000
local gNumTurbinesTransient = 0

local turbineStateData = {
--[[
	[turbineState.ERROR]		= { active = false, inductor = true }
	[turbineState.OFFLINE]		= { active = false, inductor = false }
	[turbineState.STARTING]		= { active = false, inductor = false }
	[turbineState.CALIBRATING]	= { active = true, inductor = true }
	[turbineState.KICKOFF]		= { active = true, inductor = false }
	[turbineState.SPINUP]		= { active = true, inductor = false }
	[turbineState.SPINUP_SLOW]	= { active = true, inductor = true }
	[turbineState.SPINDOWN]		= { active = false, inductor = true }
	[turbineState.SPINDOWN_FAST]= { active = false, inductor = true }
	[turbineState.STABLE]		= { active = true, inductor = true }
	[turbineState.SUSPENDED]	= { active = false, inductor = false }
--]]
}

turbineStateData[turbineState.ERROR]		= { active = false, inductor = true }
turbineStateData[turbineState.OFFLINE]		= { active = false, inductor = false }
turbineStateData[turbineState.STARTING]		= { active = false, inductor = false }
turbineStateData[turbineState.CALIBRATING]	= { active = true, inductor = true }
turbineStateData[turbineState.KICKOFF]		= { active = true, inductor = false }
turbineStateData[turbineState.SPINUP]		= { active = true, inductor = false }
turbineStateData[turbineState.SPINUP_SLOW]	= { active = true, inductor = true }
turbineStateData[turbineState.SPINDOWN]		= { active = false, inductor = true }
turbineStateData[turbineState.SPINDOWN_FAST]= { active = false, inductor = true }
turbineStateData[turbineState.STABLE]		= { active = true, inductor = true }
turbineStateData[turbineState.SUSPENDED]	= { active = false, inductor = false }


local turbine = {
	mAddress = nil,
	mComponent = nil,
	mSteamMax = nil,
	mRPMTarget = 0,
	mEnergyStoredTarget = gEnergyStoredMax / 2,

	mState = turbineState.OFFLINE,

	mTurbineConfig = {
		outputRateMax = nil,
		rpmMax = nil,
		disabled = false,
		independent = false
	},

	mTurbineStats = {
		outputRateCurrent = 0,
		outputExtractionRate = 0,

		outputStoredCurrent = 0,
		outputStoredLast = 0,
		outputStoredRate = 0,
		outputCapacity = 0,

		rpmCurrent = 0,
		rpmLast = 0,
		rpmRate = 0,

		steamRate = 0,

		tickLast = 0,
		timeDiff = 0
	}
}
oop.make(turbine)

function turbine:construct(address, config)
	checkArg(1, address, "string")
	checkArg(2, config, "table", "nil")

	self.mAddress = address
	self.mTurbineConfig = config or { }
	self.mTurbineStats = { }

	setmetatable(self.mTurbineConfig, {__index = turbine.mTurbineConfig})
	setmetatable(self.mTurbineStats, {__index = turbine.mTurbineStats})
end

function turbine:connect()
	self.mComponent = component.proxy(self.mAddress)
	if self.mComponent == nil then
		return false
	end
	self.mSteamMax = 25 * self.mComponent.getNumberOfBlades()
	self:updateStats()

	if not self:isDisabled() then
		self:setState(turbineState.STARTING)
	end

	return true
end

function turbine:isConnected()
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

function turbine:isReady()
	local isAssembled = true

	if self.mComponent.mbIsAssembled then
		local success, state = pcall(self.mComponent.mbIsAssembled)

		isAssembled = success and state
	end

	return isAssembled
end

function turbine:getAddress()
	return self.mAddress
end

function turbine:getAddressShort()
	return string.sub(self.mAddress,1,3)
end

function turbine:isDisabled()
	return not not self.mTurbineConfig.disabled
end

function turbine:setDisabled(disabled)
	-- Don't update if nothing changed. Saves some i/o.
	if self.mTurbineConfig.disabled ~= not not disabled then
		self.mTurbineConfig.disabled = not not disabled
		config_api.setTurbine(self:getAddress(), self.mTurbineConfig)
	end
end

function turbine:isIndependent()
	return self.mTurbineConfig.independent
end

function turbine:setIndependent(independent)
	-- Don't update if nothing changed. Saves some i/o.
	if self.mTurbineConfig.independent ~= not not independent then
		self.mTurbineConfig.independent = not not independent
		config_api.setTurbine(self:getAddress(), self.mTurbineConfig)
	end
end

function turbine:isCalibrated()
	return self:getRPMMax() ~= nil
end

function turbine:getOutputStats()
	if self.mComponent.getEnergyStats then
		local stats = self.mComponent.getEnergyStats()
		return {
			outputStored = stats.energyStored,
			outputCapacity = stats.energyCapacity,
			outputProducedLastTick = stats.energyProducedLastTick
		}
	else
		return {
			outputStored = self.mComponent.getEnergyStored(),
			outputCapacity = gEnergyStoredMax,
			outputProducedLastTick = self.mComponent.getEnergyProducedLastTick()
		}
	end
end

function turbine:updateStats()
	-- If we're not connected, we can't do anything really.
	-- In otder to avoid computing wierd stuff as soon as the turbine reconnects,
	-- we're going to reset the stats instead.
	if not self:isConnected() then
		self.mTurbineConfig = { }
		setmetatable(self.mTurbineStats, {__index = turbine.mTurbineStats})
	end

	local now = computer.uptime() * 20
	local timediff = now - self.mTurbineStats.tickLast

	-- Did we advance at least on tick?
	if timediff <= 0 then
		-- We've already been called this tick. No need to do anything.
		-- This it NOT an optimization. Stuff will break if we go any further.
		return false
	end

	local outputStats = self:getOutputStats()

	-- Shift current stats to last stats
	self.mTurbineStats.outputStoredLast = self.mTurbineStats.outputStoredCurrent
	self.mTurbineStats.rpmLast = self.mTurbineStats.rpmCurrent

	-- Update raw stats
	self.mTurbineStats.outputRateCurrent = outputStats.outputProducedLastTick
	self.mTurbineStats.outputStoredCurrent = outputStats.outputStored
	self.mTurbineStats.outputCapacity = outputStats.outputCapacity
	self.mTurbineStats.rpmCurrent = self.mComponent.getRotorSpeed()
	self.mTurbineStats.steamRate = self:getSteamRateDirect()

	-- Update rates
	-- If tickLast is 0 then this is the first iteration and we can't compute any rates.
	if self.mTurbineStats.tickLast > 0 then
		self.mTurbineStats.outputStoredRate = ( self.mTurbineStats.outputStoredCurrent - self.mTurbineStats.outputStoredLast ) / timediff
		self.mTurbineStats.outputExtractionRate = math.max( 0, self.mTurbineStats.outputRateCurrent - self.mTurbineStats.outputStoredRate )
		self.mTurbineStats.rpmRate = ( self.mTurbineStats.rpmCurrent - self.mTurbineStats.rpmLast ) / timediff
	end

	self.mTurbineStats.tickLast = now
	self.mTurbineStats.timeDiff = timediff
	-- Fail for the first time so nobody can accidentally run the statemachine and crash.
	return ( timediff ~= now )
end

-- Getters related to rotor speed (RPM)

function turbine:getRPM()
	return self.mTurbineStats.rpmCurrent
end

function turbine:getRPMMax()
	return self.mTurbineConfig.rpmMax
end

function turbine:getRPMRate()
	return self.mTurbineStats.rpmRate
end

function turbine:getRPMOptimal()
	return self.mTurbineConfig.rpmMax
end

function turbine:getRPMTarget()
	return self.mRPMTarget
end

function turbine:setRPMTarget(rpm)
	checkArg(1, rpm, "number")
	self.mRPMTarget = rpm
end

-- Getters related to the turbines output

function turbine:getOutputGenerationRate()
	return self.mTurbineStats.outputRateCurrent
end

function turbine:getOutputGenerationRateMax()
	return self.mTurbineConfig.outputRateMax
end

function turbine:getOutputExtractionRate()
	return self.mTurbineStats.outputExtractionRate
end

function turbine:getOptimalOutputGenerationRate()
	return self.mTurbineConfig.outputRateMax
end

function turbine:getOutputStored()
	return self.mTurbineStats.outputStoredCurrent
end

function turbine:getOutputStoredRate()
	return self.mTurbineStats.outputStoredRate
end

function turbine:getOutputStoredMax()
	return self.mTurbineStats.outputCapacity
end

function turbine:estimateOutputGenerationRate()
	if turbineStateData[self:getState()].inductor then
		return self:getOutputGenerationRate()
	else
		return self:getOutputGenerationRateMax() * self:RPM2Percent(self:getRPM())
	end
end

-- Getters related to steam

function turbine:getSteamRateDirect()
	return self.mComponent.getFluidFlowRateMax()
end

function turbine:getSteamRate()
	return self.mTurbineStats.steamRate
end

function turbine:setSteamRate(rate)
	checkArg(1, rate, "number")
	self.mComponent.setFluidFlowRateMax(rate)
	self.mTurbineStats.streamRate = self:getSteamRateDirect()
end

--

function turbine:getState()
	return self.mState
end

function turbine:setState(state)
	local oldStateStable = turbineStateData[self.mState].inductor or not turbineStateData[self.mState].active
	local newStateStable = turbineStateData[state].inductor or not turbineStateData[state].active
	local oldState = self.mState
	local rpmCurrent = self:getRPM()
	local rpmMax = self:getRPMMax()

	if oldStateStable and not newStateStable then
		gNumTurbinesTransient = gNumTurbinesTransient + 1
	elseif not oldStateStable and newStateStable then
		gNumTurbinesTransient = gNumTurbinesTransient - 1
	end

	self.mState = state
	self.mComponent.setInductorEngaged(turbineStateData[state].inductor)
	self.mComponent.setActive(turbineStateData[state].active)

	if state == turbineState.STARTING then
		if rpmMax == nil and rpmCurrent >= 1700 then
			self:setState(turbineState.CALIBRATING)
		elseif rpmMax == nil then
			self:setState(turbineState.KICKOFF)
		elseif rpmMax ~= nil and (
										rpmCurrent >= rpmMax * 0.95 and oldState ~= turbineState.SUSPENDED or
										rpmCurrent >= gRPMSkipHigh and oldState == turbineState.SUSPENDED or
										rpmCurrent >= gRPMMin and rpmCurrent <= gRPMSkipLow) then

			self:setState(turbineState.STABLE)
			self:setRPM(rpmCurrent, true)
		else
			if rpmCurrent >= gRPMMin * 0.9 and rpmCurrent <= gRPMSkipLow then
				self.mRPMTarget = gRPMMin + (gRPMSkipLow - gRPMMin) / 2
			else
				self.mRPMTarget = rpmMax * 0.95
			end
			self:setState(turbineState.KICKOFF)
		end
	elseif state == turbineState.KICKOFF or state == turbineState.CALIBRATING then
		self:setOutput(1, true)
	end
end

function turbine:isRPMStable()
	-- return math.floor(self.mRPMLast * 250 + 0.5) == math.floor(self:getRPM() * 250 + 0.5)
	return math.abs(self:getRPMRate()) < 0.00025
end

function turbine:setRPM(targetrpm, ignorecurrent)
	checkArg(1, targetrpm, "number")
	checkArg(2, ignorecurrent, "boolean", "nil")

	local rpmCurrent = self:getRPM()

	if targetrpm > gRPMMax then
		targetrpm = gRPMMax
	elseif targetrpm < gRPMMin then
		targetrpm = gRPMMin
	end

	if not ignorecurrent then
		if rpmCurrent  >= gRPMSkipHigh * 0.95 and targetrpm < gRPMSkipHigh then
			if targetrpm > (gRPMSkipHigh+gRPMSkipLow) / 2 or rpmCurrent * 0.99 >= gRPMSkipHigh then
				targetrpm = gRPMSkipHigh
				if math.sqrt(rpmCurrent) * 0.995 > math.sqrt(targetrpm) then
					self:setState(turbineState.SPINDOWN_FAST)
				end
			else
				targetrpm = (gRPMMin + gRPMSkipLow) / 2
				self:setState(turbineState.SPINDOWN)
			end
		elseif rpmCurrent * 0.95 <= gRPMSkipLow and targetrpm > gRPMSkipLow then
			if gNumTurbinesTransient > 0 or targetrpm < (gRPMSkipHigh+gRPMSkipLow) / 2 or rpmCurrent <= gRPMSkipLow * 0.99 then
				targetrpm = gRPMSkipLow
				if math.sqrt(rpmCurrent) < math.sqrt(targetrpm) * 0.98 then
					self:setState(turbineState.SPINUP_SLOW)
				end
			else
				targetrpm = (gRPMMax + gRPMSkipHigh) / 2
				self:setState(turbineState.SPINUP)
			end
		end
	end

	if math.sqrt(rpmCurrent) * 0.992 > math.sqrt(targetrpm) and (self.mState == turbineState.STABLE or self.mState == turbineState.SPINUP_SLOW) then
		self:setState(turbineState.SPINDOWN_FAST)
	elseif math.sqrt(rpmCurrent) < math.sqrt(targetrpm) * 0.98 and (self.mState == turbineState.STABLE or self.mState == turbineState.SPINDOWN_FAST) then
		self:setState(turbineState.SPINUP_SLOW)
	end

	self.mRPMTarget = targetrpm
	if self.mState == turbineState.SPINUP_SLOW or self.mState == turbineState.SPINUP then
		self:setSteamRate(self.mSteamMax)
	else
		self:setSteamRate(self:RPM2Steam(targetrpm))
	end
end

function turbine:RPM2Steam(rpm)
	checkArg(1, rpm, "number")

	return (rpm / self:getRPMMax()) * self.mSteamMax
end

function turbine:RPM2Percent(rpm)
	checkArg(1, rpm, "number")

	if rpm >= gRPMSkipHigh then
		return math.max(1, rpm / self:getRPMMax())
	elseif rpm >= gRPMMin and rpm <= gRPMSkipLow then
		return rpm / gRPMSkipLow / 2
	else
		return 0
	end
end

function turbine:Percent2RPM(percent)
	checkArg(1, percent, "number")

	if percent >= 0.5 then
		return gRPMSkipHigh + (self:getRPMMax() - gRPMSkipHigh) * (percent - 0.5) * 2
	else
		return gRPMSkipLow * percent * 2
	end
end

function turbine:setOutput(output, force)
	checkArg(1, output, "number")

	if self:getRPMMax() == nil then
		self:setSteamRate(self.mSteamMax)
	else
		self.mRPMTarget = self:Percent2RPM(output)
		self:setRPM(self.mRPMTarget, force)
	end
end

function turbine:isActive()
	return self.mState ~= turbineState.SUSPENDED and self.mState ~= turbineState.OFFLINE and self.mState ~= turbineState.ERROR
end

function turbine:isOverburdened()
	return self:isActive() and self:getRPMMax() ~= nil and self:getRPM() >= self:getRPMMax() * 0.95 and self:getOutputStored() <= self:getOutputGenerationRate() * 2 and self.mComponent.getInductorEngaged()
end

function turbine:readyForSuspend()
	return turbine:isActive() and self:getRPM() * 0.95 <= gRPMMin and self:getOutputStored() >= self:getOutputStoredMax() - self:getOutputGenerationRate() * 2
end

function turbine:needsHelp()
	return self:isActive() and (self:getOutputStored() <= self:getOutputGenerationRate() * 2 or (self:getOutputStored() <= self:getOutputStoredMax()/4 and self:getOutputStoredRate() < 0 ))
end

function turbine:isTransient()
	return turbineStateData[self.mState].active and not turbineStateData[self.mState].inductor
end

function turbine:recalibrate()
	self:setState(turbineState.OFFLINE)

	self.mTurbineConfig = {
		disabled = self.mTurbineConfig.disabled,
		independent = self.mTurbineConfig.independent
	}
	self.mTurbineStats = { }
	setmetatable(self.mTurbineConfig, {__index = turbine.mTurbineConfig})
	setmetatable(self.mTurbineStats, {__index = turbine.mTurbineStats})

	config_api.setTurbine(self:getAddress(), self.mTurbineConfig)
	self:setState(turbineState.STARTING)
end

function turbine:runStateMachine()
	-- Before we run anything we try to update the turbines stats.
	-- If this function fails the stats have either been cleared
	-- or they're incomplete so we return early.
	if not self:updateStats() then
		return
	end

	local rpmCurrent = self:getRPM()
	local steamUsageMax = self:getSteamRate()

	if rpmCurrent >= gRPMDanger then
		self:setState(turbineState.ERROR)
	elseif self.mState == turbineState.CALIBRATING then
		if self:isRPMStable() then
			self.mTurbineConfig.rpmMax = rpmCurrent
			self.mTurbineConfig.outputRateMax = self:getOutputGenerationRate()
			config_api.setTurbine(self:getAddress(), self.mTurbineConfig)
			self:setState(turbineState.STABLE)
		end
	elseif self.mState == turbineState.KICKOFF then
		if not self:isCalibrated() and rpmCurrent >= 1780 then
			self:setState(turbineState.CALIBRATING)
		elseif self:isCalibrated() and rpmCurrent >= self.mRPMTarget then
			self:setState(turbineState.STABLE)
			self:setRPM(rpmCurrent, true)
		end
	elseif self.mState == turbineState.SPINDOWN then
		if self.mRPMTarget >= rpmCurrent * 0.95 then
			self:setState(turbineState.STABLE)
		end
	elseif self.mState == turbineState.SPINUP then
		if rpmCurrent >= self.mRPMTarget * 0.95 then
			self:setState(turbineState.STABLE)
		end
	elseif self.mState == turbineState.SPINUP_SLOW then
		if self:RPM2Steam(rpmCurrent) >= steamUsageMax * 0.98 then
			self:setState(turbineState.STABLE)
		end
		self:regulate()
	elseif self.mState == turbineState.SPINDOWN_FAST then
		if self:RPM2Steam(rpmCurrent) * 0.98 <= steamUsageMax then
			self:setState(turbineState.STABLE)
		end
		self:regulate()
	elseif self.mState == turbineState.STABLE then
		self:regulate()
	end
end

function turbine:regulate()
	local energyStored = self:getOutputStored()
	local energyStoredRate = self:getOutputStoredRate()
	local energyTargetDelta = self.mEnergyStoredTarget - energyStored
	local targetEnergyProduction

	local pEnergyStoredDelta = 0
	local pEnergyProductionDelta = 0
	local energyOffset

	if energyStored < 1 and energyStoredRate < 1 then
		targetEnergyProduction = self:getOutputGenerationRateMax()
	elseif energyStored >= self:getOutputStoredMax() - self:getOutputGenerationRate() and energyStoredRate >= 0 then
		targetEnergyProduction = 0
	else
		targetEnergyProduction = self:getOutputExtractionRate()
		pEnergyStoredDelta = energyTargetDelta / self:getOutputStoredMax()
		pEnergyProductionDelta = 0-energyStoredRate / self:getOutputGenerationRateMax()
	end

	energyOffset = pEnergyStoredDelta * 0.55 + pEnergyProductionDelta * 5

	self:setOutput( targetEnergyProduction / self:getOutputGenerationRateMax() + energyOffset )
end


return turbine
