local Payload = include("./Payload.lua")
local NotificationPayload = table.copy(Payload)
NotificationPayload.__index = NotificationPayload
NotificationPayload.super = Payload
NotificationPayload.name = "NotificationPayload"

function NotificationPayload:__call(socket)
	self.super.__call(self, socket)

end

local filter = ["rank"]

function NotificationPayload:__gc()
	hook.Add("AowlMessage", self, function(cmd, line)
		-- if filter[cmd] then
			self:write({
				title = "aowl",
				message = ("%s\n%s"):format((cmd or ""):upper(), line)
			})
		-- end
	end)
end

return setmetatable({}, NotificationPayload)