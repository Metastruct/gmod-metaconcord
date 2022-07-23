local Payload = include("./Payload.lua")
local BanAppealPayload = table.Copy(Payload)
BanAppealPayload.__index = BanAppealPayload
BanAppealPayload.super = Payload
BanAppealPayload.name = "BanAppealPayload"

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

function BanAppealPayload:__call(socket)
  self.super.__call(self, socket)

  hook.Add("OnPlayerBanAppealed", self, function(_, steamId, bannerSteamId, banreason, unbanTime, appeal)
    self:write({
      player = {
        nick = getPlayerNick(bannerSteamId),
        steamId = bannerSteamId,
      },
      banned = {
        nick = getPlayerNick(steamId),
        steamId = steamId,
      },
      banReason = banreason,
      appeal = appeal
      unbanTime = tostring(unbanTime),
    })
  end)

  return self
end

function BanAppealPayload:__gc()
  hook.Remove("OnPlayerBanAppealed", self)
end

return setmetatable({}, BanAppealPayload)