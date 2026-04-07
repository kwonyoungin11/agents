---
name: zipline-system
description: |
  Zipline system for Roblox: zipline parts between two points, attach/detach mechanic,
  speed along line, BodyVelocity/AlignPosition movement. Use when the user asks about
  ziplines, zip lines, cable ride, rope travel, slide along cable, wire ride, or
  traversal between points.
  집라인, 케이블, 로프 이동, 와이어, 활강.
  Triggers on: zipline, zip line, cable, wire, slide line, cable ride, traverse,
  rope ride, AlignPosition, BodyVelocity, overhead rail, pulley.
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
effort: high
---

# Zipline System Skill

Complete zipline system with cable rendering, attach/detach mechanics, smooth
movement along a line using AlignPosition, and visual/sound feedback.

---

## Architecture Overview

```
ZiplineSetup (Folder in workspace)
 ├─ StartNode (Part, Anchored)
 │   └─ Attachment "ZiplineStart"
 ├─ EndNode (Part, Anchored)
 │   └─ Attachment "ZiplineEnd"
 ├─ Cable (Beam between StartNode and EndNode)
 └─ Trigger (invisible part or ProximityPrompt for attachment)
```

---

## 1. Zipline Builder (Server Module)

```luau
--!strict
-- ServerScriptService/ZiplineBuilder.lua
-- Creates zipline infrastructure between two points.

local CollectionService = game:GetService("CollectionService")

local ZiplineBuilder = {}

export type ZiplineConfig = {
    startPosition: Vector3,
    endPosition: Vector3,
    cableColor: Color3,
    cableWidth: number,
    cableSag: number,          -- visual sag of the cable
    speed: number,             -- studs per second along the line
    nodeSize: Vector3,         -- size of start/end node parts
    nodeColor: Color3,
    useProximityPrompt: boolean,
    promptDistance: number,
    promptText: string,
}

local DEFAULT_CONFIG: ZiplineConfig = {
    startPosition = Vector3.new(0, 20, 0),
    endPosition = Vector3.new(50, 10, 0),
    cableColor = Color3.fromRGB(80, 80, 80),
    cableWidth = 0.3,
    cableSag = -3,
    speed = 40,
    nodeSize = Vector3.new(2, 2, 2),
    nodeColor = Color3.fromRGB(100, 100, 100),
    useProximityPrompt = true,
    promptDistance = 10,
    promptText = "Ride Zipline",
}

function ZiplineBuilder.create(config: ZiplineConfig?): Folder
    local cfg = config or DEFAULT_CONFIG

    local folder = Instance.new("Folder")
    folder.Name = "Zipline"
    CollectionService:AddTag(folder, "Zipline")

    -- Start node
    local startNode = Instance.new("Part")
    startNode.Name = "StartNode"
    startNode.Size = cfg.nodeSize
    startNode.Position = cfg.startPosition
    startNode.Anchored = true
    startNode.CanCollide = true
    startNode.Material = Enum.Material.Metal
    startNode.Color = cfg.nodeColor
    startNode.Parent = folder

    local startAtt = Instance.new("Attachment")
    startAtt.Name = "ZiplineAttachment"
    startAtt.Parent = startNode

    -- End node
    local endNode = Instance.new("Part")
    endNode.Name = "EndNode"
    endNode.Size = cfg.nodeSize
    endNode.Position = cfg.endPosition
    endNode.Anchored = true
    endNode.CanCollide = true
    endNode.Material = Enum.Material.Metal
    endNode.Color = cfg.nodeColor
    endNode.Parent = folder

    local endAtt = Instance.new("Attachment")
    endAtt.Name = "ZiplineAttachment"
    endAtt.Parent = endNode

    -- Cable beam
    local beam = Instance.new("Beam")
    beam.Name = "Cable"
    beam.Attachment0 = startAtt
    beam.Attachment1 = endAtt
    beam.Color = ColorSequence.new(cfg.cableColor)
    beam.Width0 = cfg.cableWidth
    beam.Width1 = cfg.cableWidth
    beam.FaceCamera = true
    beam.Segments = 30
    beam.CurveSize0 = 0
    beam.CurveSize1 = cfg.cableSag
    beam.Parent = startNode

    -- Store config as attributes
    startNode:SetAttribute("ZiplineSpeed", cfg.speed)
    startNode:SetAttribute("ZiplineEndX", cfg.endPosition.X)
    startNode:SetAttribute("ZiplineEndY", cfg.endPosition.Y)
    startNode:SetAttribute("ZiplineEndZ", cfg.endPosition.Z)

    -- ProximityPrompt for attachment
    if cfg.useProximityPrompt then
        local prompt = Instance.new("ProximityPrompt")
        prompt.Name = "ZiplinePrompt"
        prompt.ActionText = cfg.promptText
        prompt.ObjectText = "Zipline"
        prompt.MaxActivationDistance = cfg.promptDistance
        prompt.HoldDuration = 0
        prompt.RequiresLineOfSight = false
        prompt.Parent = startNode

        -- Also add prompt at end node for reverse travel
        local reversePrompt = prompt:Clone()
        reversePrompt.Parent = endNode
    end

    folder.Parent = workspace
    return folder
end

-- Build from two existing parts
function ZiplineBuilder.createFromParts(startPart: BasePart, endPart: BasePart, config: ZiplineConfig?): Folder
    local cfg = config or table.clone(DEFAULT_CONFIG)
    cfg.startPosition = startPart.Position
    cfg.endPosition = endPart.Position
    return ZiplineBuilder.create(cfg)
end

return ZiplineBuilder
```

---

## 2. Zipline Rider (Server Script)

```luau
--!strict
-- ServerScriptService/ZiplineRider.server.lua
-- Handles zipline riding logic, player attachment, and movement.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

-- Track active riders
local activeRiders: { [Player]: {
    startPos: Vector3,
    endPos: Vector3,
    speed: number,
    progress: number,
    connection: RBXScriptConnection?,
    alignPosition: AlignPosition?,
    alignOrientation: AlignOrientation?,
    attachment: Attachment?,
} } = {}

-- Attach player to zipline
local function attachToZipline(player: Player, startPos: Vector3, endPos: Vector3, speed: number)
    local character = player.Character
    if not character then return end

    local humanoid = character:FindFirstChildWhichIsA("Humanoid")
    local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
    if not humanoid or not rootPart then return end

    -- Prevent walking/jumping while on zipline
    humanoid.PlatformStand = true

    -- Create attachment on root part
    local att = Instance.new("Attachment")
    att.Name = "ZiplineRiderAtt"
    att.Parent = rootPart

    -- AlignPosition to move along the line
    local alignPos = Instance.new("AlignPosition")
    alignPos.Name = "ZiplineAlign"
    alignPos.Mode = Enum.PositionAlignmentMode.OneAttachment
    alignPos.Attachment0 = att
    alignPos.MaxForce = 100000
    alignPos.MaxVelocity = speed
    alignPos.Responsiveness = 50
    alignPos.Position = startPos - Vector3.new(0, 3, 0) -- hang below cable
    alignPos.Parent = rootPart

    -- AlignOrientation to face direction of travel
    local alignOri = Instance.new("AlignOrientation")
    alignOri.Name = "ZiplineOrient"
    alignOri.Mode = Enum.OrientationAlignmentMode.OneAttachment
    alignOri.Attachment0 = att
    alignOri.MaxTorque = 50000
    alignOri.Responsiveness = 20
    local travelDir = (endPos - startPos).Unit
    alignOri.CFrame = CFrame.lookAt(Vector3.zero, travelDir)
    alignOri.Parent = rootPart

    -- Calculate total distance and time
    local totalDistance = (endPos - startPos).Magnitude
    local lineDirection = (endPos - startPos).Unit

    -- Determine starting progress (find closest point on line to player)
    local toPlayer = rootPart.Position - startPos
    local projection = toPlayer:Dot(lineDirection)
    local startProgress = math.clamp(projection / totalDistance, 0, 1)

    local riderData = {
        startPos = startPos,
        endPos = endPos,
        speed = speed,
        progress = startProgress,
        connection = nil,
        alignPosition = alignPos,
        alignOrientation = alignOri,
        attachment = att,
    }

    -- Movement update
    local connection = RunService.Heartbeat:Connect(function(dt: number)
        if not character.Parent or not rootPart.Parent then
            detachFromZipline(player)
            return
        end

        -- Advance progress
        riderData.progress += (speed * dt) / totalDistance

        if riderData.progress >= 1 then
            -- Reached end
            riderData.progress = 1
            detachFromZipline(player)
            return
        end

        -- Calculate position on line (with slight hang offset)
        local linePos = startPos:Lerp(endPos, riderData.progress)

        -- Add sag: parabolic curve simulating cable sag
        local sagAmount = -3 * 4 * riderData.progress * (1 - riderData.progress)
        linePos = linePos + Vector3.new(0, sagAmount - 3, 0) -- hang below + sag

        alignPos.Position = linePos
    end)

    riderData.connection = connection
    activeRiders[player] = riderData

    -- Set attribute for client VFX
    character:SetAttribute("OnZipline", true)
end

-- Detach player from zipline
function detachFromZipline(player: Player)
    local data = activeRiders[player]
    if not data then return end

    -- Disconnect heartbeat
    if data.connection then
        data.connection:Disconnect()
    end

    -- Remove constraints
    if data.alignPosition then data.alignPosition:Destroy() end
    if data.alignOrientation then data.alignOrientation:Destroy() end
    if data.attachment then data.attachment:Destroy() end

    activeRiders[player] = nil

    -- Restore humanoid
    local character = player.Character
    if character then
        local humanoid = character:FindFirstChildWhichIsA("Humanoid")
        if humanoid then
            humanoid.PlatformStand = false
        end
        character:SetAttribute("OnZipline", false)

        -- Give a small upward impulse on detach to prevent immediate fall
        local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
        if rootPart then
            rootPart:ApplyImpulse(Vector3.new(0, 300, 0))
        end
    end
end

-- Setup ProximityPrompt handlers for all zipline nodes
local function setupZiplineNode(node: BasePart)
    local prompt = node:FindFirstChild("ZiplinePrompt") :: ProximityPrompt?
    if not prompt then return end

    prompt.Triggered:Connect(function(playerWhoTriggered: Player)
        -- Prevent double-riding
        if activeRiders[playerWhoTriggered] then return end

        -- Determine direction
        local folder = node.Parent
        if not folder then return end

        local startNode = folder:FindFirstChild("StartNode") :: BasePart?
        local endNode = folder:FindFirstChild("EndNode") :: BasePart?
        if not startNode or not endNode then return end

        local speed = startNode:GetAttribute("ZiplineSpeed") or 40

        -- If triggered from start, go to end; if from end, go to start
        local startPos: Vector3
        local endPos: Vector3
        if node == startNode then
            startPos = startNode.Position
            endPos = endNode.Position
        else
            startPos = endNode.Position
            endPos = startNode.Position
        end

        attachToZipline(playerWhoTriggered, startPos, endPos, speed)
    end)
end

-- Initialize existing ziplines
for _, folder in CollectionService:GetTagged("Zipline") do
    for _, child in folder:GetChildren() do
        if child:IsA("BasePart") then
            setupZiplineNode(child)
        end
    end
end

-- Listen for new ziplines
CollectionService:GetInstanceAddedSignal("Zipline"):Connect(function(instance)
    if instance:IsA("Folder") then
        task.wait(0.1) -- wait for children to load
        for _, child in instance:GetChildren() do
            if child:IsA("BasePart") then
                setupZiplineNode(child)
            end
        end
    end
end)

-- Detach on jump (allow player to jump off zipline)
local jumpRemote = Instance.new("RemoteEvent")
jumpRemote.Name = "ZiplineJumpOff"
jumpRemote.Parent = game:GetService("ReplicatedStorage")

jumpRemote.OnServerEvent:Connect(function(player: Player)
    if activeRiders[player] then
        detachFromZipline(player)
    end
end)

-- Cleanup on player leave
Players.PlayerRemoving:Connect(function(player: Player)
    if activeRiders[player] then
        detachFromZipline(player)
    end
end)
```

---

## 3. Zipline Client VFX (Client Script)

```luau
--!strict
-- StarterPlayerScripts/ZiplineVFX.client.lua
-- Visual and audio effects while riding a zipline.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- Configuration
local WIND_SOUND_ID = ""          -- looping wind sound
local SPEED_LINES = true
local CAMERA_TILT = true
local CAMERA_TILT_ANGLE = 5       -- degrees
local FOV_BOOST = 8

-- State
local windSound: Sound? = nil
local speedParticles: ParticleEmitter? = nil
local originalFOV = 70

-- Jump off zipline remote
local jumpOffRemote = ReplicatedStorage:WaitForChild("ZiplineJumpOff", 10) :: RemoteEvent?

-- Create wind sound
local function startWindSound(rootPart: BasePart)
    if WIND_SOUND_ID == "" then return end

    local sound = Instance.new("Sound")
    sound.Name = "ZiplineWind"
    sound.SoundId = WIND_SOUND_ID
    sound.Looped = true
    sound.Volume = 0.4
    sound.Parent = rootPart
    sound:Play()
    windSound = sound
end

local function stopWindSound()
    if windSound then
        windSound:Stop()
        windSound:Destroy()
        windSound = nil
    end
end

-- Speed line particles
local function startSpeedLines(rootPart: BasePart)
    if not SPEED_LINES then return end

    local emitter = Instance.new("ParticleEmitter")
    emitter.Name = "ZiplineSpeedLines"
    emitter.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
    emitter.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0),
        NumberSequenceKeypoint.new(0.1, 0.1),
        NumberSequenceKeypoint.new(1, 0),
    })
    emitter.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.5),
        NumberSequenceKeypoint.new(1, 1),
    })
    emitter.Lifetime = NumberRange.new(0.2, 0.4)
    emitter.Speed = NumberRange.new(30, 50)
    emitter.SpreadAngle = Vector2.new(10, 10)
    emitter.Rate = 40
    emitter.EmissionDirection = Enum.NormalId.Back
    emitter.Parent = rootPart
    speedParticles = emitter
end

local function stopSpeedLines()
    if speedParticles then
        speedParticles:Destroy()
        speedParticles = nil
    end
end

-- Camera effects
local function startCameraEffects()
    originalFOV = camera.FieldOfView
    TweenService:Create(
        camera,
        TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { FieldOfView = originalFOV + FOV_BOOST }
    ):Play()
end

local function stopCameraEffects()
    TweenService:Create(
        camera,
        TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
        { FieldOfView = originalFOV }
    ):Play()
end

-- Monitor zipline state
local wasOnZipline = false

RunService.RenderStepped:Connect(function()
    local character = player.Character
    if not character then return end

    local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
    if not rootPart then return end

    local onZipline = character:GetAttribute("OnZipline") == true

    -- Started riding
    if onZipline and not wasOnZipline then
        startWindSound(rootPart)
        startSpeedLines(rootPart)
        startCameraEffects()
    end

    -- Stopped riding
    if not onZipline and wasOnZipline then
        stopWindSound()
        stopSpeedLines()
        stopCameraEffects()
    end

    wasOnZipline = onZipline
end)

-- Allow jumping off with Space
UserInputService.JumpRequest:Connect(function()
    local character = player.Character
    if not character then return end

    if character:GetAttribute("OnZipline") == true then
        if jumpOffRemote then
            jumpOffRemote:FireServer()
        end
    end
end)
```

---

## Guidelines

- **AlignPosition** is preferred over BodyVelocity (deprecated) for moving the player along the zipline path.
- **Set `Humanoid.PlatformStand = true`** while riding to prevent walking/jumping conflicts.
- **ProximityPrompt** is the cleanest way to let players attach to ziplines.
- **Cable sag** is simulated visually via `Beam.CurveSize` and physically by offsetting the rider position with a parabolic curve.
- **Jump to detach**: listen for JumpRequest on client, fire RemoteEvent to server to detach.
- The rider position is calculated as a `Lerp` between start and end positions, offset downward to "hang" below the cable.
- **Bidirectional travel**: add ProximityPrompt to both start and end nodes.
- Use `Debris:AddItem()` for any temporary VFX parts.
- Clean up all constraints and attachments on detach, death, and player leaving.

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

When generating zipline code, adapt to these user-specified parameters:

- `$SPEED` - Travel speed in studs/s (default: 40)
- `$CABLE_COLOR` - Color of the zipline cable (default: "80,80,80")
- `$CABLE_WIDTH` - Visual width of cable (default: 0.3)
- `$CABLE_SAG` - Visual sag amount (default: -3)
- `$USE_PROXIMITY_PROMPT` - Whether to use ProximityPrompt or touch trigger (default: true)
- `$PROMPT_TEXT` - Text shown on ProximityPrompt (default: "Ride Zipline")
- `$BIDIRECTIONAL` - Whether zipline works both ways (default: true)
- `$JUMP_TO_DETACH` - Whether pressing jump detaches from zipline (default: true)
- `$VFX_SPEED_LINES` - Whether to show speed particles (default: true)
- `$VFX_FOV` - Whether to boost FOV while riding (default: true)
- `$WIND_SOUND` - Whether to play wind sound (default: true)
