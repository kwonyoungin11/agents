---
name: trap-system
description: |
  Trap system for Roblox. Spike traps, falling floors, arrow shooters, flame jets,
  poison gas zones, trigger zones with configurable timing, damage, activation
  patterns, and visual/audio feedback.
  키워드: 함정 시스템, 스파이크, 함정 바닥, 화살 발사, 화염, 독가스, 트리거 존
allowed-tools:
  - Bash
  - Read
  - Edit
  - Write
  - Glob
  - Grep
effort: high
---

# Trap System

Comprehensive trap system for Roblox: spike traps, falling floors, arrow shooters, flame jets, poison gas, and trigger zones with configurable timing and patterns. All code is Luau.

---

## Architecture Overview

```
ReplicatedStorage/
  Shared/
    TrapConfig.luau           -- Trap types, damage values, timing
ServerScriptService/
  Services/
    TrapService.luau          -- Server: trap logic, damage, activation
StarterPlayerScripts/
  Controllers/
    TrapVFX.luau              -- Client: visual/audio effects for traps
workspace/
  Traps/                      -- Tagged trap instances with attributes
```

---

## 1. Trap Configuration

```luau
-- ReplicatedStorage/Shared/TrapConfig.luau
--!strict

export type TrapType = "SpikeTrap" | "FallingFloor" | "ArrowShooter" | "FlameJet" | "PoisonGas" | "SwingingBlade" | "BoulderTrap" | "ElectricFloor"

export type ActivationMode = "Proximity" | "Timer" | "Trigger" | "Pressure" | "AlwaysOn"

export type TrapDefinition = {
    trapType: TrapType,
    damage: number,
    damageInterval: number?,     -- for continuous damage traps
    activationMode: ActivationMode,
    activationRadius: number?,   -- for proximity mode
    activationDelay: number,     -- delay between trigger and activation
    activeTime: number,          -- how long trap stays active
    cooldown: number,            -- time between activations
    warningTime: number,         -- visual warning before activation
    canBeDisabled: boolean,
    knockbackForce: number?,
}

local TrapConfig = {}

TrapConfig.DEFAULTS: { [TrapType]: TrapDefinition } = {
    SpikeTrap = {
        trapType = "SpikeTrap",
        damage = 30,
        damageInterval = nil,
        activationMode = "Timer",
        activationRadius = nil,
        activationDelay = 0.3,
        activeTime = 1.5,
        cooldown = 3.0,
        warningTime = 0.5,
        canBeDisabled = true,
        knockbackForce = 30,
    },
    FallingFloor = {
        trapType = "FallingFloor",
        damage = 0,
        damageInterval = nil,
        activationMode = "Pressure",
        activationRadius = nil,
        activationDelay = 0.8,
        activeTime = 3.0,
        cooldown = 5.0,
        warningTime = 0.5,
        canBeDisabled = false,
        knockbackForce = nil,
    },
    ArrowShooter = {
        trapType = "ArrowShooter",
        damage = 20,
        damageInterval = nil,
        activationMode = "Proximity",
        activationRadius = 20,
        activationDelay = 0.2,
        activeTime = 0.1,
        cooldown = 2.0,
        warningTime = 0.1,
        canBeDisabled = true,
        knockbackForce = 15,
    },
    FlameJet = {
        trapType = "FlameJet",
        damage = 8,
        damageInterval = 0.3,
        activationMode = "Timer",
        activationRadius = nil,
        activationDelay = 0,
        activeTime = 3.0,
        cooldown = 4.0,
        warningTime = 1.0,
        canBeDisabled = true,
        knockbackForce = nil,
    },
    PoisonGas = {
        trapType = "PoisonGas",
        damage = 5,
        damageInterval = 0.5,
        activationMode = "Trigger",
        activationRadius = 15,
        activationDelay = 1.0,
        activeTime = 8.0,
        cooldown = 15.0,
        warningTime = 1.5,
        canBeDisabled = true,
        knockbackForce = nil,
    },
    SwingingBlade = {
        trapType = "SwingingBlade",
        damage = 40,
        damageInterval = nil,
        activationMode = "AlwaysOn",
        activationRadius = nil,
        activationDelay = 0,
        activeTime = 0,
        cooldown = 0,
        warningTime = 0,
        canBeDisabled = false,
        knockbackForce = 50,
    },
    BoulderTrap = {
        trapType = "BoulderTrap",
        damage = 100,
        damageInterval = nil,
        activationMode = "Trigger",
        activationRadius = 10,
        activationDelay = 0.5,
        activeTime = 10.0,
        cooldown = 30.0,
        warningTime = 0.5,
        canBeDisabled = false,
        knockbackForce = 200,
    },
    ElectricFloor = {
        trapType = "ElectricFloor",
        damage = 15,
        damageInterval = 0.4,
        activationMode = "Timer",
        activationRadius = nil,
        activationDelay = 0,
        activeTime = 2.0,
        cooldown = 3.0,
        warningTime = 1.0,
        canBeDisabled = true,
        knockbackForce = 20,
    },
}

return TrapConfig
```

---

## 2. Server Trap Service

```luau
-- ServerScriptService/Services/TrapService.luau
--!strict

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local TrapConfig = require(ReplicatedStorage.Shared.TrapConfig)

local TrapService = {}

type TrapInstance = {
    part: BasePart,
    config: TrapConfig.TrapDefinition,
    isActive: boolean,
    isOnCooldown: boolean,
    lastActivation: number,
    damagedPlayers: { [Player]: number }, -- player -> last damage tick
}

local traps: { [BasePart]: TrapInstance } = {}

-------------------------------------------------
-- Damage Application
-------------------------------------------------

local function applyDamage(trap: TrapInstance, character: Model)
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 then return end

    local player = Players:GetPlayerFromCharacter(character)
    if not player then return end

    -- Damage interval check for continuous traps
    if trap.config.damageInterval then
        local lastHit = trap.damagedPlayers[player] or 0
        if tick() - lastHit < trap.config.damageInterval then return end
        trap.damagedPlayers[player] = tick()
    end

    humanoid:TakeDamage(trap.config.damage)

    -- Knockback
    if trap.config.knockbackForce and trap.config.knockbackForce > 0 then
        local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
        if rootPart then
            local direction = (rootPart.Position - trap.part.Position).Unit
            direction = Vector3.new(direction.X, math.max(0.3, direction.Y), direction.Z).Unit
            rootPart.AssemblyLinearVelocity = direction * trap.config.knockbackForce
        end
    end
end

-------------------------------------------------
-- Spike Trap
-------------------------------------------------

local function activateSpikeTrap(trap: TrapInstance)
    trap.isActive = true
    local part = trap.part

    -- Animate spikes rising
    local spikeModel = part:FindFirstChild("Spikes") :: Model?
    if spikeModel then
        local originalCF = spikeModel:GetPivot()
        local raisedCF = originalCF + Vector3.new(0, 2.5, 0)

        -- Rise
        local riseTween = TweenService:Create(
            spikeModel.PrimaryPart :: BasePart,
            TweenInfo.new(trap.config.activationDelay, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
            { CFrame = raisedCF }
        )
        riseTween:Play()
        riseTween.Completed:Wait()

        -- Damage anyone on top
        local region = part.Position + Vector3.new(0, 2, 0)
        local size = part.Size + Vector3.new(0, 4, 0)
        local params = OverlapParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = { part, spikeModel }

        local touchingParts = workspace:GetPartBoundsInBox(CFrame.new(region), size, params)
        for _, touchPart in touchingParts do
            local character = touchPart.Parent :: Model?
            if character and character:FindFirstChildOfClass("Humanoid") then
                applyDamage(trap, character)
            end
        end

        -- Hold active
        task.wait(trap.config.activeTime)

        -- Retract
        local retractTween = TweenService:Create(
            spikeModel.PrimaryPart :: BasePart,
            TweenInfo.new(0.3),
            { CFrame = originalCF }
        )
        retractTween:Play()
        retractTween.Completed:Wait()
    end

    trap.isActive = false
end

-------------------------------------------------
-- Falling Floor
-------------------------------------------------

local function activateFallingFloor(trap: TrapInstance)
    trap.isActive = true
    local part = trap.part
    local originalCFrame = part.CFrame
    local originalTransparency = part.Transparency

    -- Warning: shake/flash
    part.Color = Color3.fromRGB(255, 100, 100)

    task.wait(trap.config.warningTime)

    -- Crack visual
    part.Transparency = 0.3
    task.wait(trap.config.activationDelay)

    -- Fall: unanchor and let physics take over
    part.Anchored = false
    part.CanCollide = false
    part.Transparency = 0.5

    task.wait(trap.config.activeTime)

    -- Reset
    part.Anchored = true
    part.CanCollide = true
    part.CFrame = originalCFrame
    part.Transparency = originalTransparency
    part.Color = Color3.fromRGB(150, 150, 150) -- default color

    trap.isActive = false
end

-------------------------------------------------
-- Arrow Shooter
-------------------------------------------------

local function activateArrowShooter(trap: TrapInstance)
    trap.isActive = true
    local part = trap.part

    -- Create arrow projectile
    local arrow = Instance.new("Part")
    arrow.Name = "Arrow"
    arrow.Size = Vector3.new(0.3, 0.3, 3)
    arrow.Color = Color3.fromRGB(80, 50, 20)
    arrow.Material = Enum.Material.Wood
    arrow.Anchored = false
    arrow.CanCollide = false
    arrow.CFrame = part.CFrame

    -- Velocity in the direction the shooter faces
    local direction = part.CFrame.LookVector
    arrow.AssemblyLinearVelocity = direction * 120

    arrow.Parent = workspace

    -- Hit detection
    arrow.Touched:Connect(function(hit: BasePart)
        if hit:IsDescendantOf(part.Parent :: Instance) then return end

        local character = hit.Parent :: Model?
        if character and character:FindFirstChildOfClass("Humanoid") then
            applyDamage(trap, character)
        end

        arrow:Destroy()
    end)

    -- Auto-destroy after distance
    task.delay(3, function()
        if arrow.Parent then
            arrow:Destroy()
        end
    end)

    trap.isActive = false
end

-------------------------------------------------
-- Flame Jet
-------------------------------------------------

local function activateFlameJet(trap: TrapInstance)
    trap.isActive = true
    local part = trap.part

    -- Create flame particles
    local fire = Instance.new("ParticleEmitter")
    fire.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 200, 50)),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 100, 0)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(100, 0, 0)),
    })
    fire.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1),
        NumberSequenceKeypoint.new(1, 3),
    })
    fire.Lifetime = NumberRange.new(0.3, 0.6)
    fire.Rate = 200
    fire.Speed = NumberRange.new(20, 40)
    fire.SpreadAngle = Vector2.new(10, 10)
    fire.Parent = part

    -- Damage zone: continuous damage while active
    local damageConnection: RBXScriptConnection?
    local direction = part.CFrame.LookVector
    local flameLength = 15

    damageConnection = RunService.Heartbeat:Connect(function()
        -- Check for players in flame path
        for _, player in Players:GetPlayers() do
            if not player.Character then continue end
            local rootPart = player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
            if not rootPart then continue end

            local toPlayer = rootPart.Position - part.Position
            local projection = toPlayer:Dot(direction)

            if projection > 0 and projection < flameLength then
                local perpDist = (toPlayer - direction * projection).Magnitude
                if perpDist < 3 then
                    applyDamage(trap, player.Character :: Model)
                end
            end
        end
    end)

    task.wait(trap.config.activeTime)

    if damageConnection then
        damageConnection:Disconnect()
    end
    fire:Destroy()

    trap.isActive = false
end

-------------------------------------------------
-- Poison Gas
-------------------------------------------------

local function activatePoisonGas(trap: TrapInstance)
    trap.isActive = true
    local part = trap.part
    local radius = trap.config.activationRadius or 15

    -- Create gas visual
    local gas = Instance.new("ParticleEmitter")
    gas.Color = ColorSequence.new(Color3.fromRGB(100, 200, 50))
    gas.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 2),
        NumberSequenceKeypoint.new(1, 8),
    })
    gas.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.3),
        NumberSequenceKeypoint.new(1, 1),
    })
    gas.Lifetime = NumberRange.new(2, 4)
    gas.Rate = 30
    gas.Speed = NumberRange.new(2, 5)
    gas.SpreadAngle = Vector2.new(180, 180)
    gas.Parent = part

    -- Continuous damage in radius
    local damageConnection = RunService.Heartbeat:Connect(function()
        for _, player in Players:GetPlayers() do
            if not player.Character then continue end
            local rootPart = player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
            if not rootPart then continue end

            local dist = (rootPart.Position - part.Position).Magnitude
            if dist <= radius then
                applyDamage(trap, player.Character :: Model)
            end
        end
    end)

    task.wait(trap.config.activeTime)

    damageConnection:Disconnect()
    gas:Destroy()

    trap.isActive = false
end

-------------------------------------------------
-- Swinging Blade (Always-On)
-------------------------------------------------

local function setupSwingingBlade(trap: TrapInstance)
    local part = trap.part
    local pivotPoint = part:GetAttribute("PivotOffset") :: Vector3 or Vector3.new(0, 5, 0)
    local swingSpeed = part:GetAttribute("SwingSpeed") :: number or 2
    local swingAngle = part:GetAttribute("SwingAngle") :: number or 70

    trap.isActive = true

    -- Continuous swing using CFrame rotation
    local basePosition = part.Position + pivotPoint
    local startAngle = -math.rad(swingAngle)
    local endAngle = math.rad(swingAngle)

    RunService.Heartbeat:Connect(function()
        local t = tick() * swingSpeed
        local angle = math.sin(t) * math.rad(swingAngle)
        local offset = Vector3.new(math.sin(angle) * pivotPoint.Magnitude, -math.cos(angle) * pivotPoint.Magnitude, 0)
        part.CFrame = CFrame.new(basePosition + offset) * CFrame.Angles(0, 0, angle)
    end)

    -- Continuous touch damage
    part.Touched:Connect(function(hit: BasePart)
        local character = hit.Parent :: Model?
        if character and character:FindFirstChildOfClass("Humanoid") then
            applyDamage(trap, character)
        end
    end)
end

-------------------------------------------------
-- Trap Activation Dispatcher
-------------------------------------------------

local activationHandlers: { [TrapConfig.TrapType]: (trap: TrapInstance) -> () } = {
    SpikeTrap = activateSpikeTrap,
    FallingFloor = activateFallingFloor,
    ArrowShooter = activateArrowShooter,
    FlameJet = activateFlameJet,
    PoisonGas = activatePoisonGas,
}

local function activateTrap(trap: TrapInstance)
    if trap.isActive or trap.isOnCooldown then return end

    trap.isOnCooldown = true

    -- Warning phase
    if trap.config.warningTime > 0 then
        trap.part:SetAttribute("Warning", true)
        -- Notify clients for VFX
        local remotes = ReplicatedStorage:FindFirstChild("TrapRemotes")
        if remotes then
            local warnEvent = remotes:FindFirstChild("TrapWarning") :: RemoteEvent
            if warnEvent then
                warnEvent:FireAllClients(trap.part, trap.config.trapType, trap.config.warningTime)
            end
        end
        task.wait(trap.config.warningTime)
        trap.part:SetAttribute("Warning", false)
    end

    -- Execute trap
    local handler = activationHandlers[trap.config.trapType]
    if handler then
        handler(trap)
    end

    -- Cooldown
    task.wait(trap.config.cooldown)
    trap.isOnCooldown = false
    trap.damagedPlayers = {}
end

-------------------------------------------------
-- Trigger Zone Detection
-------------------------------------------------

local function setupTriggerZone(trap: TrapInstance)
    local mode = trap.config.activationMode

    if mode == "Proximity" then
        -- Heartbeat proximity check
        RunService.Heartbeat:Connect(function()
            if trap.isActive or trap.isOnCooldown then return end
            local radius = trap.config.activationRadius or 10
            for _, player in Players:GetPlayers() do
                if not player.Character then continue end
                local rootPart = player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
                if rootPart then
                    local dist = (rootPart.Position - trap.part.Position).Magnitude
                    if dist <= radius then
                        task.spawn(function()
                            activateTrap(trap)
                        end)
                        return
                    end
                end
            end
        end)

    elseif mode == "Pressure" then
        trap.part.Touched:Connect(function(hit: BasePart)
            local character = hit.Parent :: Model?
            if not character then return end
            if not Players:GetPlayerFromCharacter(character) then return end
            task.spawn(function()
                activateTrap(trap)
            end)
        end)

    elseif mode == "Trigger" then
        -- Look for a child trigger zone part
        local triggerZone = trap.part:FindFirstChild("TriggerZone") :: BasePart?
        if triggerZone then
            triggerZone.Touched:Connect(function(hit: BasePart)
                local character = hit.Parent :: Model?
                if not character then return end
                if not Players:GetPlayerFromCharacter(character) then return end
                task.spawn(function()
                    activateTrap(trap)
                end)
            end)
        end

    elseif mode == "Timer" then
        task.spawn(function()
            while trap.part.Parent do
                activateTrap(trap)
                task.wait(0.1) -- small buffer between cycles
            end
        end)

    elseif mode == "AlwaysOn" then
        if trap.config.trapType == "SwingingBlade" then
            setupSwingingBlade(trap)
        end
    end
end

-------------------------------------------------
-- Init
-------------------------------------------------

function TrapService.Init()
    -- Create remotes
    local remotesFolder = Instance.new("Folder")
    remotesFolder.Name = "TrapRemotes"
    remotesFolder.Parent = ReplicatedStorage

    for _, name in { "TrapWarning", "TrapActivated", "TrapDeactivated" } do
        local remote = Instance.new("RemoteEvent")
        remote.Name = name
        remote.Parent = remotesFolder
    end

    -- Register traps by tag
    local function registerTrap(instance: Instance)
        if not instance:IsA("BasePart") then return end

        local trapTypeName = instance:GetAttribute("TrapType") :: string?
        if not trapTypeName then return end

        local trapType = trapTypeName :: TrapConfig.TrapType
        local defaultConfig = TrapConfig.DEFAULTS[trapType]
        if not defaultConfig then
            warn("[TrapService] Unknown trap type:", trapTypeName)
            return
        end

        -- Allow attribute overrides
        local config: TrapConfig.TrapDefinition = {
            trapType = trapType,
            damage = instance:GetAttribute("Damage") :: number? or defaultConfig.damage,
            damageInterval = instance:GetAttribute("DamageInterval") :: number? or defaultConfig.damageInterval,
            activationMode = (instance:GetAttribute("ActivationMode") :: string? or defaultConfig.activationMode) :: TrapConfig.ActivationMode,
            activationRadius = instance:GetAttribute("ActivationRadius") :: number? or defaultConfig.activationRadius,
            activationDelay = instance:GetAttribute("ActivationDelay") :: number? or defaultConfig.activationDelay,
            activeTime = instance:GetAttribute("ActiveTime") :: number? or defaultConfig.activeTime,
            cooldown = instance:GetAttribute("Cooldown") :: number? or defaultConfig.cooldown,
            warningTime = instance:GetAttribute("WarningTime") :: number? or defaultConfig.warningTime,
            canBeDisabled = defaultConfig.canBeDisabled,
            knockbackForce = instance:GetAttribute("KnockbackForce") :: number? or defaultConfig.knockbackForce,
        }

        local trap: TrapInstance = {
            part = instance :: BasePart,
            config = config,
            isActive = false,
            isOnCooldown = false,
            lastActivation = 0,
            damagedPlayers = {},
        }

        traps[instance :: BasePart] = trap
        setupTriggerZone(trap)
    end

    for _, instance in CollectionService:GetTagged("Trap") do
        registerTrap(instance)
    end

    CollectionService:GetInstanceAddedSignal("Trap"):Connect(registerTrap)

    -- Cleanup destroyed traps
    CollectionService:GetInstanceRemovedSignal("Trap"):Connect(function(instance)
        traps[instance :: BasePart] = nil
    end)
end

return TrapService
```

---

## 3. Client Trap VFX

```luau
-- StarterPlayerScripts/Controllers/TrapVFX.luau
--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local TrapVFX = {}

function TrapVFX.Init()
    local remotes = ReplicatedStorage:WaitForChild("TrapRemotes")

    local warnEvent = remotes:WaitForChild("TrapWarning") :: RemoteEvent
    warnEvent.OnClientEvent:Connect(function(part: BasePart, trapType: string, warningTime: number)
        -- Flash warning effect
        local originalColor = part.Color

        -- Pulsing red glow
        local highlight = Instance.new("Highlight")
        highlight.FillColor = Color3.fromRGB(255, 0, 0)
        highlight.FillTransparency = 0.5
        highlight.OutlineTransparency = 1
        highlight.Parent = part

        -- Pulse animation
        task.spawn(function()
            local elapsed = 0
            local pulseSpeed = 6
            while elapsed < warningTime do
                local alpha = math.abs(math.sin(elapsed * pulseSpeed))
                highlight.FillTransparency = 0.3 + alpha * 0.6
                elapsed += task.wait()
            end
            highlight:Destroy()
        end)

        -- Warning sound
        local sound = Instance.new("Sound")
        sound.SoundId = "rbxassetid://0" -- replace with actual warning sound
        sound.Volume = 0.5
        sound.Parent = part
        sound:Play()
        sound.Ended:Connect(function()
            sound:Destroy()
        end)
    end)
end

return TrapVFX
```

---

## Key Implementation Notes

1. **Attribute-driven configuration**: Each trap Part gets a `TrapType` attribute and is tagged "Trap". Optional attributes override defaults (Damage, Cooldown, etc.).
2. **Activation modes**: Proximity (distance check), Pressure (touch), Trigger (separate trigger zone), Timer (cyclic), AlwaysOn (continuous like swinging blade).
3. **Warning system**: Traps emit a warning phase before activating. The server notifies clients to show VFX (red pulse highlight).
4. **Knockback** uses direct velocity assignment on the player's HumanoidRootPart.
5. **Damage interval** prevents rapid-fire damage from continuous traps (flame jets, poison gas). Each player has an individual cooldown.
6. **Arrow projectiles** are physics-based Parts with velocity. They destroy on contact and deal damage.
7. **Falling floors** unanchor on activation, letting physics pull them down, then reset after cooldown.
8. **Swinging blades** use continuous CFrame updates with sine-wave oscillation for pendulum motion.
9. **Modular design**: Add new trap types by defining defaults in TrapConfig and adding an activation handler function.

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
- `$TRAP_TYPES` -- Which trap types to include (default: all)
- `$DAMAGE_SCALE` -- Global damage multiplier for all traps
- `$WARNING_ENABLED` -- Whether traps show visual warnings (default true)
- `$KNOCKBACK_ENABLED` -- Whether traps apply knockback (default true)
- `$COOLDOWN_SCALE` -- Multiplier for all cooldown timers
- `$DESTRUCTIBLE` -- Whether players can destroy/disable traps
- `$TRAP_DENSITY` -- Hint for how frequently traps appear in procedural generation
- `$SOUND_EFFECTS` -- Whether to include audio feedback (default true)
