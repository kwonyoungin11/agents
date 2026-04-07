---
name: grapple-system
description: |
  Grappling hook system for Roblox: RopeConstraint-based grapple, aim raycast,
  swing physics, retract mechanic, VFX rope/beam visuals. Use when the user asks about
  grappling hook, rope swing, grapple, hookshot, tether, rope physics, swing mechanic,
  pull towards, or zip to point.
  그래플, 갈고리, 로프 스윙, 후크샷, 줄, 스윙 물리.
  Triggers on: grapple, grappling hook, rope, hookshot, tether, swing, zip, pull,
  RopeConstraint, beam, rope physics, lasso, hook.
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
effort: high
---

# Grapple / Grappling Hook System Skill

Complete grappling hook system with aim raycasting, RopeConstraint swing physics,
retract mechanic, and visual rope/beam effects. Client-predicted with server authority.

---

## 1. Grapple Controller (Client Script)

```luau
--!strict
-- StarterPlayerScripts/GrappleController.client.lua
-- Handles grapple aiming, firing, swinging, and visual feedback.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local mouse = player:GetMouse()

-- Configuration
local GRAPPLE_KEY = Enum.KeyCode.E
local RETRACT_KEY = Enum.KeyCode.R
local MAX_GRAPPLE_DISTANCE = 100   -- max raycast distance
local ROPE_LENGTH_BUFFER = 2       -- extra slack in rope
local RETRACT_SPEED = 30           -- studs/s retract speed
local MIN_ROPE_LENGTH = 5          -- minimum rope length
local SWING_BOOST = 20             -- extra speed added on grapple start
local GRAPPLE_COOLDOWN = 0.5
local BEAM_COLOR = Color3.fromRGB(200, 200, 200)
local BEAM_WIDTH = 0.15
local AIM_INDICATOR = true         -- show aim dot
local SOUND_ATTACH_ID = ""
local SOUND_DETACH_ID = ""

-- State
local isGrappling = false
local grapplePoint: Vector3? = nil
local grappleAttachment: Attachment? = nil
local grappleRope: RopeConstraint? = nil
local grappleBeam: Beam? = nil
local playerAttachment: Attachment? = nil
local lastGrappleTime = 0
local currentRopeLength = 0

-- Remote
local grappleRemote = ReplicatedStorage:WaitForChild("GrappleRemote", 10) :: RemoteEvent?

-- Aim raycast: find grapple target
local function findGrappleTarget(): (boolean, Vector3, BasePart?)
    local character = player.Character
    if not character then return false, Vector3.zero, nil end

    local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
    if not rootPart then return false, Vector3.zero, nil end

    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    rayParams.FilterDescendantsInstances = { character }

    -- Ray from camera through mouse position
    local mouseLocation = UserInputService:GetMouseLocation()
    local unitRay = camera:ViewportPointToRay(mouseLocation.X, mouseLocation.Y)
    local ray = workspace:Raycast(unitRay.Origin, unitRay.Direction * MAX_GRAPPLE_DISTANCE, rayParams)

    if ray then
        return true, ray.Position, ray.Instance
    end

    return false, Vector3.zero, nil
end

-- Create visual beam (rope) between player and grapple point
local function createBeam(startPart: BasePart, endAttachment: Attachment): Beam
    -- Player attachment
    local att0 = Instance.new("Attachment")
    att0.Name = "GrapplePlayerAtt"
    att0.Parent = startPart
    playerAttachment = att0

    local beam = Instance.new("Beam")
    beam.Name = "GrappleBeam"
    beam.Attachment0 = att0
    beam.Attachment1 = endAttachment
    beam.Color = ColorSequence.new(BEAM_COLOR)
    beam.Width0 = BEAM_WIDTH
    beam.Width1 = BEAM_WIDTH * 0.5
    beam.FaceCamera = true
    beam.Segments = 20
    -- Curved beam for rope-like appearance
    beam.CurveSize0 = 0
    beam.CurveSize1 = -2  -- slight sag
    beam.Parent = startPart

    return beam
end

-- Fire grapple
local function fireGrapple()
    local character = player.Character
    if not character then return end

    local humanoid = character:FindFirstChildWhichIsA("Humanoid")
    local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
    if not humanoid or not rootPart or humanoid.Health <= 0 then return end

    -- Cooldown
    local now = tick()
    if now - lastGrappleTime < GRAPPLE_COOLDOWN then return end
    if isGrappling then return end

    -- Find target
    local found, hitPos, hitPart = findGrappleTarget()
    if not found or not hitPart then return end

    lastGrappleTime = now
    isGrappling = true
    grapplePoint = hitPos

    -- Create anchor attachment at hit point
    local anchorAtt = Instance.new("Attachment")
    anchorAtt.Name = "GrappleAnchor"
    anchorAtt.WorldPosition = hitPos
    anchorAtt.Parent = hitPart
    grappleAttachment = anchorAtt

    -- Calculate rope length
    local distance = (hitPos - rootPart.Position).Magnitude
    currentRopeLength = distance + ROPE_LENGTH_BUFFER

    -- Create RopeConstraint
    local rope = Instance.new("RopeConstraint")
    rope.Name = "GrappleRope"
    rope.Attachment0 = anchorAtt

    local playerAtt = Instance.new("Attachment")
    playerAtt.Name = "GrappleRopePlayerAtt"
    playerAtt.Parent = rootPart

    rope.Attachment1 = playerAtt
    rope.Length = currentRopeLength
    rope.Restitution = 0.3
    rope.Visible = false  -- we use Beam for visuals
    rope.Parent = rootPart
    grappleRope = rope

    -- Create visual beam
    grappleBeam = createBeam(rootPart, anchorAtt)

    -- Apply initial swing boost toward grapple point
    local toTarget = (hitPos - rootPart.Position).Unit
    local currentVel = rootPart.AssemblyLinearVelocity
    local boostVel = toTarget * SWING_BOOST
    rootPart.AssemblyLinearVelocity = currentVel + boostVel

    -- Sound
    if SOUND_ATTACH_ID ~= "" then
        local sound = Instance.new("Sound")
        sound.SoundId = SOUND_ATTACH_ID
        sound.Volume = 0.6
        sound.Parent = rootPart
        sound:Play()
        Debris:AddItem(sound, 2)
    end

    -- Notify server
    if grappleRemote then
        grappleRemote:FireServer("attach", hitPos, hitPart)
    end

    -- Set attribute for animation scripts
    character:SetAttribute("Grappling", true)
end

-- Release grapple
local function releaseGrapple()
    local character = player.Character
    if not character then return end
    if not isGrappling then return end

    isGrappling = false
    grapplePoint = nil

    -- Clean up rope constraint
    if grappleRope then
        local att = grappleRope.Attachment1
        grappleRope:Destroy()
        if att then att:Destroy() end
        grappleRope = nil
    end

    -- Clean up anchor attachment
    if grappleAttachment then
        grappleAttachment:Destroy()
        grappleAttachment = nil
    end

    -- Clean up beam
    if grappleBeam then
        grappleBeam:Destroy()
        grappleBeam = nil
    end

    if playerAttachment then
        playerAttachment:Destroy()
        playerAttachment = nil
    end

    -- Sound
    local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
    if rootPart and SOUND_DETACH_ID ~= "" then
        local sound = Instance.new("Sound")
        sound.SoundId = SOUND_DETACH_ID
        sound.Volume = 0.4
        sound.Parent = rootPart
        sound:Play()
        Debris:AddItem(sound, 2)
    end

    -- Notify server
    if grappleRemote then
        grappleRemote:FireServer("detach")
    end

    character:SetAttribute("Grappling", false)
end

-- Retract rope (shorten length)
local function retractRope(dt: number)
    if not isGrappling or not grappleRope then return end

    currentRopeLength = math.max(
        currentRopeLength - RETRACT_SPEED * dt,
        MIN_ROPE_LENGTH
    )
    grappleRope.Length = currentRopeLength
end

-- Update beam sag based on rope tension
local function updateBeamVisual()
    if not grappleBeam or not grappleRope then return end

    local character = player.Character
    if not character then return end

    local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
    if not rootPart or not grapplePoint then return end

    local distance = (grapplePoint - rootPart.Position).Magnitude
    local slack = currentRopeLength - distance
    local sagAmount = math.clamp(slack * 0.5, 0, 5)

    grappleBeam.CurveSize0 = 0
    grappleBeam.CurveSize1 = -sagAmount
end

-- Input handling
local isRetractHeld = false

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
    if gameProcessed then return end

    if input.KeyCode == GRAPPLE_KEY then
        if isGrappling then
            releaseGrapple()
        else
            fireGrapple()
        end
    elseif input.KeyCode == RETRACT_KEY then
        isRetractHeld = true
    end
end)

UserInputService.InputEnded:Connect(function(input: InputObject)
    if input.KeyCode == RETRACT_KEY then
        isRetractHeld = false
    end
end)

-- Update loop
RunService.Heartbeat:Connect(function(dt: number)
    if not isGrappling then return end

    local character = player.Character
    if not character then
        releaseGrapple()
        return
    end

    local humanoid = character:FindFirstChildWhichIsA("Humanoid")
    if not humanoid or humanoid.Health <= 0 then
        releaseGrapple()
        return
    end

    -- Retract while key held
    if isRetractHeld then
        retractRope(dt)
    end

    -- Update visual
    updateBeamVisual()

    -- Check if grapple point is still valid
    if grappleAttachment and not grappleAttachment.Parent then
        releaseGrapple()
    end
end)

-- Cleanup on death/respawn
player.CharacterAdded:Connect(function()
    releaseGrapple()
end)
```

---

## 2. Grapple Server Handler

```luau
--!strict
-- ServerScriptService/GrappleServer.server.lua
-- Server-side validation and replication for grapple system.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Create remote
local grappleRemote = Instance.new("RemoteEvent")
grappleRemote.Name = "GrappleRemote"
grappleRemote.Parent = ReplicatedStorage

-- Configuration
local MAX_GRAPPLE_DISTANCE = 105 -- slightly more than client for tolerance
local COOLDOWN = 0.4

local playerState: { [Player]: {
    isGrappling: boolean,
    lastGrapple: number,
    rope: RopeConstraint?,
    anchor: Attachment?,
} } = {}

grappleRemote.OnServerEvent:Connect(function(player: Player, action: string, ...)
    if typeof(action) ~= "string" then return end

    local state = playerState[player]
    if not state then
        state = { isGrappling = false, lastGrapple = 0, rope = nil, anchor = nil }
        playerState[player] = state
    end

    local character = player.Character
    if not character then return end

    local humanoid = character:FindFirstChildWhichIsA("Humanoid")
    local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
    if not humanoid or not rootPart or humanoid.Health <= 0 then return end

    if action == "attach" then
        local args = { ... }
        local hitPos = args[1]
        local hitPart = args[2]

        if typeof(hitPos) ~= "Vector3" then return end
        if not (typeof(hitPart) == "Instance" and hitPart:IsA("BasePart")) then return end

        -- Cooldown
        local now = tick()
        if now - state.lastGrapple < COOLDOWN then return end
        state.lastGrapple = now

        -- Distance check
        local distance = (hitPos - rootPart.Position).Magnitude
        if distance > MAX_GRAPPLE_DISTANCE then return end

        -- Verify line of sight
        local rayParams = RaycastParams.new()
        rayParams.FilterType = Enum.RaycastFilterType.Exclude
        rayParams.FilterDescendantsInstances = { character }

        local direction = (hitPos - rootPart.Position)
        local ray = workspace:Raycast(rootPart.Position, direction, rayParams)
        if not ray then return end

        -- Create server-side rope
        local anchorAtt = Instance.new("Attachment")
        anchorAtt.WorldPosition = hitPos
        anchorAtt.Parent = hitPart

        local playerAtt = Instance.new("Attachment")
        playerAtt.Parent = rootPart

        local rope = Instance.new("RopeConstraint")
        rope.Attachment0 = anchorAtt
        rope.Attachment1 = playerAtt
        rope.Length = distance + 2
        rope.Visible = false
        rope.Parent = rootPart

        state.isGrappling = true
        state.rope = rope
        state.anchor = anchorAtt

    elseif action == "detach" then
        if state.rope then
            local att = state.rope.Attachment1
            state.rope:Destroy()
            if att then att:Destroy() end
            state.rope = nil
        end
        if state.anchor then
            state.anchor:Destroy()
            state.anchor = nil
        end
        state.isGrappling = false
    end
end)

-- Cleanup on player leave
Players.PlayerRemoving:Connect(function(player: Player)
    local state = playerState[player]
    if state then
        if state.rope then state.rope:Destroy() end
        if state.anchor then state.anchor:Destroy() end
        playerState[player] = nil
    end
end)

-- Cleanup on character death
Players.PlayerAdded:Connect(function(player: Player)
    player.CharacterAdded:Connect(function()
        local state = playerState[player]
        if state then
            if state.rope then state.rope:Destroy() end
            if state.anchor then state.anchor:Destroy() end
            state.isGrappling = false
            state.rope = nil
            state.anchor = nil
        end
    end)
end)
```

---

## 3. Grapple Aim Indicator (Client)

```luau
--!strict
-- StarterPlayerScripts/GrappleAimIndicator.client.lua
-- Shows a dot/crosshair where the grapple would land.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local MAX_DISTANCE = 100
local VALID_COLOR = Color3.fromRGB(100, 255, 100)
local INVALID_COLOR = Color3.fromRGB(255, 80, 80)
local DOT_SIZE = 0.4

-- Create aim indicator
local aimDot = Instance.new("Part")
aimDot.Name = "GrappleAimDot"
aimDot.Shape = Enum.PartType.Ball
aimDot.Size = Vector3.one * DOT_SIZE
aimDot.Material = Enum.Material.Neon
aimDot.Anchored = true
aimDot.CanCollide = false
aimDot.CanQuery = false
aimDot.CanTouch = false
aimDot.Color = VALID_COLOR
aimDot.Parent = workspace

local light = Instance.new("PointLight")
light.Color = VALID_COLOR
light.Brightness = 2
light.Range = 5
light.Parent = aimDot

RunService.RenderStepped:Connect(function()
    local character = player.Character
    if not character then
        aimDot.Transparency = 1
        return
    end

    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    rayParams.FilterDescendantsInstances = { character, aimDot }

    local mouseLocation = UserInputService:GetMouseLocation()
    local unitRay = camera:ViewportPointToRay(mouseLocation.X, mouseLocation.Y)
    local ray = workspace:Raycast(unitRay.Origin, unitRay.Direction * MAX_DISTANCE, rayParams)

    if ray then
        aimDot.Position = ray.Position
        aimDot.Transparency = 0.3
        aimDot.Color = VALID_COLOR
        light.Color = VALID_COLOR
    else
        aimDot.Transparency = 1
    end
end)
```

---

## Guidelines

- **RopeConstraint** is ideal for grapple hooks. It limits maximum distance while allowing swing physics naturally.
- **Set `RopeConstraint.Visible = false`** and use a `Beam` for visuals, which offers more customization (color, width, sag).
- **Aim raycast** should go from camera through mouse position (`camera:ViewportPointToRay`), not from the character.
- **Retract** shortens the rope length over time using `RopeConstraint.Length`.
- **Beam CurveSize** simulates rope sag. Increase sag when the rope has slack, decrease when taut.
- **Server validates** grapple distance and line-of-sight before creating the authoritative RopeConstraint.
- Clean up all constraints, attachments, and beams when the grapple is released, the character dies, or the anchor part is destroyed.
- **Initial swing boost**: apply an impulse toward the grapple point when attaching for satisfying momentum.

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

When generating grapple code, adapt to these user-specified parameters:

- `$GRAPPLE_KEY` - Input key to fire/release grapple (default: "E")
- `$RETRACT_KEY` - Input key to retract rope (default: "R")
- `$MAX_DISTANCE` - Maximum grapple range in studs (default: 100)
- `$RETRACT_SPEED` - Speed of rope retraction in studs/s (default: 30)
- `$MIN_ROPE_LENGTH` - Minimum retracted rope length (default: 5)
- `$SWING_BOOST` - Initial impulse speed toward grapple point (default: 20)
- `$COOLDOWN` - Seconds between grapple uses (default: 0.5)
- `$BEAM_COLOR` - Rope/beam visual color (default: "200,200,200")
- `$BEAM_WIDTH` - Visual rope width (default: 0.15)
- `$SHOW_AIM` - Whether to show aim indicator (default: true)
- `$ROPE_SAG` - Whether beam shows dynamic sag (default: true)
