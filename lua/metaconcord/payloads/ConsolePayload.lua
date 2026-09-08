local Payload = include("./Payload.lua")
local ConsolePayload = table.Copy(Payload)
ConsolePayload.__index = ConsolePayload
ConsolePayload.super = Payload
ConsolePayload.name = "ConsolePayload"

-- the backlog a fresh subscriber gets, and the cap on live lines waiting for
-- the next flush. an unsubscribed server still fills the replay ring, so a
-- viewer opening the console sees what just happened.
local REPLAY_SIZE = 300
local QUEUE_SIZE = 1000
local FLUSH_INTERVAL = 0.25
local BATCH_SIZE = 200
local FLUSH_TIMER = "metaconcord.ConsoleFlush"
-- how long a chunk with no newline waits for the one that completes it
local PENDING_MAX_AGE = 1

-- SpewType_t: 0 message, 1 warning, 2 assert, 3 error, 4 log
local SPEW_LEVELS = { [0] = "INFO", [1] = "WARN", [2] = "ERROR", [3] = "ERROR", [4] = "INFO" }

function ConsolePayload:__call(socket)
	self.super.__call(self, socket)

	-- gm_enginespew is what turns engine console output into the EngineSpew
	-- hook; without it the stream is simply empty, so it must not be fatal
	if not pcall(require, "enginespew") then
		metaconcord.print("error", self.name, "gm_enginespew missing, console will be empty")
	end

	local replay = {}
	local queue = {}
	local subscribed = false
	-- anything we print while writing would land back in the ring, so every
	-- path that can print runs with this set
	local muted = false
	-- the tail of a chunk that had no newline yet, waiting to be completed
	local pending, pendingLevel, pendingColor, pendingSince = "", nil, nil, 0

	local function push(line)
		replay[#replay + 1] = line
		if #replay > REPLAY_SIZE then table.remove(replay, 1) end

		if not subscribed then return end

		queue[#queue + 1] = line
		if #queue > QUEUE_SIZE then table.remove(queue, 1) end
	end

	local function colorOf(r, g, b)
		-- white is the engine default, carrying it would just bloat every frame
		if r and (r ~= 255 or g ~= 255 or b ~= 255) then
			return ("%02x%02x%02x"):format(r, g, b)
		end
	end

	local function emit(text, level, color)
		-- the site joins lines with its own newline, so they are stored without
		-- one; a stray \r would otherwise move the cursor in the terminal
		push({ level = level, text = (text:gsub("\r$", "")), color = color })
	end

	local function flushPending()
		if pending == "" or SysTime() - pendingSince < PENDING_MAX_AGE then return end

		local text, level, color = pending, pendingLevel, pendingColor
		pending = ""
		emit(text, level, color)
	end

	hook.Add("EngineSpew", "metaconcord.ConsolePayload", function(logType, logMsg, logGroup, logLevel, r, g, b)
		if muted or not logMsg or logMsg == "" then return end

		local level = SPEW_LEVELS[logType] or "INFO"
		local color = colorOf(r, g, b)

		-- spew arrives as a stream of chunks, not lines: one chunk can hold
		-- several newlines or none at all, so whole lines are cut out here and
		-- the remainder waits for the chunk that finishes it
		local buffer = pending .. logMsg
		local start = 1
		pending = ""

		while true do
			local nl = buffer:find("\n", start, true)
			if not nl then break end

			emit(buffer:sub(start, nl - 1), level, color)
			start = nl + 1
		end

		if start <= #buffer then
			pending = buffer:sub(start)
			pendingLevel, pendingColor, pendingSince = level, color, SysTime()
		end
	end)

	-- takes up to BATCH_SIZE off the front of source and sends them. muted
	-- throughout, and reset even if the write throws, or capture dies silently.
	local function sendBatch(source, isReplay)
		if #source == 0 or not self:IsValid() then return false end

		local batch = {}
		for _ = 1, math.min(BATCH_SIZE, #source) do
			batch[#batch + 1] = table.remove(source, 1)
		end

		muted = true
		local ok, err = pcall(self.write, self, { lines = batch, replay = isReplay or nil })
		muted = false

		if not ok then metaconcord.print("error", self.name, tostring(err)) end

		return ok
	end

	self.onConnected = function()
		subscribed = false
		queue = {}

		-- one batch per tick, so a burst drains at a steady rate instead of
		-- dumping the whole queue into a single frame
		timer.Create(FLUSH_TIMER, FLUSH_INTERVAL, 0, function()
			flushPending()
			if subscribed then sendBatch(queue, false) end
		end)
	end

	function self:handle(data)
		if data.action == "subscribe" then
			subscribed = true
			queue = {}

			-- copied, not drained: a second viewer subscribing still gets it
			local backlog = {}
			for i = 1, #replay do
				backlog[i] = replay[i]
			end

			while #backlog > 0 do
				if not sendBatch(backlog, true) then break end
			end
		elseif data.action == "unsubscribe" then
			subscribed = false
			queue = {}
		elseif data.action == "command" and data.command then
			-- deliberately not muted: the viewer should see who ran what
			MsgC(
				Color(220, 60, 60),
				("[RCON] %s ran \"%s\"\n"):format(data.runner or "unknown", data.command)
			)
			game.ConsoleCommand(data.command .. "\n")
		end

		return true
	end

	return self
end

function ConsolePayload:__gc()
	hook.Remove("EngineSpew", "metaconcord.ConsolePayload")
	timer.Remove(FLUSH_TIMER)
end

return setmetatable({}, ConsolePayload)
