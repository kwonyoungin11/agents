---
name: boss-fight-system
description: |
  Boss fight system for Roblox with multiple phases, phase transitions with VFX,
  enrage timer, unique attack patterns per phase, health gates, aggro system,
  and boss arena management.
  키워드: 보스 전투, 페이즈 전환, 분노 타이머, 공격 패턴, 체력 게이지, 보스 레이드
allowed-tools:
  - Bash
  - Read
  - Edit
  - Write
  - Glob
  - Grep
effort: high
---

# Boss Fight System

Multi-phase boss fight system for Roblox with health gates, unique attack patterns, enrage timers, VFX transitions, and arena management. All code is Luau.

---

## Architecture Overview

```
ReplicatedStorage/
  Shared/
    BossConfig.luau           -- Boss definitions, phases, attacks
ServerScriptService/
  Services/
    BossService.luau          -- Server: boss state, phase logic, attacks
    BossAI.luau               -- Server: AI decision making, targeting
StarterPlayerScripts/
  Controllers/
    BossUI.luau               -- Client: health bar, phase indicator, enrage warning
```

---

## 1. Boss Configuration

```luau
-- ReplicatedStorage/Shared/BossConfig.luau
--!strict

export type AttackPattern = {
    name: string,
    damage: number,
    range: number,            -- studs
    cooldown: number,         -- seconds
    castTime: number,         -- seconds of wind-up (telegraphed to players)
    areaType: "Single" | "Cone" | "Circle" | "Line" | "Arena",
    areaSize: number,         -- radius for Circle, width for Cone/Line
    telegraph: string?,       -- visual indicator type: "RedZone", "Beam", "Ring"
    statusEffect: string?,    -- e.g. "Slow", "Burn", "Stun"
    statusDuration: number?,
}

export type BossPhase = {
    phaseNumber: number,
    name: string,
    healthThreshold: number,  -- transitions when health drops to this % (0-1)
    attacks: { AttackPattern },
    moveSpeed: number,
    damageMultiplier: number,
    specialMechanic: string?, -- key for unique phase behavior
    transitionDuration: number, -- seconds of invulnerability during transition
    transitionVFX: string,    -- "Explosion", "DarkAura", "Lightning", "FirePillar"
    music: string?,           -- sound asset id
}

export type BossDefinition = {
    id: string,
    displayName: string,
    modelName: string,
    maxHealth: number,
    phases: { BossPhase },
    enrageTime: number,       -- seconds before enrage
    enrageDamageMultiplier: number,
    enrageMoveSpeedMultiplier: number,
    arenaSize: number?,       -- radius of boss arena (nil = no arena)
    minPlayers: number,       -- minimum players to start
    maxPlayers: number,       -- maximum players in arena
}

local BossConfig = {}

BossConfig.Bosses: { [string]: BossDefinition } = {
    shadow_lord = {
        id = "shadow_lord",
        displayName = "Shadow Lord Malachar",
        modelName = "ShadowLordModel",
        maxHealth = 50000,
        enrageTime = 300,      -- 5 minutes
        enrageDamageMultiplier = 2.5,
        enrageMoveSpeedMultiplier = 1.5,
        arenaSize = 80,
        minPlayers = 1,
        maxPlayers = 8,
        phases = {
            {
                phaseNumber = 1,
                name = "Shadow Dance",
                healthThreshold = 1.0,
                attacks = {
                    {
                        name = "Shadow Slash",
                        damage = 25,
                        range = 12,
                        cooldown = 3,
                        castTime = 0.5,
                        areaType = "Cone",
                        areaSize = 8,
                        telegraph = "RedZone",
                        statusEffect = nil,
                        statusDuration = nil,
                    },
                    {
                        name = "Dark Orb",
                        damage = 40,
                        range = 50,
                        cooldown = 8,
                        castTime = 1.5,
                        areaType = "Circle",
                        areaSize = 10,
                        telegraph = "Ring",
                        statusEffect = "Slow",
                        statusDuration = 3,
                    },
                },
                moveSpeed = 20,
                damageMultiplier = 1.0,
                specialMechanic = nil,
                transitionDuration = 3,
                transitionVFX = "DarkAura",
                music = nil,
            },
            {
                phaseNumber = 2,
                name = "Umbral Fury",
                healthThreshold = 0.6,
                attacks = {
                    {
                        name = "Shadow Slash",
                        damage = 35,
                        range = 12,
                        cooldown = 2,
                        castTime = 0.4,
                        areaType = "Cone",
                        areaSize = 10,
                        telegraph = "RedZone",
                        statusEffect = nil,
                        statusDuration = nil,
                    },
                    {
                        name = "Void Eruption",
                        damage = 60,
                        range = 0,
                        cooldown = 15,
                        castTime = 3,
                        areaType = "Arena",
                        areaSize = 0,
                        telegraph = "Ring",
                        statusEffect = "Burn",
                        statusDuration = 5,
                    },
                    {
                        name = "Shadow Clone Summon",
                        damage = 0,
                        range = 0,
                        cooldown = 25,
                        castTime = 2,
                        areaType = "Arena",
                        areaSize = 0,
                        telegraph = nil,
                        statusEffect = nil,
                        statusDuration = nil,
                    },
                },
                moveSpeed = 24,
                damageMultiplier = 1.3,
                specialMechanic = "shadow_clones",
                transitionDuration = 4,
                transitionVFX = "Explosion",
                music = nil,
            },
            {
                phaseNumber = 3,
                name = "Final Shadow",
                healthThreshold = 0.25,
                attacks = {
                    {
                        name = "Oblivion Beam",
                        damage = 80,
                        range = 60,
                        cooldown = 6,
                        castTime = 2,
                        areaType = "Line",
                        areaSize = 6,
                        telegraph = "Beam",
                        statusEffect = "Stun",
                        statusDuration = 2,
                    },
                    {
                        name = "Shadow Nova",
                        damage = 100,
                        range = 0,
                        cooldown = 20,
                        castTime = 4,
                        areaType = "Arena",
                        areaSize = 0,
                        telegraph = "Ring",
                        statusEffect = nil,
                        statusDuration = nil,
                    },
                },
                moveSpeed = 28,
                damageMultiplier = 1.8,
                specialMechanic = "darkness_mechanic",
                transitionDuration = 5,
                transitionVFX = "FirePillar",
                music = nil,
            },
        },
    },
}

return BossConfig
```

---

## 2. Server Boss Service

```luau
-- ServerScriptService/Services/BossService.luau
--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")

local BossConfig = require(ReplicatedStorage.Shared.BossConfig)

type BossInstance = {
    bossId: string,
    model: Model,
    currentHealth: number,
    maxHealth: number,
    currentPhase: number,
    isTransitioning: boolean,
    isEnraged: boolean,
    startTime: number,
    participants: { Player },
    attackCooldowns: { [string]: number },
    isAlive: boolean,
    targetPlayer: Player?,
}

local BossService = {}

local activeBosses: { [string]: BossInstance } = {}

-------------------------------------------------
-- Telegraph VFX (server creates parts clients see)
-------------------------------------------------

local function createTelegraph(position: Vector3, attackPattern: BossConfig.AttackPattern, direction: Vector3?)
    local telegraph = attackPattern.telegraph
    if not telegraph then return end

    local part = Instance.new("Part")
    part.Name = "Telegraph"
    part.Anchored = true
    part.CanCollide = false
    part.Material = Enum.Material.Neon
    part.Color = Color3.fromRGB(255, 50, 50)
    part.Transparency = 0.5
    part.CastShadow = false

    if attackPattern.areaType == "Circle" then
        part.Shape = Enum.PartType.Cylinder
        local diameter = attackPattern.areaSize * 2
        part.Size = Vector3.new(0.2, diameter, diameter)
        part.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
    elseif attackPattern.areaType == "Cone" then
        part.Shape = Enum.PartType.Block
        part.Size = Vector3.new(attackPattern.areaSize, 0.2, attackPattern.range)
        local dir = direction or Vector3.new(0, 0, 1)
        part.CFrame = CFrame.lookAt(position, position + dir) * CFrame.new(0, 0, -attackPattern.range / 2)
    elseif attackPattern.areaType == "Line" then
        part.Shape = Enum.PartType.Block
        part.Size = Vector3.new(attackPattern.areaSize, 0.2, attackPattern.range)
        local dir = direction or Vector3.new(0, 0, 1)
        part.CFrame = CFrame.lookAt(position, position + dir) * CFrame.new(0, 0, -attackPattern.range / 2)
    elseif attackPattern.areaType == "Arena" then
        -- Full arena ring effect
        part.Shape = Enum.PartType.Cylinder
        part.Size = Vector3.new(0.3, 160, 160)
        part.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
        part.Transparency = 0.7
    end

    part.Parent = workspace

    -- Pulse transparency then destroy
    task.spawn(function()
        local elapsed = 0
        while elapsed < attackPattern.castTime do
            local alpha = math.sin(elapsed * 8) * 0.3
            part.Transparency = 0.4 + alpha
            elapsed += RunService.Heartbeat:Wait()
        end
        part:Destroy()
    end)
end

-------------------------------------------------
-- Attack Execution
-------------------------------------------------

local function executeAttack(boss: BossInstance, attack: BossConfig.AttackPattern)
    local model = boss.model
    local primaryPart = model.PrimaryPart
    if not primaryPart then return end

    local bossPos = primaryPart.Position
    local target = boss.targetPlayer
    local targetPos: Vector3

    if target and target.Character then
        local rootPart = target.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
        if rootPart then
            targetPos = rootPart.Position
        else
            targetPos = bossPos + Vector3.new(0, 0, 10)
        end
    else
        targetPos = bossPos + Vector3.new(0, 0, 10)
    end

    local direction = (targetPos - bossPos).Unit

    -- Show telegraph
    local telegraphPos = if attack.areaType == "Circle" then targetPos else bossPos
    createTelegraph(telegraphPos, attack, direction)

    -- Wait for cast time
    task.wait(attack.castTime)

    if not boss.isAlive then return end

    -- Apply damage
    local definition = BossConfig.Bosses[boss.bossId]
    if not definition then return end
    local phase = definition.phases[boss.currentPhase]
    if not phase then return end

    local damageMultiplier = phase.damageMultiplier * (if boss.isEnraged then definition.enrageDamageMultiplier else 1)
    local finalDamage = attack.damage * damageMultiplier

    for _, participant in boss.participants do
        if not participant.Character then continue end
        local rootPart = participant.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
        local humanoid = participant.Character:FindFirstChildOfClass("Humanoid")
        if not rootPart or not humanoid then continue end

        local playerPos = rootPart.Position
        local hit = false

        if attack.areaType == "Circle" then
            hit = (playerPos - targetPos).Magnitude <= attack.areaSize
        elseif attack.areaType == "Cone" then
            local toPlayer = (playerPos - bossPos)
            local dist = toPlayer.Magnitude
            if dist <= attack.range then
                local angle = math.acos(math.clamp(toPlayer.Unit:Dot(direction), -1, 1))
                hit = angle <= math.rad(30)
            end
        elseif attack.areaType == "Line" then
            local toPlayer = playerPos - bossPos
            local proj = toPlayer:Dot(direction)
            if proj > 0 and proj <= attack.range then
                local perpDist = (toPlayer - direction * proj).Magnitude
                hit = perpDist <= attack.areaSize / 2
            end
        elseif attack.areaType == "Arena" then
            hit = true -- hits everyone in the arena
        elseif attack.areaType == "Single" then
            hit = (playerPos - bossPos).Magnitude <= attack.range and participant == target
        end

        if hit then
            humanoid:TakeDamage(finalDamage)

            -- Apply status effect
            if attack.statusEffect and attack.statusDuration then
                local char = participant.Character :: Model
                char:SetAttribute("StatusEffect", attack.statusEffect)
                char:SetAttribute("StatusExpiry", tick() + attack.statusDuration)

                if attack.statusEffect == "Slow" then
                    local hum = char:FindFirstChildOfClass("Humanoid")
                    if hum then
                        local origSpeed = hum.WalkSpeed
                        hum.WalkSpeed = origSpeed * 0.4
                        task.delay(attack.statusDuration, function()
                            if hum and hum.Parent then
                                hum.WalkSpeed = origSpeed
                            end
                        end)
                    end
                elseif attack.statusEffect == "Stun" then
                    local hum = char:FindFirstChildOfClass("Humanoid")
                    if hum then
                        local origSpeed = hum.WalkSpeed
                        hum.WalkSpeed = 0
                        hum.JumpPower = 0
                        task.delay(attack.statusDuration, function()
                            if hum and hum.Parent then
                                hum.WalkSpeed = origSpeed
                                hum.JumpPower = 50
                            end
                        end)
                    end
                end
            end
        end
    end
end

-------------------------------------------------
-- Phase Transitions
-------------------------------------------------

local function transitionToPhase(boss: BossInstance, phaseNumber: number)
    local definition = BossConfig.Bosses[boss.bossId]
    if not definition then return end

    local newPhase = definition.phases[phaseNumber]
    if not newPhase then return end

    boss.isTransitioning = true

    -- Notify clients of phase transition
    local remotes = ReplicatedStorage:FindFirstChild("BossRemotes")
    if remotes then
        local phaseEvent = remotes:FindFirstChild("PhaseTransition") :: RemoteEvent
        if phaseEvent then
            phaseEvent:FireAllClients(boss.bossId, phaseNumber, newPhase.name, newPhase.transitionVFX)
        end
    end

    -- Create transition VFX on server (visible to all)
    local primaryPart = boss.model.PrimaryPart
    if primaryPart then
        local vfx = newPhase.transitionVFX

        if vfx == "Explosion" then
            local explosion = Instance.new("Explosion")
            explosion.Position = primaryPart.Position
            explosion.BlastRadius = 0
            explosion.BlastPressure = 0
            explosion.Parent = workspace
        elseif vfx == "DarkAura" then
            local particle = Instance.new("ParticleEmitter")
            particle.Color = ColorSequence.new(Color3.fromRGB(50, 0, 80))
            particle.Size = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 5),
                NumberSequenceKeypoint.new(1, 0),
            })
            particle.Lifetime = NumberRange.new(1, 2)
            particle.Rate = 100
            particle.Speed = NumberRange.new(10, 20)
            particle.SpreadAngle = Vector2.new(360, 360)
            particle.Parent = primaryPart
            task.delay(newPhase.transitionDuration, function()
                particle:Destroy()
            end)
        elseif vfx == "FirePillar" then
            local beam = Instance.new("Part")
            beam.Anchored = true
            beam.CanCollide = false
            beam.Material = Enum.Material.Neon
            beam.Color = Color3.fromRGB(255, 100, 0)
            beam.Size = Vector3.new(6, 200, 6)
            beam.CFrame = CFrame.new(primaryPart.Position + Vector3.new(0, 100, 0))
            beam.Transparency = 0.3
            beam.Parent = workspace
            task.delay(newPhase.transitionDuration, function()
                beam:Destroy()
            end)
        end
    end

    -- Boss is invulnerable during transition
    task.wait(newPhase.transitionDuration)

    boss.currentPhase = phaseNumber
    boss.isTransitioning = false
    boss.attackCooldowns = {} -- reset cooldowns on phase change
end

-------------------------------------------------
-- Boss AI Loop
-------------------------------------------------

local function updateBossAI(boss: BossInstance)
    if not boss.isAlive or boss.isTransitioning then return end

    local definition = BossConfig.Bosses[boss.bossId]
    if not definition then return end
    local phase = definition.phases[boss.currentPhase]
    if not phase then return end

    -- Check enrage timer
    if not boss.isEnraged then
        local elapsed = tick() - boss.startTime
        if elapsed >= definition.enrageTime then
            boss.isEnraged = true
            local remotes = ReplicatedStorage:FindFirstChild("BossRemotes")
            if remotes then
                local enrageEvent = remotes:FindFirstChild("BossEnraged") :: RemoteEvent
                if enrageEvent then
                    enrageEvent:FireAllClients(boss.bossId)
                end
            end
        end
    end

    -- Check health gate for phase transition
    local healthPercent = boss.currentHealth / boss.maxHealth
    for i = boss.currentPhase + 1, #definition.phases do
        local nextPhase = definition.phases[i]
        if healthPercent <= nextPhase.healthThreshold then
            transitionToPhase(boss, i)
            return
        end
    end

    -- Target selection: pick closest alive player
    local closestDist = math.huge
    local closestPlayer: Player? = nil
    local primaryPart = boss.model.PrimaryPart
    if not primaryPart then return end

    for _, participant in boss.participants do
        if participant.Character then
            local rootPart = participant.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
            local humanoid = participant.Character:FindFirstChildOfClass("Humanoid")
            if rootPart and humanoid and humanoid.Health > 0 then
                local dist = (rootPart.Position - primaryPart.Position).Magnitude
                if dist < closestDist then
                    closestDist = dist
                    closestPlayer = participant
                end
            end
        end
    end
    boss.targetPlayer = closestPlayer

    -- Choose and execute an attack
    local now = tick()
    for _, attack in phase.attacks do
        local lastUsed = boss.attackCooldowns[attack.name] or 0
        if now - lastUsed >= attack.cooldown then
            -- Range check for non-arena attacks
            if attack.areaType == "Arena" or closestDist <= attack.range * 1.5 then
                boss.attackCooldowns[attack.name] = now
                task.spawn(function()
                    executeAttack(boss, attack)
                end)
                return -- one attack per tick
            end
        end
    end

    -- If no attack available, move toward target
    if closestPlayer and closestPlayer.Character then
        local targetRoot = closestPlayer.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
        if targetRoot then
            local humanoid = boss.model:FindFirstChildOfClass("Humanoid")
            if humanoid then
                local speed = phase.moveSpeed * (if boss.isEnraged then definition.enrageMoveSpeedMultiplier else 1)
                humanoid.WalkSpeed = speed
                humanoid:MoveTo(targetRoot.Position)
            end
        end
    end
end

-------------------------------------------------
-- Boss Damage Handling
-------------------------------------------------

function BossService.DamageBoss(bossId: string, amount: number, attacker: Player?)
    local boss = activeBosses[bossId]
    if not boss or not boss.isAlive or boss.isTransitioning then return end

    boss.currentHealth = math.max(0, boss.currentHealth - amount)

    -- Update replicated health
    local remotes = ReplicatedStorage:FindFirstChild("BossRemotes")
    if remotes then
        local healthEvent = remotes:FindFirstChild("HealthUpdate") :: RemoteEvent
        if healthEvent then
            healthEvent:FireAllClients(bossId, boss.currentHealth, boss.maxHealth)
        end
    end

    -- Check death
    if boss.currentHealth <= 0 then
        BossService._OnBossDeath(boss)
    end
end

function BossService._OnBossDeath(boss: BossInstance)
    boss.isAlive = false

    -- Notify clients
    local remotes = ReplicatedStorage:FindFirstChild("BossRemotes")
    if remotes then
        local deathEvent = remotes:FindFirstChild("BossDefeated") :: RemoteEvent
        if deathEvent then
            deathEvent:FireAllClients(boss.bossId)
        end
    end

    -- Distribute rewards
    for _, participant in boss.participants do
        local ls = participant:FindFirstChild("leaderstats")
        if ls then
            local coins = ls:FindFirstChild("Coins") :: IntValue?
            if coins then coins.Value += 1000 end
        end
    end

    -- Death VFX and cleanup
    task.delay(5, function()
        if boss.model.Parent then
            boss.model:Destroy()
        end
        activeBosses[boss.bossId] = nil
    end)
end

-------------------------------------------------
-- Spawn Boss
-------------------------------------------------

function BossService.SpawnBoss(bossId: string, position: Vector3): BossInstance?
    local definition = BossConfig.Bosses[bossId]
    if not definition then return nil end

    if activeBosses[bossId] then
        warn("[BossService] Boss already active:", bossId)
        return nil
    end

    local modelsFolder = ServerStorage:FindFirstChild("BossModels")
    if not modelsFolder then return nil end

    local template = modelsFolder:FindFirstChild(definition.modelName)
    if not template or not template:IsA("Model") then return nil end

    local model = template:Clone() :: Model
    model:PivotTo(CFrame.new(position))
    model.Name = "Boss_" .. bossId
    model.Parent = workspace

    local humanoid = model:FindFirstChildOfClass("Humanoid")
    if humanoid then
        humanoid.MaxHealth = definition.maxHealth
        humanoid.Health = definition.maxHealth
    end

    local boss: BossInstance = {
        bossId = bossId,
        model = model,
        currentHealth = definition.maxHealth,
        maxHealth = definition.maxHealth,
        currentPhase = 1,
        isTransitioning = false,
        isEnraged = false,
        startTime = tick(),
        participants = {},
        attackCooldowns = {},
        isAlive = true,
        targetPlayer = nil,
    }

    -- Gather participants (all players in range or in server)
    for _, plr in Players:GetPlayers() do
        table.insert(boss.participants, plr)
    end

    activeBosses[bossId] = boss

    -- Notify clients
    local remotes = ReplicatedStorage:FindFirstChild("BossRemotes")
    if remotes then
        local spawnEvent = remotes:FindFirstChild("BossSpawned") :: RemoteEvent
        if spawnEvent then
            spawnEvent:FireAllClients(bossId, definition.displayName, definition.maxHealth)
        end
    end

    return boss
end

-------------------------------------------------
-- Init
-------------------------------------------------

function BossService.Init()
    local remotesFolder = Instance.new("Folder")
    remotesFolder.Name = "BossRemotes"
    remotesFolder.Parent = ReplicatedStorage

    for _, name in { "BossSpawned", "BossDefeated", "BossEnraged", "PhaseTransition", "HealthUpdate" } do
        local remote = Instance.new("RemoteEvent")
        remote.Name = name
        remote.Parent = remotesFolder
    end

    -- AI update loop
    RunService.Heartbeat:Connect(function()
        for _, boss in activeBosses do
            updateBossAI(boss)
        end
    end)
end

return BossService
```

---

## 3. Client Boss UI

```luau
-- StarterPlayerScripts/Controllers/BossUI.luau
--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local BossUI = {}

local activeHealthBars: { [string]: Frame } = {}

local function createBossHealthBar(bossId: string, bossName: string, maxHealth: number): Frame
    local screenGui = playerGui:FindFirstChild("BossUI") :: ScreenGui?
    if not screenGui then
        screenGui = Instance.new("ScreenGui")
        screenGui.Name = "BossUI"
        screenGui.ResetOnSpawn = false
        screenGui.Parent = playerGui
    end

    local container = Instance.new("Frame")
    container.Name = "BossBar_" .. bossId
    container.Size = UDim2.new(0.5, 0, 0, 60)
    container.Position = UDim2.new(0.25, 0, 0.05, 0)
    container.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
    container.BackgroundTransparency = 0.2
    container.Parent = screenGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = container

    local nameLabel = Instance.new("TextLabel")
    nameLabel.Name = "BossName"
    nameLabel.Size = UDim2.new(1, 0, 0, 25)
    nameLabel.BackgroundTransparency = 1
    nameLabel.Text = bossName
    nameLabel.TextColor3 = Color3.fromRGB(255, 200, 50)
    nameLabel.TextSize = 20
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.Parent = container

    local phaseLabel = Instance.new("TextLabel")
    phaseLabel.Name = "PhaseLabel"
    phaseLabel.Size = UDim2.new(0.3, 0, 0, 15)
    phaseLabel.Position = UDim2.new(0.7, 0, 0, 5)
    phaseLabel.BackgroundTransparency = 1
    phaseLabel.Text = "Phase 1"
    phaseLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
    phaseLabel.TextSize = 12
    phaseLabel.Font = Enum.Font.Gotham
    phaseLabel.Parent = container

    local barBg = Instance.new("Frame")
    barBg.Name = "BarBackground"
    barBg.Size = UDim2.new(0.95, 0, 0, 20)
    barBg.Position = UDim2.new(0.025, 0, 0, 30)
    barBg.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
    barBg.Parent = container

    local barCorner = Instance.new("UICorner")
    barCorner.CornerRadius = UDim.new(0, 4)
    barCorner.Parent = barBg

    local barFill = Instance.new("Frame")
    barFill.Name = "Fill"
    barFill.Size = UDim2.new(1, 0, 1, 0)
    barFill.BackgroundColor3 = Color3.fromRGB(200, 30, 30)
    barFill.Parent = barBg

    local fillCorner = Instance.new("UICorner")
    fillCorner.CornerRadius = UDim.new(0, 4)
    fillCorner.Parent = barFill

    local healthText = Instance.new("TextLabel")
    healthText.Name = "HealthText"
    healthText.Size = UDim2.new(1, 0, 1, 0)
    healthText.BackgroundTransparency = 1
    healthText.Text = tostring(maxHealth) .. " / " .. tostring(maxHealth)
    healthText.TextColor3 = Color3.fromRGB(255, 255, 255)
    healthText.TextSize = 14
    healthText.Font = Enum.Font.GothamBold
    healthText.ZIndex = 2
    healthText.Parent = barBg

    activeHealthBars[bossId] = container
    return container
end

function BossUI.Init()
    local remotes = ReplicatedStorage:WaitForChild("BossRemotes")

    local spawnedEvent = remotes:WaitForChild("BossSpawned") :: RemoteEvent
    spawnedEvent.OnClientEvent:Connect(function(bossId: string, bossName: string, maxHealth: number)
        createBossHealthBar(bossId, bossName, maxHealth)
    end)

    local healthEvent = remotes:WaitForChild("HealthUpdate") :: RemoteEvent
    healthEvent.OnClientEvent:Connect(function(bossId: string, currentHealth: number, maxHealth: number)
        local bar = activeHealthBars[bossId]
        if not bar then return end

        local barBg = bar:FindFirstChild("BarBackground") :: Frame?
        if not barBg then return end
        local fill = barBg:FindFirstChild("Fill") :: Frame?
        local text = barBg:FindFirstChild("HealthText") :: TextLabel?

        if fill then
            local ratio = math.clamp(currentHealth / maxHealth, 0, 1)
            TweenService:Create(fill, TweenInfo.new(0.3), { Size = UDim2.new(ratio, 0, 1, 0) }):Play()

            -- Color shift: green -> yellow -> red
            if ratio > 0.5 then
                fill.BackgroundColor3 = Color3.fromRGB(200, 30, 30)
            elseif ratio > 0.25 then
                fill.BackgroundColor3 = Color3.fromRGB(255, 150, 0)
            else
                fill.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
            end
        end

        if text then
            text.Text = tostring(math.floor(currentHealth)) .. " / " .. tostring(maxHealth)
        end
    end)

    local phaseEvent = remotes:WaitForChild("PhaseTransition") :: RemoteEvent
    phaseEvent.OnClientEvent:Connect(function(bossId: string, phaseNumber: number, phaseName: string, _vfxType: string)
        local bar = activeHealthBars[bossId]
        if not bar then return end
        local phaseLabel = bar:FindFirstChild("PhaseLabel") :: TextLabel?
        if phaseLabel then
            phaseLabel.Text = "Phase " .. tostring(phaseNumber) .. ": " .. phaseName
        end
    end)

    local enrageEvent = remotes:WaitForChild("BossEnraged") :: RemoteEvent
    enrageEvent.OnClientEvent:Connect(function(bossId: string)
        local bar = activeHealthBars[bossId]
        if not bar then return end
        local nameLabel = bar:FindFirstChild("BossName") :: TextLabel?
        if nameLabel then
            nameLabel.Text = nameLabel.Text .. " [ENRAGED]"
            nameLabel.TextColor3 = Color3.fromRGB(255, 50, 50)
        end
    end)

    local defeatedEvent = remotes:WaitForChild("BossDefeated") :: RemoteEvent
    defeatedEvent.OnClientEvent:Connect(function(bossId: string)
        local bar = activeHealthBars[bossId]
        if bar then
            task.delay(3, function()
                bar:Destroy()
                activeHealthBars[bossId] = nil
            end)
        end
    end)
end

return BossUI
```

---

## Key Implementation Notes

1. **Health gates**: Each phase has a `healthThreshold` (0-1). When boss health drops below that percentage, the next phase triggers.
2. **Invulnerability during transitions**: `isTransitioning` flag blocks all damage intake during phase-change animations.
3. **Enrage timer**: After `enrageTime` seconds, the boss gains multiplied damage and movement speed. Incentivizes DPS checks.
4. **Attack telegraphs**: Server creates red zone indicators (Parts) before attacks land. `castTime` determines how long players have to dodge.
5. **Area types**: Single (one target), Cone (frontal), Circle (AoE at position), Line (beam), Arena (unavoidable, must use mechanic).
6. **Status effects** are stored as attributes on the player's character for easy cross-system reading.
7. **Boss AI** runs on Heartbeat, choosing the highest-priority available attack each tick.

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
- `$BOSS_NAME` -- Custom boss definition to generate
- `$NUM_PHASES` -- Number of phases (default 3)
- `$ENRAGE_TIME` -- Seconds before enrage (default 300)
- `$ARENA_SIZE` -- Boss arena radius in studs (default 80)
- `$ATTACK_PATTERNS` -- Custom attack pattern list
- `$HEALTH_POOL` -- Override boss max health
- `$LOOT_TABLE` -- Define drops on boss defeat
- `$MULTIPLAYER` -- Whether to scale for player count in the arena
