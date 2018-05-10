--[[
Init script for Big Reactors Grid Control - Grid Controller for OpenComputers by XyFreak
Website: http://tenyx.de/brgc/
--]]

local grid_controller = require("brgc/grid_controller")

function start()
	if grid_controller.isRunning() then
		io.stderr:write("Big Reactors Grid Control - Grid Controller service already running.")
	else
		grid_controller.start()
	end
end

function stop()
	if not grid_controller.isRunning() then
		io.stderr:write("Big Reactors Grid Control - Grid Controller service not running.")
	else
		grid_controller.stop()
	end
end

function restart()
	if grid_controller.isRunning() then
		grid_controller.stop()
	end
	grid_controller.start()
end

function status()
	if grid_controller.isRunning() then
		io.write("Big Reactors Grid Control - Grid Controller is running.")
	else
		io.write("Big Reactors Grid Control - Grid Controller is not running.")
	end
end