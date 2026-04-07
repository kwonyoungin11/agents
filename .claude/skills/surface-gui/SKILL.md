---
name: surface-gui
description: |
  SurfaceGui 파트 적용 (스크린, 표지판, 버튼), 인터랙티브 표면 버튼, 디스플레이 보드, 화면 UI 시스템.
  SurfaceGui on parts for screens, signs, buttons, interactive surface elements, display boards, in-world UI panels, dynamic content rendering.
allowed-tools:
  - Bash
  - Edit
  - Write
  - Read
  - Glob
  - Grep
effort: high
---

# SurfaceGui System (Screens, Signs, Buttons)

This skill covers SurfaceGui creation and configuration for in-world screens, signs, interactive buttons, display boards, and dynamic content panels in Roblox.

---

## 1. SurfaceGui Foundation

```luau
--!strict
-- ModuleScript: SurfaceGui builder with sensible defaults

local SurfaceGuiBuilder = {}

export type SurfaceGuiConfig = {
    face: Enum.NormalId?,
    pixelsPerStud: number?,
    sizingMode: Enum.SurfaceGuiSizingMode?,
    alwaysOnTop: boolean?,
    maxDistance: number?,
    brightness: number?,
    lightInfluence: number?,
    clipsDescendants: boolean?,
}

--- Creates a SurfaceGui with standard configuration.
function SurfaceGuiBuilder.create(part: BasePart, config: SurfaceGuiConfig?): SurfaceGui
    local cfg = config or {}
    local gui = Instance.new("SurfaceGui")
    gui.Face = cfg.face or Enum.NormalId.Front
    gui.PixelsPerStud = cfg.pixelsPerStud or 50
    gui.SizingMode = cfg.sizingMode or Enum.SurfaceGuiSizingMode.PixelsPerStud
    gui.AlwaysOnTop = cfg.alwaysOnTop or false
    gui.MaxDistance = cfg.maxDistance or 0 -- 0 = infinite
    gui.Brightness = cfg.brightness or 1
    gui.LightInfluence = cfg.lightInfluence or 0.5
    gui.ClipsDescendants = if cfg.clipsDescendants ~= nil then cfg.clipsDescendants else true
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Parent = part
    return gui
end

return SurfaceGuiBuilder
```

---

## 2. In-World Screen System

```luau
--!strict
-- ModuleScript: Full screen display on a part (monitors, TVs, info panels)

local TweenService = game:GetService("TweenService")

local ScreenDisplay = {}

export type ScreenConfig = {
    title: string?,
    bodyText: string?,
    backgroundColor: Color3?,
    textColor: Color3?,
    headerColor: Color3?,
    fontSize: number?,
    padding: number?,
}

--- Creates a complete screen UI on a SurfaceGui (title bar + body).
function ScreenDisplay.createInfoScreen(surfaceGui: SurfaceGui, config: ScreenConfig): Frame
    local mainFrame = Instance.new("Frame")
    mainFrame.Size = UDim2.fromScale(1, 1)
    mainFrame.BackgroundColor3 = config.backgroundColor or Color3.fromRGB(20, 20, 30)
    mainFrame.BorderSizePixel = 0
    mainFrame.Parent = surfaceGui

    local padding = Instance.new("UIPadding")
    local pad = UDim.new(0, config.padding or 8)
    padding.PaddingTop = pad
    padding.PaddingBottom = pad
    padding.PaddingLeft = pad
    padding.PaddingRight = pad
    padding.Parent = mainFrame

    local layout = Instance.new("UIListLayout")
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, 6)
    layout.Parent = mainFrame

    -- Title bar
    if config.title then
        local titleLabel = Instance.new("TextLabel")
        titleLabel.Size = UDim2.new(1, 0, 0, 40)
        titleLabel.BackgroundColor3 = config.headerColor or Color3.fromRGB(40, 80, 180)
        titleLabel.TextColor3 = config.textColor or Color3.fromRGB(255, 255, 255)
        titleLabel.Text = config.title
        titleLabel.TextScaled = true
        titleLabel.Font = Enum.Font.GothamBold
        titleLabel.LayoutOrder = 1
        titleLabel.Parent = mainFrame

        local titleCorner = Instance.new("UICorner")
        titleCorner.CornerRadius = UDim.new(0, 4)
        titleCorner.Parent = titleLabel
    end

    -- Body text
    if config.bodyText then
        local bodyLabel = Instance.new("TextLabel")
        bodyLabel.Size = UDim2.new(1, 0, 1, -50)
        bodyLabel.BackgroundTransparency = 1
        bodyLabel.TextColor3 = config.textColor or Color3.fromRGB(200, 200, 210)
        bodyLabel.Text = config.bodyText
        bodyLabel.TextWrapped = true
        bodyLabel.TextScaled = false
        bodyLabel.TextSize = config.fontSize or 18
        bodyLabel.Font = Enum.Font.Gotham
        bodyLabel.TextXAlignment = Enum.TextXAlignment.Left
        bodyLabel.TextYAlignment = Enum.TextYAlignment.Top
        bodyLabel.LayoutOrder = 2
        bodyLabel.Parent = mainFrame
    end

    return mainFrame
end

--- Updates text content on an existing screen.
function ScreenDisplay.updateContent(mainFrame: Frame, title: string?, body: string?)
    for _, child in mainFrame:GetChildren() do
        if child:IsA("TextLabel") then
            if child.LayoutOrder == 1 and title then
                child.Text = title
            elseif child.LayoutOrder == 2 and body then
                child.Text = body
            end
        end
    end
end

return ScreenDisplay
```

---

## 3. Interactive Surface Buttons

```luau
--!strict
-- ModuleScript: Clickable buttons on SurfaceGui with hover/press feedback

local TweenService = game:GetService("TweenService")

local SurfaceButton = {}

export type ButtonConfig = {
    text: string,
    size: UDim2?,
    position: UDim2?,
    backgroundColor: Color3?,
    hoverColor: Color3?,
    pressColor: Color3?,
    textColor: Color3?,
    font: Enum.Font?,
    cornerRadius: number?,
    onClick: (() -> ())?,
}

--- Creates an interactive button inside a SurfaceGui.
--- NOTE: SurfaceGui buttons require ClickDetector on the parent part
--- or the player must have a Mouse/Touch target on the SurfaceGui.
function SurfaceButton.create(parent: GuiObject, config: ButtonConfig): TextButton
    local button = Instance.new("TextButton")
    button.Size = config.size or UDim2.new(0.8, 0, 0, 50)
    button.Position = config.position or UDim2.new(0.1, 0, 0.5, -25)
    button.BackgroundColor3 = config.backgroundColor or Color3.fromRGB(50, 120, 220)
    button.TextColor3 = config.textColor or Color3.fromRGB(255, 255, 255)
    button.Text = config.text
    button.TextScaled = true
    button.Font = config.font or Enum.Font.GothamBold
    button.AutoButtonColor = false
    button.BorderSizePixel = 0
    button.Parent = parent

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, config.cornerRadius or 8)
    corner.Parent = button

    -- Hover effect
    local normalColor = config.backgroundColor or Color3.fromRGB(50, 120, 220)
    local hoverColor = config.hoverColor or Color3.fromRGB(70, 150, 255)
    local pressColor = config.pressColor or Color3.fromRGB(30, 80, 180)

    local tweenInfo = TweenInfo.new(0.15, Enum.EasingStyle.Quad)

    button.MouseEnter:Connect(function()
        TweenService:Create(button, tweenInfo, { BackgroundColor3 = hoverColor }):Play()
    end)

    button.MouseLeave:Connect(function()
        TweenService:Create(button, tweenInfo, { BackgroundColor3 = normalColor }):Play()
    end)

    button.MouseButton1Down:Connect(function()
        TweenService:Create(button, tweenInfo, { BackgroundColor3 = pressColor }):Play()
    end)

    button.MouseButton1Up:Connect(function()
        TweenService:Create(button, tweenInfo, { BackgroundColor3 = hoverColor }):Play()
    end)

    if config.onClick then
        button.MouseButton1Click:Connect(config.onClick)
    end

    return button
end

--- Creates a button group (vertical list of buttons).
function SurfaceButton.createGroup(parent: GuiObject, buttons: { ButtonConfig }): Frame
    local frame = Instance.new("Frame")
    frame.Size = UDim2.fromScale(1, 1)
    frame.BackgroundTransparency = 1
    frame.Parent = parent

    local layout = Instance.new("UIListLayout")
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    layout.Padding = UDim.new(0, 8)
    layout.Parent = frame

    for i, config in buttons do
        local btn = SurfaceButton.create(frame, config)
        btn.LayoutOrder = i
    end

    return frame
end

return SurfaceButton
```

---

## 4. Display Board (Scoreboard / Leaderboard)

```luau
--!strict
-- ModuleScript: Dynamic scoreboard/leaderboard on a SurfaceGui

local DisplayBoard = {}

export type LeaderboardEntry = {
    rank: number,
    name: string,
    score: number,
}

--- Creates a leaderboard display on a SurfaceGui.
function DisplayBoard.createLeaderboard(surfaceGui: SurfaceGui, title: string, entries: { LeaderboardEntry }): Frame
    local frame = Instance.new("Frame")
    frame.Size = UDim2.fromScale(1, 1)
    frame.BackgroundColor3 = Color3.fromRGB(15, 15, 25)
    frame.BorderSizePixel = 0
    frame.Parent = surfaceGui

    local padding = Instance.new("UIPadding")
    padding.PaddingTop = UDim.new(0, 10)
    padding.PaddingLeft = UDim.new(0, 10)
    padding.PaddingRight = UDim.new(0, 10)
    padding.Parent = frame

    local layout = Instance.new("UIListLayout")
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, 4)
    layout.Parent = frame

    -- Title
    local titleLabel = Instance.new("TextLabel")
    titleLabel.Size = UDim2.new(1, 0, 0, 36)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Text = title
    titleLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
    titleLabel.TextScaled = true
    titleLabel.Font = Enum.Font.GothamBold
    titleLabel.LayoutOrder = 0
    titleLabel.Parent = frame

    -- Entries
    local rankColors = {
        [1] = Color3.fromRGB(255, 215, 0),   -- Gold
        [2] = Color3.fromRGB(192, 192, 192), -- Silver
        [3] = Color3.fromRGB(205, 127, 50),  -- Bronze
    }

    for i, entry in entries do
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, 0, 0, 28)
        row.BackgroundColor3 = if i % 2 == 0 then Color3.fromRGB(25, 25, 40) else Color3.fromRGB(20, 20, 32)
        row.BorderSizePixel = 0
        row.LayoutOrder = i
        row.Parent = frame

        local rowCorner = Instance.new("UICorner")
        rowCorner.CornerRadius = UDim.new(0, 4)
        rowCorner.Parent = row

        local rankLabel = Instance.new("TextLabel")
        rankLabel.Size = UDim2.new(0.15, 0, 1, 0)
        rankLabel.Position = UDim2.new(0, 0, 0, 0)
        rankLabel.BackgroundTransparency = 1
        rankLabel.Text = `#{entry.rank}`
        rankLabel.TextColor3 = rankColors[entry.rank] or Color3.fromRGB(180, 180, 190)
        rankLabel.TextScaled = true
        rankLabel.Font = Enum.Font.GothamBold
        rankLabel.Parent = row

        local nameLabel = Instance.new("TextLabel")
        nameLabel.Size = UDim2.new(0.55, 0, 1, 0)
        nameLabel.Position = UDim2.new(0.15, 0, 0, 0)
        nameLabel.BackgroundTransparency = 1
        nameLabel.Text = entry.name
        nameLabel.TextColor3 = Color3.fromRGB(220, 220, 230)
        nameLabel.TextScaled = true
        nameLabel.Font = Enum.Font.Gotham
        nameLabel.TextXAlignment = Enum.TextXAlignment.Left
        nameLabel.Parent = row

        local scoreLabel = Instance.new("TextLabel")
        scoreLabel.Size = UDim2.new(0.3, 0, 1, 0)
        scoreLabel.Position = UDim2.new(0.7, 0, 0, 0)
        scoreLabel.BackgroundTransparency = 1
        scoreLabel.Text = tostring(entry.score)
        scoreLabel.TextColor3 = Color3.fromRGB(100, 200, 255)
        scoreLabel.TextScaled = true
        scoreLabel.Font = Enum.Font.GothamBold
        scoreLabel.TextXAlignment = Enum.TextXAlignment.Right
        scoreLabel.Parent = row
    end

    return frame
end

--- Updates the leaderboard with new data (destroys and recreates entries).
function DisplayBoard.updateLeaderboard(surfaceGui: SurfaceGui, title: string, entries: { LeaderboardEntry })
    for _, child in surfaceGui:GetChildren() do
        child:Destroy()
    end
    DisplayBoard.createLeaderboard(surfaceGui, title, entries)
end

return DisplayBoard
```

---

## 5. Sign Factory

```luau
--!strict
-- ModuleScript: Quick sign creation helpers

local SurfaceGuiBuilder = require(script.Parent.SurfaceGuiBuilder)

local SignFactory = {}

--- Creates a simple text sign on a part.
function SignFactory.createTextSign(part: BasePart, text: string, config: {
    face: Enum.NormalId?,
    textColor: Color3?,
    backgroundColor: Color3?,
    font: Enum.Font?,
}?): SurfaceGui
    local cfg = config or {}
    local gui = SurfaceGuiBuilder.create(part, { face = cfg.face })

    local label = Instance.new("TextLabel")
    label.Size = UDim2.fromScale(1, 1)
    label.BackgroundColor3 = cfg.backgroundColor or Color3.fromRGB(40, 40, 50)
    label.BackgroundTransparency = 0
    label.TextColor3 = cfg.textColor or Color3.fromRGB(255, 255, 255)
    label.Text = text
    label.TextScaled = true
    label.Font = cfg.font or Enum.Font.GothamBold
    label.Parent = gui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = label

    return gui
end

--- Creates a warning sign with hazard stripe styling.
function SignFactory.createWarningSign(part: BasePart, text: string, face: Enum.NormalId?): SurfaceGui
    local gui = SurfaceGuiBuilder.create(part, { face = face })

    local bg = Instance.new("Frame")
    bg.Size = UDim2.fromScale(1, 1)
    bg.BackgroundColor3 = Color3.fromRGB(255, 200, 0)
    bg.BorderSizePixel = 0
    bg.Parent = gui

    local inner = Instance.new("Frame")
    inner.Size = UDim2.new(1, -16, 1, -16)
    inner.Position = UDim2.fromOffset(8, 8)
    inner.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    inner.BorderSizePixel = 0
    inner.Parent = bg

    local label = Instance.new("TextLabel")
    label.Size = UDim2.fromScale(1, 1)
    label.BackgroundTransparency = 1
    label.TextColor3 = Color3.fromRGB(255, 200, 0)
    label.Text = "WARNING\n" .. text
    label.TextScaled = true
    label.Font = Enum.Font.GothamBold
    label.TextWrapped = true
    label.Parent = inner

    return gui
end

return SignFactory
```

---

## Key Design Principles

1. **PixelsPerStud**: Higher = sharper text but more memory. Use 50 for signs, 25 for large walls.
2. **LightInfluence**: 0 = fully self-lit (screens), 1 = matches world lighting (signs).
3. **MaxDistance**: Set > 0 to hide GUI at distance (performance optimization).
4. **AlwaysOnTop**: Only for critical HUD-like surfaces; breaks depth perception otherwise.
5. **SizingMode**: Use `PixelsPerStud` for consistent resolution across part sizes.

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

- `face` (string) - Surface face: "Front", "Back", "Top", "Bottom", "Left", "Right"
- `pixels_per_stud` (number) - Resolution of the SurfaceGui (default: 50)
- `title` (string) - Screen/sign title text
- `body_text` (string) - Screen body content
- `background_color` (Color3) - Background color of the screen
- `text_color` (Color3) - Text color
- `max_distance` (number) - Max render distance (0 = infinite)
- `always_on_top` (boolean) - Whether to render on top of 3D
- `light_influence` (number) - How much world lighting affects the GUI (0-1)
- `button_texts` (table) - Array of button label strings
- `leaderboard_data` (table) - Array of {rank, name, score} entries
