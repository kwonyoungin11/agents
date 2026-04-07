---
name: props
description: |
  Roblox 소품/프롭 시스템 스킬. 가구(테이블/의자/침대/선반), 횃불과 불 VFX, 상자/통,
  ClickDetector 인터랙티브 소품, 가로등을 생성합니다.
  키워드: 가구, 테이블, 의자, 침대, 선반, 횃불, 불, 상자, 통, 소품, 프롭, 인터랙션,
  클릭, 가로등, 랜턴, 책상, 서랍, 소파, 벤치, 화로, 모닥불, 촛불,
  furniture, table, chair, bed, shelf, torch, fire, crate, barrel, prop, lamp, lantern
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

# Props Skill

Roblox에서 가구, 소품, 인터랙티브 오브젝트를 생성하는 스킬입니다.

## Furniture

### Table
```lua
local function createTable(config: {
    position: Vector3,
    size: Vector3?,       -- {width, height, depth}
    material: Enum.Material?,
    color: Color3?,
    legStyle: string?,    -- "square" | "round"
}): Model
    local w = (config.size and config.size.X) or 6
    local h = (config.size and config.size.Y) or 3
    local d = (config.size and config.size.Z) or 4
    local mat = config.material or Enum.Material.Wood
    local col = config.color or Color3.fromRGB(139, 90, 50)
    local legStyle = config.legStyle or "square"

    local model = Instance.new("Model")
    model.Name = "Table"

    -- Tabletop
    local top = Instance.new("Part")
    top.Name = "Tabletop"
    top.Size = Vector3.new(w, 0.3, d)
    top.CFrame = CFrame.new(config.position + Vector3.new(0, h, 0))
    top.Material = mat
    top.Color = col
    top.Anchored = true
    top.Parent = model

    -- Legs
    local legThickness = 0.4
    local legHeight = h - 0.15
    local offsets = {
        Vector3.new(-w / 2 + legThickness / 2, 0, -d / 2 + legThickness / 2),
        Vector3.new(w / 2 - legThickness / 2, 0, -d / 2 + legThickness / 2),
        Vector3.new(-w / 2 + legThickness / 2, 0, d / 2 - legThickness / 2),
        Vector3.new(w / 2 - legThickness / 2, 0, d / 2 - legThickness / 2),
    }

    for i, offset in ipairs(offsets) do
        local leg = Instance.new("Part")
        leg.Name = "Leg_" .. i

        if legStyle == "round" then
            leg.Shape = Enum.PartType.Cylinder
            leg.Size = Vector3.new(legHeight, legThickness, legThickness)
            leg.CFrame = CFrame.new(config.position + offset + Vector3.new(0, legHeight / 2, 0))
                * CFrame.Angles(0, 0, math.rad(90))
        else
            leg.Size = Vector3.new(legThickness, legHeight, legThickness)
            leg.CFrame = CFrame.new(config.position + offset + Vector3.new(0, legHeight / 2, 0))
        end

        leg.Material = mat
        leg.Color = col
        leg.Anchored = true
        leg.Parent = model
    end

    model.PrimaryPart = top
    model.Parent = workspace
    return model
end
```

### Chair
```lua
local function createChair(config: {
    position: Vector3,
    rotation: number?,     -- Y-axis rotation in degrees
    material: Enum.Material?,
    color: Color3?,
    withArmrests: boolean?,
}): Model
    local mat = config.material or Enum.Material.Wood
    local col = config.color or Color3.fromRGB(139, 90, 50)
    local rot = math.rad(config.rotation or 0)

    local model = Instance.new("Model")
    model.Name = "Chair"

    local baseCF = CFrame.new(config.position) * CFrame.Angles(0, rot, 0)

    -- Seat
    local seat = Instance.new("Seat")
    seat.Name = "Seat"
    seat.Size = Vector3.new(2, 0.3, 2)
    seat.CFrame = baseCF * CFrame.new(0, 2, 0)
    seat.Material = mat
    seat.Color = col
    seat.Anchored = true
    seat.Parent = model

    -- Back rest
    local backrest = Instance.new("Part")
    backrest.Name = "Backrest"
    backrest.Size = Vector3.new(2, 2.5, 0.3)
    backrest.CFrame = baseCF * CFrame.new(0, 3.25, -0.85)
    backrest.Material = mat
    backrest.Color = col
    backrest.Anchored = true
    backrest.Parent = model

    -- Legs
    local legThickness = 0.3
    local legH = 1.85
    local legOffsets = {
        CFrame.new(-0.7, legH / 2, -0.7),
        CFrame.new(0.7, legH / 2, -0.7),
        CFrame.new(-0.7, legH / 2, 0.7),
        CFrame.new(0.7, legH / 2, 0.7),
    }

    for i, offset in ipairs(legOffsets) do
        local leg = Instance.new("Part")
        leg.Name = "Leg_" .. i
        leg.Size = Vector3.new(legThickness, legH, legThickness)
        leg.CFrame = baseCF * offset
        leg.Material = mat
        leg.Color = col
        leg.Anchored = true
        leg.Parent = model
    end

    -- Armrests (optional)
    if config.withArmrests then
        for _, side in ipairs({-1, 1}) do
            local armrest = Instance.new("Part")
            armrest.Name = "Armrest"
            armrest.Size = Vector3.new(0.3, 0.3, 2)
            armrest.CFrame = baseCF * CFrame.new(side * 1.15, 2.8, 0)
            armrest.Material = mat
            armrest.Color = col
            armrest.Anchored = true
            armrest.Parent = model

            -- Armrest support
            local support = Instance.new("Part")
            support.Name = "ArmrestSupport"
            support.Size = Vector3.new(0.2, 0.8, 0.2)
            support.CFrame = baseCF * CFrame.new(side * 1.15, 2.4, 0.7)
            support.Material = mat
            support.Color = col
            support.Anchored = true
            support.Parent = model
        end
    end

    model.PrimaryPart = seat
    model.Parent = workspace
    return model
end
```

### Bed
```lua
local function createBed(config: {
    position: Vector3,
    rotation: number?,
    size: string?,        -- "single" | "double" | "king"
    frameColor: Color3?,
    sheetColor: Color3?,
    pillows: boolean?,
}): Model
    local rot = math.rad(config.rotation or 0)
    local sizeType = config.size or "single"

    local bedWidth = ({ single = 4, double = 6, king = 8 })[sizeType] or 4
    local bedLength = 8
    local frameH = 1.5

    local frameCol = config.frameColor or Color3.fromRGB(100, 65, 35)
    local sheetCol = config.sheetColor or Color3.fromRGB(240, 235, 220)

    local model = Instance.new("Model")
    model.Name = "Bed"
    local baseCF = CFrame.new(config.position) * CFrame.Angles(0, rot, 0)

    -- Frame base
    local frame = Instance.new("Part")
    frame.Name = "Frame"
    frame.Size = Vector3.new(bedWidth + 0.4, frameH, bedLength + 0.4)
    frame.CFrame = baseCF * CFrame.new(0, frameH / 2, 0)
    frame.Material = Enum.Material.Wood
    frame.Color = frameCol
    frame.Anchored = true
    frame.Parent = model

    -- Mattress
    local mattress = Instance.new("Part")
    mattress.Name = "Mattress"
    mattress.Size = Vector3.new(bedWidth, 0.6, bedLength)
    mattress.CFrame = baseCF * CFrame.new(0, frameH + 0.3, 0)
    mattress.Material = Enum.Material.Fabric
    mattress.Color = sheetCol
    mattress.Anchored = true
    mattress.Parent = model

    -- Headboard
    local headboard = Instance.new("Part")
    headboard.Name = "Headboard"
    headboard.Size = Vector3.new(bedWidth + 0.4, 3, 0.4)
    headboard.CFrame = baseCF * CFrame.new(0, frameH + 1.5, -bedLength / 2 - 0.2)
    headboard.Material = Enum.Material.Wood
    headboard.Color = frameCol
    headboard.Anchored = true
    headboard.Parent = model

    -- Pillows
    if config.pillows ~= false then
        local pillowCount = math.ceil(bedWidth / 3)
        for i = 1, pillowCount do
            local pillow = Instance.new("Part")
            pillow.Name = "Pillow_" .. i
            pillow.Size = Vector3.new(2, 0.5, 1.5)
            local xOff = (i - (pillowCount + 1) / 2) * 2.5
            pillow.CFrame = baseCF * CFrame.new(xOff, frameH + 0.85, -bedLength / 2 + 1.2)
            pillow.Material = Enum.Material.Fabric
            pillow.Color = Color3.fromRGB(255, 255, 250)
            pillow.Anchored = true
            pillow.Parent = model
        end
    end

    -- Blanket
    local blanket = Instance.new("Part")
    blanket.Name = "Blanket"
    blanket.Size = Vector3.new(bedWidth + 0.6, 0.2, bedLength * 0.6)
    blanket.CFrame = baseCF * CFrame.new(0, frameH + 0.7, bedLength * 0.15)
    blanket.Material = Enum.Material.Fabric
    blanket.Color = Color3.fromRGB(70, 90, 130)
    blanket.Anchored = true
    blanket.Parent = model

    model.PrimaryPart = frame
    model.Parent = workspace
    return model
end
```

### Shelf / Bookshelf
```lua
local function createShelf(config: {
    position: Vector3,
    rotation: number?,
    width: number?,
    height: number?,
    depth: number?,
    shelfCount: number?,
    material: Enum.Material?,
    color: Color3?,
    withBooks: boolean?,
}): Model
    local w = config.width or 6
    local h = config.height or 8
    local d = config.depth or 1.5
    local shelves = config.shelfCount or 4
    local mat = config.material or Enum.Material.Wood
    local col = config.color or Color3.fromRGB(120, 80, 45)
    local rot = math.rad(config.rotation or 0)

    local model = Instance.new("Model")
    model.Name = "Shelf"
    local baseCF = CFrame.new(config.position) * CFrame.Angles(0, rot, 0)

    local thickness = 0.2

    -- Back panel
    local back = Instance.new("Part")
    back.Name = "BackPanel"
    back.Size = Vector3.new(w, h, thickness)
    back.CFrame = baseCF * CFrame.new(0, h / 2, -d / 2 + thickness / 2)
    back.Material = mat
    back.Color = col
    back.Anchored = true
    back.Parent = model

    -- Side panels
    for _, side in ipairs({-1, 1}) do
        local panel = Instance.new("Part")
        panel.Name = "SidePanel"
        panel.Size = Vector3.new(thickness, h, d)
        panel.CFrame = baseCF * CFrame.new(side * (w / 2 - thickness / 2), h / 2, 0)
        panel.Material = mat
        panel.Color = col
        panel.Anchored = true
        panel.Parent = model
    end

    -- Shelf boards
    local spacing = h / (shelves + 1)
    for i = 0, shelves do
        local shelf = Instance.new("Part")
        shelf.Name = "ShelfBoard_" .. i
        shelf.Size = Vector3.new(w - thickness * 2, thickness, d)
        local yPos = i * spacing + thickness / 2
        if i == shelves then yPos = h - thickness / 2 end
        shelf.CFrame = baseCF * CFrame.new(0, yPos, 0)
        shelf.Material = mat
        shelf.Color = col
        shelf.Anchored = true
        shelf.Parent = model
    end

    -- Optional books
    if config.withBooks then
        local bookColors = {
            Color3.fromRGB(150, 30, 30),
            Color3.fromRGB(30, 80, 150),
            Color3.fromRGB(30, 120, 50),
            Color3.fromRGB(140, 100, 40),
            Color3.fromRGB(80, 30, 120),
        }

        for i = 1, shelves do
            local shelfY = i * spacing
            local bookCount = math.random(3, math.floor(w / 0.6))
            local xStart = -w / 2 + thickness + 0.4

            for b = 1, bookCount do
                local bookW = 0.3 + math.random() * 0.3
                local bookH = spacing * (0.5 + math.random() * 0.35)
                local book = Instance.new("Part")
                book.Name = "Book"
                book.Size = Vector3.new(bookW, bookH, d * 0.7)
                book.CFrame = baseCF * CFrame.new(
                    xStart + (b - 1) * 0.5,
                    shelfY + bookH / 2 + thickness / 2,
                    0.1
                )
                book.Material = Enum.Material.SmoothPlastic
                book.Color = bookColors[math.random(1, #bookColors)]
                book.Anchored = true
                book.CanCollide = false
                book.Parent = model

                if xStart + b * 0.5 > w / 2 - thickness then break end
            end
        end
    end

    model.PrimaryPart = back
    model.Parent = workspace
    return model
end
```

## Torch with Fire VFX

```lua
local function createTorch(config: {
    position: Vector3,
    wallMounted: boolean?,
    wallFace: Enum.NormalId?,
    flameColor: Color3?,
    brightness: number?,
}): Model
    local model = Instance.new("Model")
    model.Name = "Torch"

    local flameColor = config.flameColor or Color3.fromRGB(255, 150, 30)

    -- Handle
    local handle = Instance.new("Part")
    handle.Name = "Handle"
    handle.Shape = Enum.PartType.Cylinder
    handle.Size = Vector3.new(3, 0.3, 0.3)

    if config.wallMounted then
        local faceOffset = {
            [Enum.NormalId.Front] = CFrame.new(0, 0, -0.5) * CFrame.Angles(math.rad(45), 0, math.rad(90)),
            [Enum.NormalId.Back]  = CFrame.new(0, 0, 0.5) * CFrame.Angles(math.rad(-45), 0, math.rad(90)),
            [Enum.NormalId.Left]  = CFrame.new(-0.5, 0, 0) * CFrame.Angles(0, 0, math.rad(45)),
            [Enum.NormalId.Right] = CFrame.new(0.5, 0, 0) * CFrame.Angles(0, 0, math.rad(-45)),
        }
        local face = config.wallFace or Enum.NormalId.Front
        handle.CFrame = CFrame.new(config.position) * (faceOffset[face] or faceOffset[Enum.NormalId.Front])
    else
        handle.CFrame = CFrame.new(config.position) * CFrame.Angles(0, 0, math.rad(90))
    end

    handle.Material = Enum.Material.Wood
    handle.Color = Color3.fromRGB(80, 50, 25)
    handle.Anchored = true
    handle.Parent = model

    -- Fire holder (top of torch)
    local holder = Instance.new("Part")
    holder.Name = "FireHolder"
    holder.Size = Vector3.new(0.6, 0.6, 0.6)
    holder.CFrame = handle.CFrame * CFrame.new(1.5, 0, 0) * CFrame.Angles(0, 0, math.rad(-90))
    holder.Material = Enum.Material.Metal
    holder.Color = Color3.fromRGB(50, 50, 50)
    holder.Anchored = true
    holder.Parent = model

    -- Fire particle effect
    local fireAttachment = Instance.new("Attachment")
    fireAttachment.Parent = holder

    local fire = Instance.new("ParticleEmitter")
    fire.Name = "Fire"
    fire.Texture = "rbxassetid://296874871"
    fire.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 200, 50)),
        ColorSequenceKeypoint.new(0.4, flameColor),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 50, 10)),
    })
    fire.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.5),
        NumberSequenceKeypoint.new(0.3, 1.2),
        NumberSequenceKeypoint.new(1, 0),
    })
    fire.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.3),
        NumberSequenceKeypoint.new(0.5, 0.5),
        NumberSequenceKeypoint.new(1, 1),
    })
    fire.Lifetime = NumberRange.new(0.3, 0.6)
    fire.Rate = 80
    fire.Speed = NumberRange.new(3, 6)
    fire.SpreadAngle = Vector2.new(15, 15)
    fire.EmissionDirection = Enum.NormalId.Top
    fire.LightEmission = 1
    fire.LightInfluence = 0
    fire.Parent = fireAttachment

    -- Smoke
    local smoke = Instance.new("ParticleEmitter")
    smoke.Name = "Smoke"
    smoke.Texture = "rbxassetid://1084981289"
    smoke.Color = ColorSequence.new(Color3.fromRGB(80, 80, 80))
    smoke.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.2),
        NumberSequenceKeypoint.new(1, 1.5),
    })
    smoke.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.7),
        NumberSequenceKeypoint.new(1, 1),
    })
    smoke.Lifetime = NumberRange.new(1, 2)
    smoke.Rate = 15
    smoke.Speed = NumberRange.new(1, 3)
    smoke.EmissionDirection = Enum.NormalId.Top
    smoke.Parent = fireAttachment

    -- PointLight for illumination
    local light = Instance.new("PointLight")
    light.Brightness = config.brightness or 2
    light.Color = flameColor
    light.Range = 20
    light.Shadows = true
    light.Parent = holder

    -- Flickering effect
    task.spawn(function()
        while holder.Parent do
            light.Brightness = (config.brightness or 2) * (0.8 + math.random() * 0.4)
            task.wait(0.1 + math.random() * 0.1)
        end
    end)

    model.Parent = workspace
    return model
end
```

## Crates and Barrels

### Crate
```lua
local function createCrate(config: {
    position: Vector3,
    size: number?,
    material: Enum.Material?,
    color: Color3?,
    open: boolean?,
}): Model
    local s = config.size or 3
    local mat = config.material or Enum.Material.Wood
    local col = config.color or Color3.fromRGB(150, 110, 60)

    local model = Instance.new("Model")
    model.Name = "Crate"

    -- Main box
    local box = Instance.new("Part")
    box.Name = "Body"
    box.Size = Vector3.new(s, s, s)
    box.CFrame = CFrame.new(config.position + Vector3.new(0, s / 2, 0))
    box.Material = mat
    box.Color = col
    box.Anchored = true
    box.Parent = model

    -- Cross braces on front and back
    for _, zOff in ipairs({-1, 1}) do
        -- Horizontal brace
        local hBrace = Instance.new("Part")
        hBrace.Name = "HBrace"
        hBrace.Size = Vector3.new(s * 0.9, 0.15, 0.1)
        hBrace.CFrame = CFrame.new(config.position + Vector3.new(0, s / 2, zOff * s / 2 + zOff * 0.06))
        hBrace.Material = Enum.Material.Wood
        hBrace.Color = Color3.fromRGB(120, 85, 40)
        hBrace.Anchored = true
        hBrace.Parent = model

        -- Vertical brace
        local vBrace = Instance.new("Part")
        vBrace.Name = "VBrace"
        vBrace.Size = Vector3.new(0.15, s * 0.9, 0.1)
        vBrace.CFrame = CFrame.new(config.position + Vector3.new(0, s / 2, zOff * s / 2 + zOff * 0.06))
        vBrace.Material = Enum.Material.Wood
        vBrace.Color = Color3.fromRGB(120, 85, 40)
        vBrace.Anchored = true
        vBrace.Parent = model
    end

    -- Open lid
    if config.open then
        local lid = Instance.new("Part")
        lid.Name = "Lid"
        lid.Size = Vector3.new(s, 0.2, s)
        lid.CFrame = CFrame.new(config.position + Vector3.new(0, s + 0.1, -s / 2))
            * CFrame.Angles(math.rad(-60), 0, 0)
            * CFrame.new(0, 0, s / 2)
        lid.Material = mat
        lid.Color = col
        lid.Anchored = true
        lid.Parent = model
    end

    model.PrimaryPart = box
    model.Parent = workspace
    return model
end
```

### Barrel
```lua
local function createBarrel(config: {
    position: Vector3,
    height: number?,
    radius: number?,
    color: Color3?,
    tipped: boolean?,
}): Model
    local h = config.height or 4
    local r = config.radius or 1.5
    local col = config.color or Color3.fromRGB(140, 100, 50)

    local model = Instance.new("Model")
    model.Name = "Barrel"

    -- Main body
    local body = Instance.new("Part")
    body.Name = "Body"
    body.Shape = Enum.PartType.Cylinder
    body.Size = Vector3.new(h, r * 2, r * 2)

    if config.tipped then
        body.CFrame = CFrame.new(config.position + Vector3.new(0, r, 0))
            * CFrame.Angles(0, 0, math.rad(0))
    else
        body.CFrame = CFrame.new(config.position + Vector3.new(0, h / 2, 0))
            * CFrame.Angles(0, 0, math.rad(90))
    end

    body.Material = Enum.Material.Wood
    body.Color = col
    body.Anchored = true
    body.Parent = model

    -- Metal bands
    for _, yFrac in ipairs({0.2, 0.5, 0.8}) do
        local band = Instance.new("Part")
        band.Name = "Band"
        band.Shape = Enum.PartType.Cylinder
        band.Size = Vector3.new(0.15, r * 2 + 0.1, r * 2 + 0.1)

        if config.tipped then
            band.CFrame = body.CFrame * CFrame.new(h * (yFrac - 0.5), 0, 0)
        else
            band.CFrame = CFrame.new(config.position + Vector3.new(0, h * yFrac, 0))
                * CFrame.Angles(0, 0, math.rad(90))
        end

        band.Material = Enum.Material.Metal
        band.Color = Color3.fromRGB(70, 70, 75)
        band.Anchored = true
        band.Parent = model
    end

    model.PrimaryPart = body
    model.Parent = workspace
    return model
end
```

## Interactive Props with ClickDetector

### Generic Interactive Prop
```lua
local function makeInteractive(part: BasePart, config: {
    maxActivationDistance: number?,
    cursor: string?,
    onClicked: ((player: Player) -> ())?,
    onHoverEnter: ((player: Player) -> ())?,
    onHoverLeave: ((player: Player) -> ())?,
}): ClickDetector
    local detector = Instance.new("ClickDetector")
    detector.MaxActivationDistance = config.maxActivationDistance or 16
    detector.CursorIcon = config.cursor or ""
    detector.Parent = part

    if config.onClicked then
        detector.MouseClick:Connect(config.onClicked)
    end
    if config.onHoverEnter then
        detector.MouseHoverEnter:Connect(config.onHoverEnter)
    end
    if config.onHoverLeave then
        detector.MouseHoverLeave:Connect(config.onHoverLeave)
    end

    return detector
end
```

### Interactive Chest (Open/Close)
```lua
local function createInteractiveChest(config: {
    position: Vector3,
    lootItems: { string }?,
}): Model
    local model = Instance.new("Model")
    model.Name = "InteractiveChest"

    local body = Instance.new("Part")
    body.Name = "Body"
    body.Size = Vector3.new(4, 2.5, 3)
    body.CFrame = CFrame.new(config.position + Vector3.new(0, 1.25, 0))
    body.Material = Enum.Material.Wood
    body.Color = Color3.fromRGB(120, 80, 40)
    body.Anchored = true
    body.Parent = model

    local lid = Instance.new("Part")
    lid.Name = "Lid"
    lid.Size = Vector3.new(4, 0.5, 3)
    lid.CFrame = CFrame.new(config.position + Vector3.new(0, 2.75, 0))
    lid.Material = Enum.Material.Wood
    lid.Color = Color3.fromRGB(120, 80, 40)
    lid.Anchored = true
    lid.Parent = model

    -- Gold trim
    local trim = Instance.new("Part")
    trim.Name = "Trim"
    trim.Size = Vector3.new(4.1, 0.2, 3.1)
    trim.CFrame = CFrame.new(config.position + Vector3.new(0, 2.5, 0))
    trim.Material = Enum.Material.Gold
    trim.Color = Color3.fromRGB(255, 200, 50)
    trim.Anchored = true
    trim.Parent = model

    -- Interactive behavior
    local isOpen = false
    local TweenService = game:GetService("TweenService")

    local detector = Instance.new("ClickDetector")
    detector.MaxActivationDistance = 12
    detector.Parent = body

    local closedCF = lid.CFrame
    local openCF = CFrame.new(config.position + Vector3.new(0, 2.75, -1.5))
        * CFrame.Angles(math.rad(-110), 0, 0)

    detector.MouseClick:Connect(function(player)
        isOpen = not isOpen
        local targetCF = isOpen and openCF or closedCF
        local tween = TweenService:Create(lid, TweenInfo.new(0.5, Enum.EasingStyle.Back), {
            CFrame = targetCF,
        })
        tween:Play()

        if isOpen and config.lootItems then
            -- Display loot notification (simple print for now)
            print(player.Name .. " opened chest! Contains: " .. table.concat(config.lootItems, ", "))
        end
    end)

    model.PrimaryPart = body
    model.Parent = workspace
    return model
end
```

## Lamp Post

```lua
local function createLampPost(config: {
    position: Vector3,
    height: number?,
    style: string?,       -- "modern" | "victorian" | "simple"
    lightColor: Color3?,
    brightness: number?,
    autoOnAtNight: boolean?,
}): Model
    local h = config.height or 14
    local style = config.style or "modern"
    local lightCol = config.lightColor or Color3.fromRGB(255, 220, 160)

    local model = Instance.new("Model")
    model.Name = "LampPost"

    -- Base
    local base = Instance.new("Part")
    base.Name = "Base"
    base.Size = Vector3.new(2, 0.5, 2)
    base.CFrame = CFrame.new(config.position + Vector3.new(0, 0.25, 0))
    base.Material = Enum.Material.Metal
    base.Color = Color3.fromRGB(60, 60, 65)
    base.Anchored = true
    base.Parent = model

    -- Pole
    local pole = Instance.new("Part")
    pole.Name = "Pole"
    pole.Shape = Enum.PartType.Cylinder
    pole.Size = Vector3.new(h - 1, 0.4, 0.4)
    pole.CFrame = CFrame.new(config.position + Vector3.new(0, h / 2, 0))
        * CFrame.Angles(0, 0, math.rad(90))
    pole.Material = Enum.Material.Metal
    pole.Color = Color3.fromRGB(60, 60, 65)
    pole.Anchored = true
    pole.Parent = model

    -- Lamp housing
    local housing
    if style == "victorian" then
        housing = Instance.new("Part")
        housing.Name = "Housing"
        housing.Size = Vector3.new(2.5, 3, 2.5)
        housing.CFrame = CFrame.new(config.position + Vector3.new(0, h + 1, 0))
        housing.Material = Enum.Material.Metal
        housing.Color = Color3.fromRGB(50, 50, 55)
    elseif style == "modern" then
        housing = Instance.new("Part")
        housing.Name = "Housing"
        housing.Size = Vector3.new(3, 1, 1.5)
        housing.CFrame = CFrame.new(config.position + Vector3.new(1, h, 0))
        housing.Material = Enum.Material.Metal
        housing.Color = Color3.fromRGB(80, 80, 85)
    else
        housing = Instance.new("Part")
        housing.Name = "Housing"
        housing.Shape = Enum.PartType.Ball
        housing.Size = Vector3.new(2, 2, 2)
        housing.CFrame = CFrame.new(config.position + Vector3.new(0, h + 0.5, 0))
        housing.Material = Enum.Material.Metal
        housing.Color = Color3.fromRGB(70, 70, 75)
    end
    housing.Anchored = true
    housing.Parent = model

    -- Light bulb (Neon part)
    local bulb = Instance.new("Part")
    bulb.Name = "Bulb"
    bulb.Shape = Enum.PartType.Ball
    bulb.Size = Vector3.new(1, 1, 1)
    bulb.CFrame = housing.CFrame + Vector3.new(0, -0.5, 0)
    bulb.Material = Enum.Material.Neon
    bulb.Color = lightCol
    bulb.Anchored = true
    bulb.Transparency = 0.2
    bulb.Parent = model

    -- SpotLight
    local spotLight = Instance.new("SpotLight")
    spotLight.Brightness = config.brightness or 3
    spotLight.Color = lightCol
    spotLight.Range = 40
    spotLight.Angle = 60
    spotLight.Face = Enum.NormalId.Bottom
    spotLight.Shadows = true
    spotLight.Parent = housing

    -- PointLight for ambient glow
    local pointLight = Instance.new("PointLight")
    pointLight.Brightness = (config.brightness or 3) * 0.3
    pointLight.Color = lightCol
    pointLight.Range = 15
    pointLight.Shadows = false
    pointLight.Parent = bulb

    -- Auto on/off at night
    if config.autoOnAtNight then
        local Lighting = game:GetService("Lighting")
        Lighting:GetPropertyChangedSignal("ClockTime"):Connect(function()
            local t = Lighting.ClockTime
            local shouldBeOn = t >= 18 or t <= 6
            spotLight.Enabled = shouldBeOn
            pointLight.Enabled = shouldBeOn
            bulb.Transparency = shouldBeOn and 0.2 or 0.8
        end)
    end

    model.PrimaryPart = pole
    model.Parent = workspace
    return model
end
```

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

- `propType`: "table" | "chair" | "bed" | "shelf" | "torch" | "crate" | "barrel" | "chest" | "lampPost" -- 소품 종류
- `position`: {x: number, y: number, z: number} -- 위치
- `rotation`: number -- Y축 회전 (도)
- `size`: string | {x, y, z} -- 크기 또는 사이즈 프리셋
- `material`: string -- 재질 (Enum.Material 이름)
- `color`: {r: number, g: number, b: number} -- 색상
- `interactive`: boolean -- 인터랙티브 여부
- `style`: string -- 스타일 (가구/가로등별 상이)
- `count`: number -- 생성 수량
- `flameColor`: {r: number, g: number, b: number} -- 횃불 불꽃 색상
- `withBooks`: boolean -- 선반에 책 포함
- `pillows`: boolean -- 침대에 베개 포함
