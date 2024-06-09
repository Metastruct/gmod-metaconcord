local Payload = include("./Payload.lua")
local StatusPayload = table.Copy(Payload)
StatusPayload.__index = StatusPayload
StatusPayload.super = Payload
StatusPayload.name = "StatusPayload"

local function hookAndListen(name, ...)
	gameevent.Listen(name)
	hook.Add(name, ...)
end

local connectingPlayers = {}
local isReady = false

function StatusPayload:__call(socket)
	self.super.__call(self, socket)

	_G._dont_draw = _G._dont_draw or {}
	local _dont_draw = _G._dont_draw

	-- stuff that we only send once
	function self:sendInfo()
		local wmap = cookie.GetString("wmap", "")
		local wsName, wsId = wmap:match("(.-)|(.+)")
		local map = game.GetMap()
		local workshopMap

		if wsName and #wsName > 0 then
			workshopMap = {
				name = wsName,
				id = wsId
			}
		else
			local wsid = file.Read("maps/" .. map .. ".bsp.wsid", true)
			if wsid then
				workshopMap = {
					name = map,
					id = wsid
				}
			end
		end

		local supportedGamemodes = gm_request and gm_request:GetSupportedGamemodes() or { [GAMEMODE.FolderName] = true }
		local gamemodeList = {}
		for name, _ in pairs(supportedGamemodes) do
			gamemodeList[#gamemodeList + 1] = name
		end

		self:write {
			defcon = defcon and defcon.Level or 5,
			hostname = GetHostName(),
			mapName = map,
			workshopMap = workshopMap,
			serverUptime = SysTime(),
			mapUptime = CurTime(),
			gamemode = {
				folderName = GAMEMODE.FolderName,
				name = GAMEMODE.Name,
			},
			gamemodes = gamemodeList
		}

		isReady = true
	end

	--- player status info
	function self:updatePlayerStatus()
		if not isReady then return end

		local list = {}

		for _, ply in player.Iterator() do
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

		for _, data in next, connectingPlayers do
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

		self:write {
			players = list
		}
	end

	self.onConnected = function()
		timer.Simple(5, function() -- discord might not be connected yet
			self:sendInfo()
			self:updatePlayerStatus()
		end)
	end

	local function add(self, data)
		if not isReady then return end
		connectingPlayers[data.userid] = data

		timer.Simple(0, function()
			self:updatePlayerStatus()
		end)
	end

	local function remove(self, data)
		if not isReady or not connectingPlayers[data.userid] and not data.reason then return end
		connectingPlayers[data.userid] = nil

		timer.Simple(0, function()
			self:updatePlayerStatus()
		end)
	end

	hookAndListen("player_connect", self, add)
	hookAndListen("player_spawn", self, remove)
	hookAndListen("player_disconnect", self, remove)

	hook.Add("AowlCountdown", self, function(_, typ, time, text)
		if not isReady then return end
		self:write {
			countdown = {
				typ = typ,
				time = time,
				text = text
			}
		}
	end)

	hook.Add("DefconLevelChange", self, function(_, level)
		if not isReady then return end
		self:write {
			defcon = tonumber(level)
		}
	end)

	return self
end

function StatusPayload:__gc()
	hook.Remove("player_connect", self)
	hook.Remove("player_spawn", self)
	hook.Remove("player_disconnect", self)
	hook.Remove("AowlCountdown", self)
	hook.Remove("DefconLevelChange", self)
end

return setmetatable({}, StatusPayload)
