---
name: hud
description: >
  Roblox HUD 시스템 전문가. Health bar, Mana bar, Stamina bar, XP bar, 미니맵 인디케이터,
  상태 아이콘, 보스 체력바를 TweenService 애니메이션과 함께 구현.
  체력바, 마나바, 스태미나, 경험치, HUD, 헤드업디스플레이, 보스바, 상태표시 요청 시 자동 발동.
allowed-tools: Agent Read Grep Glob Bash
effort: high
---

# HUD Agent — Roblox HUD 시스템 전문가

모든 HUD 요소를 **즉시 실행 가능한 Luau 코드**로 구현한다.

---

## 절대 원칙

1. **ScreenGui 설정** — `ResetOnSpawn = false`, `ZIndexBehavior = Sibling`, `IgnoreGuiInset = true`
2. **TweenService 애니메이션** — 모든 값 변경은 부드러운 트윈으로
3. **모듈화** — 각 바는 독립 모듈, 개별 토글 가능
4. **성능** — 불필요한 매 프레임 업데이트 금지, 이벤트 기반으로 갱신
5. **Parent 마지막** — 모든 속성 설정 후 Parent 지정
6. **UICorner + UIStroke** — 모든 바에 둥근 모서리와 테두리 적용

---

## HUD 구조

```
ScreenGui "HUD" (ResetOnSpawn=false, IgnoreGuiInset=true)
├── BarsContainer (좌하단, UIListLayout)
│   ├── HealthBar (빨강, Humanoid.Health 자동 연동)
│   ├── ManaBar (파랑, RemoteEvent 연동)
│   ├── StaminaBar (노랑, RemoteEvent 연동)
│   └── XPBar (초록, RemoteEvent 연동)
├── StatusIcons (좌하단 위, UIListLayout 수평)
│   └── StatusIcon_N (아이콘 + 타이머)
├── BossHealthBar (상단 중앙)
│   ├── BossName (TextLabel)
│   └── BarBg > Fill (빨강 그라데이션)
└── MinimapIndicator (우상단 작은 점)
```

---

## 완전한 HUD 시스템 구현

```lua
--!strict
-- HUDSystem.luau — LocalScript under StarterPlayerScripts
-- 완전한 HUD: 체력바, 마나바, 스태미나바, XP바, 상태 아이콘, 보스 체력바

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

------------------------------------------------------------------------
-- CONFIG
------------------------------------------------------------------------
local CONFIG = {
    BarWidth = 260,
    BarHeight = 24,
    BarCornerRadius = 6,
    BarSpacing = 6,
    TweenSpeed = 0.3,
    TweenEasing = Enum.EasingStyle.Quad,

    HealthColor = Color3.fromRGB(220, 50, 50),
    HealthBgColor = Color3.fromRGB(80, 20, 20),
    ManaColor = Color3.fromRGB(50, 120, 220),
    ManaBgColor = Color3.fromRGB(20, 40, 80),
    StaminaColor = Color3.fromRGB(220, 180, 30),
    StaminaBgColor = Color3.fromRGB(80, 65, 10),
    XPColor = Color3.fromRGB(80, 220, 80),
    XPBgColor = Color3.fromRGB(25, 70, 25),

    BossBarWidth = 500,
    BossBarHeight = 30,
    BossColor = Color3.fromRGB(200, 40, 40),
    BossBgColor = Color3.fromRGB(60, 15, 15),

    MaxStatusIcons = 8,
    StatusIconSize = 36,
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
    s.Color = color
    s.Thickness = thickness
    s.Parent = parent
end

local function addGradient(parent: GuiObject)
    local g = Instance.new("UIGradient")
    g.Rotation = 90
    g.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0),
        NumberSequenceKeypoint.new(0.5, 0.15),
        NumberSequenceKeypoint.new(1, 0.35),
    })
    g.Parent = parent
end

------------------------------------------------------------------------
-- SCREEN GUI
------------------------------------------------------------------------
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "HUD"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.DisplayOrder = 5
screenGui.Parent = playerGui

------------------------------------------------------------------------
-- BAR SYSTEM
------------------------------------------------------------------------
local barsContainer = Instance.new("Frame")
barsContainer.Name = "BarsContainer"
barsContainer.AnchorPoint = Vector2.new(0, 1)
barsContainer.Position = UDim2.new(0, 20, 1, -20)
barsContainer.Size = UDim2.new(0, CONFIG.BarWidth, 0, 0)
barsContainer.AutomaticSize = Enum.AutomaticSize.Y
barsContainer.BackgroundTransparency = 1
barsContainer.Parent = screenGui

local barsLayout = Instance.new("UIListLayout")
barsLayout.FillDirection = Enum.FillDirection.Vertical
barsLayout.SortOrder = Enum.SortOrder.LayoutOrder
barsLayout.Padding = UDim.new(0, CONFIG.BarSpacing)
barsLayout.Parent = barsContainer

type BarObject = {
    frame: Frame,
    fill: Frame,
    label: TextLabel,
    tweenObj: Tween?,
    setValue: (BarObject, number, number) -> (),
}

local function createBar(name: string, order: number, fillColor: Color3, bgColor: Color3): BarObject
    local frame = Instance.new("Frame")
    frame.Name = name .. "Bar"
    frame.Size = UDim2.new(1, 0, 0, CONFIG.BarHeight)
    frame.BackgroundColor3 = bgColor
    frame.LayoutOrder = order
    addCorner(frame, CONFIG.BarCornerRadius)
    addStroke(frame, Color3.fromRGB(0, 0, 0), 1.5)
    frame.Parent = barsContainer

    local fill = Instance.new("Frame")
    fill.Name = "Fill"
    fill.Size = UDim2.new(1, 0, 1, 0)
    fill.BackgroundColor3 = fillColor
    fill.BorderSizePixel = 0
    addCorner(fill, CONFIG.BarCornerRadius)
    addGradient(fill)
    fill.Parent = frame

    local label = Instance.new("TextLabel")
    label.Name = "Label"
    label.AnchorPoint = Vector2.new(0.5, 0.5)
    label.Position = UDim2.new(0.5, 0, 0.5, 0)
    label.Size = UDim2.new(1, -8, 1, 0)
    label.BackgroundTransparency = 1
    label.Text = "100 / 100"
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.TextStrokeTransparency = 0.5
    label.TextSize = 14
    label.Font = Enum.Font.GothamBold
    label.Parent = frame

    local bar: BarObject = {
        frame = frame,
        fill = fill,
        label = label,
        tweenObj = nil,
        setValue = function() end,
    }

    function bar.setValue(self: BarObject, current: number, max: number)
        local clamped = math.clamp(current, 0, max)
        local ratio = if max > 0 then clamped / max else 0
        if self.tweenObj then self.tweenObj:Cancel() end
        self.tweenObj = TweenService:Create(
            self.fill,
            TweenInfo.new(CONFIG.TweenSpeed, CONFIG.TweenEasing, Enum.EasingDirection.Out),
            { Size = UDim2.new(ratio, 0, 1, 0) }
        )
        self.tweenObj:Play()
        self.label.Text = string.format("%d / %d", math.floor(clamped), math.floor(max))
    end

    return bar
end

local healthBar = createBar("Health", 1, CONFIG.HealthColor, CONFIG.HealthBgColor)
local manaBar = createBar("Mana", 2, CONFIG.ManaColor, CONFIG.ManaBgColor)
local staminaBar = createBar("Stamina", 3, CONFIG.StaminaColor, CONFIG.StaminaBgColor)
local xpBar = createBar("XP", 4, CONFIG.XPColor, CONFIG.XPBgColor)

------------------------------------------------------------------------
-- STATUS ICONS
------------------------------------------------------------------------
local statusContainer = Instance.new("Frame")
statusContainer.Name = "StatusIcons"
statusContainer.AnchorPoint = Vector2.new(0, 1)
statusContainer.Position = UDim2.new(0, 20, 1, -170)
statusContainer.Size = UDim2.new(0, CONFIG.StatusIconSize * CONFIG.MaxStatusIcons + 28, 0, CONFIG.StatusIconSize)
statusContainer.BackgroundTransparency = 1
statusContainer.Parent = screenGui

local statusLayout = Instance.new("UIListLayout")
statusLayout.FillDirection = Enum.FillDirection.Horizontal
statusLayout.Padding = UDim.new(0, 4)
statusLayout.SortOrder = Enum.SortOrder.LayoutOrder
statusLayout.Parent = statusContainer

local activeIcons: { [string]: Frame } = {}
local iconOrder = 0

local function addStatusIcon(id: string, imageId: string, duration: number?)
    if activeIcons[id] then return end
    iconOrder += 1

    local frame = Instance.new("Frame")
    frame.Name = "Status_" .. id
    frame.Size = UDim2.new(0, CONFIG.StatusIconSize, 0, CONFIG.StatusIconSize)
    frame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    frame.BackgroundTransparency = 0.3
    frame.LayoutOrder = iconOrder
    addCorner(frame, 6)
    addStroke(frame, Color3.fromRGB(200, 200, 200), 1)

    local icon = Instance.new("ImageLabel")
    icon.AnchorPoint = Vector2.new(0.5, 0.5)
    icon.Position = UDim2.new(0.5, 0, 0.45, 0)
    icon.Size = UDim2.new(0.7, 0, 0.7, 0)
    icon.BackgroundTransparency = 1
    icon.Image = imageId
    icon.Parent = frame

    local timer = Instance.new("TextLabel")
    timer.AnchorPoint = Vector2.new(0.5, 1)
    timer.Position = UDim2.new(0.5, 0, 1, -2)
    timer.Size = UDim2.new(1, 0, 0, 10)
    timer.BackgroundTransparency = 1
    timer.TextColor3 = Color3.fromRGB(255, 255, 255)
    timer.TextSize = 9
    timer.Font = Enum.Font.GothamBold
    timer.Text = ""
    timer.Parent = frame

    frame.Parent = statusContainer
    activeIcons[id] = frame

    if duration and duration > 0 then
        task.spawn(function()
            local remaining = duration
            while remaining > 0 and activeIcons[id] do
                timer.Text = tostring(math.ceil(remaining))
                task.wait(1)
                remaining -= 1
            end
            if activeIcons[id] then
                local fadeOut = TweenService:Create(frame, TweenInfo.new(0.3), { BackgroundTransparency = 1 })
                fadeOut:Play()
                fadeOut.Completed:Wait()
                frame:Destroy()
                activeIcons[id] = nil
            end
        end)
    end
end

local function removeStatusIcon(id: string)
    local frame = activeIcons[id]
    if frame then
        frame:Destroy()
        activeIcons[id] = nil
    end
end

------------------------------------------------------------------------
-- BOSS HEALTH BAR
------------------------------------------------------------------------
local bossFrame = Instance.new("Frame")
bossFrame.Name = "BossHealthBar"
bossFrame.AnchorPoint = Vector2.new(0.5, 0)
bossFrame.Position = UDim2.new(0.5, 0, 0, 40)
bossFrame.Size = UDim2.new(0, CONFIG.BossBarWidth, 0, CONFIG.BossBarHeight + 28)
bossFrame.BackgroundTransparency = 1
bossFrame.Visible = false
bossFrame.Parent = screenGui

local bossName = Instance.new("TextLabel")
bossName.Size = UDim2.new(1, 0, 0, 22)
bossName.BackgroundTransparency = 1
bossName.Text = "Boss"
bossName.TextColor3 = Color3.fromRGB(255, 60, 60)
bossName.TextSize = 18
bossName.Font = Enum.Font.GothamBold
bossName.TextStrokeTransparency = 0.4
bossName.Parent = bossFrame

local bossBg = Instance.new("Frame")
bossBg.Position = UDim2.new(0, 0, 0, 24)
bossBg.Size = UDim2.new(1, 0, 0, CONFIG.BossBarHeight)
bossBg.BackgroundColor3 = CONFIG.BossBgColor
addCorner(bossBg, 4)
addStroke(bossBg, Color3.fromRGB(150, 30, 30), 2)
bossBg.Parent = bossFrame

local bossFill = Instance.new("Frame")
bossFill.Size = UDim2.new(1, 0, 1, 0)
bossFill.BackgroundColor3 = CONFIG.BossColor
addCorner(bossFill, 4)
addGradient(bossFill)
bossFill.Parent = bossBg

local bossPercent = Instance.new("TextLabel")
bossPercent.AnchorPoint = Vector2.new(0.5, 0.5)
bossPercent.Position = UDim2.new(0.5, 0, 0.5, 0)
bossPercent.Size = UDim2.new(1, 0, 1, 0)
bossPercent.BackgroundTransparency = 1
bossPercent.Text = "100%"
bossPercent.TextColor3 = Color3.fromRGB(255, 255, 255)
bossPercent.TextStrokeTransparency = 0.3
bossPercent.TextSize = 16
bossPercent.Font = Enum.Font.GothamBold
bossPercent.Parent = bossBg

local bossTween: Tween? = nil

local function showBossBar(name: string, current: number, max: number)
    bossFrame.Visible = true
    bossName.Text = name
    local ratio = if max > 0 then math.clamp(current / max, 0, 1) else 0
    if bossTween then bossTween:Cancel() end
    bossTween = TweenService:Create(bossFill,
        TweenInfo.new(CONFIG.TweenSpeed, CONFIG.TweenEasing),
        { Size = UDim2.new(ratio, 0, 1, 0) })
    bossTween:Play()
    bossPercent.Text = string.format("%.0f%%", ratio * 100)
end

local function hideBossBar()
    local t = TweenService:Create(bossFrame, TweenInfo.new(0.5), { Position = UDim2.new(0.5, 0, 0, -60) })
    t:Play()
    t.Completed:Connect(function()
        bossFrame.Visible = false
        bossFrame.Position = UDim2.new(0.5, 0, 0, 40)
    end)
end

------------------------------------------------------------------------
-- CHARACTER HEALTH AUTO-BIND
------------------------------------------------------------------------
local function onCharacterAdded(character: Model)
    local humanoid = character:WaitForChild("Humanoid") :: Humanoid
    healthBar:setValue(humanoid.Health, humanoid.MaxHealth)
    humanoid.HealthChanged:Connect(function(newHealth)
        healthBar:setValue(newHealth, humanoid.MaxHealth)
    end)
    humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(function()
        healthBar:setValue(humanoid.Health, humanoid.MaxHealth)
    end)
end
if player.Character then task.spawn(onCharacterAdded, player.Character) end
player.CharacterAdded:Connect(onCharacterAdded)

------------------------------------------------------------------------
-- REMOTE EVENT LISTENERS
------------------------------------------------------------------------
local function safeListen(name: string, cb: (...any) -> ())
    local e = ReplicatedStorage:FindFirstChild(name)
    if e and e:IsA("RemoteEvent") then
        (e :: RemoteEvent).OnClientEvent:Connect(cb)
    end
end

safeListen("UpdateMana", function(cur, max) manaBar:setValue(cur, max) end)
safeListen("UpdateStamina", function(cur, max) staminaBar:setValue(cur, max) end)
safeListen("UpdateXP", function(cur, max) xpBar:setValue(cur, max) end)
safeListen("ShowBossBar", function(n, cur, max) showBossBar(n, cur, max) end)
safeListen("HideBossBar", function() hideBossBar() end)
safeListen("AddStatusIcon", function(id, img, dur) addStatusIcon(id, img, dur) end)
safeListen("RemoveStatusIcon", function(id) removeStatusIcon(id) end)
```

## 서버측 RemoteEvent 생성

```lua
-- ServerScriptService > Script
local RS = game:GetService("ReplicatedStorage")
for _, name in {"UpdateMana","UpdateStamina","UpdateXP","ShowBossBar","HideBossBar","AddStatusIcon","RemoveStatusIcon"} do
    if not RS:FindFirstChild(name) then
        local r = Instance.new("RemoteEvent")
        r.Name = name
        r.Parent = RS
    end
end
```

## 사용 예시

```lua
-- 서버에서 마나 업데이트
ReplicatedStorage.UpdateMana:FireClient(player, 50, 100)

-- 보스바 표시
ReplicatedStorage.ShowBossBar:FireAllClients("드래곤 로드", 8000, 10000)

-- 상태 아이콘 (독 30초)
ReplicatedStorage.AddStatusIcon:FireClient(player, "poison", "rbxassetid://6034287594", 30)
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
