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
    if not self.socket then return ErrorNoHalt("no socket object\n") end
    if not self.socket:isConnected() then return ErrorNoHalt("socket not open\n") end
    if type(payload) ~= "table" then return ErrorNoHalt("invalid payload, table needed\n") end
    payload.name = self.name

    self.socket:write(util.TableToJSON({
        payload = payload
    }))

    return true
end

function Payload:handle(payload)
    return true
end

return Payload