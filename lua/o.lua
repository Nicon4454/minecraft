-- file = io.open("methods.txt", "a")
m = peripheral.wrap("BigReactors-Reactor_0")

--[[
for i, v in ipairs(peripheral.getMethods("BigReactors-Reactor_0")) do
    print(i .. ". " .. v)
    o = (i .. ". " .. v)
    file:write(o .. "\n")
end
file:close()
]]
print(m)
