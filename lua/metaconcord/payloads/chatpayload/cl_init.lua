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

	hook.Run("DiscordSay", name, content, color, avatar_url, {
		name = replied_name,
		color = replied_color,
		content = replied_content,
		avatar_url = replied_avatar_url
	}
end)
