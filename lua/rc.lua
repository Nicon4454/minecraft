--[[
###############################
## Reactor Control Program   ##
## by nicon4454              ## 
## 02/05/2020 v0.01          ##
###############################
]] -- Please change this section to match your needs(i.e. capacitor_bank_?)
cb = peripheral.wrap("capacitor_bank_0")
br = peripheral.wrap("BigReactors-Reactor_0")
mon = peripheral.wrap("monitor_0")

-- the ronp is the percent that the reactor will turn on when the power reaches that % of max power in your capacitor bank(s)
ronp = 0.25
-- the roffp is the percent that the reactor will turn off when the power reaches that % of max power in your capacitor bank(s)
roffp = 0.95
-- redrawl intervil in seconds (default is 5)
redrawl = 5

-- DO NOT CHANGE ANYTHING BELOW THIS LINE --
-- this is a list of enviroment cursor postions.

crft =
cch = 
cfh = 
cfl =
cwl = 
cactive =
ch = 0 -- case heat
fh = 0 -- Fuel heat
fl = 0 -- Fuel level
wl = 0 -- waste level
rft = 0 -- rf per a tick
ron = 0
roff = 0
active = 0 -- weather the reactor is on (1) or off (0)

function reactoronoffp()
    ron = (cb.getMaxEnergyStored() * ronp)
    roff = (cb.getMaxEnergyStored() * roffp)
end

function comma_value(amount)
    local formatted = amount
    while true do
        formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
        if (k == 0) then break end
    end
    return formatted
end
--[[ 
es = (comma_value(string.format("%.1d", (cb.getEnergyStored())))) 
mes = (comma_value(string.format("%.1d", (cb.getMaxEnergyStored()))))
print("There is " .. es .. " out of a Max of " .. mes)
]]

function reactoronoffp()
fron = (comma_value(string.format("%.1d", (ron))))
froff = (comma_value(string.format("%.1d", (roff))))
end
--[[
print("the reactor will turn off when the capacitor power reaches " .. froff ..
          " and it will turn on when it will reach " .. fron)
]]
function reactor_off()
br.setActive(false)
active = 0
end

function reactor_on()
br.setActive(true)
active = 1  
end

function getstats()
rft = (coma_value(string.format("%.1d", (br.getEnergyproducedLastTick()))))
ch = (coma_value(string.format("%.1d", (br.getCasingTemperature()))))
fh = (coma_value(string.format("%.1d", (br.getFuelTemperature()))))
fl = (coma_value(string.format("%.1d", (br.getFuelLevel()))))
wl = (coma_value(string.format("%.1d", (br.getWasteLevel()))))
end
