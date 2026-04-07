---
name: ragdoll-system
description: |
  Ragdoll physics system for Roblox: Motor6D to BallSocketConstraint conversion,
  enable/disable ragdoll, death ragdoll, knockback ragdoll with impulse forces.
  Use when the user asks about ragdoll, physics death, knockback, limp body, joint
  constraints, BallSocketConstraint, Motor6D disable, character physics, rag doll.
  래그돌, 물리, 죽음, 넉백, 관절, 캐릭터 물리, 조인트.
  Triggers on: ragdoll, rag doll, ragdolling, Motor6D, BallSocketConstraint,
  death physics, knockback, limp, joint physics, character collapse.
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
effort: high
---

# Ragdoll System Skill

Comprehensive ragdoll physics system for Roblox R15 characters. Converts Motor6D joints
to BallSocketConstraints and back, with death ragdoll, knockback, and proper cleanup.

---

## Architecture Overview

```
Character (R15)
 ├─ HumanoidRootPart
 │   └─ Motor6D "RootJoint" → BallSocketConstraint (when ragdolled)
 ├─ UpperTorso
 │   └─ Motor6D "Waist" → BallSocketConstraint
 ├─ Head
 │   └─ Motor6D "Neck" → BallSocketConstraint
 ├─ LeftUpperArm / RightUpperArm
 │   └─ Motor6D "LeftShoulder"/"RightShoulder" → BallSocketConstraint
 └─ ... (all limbs follow same pattern)
```

---

## 1. RagdollService (Server Module)

```luau
--!strict
-- ServerScriptService/RagdollService.lua
-- Handles ragdoll state for all characters. Server-authoritative.

local Players = game:GetService("Players")
local Debris = game:GetService("Debris")

local RagdollService = {}

-- Joint limit presets per Motor6D name for realistic ragdoll poses
local JOINT_LIMITS: { [string]: { upperAngle: number, twistLower: number, twistUpper: number } } = {
    RootJoint       = { upperAngle = 10,  twistLower = -20,  twistUpper = 20 },
    Waist           = { upperAngle = 30,  twistLower = -30,  twistUpper = 30 },
    Neck            = { upperAngle = 30,  twistLower = -60,  twistUpper = 60 },
    LeftShoulder    = { upperAngle = 120, twistLower = -90,  twistUpper = 90 },
    RightShoulder   = { upperAngle = 120, twistLower = -90,  twistUpper = 90 },
    LeftElbow       = { upperAngle = 5,   twistLower = -5,   twistUpper = 135 },
    RightElbow      = { upperAngle = 5,   twistLower = -5,   twistUpper = 135 },
    LeftWrist       = { upperAngle = 30,  twistLower = -30,  twistUpper = 30 },
    RightWrist      = { upperAngle = 30,  twistLower = -30,  twistUpper = 30 },
    LeftHip         = { upperAngle = 80,  twistLower = -10,  twistUpper = 80 },
    RightHip        = { upperAngle = 80,  twistLower = -10,  twistUpper = 80 },
    LeftKnee        = { upperAngle = 5,   twistLower = -120, twistUpper = 5 },
    RightKnee       = { upperAngle = 5,   twistLower = -120, twistUpper = 5 },
    LeftAnkle       = { upperAngle = 20,  twistLower = -20,  twistUpper = 20 },
    RightAnkle      = { upperAngle = 20,  twistLower = -20,  twistUpper = 20 },
}

-- Convert a single Motor6D to a BallSocketConstraint
local function motorToBallSocket(motor: Motor6D): BallSocketConstraint?
    local part0 = motor.Part0
    local part1 = motor.Part1
    if not part0 or not part1 then return nil end

    -- Create attachments matching Motor6D C0/C1 transforms
    local att0 = Instance.new("Attachment")
    att0.Name = "RagdollAttach0_" .. motor.Name
    att0.CFrame = motor.C0
    att0.Parent = part0

    local att1 = Instance.new("Attachment")
    att1.Name = "RagdollAttach1_" .. motor.Name
    att1.CFrame = motor.C1
    att1.Parent = part1

    -- Create BallSocketConstraint
    local ball = Instance.new("BallSocketConstraint")
    ball.Name = "RagdollJoint_" .. motor.Name
    ball.Attachment0 = att0
    ball.Attachment1 = att1

    -- Apply joint limits
    local limits = JOINT_LIMITS[motor.Name]
    if limits then
        ball.LimitsEnabled = true
        ball.UpperAngle = limits.upperAngle
        ball.TwistLimitsEnabled = true
        ball.TwistLowerAngle = limits.twistLower
        ball.TwistUpperAngle = limits.twistUpper
    else
        ball.LimitsEnabled = true
        ball.UpperAngle = 60
    end

    ball.Parent = part0

    -- Disable the Motor6D (don't destroy -- we need it to un-ragdoll)
    motor.Enabled = false

    return ball
end

-- Restore a Motor6D from its BallSocketConstraint replacement
local function ballSocketToMotor(motor: Motor6D)
    local part0 = motor.Part0
    if not part0 then return end

    -- Find and remove the BallSocketConstraint + attachments
    local ball = part0:FindFirstChild("RagdollJoint_" .. motor.Name)
    if ball then ball:Destroy() end

    local att0 = part0:FindFirstChild("RagdollAttach0_" .. motor.Name)
    if att0 then att0:Destroy() end

    if motor.Part1 then
        local att1 = motor.Part1:FindFirstChild("RagdollAttach1_" .. motor.Name)
        if att1 then att1:Destroy() end
    end

    motor.Enabled = true
end

-- Enable ragdoll on a character
function RagdollService.enableRagdoll(character: Model)
    local humanoid = character:FindFirstChildWhichIsA("Humanoid")
    if not humanoid then return end

    -- Tag as ragdolled
    character:SetAttribute("Ragdolled", true)

    -- Disable humanoid state control so it doesn't fight the ragdoll
    humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)
    humanoid:SetStateEnabled(Enum.HumanoidStateType.Running, false)
    humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
    humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
    humanoid:ChangeState(Enum.HumanoidStateType.Physics)

    -- Convert all Motor6Ds to BallSocketConstraints
    for _, descendant in character:GetDescendants() do
        if descendant:IsA("Motor6D") and descendant.Name ~= "RootJoint" then
            -- Keep RootJoint for HumanoidRootPart stability or convert too
            motorToBallSocket(descendant)
        end
    end

    -- Also handle the root joint for full ragdoll
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if rootPart then
        local rootJoint = rootPart:FindFirstChild("RootJoint") :: Motor6D?
        if rootJoint then
            motorToBallSocket(rootJoint)
        end
    end

    -- Make all parts collidable for ragdoll physics
    for _, part in character:GetDescendants() do
        if part:IsA("BasePart") then
            part:SetAttribute("PreRagdollCollision", part.CanCollide)
            part.CanCollide = true
        end
    end
end

-- Disable ragdoll and restore normal character
function RagdollService.disableRagdoll(character: Model)
    local humanoid = character:FindFirstChildWhichIsA("Humanoid")
    if not humanoid then return end

    character:SetAttribute("Ragdolled", false)

    -- Restore all Motor6Ds
    for _, descendant in character:GetDescendants() do
        if descendant:IsA("Motor6D") then
            ballSocketToMotor(descendant)
        end
    end

    -- Restore collision states
    for _, part in character:GetDescendants() do
        if part:IsA("BasePart") then
            local preCollision = part:GetAttribute("PreRagdollCollision")
            if preCollision ~= nil then
                part.CanCollide = preCollision
                part:SetAttribute("PreRagdollCollision", nil)
            end
        end
    end

    -- Re-enable humanoid states
    humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, true)
    humanoid:SetStateEnabled(Enum.HumanoidStateType.Running, true)
    humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
    humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, true)
    humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
end

-- Check if character is ragdolled
function RagdollService.isRagdolled(character: Model): boolean
    return character:GetAttribute("Ragdolled") == true
end

return RagdollService
```

---

## 2. Death Ragdoll Handler (Server Script)

```luau
--!strict
-- ServerScriptService/DeathRagdoll.server.lua
-- Automatically ragdolls characters on death, with cleanup.

local Players = game:GetService("Players")
local Debris = game:GetService("Debris")

local RagdollService = require(script.Parent:WaitForChild("RagdollService"))

local RAGDOLL_DURATION = 5  -- seconds before cleanup/respawn

local function onCharacterAdded(character: Model)
    local humanoid = character:WaitForChild("Humanoid") :: Humanoid

    humanoid.Died:Connect(function()
        -- Enable ragdoll on death
        RagdollService.enableRagdoll(character)

        -- Prevent character from being auto-removed
        humanoid.BreakJointsOnDeath = false

        -- Optional: add slight upward impulse to make death feel impactful
        local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
        if rootPart then
            rootPart:ApplyImpulse(Vector3.new(0, 200, 0))
        end

        -- Clean up ragdoll after duration
        task.delay(RAGDOLL_DURATION, function()
            if character.Parent then
                -- Fade out parts
                for _, part in character:GetDescendants() do
                    if part:IsA("BasePart") then
                        local tween = game:GetService("TweenService"):Create(
                            part,
                            TweenInfo.new(1, Enum.EasingStyle.Linear),
                            { Transparency = 1 }
                        )
                        tween:Play()
                    end
                end
                Debris:AddItem(character, 1.5)
            end
        end)
    end)
end

Players.PlayerAdded:Connect(function(player: Player)
    player.CharacterAdded:Connect(onCharacterAdded)
    if player.Character then
        onCharacterAdded(player.Character)
    end
end)
```

---

## 3. Knockback Ragdoll (Server Module)

```luau
--!strict
-- ServerScriptService/KnockbackRagdoll.lua
-- Applies ragdoll + directional knockback impulse, auto-recovers.

local RagdollService = require(script.Parent:WaitForChild("RagdollService"))

local KnockbackRagdoll = {}

export type KnockbackConfig = {
    force: number,           -- impulse magnitude
    upwardBias: number,      -- extra upward force (0-1 scale of force)
    ragdollDuration: number, -- seconds before auto-recovery
    recoveryDelay: number,   -- extra delay after ragdoll ends before full control
}

local DEFAULT_KNOCKBACK: KnockbackConfig = {
    force = 1500,
    upwardBias = 0.3,
    ragdollDuration = 2.0,
    recoveryDelay = 0.5,
}

function KnockbackRagdoll.apply(
    character: Model,
    direction: Vector3,        -- normalized direction of knockback
    config: KnockbackConfig?
)
    local cfg = config or DEFAULT_KNOCKBACK
    local humanoid = character:FindFirstChildWhichIsA("Humanoid")
    if not humanoid or humanoid.Health <= 0 then return end
    if RagdollService.isRagdolled(character) then return end

    -- Enable ragdoll
    RagdollService.enableRagdoll(character)

    -- Apply impulse
    local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
    if rootPart then
        local knockDir = direction.Unit
        local upBias = Vector3.new(0, cfg.upwardBias, 0)
        local impulse = (knockDir + upBias).Unit * cfg.force
        rootPart:ApplyImpulse(impulse)

        -- Also apply angular impulse for tumbling
        local randomSpin = Vector3.new(
            math.random() - 0.5,
            math.random() - 0.5,
            math.random() - 0.5
        ) * cfg.force * 0.1
        rootPart:ApplyAngularImpulse(randomSpin)
    end

    -- Auto-recover after duration
    task.delay(cfg.ragdollDuration, function()
        if character.Parent and humanoid.Health > 0 then
            RagdollService.disableRagdoll(character)
        end
    end)
end

-- Convenience: knockback away from a point (explosion center, attacker position)
function KnockbackRagdoll.applyFromPoint(
    character: Model,
    sourcePosition: Vector3,
    config: KnockbackConfig?
)
    local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
    if not rootPart then return end

    local direction = (rootPart.Position - sourcePosition)
    if direction.Magnitude < 0.01 then
        direction = Vector3.new(0, 1, 0)
    end

    KnockbackRagdoll.apply(character, direction.Unit, config)
end

return KnockbackRagdoll
```

---

## 4. Ragdoll Toggle (Client - for testing or player-initiated)

```luau
--!strict
-- StarterPlayerScripts/RagdollToggle.client.lua
-- Press R to toggle ragdoll (fires remote to server).

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Create or find RemoteEvent
local ragdollRemote = ReplicatedStorage:FindFirstChild("RagdollToggle") :: RemoteEvent?
if not ragdollRemote then
    -- Server should create this; client waits for it
    ragdollRemote = ReplicatedStorage:WaitForChild("RagdollToggle", 10) :: RemoteEvent?
end

if not ragdollRemote then
    warn("[RagdollToggle] RemoteEvent not found in ReplicatedStorage")
    return
end

local TOGGLE_KEY = Enum.KeyCode.R
local debounce = false
local DEBOUNCE_TIME = 0.5

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
    if gameProcessed then return end
    if input.KeyCode ~= TOGGLE_KEY then return end
    if debounce then return end

    debounce = true
    ragdollRemote:FireServer()

    task.delay(DEBOUNCE_TIME, function()
        debounce = false
    end)
end)
```

---

## 5. Server-side Remote Handler

```luau
--!strict
-- ServerScriptService/RagdollRemoteHandler.server.lua
-- Handles client ragdoll toggle requests.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RagdollService = require(script.Parent:WaitForChild("RagdollService"))

-- Create RemoteEvent
local ragdollRemote = Instance.new("RemoteEvent")
ragdollRemote.Name = "RagdollToggle"
ragdollRemote.Parent = ReplicatedStorage

local COOLDOWN = 1.0
local cooldowns: { [Player]: number } = {}

ragdollRemote.OnServerEvent:Connect(function(player: Player)
    -- Cooldown check
    local now = tick()
    if cooldowns[player] and now - cooldowns[player] < COOLDOWN then
        return
    end
    cooldowns[player] = now

    local character = player.Character
    if not character then return end

    local humanoid = character:FindFirstChildWhichIsA("Humanoid")
    if not humanoid or humanoid.Health <= 0 then return end

    if RagdollService.isRagdolled(character) then
        RagdollService.disableRagdoll(character)
    else
        RagdollService.enableRagdoll(character)
        -- Auto-recover after 3 seconds for toggle ragdoll
        task.delay(3, function()
            if character.Parent and humanoid.Health > 0 and RagdollService.isRagdolled(character) then
                RagdollService.disableRagdoll(character)
            end
        end)
    end
end)

-- Cleanup cooldowns
Players.PlayerRemoving:Connect(function(player: Player)
    cooldowns[player] = nil
end)
```

---

## Guidelines

- **Always disable Motor6D instead of destroying** so you can restore the character cleanly.
- **BallSocketConstraint attachments must match Motor6D C0/C1** exactly for proper joint positioning.
- **Set HumanoidStateType to Physics** when ragdolling; switch to GettingUp when recovering.
- **Disable BreakJointsOnDeath** before the character dies if you want the ragdoll to stay together.
- **Joint limits** prevent unrealistic body poses (e.g., knees bending forward).
- **CanCollide** must be true on limb parts during ragdoll for them to interact with the world.
- Server handles all ragdoll state changes; client only sends requests via RemoteEvent.
- Use `Debris:AddItem()` for timed cleanup of death ragdolls.

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

When generating ragdoll code, adapt to these user-specified parameters:

- `$RAGDOLL_DURATION` - How long ragdoll lasts before auto-recovery (default: 3)
- `$DEATH_RAGDOLL` - Whether to ragdoll on death (default: true)
- `$KNOCKBACK_FORCE` - Impulse force for knockback ragdoll (default: 1500)
- `$TOGGLE_KEY` - Key to toggle ragdoll (default: "R")
- `$JOINT_STIFFNESS` - How tight joint limits are, "loose" | "normal" | "tight" (default: "normal")
- `$FADE_ON_DEATH` - Whether dead ragdolls fade out (default: true)
- `$FADE_DURATION` - Seconds for fade-out after death (default: 5)
- `$CHARACTER_RIG` - "R15" | "R6" (default: "R15")
