local oop = require("oop")
local promise = require("promise")
local config_api = require("brgc/config")
local reactorState = require("brgc/reactor_state")
local regulationState = require("brgc/regulation_state")
local reactor_base = require("brgc/reactor_base")
local polynomial_iterpolator = require("polynomial_iterpolator")

local gEnergyStoredMax = 10000000

local reactor_passive = {
	mEnergyStoredTarget = gEnergyStoredMax/2
}

oop.inherit(reactor_passive, reactor_base)

function reactor_passive:construct(address, config)
	reactor_base.construct(self, address, config)
end

function reactor_passive:getOutputStats()
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

function reactor_passive:regulate()
	local grid_controller = _G.package.loaded["brgc/grid_controller"]
	local behaviour = self:getRegulationBehaviour()
	if behaviour == regulationState.AUTO or ( behaviour == regulationState.GRID and (not grid_controller or not grid_controller.isRunning()) ) then
		local energyStored = self:getOutputStored()
		local energyLoad = self:getOutputExtractionRate()

		if self:getOptimalOutputGenerationRate() >= energyLoad and energyStored >= 2 * self:getOutputGenerationRate() then
			if self.mRegulationState == regulationState.LOAD then
				self:setOutput(self:getOutputOpt(), 0)
			end
			self.mRegulationState = regulationState.PWM
		elseif energyStored < self.mEnergyStoredTarget or energyLoad >= self:getOutputGenerationRateMax() then
			self.mRegulationState = regulationState.LOAD
		end
	elseif behaviour == regulationState.LOAD or behaviour == regulationState.PWM then
		if behaviour ~= self.mRegulationState and behaviour == regulationState.PWM then
			self:setOutput(self:getOutputOpt(), 0)
		end
		self.mRegulationState = behaviour
	elseif behaviour == regulationState.GRID then
		self.mRegulationState = regulationState.GRID
	end

	if self.mRegulationState == regulationState.PWM then
		self:regulatePWM()
	elseif self.mRegulationState == regulationState.LOAD then
		self:regulatePD()
	end
end

function reactor_passive:regulatePWM()
	local pEnergyStored = self:getOutputStored() / self:getOutputStoredMax()

	if pEnergyStored >= self.mReactorConfig.PWMLevelOffline then
		self:setOutput(0, 0)
	elseif pEnergyStored <= self.mReactorConfig.PWMLevelOnline then
		self:setOutput(self:getOutputOpt(), 0)
	end
end

function reactor_passive:regulatePD()
	local energyStored = self:getOutputStored()
	local energyStoredRate = self:getOutputStoredRate()
	local energyTargetDelta = self.mEnergyStoredTarget - energyStored
	local targetEnergyProduction

	local pEnergyStoredDelta = 0
	local pEnergyProductionDelta = 0

	if energyStored < 1 and energyStoredRate < 1 then
		targetEnergyProduction = self:getOutputGenerationRateMax()
	elseif energyStored >= self:getOutputStoredMax() - self:getOutputGenerationRate() and energyStoredRate >= 0 then
		targetEnergyProduction = 0
	else
		targetEnergyProduction = self:getOutputExtractionRate()
		pEnergyStoredDelta = energyTargetDelta / self:getOutputStoredMax()
		pEnergyProductionDelta = 0-energyStoredRate / self:getOutputGenerationRateMax()
	end

	local pTargetEnergyProduction = targetEnergyProduction / self:getOutputGenerationRateMax()

	self:regulatePD2(pTargetEnergyProduction, pEnergyStoredDelta, pEnergyProductionDelta)
end

function reactor_passive:regulatePD2(pTargetEnergyProduction, pEnergyStoredDelta, pEnergyProductionDelta)
	local energyOffset = pEnergyStoredDelta*1.25 + pEnergyProductionDelta

	self:setOutput( self:translateFromLinearOutput(pTargetEnergyProduction), energyOffset )
end

function reactor_passive.isGood()
	return true
end

function reactor_passive:finalizeCalibration()
	if #self.mCalibrationData < 6 or self.mReactorConfig.rodLevelMin >= 100 then
		self:setState(reactorState.ERROR)
		return
	end

	local rft_samples = {}
	local rft_reverse_samples = {}
	local efficiency_samples = {}

	for _, data in pairs(self.mCalibrationData) do
		table.insert(rft_samples, {
			data.load,
			data.value
		})
		table.insert(rft_reverse_samples, {
			data.value,
			data.load
		})
		table.insert(efficiency_samples, {
			data.load,
			data.efficiency
		})
	end

	self:setState(reactorState.OFFLINE)
	promise(function()
		local poly_output = polynomial_iterpolator.interpolate(rft_samples, 3)
		os.sleep()
		local poly_reverse_output = polynomial_iterpolator.interpolate(rft_reverse_samples, 5)
		os.sleep()
		local poly_efficiency = polynomial_iterpolator.interpolate(efficiency_samples, 6)
		os.sleep()

		return poly_output, poly_reverse_output, poly_efficiency
	end):after(function(reactor, poly_output, poly_reverse_output, poly_efficiency)
		reactor.mReactorConfig.outputPoly = poly_output
		reactor.mReactorConfig.outputReversePoly = poly_reverse_output
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

return reactor_passive
