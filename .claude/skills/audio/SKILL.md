---
name: audio
description: >
  Roblox 사운드/음악 전문가. 3D 공간 사운드, BGM, 환경음, SoundGroup, 페이드,
  발소리 시스템, 전투음, 동적 음악 시스템을 완벽히 구현.
  소리, 음악, BGM, 효과음, 사운드, 발소리, 환경음, 오디오 요청 시 자동 발동.
allowed-tools: Agent Read Grep Glob Bash
effort: high
---

# Audio Agent — Roblox 사운드 전문가

게임의 모든 소리를 설계한다. **소리가 없는 게임은 50%만 완성된 게임이다.**

---

## Sound 기본

### 3D 공간 사운드 (위치 기반)
```lua
local function play3DSound(parent, soundId, config)
    config = config or {}
    local sound = Instance.new("Sound")
    sound.SoundId = "rbxassetid://" .. soundId
    sound.Volume = config.volume or 1
    sound.PlaybackSpeed = config.speed or 1
    sound.Looped = config.looped or false
    sound.RollOffMode = config.rollOff or Enum.RollOffMode.Linear
    sound.RollOffMinDistance = config.minDist or 10
    sound.RollOffMaxDistance = config.maxDist or 100
    sound.Parent = parent  -- 3D 위치는 부모 파트 기준
    sound:Play()
    
    if not config.looped then
        sound.Ended:Once(function() sound:Destroy() end)
    end
    return sound
end
```

### 2D 사운드 (위치 무관 — BGM, UI)
```lua
local function play2DSound(soundId, config)
    config = config or {}
    local sound = Instance.new("Sound")
    sound.SoundId = "rbxassetid://" .. soundId
    sound.Volume = config.volume or 0.5
    sound.Looped = config.looped or false
    sound.PlaybackSpeed = config.speed or 1
    sound.Parent = game:GetService("SoundService")  -- 2D
    sound:Play()
    return sound
end
```

### RollOffMode 선택
```
Linear       — 거리에 비례하여 선형 감소 (가장 예측 가능)
InverseTapered — 가까이서 크고 멀면 급격히 줄어듦 (기본값, 현실적)
Inverse      — 1/거리 비례 (극단적)
```

---

## SoundGroup (볼륨 그룹 관리)

```lua
local SoundService = game:GetService("SoundService")

local function createSoundGroups()
    local groups = {}
    
    local function makeGroup(name, volume)
        local g = Instance.new("SoundGroup")
        g.Name = name; g.Volume = volume
        g.Parent = SoundService
        groups[name] = g
        return g
    end
    
    groups.Master = makeGroup("Master", 1)
    groups.Music  = makeGroup("Music", 0.5)
    groups.SFX    = makeGroup("SFX", 1)
    groups.Ambient = makeGroup("Ambient", 0.6)
    groups.UI     = makeGroup("UI", 0.8)
    groups.Voice  = makeGroup("Voice", 0.9)
    
    return groups
end

-- 사운드에 그룹 할당
sound.SoundGroup = groups.SFX
bgm.SoundGroup = groups.Music
```

---

## 페이드 시스템

```lua
local TweenService = game:GetService("TweenService")

local function fadeIn(sound, duration, targetVol)
    targetVol = targetVol or sound.Volume
    sound.Volume = 0
    sound:Play()
    TweenService:Create(sound, TweenInfo.new(duration or 1), {Volume = targetVol}):Play()
end

local function fadeOut(sound, duration, destroy)
    local tween = TweenService:Create(sound, TweenInfo.new(duration or 1), {Volume = 0})
    tween:Play()
    tween.Completed:Connect(function()
        sound:Stop()
        if destroy then sound:Destroy() end
    end)
end

local function crossFade(oldSound, newSound, duration)
    duration = duration or 1
    fadeOut(oldSound, duration)
    fadeIn(newSound, duration)
end
```

---

## BGM 시스템 (동적 음악)

```lua
local MusicSystem = {}
local currentBGM = nil
local musicFolder = nil

function MusicSystem.init()
    musicFolder = Instance.new("Folder")
    musicFolder.Name = "_MusicSystem"
    musicFolder.Parent = SoundService
end

function MusicSystem.play(soundId, config)
    config = config or {}
    
    -- 현재 음악 페이드아웃
    if currentBGM and currentBGM.IsPlaying then
        fadeOut(currentBGM, config.fadeDuration or 1, true)
    end
    
    -- 새 음악
    local bgm = Instance.new("Sound")
    bgm.SoundId = "rbxassetid://" .. soundId
    bgm.Volume = 0
    bgm.Looped = config.looped ~= false  -- 기본: 루프
    bgm.PlaybackSpeed = config.speed or 1
    bgm.Parent = musicFolder
    
    if config.soundGroup then
        bgm.SoundGroup = config.soundGroup
    end
    
    fadeIn(bgm, config.fadeDuration or 1, config.volume or 0.5)
    currentBGM = bgm
    return bgm
end

function MusicSystem.stop(fadeDuration)
    if currentBGM then
        fadeOut(currentBGM, fadeDuration or 1, true)
        currentBGM = nil
    end
end

function MusicSystem.setVolume(vol, duration)
    if currentBGM then
        TweenService:Create(currentBGM, TweenInfo.new(duration or 0.5),
            {Volume = vol}):Play()
    end
end
```

---

## 환경음 시스템

```lua
local AmbienceSystem = {}
local activeAmbience = {}

function AmbienceSystem.start(zoneName, sounds)
    AmbienceSystem.stop(zoneName)  -- 기존 것 제거
    
    activeAmbience[zoneName] = {}
    
    for name, config in sounds do
        local s = Instance.new("Sound")
        s.Name = zoneName .. "_" .. name
        s.SoundId = "rbxassetid://" .. config.id
        s.Volume = 0
        s.Looped = true
        s.RollOffMaxDistance = config.range or 200
        
        if config.parent then
            s.Parent = config.parent  -- 3D 위치
        else
            s.Parent = SoundService   -- 2D (전체)
        end
        
        fadeIn(s, 2, config.volume or 0.3)
        table.insert(activeAmbience[zoneName], s)
    end
end

function AmbienceSystem.stop(zoneName)
    if activeAmbience[zoneName] then
        for _, s in activeAmbience[zoneName] do
            fadeOut(s, 2, true)
        end
        activeAmbience[zoneName] = nil
    end
end

-- 환경별 프리셋
local ambiencePresets = {
    Forest = {
        Birds   = {id = "9120386436", volume = 0.2},
        Wind    = {id = "9120386437", volume = 0.15},
        Leaves  = {id = "9120386438", volume = 0.1},
    },
    Dungeon = {
        Drips   = {id = "6489420462", volume = 0.2},
        Wind    = {id = "9120386436", volume = 0.1},
        Creaks  = {id = "5206581680", volume = 0.08},
    },
    Ocean = {
        Waves   = {id = "9120386439", volume = 0.3},
        Seagull = {id = "9120386440", volume = 0.1},
        Wind    = {id = "9120386437", volume = 0.15},
    },
}
-- 참고: 실제 사운드 ID는 Creator Store에서 검색 필요
```

---

## 발소리 시스템

```lua
local function setupFootsteps(character)
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart")
    if not humanoid or not root then return end
    
    -- 재질별 발소리 (실제 ID는 Creator Store에서 검색)
    local sounds = {
        [Enum.Material.Grass]     = "rbxassetid://GRASS_ID",
        [Enum.Material.Concrete]  = "rbxassetid://CONCRETE_ID",
        [Enum.Material.Wood]      = "rbxassetid://WOOD_ID",
        [Enum.Material.Metal]     = "rbxassetid://METAL_ID",
        [Enum.Material.Sand]      = "rbxassetid://SAND_ID",
        [Enum.Material.Slate]     = "rbxassetid://STONE_ID",
    }
    local defaultSound = "rbxassetid://CONCRETE_ID"
    
    local stepInterval = 0.4
    local lastStep = 0
    
    humanoid.Running:Connect(function(speed)
        if speed < 1 then return end
        if tick() - lastStep < stepInterval then return end
        lastStep = tick()
        
        -- 레이캐스트로 바닥 재질 감지
        local params = RaycastParams.new()
        params.FilterDescendantsInstances = {character}
        local ray = workspace:Raycast(root.Position, Vector3.new(0, -5, 0), params)
        
        local soundId = defaultSound
        if ray then
            soundId = sounds[ray.Material] or defaultSound
        end
        
        local s = Instance.new("Sound")
        s.SoundId = soundId
        s.Volume = 0.3
        s.PlaybackSpeed = 0.9 + math.random() * 0.2  -- 약간의 랜덤
        s.RollOffMaxDistance = 30
        s.Parent = root
        s:Play()
        s.Ended:Once(function() s:Destroy() end)
    end)
end
```

---

## 전투/이펙트 효과음

```lua
local function playSFX(parent, soundId, config)
    config = config or {}
    local s = Instance.new("Sound")
    s.SoundId = "rbxassetid://" .. soundId
    s.Volume = config.volume or 0.8
    s.PlaybackSpeed = config.speed or (0.9 + math.random() * 0.2)  -- 약간 랜덤
    s.RollOffMaxDistance = config.range or 50
    s.Parent = parent or SoundService
    s:Play()
    s.Ended:Once(function() s:Destroy() end)
    return s
end

-- 사용 패턴
-- 검 휘두름:   playSFX(sword, "SLASH_ID", {volume=0.6})
-- 타격:        playSFX(target, "HIT_ID", {volume=0.8})
-- 폭발:        playSFX(workspace.Terrain, "EXPLOSION_ID", {volume=1, range=100})
-- 주문:        playSFX(caster, "SPELL_ID", {volume=0.7})
```

---

## 피치 변조 (긴장감 연출)

```lua
-- 위기 상황에서 BGM 피치 올리기
local function tensionRamp(sound, targetSpeed, duration)
    TweenService:Create(sound, TweenInfo.new(duration), {PlaybackSpeed = targetSpeed}):Play()
end

-- 슬로우모션 효과
local function slowMotionAudio(duration)
    if currentBGM then
        TweenService:Create(currentBGM, TweenInfo.new(0.3), {PlaybackSpeed = 0.5}):Play()
        task.wait(duration)
        TweenService:Create(currentBGM, TweenInfo.new(0.3), {PlaybackSpeed = 1}):Play()
    end
end
```

---

## 작업 완료 후 필수

1. 모든 사운드에 적절한 SoundGroup 할당
2. Volume 밸런스 확인 (BGM < SFX < 환경음 순서 아님, 맥락에 따라)
3. 루프 사운드는 적절한 정리(cleanup) 확인
4. SessionManager에 추가된 사운드 기록



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
