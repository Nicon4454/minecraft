local computer = require("computer")
local component = require("component")
local event = require("event")
local reactorState = require("brgc/reactor_state")
local turbineState = require("brgc/turbine_state")
local regulationState = require("brgc/regulation_state")
local reactor_api = require("brgc/reactor_ctrl")
local turbine_api = require("brgc/turbine_ctrl")
local energy_storage_component = require("brgc/energy_storage_component")

local controllerState = {
	PWM_OFF = 0,
	PWM_ON = 1,
	LOAD = 2
}

local grid_controller = {
	mTimerId = nil,
	mReactorsSorted = nil,
	mTurbinesSorted = nil,
	mEnergyStorage = {},

	mStats = {
		energyProductionRateReactors = 0,
		energyProductionRateReactorsMax = 0,
		energyProductionRateTurbines = 0,
		energyProductionRateTurbinesMax = 0,
		energyProductionRate = 0,
		energyExtractionRate = 0,
		energyExtractionRateWeighted = 0,

		energyStoredMax = 0,
		energyStoredCurrent = 0,
		energyStoredLast = 0,
		energyStoredRate = 0,

		tickLast = 0,
		timeDiff = 0,
		negativeExtractionRateSince = 0,
	},


	mEnergyStoredTarget = nil,
	mState = controllerState.PWM_OFF,
	mCharge = false,
	mPWMLimitUpper = 0.95,
	mPWMLimitLower = 0.20,
}

function grid_controller.updateStats()
	local now = computer.uptime() * 20
	local timediff = now - grid_controller.mStats.tickLast

	-- Did we advance at least one tick?
	if timediff <= 0 then
		-- We've already been called this tick. No need to do anything.
		-- This it NOT an optimization. Stuff will break if we continue.
		return false
	end

	for _, storage in pairs(grid_controller.mEnergyStorage) do
		if storage:isGood() then
			storage:update()
		end
	end

	grid_controller.mReactorsSorted = grid_controller.getReactors()
	grid_controller.mTurbinesSorted = grid_controller.getTurbines()

	-- Shift current stats to last stats
	grid_controller.mStats.energyStoredLast = grid_controller.mStats.energyStoredCurrent

	-- Update raw sats
	grid_controller.mStats.energyStoredMax = grid_controller.getMaxEnergyStoredDirect()
	grid_controller.mStats.energyStoredCurrent = grid_controller.getEnergyStoredDirect()
	grid_controller.mStats.energyProductionRateReactors = grid_controller.getEnergyProductionRateReactorsDirect()
	grid_controller.mStats.energyProductionRateReactorsMax = grid_controller.getEnergyProductionRateReactorsMaxDirect()
	grid_controller.mStats.energyProductionRateTurbines = grid_controller.getEnergyProductionRateTurbinesDirect()
	grid_controller.mStats.energyProductionRateTurbinesMax = grid_controller.getEnergyProductionRateTurbinesMaxDirect()
	grid_controller.mStats.energyProductionRate = grid_controller.mStats.energyProductionRateTurbines + grid_controller.mStats.energyProductionRateReactors

	-- Check if some energy components have gone offline. If so, reset the
	-- weighted extraction rate, as this thing might underflow so bad it'll be
	-- a while until it's positive again otherwise.
	if grid_controller.mStats.energyStoredLast > grid_controller.mStats.energyStoredMax then
		grid_controller.mStats.energyExtractionRateWeighted = 0
	end

	-- Update rates
	-- If tickLast is 0 then this is the first iteration and we can't compute any rates.
	if grid_controller.mStats.tickLast > 0 then
		grid_controller.mStats.energyStoredRate = ( grid_controller.mStats.energyStoredCurrent - grid_controller.mStats.energyStoredLast ) / timediff
		grid_controller.mStats.energyExtractionRate = grid_controller.mStats.energyProductionRate - grid_controller.mStats.energyStoredRate

		-- Compute the weighted extraction rate
		local weight = math.pow(grid_controller.mStats.energyStoredCurrent / grid_controller.mStats.energyStoredMax, 0.25)
		grid_controller.mStats.energyExtractionRateWeighted = weight * grid_controller.mStats.energyExtractionRateWeighted + ( 1 - weight ) * grid_controller.mStats.energyExtractionRate
	end

	if grid_controller.mStats.energyExtractionRate < 0 then
		grid_controller.mStats.negativeExtractionRateSince = grid_controller.mStats.negativeExtractionRateSince + 1
	elseif grid_controller.mStats.negativeExtractionRateSince > 0 then
		grid_controller.mStats.negativeExtractionRateSince = 0
	end

	grid_controller.mStats.tickLast = now
	grid_controller.mStats.timeDiff = timediff

	-- Fail for the first time so nobody can accidentally run the state machine and crash.
	return (timediff ~= now)
end

function grid_controller.getMaxEnergyStoredDirect()
	local maxEnergyStored = 0

	for _, storage in pairs(grid_controller.mEnergyStorage) do
		if storage:isGood() then
			maxEnergyStored = maxEnergyStored + storage:getMaxEnergyStored()
		end
	end

	return maxEnergyStored
end

function grid_controller.getMaxEnergyStored()
	return grid_controller.mStats.energyStoredMax
end

function grid_controller.getEnergyStoredDirect()
	local energyStored = 0

	for _, storage in pairs(grid_controller.mEnergyStorage) do
		if storage:isGood() then
			energyStored = energyStored + storage:getEnergyStored()
		end
	end

	return energyStored
end

function grid_controller.getEnergyStored()
	return grid_controller.mStats.energyStoredCurrent
end

function grid_controller.getEnergyStoredRate()
	return grid_controller.mStats.energyStoredRate
end

function grid_controller.getReactors()
	local reactors = {}

	for _, reactor in pairs(reactor_api.mReactors) do
		if
			reactor:isConnected()
			and not reactor:isDisabled()
			and not reactor:isActivelyCooled()
			and reactor:isCalibrated()
			and reactor:getRegulationBehaviour() == regulationState.GRID
			and reactor:getFuelLevel() > 0
		then
			table.insert(reactors, reactor)
		end
	end

	table.sort(reactors, function(a, b) return a:getCurrentOptimalOutputGenerationRate() > b:getCurrentOptimalOutputGenerationRate() end)
	return reactors
end

function grid_controller.getTurbines()
	local turbines = {}

	for _, turbine in pairs(turbine_api.mTurbines) do
		if
			turbine:isConnected()
			and not turbine:isDisabled()
			and turbine:isCalibrated()
			and not turbine:isIndependent()
			and turbine:getState() ~= turbineState.ERROR
			and not turbine:isTransient()
		then
			table.insert(turbines, turbine)
		end
	end

	table.sort(turbines, function(a, b) return a:getRPM() > b:getRPM() end)
	return turbines
end

function grid_controller.getOptEnergyProduction()
	local optEnergyProduction = 0

	for _, turbine in pairs(grid_controller.mTurbinesSorted) do
		optEnergyProduction = optEnergyProduction + turbine:getOutputGenerationRateMax()
	end

	for _, reactor in pairs(grid_controller.mReactorsSorted) do
		optEnergyProduction = optEnergyProduction + reactor:getCurrentOptimalOutputGenerationRate()
	end

	return optEnergyProduction
end

function grid_controller.getEnergyProductionRateDirect()
	return grid_controller.getEnergyProductionRateReactorsDirect() + grid_controller.getEnergyProductionRateTurbinesDirect()
end

function grid_controller.getEnergyProductionRateTurbinesDirect()
	local currentEnergyProduction = 0

	for _, turbine in pairs(grid_controller.mTurbinesSorted) do
		currentEnergyProduction = currentEnergyProduction + turbine:getOutputGenerationRate()
	end

	return currentEnergyProduction
end

function grid_controller.getEnergyProductionRateTurbinesMaxDirect()
	local energyProductionMax = 0

	for _, turbine in pairs(grid_controller.mTurbinesSorted) do
		energyProductionMax = energyProductionMax + turbine:getOutputGenerationRateMax()
	end

	return energyProductionMax
end

function grid_controller.getEnergyProductionRateReactorsDirect()
	local currentEnergyProduction = 0

	for _, reactor in pairs(grid_controller.mReactorsSorted) do
		currentEnergyProduction = currentEnergyProduction + reactor:getOutputGenerationRate()
	end

	return currentEnergyProduction
end

function grid_controller.getEnergyProductionRateReactorsMaxDirect()
	local energyProductionMax = 0

	for _, reactor in pairs(grid_controller.mReactorsSorted) do
		energyProductionMax = energyProductionMax + reactor:getOutputGenerationRateMax()
	end

	return energyProductionMax
end

function grid_controller.getEnergyProductionRate()
	return grid_controller.mStats.energyProductionRate
end

function grid_controller.getEnergyProductionRateReactors()
	return grid_controller.mStats.energyProductionRateReactors
end

function grid_controller.getEnergyProductionRateReactorsMax()
	return grid_controller.mStats.energyProductionRateReactorsMax
end

function grid_controller.getEnergyProductionRateTurbines()
	return grid_controller.mStats.energyProductionRateTurbines
end

function grid_controller.getEnergyProductionRateTurbinesMax()
	return grid_controller.mStats.energyProductionRateTurbinesMax
end

function grid_controller.getEnergyExtractionRate()
	return math.max(0, grid_controller.mStats.energyExtractionRate)
end

function grid_controller.getEnergyExtractionRateWeighted()
	return math.max(0, grid_controller.mStats.energyExtractionRateWeighted)
end

function grid_controller.setChargeMode(enable)
	checkArg(1, enable, "boolean")

	grid_controller.mCharge = enable
end

function grid_controller.getChargeMode()
	return grid_controller.mCharge
end

function grid_controller.getPaused()
	return grid_controller.mStats.negativeExtractionRateSince > 0 and grid_controller.mStats.negativeExtractionRateSince < 10
end

function grid_controller.runOnce()
	if not grid_controller.updateStats() then
		return
	end

	-- We need at least SOME energy storage for this to work!
	if grid_controller.getMaxEnergyStored() <= 0 then
		return
	end

	-- See if we observed some kind of disturbance in the fo...eh.. the power
	-- grid. If there is, we wait a bit to avoid rapidly turning on and off
	-- turbines / reactors
	if grid_controller.getPaused() then
		return
	end

	local energyDemandWeighted = grid_controller.getEnergyExtractionRateWeighted()
	local energyDemand = grid_controller.getEnergyExtractionRate()
	local energyRate = grid_controller.getEnergyProductionRate() - energyDemand


	if grid_controller.getChargeMode() and grid_controller.getEnergyStored() >= grid_controller.getMaxEnergyStored() - 60 * grid_controller.getEnergyProductionRate() then
		grid_controller.setChargeMode(false)
	end

	-- When we're producing more energy than required and the energy storage is
	-- full, the energy extraction rate will clip to the production rate. This
	-- will cause the controller to never shut down and produce as much energy
	-- as possible. As a workaround, we force the energy demand to be 0 if the
	-- energy storage is full. This will cause the controller to shut down
	-- energy production until the energy storage is not full anymore.
	-- energyRate is forced to 1the current production rate so runModePWM
	-- actually does useful things (aka shut down everything).
	if grid_controller.getEnergyStored() >= grid_controller.getMaxEnergyStored() - grid_controller.getEnergyProductionRate() then
		energyDemand = 0
		energyDemandWeighted = 0
		energyRate = grid_controller.getEnergyProductionRate()
	end

	if energyDemandWeighted > grid_controller.getOptEnergyProduction() then
		if grid_controller.mEnergyStoredTarget == nil then
			grid_controller.mEnergyStoredTarget = grid_controller.getEnergyStored()
		end
		grid_controller.mState = controllerState.LOAD
		-- We have to put some reactors into overdrive
		grid_controller.runModeLoad(energyRate, energyDemand, grid_controller.mEnergyStoredTarget)
	else
		if grid_controller.mEnergyStoredTarget ~= nil then
			local energyStoredPercent = grid_controller.getEnergyStored() / grid_controller.getMaxEnergyStored()
			if energyStoredPercent >= 0.5 then
				grid_controller.mState = controllerState.PWM_OFF
			else
				grid_controller.mState = controllerState.PWM_ON
			end
			grid_controller.mEnergyStoredTarget = nil
		end

		if grid_controller.getChargeMode() then
			grid_controller.runModeCharge()
		else
			grid_controller.runModePWM(energyRate, energyDemand)
		end
	end
end

function grid_controller.runModePWM(energyRate, energyDemand)
	checkArg(1, energyRate, "number")
	checkArg(2, energyDemand, "number")

	local energyStored = grid_controller.getEnergyStored()
	local energyStoredMax = grid_controller.getMaxEnergyStored()
	local energyStoredPercent = energyStored / energyStoredMax

	if energyStoredPercent > grid_controller.mPWMLimitUpper then
		grid_controller.mState = controllerState.PWM_OFF
	elseif energyStoredPercent < grid_controller.mPWMLimitLower then
		grid_controller.mState = controllerState.PWM_ON
	end

	if energyRate < 0 then
		grid_controller.doPWMIncrease(energyRate, energyDemand, grid_controller.mState == controllerState.PWM_ON)
	elseif energyRate > 0 then
		grid_controller.doPWMDecrease(energyRate, energyDemand, grid_controller.mState == controllerState.PWM_OFF)
	end
end

function grid_controller.doPWMDecrease(energyRate, energyDemand, allowNegativeRate)
	checkArg(1, energyRate, "number")
	checkArg(2, energyDemand, "number")
	checkArg(3, allowNegativeRate, "boolean")

	local newEnergyRate = energyRate
	local hasOnlineReactors = false
	-- See if we can turn off some reactors first
	for i = #grid_controller.mReactorsSorted, 1, -1 do
		-- Shut down the least efficient reactor that is online
		-- Repeat that for as long as we have reactors left or the energy rate is now negative
		local reactor = grid_controller.mReactorsSorted[i]

		if newEnergyRate <= 0 or (not allowNegativeRate and newEnergyRate - reactor:getOutputGenerationRate() < 0) then
			-- Nothing to do here
		elseif reactor:getOutput() > 0 then
			reactor:setOutput(0, 0)
		end

		-- Always substract the current output because reactors that have been offlined already
		-- are not going to produce any more energy very soon. If this wouldn't be taken into
		-- account the controller would flicker on/off some, if not all, reactors until the
		-- energy rate has stabilized (which might not ever happen because of this).
		if reactor:getOutput() == 0 then
			newEnergyRate = newEnergyRate - reactor:getOutputGenerationRate()
		else
			hasOnlineReactors = true
			-- Check if we need to readjust the reactors output. This may be
			-- neccessary if we've just dropped out of LOAD mode
			if math.abs(reactor:getOutput() - reactor:getOutputOpt()) > 0.01 then
				reactor:setOutput(reactor:getOutputOpt(), 0)
			end
		end
	end

	-- Now for turbines...
	-- If we have online reactors, don't attempt to shut down turbines.
	for i = #grid_controller.mTurbinesSorted, 1, -1 do
		local turbine = grid_controller.mTurbinesSorted[i]

		if newEnergyRate <= 0 or (not allowNegativeRate and newEnergyRate - turbine:getOutputGenerationRate() < 0) or hasOnlineReactors then
			-- Nothing to do here
		elseif turbine:getState() ~= turbineState.SUSPENDED then
			newEnergyRate = newEnergyRate - turbine:getOutputGenerationRate()
			turbine:setState(turbineState.SUSPENDED)
		end
	end

	return newEnergyRate
end

function grid_controller.doPWMIncrease(energyRate, energyDemand, allowPositiveRate)
	checkArg(1, energyRate, "number")
	checkArg(2, energyDemand, "number")
	checkArg(3, allowPositiveRate, "boolean")

	local newEnergyRate = energyRate
	local hasSuspendedTurbines = false
	-- See if we can turn on some turbines first
	for _, turbine in pairs(grid_controller.mTurbinesSorted) do
		if newEnergyRate >= 0 or (not allowPositiveRate and newEnergyRate + turbine:getOutputGenerationRateMax() > 0) then
			-- Nothing to do here
			hasSuspendedTurbines = hasSuspendedTurbines or turbine:getState() == turbineState.SUSPENDED
		elseif turbine:getState() == turbineState.SUSPENDED then
			newEnergyRate = newEnergyRate + turbine:estimateOutputGenerationRate()
			turbine:setState(turbineState.STARTING)
		end
	end

	-- Now for reactors...
	-- If we have suspended turbines, don't attempt to enable reactors.
	for _, reactor in pairs(grid_controller.mReactorsSorted) do
		if newEnergyRate >= 0 or (not allowPositiveRate and newEnergyRate + reactor:getCurrentOptimalOutputGenerationRate() > 0) or hasSuspendedTurbines then
			-- Nothing to do here
		elseif reactor:getOutput() == 0 then
			reactor:setOutput(reactor:getOutputOpt(), 0)
		end

		-- Check if we need to readjust the reactors output. This may be
		-- neccessary if we've just dropped out of LOAD mode
		if reactor:getOutput() > 0 and math.abs(reactor:getOutput() - reactor:getOutputOpt()) > 0.01 then
			reactor:setOutput(reactor:getOutputOpt(), 0)
		end

		-- We need to consider that reactors take a second or two to get going.
		-- If we didn't do this the controller might flicker on/off some reactors.
		if reactor:getOutput() > 0 and reactor:getOutputGenerationRate() < reactor:getCurrentOptimalOutputGenerationRate() * 0.75 then
			newEnergyRate = newEnergyRate + reactor:getCurrentOptimalOutputGenerationRate()
		else
			newEnergyRate = newEnergyRate + reactor:getOutputGenerationRate()
		end
	end

	return newEnergyRate
end


function grid_controller.runModeLoad(energyRate, energyDemand, energyStoredTarget)
	checkArg(1, energyRate, "number")
	checkArg(2, energyDemand, "number")
	checkArg(3, energyStoredTarget, "number")

	local newEnergyRate = 0

	-- Turn on as many turbines as possible.
	for _, turbine in pairs(grid_controller.mTurbinesSorted) do
		if newEnergyRate >= energyDemand then
			-- Suspend turbines that are not needed.
			turbine:setState(turbineState.SUSPENDED)
		elseif turbine:getState() == turbineState.SUSPENDED then
			newEnergyRate = newEnergyRate + turbine:estimateOutputGenerationRate()
			turbine:setState(turbineState.STARTING)
		else
			newEnergyRate = newEnergyRate + turbine:estimateOutputGenerationRate()
		end
	end

	local energyDemandLeft = energyDemand - newEnergyRate
	local reactorOutputMax = 0

	for _, reactor in pairs(grid_controller.mReactorsSorted) do
		reactorOutputMax = reactorOutputMax + reactor:getOutputGenerationRateMax()
	end

	local pTargetEnergyProduction = energyDemandLeft / reactorOutputMax
	local pEnergyStoredDelta = ( energyStoredTarget - grid_controller.getEnergyStored() ) / grid_controller.getMaxEnergyStored()
	local pEnergyProductionDelta = 0 - grid_controller.getEnergyStoredRate() / reactorOutputMax

	for _, reactor in pairs(grid_controller.mReactorsSorted) do
		reactor:regulatePD2(pTargetEnergyProduction, pEnergyStoredDelta, pEnergyProductionDelta)
	end

	-- TODO: estimate actual energy production
	return energyDemand
end

function grid_controller.runModeCharge()
	local newEnergyRate = 0

	for _, turbine in pairs(grid_controller.mTurbinesSorted) do
		if turbine:getState() == turbineState.SUSPENDED then
			newEnergyRate = newEnergyRate + turbine:estimateOutputGenerationRate()
			turbine:setState(turbineState.STARTING)
		else
			newEnergyRate = newEnergyRate + turbine:estimateOutputGenerationRate()
		end
	end

	for _, reactor in pairs(grid_controller.mReactorsSorted) do
		if reactor:getOutput() ~= reactor:getOutputOpt() then
			reactor:setOutput(reactor:getOutputOpt(), 0)
		end

		newEnergyRate = newEnergyRate + reactor:getOutputGenerationRate()
	end

	return newEnergyRate
end

-- Storage functions

function grid_controller.discoverStorage()
	-- Loop over the types of supported energy storage components
	for typeID, _ in pairs(energy_storage_component.mCompatibleComponents) do
		local br_components = component.list(typeID)
		-- Add all addresses for the current component. If the component
		-- already exists, nothing happens.
		for address, _ in pairs(br_components) do
			grid_controller.addStorage(address)
		end
	end
end

function grid_controller.addStorage(address)
	checkArg(1, address, "string")

	if grid_controller.mEnergyStorage[address] == nil then
		local new_storage = energy_storage_component(address)

		if new_storage:isGood() then
			new_storage:update()
			grid_controller.mEnergyStorage[address] = new_storage
			computer.pushSignal("brgc_storage_added", address)
		end
	end
end

function grid_controller.removeStorage(address)
	checkArg(1, address, "string")

	if grid_controller.mEnergyStorage[address] ~= nil then
		grid_controller.mEnergyStorage[address] = nil
		computer.pushSignal("brgc_storage_removed", address)
	end
end

-- Service functions

function grid_controller.start()
	if grid_controller.mTimerId ~= nil then
		return false
	else
		event.listen("component_added", grid_controller.asyncComponentAddedHandler)
		event.listen("component_removed", grid_controller.asyncComponentRemovedHandler)
		grid_controller.mTimerId = event.timer(1, grid_controller.asyncTimerHandler, math.huge)
		return true
	end
end

function grid_controller.stop()
	if grid_controller.mTimerId == nil then
		return false
	else
		event.ignore("component_added", grid_controller.asyncComponentAddedHandler)
		event.ignore("component_removed", grid_controller.asyncComponentRemovedHandler)
		event.cancel(grid_controller.mTimerId)
		grid_controller.mTimerId = nil
		return true
	end
end

function grid_controller.isRunning()
	return grid_controller.mTimerId ~= nil
end

function grid_controller.asyncComponentAddedHandler(eventID, address, typeID)
	if energy_storage_component.isCompatible(typeID) then
		grid_controller.addStorage(address)
	end
end

function grid_controller.asyncComponentRemovedHandler(eventID, address, typeID)
	if energy_storage_component.isCompatible(typeID) then
		grid_controller.removeStorage(address)
	end
end

function grid_controller.asyncTimerHandler()
	xpcall(grid_controller.runOnce, function(...) io.stderr:write(debug.traceback(...) .. "\n") end)
end

return grid_controller
