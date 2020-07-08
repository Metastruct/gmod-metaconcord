local Payload = include("./Payload.lua")
local JoinLeavePayload = table.Copy(Payload)
JoinLeavePayload.__index = JoinLeavePayload
JoinLeavePayload.super = Payload
JoinLeavePayload.name = "JoinLeavePayload"

function JoinLeavePayload:__call(socket)
	self.super.__call(self, socket)
	local UndecorateNick = UndecorateNick or function(...) return ... end

	hook.Add("PlayerLeave", self, function(_, name, userId, steamId, reason)
		local ply = Player(userId)
		if (IsValid(ply) and ply:IsBot()) or not steamId:match("STEAM_0:%d+:%d+") then return end

		self:write({
			player = {
				name = UndecorateNick(IsValid(ply) and ply:Nick() or name),
				steamId64 = steamId
			},
			reason = reason
		})
	end)

	hook.Add("PlayerInitialSpawn", self, function(_, ply)
		if ply:IsBot() then return end

		self:write({
			player = {
				name = UndecorateNick(ply:Nick()),
				steamId64 = ply:SteamID64()
			},
			spawned = true
		})
	end)

	return self
end

function JoinLeavePayload:__gc()
	hook.Remove("PlayerLeave", self)
	hook.Remove("PlayerInitialSpawn", self)
end

return setmetatable({}, JoinLeavePayload)