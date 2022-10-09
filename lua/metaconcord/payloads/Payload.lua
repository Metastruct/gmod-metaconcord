local Payload = {}
Payload.__index = Payload
Payload.super = Payload
Payload.socket = nil
Payload.name = nil

function Payload:IsValid()
	return self.socket and self.socket:isConnected()
end

function Payload:__tostring()
	return ("metaconcord.Payload [%s]"):format(self.name)
end

function Payload:__call(socket)
	self.socket = socket

	return self
end

function Payload:__gc()
end

function Payload:write(payload)
	if not self.socket then return metaconcord.print("error", self.name, "no socket object") end
	if not self.socket:isConnected() then return metaconcord.print("error", self.name, "socket not open") end
	if type(payload) ~= "table" then return metaconcord.print("error", self.name, "invalid payload, table needed") end

	self.socket:write(util.TableToJSON({
		name = self.name,
		data = payload
	}))

	return true
end

function Payload:handle(payload)
	return true
end

return Payload