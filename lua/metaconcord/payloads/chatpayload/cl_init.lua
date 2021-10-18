net.Receive("metaconcordChatPayload", function()
	local name = net.ReadString()
	local color = net.ReadInt(25)
	local content = net.ReadString()
	local avatar_url = net.ReadString()

	local replied_name = net.ReadString()
	local replied_color = net.ReadInt(25)
	local replied_content = net.ReadString()
	local replied_avatar_url = net.ReadString()

	hook.Run("DiscordSay", name, content, color, avatar_url, {
		name = replied_name,
		color = replied_color,
		content = replied_content,
		avatar_url = replied_avatar_url
	}
end)
