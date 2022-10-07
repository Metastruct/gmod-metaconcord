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

	hook.Add("DiscordNotification", self, function(_, title, msg)
		self:write({
			title = title,
			message = msg,
		})
	end)
end

function NotificationPayload:__gc()
	hook.Remove("AowlMessage", self)
	hook.Remove("DiscordNotification", self)
end

function DiscordAdminNotification(title, msg)
	hook.Run("DiscordNotification", title, msg)
end

return setmetatable({}, NotificationPayload)