---
name: vegetation
description: |
  Roblox 식생 시스템 스킬. 나무 생성기(활엽수/소나무/야자수), 레이캐스트 기반 숲 배치,
  꽃밭, 잔디, 관목, 절차적 숲 생성을 구현합니다.
  키워드: 나무, 숲, 식물, 풀, 꽃, 잔디, 관목, 덤불, 소나무, 야자수, 활엽수, 식생,
  정원, 화단, 자연, 조경, 조림, 수풀,
  tree, forest, plant, grass, flower, bush, pine, palm, vegetation, garden, nature
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

# Vegetation Skill

Roblox에서 나무, 숲, 꽃, 잔디 등 식생을 절차적으로 생성하는 스킬입니다.

## Tree Generator

### Deciduous Tree (활엽수)
```lua
local function createDeciduousTree(config: {
    position: Vector3,
    trunkHeight: number?,
    trunkRadius: number?,
    canopyRadius: number?,
    canopyColor: Color3?,
    trunkColor: Color3?,
    leafDensity: number?,   -- 1-5
}): Model
    local trunkH = config.trunkHeight or math.random(12, 20)
    local trunkR = config.trunkRadius or math.random(8, 15) / 10
    local canopyR = config.canopyRadius or trunkH * 0.5
    local leafDensity = config.leafDensity or 3

    local model = Instance.new("Model")
    model.Name = "DeciduousTree"

    -- Trunk
    local trunk = Instance.new("Part")
    trunk.Name = "Trunk"
    trunk.Shape = Enum.PartType.Cylinder
    trunk.Size = Vector3.new(trunkH, trunkR * 2, trunkR * 2)
    trunk.CFrame = CFrame.new(config.position + Vector3.new(0, trunkH / 2, 0))
        * CFrame.Angles(0, 0, math.rad(90))
    trunk.Material = Enum.Material.Wood
    trunk.Color = config.trunkColor or Color3.fromRGB(100, 70, 40)
    trunk.Anchored = true
    trunk.Parent = model

    -- Canopy - multiple overlapping spheres for organic look
    local canopyCenter = config.position + Vector3.new(0, trunkH, 0)
    local canopyColor = config.canopyColor or Color3.fromRGB(60, 140, 50)

    for i = 1, leafDensity do
        local sphere = Instance.new("Part")
        sphere.Name = "Canopy_" .. i
        sphere.Shape = Enum.PartType.Ball

        local sizeVariation = canopyR * (0.6 + math.random() * 0.6)
        sphere.Size = Vector3.new(sizeVariation * 2, sizeVariation * 2, sizeVariation * 2)

        local offsetX = (math.random() - 0.5) * canopyR * 0.6
        local offsetY = (math.random() - 0.3) * canopyR * 0.4
        local offsetZ = (math.random() - 0.5) * canopyR * 0.6
        sphere.CFrame = CFrame.new(canopyCenter + Vector3.new(offsetX, offsetY, offsetZ))

        sphere.Material = Enum.Material.Grass
        -- Slight color variation per sphere
        local r = math.clamp(canopyColor.R * 255 + math.random(-20, 20), 0, 255)
        local g = math.clamp(canopyColor.G * 255 + math.random(-20, 20), 0, 255)
        local b = math.clamp(canopyColor.B * 255 + math.random(-10, 10), 0, 255)
        sphere.Color = Color3.fromRGB(r, g, b)
        sphere.Anchored = true
        sphere.CanCollide = false
        sphere.CastShadow = true
        sphere.Parent = model
    end

    -- Branches (simple cylinders)
    for i = 1, 3 do
        local branch = Instance.new("Part")
        branch.Name = "Branch_" .. i
        branch.Shape = Enum.PartType.Cylinder
        local branchLen = canopyR * (0.4 + math.random() * 0.3)
        local branchR = trunkR * 0.3
        branch.Size = Vector3.new(branchLen, branchR * 2, branchR * 2)

        local branchHeight = trunkH * (0.5 + math.random() * 0.4)
        local angle = math.rad(math.random(0, 360))
        local tilt = math.rad(math.random(20, 50))

        branch.CFrame = CFrame.new(config.position + Vector3.new(0, branchHeight, 0))
            * CFrame.Angles(0, angle, tilt)
        branch.Material = Enum.Material.Wood
        branch.Color = config.trunkColor or Color3.fromRGB(100, 70, 40)
        branch.Anchored = true
        branch.Parent = model
    end

    model.PrimaryPart = trunk
    model.Parent = workspace
    return model
end
```

### Pine Tree (소나무)
```lua
local function createPineTree(config: {
    position: Vector3,
    height: number?,
    baseRadius: number?,
    trunkColor: Color3?,
    needleColor: Color3?,
    layers: number?,
}): Model
    local height = config.height or math.random(15, 30)
    local baseRadius = config.baseRadius or height * 0.25
    local layers = config.layers or math.floor(height / 4)

    local model = Instance.new("Model")
    model.Name = "PineTree"

    -- Trunk
    local trunkR = height * 0.04
    local trunk = Instance.new("Part")
    trunk.Name = "Trunk"
    trunk.Shape = Enum.PartType.Cylinder
    trunk.Size = Vector3.new(height, trunkR * 2, trunkR * 2)
    trunk.CFrame = CFrame.new(config.position + Vector3.new(0, height / 2, 0))
        * CFrame.Angles(0, 0, math.rad(90))
    trunk.Material = Enum.Material.Wood
    trunk.Color = config.trunkColor or Color3.fromRGB(90, 60, 35)
    trunk.Anchored = true
    trunk.Parent = model

    -- Cone layers (stacked, progressively smaller)
    local needleColor = config.needleColor or Color3.fromRGB(30, 100, 40)
    local layerSpacing = height / (layers + 1)

    for i = 1, layers do
        local cone = Instance.new("Part")
        cone.Name = "NeedleLayer_" .. i

        -- Each layer gets smaller toward the top
        local progress = i / layers
        local layerRadius = baseRadius * (1 - progress * 0.7)
        local layerHeight = layerSpacing * 1.2

        cone.Size = Vector3.new(layerRadius * 2, layerHeight, layerRadius * 2)
        cone.CFrame = CFrame.new(config.position + Vector3.new(0, layerSpacing * i + height * 0.15, 0))
        cone.Material = Enum.Material.Grass
        -- Variation in green
        local r = math.clamp(needleColor.R * 255 + math.random(-15, 15), 0, 255)
        local g = math.clamp(needleColor.G * 255 + math.random(-15, 15), 0, 255)
        local b = math.clamp(needleColor.B * 255 + math.random(-10, 10), 0, 255)
        cone.Color = Color3.fromRGB(r, g, b)
        cone.Anchored = true
        cone.CanCollide = false
        cone.CastShadow = true
        cone.Parent = model
    end

    -- Snow cap (optional - top decoration)
    local tip = Instance.new("Part")
    tip.Name = "Tip"
    tip.Shape = Enum.PartType.Ball
    tip.Size = Vector3.new(1, 2, 1)
    tip.CFrame = CFrame.new(config.position + Vector3.new(0, height + 0.5, 0))
    tip.Material = Enum.Material.Grass
    tip.Color = needleColor
    tip.Anchored = true
    tip.CanCollide = false
    tip.Parent = model

    model.PrimaryPart = trunk
    model.Parent = workspace
    return model
end
```

### Palm Tree (야자수)
```lua
local function createPalmTree(config: {
    position: Vector3,
    trunkHeight: number?,
    trunkCurve: number?,  -- 0-1 how much the trunk curves
    frondCount: number?,
    frondLength: number?,
    coconuts: boolean?,
}): Model
    local trunkH = config.trunkHeight or math.random(15, 25)
    local curve = config.trunkCurve or 0.3
    local frondCount = config.frondCount or math.random(6, 10)
    local frondLen = config.frondLength or trunkH * 0.4

    local model = Instance.new("Model")
    model.Name = "PalmTree"

    -- Curved trunk using segmented cylinders
    local segments = 8
    local segHeight = trunkH / segments
    local segRadius = 0.8

    local prevTop = config.position
    local curveOffset = Vector3.new(curve * trunkH * 0.3, 0, 0)

    for i = 1, segments do
        local t = i / segments
        local prevT = (i - 1) / segments

        -- Quadratic curve
        local startOffset = curveOffset * prevT * prevT
        local endOffset = curveOffset * t * t

        local startPos = config.position + Vector3.new(startOffset.X, segHeight * (i - 1), startOffset.Z)
        local endPos = config.position + Vector3.new(endOffset.X, segHeight * i, endOffset.Z)

        local midPoint = (startPos + endPos) / 2
        local direction = (endPos - startPos)
        local length = direction.Magnitude

        local seg = Instance.new("Part")
        seg.Name = "TrunkSeg_" .. i
        seg.Shape = Enum.PartType.Cylinder
        -- Slight taper: thinner at top
        local radius = segRadius * (1 - t * 0.3)
        seg.Size = Vector3.new(length, radius * 2, radius * 2)
        seg.CFrame = CFrame.lookAt(midPoint, endPos) * CFrame.Angles(0, math.rad(90), 0)
        seg.Material = Enum.Material.Wood
        seg.Color = Color3.fromRGB(140, 120, 80)
        seg.Anchored = true
        seg.Parent = model

        prevTop = endPos
    end

    -- Fronds at the top
    local topPos = prevTop
    for i = 1, frondCount do
        local angle = (i / frondCount) * math.pi * 2
        local droop = math.rad(math.random(20, 45))

        local frond = Instance.new("Part")
        frond.Name = "Frond_" .. i
        frond.Size = Vector3.new(frondLen, 0.3, 2)
        frond.CFrame = CFrame.new(topPos)
            * CFrame.Angles(0, angle, 0)
            * CFrame.Angles(droop, 0, 0)
            * CFrame.new(0, 0, -frondLen / 2)
        frond.Material = Enum.Material.Grass
        frond.Color = Color3.fromRGB(50, 140, 50)
        frond.Anchored = true
        frond.CanCollide = false
        frond.Parent = model
    end

    -- Coconuts
    if config.coconuts ~= false then
        for i = 1, math.random(2, 4) do
            local coconut = Instance.new("Part")
            coconut.Name = "Coconut_" .. i
            coconut.Shape = Enum.PartType.Ball
            coconut.Size = Vector3.new(1.2, 1.2, 1.2)
            local cAngle = math.random() * math.pi * 2
            coconut.CFrame = CFrame.new(
                topPos + Vector3.new(math.cos(cAngle) * 1.5, -1, math.sin(cAngle) * 1.5)
            )
            coconut.Material = Enum.Material.Wood
            coconut.Color = Color3.fromRGB(100, 70, 30)
            coconut.Anchored = true
            coconut.Parent = model
        end
    end

    model.Parent = workspace
    return model
end
```

## Forest Placement with Raycast

### Place Trees on Terrain Surface
```lua
local function getTerrainHeight(x: number, z: number): number?
    local origin = Vector3.new(x, 500, z)
    local direction = Vector3.new(0, -1000, 0)

    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Include
    raycastParams.FilterDescendantsInstances = { workspace.Terrain }

    local result = workspace:Raycast(origin, direction, raycastParams)
    if result then
        return result.Position.Y
    end
    return nil
end

local function placeTreeOnTerrain(treeType: string, x: number, z: number, config: { [string]: any }?)
    local y = getTerrainHeight(x, z)
    if not y then return nil end

    config = config or {}
    config.position = Vector3.new(x, y, z)

    if treeType == "deciduous" then
        return createDeciduousTree(config)
    elseif treeType == "pine" then
        return createPineTree(config)
    elseif treeType == "palm" then
        return createPalmTree(config)
    end
    return nil
end
```

### Procedural Forest Generator
```lua
local function generateForest(config: {
    center: Vector3,
    radius: number,
    density: number?,          -- trees per 100 square studs
    treeTypes: { string }?,    -- {"deciduous", "pine", "palm"}
    minSpacing: number?,       -- minimum distance between trees
    slopeLimit: number?,       -- max terrain slope (degrees) for placement
    excludeWater: boolean?,
}): { Model }
    local radius = config.radius
    local density = config.density or 0.5
    local treeTypes = config.treeTypes or { "deciduous" }
    local minSpacing = config.minSpacing or 8
    local slopeLimit = config.slopeLimit or 45

    local area = math.pi * radius * radius
    local treeCount = math.floor(area / 100 * density)

    local placedPositions: { Vector3 } = {}
    local trees: { Model } = {}

    local folder = Instance.new("Folder")
    folder.Name = "Forest"
    folder.Parent = workspace

    local attempts = 0
    local maxAttempts = treeCount * 5

    while #trees < treeCount and attempts < maxAttempts do
        attempts += 1

        -- Random point within circle (uniform distribution)
        local angle = math.random() * math.pi * 2
        local dist = math.sqrt(math.random()) * radius
        local x = config.center.X + math.cos(angle) * dist
        local z = config.center.Z + math.sin(angle) * dist

        -- Check minimum spacing
        local tooClose = false
        for _, pos in ipairs(placedPositions) do
            local dx = x - pos.X
            local dz = z - pos.Z
            if math.sqrt(dx * dx + dz * dz) < minSpacing then
                tooClose = true
                break
            end
        end
        if tooClose then continue end

        -- Raycast to find terrain surface
        local origin = Vector3.new(x, 500, z)
        local rayParams = RaycastParams.new()
        rayParams.FilterType = Enum.RaycastFilterType.Include
        rayParams.FilterDescendantsInstances = { workspace.Terrain }
        local result = workspace:Raycast(origin, Vector3.new(0, -1000, 0), rayParams)

        if not result then continue end

        -- Check slope
        if result.Normal then
            local slopeAngle = math.deg(math.acos(result.Normal:Dot(Vector3.yAxis)))
            if slopeAngle > slopeLimit then continue end
        end

        -- Check for water
        if config.excludeWater ~= false then
            if result.Material == Enum.Material.Water then continue end
        end

        -- Place tree
        local treeType = treeTypes[math.random(1, #treeTypes)]
        local treeConfig = {
            position = result.Position,
        }

        -- Randomize tree properties
        if treeType == "deciduous" then
            treeConfig.trunkHeight = math.random(10, 22)
            treeConfig.leafDensity = math.random(2, 5)
        elseif treeType == "pine" then
            treeConfig.height = math.random(14, 28)
        elseif treeType == "palm" then
            treeConfig.trunkHeight = math.random(12, 22)
        end

        local tree = placeTreeOnTerrain(treeType, x, z, treeConfig)
        if tree then
            tree.Parent = folder
            table.insert(trees, tree)
            table.insert(placedPositions, result.Position)
        end

        -- Yield periodically to prevent timeout
        if attempts % 20 == 0 then
            task.wait()
        end
    end

    return trees
end

-- Usage:
-- generateForest({
--     center = Vector3.new(0, 0, 0),
--     radius = 150,
--     density = 0.8,
--     treeTypes = {"deciduous", "pine"},
--     minSpacing = 10,
-- })
```

## Flower Patches

```lua
local function createFlowerPatch(config: {
    center: Vector3,
    radius: number?,
    flowerCount: number?,
    colors: { Color3 }?,
    stemHeight: number?,
}): Model
    local radius = config.radius or 10
    local count = config.flowerCount or 30
    local stemH = config.stemHeight or 1.5
    local colors = config.colors or {
        Color3.fromRGB(255, 80, 80),   -- red
        Color3.fromRGB(255, 200, 50),  -- yellow
        Color3.fromRGB(255, 100, 200), -- pink
        Color3.fromRGB(200, 150, 255), -- purple
        Color3.fromRGB(255, 255, 255), -- white
    }

    local model = Instance.new("Model")
    model.Name = "FlowerPatch"

    for i = 1, count do
        local angle = math.random() * math.pi * 2
        local dist = math.sqrt(math.random()) * radius
        local x = config.center.X + math.cos(angle) * dist
        local z = config.center.Z + math.sin(angle) * dist

        -- Raycast for terrain height
        local rayParams = RaycastParams.new()
        rayParams.FilterType = Enum.RaycastFilterType.Include
        rayParams.FilterDescendantsInstances = { workspace.Terrain }
        local result = workspace:Raycast(
            Vector3.new(x, 500, z),
            Vector3.new(0, -1000, 0),
            rayParams
        )
        if not result then continue end

        local basePos = result.Position

        -- Stem
        local stem = Instance.new("Part")
        stem.Name = "Stem_" .. i
        stem.Size = Vector3.new(0.15, stemH, 0.15)
        stem.CFrame = CFrame.new(basePos + Vector3.new(0, stemH / 2, 0))
        stem.Material = Enum.Material.Grass
        stem.Color = Color3.fromRGB(50, 130, 40)
        stem.Anchored = true
        stem.CanCollide = false
        stem.Parent = model

        -- Flower head
        local flower = Instance.new("Part")
        flower.Name = "Flower_" .. i
        flower.Shape = Enum.PartType.Ball
        local flowerSize = 0.4 + math.random() * 0.4
        flower.Size = Vector3.new(flowerSize, flowerSize * 0.6, flowerSize)
        flower.CFrame = CFrame.new(basePos + Vector3.new(0, stemH + flowerSize * 0.2, 0))
        flower.Material = Enum.Material.SmoothPlastic
        flower.Color = colors[math.random(1, #colors)]
        flower.Anchored = true
        flower.CanCollide = false
        flower.Parent = model
    end

    model.Parent = workspace
    return model
end
```

## Grass / Ground Cover

```lua
local function createGrassField(config: {
    center: Vector3,
    size: Vector2?,       -- XZ extent
    density: number?,     -- blades per square stud
    bladeHeight: number?,
    color: Color3?,
}): Model
    local size = config.size or Vector2.new(40, 40)
    local density = config.density or 0.3
    local bladeH = config.bladeHeight or 1
    local color = config.color or Color3.fromRGB(60, 140, 50)

    local model = Instance.new("Model")
    model.Name = "GrassField"

    local totalBlades = math.floor(size.X * size.Y * density)
    local halfX = size.X / 2
    local halfZ = size.Y / 2

    for i = 1, totalBlades do
        local x = config.center.X + (math.random() - 0.5) * size.X
        local z = config.center.Z + (math.random() - 0.5) * size.Y

        local rayParams = RaycastParams.new()
        rayParams.FilterType = Enum.RaycastFilterType.Include
        rayParams.FilterDescendantsInstances = { workspace.Terrain }
        local result = workspace:Raycast(
            Vector3.new(x, 500, z),
            Vector3.new(0, -1000, 0),
            rayParams
        )
        if not result then continue end

        local h = bladeH * (0.6 + math.random() * 0.6)
        local blade = Instance.new("Part")
        blade.Name = "GrassBlade"
        blade.Size = Vector3.new(0.1, h, 0.05)
        blade.CFrame = CFrame.new(result.Position + Vector3.new(0, h / 2, 0))
            * CFrame.Angles(0, math.random() * math.pi * 2, math.rad(math.random(-10, 10)))
        blade.Material = Enum.Material.Grass
        local r = math.clamp(color.R * 255 + math.random(-20, 20), 0, 255)
        local g = math.clamp(color.G * 255 + math.random(-20, 20), 0, 255)
        local b = math.clamp(color.B * 255 + math.random(-10, 10), 0, 255)
        blade.Color = Color3.fromRGB(r, g, b)
        blade.Anchored = true
        blade.CanCollide = false
        blade.CastShadow = false
        blade.Parent = model

        if i % 50 == 0 then task.wait() end
    end

    model.Parent = workspace
    return model
end
```

## Bushes / Shrubs

```lua
local function createBush(config: {
    position: Vector3,
    size: number?,
    color: Color3?,
    berries: boolean?,
    berryColor: Color3?,
}): Model
    local bushSize = config.size or math.random(2, 4)
    local color = config.color or Color3.fromRGB(45, 120, 40)

    local model = Instance.new("Model")
    model.Name = "Bush"

    -- Main body (overlapping spheres)
    local sphereCount = math.random(3, 5)
    for i = 1, sphereCount do
        local s = Instance.new("Part")
        s.Shape = Enum.PartType.Ball
        local sz = bushSize * (0.6 + math.random() * 0.5)
        s.Size = Vector3.new(sz, sz * 0.7, sz)

        local offsetX = (math.random() - 0.5) * bushSize * 0.4
        local offsetY = (math.random() - 0.3) * bushSize * 0.2
        local offsetZ = (math.random() - 0.5) * bushSize * 0.4
        s.CFrame = CFrame.new(config.position + Vector3.new(offsetX, bushSize * 0.3 + offsetY, offsetZ))
        s.Material = Enum.Material.Grass
        local r = math.clamp(color.R * 255 + math.random(-15, 15), 0, 255)
        local g = math.clamp(color.G * 255 + math.random(-15, 15), 0, 255)
        local b = math.clamp(color.B * 255 + math.random(-10, 10), 0, 255)
        s.Color = Color3.fromRGB(r, g, b)
        s.Anchored = true
        s.CanCollide = true
        s.Parent = model
    end

    -- Optional berries
    if config.berries then
        local berryColor = config.berryColor or Color3.fromRGB(200, 30, 30)
        for i = 1, math.random(5, 12) do
            local berry = Instance.new("Part")
            berry.Shape = Enum.PartType.Ball
            berry.Size = Vector3.new(0.3, 0.3, 0.3)
            local a = math.random() * math.pi * 2
            local d = math.random() * bushSize * 0.5
            berry.CFrame = CFrame.new(
                config.position + Vector3.new(
                    math.cos(a) * d,
                    bushSize * 0.3 + math.random() * bushSize * 0.3,
                    math.sin(a) * d
                )
            )
            berry.Material = Enum.Material.SmoothPlastic
            berry.Color = berryColor
            berry.Anchored = true
            berry.CanCollide = false
            berry.Parent = model
        end
    end

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

- `treeType`: "deciduous" | "pine" | "palm" -- 나무 종류
- `position`: {x: number, y: number, z: number} -- 위치
- `count`: number -- 생성 수량
- `forestRadius`: number -- 숲 반경 (studs)
- `forestDensity`: number -- 숲 밀도 (trees per 100 sq studs)
- `treeTypes`: ["deciduous" | "pine" | "palm"] -- 숲에 포함할 나무 종류
- `minSpacing`: number -- 최소 간격
- `canopyColor`: {r: number, g: number, b: number} -- 잎 색상
- `trunkHeight`: number -- 줄기 높이
- `flowerColors`: [{r, g, b}] -- 꽃 색상 목록
- `grassDensity`: number -- 잔디 밀도
- `berries`: boolean -- 열매 포함 여부
