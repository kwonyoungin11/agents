---
name: teleport
description: |
  Roblox Teleport system - 텔레포트 서비스, 장소 간 이동, 예약 서버, 텔레포트 UI, 로딩 화면, TeleportService.
  TeleportService between places, reserved servers, teleport UI, and loading screen during teleport.
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Grep
  - Glob
effort: high
---

# Teleport System Skill

Complete TeleportService implementation for teleporting between places, reserved servers, loading screens, and teleport UI.

## Architecture Overview

```
ServerScriptService/
  TeleportManager.server.luau      -- Server-side teleport orchestration
ReplicatedStorage/
  Shared/
    TeleportConfig.luau            -- Place IDs and teleport settings
StarterGui/
  TeleportUI/
    TeleportMenu.client.luau       -- Destination selection UI
    LoadingScreen.client.luau      -- Custom loading screen during teleport
```

## Core Server: TeleportManager

```luau
--!strict
-- ServerScriptService/TeleportManager.server.luau
-- Handles all teleportation: between places, reserved servers, party teleports.

local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TeleportConfig = require(ReplicatedStorage.Shared.TeleportConfig)

------------------------------------------------------------------------
-- Types
------------------------------------------------------------------------

export type TeleportRequest = {
	placeId: number,
	players: { Player },
	useReservedServer: boolean?,
	teleportData: { [string]: any }?,
}

------------------------------------------------------------------------
-- Remote setup
------------------------------------------------------------------------

local teleportFolder = Instance.new("Folder")
teleportFolder.Name = "TeleportEvents"
teleportFolder.Parent = ReplicatedStorage

local requestTeleport = Instance.new("RemoteEvent")
requestTeleport.Name = "RequestTeleport"
requestTeleport.Parent = teleportFolder

local teleportStarted = Instance.new("RemoteEvent")
teleportStarted.Name = "TeleportStarted"
teleportStarted.Parent = teleportFolder

local teleportFailed = Instance.new("RemoteEvent")
teleportFailed.Name = "TeleportFailed"
teleportFailed.Parent = teleportFolder

local getDestinations = Instance.new("RemoteFunction")
getDestinations.Name = "GetDestinations"
getDestinations.Parent = teleportFolder

------------------------------------------------------------------------
-- State
------------------------------------------------------------------------

local teleportCooldowns: { [Player]: number } = {}
local reservedServerCodes: { [number]: string } = {} -- placeId -> code

local TeleportManager = {}

------------------------------------------------------------------------
-- Reserved Servers
------------------------------------------------------------------------

function TeleportManager.getOrCreateReservedServer(placeId: number): string
	if reservedServerCodes[placeId] then
		return reservedServerCodes[placeId]
	end

	local success, code = pcall(function()
		return TeleportService:ReserveServer(placeId)
	end)

	if success and code then
		reservedServerCodes[placeId] = code
		return code
	end

	error("Failed to reserve server for place: " .. tostring(placeId))
end

------------------------------------------------------------------------
-- Teleport Functions
------------------------------------------------------------------------

function TeleportManager.teleportPlayer(player: Player, placeId: number, teleportData: { [string]: any }?)
	-- Cooldown check
	local now = os.time()
	if teleportCooldowns[player] and (now - teleportCooldowns[player]) < TeleportConfig.TeleportCooldown then
		teleportFailed:FireClient(player, "Please wait before teleporting again.")
		return false
	end
	teleportCooldowns[player] = now

	-- Validate destination
	local destination = TeleportConfig.getDestination(placeId)
	if not destination then
		teleportFailed:FireClient(player, "Invalid destination.")
		return false
	end

	-- Notify client to show loading screen
	teleportStarted:FireClient(player, destination.name, destination.description)

	-- Build teleport options
	local teleportOptions = Instance.new("TeleportOptions")
	if teleportData then
		teleportOptions:SetTeleportData(teleportData)
	end

	-- Execute teleport with retry
	local success, err
	for attempt = 1, TeleportConfig.MaxRetries do
		success, err = pcall(function()
			TeleportService:TeleportAsync(placeId, { player }, teleportOptions)
		end)

		if success then break end
		if attempt < TeleportConfig.MaxRetries then
			task.wait(2)
		end
	end

	if not success then
		warn("[TeleportManager] Teleport failed:", err)
		teleportFailed:FireClient(player, "Teleport failed. Please try again.")
		return false
	end

	return true
end

function TeleportManager.teleportParty(players: { Player }, placeId: number, useReserved: boolean?, teleportData: { [string]: any }?)
	-- Notify all players
	local destination = TeleportConfig.getDestination(placeId)
	for _, player in ipairs(players) do
		teleportStarted:FireClient(player, if destination then destination.name else "Unknown", "Teleporting with party...")
	end

	local teleportOptions = Instance.new("TeleportOptions")
	if teleportData then
		teleportOptions:SetTeleportData(teleportData)
	end

	if useReserved then
		local reservedCode = TeleportManager.getOrCreateReservedServer(placeId)
		teleportOptions.ReservedServerAccessCode = reservedCode
	end

	local success, err = pcall(function()
		TeleportService:TeleportAsync(placeId, players, teleportOptions)
	end)

	if not success then
		warn("[TeleportManager] Party teleport failed:", err)
		for _, player in ipairs(players) do
			teleportFailed:FireClient(player, "Party teleport failed.")
		end
		return false
	end

	return true
end

function TeleportManager.teleportToReservedServer(players: { Player }, placeId: number)
	return TeleportManager.teleportParty(players, placeId, true)
end

------------------------------------------------------------------------
-- Arrival Data
------------------------------------------------------------------------

function TeleportManager.getArrivalData(player: Player): { [string]: any }?
	local success, data = pcall(function()
		local joinData = player:GetJoinData()
		return joinData.TeleportData
	end)

	if success then
		return data
	end
	return nil
end

------------------------------------------------------------------------
-- Teleport Failure Handling
------------------------------------------------------------------------

TeleportService.TeleportInitFailed:Connect(function(player: Player, result: Enum.TeleportResult, errorMessage: string, placeId: number, teleportOptions: TeleportOptions)
	warn("[TeleportManager] TeleportInitFailed for", player.Name, ":", errorMessage)

	if result == Enum.TeleportResult.Flooded then
		-- Server is full, retry after delay
		task.delay(5, function()
			if player.Parent then
				TeleportManager.teleportPlayer(player, placeId)
			end
		end)
	elseif result == Enum.TeleportResult.Failure then
		teleportFailed:FireClient(player, "Teleport failed: " .. errorMessage)
	end
end)

------------------------------------------------------------------------
-- Remote Handlers
------------------------------------------------------------------------

requestTeleport.OnServerEvent:Connect(function(player: Player, placeId: number)
	TeleportManager.teleportPlayer(player, placeId)
end)

getDestinations.OnServerInvoke = function(player: Player)
	local destinations = {}
	for _, dest in ipairs(TeleportConfig.Destinations) do
		table.insert(destinations, {
			placeId = dest.placeId,
			name = dest.name,
			description = dest.description,
			icon = dest.icon,
			playerCount = dest.playerCount,
		})
	end
	return destinations
end

------------------------------------------------------------------------
-- Cleanup
------------------------------------------------------------------------

Players.PlayerRemoving:Connect(function(player: Player)
	teleportCooldowns[player] = nil
end)

return TeleportManager
```

## Teleport Configuration

```luau
--!strict
-- ReplicatedStorage/Shared/TeleportConfig.luau

local TeleportConfig = {}

export type Destination = {
	placeId: number,
	name: string,
	description: string,
	icon: string?,
	playerCount: number?,
}

-- Replace with real place IDs from your experience
TeleportConfig.Destinations: { Destination } = {
	{
		placeId = 0,  -- Replace with real place ID
		name = "Lobby",
		description = "Return to the main lobby",
		icon = "",
	},
	{
		placeId = 0,
		name = "Battle Arena",
		description = "Fight against other players",
		icon = "",
	},
	{
		placeId = 0,
		name = "Minigames",
		description = "Play fun minigames",
		icon = "",
	},
}

function TeleportConfig.getDestination(placeId: number): Destination?
	for _, dest in ipairs(TeleportConfig.Destinations) do
		if dest.placeId == placeId then
			return dest
		end
	end
	return nil
end

TeleportConfig.TeleportCooldown = 5     -- Seconds between teleport attempts
TeleportConfig.MaxRetries = 3           -- Retry count on failure
TeleportConfig.LoadingScreenDuration = 3 -- Min loading screen display time

return TeleportConfig
```

## Client Loading Screen

```luau
--!strict
-- StarterGui/TeleportUI/LoadingScreen.client.luau
-- Custom loading screen shown during teleport.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local teleportEvents = ReplicatedStorage:WaitForChild("TeleportEvents")
local teleportStarted = teleportEvents:WaitForChild("TeleportStarted")
local teleportFailed = teleportEvents:WaitForChild("TeleportFailed")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Build loading screen
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "TeleportLoadingScreen"
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 100
screenGui.IgnoreGuiInset = true
screenGui.Enabled = false
screenGui.Parent = playerGui

local background = Instance.new("Frame")
background.Size = UDim2.new(1, 0, 1, 0)
background.BackgroundColor3 = Color3.fromRGB(15, 15, 25)
background.BackgroundTransparency = 0
background.BorderSizePixel = 0
background.Parent = screenGui

local destinationLabel = Instance.new("TextLabel")
destinationLabel.Size = UDim2.new(1, 0, 0, 40)
destinationLabel.Position = UDim2.new(0, 0, 0.4, 0)
destinationLabel.BackgroundTransparency = 1
destinationLabel.Text = "Loading..."
destinationLabel.TextColor3 = Color3.new(1, 1, 1)
destinationLabel.Font = Enum.Font.GothamBold
destinationLabel.TextSize = 28
destinationLabel.Parent = background

local descLabel = Instance.new("TextLabel")
descLabel.Size = UDim2.new(1, 0, 0, 24)
descLabel.Position = UDim2.new(0, 0, 0.4, 45)
descLabel.BackgroundTransparency = 1
descLabel.Text = ""
descLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
descLabel.Font = Enum.Font.Gotham
descLabel.TextSize = 16
descLabel.Parent = background

-- Spinner
local spinner = Instance.new("Frame")
spinner.Size = UDim2.new(0, 40, 0, 40)
spinner.Position = UDim2.new(0.5, -20, 0.55, 0)
spinner.BackgroundColor3 = Color3.new(1, 1, 1)
spinner.BackgroundTransparency = 0.5
spinner.BorderSizePixel = 0
spinner.Parent = background
Instance.new("UICorner", spinner).CornerRadius = UDim.new(0, 20)

-- Animate spinner rotation
task.spawn(function()
	local angle = 0
	while true do
		angle += 5
		spinner.Rotation = angle
		task.wait(0.03)
	end
end)

-- Tip text
local tipLabel = Instance.new("TextLabel")
tipLabel.Size = UDim2.new(0.8, 0, 0, 20)
tipLabel.Position = UDim2.new(0.1, 0, 0.85, 0)
tipLabel.BackgroundTransparency = 1
tipLabel.TextColor3 = Color3.fromRGB(130, 130, 130)
tipLabel.Font = Enum.Font.Gotham
tipLabel.TextSize = 13
tipLabel.Parent = background

local tips = {
	"Tip: Join a team for bonus XP!",
	"Tip: Visit the shop for exclusive items.",
	"Tip: Invite friends for extra rewards!",
	"Tip: Check daily rewards every day.",
}
tipLabel.Text = tips[math.random(1, #tips)]

teleportStarted.OnClientEvent:Connect(function(destName: string, destDesc: string?)
	destinationLabel.Text = "Traveling to " .. destName .. "..."
	descLabel.Text = destDesc or ""
	background.BackgroundTransparency = 1
	screenGui.Enabled = true

	-- Fade in
	TweenService:Create(background, TweenInfo.new(0.5), {
		BackgroundTransparency = 0,
	}):Play()
end)

teleportFailed.OnClientEvent:Connect(function(reason: string)
	destinationLabel.Text = "Teleport Failed"
	descLabel.Text = reason

	task.wait(3)

	-- Fade out
	local tween = TweenService:Create(background, TweenInfo.new(0.5), {
		BackgroundTransparency = 1,
	})
	tween:Play()
	tween.Completed:Wait()
	screenGui.Enabled = false
end)
```

## Client Teleport Menu

```luau
--!strict
-- StarterGui/TeleportUI/TeleportMenu.client.luau
-- Destination selection UI for teleporting between places.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local teleportEvents = ReplicatedStorage:WaitForChild("TeleportEvents")
local requestTeleport = teleportEvents:WaitForChild("RequestTeleport")
local getDestinations = teleportEvents:WaitForChild("GetDestinations")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "TeleportMenu"
screenGui.ResetOnSpawn = false
screenGui.Enabled = false
screenGui.Parent = playerGui

local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(0, 400, 0, 380)
mainFrame.Position = UDim2.new(0.5, -200, 0.5, -190)
mainFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 40)
mainFrame.BorderSizePixel = 0
mainFrame.Parent = screenGui
Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 12)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 40)
title.BackgroundTransparency = 1
title.Text = "Select Destination"
title.TextColor3 = Color3.new(1, 1, 1)
title.Font = Enum.Font.GothamBold
title.TextSize = 20
title.Parent = mainFrame

local scrollFrame = Instance.new("ScrollingFrame")
scrollFrame.Size = UDim2.new(1, -20, 1, -55)
scrollFrame.Position = UDim2.new(0, 10, 0, 48)
scrollFrame.BackgroundTransparency = 1
scrollFrame.ScrollBarThickness = 6
scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
scrollFrame.Parent = mainFrame

local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 8)
listLayout.Parent = scrollFrame

local function loadDestinations()
	for _, child in ipairs(scrollFrame:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end

	local destinations = getDestinations:InvokeServer()
	if not destinations then return end

	for _, dest in ipairs(destinations) do
		local card = Instance.new("Frame")
		card.Size = UDim2.new(1, 0, 0, 70)
		card.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
		card.BorderSizePixel = 0
		card.Parent = scrollFrame
		Instance.new("UICorner", card).CornerRadius = UDim.new(0, 8)

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Size = UDim2.new(0.6, 0, 0, 24)
		nameLabel.Position = UDim2.new(0, 12, 0, 8)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Text = dest.name
		nameLabel.TextColor3 = Color3.new(1, 1, 1)
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.TextSize = 16
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.Parent = card

		local descLbl = Instance.new("TextLabel")
		descLbl.Size = UDim2.new(0.6, 0, 0, 18)
		descLbl.Position = UDim2.new(0, 12, 0, 32)
		descLbl.BackgroundTransparency = 1
		descLbl.Text = dest.description
		descLbl.TextColor3 = Color3.fromRGB(160, 160, 160)
		descLbl.Font = Enum.Font.Gotham
		descLbl.TextSize = 12
		descLbl.TextXAlignment = Enum.TextXAlignment.Left
		descLbl.Parent = card

		local teleportBtn = Instance.new("TextButton")
		teleportBtn.Size = UDim2.new(0, 90, 0, 35)
		teleportBtn.Position = UDim2.new(1, -105, 0.5, -17)
		teleportBtn.BackgroundColor3 = Color3.fromRGB(0, 150, 255)
		teleportBtn.Text = "Teleport"
		teleportBtn.TextColor3 = Color3.new(1, 1, 1)
		teleportBtn.Font = Enum.Font.GothamBold
		teleportBtn.TextSize = 14
		teleportBtn.Parent = card
		Instance.new("UICorner", teleportBtn).CornerRadius = UDim.new(0, 6)

		teleportBtn.MouseButton1Click:Connect(function()
			requestTeleport:FireServer(dest.placeId)
			teleportBtn.Text = "..."
			teleportBtn.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
		end)
	end
end
```

## Usage Guide

1. **Set real place IDs** in `TeleportConfig.Destinations`.
2. **Teleport a single player**: `TeleportManager.teleportPlayer(player, placeId)`
3. **Party teleport**: `TeleportManager.teleportParty({player1, player2}, placeId, true)`
4. **Reserved servers**: `TeleportManager.teleportToReservedServer({player}, placeId)`
5. **Read arrival data**: `TeleportManager.getArrivalData(player)` on the destination server.
6. **Custom loading screen** displays automatically during teleport.

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

- `$DESTINATIONS` (table) -- List of teleport destinations with place IDs.
- `$TELEPORT_COOLDOWN` (number) -- Seconds between teleport attempts. Default: `5`.
- `$MAX_RETRIES` (number) -- Retry count on teleport failure. Default: `3`.
- `$LOADING_TIPS` (string[]) -- Tips shown on the loading screen.
- `$ENABLE_RESERVED_SERVERS` (boolean) -- Enable reserved server creation. Default: `true`.
- `$LOADING_SCREEN_DURATION` (number) -- Minimum loading screen time. Default: `3`.
