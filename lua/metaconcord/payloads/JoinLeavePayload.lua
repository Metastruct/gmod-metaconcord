local Payload = include("./Payload.lua")
local JoinLeavePayload = table.Copy(Payload)
JoinLeavePayload.__index = JoinLeavePayload
JoinLeavePayload.super = Payload
JoinLeavePayload.name = "JoinLeavePayload"

function JoinLeavePayload:__call(socket)
    self.super.__call(self, socket)
    local UndecorateNick = UndecorateNick or function(...) return ... end

	hook.Add("PlayerLeave", self, function(_, name, _, steamId, reason)
		if not steamId then return end

		self:write({
			player = {
				name = UndecorateNick(name),
				steamId64 = util.SteamIDTo64(steamId)
			},
			reason = reason
		})

		local payload = metaconcord.getPayload("StatusPayload")
		if payload then timer.Simple(0, function() payload:updateStatus() end end
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

		local payload = metaconcord.getPayload("StatusPayload")
		if payload then timer.Simple(0, function() payload:updateStatus() end end
	end)

    return self
end

function JoinLeavePayload:__gc()
	hook.Remove("PlayerLeave", self)
	hook.Remove("PlayerInitialSpawn", self)
end

return setmetatable({}, JoinLeavePayload)