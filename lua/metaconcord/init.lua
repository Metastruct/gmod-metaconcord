require("gwsockets")

metaconcord = metaconcord or {
    payloads = {}
}

local token = file.Read("metaconcord-token.txt", "DATA")
local blue = Color(111, 133, 210)

function metaconcord.print(...)
    MsgC(blue, "[Discord] ", Color(255, 255, 255), ...)
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

    timer.Create("metaconcord.heartbeat", 10, 0, function()
        if metaconcord.socket and metaconcord.socket:isConnected() then
            metaconcord.socket:write("") -- heartbeat LOL
        else
            metaconcord.print("Lost connection, reconnecting...")
            init()
        end
    end)

    local socket = GWSockets.createWebSocket("ws://127.0.0.1:3000/")
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
        print("Error: ", err)
    end

    function socket:onConnected()
        metaconcord.print("Connected.")
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

    for _, file in next, (file.Find(path:format("*.lua"), "LUA")) do
        local name = string.StripExtension(file)
        if name == "Payload" then continue end
        local Payload = include(path:format(file))
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