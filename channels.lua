local discordia = require "discordia"
local emitter = discordia.Emitter()
local client, logger = discordia.storage.client, discordia.storage.logger
local sqlite = require "sqlite3".open("channelsData.db")
local storageInteractionEvent = require "./utils.lua".storageInteractionEvent

local add, remove =
	sqlite:prepare("INSERT INTO channels VALUES(?)"),
	sqlite:prepare("DELETE FROM channels WHERE id = ?")

emitter:on("add", function (channelID)
	pcall(storageInteractionEvent, add, channelID)
end)

emitter:on("remove", function (channelID)
	pcall(storageInteractionEvent, remove, channelID)
end)

return setmetatable({}, {
	__index = {
		add = function (self, channelID)
			local channel = client:getChannel(channelID)
			if not self[channelID] then
				if channel then
					self[channelID] = true
					logger:log(4, "GUILD %s: Added channel %s", channel.guild.id, channelID)
				else
					
				end
			end
			emitter:emit("add", channelID)
		end,
		
		remove = function (self, channel)
			if self[channel.id] then
				self[channel.id] = nil
				logger:log(4, "GUILD %s: Deleted channel %s", channel.guild.id, channel.id)
			end
			emitter:emit("remove", channelID)
		end,
		
		load = function (self)
			logger:log(4, "STARTUP: Loading channels")
			local channelIDs = sqlite:exec("SELECT * FROM channels")
			if channelIDs then
				for _, channelID in ipairs(channelIDs[1]) do
					local channel = client:getChannel(channelID)
					if channel then
						if #channel.connectedMembers > 0 then
							self:add(channelID)
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
		end,
		
		inGuild = function (self, guildID)
			local count = 0
			for v,_ in pairs(self) do if client:getChannel(v).guild.id == guildID then count = count + 1 end end
			return count
		end
	},
	__len = function (self)
		local count = 0
		for v,_ in pairs(self) do count = count + 1 end
		return count
	end
})