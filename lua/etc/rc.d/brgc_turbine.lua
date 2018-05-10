--[[
Init script for Big Reactors Grid Control - Turbine Controller for OpenComputers by XyFreak
Website: http://tenyx.de/brgc/
--]]

local turbine_ctrl = require("brgc/turbine_ctrl")

function start()
	if turbine_ctrl.isRunning() then
		io.stderr:write("Big Reactors Grid Control - Turbine Controller service already running.")
	else
		turbine_ctrl.discover()
		turbine_ctrl.start()
	end
end

function stop()
	if not turbine_ctrl.isRunning() then
		io.stderr:write("Big Reactors Grid Control - Turbine Controller service not running.")
	else
		turbine_ctrl.stop()
	end
end

function restart()
	turbine_ctrl.reset()
	turbine_ctrl.discover()
	if not turbine_ctrl.isRunning() then
		turbine_ctrl.start()
	end
end

function status()
	if turbine_ctrl.isRunning() then
		io.write("Big Reactors Grid Control - Turbine Controller is running.")
	else
		io.write("Big Reactors Grid Control - Turbine Controller is not running.")
	end
end