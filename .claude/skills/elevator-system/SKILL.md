---
name: elevator-system
description: |
  Elevator system for Roblox: platform elevator with TweenService movement, call buttons
  at each floor, floor indicators/display, passenger detection on platform. Use when the
  user asks about elevators, lifts, platforms, moving platforms, floor buttons, vertical
  transport, TweenService platform, or call system.
  엘리베이터, 리프트, 플랫폼, 이동 플랫폼, 층 버튼, 수직 이동.
  Triggers on: elevator, lift, platform, moving platform, floor, call button, floor
  indicator, TweenService, vertical, ride platform, passenger detection.
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
effort: high
---

# Elevator System Skill

Production-quality elevator system with TweenService-driven platform movement,
call buttons, floor indicators, passenger detection, and queued floor requests.

---

## Architecture Overview

```
ElevatorSystem (Folder)
 ├─ Platform (Part, Anchored)
 │   ├─ FloorDisplay (SurfaceGui with TextLabel)
 │   └─ TouchRegion (invisible part for passenger detection)
 ├─ Floor1 (Folder)
 │   ├─ CallButton (Part + ClickDetector/ProximityPrompt)
 │   ├─ FloorIndicator (Part + SurfaceGui)
 │   └─ DoorLeft / DoorRight (optional)
 ├─ Floor2 ...
 └─ Floor3 ...
```

---

## 1. Elevator Service (Server Module)

```luau
--!strict
-- ServerScriptService/ElevatorService.lua
-- Core elevator logic: movement, floor queue, door control.

local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")

local ElevatorService = {}

export type FloorData = {
    name: string,
    position: Vector3,          -- position of the platform at this floor
    callButton: BasePart?,
    indicator: SurfaceGui?,
    doorLeft: BasePart?,
    doorRight: BasePart?,
}

export type ElevatorConfig = {
    floors: { FloorData },
    speed: number,              -- studs per second
    doorOpenTime: number,       -- seconds doors stay open
    doorMoveTime: number,       -- seconds for door open/close animation
    startFloor: number,         -- 1-indexed floor number to start at
    platformSize: Vector3,
    platformColor: Color3,
    acceleration: number,       -- tween easing responsiveness
}

local DEFAULT_CONFIG: ElevatorConfig = {
    floors = {},
    speed = 10,
    doorOpenTime = 3,
    doorMoveTime = 1,
    startFloor = 1,
    platformSize = Vector3.new(8, 1, 8),
    platformColor = Color3.fromRGB(150, 150, 150),
    acceleration = 0.5,
}

export type Elevator = {
    config: ElevatorConfig,
    platform: BasePart,
    currentFloor: number,
    targetFloor: number?,
    isMoving: boolean,
    isDoorOpen: boolean,
    floorQueue: { number },
    passengers: { Model },
    folder: Folder,
}

-- Build elevator from config
function ElevatorService.create(config: ElevatorConfig): Elevator
    local cfg = config

    -- Create folder
    local folder = Instance.new("Folder")
    folder.Name = "Elevator"
    CollectionService:AddTag(folder, "Elevator")

    -- Create platform
    local platform = Instance.new("Part")
    platform.Name = "Platform"
    platform.Size = cfg.platformSize
    platform.Color = cfg.platformColor
    platform.Material = Enum.Material.DiamondPlate
    platform.Anchored = true
    platform.TopSurface = Enum.SurfaceType.Smooth
    platform.BottomSurface = Enum.SurfaceType.Smooth
    platform.Parent = folder

    -- Set initial position
    if #cfg.floors > 0 and cfg.startFloor <= #cfg.floors then
        platform.Position = cfg.floors[cfg.startFloor].position
    end

    -- Floor display on platform
    local displayPart = Instance.new("Part")
    displayPart.Name = "DisplayBoard"
    displayPart.Size = Vector3.new(3, 2, 0.2)
    displayPart.Anchored = true
    displayPart.CanCollide = false
    displayPart.Material = Enum.Material.SmoothPlastic
    displayPart.Color = Color3.fromRGB(20, 20, 20)
    displayPart.CFrame = platform.CFrame * CFrame.new(0, cfg.platformSize.Y / 2 + 3, -cfg.platformSize.Z / 2 + 0.1)
    displayPart.Parent = folder

    local weld = Instance.new("WeldConstraint")
    weld.Part0 = platform
    weld.Part1 = displayPart
    weld.Parent = displayPart

    local surfaceGui = Instance.new("SurfaceGui")
    surfaceGui.Name = "FloorDisplay"
    surfaceGui.Face = Enum.NormalId.Front
    surfaceGui.Parent = displayPart

    local floorLabel = Instance.new("TextLabel")
    floorLabel.Name = "FloorText"
    floorLabel.Size = UDim2.fromScale(1, 0.6)
    floorLabel.Position = UDim2.fromScale(0, 0)
    floorLabel.BackgroundTransparency = 1
    floorLabel.TextColor3 = Color3.fromRGB(0, 255, 100)
    floorLabel.TextScaled = true
    floorLabel.Font = Enum.Font.Code
    floorLabel.Text = if #cfg.floors >= cfg.startFloor then cfg.floors[cfg.startFloor].name else "1"
    floorLabel.Parent = surfaceGui

    local directionLabel = Instance.new("TextLabel")
    directionLabel.Name = "DirectionText"
    directionLabel.Size = UDim2.fromScale(1, 0.4)
    directionLabel.Position = UDim2.fromScale(0, 0.6)
    directionLabel.BackgroundTransparency = 1
    directionLabel.TextColor3 = Color3.fromRGB(0, 200, 80)
    directionLabel.TextScaled = true
    directionLabel.Font = Enum.Font.Code
    directionLabel.Text = "-"
    directionLabel.Parent = surfaceGui

    folder.Parent = workspace

    local elevator: Elevator = {
        config = cfg,
        platform = platform,
        currentFloor = cfg.startFloor,
        targetFloor = nil,
        isMoving = false,
        isDoorOpen = false,
        floorQueue = {},
        passengers = {},
        folder = folder,
    }

    return elevator
end

-- Update floor display
function ElevatorService.updateDisplay(elevator: Elevator)
    local displayBoard = elevator.folder:FindFirstChild("DisplayBoard")
    if not displayBoard then return end

    local gui = displayBoard:FindFirstChild("FloorDisplay") :: SurfaceGui?
    if not gui then return end

    local floorText = gui:FindFirstChild("FloorText") :: TextLabel?
    local dirText = gui:FindFirstChild("DirectionText") :: TextLabel?

    if floorText then
        local floorData = elevator.config.floors[elevator.currentFloor]
        floorText.Text = if floorData then floorData.name else tostring(elevator.currentFloor)
    end

    if dirText then
        if elevator.isMoving and elevator.targetFloor then
            if elevator.targetFloor > elevator.currentFloor then
                dirText.Text = "▲"
            elseif elevator.targetFloor < elevator.currentFloor then
                dirText.Text = "▼"
            end
        else
            dirText.Text = "-"
        end
    end
end

-- Open doors
function ElevatorService.openDoors(elevator: Elevator)
    local floorData = elevator.config.floors[elevator.currentFloor]
    if not floorData then return end

    elevator.isDoorOpen = true

    local doorOpenOffset = Vector3.new(3, 0, 0) -- slide doors sideways

    if floorData.doorLeft then
        local doorTween = TweenService:Create(
            floorData.doorLeft,
            TweenInfo.new(elevator.config.doorMoveTime, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
            { Position = floorData.doorLeft.Position - doorOpenOffset }
        )
        floorData.doorLeft:SetAttribute("ClosedPosition", floorData.doorLeft.Position)
        doorTween:Play()
    end

    if floorData.doorRight then
        local doorTween = TweenService:Create(
            floorData.doorRight,
            TweenInfo.new(elevator.config.doorMoveTime, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
            { Position = floorData.doorRight.Position + doorOpenOffset }
        )
        floorData.doorRight:SetAttribute("ClosedPosition", floorData.doorRight.Position)
        doorTween:Play()
    end
end

-- Close doors
function ElevatorService.closeDoors(elevator: Elevator)
    local floorData = elevator.config.floors[elevator.currentFloor]
    if not floorData then return end

    if floorData.doorLeft then
        local closedPos = floorData.doorLeft:GetAttribute("ClosedPosition")
        if closedPos then
            TweenService:Create(
                floorData.doorLeft,
                TweenInfo.new(elevator.config.doorMoveTime, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
                { Position = closedPos }
            ):Play()
        end
    end

    if floorData.doorRight then
        local closedPos = floorData.doorRight:GetAttribute("ClosedPosition")
        if closedPos then
            TweenService:Create(
                floorData.doorRight,
                TweenInfo.new(elevator.config.doorMoveTime, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
                { Position = closedPos }
            ):Play()
        end
    end

    task.delay(elevator.config.doorMoveTime, function()
        elevator.isDoorOpen = false
    end)
end

-- Move elevator to a target floor
function ElevatorService.goToFloor(elevator: Elevator, floorIndex: number)
    if floorIndex < 1 or floorIndex > #elevator.config.floors then return end
    if floorIndex == elevator.currentFloor and not elevator.isMoving then return end

    -- Add to queue if already moving
    if elevator.isMoving then
        -- Avoid duplicates in queue
        for _, queued in elevator.floorQueue do
            if queued == floorIndex then return end
        end
        table.insert(elevator.floorQueue, floorIndex)
        return
    end

    elevator.isMoving = true
    elevator.targetFloor = floorIndex

    -- Close doors first
    if elevator.isDoorOpen then
        ElevatorService.closeDoors(elevator)
        task.wait(elevator.config.doorMoveTime + 0.2)
    end

    ElevatorService.updateDisplay(elevator)

    -- Calculate travel
    local targetPos = elevator.config.floors[floorIndex].position
    local distance = (targetPos - elevator.platform.Position).Magnitude
    local travelTime = distance / elevator.config.speed

    -- Tween the platform
    local tween = TweenService:Create(
        elevator.platform,
        TweenInfo.new(
            travelTime,
            Enum.EasingStyle.Sine,
            Enum.EasingDirection.InOut
        ),
        { Position = targetPos }
    )

    tween:Play()
    tween.Completed:Wait()

    -- Arrived at floor
    elevator.currentFloor = floorIndex
    elevator.targetFloor = nil
    elevator.isMoving = false

    ElevatorService.updateDisplay(elevator)

    -- Open doors
    ElevatorService.openDoors(elevator)

    -- Wait for passengers
    task.wait(elevator.config.doorOpenTime)

    -- Close doors
    ElevatorService.closeDoors(elevator)
    task.wait(elevator.config.doorMoveTime + 0.2)

    -- Process queue
    if #elevator.floorQueue > 0 then
        local nextFloor = table.remove(elevator.floorQueue, 1)
        if nextFloor then
            ElevatorService.goToFloor(elevator, nextFloor)
        end
    end
end

-- Call elevator to a floor (from call button)
function ElevatorService.callToFloor(elevator: Elevator, floorIndex: number)
    ElevatorService.goToFloor(elevator, floorIndex)
end

return ElevatorService
```

---

## 2. Passenger Detection (Server Script)

```luau
--!strict
-- ServerScriptService/ElevatorPassengers.server.lua
-- Detects passengers standing on the elevator platform and welds them.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

-- Track active passenger welds
local passengerWelds: { [Model]: WeldConstraint } = {}

local function getElevatorPlatforms(): { BasePart }
    local platforms: { BasePart } = {}
    for _, folder in CollectionService:GetTagged("Elevator") do
        local platform = folder:FindFirstChild("Platform") :: BasePart?
        if platform then
            table.insert(platforms, platform)
        end
    end
    return platforms
end

-- Check if a character is standing on a platform
local function isStandingOn(character: Model, platform: BasePart): boolean
    local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
    if not rootPart then return false end

    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    rayParams.FilterDescendantsInstances = { character }

    local ray = workspace:Raycast(
        rootPart.Position,
        Vector3.new(0, -5, 0),  -- raycast downward
        rayParams
    )

    return ray ~= nil and ray.Instance == platform
end

-- Weld passenger to platform for smooth riding
local function weldPassenger(character: Model, platform: BasePart)
    if passengerWelds[character] then return end

    local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
    if not rootPart then return end

    local weld = Instance.new("WeldConstraint")
    weld.Name = "ElevatorWeld"
    weld.Part0 = platform
    weld.Part1 = rootPart
    weld.Parent = rootPart

    passengerWelds[character] = weld
end

-- Remove passenger weld
local function unweldPassenger(character: Model)
    local weld = passengerWelds[character]
    if weld then
        weld:Destroy()
        passengerWelds[character] = nil
    end
end

-- Periodic check for passengers
RunService.Heartbeat:Connect(function()
    local platforms = getElevatorPlatforms()

    for _, player in Players:GetPlayers() do
        local character = player.Character
        if not character then continue end

        local humanoid = character:FindFirstChildWhichIsA("Humanoid")
        if not humanoid or humanoid.Health <= 0 then
            unweldPassenger(character)
            continue
        end

        local onAnyPlatform = false
        for _, platform in platforms do
            if isStandingOn(character, platform) then
                weldPassenger(character, platform)
                onAnyPlatform = true
                break
            end
        end

        if not onAnyPlatform then
            unweldPassenger(character)
        end
    end
end)

-- Cleanup on character death/removal
Players.PlayerAdded:Connect(function(player: Player)
    player.CharacterRemoving:Connect(function(character: Model)
        unweldPassenger(character)
    end)
end)
```

---

## 3. Call Button & Floor Indicator Setup

```luau
--!strict
-- ServerScriptService/ElevatorButtonSetup.server.lua
-- Creates call buttons and floor indicators, wires them to the elevator.

local TweenService = game:GetService("TweenService")
local ElevatorService = require(script.Parent:WaitForChild("ElevatorService"))

-- Example: build a 3-floor elevator
local FLOOR_HEIGHT = 15
local BASE_Y = 5

local floors: { ElevatorService.FloorData } = {}

for i = 1, 3 do
    local floorY = BASE_Y + (i - 1) * FLOOR_HEIGHT

    -- Call button
    local button = Instance.new("Part")
    button.Name = "CallButton_Floor" .. i
    button.Size = Vector3.new(1, 1, 0.3)
    button.Position = Vector3.new(6, floorY + 3, 0) -- on wall next to elevator
    button.Anchored = true
    button.Material = Enum.Material.SmoothPlastic
    button.Color = Color3.fromRGB(200, 50, 50)
    button.Parent = workspace

    local buttonCorner = Instance.new("Part")
    buttonCorner.Size = Vector3.new(1.4, 1.4, 0.1)
    buttonCorner.Position = button.Position - Vector3.new(0, 0, 0.2)
    buttonCorner.Anchored = true
    buttonCorner.Color = Color3.fromRGB(60, 60, 60)
    buttonCorner.Parent = workspace

    -- ProximityPrompt on button
    local prompt = Instance.new("ProximityPrompt")
    prompt.ActionText = "Call Elevator"
    prompt.ObjectText = "Floor " .. i
    prompt.MaxActivationDistance = 6
    prompt.HoldDuration = 0
    prompt.Parent = button

    -- Floor indicator (shows current elevator floor)
    local indicatorPart = Instance.new("Part")
    indicatorPart.Name = "FloorIndicator_Floor" .. i
    indicatorPart.Size = Vector3.new(2, 1, 0.2)
    indicatorPart.Position = Vector3.new(6, floorY + 4.5, 0)
    indicatorPart.Anchored = true
    indicatorPart.Color = Color3.fromRGB(20, 20, 20)
    indicatorPart.Material = Enum.Material.SmoothPlastic
    indicatorPart.Parent = workspace

    local indicatorGui = Instance.new("SurfaceGui")
    indicatorGui.Name = "IndicatorGui"
    indicatorGui.Face = Enum.NormalId.Front
    indicatorGui.Parent = indicatorPart

    local indicatorLabel = Instance.new("TextLabel")
    indicatorLabel.Size = UDim2.fromScale(1, 1)
    indicatorLabel.BackgroundTransparency = 1
    indicatorLabel.TextColor3 = Color3.fromRGB(0, 255, 100)
    indicatorLabel.TextScaled = true
    indicatorLabel.Font = Enum.Font.Code
    indicatorLabel.Text = "1"
    indicatorLabel.Parent = indicatorGui

    -- Optional doors
    local doorLeft = Instance.new("Part")
    doorLeft.Name = "DoorLeft_Floor" .. i
    doorLeft.Size = Vector3.new(2, 8, 0.5)
    doorLeft.Position = Vector3.new(-1, floorY + 4, -4.25)
    doorLeft.Anchored = true
    doorLeft.Material = Enum.Material.Metal
    doorLeft.Color = Color3.fromRGB(120, 120, 120)
    doorLeft.Parent = workspace

    local doorRight = Instance.new("Part")
    doorRight.Name = "DoorRight_Floor" .. i
    doorRight.Size = Vector3.new(2, 8, 0.5)
    doorRight.Position = Vector3.new(1, floorY + 4, -4.25)
    doorRight.Anchored = true
    doorRight.Material = Enum.Material.Metal
    doorRight.Color = Color3.fromRGB(120, 120, 120)
    doorRight.Parent = workspace

    table.insert(floors, {
        name = tostring(i),
        position = Vector3.new(0, floorY, 0),
        callButton = button,
        indicator = indicatorGui,
        doorLeft = doorLeft,
        doorRight = doorRight,
    })
end

-- Create the elevator
local elevator = ElevatorService.create({
    floors = floors,
    speed = 10,
    doorOpenTime = 3,
    doorMoveTime = 1,
    startFloor = 1,
    platformSize = Vector3.new(8, 1, 8),
    platformColor = Color3.fromRGB(150, 150, 150),
    acceleration = 0.5,
})

-- Wire up call buttons
for i, floorData in floors do
    if floorData.callButton then
        local prompt = floorData.callButton:FindFirstChild("ProximityPrompt") :: ProximityPrompt?
        if prompt then
            prompt.Triggered:Connect(function(_player: Player)
                -- Visual feedback: button press
                local btn = floorData.callButton :: BasePart
                local originalColor = btn.Color
                btn.Color = Color3.fromRGB(100, 255, 100) -- flash green

                TweenService:Create(
                    btn,
                    TweenInfo.new(0.5, Enum.EasingStyle.Quad),
                    { Color = originalColor }
                ):Play()

                -- Call elevator
                ElevatorService.callToFloor(elevator, i)
            end)
        end
    end
end

-- Update floor indicators periodically
task.spawn(function()
    while true do
        for _, floorData in floors do
            if floorData.indicator then
                local gui = floorData.indicator :: SurfaceGui
                local label = gui:FindFirstChild("TextLabel") :: TextLabel?
                if not label then
                    label = gui:FindFirstChildWhichIsA("TextLabel")
                end
                if label then
                    local currentFloorData = floors[elevator.currentFloor]
                    label.Text = if currentFloorData then currentFloorData.name else "?"

                    -- Direction arrow
                    if elevator.isMoving and elevator.targetFloor then
                        if elevator.targetFloor > elevator.currentFloor then
                            label.Text ..= " ▲"
                        else
                            label.Text ..= " ▼"
                        end
                    end
                end
            end
        end
        task.wait(0.2)
    end
end)
```

---

## 4. Interior Panel Buttons (for inside the elevator)

```luau
--!strict
-- ServerScriptService/ElevatorInteriorPanel.lua
-- Creates floor selection buttons inside the elevator.

local TweenService = game:GetService("TweenService")

local ElevatorInteriorPanel = {}

function ElevatorInteriorPanel.create(
    elevator: any, -- Elevator type from ElevatorService
    floors: { { name: string, position: Vector3 } }
)
    local platform = elevator.platform :: BasePart
    local panelSize = Vector3.new(0.2, 2 + #floors * 0.8, 1.5)

    -- Panel background
    local panel = Instance.new("Part")
    panel.Name = "InteriorPanel"
    panel.Size = panelSize
    panel.Anchored = true
    panel.Material = Enum.Material.SmoothPlastic
    panel.Color = Color3.fromRGB(40, 40, 40)
    panel.CFrame = platform.CFrame * CFrame.new(
        platform.Size.X / 2 - 0.1,
        platform.Size.Y / 2 + panelSize.Y / 2 + 0.5,
        0
    )
    panel.Parent = elevator.folder

    -- Weld to platform
    local panelWeld = Instance.new("WeldConstraint")
    panelWeld.Part0 = platform
    panelWeld.Part1 = panel
    panelWeld.Parent = panel

    -- Create a button for each floor
    for i, floor in floors do
        local buttonSize = Vector3.new(0.25, 0.6, 0.6)
        local yOffset = (i - (#floors + 1) / 2) * 0.8

        local button = Instance.new("Part")
        button.Name = "FloorButton_" .. i
        button.Shape = Enum.PartType.Cylinder
        button.Size = Vector3.new(0.3, 0.5, 0.5)
        button.Material = Enum.Material.SmoothPlastic
        button.Color = Color3.fromRGB(200, 200, 200)
        button.Anchored = true
        button.CFrame = panel.CFrame * CFrame.new(-0.15, yOffset, 0)
            * CFrame.Angles(0, 0, math.rad(90))
        button.Parent = elevator.folder

        local buttonWeld = Instance.new("WeldConstraint")
        buttonWeld.Part0 = panel
        buttonWeld.Part1 = button
        buttonWeld.Parent = button

        -- Floor label
        local labelGui = Instance.new("SurfaceGui")
        labelGui.Face = Enum.NormalId.Left
        labelGui.Parent = button

        local label = Instance.new("TextLabel")
        label.Size = UDim2.fromScale(1, 1)
        label.BackgroundTransparency = 1
        label.TextColor3 = Color3.fromRGB(0, 0, 0)
        label.TextScaled = true
        label.Font = Enum.Font.GothamBold
        label.Text = floor.name
        label.Parent = labelGui

        -- ProximityPrompt
        local prompt = Instance.new("ProximityPrompt")
        prompt.ActionText = "Floor " .. floor.name
        prompt.ObjectText = ""
        prompt.MaxActivationDistance = 5
        prompt.HoldDuration = 0
        prompt.UIOffset = Vector2.new(0, -30 + i * 15)
        prompt.Parent = button

        local ElevatorService = require(
            game:GetService("ServerScriptService"):WaitForChild("ElevatorService")
        )

        prompt.Triggered:Connect(function(_player: Player)
            -- Button light feedback
            local origColor = button.Color
            button.Color = Color3.fromRGB(100, 255, 100)
            button.Material = Enum.Material.Neon

            TweenService:Create(
                button,
                TweenInfo.new(1, Enum.EasingStyle.Quad),
                { Color = origColor }
            ):Play()

            task.delay(1, function()
                button.Material = Enum.Material.SmoothPlastic
            end)

            -- Send elevator to floor
            ElevatorService.goToFloor(elevator, i)
        end)
    end
end

return ElevatorInteriorPanel
```

---

## Guidelines

- **TweenService** with `EasingStyle.Sine` + `EasingDirection.InOut` creates smooth elevator acceleration and deceleration.
- **WeldConstraint** passengers to the platform so they move with it. Raycast downward from the character to detect if they're standing on the platform.
- **Floor queue**: if the elevator is already moving, queue the request and process it when the current move completes.
- **Doors**: tween door parts sideways (or use HingeConstraint for swinging doors). Store `ClosedPosition` as an attribute for reliable closing.
- **Floor indicators** at each floor should update periodically to show the elevator's current floor and direction.
- **ProximityPrompt** is used for both exterior call buttons and interior floor buttons.
- The platform must be **Anchored = true** for TweenService to work (tweening an unanchored part is unreliable).
- **Interior panel buttons**: position them relative to the platform and weld them so they move together.
- Always provide visual feedback when buttons are pressed (color flash, neon material briefly).

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

When generating elevator code, adapt to these user-specified parameters:

- `$FLOOR_COUNT` - Number of floors (default: 3)
- `$FLOOR_HEIGHT` - Vertical distance between floors in studs (default: 15)
- `$SPEED` - Elevator speed in studs/s (default: 10)
- `$DOOR_OPEN_TIME` - Seconds doors remain open (default: 3)
- `$DOOR_MOVE_TIME` - Seconds for door animation (default: 1)
- `$PLATFORM_SIZE` - Platform dimensions as "X,Y,Z" (default: "8,1,8")
- `$HAS_DOORS` - Whether to include animated doors (default: true)
- `$HAS_INTERIOR_PANEL` - Whether to include interior floor buttons (default: true)
- `$HAS_FLOOR_INDICATORS` - Whether to include floor indicators at each floor (default: true)
- `$CALL_BUTTON_TYPE` - "proximity" | "click" (default: "proximity")
- `$SOUND_ENABLED` - Whether to include elevator sounds (default: false)
- `$FLOOR_NAMES` - Custom floor names as comma-separated list (default: "1,2,3")
