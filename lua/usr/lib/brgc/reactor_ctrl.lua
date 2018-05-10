local computer = require("computer")
local component = require("component")
local event = require("event")
local config = require("brgc/config")
local reactorState = require("brgc/reactor_state")
local reactorFactory = require("brgc/reactor_factory")

local reactor_api = {
	mReactors = {},
	mDebug = false,
	mTimerId = nil,
	mSteamMax = 0,
	mSteamProductionTarget = 0
}

function reactor_api.reset()
	reactor_api.mReactors = {}
	reactor_api.mSteamMax = 0
end

function reactor_api.discover()
	local br_components = component.list("br_reactor")
	config.load()

	for address, _ in pairs(br_components) do
		reactor_api.add(address)
	end
end

function reactor_api.add(address)
	checkArg(1, address, "string")

	if reactor_api.mReactors[address] == nil then
		local reactor = reactorFactory(address)

		if reactor ~= nil then
			if not reactor:isDisabled() then
				reactor:setState(reactorState.ONLINE)
				if reactor:isActivelyCooled() and reactor:isCalibrated() then
					reactor_api.mSteamMax = reactor_api.mSteamMax + reactor:getOutputGenerationRateMax()
				end
			end

			reactor_api.mReactors[address] = reactor

			if reactor:isActivelyCooled() then
				computer.pushSignal("brgc_reactor_added", address, "active")
				reactor_api.print("Connected with active reactor " .. address)
			else
				computer.pushSignal("brgc_reactor_added", address, "passive")
				reactor_api.print("Connected with passive reactor " .. address)
			end
		end
	end
end

function reactor_api.remove(address)
	checkArg(1, address, "string")

	if reactor_api.mReactors[address] ~= nil then
		if reactor_api.mReactors[address]:isActivelyCooled() then
			reactor_api.mSteamMax = reactor_api.mSteamMax - reactor_api.mReactors[address]:getOutputGenerationRateMax()
		end
		reactor_api.mReactors[address] = nil
		computer.pushSignal("brgc_reactor_removed", address)
	end
end

function reactor_api.reload()
	local reactors = { }
	config.load()

	for address, _ in pairs(reactor_api.mReactors) do
		table.insert(reactors, address)
	end

	for _, address in pairs(reactors) do
		reactor_api.remove(address)
		reactor_api.add(address)
	end
end

function reactor_api.setSteamProductionTarget(target)
	reactor_api.mSteamProductionTarget = math.max(0, target)
end

function reactor_api.getSteamProductionTarget()
	return reactor_api.mSteamProductionTarget
end

function reactor_api.runOnce()
	local maxsteam = 0
	for _, reactor in pairs(reactor_api.mReactors) do
		if reactor:isActivelyCooled() and reactor:isCalibrated() then
			if reactor_api.mSteamProductionTarget > 0 and reactor_api.mSteamMax > 0 then
				reactor:setSteamProductionTarget(reactor:getOutputGenerationRateMax() * reactor_api.mSteamProductionTarget / reactor_api.mSteamMax)
			else
				reactor:setSteamProductionTarget(0)
			end
		end
		reactor:runStateMachine()
		if reactor:isActivelyCooled() and reactor:isCalibrated() and not reactor:isDisabled() then
			maxsteam = maxsteam + reactor:getOutputGenerationRateMax()
		end
	end
	reactor_api.mSteamMax = maxsteam
end

function reactor_api.shutdown()
	reactor_api.setAsync(false)
	for _, reactor in pairs(reactor_api.mReactors) do
		reactor:setState(reactorState.OFFLINE)
	end
	reactor_api.reset()
end

function reactor_api.start()
	if reactor_api.mTimerId ~= nil then
		return false
	else
		event.listen("component_added", reactor_api.asyncComponentAddedHandler)
		event.listen("component_removed", reactor_api.asyncComponentRemovedHandler)
		reactor_api.mTimerId = event.timer(0.5, reactor_api.asyncTimerHandler, math.huge)
		return true
	end
end

function reactor_api.stop()
	if reactor_api.mTimerId == nil then
		return false
	else
		event.ignore("component_added", reactor_api.asyncComponentAddedHandler)
		event.ignore("component_removed", reactor_api.asyncComponentRemovedHandler)
		event.cancel(reactor_api.mTimerId)
		reactor_api.mTimerId = nil
		return true
	end
end

function reactor_api.isRunning()
	return reactor_api.mTimerId ~= nil
end

function reactor_api.toggleDebug()
	reactor_api.mDebug = not reactor_api.mDebug
end

function reactor_api.print(...)
	if reactor_api.mDebug then
		print(...)
	end
end

-- Async handlers

function reactor_api.asyncComponentAddedHandler(_, address, typeID)
	if typeID == "br_reactor" then
		reactor_api.add(address)
	end
end

function reactor_api.asyncComponentRemovedHandler(_, address, typeID)
	if typeID == "br_reactor" then
		reactor_api.remove(address)
	end
end

function reactor_api.asyncTimerHandler()
	xpcall(reactor_api.runOnce, function(...) io.stderr:write(debug.traceback(...) .. "\n") end)
end

return reactor_api