-- Runs gserv verbs on behalf of metaconcord, which used to reach the host over
-- ssh to do it. The verb whitelist lives in the native module, not here: lua is
-- shared with every other addon on the box, so a check up here would only be a
-- typo guard.
local Payload = include("./Payload.lua")
local GservPayload = table.Copy(Payload)
GservPayload.__index = GservPayload
GservPayload.super = Payload
GservPayload.name = "GservPayload"

function GservPayload:__call(socket)
	self.super.__call(self, socket)

	function self:handle(data)
		local identifier = data.identifier

		-- one run at a time is enforced in the module, since an in-game aowl
		-- command reaches gserv without passing through here
		if not metaconcord.native then
			self:write({ identifier = identifier, done = true, error = "native module missing" })
			return true
		end

		metaconcord.native.Gserv(data.command or "", function(err, event)
			if err then
				if self:IsValid() then
					self:write({ identifier = identifier, done = true, error = tostring(err) })
				end
				return
			end

			if event.kind == "exit" then
				if self:IsValid() then
					self:write({ identifier = identifier, done = true, code = event.code })
				end
				return
			end

			if self:IsValid() then
				self:write({ identifier = identifier, kind = event.kind, data = event.data })
			end
		end)

		return true
	end

	return self
end

return setmetatable({}, GservPayload)
