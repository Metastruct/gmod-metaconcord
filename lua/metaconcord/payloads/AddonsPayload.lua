-- engine.GetAddons() is empty on our servers, so this only tells metaconcord the
-- server just booted and its addon list should be pulled over SSH (~/gserv/repos).
-- Sent once per server lifetime: payloads are re-created on every socket
-- reconnect, so the flag lives on the global metaconcord table.
local Payload = include("./Payload.lua")
local AddonsPayload = table.Copy(Payload)
AddonsPayload.__index = AddonsPayload
AddonsPayload.super = Payload
AddonsPayload.name = "AddonsPayload"

function AddonsPayload:__call(socket)
	self.super.__call(self, socket)

	self.onConnected = function()
		if metaconcord.addonsPulled then return end
		metaconcord.addonsPulled = true
		timer.Simple(10, function() -- after StatusPayload's initial info
			self:write({ pull = true })
		end)
	end

	return self
end

return setmetatable({}, AddonsPayload)
