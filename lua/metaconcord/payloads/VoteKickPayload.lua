local Payload = include("./Payload.lua")
local VoteKickPayload = table.Copy(Payload)
VoteKickPayload.__index = VoteKickPayload
VoteKickPayload.super = Payload
VoteKickPayload.name = "VoteKickPayload"

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

function VoteKickPayload:__call(socket)
	self.super.__call(self, socket)

	hook.Add("OnPlayerVoteKickRequested", self, function(_, offenderSteamID, reporterSteamID, reason)
		self:write({
			offender = {
			nick = getPlayerNick(offenderSteamID),
			steamID = offenderSteamID,
		},
			reporter = {
			nick = getPlayerNick(reporterSteamID),
			steamID = reporterSteamID,
		},
			reason = reason
		})
	end)

	hook.Add("OnPlayerVoteKicked", self, function(_, offenderSteamID, reporterSteamID, reason)
		self:write({
			offender = {
				nick = getPlayerNick(offenderSteamID),
				steamID = offenderSteamID,
			},
			reporter = {
				nick = getPlayerNick(reporterSteamID),
				steamID = reporterSteamID,
			},
			reason = reason,
			result = {
				success = true
			}
		})
	end)

	hook.Add("OnPlayerVoteKickFailed", self, function(_, offenderSteamID, reporterSteamID, reason, why)
		self:write({
			offender = {
				nick = getPlayerNick(offenderSteamID),
				steamID = offenderSteamID,
			},
			reporter = {
				nick = getPlayerNick(reporterSteamID),
				steamID = reporterSteamID,
			},
			reason = reason,
			result = {
				success = false,
				reason = why
			}
		})
	end)

	return self
end

function VoteKickPayload:__gc()
	hook.Remove("OnPlayerVoteKickRequested", self)
	hook.Remove("OnPlayerVoteKicked", self)
	hook.Remove("OnPlayerVoteKickFailed", self)
end

return setmetatable({}, VoteKickPayload)