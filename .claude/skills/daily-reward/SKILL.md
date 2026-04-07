---
name: daily-reward
description: |
  Roblox Daily login reward system - 일일 보상, 출석 체크, 연속 출석, 보상 캘린더 UI, os.time() 기반 보상 수령, 연속 출석 리셋.
  Daily login rewards, streak system, reward calendar UI, os.time() claim, and streak reset logic.
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Grep
  - Glob
effort: high
---

# Daily Reward System Skill

Complete daily login reward system with streaks, calendar UI, and persistent tracking via DataStore.

## Architecture Overview

```
ServerScriptService/
  DailyRewardManager.server.luau   -- Server logic, claim validation, streak tracking
ReplicatedStorage/
  Shared/
    DailyRewardConfig.luau         -- Reward definitions per day
StarterGui/
  DailyRewardUI/
    RewardCalendar.client.luau     -- Calendar grid UI with claim button
```

## Core Server: DailyRewardManager

```luau
--!strict
-- ServerScriptService/DailyRewardManager.server.luau
-- Manages daily reward claims, streak tracking, and reward distribution.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DailyRewardConfig = require(ReplicatedStorage.Shared.DailyRewardConfig)

local rewardStore = DataStoreService:GetDataStore("DailyRewards_v1")

------------------------------------------------------------------------
-- Types
------------------------------------------------------------------------

export type PlayerRewardData = {
	lastClaimTime: number,    -- os.time() of last claim
	currentStreak: number,    -- consecutive days claimed
	totalDaysClaimed: number, -- lifetime total
	claimedToday: boolean,    -- already claimed this session
}

------------------------------------------------------------------------
-- Constants
------------------------------------------------------------------------

local SECONDS_PER_DAY = 86400
local STREAK_GRACE_HOURS = 36  -- hours before streak resets (allows late claim)
local STREAK_GRACE_SECONDS = STREAK_GRACE_HOURS * 3600

------------------------------------------------------------------------
-- Remote setup
------------------------------------------------------------------------

local rewardFolder = Instance.new("Folder")
rewardFolder.Name = "DailyRewardEvents"
rewardFolder.Parent = ReplicatedStorage

local claimReward = Instance.new("RemoteFunction")
claimReward.Name = "ClaimReward"
claimReward.Parent = rewardFolder

local getRewardData = Instance.new("RemoteFunction")
getRewardData.Name = "GetRewardData"
getRewardData.Parent = rewardFolder

local rewardClaimed = Instance.new("RemoteEvent")
rewardClaimed.Name = "RewardClaimed"
rewardClaimed.Parent = rewardFolder

------------------------------------------------------------------------
-- State
------------------------------------------------------------------------

local playerRewardData: { [Player]: PlayerRewardData } = {}

------------------------------------------------------------------------
-- Data persistence
------------------------------------------------------------------------

local function loadRewardData(player: Player): PlayerRewardData
	local success, data = pcall(function()
		return rewardStore:GetAsync("daily_" .. tostring(player.UserId))
	end)

	if success and data then
		-- Check if streak should be reset
		local now = os.time()
		local timeSinceLastClaim = now - (data.lastClaimTime or 0)

		if timeSinceLastClaim > STREAK_GRACE_SECONDS then
			-- Streak broken -- reset
			data.currentStreak = 0
		end

		-- Determine if already claimed today
		local lastClaimDay = math.floor((data.lastClaimTime or 0) / SECONDS_PER_DAY)
		local currentDay = math.floor(now / SECONDS_PER_DAY)
		data.claimedToday = (lastClaimDay == currentDay)

		return data :: PlayerRewardData
	end

	return {
		lastClaimTime = 0,
		currentStreak = 0,
		totalDaysClaimed = 0,
		claimedToday = false,
	}
end

local function saveRewardData(player: Player)
	local data = playerRewardData[player]
	if not data then return end

	pcall(function()
		rewardStore:SetAsync("daily_" .. tostring(player.UserId), {
			lastClaimTime = data.lastClaimTime,
			currentStreak = data.currentStreak,
			totalDaysClaimed = data.totalDaysClaimed,
		})
	end)
end

------------------------------------------------------------------------
-- Core Logic
------------------------------------------------------------------------

local function canClaim(player: Player): boolean
	local data = playerRewardData[player]
	if not data then return false end
	return not data.claimedToday
end

local function getRewardForDay(streakDay: number): DailyRewardConfig.DayReward
	-- Wrap around the reward cycle
	local cycleLength = #DailyRewardConfig.Rewards
	local dayIndex = ((streakDay - 1) % cycleLength) + 1
	return DailyRewardConfig.Rewards[dayIndex]
end

local function claimDailyReward(player: Player): (boolean, string?, any?)
	local data = playerRewardData[player]
	if not data then
		return false, "Data not loaded", nil
	end

	if data.claimedToday then
		return false, "Already claimed today", nil
	end

	local now = os.time()
	local lastClaimDay = math.floor(data.lastClaimTime / SECONDS_PER_DAY)
	local currentDay = math.floor(now / SECONDS_PER_DAY)

	-- Check minimum time between claims (prevent double-claim exploits)
	if data.lastClaimTime > 0 and (now - data.lastClaimTime) < (SECONDS_PER_DAY * 0.9) then
		return false, "Too soon to claim again", nil
	end

	-- Update streak
	local dayDiff = currentDay - lastClaimDay
	if dayDiff == 1 then
		-- Consecutive day
		data.currentStreak += 1
	elseif dayDiff > 1 or data.lastClaimTime == 0 then
		-- Streak broken or first claim
		data.currentStreak = 1
	end

	-- Get reward for current streak day
	local reward = getRewardForDay(data.currentStreak)

	-- Update data
	data.lastClaimTime = now
	data.totalDaysClaimed += 1
	data.claimedToday = true

	-- Grant reward
	if reward.currency then
		-- TODO: integrate with currency system
		-- CurrencyManager.add(player, reward.currency)
	end
	if reward.items then
		-- TODO: integrate with inventory system
		-- InventoryManager.addItems(player, reward.items)
	end

	-- Apply streak bonus multiplier
	local streakBonus = 1
	if data.currentStreak >= 7 then
		streakBonus = DailyRewardConfig.WeekStreakMultiplier
	elseif data.currentStreak >= 3 then
		streakBonus = DailyRewardConfig.ThreeDayStreakMultiplier
	end

	-- Save
	saveRewardData(player)

	return true, nil, {
		reward = reward,
		streak = data.currentStreak,
		streakBonus = streakBonus,
		totalDays = data.totalDaysClaimed,
	}
end

------------------------------------------------------------------------
-- Remote Handlers
------------------------------------------------------------------------

claimReward.OnServerInvoke = function(player: Player)
	local success, err, result = claimDailyReward(player)
	if success then
		rewardClaimed:FireClient(player, result)
	end
	return success, err, result
end

getRewardData.OnServerInvoke = function(player: Player)
	local data = playerRewardData[player]
	if not data then return nil end

	local rewards = {}
	for i = 1, #DailyRewardConfig.Rewards do
		local r = DailyRewardConfig.Rewards[i]
		table.insert(rewards, {
			day = i,
			currency = r.currency,
			items = r.items,
			description = r.description,
			isClaimed = i <= data.totalDaysClaimed,
			isToday = ((data.currentStreak % #DailyRewardConfig.Rewards) + 1) == i and not data.claimedToday,
		})
	end

	return {
		rewards = rewards,
		currentStreak = data.currentStreak,
		canClaim = not data.claimedToday,
		totalDaysClaimed = data.totalDaysClaimed,
	}
end

------------------------------------------------------------------------
-- Initialization
------------------------------------------------------------------------

Players.PlayerAdded:Connect(function(player: Player)
	local data = loadRewardData(player)
	playerRewardData[player] = data
end)

Players.PlayerRemoving:Connect(function(player: Player)
	saveRewardData(player)
	playerRewardData[player] = nil
end)
```

## Reward Configuration

```luau
--!strict
-- ReplicatedStorage/Shared/DailyRewardConfig.luau

local DailyRewardConfig = {}

export type DayReward = {
	currency: number?,
	items: { string }?,
	description: string,
}

-- 7-day reward cycle (loops after day 7)
DailyRewardConfig.Rewards: { DayReward } = {
	{ currency = 100,  description = "Day 1: 100 Coins" },
	{ currency = 150,  description = "Day 2: 150 Coins" },
	{ currency = 200,  description = "Day 3: 200 Coins" },
	{ currency = 300,  description = "Day 4: 300 Coins" },
	{ currency = 400,  description = "Day 5: 400 Coins" },
	{ currency = 500,  description = "Day 6: 500 Coins" },
	{ currency = 1000, items = { "mystery_box" }, description = "Day 7: 1000 Coins + Mystery Box!" },
}

DailyRewardConfig.ThreeDayStreakMultiplier = 1.25
DailyRewardConfig.WeekStreakMultiplier = 1.5

-- Show daily reward UI automatically on join
DailyRewardConfig.ShowOnJoin = true

-- Delay before showing UI after join (seconds)
DailyRewardConfig.ShowDelay = 2

return DailyRewardConfig
```

## Client Calendar UI

```luau
--!strict
-- StarterGui/DailyRewardUI/RewardCalendar.client.luau
-- Displays a 7-day reward calendar with claim button and streak info.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local rewardEvents = ReplicatedStorage:WaitForChild("DailyRewardEvents")
local claimReward = rewardEvents:WaitForChild("ClaimReward")
local getRewardData = rewardEvents:WaitForChild("GetRewardData")
local rewardClaimed = rewardEvents:WaitForChild("RewardClaimed")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

------------------------------------------------------------------------
-- UI Construction
------------------------------------------------------------------------

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "DailyRewardCalendar"
screenGui.ResetOnSpawn = false
screenGui.Enabled = false
screenGui.DisplayOrder = 5
screenGui.Parent = playerGui

-- Background overlay
local overlay = Instance.new("Frame")
overlay.Size = UDim2.new(1, 0, 1, 0)
overlay.BackgroundColor3 = Color3.new(0, 0, 0)
overlay.BackgroundTransparency = 0.5
overlay.BorderSizePixel = 0
overlay.Parent = screenGui

local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(0, 560, 0, 360)
mainFrame.Position = UDim2.new(0.5, -280, 0.5, -180)
mainFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 45)
mainFrame.BorderSizePixel = 0
mainFrame.Parent = screenGui
Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 14)

-- Title
local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, 0, 0, 45)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "Daily Rewards"
titleLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextSize = 24
titleLabel.Parent = mainFrame

-- Streak label
local streakLabel = Instance.new("TextLabel")
streakLabel.Size = UDim2.new(1, 0, 0, 25)
streakLabel.Position = UDim2.new(0, 0, 0, 40)
streakLabel.BackgroundTransparency = 1
streakLabel.Text = "Current Streak: 0 days"
streakLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
streakLabel.Font = Enum.Font.Gotham
streakLabel.TextSize = 14
streakLabel.Parent = mainFrame

-- Day grid container
local gridFrame = Instance.new("Frame")
gridFrame.Size = UDim2.new(1, -40, 0, 180)
gridFrame.Position = UDim2.new(0, 20, 0, 75)
gridFrame.BackgroundTransparency = 1
gridFrame.Parent = mainFrame

local gridLayout = Instance.new("UIGridLayout")
gridLayout.CellSize = UDim2.new(0, 68, 0, 80)
gridLayout.CellPadding = UDim2.new(0, 6, 0, 6)
gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
gridLayout.Parent = gridFrame

-- Claim button
local claimButton = Instance.new("TextButton")
claimButton.Size = UDim2.new(0, 200, 0, 45)
claimButton.Position = UDim2.new(0.5, -100, 1, -65)
claimButton.BackgroundColor3 = Color3.fromRGB(0, 170, 0)
claimButton.Text = "Claim Reward!"
claimButton.TextColor3 = Color3.new(1, 1, 1)
claimButton.Font = Enum.Font.GothamBold
claimButton.TextSize = 18
claimButton.Parent = mainFrame
Instance.new("UICorner", claimButton).CornerRadius = UDim.new(0, 8)

-- Close button
local closeButton = Instance.new("TextButton")
closeButton.Size = UDim2.new(0, 30, 0, 30)
closeButton.Position = UDim2.new(1, -40, 0, 8)
closeButton.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
closeButton.Text = "X"
closeButton.TextColor3 = Color3.new(1, 1, 1)
closeButton.Font = Enum.Font.GothamBold
closeButton.TextSize = 16
closeButton.Parent = mainFrame
Instance.new("UICorner", closeButton).CornerRadius = UDim.new(0, 6)

------------------------------------------------------------------------
-- Logic
------------------------------------------------------------------------

local dayFrames: { Frame } = {}

local function buildCalendar(data: { [string]: any })
	-- Clear existing
	for _, f in ipairs(dayFrames) do f:Destroy() end
	dayFrames = {}

	for _, reward in ipairs(data.rewards) do
		local dayFrame = Instance.new("Frame")
		dayFrame.Name = "Day" .. tostring(reward.day)
		dayFrame.LayoutOrder = reward.day
		dayFrame.BorderSizePixel = 0
		dayFrame.Parent = gridFrame

		if reward.isClaimed then
			dayFrame.BackgroundColor3 = Color3.fromRGB(40, 80, 40)
		elseif reward.isToday then
			dayFrame.BackgroundColor3 = Color3.fromRGB(80, 60, 20)
		else
			dayFrame.BackgroundColor3 = Color3.fromRGB(50, 50, 65)
		end
		Instance.new("UICorner", dayFrame).CornerRadius = UDim.new(0, 8)

		local dayLabel = Instance.new("TextLabel")
		dayLabel.Size = UDim2.new(1, 0, 0, 20)
		dayLabel.BackgroundTransparency = 1
		dayLabel.Text = "Day " .. tostring(reward.day)
		dayLabel.TextColor3 = Color3.new(1, 1, 1)
		dayLabel.Font = Enum.Font.GothamBold
		dayLabel.TextSize = 11
		dayLabel.Parent = dayFrame

		local rewardLabel = Instance.new("TextLabel")
		rewardLabel.Size = UDim2.new(1, 0, 0, 16)
		rewardLabel.Position = UDim2.new(0, 0, 0, 25)
		rewardLabel.BackgroundTransparency = 1
		rewardLabel.Text = if reward.currency then tostring(reward.currency) .. " Coins" else "Items"
		rewardLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
		rewardLabel.Font = Enum.Font.Gotham
		rewardLabel.TextSize = 10
		rewardLabel.Parent = dayFrame

		if reward.isClaimed then
			local checkmark = Instance.new("TextLabel")
			checkmark.Size = UDim2.new(1, 0, 0, 25)
			checkmark.Position = UDim2.new(0, 0, 0, 45)
			checkmark.BackgroundTransparency = 1
			checkmark.Text = "Claimed"
			checkmark.TextColor3 = Color3.fromRGB(100, 255, 100)
			checkmark.Font = Enum.Font.GothamBold
			checkmark.TextSize = 10
			checkmark.Parent = dayFrame
		end

		table.insert(dayFrames, dayFrame)
	end

	streakLabel.Text = "Current Streak: " .. tostring(data.currentStreak) .. " days"
	claimButton.Visible = data.canClaim
end

local function showCalendar()
	local data = getRewardData:InvokeServer()
	if data then
		buildCalendar(data)
		screenGui.Enabled = true
	end
end

claimButton.MouseButton1Click:Connect(function()
	local success, err, result = claimReward:InvokeServer()
	if success then
		claimButton.Visible = false
		claimButton.Text = "Claimed!"
		-- Refresh calendar
		task.wait(0.5)
		showCalendar()
	else
		claimButton.Text = err or "Error"
		task.wait(2)
		claimButton.Text = "Claim Reward!"
	end
end)

closeButton.MouseButton1Click:Connect(function()
	screenGui.Enabled = false
end)

-- Auto-show on join after delay
task.delay(2, function()
	showCalendar()
end)
```

## Usage Guide

1. **Customize rewards** in `DailyRewardConfig.luau` -- edit the 7-day reward table.
2. **Integrate currency/inventory**: replace TODO stubs in `DailyRewardManager` with your systems.
3. **Streak multipliers**: adjust `ThreeDayStreakMultiplier` and `WeekStreakMultiplier`.
4. **Grace period**: `STREAK_GRACE_HOURS` controls how many hours before the streak resets (default 36h).

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

- `$REWARD_CYCLE_LENGTH` (number) -- Number of days in the reward cycle. Default: `7`.
- `$REWARDS` (table) -- Reward definitions per day. Default: see DailyRewardConfig.
- `$STREAK_GRACE_HOURS` (number) -- Hours before streak resets. Default: `36`.
- `$THREE_DAY_MULTIPLIER` (number) -- Bonus multiplier at 3-day streak. Default: `1.25`.
- `$WEEK_MULTIPLIER` (number) -- Bonus multiplier at 7-day streak. Default: `1.5`.
- `$SHOW_ON_JOIN` (boolean) -- Auto-show calendar on player join. Default: `true`.
- `$SHOW_DELAY` (number) -- Seconds to wait before showing UI. Default: `2`.
- `$DATASTORE_NAME` (string) -- DataStore name. Default: `"DailyRewards_v1"`.
