--[[
luvit redefines lua's require
"packageName" must be in luvit's local "deps" folder
"./filename.lua" may be anywhere, just make sure the path is fine

require "discordia"								table: 0x02563805ddf8
require "../deps/discordia/init.lua"			table: 0x02563805ddf8
require "D:\\lua\\deps\\discordia\\init.lua"	table: 0x025638037e88 absolute path is a bitch i guess :/
]]
local discordia = require "discordia"
-- 

local client = discordia.Client()
local clock = discordia.Clock()
-- those instances will be used everywhere, they will be stored in discordia.storage for easy access
discordia.storage = {client = client, clock = clock, logger = discordia.Logger(4, '%F %T')}

--[[ storage for access tokens
return {
	token = "your_discord_bot_token",
	tokens = {
		["discordbotlist.com"] = "token",
		["top.gg"] = "token",
		...
	}
}
]]
local config = require "./config.lua"

--[[ 
holds all the event methods and logic
notice that metametod call of the table produces two values
]]
local events = require "./events.lua"

-- Other events are registered in "ready"
client:on(events("ready"))

-- bot starts working here
client:run('Bot '..config.token)