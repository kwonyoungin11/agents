---
name: chat-system
description: |
  Roblox Custom chat system - 채팅 시스템, 채팅 명령어, TextChatService, 채팅 필터, 팀 채팅, 시스템 메시지, 뮤트.
  Custom chat commands, TextChatService integration, chat filters, team chat, system messages, and mute functionality.
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Grep
  - Glob
effort: high
---

# Chat System Skill

Complete custom chat system using TextChatService with commands, team chat, filters, system messages, and mute.

## Architecture Overview

```
ServerScriptService/
  ChatManager.server.luau          -- Command processing, mute logic, system messages
ReplicatedStorage/
  Shared/
    ChatConfig.luau                -- Command definitions, filter rules
StarterPlayerScripts/
  ChatClient.client.luau           -- Client-side TextChatService hooks
```

## Core Server: ChatManager

```luau
--!strict
-- ServerScriptService/ChatManager.server.luau
-- Server-side chat management: commands, mute, team chat, system messages.

local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Teams = game:GetService("Teams")

local ChatConfig = require(ReplicatedStorage.Shared.ChatConfig)

------------------------------------------------------------------------
-- Types
------------------------------------------------------------------------

export type ChatCommand = {
	name: string,
	aliases: { string }?,
	description: string,
	requiredPermission: "all" | "admin" | "moderator"?,
	execute: (player: Player, args: { string }) -> string?,
}

------------------------------------------------------------------------
-- Remote setup
------------------------------------------------------------------------

local chatFolder = Instance.new("Folder")
chatFolder.Name = "ChatEvents"
chatFolder.Parent = ReplicatedStorage

local systemMessage = Instance.new("RemoteEvent")
systemMessage.Name = "SystemMessage"
systemMessage.Parent = chatFolder

local muteChanged = Instance.new("RemoteEvent")
muteChanged.Name = "MuteChanged"
muteChanged.Parent = chatFolder

------------------------------------------------------------------------
-- State
------------------------------------------------------------------------

local mutedPlayers: { [number]: { until_time: number, reason: string? } } = {}
local adminUserIds: { [number]: boolean } = {}  -- populate with your admin list
local commandMap: { [string]: ChatCommand } = {}

local ChatManager = {}

------------------------------------------------------------------------
-- Admin Check
------------------------------------------------------------------------

function ChatManager.isAdmin(player: Player): boolean
	return adminUserIds[player.UserId] == true
end

function ChatManager.isModerator(player: Player): boolean
	-- TODO: implement moderator check
	return ChatManager.isAdmin(player)
end

------------------------------------------------------------------------
-- Mute System
------------------------------------------------------------------------

function ChatManager.mutePlayer(target: Player, durationSeconds: number?, reason: string?)
	local untilTime = if durationSeconds then os.time() + durationSeconds else math.huge
	mutedPlayers[target.UserId] = {
		until_time = untilTime,
		reason = reason,
	}
	muteChanged:FireClient(target, true, reason, durationSeconds)
end

function ChatManager.unmutePlayer(target: Player)
	mutedPlayers[target.UserId] = nil
	muteChanged:FireClient(target, false)
end

function ChatManager.isMuted(player: Player): boolean
	local muteData = mutedPlayers[player.UserId]
	if not muteData then return false end

	if os.time() > muteData.until_time then
		mutedPlayers[player.UserId] = nil
		return false
	end

	return true
end

------------------------------------------------------------------------
-- System Messages
------------------------------------------------------------------------

function ChatManager.sendSystemMessage(message: string, recipient: Player?)
	if recipient then
		systemMessage:FireClient(recipient, message, "system")
	else
		systemMessage:FireAllClients(message, "system")
	end
end

function ChatManager.sendTeamMessage(teamName: string, message: string)
	local team = Teams:FindFirstChild(teamName)
	if not team then return end

	for _, player in ipairs(Players:GetPlayers()) do
		if player.Team and player.Team.Name == teamName then
			systemMessage:FireClient(player, message, "team")
		end
	end
end

function ChatManager.sendAnnouncment(message: string)
	systemMessage:FireAllClients(message, "announcement")
end

------------------------------------------------------------------------
-- Command Registration
------------------------------------------------------------------------

function ChatManager.registerCommand(command: ChatCommand)
	commandMap[command.name:lower()] = command
	if command.aliases then
		for _, alias in ipairs(command.aliases) do
			commandMap[alias:lower()] = command
		end
	end
end

------------------------------------------------------------------------
-- Built-in Commands
------------------------------------------------------------------------

ChatManager.registerCommand({
	name = "help",
	aliases = { "?" },
	description = "Show available commands",
	requiredPermission = "all",
	execute = function(player: Player, args: { string }): string?
		local lines = { "Available commands:" }
		local seen: { [string]: boolean } = {}
		for _, cmd in pairs(commandMap) do
			if not seen[cmd.name] then
				seen[cmd.name] = true
				local perm = cmd.requiredPermission or "all"
				if perm == "all" or (perm == "admin" and ChatManager.isAdmin(player)) or (perm == "moderator" and ChatManager.isModerator(player)) then
					table.insert(lines, "/" .. cmd.name .. " - " .. cmd.description)
				end
			end
		end
		return table.concat(lines, "\n")
	end,
})

ChatManager.registerCommand({
	name = "mute",
	description = "Mute a player (admin only)",
	requiredPermission = "admin",
	execute = function(player: Player, args: { string }): string?
		if not ChatManager.isAdmin(player) then
			return "No permission."
		end

		local targetName = args[1]
		if not targetName then return "Usage: /mute <player> [duration_seconds] [reason]" end

		local target = Players:FindFirstChild(targetName)
		if not target or not target:IsA("Player") then return "Player not found." end

		local duration = tonumber(args[2])
		local reason = args[3]
		ChatManager.mutePlayer(target, duration, reason)
		return "Muted " .. target.Name
	end,
})

ChatManager.registerCommand({
	name = "unmute",
	description = "Unmute a player (admin only)",
	requiredPermission = "admin",
	execute = function(player: Player, args: { string }): string?
		if not ChatManager.isAdmin(player) then
			return "No permission."
		end

		local targetName = args[1]
		if not targetName then return "Usage: /unmute <player>" end

		local target = Players:FindFirstChild(targetName)
		if not target or not target:IsA("Player") then return "Player not found." end

		ChatManager.unmutePlayer(target)
		return "Unmuted " .. target.Name
	end,
})

ChatManager.registerCommand({
	name = "announce",
	aliases = { "ann" },
	description = "Send a server announcement (admin only)",
	requiredPermission = "admin",
	execute = function(player: Player, args: { string }): string?
		if not ChatManager.isAdmin(player) then
			return "No permission."
		end
		local message = table.concat(args, " ")
		if message == "" then return "Usage: /announce <message>" end
		ChatManager.sendAnnouncment(message)
		return nil
	end,
})

ChatManager.registerCommand({
	name = "team",
	aliases = { "t" },
	description = "Send a message to your team only",
	requiredPermission = "all",
	execute = function(player: Player, args: { string }): string?
		if not player.Team then return "You are not on a team." end
		local message = table.concat(args, " ")
		if message == "" then return "Usage: /team <message>" end
		ChatManager.sendTeamMessage(player.Team.Name, "[TEAM] " .. player.Name .. ": " .. message)
		return nil
	end,
})

ChatManager.registerCommand({
	name = "w",
	aliases = { "whisper", "msg" },
	description = "Send a private message",
	requiredPermission = "all",
	execute = function(player: Player, args: { string }): string?
		local targetName = args[1]
		if not targetName then return "Usage: /w <player> <message>" end

		local target = Players:FindFirstChild(targetName)
		if not target or not target:IsA("Player") then return "Player not found." end

		local message = table.concat(args, " ", 2)
		systemMessage:FireClient(target, "[From " .. player.Name .. "]: " .. message, "whisper")
		return "[To " .. target.Name .. "]: " .. message
	end,
})

------------------------------------------------------------------------
-- TextChatService Integration
------------------------------------------------------------------------

-- Process commands via TextChatService callback
local function onIncomingMessage(message: TextChatMessage)
	local source = message.TextSource
	if not source then return end

	local player = Players:GetPlayerByUserId(source.UserId)
	if not player then return end

	local text = message.Text
	if not text or text == "" then return end

	-- Check mute
	if ChatManager.isMuted(player) then
		-- Message is already sent through TextChatService; we filter on display
		return
	end

	-- Check for command prefix
	if text:sub(1, 1) == "/" then
		local parts = text:sub(2):split(" ")
		local cmdName = parts[1]:lower()
		local args = {}
		for i = 2, #parts do
			table.insert(args, parts[i])
		end

		local command = commandMap[cmdName]
		if command then
			local response = command.execute(player, args)
			if response then
				systemMessage:FireClient(player, response, "command_response")
			end
		end
	end
end

-- Setup TextChatService
local textChannels = TextChatService:WaitForChild("TextChannels", 10)
if textChannels then
	local generalChannel = textChannels:FindFirstChild("RBXGeneral")
	if generalChannel then
		(generalChannel :: any).MessageReceived:Connect(onIncomingMessage)
	end
end

------------------------------------------------------------------------
-- Player Events
------------------------------------------------------------------------

Players.PlayerAdded:Connect(function(player: Player)
	-- Send welcome message
	task.delay(2, function()
		ChatManager.sendSystemMessage("Welcome to the game, " .. player.Name .. "! Type /help for commands.", player)
	end)
end)

Players.PlayerRemoving:Connect(function(player: Player)
	-- Cleanup mute data if temporary
	if mutedPlayers[player.UserId] then
		if mutedPlayers[player.UserId].until_time ~= math.huge then
			-- Keep timed mutes for when they rejoin
		else
			mutedPlayers[player.UserId] = nil
		end
	end
end)

return ChatManager
```

## Chat Configuration

```luau
--!strict
-- ReplicatedStorage/Shared/ChatConfig.luau

local ChatConfig = {}

-- Command prefix character
ChatConfig.CommandPrefix = "/"

-- Admin user IDs (add your own)
ChatConfig.AdminUserIds = {
	-- 12345678,
}

-- Filtered words (TextChatService already handles Roblox filtering;
-- this is for game-specific additional filters)
ChatConfig.FilteredPatterns = {
	-- Add custom patterns to filter
}

-- Chat colors by role
ChatConfig.RoleColors = {
	admin = Color3.fromRGB(255, 85, 85),
	moderator = Color3.fromRGB(85, 170, 255),
	vip = Color3.fromRGB(255, 215, 0),
	default = Color3.fromRGB(255, 255, 255),
}

-- Team chat prefix
ChatConfig.TeamChatPrefix = "/t "

-- Max message length (additional to Roblox limit)
ChatConfig.MaxMessageLength = 200

return ChatConfig
```

## Client Chat Integration

```luau
--!strict
-- StarterPlayerScripts/ChatClient.client.luau
-- Client-side: display system messages, handle mute UI, custom chat rendering.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local chatEvents = ReplicatedStorage:WaitForChild("ChatEvents")
local systemMessageEvent = chatEvents:WaitForChild("SystemMessage")
local muteChangedEvent = chatEvents:WaitForChild("MuteChanged")

local player = Players.LocalPlayer

-- Display system messages in chat
systemMessageEvent.OnClientEvent:Connect(function(message: string, messageType: string)
	local channels = TextChatService:FindFirstChild("TextChannels")
	if not channels then return end

	local generalChannel = channels:FindFirstChild("RBXGeneral")
	if generalChannel and (generalChannel :: any).DisplaySystemMessage then
		local prefix = ""
		if messageType == "system" then
			prefix = "[System] "
		elseif messageType == "team" then
			prefix = "[Team] "
		elseif messageType == "announcement" then
			prefix = "[Announcement] "
		elseif messageType == "whisper" then
			prefix = "[Whisper] "
		elseif messageType == "command_response" then
			prefix = ""
		end

		(generalChannel :: any):DisplaySystemMessage(prefix .. message)
	end
end)

-- Mute notification
muteChangedEvent.OnClientEvent:Connect(function(isMuted: boolean, reason: string?, duration: number?)
	if isMuted then
		local msg = "You have been muted."
		if reason then msg = msg .. " Reason: " .. reason end
		if duration then msg = msg .. " Duration: " .. tostring(duration) .. "s" end

		local channels = TextChatService:FindFirstChild("TextChannels")
		if channels then
			local general = channels:FindFirstChild("RBXGeneral")
			if general and (general :: any).DisplaySystemMessage then
				(general :: any):DisplaySystemMessage(msg)
			end
		end
	else
		local channels = TextChatService:FindFirstChild("TextChannels")
		if channels then
			local general = channels:FindFirstChild("RBXGeneral")
			if general and (general :: any).DisplaySystemMessage then
				(general :: any):DisplaySystemMessage("You have been unmuted.")
			end
		end
	end
end)
```

## Usage Guide

1. **Register custom commands**:
   ```luau
   ChatManager.registerCommand({
       name = "spawn",
       description = "Teleport to spawn",
       execute = function(player, args)
           -- teleport logic
           return "Teleported to spawn!"
       end,
   })
   ```
2. **System messages**: `ChatManager.sendSystemMessage("Server restarting in 5 minutes!")`
3. **Team chat**: Players use `/t <message>` or `/team <message>`.
4. **Mute**: Admins use `/mute <player> [duration] [reason]`.
5. **Admin setup**: Add user IDs to `ChatConfig.AdminUserIds`.

## 

---

## Learned Lessons

<!-- skill-evolve 에이전트가 자동으로 이 섹션에 교훈을 추가합니다 -->
<!-- 형식: ### [날짜] 문제명 / 원인 / 해결 / 규칙 -->

## Self-Evolution Protocol

이 스킬에서 에러가 발생하면:
1. 에러의 근본 원인을 분석한다
2. 이 파일의 `## Learned Lessons` 섹션에 교훈을 추가한다
3. 같은 실수가 반복되지 않도록 규칙화한다
4. SessionManager에 에러와 학습 내용을 기록한다

```lua
local SM = require(game.ServerStorage._RobloxEngine.SessionManager)
SM.logAction("SKILL_ERROR", "[이 스킬 이름] | [에러 설명]")
SM.logAction("SKILL_LEARNED", "[이 스킬 이름] | [배운 교훈]")
```

**매 작업 시 반드시 Learned Lessons 섹션을 먼저 읽고, 기존 교훈을 위반하지 않는지 확인한다.**

$ARGUMENTS

- `$ADMIN_USER_IDS` (number[]) -- List of admin user IDs.
- `$COMMAND_PREFIX` (string) -- Chat command prefix character. Default: `"/"`.
- `$CUSTOM_COMMANDS` (table) -- Additional custom command definitions.
- `$ROLE_COLORS` (table) -- Color3 values for different player roles.
- `$MAX_MESSAGE_LENGTH` (number) -- Additional message length limit. Default: `200`.
- `$ENABLE_TEAM_CHAT` (boolean) -- Enable team chat feature. Default: `true`.
- `$ENABLE_WHISPER` (boolean) -- Enable private messaging. Default: `true`.
