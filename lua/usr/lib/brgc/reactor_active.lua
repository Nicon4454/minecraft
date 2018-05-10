local oop = require("oop")
local promise = require("promise")
local config_api = require("brgc/config")
local reactor_base = require("brgc/reactor_base")
local reactorState = require("brgc/reactor_state")
local polynomial_iterpolator = require("polynomial_iterpolator")
local polynomial = require("polynomial")

local reactor_active = {
	mSteamProductionTarget = 0
}
oop.inherit(reactor_active, reactor_base)

function reactor_active:construct(address, config)
	reactor_base.construct(self, address, config)
end

function reactor_active:init()
	self:setOutput(self.mSteamProductionTarget)
end

function reactor_active:getOutputStats()
	if self.mComponent.getHotFluidStats then
		local stats = self.mComponent.getHotFluidStats()
		return {
			outputStored = stats.fluidAmount,
			outputCapacity = stats.fluidCapacity,
			outputProducedLastTick = stats.fluidProducedLastTick
		}
	else
		return {
			outputStored = self.mComponent.getHotFluidAmount(),
			outputCapacity = self.mComponent.getHotFluidAmountMax(),
			outputProducedLastTick = self.mComponent.getHotFluidProducedLastTick()
		}
	end
end

function reactor_active:setSteamProductionTarget(steamtarget)
	self.mSteamProductionTarget = steamtarget
	self:setOutput(steamtarget / self:getOutputGenerationRateMax())
end

function reactor_active:regulate()
	local steamStored = self:getOutputStored()
	local steamProduced = self:getOutputGenerationRate()
	--[[
	local steamStoredTarget = math.min(
		self.mComponent.getCoolantAmount() - steamProduced / 2,
		3 * (self:getOutputStoredMax() - steamProduced) / 4
	) --math.min(self:getOutputStoredMax() - steamProduced * 1.1, self:getOutputStoredMax() / 4 * 3)
	--]]
	-- local steamStoredTarget = (self:getOutputStoredMax() - steamProduced*2)/2
	--[[
		local steamStoredTarget = math.min(
			self:getOutputStoredMax() - steamProduced * 1.1,
			self:getOutputStoredMax() / 4 * 3
		)
	--]]
	local steamStoredTarget = self:getOutputStoredMax() / 2
	if steamProduced > steamStoredTarget then
		steamStoredTarget = (self:getOutputStoredMax() - steamProduced*2)/2
	end
	local steamStoredDelta = steamStoredTarget - steamStored

	local pSteamStoredDelta = steamStoredDelta / self:getOutputStoredMax()
	local pSteamProductionDelta = 0-self:getOutputStoredRate() / self:getOutputGenerationRateMax()
	local pTemperatureLimit = 0-math.max(0, math.pow(1.5, (self:getFuelTemperature() - 700)/100) - 1) * 0.1

	local steamOffset = pSteamStoredDelta * 0.15 + pSteamProductionDelta * 0.35 + pTemperatureLimit
--	local steamOffset = pSteamStoredDelta * 0.007 + pSteamProductionDelta * 0.35 + pTemperatureLimit
	if steamStored + steamProduced >= self:getOutputStoredMax() * 0.99 then
		steamOffset = self:getOutputOffset() - 0.01
	end

--[[
	print("pSteamStoredDelta = " .. pSteamStoredDelta ..
		" pSteamProductionDelta = " .. pSteamProductionDelta ..
		" pTemperatureLimit = " .. pTemperatureLimit ..
		" steamOffset = " .. steamOffset ..
		" steamStoredTarget = " .. steamStoredTarget
	)
--]]
	self:setOutputOffset(steamOffset)
end

function reactor_active:isGood()
	local temperature = self:getFuelTemperature()
	local coolantThreshold = self:getOutputGenerationRate()
	local steamThreshold = self:getOutputStoredMax() - coolantThreshold

	return (temperature < 1500) and (self.mComponent.getCoolantAmount() >= coolantThreshold) and (self:getOutputStored() < steamThreshold)
end

function reactor_active:finalizeCalibration()
	local calibrationValue = 0
	local rodLevelMin = math.min(100, math.max(0, self.mReactorConfig.rodLevelMin or 0))

	if #self.mCalibrationData == 0 or rodLevelMin >= 100 then
		self:setState(reactorState.ERROR)
		return
	end

	for _,value in pairs(self.mCalibrationData) do
		calibrationValue = calibrationValue + value.value/value.load
	end
	calibrationValue = calibrationValue / #self.mCalibrationData * (100-rodLevelMin)/100

	local estMinRodInsertion = rodLevelMin/100
	local curMinRodInsertion = rodLevelMin/100
	local steamTankMax = self:getOutputStoredMax()

	if calibrationValue > steamTankMax then
		estMinRodInsertion = (1 - steamTankMax / calibrationValue)
		calibrationValue = steamTankMax
	end

	if curMinRodInsertion > estMinRodInsertion then
		calibrationValue = calibrationValue / (1-estMinRodInsertion) * (1-curMinRodInsertion)
		estMinRodInsertion = curMinRodInsertion
	end

	local efficiency_samples = {}
	for _, data in pairs(self.mCalibrationData) do
		table.insert(efficiency_samples, {
			data.load / (1-estMinRodInsertion),
			data.efficiency
		})
	end

	self:setState(reactorState.OFFLINE)
	promise(function()
		local poly_efficiency = polynomial_iterpolator.interpolate(efficiency_samples, math.min(5, #efficiency_samples - 1))

		return poly_efficiency
	end):after(function(reactor, poly_efficiency)
		reactor.mReactorConfig.rodLevelMin = estMinRodInsertion * 100
		reactor.mReactorConfig.outputPoly = polynomial.make({0, calibrationValue})
		reactor.mReactorConfig.outputReversePoly = polynomial.make({0, 1 / calibrationValue})
		reactor.mReactorConfig.outputOpt = math.max(0.01, math.min(1, poly_efficiency:converge(0, 10)))
		reactor:recalculateOpts()
	end, self):catch(function(reactor)
		reactor:setState(reactorState.ERROR)
	end, self):finally(function(reactor)
		reactor.mCalibrationData = nil
		reactor.mCalibrationStep = nil
		reactor.mCalibrationValueLast = nil

		if reactor:getState() ~= reactorState.ERROR then
			config_api.setReactor(reactor:getAddress(), reactor.mReactorConfig)

			reactor:setOutput(0, 0)
			reactor:setState(reactorState.ONLINE)
		end
	end, self)
end


return reactor_active