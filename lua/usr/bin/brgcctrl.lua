local shell = require("shell")
local reactor_ctrl = require("brgc/reactor_ctrl")
local turbine_ctrl = require("brgc/turbine_ctrl")
local grid_ctrl = require("brgc/grid_controller")
local turbineState = require("brgc/turbine_state")
local reactorState = require("brgc/reactor_state")
local brgc_config = require("brgc/config")

local g_modules = { }

local function get_component_by_partial_address(partialAddress, includeReactors, includeTurbines)
	local maps = { }
	if includeReactors then
		table.insert(maps, reactor_ctrl.mReactors)
	end
	if includeTurbines then
		table.insert(maps, turbine_ctrl.mTurbines)
	end

	local selectedComponent = nil
	for _, v in pairs(maps) do
		for componentAddress, component in pairs(v) do
			if string.sub(componentAddress, 1, string.len(partialAddress)) == partialAddress then
				if selectedComponent == nil then
					selectedComponent = component
				else
					return nil
				end
			end
		end
	end
	return selectedComponent
end

local function print_submodules(module, stderr)
	for key, value in pairs(module) do
		local meta = getmetatable(value)
		if not stderr then
			io.write(" - " .. tostring(key) .. "\n")
			if meta.__description then
				io.write("   " .. tostring(meta.__description) .. "\n")
			end
		else
			io.stderr:write(" - " .. tostring(key) .. "\n")
			if meta.__description then
				io.stderr:write("   " .. tostring(meta.__description) .. "\n")
			end
		end
	end
end

local function list_turbines()
	for turbineAddress, turbine in pairs(turbine_ctrl.mTurbines) do
		io.write(
			string.format("%s  %13s  %6d RF/t  %4d RPM\n", turbineAddress, turbineState.toString(turbine:getState()), math.floor(turbine:getOutputGenerationRate() + 0.5), turbine:getRPM())
		)
	end
end

local function list_reactors()
	for reactorAddress, reactor in pairs(reactor_ctrl.mReactors) do
		if reactor:isActivelyCooled() then
			io.write(
				string.format("%s  %13s  %6d mB/t\n", reactorAddress, reactorState.toString(reactor:getState()), math.floor(reactor:getOutputGenerationRate() + 0.5))
			)
		else
			io.write(
				string.format("%s  %13s  %6d RF/t\n", reactorAddress, reactorState.toString(reactor:getState()), math.floor(reactor:getOutputGenerationRate() + 0.5))
			)
		end
	end
end

local function print_help()
	io.write("Usage: brctrl <modules...>\n")
	io.write("\n")
	print_submodules(g_modules)
end

g_modules = {
	__call = print_help,
	help = {
		__call = print_help,
		__description = "Usage: brctrl help <module>\n   " ..
						"Display help for the given module"
	}, -- help = { ... }

	service = {
		reactor = {
			start = {
				__call = function()
					if reactor_ctrl.isRunning() then
						io.stderr:write("Big Reactors Grid Control - Reactor Controller service already running.\n")
					else
						reactor_ctrl.discover()
						reactor_ctrl.start()
					end
				end
			},
			stop = {
				__call = function()
					if not reactor_ctrl.isRunning() then
						io.stderr:write("Big Reactors Grid Control - Reactor Controller service not running.\n")
					else
						reactor_ctrl.stop()
					end
				end
			},
			restart = {
				__call = function()
					reactor_ctrl.reset()
					reactor_ctrl.discover()
					if not reactor_ctrl.isRunning() then
						reactor_ctrl.start()
					end
				end
			},
			status = {
				__call = function()
					if reactor_ctrl.isRunning() then
						io.write("Big Reactors Grid Control - Reactor Controller is running.\n")
					else
						io.write("Big Reactors Grid Control - Reactor Controller is not running.\n")
					end
				end
			},
			shutdown = {
				__call = reactor_ctrl.shutdown
			},
			runOnce = {
				__call = reactor_ctrl.runOnce
			}
		}, -- reactor = { ... }

		turbine = {
			start = {
				__call = function()
					if turbine_ctrl.isRunning() then
						io.stderr:write("Big Reactors Grid Control - Turbine Controller service already running.\n")
					else
						turbine_ctrl.discover()
						turbine_ctrl.start()
					end
				end
			},
			stop = {
				__call = function()
					if not turbine_ctrl.isRunning() then
						io.stderr:write("Big Reactors Grid Control - Turbine Controller service not running.\n")
					else
						turbine_ctrl.stop()
					end
				end
			},
			restart = {
				__call = function()
					turbine_ctrl.reset()
					turbine_ctrl.discover()
					if not turbine_ctrl.isRunning() then
						turbine_ctrl.start()
					end
				end
			},
			status = {
				__call = function()
					if turbine_ctrl.isRunning() then
						io.write("Big Reactors Grid Control - Turbine Controller is running.\n")
					else
						io.write("Big Reactors Grid Control - Turbine Controller is not running.\n")
					end
				end
			},
			shutdown = {
				__call = turbine_ctrl.shutdown
			},
			runOnce = {
				__call = turbine_ctrl.runOnce
			}
		}, -- turbine = { ... }

		grid = {
			start = {
				__call = function()
					if grid_ctrl.isRunning() then
						io.stderr:write("Big Reactors Grid Control - Grid Controller service already running.\n")
					else
						grid_ctrl.discoverStorage()
						grid_ctrl.start()
					end
				end
			},
			stop = {
				__call = function()
					if not grid_ctrl.isRunning() then
						io.stderr:write("Big Reactors Grid Control - Grid Controller service not running.\n")
					else
						grid_ctrl.stop()
					end
				end
			},
			restart = {
				__call = function()
					grid_ctrl.reset()
					grid_ctrl.discoverStorage()
					if not grid_ctrl.isRunning() then
						grid_ctrl.start()
					end
				end
			},
			status = {
				__call = function()
					if grid_ctrl.isRunning() then
						io.write("Big Reactors Grid Control - Grid Controller is running.\n")
					else
						io.write("Big Reactors Grid Control - Grid Controller is not running.\n")
					end
				end
			},
			runOnce = {
				__call = grid_ctrl.runOnce
			}
		}, -- grid = { ... }

		all = {
			start = {
				__call = function()
					g_modules.service.reactor.start()
					g_modules.service.turbine.start()
					g_modules.service.grid.start()
				end
			},
			stop = {
				__call = function()
					g_modules.service.grid.stop()
					g_modules.service.turbine.stop()
					g_modules.service.reactor.stop()
				end
			},
			restart = {
				__call = function()
					g_modules.service.reactor.restart()
					g_modules.service.turbine.restart()
					g_modules.service.grid.restart()
				end
			},
			shutdown = {
				__call = function()
					g_modules.service.turbine.shutdown()
					g_modules.service.reactor.shutdown()
				end
			}
		} -- all = { ... }
	}, -- service = { ... }

	list = {
		__call = function(context, args)
			assert(#args == 0, "This method has no arguments.\n")
			io.write("Reactors\n")
			list_reactors()
			io.write("\nTurbines\n")
			list_turbines()
		end,

		reactors = {
			__call = list_reactors
		},

		turbines = {
			__call = list_turbines
		}
	}, -- list = { ... }

	discover = {
		__call = function(context, args)
			assert(#args == 0, "This method has no arguments.\n")
			reactor_ctrl.discover()
			turbine_ctrl.discover()
		end,

		reactors = {
			__call = reactor_ctrl.discover
		},

		turbines = {
			__call = turbine_ctrl.discover
		}
	}, -- discover = { ... }

	steamtarget = {
		get = {
			__call = function()
				io.write(
					string.format("Current steam production target: %d mB/t\n", reactor_ctrl.getSteamProductionTarget() )
				)
			end
		},

		set = {
			__call = function(context, args)
				assert(#args == 1, "This method requires exactly one argument")
				local steamtarget = tonumber(args[1])
				assert(tostring(steamtarget) == args[1], "This method requires a non-negative number as argument")
				assert(steamtarget >= 0, tostring(steamtarget) .. " is not a non-negative number")
				reactor_ctrl.setSteamProductionTarget(steamtarget)
			end
		}
	}, -- steamtarget = { ... }

	config = {
		reactor = {
--			__args = 1,
			get = {
				__call = function(context, args)
					assert(#args == 1 or #args == 2, "This method requires exactly one or two arguments:\nbrgcctrl config reactor <partial address> get [<property>]")
					local reactor = get_component_by_partial_address(args[1], true, false)
					assert(reactor ~= nil, "No reactor can be uniquely identified by '" .. tostring(args[1]) .. "'")
					local reactor_config = brgc_config:getReactorConfig(reactor:getAddress())
					if reactor_config == nil then
						io.write("Note: No configuration found for reactor '" .. reactor:getAddress() .. "'. Using defaults.\n")
						reactor_config = brgc_config:getDefaultReactorConfig()
					end
					if #args == 2 then
						io.write(tostring(args[2]) .. " = " .. tostring(reactor_config[args[2]]) .. "\n")
					else
						for key, value in pairs(reactor_config) do
							io.write(tostring(key) .. " = " .. tostring(value) .. "\n")
						end
					end
				end
			}, -- reactor::get()
			set = {
				__call = function(context, args)
					assert(#args == 3, "This method requires exactly three arguments:\nbrgcctrl config reactor <partial address> set <property> <value>")
					local reactor = get_component_by_partial_address(args[1], true, false)
					assert(reactor ~= nil, "No reactor can be uniquely identified by '" .. tostring(args[1]) .. "'")
					local value = nil
					if args[3] == "nil" then
					elseif tostring(tonumber(args[3])) == args[3] then
						value = tonumber(args[3])
					else
						value = args[3]
					end
					brgc_config:setReactorAttribute(reactor:getAddress(), args[2], value)
				end
			}, -- reactor::set()
			commit = {
				__call = reactor_ctrl.reload
			} -- reactor::commit()
		}, -- reactor = { ... }
		turbine = {
--			__args = 1,
			get = {
				__call = function(context, args)
					assert(#args == 1 or #args == 2, "This method requires exactly one or two arguments:\nbrgcctrl config turbine <partial address> get [<property>]")
					local turbine = get_component_by_partial_address(args[1], false, true)
					assert(turbine ~= nil, "No turbine can be uniquely identified by '" .. tostring(args[1]) .. "'")
					local turbine_config = brgc_config:getTurbineConfig(turbine:getAddress())
					if turbine_config == nil then
						io.write("Note: No configuration found for turbine '" .. turbine:getAddress() .. "'. Using defaults.\n")
						turbine_config = brgc_config:getDefaultTurbineConfig()
					end
					if #args == 2 then
						io.write(tostring(args[2]) .. " = " .. tostring(turbine_config[args[2]]) .. "\n")
					else
						for key, value in pairs(turbine_config) do
							io.write(tostring(key) .. " = " .. tostring(value) .. "\n")
						end
					end
				end
			}, -- turbine::get()
			set = {
				__call = function(context, args)
					assert(#args == 3, "This method requires exactly three arguments:\nbrgcctrl config turbine <partial address> set <property> <value>")
					local turbine = get_component_by_partial_address(args[1], false, true)
					assert(turbine ~= nil, "No turbine can be uniquely identified by '" .. tostring(args[1]) .. "'")
					local value = nil
					if args[3] == "nil" then
					elseif tostring(tonumber(args[3])) == args[3] then
						value = tonumber(args[3])
					else
						value = args[3]
					end
					brgc_config:setTurbineAttribute(turbine:getAddress(), args[2], value)
				end
			}, -- turbine::set()
			commit = {
				__call = turbine_ctrl.reload
			} -- turbine::commit()
		}, -- turbine = { ... }
		commit = {
			__call = function(context, args)
				assert(#args == 0, "This method has no arguments.\n")
				reactor_ctrl.reload()
				turbine_ctrl.reload()
			end
		} -- commit = { ... }
	}, -- config = { ... }

	calibrate = {
		__call = function(context, args)
			assert(#args == 1, "This method requires exactly one argument:\nbrgcctrl calibrate <partial address>")
			local component = get_component_by_partial_address(args[1], true, true)
			assert(component ~= nil, "No component can be uniquely identified by '" .. tostring(args[1]) .. "'")
			component:recalibrate()
		end
	} -- calibrate = { ... }
}


local function convert_context_table(t)
	local meta = getmetatable(t) or { }
	local remove = {}
	for key, value in pairs(t) do
		if string.sub(key, 1, 2) == "__" then
			meta[key] = value
			table.insert(remove, key)
		elseif type(value) == "table" then
			convert_context_table(value)
		end
	end
	for _, key in pairs(remove) do
		t[key] = nil
	end
	if meta.__call == nil then
		meta.__call = function(context)
			io.write("The following modules are available in the current context:\n")
			print_submodules(context)
		end
	end
	setmetatable(t, meta)
end

convert_context_table(g_modules)

local args = shell.parse(...)
local currentContext = g_modules
local contextArgs = {}

while #args > 0 do
	local nextModuleName = table.remove(args, 1)
	local nextContext = currentContext[nextModuleName]
	if nextContext == nil then
		io.stderr:write("The selected module '" .. tostring(nextModuleName) .. "' could not be found.\n")
		io.stderr:write("The following modules are available in the current context:\n")
		for key, _ in pairs(currentContext) do
			io.stderr:write(" - " .. tostring(key) .. "\n")
		end
		io.stderr:write("\n")
		return false
	else
		currentContext = nextContext
		if next(nextContext) ~= nil then
			local meta = getmetatable(currentContext)
			local i = 1
			while #args > 0 and i <= (meta.__args or 0) do
				table.insert(contextArgs, table.remove(args, 1))
				i = i + 1
			end
			if i < (meta.__args or 0)+1 then
				io.stderr:write("Module '" .. tostring(nextModuleName) .. "' expects " .. tostring(meta.__args or 0) .. " arguments. " .. tostring(i-1) .. " given.\n")
				return false
			end
		else
			break
		end
	end
end

while #args > 0 do
	table.insert(contextArgs, table.remove(args, 1))
end

local success, errorMessage = xpcall(function() currentContext(contextArgs) end, debug.traceback)
if not success then
	io.stderr:write("An error occurred during context execution:\n")
	io.stderr:write(errorMessage .. "\n")
	return false
end

return true
