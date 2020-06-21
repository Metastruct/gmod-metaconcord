local path = "metaconcord/payloads/client/%s"

for _, folder in next, select(2, file.Find(path:format("*"), "LUA")) do
    local filePath = (path .. "/%s"):format(folder, "cl_init.lua")

    if file.Exists(filePath, "LUA") then
        include(filePath)
    end
end