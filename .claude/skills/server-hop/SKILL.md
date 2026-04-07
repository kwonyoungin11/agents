---
name: server-hop
description: |
  Roblox Server hop system - 서버 이동, 서버 목록, 특정 서버 참가, TeleportToPlaceInstance, 서버 브라우저 UI.
  Server list, join specific server, TeleportService:TeleportToPlaceInstance, and server browser UI.
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Grep
  - Glob
effort: high
---

# Server Hop System Skill

Complete server hop system with server list browser, join specific server, and TeleportService integration.

## Architecture Overview

```
ServerScriptService/
  ServerHopManager.server.luau     -- Server info reporting, teleport to specific instance
ReplicatedStorage/
  Shared/
    ServerHopConfig.luau           -- Configuration
StarterGui/
  ServerHopUI/
    ServerBrowser.client.luau      -- Server list browser UI
```

## Core Server: ServerHopManager

```luau
--!strict
-- ServerScriptService/ServerHopManager.server.luau
-- Manages server listing, server info broadcast, and targeted server teleportation.

local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ServerHopConfig = require(ReplicatedStorage.Shared.ServerHopConfig)

------------------------------------------------------------------------
-- Types
------------------------------------------------------------------------

export type ServerInfo = {
	serverId: string,
	playerCount: number,
	maxPlayers: number,
	region: string?,
	uptime: number,
	lastUpdated: number,
}

------------------------------------------------------------------------
-- Remote setup
------------------------------------------------------------------------

local serverHopFolder = Instance.new("Folder")
serverHopFolder.Name = "ServerHopEvents"
serverHopFolder.Parent = ReplicatedStorage

local getServerList = Instance.new("RemoteFunction")
getServerList.Name = "GetServerList"
getServerList.Parent = serverHopFolder

local requestServerHop = Instance.new("RemoteEvent")
requestServerHop.Name = "RequestServerHop"
requestServerHop.Parent = serverHopFolder

local requestRandomHop = Instance.new("RemoteEvent")
requestRandomHop.Name = "RequestRandomHop"
requestRandomHop.Parent = serverHopFolder

local hopStatus = Instance.new("RemoteEvent")
hopStatus.Name = "HopStatus"
hopStatus.Parent = serverHopFolder

------------------------------------------------------------------------
-- MemoryStore for server registry
------------------------------------------------------------------------

local serverRegistry = MemoryStoreService:GetSortedMap("ServerRegistry_v1")

local currentServerId = game.JobId or "studio_" .. tostring(os.time())
local serverStartTime = os.time()

local ServerHopManager = {}

------------------------------------------------------------------------
-- Server Registration
------------------------------------------------------------------------

local function registerServer()
	local info: ServerInfo = {
		serverId = currentServerId,
		playerCount = #Players:GetPlayers(),
		maxPlayers = Players.MaxPlayers,
		region = nil,  -- Roblox doesn't expose region directly
		uptime = os.time() - serverStartTime,
		lastUpdated = os.time(),
	}

	pcall(function()
		serverRegistry:SetAsync(currentServerId, info, ServerHopConfig.ServerRegistrationTTL)
	end)
end

local function unregisterServer()
	pcall(function()
		serverRegistry:RemoveAsync(currentServerId)
	end)
end

-- Update server info periodically
task.spawn(function()
	while true do
		registerServer()
		task.wait(ServerHopConfig.RegistrationUpdateInterval)
	end
end)

-- Unregister on shutdown
game:BindToClose(function()
	unregisterServer()
end)

------------------------------------------------------------------------
-- Server List
------------------------------------------------------------------------

function ServerHopManager.getServerList(): { ServerInfo }
	local servers: { ServerInfo } = {}

	local success, items = pcall(function()
		return serverRegistry:GetRangeAsync(Enum.SortDirection.Descending, 100)
	end)

	if success and items then
		for _, item in ipairs(items) do
			local info = item.value :: ServerInfo
			-- Filter out stale entries and current server
			if info.serverId ~= currentServerId and (os.time() - info.lastUpdated) < ServerHopConfig.ServerRegistrationTTL then
				table.insert(servers, info)
			end
		end
	end

	-- Sort by player count (most populated first)
	table.sort(servers, function(a, b)
		return a.playerCount > b.playerCount
	end)

	return servers
end

------------------------------------------------------------------------
-- Server Hopping
------------------------------------------------------------------------

function ServerHopManager.hopToServer(player: Player, targetServerId: string): boolean
	if targetServerId == currentServerId then
		hopStatus:FireClient(player, false, "You are already on this server.")
		return false
	end

	hopStatus:FireClient(player, true, "Teleporting to server...")

	local placeId = game.PlaceId

	local success, err = pcall(function()
		TeleportService:TeleportToPlaceInstance(placeId, targetServerId, player)
	end)

	if not success then
		warn("[ServerHop] Failed to hop:", err)
		hopStatus:FireClient(player, false, "Failed to join server. It may be full or no longer available.")
		return false
	end

	return true
end

function ServerHopManager.hopToRandomServer(player: Player): boolean
	local servers = ServerHopManager.getServerList()

	-- Filter to servers with available space
	local available: { ServerInfo } = {}
	for _, server in ipairs(servers) do
		if server.playerCount < server.maxPlayers then
			table.insert(available, server)
		end
	end

	if #available == 0 then
		-- No other servers; create fresh
		hopStatus:FireClient(player, true, "No other servers found. Creating new server...")

		local success, err = pcall(function()
			TeleportService:Teleport(game.PlaceId, player)
		end)

		if not success then
			hopStatus:FireClient(player, false, "Failed to server hop.")
			return false
		end
		return true
	end

	-- Pick a random server
	local target = available[math.random(1, #available)]
	return ServerHopManager.hopToServer(player, target.serverId)
end

function ServerHopManager.hopToLeastPopulated(player: Player): boolean
	local servers = ServerHopManager.getServerList()

	local best: ServerInfo? = nil
	for _, server in ipairs(servers) do
		if server.playerCount < server.maxPlayers then
			if not best or server.playerCount < best.playerCount then
				best = server
			end
		end
	end

	if best then
		return ServerHopManager.hopToServer(player, best.serverId)
	end

	hopStatus:FireClient(player, false, "No available servers found.")
	return false
end

function ServerHopManager.hopToMostPopulated(player: Player): boolean
	local servers = ServerHopManager.getServerList()

	for _, server in ipairs(servers) do
		if server.playerCount < server.maxPlayers then
			return ServerHopManager.hopToServer(player, server.serverId)
		end
	end

	hopStatus:FireClient(player, false, "All servers are full.")
	return false
end

------------------------------------------------------------------------
-- Remote Handlers
------------------------------------------------------------------------

getServerList.OnServerInvoke = function(player: Player)
	local servers = ServerHopManager.getServerList()
	-- Include current server info
	local currentInfo: ServerInfo = {
		serverId = currentServerId,
		playerCount = #Players:GetPlayers(),
		maxPlayers = Players.MaxPlayers,
		uptime = os.time() - serverStartTime,
		lastUpdated = os.time(),
	}
	return {
		servers = servers,
		currentServer = currentInfo,
	}
end

requestServerHop.OnServerEvent:Connect(function(player: Player, targetServerId: string)
	ServerHopManager.hopToServer(player, targetServerId)
end)

requestRandomHop.OnServerEvent:Connect(function(player: Player)
	ServerHopManager.hopToRandomServer(player)
end)

-- Update registration when player count changes
Players.PlayerAdded:Connect(function()
	registerServer()
end)

Players.PlayerRemoving:Connect(function()
	task.defer(registerServer) -- defer to get accurate count after removal
end)

return ServerHopManager
```

## Server Hop Configuration

```luau
--!strict
-- ReplicatedStorage/Shared/ServerHopConfig.luau

local ServerHopConfig = {}

-- How often to update server registration (seconds)
ServerHopConfig.RegistrationUpdateInterval = 15

-- TTL for server registration in MemoryStore (seconds)
ServerHopConfig.ServerRegistrationTTL = 60

-- Minimum time between server hops per player (seconds)
ServerHopConfig.HopCooldown = 10

-- Show player count in server list
ServerHopConfig.ShowPlayerCount = true

-- Show server uptime
ServerHopConfig.ShowUptime = true

return ServerHopConfig
```

## Client Server Browser

```luau
--!strict
-- StarterGui/ServerHopUI/ServerBrowser.client.luau
-- Server browser UI with server list, player counts, and join buttons.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local serverHopEvents = ReplicatedStorage:WaitForChild("ServerHopEvents")
local getServerList = serverHopEvents:WaitForChild("GetServerList")
local requestServerHop = serverHopEvents:WaitForChild("RequestServerHop")
local requestRandomHop = serverHopEvents:WaitForChild("RequestRandomHop")
local hopStatus = serverHopEvents:WaitForChild("HopStatus")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ServerBrowser"
screenGui.ResetOnSpawn = false
screenGui.Enabled = false
screenGui.Parent = playerGui

local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(0, 480, 0, 450)
mainFrame.Position = UDim2.new(0.5, -240, 0.5, -225)
mainFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 40)
mainFrame.BorderSizePixel = 0
mainFrame.Parent = screenGui
Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 12)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 40)
title.BackgroundTransparency = 1
title.Text = "Server Browser"
title.TextColor3 = Color3.new(1, 1, 1)
title.Font = Enum.Font.GothamBold
title.TextSize = 20
title.Parent = mainFrame

-- Current server info
local currentLabel = Instance.new("TextLabel")
currentLabel.Size = UDim2.new(1, -20, 0, 20)
currentLabel.Position = UDim2.new(0, 10, 0, 38)
currentLabel.BackgroundTransparency = 1
currentLabel.Text = "Current server: loading..."
currentLabel.TextColor3 = Color3.fromRGB(160, 160, 160)
currentLabel.Font = Enum.Font.Gotham
currentLabel.TextSize = 12
currentLabel.TextXAlignment = Enum.TextXAlignment.Left
currentLabel.Parent = mainFrame

-- Random hop button
local randomBtn = Instance.new("TextButton")
randomBtn.Size = UDim2.new(0, 140, 0, 35)
randomBtn.Position = UDim2.new(0, 10, 0, 65)
randomBtn.BackgroundColor3 = Color3.fromRGB(0, 150, 255)
randomBtn.Text = "Random Server"
randomBtn.TextColor3 = Color3.new(1, 1, 1)
randomBtn.Font = Enum.Font.GothamBold
randomBtn.TextSize = 13
randomBtn.Parent = mainFrame
Instance.new("UICorner", randomBtn).CornerRadius = UDim.new(0, 6)

-- Refresh button
local refreshBtn = Instance.new("TextButton")
refreshBtn.Size = UDim2.new(0, 100, 0, 35)
refreshBtn.Position = UDim2.new(0, 160, 0, 65)
refreshBtn.BackgroundColor3 = Color3.fromRGB(80, 80, 100)
refreshBtn.Text = "Refresh"
refreshBtn.TextColor3 = Color3.new(1, 1, 1)
refreshBtn.Font = Enum.Font.GothamBold
refreshBtn.TextSize = 13
refreshBtn.Parent = mainFrame
Instance.new("UICorner", refreshBtn).CornerRadius = UDim.new(0, 6)

-- Close button
local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 30, 0, 30)
closeBtn.Position = UDim2.new(1, -40, 0, 8)
closeBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
closeBtn.Text = "X"
closeBtn.TextColor3 = Color3.new(1, 1, 1)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 14
closeBtn.Parent = mainFrame
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 6)

-- Server list
local scrollFrame = Instance.new("ScrollingFrame")
scrollFrame.Size = UDim2.new(1, -20, 1, -120)
scrollFrame.Position = UDim2.new(0, 10, 0, 110)
scrollFrame.BackgroundTransparency = 1
scrollFrame.ScrollBarThickness = 6
scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
scrollFrame.Parent = mainFrame

local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 6)
listLayout.Parent = scrollFrame

-- Status label
local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1, 0, 0, 30)
statusLabel.BackgroundTransparency = 1
statusLabel.Text = ""
statusLabel.TextColor3 = Color3.fromRGB(255, 200, 100)
statusLabel.Font = Enum.Font.Gotham
statusLabel.TextSize = 13
statusLabel.Parent = scrollFrame

local function formatUptime(seconds: number): string
	local minutes = math.floor(seconds / 60)
	local hours = math.floor(minutes / 60)
	minutes = minutes % 60
	if hours > 0 then
		return string.format("%dh %dm", hours, minutes)
	end
	return string.format("%dm", minutes)
end

local function refreshServerList()
	for _, child in ipairs(scrollFrame:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end
	statusLabel.Text = "Loading servers..."

	local data = getServerList:InvokeServer()
	if not data then
		statusLabel.Text = "Failed to load servers."
		return
	end

	-- Update current server info
	local current = data.currentServer
	if current then
		currentLabel.Text = string.format("Current: %d/%d players | Uptime: %s | ID: %s",
			current.playerCount, current.maxPlayers,
			formatUptime(current.uptime),
			string.sub(current.serverId, 1, 8))
	end

	local servers = data.servers
	if #servers == 0 then
		statusLabel.Text = "No other servers available."
		return
	end

	statusLabel.Text = ""

	for i, server in ipairs(servers) do
		local card = Instance.new("Frame")
		card.Size = UDim2.new(1, 0, 0, 55)
		card.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
		card.BorderSizePixel = 0
		card.LayoutOrder = i
		card.Parent = scrollFrame
		Instance.new("UICorner", card).CornerRadius = UDim.new(0, 8)

		local serverLabel = Instance.new("TextLabel")
		serverLabel.Size = UDim2.new(0.5, 0, 0, 22)
		serverLabel.Position = UDim2.new(0, 12, 0, 5)
		serverLabel.BackgroundTransparency = 1
		serverLabel.Text = "Server " .. string.sub(server.serverId, 1, 8)
		serverLabel.TextColor3 = Color3.new(1, 1, 1)
		serverLabel.Font = Enum.Font.GothamBold
		serverLabel.TextSize = 13
		serverLabel.TextXAlignment = Enum.TextXAlignment.Left
		serverLabel.Parent = card

		local infoLabel = Instance.new("TextLabel")
		infoLabel.Size = UDim2.new(0.5, 0, 0, 18)
		infoLabel.Position = UDim2.new(0, 12, 0, 28)
		infoLabel.BackgroundTransparency = 1
		infoLabel.Text = string.format("%d/%d players | %s",
			server.playerCount, server.maxPlayers, formatUptime(server.uptime))
		infoLabel.TextColor3 = Color3.fromRGB(160, 160, 160)
		infoLabel.Font = Enum.Font.Gotham
		infoLabel.TextSize = 11
		infoLabel.TextXAlignment = Enum.TextXAlignment.Left
		infoLabel.Parent = card

		-- Player count bar
		local barBg = Instance.new("Frame")
		barBg.Size = UDim2.new(0.2, 0, 0, 8)
		barBg.Position = UDim2.new(0.5, 10, 0.5, -4)
		barBg.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
		barBg.BorderSizePixel = 0
		barBg.Parent = card
		Instance.new("UICorner", barBg).CornerRadius = UDim.new(0, 4)

		local pct = server.playerCount / math.max(server.maxPlayers, 1)
		local barFill = Instance.new("Frame")
		barFill.Size = UDim2.new(math.clamp(pct, 0, 1), 0, 1, 0)
		barFill.BackgroundColor3 = if pct > 0.8 then Color3.fromRGB(255, 80, 80)
			elseif pct > 0.5 then Color3.fromRGB(255, 200, 50)
			else Color3.fromRGB(50, 200, 50)
		barFill.BorderSizePixel = 0
		barFill.Parent = barBg
		Instance.new("UICorner", barFill).CornerRadius = UDim.new(0, 4)

		-- Join button
		local joinBtn = Instance.new("TextButton")
		joinBtn.Size = UDim2.new(0, 70, 0, 30)
		joinBtn.Position = UDim2.new(1, -85, 0.5, -15)
		joinBtn.BackgroundColor3 = if server.playerCount < server.maxPlayers
			then Color3.fromRGB(0, 150, 255)
			else Color3.fromRGB(80, 80, 80)
		joinBtn.Text = if server.playerCount < server.maxPlayers then "Join" else "Full"
		joinBtn.TextColor3 = Color3.new(1, 1, 1)
		joinBtn.Font = Enum.Font.GothamBold
		joinBtn.TextSize = 13
		joinBtn.Parent = card
		Instance.new("UICorner", joinBtn).CornerRadius = UDim.new(0, 6)

		if server.playerCount < server.maxPlayers then
			joinBtn.MouseButton1Click:Connect(function()
				requestServerHop:FireServer(server.serverId)
				joinBtn.Text = "..."
				joinBtn.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
			end)
		end
	end
end

randomBtn.MouseButton1Click:Connect(function()
	requestRandomHop:FireServer()
	randomBtn.Text = "Hopping..."
	randomBtn.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
end)

refreshBtn.MouseButton1Click:Connect(function()
	refreshServerList()
end)

closeBtn.MouseButton1Click:Connect(function()
	screenGui.Enabled = false
end)

hopStatus.OnClientEvent:Connect(function(success: boolean, message: string)
	if not success then
		randomBtn.Text = "Random Server"
		randomBtn.BackgroundColor3 = Color3.fromRGB(0, 150, 255)
		-- Show error briefly
		statusLabel.Text = message
		task.delay(3, function()
			statusLabel.Text = ""
		end)
	end
end)
```

## Usage Guide

1. **Server registry**: servers auto-register in MemoryStoreService every 15 seconds.
2. **Server browser**: client requests `GetServerList` to see available servers.
3. **Join specific server**: `ServerHopManager.hopToServer(player, serverId)`
4. **Random hop**: `ServerHopManager.hopToRandomServer(player)`
5. **Smart hop**: `hopToLeastPopulated()` or `hopToMostPopulated()` for specific needs.

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

- `$REGISTRATION_INTERVAL` (number) -- Seconds between server registration updates. Default: `15`.
- `$REGISTRATION_TTL` (number) -- MemoryStore TTL for server entries. Default: `60`.
- `$HOP_COOLDOWN` (number) -- Seconds between hops per player. Default: `10`.
- `$SHOW_PLAYER_COUNT` (boolean) -- Show player count in browser. Default: `true`.
- `$SHOW_UPTIME` (boolean) -- Show server uptime. Default: `true`.
