---
name: wall-jump-system
description: |
  Wall jump system for Roblox: wall detection via raycast, wall slide with reduced gravity,
  wall jump impulse away from wall, wall cling timer. Use when the user asks about wall
  jumping, wall sliding, wall climbing, wall cling, wall detection, parkour movement,
  or platformer mechanics.
  벽 점프, 벽 슬라이드, 벽 타기, 벽 매달리기, 파쿠르, 플랫포머.
  Triggers on: wall jump, wall slide, wall cling, wall climb, wall detection, parkour,
  platformer, wall run, wall kick, wall bounce.
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
effort: high
---

# Wall Jump System Skill

Complete wall jump system with wall detection raycasting, wall slide physics,
timed wall cling, and jump impulse away from walls. Client-predicted with server sync.

---

## 1. Wall Jump Controller (Client Script)

```luau
--!strict
-- StarterPlayerScripts/WallJumpController.client.lua
-- Handles wall detection, sliding, clinging, and wall jumping.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- Configuration
local WALL_CHECK_DISTANCE = 2.5       -- raycast distance from character to detect walls
local WALL_CHECK_COUNT = 4            -- number of raycasts around the character
local MIN_WALL_ANGLE = 70             -- minimum angle (degrees) from ground to count as wall
local WALL_SLIDE_SPEED = -8           -- downward speed during wall slide (negative = down)
local WALL_CLING_DURATION = 1.5       -- max seconds to cling to a wall
local WALL_JUMP_UP_FORCE = 50         -- upward velocity on wall jump
local WALL_JUMP_AWAY_FORCE = 35       -- force pushing away from wall
local WALL_JUMP_COOLDOWN = 0.3        -- seconds between wall jumps
local MIN_FALL_SPEED = -5             -- must be falling at least this fast to wall slide
local VFX_ENABLED = true
local VFX_SLIDE_PARTICLES = true
local VFX_JUMP_BURST = true

-- State
local isOnWall = false
local wallNormal = Vector3.zero
local wallPart: BasePart? = nil
local clingStartTime = 0
local lastWallJumpTime = 0
local slideVelocityConstraint: LinearVelocity? = nil
local currentCharacter: Model? = nil
local currentHumanoid: Humanoid? = nil

-- Remote
local wallJumpRemote = ReplicatedStorage:WaitForChild("WallJumpRemote", 10) :: RemoteEvent?

-- Raycast to detect nearby walls
local function detectWall(character: Model, rootPart: BasePart): (boolean, Vector3, BasePart?)
    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    rayParams.FilterDescendantsInstances = { character }

    local position = rootPart.Position
    local bestNormal = Vector3.zero
    local bestPart: BasePart? = nil
    local bestDistance = math.huge

    -- Cast rays in multiple directions around the character
    for i = 0, WALL_CHECK_COUNT - 1 do
        local angle = (i / WALL_CHECK_COUNT) * math.pi * 2
        local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))

        -- Cast at multiple heights (waist, chest)
        for _, yOffset in { -0.5, 0.5, 1.5 } do
            local origin = position + Vector3.new(0, yOffset, 0)
            local ray = workspace:Raycast(origin, direction * WALL_CHECK_DISTANCE, rayParams)

            if ray then
                -- Check it's actually a wall (not floor/ceiling)
                local surfaceAngle = math.deg(math.acos(math.clamp(ray.Normal:Dot(Vector3.yAxis), -1, 1)))
                local isWall = surfaceAngle > MIN_WALL_ANGLE and surfaceAngle < (180 - MIN_WALL_ANGLE)

                if isWall and ray.Distance < bestDistance then
                    bestDistance = ray.Distance
                    bestNormal = ray.Normal
                    bestPart = ray.Instance
                end
            end
        end
    end

    return bestDistance < math.huge, bestNormal, bestPart
end

-- VFX: wall slide dust particles
local function createSlideParticles(character: Model, position: Vector3, normal: Vector3)
    if not VFX_SLIDE_PARTICLES then return end

    local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
    if not rootPart then return end

    -- Check if emitter already exists
    if rootPart:FindFirstChild("WallSlideEmitter") then return end

    local emitterPart = Instance.new("Part")
    emitterPart.Name = "WallSlideEmitter"
    emitterPart.Size = Vector3.one * 0.1
    emitterPart.Transparency = 1
    emitterPart.Anchored = false
    emitterPart.CanCollide = false
    emitterPart.CanQuery = false
    emitterPart.Parent = rootPart

    local weld = Instance.new("WeldConstraint")
    weld.Part0 = rootPart
    weld.Part1 = emitterPart
    weld.Parent = emitterPart

    local emitter = Instance.new("ParticleEmitter")
    emitter.Color = ColorSequence.new(Color3.fromRGB(200, 200, 200))
    emitter.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.3),
        NumberSequenceKeypoint.new(1, 0),
    })
    emitter.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.3),
        NumberSequenceKeypoint.new(1, 1),
    })
    emitter.Lifetime = NumberRange.new(0.3, 0.6)
    emitter.Speed = NumberRange.new(2, 5)
    emitter.Rate = 30
    -- Emit away from wall
    emitter.EmissionDirection = Enum.NormalId.Front
    emitter.Parent = emitterPart

    return emitterPart
end

local function removeSlideParticles(character: Model)
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if rootPart then
        local emitter = rootPart:FindFirstChild("WallSlideEmitter")
        if emitter then emitter:Destroy() end
    end
end

-- VFX: burst on wall jump
local function createWallJumpBurst(position: Vector3, normal: Vector3)
    if not VFX_JUMP_BURST then return end

    -- Ring effect at wall
    local ring = Instance.new("Part")
    ring.Shape = Enum.PartType.Cylinder
    ring.Anchored = true
    ring.CanCollide = false
    ring.CanQuery = false
    ring.Material = Enum.Material.Neon
    ring.Color = Color3.fromRGB(200, 230, 255)
    ring.Transparency = 0.3
    ring.Size = Vector3.new(0.1, 1, 1)

    -- Orient ring to face away from wall
    local up = Vector3.yAxis
    local right = normal:Cross(up).Unit
    ring.CFrame = CFrame.lookAt(position, position + normal) * CFrame.Angles(0, math.rad(90), 0)
    ring.Parent = workspace

    TweenService:Create(
        ring,
        TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { Size = Vector3.new(0.1, 6, 6), Transparency = 1 }
    ):Play()

    Debris:AddItem(ring, 0.4)

    -- Particle burst
    local burstPart = Instance.new("Part")
    burstPart.Size = Vector3.one * 0.1
    burstPart.Transparency = 1
    burstPart.Anchored = true
    burstPart.CanCollide = false
    burstPart.Position = position
    burstPart.Parent = workspace

    local emitter = Instance.new("ParticleEmitter")
    emitter.Color = ColorSequence.new(Color3.fromRGB(200, 230, 255))
    emitter.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.5),
        NumberSequenceKeypoint.new(1, 0),
    })
    emitter.Lifetime = NumberRange.new(0.2, 0.4)
    emitter.Speed = NumberRange.new(10, 20)
    emitter.SpreadAngle = Vector2.new(60, 60)
    emitter.Rate = 0
    emitter.Parent = burstPart
    emitter:Emit(20)

    Debris:AddItem(burstPart, 1)
end

-- Start wall slide
local function startWallSlide(character: Model, rootPart: BasePart, normal: Vector3)
    if isOnWall then return end

    isOnWall = true
    wallNormal = normal
    clingStartTime = tick()

    -- Apply wall slide physics: slow descent
    local att = Instance.new("Attachment")
    att.Name = "WallSlideAtt"
    att.Parent = rootPart

    local lv = Instance.new("LinearVelocity")
    lv.Name = "WallSlideVelocity"
    lv.Attachment0 = att
    lv.RelativeTo = Enum.ActuatorRelativeTo.World
    lv.MaxForce = 10000
    -- Keep horizontal velocity near zero (stick to wall), slow descent
    lv.VectorVelocity = Vector3.new(0, WALL_SLIDE_SPEED, 0)
    lv.Parent = rootPart

    slideVelocityConstraint = lv

    -- VFX
    if VFX_ENABLED then
        createSlideParticles(character, rootPart.Position, normal)
    end

    -- Set attribute for animation scripts
    character:SetAttribute("WallSliding", true)
end

-- End wall slide
local function endWallSlide(character: Model, rootPart: BasePart)
    if not isOnWall then return end

    isOnWall = false
    wallNormal = Vector3.zero
    wallPart = nil

    -- Remove slide physics
    if slideVelocityConstraint then
        local att = slideVelocityConstraint.Attachment0
        slideVelocityConstraint:Destroy()
        if att then att:Destroy() end
        slideVelocityConstraint = nil
    end

    -- Remove VFX
    removeSlideParticles(character)

    character:SetAttribute("WallSliding", false)
end

-- Perform wall jump
local function performWallJump(character: Model, rootPart: BasePart)
    local now = tick()
    if now - lastWallJumpTime < WALL_JUMP_COOLDOWN then return end
    lastWallJumpTime = now

    local jumpNormal = wallNormal
    local jumpPosition = rootPart.Position

    -- End wall slide first
    endWallSlide(character, rootPart)

    -- Apply wall jump velocity
    local awayForce = jumpNormal * WALL_JUMP_AWAY_FORCE
    local upForce = Vector3.new(0, WALL_JUMP_UP_FORCE, 0)
    rootPart.AssemblyLinearVelocity = awayForce + upForce

    -- VFX
    if VFX_ENABLED then
        createWallJumpBurst(jumpPosition - jumpNormal * 1, jumpNormal)
    end

    -- Notify server
    if wallJumpRemote then
        wallJumpRemote:FireServer(jumpNormal)
    end
end

-- Main update loop
local function onCharacterAdded(character: Model)
    currentCharacter = character
    local humanoid = character:WaitForChild("Humanoid") :: Humanoid
    currentHumanoid = humanoid

    isOnWall = false
    wallNormal = Vector3.zero

    local rootPart = character:WaitForChild("HumanoidRootPart") :: BasePart

    RunService.Heartbeat:Connect(function(_dt: number)
        if not character.Parent or humanoid.Health <= 0 then
            if isOnWall then
                endWallSlide(character, rootPart)
            end
            return
        end

        local state = humanoid:GetState()
        local isFalling = state == Enum.HumanoidStateType.Freefall

        if isFalling then
            local vel = rootPart.AssemblyLinearVelocity
            local isFallingDown = vel.Y < MIN_FALL_SPEED

            if not isOnWall and isFallingDown then
                -- Check for walls
                local found, normal, part = detectWall(character, rootPart)
                if found then
                    wallPart = part
                    startWallSlide(character, rootPart, normal)
                end
            elseif isOnWall then
                -- Check if still on wall
                local found, normal, _ = detectWall(character, rootPart)
                if not found then
                    endWallSlide(character, rootPart)
                else
                    wallNormal = normal -- update normal
                end

                -- Check cling timer
                if tick() - clingStartTime > WALL_CLING_DURATION then
                    endWallSlide(character, rootPart)
                end
            end
        else
            -- Not falling, end any wall slide
            if isOnWall then
                endWallSlide(character, rootPart)
            end
        end
    end)

    -- Handle landing
    humanoid.StateChanged:Connect(function(_old, new)
        if new == Enum.HumanoidStateType.Landed or new == Enum.HumanoidStateType.Running then
            if isOnWall then
                endWallSlide(character, rootPart)
            end
        end
    end)
end

-- Jump input: if on wall, do wall jump instead of normal jump
UserInputService.JumpRequest:Connect(function()
    if not currentCharacter or not currentHumanoid then return end
    if currentHumanoid.Health <= 0 then return end

    local rootPart = currentCharacter:FindFirstChild("HumanoidRootPart") :: BasePart?
    if not rootPart then return end

    if isOnWall then
        performWallJump(currentCharacter, rootPart)
    end
end)

-- Character setup
player.CharacterAdded:Connect(onCharacterAdded)
if player.Character then
    onCharacterAdded(player.Character)
end
```

---

## 2. Wall Jump Server Handler

```luau
--!strict
-- ServerScriptService/WallJumpServer.server.lua
-- Server-side validation for wall jumps.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Create remote
local wallJumpRemote = Instance.new("RemoteEvent")
wallJumpRemote.Name = "WallJumpRemote"
wallJumpRemote.Parent = ReplicatedStorage

-- Configuration
local WALL_JUMP_UP_FORCE = 50
local WALL_JUMP_AWAY_FORCE = 35
local WALL_CHECK_DISTANCE = 3
local COOLDOWN = 0.25

local playerCooldowns: { [Player]: number } = {}

-- Server-side wall detection
local function verifyNearWall(character: Model): (boolean, Vector3)
    local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
    if not rootPart then return false, Vector3.zero end

    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    rayParams.FilterDescendantsInstances = { character }

    -- Check 8 directions
    for i = 0, 7 do
        local angle = (i / 8) * math.pi * 2
        local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
        local ray = workspace:Raycast(rootPart.Position, direction * WALL_CHECK_DISTANCE, rayParams)

        if ray then
            local surfaceAngle = math.deg(math.acos(math.clamp(ray.Normal:Dot(Vector3.yAxis), -1, 1)))
            if surfaceAngle > 70 and surfaceAngle < 110 then
                return true, ray.Normal
            end
        end
    end

    return false, Vector3.zero
end

wallJumpRemote.OnServerEvent:Connect(function(player: Player, clientNormal: Vector3)
    if typeof(clientNormal) ~= "Vector3" then return end

    local now = tick()
    if playerCooldowns[player] and now - playerCooldowns[player] < COOLDOWN then return end

    local character = player.Character
    if not character then return end

    local humanoid = character:FindFirstChildWhichIsA("Humanoid")
    if not humanoid or humanoid.Health <= 0 then return end

    -- Verify character is in the air
    local state = humanoid:GetState()
    if state ~= Enum.HumanoidStateType.Freefall and state ~= Enum.HumanoidStateType.Jumping then
        return
    end

    -- Verify wall exists
    local nearWall, serverNormal = verifyNearWall(character)
    if not nearWall then return end

    playerCooldowns[player] = now

    -- Apply server-authoritative wall jump
    local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
    if rootPart then
        local awayForce = serverNormal * WALL_JUMP_AWAY_FORCE
        local upForce = Vector3.new(0, WALL_JUMP_UP_FORCE, 0)
        rootPart.AssemblyLinearVelocity = awayForce + upForce
    end
end)

Players.PlayerRemoving:Connect(function(player: Player)
    playerCooldowns[player] = nil
end)
```

---

## Guidelines

- **Multiple raycasts** around the character improve wall detection reliability. Cast at different heights (waist, chest) and horizontal angles.
- **Wall angle check**: use dot product with `Vector3.yAxis` to ensure the surface is vertical (70-110 degrees from up).
- **LinearVelocity** controls descent speed during wall slide. Set `MaxForce` high enough to override gravity.
- **Wall cling timer** prevents infinite wall clinging. After the timer expires, the character slides off.
- **Wall jump impulse** combines upward force with force away from the wall (along wall normal).
- **Server validates** wall proximity using its own raycasts before accepting wall jump requests.
- Set character attributes (`WallSliding`, `WallClinging`) so animation scripts can play appropriate animations.
- Combine with the double-jump system: wall jumping can reset the extra jump count.

---

## 

---

## Learned Lessons

<!-- skill-evolve 에이전트가 자동으로 이 섹션에 교훈을 추가합니다 -->

## Self-Evolution Protocol

이 스킬에서 에러가 발생하면:
1. 에러의 근본 원인을 분석한다
2. 이 파일의 Learned Lessons 섹션에 교훈을 추가한다
3. 같은 실수가 반복되지 않도록 규칙화한다
4. SessionManager에 에러와 학습 내용을 기록한다

```lua
local SM = require(game.ServerStorage._RobloxEngine.SessionManager)
SM.logAction("SKILL_ERROR", "[스킬명] | [에러]")
SM.logAction("SKILL_LEARNED", "[스킬명] | [교훈]")
```

**매 작업 시 반드시 Learned Lessons를 먼저 읽고 기존 교훈을 위반하지 않는지 확인한다.**

$ARGUMENTS

When generating wall jump code, adapt to these user-specified parameters:

- `$WALL_CHECK_DISTANCE` - Raycast distance for wall detection (default: 2.5)
- `$WALL_SLIDE_SPEED` - Descent speed during wall slide (default: -8)
- `$WALL_CLING_DURATION` - Max seconds clinging to wall (default: 1.5)
- `$WALL_JUMP_UP_FORCE` - Upward impulse on wall jump (default: 50)
- `$WALL_JUMP_AWAY_FORCE` - Away-from-wall impulse (default: 35)
- `$WALL_JUMP_COOLDOWN` - Seconds between wall jumps (default: 0.3)
- `$VFX_ENABLED` - Whether to show visual effects (default: true)
- `$VFX_SLIDE_DUST` - Whether to show slide dust particles (default: true)
- `$VFX_JUMP_BURST` - Whether to show jump burst ring (default: true)
- `$RESET_EXTRA_JUMPS` - Whether wall jump resets double-jump count (default: false)
