local Payload = include("./Payload.lua")
local AdminNotifyPayload = table.Copy(Payload)
AdminNotifyPayload.__index = AdminNotifyPayload
AdminNotifyPayload.super = Payload
AdminNotifyPayload.name = "AdminNotifyPayload"

function AdminNotifyPayload:__call(socket)
	self.super.__call(self, socket)

	hook.Add("AowlAdminReport", self, function(_, nick, steamId, reportedNick, reportedSteamId, message)
		self:write({
			player = {
				nick = nick,
				steamId = steamId,
			},
			reported = {
				nick = reportedNick,
				steamId = reportedSteamId,
			},
			message = message,
		})
	end)

	return self
end

function AdminNotifyPayload:__gc()
	hook.Remove("AowlAdminReport", self)
end

return setmetatable({}, AdminNotifyPayload)
