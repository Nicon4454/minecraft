local computer = require("computer")
local component = require("component")
local event = require("event")
local reactor_api = require("brgc/reactor_ctrl")
local config = require("brgc/config")
local turbineState = require("brgc/turbine_state")
local turbineFactory = require("brgc/turbine_factory")


local turbine_api = {
	mTurbines = {},
	mDebug = false,
	mTimerId = nil
}

function turbine_api.reset()
	turbine_api.mTurbines = {}
end

function turbine_api.discover()
	local br_components = component.list("br_turbine")
	config.load()

	for address, _ in pairs(br_components) do
		turbine_api.add(address)
	end
end

function turbine_api.add(address)
	checkArg(1, address, "string")

	if turbine_api.mTurbines[address] == nil then
		local turbine = turbineFactory(address)
		if turbine ~= nil then
			if not turbine:isDisabled() then
				reactor_api.setSteamProductionTarget(reactor_api.getSteamProductionTarget() + turbine:getSteamRate())
			end

			turbine_api.mTurbines[address] = turbine

			turbine_api.print("Connected with turbine " .. address)
			computer.pushSignal("brgc_turbine_added", address)
		end
	end
end

function turbine_api.remove(address)
	checkArg(1, address, "string")

	if turbine_api.mTurbines[address] ~= nil then
		reactor_api.setSteamProductionTarget(reactor_api.getSteamProductionTarget() - turbine_api.mTurbines[address]:getSteamRate())
		turbine_api.mTurbines[address] = nil
		computer.pushSignal("brgc_turbine_removed", address)
	end
end

function turbine_api.reload()
	for address, turbine in pairs(turbine_api.mTurbines) do
		local turbine_config = config:getTurbineConfigOrDefault(address)
		if turbine_config and turbine:isConnected() then
			turbine:setEnergyProductionMax(turbine_config.energyProductionMax)
			turbine:setRPMMax(turbine_config.RPMMax)
			turbine:setIndependent(turbine_config.independent or false)
		end
	end

	local turbines = { }
	config.load()

	for address, _ in pairs(turbine_api.mTurbines) do
		table.insert(turbines, address)
	end

	for _, address in pairs(turbines) do
		turbine_api.remove(address)
		turbine_api.add(address)
	end
end

function turbine_api.runOnce()
	local steamNeeded = 0

	for _, turbine in pairs(turbine_api.mTurbines) do
		if turbine:isConnected() then
			turbine:runStateMachine()
			if turbine:isActive() then
				steamNeeded = steamNeeded + turbine:getSteamRate()
			end
		end
	end

	reactor_api.setSteamProductionTarget(steamNeeded)
end

function turbine_api.shutdown()
	turbine_api.setAsync(false)
	for _, turbine in pairs(turbine_api.mTurbines) do
		turbine:setState(turbineState.OFFLINE)
	end
	turbine_api.reset()
end

function turbine_api.start()
	if turbine_api.mTimerId ~= nil then
		return false
	else
		event.listen("component_added", turbine_api.asyncComponentAddedHandler)
		event.listen("component_removed", turbine_api.asyncComponentRemovedHandler)
		turbine_api.mTimerId = event.timer(1, turbine_api.asyncTimerHandler, math.huge)
		return true
	end
end

function turbine_api.stop()
	if turbine_api.mTimerId == nil then
		return false
	else
		event.ignore("component_added", turbine_api.asyncComponentAddedHandler)
		event.ignore("component_removed", turbine_api.asyncComponentRemovedHandler)
		event.cancel(turbine_api.mTimerId)
		turbine_api.mTimerId = nil
		return true
	end
end

function turbine_api.isRunning()
	return turbine_api.mTimerId ~= nil
end

function turbine_api.toggleDebug()
	turbine_api.mDebug = not turbine_api.mDebug
end

function turbine_api.print(...)
	if turbine_api.mDebug then
		print(...)
	end
end

function turbine_api.getTurbines()
	return turbine_api.mTurbines
end

-- Async handlers

function turbine_api.asyncComponentAddedHandler(_, address, typeID)
	if typeID == "br_turbine" then
		turbine_api.add(address)
	end
end

function turbine_api.asyncComponentRemovedHandler(_, address, typeID)
	if typeID == "br_turbine" then
		turbine_api.remove(address)
	end
end

function turbine_api.asyncTimerHandler()
	xpcall(turbine_api.runOnce, function(...) io.stderr:write(debug.traceback(...) .. "\n") end)
end

return turbine_api