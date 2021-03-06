local discordia = require "discordia"
local mutexes = {}

-- array, that allows holes
local hollowArray = {
	fill = function (self, o, pos)
		self.mutex:lock()
		pos = pos or self.space	-- pos may be nil
		if self[pos] == nil then self.n = self.n + 1 end
		self[pos] = o
		if pos > self.max then self.max = pos end
		while self[self.space] ~= nil do self.space = self.space + 1 end
		self.mutex:unlock()
		return pos
	end,
	
	drain = function (self, pos)
		if self[pos] == nil then return end
		
		self.mutex:lock()
		local ret = self[pos]
		self[pos] = nil
		self.n = self.n - 1
		if pos < self.space then self.space = pos end
		while self[self.max] == nil and self.max > 0 do self.max = self.max - 1 end
		self.mutex:unlock()
		return ret
	end
}

local haIter = function (t, index)
	if not index then index = 0 end
	index = index + 1
	
	repeat 
		if t[index] then
			return index, t[index]
		else
			index = index + 1
		end
	until index > t.max
	
	return nil
end

local hamt = {
	__index = hollowArray,
	__len = function (self) return self.n end,
	__pairs = function (self)
		return haIter, self
	end
}

-- classic set
local set = {
	add = function (self, o)
		if self[o] then return end
		
		self[o] = true
		self.n = self.n + 1
	end,
	
	remove = function (self, o)
		if not self[o] then return end
		
		self[o] = nil
		self.n = self.n - 1
	end,
	
	explist = function (self)
		return function (t, index)
			local k = next(t, index)
			if k == "n" then k = next(t,k) end
			return k
		end, self
	end
}

local smt = {
	__index = set,
	__len = function (self) return self.n end
}

local pcallFunc = function (statement, ...) statement:reset():bind(...):step() end

return {
	-- returns channels in the same order they are presented in the app
	-- https://imgur.com/a/hRWM73c
	truePositionSorting = function (a, b)
		return (not a.category and b.category) or
			(a.category and b.category and a.category.position < b.category.position) or
			(a.category == b.category and a.position < b.position)
	end,
	
	-- any interaction with database comes through here
	-- it ensures that no statement is used by two threads at the same time 
	storageInteractionEvent = function (statement, ...)
		if not mutexes[statement] then
			mutexes[statement] = discordia.Mutex()
		end
		mutexes[statement]:lock()
		local ok, msg = pcall(pcallFunc, statement, ...)
		mutexes[statement]:unlock()
		if not ok then error(msg) end
	end,
	
	hollowArray = setmetatable(hollowArray,{
		__call = function ()
			return setmetatable({n = 0, space = 1, max = 0, mutex = discordia.Mutex()},hamt)
		end
	}),
	
	set = setmetatable(set,{
		__call = function ()
			return setmetatable({n = 0},smt)
		end
	})
}