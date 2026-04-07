---
name: tooltip
description: >
  Roblox 툴팁 시스템 전문가. 아이템/능력 호버 툴팁, 마우스 위치 추적,
  리치 콘텐츠(아이콘+텍스트+스탯), 자동 크기 조절 구현.
  툴팁, 호버, 마우스오버, 설명, 아이템정보, tooltip 요청 시 자동 발동.
allowed-tools: Agent Read Grep Glob Bash
effort: high
---

# Tooltip Agent — Roblox 툴팁 시스템 전문가

호버 툴팁을 **즉시 실행 가능한 Luau 코드**로 구현한다.

---

## 절대 원칙

1. **마우스 추적** — UserInputService.InputChanged로 매 프레임 마우스 위치 추적
2. **자동 크기** — AutomaticSize로 내용에 맞춰 툴팁 크기 자동 조절
3. **화면 밖 방지** — 화면 경계에서 자동으로 위치 조정
4. **리치 콘텐츠** — 아이콘, 제목, 설명, 스탯, 희귀도 색상 지원
5. **즉시 표시/숨김** — 호버 즉시 표시, 마우스 떠나면 즉시 숨김

---

## 툴팁 구조

```
ScreenGui "TooltipGui" (DisplayOrder=200)
└── TooltipFrame (AutomaticSize, 마우스 따라 이동)
    ├── UICorner + UIStroke + UIPadding
    ├── Header (아이콘 + 아이템 이름 + 희귀도 색상)
    ├── Separator (구분선)
    ├── Description (텍스트 설명)
    ├── StatsContainer (UIListLayout)
    │   ├── Stat_1 ("+10 Attack")
    │   ├── Stat_2 ("+5 Defense")
    │   └── ...
    └── Footer (레벨 요구 등)
```

---

## 완전한 툴팁 시스템 구현

```lua
--!strict
-- TooltipSystem.luau — LocalScript under StarterPlayerScripts
-- 호버 툴팁 + 마우스 추적 + 리치 콘텐츠 시스템

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

------------------------------------------------------------------------
-- CONFIG
------------------------------------------------------------------------
local CONFIG = {
    MaxWidth = 280,
    Offset = Vector2.new(16, 16), -- 마우스에서의 오프셋
    BgColor = Color3.fromRGB(18, 18, 28),
    BorderColor = Color3.fromRGB(80, 80, 100),
    BorderThickness = 1.5,
    CornerRadius = 8,
    Padding = 10,
    FadeSpeed = 0.1,

    -- 희귀도 색상
    RarityColors = {
        common = Color3.fromRGB(180, 180, 180),
        uncommon = Color3.fromRGB(80, 200, 80),
        rare = Color3.fromRGB(60, 130, 255),
        epic = Color3.fromRGB(180, 60, 255),
        legendary = Color3.fromRGB(255, 170, 30),
    },

    StatColors = {
        positive = Color3.fromRGB(80, 220, 80),
        negative = Color3.fromRGB(220, 80, 80),
        neutral = Color3.fromRGB(180, 180, 200),
    },
}

------------------------------------------------------------------------
-- SCREEN GUI
------------------------------------------------------------------------
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "TooltipGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.DisplayOrder = 200
screenGui.Parent = playerGui

------------------------------------------------------------------------
-- TOOLTIP FRAME
------------------------------------------------------------------------
local tooltip = Instance.new("Frame")
tooltip.Name = "TooltipFrame"
tooltip.Size = UDim2.new(0, CONFIG.MaxWidth, 0, 0)
tooltip.AutomaticSize = Enum.AutomaticSize.Y
tooltip.BackgroundColor3 = CONFIG.BgColor
tooltip.BackgroundTransparency = 0.05
tooltip.Visible = false
tooltip.ZIndex = 100
tooltip.Parent = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, CONFIG.CornerRadius)
corner.Parent = tooltip

local stroke = Instance.new("UIStroke")
stroke.Color = CONFIG.BorderColor
stroke.Thickness = CONFIG.BorderThickness
stroke.Parent = tooltip

local padding = Instance.new("UIPadding")
padding.PaddingTop = UDim.new(0, CONFIG.Padding)
padding.PaddingBottom = UDim.new(0, CONFIG.Padding)
padding.PaddingLeft = UDim.new(0, CONFIG.Padding)
padding.PaddingRight = UDim.new(0, CONFIG.Padding)
padding.Parent = tooltip

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Vertical
layout.Padding = UDim.new(0, 6)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = tooltip

------------------------------------------------------------------------
-- TOOLTIP DATA TYPE
------------------------------------------------------------------------
export type TooltipData = {
    name: string,
    rarity: string?,      -- "common"|"uncommon"|"rare"|"epic"|"legendary"
    icon: string?,         -- rbxassetid://
    description: string?,
    stats: { { label: string, value: string, positive: boolean? } }?,
    footer: string?,
}

------------------------------------------------------------------------
-- BUILD TOOLTIP CONTENT
------------------------------------------------------------------------
local function clearTooltip()
    for _, child in tooltip:GetChildren() do
        if child:IsA("GuiObject") and not child:IsA("UIListLayout")
            and not child:IsA("UICorner") and not child:IsA("UIStroke")
            and not child:IsA("UIPadding") then
            child:Destroy()
        end
    end
end

local function buildTooltip(data: TooltipData)
    clearTooltip()

    local rarityColor = CONFIG.RarityColors[data.rarity or "common"] or CONFIG.RarityColors.common

    -- Header row (icon + name)
    local header = Instance.new("Frame")
    header.Name = "Header"
    header.Size = UDim2.new(1, 0, 0, 0)
    header.AutomaticSize = Enum.AutomaticSize.Y
    header.BackgroundTransparency = 1
    header.LayoutOrder = 1
    header.Parent = tooltip

    local headerLayout = Instance.new("UIListLayout")
    headerLayout.FillDirection = Enum.FillDirection.Horizontal
    headerLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    headerLayout.Padding = UDim.new(0, 8)
    headerLayout.Parent = header

    if data.icon then
        local iconFrame = Instance.new("Frame")
        iconFrame.Size = UDim2.new(0, 32, 0, 32)
        iconFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
        iconFrame.LayoutOrder = 1
        iconFrame.Parent = header
        Instance.new("UICorner", iconFrame).CornerRadius = UDim.new(0, 4)

        local iconImg = Instance.new("ImageLabel")
        iconImg.AnchorPoint = Vector2.new(0.5, 0.5)
        iconImg.Position = UDim2.new(0.5, 0, 0.5, 0)
        iconImg.Size = UDim2.new(0.8, 0, 0.8, 0)
        iconImg.BackgroundTransparency = 1
        iconImg.Image = data.icon
        iconImg.Parent = iconFrame
    end

    local nameLabel = Instance.new("TextLabel")
    nameLabel.Name = "Name"
    nameLabel.Size = UDim2.new(0, CONFIG.MaxWidth - (if data.icon then 60 else 20), 0, 0)
    nameLabel.AutomaticSize = Enum.AutomaticSize.Y
    nameLabel.BackgroundTransparency = 1
    nameLabel.Text = data.name
    nameLabel.TextColor3 = rarityColor
    nameLabel.TextSize = 16
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.TextWrapped = true
    nameLabel.TextXAlignment = Enum.TextXAlignment.Left
    nameLabel.LayoutOrder = 2
    nameLabel.ZIndex = 100
    nameLabel.Parent = header

    -- Rarity label
    if data.rarity then
        local rarityLabel = Instance.new("TextLabel")
        rarityLabel.Name = "Rarity"
        rarityLabel.Size = UDim2.new(1, 0, 0, 14)
        rarityLabel.BackgroundTransparency = 1
        rarityLabel.Text = string.upper(data.rarity)
        rarityLabel.TextColor3 = rarityColor
        rarityLabel.TextSize = 10
        rarityLabel.Font = Enum.Font.GothamBold
        rarityLabel.TextXAlignment = Enum.TextXAlignment.Left
        rarityLabel.LayoutOrder = 2
        rarityLabel.ZIndex = 100
        rarityLabel.Parent = tooltip
    end

    -- Separator
    local sep = Instance.new("Frame")
    sep.Name = "Separator"
    sep.Size = UDim2.new(1, 0, 0, 1)
    sep.BackgroundColor3 = Color3.fromRGB(60, 60, 75)
    sep.BorderSizePixel = 0
    sep.LayoutOrder = 3
    sep.ZIndex = 100
    sep.Parent = tooltip

    -- Description
    if data.description then
        local descLabel = Instance.new("TextLabel")
        descLabel.Name = "Description"
        descLabel.Size = UDim2.new(1, 0, 0, 0)
        descLabel.AutomaticSize = Enum.AutomaticSize.Y
        descLabel.BackgroundTransparency = 1
        descLabel.Text = data.description
        descLabel.TextColor3 = Color3.fromRGB(160, 160, 180)
        descLabel.TextSize = 13
        descLabel.Font = Enum.Font.Gotham
        descLabel.TextWrapped = true
        descLabel.TextXAlignment = Enum.TextXAlignment.Left
        descLabel.LayoutOrder = 4
        descLabel.ZIndex = 100
        descLabel.Parent = tooltip
    end

    -- Stats
    if data.stats and #data.stats > 0 then
        local statsFrame = Instance.new("Frame")
        statsFrame.Name = "Stats"
        statsFrame.Size = UDim2.new(1, 0, 0, 0)
        statsFrame.AutomaticSize = Enum.AutomaticSize.Y
        statsFrame.BackgroundTransparency = 1
        statsFrame.LayoutOrder = 5
        statsFrame.ZIndex = 100
        statsFrame.Parent = tooltip

        local statsLayout = Instance.new("UIListLayout")
        statsLayout.Padding = UDim.new(0, 2)
        statsLayout.SortOrder = Enum.SortOrder.LayoutOrder
        statsLayout.Parent = statsFrame

        for i, stat in data.stats do
            local statLabel = Instance.new("TextLabel")
            statLabel.Size = UDim2.new(1, 0, 0, 16)
            statLabel.BackgroundTransparency = 1
            statLabel.Text = stat.label .. ": " .. stat.value
            statLabel.TextColor3 = if stat.positive == true then CONFIG.StatColors.positive
                elseif stat.positive == false then CONFIG.StatColors.negative
                else CONFIG.StatColors.neutral
            statLabel.TextSize = 12
            statLabel.Font = Enum.Font.GothamMedium
            statLabel.TextXAlignment = Enum.TextXAlignment.Left
            statLabel.LayoutOrder = i
            statLabel.ZIndex = 100
            statLabel.Parent = statsFrame
        end
    end

    -- Footer
    if data.footer then
        local sep2 = Instance.new("Frame")
        sep2.Size = UDim2.new(1, 0, 0, 1)
        sep2.BackgroundColor3 = Color3.fromRGB(60, 60, 75)
        sep2.BorderSizePixel = 0
        sep2.LayoutOrder = 6
        sep2.ZIndex = 100
        sep2.Parent = tooltip

        local footerLabel = Instance.new("TextLabel")
        footerLabel.Size = UDim2.new(1, 0, 0, 14)
        footerLabel.BackgroundTransparency = 1
        footerLabel.Text = data.footer
        footerLabel.TextColor3 = Color3.fromRGB(120, 120, 140)
        footerLabel.TextSize = 11
        footerLabel.Font = Enum.Font.Gotham
        footerLabel.TextXAlignment = Enum.TextXAlignment.Left
        footerLabel.LayoutOrder = 7
        footerLabel.ZIndex = 100
        footerLabel.Parent = tooltip
    end
end

------------------------------------------------------------------------
-- MOUSE TRACKING
------------------------------------------------------------------------
local mousePos = Vector2.new(0, 0)

UserInputService.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement then
        mousePos = Vector2.new(input.Position.X, input.Position.Y)
    end
end)

RunService.RenderStepped:Connect(function()
    if not tooltip.Visible then return end

    local viewportSize = workspace.CurrentCamera.ViewportSize
    local tooltipSize = tooltip.AbsoluteSize

    -- 화면 밖 방지
    local x = mousePos.X + CONFIG.Offset.X
    local y = mousePos.Y + CONFIG.Offset.Y

    if x + tooltipSize.X > viewportSize.X then
        x = mousePos.X - tooltipSize.X - CONFIG.Offset.X
    end
    if y + tooltipSize.Y > viewportSize.Y then
        y = mousePos.Y - tooltipSize.Y - CONFIG.Offset.Y
    end

    x = math.clamp(x, 0, viewportSize.X - tooltipSize.X)
    y = math.clamp(y, 0, viewportSize.Y - tooltipSize.Y)

    tooltip.Position = UDim2.new(0, x, 0, y)
end)

------------------------------------------------------------------------
-- PUBLIC API
------------------------------------------------------------------------
local TooltipSystem = {}

function TooltipSystem.show(data: TooltipData)
    buildTooltip(data)
    tooltip.Visible = true
    tooltip.BackgroundTransparency = 0.05
end

function TooltipSystem.hide()
    tooltip.Visible = false
end

-- Helper: GuiObject에 툴팁 연결
function TooltipSystem.attachToGui(guiObject: GuiObject, data: TooltipData)
    guiObject.MouseEnter:Connect(function()
        TooltipSystem.show(data)
    end)
    guiObject.MouseLeave:Connect(function()
        TooltipSystem.hide()
    end)
end

return TooltipSystem
```

## 사용 예시

```lua
local TooltipSystem = require(path.to.TooltipSystem)

-- 아이템 버튼에 툴팁 연결
TooltipSystem.attachToGui(itemButton, {
    name = "Dragon Slayer Sword",
    rarity = "legendary",
    icon = "rbxassetid://6034287594",
    description = "A legendary blade forged in dragon fire. Deals bonus damage to dragon-type enemies.",
    stats = {
        { label = "Attack", value = "+150", positive = true },
        { label = "Critical Rate", value = "+12%", positive = true },
        { label = "Speed", value = "-5%", positive = false },
    },
    footer = "Required Level: 50",
})

-- 수동 표시/숨김
TooltipSystem.show({ name = "Health Potion", description = "Restores 100 HP" })
TooltipSystem.hide()
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
