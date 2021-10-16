local Payload = include("./Payload.lua")
local BanPayload = table.Copy(Payload)
BanPayload.__index = BanPayload
BanPayload.super = Payload
BanPayload.name = "BanPayload"
local UndecorateNick = UndecorateNick or function(...) return ... end

local function getPlayerNick(steamId)
  local ply

  if type(steamId) == "string" and steamId:match("^STEAM_0:1") then
    ply = player.GetBySteamID(steamId)

    if IsValid(ply) then
      return UndecorateNick(banner:Nick())
    elseif playerseen then
      local seenEntry = playerseen.GetPlayerBySteamID(ply)
      if seenEntry and seenEntry[1] then return seenEntry[1].nick or steamId end
    else
      return steamId
    end
  end

  return "???"
end

function BanPayload:__call(socket)
  self.super.__call(self, socket)

  hook.Add("OnPlayerBanned", self, function(_, steamId, bannerSteamId, reason, unbanTime)
    self:write({
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
    })
  end)

  return self
end

function BanPayload:__gc()
  hook.Remove("OnPlayerBanned", self)
end

return setmetatable({}, BanPayload)