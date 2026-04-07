---
name: constraint-build
description: |
  Building with constraints in Roblox. Rope bridges, swinging platforms, drawbridges
  with HingeConstraint, pendulums, chain links, and physics-based interactive structures
  using RopeConstraint, SpringConstraint, and BallSocketConstraint.
  제약 조건 빌딩, 로프 다리, 스윙 플랫폼, 도개교, 진자, 체인 링크
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
effort: high
---

# Building with Constraints

Build physics-based interactive structures using Roblox constraints: rope bridges, swinging platforms, drawbridges, pendulums, and chain link systems.

## Architecture Overview

```
ServerScriptService/
  ConstraintBuilder.server.lua   -- Server-side structure creation and interaction
ReplicatedStorage/
  ConstraintConfig.lua           -- Presets for different structure types
  ConstraintShared.lua           -- Shared types
  ConstraintLib.lua              -- Reusable constraint creation utilities
Workspace/
  Structures/                    -- Generated or placed constraint structures
```

## Constraint Library (Reusable Utilities)

```lua
-- ReplicatedStorage/ConstraintLib.lua
local ConstraintLib = {}

--------------------------------------------------------------------------------
-- Create an Attachment on a part at a local position
--------------------------------------------------------------------------------
function ConstraintLib.createAttachment(part: BasePart, position: Vector3?, name: string?): Attachment
    local attachment = Instance.new("Attachment")
    attachment.Name = name or "Attachment"
    if position then
        attachment.Position = position
    end
    attachment.Parent = part
    return attachment
end

--------------------------------------------------------------------------------
-- Create a RopeConstraint between two parts
--------------------------------------------------------------------------------
function ConstraintLib.createRope(
    part0: BasePart, pos0: Vector3,
    part1: BasePart, pos1: Vector3,
    length: number,
    options: {
        thickness: number?,
        color: BrickColor?,
        visible: boolean?,
        restitution: number?,
    }?
): RopeConstraint
    local a0 = ConstraintLib.createAttachment(part0, pos0, "RopeAttach0")
    local a1 = ConstraintLib.createAttachment(part1, pos1, "RopeAttach1")

    local rope = Instance.new("RopeConstraint")
    rope.Attachment0 = a0
    rope.Attachment1 = a1
    rope.Length = length
    rope.Visible = if options and options.visible ~= nil then options.visible else true
    rope.Thickness = (options and options.thickness) or 0.2
    rope.Color = (options and options.color) or BrickColor.new("Brown")
    rope.Restitution = (options and options.restitution) or 0.3
    rope.Parent = part0
    return rope
end

--------------------------------------------------------------------------------
-- Create a HingeConstraint (for drawbridges, doors, pendulums)
--------------------------------------------------------------------------------
function ConstraintLib.createHinge(
    part0: BasePart, pos0: Vector3, axis0: Vector3,
    part1: BasePart, pos1: Vector3,
    options: {
        actuatorType: Enum.ActuatorType?,
        angularSpeed: number?,
        targetAngle: number?,
        lowerAngle: number?,
        upperAngle: number?,
        limitsEnabled: boolean?,
        servoMaxTorque: number?,
        motorMaxTorque: number?,
    }?
): HingeConstraint
    local a0 = ConstraintLib.createAttachment(part0, pos0, "HingeAttach0")
    a0.Axis = axis0 or Vector3.new(1, 0, 0)

    local a1 = ConstraintLib.createAttachment(part1, pos1, "HingeAttach1")
    a1.Axis = axis0 or Vector3.new(1, 0, 0)

    local hinge = Instance.new("HingeConstraint")
    hinge.Attachment0 = a0
    hinge.Attachment1 = a1

    if options then
        hinge.ActuatorType = options.actuatorType or Enum.ActuatorType.None
        if options.actuatorType == Enum.ActuatorType.Servo then
            hinge.AngularSpeed = options.angularSpeed or 45
            hinge.TargetAngle = options.targetAngle or 0
            hinge.ServoMaxTorque = options.servoMaxTorque or 10000
        elseif options.actuatorType == Enum.ActuatorType.Motor then
            hinge.AngularVelocity = options.angularSpeed or 45
            hinge.MotorMaxTorque = options.motorMaxTorque or 10000
        end
        if options.limitsEnabled then
            hinge.LimitsEnabled = true
            hinge.LowerAngle = options.lowerAngle or -90
            hinge.UpperAngle = options.upperAngle or 90
        end
    end

    hinge.Parent = part0
    return hinge
end

--------------------------------------------------------------------------------
-- Create a SpringConstraint
--------------------------------------------------------------------------------
function ConstraintLib.createSpring(
    part0: BasePart, pos0: Vector3,
    part1: BasePart, pos1: Vector3,
    options: {
        stiffness: number?,
        damping: number?,
        freeLength: number?,
        visible: boolean?,
        thickness: number?,
        coils: number?,
    }?
): SpringConstraint
    local a0 = ConstraintLib.createAttachment(part0, pos0, "SpringAttach0")
    local a1 = ConstraintLib.createAttachment(part1, pos1, "SpringAttach1")

    local spring = Instance.new("SpringConstraint")
    spring.Attachment0 = a0
    spring.Attachment1 = a1
    spring.Stiffness = (options and options.stiffness) or 100
    spring.Damping = (options and options.damping) or 5
    spring.FreeLength = (options and options.freeLength) or 5
    spring.Visible = if options and options.visible ~= nil then options.visible else true
    spring.Thickness = (options and options.thickness) or 0.3
    spring.Coils = (options and options.coils) or 8
    spring.Parent = part0
    return spring
end

--------------------------------------------------------------------------------
-- Create a BallSocketConstraint (universal joint)
--------------------------------------------------------------------------------
function ConstraintLib.createBallSocket(
    part0: BasePart, pos0: Vector3,
    part1: BasePart, pos1: Vector3,
    options: {
        limitsEnabled: boolean?,
        upperAngle: number?,
        twistEnabled: boolean?,
        twistLower: number?,
        twistUpper: number?,
    }?
): BallSocketConstraint
    local a0 = ConstraintLib.createAttachment(part0, pos0, "BallAttach0")
    local a1 = ConstraintLib.createAttachment(part1, pos1, "BallAttach1")

    local ball = Instance.new("BallSocketConstraint")
    ball.Attachment0 = a0
    ball.Attachment1 = a1

    if options then
        ball.LimitsEnabled = options.limitsEnabled or false
        ball.UpperAngle = options.upperAngle or 45
        if options.twistEnabled then
            ball.TwistLimitsEnabled = true
            ball.TwistLowerAngle = options.twistLower or -45
            ball.TwistUpperAngle = options.twistUpper or 45
        end
    end

    ball.Parent = part0
    return ball
end

--------------------------------------------------------------------------------
-- Create a PrismaticConstraint (sliding rail)
--------------------------------------------------------------------------------
function ConstraintLib.createPrismatic(
    part0: BasePart, pos0: Vector3, axis: Vector3,
    part1: BasePart, pos1: Vector3,
    options: {
        actuatorType: Enum.ActuatorType?,
        speed: number?,
        targetPosition: number?,
        lowerLimit: number?,
        upperLimit: number?,
        limitsEnabled: boolean?,
        servoMaxForce: number?,
        motorMaxForce: number?,
    }?
): PrismaticConstraint
    local a0 = ConstraintLib.createAttachment(part0, pos0, "PrismaticAttach0")
    a0.Axis = axis or Vector3.new(0, 1, 0)

    local a1 = ConstraintLib.createAttachment(part1, pos1, "PrismaticAttach1")
    a1.Axis = axis or Vector3.new(0, 1, 0)

    local prismatic = Instance.new("PrismaticConstraint")
    prismatic.Attachment0 = a0
    prismatic.Attachment1 = a1

    if options then
        prismatic.ActuatorType = options.actuatorType or Enum.ActuatorType.None
        if options.limitsEnabled then
            prismatic.LimitsEnabled = true
            prismatic.LowerLimit = options.lowerLimit or -5
            prismatic.UpperLimit = options.upperLimit or 5
        end
        if options.actuatorType == Enum.ActuatorType.Servo then
            prismatic.Speed = options.speed or 5
            prismatic.TargetPosition = options.targetPosition or 0
            prismatic.ServoMaxForce = options.servoMaxForce or 50000
        elseif options.actuatorType == Enum.ActuatorType.Motor then
            prismatic.Velocity = options.speed or 5
            prismatic.MotorMaxForce = options.motorMaxForce or 50000
        end
    end

    prismatic.Parent = part0
    return prismatic
end

return ConstraintLib
```

## Structure Builders

```lua
-- ReplicatedStorage/ConstraintConfig.lua

local ConstraintConfig = {}

--------------------------------------------------------------------------------
-- Rope Bridge Builder
-- Creates a series of planks connected by rope constraints
--------------------------------------------------------------------------------
function ConstraintConfig.buildRopeBridge(
    startPos: Vector3,
    endPos: Vector3,
    plankCount: number?,
    plankSize: Vector3?,
    ropeSlack: number?
): Model
    local ConstraintLib = require(script.Parent:WaitForChild("ConstraintLib"))

    local numPlanks = plankCount or 10
    local size = plankSize or Vector3.new(6, 0.5, 2)
    local slack = ropeSlack or 1.2

    local bridge = Instance.new("Model")
    bridge.Name = "RopeBridge"

    local direction = (endPos - startPos)
    local spacing = direction.Magnitude / (numPlanks + 1)
    local dirUnit = direction.Unit

    -- Anchor points
    local anchorStart = Instance.new("Part")
    anchorStart.Size = Vector3.new(2, 4, size.Z + 2)
    anchorStart.Position = startPos
    anchorStart.Anchored = true
    anchorStart.Material = Enum.Material.Wood
    anchorStart.Color = Color3.fromRGB(120, 80, 40)
    anchorStart.Name = "AnchorStart"
    anchorStart.Parent = bridge

    local anchorEnd = Instance.new("Part")
    anchorEnd.Size = Vector3.new(2, 4, size.Z + 2)
    anchorEnd.Position = endPos
    anchorEnd.Anchored = true
    anchorEnd.Material = Enum.Material.Wood
    anchorEnd.Color = Color3.fromRGB(120, 80, 40)
    anchorEnd.Name = "AnchorEnd"
    anchorEnd.Parent = bridge

    local planks: { BasePart } = {}
    for i = 1, numPlanks do
        local plank = Instance.new("Part")
        plank.Size = size
        plank.Position = startPos + dirUnit * (spacing * i)
        plank.Anchored = false
        plank.Material = Enum.Material.Wood
        plank.Color = Color3.fromRGB(139, 90, 43)
        plank.Name = "Plank" .. i
        plank.Parent = bridge
        planks[i] = plank
    end

    -- Connect planks with ropes
    local ropeLength = spacing * slack
    local halfZ = size.Z / 2

    -- Connect first plank to start anchor (left and right ropes)
    ConstraintLib.createRope(
        anchorStart, Vector3.new(0, 1, halfZ),
        planks[1], Vector3.new(0, 0, halfZ),
        ropeLength
    )
    ConstraintLib.createRope(
        anchorStart, Vector3.new(0, 1, -halfZ),
        planks[1], Vector3.new(0, 0, -halfZ),
        ropeLength
    )

    -- Connect adjacent planks
    for i = 1, numPlanks - 1 do
        ConstraintLib.createRope(
            planks[i], Vector3.new(size.X / 2, 0, halfZ),
            planks[i + 1], Vector3.new(-size.X / 2, 0, halfZ),
            ropeLength * 0.6
        )
        ConstraintLib.createRope(
            planks[i], Vector3.new(size.X / 2, 0, -halfZ),
            planks[i + 1], Vector3.new(-size.X / 2, 0, -halfZ),
            ropeLength * 0.6
        )
    end

    -- Connect last plank to end anchor
    ConstraintLib.createRope(
        planks[numPlanks], Vector3.new(0, 0, halfZ),
        anchorEnd, Vector3.new(0, 1, halfZ),
        ropeLength
    )
    ConstraintLib.createRope(
        planks[numPlanks], Vector3.new(0, 0, -halfZ),
        anchorEnd, Vector3.new(0, 1, -halfZ),
        ropeLength
    )

    bridge.Parent = workspace
    return bridge
end

--------------------------------------------------------------------------------
-- Drawbridge Builder
-- A hinged platform that swings open/closed
--------------------------------------------------------------------------------
function ConstraintConfig.buildDrawbridge(
    position: Vector3,
    bridgeSize: Vector3?,
    openAngle: number?
): (Model, HingeConstraint)
    local ConstraintLib = require(script.Parent:WaitForChild("ConstraintLib"))

    local size = bridgeSize or Vector3.new(10, 0.5, 8)
    local angle = openAngle or -90

    local drawbridge = Instance.new("Model")
    drawbridge.Name = "Drawbridge"

    -- Fixed anchor at the hinge point
    local anchor = Instance.new("Part")
    anchor.Size = Vector3.new(size.X, 2, 2)
    anchor.Position = position
    anchor.Anchored = true
    anchor.Material = Enum.Material.Concrete
    anchor.Color = Color3.fromRGB(100, 100, 100)
    anchor.Name = "HingeAnchor"
    anchor.Parent = drawbridge

    -- The bridge platform
    local platform = Instance.new("Part")
    platform.Size = size
    platform.Position = position + Vector3.new(0, -1, size.Z / 2 + 1)
    platform.Anchored = false
    platform.Material = Enum.Material.Wood
    platform.Color = Color3.fromRGB(120, 80, 40)
    platform.Name = "Platform"
    platform.Parent = drawbridge

    -- Hinge constraint
    local hinge = ConstraintLib.createHinge(
        anchor, Vector3.new(0, -1, 1),
        Vector3.new(1, 0, 0),
        platform, Vector3.new(0, 0, -size.Z / 2),
        {
            actuatorType = Enum.ActuatorType.Servo,
            angularSpeed = 30,
            targetAngle = 0,
            limitsEnabled = true,
            lowerAngle = angle,
            upperAngle = 0,
            servoMaxTorque = 50000,
        }
    )

    drawbridge.Parent = workspace
    return drawbridge, hinge
end

--------------------------------------------------------------------------------
-- Pendulum Builder
--------------------------------------------------------------------------------
function ConstraintConfig.buildPendulum(
    anchorPos: Vector3,
    ropeLength: number?,
    bobSize: Vector3?,
    bobMass: number?
): Model
    local ConstraintLib = require(script.Parent:WaitForChild("ConstraintLib"))

    local length = ropeLength or 15
    local size = bobSize or Vector3.new(4, 4, 4)

    local pendulum = Instance.new("Model")
    pendulum.Name = "Pendulum"

    -- Anchor (invisible, anchored)
    local anchor = Instance.new("Part")
    anchor.Size = Vector3.new(2, 2, 2)
    anchor.Position = anchorPos
    anchor.Anchored = true
    anchor.Transparency = 0.5
    anchor.Name = "PendulumAnchor"
    anchor.Parent = pendulum

    -- Bob (the swinging weight)
    local bob = Instance.new("Part")
    bob.Size = size
    bob.Position = anchorPos + Vector3.new(length * 0.5, -length, 0) -- offset to start swinging
    bob.Anchored = false
    bob.Material = Enum.Material.Metal
    bob.Color = Color3.fromRGB(80, 80, 80)
    bob.Name = "Bob"
    bob.Parent = pendulum

    if bobMass then
        bob.CustomPhysicalProperties = PhysicalProperties.new(
            bobMass / (size.X * size.Y * size.Z), -- density
            0.3, -- friction
            0.1, -- elasticity
            1, 1
        )
    end

    -- Rod constraint (rigid rope)
    local rod = Instance.new("RodConstraint")
    local a0 = ConstraintLib.createAttachment(anchor, Vector3.new(0, 0, 0), "PendulumTop")
    local a1 = ConstraintLib.createAttachment(bob, Vector3.new(0, size.Y / 2, 0), "PendulumBob")
    rod.Attachment0 = a0
    rod.Attachment1 = a1
    rod.Length = length
    rod.Visible = true
    rod.Thickness = 0.3
    rod.Parent = anchor

    pendulum.Parent = workspace
    return pendulum
end

--------------------------------------------------------------------------------
-- Swinging Platform Builder
--------------------------------------------------------------------------------
function ConstraintConfig.buildSwingingPlatform(
    anchorPos: Vector3,
    chainLength: number?,
    platformSize: Vector3?
): Model
    local ConstraintLib = require(script.Parent:WaitForChild("ConstraintLib"))

    local length = chainLength or 10
    local size = platformSize or Vector3.new(8, 1, 8)

    local structure = Instance.new("Model")
    structure.Name = "SwingingPlatform"

    -- Ceiling anchor
    local anchor = Instance.new("Part")
    anchor.Size = Vector3.new(size.X + 2, 2, size.Z + 2)
    anchor.Position = anchorPos
    anchor.Anchored = true
    anchor.Material = Enum.Material.Metal
    anchor.Color = Color3.fromRGB(100, 100, 100)
    anchor.Transparency = 0.3
    anchor.Name = "CeilingAnchor"
    anchor.Parent = structure

    -- Platform
    local platform = Instance.new("Part")
    platform.Size = size
    platform.Position = anchorPos - Vector3.new(0, length, 0)
    platform.Anchored = false
    platform.Material = Enum.Material.Wood
    platform.Color = Color3.fromRGB(139, 90, 43)
    platform.Name = "Platform"
    platform.Parent = structure

    -- Four corner ropes
    local halfX = size.X / 2 - 0.5
    local halfZ = size.Z / 2 - 0.5
    local corners = {
        { Vector3.new(-halfX, 0, -halfZ), Vector3.new(-halfX, 0, -halfZ) },
        { Vector3.new(halfX, 0, -halfZ), Vector3.new(halfX, 0, -halfZ) },
        { Vector3.new(-halfX, 0, halfZ), Vector3.new(-halfX, 0, halfZ) },
        { Vector3.new(halfX, 0, halfZ), Vector3.new(halfX, 0, halfZ) },
    }

    for i, corner in corners do
        ConstraintLib.createRope(
            anchor, corner[1],
            platform, corner[2],
            length * 1.02, -- slightly slack
            { thickness = 0.15, color = BrickColor.new("Dark stone grey") }
        )
    end

    structure.Parent = workspace
    return structure
end

--------------------------------------------------------------------------------
-- Chain Link Builder
-- Creates a chain of connected links between two points
--------------------------------------------------------------------------------
function ConstraintConfig.buildChain(
    startPos: Vector3,
    endPos: Vector3,
    linkCount: number?,
    linkSize: Vector3?
): Model
    local ConstraintLib = require(script.Parent:WaitForChild("ConstraintLib"))

    local numLinks = linkCount or 12
    local size = linkSize or Vector3.new(0.8, 0.3, 2)

    local chain = Instance.new("Model")
    chain.Name = "Chain"

    local direction = (endPos - startPos)
    local spacing = direction.Magnitude / (numLinks + 1)
    local dirUnit = direction.Unit

    -- Anchor points
    local anchorStart = Instance.new("Part")
    anchorStart.Size = Vector3.new(1, 1, 1)
    anchorStart.Position = startPos
    anchorStart.Anchored = true
    anchorStart.Name = "ChainStart"
    anchorStart.Parent = chain

    local anchorEnd = Instance.new("Part")
    anchorEnd.Size = Vector3.new(1, 1, 1)
    anchorEnd.Position = endPos
    anchorEnd.Anchored = true
    anchorEnd.Name = "ChainEnd"
    anchorEnd.Parent = chain

    local links: { BasePart } = {}
    for i = 1, numLinks do
        local link = Instance.new("Part")
        link.Size = size
        link.Position = startPos + dirUnit * (spacing * i)
        link.Anchored = false
        link.Material = Enum.Material.Metal
        link.Color = Color3.fromRGB(120, 120, 120)
        link.Name = "Link" .. i

        -- Alternate rotation for chain look
        if i % 2 == 0 then
            link.CFrame = link.CFrame * CFrame.Angles(0, math.rad(90), 0)
        end

        link.Parent = chain
        links[i] = link
    end

    -- Connect with BallSocket constraints
    -- Start anchor to first link
    ConstraintLib.createBallSocket(
        anchorStart, Vector3.new(0, 0, 0),
        links[1], Vector3.new(0, 0, -size.Z / 2),
        { limitsEnabled = true, upperAngle = 30 }
    )

    -- Link to link
    for i = 1, numLinks - 1 do
        ConstraintLib.createBallSocket(
            links[i], Vector3.new(0, 0, size.Z / 2),
            links[i + 1], Vector3.new(0, 0, -size.Z / 2),
            { limitsEnabled = true, upperAngle = 20 }
        )
    end

    -- Last link to end anchor
    ConstraintLib.createBallSocket(
        links[numLinks], Vector3.new(0, 0, size.Z / 2),
        anchorEnd, Vector3.new(0, 0, 0),
        { limitsEnabled = true, upperAngle = 30 }
    )

    chain.Parent = workspace
    return chain
end

return ConstraintConfig
```

## Server: Interactive Structures

```lua
-- ServerScriptService/ConstraintBuilder.server.lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local ConstraintLib = require(ReplicatedStorage:WaitForChild("ConstraintLib"))

-- Handle drawbridge toggle via ProximityPrompt
for _, part in CollectionService:GetTagged("DrawbridgeLever") do
    local bridgeName = part:GetAttribute("BridgeName")
    if not bridgeName then continue end

    local prompt = Instance.new("ProximityPrompt")
    prompt.ActionText = "Toggle Bridge"
    prompt.HoldDuration = 0.5
    prompt.Parent = part

    local isOpen = false

    prompt.Triggered:Connect(function(player)
        local bridge = workspace:FindFirstChild(bridgeName)
        if not bridge then return end

        local hingeAnchor = bridge:FindFirstChild("HingeAnchor")
        if not hingeAnchor then return end

        local hinge = hingeAnchor:FindFirstChildWhichIsA("HingeConstraint")
        if not hinge then return end

        isOpen = not isOpen
        hinge.TargetAngle = if isOpen then hinge.LowerAngle else 0

        -- Play sound effect
        local sound = Instance.new("Sound")
        sound.SoundId = "rbxassetid://0" -- bridge creaking sound
        sound.Volume = 0.8
        sound.Parent = part
        sound:Play()
        sound.Ended:Connect(function() sound:Destroy() end)
    end)
end

-- Handle elevator/lift platforms
for _, part in CollectionService:GetTagged("ElevatorButton") do
    local elevatorName = part:GetAttribute("ElevatorName")
    local targetPosition = part:GetAttribute("TargetPosition") -- number

    if not elevatorName or not targetPosition then continue end

    local prompt = Instance.new("ProximityPrompt")
    prompt.ActionText = "Call Elevator"
    prompt.Parent = part

    prompt.Triggered:Connect(function()
        local elevator = workspace:FindFirstChild(elevatorName)
        if not elevator then return end

        local platform = elevator:FindFirstChild("Platform")
        if not platform then return end

        local prismatic = platform:FindFirstChildWhichIsA("PrismaticConstraint")
            or platform.Parent:FindFirstChildWhichIsA("PrismaticConstraint")
        if not prismatic then return end

        prismatic.TargetPosition = targetPosition
    end)
end
```

## Key Implementation Notes

1. **RopeConstraint**: Flexible connection with sag. Use for rope bridges, hanging decorations, swinging platforms. Set `Length` slightly longer than distance for natural sag.

2. **HingeConstraint**: Rotation around a single axis. Use Servo actuator for controlled motion (drawbridges, doors). Use Motor for continuous rotation (windmills, gears).

3. **SpringConstraint**: Elastic connection. Great for bouncy platforms, shock absorbers, trampoline effects. Tune `Stiffness` and `Damping`.

4. **BallSocketConstraint**: Universal joint allowing rotation in all directions. Use for chain links and ragdoll joints. Enable `LimitsEnabled` to restrict swing angle.

5. **RodConstraint**: Rigid distance constraint (not a physical rod). Use for pendulums where you want fixed-length connection.

6. **PrismaticConstraint**: Linear sliding motion. Use for elevators, sliding doors, pistons. Servo actuator for position control.

7. **Performance**: Unanchored physics parts have CPU cost. Use `Anchored = true` where possible. For large rope bridges, consider fewer planks or freezing distant bridges.

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

When the user asks for constraint-based structures, ask:
- What type of structure? (rope bridge, drawbridge, pendulum, chain, elevator)
- How large should it be? (dimensions, number of links/planks)
- Should it be interactive? (toggle switch, button, proximity prompt)
- Does it need physics simulation or just visual appearance?
- Any performance concerns? (many structures, mobile support)
- Should structures be procedurally generated or manually placed in Studio?
