---
name: menu-system
description: >
  Roblox 메뉴 시스템 전문가. 메인 메뉴(Play/Settings/Quit), 일시정지 메뉴, 설정 메뉴
  (슬라이더/토글), 메뉴 전환 애니메이션을 완벽 구현.
  메뉴, 메인메뉴, 일시정지, 설정화면, 버튼, 시작화면, 타이틀, 옵션 요청 시 자동 발동.
allowed-tools: Agent Read Grep Glob Bash
effort: high
---

# Menu System Agent — Roblox 메뉴 시스템 전문가

모든 메뉴 UI를 **즉시 실행 가능한 Luau 코드**로 구현한다.

---

## 절대 원칙

1. **ScreenGui 계층** — 메인/일시정지/설정 각각 별도 ScreenGui 또는 Frame으로 관리
2. **전환 애니메이션** — 페이드/슬라이드/스케일 트윈으로 자연스러운 전환
3. **입력 처리** — Escape로 일시정지 토글, 메뉴 활성화 시 게임 입력 차단
4. **슬라이더/토글** — 드래그 가능한 실제 슬라이더와 토글 스위치
5. **GuiService** — 메뉴 모드에서 마우스 커서 자동 표시

---

## 메뉴 구조

```
ScreenGui "MenuSystem"
├── MainMenu (타이틀 + 버튼들)
│   ├── Title (게임 이름)
│   ├── PlayButton
│   ├── SettingsButton
│   └── QuitButton
├── PauseMenu (반투명 배경 + 버튼들)
│   ├── Overlay (검정 반투명)
│   ├── ResumeButton
│   ├── SettingsButton
│   └── QuitButton
└── SettingsMenu (슬라이더, 토글, 뒤로가기)
    ├── VolumeSlider
    ├── SensitivitySlider
    ├── FullscreenToggle
    └── BackButton
```

---

## 완전한 메뉴 시스템 구현

```lua
--!strict
-- MenuSystem.luau — LocalScript under StarterPlayerScripts
-- 메인 메뉴, 일시정지 메뉴, 설정 메뉴 전체 구현

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local StarterGui = game:GetService("StarterGui")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

------------------------------------------------------------------------
-- CONFIG
------------------------------------------------------------------------
local COLORS = {
    bg = Color3.fromRGB(20, 20, 30),
    panel = Color3.fromRGB(30, 30, 45),
    accent = Color3.fromRGB(80, 140, 255),
    accentHover = Color3.fromRGB(110, 165, 255),
    text = Color3.fromRGB(240, 240, 240),
    textDim = Color3.fromRGB(160, 160, 180),
    danger = Color3.fromRGB(220, 60, 60),
    overlay = Color3.fromRGB(0, 0, 0),
    sliderBg = Color3.fromRGB(50, 50, 65),
    sliderFill = Color3.fromRGB(80, 140, 255),
    toggleOff = Color3.fromRGB(80, 80, 100),
    toggleOn = Color3.fromRGB(80, 200, 120),
}

local TWEEN_SPEED = 0.35
local BUTTON_HEIGHT = 50
local BUTTON_WIDTH = 280

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

local function tweenProp(obj: Instance, props: {[string]: any}, duration: number?)
    local t = TweenService:Create(obj,
        TweenInfo.new(duration or TWEEN_SPEED, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        props)
    t:Play()
    return t
end

------------------------------------------------------------------------
-- SCREEN GUI
------------------------------------------------------------------------
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "MenuSystem"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.DisplayOrder = 100
screenGui.Parent = playerGui

------------------------------------------------------------------------
-- BUTTON FACTORY
------------------------------------------------------------------------
local function createButton(text: string, parent: GuiObject, order: number, color: Color3?): TextButton
    local btn = Instance.new("TextButton")
    btn.Name = text .. "Button"
    btn.Size = UDim2.new(0, BUTTON_WIDTH, 0, BUTTON_HEIGHT)
    btn.BackgroundColor3 = color or COLORS.accent
    btn.Text = text
    btn.TextColor3 = COLORS.text
    btn.TextSize = 20
    btn.Font = Enum.Font.GothamBold
    btn.LayoutOrder = order
    btn.AutoButtonColor = false
    addCorner(btn, 10)
    addStroke(btn, Color3.fromRGB(255, 255, 255), 1)
    btn.Parent = parent

    -- Hover effects
    btn.MouseEnter:Connect(function()
        tweenProp(btn, { BackgroundColor3 = COLORS.accentHover, Size = UDim2.new(0, BUTTON_WIDTH + 10, 0, BUTTON_HEIGHT + 4) }, 0.15)
    end)
    btn.MouseLeave:Connect(function()
        tweenProp(btn, { BackgroundColor3 = color or COLORS.accent, Size = UDim2.new(0, BUTTON_WIDTH, 0, BUTTON_HEIGHT) }, 0.15)
    end)

    return btn
end

------------------------------------------------------------------------
-- SLIDER FACTORY
------------------------------------------------------------------------
local function createSlider(labelText: string, parent: GuiObject, order: number, default: number, callback: (number) -> ())
    local container = Instance.new("Frame")
    container.Name = labelText .. "Slider"
    container.Size = UDim2.new(1, -40, 0, 50)
    container.BackgroundTransparency = 1
    container.LayoutOrder = order
    container.Parent = parent

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(0.4, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.Text = labelText
    label.TextColor3 = COLORS.text
    label.TextSize = 16
    label.Font = Enum.Font.GothamMedium
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = container

    local track = Instance.new("Frame")
    track.AnchorPoint = Vector2.new(0, 0.5)
    track.Position = UDim2.new(0.42, 0, 0.5, 0)
    track.Size = UDim2.new(0.45, 0, 0, 8)
    track.BackgroundColor3 = COLORS.sliderBg
    addCorner(track, 4)
    track.Parent = container

    local fill = Instance.new("Frame")
    fill.Size = UDim2.new(default, 0, 1, 0)
    fill.BackgroundColor3 = COLORS.sliderFill
    addCorner(fill, 4)
    fill.Parent = track

    local knob = Instance.new("Frame")
    knob.AnchorPoint = Vector2.new(0.5, 0.5)
    knob.Position = UDim2.new(default, 0, 0.5, 0)
    knob.Size = UDim2.new(0, 20, 0, 20)
    knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    addCorner(knob, 10)
    knob.Parent = track

    local valueLabel = Instance.new("TextLabel")
    valueLabel.AnchorPoint = Vector2.new(1, 0.5)
    valueLabel.Position = UDim2.new(1, -5, 0.5, 0)
    valueLabel.Size = UDim2.new(0.1, 0, 1, 0)
    valueLabel.BackgroundTransparency = 1
    valueLabel.Text = tostring(math.floor(default * 100))
    valueLabel.TextColor3 = COLORS.textDim
    valueLabel.TextSize = 14
    valueLabel.Font = Enum.Font.GothamMedium
    valueLabel.Parent = container

    -- Drag logic
    local dragging = false
    knob.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local trackAbsPos = track.AbsolutePosition.X
            local trackAbsSize = track.AbsoluteSize.X
            local mouseX = input.Position.X
            local ratio = math.clamp((mouseX - trackAbsPos) / trackAbsSize, 0, 1)
            knob.Position = UDim2.new(ratio, 0, 0.5, 0)
            fill.Size = UDim2.new(ratio, 0, 1, 0)
            valueLabel.Text = tostring(math.floor(ratio * 100))
            callback(ratio)
        end
    end)
end

------------------------------------------------------------------------
-- TOGGLE FACTORY
------------------------------------------------------------------------
local function createToggle(labelText: string, parent: GuiObject, order: number, default: boolean, callback: (boolean) -> ())
    local container = Instance.new("Frame")
    container.Name = labelText .. "Toggle"
    container.Size = UDim2.new(1, -40, 0, 50)
    container.BackgroundTransparency = 1
    container.LayoutOrder = order
    container.Parent = parent

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(0.7, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.Text = labelText
    label.TextColor3 = COLORS.text
    label.TextSize = 16
    label.Font = Enum.Font.GothamMedium
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = container

    local track = Instance.new("TextButton")
    track.AnchorPoint = Vector2.new(1, 0.5)
    track.Position = UDim2.new(0.9, 0, 0.5, 0)
    track.Size = UDim2.new(0, 50, 0, 26)
    track.BackgroundColor3 = if default then COLORS.toggleOn else COLORS.toggleOff
    track.Text = ""
    track.AutoButtonColor = false
    addCorner(track, 13)
    track.Parent = container

    local knob = Instance.new("Frame")
    knob.AnchorPoint = Vector2.new(0.5, 0.5)
    knob.Position = UDim2.new(if default then 0.7 else 0.3, 0, 0.5, 0)
    knob.Size = UDim2.new(0, 20, 0, 20)
    knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    addCorner(knob, 10)
    knob.Parent = track

    local state = default
    track.MouseButton1Click:Connect(function()
        state = not state
        tweenProp(knob, { Position = UDim2.new(if state then 0.7 else 0.3, 0, 0.5, 0) }, 0.2)
        tweenProp(track, { BackgroundColor3 = if state then COLORS.toggleOn else COLORS.toggleOff }, 0.2)
        callback(state)
    end)
end

------------------------------------------------------------------------
-- MAIN MENU
------------------------------------------------------------------------
local mainMenu = Instance.new("Frame")
mainMenu.Name = "MainMenu"
mainMenu.Size = UDim2.new(1, 0, 1, 0)
mainMenu.BackgroundColor3 = COLORS.bg
mainMenu.Parent = screenGui

local mainGrad = Instance.new("UIGradient")
mainGrad.Rotation = 135
mainGrad.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(15, 15, 30)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(30, 25, 50)),
})
mainGrad.Parent = mainMenu

local title = Instance.new("TextLabel")
title.Name = "Title"
title.AnchorPoint = Vector2.new(0.5, 0)
title.Position = UDim2.new(0.5, 0, 0.15, 0)
title.Size = UDim2.new(0.6, 0, 0, 80)
title.BackgroundTransparency = 1
title.Text = "GAME TITLE"
title.TextColor3 = COLORS.text
title.TextSize = 56
title.Font = Enum.Font.GothamBlack
title.TextStrokeTransparency = 0.6
title.Parent = mainMenu

local mainBtns = Instance.new("Frame")
mainBtns.Name = "Buttons"
mainBtns.AnchorPoint = Vector2.new(0.5, 0.5)
mainBtns.Position = UDim2.new(0.5, 0, 0.55, 0)
mainBtns.Size = UDim2.new(0, BUTTON_WIDTH, 0, 0)
mainBtns.AutomaticSize = Enum.AutomaticSize.Y
mainBtns.BackgroundTransparency = 1
mainBtns.Parent = mainMenu

local mainBtnsLayout = Instance.new("UIListLayout")
mainBtnsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
mainBtnsLayout.Padding = UDim.new(0, 14)
mainBtnsLayout.SortOrder = Enum.SortOrder.LayoutOrder
mainBtnsLayout.Parent = mainBtns

local playBtn = createButton("Play", mainBtns, 1)
local settingsFromMainBtn = createButton("Settings", mainBtns, 2)
local quitBtn = createButton("Quit", mainBtns, 3, COLORS.danger)

------------------------------------------------------------------------
-- PAUSE MENU
------------------------------------------------------------------------
local pauseMenu = Instance.new("Frame")
pauseMenu.Name = "PauseMenu"
pauseMenu.Size = UDim2.new(1, 0, 1, 0)
pauseMenu.BackgroundTransparency = 1
pauseMenu.Visible = false
pauseMenu.Parent = screenGui

local overlay = Instance.new("Frame")
overlay.Name = "Overlay"
overlay.Size = UDim2.new(1, 0, 1, 0)
overlay.BackgroundColor3 = COLORS.overlay
overlay.BackgroundTransparency = 0.4
overlay.Parent = pauseMenu

local pausePanel = Instance.new("Frame")
pausePanel.Name = "Panel"
pausePanel.AnchorPoint = Vector2.new(0.5, 0.5)
pausePanel.Position = UDim2.new(0.5, 0, 0.5, 0)
pausePanel.Size = UDim2.new(0, BUTTON_WIDTH + 60, 0, 0)
pausePanel.AutomaticSize = Enum.AutomaticSize.Y
pausePanel.BackgroundColor3 = COLORS.panel
pausePanel.BackgroundTransparency = 0.1
addCorner(pausePanel, 16)
addStroke(pausePanel, COLORS.accent, 2)
pausePanel.Parent = pauseMenu

local pausePad = Instance.new("UIPadding")
pausePad.PaddingTop = UDim.new(0, 30)
pausePad.PaddingBottom = UDim.new(0, 30)
pausePad.PaddingLeft = UDim.new(0, 30)
pausePad.PaddingRight = UDim.new(0, 30)
pausePad.Parent = pausePanel

local pauseTitle = Instance.new("TextLabel")
pauseTitle.Name = "PauseTitle"
pauseTitle.Size = UDim2.new(1, 0, 0, 40)
pauseTitle.BackgroundTransparency = 1
pauseTitle.Text = "PAUSED"
pauseTitle.TextColor3 = COLORS.text
pauseTitle.TextSize = 28
pauseTitle.Font = Enum.Font.GothamBold
pauseTitle.LayoutOrder = 0
pauseTitle.Parent = pausePanel

local pauseBtnsLayout = Instance.new("UIListLayout")
pauseBtnsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
pauseBtnsLayout.Padding = UDim.new(0, 12)
pauseBtnsLayout.SortOrder = Enum.SortOrder.LayoutOrder
pauseBtnsLayout.Parent = pausePanel

local resumeBtn = createButton("Resume", pausePanel, 1)
local settingsFromPauseBtn = createButton("Settings", pausePanel, 2)
local quitFromPauseBtn = createButton("Quit to Menu", pausePanel, 3, COLORS.danger)

------------------------------------------------------------------------
-- SETTINGS MENU
------------------------------------------------------------------------
local settingsMenu = Instance.new("Frame")
settingsMenu.Name = "SettingsMenu"
settingsMenu.Size = UDim2.new(1, 0, 1, 0)
settingsMenu.BackgroundColor3 = COLORS.bg
settingsMenu.BackgroundTransparency = 0.05
settingsMenu.Visible = false
settingsMenu.Parent = screenGui

local settingsPanel = Instance.new("Frame")
settingsPanel.AnchorPoint = Vector2.new(0.5, 0.5)
settingsPanel.Position = UDim2.new(0.5, 0, 0.5, 0)
settingsPanel.Size = UDim2.new(0, 500, 0, 0)
settingsPanel.AutomaticSize = Enum.AutomaticSize.Y
settingsPanel.BackgroundColor3 = COLORS.panel
addCorner(settingsPanel, 16)
addStroke(settingsPanel, COLORS.accent, 2)
settingsPanel.Parent = settingsMenu

local settingsPad = Instance.new("UIPadding")
settingsPad.PaddingTop = UDim.new(0, 20)
settingsPad.PaddingBottom = UDim.new(0, 20)
settingsPad.PaddingLeft = UDim.new(0, 20)
settingsPad.PaddingRight = UDim.new(0, 20)
settingsPad.Parent = settingsPanel

local settingsLayout = Instance.new("UIListLayout")
settingsLayout.Padding = UDim.new(0, 8)
settingsLayout.SortOrder = Enum.SortOrder.LayoutOrder
settingsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
settingsLayout.Parent = settingsPanel

local settingsTitle = Instance.new("TextLabel")
settingsTitle.Size = UDim2.new(1, 0, 0, 40)
settingsTitle.BackgroundTransparency = 1
settingsTitle.Text = "Settings"
settingsTitle.TextColor3 = COLORS.text
settingsTitle.TextSize = 24
settingsTitle.Font = Enum.Font.GothamBold
settingsTitle.LayoutOrder = 0
settingsTitle.Parent = settingsPanel

createSlider("Master Volume", settingsPanel, 1, 0.8, function(val)
    -- game:GetService("SoundService").AmbientReverb 등 연결
end)
createSlider("Music Volume", settingsPanel, 2, 0.6, function(val) end)
createSlider("SFX Volume", settingsPanel, 3, 0.7, function(val) end)
createSlider("Sensitivity", settingsPanel, 4, 0.5, function(val) end)
createToggle("Fullscreen", settingsPanel, 5, false, function(val) end)
createToggle("Show FPS", settingsPanel, 6, false, function(val) end)

local backBtn = createButton("Back", settingsPanel, 10)

------------------------------------------------------------------------
-- TRANSITIONS
------------------------------------------------------------------------
local currentMenu: string = "main"

local function transitionTo(target: string)
    local menus = { main = mainMenu, pause = pauseMenu, settings = settingsMenu }
    -- Fade out current
    for name, menu in menus do
        if name ~= target and menu.Visible then
            local t = tweenProp(menu, { BackgroundTransparency = 1 }, TWEEN_SPEED)
            -- Fade out all children too
            for _, child in menu:GetDescendants() do
                if child:IsA("GuiObject") then
                    pcall(function()
                        tweenProp(child, { BackgroundTransparency = 1, TextTransparency = 1 }, TWEEN_SPEED)
                    end)
                end
            end
            task.delay(TWEEN_SPEED, function() menu.Visible = false end)
        end
    end

    -- Fade in target
    task.delay(TWEEN_SPEED * 0.5, function()
        local menu = menus[target]
        if menu then
            menu.Visible = true
            tweenProp(menu, { BackgroundTransparency = if target == "pause" then 1 else 0 }, TWEEN_SPEED)
            for _, child in menu:GetDescendants() do
                if child:IsA("GuiObject") then
                    pcall(function()
                        tweenProp(child, { BackgroundTransparency = 0, TextTransparency = 0 }, TWEEN_SPEED)
                    end)
                end
            end
        end
    end)
    currentMenu = target
end

------------------------------------------------------------------------
-- BUTTON CONNECTIONS
------------------------------------------------------------------------
playBtn.MouseButton1Click:Connect(function()
    mainMenu.Visible = false
    -- Game starts
end)

settingsFromMainBtn.MouseButton1Click:Connect(function() transitionTo("settings") end)
settingsFromPauseBtn.MouseButton1Click:Connect(function() transitionTo("settings") end)

quitBtn.MouseButton1Click:Connect(function()
    player:Kick("Thanks for playing!")
end)

resumeBtn.MouseButton1Click:Connect(function()
    pauseMenu.Visible = false
end)

quitFromPauseBtn.MouseButton1Click:Connect(function()
    transitionTo("main")
end)

backBtn.MouseButton1Click:Connect(function()
    if currentMenu == "settings" then
        transitionTo("pause")
    end
end)

------------------------------------------------------------------------
-- ESCAPE KEY TOGGLE PAUSE
------------------------------------------------------------------------
UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == Enum.KeyCode.Escape then
        if mainMenu.Visible then return end
        if pauseMenu.Visible then
            pauseMenu.Visible = false
        else
            pauseMenu.Visible = true
        end
    end
end)
```

## 사용 예시

```lua
-- 메인 메뉴 타이틀 변경
local menuGui = playerGui:WaitForChild("MenuSystem")
menuGui.MainMenu.Title.Text = "My Awesome Game"

-- 프로그래밍으로 일시정지 메뉴 열기
menuGui.PauseMenu.Visible = true
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
