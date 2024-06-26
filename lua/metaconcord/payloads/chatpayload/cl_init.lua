net.Receive("metaconcordChatPayload", function()
	local id = net.ReadString()
	local username = net.ReadString()
	local nick = net.ReadString()
	local color = net.ReadInt(25)
	local avatar_url = net.ReadString()
	local content = net.ReadString()
	local msgID = net.ReadString()
	local replied_content = net.ReadString()
	local replied_msgID = net.ReadString()
	local replied_ingameName = net.ReadString()

	hook.Run("DiscordSay", {
			id = id,
			username = username,
			name = nick ~= "" and nick or username,
			color = color,
			avatar_url = avatar_url,
		},
		content,
		msgID,
		{
			msgID = replied_msgID,
			content = replied_content,
			ingameName = replied_ingameName,
		}
	)
end)
