local Payload = include("./Payload.lua")
local RconPayload = table.Copy(Payload)
RconPayload.__index = RconPayload
RconPayload.super = Payload
RconPayload.name = "RconPayload"

function RconPayload:__call(socket)
	self.super.__call(self, socket)
	return self
end

function RconPayload:__gc()
end

local function createExecutionContext() 
	local ctx = {
		stdout = "",
		errors = {},
		returns = {},
	}

	local function stdout(func, options, ...)
		options = options or {}

		local args = { ... }
		for i, arg in pairs(args) do
			args[i] = tostring(arg)
		end

		local out = table.concat({ ... }, options.concatenator);
		ctx.stdout = ctx.stdout .. out
		if options.newline then
			ctx.stdout = ctx.stdout .. "\n"
		end

		func(...)
	end

	local function stderr(func, ...)
		local args = { ... }
		for _, arg in pairs(args) do
			table.insert(ctx.errors, tostring(arg))
		end

		func(...)
	end

	ctx.env = setmetatable({
		print = function(...) 
			stdout(print, { concatenator = "\t", newline = true, }, ...) 
		end,
		Msg = function(...) 
			stdout(Msg, nil ...) 
		end,
		MsgC = function(...) 
			stdout(Msg, nil, ...) 
		end,
		MsgN = function(...) 
			stdout(Msg, { newline = true }, ...)  
		end,
		ErrorNoHalt = function(...)
			stderr(ErrorNoHalt, ...)
		end,
		ErrorNoHaltWithStack = function(...)
			stderr(ErrorNoHaltWithStack, ...)
		end,
		Error = function(...)
			stderr(Error, ...)
		end,
		error = function(...)
			stderr(error, ...)
		end
	}, { __index = _G })

	return ctx
end

local IDENTIFIER = "metaconcord"
function RconPayload:handle(data)
	if not data.isLua then
		game.ConsoleCommand(data.command .. "\n")
	else
		local ctx = createExecutionContext()
		local runnerLog = ("[ %s: %s ]"):format(IDENTIFIER, data.runner)
		if data.realm == "sv" then
			local func = CompileString(data.code, runnerLog, false)
			if isstring(func) then
				table.insert(ctx.errors, ("Syntax error: %s"):format(func))
			elseif isfunction(func)
				local ret = { pcall(func) }
				if table.remove(ret, 1) == true then
					ctx.returns = ret
				else
					table.insert(ctx.errors, ret[1])
				end
			end
		elseif luadev and data.realm == "sh" then
			local succ, ret = luadev.RunOnShared(data.code, runnerLog)
			if not succ then
				table.insert(ctx.errors, ret)
			else
				ctx.returns = ret
			end

			ctx.stdout = "stdout not available in shared mode"
		elseif luadev and data.realm == "cl" then
			luadev.RunOnClients(data.code, runnerLog)
			ctx.stdout = "stdout not available in clients mode"
		else
			print(("Unknown realm '%s' for metaconcord lua payload by %s"):format(data.realm, data.runner))
		end
	
		self:write({
			identifier = data.identifier,
			returns = ctx.returns,
			errors = ctx.errors,
			stdout = ctx.stdout,
		})
	end
end

return setmetatable({}, RconPayload)