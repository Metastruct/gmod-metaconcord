local Payload = include("./Payload.lua")
local BanPayload = table.Copy(Payload)
BanPayload.__index = BanPayload
BanPayload.super = Payload
BanPayload.name = "BanPayload"

function BanPayload:__call(socket)
	self.super.__call(self, socket)

	local UndecorateNick = UndecorateNick or function(...) return ... end

	hook.Add("OnPlayerBanned", self, function(_, steamId, bannerSteamId, reason, unbanTime)
		local banned = player.GetBySteamID(steamId)
		local banner = player.GetBySteamID(bannerSteamId)

		self:write({
			player = {
				nick = IsValid(banner) and UndecorateNick(banner:Nick()),
				steamId = bannerSteamId,
			},
			banned = {
				nick = IsValid(banned) and UndecorateNick(banned:Nick()),
				steamId = steamId,
			},
			reason = reason,
			unbanTime = tostring(unbanTime),
		})
	end)

	return self
end

function BanPayload:__gc()
	hook.Remove("OnPlayerBanned", self)
end

return setmetatable({}, BanPayload)