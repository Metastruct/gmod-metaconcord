local Payload = include("./Payload.lua")
local NotificationPayload = table.Copy(Payload)
NotificationPayload.__index = NotificationPayload
NotificationPayload.super = Payload
NotificationPayload.name = "NotificationPayload"

local msgFilter = {
	rank = true,
	tmpdev = true,
	psa = true
}

local cmdFilter = {
	sfallow = true,
	rank = true
}

function NotificationPayload:__call(socket)
	self.super.__call(self, socket)
	hook.Add("AowlMessage", self, function(_, cmd, line)
		if msgFilter[tostring(cmd):lower()] then
			self:write({
				title = "aowl",
				message = ("%s\n%s"):format((tostring(cmd) or ""):upper(), line)
			})
		end
	end)

	hook.Add("AowlTargetCommand", self, function(_, ply, cmd, target, ...)
		if not cmdFilter[tostring(cmd):lower()] then return end
		local count = select("#", ...)
		local extra = ""
		for i = 1, count do
			extra = extra .. tostring(select(i, ...))
			if i ~= count then
				extra = extra .. ", "
			end
		end
		self:write({
			title = "aowl command",
			message = ("[%s (%s)] %s -> [%s (%s)]%s"):format(ply:Nick(), ply:SteamID64(), cmd, target:Nick(), target:SteamID64(), extra ~= "" and (" (%s)"):format(extra) or "")
		})
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
	hook.Remove("AowlTargetCommand", self)
	hook.Remove("DiscordNotification", self)
end

function DiscordAdminNotification(title, msg)
	hook.Run("DiscordNotification", title, msg)
end

return setmetatable({}, NotificationPayload)