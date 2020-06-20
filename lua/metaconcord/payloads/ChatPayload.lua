local Payload = include("./Payload.lua")
local ChatPayload = table.Copy(Payload)
ChatPayload.__index = ChatPayload
ChatPayload.super = Payload
ChatPayload.name = "ChatPayload"

function ChatPayload:__call(socket)
    self.super.__call(self, socket)

    hook.Add("PlayerSay", self, function(_, ply, message, isTeamChat, isLocalChat)
        if ply.IsBanned and ply:IsBanned() then return end
        message = message:gsub("<.-=.->", "")
        message = message:gsub("/me%s+", "")
        message = message:gsub("<stop>", "")

        self:write({
            message = {
                player = {
                    name = ply:Nick(),
                    steamId64 = ply:SteamID64()
                },
                content = message
            }
        })
    end)

    return self
end

function ChatPayload:__gc()
    hook.Remove("PlayerSay", self)
end

function ChatPayload:handle(data)
    PrintTable(data)
end

return setmetatable({}, ChatPayload)