local gray = Color(100, 100, 100)
local blurple = Color(114, 137, 218)

net.Receive("metaconcordChatPayload", function()
	local name = net.ReadString()
	local color = net.ReadInt(25)
	local content = net.ReadString()
	local roleColor = blurple

	local ret = hook.Run("DiscordSay", name, content)
	if ret == false then return end

	if color > 1 then
		local hex = string.format("%.6x", color)
		-- Disgusting
		roleColor = Color(tonumber("0x" .. hex:sub(1, 2)), tonumber("0x" .. hex:sub(3, 4)), tonumber("0x" .. hex:sub(5, 6)))
	end

	chat.AddText(gray, "[Discord] ", roleColor, name, color_white, ": ", content)
end)