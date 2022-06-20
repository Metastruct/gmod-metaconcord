local Payload = include("./Payload.lua")
local NotificationPayload = table.Copy(Payload)
NotificationPayload.__index = NotificationPayload
NotificationPayload.super = Payload
NotificationPayload.name = "NotificationPayload"

local filter = {
	rank = true,
	tmpdev = true,
	psa = true
}

function NotificationPayload:__call(socket)
	self.super.__call(self, socket)
	hook.Add("AowlMessage", self, function(_, cmd, line)
		if filter[tostring(cmd):lower()] then
			self:write({
				title = "aowl",
				message = ("%s\n%s"):format((tostring(cmd) or ""):upper(), line)
			})
		end
	end)
	hook.Add("OnPlayerVoteKicked", self, function(kicked, caller, reason)
		-- how annoying, shit is gonna break if it's invalid but who cares
		local kicked = player.GetBySteamID(kicked)
		local caller = player.GetBySteamID(caller)
		self:write({
			title = "votekick",
			message = ("%s got votekicked by %s\nreason: ```%s```"):format(aowlNiceCallerName(kicked), aowlNiceCallerName(caller), reason)
		})
	end)
end

function NotificationPayload:__gc()
	hook.Remove("AowlMessage", self)
	hook.Remove("OnPlayerVoteKicked", self)
end

return setmetatable({}, NotificationPayload)