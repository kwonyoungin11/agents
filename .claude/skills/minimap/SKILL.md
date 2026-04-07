---
name: minimap
description: >
  Roblox 미니맵 시스템 전문가. ViewportFrame 기반 미니맵, 플레이어 점 표시,
  적 점 표시, POI 마커, 플레이어 방향에 따른 회전, 줌 기능 구현.
  미니맵, 지도, 맵, 레이더, 위치표시, minimap 요청 시 자동 발동.
allowed-tools: Agent Read Grep Glob Bash
effort: high
---

# Minimap Agent — Roblox 미니맵 시스템 전문가

ViewportFrame 기반 실시간 미니맵을 **즉시 실행 가능한 Luau 코드**로 구현한다.

---

## 절대 원칙

1. **ViewportFrame 사용** — 3D 세계를 미니맵으로 렌더링하는 최적 방법
2. **RunService.Heartbeat** — 매 프레임 플레이어 위치 추적 및 회전 동기화
3. **성능 관리** — ViewportFrame 내 오브젝트 수 최소화, LOD 적용
4. **마커 시스템** — 점/아이콘으로 적/NPC/POI 표시
5. **ClipsDescendants** — 미니맵 밖으로 요소 삐져나가지 않도록

---

## 미니맵 구조

```
ScreenGui "MinimapGui"
└── MinimapContainer (우상단, 원형 클리핑)
    ├── UICorner (원형)
    ├── UIStroke (테두리)
    ├── ViewportFrame (3D 월드 투영)
    │   └── ViewportCamera
    ├── MarkersFrame (2D 오버레이 마커)
    │   ├── PlayerDot (중앙 고정, 방향 화살표)
    │   ├── EnemyDot_N (빨간 점)
    │   └── POI_N (아이콘 마커)
    ├── CompassFrame (NESW 방위 표시)
    └── ZoomControls (+/- 버튼)
```

---

## 완전한 미니맵 시스템 구현

```lua
--!strict
-- MinimapSystem.luau — LocalScript under StarterPlayerScripts
-- ViewportFrame 기반 실시간 미니맵 + 마커 시스템

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

------------------------------------------------------------------------
-- CONFIG
------------------------------------------------------------------------
local CONFIG = {
    Size = 200,                  -- 미니맵 크기 (px)
    Position = UDim2.new(1, -20, 0, 20), -- 우상단
    ZoomHeight = 80,             -- 카메라 높이 (studs)
    MinZoom = 40,
    MaxZoom = 200,
    ZoomStep = 20,
    RotateWithPlayer = true,     -- 플레이어 방향에 따라 회전
    PlayerDotSize = 12,
    EnemyDotSize = 8,
    POISize = 16,
    BorderColor = Color3.fromRGB(60, 60, 80),
    BorderThickness = 3,
    PlayerColor = Color3.fromRGB(80, 200, 255),
    EnemyColor = Color3.fromRGB(255, 60, 60),
    AllyColor = Color3.fromRGB(60, 255, 60),
    POIColor = Color3.fromRGB(255, 220, 50),
}

------------------------------------------------------------------------
-- HELPERS
------------------------------------------------------------------------
local function addCorner(parent: GuiObject, radius: number)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius)
    c.Parent = parent
end

------------------------------------------------------------------------
-- SCREEN GUI
------------------------------------------------------------------------
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "MinimapGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.DisplayOrder = 8
screenGui.Parent = playerGui

------------------------------------------------------------------------
-- MINIMAP CONTAINER
------------------------------------------------------------------------
local container = Instance.new("Frame")
container.Name = "MinimapContainer"
container.AnchorPoint = Vector2.new(1, 0)
container.Position = CONFIG.Position
container.Size = UDim2.new(0, CONFIG.Size, 0, CONFIG.Size)
container.BackgroundColor3 = Color3.fromRGB(10, 10, 15)
container.ClipsDescendants = true
addCorner(container, CONFIG.Size / 2) -- 원형
container.Parent = screenGui

local stroke = Instance.new("UIStroke")
stroke.Color = CONFIG.BorderColor
stroke.Thickness = CONFIG.BorderThickness
stroke.Parent = container

------------------------------------------------------------------------
-- VIEWPORT FRAME (3D 세계 투영)
------------------------------------------------------------------------
local viewport = Instance.new("ViewportFrame")
viewport.Name = "ViewportFrame"
viewport.Size = UDim2.new(1, 0, 1, 0)
viewport.BackgroundTransparency = 1
viewport.Ambient = Color3.fromRGB(150, 150, 150)
viewport.LightColor = Color3.fromRGB(200, 200, 200)
viewport.LightDirection = Vector3.new(-1, -1, -1)
addCorner(viewport, CONFIG.Size / 2)
viewport.Parent = container

local vpCamera = Instance.new("Camera")
vpCamera.CameraType = Enum.CameraType.Scriptable
vpCamera.FieldOfView = 70
viewport.CurrentCamera = vpCamera
vpCamera.Parent = viewport

------------------------------------------------------------------------
-- MARKERS OVERLAY (2D)
------------------------------------------------------------------------
local markersFrame = Instance.new("Frame")
markersFrame.Name = "Markers"
markersFrame.Size = UDim2.new(1, 0, 1, 0)
markersFrame.BackgroundTransparency = 1
markersFrame.ClipsDescendants = true
addCorner(markersFrame, CONFIG.Size / 2)
markersFrame.Parent = container

-- Player dot (항상 중앙)
local playerDot = Instance.new("Frame")
playerDot.Name = "PlayerDot"
playerDot.AnchorPoint = Vector2.new(0.5, 0.5)
playerDot.Position = UDim2.new(0.5, 0, 0.5, 0)
playerDot.Size = UDim2.new(0, CONFIG.PlayerDotSize, 0, CONFIG.PlayerDotSize)
playerDot.BackgroundColor3 = CONFIG.PlayerColor
playerDot.ZIndex = 10
addCorner(playerDot, CONFIG.PlayerDotSize / 2)
playerDot.Parent = markersFrame

-- 방향 화살표 (삼각형)
local arrow = Instance.new("ImageLabel")
arrow.Name = "Arrow"
arrow.AnchorPoint = Vector2.new(0.5, 1)
arrow.Position = UDim2.new(0.5, 0, 0, -2)
arrow.Size = UDim2.new(0, 8, 0, 10)
arrow.BackgroundTransparency = 1
arrow.ImageColor3 = CONFIG.PlayerColor
arrow.Image = "rbxassetid://6034818375" -- triangle/arrow asset
arrow.Parent = playerDot

------------------------------------------------------------------------
-- COMPASS (NESW)
------------------------------------------------------------------------
local compassLabels = { "N", "E", "S", "W" }
local compassAngles = { 0, 90, 180, 270 }

for i, dir in compassLabels do
    local label = Instance.new("TextLabel")
    label.Name = "Compass_" .. dir
    label.AnchorPoint = Vector2.new(0.5, 0.5)
    label.Size = UDim2.new(0, 16, 0, 16)
    label.BackgroundTransparency = 1
    label.Text = dir
    label.TextColor3 = if dir == "N" then Color3.fromRGB(255, 80, 80) else Color3.fromRGB(200, 200, 200)
    label.TextSize = 11
    label.Font = Enum.Font.GothamBold
    label.ZIndex = 15
    label.Parent = markersFrame
    label:SetAttribute("CompassAngle", compassAngles[i])
end

------------------------------------------------------------------------
-- ZOOM CONTROLS
------------------------------------------------------------------------
local zoomHeight = CONFIG.ZoomHeight

local zoomIn = Instance.new("TextButton")
zoomIn.Name = "ZoomIn"
zoomIn.AnchorPoint = Vector2.new(1, 0)
zoomIn.Position = UDim2.new(1, -5, 1, 5)
zoomIn.Size = UDim2.new(0, 28, 0, 28)
zoomIn.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
zoomIn.Text = "+"
zoomIn.TextColor3 = Color3.fromRGB(200, 200, 200)
zoomIn.TextSize = 18
zoomIn.Font = Enum.Font.GothamBold
addCorner(zoomIn, 6)
zoomIn.Parent = screenGui
-- Position relative to minimap
zoomIn.AnchorPoint = Vector2.new(1, 0)
zoomIn.Position = UDim2.new(1, -20, 0, CONFIG.Size + 28)

local zoomOut = Instance.new("TextButton")
zoomOut.Name = "ZoomOut"
zoomOut.AnchorPoint = Vector2.new(1, 0)
zoomOut.Position = UDim2.new(1, -54, 0, CONFIG.Size + 28)
zoomOut.Size = UDim2.new(0, 28, 0, 28)
zoomOut.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
zoomOut.Text = "-"
zoomOut.TextColor3 = Color3.fromRGB(200, 200, 200)
zoomOut.TextSize = 18
zoomOut.Font = Enum.Font.GothamBold
addCorner(zoomOut, 6)
zoomOut.Parent = screenGui

zoomIn.MouseButton1Click:Connect(function()
    zoomHeight = math.clamp(zoomHeight - CONFIG.ZoomStep, CONFIG.MinZoom, CONFIG.MaxZoom)
end)
zoomOut.MouseButton1Click:Connect(function()
    zoomHeight = math.clamp(zoomHeight + CONFIG.ZoomStep, CONFIG.MinZoom, CONFIG.MaxZoom)
end)

------------------------------------------------------------------------
-- MARKER MANAGEMENT
------------------------------------------------------------------------
type MarkerInfo = {
    dot: Frame,
    worldObject: BasePart?,
    worldPosition: Vector3?,
    color: Color3,
}

local markers: { [string]: MarkerInfo } = {}

local function addMarker(id: string, color: Color3, size: number, worldObj: BasePart?, worldPos: Vector3?)
    if markers[id] then return end
    local dot = Instance.new("Frame")
    dot.Name = "Marker_" .. id
    dot.AnchorPoint = Vector2.new(0.5, 0.5)
    dot.Size = UDim2.new(0, size, 0, size)
    dot.BackgroundColor3 = color
    dot.ZIndex = 5
    addCorner(dot, size / 2)
    dot.Parent = markersFrame

    markers[id] = {
        dot = dot,
        worldObject = worldObj,
        worldPosition = worldPos,
        color = color,
    }
end

local function removeMarker(id: string)
    local m = markers[id]
    if m then
        m.dot:Destroy()
        markers[id] = nil
    end
end

local function addEnemyMarker(id: string, part: BasePart)
    addMarker(id, CONFIG.EnemyColor, CONFIG.EnemyDotSize, part, nil)
end

local function addPOIMarker(id: string, position: Vector3)
    addMarker(id, CONFIG.POIColor, CONFIG.POISize, nil, position)
end

------------------------------------------------------------------------
-- CLONE WORLD INTO VIEWPORT (간략 버전)
------------------------------------------------------------------------
local function cloneWorldToViewport()
    -- Terrain이나 주요 Part만 복제 (성능상 전체 복제는 비추천)
    for _, obj in workspace:GetChildren() do
        if obj:IsA("BasePart") and obj.Size.Magnitude > 5 then
            local clone = obj:Clone()
            clone.Anchored = true
            clone.CanCollide = false
            clone.Parent = viewport
        elseif obj:IsA("Model") then
            local clone = obj:Clone()
            for _, desc in clone:GetDescendants() do
                if desc:IsA("BasePart") then
                    desc.Anchored = true
                    desc.CanCollide = false
                elseif desc:IsA("Script") or desc:IsA("LocalScript") then
                    desc:Destroy()
                end
            end
            clone.Parent = viewport
        end
    end
end
-- 초기 복제 (성능이 문제가 되면 간략화된 블록으로 대체)
task.spawn(cloneWorldToViewport)

------------------------------------------------------------------------
-- UPDATE LOOP
------------------------------------------------------------------------
RunService.Heartbeat:Connect(function()
    local character = player.Character
    if not character then return end
    local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
    if not root then return end

    local pos = root.Position
    local _, yRot, _ = root.CFrame:ToEulerAnglesYXZ()

    -- 카메라를 플레이어 위에 배치 (탑다운)
    local rotation = if CONFIG.RotateWithPlayer then CFrame.Angles(0, -yRot, 0) else CFrame.new()
    vpCamera.CFrame = CFrame.new(pos + Vector3.new(0, zoomHeight, 0))
        * CFrame.Angles(-math.pi / 2, 0, 0)
        * (if CONFIG.RotateWithPlayer then CFrame.Angles(0, 0, yRot) else CFrame.new())

    -- 마커 위치 업데이트
    local halfSize = CONFIG.Size / 2
    local scale = halfSize / zoomHeight -- 월드 studs -> 픽셀 변환

    for _, marker in markers do
        local worldPos: Vector3
        if marker.worldObject and marker.worldObject.Parent then
            worldPos = marker.worldObject.Position
        elseif marker.worldPosition then
            worldPos = marker.worldPosition
        else
            marker.dot.Visible = false
            continue
        end

        local offset = worldPos - pos
        local localX, localZ: number
        if CONFIG.RotateWithPlayer then
            -- 플레이어 기준 회전 적용
            local cosY = math.cos(-yRot)
            local sinY = math.sin(-yRot)
            localX = offset.X * cosY - offset.Z * sinY
            localZ = offset.X * sinY + offset.Z * cosY
        else
            localX = offset.X
            localZ = offset.Z
        end

        local px = 0.5 + (localX * scale) / CONFIG.Size
        local py = 0.5 + (localZ * scale) / CONFIG.Size

        -- 범위 밖이면 숨기기
        local dist = math.sqrt((px - 0.5)^2 + (py - 0.5)^2)
        if dist > 0.45 then
            marker.dot.Visible = false
        else
            marker.dot.Visible = true
            marker.dot.Position = UDim2.new(px, 0, py, 0)
        end
    end

    -- 나침반 업데이트
    for _, child in markersFrame:GetChildren() do
        local angle = child:GetAttribute("CompassAngle")
        if angle then
            local rad = math.rad(angle) - (if CONFIG.RotateWithPlayer then yRot else 0)
            local dist = 0.42
            child.Position = UDim2.new(0.5 + math.sin(rad) * dist, 0, 0.5 - math.cos(rad) * dist, 0)
        end
    end

    -- 방향 화살표 회전
    if not CONFIG.RotateWithPlayer then
        playerDot.Rotation = math.deg(yRot)
    else
        playerDot.Rotation = 0
    end
end)

------------------------------------------------------------------------
-- 다른 플레이어 자동 추적
------------------------------------------------------------------------
local function trackPlayer(otherPlayer: Player)
    otherPlayer.CharacterAdded:Connect(function(char)
        local root = char:WaitForChild("HumanoidRootPart") :: BasePart
        addMarker("player_" .. otherPlayer.Name, CONFIG.AllyColor, CONFIG.EnemyDotSize, root, nil)
    end)
    if otherPlayer.Character then
        local root = otherPlayer.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
        if root then
            addMarker("player_" .. otherPlayer.Name, CONFIG.AllyColor, CONFIG.EnemyDotSize, root, nil)
        end
    end
    otherPlayer.CharacterRemoving:Connect(function()
        removeMarker("player_" .. otherPlayer.Name)
    end)
end

for _, p in Players:GetPlayers() do
    if p ~= player then trackPlayer(p) end
end
Players.PlayerAdded:Connect(function(p)
    if p ~= player then trackPlayer(p) end
end)
Players.PlayerRemoving:Connect(function(p)
    removeMarker("player_" .. p.Name)
end)
```

## 사용 예시

```lua
-- POI 마커 추가
addPOIMarker("shop", Vector3.new(100, 0, 50))

-- 적 마커 추가
local enemyPart = workspace.Enemies.Goblin.HumanoidRootPart
addEnemyMarker("goblin1", enemyPart)

-- 마커 제거
removeMarker("goblin1")

-- 줌 변경
zoomHeight = 120
```



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
