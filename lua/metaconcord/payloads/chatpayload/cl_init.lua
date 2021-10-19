net.Receive("metaconcordChatPayload", function()
	local id = net.ReadString()
	local name = net.ReadString()
	local color = net.ReadInt(25)
	local avatar_url = net.ReadString()
	local content = net.ReadString()
	local msgID = net.ReadString()
	local replied_content = net.ReadString()
	local replied_msgID = net.ReadString()
	local replied_ingame = net.ReadBool()

	hook.Run("DiscordSay", {
			id = id,
			name = name,
			color = color,
			avatar_url = avatar_url,
		},
		content,
		msgID,
		{
			msgID = replied_msgID,
			content = replied_content,
			ingame = replied_ingame,
		}
	)
end)
