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

	hook.Add("DiscordNotification", self, function(_, msg)
		self:write({
			title = "aowl",
			message = ("%s\n%s"):format((tostring(cmd) or ""):upper(), line)
		})
	end)
end

function NotificationPayload:__gc()
	hook.Remove("AowlMessage", self)
end

function DiscordAdminNotification(msg)
	hook.Run("DiscordNotification", msg)
end

return setmetatable({}, NotificationPayload)