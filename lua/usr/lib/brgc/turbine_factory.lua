local config = require("brgc/config")
local turbine_base = require("brgc/turbine")

local turbine_factory = {

}


function turbine_factory:make(turbineAddress)
	checkArg(1, turbineAddress, "string")

	local turbineConfig = config.getTurbineConfigOrDefault(turbineAddress)
	assert(turbineConfig ~= nil, "Failed to get turbine configuration")

	local turbine = turbine_base(turbineAddress, turbineConfig)

	if not turbine:connect() then
		return nil
	end

	return turbine
end

setmetatable(turbine_factory, { __call = turbine_factory.make })

return turbine_factory