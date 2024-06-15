local Payload = include("./Payload.lua")
local BanPayload = table.Copy(Payload)
BanPayload.__index = BanPayload
BanPayload.super = Payload
BanPayload.name = "BanPayload"

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

function BanPayload:__call(socket)
  self.super.__call(self, socket)

  hook.Add("OnPlayerBanned", self, function(_, steamId, bannerSteamId, reason, unbanTime, gamemode)
    self:write{
      player = {
        nick = getPlayerNick(bannerSteamId),
        steamId = bannerSteamId,
      },
      banned = {
        nick = getPlayerNick(steamId),
        steamId = steamId,
      },
      reason = reason,
      unbanTime = tostring(unbanTime),
      gamemode = gamemode
    }
  end)

  return self
end

function BanPayload:__gc()
  hook.Remove("OnPlayerBanned", self)
end

return setmetatable({}, BanPayload)