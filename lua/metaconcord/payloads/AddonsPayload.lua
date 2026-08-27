-- engine.GetAddons() is empty on our servers, so `pull` only tells metaconcord the
-- server just booted and its addon list should be pulled over SSH (~/gserv/repos).
-- Pulled once per server lifetime: payloads are re-created on every socket
-- reconnect, so the flag lives on the global metaconcord table. The mounted games
-- are sent on every connect instead, so a metaconcord restart gets them back
-- without waiting for the next server boot.
local Payload = include("./Payload.lua")
local AddonsPayload = table.Copy(Payload)
AddonsPayload.__index = AddonsPayload
AddonsPayload.super = Payload
AddonsPayload.name = "AddonsPayload"

local function mountedGames()
	if not engine.GetGames then return end

	local games = {}
	for _, game in ipairs(engine.GetGames()) do
		if game.mounted then
			-- depot is the steam app id, which the website links and pictures with
			games[#games + 1] = { folder = game.folder, title = game.title, depot = game.depot }
		end
	end

	-- an empty lua table encodes as {} rather than [], which is not a list
	return #games > 0 and games or nil
end

function AddonsPayload:__call(socket)
	self.super.__call(self, socket)

	self.onConnected = function()
		timer.Simple(10, function() -- after StatusPayload's initial info
			local pull = not metaconcord.addonsPulled
			metaconcord.addonsPulled = true
			self:write({ pull = pull, games = mountedGames() })
		end)
	end

	return self
end

return setmetatable({}, AddonsPayload)
