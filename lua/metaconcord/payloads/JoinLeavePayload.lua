local Payload = include("./Payload.lua")
local JoinLeavePayload = table.Copy(Payload)
JoinLeavePayload.__index = JoinLeavePayload
JoinLeavePayload.super = Payload
JoinLeavePayload.name = "JoinLeavePayload"

function JoinLeavePayload:__call(socket)
	self.super.__call(self, socket)

	_G._dont_draw = _G._dont_draw or {}
	local _dont_draw = _G._dont_draw

	hook.Add("PlayerLeave", self, function(_, nick, userId, steamId, reason)
		if _dont_draw[steamId] then return end

		local ply = Player(userId)
		if (IsValid(ply) and ply:IsBot()) or not steamId:match("STEAM_0:%d+:%d+") then return end

		self:write({
			player = {
				nick = IsValid(ply) and ply:Nick() or nick,
				steamId64 = util.SteamIDTo64(steamId)
			},
			reason = reason
		})
	end)

	hook.Add("PlayerInitialSpawn", self, function(_, ply)
		if ply:IsBot() then return end
		if ply.ConnectedThisMap and not ply:ConnectedThisMap() then return end -- only display initial connects
		if _dont_draw[ply:SteamID()] then return end

		self:write({
			player = {
				nick = ply:Nick(),
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
