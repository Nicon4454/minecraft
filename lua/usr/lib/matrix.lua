local matrix = {
	columns = nil,
	rows = nil,
	data = nil,
}


function matrix.make(rows, columns)
	assert(tonumber(rows) ~= nil, "rows needs to be a number")
	assert(tonumber(columns) ~= nil, "columns needs to be a number")
	assert(rows > 0 and columns > 0, "Invalid dimension for matrix: " .. tostring(rows) .."x" .. tostring(columns))

	local new_matrix = {
		rows = rows,
		columns = columns,
		data = {}
	}

	for i=1,(rows*columns) do
		table.insert(new_matrix.data, 0)
	end

	setmetatable(new_matrix, {
		__index = matrix;
	})
	return new_matrix
end

function matrix.makeE(rows, columns)
	local result = matrix.make(rows, columns)

	for i=0, math.min(rows, columns)-1 do
		result:set(i, i, 1)
	end
	return result
end

function matrix.set(matrix, row, column, value)
	assert(tonumber(row) ~= nil, "row needs to be a number")
	assert(tonumber(column) ~= nil, "column needs to be a number")
	assert(tonumber(value) ~= nil, "value needs to be a number")
	assert(row < matrix.rows and column < matrix.columns, "Tried to access cell [" .. tostring(row) .."][" .. tostring(column) .. "] of matrix " .. tostring(matrix) .. " with dimension " .. tostring(matrix.rows) .. "x" .. tostring(matrix.columns))

	matrix.data[1 + column*matrix.rows + row] = tonumber(value);
end

function matrix.get(matrix, row, column)
	assert(tonumber(row) ~= nil, "row needs to be a number")
	assert(tonumber(column) ~= nil, "column needs to be a number")
	assert(row < matrix.rows and column < matrix.columns, "Tried to access cell [" .. tostring(row) .."][" .. tostring(column) .. "] of matrix " .. tostring(matrix) .. " with dimension " .. tostring(matrix.rows) .. "x" .. tostring(matrix.columns))

	return matrix.data[1 + column*matrix.rows + row];
end

function matrix.extractC(matrix, column)
	assert(tonumber(column) ~= nil, "column needs to be a number")

	local result = matrix.make(matrix.rows, 1)
	for row=0, matrix.rows-1 do
		result:set(row, 0, matrix:get(row, column))
	end
	return result
end

function matrix.sub(matrixA, matrixB)
	assert(matrixA.rows == matrixB.rows and matrixA.columns == matrixB.columns, "Tried to substract two incompatible matrices: LHS has dimension " .. tostring(matrixA.rows) .. "x" .. tostring(matrixA.columns) .. ", RHS has dimension " .. tostring(matrixB.rows) .. "x" .. tostring(matrixB.columns))
	local result = matrix.make(matrixA.rows, matrixA.columns)

	for i=1,(matrixA.rows*matrixA.columns) do
		result.data[i] = matrixA.data[i] - matrixB.data[i]
	end
	return result
end

function matrix.add(matrixA, matrixB)
	assert(matrixA.rows == matrixB.rows and matrixA.columns == matrixB.columns, "Tried to add two incompatible matrices: LHS has dimension " .. tostring(matrixA.rows) .. "x" .. tostring(matrixA.columns) .. ", RHS has dimension " .. tostring(matrixB.rows) .. "x" .. tostring(matrixB.columns))
	local result = matrix.make(matrixA.rows, matrixA.columns)

	for i=1,(matrixA.rows*matrixA.columns) do
		result.data[i] = matrixA.data[i] + matrixB.data[i]
	end
	return result
end

function matrix.mult(matrixA, matrixB)
	assert(matrixA.columns == matrixB.rows, "Tried to multiply two incompatible matrices: LHS has dimension " .. tostring(matrixA.rows) .. "x" .. tostring(matrixA.columns) .. ", RHS has dimension " .. tostring(matrixB.rows) .. "x" .. tostring(matrixB.columns))
	local result = matrix.make(matrixA.rows, matrixB.columns)

	for column=0, matrixB.columns-1 do
		for row=0, matrixA.rows-1 do
			local cell_value = 0
			for i=0, matrixA.columns-1 do
				cell_value = cell_value + matrixA:get(row, i) * matrixB:get(i, column)
			end
			result:set(row, column, cell_value)
		end
	end
	return result
end

function matrix.multI(matrix, mult)
	assert(tonumber(mult) ~= nil, "mult needs to be a number")
	local result = matrix.make(matrix.rows, matrix.columns)

	for i=1,(matrix.rows*matrix.columns) do
		result.data[i] = mult * matrix.data[i]
	end
	return result
end

function matrix.transponate(matrix)
	local result = matrix.make(matrix.columns, matrix.rows)

	for column=0, matrix.columns-1 do
		for row=0, matrix.rows-1 do
			result:set(column, row, matrix:get(row, column))
		end
	end
	return result
end

function matrix.norm(matrix, norm)
	if norm == nil then
		norm = 2
	end

	local tmp = 0
	for i=1,(matrix.rows*matrix.columns) do
		tmp = tmp + math.pow(matrix.data[i], norm)
	end
	return math.pow(tmp, 1/norm)
end

function matrix.dump(matrix)
	print(tostring(matrix.rows) .. "x" .. tostring(matrix.columns))
	for row=0, matrix.rows-1 do
		local str = nil
		for column=0, matrix.columns-1 do
			if str ~= nil then
				str = str .. string.format(" % 10.6f", matrix:get(row, column))
			else
				str = string.format("% 10.6f", matrix:get(row, column))
			end
		end
		print(str)
	end
end


return matrix