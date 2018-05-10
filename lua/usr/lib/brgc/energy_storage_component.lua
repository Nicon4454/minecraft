local component = require("component")
local computer = require("computer")
local oop = require("oop")

local energy_storage_component = {
	mAddress = nil,
	mComponent = nil,
	mEnergyTransformFactor = 1,
	mEnergyStored = 0,
	mEnergyStoredMax = 0,
	mEnergyStoredLast = 0,
	mLastUpdate = 0,
	mCompatibleComponents = {
		["capacitor_bank"] = 1,
		["draconic_rf_storage"] = 1,
		["rftools_powercell"] = 1,
		["energy_device"] = 1,
		["induction_matrix"] = 0.4
	}
}
oop.make(energy_storage_component)

function energy_storage_component:construct(address)
	checkArg(1, address, "string")

	self.mAddress = address
	self.mComponent = component.proxy(address)

	if self.mComponent then
		self.mEnergyTransformFactor = energy_storage_component.mCompatibleComponents[self.mComponent.type] or 1
	end

	if self.mComponent and self.mComponent.getEnergy then
		self.mComponent.getEnergyStored = self.mComponent.getEnergy
	end
	if self.mComponent and self.mComponent.getMaxEnergy then
		self.mComponent.getMaxEnergyStored = self.mComponent.getMaxEnergy
	end

	if self.mComponent and self.mComponent.getEnergyStored and self.mComponent.getMaxEnergyStored then
		-- The component supports storing energy
	else
		self.mComponent = nil
	end
end

function energy_storage_component:isGood()
	return self.mComponent ~= nil
end

function energy_storage_component:getEnergyStored()
	return self.mEnergyStored
end

function energy_storage_component:getEnergyStoredLast()
	return self.mEnergyStoredLast
end

function energy_storage_component:getMaxEnergyStored()
	return self.mEnergyStoredMax
end

function energy_storage_component:update()
	local now = computer.uptime() * 20
	if now == self.mLastUpdate then
		return
	end

	self.mEnergyStoredLast = self.mEnergyStored
	self.mEnergyStored = self.mComponent.getEnergyStored() * self.mEnergyTransformFactor
	self.mEnergyStoredMax = self.mComponent.getMaxEnergyStored() * self.mEnergyTransformFactor

	self.mLastUpdate = now
end

function energy_storage_component.isCompatible(componentName)
	checkArg(1, componentName, "string")

	return not not energy_storage_component.mCompatibleComponents[componentName]
end

function energy_storage_component.isCompatibleAddress(componentAddress)
	checkArg(1, componentAddress, "string")

	local result1, result2 =  pcall(function()
		return energy_storage_component(componentAddress):isGood()
	end)

	return result1 and result2
end

return energy_storage_component
