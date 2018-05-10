local config = require("brgc/config")
local component = require("component")
local reactor_active = require("brgc/reactor_active")
local reactor_passive = require("brgc/reactor_passive")

local reactor_factory = {

}


function reactor_factory:make(reactorAddress)
	checkArg(1, reactorAddress, "string")

	local reactorConfig = config.getReactorConfigOrDefault(reactorAddress)
	assert(reactorConfig ~= nil, "Failed to get reactor configuration")

	local reactor_proxy = component.proxy(reactorAddress)
	local reactor
	if reactor_proxy.isActivelyCooled() then
		reactor = reactor_active(reactorAddress, reactorConfig)
	else
		reactor = reactor_passive(reactorAddress, reactorConfig)
	end

	if not reactor:connect() then
		return nil
	end

	reactor:recalculateOpts()

	return reactor
end

setmetatable(reactor_factory, { __call = reactor_factory.make })

return reactor_factory