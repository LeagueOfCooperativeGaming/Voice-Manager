local discordia = require "../deps/discordia/init.lua"
local config = require "./config.lua"
local https = require "coro-http"
local json = require "json"

local client = discordia.Client {routeDelay = 300}
local clock = discordia.Clock()
local logger = discordia.Logger(4, '%F %T')
local serversMutex, channelsMutex = discordia.Mutex(), discordia.Mutex()
local permission, channelType = discordia.enums.permission, discordia.enums.channelType

local servers
local stats = {servers = 0, lobbies = 0, channels = 0, people = 0}

local commands = {
	help = "help",
	register = "register",
	unregister = "unregister",
	list = "list",
	shutdown = "shutdown",
	stats = "stats",
	support = "support",
	id = "id"
}

local pingServer = function (serverID)
	if client:getGuild(serverID) then 
		if not servers[serverID] then
			servers[serverID] = {}
		end
		return true
	elseif servers[serverID] then
		servers[serverID] = nil
	end
end

local pingChannel = function (serverID, channelID)
	if pingServer(serverID) then
		if client:getChannel(channelID) then
			return true
		elseif servers[serverID][channelID] then
			servers[serverID][channelID] = nil
		end
	end
end

servers = setmetatable({
	-- serverID = {channelID = 0 (if main lobby) or 1 (if new lobby)}
},{
	__index = {
		load = function (self)		-- used only upon startup
			for _, guild in pairs(client.guilds) do self[guild.id] = {} end
			serversMutex:lock()
			logger:log(3, "Loading servers file")
			local serverCount, channelCount = 0,0
			local file, err = io.open(config.saveServers,"r")
			if file then
				logger:log(4, "Found servers save file, reading...")
				for line in file:read("*all"):gmatch("(.-)\n") do
					local serverID = line:match("%d+")
					if client:getGuild(serverID) then
						serverCount = serverCount + 1
						self[serverID] = {}
						local server = self[serverID]
						for channelID in line:gmatch("%s(%d+)") do
							if client:getChannel(channelID) then
								channelCount = channelCount + 1
								server[channelID] = 0
							end
						end
					else
						logger:log(2, "No servers info found")
					end
				end
				file:close()
				logger:log(4, "Done with servers save file, found "..serverCount.." servers and "..channelCount.." bound channels")
				stats.servers = serverCount
				stats.lobbies = channelCount
			else
				logger:log(1, "Couldn't open the servers file, "..err)
			end
			serversMutex:unlock()
			
			serverCount, channelCount = 0,0
			channelsMutex:lock()
			logger:log(3, "Loading channels file")
			file, err = io.open(config.saveChannels,"r")
			if file then
				logger:log(4, "Found channels save file, reading...")
				stats.people = 0
				for line in file:read("*all"):gmatch("(.-)\n") do
					local serverID = line:match("%d+")
					if client:getGuild(serverID) then
						serverCount = serverCount + 1
						if not self[serverID] then self[serverID] = {} end
						local server = self[serverID]
						for channelID in line:gmatch("%s(%d+)") do
							local channel = client:getChannel(channelID)
							if channel then
								channelCount = channelCount + 1
								stats.people = stats.people + #channel.connectedMembers
								server[channelID] = 1
							end
						end
					else
						logger:log(2, "No channels info found")
					end
				end
				file:close()
				logger:log(4, "Done with channels save file, found "..serverCount.." servers and "..channelCount.." new channels")
				stats.servers = serverCount
				stats.channels = channelCount
			else
				logger:log(1, "Couldn't open the channels file, "..err)
			end
			channelsMutex:unlock()
		end,

		saveServers = function (self)
			local serverCount, channelCount = 0,0
			serversMutex:lock()
			logger:log(3, "Updating servers file")
			local file, err = io.open(config.saveServers,"w")
			if file then
				logger:log(4, "Found servers save file, writing...")
				for serverID, server in pairs(self) do
					if pingServer(serverID) then
						serverCount = serverCount + 1
						file:write(serverID)
						for channelID, type in pairs(server) do
							if pingChannel(serverID, channelID) then
								if type == 0 then
									file:write(" ",channelID)
									channelCount = channelCount + 1
								end
							end
						end
						file:write("\n")
					end
				end
				file:close()
				logger:log(4, "Done with servers save file, wrote "..serverCount.." servers and "..channelCount.." bound channels")
				stats.servers = serverCount
				stats.channels = channelCount
			else
				logger:log(1, "Couldn't open the servers file, "..err)
			end
			serversMutex:unlock()
		end,
		
		saveChannels = function (self)
			local serverCount, channelCount = 0,0
			channelsMutex:lock()
			logger:log(3, "Updating channels file")
			local file, err = io.open(config.saveChannels,"w")
			if file then
				logger:log(4, "Found channels save file, writing...")
				stats.people = 0
				for serverID, server in pairs(self) do
					if pingServer(serverID) then
						serverCount = serverCount + 1
						file:write(serverID)
						for channelID, type in pairs(server) do
							if pingChannel(serverID, channelID) and type == 1 then
								file:write(" ",channelID)
								stats.people = stats.people + #client:getChannel(channelID).connectedMembers
								channelCount = channelCount + 1
							end
						end
						file:write("\n")
					end
				end
				file:close()
				logger:log(4, "Done with channels save file, wrote "..serverCount.." servers and "..channelCount.." new channels")
				stats.servers = serverCount
				stats.channels = channelCount
			else
				logger:log(1, "Couldn't open the channels file, "..err)
			end
			channelsMutex:unlock()
		end
	}
})

local statservers = setmetatable({
	["discordbotlist.com"] = {
		endpoint = "https://discordbotlist.com/api/bots/601347755046076427/stats",
		body = "guilds"
	},
	
	["top.gg"] = {
		endpoint = "https://top.gg/api/bots/601347755046076427/stats",
		body = "server_count"
	},
	
	["botsfordiscord.com"] = {
		endpoint = "https://botsfordiscord.com/api/bot/601347755046076427",
		body = "server_count"
	},
	
	["discord.boats"] = {
		endpoint = "https://discord.boats/api/bot/601347755046076427",
		body = "server_count"
	},
	
	--["bots.ondiscord.xyz"] = {
	--	endpoint = "https://bots.ondiscord.xyz/bot-api/bots/601347755046076427/guilds",
	--	body = "guildCount"
	--},
	
	["discord.bots.gg"] = {
		endpoint = "https://discord.bots.gg/api/v1/bots/601347755046076427/stats",
		body = "guildCount"
	}
},{
	__call = function (self)
		for name, server in pairs(self) do 
			coroutine.wrap(function (name, server)
				local res, body = https.request("POST",server.endpoint,
					{{"Authorization", config.tokens[name]},{"Content-Type", "application/json"},{"Accept", "application/json"}},
					json.encode({[server.body] = stats.servers}))
				if res.code ~= 204 and res.code ~= 200 then 
					logger:log(2, "Couldn't send stats to "..name.." - "..body)
				end
			end)(name, server)
		end 
	end
})

local actions
actions = {
	[commands.help] = function (message)
		logger:log(4, "Help action invoked")
		message:reply("Ping this bot to get help message\nWrite commands after the mention, for example - `@Voice Manager register 123456789123456780`\n`"..
			commands.register.." [voice_chat_id OR voice_chat_name]` - registers a voice chat that will be used as a lobby\n`"..
			commands.unregister.." [voice_chat_id OR voice_chat_name]` - unregisters an existing lobby\n`"..
			commands.id.." [voice_chat_name OR category_name]` - use this to learn ids of voice channels by name or category\n**:arrow_up: You need a 'Manage Channels permission to use those commands! :arrow_up:**\n`"..
			commands.list.."` - lists all registered lobbies and how many new channels exist\n`"..
			commands.stats.."` - take a sneak peek on bot's performance!\n`"..
			commands.support.."` - sends an invite to support Discord server")
	end,
	
	regFilter = function (message, command)
		if not message.member:hasPermission(permission.manageChannels) then
			logger:log(4, "Mention in vain")
			message:reply(message.author.mentionString.. ', you need to have "Manage Channels" permission to do this')
			return
		end
		
		logger:log(4, command.." action invoked")
		local id = message.content:match(command.."%s+(.-)$")
		
		if not tonumber(id) and type(id) == "string" then
			id = id:lower()
			local channels = message.guild.voiceChannels:toArray("position", function (channel) return channel.name:lower() == id end)
			if #channels == 0 then
				logger:log(4, "Bad "..command.." input")
				message:reply("Couldn't find a channel by name")
				return
			elseif #channels == 1 then
				id = channels[1].id
			else
				logger:log(4, "Ambiguous "..command.." input")
				actions[commands.id](message, id)
				return
			end
		end
		
		if not id or not message.guild.voiceChannels:find(function(voiceChannel) if id == voiceChannel.id then return true end end) then 
			logger:log(4, "Bad "..command.." input")
			message:reply("You have to specify a valid voice channel id or name\nExample: `@Voice Manager "..command.." 123456789123456780`")
			return
		end
		
		return id
	end,

	[commands.register] = function (message)
		local id = actions.regFilter(message, commands.register)
		if not id then return end
		
		servers[message.guild.id][id] = 0
		servers:saveServers()
		message.channel:send("Channel `"..client:getChannel(id).name.."` is now registered as a lobby")
		logger:log(4, "Registered "..id.." successfully")
		stats.lobbies = stats.lobbies + 1
	end,

	[commands.unregister] = function (message)
		local id = actions.regFilter(message, commands.unregister)
		if not id then return end
		
		servers[message.guild.id][id] = nil
		servers:saveServers()
		message.channel:send("Channel `"..client:getChannel(id).name.."` was unregistered")
		logger:log(4, "Unregistered "..message.channel.id.." successfully")
		stats.lobbies = stats.lobbies - 1
	end,
	
	[commands.id] = function (message, target)
		if not message.member:hasPermission(permission.manageChannels) then
			logger:log(4, "Mention in vain")
			message:reply(message.author.mentionString.. ', you need to have "Manage Channels" permission to do this')
			return
		end
	
		logger:log(4, "ID action invoked")
		local msg = target and "There are several channels with this name\n" or ""
		target = target or message.content:match(commands.id.."%s+(.-)$")
		local categories = message.guild.categories:toArray("position")
		local channels = message.guild.voiceChannels:toArray("position", function (channel) return not channel.category end)
		
		if target then
			target = target:lower()
			for _, channel in ipairs(channels) do
				if channel.name == target then
					msg = msg.."`"..channel.name.."` -> `"..channel.id.."`\n"
				end
			end
			for _, category in ipairs(categories) do
				for _, channel in ipairs(category.voiceChannels:toArray("position")) do
					if category.name:lower() == target or channel.name:lower() == target then
						msg = msg.."`"..channel.name.."` in `"..channel.category.name.."` -> `"..channel.id.."`\n"
					end
				end
			end
		else
			for _, channel in ipairs(channels) do
				msg = msg.."`"..channel.name.."` -> `"..channel.id.."`\n"
			end
			for _, category in ipairs(categories) do
				for _, channel in ipairs(category.voiceChannels:toArray("position")) do
					msg = msg.."`"..channel.name.."` in `"..channel.category.name.."` -> `"..channel.id.."`\n"
				end
			end
		end
		
		if #msg > 2000 then
			msg = msg:sub(1,1800).."\nPhew, I can't display more than that! Try to narrow down the list with the channel name, like ```@Voice Manager id channel_name```Also, consider turning the developer mode on, it's quite useful!"
		end
		message:reply(msg)
	end,
	
	[commands.list] = function (message)
		logger:log(4, "List action invoked")
		local str = "Registered lobbies on this server:\n"
		local channels = 0
		if not servers[message.guild.id] then servers[message.guild.id] = {} end
		for channelID, type in pairs(servers[message.guild.id]) do
			if pingChannel(message.guild.id, channelID) then
				if type == 0 then
					str = str.."`"..channelID.."` -> `"..client:getChannel(channelID).name.."`\n"
				else
					channels = channels + 1
				end
			end
		end
		message.channel:send(str.."New channels on this server: **"..channels.."**")
	end,
	
	[commands.shutdown] = function (message)
		if message.author.id ~= "188731184501620736" then return end
		logger:log(4, "Shutdown action invoked")
		client:setGame({name = "the maintenance", type = 3})
		message:reply("Shutting down gracefully")
		local status, msg = pcall(function()
			clock:stop()
			client:stop()
		end)
		logger:log(3, (status and "Shutdown successfull, saving data..." or ("Couldn't shutdown gracefully, "..msg)))
		servers:saveServers()
		servers:saveChannels()
		process:exit()
	end,
	
	[commands.stats] = function (message)
		local t = os.clock()
		message.channel:broadcastTyping()
		t = os.clock() - t
		logger:log(4, "Stats action invoked")
		message:reply("I'm currently on **`"..
			stats.servers..(stats.servers == 1 and "`** server serving **`" or "`** servers serving **`")..
			stats.lobbies..(stats.lobbies == 1 and "`** lobby\nThere " or "`** lobbies\nThere ")..
			(stats.channels == 1 and "is **`" or "are **`")..stats.channels..(stats.channels == 1 and "`** new channel with " or "`** new channels with **`")..
			stats.people..(stats.people == 1 and "`** person" or "`** people").."\nPing is **`"..t.."ms`**")
	end,
	
	[commands.support] = function (message)
		message:reply("https://discord.gg/tqj6jvT")
	end
}

client:on('messageCreate', function (message)
	if message.channel.type ~= channelType.text and not message.author.bot then
		message:reply("This bot can only be used in servers. Mention the bot within the server to get the help message.")
		return
	end
	
	if not message.mentionedUsers:find(function(user) return user == client.user end) or message.author.bot then 
		return 
	end

	logger:log(4, "Message received, processing...")
	if not servers[message.guild.id] then servers[message.guild.id] = {} end
	if not message.guild.me:getPermissions(message.channel):has(permission.manageChannels, permission.moveMembers) then
		message:reply('This bot needs "Manage Channels" and "Move Members" permissions to function!')
	end
	
	local command = message.content:match("%s(%a+)")
	if not command then command = commands.help end
	local res, msg = pcall(function() if actions[command] then actions[command](message) end end)
	if not res then logger:log(1, "Couldn't process the message, "..msg) end
end)

client:on('guildCreate', function (guild)
	servers[guild.id] = {}
	client:getChannel("676432067566895111"):send(guild.name.." added me!\n")
	servers:saveServers()
end)

client:on('guildDelete', function (guild)
	servers[guild.id] = nil
	client:getChannel("676432067566895111"):send(guild.name.." removed me!\n")
	servers:saveServers()
end)

client:on('voiceChannelJoin', function (member, channel)
	if not servers[channel.guild.id] then servers[channel.guild.id] = {}; return end
	if servers[channel.guild.id][channel.id] == 0 then
		logger:log(4, member.user.id.." joined lobby "..channel.id)
		local category = channel.category or channel.guild
		local newChannel = category:createVoiceChannel((member.nickname or member.user.name).."'s channel")
		member:setVoiceChannel(newChannel.id)
		logger:log(4, "Created new channel "..newChannel.id)
		servers[channel.guild.id][newChannel.id] = 1
		newChannel:setUserLimit(channel.userLimit)
		if channel.guild.me:getPermissions(channel):has(permission.manageRoles, permission.manageChannels, permission.muteMembers, permission.deafenMembers, permission.moveMembers) then
			newChannel:getPermissionOverwriteFor(member):allowPermissions(permission.manageChannels, permission.muteMembers, permission.deafenMembers, permission.moveMembers)
		end
	end
end)

client:on('voiceChannelLeave', function (member, channel)
	if not channel then return end
	if not servers[channel.guild.id] then servers[channel.guild.id] = {}; return end
	if servers[channel.guild.id][channel.id] == 1 and #channel.connectedMembers == 0 then
		servers[channel.guild.id][channel.id] = nil
		channel:delete()
		logger:log(4, "Deleted "..channel.id)
	end
end)

client:on('channelDelete', function (channel)
	pingChannel(channel.guild.id, channel.id)
end)

client:on('ready', function()
	servers:load()
	servers:saveServers()
	servers:saveChannels()
	clock:start()
	client:getChannel("676432067566895111"):send("I'm listening")
end)

clock:on('min', function()
	servers:saveChannels()
	local people, channels = 0, 0
	for serverID, server in pairs(servers) do
		for channelID, type in pairs(server) do
			if pingChannel(serverID, channelID) then
				if type == 1 then
					local channel = client:getChannel(channelID)
					if #channel.connectedMembers ~= 0 then
						channels = channels + 1
						people = people + #channel.connectedMembers
					else
						channel:delete()
						server[channelID] = nil
					end
				end
			end
		end
	end
	client:setGame({name = people == 0 and "the sound of silence" or (people..(people == 1 and " person" or " people").." on "..channels..(channels == 1 and " channel" or " channels")), type = 2})
	stats.channels = channels
	stats.people = people
	client:getChannel("676791988518912020"):getLastMessage():delete()
	client:getChannel("676791988518912020"):send("beep boop beep")
	statservers()
end)

client:on('shutdown', actions[commands.shutdown])

local sd = function () client:emit("shutdown") end -- ensures graceful shutdown

process.stdin:on('data', function (data)
	if data:match("shutdown") then sd() end
end)

process:on('sigterm', sd)
process:on('sigint', sd)

client:run('Bot '..config.token)