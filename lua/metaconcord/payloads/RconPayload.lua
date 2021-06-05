local Payload = include("./Payload.lua")
local RconPayload = table.Copy(Payload)
RconPayload.__index = RconPayload
RconPayload.super = Payload
RconPayload.name = "RconPayload"

function RconPayload:__call(socket)
	self.super.__call(self, socket)
	return self
end

function RconPayload:__gc()
end

local IDENTIFIER = "metaconcord"
function RconPayload:handle(data)
	if not data.isLua then
		game.ConsoleCommand(data.command .. "\n")
	else
		if not luadev then return end

		local runnerLog = ("[ %s: %s ]"):format(IDENTIFIER, data.runner)
		if data.realm == "sv" then
			luadev.RunOnServer(data.code, runnerLog)
		elseif data.realm == "sh" then
			luadev.RunOnShared(data.code, runnerLog)
		elseif data.realm == "cl" then
			luadev.RunOnClients(data.code, runnerLog)
		else
			print(("Unknown realm '%s' for metaconcord lua payload by %s"):format(data.realm, data.runner))
		end
	end
end

return setmetatable({}, RconPayload)