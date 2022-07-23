local Payload = include("./Payload.lua")
local UnbanPayload = table.Copy(Payload)
UnbanPayload.__index = UnbanPayload
UnbanPayload.super = Payload
UnbanPayload.name = "UnbanPayload"

local function getPlayerNick(ply)
  if type(ply) == "string" and ply:match("^STEAM_0:%d:%d*$") then
    local _ply = player.GetBySteamID(ply)

    if IsValid(_ply) then
      ply = _ply
    end
  end

  if IsValid(ply) then
    return ply:Nick()
  elseif playerseen then
    local seenEntry = playerseen.GetPlayerBySteamID(ply)
    if seenEntry and seenEntry[1] then return seenEntry[1].nick or ply end
  end

  return "???"
end

function UnbanPayload:__call(socket)
  self.super.__call(self, socket)

  hook.Add("OnPlayerUnbanned", self, function(_, steamId, unbannerSteamId, unbanreason, unbanTime, banreason)
    self:write({
      player = {
        nick = getPlayerNick(unbannerSteamId),
        steamId = unbannerSteamId,
      },
      banned = {
        nick = getPlayerNick(steamId),
        steamId = steamId,
      },
      banReason = banreason,
      unbanReason = unbanreason
      unbanTime = tostring(unbanTime),
    })
  end)

  return self
end

function UnbanPayload:__gc()
  hook.Remove("OnPlayerUnbanned", self)
end

return setmetatable({}, UnbanPayload)