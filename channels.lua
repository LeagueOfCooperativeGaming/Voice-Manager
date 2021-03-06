-- object to store data about new channels and interact with corresponding db
-- CREATE TABLE channels(id VARCHAR PRIMARY KEY, parent VARCHAR, position INTEGER)

local discordia = require "discordia"
local sqlite = require "sqlite3".open("channelsData.db")

local client, logger = discordia.storage.client, discordia.storage.logger

local storageInteractionEvent = require "./utils.lua".storageInteractionEvent

-- used to start storageInteractionEvent as async process
-- because fuck data preservation, we need dat speed
local emitter = discordia.Emitter()

-- prepared statements
local add, remove =
	sqlite:prepare("INSERT INTO channels VALUES(?,?,?)"),
	sqlite:prepare("DELETE FROM channels WHERE id = ?")

emitter:on("add", function (channelID, parent, position)
	local ok, msg = pcall(storageInteractionEvent, add, channelID, parent, position)
	if ok then
		logger:log(4, "MEMORY: Added channel %s", channelID)
	else
		logger:log(2, "MEMORY: Couldn't add channel %s: %s", channelID, msg)
		client:getChannel("686261668522491980"):sendf("Couldn't add channel %s: %s", channelID, msg)
	end
end)

emitter:on("remove", function (channelID)
	local ok, msg = pcall(storageInteractionEvent, remove, channelID)
	if ok then
		logger:log(4, "MEMORY: Removed channel %s", channelID)
	else
		logger:log(2, "MEMORY: Couldn't remove channel %s: %s", channelID, msg)
		client:getChannel("686261668522491980"):sendf("Couldn't remove channel %s: %s", channelID, msg)
	end
end)

return setmetatable({}, {
	-- move functions to index table to iterate over channels easily
	__index = {
		-- perform checks and add channel to table
		loadAdd = function (self, channelID, parent, position)
			if not self[channelID] then
				local channel = client:getChannel(channelID)
				if channel and channel.guild then
					self[channelID] = {parent = parent, position = position}
					logger:log(4, "GUILD %s: Added channel %s", channel.guild.id, channelID)
				end
			end
		end,
		
		-- loadAdd and start interaction with db
		add = function (self, channelID, parent, position)
			self:loadAdd(channelID, parent, position)
			if self[channelID] then emitter:emit("add", channelID, parent, position) end
		end,
		
		-- no granular control, if it goes away, it does so everywhere
		remove = function (self, channelID)
			if self[channelID] then
				self[channelID] = nil
				local channel = client:getChannel(channelID)
				if channel and channel.guild then
					logger:log(4, "GUILD %s: Removed channel %s", channel.guild.id, channelID)
				else
					logger:log(4, "NULL: Removed channel %s", channelID)
				end
			end
			emitter:emit("remove", channelID)
		end,
		
		load = function (self)
			logger:log(4, "STARTUP: Loading channels")
			local channelIDs = sqlite:exec("SELECT * FROM channels")
			if channelIDs then
				for i, channelID in ipairs(channelIDs[1]) do
					local channel = client:getChannel(channelID)
					if channel then
						if #channel.connectedMembers > 0 then
							self:loadAdd(channelID, channelIDs[2][i], tonumber(channelIDs[3][i]))
						else
							channel:delete()
						end
					else
						self:remove(channelID)
					end
				end
			end
			logger:log(4, "STARTUP: Loaded!")
		end,
		
		-- are there empty channels? kill!
		cleanup = function (self)
			for channelID,_ in pairs(self) do
				local channel = client:getChannel(channelID)
				if channel then
					if #channel.connectedMembers == 0 then
						channel:delete()
					end
				else
					self:remove(channelID)
				end
			end
		end,
		
		-- how many are there?
		people = function (self, guildID)
			local p = 0
			for channelID, _ in pairs(self) do
				local channel = client:getChannel(channelID)
				if channel then
					if guildID and channel.guild.id == guildID or not guildID then p = p + #channel.connectedMembers end
				else
					self:remove(channelID)
				end
			end
			return p
		end
	},
	__len = function (self)
		local count = 0
		for v,_ in pairs(self) do count = count + 1 end
		return count
	end
})