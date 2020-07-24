local Payload = include("./Payload.lua")
local BanPayload = table.Copy(Payload)
BanPayload.__index = BanPayload
BanPayload.super = Payload
BanPayload.name = "BanPayload"

function BanPayload:__call(socket)
	self.super.__call(self, socket)

	hook.Add("OnPlayerBanned", self, function(_, bannedId, bannerId, banReason, unbanTime)
		local banned = player.GetBySteamID(bannedId)
		local banner = player.GetBySteamID(bannerId)

		local UndecorateNick = UndecorateNick or function(...) return ... end
		local bannedInfo = IsValid(banned) and ("%s (%s)"):format(UndecorateNick(banned:Nick()), bannedId) or bannedId
		local bannerInfo = IsValid(banner) and ("%s (%s)"):format(UndecorateNick(banner:Nick()), bannedId) or bannerId

		self:write({
			ban = {
				banned = bannedInfo,
				banner = bannerInfo,
				reason = banReason,
				unbanTime = tostring(unbanTime),
			}
		})
	end)

	return self
end

function BanPayload:__gc()
	hook.Remove("OnPlayerBanned", self)
end

return setmetatable({}, BanPayload)