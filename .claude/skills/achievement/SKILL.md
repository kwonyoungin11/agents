---
name: achievement
description: |
  Roblox Achievement system - 업적 시스템, 조건 추적, 배지 부여 (BadgeService), 업적 팝업, 진행도 추적.
  Achievement condition tracking, badge granting via BadgeService, achievement popup UI, and progress tracking.
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Grep
  - Glob
effort: high
---

# Achievement System Skill

Complete achievement system with condition tracking, badge granting, popup notifications, and persistent progress.

## Architecture Overview

```
ServerScriptService/
  AchievementManager.server.luau   -- Core logic, condition evaluation, badge granting
ServerStorage/
  AchievementDefinitions.luau      -- Achievement registry
ReplicatedStorage/
  Shared/
    AchievementTypes.luau          -- Shared types
StarterGui/
  AchievementUI/
    AchievementPopup.client.luau   -- Popup notification
    AchievementList.client.luau    -- Achievement browser
```

## Core Server: AchievementManager

```luau
--!strict
-- ServerScriptService/AchievementManager.server.luau
-- Tracks player progress, evaluates conditions, grants badges.

local Players = game:GetService("Players")
local BadgeService = game:GetService("BadgeService")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local achievementStore = DataStoreService:GetDataStore("AchievementProgress_v1")

------------------------------------------------------------------------
-- Types
------------------------------------------------------------------------

export type AchievementCondition = {
	stat: string,           -- which stat to track (e.g., "kills", "playtime", "coins")
	target: number,         -- value required to unlock
	comparison: "gte" | "eq" | "lte"?,  -- default: "gte"
}

export type AchievementDef = {
	id: string,
	name: string,
	description: string,
	icon: string?,           -- asset ID for icon
	badgeId: number?,        -- Roblox badge to award
	conditions: { AchievementCondition },
	reward: {
		currency: number?,
		items: { string }?,
	}?,
	hidden: boolean?,        -- hide until unlocked
}

export type PlayerProgress = {
	stats: { [string]: number },
	unlocked: { [string]: boolean },
}

------------------------------------------------------------------------
-- Remote setup
------------------------------------------------------------------------

local achievementFolder = Instance.new("Folder")
achievementFolder.Name = "AchievementEvents"
achievementFolder.Parent = ReplicatedStorage

local achievementUnlocked = Instance.new("RemoteEvent")
achievementUnlocked.Name = "AchievementUnlocked"
achievementUnlocked.Parent = achievementFolder

local progressUpdated = Instance.new("RemoteEvent")
progressUpdated.Name = "ProgressUpdated"
progressUpdated.Parent = achievementFolder

local requestProgress = Instance.new("RemoteFunction")
requestProgress.Name = "RequestProgress"
requestProgress.Parent = achievementFolder

------------------------------------------------------------------------
-- Achievement Definitions
------------------------------------------------------------------------

local achievements: { AchievementDef } = {
	{
		id = "first_kill",
		name = "First Blood",
		description = "Defeat your first enemy",
		badgeId = 0, -- Replace with real badge ID
		conditions = { { stat = "kills", target = 1 } },
		reward = { currency = 100 },
	},
	{
		id = "play_1_hour",
		name = "Dedicated Player",
		description = "Play for 1 hour total",
		badgeId = 0,
		conditions = { { stat = "playtime_minutes", target = 60 } },
		reward = { currency = 500 },
	},
	{
		id = "collect_100_coins",
		name = "Coin Collector",
		description = "Collect 100 coins",
		badgeId = 0,
		conditions = { { stat = "coins_collected", target = 100 } },
		reward = { currency = 200 },
	},
	{
		id = "win_10_games",
		name = "Champion",
		description = "Win 10 games",
		badgeId = 0,
		conditions = { { stat = "wins", target = 10 } },
		reward = { currency = 1000 },
	},
	{
		id = "reach_level_10",
		name = "Seasoned Veteran",
		description = "Reach level 10",
		badgeId = 0,
		conditions = { { stat = "level", target = 10 } },
		hidden = true,
	},
}

local achievementMap: { [string]: AchievementDef } = {}
for _, def in ipairs(achievements) do
	achievementMap[def.id] = def
end

------------------------------------------------------------------------
-- Player Data
------------------------------------------------------------------------

local playerProgress: { [Player]: PlayerProgress } = {}

local function loadProgress(player: Player): PlayerProgress
	local success, data = pcall(function()
		return achievementStore:GetAsync("progress_" .. tostring(player.UserId))
	end)

	if success and data then
		return data :: PlayerProgress
	end

	return {
		stats = {},
		unlocked = {},
	}
end

local function saveProgress(player: Player)
	local progress = playerProgress[player]
	if not progress then return end

	pcall(function()
		achievementStore:SetAsync("progress_" .. tostring(player.UserId), progress)
	end)
end

------------------------------------------------------------------------
-- Condition Evaluation
------------------------------------------------------------------------

local function evaluateCondition(condition: AchievementCondition, stats: { [string]: number }): boolean
	local value = stats[condition.stat] or 0
	local comparison = condition.comparison or "gte"

	if comparison == "gte" then
		return value >= condition.target
	elseif comparison == "eq" then
		return value == condition.target
	elseif comparison == "lte" then
		return value <= condition.target
	end
	return false
end

local function checkAchievement(player: Player, achievementId: string): boolean
	local def = achievementMap[achievementId]
	if not def then return false end

	local progress = playerProgress[player]
	if not progress then return false end

	-- Already unlocked
	if progress.unlocked[achievementId] then return false end

	-- Check all conditions
	for _, condition in ipairs(def.conditions) do
		if not evaluateCondition(condition, progress.stats) then
			return false
		end
	end

	return true
end

------------------------------------------------------------------------
-- Core API
------------------------------------------------------------------------

local AchievementManager = {}

function AchievementManager.incrementStat(player: Player, stat: string, amount: number?)
	local progress = playerProgress[player]
	if not progress then return end

	local increment = amount or 1
	progress.stats[stat] = (progress.stats[stat] or 0) + increment

	-- Notify client of progress update
	progressUpdated:FireClient(player, stat, progress.stats[stat])

	-- Check all achievements that use this stat
	for _, def in ipairs(achievements) do
		for _, condition in ipairs(def.conditions) do
			if condition.stat == stat then
				if checkAchievement(player, def.id) then
					AchievementManager.unlock(player, def.id)
				end
				break
			end
		end
	end
end

function AchievementManager.setStat(player: Player, stat: string, value: number)
	local progress = playerProgress[player]
	if not progress then return end

	progress.stats[stat] = value
	progressUpdated:FireClient(player, stat, value)

	-- Check relevant achievements
	for _, def in ipairs(achievements) do
		for _, condition in ipairs(def.conditions) do
			if condition.stat == stat then
				if checkAchievement(player, def.id) then
					AchievementManager.unlock(player, def.id)
				end
				break
			end
		end
	end
end

function AchievementManager.unlock(player: Player, achievementId: string)
	local def = achievementMap[achievementId]
	if not def then return end

	local progress = playerProgress[player]
	if not progress or progress.unlocked[achievementId] then return end

	-- Mark as unlocked
	progress.unlocked[achievementId] = true

	-- Grant badge via BadgeService
	if def.badgeId and def.badgeId > 0 then
		local success, err = pcall(function()
			BadgeService:AwardBadge(player.UserId, def.badgeId)
		end)
		if not success then
			warn("[Achievement] Badge award failed:", err)
		end
	end

	-- Grant rewards
	if def.reward then
		if def.reward.currency then
			-- TODO: integrate with currency system
			-- CurrencyManager.add(player, def.reward.currency)
		end
		if def.reward.items then
			-- TODO: integrate with inventory system
			-- InventoryManager.addItems(player, def.reward.items)
		end
	end

	-- Notify client for popup
	achievementUnlocked:FireClient(player, {
		id = def.id,
		name = def.name,
		description = def.description,
		icon = def.icon,
	})

	-- Save immediately on unlock
	saveProgress(player)
end

function AchievementManager.getProgress(player: Player, achievementId: string): number?
	local def = achievementMap[achievementId]
	if not def then return nil end

	local progress = playerProgress[player]
	if not progress then return nil end

	-- Return progress fraction for first condition (simple case)
	local condition = def.conditions[1]
	if condition then
		local current = progress.stats[condition.stat] or 0
		return math.clamp(current / condition.target, 0, 1)
	end
	return 0
end

function AchievementManager.isUnlocked(player: Player, achievementId: string): boolean
	local progress = playerProgress[player]
	return if progress then progress.unlocked[achievementId] == true else false
end

------------------------------------------------------------------------
-- Initialization
------------------------------------------------------------------------

Players.PlayerAdded:Connect(function(player: Player)
	local progress = loadProgress(player)
	playerProgress[player] = progress

	-- Track playtime
	task.spawn(function()
		while player.Parent do
			task.wait(60)
			AchievementManager.incrementStat(player, "playtime_minutes", 1)
		end
	end)
end)

Players.PlayerRemoving:Connect(function(player: Player)
	saveProgress(player)
	playerProgress[player] = nil
end)

requestProgress.OnServerInvoke = function(player: Player)
	local progress = playerProgress[player]
	if not progress then return {} end

	local result = {}
	for _, def in ipairs(achievements) do
		if not def.hidden or progress.unlocked[def.id] then
			local condition = def.conditions[1]
			local current = if condition then (progress.stats[condition.stat] or 0) else 0
			local target = if condition then condition.target else 1
			table.insert(result, {
				id = def.id,
				name = def.name,
				description = def.description,
				icon = def.icon,
				unlocked = progress.unlocked[def.id] == true,
				progress = current,
				target = target,
				hidden = def.hidden,
			})
		end
	end
	return result
end

return AchievementManager
```

## Client Achievement Popup

```luau
--!strict
-- StarterGui/AchievementUI/AchievementPopup.client.luau
-- Animated popup when an achievement is unlocked.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local achievementEvents = ReplicatedStorage:WaitForChild("AchievementEvents")
local achievementUnlocked = achievementEvents:WaitForChild("AchievementUnlocked")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "AchievementPopup"
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 10
screenGui.Parent = playerGui

local popupQueue: { any } = {}
local isShowing = false

local function showPopup(data: { id: string, name: string, description: string, icon: string? })
	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(0, 340, 0, 80)
	frame.Position = UDim2.new(0.5, -170, 0, -90)
	frame.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
	frame.BorderSizePixel = 0
	frame.Parent = screenGui
	Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10)

	-- Gold accent stripe
	local accent = Instance.new("Frame")
	accent.Size = UDim2.new(0, 4, 1, 0)
	accent.BackgroundColor3 = Color3.fromRGB(255, 215, 0)
	accent.BorderSizePixel = 0
	accent.Parent = frame

	-- Icon placeholder
	if data.icon then
		local icon = Instance.new("ImageLabel")
		icon.Size = UDim2.new(0, 50, 0, 50)
		icon.Position = UDim2.new(0, 15, 0.5, -25)
		icon.BackgroundTransparency = 1
		icon.Image = data.icon
		icon.Parent = frame
	end

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Size = UDim2.new(0, 250, 0, 25)
	titleLabel.Position = UDim2.new(0, 75, 0, 10)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = "Achievement Unlocked!"
	titleLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextSize = 14
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Parent = frame

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(0, 250, 0, 20)
	nameLabel.Position = UDim2.new(0, 75, 0, 33)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = data.name
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 16
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Parent = frame

	local descLabel = Instance.new("TextLabel")
	descLabel.Size = UDim2.new(0, 250, 0, 16)
	descLabel.Position = UDim2.new(0, 75, 0, 53)
	descLabel.BackgroundTransparency = 1
	descLabel.Text = data.description
	descLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
	descLabel.Font = Enum.Font.Gotham
	descLabel.TextSize = 12
	descLabel.TextXAlignment = Enum.TextXAlignment.Left
	descLabel.Parent = frame

	-- Slide in
	local tweenIn = TweenService:Create(frame, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, -170, 0, 20),
	})
	tweenIn:Play()
	tweenIn.Completed:Wait()

	task.wait(3)

	-- Slide out
	local tweenOut = TweenService:Create(frame, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Position = UDim2.new(0.5, -170, 0, -90),
	})
	tweenOut:Play()
	tweenOut.Completed:Wait()
	frame:Destroy()
end

local function processQueue()
	if isShowing then return end
	if #popupQueue == 0 then return end

	isShowing = true
	local data = table.remove(popupQueue, 1)
	showPopup(data)
	isShowing = false

	-- Process next in queue
	if #popupQueue > 0 then
		processQueue()
	end
end

achievementUnlocked.OnClientEvent:Connect(function(data)
	table.insert(popupQueue, data)
	task.spawn(processQueue)
end)
```

## Achievement List UI

```luau
--!strict
-- StarterGui/AchievementUI/AchievementList.client.luau
-- Scrollable list of all achievements with progress bars.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local achievementEvents = ReplicatedStorage:WaitForChild("AchievementEvents")
local requestProgress = achievementEvents:WaitForChild("RequestProgress")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "AchievementList"
screenGui.ResetOnSpawn = false
screenGui.Enabled = false
screenGui.Parent = playerGui

local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(0, 400, 0, 500)
mainFrame.Position = UDim2.new(0.5, -200, 0.5, -250)
mainFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
mainFrame.BorderSizePixel = 0
mainFrame.Parent = screenGui
Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 12)

local titleBar = Instance.new("TextLabel")
titleBar.Size = UDim2.new(1, 0, 0, 45)
titleBar.BackgroundTransparency = 1
titleBar.Text = "Achievements"
titleBar.TextColor3 = Color3.new(1, 1, 1)
titleBar.Font = Enum.Font.GothamBold
titleBar.TextSize = 20
titleBar.Parent = mainFrame

local scrollFrame = Instance.new("ScrollingFrame")
scrollFrame.Size = UDim2.new(1, -20, 1, -55)
scrollFrame.Position = UDim2.new(0, 10, 0, 50)
scrollFrame.BackgroundTransparency = 1
scrollFrame.ScrollBarThickness = 6
scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
scrollFrame.Parent = mainFrame

local listLayout = Instance.new("UIListLayout")
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Padding = UDim.new(0, 6)
listLayout.Parent = scrollFrame

local function createEntry(data: { [string]: any })
	local entry = Instance.new("Frame")
	entry.Size = UDim2.new(1, 0, 0, 70)
	entry.BackgroundColor3 = if data.unlocked then Color3.fromRGB(40, 55, 40) else Color3.fromRGB(40, 40, 50)
	entry.BorderSizePixel = 0
	entry.Parent = scrollFrame
	Instance.new("UICorner", entry).CornerRadius = UDim.new(0, 8)

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, -20, 0, 22)
	nameLabel.Position = UDim2.new(0, 10, 0, 5)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = if data.unlocked then data.name .. " [UNLOCKED]" else data.name
	nameLabel.TextColor3 = if data.unlocked then Color3.fromRGB(100, 255, 100) else Color3.new(1, 1, 1)
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 14
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Parent = entry

	local descLabel = Instance.new("TextLabel")
	descLabel.Size = UDim2.new(1, -20, 0, 16)
	descLabel.Position = UDim2.new(0, 10, 0, 27)
	descLabel.BackgroundTransparency = 1
	descLabel.Text = data.description
	descLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
	descLabel.Font = Enum.Font.Gotham
	descLabel.TextSize = 12
	descLabel.TextXAlignment = Enum.TextXAlignment.Left
	descLabel.Parent = entry

	-- Progress bar
	if not data.unlocked then
		local barBg = Instance.new("Frame")
		barBg.Size = UDim2.new(0.8, 0, 0, 10)
		barBg.Position = UDim2.new(0.1, 0, 0, 50)
		barBg.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
		barBg.BorderSizePixel = 0
		barBg.Parent = entry
		Instance.new("UICorner", barBg).CornerRadius = UDim.new(0, 5)

		local barFill = Instance.new("Frame")
		local pct = math.clamp(data.progress / data.target, 0, 1)
		barFill.Size = UDim2.new(pct, 0, 1, 0)
		barFill.BackgroundColor3 = Color3.fromRGB(0, 170, 255)
		barFill.BorderSizePixel = 0
		barFill.Parent = barBg
		Instance.new("UICorner", barFill).CornerRadius = UDim.new(0, 5)

		local progressLabel = Instance.new("TextLabel")
		progressLabel.Size = UDim2.new(1, 0, 1, 0)
		progressLabel.BackgroundTransparency = 1
		progressLabel.Text = tostring(data.progress) .. "/" .. tostring(data.target)
		progressLabel.TextColor3 = Color3.new(1, 1, 1)
		progressLabel.Font = Enum.Font.Gotham
		progressLabel.TextSize = 8
		progressLabel.Parent = barBg
	end
end

local function refresh()
	for _, child in ipairs(scrollFrame:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end

	local data = requestProgress:InvokeServer()
	if data then
		for _, entry in ipairs(data) do
			createEntry(entry)
		end
	end
end

-- Toggle visibility (bind to a button or keybind)
-- refresh() when opened
```

## Usage Guide

1. **Increment stats** from game scripts: `AchievementManager.incrementStat(player, "kills", 1)`
2. **Set stats** directly: `AchievementManager.setStat(player, "level", 10)`
3. **Add achievements** by editing the `achievements` table -- set real `badgeId` values.
4. **Multi-condition achievements**: add multiple entries to the `conditions` array.
5. **Hidden achievements**: set `hidden = true` to hide until unlocked.

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

- `$GAME_ID` (number) -- Your game/experience ID for BadgeService. Required for badge granting.
- `$ACHIEVEMENTS` (table) -- List of achievement definitions to register.
- `$DATASTORE_NAME` (string) -- DataStore name for progress persistence. Default: `"AchievementProgress_v1"`.
- `$POPUP_DURATION` (number) -- Seconds popup stays visible. Default: `3`.
- `$AUTO_SAVE_INTERVAL` (number) -- Seconds between auto-saves. Default: `60`.
- `$TRACK_PLAYTIME` (boolean) -- Automatically track playtime as a stat. Default: `true`.
