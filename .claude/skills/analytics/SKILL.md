---
name: analytics
description: |
  Roblox Analytics system - 플레이어 추적, 접속/플레이타임/구매, 커스텀 이벤트 로깅, 퍼널 분석, A/B 테스트 플래그.
  Player tracking (joins, playtime, purchases), custom event logging, funnel analysis, and A/B testing flags.
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Grep
  - Glob
effort: high
---

# Analytics System Skill

Complete analytics system for tracking player behavior, custom events, funnel analysis, and A/B testing.

## Architecture Overview

```
ServerScriptService/
  AnalyticsManager.server.luau     -- Core tracking, event logging, A/B assignment
  AnalyticsWriter.server.luau      -- Batch writes to DataStore / external endpoint
ReplicatedStorage/
  Shared/
    AnalyticsConfig.luau           -- Event definitions, A/B test configs
```

## Core Server: AnalyticsManager

```luau
--!strict
-- ServerScriptService/AnalyticsManager.server.luau
-- Tracks player sessions, custom events, funnels, and A/B test assignments.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AnalyticsConfig = require(ReplicatedStorage.Shared.AnalyticsConfig)

local analyticsStore = DataStoreService:GetDataStore("Analytics_v1")
local eventStore = DataStoreService:GetDataStore("AnalyticsEvents_v1")

------------------------------------------------------------------------
-- Types
------------------------------------------------------------------------

export type AnalyticsEvent = {
	eventName: string,
	userId: number,
	timestamp: number,
	sessionId: string,
	properties: { [string]: any }?,
}

export type PlayerSession = {
	userId: number,
	sessionId: string,
	joinTime: number,
	lastActiveTime: number,
	abGroups: { [string]: string },
	funnelSteps: { [string]: { string } },
	eventCount: number,
}

export type PlayerProfile = {
	firstJoin: number,
	totalSessions: number,
	totalPlaytimeMinutes: number,
	totalPurchases: number,
	totalSpent: number,
	lastSeen: number,
	abAssignments: { [string]: string },
}

------------------------------------------------------------------------
-- State
------------------------------------------------------------------------

local activeSessions: { [Player]: PlayerSession } = {}
local eventBuffer: { AnalyticsEvent } = {}
local BUFFER_FLUSH_INTERVAL = 30  -- seconds
local MAX_BUFFER_SIZE = 100

local AnalyticsManager = {}

------------------------------------------------------------------------
-- Session Management
------------------------------------------------------------------------

local function generateSessionId(): string
	return HttpService:GenerateGUID(false)
end

local function loadOrCreateProfile(userId: number): PlayerProfile
	local success, data = pcall(function()
		return analyticsStore:GetAsync("profile_" .. tostring(userId))
	end)

	if success and data then
		return data :: PlayerProfile
	end

	return {
		firstJoin = os.time(),
		totalSessions = 0,
		totalPlaytimeMinutes = 0,
		totalPurchases = 0,
		totalSpent = 0,
		lastSeen = 0,
		abAssignments = {},
	}
end

local function saveProfile(userId: number, profile: PlayerProfile)
	pcall(function()
		analyticsStore:SetAsync("profile_" .. tostring(userId), profile)
	end)
end

------------------------------------------------------------------------
-- A/B Testing
------------------------------------------------------------------------

function AnalyticsManager.assignABGroup(player: Player, testName: string): string
	local session = activeSessions[player]
	if not session then return "control" end

	-- Check if already assigned
	if session.abGroups[testName] then
		return session.abGroups[testName]
	end

	local testConfig = AnalyticsConfig.ABTests[testName]
	if not testConfig then return "control" end

	-- Deterministic assignment based on userId for consistency across sessions
	local userId = player.UserId
	local hash = userId % 100  -- 0-99

	local cumulative = 0
	local assignedGroup = "control"

	for groupName, percentage in pairs(testConfig.groups) do
		cumulative += percentage
		if hash < cumulative then
			assignedGroup = groupName
			break
		end
	end

	session.abGroups[testName] = assignedGroup

	-- Log the assignment
	AnalyticsManager.logEvent(player, "ab_assigned", {
		test = testName,
		group = assignedGroup,
	})

	return assignedGroup
end

function AnalyticsManager.getABGroup(player: Player, testName: string): string
	local session = activeSessions[player]
	if session and session.abGroups[testName] then
		return session.abGroups[testName]
	end
	return AnalyticsManager.assignABGroup(player, testName)
end

------------------------------------------------------------------------
-- Event Logging
------------------------------------------------------------------------

function AnalyticsManager.logEvent(player: Player, eventName: string, properties: { [string]: any }?)
	local session = activeSessions[player]
	if not session then return end

	local event: AnalyticsEvent = {
		eventName = eventName,
		userId = player.UserId,
		timestamp = os.time(),
		sessionId = session.sessionId,
		properties = properties or {},
	}

	-- Add AB groups to properties
	event.properties = event.properties or {}
	for testName, group in pairs(session.abGroups) do
		(event.properties :: any)["ab_" .. testName] = group
	end

	table.insert(eventBuffer, event)
	session.eventCount += 1

	-- Flush if buffer is full
	if #eventBuffer >= MAX_BUFFER_SIZE then
		AnalyticsManager.flushEvents()
	end
end

function AnalyticsManager.flushEvents()
	if #eventBuffer == 0 then return end

	local batch = eventBuffer
	eventBuffer = {}

	-- Store events (in production, send to external analytics service)
	pcall(function()
		local key = "events_" .. tostring(os.time()) .. "_" .. generateSessionId()
		eventStore:SetAsync(key, batch)
	end)

	-- Optional: send to external endpoint
	if AnalyticsConfig.ExternalEndpoint then
		pcall(function()
			HttpService:PostAsync(
				AnalyticsConfig.ExternalEndpoint,
				HttpService:JSONEncode(batch),
				Enum.HttpContentType.ApplicationJson
			)
		end)
	end
end

------------------------------------------------------------------------
-- Funnel Tracking
------------------------------------------------------------------------

function AnalyticsManager.trackFunnelStep(player: Player, funnelName: string, stepName: string)
	local session = activeSessions[player]
	if not session then return end

	if not session.funnelSteps[funnelName] then
		session.funnelSteps[funnelName] = {}
	end

	-- Only add if not already tracked (prevent duplicates)
	local steps = session.funnelSteps[funnelName]
	for _, existing in ipairs(steps) do
		if existing == stepName then return end
	end

	table.insert(steps, stepName)

	AnalyticsManager.logEvent(player, "funnel_step", {
		funnel = funnelName,
		step = stepName,
		stepIndex = #steps,
	})
end

------------------------------------------------------------------------
-- Purchase Tracking
------------------------------------------------------------------------

function AnalyticsManager.trackPurchase(player: Player, productId: number, amount: number, currency: string?)
	AnalyticsManager.logEvent(player, "purchase", {
		productId = productId,
		amount = amount,
		currency = currency or "robux",
	})
end

------------------------------------------------------------------------
-- Convenience Tracking
------------------------------------------------------------------------

function AnalyticsManager.trackButtonClick(player: Player, buttonName: string, context: string?)
	AnalyticsManager.logEvent(player, "button_click", {
		button = buttonName,
		context = context,
	})
end

function AnalyticsManager.trackScreenView(player: Player, screenName: string)
	AnalyticsManager.logEvent(player, "screen_view", {
		screen = screenName,
	})
end

function AnalyticsManager.trackError(player: Player, errorType: string, message: string)
	AnalyticsManager.logEvent(player, "error", {
		errorType = errorType,
		message = message,
	})
end

------------------------------------------------------------------------
-- Session Lifecycle
------------------------------------------------------------------------

Players.PlayerAdded:Connect(function(player: Player)
	local sessionId = generateSessionId()
	local profile = loadOrCreateProfile(player.UserId)

	activeSessions[player] = {
		userId = player.UserId,
		sessionId = sessionId,
		joinTime = os.time(),
		lastActiveTime = os.time(),
		abGroups = profile.abAssignments or {},
		funnelSteps = {},
		eventCount = 0,
	}

	-- Update profile
	profile.totalSessions += 1
	profile.lastSeen = os.time()

	-- Auto-assign all active A/B tests
	for testName, _ in pairs(AnalyticsConfig.ABTests) do
		AnalyticsManager.assignABGroup(player, testName)
	end

	-- Log session start
	AnalyticsManager.logEvent(player, "session_start", {
		isFirstSession = profile.totalSessions == 1,
		totalSessions = profile.totalSessions,
	})

	-- Track FTUE funnel for new players
	if profile.totalSessions == 1 then
		AnalyticsManager.trackFunnelStep(player, "ftue", "joined")
	end

	saveProfile(player.UserId, profile)
end)

Players.PlayerRemoving:Connect(function(player: Player)
	local session = activeSessions[player]
	if not session then return end

	local playtimeMinutes = math.floor((os.time() - session.joinTime) / 60)

	AnalyticsManager.logEvent(player, "session_end", {
		playtimeMinutes = playtimeMinutes,
		eventCount = session.eventCount,
	})

	-- Update profile
	local profile = loadOrCreateProfile(player.UserId)
	profile.totalPlaytimeMinutes += playtimeMinutes
	profile.lastSeen = os.time()
	profile.abAssignments = session.abGroups
	saveProfile(player.UserId, profile)

	activeSessions[player] = nil
	AnalyticsManager.flushEvents()
end)

-- Periodic buffer flush
task.spawn(function()
	while true do
		task.wait(BUFFER_FLUSH_INTERVAL)
		AnalyticsManager.flushEvents()
	end
end)

-- Flush on server shutdown
game:BindToClose(function()
	AnalyticsManager.flushEvents()
end)

return AnalyticsManager
```

## Analytics Configuration

```luau
--!strict
-- ReplicatedStorage/Shared/AnalyticsConfig.luau

local AnalyticsConfig = {}

-- A/B Test definitions
-- Groups must sum to 100 (percent)
AnalyticsConfig.ABTests = {
	new_shop_ui = {
		groups = {
			control = 50,
			variant_a = 25,
			variant_b = 25,
		},
		description = "Testing new shop layout",
	},
	onboarding_flow = {
		groups = {
			control = 50,
			simplified = 50,
		},
		description = "Simplified onboarding vs original",
	},
}

-- Funnel definitions (for reference/documentation)
AnalyticsConfig.Funnels = {
	ftue = { "joined", "tutorial_start", "tutorial_complete", "first_game", "first_purchase" },
	purchase = { "shop_opened", "item_selected", "purchase_prompted", "purchase_completed" },
}

-- External analytics endpoint (optional, set nil to disable)
AnalyticsConfig.ExternalEndpoint = nil  -- "https://your-analytics.example.com/events"

-- Event buffer settings
AnalyticsConfig.BufferFlushInterval = 30
AnalyticsConfig.MaxBufferSize = 100

return AnalyticsConfig
```

## Usage Guide

1. **Log custom events**: `AnalyticsManager.logEvent(player, "level_up", { level = 5 })`
2. **Track funnels**: `AnalyticsManager.trackFunnelStep(player, "ftue", "tutorial_complete")`
3. **A/B testing**:
   ```luau
   local group = AnalyticsManager.getABGroup(player, "new_shop_ui")
   if group == "variant_a" then ... end
   ```
4. **Purchase tracking**: `AnalyticsManager.trackPurchase(player, productId, 99, "robux")`
5. **External endpoint**: Set `AnalyticsConfig.ExternalEndpoint` to forward events to your analytics backend.

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

- `$AB_TESTS` (table) -- A/B test definitions with group percentages.
- `$FUNNELS` (table) -- Funnel step definitions for tracking.
- `$EXTERNAL_ENDPOINT` (string?) -- External analytics endpoint URL. Default: `nil`.
- `$BUFFER_FLUSH_INTERVAL` (number) -- Seconds between event flushes. Default: `30`.
- `$MAX_BUFFER_SIZE` (number) -- Max events before forced flush. Default: `100`.
- `$DATASTORE_NAME` (string) -- DataStore name for profiles. Default: `"Analytics_v1"`.
