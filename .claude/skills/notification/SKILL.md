---
name: notification
description: >
  Roblox 알림 시스템 전문가. 토스트 알림, 업적 팝업, 데미지 넘버, 아이템 획득 표시,
  큐 시스템을 통한 순차적 알림 표시 구현.
  알림, 토스트, 팝업, 업적, 공지, 메시지, 획득, notification 요청 시 자동 발동.
allowed-tools: Agent Read Grep Glob Bash
effort: high
---

# Notification Agent — Roblox 알림 시스템 전문가

모든 게임 내 알림을 **즉시 실행 가능한 Luau 코드**로 구현한다.

---

## 절대 원칙

1. **큐 시스템** — 알림이 겹치지 않도록 큐로 순차 표시
2. **TweenService 애니메이션** — 슬라이드 인/아웃, 페이드, 스케일 효과
3. **자동 소멸** — 지정 시간 후 자동으로 페이드 아웃 및 제거
4. **타입별 스타일** — 정보/성공/경고/에러/업적 각각 다른 색상과 아이콘
5. **스택 관리** — 동시에 표시되는 알림 수 제한, 오래된 것부터 제거

---

## 알림 구조

```
ScreenGui "NotificationGui"
├── ToastContainer (우상단, UIListLayout 수직)
│   └── Toast_N (슬라이드 인 → 대기 → 페이드 아웃)
├── AchievementPopup (화면 중앙 상단)
│   ├── Icon + Title + Description
│   └── 스케일 인 → 대기 → 슬라이드 아웃
├── ItemPickupContainer (화면 하단 중앙)
│   └── ItemPickup_N (아이템 아이콘 + 이름 + 수량)
└── DamageNumberContainer (월드 공간 BillboardGui)
```

---

## 완전한 알림 시스템 구현

```lua
--!strict
-- NotificationSystem.luau — LocalScript under StarterPlayerScripts
-- 토스트, 업적 팝업, 아이템 획득, 데미지 넘버 통합 알림 시스템

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

------------------------------------------------------------------------
-- CONFIG
------------------------------------------------------------------------
local CONFIG = {
    MaxToasts = 5,
    ToastDuration = 4,
    ToastWidth = 320,
    ToastHeight = 60,
    ToastSlideSpeed = 0.35,

    AchievementDuration = 5,

    ItemPickupDuration = 3,
    MaxItemPickups = 4,

    -- 타입별 색상
    Colors = {
        info = Color3.fromRGB(60, 130, 220),
        success = Color3.fromRGB(50, 180, 80),
        warning = Color3.fromRGB(220, 170, 30),
        error = Color3.fromRGB(220, 50, 50),
        achievement = Color3.fromRGB(220, 180, 50),
    },
}

------------------------------------------------------------------------
-- HELPERS
------------------------------------------------------------------------
local function addCorner(parent: GuiObject, radius: number)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius)
    c.Parent = parent
end

local function addStroke(parent: GuiObject, color: Color3, thickness: number)
    local s = Instance.new("UIStroke")
    s.Color = color; s.Thickness = thickness
    s.Parent = parent
end

------------------------------------------------------------------------
-- SCREEN GUI
------------------------------------------------------------------------
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "NotificationGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.DisplayOrder = 50
screenGui.Parent = playerGui

------------------------------------------------------------------------
-- TOAST SYSTEM
------------------------------------------------------------------------
local toastContainer = Instance.new("Frame")
toastContainer.Name = "ToastContainer"
toastContainer.AnchorPoint = Vector2.new(1, 0)
toastContainer.Position = UDim2.new(1, -20, 0, 80)
toastContainer.Size = UDim2.new(0, CONFIG.ToastWidth, 1, -100)
toastContainer.BackgroundTransparency = 1
toastContainer.Parent = screenGui

local toastLayout = Instance.new("UIListLayout")
toastLayout.FillDirection = Enum.FillDirection.Vertical
toastLayout.VerticalAlignment = Enum.VerticalAlignment.Top
toastLayout.Padding = UDim.new(0, 8)
toastLayout.SortOrder = Enum.SortOrder.LayoutOrder
toastLayout.Parent = toastContainer

local toastQueue: { { text: string, type: string, icon: string? } } = {}
local activeToasts = 0
local toastOrder = 0

local function processToastQueue()
    if #toastQueue == 0 or activeToasts >= CONFIG.MaxToasts then return end
    local data = table.remove(toastQueue, 1)
    if not data then return end
    activeToasts += 1
    toastOrder += 1

    local color = CONFIG.Colors[data.type] or CONFIG.Colors.info

    -- Toast frame
    local toast = Instance.new("Frame")
    toast.Name = "Toast"
    toast.Size = UDim2.new(1, 0, 0, CONFIG.ToastHeight)
    toast.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
    toast.BackgroundTransparency = 0.1
    toast.LayoutOrder = toastOrder
    toast.ClipsDescendants = true
    addCorner(toast, 8)
    addStroke(toast, color, 1.5)

    -- Accent bar (left side color)
    local accent = Instance.new("Frame")
    accent.Size = UDim2.new(0, 4, 1, 0)
    accent.BackgroundColor3 = color
    accent.BorderSizePixel = 0
    accent.Parent = toast

    -- Icon (optional)
    if data.icon then
        local icon = Instance.new("ImageLabel")
        icon.AnchorPoint = Vector2.new(0, 0.5)
        icon.Position = UDim2.new(0, 14, 0.5, 0)
        icon.Size = UDim2.new(0, 28, 0, 28)
        icon.BackgroundTransparency = 1
        icon.Image = data.icon
        icon.ImageColor3 = color
        icon.Parent = toast
    end

    -- Text
    local textLabel = Instance.new("TextLabel")
    textLabel.AnchorPoint = Vector2.new(0, 0.5)
    textLabel.Position = UDim2.new(0, if data.icon then 50 else 16, 0.5, 0)
    textLabel.Size = UDim2.new(1, if data.icon then -60 else -24, 0, 40)
    textLabel.BackgroundTransparency = 1
    textLabel.Text = data.text
    textLabel.TextColor3 = Color3.fromRGB(230, 230, 230)
    textLabel.TextSize = 14
    textLabel.Font = Enum.Font.GothamMedium
    textLabel.TextWrapped = true
    textLabel.TextXAlignment = Enum.TextXAlignment.Left
    textLabel.Parent = toast

    -- Slide in from right
    toast.Position = UDim2.new(1, 0, 0, 0) -- offscreen right
    toast.Parent = toastContainer
    TweenService:Create(toast, TweenInfo.new(CONFIG.ToastSlideSpeed, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
        { Position = UDim2.new(0, 0, 0, 0) }):Play()

    -- Auto remove
    task.delay(CONFIG.ToastDuration, function()
        local fadeOut = TweenService:Create(toast,
            TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
            { BackgroundTransparency = 1, Position = UDim2.new(1, 0, 0, 0) })
        fadeOut:Play()
        fadeOut.Completed:Wait()
        toast:Destroy()
        activeToasts -= 1
        processToastQueue()
    end)
end

local function showToast(text: string, toastType: string?, icon: string?)
    table.insert(toastQueue, { text = text, type = toastType or "info", icon = icon })
    processToastQueue()
end

------------------------------------------------------------------------
-- ACHIEVEMENT POPUP
------------------------------------------------------------------------
local function showAchievement(title: string, description: string, icon: string?)
    local popup = Instance.new("Frame")
    popup.Name = "AchievementPopup"
    popup.AnchorPoint = Vector2.new(0.5, 0)
    popup.Position = UDim2.new(0.5, 0, 0, 30)
    popup.Size = UDim2.new(0, 400, 0, 80)
    popup.BackgroundColor3 = Color3.fromRGB(30, 28, 15)
    popup.BackgroundTransparency = 0.05
    addCorner(popup, 12)
    addStroke(popup, CONFIG.Colors.achievement, 2)
    popup.Parent = screenGui

    -- Gradient
    local grad = Instance.new("UIGradient")
    grad.Rotation = 90
    grad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(50, 45, 20)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(25, 23, 10)),
    })
    grad.Parent = popup

    -- Icon
    if icon then
        local img = Instance.new("ImageLabel")
        img.AnchorPoint = Vector2.new(0, 0.5)
        img.Position = UDim2.new(0, 12, 0.5, 0)
        img.Size = UDim2.new(0, 50, 0, 50)
        img.BackgroundTransparency = 1
        img.Image = icon
        img.Parent = popup
    end

    -- "ACHIEVEMENT UNLOCKED"
    local header = Instance.new("TextLabel")
    header.Position = UDim2.new(0, if icon then 72 else 16, 0, 8)
    header.Size = UDim2.new(1, -80, 0, 18)
    header.BackgroundTransparency = 1
    header.Text = "ACHIEVEMENT UNLOCKED"
    header.TextColor3 = CONFIG.Colors.achievement
    header.TextSize = 12
    header.Font = Enum.Font.GothamBold
    header.TextXAlignment = Enum.TextXAlignment.Left
    header.Parent = popup

    -- Title
    local titleLabel = Instance.new("TextLabel")
    titleLabel.Position = UDim2.new(0, if icon then 72 else 16, 0, 28)
    titleLabel.Size = UDim2.new(1, -80, 0, 22)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Text = title
    titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    titleLabel.TextSize = 18
    titleLabel.Font = Enum.Font.GothamBold
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.Parent = popup

    -- Description
    local desc = Instance.new("TextLabel")
    desc.Position = UDim2.new(0, if icon then 72 else 16, 0, 52)
    desc.Size = UDim2.new(1, -80, 0, 18)
    desc.BackgroundTransparency = 1
    desc.Text = description
    desc.TextColor3 = Color3.fromRGB(180, 180, 160)
    desc.TextSize = 13
    desc.Font = Enum.Font.Gotham
    desc.TextXAlignment = Enum.TextXAlignment.Left
    desc.Parent = popup

    -- Animate in (scale up)
    popup.Size = UDim2.new(0, 0, 0, 0)
    TweenService:Create(popup,
        TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
        { Size = UDim2.new(0, 400, 0, 80) }):Play()

    -- Auto remove
    task.delay(CONFIG.AchievementDuration, function()
        local slideOut = TweenService:Create(popup,
            TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
            { Position = UDim2.new(0.5, 0, 0, -100), BackgroundTransparency = 1 })
        slideOut:Play()
        slideOut.Completed:Wait()
        popup:Destroy()
    end)
end

------------------------------------------------------------------------
-- ITEM PICKUP DISPLAY
------------------------------------------------------------------------
local itemContainer = Instance.new("Frame")
itemContainer.Name = "ItemPickupContainer"
itemContainer.AnchorPoint = Vector2.new(0.5, 1)
itemContainer.Position = UDim2.new(0.5, 0, 1, -120)
itemContainer.Size = UDim2.new(0, 300, 0, 0)
itemContainer.AutomaticSize = Enum.AutomaticSize.Y
itemContainer.BackgroundTransparency = 1
itemContainer.Parent = screenGui

local itemLayout = Instance.new("UIListLayout")
itemLayout.FillDirection = Enum.FillDirection.Vertical
itemLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
itemLayout.Padding = UDim.new(0, 4)
itemLayout.SortOrder = Enum.SortOrder.LayoutOrder
itemLayout.Parent = itemContainer

local itemPickupOrder = 0

local function showItemPickup(itemName: string, quantity: number, icon: string?)
    itemPickupOrder += 1
    local frame = Instance.new("Frame")
    frame.Name = "ItemPickup"
    frame.Size = UDim2.new(1, 0, 0, 36)
    frame.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
    frame.BackgroundTransparency = 0.2
    frame.LayoutOrder = itemPickupOrder
    addCorner(frame, 6)
    addStroke(frame, Color3.fromRGB(100, 180, 255), 1)

    if icon then
        local img = Instance.new("ImageLabel")
        img.AnchorPoint = Vector2.new(0, 0.5)
        img.Position = UDim2.new(0, 6, 0.5, 0)
        img.Size = UDim2.new(0, 24, 0, 24)
        img.BackgroundTransparency = 1
        img.Image = icon
        img.Parent = frame
    end

    local text = Instance.new("TextLabel")
    text.AnchorPoint = Vector2.new(0, 0.5)
    text.Position = UDim2.new(0, if icon then 36 else 10, 0.5, 0)
    text.Size = UDim2.new(1, -50, 1, 0)
    text.BackgroundTransparency = 1
    text.Text = string.format("+%d %s", quantity, itemName)
    text.TextColor3 = Color3.fromRGB(100, 200, 255)
    text.TextSize = 14
    text.Font = Enum.Font.GothamBold
    text.TextXAlignment = Enum.TextXAlignment.Left
    text.Parent = frame

    -- Slide in
    frame.BackgroundTransparency = 1
    frame.Parent = itemContainer
    TweenService:Create(frame, TweenInfo.new(0.3, Enum.EasingStyle.Back),
        { BackgroundTransparency = 0.2 }):Play()

    -- Auto remove
    task.delay(CONFIG.ItemPickupDuration, function()
        local fade = TweenService:Create(frame, TweenInfo.new(0.3), { BackgroundTransparency = 1 })
        fade:Play()
        fade.Completed:Wait()
        frame:Destroy()
    end)
end

------------------------------------------------------------------------
-- DAMAGE NUMBERS (BillboardGui)
------------------------------------------------------------------------
local function showDamageNumber(position: Vector3, damage: number, damageType: string?)
    local color: Color3
    local size: number
    if damageType == "crit" then
        color = Color3.fromRGB(255, 220, 50)
        size = 28
    elseif damageType == "heal" then
        color = Color3.fromRGB(80, 255, 80)
        size = 22
    else
        color = Color3.fromRGB(255, 255, 255)
        size = 20
    end

    local part = Instance.new("Part")
    part.Size = Vector3.new(0.1, 0.1, 0.1)
    part.Position = position + Vector3.new(math.random(-10, 10) / 10, 1, math.random(-10, 10) / 10)
    part.Anchored = true
    part.CanCollide = false
    part.Transparency = 1
    part.Parent = workspace

    local billboard = Instance.new("BillboardGui")
    billboard.Size = UDim2.new(0, 100, 0, 50)
    billboard.StudsOffset = Vector3.new(0, 0, 0)
    billboard.AlwaysOnTop = true
    billboard.Parent = part

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.Text = if damageType == "heal" then "+" .. tostring(math.floor(damage)) else tostring(math.floor(damage))
    label.TextColor3 = color
    label.TextSize = size
    label.Font = Enum.Font.GothamBlack
    label.TextStrokeTransparency = 0.3
    label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    label.Parent = billboard

    -- Float up and fade
    local floatTween = TweenService:Create(part,
        TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { Position = part.Position + Vector3.new(0, 3, 0) })
    floatTween:Play()

    local fadeTween = TweenService:Create(label,
        TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
        { TextTransparency = 1, TextStrokeTransparency = 1 })
    fadeTween:Play()

    fadeTween.Completed:Wait()
    part:Destroy()
end

------------------------------------------------------------------------
-- REMOTE EVENT LISTENERS
------------------------------------------------------------------------
local function safeListen(name: string, cb: (...any) -> ())
    local e = ReplicatedStorage:FindFirstChild(name)
    if e and e:IsA("RemoteEvent") then
        (e :: RemoteEvent).OnClientEvent:Connect(cb)
    end
end

safeListen("ShowToast", function(text, toastType, icon)
    showToast(text, toastType, icon)
end)

safeListen("ShowAchievement", function(title, desc, icon)
    showAchievement(title, desc, icon)
end)

safeListen("ShowItemPickup", function(name, qty, icon)
    showItemPickup(name, qty, icon)
end)

safeListen("ShowDamageNumber", function(pos, dmg, dmgType)
    showDamageNumber(pos, dmg, dmgType)
end)
```

## 사용 예시

```lua
-- 토스트 알림
showToast("서버에 접속했습니다!", "success")
showToast("체력이 낮습니다!", "warning", "rbxassetid://6034287594")

-- 업적 팝업
showAchievement("첫 킬", "첫 번째 적을 처치했습니다!", "rbxassetid://6034287594")

-- 아이템 획득
showItemPickup("철 검", 1, "rbxassetid://6034287594")

-- 데미지 넘버
showDamageNumber(Vector3.new(0, 5, 0), 150, "crit")

-- 서버에서 클라이언트로
ReplicatedStorage.ShowToast:FireClient(player, "환영합니다!", "info")
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
