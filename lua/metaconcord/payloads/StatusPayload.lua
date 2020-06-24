local Payload = include("./Payload.lua")
local StatusPayload = table.Copy(Payload)
StatusPayload.__index = StatusPayload
StatusPayload.super = Payload
StatusPayload.name = "StatusPayload"

local function hookAndListen(name, ...)
	gameevent.Listen(name)
	hook.Add(name, ...)
end

local connecting = {}

function StatusPayload:__call(socket)
	self.super.__call(self, socket)
	local UndecorateNick = UndecorateNick or function(...) return ... end

	function self:updateStatus()
		local players = player.GetAll()
		local list = {}

		for _, ply in next, players do
			list[#list + 1] = UndecorateNick(ply:Nick())
		end

		for _, name in next, connecting do
			list[#list + 1] = name .. " (joining)"
		end

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
			status = {
				hostname = GetHostName(),
				players = list,
				map = map,
				workshopMap = workshopMap,
				uptime = SysTime() / 60 / 60
			}
		})
	end

	self.onConnected = self.updateStatus

	local function add(self, data)
		connecting[data.userid] = data.name

		timer.Simple(0, function()
			self:updateStatus()
		end)
	end

	local function remove(self, data)
		connecting[data.userid] = nil

		timer.Simple(0, function()
			self:updateStatus()
		end)
	end

	hookAndListen("player_connect", self, add)
	hookAndListen("player_spawn", self, remove)
	hookAndListen("player_disconnect", self, remove)

	return self
end

function StatusPayload:__gc()
	timer.Remove("metaconcordStatusPayload")
	hook.Remove("player_connect", self)
	hook.Remove("player_spawn", self)
	hook.Remove("player_disconnect", self)
end

return setmetatable({}, StatusPayload)