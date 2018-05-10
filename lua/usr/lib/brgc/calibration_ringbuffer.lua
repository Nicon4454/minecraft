local oop = require("oop")

local calibration_ringbuffer = {
	mBuffer = nil,
	mSizeMax = 0,
	mAverage = nil,
	mStandardDeviation = nil,
	mMonotonicSince = 0,
	mMonotonicDirection = 0
}
oop.make(calibration_ringbuffer)

function calibration_ringbuffer:construct(size)
	checkArg(1, size, "number")

	self.mSizeMax = size
	self.mBuffer = {}
end

function calibration_ringbuffer:count()
	return  #self.mBuffer
end

function calibration_ringbuffer:getAverage()
	return self.mAverage
end

function calibration_ringbuffer:getStandardDeviation()
	return self.mStandardDeviation
end

function calibration_ringbuffer:isMonotonic()
	return #self.mBuffer > 0 and (#self.mBuffer - 1) / 3 <= self.mMonotonicSince
end

function calibration_ringbuffer:push(value)
	checkArg(1, value, "number")

	table.insert(self.mBuffer, value)

	while #self.mBuffer > self.mSizeMax do
		table.remove(self.mBuffer, 1)
	end

	local newAverage = self:calculateAverage()

	if #self.mBuffer > 1 then
		if self.mAverage > newAverage then
			if self.mMonotonicDirection == -1 then
				self.mMonotonicSince = math.min(self.mMonotonicSince + 1, self.mSizeMax)
			else
				self.mMonotonicSince = 1
				self.mMonotonicDirection = -1
			end
		elseif self.mAverage < newAverage then
			if self.mMonotonicDirection == 1 then
				self.mMonotonicSince = math.min(self.mMonotonicSince + 1, self.mSizeMax)
			else
				self.mMonotonicSince = 1
				self.mMonotonicDirection = 1
			end
		else
			self.mMonotonicSince = self.mMonotonicSince + 1
		end
	end

	self.mAverage = newAverage
	self.mStandardDeviation = self:calculateStandardDeviation()
end

function calibration_ringbuffer:calculateAverage()
	local avg = 0

	if #self.mBuffer == 0 then
		return nil
	end

	for _, val in pairs(self.mBuffer) do
		avg = avg + val / #self.mBuffer
	end

	return avg
end

function calibration_ringbuffer:calculateStandardDeviation()
	local avg = self:getAverage()

	if #self.mBuffer == 0 then
		return nil
	end

	local tmp = 0
	for _, val in pairs(self.mBuffer) do
		tmp = tmp + (val - avg) * (val - avg) / #self.mBuffer
	end

	return math.sqrt(tmp)
end

return calibration_ringbuffer
