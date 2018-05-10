local filesystem = require("filesystem")
local serialization = require("serialization")

local config_api = {
	turbines = { },
	reactors = { },

	default_turbine = { },
	default_reactor = { }
}

function config_api.writeComponentData(file, address, data)
	file:write("        [\"" .. tostring(address) .. "\"] = {\n")
	local maxPropNameLength = 0

	for key, _ in pairs(data) do
		if string.len(key) > maxPropNameLength then
			maxPropNameLength = string.len( key )
		end
	end

	for key, value in pairs(data) do
		if type(value) == "table" then
			file:write(string.format( "            % " .. tostring(maxPropNameLength) .. "s = %s,\n",
				key, serialization.serialize(value)))
		elseif type(value) == "string" then
			file:write(string.format( "            % " .. tostring(maxPropNameLength) .. "s = \"%s\",\n",
				key, value))
		else
			file:write(string.format( "            % " .. tostring(maxPropNameLength) .. "s = %s,\n",
				key, tostring(value)))
		end
	end

	file:write("        },\n")
end

function config_api.load()
	local f = io.open("/etc/br_control.cfg","r")
	if f then
		local config_string = f:read("*all")
		f:close()
		local config = serialization.unserialize(config_string)
		if config then
			config_api.turbines = {}
			for address, turbine in pairs(config.turbines or {}) do
				if address == "default" then
					config_api.default_turbine = turbine
				else
					config_api.turbines[address] = turbine
				end
			end

			config_api.reactors = {}
			for address, reactor in pairs(config.reactors or {}) do
				if address == "default" then
					config_api.default_reactor = reactor
				else
					config_api.reactors[address] = reactor
				end
			end
			return true
		end
	end
	return false
end

function config_api.save()
	local root = filesystem.get("/")
	if root and not root.isReadOnly() then
		filesystem.makeDirectory("/etc")
		local f = io.open("/etc/br_control.cfg", "w")

		if f then
			-- Sort reactors
			local reactors = {}
			for address, reactor in pairs(config_api.reactors) do
				table.insert(reactors, { address = address, reactor = reactor })
			end
			table.sort(reactors, function(a,b) return a.address < b.address end)

			-- Sort turbines
			local turbines = {}
			for address, turbine in pairs(config_api.turbines) do
				table.insert(turbines, { address = address, turbine = turbine })
			end
			table.sort(turbines, function(a,b) return a.address < b.address end)

			-- Write data
			f:write("{\n")
			f:write("    reactors = {\n")

			config_api.writeComponentData(f, "default", config_api.default_reactor)
			for _, v in pairs(reactors) do
				config_api.writeComponentData(f, v.address, v.reactor)
			end

			f:write("    },\n")
			f:write("    turbines = {\n")

			config_api.writeComponentData(f, "default", config_api.default_turbine)
			for _, v in pairs(turbines) do
				config_api.writeComponentData(f, v.address, v.turbine)
			end

			f:write("    }\n")
			f:write("}\n")
			f:close()
		end
	end
end

function config_api.setReactor(address, config)
	config_api.reactors[address] = config
	config_api.save()
end

function config_api.setReactorAttribute(address, var, val)
	config_api.reactors[address][var] = val
	config_api.save()
end

function config_api.getReactorConfig(address)
	return config_api.reactors[address]
end

function config_api.getDefaultReactorConfig()
	return config_api.default_reactor
end

function config_api.getReactorConfigOrDefault(address)
	local config = config_api.getReactorConfig(address)
	if config then
		return config
	else
		local newconfig = { }
		setmetatable(newconfig, { __index = config_api.getDefaultReactorConfig() })
		return newconfig
	end
end

function config_api.setTurbine(address, config)
	config_api.turbines[address] = config
	config_api.save()
end

function config_api.setTurbineAttribute(address, var, val)
	config_api.turbines[address][var] = val
	config_api.save()
end

function config_api.getTurbineConfig(address)
	return config_api.turbines[address]
end

function config_api.getDefaultTurbineConfig()
	return config_api.default_turbine
end

function config_api.getTurbineConfigOrDefault(address)
	local config = config_api.getTurbineConfig(address)
	if config then
		return config
	else
		local newconfig = { }
		setmetatable(newconfig, { __index = config_api.getDefaultTurbineConfig() })
		return newconfig
	end
end


return config_api