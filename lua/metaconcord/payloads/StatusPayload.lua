local Payload = include("./Payload.lua")
local StatusPayload = table.Copy(Payload)
StatusPayload.__index = StatusPayload
StatusPayload.super = Payload
StatusPayload.name = "StatusPayload"

function StatusPayload:__call(socket)
    self.super.__call(self, socket)
    local UndecorateNick = UndecorateNick or function(...) return ... end

	local function updateStatus()
		local players = player.GetAll()
		local list = {}
		for _, ply in next, players do
			list[#list + 1] = UndecorateNick(ply:Nick())
		end

		local wmap = cookie.GetString("wmap", "")
		local wsName, wsId = wmap:match("(.-)|(.+)")
		local map = game.GetMap()
		local workshopMap
		if map == wsname then
			workshopMap = {
				name = wsname,
				id = wsid
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

	self.onConnected = updateStatus
	timer.Create("metaconcordStatusPayload", 30, 0, updateStatus)

    return self
end

function StatusPayload:__gc()
    timer.Remove("metaconcordStatusPayload")
end

return setmetatable({}, StatusPayload)