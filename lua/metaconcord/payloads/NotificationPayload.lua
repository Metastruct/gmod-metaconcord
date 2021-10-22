local Payload = include("./Payload.lua")
local NotificationPayload = table.Copy(Payload)
NotificationPayload.__index = NotificationPayload
NotificationPayload.super = Payload
NotificationPayload.name = "NotificationPayload"

local filter = {"rank", "tmpdev", "PSA"}

function NotificationPayload:__call(socket)
	self.super.__call(self, socket)
	hook.Add("AowlMessage", self, function(cmd, line)
		if filter[cmd] then
			self:write({
				title = "aowl",
				message = ("%s\n%s"):format((tostring(cmd) or ""):upper(), line)
			})
		end
	end)
end

function NotificationPayload:__gc()
	hook.Remove("AowlMessage", self)
end

return setmetatable({}, NotificationPayload)