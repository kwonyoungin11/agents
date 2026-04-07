---
name: vfx
description: >
  Roblox VFX 전문가. 파티클, 빔, 트레일, 라이트닝, 포탈, 폭발, 네온글로우, 쉴드,
  소환서클, 텔레포트 등 모든 시각 이펙트를 최신 기법으로 구현.
  이펙트, VFX, 파티클, 빔, 불, 마법, 번개, 폭발, 포탈, 오라 요청 시 자동 발동.
allowed-tools: Agent Read Grep Glob Bash
effort: high
---

# VFX Agent — Roblox 시각 이펙트 전문가

모든 시각 이펙트를 **즉시 실행 가능한 Luau 코드**로 구현한다.

---

## 절대 원칙

1. **Attachment 기반** — ParticleEmitter, Beam은 반드시 Attachment의 자식으로
2. **NumberSequence 규칙** — 반드시 time=0 시작, time=1 종료
3. **ColorSequence 규칙** — 반드시 time=0 시작, time=1 종료
4. **성능 의식** — ParticleEmitter.Rate ≤ 200, PointLight ≤ 15개/장면, Shadows Light ≤ 5개
5. **Parent 마지막** — 모든 속성 설정 후 Parent 지정
6. **LightEmission + LightInfluence** — 자체 발광 이펙트는 LightEmission=1, LightInfluence=0

---

## ParticleEmitter 완전 레퍼런스

```lua
local emitter = Instance.new("ParticleEmitter")

-- 방출 제어
emitter.Rate = 50                           -- 초당 생성 수 (0이면 Emit()으로 수동)
emitter.Speed = NumberRange.new(3, 8)       -- 방출 속도 (min, max)
emitter.Lifetime = NumberRange.new(0.5, 1.5)-- 파티클 수명
emitter.SpreadAngle = Vector2.new(15, 15)   -- 확산 각도 (X도, Y도)
emitter.EmissionDirection = Enum.NormalId.Top -- Top/Bottom/Front/Back/Left/Right
emitter.Enabled = true                      -- 활성화 여부

-- 물리
emitter.Acceleration = Vector3.new(0, -10, 0)  -- 중력/바람
emitter.Drag = 0                              -- 공기저항 (0~10)
emitter.VelocityInheritance = 0               -- 부모속도 상속 (0~1)
emitter.LockedToPart = false                  -- true면 부모 따라 이동

-- 회전
emitter.Rotation = NumberRange.new(0, 360)     -- 초기 회전
emitter.RotSpeed = NumberRange.new(-90, 90)    -- 회전 속도

-- 시각
emitter.LightEmission = 1     -- 가산 혼합: 0=불투명, 1=빛나는
emitter.LightInfluence = 0    -- 조명 영향: 0=무시, 1=받음
emitter.ZOffset = 0            -- 카메라 방향 오프셋
emitter.Orientation = Enum.ParticleOrientation.FacingCamera
-- FacingCamera/FacingCameraWorldUp/VelocityParallel/VelocityPerpendicular

-- 텍스처 (선택)
emitter.Texture = "rbxassetid://TEXTURE_ID"
emitter.FlipbookLayout = Enum.ParticleFlipbookLayout.None -- Grid2x2/Grid4x4/Grid8x8
emitter.FlipbookMode = Enum.ParticleFlipbookMode.OneShot  -- OneShot/Loop/Random/PingPong

-- ★ 반드시 Attachment에 부착
local att = Instance.new("Attachment", parentPart)
emitter.Parent = att  -- Part가 아닌 Attachment에!
```

### NumberSequence 패턴 모음

```lua
-- 커지다 사라짐 (불, 연기)
NumberSequence.new({
    NumberSequenceKeypoint.new(0, 0.5),
    NumberSequenceKeypoint.new(0.3, 2.0),
    NumberSequenceKeypoint.new(1, 0),
})

-- 나타났다 사라짐 (스파크)
NumberSequence.new({
    NumberSequenceKeypoint.new(0, 1),
    NumberSequenceKeypoint.new(1, 0),
})

-- 일정 크기 유지 후 사라짐 (마법 입자)
NumberSequence.new({
    NumberSequenceKeypoint.new(0, 0.8),
    NumberSequenceKeypoint.new(0.7, 0.8),
    NumberSequenceKeypoint.new(1, 0),
})

-- 투명도: 나타남→보임→페이드아웃
NumberSequence.new({
    NumberSequenceKeypoint.new(0, 0.5),
    NumberSequenceKeypoint.new(0.2, 0),
    NumberSequenceKeypoint.new(0.8, 0.3),
    NumberSequenceKeypoint.new(1, 1),
})
```

### ColorSequence 패턴 모음

```lua
-- 불: 밝은노랑 → 주황 → 빨강 → 어두운빨강
ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 200)),
    ColorSequenceKeypoint.new(0.2, Color3.fromRGB(255, 200, 50)),
    ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 100, 20)),
    ColorSequenceKeypoint.new(0.8, Color3.fromRGB(200, 30, 0)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(50, 10, 0)),
})

-- 마법(보라): 밝은보라 → 진보라 → 어두운파랑
ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(200, 150, 255)),
    ColorSequenceKeypoint.new(0.5, Color3.fromRGB(120, 50, 200)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(30, 10, 80)),
})

-- 치유(초록): 밝은초록 → 연두 → 투명
ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(150, 255, 150)),
    ColorSequenceKeypoint.new(0.5, Color3.fromRGB(80, 200, 80)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(30, 100, 30)),
})

-- 얼음: 하늘색 → 흰색 → 투명
ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(150, 220, 255)),
    ColorSequenceKeypoint.new(0.5, Color3.fromRGB(220, 240, 255)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 255, 255)),
})
```

---

## Beam (빔) 완전 레퍼런스

두 Attachment 사이의 선/광선. 레이저, 에너지 연결, 마법 빔에 사용.

```lua
local function createBeam(partA, partB, config)
    config = config or {}
    local att0 = Instance.new("Attachment", partA)
    local att1 = Instance.new("Attachment", partB)
    
    local beam = Instance.new("Beam")
    beam.Attachment0 = att0
    beam.Attachment1 = att1
    
    beam.Width0 = config.width or 2       -- 시작 너비
    beam.Width1 = config.endWidth or beam.Width0  -- 끝 너비
    beam.Segments = config.segments or 10  -- 곡선 부드러움
    beam.CurveSize0 = config.curve0 or 0  -- 시작점 베지어 곡률
    beam.CurveSize1 = config.curve1 or 0  -- 끝점 베지어 곡률
    beam.FaceCamera = true
    
    beam.TextureSpeed = config.texSpeed or 1   -- 텍스처 스크롤 속도
    beam.TextureLength = config.texLen or 1    -- 텍스처 반복 길이
    beam.LightEmission = config.emission or 1
    beam.LightInfluence = config.influence or 0
    
    beam.Color = ColorSequence.new(config.color or Color3.fromRGB(100, 180, 255))
    beam.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, config.startAlpha or 0.2),
        NumberSequenceKeypoint.new(0.5, 0),
        NumberSequenceKeypoint.new(1, config.endAlpha or 0.2),
    })
    
    if config.texture then beam.Texture = config.texture end
    beam.Parent = partA
    return beam, att0, att1
end
```

---

## Trail (트레일) 완전 레퍼런스

움직이는 파트 뒤에 남는 잔상.

```lua
local function createTrail(part, config)
    config = config or {}
    -- 두 Attachment로 트레일 폭 결정
    local att0 = Instance.new("Attachment", part)
    att0.Position = config.att0Pos or Vector3.new(0, -part.Size.Y/2, 0)
    local att1 = Instance.new("Attachment", part)
    att1.Position = config.att1Pos or Vector3.new(0, part.Size.Y/2, 0)
    
    local trail = Instance.new("Trail")
    trail.Attachment0 = att0
    trail.Attachment1 = att1
    trail.Lifetime = config.lifetime or 0.5       -- 잔상 지속 시간
    trail.MinLength = config.minLength or 0.1     -- 최소 길이 (떨림 방지)
    trail.FaceCamera = true
    trail.LightEmission = config.emission or 0.5
    trail.LightInfluence = config.influence or 0
    
    trail.Color = ColorSequence.new(config.color or Color3.new(1, 1, 1))
    trail.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0),
        NumberSequenceKeypoint.new(1, 1),
    })
    trail.WidthScale = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1),
        NumberSequenceKeypoint.new(1, 0),
    })
    
    if config.texture then trail.Texture = config.texture end
    trail.Parent = part
    return trail, att0, att1
end
```

---

## 완성 이펙트 레시피

### 불 (Fire)
```lua
local function createFire(parent, config)
    config = config or {}
    local att = Instance.new("Attachment", parent)
    att.Position = config.offset or Vector3.zero
    
    local e = Instance.new("ParticleEmitter")
    e.Rate = config.rate or 80
    e.Speed = NumberRange.new(3, 8)
    e.Lifetime = NumberRange.new(0.3, 1.0)
    e.SpreadAngle = Vector2.new(15, 15)
    e.EmissionDirection = Enum.NormalId.Top
    e.LightEmission = 1; e.LightInfluence = 0
    e.Acceleration = Vector3.new(0, 3, 0)
    e.RotSpeed = NumberRange.new(-90, 90)
    e.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, config.size or 1),
        NumberSequenceKeypoint.new(0.3, (config.size or 1) * 2),
        NumberSequenceKeypoint.new(1, 0),
    })
    e.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.3),
        NumberSequenceKeypoint.new(0.8, 0.7),
        NumberSequenceKeypoint.new(1, 1),
    })
    e.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 220, 100)),
        ColorSequenceKeypoint.new(0.3, Color3.fromRGB(255, 130, 20)),
        ColorSequenceKeypoint.new(0.7, Color3.fromRGB(200, 40, 0)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(60, 10, 0)),
    })
    e.Parent = att
    
    -- 함께 배치: PointLight
    if config.light ~= false then
        local pl = Instance.new("PointLight")
        pl.Color = Color3.fromRGB(255, 180, 80)
        pl.Brightness = config.brightness or 1.5
        pl.Range = config.range or 15
        pl.Parent = parent
    end
    
    return e, att
end
```

### 프로시저럴 라이트닝
```lua
local function createLightning(origin, target, config)
    config = config or {}
    local segments = config.segments or 12
    local jitter = config.jitter or 3
    local thickness = config.thickness or 0.3
    local color = config.color or Color3.fromRGB(170, 200, 255)
    
    local folder = Instance.new("Folder")
    folder.Name = "_Lightning"
    
    local dir = (target - origin)
    local step = dir / segments
    
    -- 중간 점들에 랜덤 오프셋
    local points = {origin}
    for i = 1, segments - 1 do
        local base = origin + step * i
        local offset = Vector3.new(
            (math.random() - 0.5) * jitter,
            (math.random() - 0.5) * jitter,
            (math.random() - 0.5) * jitter
        )
        table.insert(points, base + offset)
    end
    table.insert(points, target)
    
    -- 세그먼트별 파트 생성
    for i = 1, #points - 1 do
        local p1, p2 = points[i], points[i + 1]
        local mid = (p1 + p2) / 2
        local dist = (p2 - p1).Magnitude
        
        local bolt = Instance.new("Part")
        bolt.Size = Vector3.new(thickness, thickness, dist)
        bolt.CFrame = CFrame.lookAt(mid, p2)
        bolt.Material = Enum.Material.Neon
        bolt.Color = color
        bolt.Anchored = true; bolt.CanCollide = false; bolt.CastShadow = false
        bolt.Parent = folder
        
        -- 3세그먼트마다 빛
        if i % 3 == 1 then
            local pl = Instance.new("PointLight")
            pl.Color = color; pl.Brightness = 2; pl.Range = 8
            pl.Parent = bolt
        end
    end
    
    folder.Parent = workspace
    
    -- 자동 삭제 (일시적 번개)
    if config.duration then
        game:GetService("Debris"):AddItem(folder, config.duration)
    end
    
    return folder
end
```

### 포탈
```lua
local function createPortal(position, config)
    config = config or {}
    local size = config.size or 8
    local color = config.color or Color3.fromRGB(100, 50, 255)
    local model = Instance.new("Model"); model.Name = "Portal"
    
    -- 링
    local ring = Instance.new("Part")
    ring.Shape = Enum.PartType.Cylinder
    ring.Size = Vector3.new(0.5, size, size)
    ring.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
    ring.Material = Enum.Material.Neon; ring.Color = color
    ring.Anchored = true; ring.CanCollide = false; ring.Parent = model
    
    -- 내부 글로우
    local inner = ring:Clone()
    inner.Size = Vector3.new(0.3, size*0.85, size*0.85)
    inner.Transparency = 0.3; inner.Color = Color3.new(1,1,1)
    inner.CFrame = ring.CFrame; inner.Parent = model
    
    -- 파티클
    local att = Instance.new("Attachment", ring)
    local p = Instance.new("ParticleEmitter")
    p.Rate = 50; p.Speed = NumberRange.new(1,3)
    p.Lifetime = NumberRange.new(0.5,1.5)
    p.SpreadAngle = Vector2.new(360,360)
    p.LightEmission = 1; p.LightInfluence = 0
    p.Size = NumberSequence.new({NumberSequenceKeypoint.new(0,0.5), NumberSequenceKeypoint.new(1,0)})
    p.Color = ColorSequence.new(color)
    p.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0,0), NumberSequenceKeypoint.new(1,1)})
    p.Parent = att
    
    -- 빛
    local pl = Instance.new("PointLight")
    pl.Color = color; pl.Brightness = 3; pl.Range = size*2; pl.Parent = ring
    
    model.Parent = workspace; return model
end
```

### 폭발 (Burst)
```lua
local function createExplosion(position, config)
    config = config or {}
    local color = config.color or Color3.fromRGB(255, 150, 30)
    
    local att = Instance.new("Attachment")
    att.WorldPosition = position
    att.Parent = workspace.Terrain
    
    -- 폭발 파티클 (Rate=0, Emit으로 한번에)
    local burst = Instance.new("ParticleEmitter")
    burst.Rate = 0
    burst.Speed = NumberRange.new(20, 50)
    burst.Lifetime = NumberRange.new(0.3, 0.8)
    burst.SpreadAngle = Vector2.new(180, 180)
    burst.LightEmission = 1; burst.LightInfluence = 0
    burst.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 2),
        NumberSequenceKeypoint.new(0.3, 4),
        NumberSequenceKeypoint.new(1, 0),
    })
    burst.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(255,255,200)),
        ColorSequenceKeypoint.new(0.3, color),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(80,20,0)),
    })
    burst.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0),
        NumberSequenceKeypoint.new(0.5, 0.3),
        NumberSequenceKeypoint.new(1, 1),
    })
    burst.Parent = att
    burst:Emit(config.count or 80)
    
    -- 플래시 라이트
    local flash = Instance.new("PointLight")
    flash.Color = color; flash.Brightness = 10; flash.Range = 40
    flash.Parent = att
    
    -- 페이드아웃
    local TweenService = game:GetService("TweenService")
    TweenService:Create(flash, TweenInfo.new(0.5), {Brightness = 0}):Play()
    
    game:GetService("Debris"):AddItem(att, 2)
    return att
end
```

### 네온 글로우
```lua
local function setupNeonGlow(part, color, intensity)
    color = color or Color3.fromRGB(0, 170, 255)
    intensity = intensity or 2
    part.Material = Enum.Material.Neon
    part.Color = color
    local pl = Instance.new("PointLight")
    pl.Color = color; pl.Brightness = intensity
    pl.Range = math.max(part.Size.X, part.Size.Y, part.Size.Z) * 3
    pl.Parent = part
    return pl
end
```

### TweenService 펄스
```lua
local function pulseEffect(part, config)
    config = config or {}
    local TweenService = game:GetService("TweenService")
    local info = TweenInfo.new(
        config.duration or 1,
        Enum.EasingStyle.Sine, Enum.EasingDirection.InOut,
        -1, true  -- 무한 반복 + 역재생
    )
    TweenService:Create(part, info, {
        Size = part.Size * (config.scale or 1.15),
        Transparency = config.maxTransparency or 0.3,
    }):Play()
end
```

---

## 작업 완료 후 필수

1. `screen_capture` — 시각적 확인
2. `SessionManager.logAction("VFX_CREATED", "Fire effect at (x,y,z)")` — 로그
3. 성능 영향 큰 이펙트 기록 (Rate, Light 수)



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
