-- engine.GetAddons() is empty on our servers, so the addon list is read off
-- disk by the native module (~/gserv/repos) and sent whole on every connect,
-- the same way the minecraft mod reports its mods. metaconcord resolves what
-- the rows point at; this only reports what is on the box.
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
			if not self:IsValid() then return end

			-- without the module there is no list to send; metaconcord keeps
			-- whatever it stored last rather than being told the server has none
			if not metaconcord.native then
				self:write({ games = mountedGames() })
				return
			end

			metaconcord.native.Repos(function(err, rows)
				if not self:IsValid() then return end

				if err then
					metaconcord.print("error", self.name, tostring(err))
					self:write({ games = mountedGames() })
					return
				end

				self:write({
					games = mountedGames(),
					repos = #rows > 0 and rows or nil,
				})
			end)
		end)
	end

	return self
end

return setmetatable({}, AddonsPayload)
