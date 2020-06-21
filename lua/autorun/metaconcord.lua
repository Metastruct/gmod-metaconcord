AddCSLuaFile("metaconcord/cl_init.lua")

if CLIENT then
    include("metaconcord/cl_init.lua")

    return
end

include("metaconcord/init.lua")