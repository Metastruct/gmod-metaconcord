local path = "metaconcord/payloads/%s"

for _, folder in next, ({file.Find(path:format("*"), "LUA")})[2] do
    local scriptPath = (path .. "/%s"):format(folder, "cl_init.lua")

    if file.Exists(scriptPath, "LUA") then
        include(scriptPath)
    end
end