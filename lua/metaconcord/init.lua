require("gwsockets")

metaconcord = metaconcord or {
	payloads = {}
}

local token = file.Read("metaconcord-token.txt", "DATA")
local endpoint = file.Read("metaconcord-endpoint.txt", "DATA")
local path = "metaconcord/payloads/%s"
local headerCol = Color(53, 219, 166)
local retry = false
local backoff = 0

local logCol = {
	["info"] = 	Color(255, 255, 255),
	["error"] = Color(255, 0, 0)
}

function metaconcord.print(state, extra,...)
	if metalog then
		metalog.[state]("metaconcord", extra, ...)
		return
	end
	MsgC(headerCol, "[metaconcord] ", logCol[state], ...)
	Msg("\n")
end

function metaconcord.connect()
	if metaconcord.socket then return end -- metaconcord.print("Already connected!")
	local socket = GWSockets.createWebSocket(("ws://%s"):format(endpoint))
	socket:setHeader("X-Auth-Token", token)

	function socket:onMessage(data)
		data = util.JSONToTable(data)

		if data then
			for _, payload in next, metaconcord.payloads do
				if data.payload.name == payload.name then
					payload:handle(data.payload.data)
				end
			end
		end
	end

	function socket:onError(err)
		metaconcord.print("error", "socket", err)
	end

	function socket:onConnected()
		metaconcord.print("info", "socket", "Connected.")
		backoff = 0

		for _, script in pairs(file.Find(path:format("*.lua"), "LUA")) do
			local name = string.StripExtension(script)

			if name ~= "Payload" then
				local Payload = include(path:format(script))
				metaconcord.payloads[Payload.name] = Payload(self)
			end
		end

		for _, folder in next, ({file.Find(path:format("*"), "LUA")})[2] do
			local scriptPath = (path .. "/%s"):format(folder, "init.lua")
			local clScriptPath = (path .. "/%s"):format(folder, "cl_init.lua")

			if file.Exists(scriptPath, "LUA") then
				local Payload = include(scriptPath)
				metaconcord.payloads[Payload.name] = Payload(self)
			end

			if file.Exists(clScriptPath, "LUA") then
				AddCSLuaFile(clScriptPath)
			end
		end

		-- Wait a while for the other side to initialize
		timer.Simple(0, function()
			for _, payload in next, metaconcord.payloads do
				if payload.onConnected then
					payload:onConnected()
				end
			end
		end)

		timer.Create("metaconcord.Heartbeat", 10, 0, function()
			if metaconcord.socket and metaconcord.socket:isConnected() then
				metaconcord.socket:write("") -- heartbeat LOL
			end
		end)

		timer.Remove("metaconcord.Retry")
	end

	function socket:onDisconnected()
		for k, payload in pairs(metaconcord.payloads) do
			payload:__gc() -- 5.2 only :(
			metaconcord.payloads[k] = nil
		end

		metaconcord.socket = nil
		metaconcord.print("info", "socket", "Disconnected.")
		timer.Remove("metaconcord.Heartbeat")

		timer.Create("metaconcord.Retry", math.min(2 ^ backoff, 60 * 5), 1, function()
			if not retry then return end
			metaconcord.print("info", "socket", "Lost connection, reconnecting...")
			metaconcord.start()
		end)

		backoff = backoff + 1
	end

	metaconcord.socket = socket
	metaconcord.print("info", "socket", "Connecting...")
	metaconcord.socket:open()
end

function metaconcord.disconnect()
	if not metaconcord.socket or not metaconcord.socket:isConnected() then return end
	metaconcord.print("info", "socket", "Disconnecting...")
	metaconcord.socket:close()
end

function metaconcord.start()
	retry = true
	metaconcord.connect()

	-- every 10 mins
	timer.Create("metaconcord.PeriodicChecks", 60 * 60 * 10, 0, function()
		if not metaconcord.socket or not metaconcord.socket:isConnected() then
			metaconcord.print("info", "socket", "Lost connection, reconnecting...")
			metaconcord.stop()
			metaconcord.start()
		end
	end)
end

function metaconcord.stop()
	retry = false
	metaconcord.disconnect()
	backoff = 0
end

function metaconcord.getPayload(name)
	for _, payload in next, metaconcord.payloads do
		if name == payload.name then return payload end
	end
end

hook.Add("Initialize", "metaconcord", metaconcord.start)

if GAMEMODE then
	if metaconcord.socket then
		local onDisconnected = metaconcord.socket.onDisconnected

		metaconcord.socket.onDisconnected = function(self)
			onDisconnected(self)
			timer.Simple(0, hook.GetTable().Initialize.metaconcord)
		end

		metaconcord.stop()
	else
		hook.GetTable().Initialize.metaconcord()
	end
end