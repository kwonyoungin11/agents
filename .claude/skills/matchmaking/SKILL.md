---
name: matchmaking
description: |
  Roblox Matchmaking system - 매치메이킹, 로비 시스템, 대기열, 실력 기반 매칭, MemoryStoreService, 파티 참가.
  Lobby system, queue management, skill-based matching, MemoryStoreService for cross-server, and party join.
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Grep
  - Glob
effort: high
---

# Matchmaking System Skill

Complete matchmaking system with lobby, queue, skill-based matching, MemoryStoreService for cross-server state, and party support.

## Architecture Overview

```
ServerScriptService/
  MatchmakingManager.server.luau   -- Queue management, matching algorithm, teleport
  MatchmakingWorker.server.luau    -- Background worker that processes queue
ReplicatedStorage/
  Shared/
    MatchmakingConfig.luau         -- Match parameters, skill brackets
StarterGui/
  MatchmakingUI/
    QueueUI.client.luau            -- Queue status, estimated wait time
```

## Core Server: MatchmakingManager

```luau
--!strict
-- ServerScriptService/MatchmakingManager.server.luau
-- Server-side matchmaking: queue, skill-based matching, cross-server via MemoryStoreService.

local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MatchmakingConfig = require(ReplicatedStorage.Shared.MatchmakingConfig)

------------------------------------------------------------------------
-- Types
------------------------------------------------------------------------

export type QueueEntry = {
	userId: number,
	playerName: string,
	skillRating: number,
	queueTime: number,
	partyId: string?,
	partyMembers: { number }?,
	serverId: string,
}

export type MatchGroup = {
	players: { QueueEntry },
	averageSkill: number,
	matchId: string,
}

------------------------------------------------------------------------
-- Remote setup
------------------------------------------------------------------------

local mmFolder = Instance.new("Folder")
mmFolder.Name = "MatchmakingEvents"
mmFolder.Parent = ReplicatedStorage

local joinQueue = Instance.new("RemoteEvent")
joinQueue.Name = "JoinQueue"
joinQueue.Parent = mmFolder

local leaveQueue = Instance.new("RemoteEvent")
leaveQueue.Name = "LeaveQueue"
leaveQueue.Parent = mmFolder

local queueStatus = Instance.new("RemoteEvent")
queueStatus.Name = "QueueStatus"
queueStatus.Parent = mmFolder

local matchFound = Instance.new("RemoteEvent")
matchFound.Name = "MatchFound"
matchFound.Parent = mmFolder

local getQueueInfo = Instance.new("RemoteFunction")
getQueueInfo.Name = "GetQueueInfo"
getQueueInfo.Parent = mmFolder

------------------------------------------------------------------------
-- MemoryStore for cross-server queue
------------------------------------------------------------------------

local queueSortedMap = MemoryStoreService:GetSortedMap("MatchmakingQueue_v1")
local matchResultMap = MemoryStoreService:GetSortedMap("MatchResults_v1")

------------------------------------------------------------------------
-- State
------------------------------------------------------------------------

local localQueue: { [number]: QueueEntry } = {}  -- userId -> entry (local server tracking)
local playerSkillCache: { [number]: number } = {}
local skillStore = DataStoreService:GetDataStore("PlayerSkillRatings_v1")

local serverId = game.JobId or "studio_" .. tostring(os.time())

local MatchmakingManager = {}

------------------------------------------------------------------------
-- Skill Rating
------------------------------------------------------------------------

function MatchmakingManager.getSkillRating(player: Player): number
	local userId = player.UserId

	if playerSkillCache[userId] then
		return playerSkillCache[userId]
	end

	local success, rating = pcall(function()
		return skillStore:GetAsync("skill_" .. tostring(userId))
	end)

	local skill = if success and rating then rating else MatchmakingConfig.DefaultSkillRating
	playerSkillCache[userId] = skill
	return skill
end

function MatchmakingManager.updateSkillRating(player: Player, newRating: number)
	playerSkillCache[player.UserId] = newRating
	pcall(function()
		skillStore:SetAsync("skill_" .. tostring(player.UserId), newRating)
	end)
end

------------------------------------------------------------------------
-- Queue Management
------------------------------------------------------------------------

function MatchmakingManager.addToQueue(player: Player, partyId: string?, partyMembers: { number }?)
	local userId = player.UserId

	-- Already in queue
	if localQueue[userId] then return end

	local skill = MatchmakingManager.getSkillRating(player)

	local entry: QueueEntry = {
		userId = userId,
		playerName = player.Name,
		skillRating = skill,
		queueTime = os.time(),
		partyId = partyId,
		partyMembers = partyMembers,
		serverId = serverId,
	}

	localQueue[userId] = entry

	-- Add to cross-server queue via MemoryStore
	pcall(function()
		queueSortedMap:SetAsync(
			tostring(userId),
			entry,
			MatchmakingConfig.QueueExpiration -- TTL in seconds
		)
	end)

	-- Notify client
	queueStatus:FireClient(player, {
		inQueue = true,
		estimatedWait = MatchmakingManager.estimateWaitTime(skill),
		queueSize = MatchmakingManager.getQueueSize(),
	})
end

function MatchmakingManager.removeFromQueue(player: Player)
	local userId = player.UserId
	localQueue[userId] = nil

	pcall(function()
		queueSortedMap:RemoveAsync(tostring(userId))
	end)

	queueStatus:FireClient(player, {
		inQueue = false,
	})
end

function MatchmakingManager.isInQueue(player: Player): boolean
	return localQueue[player.UserId] ~= nil
end

------------------------------------------------------------------------
-- Matching Algorithm
------------------------------------------------------------------------

function MatchmakingManager.getQueueSize(): number
	local count = 0
	-- Count from MemoryStore (approximate)
	local success, items = pcall(function()
		return queueSortedMap:GetRangeAsync(Enum.SortDirection.Ascending, 200)
	end)

	if success and items then
		return #items
	end

	-- Fallback to local count
	for _ in pairs(localQueue) do
		count += 1
	end
	return count
end

function MatchmakingManager.estimateWaitTime(skillRating: number): number
	local queueSize = MatchmakingManager.getQueueSize()
	local playersNeeded = MatchmakingConfig.PlayersPerMatch

	if queueSize >= playersNeeded then
		return 5  -- near-instant
	end

	-- Rough estimate based on queue size
	return math.max(5, (playersNeeded - queueSize) * 15)
end

function MatchmakingManager.findMatch(): MatchGroup?
	-- Fetch queue entries from MemoryStore
	local success, items = pcall(function()
		return queueSortedMap:GetRangeAsync(Enum.SortDirection.Ascending, 200)
	end)

	if not success or not items or #items < MatchmakingConfig.PlayersPerMatch then
		return nil
	end

	-- Parse entries
	local entries: { QueueEntry } = {}
	for _, item in ipairs(items) do
		table.insert(entries, item.value)
	end

	-- Sort by skill rating
	table.sort(entries, function(a, b)
		return a.skillRating < b.skillRating
	end)

	-- Sliding window to find best group within skill range
	local bestGroup: { QueueEntry }? = nil
	local bestSkillSpread = math.huge
	local needed = MatchmakingConfig.PlayersPerMatch

	for i = 1, #entries - needed + 1 do
		local group = {}
		for j = i, i + needed - 1 do
			table.insert(group, entries[j])
		end

		local spread = group[#group].skillRating - group[1].skillRating

		-- Check if within acceptable skill range
		local maxWait = os.time() - group[1].queueTime
		local expandedRange = MatchmakingConfig.BaseSkillRange + (maxWait / MatchmakingConfig.SkillRangeExpandRate) * MatchmakingConfig.SkillRangeExpandAmount

		if spread <= expandedRange and spread < bestSkillSpread then
			bestSkillSpread = spread
			bestGroup = group
		end
	end

	if bestGroup then
		local totalSkill = 0
		for _, entry in ipairs(bestGroup) do
			totalSkill += entry.skillRating
		end

		return {
			players = bestGroup,
			averageSkill = totalSkill / #bestGroup,
			matchId = "match_" .. tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999)),
		}
	end

	return nil
end

------------------------------------------------------------------------
-- Match Execution
------------------------------------------------------------------------

function MatchmakingManager.executeMatch(match: MatchGroup)
	local placeId = MatchmakingConfig.GamePlaceId

	-- Reserve a server
	local success, serverCode = pcall(function()
		return TeleportService:ReserveServer(placeId)
	end)

	if not success or not serverCode then
		warn("[Matchmaking] Failed to reserve server")
		return
	end

	-- Remove matched players from queue
	for _, entry in ipairs(match.players) do
		pcall(function()
			queueSortedMap:RemoveAsync(tostring(entry.userId))
		end)
		localQueue[entry.userId] = nil
	end

	-- Store match result for cross-server pickup
	pcall(function()
		matchResultMap:SetAsync(match.matchId, {
			serverCode = serverCode,
			placeId = placeId,
			players = match.players,
			averageSkill = match.averageSkill,
		}, 120) -- 2 minute TTL
	end)

	-- Teleport players on this server
	local playersToTeleport: { Player } = {}
	for _, entry in ipairs(match.players) do
		if entry.serverId == serverId then
			local player = Players:GetPlayerByUserId(entry.userId)
			if player then
				matchFound:FireClient(player, {
					matchId = match.matchId,
					averageSkill = match.averageSkill,
					playerCount = #match.players,
				})
				table.insert(playersToTeleport, player)
			end
		end
	end

	-- Short delay for UI display
	task.wait(3)

	if #playersToTeleport > 0 then
		local teleportOptions = Instance.new("TeleportOptions")
		teleportOptions.ReservedServerAccessCode = serverCode
		teleportOptions:SetTeleportData({
			matchId = match.matchId,
			averageSkill = match.averageSkill,
		})

		pcall(function()
			TeleportService:TeleportAsync(placeId, playersToTeleport, teleportOptions)
		end)
	end
end

------------------------------------------------------------------------
-- Background Worker
------------------------------------------------------------------------

task.spawn(function()
	while true do
		task.wait(MatchmakingConfig.MatchCheckInterval)

		local match = MatchmakingManager.findMatch()
		if match then
			MatchmakingManager.executeMatch(match)
		end

		-- Update queue status for all queued players
		for userId, entry in pairs(localQueue) do
			local player = Players:GetPlayerByUserId(userId)
			if player then
				local waitTime = os.time() - entry.queueTime
				queueStatus:FireClient(player, {
					inQueue = true,
					waitTime = waitTime,
					estimatedWait = MatchmakingManager.estimateWaitTime(entry.skillRating),
					queueSize = MatchmakingManager.getQueueSize(),
				})
			end
		end
	end
end)

------------------------------------------------------------------------
-- Remote Handlers
------------------------------------------------------------------------

joinQueue.OnServerEvent:Connect(function(player: Player)
	MatchmakingManager.addToQueue(player)
end)

leaveQueue.OnServerEvent:Connect(function(player: Player)
	MatchmakingManager.removeFromQueue(player)
end)

getQueueInfo.OnServerInvoke = function(player: Player)
	local entry = localQueue[player.UserId]
	return {
		inQueue = entry ~= nil,
		queueSize = MatchmakingManager.getQueueSize(),
		skillRating = MatchmakingManager.getSkillRating(player),
	}
end

Players.PlayerRemoving:Connect(function(player: Player)
	MatchmakingManager.removeFromQueue(player)
	playerSkillCache[player.UserId] = nil
end)

return MatchmakingManager
```

## Matchmaking Configuration

```luau
--!strict
-- ReplicatedStorage/Shared/MatchmakingConfig.luau

local MatchmakingConfig = {}

-- Game place to teleport matched players to
MatchmakingConfig.GamePlaceId = 0  -- Replace with real place ID

-- Players needed per match
MatchmakingConfig.PlayersPerMatch = 8

-- Minimum players to start a match (if queue takes too long)
MatchmakingConfig.MinPlayersPerMatch = 4

-- Skill rating defaults
MatchmakingConfig.DefaultSkillRating = 1000
MatchmakingConfig.MinSkillRating = 0
MatchmakingConfig.MaxSkillRating = 3000

-- Skill range for matching
MatchmakingConfig.BaseSkillRange = 200        -- initial skill range
MatchmakingConfig.SkillRangeExpandRate = 30   -- seconds before expanding
MatchmakingConfig.SkillRangeExpandAmount = 100 -- expand by this much each interval

-- Queue settings
MatchmakingConfig.QueueExpiration = 300       -- seconds before queue entry expires
MatchmakingConfig.MatchCheckInterval = 5      -- seconds between match attempts
MatchmakingConfig.MaxQueueTime = 300          -- max seconds in queue before force-match

return MatchmakingConfig
```

## Client Queue UI

```luau
--!strict
-- StarterGui/MatchmakingUI/QueueUI.client.luau
-- Queue status display with estimated wait time and cancel button.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local mmEvents = ReplicatedStorage:WaitForChild("MatchmakingEvents")
local joinQueueEvent = mmEvents:WaitForChild("JoinQueue")
local leaveQueueEvent = mmEvents:WaitForChild("LeaveQueue")
local queueStatusEvent = mmEvents:WaitForChild("QueueStatus")
local matchFoundEvent = mmEvents:WaitForChild("MatchFound")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "QueueUI"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

-- Queue button (always visible)
local queueBtn = Instance.new("TextButton")
queueBtn.Size = UDim2.new(0, 180, 0, 50)
queueBtn.Position = UDim2.new(0.5, -90, 1, -70)
queueBtn.BackgroundColor3 = Color3.fromRGB(0, 150, 255)
queueBtn.Text = "Find Match"
queueBtn.TextColor3 = Color3.new(1, 1, 1)
queueBtn.Font = Enum.Font.GothamBold
queueBtn.TextSize = 18
queueBtn.Parent = screenGui
Instance.new("UICorner", queueBtn).CornerRadius = UDim.new(0, 10)

-- Queue status panel
local statusPanel = Instance.new("Frame")
statusPanel.Size = UDim2.new(0, 300, 0, 120)
statusPanel.Position = UDim2.new(0.5, -150, 0.5, -60)
statusPanel.BackgroundColor3 = Color3.fromRGB(25, 25, 40)
statusPanel.BorderSizePixel = 0
statusPanel.Visible = false
statusPanel.Parent = screenGui
Instance.new("UICorner", statusPanel).CornerRadius = UDim.new(0, 12)

local searchingLabel = Instance.new("TextLabel")
searchingLabel.Size = UDim2.new(1, 0, 0, 30)
searchingLabel.Position = UDim2.new(0, 0, 0, 10)
searchingLabel.BackgroundTransparency = 1
searchingLabel.Text = "Searching for match..."
searchingLabel.TextColor3 = Color3.new(1, 1, 1)
searchingLabel.Font = Enum.Font.GothamBold
searchingLabel.TextSize = 16
searchingLabel.Parent = statusPanel

local waitLabel = Instance.new("TextLabel")
waitLabel.Size = UDim2.new(1, 0, 0, 20)
waitLabel.Position = UDim2.new(0, 0, 0, 40)
waitLabel.BackgroundTransparency = 1
waitLabel.Text = "Wait time: 0s | Queue: 0"
waitLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
waitLabel.Font = Enum.Font.Gotham
waitLabel.TextSize = 13
waitLabel.Parent = statusPanel

local cancelBtn = Instance.new("TextButton")
cancelBtn.Size = UDim2.new(0, 120, 0, 35)
cancelBtn.Position = UDim2.new(0.5, -60, 1, -48)
cancelBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
cancelBtn.Text = "Cancel"
cancelBtn.TextColor3 = Color3.new(1, 1, 1)
cancelBtn.Font = Enum.Font.GothamBold
cancelBtn.TextSize = 14
cancelBtn.Parent = statusPanel
Instance.new("UICorner", cancelBtn).CornerRadius = UDim.new(0, 6)

-- Match found panel
local matchPanel = Instance.new("Frame")
matchPanel.Size = UDim2.new(0, 300, 0, 100)
matchPanel.Position = UDim2.new(0.5, -150, 0.5, -50)
matchPanel.BackgroundColor3 = Color3.fromRGB(20, 50, 20)
matchPanel.BorderSizePixel = 0
matchPanel.Visible = false
matchPanel.Parent = screenGui
Instance.new("UICorner", matchPanel).CornerRadius = UDim.new(0, 12)

local matchLabel = Instance.new("TextLabel")
matchLabel.Size = UDim2.new(1, 0, 1, 0)
matchLabel.BackgroundTransparency = 1
matchLabel.Text = "Match Found!\nTeleporting..."
matchLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
matchLabel.Font = Enum.Font.GothamBold
matchLabel.TextSize = 20
matchLabel.Parent = matchPanel

local inQueue = false

queueBtn.MouseButton1Click:Connect(function()
	if inQueue then return end
	joinQueueEvent:FireServer()
end)

cancelBtn.MouseButton1Click:Connect(function()
	leaveQueueEvent:FireServer()
end)

queueStatusEvent.OnClientEvent:Connect(function(data)
	inQueue = data.inQueue

	if data.inQueue then
		statusPanel.Visible = true
		queueBtn.Visible = false
		local wait = data.waitTime or 0
		local est = data.estimatedWait or 0
		local size = data.queueSize or 0
		waitLabel.Text = string.format("Wait: %ds | Est: %ds | Queue: %d", wait, est, size)
	else
		statusPanel.Visible = false
		queueBtn.Visible = true
	end
end)

matchFoundEvent.OnClientEvent:Connect(function(data)
	statusPanel.Visible = false
	matchPanel.Visible = true
	matchLabel.Text = string.format("Match Found!\n%d players | Avg skill: %d\nTeleporting...",
		data.playerCount or 0, math.floor(data.averageSkill or 0))
end)
```

## Usage Guide

1. **Set `GamePlaceId`** in `MatchmakingConfig` to the destination place.
2. **Adjust skill parameters**: `BaseSkillRange`, expand rates, player counts.
3. **Update skill ratings** after matches:
   ```luau
   MatchmakingManager.updateSkillRating(player, newRating)
   ```
4. **Party queuing**: pass `partyId` and `partyMembers` to `addToQueue()`.
5. **Cross-server**: MemoryStoreService keeps queue state across all servers.

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

- `$GAME_PLACE_ID` (number) -- Place ID for match games. Required.
- `$PLAYERS_PER_MATCH` (number) -- Target players per match. Default: `8`.
- `$MIN_PLAYERS_PER_MATCH` (number) -- Minimum to start match. Default: `4`.
- `$DEFAULT_SKILL_RATING` (number) -- Starting skill rating. Default: `1000`.
- `$BASE_SKILL_RANGE` (number) -- Initial skill matching range. Default: `200`.
- `$MATCH_CHECK_INTERVAL` (number) -- Seconds between match checks. Default: `5`.
- `$QUEUE_EXPIRATION` (number) -- Queue entry TTL in seconds. Default: `300`.
