local polynomial = require("polynomial")
local matrix = require("matrix")

local polynomial_interpolator = {
}

local function QRstep(A, E, step)
	local v = A:extractC(step)
	for i=0, step-1 do
		v:set(i, 0, 0)
	end
	local u = E:extractC(step):multI(v:norm()):add(v)
	local H = E:sub(u:mult(u:transponate()):multI( 2.0 / u:transponate():mult(u):get(0,0) ))
	local As = H:mult(A)
	return { H = H, As = As }
end

local function QRsolve(As, x)
	local dimension = As.columns - 1
	local coefs = {}

	for i=0, dimension do
		table.insert(coefs, 0)
	end

	for i2=0, dimension do
		local i = dimension - i2
		local x = x:get(i, 0)

		for j=i+1, dimension do
			x = x - coefs[1 + j] * As:get(i, j)
		end
		coefs[1 + i] = x / As:get(i,i)
	end

	return coefs
end

function polynomial_interpolator.interpolate(data, dimension)
	assert(#data >= dimension+1, "Not enough data provided to interpolate a polynom of the desired dimension")

	local E = matrix.makeE(#data, #data)
	local A = matrix.make(#data, dimension+1)
	local b = matrix.make(#data, 1)

	for i=0, #data-1 do
		for j=0, dimension do
			A:set(i, j, math.pow(data[i+1][1], j))
		end
		b:set(i, 0, data[i+1][2])
	end

	local ip = QRstep(A, E, 0)
	local Q = ip.H
	for i=1, dimension do
		ip = QRstep(ip.As, E, i)
		Q = Q:mult(ip.H)
	end

	local x = Q:transponate():mult(b)

	local coefs = QRsolve(ip.As, x)
	return polynomial.make(coefs)
end

setmetatable(polynomial_interpolator, {
	__call = polynomial_interpolator.interpolate
})

return polynomial_interpolator