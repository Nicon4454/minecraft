local polynomial = {
	coefs = nil
}

function polynomial.make(coefs)
	local new_polynomial = {
		coefs = {}
	}

	for _, coef in pairs(coefs) do
		table.insert(new_polynomial.coefs, coef)
	end

	setmetatable(new_polynomial, {
		__index = polynomial
	})
	return new_polynomial
end

function polynomial.eval(polynomial, x)
	local fx = 0
	local x2 = 1
	for i, coef in pairs(polynomial.coefs) do
		fx = fx + coef*x2
		x2 = x2 * x
	end
	return fx
end

function polynomial.derivate(polynomial)
	local new_coefs = {}
	for i=2, #polynomial.coefs do
		table.insert(new_coefs, (i-1)*polynomial.coefs[i])
	end
	return polynomial.make(new_coefs)
end

function polynomial.toString(polynomial)
	local str = "0"
	for i, coef in pairs(polynomial.coefs) do
		if i > 1 then
			if coef > 0 then
				str = str .. " + " .. string.format("%f", coef) .. " x^" .. tostring(i-1)
			elseif coef < 0 then
				str = str .. " - " .. string.format("%f", -coef) .. " x^" .. tostring(i-1)
			end
		else
			str = string.format("%f", coef)
		end
	end
	return str
end

function polynomial.converge(polynomial, x, iterations)
	local df1 = polynomial:derivate()
	local df2 = df1:derivate()

	for i=1, iterations do
		x = x - df1:eval(x) / df2:eval(x)
	end
	return x
end

return polynomial