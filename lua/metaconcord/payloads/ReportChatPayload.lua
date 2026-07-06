local Payload = include("./Payload.lua")
local ReportChatPayload = table.Copy(Payload)
ReportChatPayload.__index = ReportChatPayload
ReportChatPayload.super = Payload
ReportChatPayload.name = "ReportChatPayload"

util.AddNetworkString("metaconcord_report_chat_msg")
util.AddNetworkString("metaconcord_report_chat_response")

local activeReports = {}

function ReportChatPayload:__call(socket)
	self.super.__call(self, socket)

	hook.Add("PlayerAuthed", self, function(ply, steamid, uniqueid)
		local sid64 = util.SteamID64(tostring(steamid))
		if activeReports[sid64] then
			ply._active_report = activeReports[sid64]
		end
	end)

	hook.Add("AowlAdminReport", self, function(_, senderSteamID, _, reportedSid)
		activeReports[util.SteamIDTo64(senderSteamID)] = reportedSid
	end)

	net.Receive("metaconcord_report_chat_msg", function(len, ply)
		if not IsValid(ply) or not ply:IsPlayer() then
			return
		end
		if not ply._active_report then
			local sid64 = ply:SteamID64()
			if activeReports[sid64] then
				ply._active_report = activeReports[sid64]
			else
				return
			end
		end

		local content = net.ReadString()
		content = string.Trim(content)
		if #content < 1 then
			return
		end
		if #content > 2000 then
			content = content:sub(1, 2000)
		end

		self:write({
			steamId64 = ply:SteamID64(),
			content = content,
		})
	end)

	function ReportChatPayload:handle(payload)
		if not payload or not payload.type then
			return
		end

		local reporterSteamId64 = tostring(payload.reporterSteamId64 or "")

		if payload.type == "resolve" and reporterSteamId64 ~= "" then
			activeReports[reporterSteamId64] = nil
		end

		if payload.type == "queued" and (not payload.messages or #payload.messages == 0) then
			self:write({
				type = "info",
				content = "No queued messages found.",
				reporterSteamId64 = reporterSteamId64,
			})
			return
		end

		payload.reporterSteamId64 = reporterSteamId64

		local targetPly = player.GetBySteamID64(reporterSteamId64)

		net.Start("metaconcord_report_chat_response")
		net.WriteTable(payload)
		if IsValid(targetPly) then
			net.Send(targetPly)
		end
	end

	return self
end

function ReportChatPayload:__gc()
	hook.Remove("PlayerAuthed", self)
	hook.Remove("AowlAdminReport", self)
end

return setmetatable({}, ReportChatPayload)
