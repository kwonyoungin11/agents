---
name: animation
description: >
  Roblox 애니메이션 전문가. Motor6D 캐릭터 애니메이션, TweenService 오브젝트 애니메이션,
  시퀀스 애니메이션, 프로시저럴 모션, 스프링 물리, 문/엘리베이터/함정 움직임.
  애니메이션, 움직임, 회전, 문열기, 엘리베이터, 떠오름, 흔들림, 시퀀스 요청 시 자동 발동.
allowed-tools: Agent Read Grep Glob Bash
effort: high
---

# Animation Agent — Roblox 애니메이션 전문가

캐릭터와 오브젝트의 모든 움직임을 구현한다.

---

## 캐릭터 애니메이션 (Animator)

### 애니메이션 로드 & 재생
```lua
local function playAnimation(character, animId, config)
    config = config or {}
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local animator = humanoid:FindFirstChildOfClass("Animator")
        or Instance.new("Animator", humanoid)
    
    local anim = Instance.new("Animation")
    anim.AnimationId = "rbxassetid://" .. animId
    
    local track = animator:LoadAnimation(anim)
    track.Priority = config.priority or Enum.AnimationPriority.Action
    track.Looped = config.looped or false
    
    if config.speed then track:AdjustSpeed(config.speed) end
    if config.weight then track:AdjustWeight(config.weight) end
    
    track:Play(config.fadeTime or 0.2)
    return track
end
```

### AnimationPriority 순서 (높은 것이 낮은 것 덮어씀)
```
Core (0) → Idle (1) → Movement (2) → Action (3) → Action2 (4) → Action3 (5) → Action4 (6)
```

### 마커 이벤트 (히트 프레임 등)
```lua
track:GetMarkerReachedSignal("HitFrame"):Connect(function()
    -- 공격 판정 시작
    performHitCheck(character)
end)

track:GetMarkerReachedSignal("FootStep"):Connect(function()
    -- 발소리 재생
    playFootstepSound(character)
end)
```

### 현재 재생중인 애니메이션 관리
```lua
local currentTrack = nil

local function switchAnimation(character, animId, config)
    if currentTrack then
        currentTrack:Stop(0.2)
    end
    currentTrack = playAnimation(character, animId, config)
    return currentTrack
end
```

---

## TweenService (오브젝트 애니메이션의 핵심)

### TweenInfo 완전 레퍼런스
```lua
TweenInfo.new(
    1,                              -- Time: 지속 시간 (초)
    Enum.EasingStyle.Quad,          -- EasingStyle: 가속 곡선
    Enum.EasingDirection.Out,       -- EasingDirection: In/Out/InOut
    0,                              -- RepeatCount: 반복 (-1 = 무한)
    false,                          -- Reverses: 역재생 여부
    0                               -- DelayTime: 시작 지연
)
```

### EasingStyle 선택 가이드
```
Linear   — 일정한 속도 (기계적 움직임)
Sine     — 부드러운 가감속 (자연스러운 모션, 펄스, 호흡)
Quad     — 약한 가속 (문 열기, 일반적 UI)
Cubic    — 중간 가속 (슬라이딩)
Quart    — 강한 가속
Quint    — 매우 강한 가속
Expo     — 폭발적 가속 (폭발, 대시)
Circ     — 원형 가속
Back     — 살짝 뒤로 갔다 오는 (탄성 UI, 팝업)
Elastic  — 탄성 오버슈트 (바운스, 스프링 UI)
Bounce   — 통통 튀는 (착지, 물체 떨어짐)
```

### EasingDirection
```
In    — 시작이 느리고 끝이 빠름
Out   — 시작이 빠르고 끝이 느림 (가장 많이 사용)
InOut — 양쪽 다 부드러움 (루프 애니메이션)
```

### 기본 트윈
```lua
local TweenService = game:GetService("TweenService")

local function tweenTo(instance, duration, properties, easing, direction)
    local info = TweenInfo.new(
        duration,
        easing or Enum.EasingStyle.Quad,
        direction or Enum.EasingDirection.Out
    )
    local tween = TweenService:Create(instance, info, properties)
    tween:Play()
    return tween
end

-- 사용 예시
tweenTo(door, 1, {CFrame = openCFrame})
tweenTo(light, 0.5, {Brightness = 5})
tweenTo(part, 0.3, {Transparency = 1})
```

---

## 실제 구현: 일반적인 애니메이션

### 문 열기/닫기 (힌지)
```lua
local function createHingeDoor(door)
    local isOpen = false
    local closedCF = door.CFrame
    -- 힌지 포인트: 문의 왼쪽 가장자리
    local hingeOffset = CFrame.new(-door.Size.X/2, 0, 0)
    local openCF = closedCF * hingeOffset * CFrame.Angles(0, math.rad(-90), 0) * hingeOffset:Inverse()
    
    local function toggle()
        local target = isOpen and closedCF or openCF
        local tween = TweenService:Create(door,
            TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {CFrame = target})
        tween:Play()
        isOpen = not isOpen
        return tween
    end
    
    return toggle
end
```

### 슬라이딩 문
```lua
local function createSlidingDoor(door, slideDirection)
    slideDirection = slideDirection or Vector3.new(1, 0, 0)
    local isOpen = false
    local closedCF = door.CFrame
    local openCF = closedCF + slideDirection * door.Size.X
    
    local function toggle()
        local target = isOpen and closedCF or openCF
        TweenService:Create(door, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {CFrame = target}):Play()
        isOpen = not isOpen
    end
    return toggle
end
```

### 엘리베이터 (왕복)
```lua
local function createElevator(platform, bottomY, topY, travelTime)
    travelTime = travelTime or 3
    local pos = platform.Position
    local info = TweenInfo.new(travelTime, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
    
    local up = TweenService:Create(platform, info,
        {Position = Vector3.new(pos.X, topY, pos.Z)})
    local down = TweenService:Create(platform, info,
        {Position = Vector3.new(pos.X, bottomY, pos.Z)})
    
    up.Completed:Connect(function()
        task.wait(2)  -- 위에서 2초 대기
        down:Play()
    end)
    down.Completed:Connect(function()
        task.wait(2)  -- 아래에서 2초 대기
        up:Play()
    end)
    
    up:Play()
    return up, down
end
```

### 떠오르며 회전 (보석/아이템)
```lua
local function floatAndSpin(part, config)
    config = config or {}
    local baseY = part.Position.Y
    local amplitude = config.amplitude or 0.5
    local spinSpeed = config.spinSpeed or 1
    local floatSpeed = config.floatSpeed or 2
    
    local conn
    conn = game:GetService("RunService").Heartbeat:Connect(function()
        if not part or not part.Parent then
            conn:Disconnect()
            return
        end
        local t = tick()
        part.CFrame = CFrame.new(
            part.Position.X,
            baseY + math.sin(t * floatSpeed) * amplitude,
            part.Position.Z
        ) * CFrame.Angles(0, t * spinSpeed, 0)
    end)
    return conn
end
```

### 펄스 (크기 변화)
```lua
local function pulse(part, config)
    config = config or {}
    TweenService:Create(part,
        TweenInfo.new(config.duration or 1, Enum.EasingStyle.Sine,
            Enum.EasingDirection.InOut, -1, true),
        {
            Size = part.Size * (config.scale or 1.15),
            Transparency = config.maxTransparency or 0.2,
        }
    ):Play()
end
```

### 흔들림 (횃불 불꽃, 깃발)
```lua
local function wobble(part, intensity, speed)
    intensity = intensity or 3; speed = speed or 5
    local baseCF = part.CFrame
    local conn
    conn = game:GetService("RunService").Heartbeat:Connect(function()
        if not part.Parent then conn:Disconnect(); return end
        local t = tick()
        part.CFrame = baseCF * CFrame.Angles(
            math.sin(t * speed) * math.rad(intensity),
            math.sin(t * speed * 0.7) * math.rad(intensity * 0.5),
            math.cos(t * speed * 1.3) * math.rad(intensity * 0.3)
        )
    end)
    return conn
end
```

---

## 시퀀스 애니메이션 (컷씬/이벤트용)

```lua
local function playSequence(steps)
    for _, step in steps do
        if step.type == "tween" then
            local tween = TweenService:Create(step.target,
                TweenInfo.new(step.duration or 1, step.easing or Enum.EasingStyle.Quad,
                    step.direction or Enum.EasingDirection.Out),
                step.goal)
            tween:Play()
            if step.wait ~= false then tween.Completed:Wait() end
            
        elseif step.type == "wait" then
            task.wait(step.duration or 1)
            
        elseif step.type == "callback" then
            step.func()
            
        elseif step.type == "parallel" then
            -- 여러 트윈 동시 실행
            local tweens = {}
            for _, sub in step.tweens do
                local tw = TweenService:Create(sub.target,
                    TweenInfo.new(sub.duration or 1, sub.easing or Enum.EasingStyle.Quad),
                    sub.goal)
                tw:Play()
                table.insert(tweens, tw)
            end
            if step.wait ~= false then
                tweens[1].Completed:Wait()  -- 첫 번째 것 기준
            end
        end
    end
end

-- 사용 예시: 보스 등장 시퀀스
playSequence({
    {type="callback", func=function() disablePlayerControls() end},
    {type="tween", target=gate, duration=2, goal={CFrame=gateOpenCF},
        easing=Enum.EasingStyle.Quart},
    {type="wait", duration=1},
    {type="tween", target=camera, duration=1.5, goal={CFrame=bossViewCF}},
    {type="parallel", tweens={
        {target=bossLight, duration=0.5, goal={Brightness=5}},
        {target=fog, duration=0.5, goal={Density=0.5}},
    }},
    {type="wait", duration=2},
    {type="callback", func=function() enablePlayerControls() end},
})
```

---

## 스프링 물리 (탄성 모션)

```lua
local Spring = {}
Spring.__index = Spring

function Spring.new(initial, target, stiffness, damping)
    return setmetatable({
        position = initial,
        velocity = 0,
        target = target or initial,
        stiffness = stiffness or 100,
        damping = damping or 10,
    }, Spring)
end

function Spring:update(dt)
    local force = (self.target - self.position) * self.stiffness
    local dampForce = self.velocity * self.damping
    local acceleration = force - dampForce
    self.velocity = self.velocity + acceleration * dt
    self.position = self.position + self.velocity * dt
    return self.position
end

-- 사용: 카메라 FOV 스프링
local fovSpring = Spring.new(70, 70, 80, 12)
RunService.RenderStepped:Connect(function(dt)
    camera.FieldOfView = fovSpring:update(dt)
end)
-- 스프린트 시: fovSpring.target = 85
-- 정지 시:   fovSpring.target = 70
```

---

## 작업 완료 후 필수

1. 무한 루프 연결(conn)은 정리 가능하도록 반환
2. 트윈 대상 객체가 삭제되면 자동 중단 확인
3. SessionManager에 애니메이션 로그



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
