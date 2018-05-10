local uuid = require("uuid")
local oop = require("oop")
local thread = require("thread")

-- Workaround for a bug in OpenOS 1.7.1 on Lua 5.3 mode.
-- Hopefully this will be removed some day...
_G.bit32 = require("bit32")

local promise = {
	uuid_ = nil,
	onCompletionCallbacks_ = {},
	onFailureCallbacks_ = {},
	onFinallyCallbacks_ = {},
	retvalCompleted_ = nil,
	retvalFailed_ = nil,
	thread_ = nil
}
oop.make(promise)

function promise:construct(taskProc, ...)
	local this = self
	local this_uuid = uuid.next()
	self.uuid_ = this_uuid

	local on_complete = function(self, ...)
		for _, callback in pairs(self.onCompletionCallbacks_) do
			xpcall(callback, function(...)
				io.stderr:write("[promise " .. this_uuid .. "] Error in completion handler\n" .. debug.traceback( ... ) .. "\n")
			end, ...)
		end
	end

	local on_failure = function(self, ...)
		for _, callback in pairs(self.onFailureCallbacks_) do
			xpcall(callback, function(...)
				io.stderr:write("[promise " .. this_uuid .. "] Error in failure handler\n" .. debug.traceback( ... ) .. "\n")
			end, ...)
		end

		if #self.onFailureCallbacks_ == 0 then
			io.stderr:write("[promise " .. this_uuid .. "] " .. debug.traceback( ... ) .. "\n")
		end
	end

	local on_finally = function(self)
		for _, callback in pairs(self.onFinallyCallbacks_) do
			xpcall(callback, function(...)
				io.stderr:write("[promise " .. this_uuid .. "] Error in finally handler\n" .. debug.traceback( ... ) .. "\n")
			end)
		end
	end

	local thread_proc = function(self, ...)
		os.sleep()
		local retval = table.pack(xpcall(taskProc, function(...)
			this.retvalFailed_ = table.pack(...)
			on_failure(this, ...)
			on_finally(this)
		end, ...))

		if retval[1] then
			table.remove(retval, 1)
			self.retvalCompleted_ = retval
			on_complete(this, table.unpack(retval))
			on_finally(this)
		end
	end

	self.thread_ = thread.create(thread_proc, self, ...)
end

function promise:after(callback, ...)
	checkArg(1, callback, "function")

	local this = self
	local args = table.pack(...)

	if self.retvalCompleted_ == nil then
		table.insert(self.onCompletionCallbacks_, function(...)
			if #args > 0 then
				callback(table.unpack(args), ...)
			else
				callback(...)
			end
		end)
	elseif #args > 0 then
		xpcall(callback, function(...)
			io.stderr:write("[promise " .. this.uuid_ .. "] Error in completion handler\n" .. debug.traceback( ... ) .. "\n")
		end, ..., table.unpack(self.retvalCompleted_))
	else
		xpcall(callback, function(...)
			io.stderr:write("[promise " .. this.uuid_ .. "] Error in completion handler\n" .. debug.traceback( ... ) .. "\n")
		end, table.unpack(self.retvalCompleted_))
	end

	return self
end

function promise:catch(callback, ...)
	checkArg(1, callback, "function")

	local this = self
	local args = table.pack(...)

	if self.retvalFailed_ == nil then
		table.insert(self.onFailureCallbacks_, function(...)
			if #args > 0 then
				callback(table.unpack(args), ...)
			else
				callback(...)
			end
		end)
	elseif #args > 0 then
		xpcall(callback, function(...)
			io.stderr:write("[promise " .. this.uuid_ .. "] Error in failure handler\n" .. debug.traceback( ... ) .. "\n")
		end, ..., table.unpack(self.retvalFailed_))
	else
		xpcall(callback, function(...)
			io.stderr:write("[promise " .. this.uuid_ .. "] Error in failure handler\n" .. debug.traceback( ... ) .. "\n")
		end, table.unpack(self.retvalFailed_))
	end

	return self
end

function promise:finally(callback, ...)
	checkArg(1, callback, "function")

	local this = self
	local args = table.pack(...)

	if self.retvalCompleted_ == nil and self.retvalFailed_ == nil then
		table.insert(self.onFinallyCallbacks_, function()
			callback(table.unpack(args))
		end)
	else
		xpcall(callback, function(...)
			io.stderr:write("[promise " .. this.uuid_ .. "] Error in finally handler\n" .. debug.traceback( ... ) .. "\n")
		end, ...)
	end

	return self
end

function promise:wait()
	thread.waitForAll({self.thread_})
end

return promise
