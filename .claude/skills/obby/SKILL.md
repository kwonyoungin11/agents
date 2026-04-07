---
name: obby-system
description: |
  Obstacle course (obby) system for Roblox. Checkpoint system with spawn saving,
  kill bricks, moving platforms, disappearing blocks, difficulty progression,
  speed-run timer, stage tracking, and leaderboard integration.
  키워드: 오비, 장애물 코스, 체크포인트, 킬 브릭, 이동 플랫폼, 타이머, 난이도 진행
allowed-tools:
  - Bash
  - Read
  - Edit
  - Write
  - Glob
  - Grep
effort: high
---

# Obstacle Course (Obby) System

Full obby framework for Roblox: stages with checkpoints, kill bricks, moving/disappearing platforms, difficulty scaling, speed-run timer, and stage persistence. All code is Luau.

---

## Architecture Overview

```
ReplicatedStorage/
  Shared/
    ObbyConfig.luau           -- Stage definitions, obstacle types, settings
ServerScriptService/
  Services/
    ObbyService.luau          -- Server: stage tracking, checkpoint saves, timer
StarterPlayerScripts/
  Controllers/
    ObbyHUD.luau              -- Client: timer display, stage counter, death counter
workspace/
  ObbyStages/
    Stage_001/                -- Each stage: Checkpoint, obstacles, KillBricks
    Stage_002/
    ...
```

---

## 1. Obby Configuration

```luau
-- ReplicatedStorage/Shared/ObbyConfig.luau
--!strict

export type ObstacleType = "KillBrick" | "MovingPlatform" | "DisappearingBlock" | "SpinningBar" | "Trampoline" | "Conveyor" | "WallJump" | "Zipline"

export type DifficultyTier = "Easy" | "Medium" | "Hard" | "Expert" | "Insane"

export type StageDefinition = {
    stageNumber: number,
    name: string,
    difficulty: DifficultyTier,
    parTime: number,       -- seconds for speed-run par
    obstacles: { ObstacleType },
    rewardCoins: number,
}

local ObbyConfig = {}

ObbyConfig.TOTAL_STAGES = 100
ObbyConfig.KILL_BRICK_TAG = "KillBrick"
ObbyConfig.CHECKPOINT_TAG = "ObbyCheckpoint"
ObbyConfig.RESPAWN_DELAY = 0.5
ObbyConfig.DEATH_HEIGHT = -50            -- Y threshold for falling death
ObbyConfig.MOVING_PLATFORM_SPEED = 6     -- studs/sec default
ObbyConfig.DISAPPEARING_VISIBLE_TIME = 3 -- seconds visible
ObbyConfig.DISAPPEARING_HIDDEN_TIME = 2  -- seconds hidden
ObbyConfig.SPINNING_BAR_SPEED = 60       -- degrees per second
ObbyConfig.TRAMPOLINE_FORCE = 100        -- upward velocity
ObbyConfig.CONVEYOR_SPEED = 20           -- studs/sec

ObbyConfig.DIFFICULTY_COLORS: { [DifficultyTier]: Color3 } = {
    Easy = Color3.fromRGB(100, 255, 100),
    Medium = Color3.fromRGB(255, 255, 100),
    Hard = Color3.fromRGB(255, 150, 50),
    Expert = Color3.fromRGB(255, 50, 50),
    Insane = Color3.fromRGB(180, 0, 255),
}

-- Auto-generate stage definitions
function ObbyConfig.GetStageDefinition(stageNumber: number): StageDefinition
    local difficulty: DifficultyTier
    if stageNumber <= 20 then
        difficulty = "Easy"
    elseif stageNumber <= 40 then
        difficulty = "Medium"
    elseif stageNumber <= 60 then
        difficulty = "Hard"
    elseif stageNumber <= 80 then
        difficulty = "Expert"
    else
        difficulty = "Insane"
    end

    local parTime = math.max(5, 30 - stageNumber * 0.2) -- tighter pars at higher stages

    return {
        stageNumber = stageNumber,
        name = "Stage " .. tostring(stageNumber),
        difficulty = difficulty,
        parTime = parTime,
        obstacles = {},
        rewardCoins = stageNumber * 5,
    }
end

return ObbyConfig
```

---

## 2. Server Obby Service

```luau
-- ServerScriptService/Services/ObbyService.luau
--!strict

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ObbyConfig = require(ReplicatedStorage.Shared.ObbyConfig)

local ObbyService = {}

local dataStore = DataStoreService:GetDataStore("ObbyProgress_v1")

type PlayerObbyData = {
    currentStage: number,
    highestStage: number,
    deaths: number,
    totalTime: number,
    bestTimes: { [number]: number }, -- stage -> best time
}

local playerData: { [Player]: PlayerObbyData } = {}
local playerTimers: { [Player]: number } = {} -- tick when timer started
local checkpointCFrames: { [number]: CFrame } = {} -- stage -> spawn CFrame

-------------------------------------------------
-- Data Persistence
-------------------------------------------------

local function loadData(player: Player): PlayerObbyData
    local success, data = pcall(function()
        return dataStore:GetAsync("obby_" .. player.UserId)
    end)
    if success and data then
        return data :: PlayerObbyData
    end
    return {
        currentStage = 1,
        highestStage = 1,
        deaths = 0,
        totalTime = 0,
        bestTimes = {},
    }
end

local function saveData(player: Player)
    local data = playerData[player]
    if not data then return end
    pcall(function()
        dataStore:SetAsync("obby_" .. player.UserId, data)
    end)
end

-------------------------------------------------
-- Checkpoint Registration
-------------------------------------------------

local function registerCheckpoint(part: BasePart)
    local stageNumber = part:GetAttribute("StageNumber") :: number?
    if not stageNumber then return end

    -- Store the CFrame slightly above the checkpoint
    checkpointCFrames[stageNumber] = part.CFrame + Vector3.new(0, 3, 0)

    -- Visual: stage number billboard
    local billboard = Instance.new("BillboardGui")
    billboard.Size = UDim2.fromOffset(100, 40)
    billboard.StudsOffset = Vector3.new(0, 4, 0)
    billboard.AlwaysOnTop = false
    billboard.Parent = part

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.Text = "Stage " .. tostring(stageNumber)
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.TextStrokeTransparency = 0.5
    label.TextSize = 20
    label.Font = Enum.Font.GothamBold
    label.Parent = billboard

    -- Touch detection for reaching checkpoint
    part.Touched:Connect(function(hit: BasePart)
        local character = hit.Parent :: Model?
        if not character then return end
        local player = Players:GetPlayerFromCharacter(character)
        if not player then return end

        local data = playerData[player]
        if not data then return end

        -- Only advance if this is the next stage or a later stage
        if stageNumber > data.currentStage then
            -- Award stage completion
            local prevStage = data.currentStage
            data.currentStage = stageNumber

            if stageNumber > data.highestStage then
                data.highestStage = stageNumber
            end

            -- Record time for completed stage
            local stageTime = 0
            if playerTimers[player] then
                stageTime = tick() - playerTimers[player]
                playerTimers[player] = tick() -- reset for next stage
            end

            -- Best time tracking
            local prevBest = data.bestTimes[prevStage]
            if not prevBest or stageTime < prevBest then
                data.bestTimes[prevStage] = stageTime
            end

            -- Award coins
            local stageDef = ObbyConfig.GetStageDefinition(prevStage)
            local ls = player:FindFirstChild("leaderstats")
            if ls then
                local coins = ls:FindFirstChild("Coins") :: IntValue?
                if coins then
                    coins.Value += stageDef.rewardCoins
                end
                local stageVal = ls:FindFirstChild("Stage") :: IntValue?
                if stageVal then
                    stageVal.Value = stageNumber
                end
            end

            -- Notify client
            local remotes = ReplicatedStorage:FindFirstChild("ObbyRemotes")
            if remotes then
                local stageEvent = remotes:FindFirstChild("StageReached") :: RemoteEvent
                if stageEvent then
                    stageEvent:FireClient(player, stageNumber, stageTime, stageDef.rewardCoins)
                end
            end
        end
    end)
end

-------------------------------------------------
-- Kill Bricks
-------------------------------------------------

local function setupKillBrick(part: BasePart)
    part.Touched:Connect(function(hit: BasePart)
        local character = hit.Parent :: Model?
        if not character then return end
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if humanoid and humanoid.Health > 0 then
            humanoid.Health = 0
        end
    end)
end

-------------------------------------------------
-- Moving Platforms
-------------------------------------------------

local function setupMovingPlatform(part: BasePart)
    local pointA = part.Position
    local offset = part:GetAttribute("MoveOffset") :: Vector3 or Vector3.new(10, 0, 0)
    local pointB = pointA + offset
    local speed = part:GetAttribute("Speed") :: number or ObbyConfig.MOVING_PLATFORM_SPEED
    local moveTime = offset.Magnitude / speed

    -- Continuous back-and-forth tween
    local function tweenLoop()
        local tweenToB = TweenService:Create(part, TweenInfo.new(moveTime, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
            Position = pointB,
        })
        local tweenToA = TweenService:Create(part, TweenInfo.new(moveTime, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
            Position = pointA,
        })

        while part.Parent do
            tweenToB:Play()
            tweenToB.Completed:Wait()
            tweenToA:Play()
            tweenToA.Completed:Wait()
        end
    end

    task.spawn(tweenLoop)
end

-------------------------------------------------
-- Disappearing Blocks
-------------------------------------------------

local function setupDisappearingBlock(part: BasePart)
    local visibleTime = part:GetAttribute("VisibleTime") :: number or ObbyConfig.DISAPPEARING_VISIBLE_TIME
    local hiddenTime = part:GetAttribute("HiddenTime") :: number or ObbyConfig.DISAPPEARING_HIDDEN_TIME
    local phaseOffset = part:GetAttribute("PhaseOffset") :: number or 0

    task.spawn(function()
        task.wait(phaseOffset) -- stagger different blocks

        while part.Parent do
            -- Visible phase
            part.Transparency = 0
            part.CanCollide = true
            task.wait(visibleTime)

            -- Fade out
            TweenService:Create(part, TweenInfo.new(0.3), { Transparency = 0.8 }):Play()
            task.wait(0.3)

            -- Hidden phase
            part.Transparency = 1
            part.CanCollide = false
            task.wait(hiddenTime)

            -- Fade in
            part.Transparency = 0.5
            part.CanCollide = true
            TweenService:Create(part, TweenInfo.new(0.3), { Transparency = 0 }):Play()
        end
    end)
end

-------------------------------------------------
-- Spinning Bar
-------------------------------------------------

local function setupSpinningBar(part: BasePart)
    local speed = part:GetAttribute("SpinSpeed") :: number or ObbyConfig.SPINNING_BAR_SPEED
    local axis = part:GetAttribute("SpinAxis") :: string or "Y"

    -- Kill on touch
    part.Touched:Connect(function(hit: BasePart)
        local character = hit.Parent :: Model?
        if not character then return end
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if humanoid and humanoid.Health > 0 then
            humanoid.Health = 0
        end
    end)

    -- Rotation loop
    RunService.Heartbeat:Connect(function(dt: number)
        local angleDelta = math.rad(speed * dt)
        if axis == "X" then
            part.CFrame *= CFrame.Angles(angleDelta, 0, 0)
        elseif axis == "Z" then
            part.CFrame *= CFrame.Angles(0, 0, angleDelta)
        else
            part.CFrame *= CFrame.Angles(0, angleDelta, 0)
        end
    end)
end

-------------------------------------------------
-- Trampoline
-------------------------------------------------

local function setupTrampoline(part: BasePart)
    local force = part:GetAttribute("BounceForce") :: number or ObbyConfig.TRAMPOLINE_FORCE

    part.Touched:Connect(function(hit: BasePart)
        local character = hit.Parent :: Model?
        if not character then return end
        local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
        if rootPart then
            rootPart.AssemblyLinearVelocity = Vector3.new(
                rootPart.AssemblyLinearVelocity.X,
                force,
                rootPart.AssemblyLinearVelocity.Z
            )
        end
    end)
end

-------------------------------------------------
-- Conveyor Belt
-------------------------------------------------

local function setupConveyor(part: BasePart)
    local speed = part:GetAttribute("ConveyorSpeed") :: number or ObbyConfig.CONVEYOR_SPEED
    local direction = part:GetAttribute("ConveyorDirection") :: Vector3 or part.CFrame.LookVector

    -- Use AssemblyLinearVelocity on the part itself for conveyor effect
    part.AssemblyLinearVelocity = direction.Unit * speed
    part.Anchored = false

    -- Keep conveyor in place with a BodyPosition equivalent
    local attachment = Instance.new("Attachment")
    attachment.Parent = part
    local alignPos = Instance.new("AlignPosition")
    alignPos.Mode = Enum.PositionAlignmentMode.OneAttachment
    alignPos.Attachment0 = attachment
    alignPos.Position = part.Position
    alignPos.MaxForce = math.huge
    alignPos.Responsiveness = 200
    alignPos.Parent = part

    local alignOri = Instance.new("AlignOrientation")
    alignOri.Mode = Enum.OrientationAlignmentMode.OneAttachment
    alignOri.Attachment0 = attachment
    alignOri.CFrame = part.CFrame - part.Position
    alignOri.MaxTorque = math.huge
    alignOri.Responsiveness = 200
    alignOri.Parent = part
end

-------------------------------------------------
-- Death / Respawn Handling
-------------------------------------------------

local function onPlayerDeath(player: Player)
    local data = playerData[player]
    if not data then return end

    data.deaths += 1

    -- Update death counter on client
    local remotes = ReplicatedStorage:FindFirstChild("ObbyRemotes")
    if remotes then
        local deathEvent = remotes:FindFirstChild("PlayerDied") :: RemoteEvent
        if deathEvent then
            deathEvent:FireClient(player, data.deaths)
        end
    end
end

local function teleportToCheckpoint(player: Player)
    local data = playerData[player]
    if not data then return end

    local checkpointCF = checkpointCFrames[data.currentStage]
    if not checkpointCF then
        -- Fallback to stage 1
        checkpointCF = checkpointCFrames[1] or CFrame.new(0, 10, 0)
    end

    local character = player.Character
    if character then
        local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
        if rootPart then
            rootPart.CFrame = checkpointCF
        end
    end
end

-------------------------------------------------
-- Fall Detection
-------------------------------------------------

local function checkFallDeath()
    for _, player in Players:GetPlayers() do
        if player.Character then
            local rootPart = player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
            if rootPart and rootPart.Position.Y < ObbyConfig.DEATH_HEIGHT then
                local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
                if humanoid and humanoid.Health > 0 then
                    humanoid.Health = 0
                end
            end
        end
    end
end

-------------------------------------------------
-- Init
-------------------------------------------------

function ObbyService.Init()
    -- Create remotes
    local remotesFolder = Instance.new("Folder")
    remotesFolder.Name = "ObbyRemotes"
    remotesFolder.Parent = ReplicatedStorage

    for _, name in { "StageReached", "PlayerDied", "TimerUpdate", "SkipStage" } do
        local remote = Instance.new("RemoteEvent")
        remote.Name = name
        remote.Parent = remotesFolder
    end

    -- Register obstacles by tag
    for _, part in CollectionService:GetTagged(ObbyConfig.CHECKPOINT_TAG) do
        registerCheckpoint(part :: BasePart)
    end
    CollectionService:GetInstanceAddedSignal(ObbyConfig.CHECKPOINT_TAG):Connect(function(inst)
        registerCheckpoint(inst :: BasePart)
    end)

    for _, part in CollectionService:GetTagged(ObbyConfig.KILL_BRICK_TAG) do
        setupKillBrick(part :: BasePart)
    end
    CollectionService:GetInstanceAddedSignal(ObbyConfig.KILL_BRICK_TAG):Connect(function(inst)
        setupKillBrick(inst :: BasePart)
    end)

    for _, part in CollectionService:GetTagged("MovingPlatform") do
        setupMovingPlatform(part :: BasePart)
    end
    CollectionService:GetInstanceAddedSignal("MovingPlatform"):Connect(function(inst)
        setupMovingPlatform(inst :: BasePart)
    end)

    for _, part in CollectionService:GetTagged("DisappearingBlock") do
        setupDisappearingBlock(part :: BasePart)
    end
    CollectionService:GetInstanceAddedSignal("DisappearingBlock"):Connect(function(inst)
        setupDisappearingBlock(inst :: BasePart)
    end)

    for _, part in CollectionService:GetTagged("SpinningBar") do
        setupSpinningBar(part :: BasePart)
    end

    for _, part in CollectionService:GetTagged("Trampoline") do
        setupTrampoline(part :: BasePart)
    end

    for _, part in CollectionService:GetTagged("Conveyor") do
        setupConveyor(part :: BasePart)
    end

    -- Player lifecycle
    Players.PlayerAdded:Connect(function(player: Player)
        local data = loadData(player)
        playerData[player] = data

        -- Create leaderstats
        local ls = Instance.new("Folder")
        ls.Name = "leaderstats"
        ls.Parent = player

        local stageVal = Instance.new("IntValue")
        stageVal.Name = "Stage"
        stageVal.Value = data.currentStage
        stageVal.Parent = ls

        local coinsVal = Instance.new("IntValue")
        coinsVal.Name = "Coins"
        coinsVal.Value = 0
        coinsVal.Parent = ls

        -- Start timer
        playerTimers[player] = tick()

        -- Character handling
        player.CharacterAdded:Connect(function(character: Model)
            local humanoid = character:WaitForChild("Humanoid") :: Humanoid

            -- Teleport to checkpoint on spawn
            task.wait(0.1)
            teleportToCheckpoint(player)

            humanoid.Died:Connect(function()
                onPlayerDeath(player)
                -- Auto respawn
                task.wait(ObbyConfig.RESPAWN_DELAY)
                player:LoadCharacter()
            end)
        end)
    end)

    Players.PlayerRemoving:Connect(function(player: Player)
        saveData(player)
        playerData[player] = nil
        playerTimers[player] = nil
    end)

    -- Fall detection loop
    RunService.Heartbeat:Connect(function()
        checkFallDeath()
    end)

    -- Periodic save
    task.spawn(function()
        while true do
            task.wait(60)
            for plr, _ in playerData do
                if plr.Parent then saveData(plr) end
            end
        end
    end)
end

return ObbyService
```

---

## 3. Client Obby HUD

```luau
-- StarterPlayerScripts/Controllers/ObbyHUD.luau
--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local ObbyHUD = {}

function ObbyHUD.Init()
    local remotes = ReplicatedStorage:WaitForChild("ObbyRemotes")

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "ObbyHUD"
    screenGui.ResetOnSpawn = false
    screenGui.Parent = playerGui

    -- Stage display
    local stageFrame = Instance.new("Frame")
    stageFrame.Size = UDim2.fromOffset(200, 50)
    stageFrame.Position = UDim2.new(0.5, -100, 0, 10)
    stageFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
    stageFrame.BackgroundTransparency = 0.3
    stageFrame.Parent = screenGui

    local stageCorner = Instance.new("UICorner")
    stageCorner.CornerRadius = UDim.new(0, 8)
    stageCorner.Parent = stageFrame

    local stageLabel = Instance.new("TextLabel")
    stageLabel.Size = UDim2.new(1, 0, 1, 0)
    stageLabel.BackgroundTransparency = 1
    stageLabel.Text = "Stage 1"
    stageLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    stageLabel.TextSize = 28
    stageLabel.Font = Enum.Font.GothamBold
    stageLabel.Parent = stageFrame

    -- Timer display
    local timerLabel = Instance.new("TextLabel")
    timerLabel.Size = UDim2.fromOffset(150, 30)
    timerLabel.Position = UDim2.new(0.5, -75, 0, 65)
    timerLabel.BackgroundTransparency = 1
    timerLabel.Text = "0:00.00"
    timerLabel.TextColor3 = Color3.fromRGB(255, 255, 100)
    timerLabel.TextSize = 22
    timerLabel.Font = Enum.Font.Code
    timerLabel.Parent = screenGui

    -- Death counter
    local deathLabel = Instance.new("TextLabel")
    deathLabel.Size = UDim2.fromOffset(120, 25)
    deathLabel.Position = UDim2.new(1, -130, 0, 10)
    deathLabel.BackgroundTransparency = 1
    deathLabel.Text = "Deaths: 0"
    deathLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
    deathLabel.TextSize = 18
    deathLabel.Font = Enum.Font.Gotham
    deathLabel.Parent = screenGui

    -- Timer update
    local startTick = tick()

    RunService.RenderStepped:Connect(function()
        local elapsed = tick() - startTick
        local minutes = math.floor(elapsed / 60)
        local seconds = elapsed % 60
        timerLabel.Text = string.format("%d:%05.2f", minutes, seconds)
    end)

    -- Event listeners
    local stageReached = remotes:WaitForChild("StageReached") :: RemoteEvent
    stageReached.OnClientEvent:Connect(function(stageNumber: number, stageTime: number, reward: number)
        stageLabel.Text = "Stage " .. tostring(stageNumber)
        startTick = tick() -- reset stage timer
    end)

    local deathEvent = remotes:WaitForChild("PlayerDied") :: RemoteEvent
    deathEvent.OnClientEvent:Connect(function(totalDeaths: number)
        deathLabel.Text = "Deaths: " .. tostring(totalDeaths)
    end)
end

return ObbyHUD
```

---

## Key Implementation Notes

1. **Checkpoint saving**: Player stage progress is saved to DataStore. On join, they respawn at their last checkpoint.
2. **CollectionService tags**: All obstacles are tagged (KillBrick, MovingPlatform, DisappearingBlock, etc.) for automatic setup. Just tag parts in Studio.
3. **Difficulty progression**: Stages 1-20 Easy, 21-40 Medium, etc. The config function auto-generates definitions.
4. **Disappearing blocks** use `PhaseOffset` attribute to stagger timing across a group of blocks.
5. **Moving platforms** use TweenService with `MoveOffset` attribute for the travel vector.
6. **Conveyors** use AlignPosition to stay in place while AssemblyLinearVelocity moves objects on top.
7. **Fall death** is checked every Heartbeat for players below `DEATH_HEIGHT` Y threshold.
8. **Auto-respawn** after a configurable delay -- obby players expect instant respawn.

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
- `$TOTAL_STAGES` -- Total number of stages (default 100)
- `$OBSTACLES` -- Which obstacle types to include
- `$TIMER_MODE` -- "per_stage" (resets each stage) or "total" (cumulative) or "both"
- `$RESPAWN_DELAY` -- Seconds before auto-respawn (default 0.5)
- `$SKIP_ENABLED` -- Whether players can skip stages (with cost)
- `$LEADERBOARD` -- Whether to include a speed-run leaderboard
- `$DIFFICULTY_SCALE` -- Custom difficulty tier boundaries
- `$REWARD_SYSTEM` -- Coins per stage completion formula
