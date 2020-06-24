require("gwsockets")

metaconcord = metaconcord or {
    payloads = {}
}

local token = file.Read("metaconcord-token.txt", "DATA")
local endpoint = file.Read("metaconcord-endpoint.txt", "DATA")
local path = "metaconcord/payloads/%s"
local headerCol = Color(53, 219, 166)

function metaconcord.print(...)
    MsgC(headerCol, "[metaconcord] ", Color(255, 255, 255), ...)
    Msg("\n")
end

function metaconcord.connect()
    if metaconcord.socket and metaconcord.socket:isConnected() then return end -- metaconcord.print("Already connected!")
    local socket = GWSockets.createWebSocket(("ws://%s"):format(endpoint))
    socket:setHeader("X-Auth-Token", token)

    function socket:onMessage(data)
        data = util.JSONToTable(data)

        if data then
            for _, payload in next, metaconcord.payloads do
                if data.payload.name == payload.name then
                    payload:handle(data.payload)
                end
            end
        end
    end

    function socket:onError(err)
        metaconcord.print("Error: ", Color(255, 0, 0), err)
        metaconcord.disconnect()
    end

    function socket:onConnected()
        metaconcord.print("Connected.")

        for _, script in next, (file.Find(path:format("*.lua"), "LUA")) do
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

        timer.Simple(0, function()
            for _, payload in next, metaconcord.payloads do
                if payload.onConnected then
                    payload:onConnected()
                end
            end
        end)
    end

    function socket:onDisconnected()
        for k, payload in pairs(metaconcord.payloads) do
            payload:__gc() -- 5.2 only :(
            metaconcord.payloads[k] = nil
        end
    end

    metaconcord.socket = socket
    metaconcord.print("Connecting...")
    metaconcord.socket:open()

    timer.Create("metaconcordHeartbeat", 10, 0, function()
        if metaconcord.socket and metaconcord.socket:isConnected() then
            metaconcord.socket:write("") -- heartbeat LOL
        else
            metaconcord.print("Lost connection, reconnecting...")
            metaconcord.start()
        end
    end)
end

function metaconcord.disconnect()
    if not metaconcord.socket or not metaconcord.socket:isConnected() then return end -- metaconcord.print("Not connected.")
    metaconcord.print("Disconnecting...")
    metaconcord.socket:close()
    metaconcord.socket = nil
    metaconcord.print("Disconnected.")
end

function metaconcord.start()
    if metaconcord.socket and metaconcord.socket:isConnected() then
        local onDisconnected = metaconcord.socket.onDisconnected
        metaconcord.socket.onDisconnected = function(self)
            onDisconnected(self)

            timer.Simple(0, function() metaconcord.connect() end)
        end
        metaconcord.stop()
    else
        metaconcord.connect()
    end
end

function metaconcord.stop()
    metaconcord.disconnect()
    timer.Remove("metaconcordHeartbeat")
end

function metaconcord.getPayload(name)
    for _, payload in next, metaconcord.payloads do
        if name == payload.name then
            return payload
        end
    end
end

hook.Add("Initialize", "metaconcord", metaconcord.start)

if GAMEMODE then
    hook.GetTable().Initialize.metaconcord()
end