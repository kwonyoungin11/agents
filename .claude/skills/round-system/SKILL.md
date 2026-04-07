---
name: round-system
description: |
  Round-based game system for Roblox. Lobby phase with countdown, active game phase,
  end/results phase, scoring system, map rotation, player tracking,
  winner determination, and intermission.
  키워드: 라운드 시스템, 로비, 카운트다운, 게임 페이즈, 점수, 맵 로테이션, 승리 판정
allowed-tools:
  - Bash
  - Read
  - Edit
  - Write
  - Glob
  - Grep
effort: high
---

# Round-Based Game System

Complete round-based game framework for Roblox: lobby, countdown, active phase, end phase, scoring, map rotation, and player lifecycle. All code is Luau.

---

## Architecture Overview

```
ReplicatedStorage/
  Shared/
    RoundConfig.luau          -- Phase timings, scoring rules, map list
ServerScriptService/
  Services/
    RoundService.luau         -- Server: state machine, player management
    MapService.luau           -- Server: map loading/unloading
StarterPlayerScripts/
  Controllers/
    RoundHUD.luau             -- Client: status display, countdown, scoreboard
ServerStorage/
  Maps/                       -- Map models to clone into workspace
```

---

## 1. Round Configuration

```luau
-- ReplicatedStorage/Shared/RoundConfig.luau
--!strict

export type RoundPhase = "Lobby" | "Countdown" | "Active" | "Ending" | "Intermission"

export type ScoringMode = "LastStanding" | "MostKills" | "MostPoints" | "TeamBased" | "TimeAttack"

export type MapDefinition = {
    name: string,
    modelName: string,
    maxPlayers: number,
    spawnPoints: number,      -- number of spawn locations in the map
    description: string,
}

local RoundConfig = {}

RoundConfig.MIN_PLAYERS_TO_START = 2
RoundConfig.LOBBY_WAIT_TIME = 30         -- max seconds in lobby
RoundConfig.COUNTDOWN_TIME = 10          -- countdown before round starts
RoundConfig.ROUND_TIME = 180             -- active round duration (seconds)
RoundConfig.ENDING_TIME = 10             -- results screen duration
RoundConfig.INTERMISSION_TIME = 15       -- between rounds
RoundConfig.SCORING_MODE = "MostKills" :: ScoringMode
RoundConfig.WIN_KILL_COUNT = nil         -- nil = use timer; number = first to N kills wins
RoundConfig.ENABLE_MAP_VOTING = true
RoundConfig.MAP_VOTE_TIME = 15

RoundConfig.Maps: { MapDefinition } = {
    {
        name = "Desert Arena",
        modelName = "DesertArena",
        maxPlayers = 16,
        spawnPoints = 8,
        description = "A sun-scorched arena with cover positions",
    },
    {
        name = "Forest Clearing",
        modelName = "ForestClearing",
        maxPlayers = 12,
        spawnPoints = 6,
        description = "Dense forest with a central clearing",
    },
    {
        name = "Space Station",
        modelName = "SpaceStation",
        maxPlayers = 10,
        spawnPoints = 5,
        description = "Zero-gravity corridors and open bays",
    },
}

-- Scoring rules
RoundConfig.POINTS_PER_KILL = 100
RoundConfig.POINTS_PER_ASSIST = 25
RoundConfig.POINTS_PER_OBJECTIVE = 50
RoundConfig.BONUS_FIRST_BLOOD = 50
RoundConfig.BONUS_WINNING_TEAM = 200

return RoundConfig
```

---

## 2. Server Round Service (State Machine)

```luau
-- ServerScriptService/Services/RoundService.luau
--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local RoundConfig = require(ReplicatedStorage.Shared.RoundConfig)

local RoundService = {}

-- State
local currentPhase: RoundConfig.RoundPhase = "Lobby"
local currentMap: RoundConfig.MapDefinition? = nil
local currentMapModel: Model? = nil
local roundNumber = 0
local phaseStartTime = 0
local roundTimer = 0

-- Player tracking
type PlayerRoundData = {
    kills: number,
    deaths: number,
    assists: number,
    points: number,
    isAlive: boolean,
    joinedMidRound: boolean,
}

local playerRoundData: { [Player]: PlayerRoundData } = {}
local activePlayers: { Player } = {}

-- Replicated values
local statusFolder: Folder
local phaseValue: StringValue
local timerValue: NumberValue
local roundNumberValue: IntValue
local mapNameValue: StringValue

-- Map history for rotation (avoid repeats)
local mapHistory: { string } = {}

-------------------------------------------------
-- Map Management
-------------------------------------------------

local function getNextMap(): RoundConfig.MapDefinition
    -- Simple rotation: pick random map not recently played
    local available = {}
    for _, mapDef in RoundConfig.Maps do
        local recentlyPlayed = false
        for i = math.max(1, #mapHistory - 2), #mapHistory do
            if mapHistory[i] == mapDef.name then
                recentlyPlayed = true
                break
            end
        end
        if not recentlyPlayed then
            table.insert(available, mapDef)
        end
    end

    if #available == 0 then
        available = RoundConfig.Maps
    end

    return available[math.random(1, #available)]
end

local function loadMap(mapDef: RoundConfig.MapDefinition): Model?
    local mapsFolder = ServerStorage:FindFirstChild("Maps")
    if not mapsFolder then
        warn("[RoundService] ServerStorage.Maps not found")
        return nil
    end

    local template = mapsFolder:FindFirstChild(mapDef.modelName)
    if not template or not template:IsA("Model") then
        warn("[RoundService] Map model not found:", mapDef.modelName)
        return nil
    end

    local mapModel = template:Clone() :: Model
    mapModel.Name = "ActiveMap"
    mapModel.Parent = workspace

    table.insert(mapHistory, mapDef.name)
    return mapModel
end

local function unloadMap()
    if currentMapModel then
        currentMapModel:Destroy()
        currentMapModel = nil
    end
end

local function getMapSpawnPoints(): { BasePart }
    if not currentMapModel then return {} end
    local points = {}
    for _, child in currentMapModel:GetDescendants() do
        if child:IsA("BasePart") and child.Name == "SpawnPoint" then
            table.insert(points, child)
        end
    end
    return points
end

-------------------------------------------------
-- Player Management
-------------------------------------------------

local function initPlayerRoundData(player: Player, midRound: boolean): PlayerRoundData
    local data: PlayerRoundData = {
        kills = 0,
        deaths = 0,
        assists = 0,
        points = 0,
        isAlive = true,
        joinedMidRound = midRound,
    }
    playerRoundData[player] = data
    return data
end

local function teleportToMap(player: Player)
    local spawnPoints = getMapSpawnPoints()
    if #spawnPoints == 0 then return end

    local character = player.Character
    if not character then return end
    local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
    if not rootPart then return end

    local spawn = spawnPoints[math.random(1, #spawnPoints)]
    rootPart.CFrame = spawn.CFrame + Vector3.new(0, 3, 0)
end

local function teleportToLobby(player: Player)
    local lobbySpawn = workspace:FindFirstChild("LobbySpawn") :: BasePart?
    if not lobbySpawn then return end

    local character = player.Character
    if not character then return end
    local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
    if rootPart then
        rootPart.CFrame = lobbySpawn.CFrame + Vector3.new(0, 3, 0)
    end
end

-------------------------------------------------
-- Phase Transitions
-------------------------------------------------

local function setPhase(phase: RoundConfig.RoundPhase)
    currentPhase = phase
    phaseValue.Value = phase
    phaseStartTime = tick()

    local remotes = ReplicatedStorage:FindFirstChild("RoundRemotes")
    if remotes then
        local phaseEvent = remotes:FindFirstChild("PhaseChanged") :: RemoteEvent
        if phaseEvent then
            phaseEvent:FireAllClients(phase, roundNumber)
        end
    end
end

local function runLobbyPhase()
    setPhase("Lobby")
    roundTimer = RoundConfig.LOBBY_WAIT_TIME

    while currentPhase == "Lobby" do
        timerValue.Value = roundTimer

        -- Check if enough players
        if #Players:GetPlayers() >= RoundConfig.MIN_PLAYERS_TO_START then
            roundTimer -= 1
            if roundTimer <= 0 then
                break
            end
        else
            roundTimer = RoundConfig.LOBBY_WAIT_TIME
        end

        task.wait(1)
    end
end

local function runCountdownPhase()
    setPhase("Countdown")

    -- Select map
    currentMap = getNextMap()
    if currentMap then
        currentMapModel = loadMap(currentMap)
        mapNameValue.Value = currentMap.name
    end

    -- Initialize player data
    activePlayers = {}
    playerRoundData = {}
    for _, player in Players:GetPlayers() do
        initPlayerRoundData(player, false)
        table.insert(activePlayers, player)
    end

    -- Countdown
    for i = RoundConfig.COUNTDOWN_TIME, 1, -1 do
        timerValue.Value = i
        task.wait(1)
    end

    -- Teleport all players to map
    for _, player in activePlayers do
        player:LoadCharacter()
        task.wait(0.2)
        teleportToMap(player)
    end
end

local function runActivePhase()
    setPhase("Active")
    roundTimer = RoundConfig.ROUND_TIME

    -- Set up death tracking
    for _, player in activePlayers do
        if player.Character then
            local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
            if humanoid then
                humanoid.Died:Connect(function()
                    local data = playerRoundData[player]
                    if data then
                        data.deaths += 1
                        data.isAlive = false
                    end

                    -- Check win condition: last standing
                    if RoundConfig.SCORING_MODE == "LastStanding" then
                        local aliveCount = 0
                        local lastAlive: Player? = nil
                        for _, plr in activePlayers do
                            local d = playerRoundData[plr]
                            if d and d.isAlive then
                                aliveCount += 1
                                lastAlive = plr
                            end
                        end
                        if aliveCount <= 1 then
                            -- End round
                            roundTimer = 0
                        end
                    end

                    -- Respawn for non-last-standing modes
                    if RoundConfig.SCORING_MODE ~= "LastStanding" then
                        task.delay(3, function()
                            if currentPhase == "Active" and player.Parent then
                                local d = playerRoundData[player]
                                if d then d.isAlive = true end
                                player:LoadCharacter()
                                task.wait(0.5)
                                teleportToMap(player)
                            end
                        end)
                    end
                end)
            end
        end
    end

    -- Timer loop
    while currentPhase == "Active" and roundTimer > 0 do
        timerValue.Value = roundTimer
        roundTimer -= 1
        task.wait(1)
    end
end

local function runEndingPhase()
    setPhase("Ending")

    -- Determine winner
    local winner: Player? = nil
    local bestScore = -1

    if RoundConfig.SCORING_MODE == "LastStanding" then
        for _, player in activePlayers do
            local data = playerRoundData[player]
            if data and data.isAlive then
                winner = player
                break
            end
        end
    else
        for _, player in activePlayers do
            local data = playerRoundData[player]
            if data then
                local score = data.points
                if RoundConfig.SCORING_MODE == "MostKills" then
                    score = data.kills
                end
                if score > bestScore then
                    bestScore = score
                    winner = player
                end
            end
        end
    end

    -- Build scoreboard data
    local scoreboard: { { name: string, kills: number, deaths: number, points: number } } = {}
    for _, player in activePlayers do
        local data = playerRoundData[player]
        if data then
            table.insert(scoreboard, {
                name = player.Name,
                kills = data.kills,
                deaths = data.deaths,
                points = data.points,
            })
        end
    end

    -- Sort by points/kills
    table.sort(scoreboard, function(a, b)
        return a.points > b.points
    end)

    -- Send results to clients
    local remotes = ReplicatedStorage:FindFirstChild("RoundRemotes")
    if remotes then
        local resultsEvent = remotes:FindFirstChild("RoundResults") :: RemoteEvent
        if resultsEvent then
            resultsEvent:FireAllClients(
                if winner then winner.Name else "No winner",
                scoreboard,
                roundNumber
            )
        end
    end

    -- Award winner bonus
    if winner then
        local data = playerRoundData[winner]
        if data then
            data.points += RoundConfig.BONUS_WINNING_TEAM
        end
    end

    -- Display results
    timerValue.Value = RoundConfig.ENDING_TIME
    for i = RoundConfig.ENDING_TIME, 1, -1 do
        timerValue.Value = i
        task.wait(1)
    end

    -- Teleport everyone back to lobby
    for _, player in Players:GetPlayers() do
        teleportToLobby(player)
    end

    -- Unload map
    unloadMap()
end

local function runIntermissionPhase()
    setPhase("Intermission")

    for i = RoundConfig.INTERMISSION_TIME, 1, -1 do
        timerValue.Value = i
        task.wait(1)
    end
end

-------------------------------------------------
-- Kill Registration (called by combat system)
-------------------------------------------------

function RoundService.RegisterKill(killer: Player, victim: Player)
    if currentPhase ~= "Active" then return end

    local killerData = playerRoundData[killer]
    if killerData then
        killerData.kills += 1
        killerData.points += RoundConfig.POINTS_PER_KILL
    end

    -- Check kill-based win condition
    if RoundConfig.WIN_KILL_COUNT and killerData then
        if killerData.kills >= RoundConfig.WIN_KILL_COUNT then
            roundTimer = 0 -- ends the active phase
        end
    end

    -- Update scoreboard in real-time
    local remotes = ReplicatedStorage:FindFirstChild("RoundRemotes")
    if remotes then
        local killEvent = remotes:FindFirstChild("KillFeed") :: RemoteEvent
        if killEvent then
            killEvent:FireAllClients(killer.Name, victim.Name)
        end

        local scoreUpdate = remotes:FindFirstChild("ScoreUpdate") :: RemoteEvent
        if scoreUpdate and killerData then
            scoreUpdate:FireAllClients(killer.Name, killerData.kills, killerData.points)
        end
    end
end

-------------------------------------------------
-- Main Game Loop
-------------------------------------------------

local function gameLoop()
    while true do
        roundNumber += 1
        roundNumberValue.Value = roundNumber

        runLobbyPhase()
        runCountdownPhase()
        runActivePhase()
        runEndingPhase()
        runIntermissionPhase()
    end
end

-------------------------------------------------
-- Init
-------------------------------------------------

function RoundService.Init()
    -- Replicated values
    statusFolder = Instance.new("Folder")
    statusFolder.Name = "RoundStatus"
    statusFolder.Parent = ReplicatedStorage

    phaseValue = Instance.new("StringValue")
    phaseValue.Name = "Phase"
    phaseValue.Value = "Lobby"
    phaseValue.Parent = statusFolder

    timerValue = Instance.new("NumberValue")
    timerValue.Name = "Timer"
    timerValue.Value = 0
    timerValue.Parent = statusFolder

    roundNumberValue = Instance.new("IntValue")
    roundNumberValue.Name = "RoundNumber"
    roundNumberValue.Value = 0
    roundNumberValue.Parent = statusFolder

    mapNameValue = Instance.new("StringValue")
    mapNameValue.Name = "MapName"
    mapNameValue.Value = ""
    mapNameValue.Parent = statusFolder

    -- Create remotes
    local remotesFolder = Instance.new("Folder")
    remotesFolder.Name = "RoundRemotes"
    remotesFolder.Parent = ReplicatedStorage

    for _, name in { "PhaseChanged", "RoundResults", "KillFeed", "ScoreUpdate", "MapVote" } do
        local remote = Instance.new("RemoteEvent")
        remote.Name = name
        remote.Parent = remotesFolder
    end

    -- Handle mid-round joins
    Players.PlayerAdded:Connect(function(player: Player)
        if currentPhase == "Active" then
            -- Send to lobby, don't add to round
            player.CharacterAdded:Wait()
            task.wait(0.5)
            teleportToLobby(player)
        end
    end)

    -- Handle disconnects
    Players.PlayerRemoving:Connect(function(player: Player)
        playerRoundData[player] = nil
        local idx = table.find(activePlayers, player)
        if idx then
            table.remove(activePlayers, idx)
        end
    end)

    -- Start game loop
    task.spawn(gameLoop)
end

return RoundService
```

---

## 3. Client Round HUD

```luau
-- StarterPlayerScripts/Controllers/RoundHUD.luau
--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local RoundHUD = {}

function RoundHUD.Init()
    local roundStatus = ReplicatedStorage:WaitForChild("RoundStatus")
    local phaseValue = roundStatus:WaitForChild("Phase") :: StringValue
    local timerValue = roundStatus:WaitForChild("Timer") :: NumberValue
    local roundNumber = roundStatus:WaitForChild("RoundNumber") :: IntValue
    local mapName = roundStatus:WaitForChild("MapName") :: StringValue

    local remotes = ReplicatedStorage:WaitForChild("RoundRemotes")

    -- Create UI
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "RoundHUD"
    screenGui.ResetOnSpawn = false
    screenGui.Parent = playerGui

    -- Top bar
    local topBar = Instance.new("Frame")
    topBar.Size = UDim2.new(0.4, 0, 0, 50)
    topBar.Position = UDim2.new(0.3, 0, 0, 5)
    topBar.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
    topBar.BackgroundTransparency = 0.3
    topBar.Parent = screenGui

    local topCorner = Instance.new("UICorner")
    topCorner.CornerRadius = UDim.new(0, 8)
    topCorner.Parent = topBar

    local phaseLabel = Instance.new("TextLabel")
    phaseLabel.Name = "PhaseLabel"
    phaseLabel.Size = UDim2.new(0.5, 0, 0.5, 0)
    phaseLabel.BackgroundTransparency = 1
    phaseLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    phaseLabel.TextSize = 20
    phaseLabel.Font = Enum.Font.GothamBold
    phaseLabel.Text = "Lobby"
    phaseLabel.Parent = topBar

    local timerLabel = Instance.new("TextLabel")
    timerLabel.Name = "TimerLabel"
    timerLabel.Size = UDim2.new(0.5, 0, 0.5, 0)
    timerLabel.Position = UDim2.new(0.5, 0, 0, 0)
    timerLabel.BackgroundTransparency = 1
    timerLabel.TextColor3 = Color3.fromRGB(255, 255, 100)
    timerLabel.TextSize = 24
    timerLabel.Font = Enum.Font.GothamBold
    timerLabel.Text = "0:00"
    timerLabel.Parent = topBar

    local mapLabel = Instance.new("TextLabel")
    mapLabel.Size = UDim2.new(1, 0, 0.5, 0)
    mapLabel.Position = UDim2.new(0, 0, 0.5, 0)
    mapLabel.BackgroundTransparency = 1
    mapLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
    mapLabel.TextSize = 14
    mapLabel.Font = Enum.Font.Gotham
    mapLabel.Text = ""
    mapLabel.Parent = topBar

    -- Kill feed
    local killFeed = Instance.new("Frame")
    killFeed.Name = "KillFeed"
    killFeed.Size = UDim2.fromOffset(300, 200)
    killFeed.Position = UDim2.new(1, -310, 0.3, 0)
    killFeed.BackgroundTransparency = 1
    killFeed.Parent = screenGui

    local killFeedLayout = Instance.new("UIListLayout")
    killFeedLayout.SortOrder = Enum.SortOrder.LayoutOrder
    killFeedLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
    killFeedLayout.Padding = UDim.new(0, 2)
    killFeedLayout.Parent = killFeed

    -- Bindings
    phaseValue.Changed:Connect(function(val)
        local displayNames: { [string]: string } = {
            Lobby = "Waiting for Players",
            Countdown = "Starting...",
            Active = "Round In Progress",
            Ending = "Round Over",
            Intermission = "Intermission",
        }
        phaseLabel.Text = displayNames[val] or val
    end)

    timerValue.Changed:Connect(function(val)
        local minutes = math.floor(val / 60)
        local seconds = math.floor(val % 60)
        timerLabel.Text = string.format("%d:%02d", minutes, seconds)

        -- Flash red when low time
        if val <= 10 and phaseValue.Value == "Active" then
            timerLabel.TextColor3 = Color3.fromRGB(255, 50, 50)
        else
            timerLabel.TextColor3 = Color3.fromRGB(255, 255, 100)
        end
    end)

    mapName.Changed:Connect(function(val)
        mapLabel.Text = if val ~= "" then "Map: " .. val else ""
    end)

    -- Kill feed events
    local killFeedEvent = remotes:WaitForChild("KillFeed") :: RemoteEvent
    killFeedEvent.OnClientEvent:Connect(function(killerName: string, victimName: string)
        local entry = Instance.new("TextLabel")
        entry.Size = UDim2.new(1, 0, 0, 20)
        entry.BackgroundTransparency = 1
        entry.Text = killerName .. " eliminated " .. victimName
        entry.TextColor3 = Color3.fromRGB(255, 200, 200)
        entry.TextSize = 14
        entry.Font = Enum.Font.Gotham
        entry.TextXAlignment = Enum.TextXAlignment.Right
        entry.Parent = killFeed

        -- Fade out after a few seconds
        task.delay(5, function()
            TweenService:Create(entry, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
            task.delay(0.5, function()
                entry:Destroy()
            end)
        end)
    end)

    -- Results screen
    local resultsEvent = remotes:WaitForChild("RoundResults") :: RemoteEvent
    resultsEvent.OnClientEvent:Connect(function(winnerName: string, scoreboard: any, roundNum: number)
        local resultsFrame = Instance.new("Frame")
        resultsFrame.Size = UDim2.new(0.5, 0, 0.6, 0)
        resultsFrame.Position = UDim2.new(0.25, 0, 0.2, 0)
        resultsFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 40)
        resultsFrame.BackgroundTransparency = 0.1
        resultsFrame.Parent = screenGui

        local resultsCorner = Instance.new("UICorner")
        resultsCorner.CornerRadius = UDim.new(0, 12)
        resultsCorner.Parent = resultsFrame

        local winnerLabel = Instance.new("TextLabel")
        winnerLabel.Size = UDim2.new(1, 0, 0, 50)
        winnerLabel.BackgroundTransparency = 1
        winnerLabel.Text = "Winner: " .. winnerName
        winnerLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
        winnerLabel.TextSize = 30
        winnerLabel.Font = Enum.Font.GothamBold
        winnerLabel.Parent = resultsFrame

        -- Auto-destroy results screen
        task.delay(RoundConfig.ENDING_TIME, function()
            resultsFrame:Destroy()
        end)
    end)
end

local RoundConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RoundConfig"))

return RoundHUD
```

---

## Key Implementation Notes

1. **State machine** drives the entire game loop: Lobby -> Countdown -> Active -> Ending -> Intermission -> repeat.
2. **Map rotation** avoids recently played maps. Maps are stored in ServerStorage and cloned into workspace.
3. **Scoring modes**: LastStanding (battle royale), MostKills (deathmatch), MostPoints (objective), TeamBased, TimeAttack.
4. **Kill registration**: `RoundService.RegisterKill()` is called by your combat system. It updates scores and checks win conditions.
5. **Replicated values** (Phase, Timer, RoundNumber, MapName) let clients display HUD without constant RemoteEvent fire.
6. **Mid-round joins** send players to the lobby. They join the next round.
7. **Map spawn points** are BaseParts named "SpawnPoint" inside the map model.
8. **Kill feed** shows recent eliminations and auto-fades entries.

---

## 

---

## Learned Lessons

<!-- skill-evolve 에이전트가 자동으로 교훈 추가 -->

## Self-Evolution Protocol

이 스킬에서 에러가 발생하면:
1. 에러의 근본 원인을 분석한다
2. Learned Lessons 섹션에 교훈을 추가한다
3. 규칙화하여 반복 방지
4. SessionManager에 기록

```lua
local SM = require(game.ServerStorage._RobloxEngine.SessionManager)
SM.logAction("SKILL_ERROR", "[스킬명] | [에러]")
SM.logAction("SKILL_LEARNED", "[스킬명] | [교훈]")
```

**매 작업 시 Learned Lessons를 먼저 읽고 위반하지 않는지 확인.**

$ARGUMENTS

The user may specify:
- `$MIN_PLAYERS` -- Minimum players to start (default 2)
- `$ROUND_TIME` -- Active round duration in seconds (default 180)
- `$SCORING_MODE` -- "LastStanding", "MostKills", "MostPoints", "TeamBased", "TimeAttack"
- `$MAP_LIST` -- Custom map definitions
- `$MAP_VOTING` -- Whether to include map voting (default true)
- `$TEAM_MODE` -- Whether to split players into teams
- `$RESPAWN_IN_ROUND` -- Whether players respawn during active phase (default: depends on scoring mode)
- `$LOBBY_ACTIVITIES` -- Whether lobby has minigames/activities while waiting
