--[[
###############################
## Reactor Control Program   ##
## by nicon4454              ##
## 02/05/2020 v0.01          ##
###############################
]]

-- Please change this section to match your needs
cb = peripheral.wrap("capacitor_bank_0")
br = peripheral.wrap("BigReactors-Reactor_0")
mon = peripheral.wrap("monitor_0")

-- the ron is the percent that the reactor will turn on when the power reaches that % of max power in your capacitor bank(s)
ron = 0.25
-- the roff is the percent that the reactor will turn off when the power reaches that % of max power in your capacitor bank(s)
roff = 0.95
-- DO NOT CHANGE ANYTHING BELOW THIS LINE --
ch = 0 --case heat
fh = 0 --Fuel heat
fl = 0 --Fuel level
wl = 0 --waste level
active = 0 --weather the reactor is on (1) or off (0)






function 

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
