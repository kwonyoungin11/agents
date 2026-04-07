---
name: lighting
description: |
  Roblox 조명 시스템 스킬. PointLight, SpotLight, SurfaceLight 생성, Lighting 서비스 설정,
  시간대별 프리셋(낮/밤/새벽/황혼), 실내/실외 조명 패턴, 포스트프로세싱(Bloom, ColorCorrection,
  SunRays, DepthOfField, Atmosphere) 설정을 수행합니다.
  키워드: 조명, 빛, 라이트, 라이팅, 포인트라이트, 스포트라이트, 서피스라이트, 블룸, 분위기,
  색보정, 안개, 햇살, 피사계심도, 대기, 낮, 밤, 새벽, 황혼, 실내조명, 실외조명, 포스트프로세싱,
  light, lighting, bloom, atmosphere, sun, rays, depth of field
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

# Lighting Skill

Roblox Studio에서 조명을 생성하고 Lighting 서비스를 구성하며 포스트프로세싱 효과를 적용하는 스킬입니다.

## Core Light Types

### PointLight (점 광원)
모든 방향으로 빛을 방출하는 광원. 램프, 횃불, 마법 오브 등에 사용.

```lua
local function createPointLight(parent: BasePart, config: {
    brightness: number?,
    color: Color3?,
    range: number?,
    shadows: boolean?,
    enabled: boolean?,
}): PointLight
    local light = Instance.new("PointLight")
    light.Brightness = config.brightness or 1
    light.Color = config.color or Color3.fromRGB(255, 255, 255)
    light.Range = config.range or 16
    light.Shadows = if config.shadows ~= nil then config.shadows else true
    light.Enabled = if config.enabled ~= nil then config.enabled else true
    light.Parent = parent
    return light
end
```

### SpotLight (스포트라이트)
원뿔 형태로 빛을 방출. 무대 조명, 손전등, 탐조등에 사용.

```lua
local function createSpotLight(parent: BasePart, config: {
    brightness: number?,
    color: Color3?,
    range: number?,
    angle: number?,
    face: Enum.NormalId?,
    shadows: boolean?,
}): SpotLight
    local light = Instance.new("SpotLight")
    light.Brightness = config.brightness or 1
    light.Color = config.color or Color3.fromRGB(255, 255, 255)
    light.Range = config.range or 16
    light.Angle = config.angle or 45
    light.Face = config.face or Enum.NormalId.Front
    light.Shadows = if config.shadows ~= nil then config.shadows else true
    light.Parent = parent
    return light
end
```

### SurfaceLight (표면 광원)
파트의 한 면에서 넓게 빛을 방출. 네온 사인, 천장 패널, 벽 조명에 사용.

```lua
local function createSurfaceLight(parent: BasePart, config: {
    brightness: number?,
    color: Color3?,
    range: number?,
    angle: number?,
    face: Enum.NormalId?,
    shadows: boolean?,
}): SurfaceLight
    local light = Instance.new("SurfaceLight")
    light.Brightness = config.brightness or 1
    light.Color = config.color or Color3.fromRGB(255, 255, 255)
    light.Range = config.range or 16
    light.Angle = config.angle or 90
    light.Face = config.face or Enum.NormalId.Bottom
    light.Shadows = if config.shadows ~= nil then config.shadows else true
    light.Parent = parent
    return light
end
```

## Lighting Service Configuration

### Time-of-Day Presets

```lua
local Lighting = game:GetService("Lighting")

local TIME_PRESETS = {
    dawn = {
        ClockTime = 6,
        Brightness = 1,
        Ambient = Color3.fromRGB(130, 100, 70),
        OutdoorAmbient = Color3.fromRGB(130, 100, 70),
        ColorShift_Top = Color3.fromRGB(255, 180, 100),
        ColorShift_Bottom = Color3.fromRGB(60, 40, 80),
        EnvironmentDiffuseScale = 0.5,
        EnvironmentSpecularScale = 0.5,
        GeographicLatitude = 30,
    },
    morning = {
        ClockTime = 9,
        Brightness = 2,
        Ambient = Color3.fromRGB(150, 150, 140),
        OutdoorAmbient = Color3.fromRGB(150, 150, 140),
        ColorShift_Top = Color3.fromRGB(255, 240, 210),
        ColorShift_Bottom = Color3.fromRGB(100, 100, 120),
        EnvironmentDiffuseScale = 1,
        EnvironmentSpecularScale = 1,
        GeographicLatitude = 30,
    },
    noon = {
        ClockTime = 12,
        Brightness = 3,
        Ambient = Color3.fromRGB(170, 170, 170),
        OutdoorAmbient = Color3.fromRGB(170, 170, 170),
        ColorShift_Top = Color3.fromRGB(255, 255, 245),
        ColorShift_Bottom = Color3.fromRGB(120, 120, 140),
        EnvironmentDiffuseScale = 1,
        EnvironmentSpecularScale = 1,
        GeographicLatitude = 0,
    },
    sunset = {
        ClockTime = 18,
        Brightness = 1.5,
        Ambient = Color3.fromRGB(140, 100, 80),
        OutdoorAmbient = Color3.fromRGB(140, 100, 80),
        ColorShift_Top = Color3.fromRGB(255, 140, 60),
        ColorShift_Bottom = Color3.fromRGB(80, 40, 100),
        EnvironmentDiffuseScale = 0.6,
        EnvironmentSpecularScale = 0.6,
        GeographicLatitude = 30,
    },
    dusk = {
        ClockTime = 19.5,
        Brightness = 0.5,
        Ambient = Color3.fromRGB(80, 60, 100),
        OutdoorAmbient = Color3.fromRGB(80, 60, 100),
        ColorShift_Top = Color3.fromRGB(180, 100, 60),
        ColorShift_Bottom = Color3.fromRGB(40, 20, 60),
        EnvironmentDiffuseScale = 0.3,
        EnvironmentSpecularScale = 0.3,
        GeographicLatitude = 30,
    },
    night = {
        ClockTime = 0,
        Brightness = 0,
        Ambient = Color3.fromRGB(30, 30, 50),
        OutdoorAmbient = Color3.fromRGB(30, 30, 50),
        ColorShift_Top = Color3.fromRGB(60, 60, 100),
        ColorShift_Bottom = Color3.fromRGB(10, 10, 30),
        EnvironmentDiffuseScale = 0.1,
        EnvironmentSpecularScale = 0.1,
        GeographicLatitude = 30,
    },
    midnight = {
        ClockTime = 0,
        Brightness = 0,
        Ambient = Color3.fromRGB(15, 15, 30),
        OutdoorAmbient = Color3.fromRGB(15, 15, 30),
        ColorShift_Top = Color3.fromRGB(30, 30, 60),
        ColorShift_Bottom = Color3.fromRGB(5, 5, 15),
        EnvironmentDiffuseScale = 0.05,
        EnvironmentSpecularScale = 0.05,
        GeographicLatitude = 30,
    },
}

local function applyTimePreset(presetName: string)
    local preset = TIME_PRESETS[presetName]
    if not preset then
        warn("Unknown preset: " .. presetName)
        return
    end
    for prop, value in pairs(preset) do
        Lighting[prop] = value
    end
end
```

### Smooth Time Transition

```lua
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")

local function transitionToPreset(presetName: string, duration: number?)
    local preset = TIME_PRESETS[presetName]
    if not preset then return end

    local tweenDuration = duration or 3
    local tweenInfo = TweenInfo.new(tweenDuration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)

    local targetTime = preset.ClockTime
    local props = {}
    for prop, value in pairs(preset) do
        if prop ~= "ClockTime" then
            props[prop] = value
        end
    end

    local tween = TweenService:Create(Lighting, tweenInfo, props)
    tween:Play()

    -- Animate ClockTime separately to handle wraparound
    local startTime = Lighting.ClockTime
    local elapsed = 0
    local heartbeat
    heartbeat = game:GetService("RunService").Heartbeat:Connect(function(dt)
        elapsed += dt
        local alpha = math.clamp(elapsed / tweenDuration, 0, 1)
        alpha = alpha * alpha * (3 - 2 * alpha)
        Lighting.ClockTime = startTime + (targetTime - startTime) * alpha
        if alpha >= 1 then
            heartbeat:Disconnect()
        end
    end)
end
```

## Indoor / Outdoor Lighting Patterns

### Indoor Room Lighting

```lua
local function setupIndoorLighting(room: Model)
    local ceiling = room:FindFirstChild("Ceiling")
    if ceiling and ceiling:IsA("BasePart") then
        local surfaceLight = Instance.new("SurfaceLight")
        surfaceLight.Face = Enum.NormalId.Bottom
        surfaceLight.Brightness = 1.5
        surfaceLight.Color = Color3.fromRGB(255, 244, 229)
        surfaceLight.Range = 30
        surfaceLight.Angle = 120
        surfaceLight.Shadows = true
        surfaceLight.Parent = ceiling
    end

    for _, part in ipairs(room:GetDescendants()) do
        if part:IsA("BasePart") and part.Name == "CornerLight" then
            local pointLight = Instance.new("PointLight")
            pointLight.Brightness = 0.5
            pointLight.Color = Color3.fromRGB(255, 244, 229)
            pointLight.Range = 20
            pointLight.Shadows = false
            pointLight.Parent = part
        end
    end
end
```

### Outdoor Street Lamp

```lua
local function createStreetLamp(position: Vector3, height: number?): Model
    local lampHeight = height or 15
    local model = Instance.new("Model")
    model.Name = "StreetLamp"

    local pole = Instance.new("Part")
    pole.Name = "Pole"
    pole.Shape = Enum.PartType.Cylinder
    pole.Size = Vector3.new(lampHeight, 0.5, 0.5)
    pole.CFrame = CFrame.new(position + Vector3.new(0, lampHeight / 2, 0))
        * CFrame.Angles(0, 0, math.rad(90))
    pole.Material = Enum.Material.Metal
    pole.Color = Color3.fromRGB(60, 60, 60)
    pole.Anchored = true
    pole.Parent = model

    local head = Instance.new("Part")
    head.Name = "LampHead"
    head.Size = Vector3.new(2, 1, 2)
    head.CFrame = CFrame.new(position + Vector3.new(0, lampHeight + 0.5, 0))
    head.Material = Enum.Material.Metal
    head.Color = Color3.fromRGB(60, 60, 60)
    head.Anchored = true
    head.Parent = model

    local bulb = Instance.new("Part")
    bulb.Name = "Bulb"
    bulb.Shape = Enum.PartType.Ball
    bulb.Size = Vector3.new(1, 1, 1)
    bulb.CFrame = CFrame.new(position + Vector3.new(0, lampHeight, 0))
    bulb.Material = Enum.Material.Neon
    bulb.Color = Color3.fromRGB(255, 220, 150)
    bulb.Anchored = true
    bulb.Transparency = 0.3
    bulb.Parent = model

    local spotLight = Instance.new("SpotLight")
    spotLight.Brightness = 3
    spotLight.Color = Color3.fromRGB(255, 220, 150)
    spotLight.Range = 40
    spotLight.Angle = 60
    spotLight.Face = Enum.NormalId.Bottom
    spotLight.Shadows = true
    spotLight.Parent = head

    local pointLight = Instance.new("PointLight")
    pointLight.Brightness = 0.8
    pointLight.Color = Color3.fromRGB(255, 220, 150)
    pointLight.Range = 20
    pointLight.Shadows = false
    pointLight.Parent = bulb

    model.PrimaryPart = pole
    model.Parent = workspace
    return model
end
```

## Post-Processing Effects

### Bloom

```lua
local function createBloom(config: {
    intensity: number?,
    size: number?,
    threshold: number?,
    enabled: boolean?,
}): BloomEffect
    local Lighting = game:GetService("Lighting")
    local existing = Lighting:FindFirstChildOfClass("BloomEffect")
    if existing then existing:Destroy() end

    local bloom = Instance.new("BloomEffect")
    bloom.Intensity = config.intensity or 0.5
    bloom.Size = config.size or 24
    bloom.Threshold = config.threshold or 1.5
    bloom.Enabled = if config.enabled ~= nil then config.enabled else true
    bloom.Parent = Lighting
    return bloom
end
```

### ColorCorrection

```lua
local function createColorCorrection(config: {
    brightness: number?,
    contrast: number?,
    saturation: number?,
    tintColor: Color3?,
    enabled: boolean?,
}): ColorCorrectionEffect
    local Lighting = game:GetService("Lighting")
    local existing = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
    if existing then existing:Destroy() end

    local cc = Instance.new("ColorCorrectionEffect")
    cc.Brightness = config.brightness or 0
    cc.Contrast = config.contrast or 0
    cc.Saturation = config.saturation or 0
    cc.TintColor = config.tintColor or Color3.fromRGB(255, 255, 255)
    cc.Enabled = if config.enabled ~= nil then config.enabled else true
    cc.Parent = Lighting
    return cc
end
```

### SunRays

```lua
local function createSunRays(config: {
    intensity: number?,
    spread: number?,
    enabled: boolean?,
}): SunRaysEffect
    local Lighting = game:GetService("Lighting")
    local existing = Lighting:FindFirstChildOfClass("SunRaysEffect")
    if existing then existing:Destroy() end

    local sunRays = Instance.new("SunRaysEffect")
    sunRays.Intensity = config.intensity or 0.1
    sunRays.Spread = config.spread or 0.5
    sunRays.Enabled = if config.enabled ~= nil then config.enabled else true
    sunRays.Parent = Lighting
    return sunRays
end
```

### DepthOfField

```lua
local function createDepthOfField(config: {
    farIntensity: number?,
    focusDistance: number?,
    inFocusRadius: number?,
    nearIntensity: number?,
    enabled: boolean?,
}): DepthOfFieldEffect
    local Lighting = game:GetService("Lighting")
    local existing = Lighting:FindFirstChildOfClass("DepthOfFieldEffect")
    if existing then existing:Destroy() end

    local dof = Instance.new("DepthOfFieldEffect")
    dof.FarIntensity = config.farIntensity or 0.3
    dof.FocusDistance = config.focusDistance or 50
    dof.InFocusRadius = config.inFocusRadius or 30
    dof.NearIntensity = config.nearIntensity or 0.5
    dof.Enabled = if config.enabled ~= nil then config.enabled else true
    dof.Parent = Lighting
    return dof
end
```

### Atmosphere

```lua
local function createAtmosphere(config: {
    density: number?,
    offset: number?,
    color: Color3?,
    decay: Color3?,
    glare: number?,
    haze: number?,
    enabled: boolean?,
}): Atmosphere
    local Lighting = game:GetService("Lighting")
    local existing = Lighting:FindFirstChildOfClass("Atmosphere")
    if existing then existing:Destroy() end

    local atmo = Instance.new("Atmosphere")
    atmo.Density = config.density or 0.3
    atmo.Offset = config.offset or 0.25
    atmo.Color = config.color or Color3.fromRGB(199, 199, 199)
    atmo.Decay = config.decay or Color3.fromRGB(92, 60, 13)
    atmo.Glare = config.glare or 0
    atmo.Haze = config.haze or 0
    atmo.Enabled = if config.enabled ~= nil then config.enabled else true
    atmo.Parent = Lighting
    return atmo
end
```

## Themed Lighting Presets

### Horror Theme

```lua
local function applyHorrorLighting()
    local Lighting = game:GetService("Lighting")
    Lighting.ClockTime = 0
    Lighting.Brightness = 0
    Lighting.Ambient = Color3.fromRGB(10, 10, 15)
    Lighting.OutdoorAmbient = Color3.fromRGB(10, 10, 15)
    Lighting.FogColor = Color3.fromRGB(20, 15, 15)
    Lighting.FogEnd = 200
    Lighting.FogStart = 10

    createColorCorrection({
        brightness = -0.05,
        contrast = 0.2,
        saturation = -0.5,
        tintColor = Color3.fromRGB(200, 180, 180),
    })
    createBloom({ intensity = 0.8, size = 40, threshold = 0.8 })
    createAtmosphere({ density = 0.5, offset = 0, color = Color3.fromRGB(50, 30, 30), haze = 5 })
end
```

### Fantasy Theme

```lua
local function applyFantasyLighting()
    local Lighting = game:GetService("Lighting")
    Lighting.ClockTime = 16
    Lighting.Brightness = 2
    Lighting.Ambient = Color3.fromRGB(120, 100, 140)
    Lighting.OutdoorAmbient = Color3.fromRGB(120, 100, 140)
    Lighting.ColorShift_Top = Color3.fromRGB(255, 210, 160)

    createColorCorrection({
        brightness = 0.02,
        contrast = 0.15,
        saturation = 0.3,
        tintColor = Color3.fromRGB(255, 240, 230),
    })
    createBloom({ intensity = 0.6, size = 30, threshold = 1.2 })
    createSunRays({ intensity = 0.15, spread = 0.6 })
    createAtmosphere({
        density = 0.35,
        offset = 0.2,
        color = Color3.fromRGB(180, 160, 200),
        decay = Color3.fromRGB(100, 70, 30),
        glare = 0.1,
        haze = 1,
    })
end
```

### SciFi Theme

```lua
local function applySciFiLighting()
    local Lighting = game:GetService("Lighting")
    Lighting.ClockTime = 14
    Lighting.Brightness = 1.5
    Lighting.Ambient = Color3.fromRGB(80, 100, 120)
    Lighting.OutdoorAmbient = Color3.fromRGB(80, 100, 120)

    createColorCorrection({
        brightness = 0,
        contrast = 0.25,
        saturation = -0.2,
        tintColor = Color3.fromRGB(200, 220, 255),
    })
    createBloom({ intensity = 0.4, size = 20, threshold = 1.0 })
    createDepthOfField({ farIntensity = 0.2, focusDistance = 80, inFocusRadius = 50, nearIntensity = 0.1 })
    createAtmosphere({
        density = 0.2,
        offset = 0.5,
        color = Color3.fromRGB(150, 170, 200),
        haze = 2,
    })
end
```

## Complete Lighting Setup

```lua
local function setupCompleteLighting(theme: string, timeOfDay: string)
    local Lighting = game:GetService("Lighting")

    if TIME_PRESETS[timeOfDay] then
        applyTimePreset(timeOfDay)
    end

    if theme == "horror" then
        applyHorrorLighting()
    elseif theme == "fantasy" then
        applyFantasyLighting()
    elseif theme == "scifi" then
        applySciFiLighting()
    else
        createBloom({ intensity = 0.3, size = 24, threshold = 1.5 })
        createColorCorrection({ brightness = 0, contrast = 0.1, saturation = 0.1 })
        createSunRays({ intensity = 0.1, spread = 0.5 })
        createAtmosphere({ density = 0.3, offset = 0.25 })
    end

    Lighting.GlobalShadows = true
    Lighting.Technology = Enum.Technology.Future
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

- `lightType`: "PointLight" | "SpotLight" | "SurfaceLight" -- 생성할 조명 타입
- `preset`: "dawn" | "morning" | "noon" | "sunset" | "dusk" | "night" | "midnight" -- 시간대 프리셋
- `theme`: "horror" | "fantasy" | "scifi" | "default" -- 테마별 조명
- `brightness`: number -- 밝기 (0~10)
- `color`: {r: number, g: number, b: number} -- 조명 색상 RGB
- `range`: number -- 조명 범위 (studs)
- `shadows`: boolean -- 그림자 활성화 여부
- `postProcessing`: { bloom, colorCorrection, sunRays, depthOfField, atmosphere } -- 포스트프로세싱
- `transition`: boolean -- 부드러운 전환 사용 여부
- `transitionDuration`: number -- 전환 시간 (초)
