---
name: vehicle-system
description: |
  Vehicle system for Roblox: car chassis, wheels with CylindricalConstraint, steering,
  VehicleSeat, boat, simple plane, speed/brake controls. Use when the user asks about
  vehicles, cars, driving, boats, planes, steering, throttle, brake, VehicleSeat, chassis,
  wheel constraints, suspension, or CylindricalConstraint.
  차량, 자동차, 운전, 보트, 비행기, 조향, 스로틀, 브레이크, 서스펜션, 바퀴.
  Triggers on: vehicle, car, drive, boat, plane, steering, throttle, brake, chassis, wheel,
  suspension, VehicleSeat, CylindricalConstraint, HingeConstraint, SpringConstraint.
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
effort: high
---

# Vehicle System Skill

Build production-quality vehicles in Roblox using modern constraint-based physics.
All code is Luau, targets Roblox 2024+ APIs, and follows best practices.

---

## Architecture Overview

```
Vehicle (Model)
 ├─ Chassis (MeshPart / Part) [RootPart]
 │   └─ VehicleSeat
 ├─ WheelFL (MeshPart)
 │   ├─ CylindricalConstraint → Chassis  (suspension + axle spin)
 │   └─ Attachment
 ├─ WheelFR ...
 ├─ WheelRL ...
 └─ WheelRR ...
```

---

## 1. Car Chassis Builder (Server Module)

```luau
--!strict
-- ServerScriptService/VehicleBuilder.lua
-- Builds a constraint-based car at runtime.

local VehicleBuilder = {}

export type VehicleConfig = {
    chassisSize: Vector3,
    chassisCFrame: CFrame,
    wheelRadius: number,
    wheelWidth: number,
    suspensionLength: number,
    suspensionStiffness: number,
    suspensionDamping: number,
    maxSteerAngle: number,       -- degrees
    maxMotorTorque: number,
    maxSpeed: number,            -- studs/s (angular velocity limit)
    brakeForce: number,
    driveType: "FWD" | "RWD" | "AWD",
}

local DEFAULT_CONFIG: VehicleConfig = {
    chassisSize       = Vector3.new(6, 1.5, 12),
    chassisCFrame     = CFrame.new(0, 10, 0),
    wheelRadius       = 1.5,
    wheelWidth         = 1,
    suspensionLength  = 2,
    suspensionStiffness = 5000,
    suspensionDamping = 500,
    maxSteerAngle     = 35,
    maxMotorTorque    = 800,
    maxSpeed          = 80,
    brakeForce        = 2000,
    driveType         = "RWD",
}

-- Helper: create a single wheel + CylindricalConstraint
local function createWheel(
    chassis: BasePart,
    config: VehicleConfig,
    localOffset: Vector3,
    name: string
): (BasePart, CylindricalConstraint)
    -- Wheel part
    local wheel = Instance.new("Part")
    wheel.Name = name
    wheel.Shape = Enum.PartType.Cylinder
    wheel.Size = Vector3.new(config.wheelWidth, config.wheelRadius * 2, config.wheelRadius * 2)
    wheel.TopSurface = Enum.SurfaceType.Smooth
    wheel.BottomSurface = Enum.SurfaceType.Smooth
    wheel.Material = Enum.Material.SmoothPlastic
    wheel.Color = Color3.fromRGB(30, 30, 30)
    wheel.CustomPhysicalProperties = PhysicalProperties.new(
        1,    -- density
        1.5,  -- friction (high for grip)
        0.3,  -- elasticity
        1,    -- frictionWeight
        1     -- elasticityWeight
    )
    wheel.CFrame = chassis.CFrame * CFrame.new(localOffset)
        * CFrame.Angles(0, 0, math.rad(90)) -- orient cylinder sideways
    wheel.Parent = chassis.Parent

    -- Attachments
    local chassisAttach = Instance.new("Attachment")
    chassisAttach.Name = name .. "_ChassisAttach"
    chassisAttach.Position = localOffset
    chassisAttach.Parent = chassis

    local wheelAttach = Instance.new("Attachment")
    wheelAttach.Name = name .. "_WheelAttach"
    wheelAttach.Parent = wheel

    -- CylindricalConstraint acts as suspension (sliding axis) + axle (rotation)
    local constraint = Instance.new("CylindricalConstraint")
    constraint.Name = name .. "_Constraint"
    constraint.Attachment0 = chassisAttach
    constraint.Attachment1 = wheelAttach

    -- Sliding axis = suspension travel (Y direction in local space)
    constraint.InclinationAngle = 90 -- slide along Y
    constraint.LimitsEnabled = true
    constraint.LowerLimit = -config.suspensionLength / 2
    constraint.UpperLimit = config.suspensionLength / 2

    -- Spring for suspension
    constraint.MotorMaxForce = 0 -- will be set by drive script
    constraint.Restitution = 0.2

    -- Rotation axis = wheel spin
    constraint.AngularLimitsEnabled = false
    constraint.RotationAxisVisible = false

    constraint.Parent = wheel

    -- SpringConstraint for suspension damping
    local spring = Instance.new("SpringConstraint")
    spring.Name = name .. "_Spring"
    spring.Attachment0 = chassisAttach
    spring.Attachment1 = wheelAttach
    spring.Stiffness = config.suspensionStiffness
    spring.Damping = config.suspensionDamping
    spring.FreeLength = config.suspensionLength
    spring.LimitsEnabled = true
    spring.MinLength = config.suspensionLength * 0.3
    spring.MaxLength = config.suspensionLength * 1.2
    spring.Parent = wheel

    return wheel, constraint
end

function VehicleBuilder.build(overrides: VehicleConfig?): Model
    local config = table.clone(DEFAULT_CONFIG)
    if overrides then
        for k, v in overrides :: any do
            (config :: any)[k] = v
        end
    end

    local model = Instance.new("Model")
    model.Name = "Vehicle"

    -- Chassis
    local chassis = Instance.new("Part")
    chassis.Name = "Chassis"
    chassis.Size = config.chassisSize
    chassis.CFrame = config.chassisCFrame
    chassis.Anchored = false
    chassis.TopSurface = Enum.SurfaceType.Smooth
    chassis.BottomSurface = Enum.SurfaceType.Smooth
    chassis.Material = Enum.Material.SmoothPlastic
    chassis.Color = Color3.fromRGB(200, 40, 40)
    chassis.Parent = model

    model.PrimaryPart = chassis

    -- VehicleSeat
    local seat = Instance.new("VehicleSeat")
    seat.Name = "DriverSeat"
    seat.Size = Vector3.new(2, 1, 2)
    seat.CFrame = chassis.CFrame * CFrame.new(0, 1.25, 0)
    seat.MaxSpeed = config.maxSpeed
    seat.Torque = config.maxMotorTorque
    seat.TurnSpeed = config.maxSteerAngle
    seat.Parent = model

    -- Weld seat to chassis
    local seatWeld = Instance.new("WeldConstraint")
    seatWeld.Part0 = chassis
    seatWeld.Part1 = seat
    seatWeld.Parent = seat

    -- Wheel offsets (local to chassis center)
    local halfX = config.chassisSize.X / 2 + config.wheelWidth / 2 + 0.2
    local halfZ = config.chassisSize.Z / 2 - config.wheelRadius
    local yOff = -(config.chassisSize.Y / 2)

    local wheelPositions = {
        { name = "WheelFL", offset = Vector3.new(-halfX, yOff, halfZ) },
        { name = "WheelFR", offset = Vector3.new(halfX, yOff, halfZ) },
        { name = "WheelRL", offset = Vector3.new(-halfX, yOff, -halfZ) },
        { name = "WheelRR", offset = Vector3.new(halfX, yOff, -halfZ) },
    }

    local wheels: { [string]: BasePart } = {}
    local constraints: { [string]: CylindricalConstraint } = {}

    for _, wp in wheelPositions do
        local wheel, constraint = createWheel(chassis, config, wp.offset, wp.name)
        wheels[wp.name] = wheel
        constraints[wp.name] = constraint
    end

    -- Store config as attributes for the drive script
    chassis:SetAttribute("MaxSteerAngle", config.maxSteerAngle)
    chassis:SetAttribute("MaxMotorTorque", config.maxMotorTorque)
    chassis:SetAttribute("MaxSpeed", config.maxSpeed)
    chassis:SetAttribute("BrakeForce", config.brakeForce)
    chassis:SetAttribute("DriveType", config.driveType)

    model.Parent = workspace
    return model
end

return VehicleBuilder
```

---

## 2. Vehicle Drive Controller (Server Script)

```luau
--!strict
-- ServerScriptService/VehicleDriveController.server.lua
-- Reads VehicleSeat.Throttle / .Steer and drives constraints.

local RunService = game:GetService("RunService")

local function setupVehicle(vehicleModel: Model)
    local chassis = vehicleModel:FindFirstChild("Chassis") :: Part
    local seat = vehicleModel:FindFirstChild("DriverSeat") :: VehicleSeat
    if not chassis or not seat then return end

    local maxSteer = chassis:GetAttribute("MaxSteerAngle") :: number
    local maxTorque = chassis:GetAttribute("MaxMotorTorque") :: number
    local maxSpeed = chassis:GetAttribute("MaxSpeed") :: number
    local brakeForce = chassis:GetAttribute("BrakeForce") :: number
    local driveType = chassis:GetAttribute("DriveType") :: string

    -- Collect constraints
    local frontConstraints: { CylindricalConstraint } = {}
    local rearConstraints: { CylindricalConstraint } = {}
    local allConstraints: { CylindricalConstraint } = {}

    for _, child in vehicleModel:GetDescendants() do
        if child:IsA("CylindricalConstraint") then
            local cyl = child :: CylindricalConstraint
            table.insert(allConstraints, cyl)
            if child.Name:match("^WheelF") then
                table.insert(frontConstraints, cyl)
            else
                table.insert(rearConstraints, cyl)
            end
        end
    end

    -- Determine drive constraints
    local driveConstraints: { CylindricalConstraint } = {}
    if driveType == "FWD" then
        driveConstraints = frontConstraints
    elseif driveType == "RWD" then
        driveConstraints = rearConstraints
    else -- AWD
        driveConstraints = allConstraints
    end

    -- Enable motor on drive wheels
    for _, c in driveConstraints do
        c.AngularActuatorType = Enum.ActuatorType.Motor
        c.MotorMaxAngularAcceleration = 50
        c.MotorMaxTorque = maxTorque
    end

    -- Steering: rotate front wheel chassis attachments
    local steerAttachments: { Attachment } = {}
    for _, name in { "WheelFL_ChassisAttach", "WheelFR_ChassisAttach" } do
        local att = chassis:FindFirstChild(name) :: Attachment?
        if att then
            table.insert(steerAttachments, att)
        end
    end

    local baseOrientations: { CFrame } = {}
    for i, att in steerAttachments do
        baseOrientations[i] = att.CFrame
    end

    RunService.Heartbeat:Connect(function(_dt: number)
        local throttle = seat.ThrottleFloat  -- -1 to 1
        local steer = seat.SteerFloat        -- -1 to 1

        -- Drive motor
        local targetAngVel = throttle * maxSpeed
        for _, c in driveConstraints do
            c.AngularVelocity = targetAngVel
        end

        -- Braking: if throttle is zero while moving
        if throttle == 0 then
            for _, c in allConstraints do
                c.MotorMaxTorque = brakeForce
                c.AngularVelocity = 0
            end
        else
            for _, c in driveConstraints do
                c.MotorMaxTorque = maxTorque
            end
        end

        -- Steering
        local steerRad = math.rad(steer * maxSteer)
        for i, att in steerAttachments do
            att.CFrame = baseOrientations[i] * CFrame.Angles(0, steerRad, 0)
        end
    end)
end

-- Auto-detect vehicles in workspace
for _, obj in workspace:GetChildren() do
    if obj:IsA("Model") and obj:FindFirstChild("DriverSeat") then
        setupVehicle(obj)
    end
end

workspace.ChildAdded:Connect(function(child)
    if child:IsA("Model") and child:FindFirstChild("DriverSeat") then
        task.wait(0.1)
        setupVehicle(child)
    end
end)
```

---

## 3. Boat System

```luau
--!strict
-- ServerScriptService/BoatSystem.lua
-- Buoyancy + rudder steering for boat vehicles.

local RunService = game:GetService("RunService")

export type BoatConfig = {
    buoyancyForce: number,
    waterHeight: number,
    dragCoefficient: number,
    rudderTurnSpeed: number,
    thrustForce: number,
    maxSpeed: number,
}

local DEFAULT_BOAT: BoatConfig = {
    buoyancyForce    = 5000,
    waterHeight      = 0,
    dragCoefficient  = 0.8,
    rudderTurnSpeed  = 1.5,
    thrustForce      = 3000,
    maxSpeed         = 60,
}

local BoatSystem = {}

function BoatSystem.setup(hull: BasePart, seat: VehicleSeat, config: BoatConfig?)
    local cfg = config or DEFAULT_BOAT

    local halfSize = hull.Size / 2
    local buoyancyOffsets = {
        Vector3.new(0, -halfSize.Y, halfSize.Z * 0.8),
        Vector3.new(0, -halfSize.Y, -halfSize.Z * 0.8),
        Vector3.new(-halfSize.X * 0.8, -halfSize.Y, 0),
        Vector3.new(halfSize.X * 0.8, -halfSize.Y, 0),
        Vector3.new(0, -halfSize.Y, 0),
    }

    local thrustAttach = Instance.new("Attachment")
    thrustAttach.Name = "ThrustAttach"
    thrustAttach.Parent = hull

    local thrustForce = Instance.new("VectorForce")
    thrustForce.Name = "Thrust"
    thrustForce.Attachment0 = thrustAttach
    thrustForce.RelativeTo = Enum.ActuatorRelativeTo.Attachment0
    thrustForce.Force = Vector3.zero
    thrustForce.Parent = hull

    local steerTorque = Instance.new("Torque")
    steerTorque.Name = "Rudder"
    steerTorque.Attachment0 = thrustAttach
    steerTorque.RelativeTo = Enum.ActuatorRelativeTo.Attachment0
    steerTorque.Torque = Vector3.zero
    steerTorque.Parent = hull

    RunService.Heartbeat:Connect(function(dt: number)
        for _, offset in buoyancyOffsets do
            local worldPos = hull.CFrame:PointToWorldSpace(offset)
            local depth = cfg.waterHeight - worldPos.Y
            if depth > 0 then
                local forceMag = cfg.buoyancyForce * math.min(depth, 3) / #buoyancyOffsets
                hull:ApplyImpulseAtPosition(
                    Vector3.new(0, forceMag * dt, 0),
                    worldPos
                )
            end
        end

        if hull.Position.Y < cfg.waterHeight then
            local vel = hull.AssemblyLinearVelocity
            local dragForce = -vel * cfg.dragCoefficient
            hull.AssemblyLinearVelocity = vel + dragForce * dt
            local angVel = hull.AssemblyAngularVelocity
            hull.AssemblyAngularVelocity = angVel * (1 - cfg.dragCoefficient * dt)
        end

        local throttle = seat.ThrottleFloat
        local steer = seat.SteerFloat
        local speed = hull.AssemblyLinearVelocity.Magnitude

        if hull.Position.Y < cfg.waterHeight + 2 then
            local thrustMag = throttle * cfg.thrustForce
            if speed < cfg.maxSpeed or throttle < 0 then
                thrustForce.Force = Vector3.new(0, 0, -thrustMag)
            else
                thrustForce.Force = Vector3.zero
            end
            steerTorque.Torque = Vector3.new(
                0,
                -steer * cfg.rudderTurnSpeed * 1000 * math.min(speed / 10, 1),
                0
            )
        else
            thrustForce.Force = Vector3.zero
            steerTorque.Torque = Vector3.zero
        end
    end)
end

return BoatSystem
```

---

## 4. Simple Plane System

```luau
--!strict
-- ServerScriptService/PlaneSystem.lua
-- Simplified plane with lift, thrust, pitch/roll/yaw.

local RunService = game:GetService("RunService")

export type PlaneConfig = {
    thrustForce: number,
    liftCoefficient: number,
    pitchSpeed: number,
    rollSpeed: number,
    yawSpeed: number,
    maxSpeed: number,
    dragCoefficient: number,
    stallSpeed: number,
}

local DEFAULT_PLANE: PlaneConfig = {
    thrustForce     = 8000,
    liftCoefficient = 1.2,
    pitchSpeed      = 3,
    rollSpeed       = 4,
    yawSpeed        = 1.5,
    maxSpeed        = 200,
    dragCoefficient = 0.3,
    stallSpeed      = 30,
}

local PlaneSystem = {}

function PlaneSystem.setup(fuselage: BasePart, seat: VehicleSeat, config: PlaneConfig?)
    local cfg = config or DEFAULT_PLANE

    local att = Instance.new("Attachment")
    att.Parent = fuselage

    local thrust = Instance.new("VectorForce")
    thrust.Attachment0 = att
    thrust.RelativeTo = Enum.ActuatorRelativeTo.Attachment0
    thrust.Parent = fuselage

    local torque = Instance.new("Torque")
    torque.Attachment0 = att
    torque.RelativeTo = Enum.ActuatorRelativeTo.Attachment0
    torque.Parent = fuselage

    local gyro = Instance.new("AlignOrientation")
    gyro.Attachment0 = att
    gyro.Mode = Enum.OrientationAlignmentMode.OneAttachment
    gyro.CFrame = fuselage.CFrame
    gyro.Responsiveness = 2
    gyro.MaxTorque = 5000
    gyro.Parent = fuselage

    RunService.Heartbeat:Connect(function(_dt: number)
        local throttle = seat.ThrottleFloat
        local steer = seat.SteerFloat
        local speed = fuselage.AssemblyLinearVelocity.Magnitude

        local thrustMag = math.max(throttle, 0) * cfg.thrustForce
        if speed < cfg.maxSpeed then
            thrust.Force = Vector3.new(0, 0, -thrustMag)
        else
            thrust.Force = Vector3.zero
        end

        local liftFactor = math.clamp((speed - cfg.stallSpeed) / cfg.stallSpeed, 0, 1)
        local lift = liftFactor * cfg.liftCoefficient * fuselage.AssemblyMass * workspace.Gravity
        fuselage:ApplyImpulse(Vector3.new(0, lift * _dt, 0))

        local dragForce = -fuselage.AssemblyLinearVelocity * cfg.dragCoefficient
        fuselage:ApplyImpulse(dragForce * _dt)

        local pitch = -throttle * cfg.pitchSpeed * 1000
        local roll = -steer * cfg.rollSpeed * 1000
        local yaw = steer * cfg.yawSpeed * 500
        torque.Torque = Vector3.new(pitch, yaw, roll)

        if math.abs(throttle) < 0.1 and math.abs(steer) < 0.1 then
            gyro.Enabled = true
        else
            gyro.Enabled = false
        end
    end)
end

return PlaneSystem
```

---

## 5. Speed/Brake Display HUD (Client)

```luau
--!strict
-- StarterPlayerScripts/VehicleHUD.client.lua
-- Shows speedometer and brake indicator when sitting in a VehicleSeat.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screenGui: ScreenGui? = nil
local speedLabel: TextLabel? = nil
local brakeIndicator: Frame? = nil
local currentSeat: VehicleSeat? = nil

local function createHUD(): ScreenGui
    local gui = Instance.new("ScreenGui")
    gui.Name = "VehicleHUD"
    gui.ResetOnSpawn = false

    local frame = Instance.new("Frame")
    frame.Name = "SpeedPanel"
    frame.Size = UDim2.fromOffset(200, 80)
    frame.Position = UDim2.new(0.5, -100, 1, -100)
    frame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
    frame.BackgroundTransparency = 0.3
    frame.Parent = gui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = frame

    local label = Instance.new("TextLabel")
    label.Name = "SpeedText"
    label.Size = UDim2.new(1, 0, 0.7, 0)
    label.BackgroundTransparency = 1
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.TextScaled = true
    label.Font = Enum.Font.GothamBold
    label.Text = "0 km/h"
    label.Parent = frame
    speedLabel = label

    local brake = Instance.new("Frame")
    brake.Name = "BrakeIndicator"
    brake.Size = UDim2.new(0.8, 0, 0.15, 0)
    brake.Position = UDim2.new(0.1, 0, 0.75, 0)
    brake.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
    brake.Parent = frame

    local brakeCorner = Instance.new("UICorner")
    brakeCorner.CornerRadius = UDim.new(0, 4)
    brakeCorner.Parent = brake
    brakeIndicator = brake

    gui.Parent = playerGui
    return gui
end

local function destroyHUD()
    if screenGui then
        screenGui:Destroy()
        screenGui = nil
        speedLabel = nil
        brakeIndicator = nil
    end
end

local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid") :: Humanoid

local connection: RBXScriptConnection? = nil

humanoid.Seated:Connect(function(active: boolean, seatPart: BasePart?)
    if active and seatPart and seatPart:IsA("VehicleSeat") then
        currentSeat = seatPart
        screenGui = createHUD()
        connection = RunService.RenderStepped:Connect(function()
            if currentSeat and speedLabel and brakeIndicator then
                local speed = currentSeat.AssemblyLinearVelocity.Magnitude
                local kmh = math.floor(speed * 0.681818)
                speedLabel.Text = tostring(kmh) .. " km/h"
                local isBraking = currentSeat.ThrottleFloat == 0 and speed > 2
                brakeIndicator.BackgroundColor3 = if isBraking
                    then Color3.fromRGB(255, 50, 50)
                    else Color3.fromRGB(60, 60, 60)
            end
        end)
    else
        currentSeat = nil
        if connection then
            connection:Disconnect()
            connection = nil
        end
        destroyHUD()
    end
end)
```

---

## Guidelines

- **Always use CylindricalConstraint** for car wheels; it combines suspension travel (linear axis) with wheel spin (angular axis) in one constraint.
- **SpringConstraint** alongside CylindricalConstraint provides realistic suspension damping.
- **VehicleSeat.ThrottleFloat / SteerFloat** are the primary input values; avoid reading keyboard input directly for vehicles.
- **Buoyancy for boats**: sample multiple points on the hull and apply upward impulses proportional to submersion depth.
- **Planes**: lift is proportional to forward speed; below stall speed the plane should lose altitude.
- For multiplayer, vehicle state is authoritative on the server; clients should only read replicated physics.
- Use `Debris:AddItem()` to clean up vehicle FX (exhaust particles, skid marks).

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

When generating vehicle code, adapt to these user-specified parameters:

- `$VEHICLE_TYPE` - "car" | "boat" | "plane" | "kart" | "truck" (default: "car")
- `$DRIVE_TYPE` - "FWD" | "RWD" | "AWD" (default: "RWD")
- `$MAX_SPEED` - Maximum speed in studs/second (default: 80)
- `$SUSPENSION_STIFFNESS` - Spring stiffness value (default: 5000)
- `$WHEEL_COUNT` - Number of wheels, 4 or 6 (default: 4)
- `$HAS_BOOST` - Whether to include a boost/nitro system (default: false)
- `$WATER_HEIGHT` - Y-level of water surface for boats (default: 0)
- `$INCLUDE_HUD` - Whether to generate the speed/brake HUD (default: true)
