---
name: wave-defense-system
description: |
  Wave defense / tower defense system for Roblox. Spawn scheduling with configurable
  enemy counts per wave, boss waves, difficulty scaling, intermission timers,
  per-wave rewards, and wave state machine.
  키워드: 웨이브 디펜스, 타워 디펜스, 적 스폰, 보스 웨이브, 라운드 보상, 난이도 조절
allowed-tools:
  - Bash
  - Read
  - Edit
  - Write
  - Glob
  - Grep
effort: high
---

# Wave Defense System

Server-authoritative wave defense system for Roblox with enemy spawning, scaling difficulty, boss waves, intermission, and rewards. All code is Luau.

---

## Architecture Overview

```
ReplicatedStorage/
  Shared/
    WaveConfig.luau           -- Wave definitions, enemy types, scaling
ServerScriptService/
  Services/
    WaveService.luau          -- Server: wave state machine, spawn logic
    EnemyService.luau         -- Server: enemy AI, pathing, health
StarterPlayerScripts/
  Controllers/
    WaveHUD.luau              -- Client: wave counter, timer, enemy count UI
```

---

## 1. Wave Configuration

```luau
-- ReplicatedStorage/Shared/WaveConfig.luau
--!strict

export type EnemyType = {
    id: string,
    displayName: string,
    modelName: string,
    baseHealth: number,
    baseDamage: number,
    moveSpeed: number,
    reward: number,           -- currency dropped on kill
    xpReward: number,
}

export type WaveSpawnEntry = {
    enemyId: string,
    count: number,
    spawnDelay: number,       -- seconds between each spawn in this group
    startDelay: number?,      -- seconds after wave start before this group begins
}

export type WaveDefinition = {
    waveNumber: number,
    isBossWave: boolean,
    spawns: { WaveSpawnEntry },
    bonusReward: number,      -- flat bonus currency for completing the wave
    intermissionTime: number, -- seconds before next wave
}

local WaveConfig = {}

WaveConfig.MAX_WAVES = 50
WaveConfig.DEFAULT_INTERMISSION = 15
WaveConfig.BOSS_INTERVAL = 5           -- boss every N waves
WaveConfig.BASE_ENEMY_SCALE = 1.0
WaveConfig.HEALTH_SCALE_PER_WAVE = 0.12 -- +12% HP per wave
WaveConfig.DAMAGE_SCALE_PER_WAVE = 0.08 -- +8% damage per wave
WaveConfig.COUNT_SCALE_PER_WAVE = 0.15   -- +15% enemy count per wave
WaveConfig.PLAYER_SCALE_FACTOR = 0.3    -- +30% per additional player

WaveConfig.EnemyTypes: { [string]: EnemyType } = {
    zombie = {
        id = "zombie",
        displayName = "Zombie",
        modelName = "ZombieModel",
        baseHealth = 100,
        baseDamage = 10,
        moveSpeed = 12,
        reward = 5,
        xpReward = 10,
    },
    skeleton = {
        id = "skeleton",
        displayName = "Skeleton",
        modelName = "SkeletonModel",
        baseHealth = 75,
        baseDamage = 15,
        moveSpeed = 16,
        reward = 8,
        xpReward = 15,
    },
    golem = {
        id = "golem",
        displayName = "Stone Golem",
        modelName = "GolemModel",
        baseHealth = 500,
        baseDamage = 30,
        moveSpeed = 8,
        reward = 25,
        xpReward = 50,
    },
    boss_dragon = {
        id = "boss_dragon",
        displayName = "Dragon Boss",
        modelName = "DragonBossModel",
        baseHealth = 5000,
        baseDamage = 50,
        moveSpeed = 10,
        reward = 200,
        xpReward = 500,
    },
}

-- Generate wave definitions procedurally
function WaveConfig.GenerateWave(waveNumber: number, playerCount: number): WaveDefinition
    local isBoss = (waveNumber % WaveConfig.BOSS_INTERVAL == 0)
    local playerScale = 1 + (playerCount - 1) * WaveConfig.PLAYER_SCALE_FACTOR
    local waveScale = 1 + (waveNumber - 1) * WaveConfig.COUNT_SCALE_PER_WAVE

    local spawns: { WaveSpawnEntry } = {}

    if isBoss then
        -- Boss wave: boss + escort enemies
        table.insert(spawns, {
            enemyId = "boss_dragon",
            count = 1,
            spawnDelay = 0,
            startDelay = 3,
        })
        table.insert(spawns, {
            enemyId = "skeleton",
            count = math.floor(5 * playerScale),
            spawnDelay = 1.5,
            startDelay = 0,
        })
    else
        -- Normal wave: mix of enemy types
        local zombieCount = math.floor(5 * waveScale * playerScale)
        local skeletonCount = math.floor(math.max(0, (waveNumber - 3)) * 2 * playerScale)

        table.insert(spawns, {
            enemyId = "zombie",
            count = zombieCount,
            spawnDelay = 0.8,
            startDelay = 0,
        })

        if skeletonCount > 0 then
            table.insert(spawns, {
                enemyId = "skeleton",
                count = skeletonCount,
                spawnDelay = 1.2,
                startDelay = 2,
            })
        end

        -- Golems start appearing at wave 8
        if waveNumber >= 8 then
            local golemCount = math.floor((waveNumber - 7) * 0.5 * playerScale)
            if golemCount > 0 then
                table.insert(spawns, {
                    enemyId = "golem",
                    count = golemCount,
                    spawnDelay = 3,
                    startDelay = 5,
                })
            end
        end
    end

    return {
        waveNumber = waveNumber,
        isBossWave = isBoss,
        spawns = spawns,
        bonusReward = math.floor(50 * waveNumber * (if isBoss then 3 else 1)),
        intermissionTime = if isBoss then 20 else WaveConfig.DEFAULT_INTERMISSION,
    }
end

-- Get scaled stats for a given wave
function WaveConfig.GetScaledStats(enemyId: string, waveNumber: number): (number, number)
    local enemyType = WaveConfig.EnemyTypes[enemyId]
    if not enemyType then return 100, 10 end

    local healthScale = 1 + (waveNumber - 1) * WaveConfig.HEALTH_SCALE_PER_WAVE
    local damageScale = 1 + (waveNumber - 1) * WaveConfig.DAMAGE_SCALE_PER_WAVE

    local scaledHealth = math.floor(enemyType.baseHealth * healthScale)
    local scaledDamage = math.floor(enemyType.baseDamage * damageScale)

    return scaledHealth, scaledDamage
end

return WaveConfig
```

---

## 2. Server Wave Service (State Machine)

```luau
-- ServerScriptService/Services/WaveService.luau
--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local WaveConfig = require(ReplicatedStorage.Shared.WaveConfig)

export type WaveState = "Idle" | "Intermission" | "Spawning" | "Active" | "BossActive" | "Completed" | "Failed"

local WaveService = {}

local currentWave = 0
local currentState: WaveState = "Idle"
local aliveEnemies: { Model } = {}
local totalEnemiesThisWave = 0
local spawnedCount = 0
local waveStartTime = 0

-- Replicated values for client HUD
local waveFolder: Folder
local waveNumberValue: IntValue
local stateValue: StringValue
local enemyCountValue: IntValue
local timerValue: NumberValue

-------------------------------------------------
-- Spawn Points
-------------------------------------------------

local function getSpawnPoints(): { BasePart }
    local folder = workspace:FindFirstChild("EnemySpawnPoints")
    if not folder then return {} end
    local points = {}
    for _, child in folder:GetChildren() do
        if child:IsA("BasePart") then
            table.insert(points, child)
        end
    end
    return points
end

local function getRandomSpawnPoint(): CFrame
    local points = getSpawnPoints()
    if #points == 0 then
        return CFrame.new(0, 5, 0)
    end
    local point = points[math.random(1, #points)]
    return point.CFrame
end

-------------------------------------------------
-- Enemy Spawning
-------------------------------------------------

local function spawnEnemy(enemyId: string, waveNumber: number): Model?
    local enemyType = WaveConfig.EnemyTypes[enemyId]
    if not enemyType then return nil end

    local modelsFolder = ServerStorage:FindFirstChild("EnemyModels")
    if not modelsFolder then
        warn("[WaveService] ServerStorage.EnemyModels not found")
        return nil
    end

    local template = modelsFolder:FindFirstChild(enemyType.modelName)
    if not template or not template:IsA("Model") then return nil end

    local enemy = template:Clone() :: Model
    local spawnCF = getRandomSpawnPoint()
    enemy:PivotTo(spawnCF)

    -- Set scaled health
    local scaledHealth, scaledDamage = WaveConfig.GetScaledStats(enemyId, waveNumber)
    local humanoid = enemy:FindFirstChildOfClass("Humanoid")
    if humanoid then
        humanoid.MaxHealth = scaledHealth
        humanoid.Health = scaledHealth
    end

    enemy:SetAttribute("EnemyId", enemyId)
    enemy:SetAttribute("Damage", scaledDamage)
    enemy:SetAttribute("Reward", enemyType.reward)
    enemy:SetAttribute("XPReward", enemyType.xpReward)
    enemy:SetAttribute("WaveNumber", waveNumber)

    -- Parent to workspace
    local enemyFolder = workspace:FindFirstChild("Enemies")
    if not enemyFolder then
        enemyFolder = Instance.new("Folder")
        enemyFolder.Name = "Enemies"
        enemyFolder.Parent = workspace
    end
    enemy.Parent = enemyFolder

    -- Track alive enemies
    table.insert(aliveEnemies, enemy)
    spawnedCount += 1

    -- Listen for death
    if humanoid then
        humanoid.Died:Connect(function()
            local idx = table.find(aliveEnemies, enemy)
            if idx then
                table.remove(aliveEnemies, idx)
            end

            -- Award kill reward to nearest/last-hit player (simplified)
            local reward = enemy:GetAttribute("Reward") :: number? or 0
            local xpReward = enemy:GetAttribute("XPReward") :: number? or 0

            -- Attribute-based reward distribution
            local lastHitUserId = enemy:GetAttribute("LastHitBy") :: number?
            if lastHitUserId then
                local plr = Players:GetPlayerByUserId(lastHitUserId)
                if plr then
                    local ls = plr:FindFirstChild("leaderstats")
                    if ls then
                        local coins = ls:FindFirstChild("Coins") :: IntValue?
                        if coins then coins.Value += reward end
                        local xp = ls:FindFirstChild("XP") :: IntValue?
                        if xp then xp.Value += xpReward end
                    end
                end
            end

            -- Update enemy count display
            enemyCountValue.Value = #aliveEnemies

            -- Check if wave is cleared
            if #aliveEnemies == 0 and currentState ~= "Spawning" then
                WaveService._OnWaveCleared()
            end

            -- Cleanup corpse after delay
            task.delay(3, function()
                if enemy.Parent then
                    enemy:Destroy()
                end
            end)
        end)
    end

    return enemy
end

-------------------------------------------------
-- Wave Execution
-------------------------------------------------

local function executeWaveSpawns(waveDef: WaveConfig.WaveDefinition)
    currentState = "Spawning"
    stateValue.Value = currentState
    spawnedCount = 0

    local spawnThreads = {}

    for _, entry in waveDef.spawns do
        local thread = task.spawn(function()
            if entry.startDelay and entry.startDelay > 0 then
                task.wait(entry.startDelay)
            end

            for i = 1, entry.count do
                if currentState == "Failed" then return end
                spawnEnemy(entry.enemyId, waveDef.waveNumber)
                if i < entry.count then
                    task.wait(entry.spawnDelay)
                end
            end
        end)
        table.insert(spawnThreads, thread)
    end

    -- Wait for all spawn groups to finish, then transition to Active
    task.spawn(function()
        -- Simple wait: calculate max spawn duration
        local maxDuration = 0
        for _, entry in waveDef.spawns do
            local duration = (entry.startDelay or 0) + (entry.count - 1) * entry.spawnDelay
            maxDuration = math.max(maxDuration, duration)
        end
        task.wait(maxDuration + 1)

        if currentState == "Spawning" then
            currentState = if waveDef.isBossWave then "BossActive" else "Active"
            stateValue.Value = currentState
        end
    end)
end

function WaveService._OnWaveCleared()
    local waveDef = WaveConfig.GenerateWave(currentWave, #Players:GetPlayers())

    -- Distribute wave bonus reward
    for _, plr in Players:GetPlayers() do
        local ls = plr:FindFirstChild("leaderstats")
        if ls then
            local coins = ls:FindFirstChild("Coins") :: IntValue?
            if coins then coins.Value += waveDef.bonusReward end
        end
    end

    -- Notify clients
    local remotes = ReplicatedStorage:FindFirstChild("WaveRemotes")
    if remotes then
        local cleared = remotes:FindFirstChild("WaveCleared") :: RemoteEvent
        if cleared then
            cleared:FireAllClients(currentWave, waveDef.bonusReward)
        end
    end

    -- Check if all waves done
    if currentWave >= WaveConfig.MAX_WAVES then
        currentState = "Completed"
        stateValue.Value = currentState
        return
    end

    -- Start intermission
    WaveService._StartIntermission(waveDef.intermissionTime)
end

function WaveService._StartIntermission(duration: number)
    currentState = "Intermission"
    stateValue.Value = currentState

    task.spawn(function()
        local remaining = duration
        while remaining > 0 do
            timerValue.Value = remaining
            task.wait(1)
            remaining -= 1
        end
        timerValue.Value = 0
        WaveService.StartNextWave()
    end)
end

-------------------------------------------------
-- Public API
-------------------------------------------------

function WaveService.StartNextWave()
    currentWave += 1
    waveNumberValue.Value = currentWave

    local playerCount = #Players:GetPlayers()
    local waveDef = WaveConfig.GenerateWave(currentWave, playerCount)

    totalEnemiesThisWave = 0
    for _, entry in waveDef.spawns do
        totalEnemiesThisWave += entry.count
    end

    aliveEnemies = {}
    waveStartTime = tick()

    -- Notify clients
    local remotes = ReplicatedStorage:FindFirstChild("WaveRemotes")
    if remotes then
        local started = remotes:FindFirstChild("WaveStarted") :: RemoteEvent
        if started then
            started:FireAllClients(currentWave, waveDef.isBossWave, totalEnemiesThisWave)
        end
    end

    executeWaveSpawns(waveDef)
end

function WaveService.GetCurrentWave(): number
    return currentWave
end

function WaveService.GetState(): WaveState
    return currentState
end

function WaveService.GetAliveCount(): number
    return #aliveEnemies
end

function WaveService.ForceStartWave(waveNum: number)
    currentWave = waveNum - 1
    WaveService.StartNextWave()
end

function WaveService.Init()
    -- Create replicated values
    waveFolder = Instance.new("Folder")
    waveFolder.Name = "WaveStatus"
    waveFolder.Parent = ReplicatedStorage

    waveNumberValue = Instance.new("IntValue")
    waveNumberValue.Name = "WaveNumber"
    waveNumberValue.Value = 0
    waveNumberValue.Parent = waveFolder

    stateValue = Instance.new("StringValue")
    stateValue.Name = "State"
    stateValue.Value = "Idle"
    stateValue.Parent = waveFolder

    enemyCountValue = Instance.new("IntValue")
    enemyCountValue.Name = "EnemyCount"
    enemyCountValue.Value = 0
    enemyCountValue.Parent = waveFolder

    timerValue = Instance.new("NumberValue")
    timerValue.Name = "Timer"
    timerValue.Value = 0
    timerValue.Parent = waveFolder

    -- Create remotes
    local remotesFolder = Instance.new("Folder")
    remotesFolder.Name = "WaveRemotes"
    remotesFolder.Parent = ReplicatedStorage

    for _, name in { "WaveStarted", "WaveCleared", "WaveFailed", "RequestSkipIntermission" } do
        local remote = Instance.new("RemoteEvent")
        remote.Name = name
        remote.Parent = remotesFolder
    end

    -- Skip intermission vote (simplified: first request skips)
    local skipRemote = remotesFolder:FindFirstChild("RequestSkipIntermission") :: RemoteEvent
    skipRemote.OnServerEvent:Connect(function(_player: Player)
        if currentState == "Intermission" then
            timerValue.Value = 0
        end
    end)

    -- Auto-start first wave after short delay
    task.delay(5, function()
        WaveService._StartIntermission(WaveConfig.DEFAULT_INTERMISSION)
    end)
end

return WaveService
```

---

## 3. Client Wave HUD

```luau
-- StarterPlayerScripts/Controllers/WaveHUD.luau
--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local WaveHUD = {}

function WaveHUD.Init()
    local waveStatus = ReplicatedStorage:WaitForChild("WaveStatus")
    local waveNumber = waveStatus:WaitForChild("WaveNumber") :: IntValue
    local state = waveStatus:WaitForChild("State") :: StringValue
    local enemyCount = waveStatus:WaitForChild("EnemyCount") :: IntValue
    local timer = waveStatus:WaitForChild("Timer") :: NumberValue

    -- Create ScreenGui
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "WaveHUD"
    screenGui.ResetOnSpawn = false
    screenGui.Parent = playerGui

    local frame = Instance.new("Frame")
    frame.Name = "WaveInfo"
    frame.Size = UDim2.fromOffset(300, 120)
    frame.Position = UDim2.new(0.5, -150, 0, 10)
    frame.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
    frame.BackgroundTransparency = 0.3
    frame.Parent = screenGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = frame

    local waveLabel = Instance.new("TextLabel")
    waveLabel.Name = "WaveLabel"
    waveLabel.Size = UDim2.new(1, 0, 0, 40)
    waveLabel.BackgroundTransparency = 1
    waveLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    waveLabel.TextSize = 28
    waveLabel.Font = Enum.Font.GothamBold
    waveLabel.Text = "Wave 0"
    waveLabel.Parent = frame

    local stateLabel = Instance.new("TextLabel")
    stateLabel.Name = "StateLabel"
    stateLabel.Size = UDim2.new(1, 0, 0, 30)
    stateLabel.Position = UDim2.fromOffset(0, 40)
    stateLabel.BackgroundTransparency = 1
    stateLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
    stateLabel.TextSize = 18
    stateLabel.Font = Enum.Font.Gotham
    stateLabel.Text = "Waiting..."
    stateLabel.Parent = frame

    local enemyLabel = Instance.new("TextLabel")
    enemyLabel.Name = "EnemyLabel"
    enemyLabel.Size = UDim2.new(1, 0, 0, 30)
    enemyLabel.Position = UDim2.fromOffset(0, 70)
    enemyLabel.BackgroundTransparency = 1
    enemyLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
    enemyLabel.TextSize = 18
    enemyLabel.Font = Enum.Font.Gotham
    enemyLabel.Text = ""
    enemyLabel.Parent = frame

    -- Update bindings
    waveNumber.Changed:Connect(function(val)
        waveLabel.Text = "Wave " .. tostring(val)
    end)

    state.Changed:Connect(function(val)
        if val == "Intermission" then
            stateLabel.Text = "Next wave in..."
        elseif val == "Spawning" or val == "Active" then
            stateLabel.Text = "Wave in progress"
        elseif val == "BossActive" then
            stateLabel.Text = "BOSS WAVE!"
            stateLabel.TextColor3 = Color3.fromRGB(255, 50, 50)
        elseif val == "Completed" then
            stateLabel.Text = "All waves cleared!"
            stateLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
        else
            stateLabel.Text = val
            stateLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
        end
    end)

    enemyCount.Changed:Connect(function(val)
        enemyLabel.Text = if val > 0 then "Enemies: " .. tostring(val) else ""
    end)

    timer.Changed:Connect(function(val)
        if val > 0 and state.Value == "Intermission" then
            stateLabel.Text = "Next wave in " .. tostring(math.ceil(val)) .. "s"
        end
    end)
end

return WaveHUD
```

---

## Key Implementation Notes

1. **Procedural wave generation**: `GenerateWave()` dynamically creates wave definitions based on wave number and player count. No need to hand-author 50 waves.
2. **Scaling**: Health, damage, and enemy count all scale independently. Player count adds extra enemies via `PLAYER_SCALE_FACTOR`.
3. **Boss waves** occur every N waves (default 5). They spawn a single boss plus escort enemies.
4. **State machine**: Idle -> Intermission -> Spawning -> Active/BossActive -> (Cleared) -> Intermission -> ... -> Completed.
5. **Replicated values** (IntValue, StringValue) provide real-time data to all clients without constant RemoteEvent firing.
6. **Kill rewards** use a `LastHitBy` attribute on the enemy model. Your damage system should set this attribute when dealing damage.
7. **Spawn groups** run concurrently via `task.spawn`, each with independent start delays and spawn intervals.

---

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

The user may specify:
- `$MAX_WAVES` -- Total number of waves (default 50)
- `$BOSS_INTERVAL` -- Boss wave every N waves (default 5)
- `$ENEMY_TYPES` -- Custom enemy type definitions
- `$SCALING_MODE` -- "linear", "exponential", or "custom" for wave scaling
- `$INTERMISSION_TIME` -- Default seconds between waves (default 15)
- `$PATH_BASED` -- If true, enemies follow a predefined path (tower defense style) instead of free roam
- `$MULTIPLAYER_SCALING` -- Whether to scale for player count (default true)
- `$REWARD_SYSTEM` -- "per_kill", "per_wave", or "both" (default "both")
