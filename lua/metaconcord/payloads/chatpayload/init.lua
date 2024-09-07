util.AddNetworkString("metaconcordChatPayload")
local Payload = include("../Payload.lua")
local ChatPayload = table.Copy(Payload)
--local blurple = 7506394
ChatPayload.__index = ChatPayload
ChatPayload.super = Payload
ChatPayload.name = "ChatPayload"

function ChatPayload:__call(socket)
	self.super.__call(self, socket)

	hook.Add("PlayerSay", self, function(_, ply, message, isTeamChat, isLocalChat)
		if isLocalChat or isTeamChat then return end
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
				nick = ply:Nick(),
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
	local id = data.user.id
	local username = data.user.username
	local nick = data.user.nick
	local color = data.user.color
	local avatar_url = data.user.avatar_url
	local content = data.content
	local msgID = data.msgID
	local replied_message = data.replied_message

	local name = nick ~= "" and nick or username

	local ret = hook.Run("DiscordSay", {
			id = id,
			username = username,
			name = name,
			color = color,
			avatar_url = avatar_url,
		},
		content,
		msgID,
		replied_message
	)

	if ret == false then return end

	local msg = isstring(ret) and ret or content
	if msg == "" then return end

	print_chat_msg(nick ~= "" and ("%s (%s)"):format(nick, username) or username, msg)

	local filter = CRecipientFiler()
	for _, ply in ipairs(player.GetAll()) do
		local should_network = hook.Run("PlayerCanSeeDiscordChat", msg, username, nick, ply)
		if should_network == false then continue end

		filter:AddPlayer(ply)
	end

	net.Start("metaconcordChatPayload")
	net.WriteString(id)
	net.WriteString(username)
	net.WriteString(nick)
	net.WriteInt(color, 25)
	net.WriteString(avatar_url)
	net.WriteString(msg)
	net.WriteString(msgID)
	net.WriteString(replied_message and replied_message.content or "")
	net.WriteString(replied_message and replied_message.msgID or "")
	net.WriteString(replied_message and replied_message.ingameName or "")
	net.Send(filter)
end

return setmetatable({}, ChatPayload)
