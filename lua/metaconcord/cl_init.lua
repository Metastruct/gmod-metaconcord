local path = "metaconcord/payloads/client/%s"

for _, filePath in next, (file.Find(path:format("*.lua"), "LUA")) do
    include(path:format(filePath))
end