util.AddNetworkString("metaconcordChatPayload")
local Payload = include("../Payload.lua")
local ChatPayload = table.Copy(Payload)
--local blurple = 7506394
ChatPayload.__index = ChatPayload
ChatPayload.super = Payload
ChatPayload.name = "ChatPayload"

function ChatPayload:__call(socket)
	self.super.__call(self, socket)
	local UndecorateNick = UndecorateNick or function(...) return ... end

	hook.Add("PlayerSay", self, function(_, ply, message, isTeamChat, isLocalChat)
		if isLocalChat then return end
		if ply.IsBanned and ply:IsBanned() then return end

		-- if it doesnt exist then markup doesnt exist so why bother anyway
		if ec_markup then
			message = ec_markup.GetText(message)
		end

		message = message:gsub("/me%s+", "")
		message = EasyChat and EasyChat.ExtendedStringTrim(message) or message:Trim()
		if #message == 0 then return end

		self:write({
			player = {
				nick = UndecorateNick(ply:Nick()),
				steamId64 = ply:SteamID64()
			},
			content = message
		})
	end)

	return self
end

function ChatPayload:__gc()
	hook.Remove("PlayerSay", self)
end

local msgc_native = _G._MsgC or _G.MsgC -- epoe compat
local COLOR_PRINT_CHAT_TIME = Color(0, 161, 255)
local COLOR_PRINT_CHAT_HEADER = Color(114, 137, 218)
local COLOR_PRINT_CHAT_NICK = Color(222, 222, 255)
local COLOR_PRINT_CHAT_MSG = Color(255, 255, 255)
local function print_chat_msg(nickname, msg)
	local print_args = {}

	table.insert(print_args, COLOR_PRINT_CHAT_TIME)
	table.insert(print_args, os.date("!%H:%M:%S "))

	table.insert(print_args, COLOR_PRINT_CHAT_HEADER)
	table.insert(print_args, "[DISCORD] ")

	table.insert(print_args, COLOR_PRINT_CHAT_NICK)
	table.insert(print_args, nickname)

	table.insert(print_args, COLOR_PRINT_CHAT_MSG)
	table.insert(print_args, (": %s\n"):format(msg))

	msgc_native(unpack(print_args))
end

function ChatPayload:handle(data)
	local ret = hook.Run("DiscordSay", {
			id = data.user.id,
			name = data.user.nick,
			color = data.user.color,
			avatar_url = data.user.avatar_url,
		},
		data.content,
		data.msgID,
		data.replied_message
	)

	if ret == false then return end

	ret = isstring(ret) and ret or data.content
	if ret == "" then return end

	print_chat_msg(data.user.nick, ret)

	net.Start("metaconcordChatPayload")
	net.WriteString(data.user.id)
	net.WriteString(data.user.nick)
	net.WriteInt(data.user.color, 25)
	net.WriteString(data.user.avatar_url)
	net.WriteString(ret)
	net.WriteString(data.msgID)
	net.WriteString(data.replied_message and data.replied_message.content or "")
	net.WriteString(data.replied_message and data.replied_message.msgID or "")
	net.WriteString(data.replied_message and data.replied_message.ingameName or "")
	net.Broadcast()
end

return setmetatable({}, ChatPayload)