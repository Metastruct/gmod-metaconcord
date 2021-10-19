util.AddNetworkString("metaconcordChatPayload")
local Payload = include("../Payload.lua")
local ChatPayload = table.Copy(Payload)
local blurple = 7506394
ChatPayload.__index = ChatPayload
ChatPayload.super = Payload
ChatPayload.name = "ChatPayload"

function ChatPayload:__call(socket)
	self.super.__call(self, socket)
	local UndecorateNick = UndecorateNick or function(...) return ... end

	hook.Add("PlayerSay", self, function(_, ply, message, isTeamChat, isLocalChat)
		if isLocalChat then return end
		if ply.IsBanned and ply:IsBanned() then return end
		message = message:gsub("<.-=.->", "")
		message = message:gsub("/me%s+", "")
		message = message:gsub("<stop>", "")
		message = message:Trim()
		if message == "" then return end

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

function ChatPayload:handle(data)
	local ret = hook.Run("DiscordSay", {
			id = data.user.id
			name = data.user.nick
			color = data.user.color
			avatar_url = data.user.avatar_url
		},
		data.content,
		data.msgID,
		data.replied_message,
		)

	if ret == false then return end

	ret = isstring(ret) and ret or data.content
	if ret == "" then return end

	net.Start("metaconcordChatPayload")
	net.WriteString(data.user.id)
	net.WriteString(data.user.nick)
	net.WriteInt(data.user.color, 25)
	net.WriteString(data.user.avatar_url)
	net.WriteString(ret)
	net.WriteString(data.msgID)
	net.WriteString(data.replied_message and data.replied_message.content or "")
	net.WriteString(data.replied_message and data.replied_message.msgID or "")
	net.WriteBool(data.replied_message and data.replied_message.ingame)
	net.Broadcast()
end

return setmetatable({}, ChatPayload)