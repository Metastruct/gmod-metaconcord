local Payload = include("./Payload.lua")
local ErrorPayload = table.Copy(Payload)
ErrorPayload.__index = ErrorPayload
ErrorPayload.super = Payload
ErrorPayload.name = "ErrorPayload"

function ErrorPayload:handle(data)
	PrintTable(data)
end

return setmetatable({}, ErrorPayload)