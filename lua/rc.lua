--[[
###############################
## Reactor Control Program   ##
## by nicon4454              ##
## 02/05/2020 v0.01          ##
###############################
]]

-- Please change this section tp match your needs
cb = peripheral.wrap("capacitor_bank_0")
br = peripheral.wrap("BigReactors-Reactor_0")
mon = peripheral.wrap("monitor_0")


-- DO NOT CHANGE ANYTHING BELOW THIS LINE --


-- yyy


function comma_value(amount)
    local formatted = amount
    while true do
        formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
        if (k == 0) then break end
    end
    return formatted
end

es = (comma_value(string.format("%.1d", (cb.getEnergyStored()))))
mes = (comma_value(string.format("%.1d", (cb.getMaxEnergyStored()))))
print("There is " .. es .. " out of a Max of " .. mes)
