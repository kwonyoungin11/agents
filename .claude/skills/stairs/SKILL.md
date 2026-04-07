---
name: stairs
description: |
  Roblox 계단/이동 시스템 스킬. 직선 계단, 나선형 계단, 사다리, 엘리베이터(트윈),
  에스컬레이터, 경사로를 생성합니다.
  키워드: 계단, 나선계단, 사다리, 엘리베이터, 에스컬레이터, 경사로, 램프, 층계,
  올라가기, 내려가기, 층간이동, 수직이동, 리프트,
  stairs, spiral, ladder, elevator, escalator, ramp, lift, staircase, steps
allowed-tools:
  - Bash
  - Edit
  - Write
  - Read
  - Grep
  - Glob
  - WebFetch
  - WebSearch
  - mcp__roblox-mcp__execute_luau_in_studio
effort: high
---

# Stairs Skill

Roblox에서 계단, 사다리, 엘리베이터, 에스컬레이터, 경사로를 생성하는 스킬입니다.

## Straight Stairs

### Basic Straight Staircase
```lua
local function createStraightStairs(config: {
    position: Vector3,
    rotation: number?,         -- Y-axis rotation in degrees
    stepCount: number?,
    stepWidth: number?,
    stepHeight: number?,
    stepDepth: number?,
    material: Enum.Material?,
    color: Color3?,
    withRailing: boolean?,
    railingColor: Color3?,
}): Model
    local steps = config.stepCount or 12
    local stepW = config.stepWidth or 6
    local stepH = config.stepHeight or 0.8
    local stepD = config.stepDepth or 1.2
    local mat = config.material or Enum.Material.Concrete
    local col = config.color or Color3.fromRGB(180, 180, 180)
    local rot = math.rad(config.rotation or 0)

    local model = Instance.new("Model")
    model.Name = "StraightStairs"
    local baseCF = CFrame.new(config.position) * CFrame.Angles(0, rot, 0)

    for i = 1, steps do
        local step = Instance.new("Part")
        step.Name = "Step_" .. i
        step.Size = Vector3.new(stepW, stepH, stepD)
        step.CFrame = baseCF * CFrame.new(0, stepH * (i - 0.5), -stepD * (i - 1))
        step.Material = mat
        step.Color = col
        step.Anchored = true
        step.Parent = model
    end

    -- Railings
    if config.withRailing ~= false then
        local railCol = config.railingColor or Color3.fromRGB(80, 80, 85)
        local railHeight = 3.5
        local railThickness = 0.2

        for _, side in ipairs({-1, 1}) do
            -- Railing posts
            for i = 1, steps, 3 do
                local post = Instance.new("Part")
                post.Name = "RailPost"
                post.Shape = Enum.PartType.Cylinder
                post.Size = Vector3.new(railHeight, railThickness, railThickness)
                post.CFrame = baseCF
                    * CFrame.new(side * stepW / 2, stepH * i + railHeight / 2, -stepD * (i - 1))
                    * CFrame.Angles(0, 0, math.rad(90))
                post.Material = Enum.Material.Metal
                post.Color = railCol
                post.Anchored = true
                post.Parent = model
            end

            -- Top rail (angled bar)
            local totalRise = stepH * steps
            local totalRun = stepD * (steps - 1)
            local railLen = math.sqrt(totalRise * totalRise + totalRun * totalRun)
            local railAngle = math.atan2(totalRise, totalRun)

            local rail = Instance.new("Part")
            rail.Name = "Rail"
            rail.Size = Vector3.new(railThickness, railThickness, railLen)
            rail.CFrame = baseCF
                * CFrame.new(
                    side * stepW / 2,
                    stepH * steps / 2 + railHeight,
                    -totalRun / 2
                )
                * CFrame.Angles(-railAngle, 0, 0)
            rail.Material = Enum.Material.Metal
            rail.Color = railCol
            rail.Anchored = true
            rail.Parent = model
        end
    end

    model.Parent = workspace
    return model
end
```

## Spiral Stairs

```lua
local function createSpiralStairs(config: {
    center: Vector3,
    totalHeight: number?,
    radius: number?,
    stepCount: number?,
    rotations: number?,       -- number of full 360 turns
    stepWidth: number?,
    stepHeight: number?,
    material: Enum.Material?,
    color: Color3?,
    direction: string?,       -- "clockwise" | "counterclockwise"
    withPole: boolean?,
    withRailing: boolean?,
}): Model
    local totalH = config.totalHeight or 20
    local radius = config.radius or 6
    local stepCount = config.stepCount or 24
    local rotations = config.rotations or 1
    local stepW = config.stepWidth or 4
    local mat = config.material or Enum.Material.Concrete
    local col = config.color or Color3.fromRGB(180, 180, 180)
    local dir = config.direction == "counterclockwise" and -1 or 1

    local stepH = totalH / stepCount
    local anglePerStep = (math.pi * 2 * rotations) / stepCount * dir

    local model = Instance.new("Model")
    model.Name = "SpiralStairs"

    -- Center pole
    if config.withPole ~= false then
        local pole = Instance.new("Part")
        pole.Name = "CenterPole"
        pole.Shape = Enum.PartType.Cylinder
        pole.Size = Vector3.new(totalH + 2, 0.8, 0.8)
        pole.CFrame = CFrame.new(config.center + Vector3.new(0, totalH / 2, 0))
            * CFrame.Angles(0, 0, math.rad(90))
        pole.Material = Enum.Material.Metal
        pole.Color = Color3.fromRGB(70, 70, 75)
        pole.Anchored = true
        pole.Parent = model
    end

    for i = 1, stepCount do
        local angle = anglePerStep * (i - 1)
        local y = stepH * i

        -- Each step is a wedge-like shape (approximated with a Part)
        local step = Instance.new("WedgePart")
        step.Name = "Step_" .. i
        step.Size = Vector3.new(stepW, stepH, 2)

        -- Position: offset from center along the radius
        local midRadius = radius / 2 + 0.4  -- slight inward offset
        local x = math.cos(angle) * midRadius
        local z = math.sin(angle) * midRadius

        step.CFrame = CFrame.new(config.center + Vector3.new(x, y - stepH / 2, z))
            * CFrame.Angles(0, -angle + math.pi / 2, 0)
        step.Material = mat
        step.Color = col
        step.Anchored = true
        step.Parent = model

        -- Railing post at outer edge
        if config.withRailing ~= false and i % 2 == 0 then
            local outerX = math.cos(angle) * (radius - 0.2)
            local outerZ = math.sin(angle) * (radius - 0.2)

            local post = Instance.new("Part")
            post.Name = "RailPost_" .. i
            post.Shape = Enum.PartType.Cylinder
            post.Size = Vector3.new(3, 0.15, 0.15)
            post.CFrame = CFrame.new(config.center + Vector3.new(outerX, y + 1.5, outerZ))
                * CFrame.Angles(0, 0, math.rad(90))
            post.Material = Enum.Material.Metal
            post.Color = Color3.fromRGB(70, 70, 75)
            post.Anchored = true
            post.Parent = model
        end
    end

    model.Parent = workspace
    return model
end
```

## Ladder

```lua
local function createLadder(config: {
    position: Vector3,
    height: number?,
    width: number?,
    rotation: number?,
    material: Enum.Material?,
    color: Color3?,
    rungSpacing: number?,
    climbable: boolean?,
}): Model
    local h = config.height or 15
    local w = config.width or 2
    local rungSpacing = config.rungSpacing or 1.2
    local mat = config.material or Enum.Material.Metal
    local col = config.color or Color3.fromRGB(80, 80, 85)
    local rot = math.rad(config.rotation or 0)

    local model = Instance.new("Model")
    model.Name = "Ladder"
    local baseCF = CFrame.new(config.position) * CFrame.Angles(0, rot, 0)

    local railThick = 0.2

    -- Side rails
    for _, side in ipairs({-1, 1}) do
        local rail = Instance.new("Part")
        rail.Name = "Rail"
        rail.Size = Vector3.new(railThick, h, railThick)
        rail.CFrame = baseCF * CFrame.new(side * w / 2, h / 2, 0)
        rail.Material = mat
        rail.Color = col
        rail.Anchored = true
        rail.Parent = model
    end

    -- Rungs
    local rungCount = math.floor(h / rungSpacing)
    for i = 1, rungCount do
        local rung = Instance.new("Part")
        rung.Name = "Rung_" .. i
        rung.Shape = Enum.PartType.Cylinder
        rung.Size = Vector3.new(0.15, w - railThick, railThick)
        rung.CFrame = baseCF * CFrame.new(0, i * rungSpacing, 0)
            * CFrame.Angles(0, 0, math.rad(90))
        rung.Material = mat
        rung.Color = col
        rung.Anchored = true
        rung.Parent = model
    end

    -- Climbable: add invisible TrussPart overlay for built-in climbing
    if config.climbable ~= false then
        local truss = Instance.new("TrussPart")
        truss.Name = "ClimbZone"
        truss.Size = Vector3.new(2, h, 2)
        truss.CFrame = baseCF * CFrame.new(0, h / 2, 0)
        truss.Transparency = 1
        truss.CanCollide = false
        truss.Anchored = true
        truss.Parent = model

        -- The TrussPart enables Humanoid climbing automatically
    end

    model.Parent = workspace
    return model
end
```

## Elevator (Tween-Based)

```lua
local TweenService = game:GetService("TweenService")

local function createElevator(config: {
    position: Vector3,
    floors: { { name: string, height: number } },  -- floor definitions
    platformSize: Vector3?,
    speed: number?,        -- studs per second
    material: Enum.Material?,
    color: Color3?,
    withDoors: boolean?,
    withShaft: boolean?,
    callButtons: boolean?,
}): Model
    local platSize = config.platformSize or Vector3.new(8, 0.5, 8)
    local speed = config.speed or 10
    local mat = config.material or Enum.Material.Metal
    local col = config.color or Color3.fromRGB(160, 160, 165)

    local model = Instance.new("Model")
    model.Name = "Elevator"

    -- Platform
    local platform = Instance.new("Part")
    platform.Name = "Platform"
    platform.Size = platSize
    platform.CFrame = CFrame.new(config.position + Vector3.new(0, platSize.Y / 2, 0))
    platform.Material = mat
    platform.Color = col
    platform.Anchored = true
    platform.Parent = model

    -- Walls (3 sides, front open)
    local wallHeight = 10
    local wallThick = 0.3

    local walls = {
        { name = "BackWall", size = Vector3.new(platSize.X, wallHeight, wallThick),
          offset = CFrame.new(0, wallHeight / 2 + platSize.Y, -platSize.Z / 2 + wallThick / 2) },
        { name = "LeftWall", size = Vector3.new(wallThick, wallHeight, platSize.Z),
          offset = CFrame.new(-platSize.X / 2 + wallThick / 2, wallHeight / 2 + platSize.Y, 0) },
        { name = "RightWall", size = Vector3.new(wallThick, wallHeight, platSize.Z),
          offset = CFrame.new(platSize.X / 2 - wallThick / 2, wallHeight / 2 + platSize.Y, 0) },
    }

    local wallParts = {}
    for _, w in ipairs(walls) do
        local wall = Instance.new("Part")
        wall.Name = w.name
        wall.Size = w.size
        wall.CFrame = CFrame.new(config.position) * w.offset
        wall.Material = Enum.Material.SmoothPlastic
        wall.Color = Color3.fromRGB(200, 200, 205)
        wall.Anchored = true
        wall.Parent = model
        table.insert(wallParts, { part = wall, offset = w.offset })
    end

    -- Ceiling
    local ceiling = Instance.new("Part")
    ceiling.Name = "Ceiling"
    ceiling.Size = Vector3.new(platSize.X, wallThick, platSize.Z)
    local ceilingOffset = CFrame.new(0, wallHeight + platSize.Y + wallThick / 2, 0)
    ceiling.CFrame = CFrame.new(config.position) * ceilingOffset
    ceiling.Material = Enum.Material.SmoothPlastic
    ceiling.Color = Color3.fromRGB(220, 220, 225)
    ceiling.Anchored = true
    ceiling.Parent = model

    -- Light inside elevator
    local light = Instance.new("SurfaceLight")
    light.Face = Enum.NormalId.Bottom
    light.Brightness = 2
    light.Range = 15
    light.Color = Color3.fromRGB(255, 250, 240)
    light.Parent = ceiling

    -- Floor state
    local currentFloor = 1
    local isMoving = false

    -- Move elevator function
    local function moveToFloor(floorIndex: number)
        if isMoving or floorIndex == currentFloor then return end
        if floorIndex < 1 or floorIndex > #config.floors then return end

        isMoving = true
        local targetHeight = config.floors[floorIndex].height
        local currentHeight = config.floors[currentFloor].height
        local distance = math.abs(targetHeight - currentHeight)
        local duration = distance / speed

        local yDelta = targetHeight - currentHeight

        -- Tween all parts simultaneously
        local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)

        local platformTarget = platform.CFrame + Vector3.new(0, yDelta, 0)
        TweenService:Create(platform, tweenInfo, { CFrame = platformTarget }):Play()

        for _, wp in ipairs(wallParts) do
            local target = wp.part.CFrame + Vector3.new(0, yDelta, 0)
            TweenService:Create(wp.part, tweenInfo, { CFrame = target }):Play()
        end

        local ceilingTarget = ceiling.CFrame + Vector3.new(0, yDelta, 0)
        local ceilingTween = TweenService:Create(ceiling, tweenInfo, { CFrame = ceilingTarget })
        ceilingTween:Play()

        ceilingTween.Completed:Wait()
        currentFloor = floorIndex
        isMoving = false
    end

    -- Interior buttons
    local buttonPanel = Instance.new("Part")
    buttonPanel.Name = "ButtonPanel"
    buttonPanel.Size = Vector3.new(1.5, #config.floors * 1.2 + 0.5, 0.1)
    local panelOffset = CFrame.new(
        platSize.X / 2 - 0.4,
        wallHeight / 2 + platSize.Y,
        -platSize.Z / 2 + 0.5
    )
    buttonPanel.CFrame = CFrame.new(config.position) * panelOffset
    buttonPanel.Material = Enum.Material.SmoothPlastic
    buttonPanel.Color = Color3.fromRGB(50, 50, 55)
    buttonPanel.Anchored = true
    buttonPanel.Parent = model
    table.insert(wallParts, { part = buttonPanel, offset = panelOffset })

    for i, floor in ipairs(config.floors) do
        local button = Instance.new("Part")
        button.Name = "Button_" .. floor.name
        button.Shape = Enum.PartType.Cylinder
        button.Size = Vector3.new(0.1, 0.8, 0.8)
        local btnOffset = CFrame.new(
            platSize.X / 2 - 0.3,
            wallHeight / 2 + platSize.Y + (i - (#config.floors + 1) / 2) * 1.2,
            -platSize.Z / 2 + 0.4
        ) * CFrame.Angles(0, math.rad(90), 0)
        button.CFrame = CFrame.new(config.position) * btnOffset
        button.Material = Enum.Material.Neon
        button.Color = Color3.fromRGB(100, 200, 100)
        button.Anchored = true
        button.Parent = model
        table.insert(wallParts, { part = button, offset = btnOffset })

        local detector = Instance.new("ClickDetector")
        detector.MaxActivationDistance = 8
        detector.Parent = button

        detector.MouseClick:Connect(function()
            button.Color = Color3.fromRGB(255, 200, 50)
            moveToFloor(i)
            button.Color = Color3.fromRGB(100, 200, 100)
        end)
    end

    -- External call buttons at each floor (optional)
    if config.callButtons then
        for i, floor in ipairs(config.floors) do
            local callBtn = Instance.new("Part")
            callBtn.Name = "CallButton_" .. floor.name
            callBtn.Size = Vector3.new(0.8, 0.8, 0.2)
            callBtn.CFrame = CFrame.new(
                config.position.X + platSize.X / 2 + 1,
                floor.height + 4,
                config.position.Z + platSize.Z / 2 + 0.5
            )
            callBtn.Material = Enum.Material.Neon
            callBtn.Color = Color3.fromRGB(100, 150, 255)
            callBtn.Anchored = true
            callBtn.Parent = model

            local callDetector = Instance.new("ClickDetector")
            callDetector.MaxActivationDistance = 10
            callDetector.Parent = callBtn

            callDetector.MouseClick:Connect(function()
                callBtn.Color = Color3.fromRGB(255, 200, 50)
                moveToFloor(i)
                callBtn.Color = Color3.fromRGB(100, 150, 255)
            end)
        end
    end

    model.PrimaryPart = platform
    model.Parent = workspace
    return model
end

-- Usage:
-- createElevator({
--     position = Vector3.new(0, 0, 0),
--     floors = {
--         { name = "Ground", height = 0 },
--         { name = "Floor1", height = 15 },
--         { name = "Floor2", height = 30 },
--         { name = "Roof", height = 45 },
--     },
--     speed = 12,
--     callButtons = true,
-- })
```

## Escalator

```lua
local function createEscalator(config: {
    position: Vector3,
    rotation: number?,
    height: number?,
    width: number?,
    length: number?,
    speed: number?,          -- studs per second for visual steps
    material: Enum.Material?,
    color: Color3?,
    direction: string?,      -- "up" | "down"
}): Model
    local h = config.height or 12
    local w = config.width or 4
    local escalatorLen = config.length or (h * 2)
    local speed = config.speed or 3
    local mat = config.material or Enum.Material.Metal
    local col = config.color or Color3.fromRGB(150, 150, 155)
    local rot = math.rad(config.rotation or 0)
    local goingUp = config.direction ~= "down"

    local model = Instance.new("Model")
    model.Name = "Escalator"
    local baseCF = CFrame.new(config.position) * CFrame.Angles(0, rot, 0)

    local angle = math.atan2(h, escalatorLen)

    -- Side rails
    local railLen = math.sqrt(h * h + escalatorLen * escalatorLen)
    for _, side in ipairs({-1, 1}) do
        local rail = Instance.new("Part")
        rail.Name = "SideRail"
        rail.Size = Vector3.new(0.3, 2, railLen)
        rail.CFrame = baseCF
            * CFrame.new(side * (w / 2 + 0.15), h / 2 + 1, -escalatorLen / 2)
            * CFrame.Angles(-angle, 0, 0)
        rail.Material = Enum.Material.Metal
        rail.Color = Color3.fromRGB(70, 70, 75)
        rail.Anchored = true
        rail.Parent = model
    end

    -- Steps (static visual representation)
    local stepDepth = 1
    local stepCount = math.floor(railLen / stepDepth)
    local stepH = h / stepCount
    local stepRunDepth = escalatorLen / stepCount

    for i = 1, stepCount do
        local step = Instance.new("Part")
        step.Name = "Step_" .. i
        step.Size = Vector3.new(w, 0.3, stepDepth * 0.9)
        local progress = (i - 0.5) / stepCount
        step.CFrame = baseCF * CFrame.new(
            0,
            progress * h + 0.15,
            -progress * escalatorLen
        )
        step.Material = mat
        step.Color = col
        step.Anchored = true
        step.Parent = model
    end

    -- Base surface (bottom flat area)
    local bottomPad = Instance.new("Part")
    bottomPad.Name = "BottomPad"
    bottomPad.Size = Vector3.new(w, 0.3, 3)
    bottomPad.CFrame = baseCF * CFrame.new(0, 0.15, 1.5)
    bottomPad.Material = mat
    bottomPad.Color = col
    bottomPad.Anchored = true
    bottomPad.Parent = model

    -- Top surface (top flat area)
    local topPad = Instance.new("Part")
    topPad.Name = "TopPad"
    topPad.Size = Vector3.new(w, 0.3, 3)
    topPad.CFrame = baseCF * CFrame.new(0, h + 0.15, -escalatorLen - 1.5)
    topPad.Material = mat
    topPad.Color = col
    topPad.Anchored = true
    topPad.Parent = model

    -- Movement conveyor using VectorForce or BodyVelocity on touch
    local conveyorPart = Instance.new("Part")
    conveyorPart.Name = "Conveyor"
    conveyorPart.Size = Vector3.new(w, 1, railLen)
    conveyorPart.CFrame = baseCF
        * CFrame.new(0, h / 2, -escalatorLen / 2)
        * CFrame.Angles(-angle, 0, 0)
    conveyorPart.Transparency = 1
    conveyorPart.CanCollide = false
    conveyorPart.Anchored = true
    conveyorPart.Parent = model

    -- Use touched event to move players
    local moveDir = baseCF:VectorToWorldSpace(
        Vector3.new(0, math.sin(angle), -math.cos(angle)) * speed * (goingUp and 1 or -1)
    )

    conveyorPart.Touched:Connect(function(hit)
        local humanoid = hit.Parent:FindFirstChildOfClass("Humanoid")
        if humanoid then
            local root = hit.Parent:FindFirstChild("HumanoidRootPart")
            if root then
                -- Apply velocity
                root.AssemblyLinearVelocity = root.AssemblyLinearVelocity + moveDir * 0.1
            end
        end
    end)

    model.Parent = workspace
    return model
end
```

## Ramp

```lua
local function createRamp(config: {
    position: Vector3,
    rotation: number?,
    height: number?,
    length: number?,
    width: number?,
    material: Enum.Material?,
    color: Color3?,
    withRailing: boolean?,
    style: string?,         -- "smooth" | "wedge" | "segmented"
}): Model
    local h = config.height or 8
    local len = config.length or 20
    local w = config.width or 6
    local mat = config.material or Enum.Material.Concrete
    local col = config.color or Color3.fromRGB(170, 170, 170)
    local rot = math.rad(config.rotation or 0)
    local style = config.style or "wedge"

    local model = Instance.new("Model")
    model.Name = "Ramp"
    local baseCF = CFrame.new(config.position) * CFrame.Angles(0, rot, 0)

    if style == "wedge" then
        local ramp = Instance.new("WedgePart")
        ramp.Name = "RampSurface"
        ramp.Size = Vector3.new(w, h, len)
        ramp.CFrame = baseCF * CFrame.new(0, h / 2, -len / 2)
        ramp.Material = mat
        ramp.Color = col
        ramp.Anchored = true
        ramp.Parent = model

    elseif style == "smooth" then
        -- Smooth ramp using angled Part
        local rampAngle = math.atan2(h, len)
        local rampLen = math.sqrt(h * h + len * len)

        local ramp = Instance.new("Part")
        ramp.Name = "RampSurface"
        ramp.Size = Vector3.new(w, 0.5, rampLen)
        ramp.CFrame = baseCF
            * CFrame.new(0, h / 2, -len / 2)
            * CFrame.Angles(-rampAngle, 0, 0)
        ramp.Material = mat
        ramp.Color = col
        ramp.Anchored = true
        ramp.Parent = model

        -- Fill underneath
        local fill = Instance.new("WedgePart")
        fill.Name = "RampFill"
        fill.Size = Vector3.new(w, h - 0.5, len)
        fill.CFrame = baseCF * CFrame.new(0, (h - 0.5) / 2, -len / 2)
        fill.Material = mat
        fill.Color = col
        fill.Transparency = 0
        fill.Anchored = true
        fill.Parent = model

    elseif style == "segmented" then
        -- Segmented ramp (small steps for smoother walking)
        local segments = math.ceil(len / 1)
        local segH = h / segments
        local segD = len / segments

        for i = 1, segments do
            local seg = Instance.new("Part")
            seg.Name = "Segment_" .. i
            seg.Size = Vector3.new(w, segH * i, segD)
            seg.CFrame = baseCF * CFrame.new(0, segH * i / 2, -segD * (i - 0.5))
            seg.Material = mat
            seg.Color = col
            seg.Anchored = true
            seg.Parent = model
        end
    end

    -- Railings
    if config.withRailing then
        local railH = 3.5
        local railAngle = math.atan2(h, len)
        local railLen = math.sqrt(h * h + len * len)

        for _, side in ipairs({-1, 1}) do
            -- Top bar
            local rail = Instance.new("Part")
            rail.Name = "Railing"
            rail.Size = Vector3.new(0.2, 0.2, railLen)
            rail.CFrame = baseCF
                * CFrame.new(side * w / 2, h / 2 + railH, -len / 2)
                * CFrame.Angles(-railAngle, 0, 0)
            rail.Material = Enum.Material.Metal
            rail.Color = Color3.fromRGB(80, 80, 85)
            rail.Anchored = true
            rail.Parent = model

            -- Posts
            local postCount = math.ceil(len / 3)
            for i = 0, postCount do
                local t = i / postCount
                local post = Instance.new("Part")
                post.Name = "RailPost"
                post.Shape = Enum.PartType.Cylinder
                post.Size = Vector3.new(railH, 0.15, 0.15)
                post.CFrame = baseCF
                    * CFrame.new(side * w / 2, t * h + railH / 2, -t * len)
                    * CFrame.Angles(0, 0, math.rad(90))
                post.Material = Enum.Material.Metal
                post.Color = Color3.fromRGB(80, 80, 85)
                post.Anchored = true
                post.Parent = model
            end
        end
    end

    model.Parent = workspace
    return model
end
```

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

- `stairType`: "straight" | "spiral" | "ladder" | "elevator" | "escalator" | "ramp" -- 계단 타입
- `position`: {x: number, y: number, z: number} -- 위치
- `rotation`: number -- Y축 회전 (도)
- `height`: number -- 높이 (studs)
- `width`: number -- 너비 (studs)
- `stepCount`: number -- 계단 수
- `material`: string -- 재질 (Enum.Material 이름)
- `color`: {r: number, g: number, b: number} -- 색상
- `withRailing`: boolean -- 난간 포함
- `radius`: number -- 나선계단 반경
- `rotations`: number -- 나선계단 회전 수
- `direction`: "up" | "down" | "clockwise" | "counterclockwise" -- 방향
- `floors`: [{ name: string, height: number }] -- 엘리베이터 층 정의
- `speed`: number -- 엘리베이터/에스컬레이터 속도
- `style`: "smooth" | "wedge" | "segmented" -- 경사로 스타일
- `climbable`: boolean -- 사다리 등반 가능 여부
