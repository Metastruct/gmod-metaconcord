local gray = Color(100, 100, 100)
local blurple = Color(114, 137, 218)
local discord_postfix = CreateClientConVar("discord_postfix", "0", true)

local function discord2color(int)
	local hex = string.format("%.6x", int)
	return Color(tonumber("0x" .. hex:sub(1, 2)), tonumber("0x" .. hex:sub(3, 4)), tonumber("0x" .. hex:sub(5, 6)))
end

net.Receive("metaconcordChatPayload", function()
	local name = net.ReadString()
	local color = net.ReadInt(25)
	local content = net.ReadString()
	local roleColor = color > 1 and discord2color(color) or blurple
	local avatar_url = net.ReadString()

	local replied_name = net.ReadString()
	local replied_color = net.ReadInt(25)
	local replied_content = net.ReadString()
	local replied_roleColor = replied_color > 1 and discord2color(replied_color) or blurple
	local replied_avatar_url = net.ReadString()

	local ret = hook.Run("DiscordSay", name, content, {nick = replied_name, color = replied_color, content = replied_content})
	if ret == false then return end

	local pastellize = GetConVar("easychat_pastel")
	if pastellize and pastellize:GetBool() and EasyChat.PastelizeNick then
		roleColor = EasyChat.PastelizeNick(name)
		replied_roleColor = EasyChat.PastelizeNick(replied_name)
	end

	if discord_postfix:GetBool() then
		if replied_name ~= "" then
			chat.AddText(roleColor, name, gray, " [replying to: ", replied_roleColor, replied_name, gray, "]", color_white, ": " .. content, gray, " [D]")
		else
			chat.AddText(roleColor, name, color_white, ": " .. content, gray, " [D]")
		end
	else
		if replied_name ~= "" then
			chat.AddText(gray, "[Discord] ", roleColor, name, gray, " [replying to: ", replied_roleColor, replied_name, gray, "]", color_white, ": ", content)
		else
			chat.AddText(gray, "[Discord] ", roleColor, name, color_white, ": ", content)
		end
	end
end)
