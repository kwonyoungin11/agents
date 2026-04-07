---
name: billboard-gui
description: |
  BillboardGui 네임태그, NPC 위 체력바, 부유 텍스트, 거리 기반 가시성, 3D 공간 UI 오버레이.
  BillboardGui for name tags, health bars above NPCs, floating text labels, distance-based visibility, always-facing-camera UI, status indicators.
allowed-tools:
  - Bash
  - Edit
  - Write
  - Read
  - Glob
  - Grep
effort: high
---

# BillboardGui System (Name Tags, Health Bars, Floating Text)

This skill covers BillboardGui creation for name tags, health bars, floating text, status indicators, and distance-based visibility controls in Roblox.

---

## 1. BillboardGui Builder

```luau
--!strict
-- ModuleScript: BillboardGui creation utilities

local BillboardBuilder = {}

export type BillboardConfig = {
    size: UDim2?,
    studOffset: Vector3?,
    studsOffsetWorldSpace: Vector3?,
    maxDistance: number?,
    alwaysOnTop: boolean?,
    lightInfluence: number?,
    clipsDescendants: boolean?,
    active: boolean?,
}

--- Creates a base BillboardGui attached to an adornee.
function BillboardBuilder.create(adornee: Instance, config: BillboardConfig?): BillboardGui
    local cfg = config or {}
    local bbGui = Instance.new("BillboardGui")
    bbGui.Size = cfg.size or UDim2.fromOffset(200, 50)
    bbGui.StudsOffset = cfg.studOffset or Vector3.new(0, 3, 0)
    bbGui.StudsOffsetWorldSpace = cfg.studsOffsetWorldSpace or Vector3.zero
    bbGui.MaxDistance = cfg.maxDistance or 50
    bbGui.AlwaysOnTop = cfg.alwaysOnTop or false
    bbGui.LightInfluence = cfg.lightInfluence or 0
    bbGui.ClipsDescendants = if cfg.clipsDescendants ~= nil then cfg.clipsDescendants else true
    bbGui.Active = cfg.active or false
    bbGui.Adornee = adornee
    bbGui.Parent = adornee
    return bbGui
end

return BillboardBuilder
```

---

## 2. Name Tag System

```luau
--!strict
-- ModuleScript: Player/NPC name tags with customizable styling

local BillboardBuilder = require(script.Parent.BillboardBuilder)
local TweenService = game:GetService("TweenService")

local NameTag = {}

export type NameTagConfig = {
    displayName: string,
    titleText: string?,
    nameColor: Color3?,
    titleColor: Color3?,
    backgroundColor: Color3?,
    backgroundTransparency: number?,
    maxDistance: number?,
    offsetY: number?,
}

--- Creates a name tag above a character or model.
function NameTag.create(adornee: Instance, config: NameTagConfig): BillboardGui
    local bbGui = BillboardBuilder.create(adornee, {
        size = UDim2.fromOffset(200, config.titleText and 55 or 30),
        studOffset = Vector3.new(0, config.offsetY or 3, 0),
        maxDistance = config.maxDistance or 50,
        alwaysOnTop = false,
    })

    local container = Instance.new("Frame")
    container.Size = UDim2.fromScale(1, 1)
    container.BackgroundColor3 = config.backgroundColor or Color3.fromRGB(0, 0, 0)
    container.BackgroundTransparency = config.backgroundTransparency or 0.5
    container.BorderSizePixel = 0
    container.Parent = bbGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = container

    local layout = Instance.new("UIListLayout")
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    layout.Padding = UDim.new(0, 2)
    layout.Parent = container

    -- Title (optional, e.g., "Guild Master", "Boss")
    if config.titleText then
        local titleLabel = Instance.new("TextLabel")
        titleLabel.Size = UDim2.new(1, 0, 0, 18)
        titleLabel.BackgroundTransparency = 1
        titleLabel.Text = config.titleText
        titleLabel.TextColor3 = config.titleColor or Color3.fromRGB(255, 215, 0)
        titleLabel.TextScaled = true
        titleLabel.Font = Enum.Font.GothamBold
        titleLabel.LayoutOrder = 1
        titleLabel.Parent = container
    end

    -- Name
    local nameLabel = Instance.new("TextLabel")
    nameLabel.Name = "NameLabel"
    nameLabel.Size = UDim2.new(1, 0, 0, 24)
    nameLabel.BackgroundTransparency = 1
    nameLabel.Text = config.displayName
    nameLabel.TextColor3 = config.nameColor or Color3.fromRGB(255, 255, 255)
    nameLabel.TextScaled = true
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.LayoutOrder = 2
    nameLabel.Parent = container

    return bbGui
end

--- Updates the name displayed on the tag.
function NameTag.setName(bbGui: BillboardGui, newName: string)
    local nameLabel = bbGui:FindFirstChild("NameLabel", true)
    if nameLabel and nameLabel:IsA("TextLabel") then
        nameLabel.Text = newName
    end
end

return NameTag
```

---

## 3. Health Bar System

```luau
--!strict
-- ModuleScript: Health bar above NPCs/players with smooth animations

local TweenService = game:GetService("TweenService")
local BillboardBuilder = require(script.Parent.BillboardBuilder)

local HealthBar = {}

export type HealthBarConfig = {
    maxHealth: number?,
    barWidth: number?,
    barHeight: number?,
    fillColor: Color3?,
    damageColor: Color3?,
    backgroundColor: Color3?,
    showText: boolean?,
    offsetY: number?,
    maxDistance: number?,
}

--- Creates a health bar above an adornee.
function HealthBar.create(adornee: Instance, config: HealthBarConfig?): BillboardGui
    local cfg = config or {}
    local barWidth = cfg.barWidth or 180
    local barHeight = cfg.barHeight or 12

    local bbGui = BillboardBuilder.create(adornee, {
        size = UDim2.fromOffset(barWidth + 10, barHeight + (if cfg.showText then 22 else 4)),
        studOffset = Vector3.new(0, cfg.offsetY or 2.5, 0),
        maxDistance = cfg.maxDistance or 40,
        alwaysOnTop = false,
    })

    local container = Instance.new("Frame")
    container.Name = "HealthContainer"
    container.Size = UDim2.fromScale(1, 1)
    container.BackgroundTransparency = 1
    container.Parent = bbGui

    -- Background bar
    local bgBar = Instance.new("Frame")
    bgBar.Name = "BackgroundBar"
    bgBar.Size = UDim2.new(1, 0, 0, barHeight)
    bgBar.Position = UDim2.new(0, 0, 0, 0)
    bgBar.BackgroundColor3 = cfg.backgroundColor or Color3.fromRGB(40, 40, 40)
    bgBar.BorderSizePixel = 0
    bgBar.Parent = container

    local bgCorner = Instance.new("UICorner")
    bgCorner.CornerRadius = UDim.new(0, 4)
    bgCorner.Parent = bgBar

    -- Damage flash bar (shows red briefly on damage)
    local damageBar = Instance.new("Frame")
    damageBar.Name = "DamageBar"
    damageBar.Size = UDim2.fromScale(1, 1)
    damageBar.BackgroundColor3 = cfg.damageColor or Color3.fromRGB(200, 50, 50)
    damageBar.BorderSizePixel = 0
    damageBar.Parent = bgBar

    local dmgCorner = Instance.new("UICorner")
    dmgCorner.CornerRadius = UDim.new(0, 4)
    dmgCorner.Parent = damageBar

    -- Fill bar
    local fillBar = Instance.new("Frame")
    fillBar.Name = "FillBar"
    fillBar.Size = UDim2.fromScale(1, 1)
    fillBar.BackgroundColor3 = cfg.fillColor or Color3.fromRGB(80, 200, 80)
    fillBar.BorderSizePixel = 0
    fillBar.Parent = bgBar

    local fillCorner = Instance.new("UICorner")
    fillCorner.CornerRadius = UDim.new(0, 4)
    fillCorner.Parent = fillBar

    -- Health text (optional)
    if cfg.showText then
        local textLabel = Instance.new("TextLabel")
        textLabel.Name = "HealthText"
        textLabel.Size = UDim2.new(1, 0, 0, 18)
        textLabel.Position = UDim2.new(0, 0, 0, barHeight + 2)
        textLabel.BackgroundTransparency = 1
        textLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
        textLabel.TextStrokeTransparency = 0.5
        textLabel.Text = `{cfg.maxHealth or 100}/{cfg.maxHealth or 100}`
        textLabel.TextScaled = true
        textLabel.Font = Enum.Font.GothamBold
        textLabel.Parent = container
    end

    return bbGui
end

--- Updates the health bar fill amount with animation.
function HealthBar.setHealth(bbGui: BillboardGui, currentHealth: number, maxHealth: number)
    local fraction = math.clamp(currentHealth / maxHealth, 0, 1)

    local container = bbGui:FindFirstChild("HealthContainer")
    if not container then return end

    local bgBar = container:FindFirstChild("BackgroundBar")
    if not bgBar then return end

    local fillBar = bgBar:FindFirstChild("FillBar")
    local damageBar = bgBar:FindFirstChild("DamageBar")
    local healthText = container:FindFirstChild("HealthText")

    if fillBar and fillBar:IsA("Frame") then
        -- Animate fill bar
        TweenService:Create(fillBar, TweenInfo.new(0.3, Enum.EasingStyle.Quad), {
            Size = UDim2.new(fraction, 0, 1, 0),
        }):Play()

        -- Color based on health percentage
        local color: Color3
        if fraction > 0.6 then
            color = Color3.fromRGB(80, 200, 80)   -- green
        elseif fraction > 0.3 then
            color = Color3.fromRGB(230, 180, 30)  -- yellow
        else
            color = Color3.fromRGB(220, 50, 50)   -- red
        end
        TweenService:Create(fillBar, TweenInfo.new(0.3), { BackgroundColor3 = color }):Play()
    end

    -- Delayed damage bar (the red portion that catches up)
    if damageBar and damageBar:IsA("Frame") then
        task.delay(0.4, function()
            TweenService:Create(damageBar, TweenInfo.new(0.5, Enum.EasingStyle.Sine), {
                Size = UDim2.new(fraction, 0, 1, 0),
            }):Play()
        end)
    end

    -- Update text
    if healthText and healthText:IsA("TextLabel") then
        healthText.Text = `{math.floor(currentHealth)}/{math.floor(maxHealth)}`
    end
end

return HealthBar
```

---

## 4. Floating Text System

```luau
--!strict
-- ModuleScript: Floating text labels, damage numbers, notifications

local TweenService = game:GetService("TweenService")

local FloatingText = {}

--- Creates floating damage/heal numbers that rise and fade.
function FloatingText.showDamageNumber(position: Vector3, amount: number, isCrit: boolean?)
    local part = Instance.new("Part")
    part.Anchored = true
    part.CanCollide = false
    part.Transparency = 1
    part.Size = Vector3.new(0.1, 0.1, 0.1)
    part.Position = position + Vector3.new(math.random(-10, 10) / 10, 0, math.random(-10, 10) / 10)
    part.Parent = workspace

    local bbGui = Instance.new("BillboardGui")
    bbGui.Size = if isCrit then UDim2.fromOffset(120, 50) else UDim2.fromOffset(80, 35)
    bbGui.StudsOffset = Vector3.new(0, 1, 0)
    bbGui.AlwaysOnTop = true
    bbGui.MaxDistance = 60
    bbGui.Parent = part

    local label = Instance.new("TextLabel")
    label.Size = UDim2.fromScale(1, 1)
    label.BackgroundTransparency = 1
    label.Text = if isCrit then `CRIT! {amount}` else tostring(amount)
    label.TextColor3 = if isCrit then Color3.fromRGB(255, 50, 50) else Color3.fromRGB(255, 200, 50)
    label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    label.TextStrokeTransparency = 0.3
    label.TextScaled = true
    label.Font = Enum.Font.GothamBold
    label.Parent = bbGui

    -- Rise and fade animation
    local riseTween = TweenService:Create(part, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Position = part.Position + Vector3.new(0, 3, 0),
    })
    local fadeTween = TweenService:Create(label, TweenInfo.new(0.4), {
        TextTransparency = 1,
        TextStrokeTransparency = 1,
    })

    riseTween:Play()
    task.delay(0.8, function()
        fadeTween:Play()
    end)
    task.delay(1.3, function()
        part:Destroy()
    end)
end

--- Shows a floating status text above a character (e.g., "Stunned!", "Healed").
function FloatingText.showStatus(adornee: Instance, text: string, color: Color3, duration: number?)
    local dur = duration or 2

    local bbGui = Instance.new("BillboardGui")
    bbGui.Size = UDim2.fromOffset(160, 30)
    bbGui.StudsOffset = Vector3.new(0, 4, 0)
    bbGui.AlwaysOnTop = true
    bbGui.MaxDistance = 40
    bbGui.Adornee = adornee
    bbGui.Parent = adornee

    local label = Instance.new("TextLabel")
    label.Size = UDim2.fromScale(1, 1)
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = color
    label.TextStrokeTransparency = 0.4
    label.TextScaled = true
    label.Font = Enum.Font.GothamBold
    label.Parent = bbGui

    -- Fade out
    task.delay(dur - 0.5, function()
        TweenService:Create(label, TweenInfo.new(0.5), {
            TextTransparency = 1,
            TextStrokeTransparency = 1,
        }):Play()
    end)

    task.delay(dur, function()
        bbGui:Destroy()
    end)
end

return FloatingText
```

---

## 5. Distance-Based Visibility Controller

```luau
--!strict
-- ModuleScript: Controls BillboardGui visibility based on camera distance

local RunService = game:GetService("RunService")

local DistanceVisibility = {}

export type VisibilityConfig = {
    fadeStartDistance: number,   -- Distance at which fade begins
    fadeEndDistance: number,     -- Distance at which fully invisible
    updateInterval: number?,    -- Frames between updates (perf optimization)
}

--- Attaches distance-based fade to a BillboardGui.
function DistanceVisibility.attach(bbGui: BillboardGui, config: VisibilityConfig): RBXScriptConnection
    local camera = workspace.CurrentCamera
    local frameCount = 0
    local interval = config.updateInterval or 3

    local connection = RunService.Heartbeat:Connect(function()
        frameCount += 1
        if frameCount % interval ~= 0 then return end

        local adornee = bbGui.Adornee
        if not adornee or not camera then return end

        local adorneePart = if adornee:IsA("BasePart") then adornee
            elseif adornee:IsA("Model") then adornee:FindFirstChild("HumanoidRootPart")
            else nil

        if not adorneePart or not adorneePart:IsA("BasePart") then return end

        local distance = (camera.CFrame.Position - adorneePart.Position).Magnitude
        local fadeRange = config.fadeEndDistance - config.fadeStartDistance

        if distance <= config.fadeStartDistance then
            bbGui.Enabled = true
            -- Full opacity for all children
            for _, desc in bbGui:GetDescendants() do
                if desc:IsA("TextLabel") or desc:IsA("TextButton") then
                    desc.TextTransparency = 0
                elseif desc:IsA("Frame") then
                    desc.BackgroundTransparency = 0
                elseif desc:IsA("ImageLabel") then
                    desc.ImageTransparency = 0
                end
            end
        elseif distance >= config.fadeEndDistance then
            bbGui.Enabled = false
        else
            bbGui.Enabled = true
            local alpha = (distance - config.fadeStartDistance) / fadeRange
            for _, desc in bbGui:GetDescendants() do
                if desc:IsA("TextLabel") or desc:IsA("TextButton") then
                    desc.TextTransparency = alpha
                elseif desc:IsA("Frame") then
                    desc.BackgroundTransparency = alpha
                elseif desc:IsA("ImageLabel") then
                    desc.ImageTransparency = alpha
                end
            end
        end
    end)

    bbGui.Destroying:Connect(function()
        connection:Disconnect()
    end)

    return connection
end

return DistanceVisibility
```

---

## Best Practices

- **MaxDistance**: Always set a reasonable MaxDistance (30-80 studs) to avoid rendering offscreen UI
- **AlwaysOnTop**: Use sparingly; only for critical indicators like boss health or quest markers
- **StudsOffset vs StudsOffsetWorldSpace**: StudsOffset moves with the adornee; WorldSpace is absolute
- **LightInfluence = 0**: Makes text readable in dark areas (self-illuminated)
- **Performance**: Avoid updating BillboardGui every frame; use frame skipping for large numbers of NPCs

---

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

- `display_name` (string) - Name to show on the name tag
- `title_text` (string) - Optional title above the name (e.g., "Boss", "Quest Giver")
- `name_color` (Color3) - Color of the name text
- `max_health` (number) - Maximum health for health bar
- `current_health` (number) - Current health value
- `show_health_text` (boolean) - Whether to show numeric health text
- `max_distance` (number) - Maximum visibility distance in studs
- `always_on_top` (boolean) - Render on top of 3D geometry
- `offset_y` (number) - Vertical offset above the adornee in studs
- `fade_start` (number) - Distance where fade begins
- `fade_end` (number) - Distance where fully invisible
- `floating_text` (string) - Text for floating label
- `floating_color` (Color3) - Color for floating text
