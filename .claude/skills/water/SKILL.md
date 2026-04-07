---
name: water
description: |
  Roblox 물/수계 시스템 스킬. Terrain 물, 강(point-to-point), 폭포(파티클), 호수, 바다,
  수영 시스템, 물 속성(WaterColor, WaterTransparency, WaterWaveSize 등)을 구현합니다.
  키워드: 물, 강, 호수, 바다, 폭포, 수영, 해변, 연못, 수중, 파도, 물결, 투명도,
  water, river, lake, ocean, waterfall, swimming, wave, pond, beach, underwater
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

# Water Skill

Roblox에서 물 관련 시스템(Terrain 물, 강, 폭포, 호수, 바다, 수영)을 구현하는 스킬입니다.

## Terrain Water Properties

### Configure Water Appearance
```lua
local Terrain = workspace.Terrain

local function configureWater(config: {
    color: Color3?,
    transparency: number?,
    waveSize: number?,
    waveSpeed: number?,
    reflectance: number?,
})
    Terrain.WaterColor = config.color or Color3.fromRGB(12, 84, 92)
    Terrain.WaterTransparency = config.transparency or 0.3
    Terrain.WaterWaveSize = config.waveSize or 0.15
    Terrain.WaterWaveSpeed = config.waveSpeed or 10
    Terrain.WaterReflectance = config.reflectance or 1
end
```

### Water Presets
```lua
local WATER_PRESETS = {
    ocean = {
        color = Color3.fromRGB(12, 84, 120),
        transparency = 0.2,
        waveSize = 0.5,
        waveSpeed = 14,
        reflectance = 1,
    },
    tropicalOcean = {
        color = Color3.fromRGB(20, 150, 170),
        transparency = 0.6,
        waveSize = 0.3,
        waveSpeed = 10,
        reflectance = 1,
    },
    lake = {
        color = Color3.fromRGB(30, 100, 80),
        transparency = 0.4,
        waveSize = 0.08,
        waveSpeed = 6,
        reflectance = 0.8,
    },
    swamp = {
        color = Color3.fromRGB(40, 70, 30),
        transparency = 0.05,
        waveSize = 0.02,
        waveSpeed = 2,
        reflectance = 0.3,
    },
    river = {
        color = Color3.fromRGB(20, 90, 100),
        transparency = 0.35,
        waveSize = 0.12,
        waveSpeed = 12,
        reflectance = 0.7,
    },
    arctic = {
        color = Color3.fromRGB(80, 140, 170),
        transparency = 0.3,
        waveSize = 0.1,
        waveSpeed = 4,
        reflectance = 0.9,
    },
    lava = {
        color = Color3.fromRGB(200, 60, 10),
        transparency = 0.0,
        waveSize = 0.2,
        waveSpeed = 3,
        reflectance = 0.1,
    },
}

local function applyWaterPreset(presetName: string)
    local preset = WATER_PRESETS[presetName]
    if preset then
        configureWater(preset)
    end
end
```

## Terrain Water Fill

### Fill Lake / Pond
```lua
local Terrain = workspace.Terrain

local function fillTerrainWater(config: {
    center: Vector3,
    size: Vector3,    -- region size in studs
}): Region3
    local halfSize = config.size / 2
    local min = config.center - halfSize
    local max = config.center + halfSize

    -- Align to terrain grid (4 stud resolution)
    local region = Region3.new(
        Vector3.new(
            math.floor(min.X / 4) * 4,
            math.floor(min.Y / 4) * 4,
            math.floor(min.Z / 4) * 4
        ),
        Vector3.new(
            math.ceil(max.X / 4) * 4,
            math.ceil(max.Y / 4) * 4,
            math.ceil(max.Z / 4) * 4
        )
    )

    local regionSize = region.Size / 4
    local sizeX = math.ceil(regionSize.X)
    local sizeY = math.ceil(regionSize.Y)
    local sizeZ = math.ceil(regionSize.Z)

    local materials = {}
    local occupancy = {}

    for x = 1, sizeX do
        materials[x] = {}
        occupancy[x] = {}
        for y = 1, sizeY do
            materials[x][y] = {}
            occupancy[x][y] = {}
            for z = 1, sizeZ do
                materials[x][y][z] = Enum.Material.Water
                occupancy[x][y][z] = 1
            end
        end
    end

    Terrain:WriteVoxels(region, 4, materials, occupancy)
    return region
end
```

### Create Circular Lake
```lua
local function createCircularLake(config: {
    center: Vector3,
    radius: number,
    depth: number?,
}): ()
    local radius = config.radius
    local depth = config.depth or 8
    local center = config.center

    local region = Region3.new(
        Vector3.new(
            math.floor((center.X - radius) / 4) * 4,
            math.floor((center.Y - depth) / 4) * 4,
            math.floor((center.Z - radius) / 4) * 4
        ),
        Vector3.new(
            math.ceil((center.X + radius) / 4) * 4,
            math.ceil(center.Y / 4) * 4,
            math.ceil((center.Z + radius) / 4) * 4
        )
    )

    local regionSize = region.Size / 4
    local sizeX = math.ceil(regionSize.X)
    local sizeY = math.ceil(regionSize.Y)
    local sizeZ = math.ceil(regionSize.Z)

    local materials = {}
    local occupancy = {}

    local regionMin = region.CFrame.Position - region.Size / 2

    for x = 1, sizeX do
        materials[x] = {}
        occupancy[x] = {}
        for y = 1, sizeY do
            materials[x][y] = {}
            occupancy[x][y] = {}
            for z = 1, sizeZ do
                local worldX = regionMin.X + (x - 0.5) * 4
                local worldZ = regionMin.Z + (z - 0.5) * 4
                local dx = worldX - center.X
                local dz = worldZ - center.Z
                local dist = math.sqrt(dx * dx + dz * dz)

                if dist <= radius then
                    materials[x][y][z] = Enum.Material.Water
                    -- Smooth edges
                    local edgeFade = math.clamp(1 - (dist / radius - 0.8) / 0.2, 0, 1)
                    occupancy[x][y][z] = edgeFade
                else
                    materials[x][y][z] = Enum.Material.Air
                    occupancy[x][y][z] = 0
                end
            end
        end
    end

    Terrain:WriteVoxels(region, 4, materials, occupancy)
end
```

## River (Point-to-Point)

### Create River Along Waypoints
```lua
local Terrain = workspace.Terrain

local function createRiver(config: {
    waypoints: { Vector3 },  -- ordered list of river path points
    width: number?,
    depth: number?,
}): ()
    local width = config.width or 12
    local depth = config.depth or 6
    local waypoints = config.waypoints

    if #waypoints < 2 then
        warn("River needs at least 2 waypoints")
        return
    end

    for i = 1, #waypoints - 1 do
        local startPos = waypoints[i]
        local endPos = waypoints[i + 1]
        local direction = (endPos - startPos)
        local length = direction.Magnitude
        local unitDir = direction.Unit

        -- Number of segments along this stretch
        local segmentCount = math.ceil(length / 4)

        for seg = 0, segmentCount do
            local t = seg / segmentCount
            local pos = startPos:Lerp(endPos, t)

            -- Smooth interpolation if we have surrounding points for Catmull-Rom
            local center = pos
            local halfWidth = width / 2

            local region = Region3.new(
                Vector3.new(
                    math.floor((center.X - halfWidth) / 4) * 4,
                    math.floor((center.Y - depth) / 4) * 4,
                    math.floor((center.Z - halfWidth) / 4) * 4
                ),
                Vector3.new(
                    math.ceil((center.X + halfWidth) / 4) * 4,
                    math.ceil(center.Y / 4) * 4,
                    math.ceil((center.Z + halfWidth) / 4) * 4
                )
            )

            local regionSize = region.Size / 4
            local sX = math.max(1, math.ceil(regionSize.X))
            local sY = math.max(1, math.ceil(regionSize.Y))
            local sZ = math.max(1, math.ceil(regionSize.Z))

            local materials = {}
            local occupancy = {}

            for x = 1, sX do
                materials[x] = {}
                occupancy[x] = {}
                for y = 1, sY do
                    materials[x][y] = {}
                    occupancy[x][y] = {}
                    for z = 1, sZ do
                        materials[x][y][z] = Enum.Material.Water
                        occupancy[x][y][z] = 1
                    end
                end
            end

            Terrain:WriteVoxels(region, 4, materials, occupancy)
        end
    end
end

-- Usage:
-- createRiver({
--     waypoints = {
--         Vector3.new(-100, 5, 0),
--         Vector3.new(-50, 4, 20),
--         Vector3.new(0, 3, 10),
--         Vector3.new(50, 2, -15),
--         Vector3.new(100, 1, 0),
--     },
--     width = 16,
--     depth = 8,
-- })
```

## Waterfall (Particle-Based)

```lua
local function createWaterfall(config: {
    topPosition: Vector3,
    height: number?,
    width: number?,
    color: Color3?,
    mist: boolean?,
    soundId: string?,
}): Model
    local height = config.height or 30
    local width = config.width or 8

    local model = Instance.new("Model")
    model.Name = "Waterfall"

    -- Main waterfall emitter part at the top
    local emitterPart = Instance.new("Part")
    emitterPart.Name = "WaterfallTop"
    emitterPart.Size = Vector3.new(width, 1, 2)
    emitterPart.CFrame = CFrame.new(config.topPosition)
    emitterPart.Anchored = true
    emitterPart.CanCollide = false
    emitterPart.Transparency = 1
    emitterPart.Parent = model

    local attachment = Instance.new("Attachment")
    attachment.Parent = emitterPart

    -- Waterfall particles
    local waterEmitter = Instance.new("ParticleEmitter")
    waterEmitter.Name = "WaterFlow"
    waterEmitter.Texture = "rbxassetid://241685484"
    waterEmitter.Color = ColorSequence.new(config.color or Color3.fromRGB(180, 210, 230))
    waterEmitter.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1),
        NumberSequenceKeypoint.new(0.5, 2),
        NumberSequenceKeypoint.new(1, 3),
    })
    waterEmitter.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.2),
        NumberSequenceKeypoint.new(0.7, 0.3),
        NumberSequenceKeypoint.new(1, 0.8),
    })
    waterEmitter.Lifetime = NumberRange.new(height / 40, height / 25)
    waterEmitter.Rate = 300
    waterEmitter.Speed = NumberRange.new(5, 15)
    waterEmitter.SpreadAngle = Vector2.new(10, 5)
    waterEmitter.Acceleration = Vector3.new(0, -workspace.Gravity * 0.6, 0)
    waterEmitter.EmissionDirection = Enum.NormalId.Bottom
    waterEmitter.RotSpeed = NumberRange.new(-30, 30)
    waterEmitter.Parent = attachment

    -- Mist at the bottom
    if config.mist ~= false then
        local mistPart = Instance.new("Part")
        mistPart.Name = "MistZone"
        mistPart.Size = Vector3.new(width * 2, 1, width * 2)
        mistPart.CFrame = CFrame.new(config.topPosition - Vector3.new(0, height, 0))
        mistPart.Anchored = true
        mistPart.CanCollide = false
        mistPart.Transparency = 1
        mistPart.Parent = model

        local mistAttachment = Instance.new("Attachment")
        mistAttachment.Parent = mistPart

        local mistEmitter = Instance.new("ParticleEmitter")
        mistEmitter.Name = "Mist"
        mistEmitter.Texture = "rbxassetid://1084981289" -- cloud/mist texture
        mistEmitter.Color = ColorSequence.new(Color3.fromRGB(220, 230, 240))
        mistEmitter.Size = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 2),
            NumberSequenceKeypoint.new(0.5, 6),
            NumberSequenceKeypoint.new(1, 10),
        })
        mistEmitter.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.6),
            NumberSequenceKeypoint.new(0.5, 0.7),
            NumberSequenceKeypoint.new(1, 1),
        })
        mistEmitter.Lifetime = NumberRange.new(2, 4)
        mistEmitter.Rate = 30
        mistEmitter.Speed = NumberRange.new(2, 6)
        mistEmitter.SpreadAngle = Vector2.new(180, 180)
        mistEmitter.EmissionDirection = Enum.NormalId.Top
        mistEmitter.Parent = mistAttachment

        -- Splash particles at base
        local splashEmitter = Instance.new("ParticleEmitter")
        splashEmitter.Name = "Splash"
        splashEmitter.Texture = "rbxassetid://241685484"
        splashEmitter.Color = ColorSequence.new(Color3.fromRGB(200, 220, 240))
        splashEmitter.Size = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.2),
            NumberSequenceKeypoint.new(0.5, 0.8),
            NumberSequenceKeypoint.new(1, 0),
        })
        splashEmitter.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.3),
            NumberSequenceKeypoint.new(1, 1),
        })
        splashEmitter.Lifetime = NumberRange.new(0.5, 1)
        splashEmitter.Rate = 80
        splashEmitter.Speed = NumberRange.new(5, 15)
        splashEmitter.SpreadAngle = Vector2.new(60, 60)
        splashEmitter.EmissionDirection = Enum.NormalId.Top
        splashEmitter.Acceleration = Vector3.new(0, -workspace.Gravity * 0.5, 0)
        splashEmitter.Parent = mistAttachment
    end

    -- Waterfall sound
    if config.soundId then
        local sound = Instance.new("Sound")
        sound.SoundId = config.soundId
        sound.Volume = 0.8
        sound.Looped = true
        sound.RollOffMaxDistance = 100
        sound.Parent = emitterPart
        sound:Play()
    end

    model.Parent = workspace
    return model
end

-- Usage:
-- createWaterfall({
--     topPosition = Vector3.new(50, 40, 0),
--     height = 30,
--     width = 10,
--     mist = true,
-- })
```

## Ocean

### Large Ocean Terrain Fill
```lua
local function createOcean(config: {
    center: Vector3?,
    size: number?,      -- square side length in studs
    depth: number?,
}): ()
    local center = config.center or Vector3.new(0, 0, 0)
    local halfSize = (config.size or 2000) / 2
    local depth = config.depth or 40

    -- Apply ocean water preset
    applyWaterPreset("ocean")

    -- Fill in chunks to avoid memory issues
    local chunkSize = 200 -- studs per chunk
    local waterY = center.Y

    for cx = center.X - halfSize, center.X + halfSize - chunkSize, chunkSize do
        for cz = center.Z - halfSize, center.Z + halfSize - chunkSize, chunkSize do
            fillTerrainWater({
                center = Vector3.new(cx + chunkSize / 2, waterY - depth / 2, cz + chunkSize / 2),
                size = Vector3.new(chunkSize, depth, chunkSize),
            })
            task.wait() -- yield to prevent timeout
        end
    end
end
```

## Swimming System

### Basic Swimming Detection and Movement
```lua
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local function setupSwimmingSystem()
    Players.PlayerAdded:Connect(function(player)
        player.CharacterAdded:Connect(function(character)
            local humanoid = character:WaitForChild("Humanoid")
            local rootPart = character:WaitForChild("HumanoidRootPart")

            local isSwimming = false
            local swimConnection = nil

            local function checkWater()
                -- Check if character is in water region
                local pos = rootPart.Position
                local region = Region3.new(
                    pos - Vector3.new(2, 2, 2),
                    pos + Vector3.new(2, 2, 2)
                )
                region = region:ExpandToGrid(4)

                local materials, _ = workspace.Terrain:ReadVoxels(region, 4)
                for x, row in ipairs(materials) do
                    for y, col in ipairs(row) do
                        for z, mat in ipairs(col) do
                            if mat == Enum.Material.Water then
                                return true
                            end
                        end
                    end
                end
                return false
            end

            swimConnection = RunService.Heartbeat:Connect(function()
                local inWater = checkWater()

                if inWater and not isSwimming then
                    isSwimming = true
                    humanoid:SetStateEnabled(Enum.HumanoidStateType.Swimming, true)
                    humanoid:ChangeState(Enum.HumanoidStateType.Swimming)
                    -- Slow movement in water
                    humanoid.WalkSpeed = humanoid.WalkSpeed * 0.6
                elseif not inWater and isSwimming then
                    isSwimming = false
                    humanoid.WalkSpeed = 16 -- restore default
                end
            end)

            humanoid.Died:Connect(function()
                if swimConnection then
                    swimConnection:Disconnect()
                end
            end)
        end)
    end)
end
```

### Underwater Visual Effects
```lua
local function createUnderwaterEffect(player: Player)
    local camera = workspace.CurrentCamera
    local playerGui = player:WaitForChild("PlayerGui")

    -- Blue overlay ScreenGui
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "UnderwaterOverlay"
    screenGui.IgnoreGuiInset = true

    local frame = Instance.new("Frame")
    frame.Size = UDim2.fromScale(1, 1)
    frame.BackgroundColor3 = Color3.fromRGB(10, 60, 100)
    frame.BackgroundTransparency = 0.7
    frame.BorderSizePixel = 0
    frame.Parent = screenGui

    screenGui.Enabled = false
    screenGui.Parent = playerGui

    -- Underwater blur
    local blur = Instance.new("BlurEffect")
    blur.Name = "UnderwaterBlur"
    blur.Size = 6
    blur.Enabled = false
    blur.Parent = game:GetService("Lighting")

    -- Color correction for underwater tint
    local cc = Instance.new("ColorCorrectionEffect")
    cc.Name = "UnderwaterCC"
    cc.Brightness = -0.1
    cc.Contrast = 0.1
    cc.Saturation = -0.3
    cc.TintColor = Color3.fromRGB(150, 200, 255)
    cc.Enabled = false
    cc.Parent = game:GetService("Lighting")

    return {
        enable = function()
            screenGui.Enabled = true
            blur.Enabled = true
            cc.Enabled = true
        end,
        disable = function()
            screenGui.Enabled = false
            blur.Enabled = false
            cc.Enabled = false
        end,
        destroy = function()
            screenGui:Destroy()
            blur:Destroy()
            cc:Destroy()
        end,
    }
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

- `waterType`: "lake" | "river" | "ocean" | "waterfall" | "pond" | "swamp" -- 물 타입
- `preset`: "ocean" | "tropicalOcean" | "lake" | "swamp" | "river" | "arctic" | "lava" -- 물 프리셋
- `center`: {x: number, y: number, z: number} -- 중심 위치
- `size`: {x: number, y: number, z: number} -- 크기 (studs)
- `radius`: number -- 호수/연못 반경
- `depth`: number -- 깊이
- `waypoints`: [{x, y, z}] -- 강 경유점 목록
- `width`: number -- 강/폭포 너비
- `waterColor`: {r: number, g: number, b: number} -- 물 색상
- `transparency`: number -- 물 투명도 (0-1)
- `waveSize`: number -- 파도 크기
- `mist`: boolean -- 폭포 안개 효과
- `swimming`: boolean -- 수영 시스템 활성화
