---
name: weather
description: |
  Roblox 날씨 시스템 스킬. 스카이박스 설정, 낮/밤 주기, 비/눈/안개/폭풍 파티클 시스템,
  동적 날씨 전환, 번개 플래시 효과를 구현합니다.
  키워드: 날씨, 비, 눈, 안개, 폭풍, 구름, 번개, 천둥, 스카이박스, 낮밤, 주기, 하늘,
  태양, 달, 폭우, 눈보라, 안개, 무지개, 바람, 기상,
  weather, rain, snow, fog, storm, cloud, lightning, thunder, skybox, day night cycle
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

# Weather Skill

Roblox에서 날씨 시스템을 구현하는 스킬. 스카이박스, 낮/밤 주기, 파티클 기반 기상 효과를 다룹니다.

## Skybox Configuration

### Basic Skybox Setup
```lua
local Lighting = game:GetService("Lighting")

local function createSkybox(textureIds: {
    top: string,
    bottom: string,
    left: string,
    right: string,
    front: string,
    back: string,
}): Sky
    local existing = Lighting:FindFirstChildOfClass("Sky")
    if existing then existing:Destroy() end

    local sky = Instance.new("Sky")
    sky.SkyboxBk = textureIds.back
    sky.SkyboxDn = textureIds.bottom
    sky.SkyboxFt = textureIds.front
    sky.SkyboxLf = textureIds.left
    sky.SkyboxRt = textureIds.right
    sky.SkyboxUp = textureIds.top
    sky.StarCount = 3000
    sky.MoonAngularSize = 11
    sky.SunAngularSize = 21
    sky.CelestialBodiesShown = true
    sky.Parent = Lighting
    return sky
end
```

### Skybox Presets
```lua
local SKYBOX_PRESETS = {
    clearDay = {
        top    = "rbxassetid://6444884337",
        bottom = "rbxassetid://6444884337",
        left   = "rbxassetid://6444884337",
        right  = "rbxassetid://6444884337",
        front  = "rbxassetid://6444884337",
        back   = "rbxassetid://6444884337",
    },
    stormy = {
        top    = "rbxassetid://1041997251",
        bottom = "rbxassetid://1041997251",
        left   = "rbxassetid://1041997251",
        right  = "rbxassetid://1041997251",
        front  = "rbxassetid://1041997251",
        back   = "rbxassetid://1041997251",
    },
    night = {
        top    = "rbxassetid://12064107",
        bottom = "rbxassetid://12064107",
        left   = "rbxassetid://12064107",
        right  = "rbxassetid://12064107",
        front  = "rbxassetid://12064107",
        back   = "rbxassetid://12064107",
    },
}

local function applySkyboxPreset(presetName: string)
    local preset = SKYBOX_PRESETS[presetName]
    if preset then
        createSkybox(preset)
    end
end
```

## Day/Night Cycle

### Continuous Day/Night Cycle
```lua
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")

local DayNightCycle = {}
DayNightCycle.__index = DayNightCycle

function DayNightCycle.new(config: {
    cycleDurationMinutes: number?,  -- Real minutes for a full 24h cycle
    startTime: number?,             -- Starting ClockTime (0-24)
    paused: boolean?,
})
    local self = setmetatable({}, DayNightCycle)
    self.cycleDuration = (config.cycleDurationMinutes or 20) * 60
    self.currentTime = config.startTime or 12
    self.paused = config.paused or false
    self._connection = nil
    return self
end

function DayNightCycle:start()
    if self._connection then return end

    self._connection = RunService.Heartbeat:Connect(function(dt)
        if self.paused then return end

        -- 24 game hours per cycleDuration real seconds
        local hoursPerSecond = 24 / self.cycleDuration
        self.currentTime = (self.currentTime + dt * hoursPerSecond) % 24
        Lighting.ClockTime = self.currentTime

        -- Dynamic ambient based on time
        self:_updateAmbient()
    end)
end

function DayNightCycle:stop()
    if self._connection then
        self._connection:Disconnect()
        self._connection = nil
    end
end

function DayNightCycle:setTime(clockTime: number)
    self.currentTime = clockTime % 24
    Lighting.ClockTime = self.currentTime
end

function DayNightCycle:_updateAmbient()
    local t = self.currentTime
    local brightness, ambientR, ambientG, ambientB

    if t >= 6 and t < 8 then -- dawn
        local alpha = (t - 6) / 2
        brightness = alpha * 2
        ambientR = 80 + alpha * 90
        ambientG = 60 + alpha * 90
        ambientB = 40 + alpha * 110
    elseif t >= 8 and t < 16 then -- day
        brightness = 2 + math.sin((t - 8) / 8 * math.pi) * 1
        ambientR = 170
        ambientG = 170
        ambientB = 170
    elseif t >= 16 and t < 18 then -- sunset
        local alpha = 1 - (t - 16) / 2
        brightness = alpha * 2
        ambientR = 80 + alpha * 90
        ambientG = 60 + alpha * 60
        ambientB = 40 + alpha * 60
    else -- night
        brightness = 0
        ambientR = 20
        ambientG = 20
        ambientB = 40
    end

    Lighting.Brightness = brightness
    Lighting.Ambient = Color3.fromRGB(ambientR, ambientG, ambientB)
    Lighting.OutdoorAmbient = Color3.fromRGB(ambientR, ambientG, ambientB)
end

-- Usage:
-- local cycle = DayNightCycle.new({ cycleDurationMinutes = 20, startTime = 6 })
-- cycle:start()
```

## Rain System

### Particle-Based Rain
```lua
local function createRainSystem(config: {
    intensity: number?,     -- 1-10 scale
    color: Color3?,
    windAngle: number?,     -- degrees of wind tilt
    soundId: string?,
}): { emitter: ParticleEmitter, attachment: Attachment, part: Part, sound: Sound? }
    local intensity = config.intensity or 5
    local windAngle = config.windAngle or 10

    -- Rain container part (large, invisible, high above)
    local rainPart = Instance.new("Part")
    rainPart.Name = "RainEmitter"
    rainPart.Size = Vector3.new(200, 1, 200)
    rainPart.Position = Vector3.new(0, 150, 0)
    rainPart.Anchored = true
    rainPart.CanCollide = false
    rainPart.Transparency = 1
    rainPart.Parent = workspace

    local attachment = Instance.new("Attachment")
    attachment.Parent = rainPart

    local emitter = Instance.new("ParticleEmitter")
    emitter.Name = "Rain"
    emitter.Texture = "rbxassetid://241685484" -- raindrop texture
    emitter.Color = ColorSequence.new(config.color or Color3.fromRGB(180, 200, 220))
    emitter.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.05),
        NumberSequenceKeypoint.new(1, 0.02),
    })
    emitter.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.3),
        NumberSequenceKeypoint.new(0.8, 0.3),
        NumberSequenceKeypoint.new(1, 1),
    })
    emitter.Lifetime = NumberRange.new(0.8, 1.2)
    emitter.Rate = intensity * 500
    emitter.Speed = NumberRange.new(80, 120)
    emitter.SpreadAngle = Vector2.new(5, 5)
    emitter.Acceleration = Vector3.new(
        math.sin(math.rad(windAngle)) * 20,
        0,
        math.cos(math.rad(windAngle)) * 5
    )
    emitter.EmissionDirection = Enum.NormalId.Bottom
    emitter.RotSpeed = NumberRange.new(0, 0)
    emitter.Parent = attachment

    -- Rain sound
    local sound = nil
    if config.soundId then
        sound = Instance.new("Sound")
        sound.SoundId = config.soundId
        sound.Volume = math.clamp(intensity / 10, 0.1, 1)
        sound.Looped = true
        sound.Parent = rainPart
        sound:Play()
    end

    -- Darken environment for rain
    local Lighting = game:GetService("Lighting")
    Lighting.Brightness = math.max(Lighting.Brightness - intensity * 0.15, 0)

    return { emitter = emitter, attachment = attachment, part = rainPart, sound = sound }
end
```

### Rain Splash on Ground
```lua
local function createRainSplashes(config: {
    area: Vector3?,
    center: Vector3?,
    rate: number?,
}): { emitter: ParticleEmitter, part: Part }
    local area = config.area or Vector3.new(200, 1, 200)

    local splashPart = Instance.new("Part")
    splashPart.Name = "RainSplashes"
    splashPart.Size = area
    splashPart.Position = config.center or Vector3.new(0, 0.5, 0)
    splashPart.Anchored = true
    splashPart.CanCollide = false
    splashPart.Transparency = 1
    splashPart.Parent = workspace

    local attachment = Instance.new("Attachment")
    attachment.Parent = splashPart

    local emitter = Instance.new("ParticleEmitter")
    emitter.Name = "Splashes"
    emitter.Texture = "rbxassetid://241685484"
    emitter.Color = ColorSequence.new(Color3.fromRGB(200, 210, 220))
    emitter.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0),
        NumberSequenceKeypoint.new(0.3, 0.3),
        NumberSequenceKeypoint.new(1, 0),
    })
    emitter.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.5),
        NumberSequenceKeypoint.new(1, 1),
    })
    emitter.Lifetime = NumberRange.new(0.2, 0.4)
    emitter.Rate = config.rate or 200
    emitter.Speed = NumberRange.new(2, 5)
    emitter.SpreadAngle = Vector2.new(180, 180)
    emitter.EmissionDirection = Enum.NormalId.Top
    emitter.Parent = attachment

    return { emitter = emitter, part = splashPart }
end
```

## Snow System

```lua
local function createSnowSystem(config: {
    intensity: number?,
    windDirection: Vector3?,
    flakeSize: number?,
}): { emitter: ParticleEmitter, part: Part }
    local intensity = config.intensity or 5

    local snowPart = Instance.new("Part")
    snowPart.Name = "SnowEmitter"
    snowPart.Size = Vector3.new(250, 1, 250)
    snowPart.Position = Vector3.new(0, 120, 0)
    snowPart.Anchored = true
    snowPart.CanCollide = false
    snowPart.Transparency = 1
    snowPart.Parent = workspace

    local attachment = Instance.new("Attachment")
    attachment.Parent = snowPart

    local flakeSize = config.flakeSize or 0.15

    local emitter = Instance.new("ParticleEmitter")
    emitter.Name = "Snow"
    emitter.Texture = "rbxassetid://243098098" -- snowflake texture
    emitter.Color = ColorSequence.new(Color3.fromRGB(240, 245, 255))
    emitter.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, flakeSize * 0.5),
        NumberSequenceKeypoint.new(0.5, flakeSize),
        NumberSequenceKeypoint.new(1, flakeSize * 0.8),
    })
    emitter.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0),
        NumberSequenceKeypoint.new(0.7, 0.1),
        NumberSequenceKeypoint.new(1, 1),
    })
    emitter.Lifetime = NumberRange.new(4, 8)
    emitter.Rate = intensity * 100
    emitter.Speed = NumberRange.new(5, 15)
    emitter.SpreadAngle = Vector2.new(30, 30)
    emitter.Acceleration = config.windDirection or Vector3.new(3, 0, 1)
    emitter.EmissionDirection = Enum.NormalId.Bottom
    emitter.Rotation = NumberRange.new(0, 360)
    emitter.RotSpeed = NumberRange.new(-60, 60)
    emitter.Parent = attachment

    return { emitter = emitter, part = snowPart }
end
```

## Fog System

```lua
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")

local function applyFog(config: {
    density: number?,     -- 0-1 scale
    color: Color3?,
    transitionTime: number?,
}): Atmosphere
    local density = config.density or 0.5
    local transitionTime = config.transitionTime or 2

    -- Atmosphere-based fog
    local atmo = Lighting:FindFirstChildOfClass("Atmosphere")
    if not atmo then
        atmo = Instance.new("Atmosphere")
        atmo.Parent = Lighting
    end

    local targetProps = {
        Density = density * 0.8,
        Offset = 0,
        Color = config.color or Color3.fromRGB(180, 180, 190),
        Decay = Color3.fromRGB(120, 120, 130),
        Haze = density * 10,
        Glare = 0,
    }

    local tween = TweenService:Create(atmo, TweenInfo.new(transitionTime, Enum.EasingStyle.Sine), targetProps)
    tween:Play()

    -- Also set legacy fog for compatibility
    Lighting.FogColor = config.color or Color3.fromRGB(180, 180, 190)
    Lighting.FogStart = (1 - density) * 100
    Lighting.FogEnd = (1 - density) * 500 + 100

    return atmo
end

local function clearFog(transitionTime: number?)
    local Lighting = game:GetService("Lighting")
    local atmo = Lighting:FindFirstChildOfClass("Atmosphere")
    if atmo then
        local tween = TweenService:Create(atmo, TweenInfo.new(transitionTime or 2, Enum.EasingStyle.Sine), {
            Density = 0.3,
            Haze = 0,
            Offset = 0.25,
        })
        tween:Play()
    end
    Lighting.FogEnd = 100000
    Lighting.FogStart = 0
end
```

## Storm System

### Complete Storm with Lightning
```lua
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")

local StormSystem = {}
StormSystem.__index = StormSystem

function StormSystem.new(config: {
    intensity: number?,        -- 1-10
    lightningEnabled: boolean?,
    thunderSoundId: string?,
    windSoundId: string?,
})
    local self = setmetatable({}, StormSystem)
    self.intensity = config.intensity or 7
    self.lightningEnabled = if config.lightningEnabled ~= nil then config.lightningEnabled else true
    self.thunderSoundId = config.thunderSoundId
    self.windSoundId = config.windSoundId
    self._active = false
    self._connections = {}
    self._parts = {}
    return self
end

function StormSystem:start()
    if self._active then return end
    self._active = true

    -- Darken sky
    self:_darkenSky()

    -- Start rain
    self._rain = createRainSystem({
        intensity = self.intensity,
        windAngle = 25,
        soundId = "rbxassetid://9114488862",
    })
    table.insert(self._parts, self._rain.part)

    -- Start rain splashes
    self._splashes = createRainSplashes({ rate = self.intensity * 50 })
    table.insert(self._parts, self._splashes.part)

    -- Heavy fog
    applyFog({ density = self.intensity / 15, color = Color3.fromRGB(100, 100, 110) })

    -- Lightning loop
    if self.lightningEnabled then
        self:_startLightning()
    end

    -- Wind sound
    if self.windSoundId then
        local windSound = Instance.new("Sound")
        windSound.SoundId = self.windSoundId
        windSound.Volume = self.intensity / 10
        windSound.Looped = true
        windSound.Parent = workspace
        windSound:Play()
        self._windSound = windSound
    end
end

function StormSystem:stop()
    self._active = false

    for _, conn in ipairs(self._connections) do
        conn:Disconnect()
    end
    self._connections = {}

    for _, part in ipairs(self._parts) do
        part:Destroy()
    end
    self._parts = {}

    if self._windSound then
        self._windSound:Destroy()
    end

    clearFog(3)
    self:_restoreSky()
end

function StormSystem:_darkenSky()
    self._savedBrightness = Lighting.Brightness
    self._savedAmbient = Lighting.Ambient

    TweenService:Create(Lighting, TweenInfo.new(3), {
        Brightness = 0.5,
        Ambient = Color3.fromRGB(40, 40, 50),
        OutdoorAmbient = Color3.fromRGB(40, 40, 50),
    }):Play()
end

function StormSystem:_restoreSky()
    TweenService:Create(Lighting, TweenInfo.new(3), {
        Brightness = self._savedBrightness or 2,
        Ambient = self._savedAmbient or Color3.fromRGB(150, 150, 150),
        OutdoorAmbient = self._savedAmbient or Color3.fromRGB(150, 150, 150),
    }):Play()
end

function StormSystem:_startLightning()
    task.spawn(function()
        while self._active do
            local waitTime = math.random(3, math.max(4, math.floor(20 / self.intensity)))
            task.wait(waitTime)
            if not self._active then break end
            self:_flashLightning()
        end
    end)
end

function StormSystem:_flashLightning()
    local originalBrightness = Lighting.Brightness
    local originalAmbient = Lighting.Ambient

    -- Flash 1
    Lighting.Brightness = 8
    Lighting.Ambient = Color3.fromRGB(220, 220, 255)
    task.wait(0.05)
    Lighting.Brightness = originalBrightness
    Lighting.Ambient = originalAmbient
    task.wait(0.1)

    -- Flash 2 (afterflash)
    Lighting.Brightness = 5
    Lighting.Ambient = Color3.fromRGB(180, 180, 220)
    task.wait(0.08)
    Lighting.Brightness = originalBrightness
    Lighting.Ambient = originalAmbient

    -- Thunder sound after delay (sound travels slower than light)
    if self.thunderSoundId then
        task.delay(math.random() * 2 + 0.5, function()
            local thunder = Instance.new("Sound")
            thunder.SoundId = self.thunderSoundId
            thunder.Volume = math.random(5, 10) / 10
            thunder.Parent = workspace
            thunder:Play()
            thunder.Ended:Once(function()
                thunder:Destroy()
            end)
        end)
    end
end

-- Usage:
-- local storm = StormSystem.new({ intensity = 8, lightningEnabled = true })
-- storm:start()
-- task.wait(60)
-- storm:stop()
```

## Dynamic Weather Switching

```lua
local WeatherManager = {}
WeatherManager.__index = WeatherManager

function WeatherManager.new()
    local self = setmetatable({}, WeatherManager)
    self.currentWeather = "clear"
    self._activeSystems = {}
    return self
end

function WeatherManager:setWeather(weatherType: string, config: { [string]: any }?)
    -- Clean up current weather
    self:_cleanup()

    self.currentWeather = weatherType
    config = config or {}

    if weatherType == "clear" then
        clearFog(2)
        local Lighting = game:GetService("Lighting")
        Lighting.Brightness = 2
        Lighting.Ambient = Color3.fromRGB(150, 150, 150)

    elseif weatherType == "rain" then
        self._activeSystems.rain = createRainSystem({
            intensity = config.intensity or 5,
        })
        self._activeSystems.splashes = createRainSplashes({})
        applyFog({ density = 0.2 })

    elseif weatherType == "snow" then
        self._activeSystems.snow = createSnowSystem({
            intensity = config.intensity or 5,
        })
        applyFog({ density = 0.15, color = Color3.fromRGB(220, 225, 235) })

    elseif weatherType == "fog" then
        applyFog({ density = config.density or 0.6 })

    elseif weatherType == "storm" then
        local storm = StormSystem.new({
            intensity = config.intensity or 8,
            lightningEnabled = true,
        })
        storm:start()
        self._activeSystems.storm = storm
    end
end

function WeatherManager:_cleanup()
    for key, system in pairs(self._activeSystems) do
        if type(system) == "table" then
            if system.stop then
                system:stop()
            end
            if system.part then
                system.part:Destroy()
            end
        end
    end
    self._activeSystems = {}
end

-- Usage:
-- local weather = WeatherManager.new()
-- weather:setWeather("rain", { intensity = 6 })
-- task.wait(30)
-- weather:setWeather("storm", { intensity = 9 })
-- task.wait(30)
-- weather:setWeather("clear")
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

- `weatherType`: "clear" | "rain" | "snow" | "fog" | "storm" -- 날씨 타입
- `intensity`: number -- 강도 (1-10)
- `dayNightCycle`: boolean -- 낮/밤 주기 활성화
- `cycleDuration`: number -- 주기 길이 (분)
- `startTime`: number -- 시작 시각 (0-24)
- `skyboxPreset`: "clearDay" | "stormy" | "night" -- 스카이박스 프리셋
- `fogDensity`: number -- 안개 밀도 (0-1)
- `fogColor`: {r: number, g: number, b: number} -- 안개 색상
- `lightningEnabled`: boolean -- 번개 활성화
- `windAngle`: number -- 바람 각도 (도)
- `transitionTime`: number -- 전환 시간 (초)
