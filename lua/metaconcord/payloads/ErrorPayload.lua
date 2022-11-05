local Payload = include("./Payload.lua")
local ErrorPayload = table.Copy(Payload)
ErrorPayload.__index = ErrorPayload
ErrorPayload.super = Payload
ErrorPayload.name = "ErrorPayload"

function ErrorPayload:handle(data)
	metaconcord.print("error", ErrorPayload.name, "External Error:")
	PrintTable(data)
end

function Payload:__call(socket)
	self.socket = socket

	hook.Add("OnHookFailed", self, function (_, name, identifier, error)
		self:write({
			hook_error = {
				name = name,
				identifier = identifier,
				error = error,
			}
		})
	end)

	-- hook.Add("LuaError", self, function(_, msg, traceback, info)
	-- 	local maxlevel = #info
	-- 	local minlevel = 5
	-- 	local addon_name = (info[min_level].source:match("lua/(.-)/") or info[min_level].source) or "???"

	-- 	self:write({
	-- 		error = {
	-- 			error = msg,
	-- 			stack = traceback:Split('\n'),
	-- 			realm = "server",
	-- 			hash = "",
	-- 			gamemode = gmod.GetGamemode()["Name"] or "???"
	-- 		}
	-- 	})

	-- end)

	return self
end

function Payload:__gc()
	-- hook.Remove("LuaError", self)
	hook.Remove("OnHookFailed", self)
end

return setmetatable({}, ErrorPayload)


-- local function hook_override(callback)
--     _G.old_error_func = _G.old_error_func or debug.getregistry()[1]
--     debug.getregistry()[1] = function(msg, ...)
--         local ok, err = pcall(function()
--             local tbl = {}
--             for i = 0, math.huge do
--                 local info = debug.getinfo(i)
--                 if not info then break end
--                 info.func_info = debug.getinfo(info.func)
--                 info.func_info.func = nil
-- 				info.func = nil
--                 tbl[i + 1] = info
--             end
--             callback(msg, debug.traceback(), tbl)
--         end)

--         if not ok then
--             ErrorNoHalt("error in error hook_override: ", err)
--         end
--         return _G.old_error_func(msg, ...)
--     end
-- end

-- if SERVER then
--     hook_override(function(msg, traceback, info)
--         -- print(msg, traceback, PrintTable(stack))
--         hook.Run("LuaError", msg, traceback, info)
--     end)
-- end


-- -- hook.Add("LuaError", me, function(msg, traceback, stack)
-- --     print(msg, traceback, stack)
-- -- end)