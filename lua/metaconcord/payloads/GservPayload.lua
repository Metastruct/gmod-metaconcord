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

	-- one run at a time, matching the single gserv button the site allows
	local running = false

	function self:handle(data)
		local identifier = data.identifier

		if running then
			self:write({ identifier = identifier, done = true, error = "a gserv run is already in progress" })
			return true
		end

		if not metaconcord.native then
			self:write({ identifier = identifier, done = true, error = "native module missing" })
			return true
		end

		running = true
		metaconcord.native.Gserv(data.command or "", function(err, event)
			if err then
				running = false
				if self:IsValid() then
					self:write({ identifier = identifier, done = true, error = tostring(err) })
				end
				return
			end

			if event.kind == "exit" then
				running = false
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
