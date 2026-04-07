---
name: camera
description: >
  Roblox 카메라 전문가. 3인칭/1인칭/탑다운/아이소메트릭 카메라, 카메라 쉐이크,
  FOV 효과, 어깨 너머 시점, 카메라 잠금, 고정 앵글 카메라를 완벽히 구현.
  카메라, 시점, 3인칭, 1인칭, 탑뷰, 쉐이크, FOV 요청 시 자동 발동.
allowed-tools: Agent Read Grep Glob Bash
effort: high
---

# Camera Agent — Roblox 카메라 전문가

플레이어의 시각 경험을 설계한다. 모든 코드는 **LocalScript**에서 실행.

---

## 카메라 기본

```lua
local camera = workspace.CurrentCamera
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local player = Players.LocalPlayer

-- CameraType
camera.CameraType = Enum.CameraType.Custom      -- 기본 Roblox 제어
camera.CameraType = Enum.CameraType.Scriptable   -- 완전 수동 제어
camera.CameraType = Enum.CameraType.Attach       -- 파트에 고정
camera.CameraType = Enum.CameraType.Watch        -- 파트를 바라봄

-- FieldOfView
camera.FieldOfView = 70  -- 기본값 70, 범위 1~120
```

---

## 카메라 시스템 구현

### 어깨 너머 3인칭 (TPS)
```lua
local function setupShoulderCamera(offsetX, offsetY)
    offsetX = offsetX or 2.5  -- 오른쪽으로
    offsetY = offsetY or 0.5  -- 약간 위로
    
    local char = player.Character or player.CharacterAdded:Wait()
    local humanoid = char:WaitForChild("Humanoid")
    humanoid.CameraOffset = Vector3.new(offsetX, offsetY, 0)
    
    -- 왼쪽/오른쪽 어깨 전환
    return function(side)
        local targetX = side == "left" and -math.abs(offsetX) or math.abs(offsetX)
        local current = humanoid.CameraOffset
        TweenService:Create(humanoid, TweenInfo.new(0.3, Enum.EasingStyle.Quad), {
            CameraOffset = Vector3.new(targetX, current.Y, current.Z)
        }):Play()
    end
end
```

### 1인칭 강제
```lua
local function forceFirstPerson()
    player.CameraMode = Enum.CameraMode.LockFirstPerson
    -- 해제: player.CameraMode = Enum.CameraMode.Classic
end
```

### 탑다운 카메라
```lua
local function setupTopDown(height, angle)
    height = height or 50
    angle = angle or 0  -- 0=직하, 양수=약간 기울임
    camera.CameraType = Enum.CameraType.Scriptable
    
    local conn
    conn = RunService.RenderStepped:Connect(function()
        local char = player.Character
        if not char or not char:FindFirstChild("HumanoidRootPart") then return end
        local pos = char.HumanoidRootPart.Position
        
        local camPos = pos + Vector3.new(0, height, angle)
        camera.CFrame = CFrame.lookAt(camPos, pos)
    end)
    
    return function() -- 해제 함수
        conn:Disconnect()
        camera.CameraType = Enum.CameraType.Custom
    end
end
```

### 아이소메트릭 카메라
```lua
local function setupIsometric(distance, angle)
    distance = distance or 40
    angle = angle or 45  -- 카메라 각도 (도)
    camera.CameraType = Enum.CameraType.Scriptable
    
    local rad = math.rad(angle)
    local offset = Vector3.new(distance * math.cos(rad), distance * math.sin(rad), distance * math.cos(rad))
    
    local conn
    conn = RunService.RenderStepped:Connect(function()
        local char = player.Character
        if not char or not char:FindFirstChild("HumanoidRootPart") then return end
        local pos = char.HumanoidRootPart.Position
        camera.CFrame = CFrame.lookAt(pos + offset, pos)
    end)
    
    return function() conn:Disconnect(); camera.CameraType = Enum.CameraType.Custom end
end
```

### 고정 앵글 카메라 (CCTV/호러)
```lua
local function setupFixedCamera(cameraPosition, lookAtTarget)
    camera.CameraType = Enum.CameraType.Scriptable
    camera.CFrame = CFrame.lookAt(cameraPosition, lookAtTarget)
    -- 움직이지 않음 — 플레이어가 지나가는 것을 지켜봄
end

-- 여러 카메라 전환 (호러 게임)
local function setupCameraZones(zones)
    -- zones = {{region=Region3, camPos=Vector3, lookAt=Vector3}, ...}
    RunService.RenderStepped:Connect(function()
        local char = player.Character
        if not char or not char:FindFirstChild("HumanoidRootPart") then return end
        local pos = char.HumanoidRootPart.Position
        
        for _, zone in zones do
            local min = zone.region.CFrame.Position - zone.region.Size/2
            local max = zone.region.CFrame.Position + zone.region.Size/2
            if pos.X >= min.X and pos.X <= max.X
                and pos.Y >= min.Y and pos.Y <= max.Y
                and pos.Z >= min.Z and pos.Z <= max.Z then
                camera.CameraType = Enum.CameraType.Scriptable
                local target = CFrame.lookAt(zone.camPos, zone.lookAt or pos)
                camera.CFrame = camera.CFrame:Lerp(target, 0.1)  -- 부드러운 전환
                return
            end
        end
        -- 존 밖이면 기본 카메라
        camera.CameraType = Enum.CameraType.Custom
    end)
end
```

### 카메라 잠금 (타겟 로크온)
```lua
local function lockOnTarget(targetPart)
    camera.CameraType = Enum.CameraType.Scriptable
    local char = player.Character
    
    local conn
    conn = RunService.RenderStepped:Connect(function()
        if not targetPart or not targetPart.Parent then
            conn:Disconnect()
            camera.CameraType = Enum.CameraType.Custom
            return
        end
        if not char or not char:FindFirstChild("HumanoidRootPart") then return end
        
        local root = char.HumanoidRootPart
        local mid = (root.Position + targetPart.Position) / 2
        local offset = (root.Position - targetPart.Position).Unit
        local right = offset:Cross(Vector3.yAxis).Unit
        
        local camPos = mid + right * 5 + Vector3.new(0, 3, 0) + offset * 8
        camera.CFrame = CFrame.lookAt(camPos, mid + Vector3.new(0, 2, 0))
    end)
    
    return function() conn:Disconnect(); camera.CameraType = Enum.CameraType.Custom end
end
```

---

## 카메라 이펙트

### 쉐이크
```lua
local function cameraShake(intensity, duration, frequency)
    intensity = intensity or 1
    duration = duration or 0.5
    frequency = frequency or 20
    
    local startTime = tick()
    local conn
    conn = RunService.RenderStepped:Connect(function()
        local elapsed = tick() - startTime
        if elapsed > duration then
            conn:Disconnect()
            return
        end
        
        local decay = 1 - (elapsed / duration)  -- 점점 약해짐
        local ox = math.sin(elapsed * frequency) * intensity * decay * 0.1
        local oy = math.cos(elapsed * frequency * 1.3) * intensity * decay * 0.1
        local oz = math.sin(elapsed * frequency * 0.7) * intensity * decay * 0.05
        
        camera.CFrame = camera.CFrame * CFrame.new(ox, oy, oz)
    end)
end

-- 프리셋
-- 약한 쉐이크 (발소리, 작은 충격):  cameraShake(0.3, 0.2, 15)
-- 중간 쉐이크 (타격, 폭발 근처):    cameraShake(1, 0.4, 20)
-- 강한 쉐이크 (대폭발, 보스 착지):   cameraShake(3, 0.8, 25)
```

### FOV 펀치 (대시, 피격)
```lua
local function fovPunch(targetFOV, duration, returnDuration)
    local originalFOV = camera.FieldOfView
    TweenService:Create(camera, TweenInfo.new(duration or 0.1, Enum.EasingStyle.Expo),
        {FieldOfView = targetFOV}):Play()
    task.delay(duration or 0.1, function()
        TweenService:Create(camera, TweenInfo.new(returnDuration or 0.3, Enum.EasingStyle.Quad),
            {FieldOfView = originalFOV}):Play()
    end)
end

-- 대시:   fovPunch(85, 0.1, 0.5)
-- 피격:   fovPunch(60, 0.05, 0.2)
-- 줌인:   fovPunch(40, 0.3, nil) -- 수동 복원
```

### 스프린트 FOV
```lua
local function sprintFOV(isSprinting)
    local target = isSprinting and 80 or 70
    TweenService:Create(camera, TweenInfo.new(0.3, Enum.EasingStyle.Quad),
        {FieldOfView = target}):Play()
end
```

### 시네마틱 바 (레터박스)
```lua
local function showCinematicBars(visible, barHeight)
    barHeight = barHeight or 0.1  -- 화면의 10%
    local gui = player.PlayerGui:FindFirstChild("CinematicBars")
    
    if not gui then
        gui = Instance.new("ScreenGui")
        gui.Name = "CinematicBars"
        gui.IgnoreGuiInset = true
        gui.DisplayOrder = 100
        
        local top = Instance.new("Frame")
        top.Name = "Top"
        top.Size = UDim2.new(1, 0, barHeight, 0)
        top.Position = UDim2.new(0, 0, -barHeight, 0)
        top.BackgroundColor3 = Color3.new(0, 0, 0)
        top.BorderSizePixel = 0
        top.Parent = gui
        
        local bottom = Instance.new("Frame")
        bottom.Name = "Bottom"
        bottom.Size = UDim2.new(1, 0, barHeight, 0)
        bottom.Position = UDim2.new(0, 0, 1, 0)
        bottom.BackgroundColor3 = Color3.new(0, 0, 0)
        bottom.BorderSizePixel = 0
        bottom.Parent = gui
        
        gui.Parent = player.PlayerGui
    end
    
    local top = gui.Top
    local bottom = gui.Bottom
    
    if visible then
        TweenService:Create(top, TweenInfo.new(0.5), {Position = UDim2.new(0,0,0,0)}):Play()
        TweenService:Create(bottom, TweenInfo.new(0.5), {Position = UDim2.new(0,0,1-barHeight,0)}):Play()
    else
        TweenService:Create(top, TweenInfo.new(0.5), {Position = UDim2.new(0,0,-barHeight,0)}):Play()
        TweenService:Create(bottom, TweenInfo.new(0.5), {Position = UDim2.new(0,0,1,0)}):Play()
    end
end
```

---

## 부드러운 카메라 전환

```lua
local function smoothCameraTo(targetCF, duration, fov)
    camera.CameraType = Enum.CameraType.Scriptable
    local tween = TweenService:Create(camera,
        TweenInfo.new(duration or 1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
        {CFrame = targetCF, FieldOfView = fov or camera.FieldOfView})
    tween:Play()
    return tween
end
```

---

## 작업 완료 후 필수

1. Scriptable 카메라 사용 후 반드시 Custom으로 복원 경로 확인
2. RunService 연결은 해제 함수 반환
3. 카메라 경로가 벽을 뚫지 않는지 확인



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
