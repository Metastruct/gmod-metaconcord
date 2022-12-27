local Payload = include("./Payload.lua")
local StatusPayload = table.Copy(Payload)
StatusPayload.__index = StatusPayload
StatusPayload.super = Payload
StatusPayload.name = "StatusPayload"

local function hookAndListen(name, ...)
	gameevent.Listen(name)
	hook.Add(name, ...)
end

local STATUS_CHECK_INTERVAL = 60 * 5
local DEFCON_CHECK_INTERVAL = 60 * 5

local connecting = {}

function StatusPayload:__call(socket)
	self.super.__call(self, socket)

	_G._dont_draw = _G._dont_draw or {}
	local _dont_draw = _G._dont_draw

	function self:updateStatus()
		local wmap = cookie.GetString("wmap", "")
		local wsName, wsId = wmap:match("(.-)|(.+)")
		local map = game.GetMap()
		local workshopMap

		if wsName and #wsName > 0 then
			workshopMap = {
				name = wsName,
				id = wsId
			}
		end
		self:write({
			defcon = defcon and defcon.Level or 5,
			hostname = GetHostName(),
			map = map,
			workshopMap = workshopMap,
			serverUptime = SysTime(),
			mapUptime = CurTime(),
			gamemode = {
				folderName = GAMEMODE.FolderName,
				name = GAMEMODE.Name,
			}
		})
	end

	function self:updatePlayerStatus()
		local players = player.GetAll()
		local list = {}

		for _, ply in next, players do
			if not ply:IsBot() and not _dont_draw[ply:SteamID()] then
				list[#list + 1] = {
					accountId = ply:AccountID(),
					avatar = ply.SteamCache and ply:SteamCache() and ply:SteamCache().avatarfull,
					ip = ply:IPAddress(),
					isAdmin = ply:IsAdmin(),
					isAfk = ply.IsAFK and ply:IsAFK() or false,
					isBanned = ply.IsBanned and ply:IsBanned() or false,
					nick = ply:Nick(),
					isLinux = ply:IsLinux(),
					isPirate = ply.IsPirate and ply:IsPirate() or false,
				}
			end
		end

		for _, data in next, connecting do
			if not _dont_draw[data.networkid] then
				list[#list + 1] = {
					accountId = util.AccountIDFromSteamID and util.AccountIDFromSteamID(data.networkid),
					ip = data.address,
					isAdmin = aowl and aowl.CheckUserGroupFromSteamID(data.networkid, "developers"),
					isBanned = banni and banni.dataexists(data.networkid) or false,
					nick = data.name .. " (joining)"
				}
			end
		end

		self:write({
			players = list
		})
	end

	self.onConnected = function()
			timer.Simple(5, function()
				self:updateStatus()
				self:updatePlayerStatus()
		end)
	end

	local function add(self, data)
		connecting[data.userid] = data

		timer.Simple(0, function()
			self:updatePlayerStatus()
		end)
	end

	local function remove(self, data)
		if not connecting[data.userid] and not data.reason then return end
		connecting[data.userid] = nil

		timer.Simple(0, function()
			self:updatePlayerStatus()
		end)
	end

	hookAndListen("player_connect", self, add)
	hookAndListen("player_spawn", self, remove)
	hookAndListen("player_disconnect", self, remove)

	hook.Add("AowlCountdown", self, function(_, typ, time, text)
		self:write{
			countdown = {
				typ = typ,
				time = time,
				text = text
			}
		}
	end)

	local lastDefconLevel = 5

	timer.Create(self.name .. "_defcon_check", DEFCON_CHECK_INTERVAL, 0, function()
		local level = defcon and defcon.Level or 5
		if lastDefconLevel ~= level then
			self:write{
				defcon = level
			}
			lastDefconLevel = level
		end
	end)

	timer.Create(self.name .. "_status_check", STATUS_CHECK_INTERVAL, 0, function()
		self:updateStatus()
	end)

	return self
end

function StatusPayload:__gc()
	hook.Remove("player_connect", self)
	hook.Remove("player_spawn", self)
	hook.Remove("player_disconnect", self)
	hook.Remove("AowlCountdown", self)
	timer.Remove(self.name .. "_defcon_check")
	timer.Remove(self.name .. "_status_check")
end

return setmetatable({}, StatusPayload)
