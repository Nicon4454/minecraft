--[[
Init script for Big Reactors Grid Control - Reactor Controller for OpenComputers by XyFreak
Website: http://tenyx.de/brgc/
--]]

local reactor_ctrl = require("brgc/reactor_ctrl")

function start()
	if reactor_ctrl.isRunning() then
		io.stderr:write("Big Reactors Grid Control - Reactor Controller service already running.")
	else
		reactor_ctrl.discover()
		reactor_ctrl.start()
	end
end

function stop()
	if not reactor_ctrl.isRunning() then
		io.stderr:write("Big Reactors Grid Control - Reactor Controller service not running.")
	else
		reactor_ctrl.stop()
	end
end

function restart()
	reactor_ctrl.reset()
	reactor_ctrl.discover()
	if not reactor_ctrl.isRunning() then
		reactor_ctrl.start()
	end
end

function status()
	if reactor_ctrl.isRunning() then
		io.write("Big Reactors Grid Control - Reactor Controller is running.")
	else
		io.write("Big Reactors Grid Control - Reactor Controller is not running.")
	end
end