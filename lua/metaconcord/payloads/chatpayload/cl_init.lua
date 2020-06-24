local gray = Color(100, 100, 100)
local blurple = Color(114, 137, 218)

net.Receive("metaconcordChatPayload", function()
	local name = net.ReadString()
	local content = net.ReadString()
	chat.AddText(gray, "[Discord] ", blurple, name, color_white, ": ", content)
end)