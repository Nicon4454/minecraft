local oop = {
};

function oop.make(c)
	setmetatable(c, {
		__call = oop.new;
	});
end

function oop.inherit(c, base)
	setmetatable(c, {
		__index = base;
		__call = oop.new;
	});
end

function oop:new(...)
	local out = {};
	setmetatable(out, {
		__index = self;
	});
	
	if out.construct then
		out:construct(...);
	end
	
	return out;
end

function oop.instantiate(template, ...)
	return oop.new(template, ...);
end

function oop.exportFunctions(object)
	local meta = {
		obj = object;
		__index = function(t, k)
			m = getmetatable(t);
			if type(m.obj[k]) == "function" then
				return m.obj[k];
			else
				return nil;
			end
		end
	};
	return setmetatable({}, meta);
end

return {
	make = oop.make,
	inherit = oop.inherit,
	instantiate = oop.instantiate,
	exportFunctions = oop.exportFunctions
};