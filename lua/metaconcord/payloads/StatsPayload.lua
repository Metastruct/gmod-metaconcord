local Payload = include("./Payload.lua")
local StatsPayload = table.Copy(Payload)
StatsPayload.__index = StatsPayload
StatsPayload.super = Payload
StatsPayload.name = "StatsPayload"

-- matches the bridge's stats ring, which holds 10 minutes at this rate
local INTERVAL = 5
local STATS_TIMER = "metaconcord.Stats"

function StatsPayload:__call(socket)
	self.super.__call(self, socket)

	self.onConnected = function()
		if not metaconcord.native then
			metaconcord.print("error", self.name, "native module missing, no stats will be sent")
			return
		end

		-- the first sample has no baseline to rate against, so it is taken and
		-- thrown away here rather than sending a reading of zero
		metaconcord.native.Stats()

		timer.Create(STATS_TIMER, INTERVAL, 0, function()
			if not self:IsValid() then return end

			local sample, err = metaconcord.native.Stats()
			if not sample then
				metaconcord.print("error", self.name, tostring(err))
				return
			end

			sample.fps = math.floor(1 / FrameTime())
			sample.players = player.GetCount()
			sample.maxPlayers = game.MaxPlayers()

			self:write(sample)
		end)
	end

	return self
end

function StatsPayload:__gc()
	timer.Remove(STATS_TIMER)
end

return setmetatable({}, StatsPayload)
