---
name: health-regen
description: |
  Health regeneration system for Roblox. Configurable regen rate per player,
  out-of-combat timer with damage tracking, regen visual effects (healing particles),
  per-player configuration, and integration with custom health bar UI.
  체력 재생 시스템, 재생 속도, 전투 외 타이머, 재생 VFX, 플레이어별 설정
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
effort: high
---

# Health Regeneration System

Build a configurable health regeneration system with out-of-combat detection, per-player settings, visual feedback, and custom health bar integration.

## Architecture Overview

```
ServerScriptService/
  HealthRegenService.server.lua  -- Core regen logic, combat tracking, config
ReplicatedStorage/
  HealthRegenConfig.lua          -- Default settings and modifier definitions
  HealthRegenShared.lua          -- Shared types
StarterPlayerScripts/
  HealthRegenClient.lua          -- VFX, health bar UI updates
StarterGui/
  HealthBarUI/                   -- Custom health bar with regen indicator
```

## Shared Types and Config

```lua
-- ReplicatedStorage/HealthRegenShared.lua
local HealthRegenShared = {}

export type RegenConfig = {
    baseRegenRate: number,         -- HP per second
    outOfCombatDelay: number,      -- seconds after last damage before regen starts
    regenTickInterval: number,     -- how often regen ticks (seconds)
    maxOverheal: number?,          -- allow regen above max HP? (nil = no)
    regenWhileMoving: boolean,     -- does regen work while moving?
    regenMultiplier: number,       -- global multiplier (1.0 = normal)
    combatRegenRate: number?,      -- HP/s during combat (nil = no regen in combat)
}

export type PlayerRegenState = {
    isInCombat: boolean,
    lastDamageTime: number,
    currentRegenRate: number,
    regenActive: boolean,
    modifiers: { [string]: number }, -- named multipliers (buff name -> multiplier)
}

return HealthRegenShared
```

```lua
-- ReplicatedStorage/HealthRegenConfig.lua
local HealthRegenShared = require(script.Parent:WaitForChild("HealthRegenShared"))

local HealthRegenConfig = {}

-- Default configuration
HealthRegenConfig.Defaults: HealthRegenShared.RegenConfig = {
    baseRegenRate = 2,             -- 2 HP per second
    outOfCombatDelay = 5,          -- 5 seconds after last damage
    regenTickInterval = 0.5,       -- tick every 0.5 seconds
    maxOverheal = nil,
    regenWhileMoving = true,
    regenMultiplier = 1.0,
    combatRegenRate = nil,         -- no regen in combat by default
}

-- Predefined regen modifier presets
HealthRegenConfig.Modifiers = {
    CampfireBonus = 2.0,           -- 2x regen near campfire
    WellFed = 1.5,                 -- 1.5x after eating
    Poisoned = -0.5,               -- negative regen (damage over time)
    BlessingOfLight = 3.0,         -- 3x regen from holy buff
    Exhausted = 0.5,               -- half regen when exhausted
}

return HealthRegenConfig
```

## Server: HealthRegenService

```lua
-- ServerScriptService/HealthRegenService.server.lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local HealthRegenConfig = require(ReplicatedStorage:WaitForChild("HealthRegenConfig"))
local HealthRegenShared = require(ReplicatedStorage:WaitForChild("HealthRegenShared"))

local RegenRemote = Instance.new("RemoteEvent")
RegenRemote.Name = "RegenRemote"
RegenRemote.Parent = ReplicatedStorage

-- Per-player state
local playerStates: { [Player]: HealthRegenShared.PlayerRegenState } = {}
local playerConfigs: { [Player]: HealthRegenShared.RegenConfig } = {}

-- Accumulated time for tick-based regen
local tickAccumulator = 0

--------------------------------------------------------------------------------
-- Initialize player regen state
--------------------------------------------------------------------------------
local function initPlayer(player: Player)
    playerStates[player] = {
        isInCombat = false,
        lastDamageTime = 0,
        currentRegenRate = HealthRegenConfig.Defaults.baseRegenRate,
        regenActive = false,
        modifiers = {},
    }
    playerConfigs[player] = table.clone(HealthRegenConfig.Defaults)
end

--------------------------------------------------------------------------------
-- Calculate effective regen rate with all modifiers
--------------------------------------------------------------------------------
local function calculateEffectiveRate(player: Player): number
    local state = playerStates[player]
    local config = playerConfigs[player]
    if not state or not config then return 0 end

    local baseRate: number
    if state.isInCombat then
        baseRate = config.combatRegenRate or 0
    else
        baseRate = config.baseRegenRate
    end

    -- Apply global multiplier
    local rate = baseRate * config.regenMultiplier

    -- Apply all named modifiers (multiplicative)
    for _, modifier in state.modifiers do
        rate *= modifier
    end

    return rate
end

--------------------------------------------------------------------------------
-- Track damage for out-of-combat detection
--------------------------------------------------------------------------------
local function onHealthChanged(player: Player, humanoid: Humanoid)
    local state = playerStates[player]
    if not state then return end

    local previousHealth = humanoid:GetAttribute("_PreviousHealth") or humanoid.MaxHealth
    local currentHealth = humanoid.Health

    if currentHealth < previousHealth then
        -- Player took damage
        state.lastDamageTime = tick()
        state.isInCombat = true
        state.regenActive = false
        RegenRemote:FireClient(player, "CombatEntered")
    end

    humanoid:SetAttribute("_PreviousHealth", currentHealth)
end

--------------------------------------------------------------------------------
-- Setup health tracking for a character
--------------------------------------------------------------------------------
local function setupCharacter(player: Player, character: Model)
    local humanoid = character:WaitForChild("Humanoid")
    humanoid:SetAttribute("_PreviousHealth", humanoid.Health)

    humanoid.HealthChanged:Connect(function()
        onHealthChanged(player, humanoid)
    end)
end

--------------------------------------------------------------------------------
-- Main regen tick (runs on Heartbeat)
--------------------------------------------------------------------------------
RunService.Heartbeat:Connect(function(dt)
    tickAccumulator += dt
    local tickInterval = HealthRegenConfig.Defaults.regenTickInterval

    if tickAccumulator < tickInterval then return end
    tickAccumulator -= tickInterval

    local now = tick()

    for player, state in playerStates do
        local config = playerConfigs[player]
        if not config then continue end

        local character = player.Character
        if not character then continue end
        local humanoid = character:FindFirstChildWhichIsA("Humanoid")
        if not humanoid or humanoid.Health <= 0 then continue end

        -- Check if player should be out of combat
        if state.isInCombat then
            if now - state.lastDamageTime >= config.outOfCombatDelay then
                state.isInCombat = false
                RegenRemote:FireClient(player, "CombatExited")
            end
        end

        -- Calculate effective rate
        local rate = calculateEffectiveRate(player)
        state.currentRegenRate = rate

        -- Check if regen should be active
        local shouldRegen = rate > 0
            and humanoid.Health < humanoid.MaxHealth
            and (not state.isInCombat or config.combatRegenRate ~= nil)

        -- Check movement restriction
        if not config.regenWhileMoving then
            local rootPart = character:FindFirstChild("HumanoidRootPart")
            if rootPart and rootPart.AssemblyLinearVelocity.Magnitude > 1 then
                shouldRegen = false
            end
        end

        if shouldRegen and not state.regenActive then
            state.regenActive = true
            RegenRemote:FireClient(player, "RegenStarted", rate)
        elseif not shouldRegen and state.regenActive then
            state.regenActive = false
            RegenRemote:FireClient(player, "RegenStopped")
        end

        -- Apply regen
        if shouldRegen then
            local healAmount = rate * tickInterval
            local maxHP = humanoid.MaxHealth
            local cap = config.maxOverheal or maxHP

            humanoid.Health = math.min(humanoid.Health + healAmount, cap)
            humanoid:SetAttribute("_PreviousHealth", humanoid.Health)

            -- Handle negative regen (poison/DoT)
            if rate < 0 then
                RegenRemote:FireClient(player, "DamageOverTime", math.abs(healAmount))
            end
        end
    end
end)

--------------------------------------------------------------------------------
-- Player connections
--------------------------------------------------------------------------------
Players.PlayerAdded:Connect(function(player)
    initPlayer(player)

    player.CharacterAdded:Connect(function(character)
        setupCharacter(player, character)
    end)

    if player.Character then
        setupCharacter(player, player.Character)
    end
end)

Players.PlayerRemoving:Connect(function(player)
    playerStates[player] = nil
    playerConfigs[player] = nil
end)

--------------------------------------------------------------------------------
-- Public API (require from other server scripts)
--------------------------------------------------------------------------------
local HealthRegenService = {}

function HealthRegenService.setRegenRate(player: Player, rate: number)
    local config = playerConfigs[player]
    if config then
        config.baseRegenRate = rate
    end
end

function HealthRegenService.setOutOfCombatDelay(player: Player, delay: number)
    local config = playerConfigs[player]
    if config then
        config.outOfCombatDelay = delay
    end
end

function HealthRegenService.addModifier(player: Player, name: string, multiplier: number)
    local state = playerStates[player]
    if state then
        state.modifiers[name] = multiplier
        RegenRemote:FireClient(player, "ModifierAdded", name, multiplier)
    end
end

function HealthRegenService.removeModifier(player: Player, name: string)
    local state = playerStates[player]
    if state then
        state.modifiers[name] = nil
        RegenRemote:FireClient(player, "ModifierRemoved", name)
    end
end

function HealthRegenService.setConfig(player: Player, config: HealthRegenShared.RegenConfig)
    playerConfigs[player] = config
end

function HealthRegenService.getState(player: Player): HealthRegenShared.PlayerRegenState?
    return playerStates[player]
end

function HealthRegenService.forceCombat(player: Player)
    local state = playerStates[player]
    if state then
        state.isInCombat = true
        state.lastDamageTime = tick()
        state.regenActive = false
        RegenRemote:FireClient(player, "CombatEntered")
    end
end

return HealthRegenService
```

## Client: VFX and Health Bar UI

```lua
-- StarterPlayerScripts/HealthRegenClient.lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local RegenRemote = ReplicatedStorage:WaitForChild("RegenRemote")

local player = Players.LocalPlayer

local isRegenerating = false
local regenVFXActive = false
local healParticleEmitter: ParticleEmitter? = nil

--------------------------------------------------------------------------------
-- Regen VFX: Healing particles around character
--------------------------------------------------------------------------------
local function createRegenVFX(character: Model)
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not rootPart then return end

    if healParticleEmitter then return end -- Already active

    local attachment = Instance.new("Attachment")
    attachment.Name = "RegenAttachment"
    attachment.Position = Vector3.new(0, -2, 0)
    attachment.Parent = rootPart

    local emitter = Instance.new("ParticleEmitter")
    emitter.Name = "RegenParticles"
    emitter.Rate = 15
    emitter.Lifetime = NumberRange.new(1, 2)
    emitter.Speed = NumberRange.new(1, 3)
    emitter.SpreadAngle = Vector2.new(30, 30)
    emitter.EmissionDirection = Enum.NormalId.Top
    emitter.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.3),
        NumberSequenceKeypoint.new(0.5, 0.5),
        NumberSequenceKeypoint.new(1, 0),
    })
    emitter.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.3),
        NumberSequenceKeypoint.new(0.7, 0.5),
        NumberSequenceKeypoint.new(1, 1),
    })
    emitter.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(100, 255, 100)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(50, 200, 50)),
    })
    emitter.LightEmission = 0.5
    emitter.Parent = attachment

    -- Subtle green glow
    local glow = Instance.new("PointLight")
    glow.Name = "RegenGlow"
    glow.Color = Color3.fromRGB(100, 255, 100)
    glow.Brightness = 0.5
    glow.Range = 8
    glow.Parent = rootPart

    healParticleEmitter = emitter
    regenVFXActive = true
end

local function removeRegenVFX(character: Model)
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not rootPart then return end

    local attachment = rootPart:FindFirstChild("RegenAttachment")
    if attachment then attachment:Destroy() end

    local glow = rootPart:FindFirstChild("RegenGlow")
    if glow then glow:Destroy() end

    healParticleEmitter = nil
    regenVFXActive = false
end

--------------------------------------------------------------------------------
-- Floating heal number
--------------------------------------------------------------------------------
local function showHealNumber(character: Model, amount: number)
    local head = character:FindFirstChild("Head")
    if not head then return end

    local billboard = Instance.new("BillboardGui")
    billboard.Size = UDim2.fromOffset(80, 30)
    billboard.StudsOffset = Vector3.new(math.random(-1, 1), 3, 0)
    billboard.AlwaysOnTop = true
    billboard.Parent = head

    local label = Instance.new("TextLabel")
    label.Size = UDim2.fromScale(1, 1)
    label.BackgroundTransparency = 1
    label.Text = "+" .. math.floor(amount)
    label.TextColor3 = Color3.fromRGB(100, 255, 100)
    label.TextStrokeTransparency = 0.5
    label.TextStrokeColor3 = Color3.fromRGB(0, 80, 0)
    label.TextSize = 18
    label.Font = Enum.Font.GothamBold
    label.Parent = billboard

    -- Float up and fade
    local floatTween = TweenService:Create(billboard, TweenInfo.new(1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        StudsOffset = billboard.StudsOffset + Vector3.new(0, 2, 0),
    })
    local fadeTween = TweenService:Create(label, TweenInfo.new(1.5), {
        TextTransparency = 1,
        TextStrokeTransparency = 1,
    })

    floatTween:Play()
    fadeTween:Play()

    task.delay(1.6, function()
        billboard:Destroy()
    end)
end

--------------------------------------------------------------------------------
-- Custom Health Bar UI
--------------------------------------------------------------------------------
local function createHealthBarUI(): (Frame, Frame, TextLabel, Frame)
    local gui = Instance.new("ScreenGui")
    gui.Name = "HealthBarUI"
    gui.Parent = player:WaitForChild("PlayerGui")

    local container = Instance.new("Frame")
    container.Name = "HealthBarContainer"
    container.Size = UDim2.new(0.3, 0, 0, 30)
    container.Position = UDim2.new(0.35, 0, 0.92, 0)
    container.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
    container.BackgroundTransparency = 0.2
    container.Parent = gui

    local containerCorner = Instance.new("UICorner")
    containerCorner.CornerRadius = UDim.new(0, 8)
    containerCorner.Parent = container

    -- Health fill bar
    local healthBar = Instance.new("Frame")
    healthBar.Name = "HealthFill"
    healthBar.Size = UDim2.fromScale(1, 1)
    healthBar.BackgroundColor3 = Color3.fromRGB(50, 180, 50)
    healthBar.Parent = container

    local healthCorner = Instance.new("UICorner")
    healthCorner.CornerRadius = UDim.new(0, 8)
    healthCorner.Parent = healthBar

    -- Regen preview bar (shows upcoming regen amount)
    local regenPreview = Instance.new("Frame")
    regenPreview.Name = "RegenPreview"
    regenPreview.Size = UDim2.fromScale(0, 1)
    regenPreview.BackgroundColor3 = Color3.fromRGB(100, 255, 100)
    regenPreview.BackgroundTransparency = 0.5
    regenPreview.ZIndex = 2
    regenPreview.Visible = false
    regenPreview.Parent = container

    -- Health text
    local healthText = Instance.new("TextLabel")
    healthText.Name = "HealthText"
    healthText.Size = UDim2.fromScale(1, 1)
    healthText.BackgroundTransparency = 1
    healthText.Text = "100 / 100"
    healthText.TextColor3 = Color3.fromRGB(255, 255, 255)
    healthText.TextStrokeTransparency = 0.5
    healthText.TextSize = 14
    healthText.Font = Enum.Font.GothamBold
    healthText.ZIndex = 5
    healthText.Parent = container

    -- Regen indicator icon
    local regenIcon = Instance.new("Frame")
    regenIcon.Name = "RegenIcon"
    regenIcon.Size = UDim2.fromOffset(10, 10)
    regenIcon.Position = UDim2.new(1, 5, 0.5, -5)
    regenIcon.BackgroundColor3 = Color3.fromRGB(100, 255, 100)
    regenIcon.Visible = false
    regenIcon.Parent = container

    local iconCorner = Instance.new("UICorner")
    iconCorner.CornerRadius = UDim.new(1, 0)
    iconCorner.Parent = regenIcon

    return container, healthBar, healthText, regenIcon
end

local healthContainer, healthBar, healthText, regenIcon = createHealthBarUI()

-- Update health bar on Heartbeat
RunService.Heartbeat:Connect(function()
    local character = player.Character
    if not character then return end
    local humanoid = character:FindFirstChildWhichIsA("Humanoid")
    if not humanoid then return end

    local ratio = humanoid.Health / humanoid.MaxHealth
    TweenService:Create(healthBar, TweenInfo.new(0.2), {
        Size = UDim2.fromScale(ratio, 1),
    }):Play()

    -- Color changes based on health percentage
    if ratio > 0.6 then
        healthBar.BackgroundColor3 = Color3.fromRGB(50, 180, 50)
    elseif ratio > 0.3 then
        healthBar.BackgroundColor3 = Color3.fromRGB(220, 180, 30)
    else
        healthBar.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
    end

    healthText.Text = string.format("%d / %d", math.ceil(humanoid.Health), humanoid.MaxHealth)
    regenIcon.Visible = isRegenerating
end)

--------------------------------------------------------------------------------
-- Handle server events
--------------------------------------------------------------------------------
local healAccumulator = 0

RegenRemote.OnClientEvent:Connect(function(action: string, ...)
    local character = player.Character

    if action == "RegenStarted" then
        local rate = ...
        isRegenerating = true
        if character then
            createRegenVFX(character)
        end

    elseif action == "RegenStopped" then
        isRegenerating = false
        if character then
            removeRegenVFX(character)
        end

    elseif action == "CombatEntered" then
        isRegenerating = false
        if character then
            removeRegenVFX(character)
        end

    elseif action == "CombatExited" then
        -- Regen will start on next tick from server
        pass

    elseif action == "ModifierAdded" then
        local name, multiplier = ...
        -- Could show a buff icon in the UI
        print(string.format("[Regen] Modifier added: %s (x%.1f)", name, multiplier))

    elseif action == "ModifierRemoved" then
        local name = ...
        print(string.format("[Regen] Modifier removed: %s", name))

    elseif action == "DamageOverTime" then
        local amount = ...
        if character then
            -- Show red damage number for DoT
            local head = character:FindFirstChild("Head")
            if head then
                local billboard = Instance.new("BillboardGui")
                billboard.Size = UDim2.fromOffset(80, 30)
                billboard.StudsOffset = Vector3.new(0, 3, 0)
                billboard.AlwaysOnTop = true
                billboard.Parent = head

                local label = Instance.new("TextLabel")
                label.Size = UDim2.fromScale(1, 1)
                label.BackgroundTransparency = 1
                label.Text = "-" .. math.floor(amount)
                label.TextColor3 = Color3.fromRGB(255, 80, 80)
                label.TextSize = 16
                label.Font = Enum.Font.GothamBold
                label.Parent = billboard

                task.delay(1, function() billboard:Destroy() end)
            end
        end
    end
end)

-- Show floating heal numbers periodically
local lastHealth = 0
local function onCharacterAdded(character: Model)
    local humanoid = character:WaitForChild("Humanoid")
    lastHealth = humanoid.Health
    healAccumulator = 0

    humanoid.HealthChanged:Connect(function(newHealth)
        local delta = newHealth - lastHealth
        if delta > 0 and isRegenerating then
            healAccumulator += delta
            if healAccumulator >= 1 then
                showHealNumber(character, healAccumulator)
                healAccumulator = 0
            end
        end
        lastHealth = newHealth
    end)
end

if player.Character then onCharacterAdded(player.Character) end
player.CharacterAdded:Connect(onCharacterAdded)
```

## Key Implementation Notes

1. **Out-of-combat timer**: Regen pauses when the player takes damage and resumes after `outOfCombatDelay` seconds with no damage.

2. **Named modifiers**: Use `addModifier(player, "CampfireBonus", 2.0)` to stack multiplicative regen buffs. Remove with `removeModifier`. All modifiers multiply together.

3. **Negative regen (poison/DoT)**: Set a negative modifier to cause damage over time through the regen system.

4. **Tick-based**: Regen runs on `Heartbeat` with an accumulator to control tick frequency. Default is every 0.5 seconds.

5. **VFX**: Green healing particles appear around the character during regen. Floating "+N" numbers show heal amounts.

6. **Health bar**: Custom health bar with smooth tweened fill, color changes at thresholds (green > yellow > red), and a regen indicator dot.

7. **Per-player config**: Each player can have different regen settings via `setConfig()` or individual setter methods.

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

When the user asks for a health regen system, ask:
- What base regen rate? (HP per second)
- Should regen pause during combat? If so, how long after damage to resume?
- Do you need regen modifiers/buffs? (campfire bonus, food buffs, poison)
- Should there be visual feedback? (particles, floating numbers, health bar)
- Does regen work while the player is moving?
- Do you need a custom health bar UI or use the default Roblox one?
