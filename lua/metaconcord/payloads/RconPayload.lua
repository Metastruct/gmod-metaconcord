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

local function stringifyTable(tbl)
	for k, v in pairs(tbl) do
		tbl[k] = tostring(v)
	end

	return tbl
end

local function createExecutionContext()
	local ctx = {
		stdout = "",
		errors = {},
		returns = {},
	}

	local function stdout(func, options, ...)
		options = options or {}

		local args = stringifyTable({ ... })
		local out = table.concat(args, options.concatenator);
		ctx.stdout = ctx.stdout .. out
		if options.newline then
			ctx.stdout = ctx.stdout .. "\n"
		end

		func(...)
	end

	local function stderr(func, ...)
		ctx.errors = stringifyTable({ ... })
		func(...)
	end

	ctx.env = setmetatable({
		print = function(...)
			stdout(print, { concatenator = "\t", newline = true, }, ...)
		end,
		Msg = function(...)
			stdout(Msg, nil, ...)
		end,
		MsgC = function(...)
			stdout(MsgC, nil, ...)
		end,
		MsgN = function(...)
			stdout(MsgN, { newline = true }, ...)
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
			elseif isfunction(func) then
				local ret = { pcall(setfenv(func, ctx.env)) }
				if table.remove(ret, 1) == true then
					ctx.returns = stringifyTable(ret)
				else
					table.insert(ctx.errors, tostring(ret[1]))
				end
			end
		elseif luadev and data.realm == "sh" then
			local succ, ret = luadev.RunOnShared(data.code, runnerLog)
			if not succ then
				table.insert(ctx.errors, tostring(ret))
			else
				ctx.returns = stringifyTable(ret)
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