---
name: team
description: |
  Roblox Team system implementation - 팀 시스템, 팀 배정, 팀 색상, 팀 스폰 포인트, 팀 점수, 팀 밸런싱.
  Team assignment, team colors, team spawn points, team scoring, auto-balancing, and team management.
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Grep
  - Glob
effort: high
---

# Team System Skill

This skill generates a complete Roblox team system with team assignment, colors, spawn points, scoring, and auto-balancing.

## Architecture Overview

```
ServerScriptService/
  TeamManager.server.luau        -- Core team logic, assignment, balancing
ReplicatedStorage/
  Shared/
    TeamConfig.luau              -- Team definitions and configuration
    TeamTypes.luau               -- Type definitions
StarterGui/
  TeamUI/
    TeamScoreboard.client.luau   -- Scoreboard UI
    TeamIndicator.client.luau    -- Overhead team indicators
```

## Core Server: TeamManager

```luau
--!strict
-- ServerScriptService/TeamManager.server.luau
-- Manages team creation, player assignment, scoring, and auto-balancing.

local Players = game:GetService("Players")
local Teams = game:GetService("Teams")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TeamConfig = require(ReplicatedStorage.Shared.TeamConfig)

export type TeamData = {
	name: string,
	color: BrickColor,
	score: number,
	players: { Player },
	spawnLocation: SpawnLocation?,
	maxPlayers: number,
}

local TeamManager = {}
TeamManager.__index = TeamManager

-- Remote events for client communication
local teamEvents = Instance.new("Folder")
teamEvents.Name = "TeamEvents"
teamEvents.Parent = ReplicatedStorage

local scoreUpdated = Instance.new("RemoteEvent")
scoreUpdated.Name = "ScoreUpdated"
scoreUpdated.Parent = teamEvents

local teamChanged = Instance.new("RemoteEvent")
teamChanged.Name = "TeamChanged"
teamChanged.Parent = teamEvents

local requestTeamChange = Instance.new("RemoteEvent")
requestTeamChange.Name = "RequestTeamChange"
requestTeamChange.Parent = teamEvents

-- Internal state
local teamDataMap: { [string]: TeamData } = {}
local playerTeamMap: { [Player]: string } = {}

------------------------------------------------------------------------
-- Team Creation
------------------------------------------------------------------------

function TeamManager.createTeam(config: TeamConfig.TeamDefinition): Team
	local team = Instance.new("Team")
	team.Name = config.name
	team.TeamColor = config.color
	team.AutoAssignable = config.autoAssignable or false
	team.Parent = Teams

	teamDataMap[config.name] = {
		name = config.name,
		color = config.color,
		score = 0,
		players = {},
		spawnLocation = nil,
		maxPlayers = config.maxPlayers or math.huge,
	}

	-- Setup spawn location if provided
	if config.spawnPart then
		local spawn = Instance.new("SpawnLocation")
		spawn.Name = config.name .. "Spawn"
		spawn.BrickColor = config.color
		spawn.TeamColor = config.color
		spawn.Neutral = false
		spawn.AllowTeamChangeOnTouch = false
		spawn.Size = Vector3.new(12, 1, 12)
		spawn.Position = config.spawnPart
		spawn.Anchored = true
		spawn.Parent = workspace
		teamDataMap[config.name].spawnLocation = spawn
	end

	return team
end

function TeamManager.createTeamsFromConfig()
	for _, def in ipairs(TeamConfig.Teams) do
		TeamManager.createTeam(def)
	end
end

------------------------------------------------------------------------
-- Player Assignment
------------------------------------------------------------------------

function TeamManager.getSmallestTeam(): string?
	local smallest: string? = nil
	local smallestCount = math.huge

	for name, data in pairs(teamDataMap) do
		local count = #data.players
		if count < smallestCount and count < data.maxPlayers then
			smallestCount = count
			smallest = name
		end
	end

	return smallest
end

function TeamManager.assignPlayer(player: Player, teamName: string): boolean
	local data = teamDataMap[teamName]
	if not data then
		warn("[TeamManager] Team not found:", teamName)
		return false
	end

	if #data.players >= data.maxPlayers then
		warn("[TeamManager] Team full:", teamName)
		return false
	end

	-- Remove from previous team
	TeamManager.removePlayerFromTeam(player)

	-- Assign to new team
	local team = Teams:FindFirstChild(teamName)
	if team and team:IsA("Team") then
		player.Team = team
	end

	table.insert(data.players, player)
	playerTeamMap[player] = teamName

	teamChanged:FireAllClients(player.Name, teamName, data.color)
	return true
end

function TeamManager.autoAssignPlayer(player: Player): boolean
	local teamName = TeamManager.getSmallestTeam()
	if not teamName then
		warn("[TeamManager] No available team for auto-assign")
		return false
	end
	return TeamManager.assignPlayer(player, teamName)
end

function TeamManager.removePlayerFromTeam(player: Player)
	local currentTeam = playerTeamMap[player]
	if currentTeam and teamDataMap[currentTeam] then
		local players = teamDataMap[currentTeam].players
		for i, p in ipairs(players) do
			if p == player then
				table.remove(players, i)
				break
			end
		end
	end
	playerTeamMap[player] = nil
end

------------------------------------------------------------------------
-- Team Scoring
------------------------------------------------------------------------

function TeamManager.addScore(teamName: string, points: number)
	local data = teamDataMap[teamName]
	if not data then return end

	data.score += points
	scoreUpdated:FireAllClients(teamName, data.score)
end

function TeamManager.setScore(teamName: string, score: number)
	local data = teamDataMap[teamName]
	if not data then return end

	data.score = score
	scoreUpdated:FireAllClients(teamName, data.score)
end

function TeamManager.getScore(teamName: string): number
	local data = teamDataMap[teamName]
	return if data then data.score else 0
end

function TeamManager.resetAllScores()
	for name, data in pairs(teamDataMap) do
		data.score = 0
		scoreUpdated:FireAllClients(name, 0)
	end
end

function TeamManager.getScoreboard(): { { name: string, score: number, playerCount: number } }
	local board = {}
	for name, data in pairs(teamDataMap) do
		table.insert(board, {
			name = name,
			score = data.score,
			playerCount = #data.players,
		})
	end
	table.sort(board, function(a, b) return a.score > b.score end)
	return board
end

------------------------------------------------------------------------
-- Team Balancing
------------------------------------------------------------------------

function TeamManager.isBalanced(tolerance: number?): boolean
	local tol = tolerance or 1
	local counts: { number } = {}
	for _, data in pairs(teamDataMap) do
		table.insert(counts, #data.players)
	end
	if #counts < 2 then return true end
	local maxCount = math.max(table.unpack(counts))
	local minCount = math.min(table.unpack(counts))
	return (maxCount - minCount) <= tol
end

function TeamManager.autoBalance()
	-- Collect all players and redistribute evenly
	local allPlayers: { Player } = {}
	for _, data in pairs(teamDataMap) do
		for _, p in ipairs(data.players) do
			table.insert(allPlayers, p)
		end
		data.players = {}
	end

	-- Shuffle for fairness
	for i = #allPlayers, 2, -1 do
		local j = math.random(1, i)
		allPlayers[i], allPlayers[j] = allPlayers[j], allPlayers[i]
	end

	-- Round-robin assignment
	local teamNames = {}
	for name in pairs(teamDataMap) do
		table.insert(teamNames, name)
	end

	for i, player in ipairs(allPlayers) do
		local teamIndex = ((i - 1) % #teamNames) + 1
		TeamManager.assignPlayer(player, teamNames[teamIndex])
	end
end

------------------------------------------------------------------------
-- Utility
------------------------------------------------------------------------

function TeamManager.getPlayerTeam(player: Player): string?
	return playerTeamMap[player]
end

function TeamManager.getTeamPlayers(teamName: string): { Player }
	local data = teamDataMap[teamName]
	return if data then data.players else {}
end

function TeamManager.getTeamData(teamName: string): TeamData?
	return teamDataMap[teamName]
end

------------------------------------------------------------------------
-- Initialization
------------------------------------------------------------------------

TeamManager.createTeamsFromConfig()

Players.PlayerAdded:Connect(function(player: Player)
	TeamManager.autoAssignPlayer(player)
end)

Players.PlayerRemoving:Connect(function(player: Player)
	TeamManager.removePlayerFromTeam(player)
end)

requestTeamChange.OnServerEvent:Connect(function(player: Player, teamName: string)
	-- Optional: add cooldown or permission checks
	TeamManager.assignPlayer(player, teamName)
end)

return TeamManager
```

## Team Configuration Module

```luau
--!strict
-- ReplicatedStorage/Shared/TeamConfig.luau
-- Define team names, colors, and spawn positions.

local TeamConfig = {}

export type TeamDefinition = {
	name: string,
	color: BrickColor,
	autoAssignable: boolean?,
	maxPlayers: number?,
	spawnPart: Vector3?,
}

TeamConfig.Teams: { TeamDefinition } = {
	{
		name = "Red Team",
		color = BrickColor.new("Bright red"),
		autoAssignable = true,
		maxPlayers = 16,
		spawnPart = Vector3.new(50, 5, 0),
	},
	{
		name = "Blue Team",
		color = BrickColor.new("Bright blue"),
		autoAssignable = true,
		maxPlayers = 16,
		spawnPart = Vector3.new(-50, 5, 0),
	},
}

-- Score required to win a round (0 = no limit)
TeamConfig.WinScore = 100

-- Tolerance for auto-balancing (max player difference between teams)
TeamConfig.BalanceTolerance = 2

-- Allow players to manually switch teams
TeamConfig.AllowTeamSwitch = true

-- Cooldown in seconds for manual team switch
TeamConfig.SwitchCooldown = 30

return TeamConfig
```

## Client Scoreboard UI

```luau
--!strict
-- StarterGui/TeamUI/TeamScoreboard.client.luau
-- Renders a team scoreboard on screen, updates via RemoteEvent.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local teamEvents = ReplicatedStorage:WaitForChild("TeamEvents")
local scoreUpdated = teamEvents:WaitForChild("ScoreUpdated")
local teamChanged = teamEvents:WaitForChild("TeamChanged")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Build ScreenGui
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "TeamScoreboard"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

local frame = Instance.new("Frame")
frame.Name = "ScoreboardFrame"
frame.Size = UDim2.new(0, 260, 0, 120)
frame.Position = UDim2.new(1, -270, 0, 10)
frame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
frame.BackgroundTransparency = 0.3
frame.BorderSizePixel = 0
frame.Parent = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = frame

local title = Instance.new("TextLabel")
title.Name = "Title"
title.Size = UDim2.new(1, 0, 0, 30)
title.BackgroundTransparency = 1
title.Text = "SCOREBOARD"
title.TextColor3 = Color3.new(1, 1, 1)
title.Font = Enum.Font.GothamBold
title.TextSize = 16
title.Parent = frame

local listLayout = Instance.new("UIListLayout")
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Padding = UDim.new(0, 4)
listLayout.Parent = frame

-- Team score labels keyed by team name
local teamLabels: { [string]: TextLabel } = {}

local function getOrCreateLabel(teamName: string): TextLabel
	if teamLabels[teamName] then return teamLabels[teamName] end

	local label = Instance.new("TextLabel")
	label.Name = teamName
	label.Size = UDim2.new(1, -16, 0, 28)
	label.Position = UDim2.new(0, 8, 0, 0)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Font = Enum.Font.Gotham
	label.TextSize = 14
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = teamName .. ": 0"
	label.Parent = frame
	teamLabels[teamName] = label
	return label
end

scoreUpdated.OnClientEvent:Connect(function(teamName: string, score: number)
	local label = getOrCreateLabel(teamName)
	label.Text = string.format("%s: %d", teamName, score)
end)

teamChanged.OnClientEvent:Connect(function(playerName: string, teamName: string)
	-- Could show a notification or update UI
	getOrCreateLabel(teamName)
end)
```

## Overhead Team Indicator

```luau
--!strict
-- StarterGui/TeamUI/TeamIndicator.client.luau
-- Shows a colored team label above each player's head.

local Players = game:GetService("Players")

local function addIndicator(character: Model, teamColor: BrickColor)
	local head = character:WaitForChild("Head", 5)
	if not head then return end

	-- Remove old indicator
	local old = head:FindFirstChild("TeamIndicator")
	if old then old:Destroy() end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "TeamIndicator"
	billboard.Size = UDim2.new(0, 100, 0, 30)
	billboard.StudsOffset = Vector3.new(0, 3, 0)
	billboard.AlwaysOnTop = false
	billboard.Adornee = head
	billboard.Parent = head

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.TextColor3 = teamColor.Color
	label.TextStrokeTransparency = 0.5
	label.Font = Enum.Font.GothamBold
	label.TextSize = 14
	label.Text = ""
	label.Parent = billboard
end

local function setupPlayer(p: Player)
	local function onTeamChanged()
		if p.Team and p.Character then
			addIndicator(p.Character, p.TeamColor)
		end
	end

	p:GetPropertyChangedSignal("Team"):Connect(onTeamChanged)
	p.CharacterAdded:Connect(function(char)
		task.wait(0.5)
		onTeamChanged()
	end)

	if p.Character and p.Team then
		addIndicator(p.Character, p.TeamColor)
	end
end

for _, p in ipairs(Players:GetPlayers()) do
	setupPlayer(p)
end
Players.PlayerAdded:Connect(setupPlayer)
```

## Usage Guide

1. **Customize teams** in `TeamConfig.luau` -- add/remove team definitions, change colors and spawn positions.
2. **Score points** from any server script:
   ```luau
   local TeamManager = require(ServerScriptService.TeamManager)
   TeamManager.addScore("Red Team", 10)
   ```
3. **Manual team switching**: fire `RequestTeamChange` from a client UI passing the desired team name.
4. **Auto-balance**: call `TeamManager.autoBalance()` at round start or on a timer.
5. **Win detection**: compare `TeamManager.getScore(name)` against `TeamConfig.WinScore`.

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

- `$TEAM_NAMES` (string[]) -- List of team names. Default: `{"Red Team", "Blue Team"}`.
- `$TEAM_COLORS` (BrickColor[]) -- Corresponding team colors. Default: `{BrickColor.new("Bright red"), BrickColor.new("Bright blue")}`.
- `$MAX_PLAYERS_PER_TEAM` (number) -- Maximum players per team. Default: `16`.
- `$WIN_SCORE` (number) -- Score required to win a round. Default: `100`.
- `$ALLOW_TEAM_SWITCH` (boolean) -- Whether players can manually switch teams. Default: `true`.
- `$BALANCE_TOLERANCE` (number) -- Max player count difference before auto-balance triggers. Default: `2`.
- `$SPAWN_POSITIONS` (Vector3[]) -- Spawn positions for each team. Default: `{Vector3.new(50,5,0), Vector3.new(-50,5,0)}`.
