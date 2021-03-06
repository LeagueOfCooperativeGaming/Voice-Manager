--[[
object to store data about embeds. there's no database to store data about embeds as there's no need for that
embeds are enhanced message structures with additional formatting options
https://leovoel.github.io/embed-visualizer/
https://discord.com/developers/docs/resources/channel#embed-object
]]

local discordia = require "discordia"
local client, sqlite, logger = discordia.storage.client, discordia.storage.sqlite, discordia.storage.logger
local guilds = require "./guilds.lua"
local locale = require "./locale"

return setmetatable({}, {
	-- move functions and static data to index table to iterate over embeds easily
	__index = {
		-- all relevant emojis
		reactions = {"1️⃣","2️⃣","3️⃣","4️⃣","5️⃣","6️⃣","7️⃣","8️⃣","9️⃣","🔟",
			["1️⃣"] = 1, ["2️⃣"] = 2, ["3️⃣"] = 3, ["4️⃣"] = 4, ["5️⃣"] = 5, ["6️⃣"] = 6, ["7️⃣"] = 7, ["8️⃣"] = 8, ["9️⃣"] = 9, ["🔟"] = 10,
			left = "⬅", right = "➡", page = "📄", all = "*️⃣", stop = "❌",
			["⬅"] = "left", ["➡"] = "right", ["📄"] = "page", ["*️⃣"] = "all", ["❌"] = "stop"},
		
		-- create new data entry
		new = function (self, action, page, ids)
			local reactions = self.reactions
			local argument = action:match("^template(.-)$") or action:match("^target(.-)$")
			action = action:match("^template") or action:match("^target") or action
			local nids = #ids
			
			local embed = {
				title = action:gsub("^.", string.upper, 1),	-- upper bold text
				color = 6561661,
				description = (action == "register" and locale.embedRegister or 
					action == "unregister" and locale.embedUnregister or 
					action == "template" and (argument == "" and locale.embedResetTemplate or locale.embedTemplate) or
					action == "target" and (argument == "" and locale.embedResetTarget or locale.embedTarget)
					):format(argument).."\n"..(nids > 10 and (locale.embedPage.."\n") or "")..locale.embedAll.."\n",
				footer = {text = (nids > 10 and (locale.embedPages:format(page, math.ceil(nids/10)).." | ") or "")..locale.embedDelete}	-- page number
			}
			
			for i=10*(page-1)+1,10*page do
				if not ids[i] then break end
				local channel = client:getChannel(ids[i])
				embed.description = embed.description.."\n"..reactions[math.fmod(i-1,10)+1]..
					string.format(locale.channelNameCategory, channel.name, channel.category and channel.category.name or "no category")
			end
			
			return embed
		end,
		
		-- sprinkle those button emojis!
		decorate = function (self, message)
			local reactions = self.reactions
			local embedData = self[message]
			if embedData.page ~= 1 then message:addReaction(reactions.left) end
			for i=10*(embedData.page-1)+1, 10*embedData.page do
				if not embedData.ids[i] then break end
				message:addReaction(reactions[math.fmod(i-1,10)+1])
			end
			if embedData.page ~= math.modf(#embedData.ids/10)+1 then message:addReaction(reactions.right) end
			if #embedData.ids > 10 then message:addReaction(reactions.page) end
			message:addReaction(reactions.all)
			message:addReaction(reactions.stop)
		end,
		
		-- create, save and send fully formed embed and decorate
		send = function (self, message, action, ids)
			local embed = self:new(action, 1, ids)
			local newMessage = message:reply {embed = embed}
			if newMessage then
				self[newMessage] = {embed = embed, killIn = 10, ids = ids, page = 1, action = action, author = message.author}
				self:decorate(newMessage)
				
				return newMessage
			end
		end,
		
		updatePage = function (self, message, page)
			local embedData = self[message]
			embedData.embed = self:new(embedData.action, page, embedData.ids)
			embedData.killIn = 10
			embedData.page = page
			
			message:clearReactions()
			message:setEmbed(embedData.embed)
			self:decorate(message)
		end,
		
		-- it dies if not noticed for long enough
		tick = function (self)
			for message, embedData in pairs(self) do
				if message and message.channel then
					embedData.killIn = embedData.killIn - 1
					if embedData.killIn == 0 then
						self[message] = nil
						message:delete()
					end
				else
					self[message] = nil
				end
			end
		end
	}
})
