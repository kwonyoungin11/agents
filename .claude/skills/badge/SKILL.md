---
name: badge
description: |
  Roblox Badge system - 배지 서비스, 배지 지급, 배지 소유 확인, 배지 표시 UI, BadgeService 활용.
  BadgeService integration, award badges on achievement, check ownership, and badge display UI.
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Grep
  - Glob
effort: high
---

# Badge System Skill

Complete BadgeService integration with badge awarding, ownership checking, and display UI.

## Architecture Overview

```
ServerScriptService/
  BadgeManager.server.luau         -- BadgeService wrapper, award logic, ownership cache
ReplicatedStorage/
  Shared/
    BadgeConfig.luau               -- Badge ID definitions and metadata
StarterGui/
  BadgeUI/
    BadgeDisplay.client.luau       -- Badge collection display
    BadgeNotification.client.luau  -- Badge earned popup
```

## Core Server: BadgeManager

```luau
--!strict
-- ServerScriptService/BadgeManager.server.luau
-- Centralized BadgeService wrapper with caching and batch operations.

local Players = game:GetService("Players")
local BadgeService = game:GetService("BadgeService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BadgeConfig = require(ReplicatedStorage.Shared.BadgeConfig)

------------------------------------------------------------------------
-- Types
------------------------------------------------------------------------

export type BadgeDef = {
	id: number,
	name: string,
	description: string,
	icon: string?,
	category: string?,
	rarity: "common" | "uncommon" | "rare" | "epic" | "legendary"?,
}

------------------------------------------------------------------------
-- Remote setup
------------------------------------------------------------------------

local badgeFolder = Instance.new("Folder")
badgeFolder.Name = "BadgeEvents"
badgeFolder.Parent = ReplicatedStorage

local badgeAwarded = Instance.new("RemoteEvent")
badgeAwarded.Name = "BadgeAwarded"
badgeAwarded.Parent = badgeFolder

local getBadges = Instance.new("RemoteFunction")
getBadges.Name = "GetBadges"
getBadges.Parent = badgeFolder

------------------------------------------------------------------------
-- State
------------------------------------------------------------------------

-- Cache: userId -> { badgeId -> owned }
local ownershipCache: { [number]: { [number]: boolean } } = {}
local awardCooldown: { [string]: number } = {}  -- "userId_badgeId" -> timestamp

local BadgeManager = {}

------------------------------------------------------------------------
-- Ownership Checking
------------------------------------------------------------------------

function BadgeManager.checkOwnership(player: Player, badgeId: number): boolean
	local userId = player.UserId

	-- Check cache
	if ownershipCache[userId] and ownershipCache[userId][badgeId] ~= nil then
		return ownershipCache[userId][badgeId]
	end

	-- Query BadgeService
	local success, owns = pcall(function()
		return BadgeService:UserOwnsGamePassAsync(userId, badgeId)
	end)

	-- Fallback to CheckUserBadgesAsync for actual badges
	if not success then
		success, owns = pcall(function()
			local result = BadgeService:GetBadgeInfoAsync(badgeId)
			if result and result.IsEnabled then
				return BadgeService:UserHasBadgeAsync(userId, badgeId)
			end
			return false
		end)
	end

	if success then
		if not ownershipCache[userId] then
			ownershipCache[userId] = {}
		end
		ownershipCache[userId][badgeId] = owns or false
		return owns or false
	end

	warn("[BadgeManager] Failed to check ownership for badge:", badgeId)
	return false
end

function BadgeManager.checkMultipleOwnership(player: Player, badgeIds: { number }): { [number]: boolean }
	local results: { [number]: boolean } = {}
	for _, badgeId in ipairs(badgeIds) do
		results[badgeId] = BadgeManager.checkOwnership(player, badgeId)
	end
	return results
end

------------------------------------------------------------------------
-- Badge Awarding
------------------------------------------------------------------------

function BadgeManager.awardBadge(player: Player, badgeId: number): boolean
	local userId = player.UserId

	-- Cooldown check (prevent spam)
	local cooldownKey = tostring(userId) .. "_" .. tostring(badgeId)
	local now = os.time()
	if awardCooldown[cooldownKey] and (now - awardCooldown[cooldownKey]) < 5 then
		return false
	end
	awardCooldown[cooldownKey] = now

	-- Check if already owned
	if BadgeManager.checkOwnership(player, badgeId) then
		return false  -- Already has badge
	end

	-- Award badge
	local success, err = pcall(function()
		BadgeService:AwardBadge(userId, badgeId)
	end)

	if success then
		-- Update cache
		if not ownershipCache[userId] then
			ownershipCache[userId] = {}
		end
		ownershipCache[userId][badgeId] = true

		-- Find badge definition for notification
		local badgeDef = BadgeConfig.getBadgeById(badgeId)

		-- Notify client
		badgeAwarded:FireClient(player, {
			id = badgeId,
			name = if badgeDef then badgeDef.name else "Badge",
			description = if badgeDef then badgeDef.description else "",
			icon = if badgeDef then badgeDef.icon else nil,
			rarity = if badgeDef then badgeDef.rarity else "common",
		})

		return true
	else
		warn("[BadgeManager] Failed to award badge:", badgeId, err)
		return false
	end
end

function BadgeManager.awardBadgeByName(player: Player, badgeName: string): boolean
	local badgeDef = BadgeConfig.getBadgeByName(badgeName)
	if not badgeDef then
		warn("[BadgeManager] Badge not found by name:", badgeName)
		return false
	end
	return BadgeManager.awardBadge(player, badgeDef.id)
end

------------------------------------------------------------------------
-- Batch Operations
------------------------------------------------------------------------

function BadgeManager.getPlayerBadgeCollection(player: Player): { { id: number, name: string, owned: boolean, rarity: string? } }
	local collection = {}

	for _, badgeDef in ipairs(BadgeConfig.Badges) do
		local owned = BadgeManager.checkOwnership(player, badgeDef.id)
		table.insert(collection, {
			id = badgeDef.id,
			name = badgeDef.name,
			description = badgeDef.description,
			icon = badgeDef.icon,
			category = badgeDef.category,
			rarity = badgeDef.rarity,
			owned = owned,
		})
	end

	return collection
end

function BadgeManager.getOwnedCount(player: Player): (number, number)
	local owned = 0
	local total = #BadgeConfig.Badges

	for _, badgeDef in ipairs(BadgeConfig.Badges) do
		if BadgeManager.checkOwnership(player, badgeDef.id) then
			owned += 1
		end
	end

	return owned, total
end

------------------------------------------------------------------------
-- Remote Handlers
------------------------------------------------------------------------

getBadges.OnServerInvoke = function(player: Player)
	return BadgeManager.getPlayerBadgeCollection(player)
end

------------------------------------------------------------------------
-- Cleanup
------------------------------------------------------------------------

Players.PlayerRemoving:Connect(function(player: Player)
	ownershipCache[player.UserId] = nil
end)

return BadgeManager
```

## Badge Configuration

```luau
--!strict
-- ReplicatedStorage/Shared/BadgeConfig.luau

local BadgeConfig = {}

export type BadgeDef = {
	id: number,
	name: string,
	description: string,
	icon: string?,
	category: string?,
	rarity: "common" | "uncommon" | "rare" | "epic" | "legendary"?,
}

-- Replace badge IDs with real ones from Roblox Creator Dashboard
BadgeConfig.Badges: { BadgeDef } = {
	{
		id = 0,  -- Replace with real badge ID
		name = "Welcome",
		description = "Join the game for the first time",
		icon = "",
		category = "General",
		rarity = "common",
	},
	{
		id = 0,
		name = "First Win",
		description = "Win your first game",
		category = "Combat",
		rarity = "uncommon",
	},
	{
		id = 0,
		name = "Veteran",
		description = "Play for 10 hours total",
		category = "General",
		rarity = "rare",
	},
	{
		id = 0,
		name = "Undefeated",
		description = "Win 10 games in a row",
		category = "Combat",
		rarity = "epic",
	},
	{
		id = 0,
		name = "Master",
		description = "Reach maximum level",
		category = "Progression",
		rarity = "legendary",
	},
}

local badgeByIdMap: { [number]: BadgeDef } = {}
local badgeByNameMap: { [string]: BadgeDef } = {}

for _, badge in ipairs(BadgeConfig.Badges) do
	badgeByIdMap[badge.id] = badge
	badgeByNameMap[badge.name:lower()] = badge
end

function BadgeConfig.getBadgeById(id: number): BadgeDef?
	return badgeByIdMap[id]
end

function BadgeConfig.getBadgeByName(name: string): BadgeDef?
	return badgeByNameMap[name:lower()]
end

-- Rarity colors for UI display
BadgeConfig.RarityColors = {
	common = Color3.fromRGB(180, 180, 180),
	uncommon = Color3.fromRGB(30, 255, 0),
	rare = Color3.fromRGB(0, 112, 255),
	epic = Color3.fromRGB(163, 53, 238),
	legendary = Color3.fromRGB(255, 165, 0),
}

return BadgeConfig
```

## Client Badge Notification

```luau
--!strict
-- StarterGui/BadgeUI/BadgeNotification.client.luau
-- Animated popup when a badge is earned.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local badgeEvents = ReplicatedStorage:WaitForChild("BadgeEvents")
local badgeAwarded = badgeEvents:WaitForChild("BadgeAwarded")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "BadgeNotification"
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 15
screenGui.Parent = playerGui

local rarityColors = {
	common = Color3.fromRGB(180, 180, 180),
	uncommon = Color3.fromRGB(30, 255, 0),
	rare = Color3.fromRGB(0, 112, 255),
	epic = Color3.fromRGB(163, 53, 238),
	legendary = Color3.fromRGB(255, 165, 0),
}

local notificationQueue: { any } = {}
local isShowing = false

local function showNotification(data: { [string]: any })
	local rarityColor = rarityColors[data.rarity or "common"] or rarityColors.common

	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(0, 300, 0, 90)
	frame.Position = UDim2.new(0.5, -150, 1, 10)
	frame.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
	frame.BorderSizePixel = 0
	frame.Parent = screenGui
	Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10)

	-- Rarity border
	local stroke = Instance.new("UIStroke")
	stroke.Color = rarityColor
	stroke.Thickness = 2
	stroke.Parent = frame

	-- Icon
	if data.icon and data.icon ~= "" then
		local icon = Instance.new("ImageLabel")
		icon.Size = UDim2.new(0, 55, 0, 55)
		icon.Position = UDim2.new(0, 12, 0.5, -27)
		icon.BackgroundTransparency = 1
		icon.Image = data.icon
		icon.Parent = frame
	end

	local headerLabel = Instance.new("TextLabel")
	headerLabel.Size = UDim2.new(0, 210, 0, 20)
	headerLabel.Position = UDim2.new(0, 78, 0, 10)
	headerLabel.BackgroundTransparency = 1
	headerLabel.Text = "Badge Earned!"
	headerLabel.TextColor3 = rarityColor
	headerLabel.Font = Enum.Font.GothamBold
	headerLabel.TextSize = 13
	headerLabel.TextXAlignment = Enum.TextXAlignment.Left
	headerLabel.Parent = frame

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(0, 210, 0, 22)
	nameLabel.Position = UDim2.new(0, 78, 0, 30)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = data.name or "Badge"
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 16
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Parent = frame

	local descLabel = Instance.new("TextLabel")
	descLabel.Size = UDim2.new(0, 210, 0, 16)
	descLabel.Position = UDim2.new(0, 78, 0, 54)
	descLabel.BackgroundTransparency = 1
	descLabel.Text = data.description or ""
	descLabel.TextColor3 = Color3.fromRGB(160, 160, 160)
	descLabel.Font = Enum.Font.Gotham
	descLabel.TextSize = 11
	descLabel.TextXAlignment = Enum.TextXAlignment.Left
	descLabel.TextTruncate = Enum.TextTruncate.AtEnd
	descLabel.Parent = frame

	-- Animate in from bottom
	local tweenIn = TweenService:Create(frame, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, -150, 1, -110),
	})
	tweenIn:Play()
	tweenIn.Completed:Wait()

	task.wait(4)

	-- Animate out
	local tweenOut = TweenService:Create(frame, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Position = UDim2.new(0.5, -150, 1, 10),
	})
	tweenOut:Play()
	tweenOut.Completed:Wait()
	frame:Destroy()
end

local function processQueue()
	if isShowing then return end
	if #notificationQueue == 0 then return end

	isShowing = true
	local data = table.remove(notificationQueue, 1)
	showNotification(data)
	isShowing = false

	if #notificationQueue > 0 then
		processQueue()
	end
end

badgeAwarded.OnClientEvent:Connect(function(data)
	table.insert(notificationQueue, data)
	task.spawn(processQueue)
end)
```

## Client Badge Display

```luau
--!strict
-- StarterGui/BadgeUI/BadgeDisplay.client.luau
-- Badge collection viewer with grid layout and rarity filtering.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local badgeEvents = ReplicatedStorage:WaitForChild("BadgeEvents")
local getBadges = badgeEvents:WaitForChild("GetBadges")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "BadgeDisplay"
screenGui.ResetOnSpawn = false
screenGui.Enabled = false
screenGui.Parent = playerGui

local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(0, 500, 0, 480)
mainFrame.Position = UDim2.new(0.5, -250, 0.5, -240)
mainFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
mainFrame.BorderSizePixel = 0
mainFrame.Parent = screenGui
Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 12)

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, 0, 0, 40)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "Badge Collection"
titleLabel.TextColor3 = Color3.new(1, 1, 1)
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextSize = 20
titleLabel.Parent = mainFrame

local countLabel = Instance.new("TextLabel")
countLabel.Size = UDim2.new(1, 0, 0, 20)
countLabel.Position = UDim2.new(0, 0, 0, 36)
countLabel.BackgroundTransparency = 1
countLabel.Text = "0 / 0 Collected"
countLabel.TextColor3 = Color3.fromRGB(160, 160, 160)
countLabel.Font = Enum.Font.Gotham
countLabel.TextSize = 13
countLabel.Parent = mainFrame

local scrollFrame = Instance.new("ScrollingFrame")
scrollFrame.Size = UDim2.new(1, -20, 1, -70)
scrollFrame.Position = UDim2.new(0, 10, 0, 60)
scrollFrame.BackgroundTransparency = 1
scrollFrame.ScrollBarThickness = 6
scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
scrollFrame.Parent = mainFrame

local gridLayout = Instance.new("UIGridLayout")
gridLayout.CellSize = UDim2.new(0, 90, 0, 100)
gridLayout.CellPadding = UDim2.new(0, 8, 0, 8)
gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
gridLayout.Parent = scrollFrame

local rarityColors = {
	common = Color3.fromRGB(180, 180, 180),
	uncommon = Color3.fromRGB(30, 255, 0),
	rare = Color3.fromRGB(0, 112, 255),
	epic = Color3.fromRGB(163, 53, 238),
	legendary = Color3.fromRGB(255, 165, 0),
}

local function refresh()
	for _, child in ipairs(scrollFrame:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end

	local badges = getBadges:InvokeServer()
	if not badges then return end

	local ownedCount = 0
	for _, badge in ipairs(badges) do
		if badge.owned then ownedCount += 1 end

		local card = Instance.new("Frame")
		card.BackgroundColor3 = if badge.owned then Color3.fromRGB(40, 45, 55) else Color3.fromRGB(30, 30, 38)
		card.BackgroundTransparency = if badge.owned then 0 else 0.3
		card.BorderSizePixel = 0
		card.Parent = scrollFrame
		Instance.new("UICorner", card).CornerRadius = UDim.new(0, 8)

		if badge.owned then
			local stroke = Instance.new("UIStroke")
			stroke.Color = rarityColors[badge.rarity or "common"] or rarityColors.common
			stroke.Thickness = 1.5
			stroke.Parent = card
		end

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Size = UDim2.new(1, -8, 0, 30)
		nameLabel.Position = UDim2.new(0, 4, 1, -35)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Text = badge.name
		nameLabel.TextColor3 = if badge.owned then Color3.new(1, 1, 1) else Color3.fromRGB(100, 100, 100)
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.TextSize = 10
		nameLabel.TextWrapped = true
		nameLabel.Parent = card

		if not badge.owned then
			local lockLabel = Instance.new("TextLabel")
			lockLabel.Size = UDim2.new(1, 0, 0, 30)
			lockLabel.Position = UDim2.new(0, 0, 0, 15)
			lockLabel.BackgroundTransparency = 1
			lockLabel.Text = "?"
			lockLabel.TextColor3 = Color3.fromRGB(80, 80, 80)
			lockLabel.Font = Enum.Font.GothamBold
			lockLabel.TextSize = 28
			lockLabel.Parent = card
		end
	end

	countLabel.Text = tostring(ownedCount) .. " / " .. tostring(#badges) .. " Collected"
end

-- Call refresh() when the UI is shown
```

## Usage Guide

1. **Award badges** from server scripts:
   ```luau
   local BadgeManager = require(ServerScriptService.BadgeManager)
   BadgeManager.awardBadge(player, 123456)
   BadgeManager.awardBadgeByName(player, "First Win")
   ```
2. **Check ownership**: `BadgeManager.checkOwnership(player, badgeId)`
3. **Set real badge IDs** in `BadgeConfig.Badges` from the Roblox Creator Dashboard.
4. **Rarity system**: badges display with colored borders based on rarity tier.

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

- `$GAME_ID` (number) -- Your game/experience ID for BadgeService.
- `$BADGES` (table) -- Badge definitions with IDs from Creator Dashboard.
- `$RARITY_COLORS` (table) -- Color3 values for each rarity tier.
- `$NOTIFICATION_DURATION` (number) -- Seconds badge popup stays visible. Default: `4`.
- `$ENABLE_RARITY_BORDERS` (boolean) -- Show colored rarity borders. Default: `true`.
