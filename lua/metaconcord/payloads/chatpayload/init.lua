util.AddNetworkString("metaconcordChatPayload")
local Payload = include("../Payload.lua")
local ChatPayload = table.Copy(Payload)
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
	local ret = hook.Run("DiscordSay", data.message.user.name, data.message.content)
	if ret == false then return end

	ret = isstring(ret) and ret or data.message.content
	if ret == "" then return end

	net.Start("metaconcordChatPayload")
	net.WriteString(data.message.user.name)
	net.WriteInt(data.message.user.color, 25)
	net.WriteString(ret)
	net.Broadcast()
end

return setmetatable({}, ChatPayload)