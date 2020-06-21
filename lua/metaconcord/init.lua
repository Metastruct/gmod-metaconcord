require("gwsockets")

metaconcord = metaconcord or {
    payloads = {}
}

local token = file.Read("metaconcord-token.txt", "DATA")
local endpoint = file.Read("metaconcord-endpoint.txt", "DATA")
local headerCol = Color(53, 219, 166)

function metaconcord.print(...)
    MsgC(headerCol, "[metaconcord] ", Color(255, 255, 255), ...)
    Msg("\n")
end

local function init()
    metaconcord.stop()

    timer.Simple(1, function()
        metaconcord.start()
    end)
end

function metaconcord.connect()
    if metaconcord.socket and metaconcord.socket:isConnected() then
        metaconcord.print("Already connected!")

        return
    end

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
    end

    function socket:onConnected()
        metaconcord.print("Connected.")

        timer.Create("metaconcord.heartbeat", 10, 0, function()
            if metaconcord.socket and metaconcord.socket:isConnected() then
                metaconcord.socket:write("") -- heartbeat LOL
            else
                metaconcord.print("Lost connection, reconnecting...")
                init()
            end
        end)
    end

    function socket:onDisconnected()
        metaconcord.socket = nil
        metaconcord.print("Disconnected.")
    end

    metaconcord.socket = socket
    metaconcord.print("Connecting...")
    metaconcord.socket:open()
end

function metaconcord.disconnect()
    if not metaconcord.socket or not metaconcord.socket:isConnected() then
        metaconcord.print("Not connected.")

        return
    end

    metaconcord.print("Disconnecting...")
    metaconcord.socket:close()
end

local path = "metaconcord/payloads/%s"

function metaconcord.clearPayloads()
    for k, payload in pairs(metaconcord.payloads) do
        payload:__gc() -- 5.2 only :(
        metaconcord.payloads[k] = nil
    end
end

function metaconcord.start()
    metaconcord.clearPayloads()
    metaconcord.connect()

    for _, filePath in next, (file.Find(path:format("*.lua"), "LUA")) do
        local name = string.StripExtension(filePath)
        if name == "Payload" then continue end
        local Payload = include(path:format(filePath))
        metaconcord.payloads[name] = Payload(metaconcord.socket)
    end
end

function metaconcord.stop()
    metaconcord.clearPayloads()
    metaconcord.disconnect()
    timer.Remove("metaconcord.heartbeat")
end

hook.Add("Initialize", "metaconcord", init)

if GAMEMODE then
    hook.GetTable().Initialize.metaconcord()
end