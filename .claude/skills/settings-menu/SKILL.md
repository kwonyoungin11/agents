---
name: settings-menu
description: >
  Roblox 설정 메뉴 전문가. 그래픽 품질 설정, 볼륨 슬라이더(마스터/음악/효과음),
  마우스 감도, 키바인드 표시, DataStore 저장/로드 구현.
  설정, 옵션, 볼륨, 그래픽, 감도, 키설정, settings 요청 시 자동 발동.
allowed-tools: Agent Read Grep Glob Bash
effort: high
---

# Settings Menu Agent — Roblox 설정 메뉴 전문가

완전한 설정 메뉴와 DataStore 영구 저장을 **즉시 실행 가능한 Luau 코드**로 구현한다.

---

## 절대 원칙

1. **DataStore 영구 저장** — 플레이어 설정은 서버 DataStore에 저장
2. **실시간 반영** — 슬라이더/토글 변경 즉시 게임에 반영
3. **기본값 관리** — 저장된 값이 없으면 기본값 사용
4. **pcall 필수** — DataStore 호출은 반드시 pcall로 래핑
5. **RemoteFunction** — 클라이언트 UI ↔ 서버 DataStore 양방향 통신

---

## 설정 구조

```
ScreenGui "SettingsGui"
└── SettingsPanel (중앙, 닫기 가능)
    ├── TabBar (Graphics | Audio | Controls)
    ├── GraphicsTab
    │   ├── QualitySlider (1~10)
    │   ├── RenderDistanceSlider
    │   ├── ShadowsToggle
    │   └── ParticlesToggle
    ├── AudioTab
    │   ├── MasterVolumeSlider
    │   ├── MusicVolumeSlider
    │   └── SFXVolumeSlider
    └── ControlsTab
        ├── SensitivitySlider
        └── KeybindList (표시 전용)
```

---

## 서버측 설정 저장/로드 시스템

```lua
--!strict
-- SettingsDataStore.luau — Script under ServerScriptService
-- DataStore 기반 플레이어 설정 영구 저장

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local settingsStore = DataStoreService:GetDataStore("PlayerSettings_v1")

------------------------------------------------------------------------
-- DEFAULT SETTINGS
------------------------------------------------------------------------
local DEFAULT_SETTINGS = {
    graphics = {
        quality = 7,
        renderDistance = 80,
        shadows = true,
        particles = true,
    },
    audio = {
        masterVolume = 80,
        musicVolume = 60,
        sfxVolume = 70,
    },
    controls = {
        sensitivity = 50,
    },
}

------------------------------------------------------------------------
-- REMOTE FUNCTIONS
------------------------------------------------------------------------
local loadSettingsRemote = Instance.new("RemoteFunction")
loadSettingsRemote.Name = "LoadSettings"
loadSettingsRemote.Parent = ReplicatedStorage

local saveSettingsRemote = Instance.new("RemoteFunction")
saveSettingsRemote.Name = "SaveSettings"
saveSettingsRemote.Parent = ReplicatedStorage

------------------------------------------------------------------------
-- CACHE
------------------------------------------------------------------------
local playerSettings: { [number]: { [string]: any } } = {}

------------------------------------------------------------------------
-- DEEP MERGE (기본값에 저장된 값 덮어쓰기)
------------------------------------------------------------------------
local function deepMerge(base: { [string]: any }, override: { [string]: any }): { [string]: any }
    local result = {}
    for k, v in base do
        if type(v) == "table" and type(override[k]) == "table" then
            result[k] = deepMerge(v, override[k])
        elseif override[k] ~= nil then
            result[k] = override[k]
        else
            result[k] = v
        end
    end
    return result
end

------------------------------------------------------------------------
-- LOAD
------------------------------------------------------------------------
local function loadPlayerSettings(player: Player): { [string]: any }
    local userId = player.UserId
    if playerSettings[userId] then
        return playerSettings[userId]
    end

    local success, data = pcall(function()
        return settingsStore:GetAsync("settings_" .. userId)
    end)

    local settings: { [string]: any }
    if success and data then
        settings = deepMerge(DEFAULT_SETTINGS, data)
    else
        settings = table.clone(DEFAULT_SETTINGS)
        -- deep clone
        for k, v in settings do
            if type(v) == "table" then
                settings[k] = table.clone(v)
            end
        end
    end

    playerSettings[userId] = settings
    return settings
end

------------------------------------------------------------------------
-- SAVE
------------------------------------------------------------------------
local function savePlayerSettings(player: Player, settings: { [string]: any }): boolean
    local userId = player.UserId
    playerSettings[userId] = settings

    local success, err = pcall(function()
        settingsStore:SetAsync("settings_" .. userId, settings)
    end)

    if not success then
        warn("[SettingsStore] Save failed for", player.Name, ":", err)
    end
    return success
end

------------------------------------------------------------------------
-- REMOTE HANDLERS
------------------------------------------------------------------------
loadSettingsRemote.OnServerInvoke = function(player: Player)
    return loadPlayerSettings(player)
end

saveSettingsRemote.OnServerInvoke = function(player: Player, settings: { [string]: any })
    -- 입력 검증
    if type(settings) ~= "table" then return false end
    if type(settings.audio) == "table" then
        for key, val in settings.audio do
            if type(val) == "number" then
                settings.audio[key] = math.clamp(val, 0, 100)
            end
        end
    end
    if type(settings.graphics) == "table" then
        if type(settings.graphics.quality) == "number" then
            settings.graphics.quality = math.clamp(math.floor(settings.graphics.quality), 1, 10)
        end
    end
    return savePlayerSettings(player, settings)
end

------------------------------------------------------------------------
-- CLEANUP
------------------------------------------------------------------------
Players.PlayerRemoving:Connect(function(player)
    local settings = playerSettings[player.UserId]
    if settings then
        savePlayerSettings(player, settings)
        playerSettings[player.UserId] = nil
    end
end)

game:BindToClose(function()
    for _, player in Players:GetPlayers() do
        local settings = playerSettings[player.UserId]
        if settings then
            pcall(function()
                settingsStore:SetAsync("settings_" .. player.UserId, settings)
            end)
        end
    end
end)
```

## 클라이언트 설정 UI

```lua
--!strict
-- SettingsUI.luau — LocalScript under StarterPlayerScripts
-- 탭 기반 설정 메뉴 + 실시간 반영 + 서버 저장

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local loadSettingsRemote = ReplicatedStorage:WaitForChild("LoadSettings") :: RemoteFunction
local saveSettingsRemote = ReplicatedStorage:WaitForChild("SaveSettings") :: RemoteFunction

------------------------------------------------------------------------
-- COLORS
------------------------------------------------------------------------
local C = {
    bg = Color3.fromRGB(18, 18, 28),
    panel = Color3.fromRGB(28, 28, 42),
    tab = Color3.fromRGB(35, 35, 50),
    tabActive = Color3.fromRGB(60, 100, 200),
    accent = Color3.fromRGB(70, 130, 255),
    text = Color3.fromRGB(230, 230, 240),
    textDim = Color3.fromRGB(140, 140, 160),
    sliderBg = Color3.fromRGB(45, 45, 60),
    sliderFill = Color3.fromRGB(70, 130, 255),
    toggleOff = Color3.fromRGB(70, 70, 90),
    toggleOn = Color3.fromRGB(70, 190, 110),
}

------------------------------------------------------------------------
-- LOAD SAVED SETTINGS
------------------------------------------------------------------------
local settings = loadSettingsRemote:InvokeServer()

------------------------------------------------------------------------
-- GUI
------------------------------------------------------------------------
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "SettingsGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 80
screenGui.Enabled = false
screenGui.Parent = playerGui

-- Dark overlay
local overlay = Instance.new("TextButton")
overlay.Size = UDim2.new(1, 0, 1, 0)
overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
overlay.BackgroundTransparency = 0.5
overlay.Text = ""
overlay.AutoButtonColor = false
overlay.Parent = screenGui

-- Main panel
local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.new(0.5, 0, 0.5, 0)
panel.Size = UDim2.new(0, 550, 0, 420)
panel.BackgroundColor3 = C.panel
panel.Parent = screenGui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 12)
local panelStroke = Instance.new("UIStroke", panel)
panelStroke.Color = C.accent; panelStroke.Thickness = 2

-- Title
local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 40)
title.BackgroundTransparency = 1
title.Text = "Settings"
title.TextColor3 = C.text
title.TextSize = 22
title.Font = Enum.Font.GothamBold
title.Parent = panel

-- Close button
local closeBtn = Instance.new("TextButton")
closeBtn.AnchorPoint = Vector2.new(1, 0)
closeBtn.Position = UDim2.new(1, -8, 0, 8)
closeBtn.Size = UDim2.new(0, 28, 0, 28)
closeBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
closeBtn.Text = "X"
closeBtn.TextColor3 = C.text
closeBtn.TextSize = 16
closeBtn.Font = Enum.Font.GothamBold
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 6)
closeBtn.Parent = panel

------------------------------------------------------------------------
-- TAB SYSTEM
------------------------------------------------------------------------
local tabBar = Instance.new("Frame")
tabBar.Position = UDim2.new(0, 0, 0, 44)
tabBar.Size = UDim2.new(1, 0, 0, 36)
tabBar.BackgroundColor3 = Color3.fromRGB(22, 22, 34)
tabBar.Parent = panel

local tabLayout = Instance.new("UIListLayout")
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.Parent = tabBar

local contentArea = Instance.new("Frame")
contentArea.Position = UDim2.new(0, 0, 0, 84)
contentArea.Size = UDim2.new(1, 0, 1, -84)
contentArea.BackgroundTransparency = 1
contentArea.ClipsDescendants = true
contentArea.Parent = panel

local tabFrames: { [string]: Frame } = {}
local tabButtons: { [string]: TextButton } = {}
local activeTab = "Graphics"

local function createTab(name: string): Frame
    local btn = Instance.new("TextButton")
    btn.Name = name .. "Tab"
    btn.Size = UDim2.new(1 / 3, 0, 1, 0)
    btn.BackgroundColor3 = C.tab
    btn.Text = name
    btn.TextColor3 = C.textDim
    btn.TextSize = 14
    btn.Font = Enum.Font.GothamMedium
    btn.AutoButtonColor = false
    btn.Parent = tabBar
    tabButtons[name] = btn

    local frame = Instance.new("Frame")
    frame.Name = name .. "Content"
    frame.Size = UDim2.new(1, 0, 1, 0)
    frame.BackgroundTransparency = 1
    frame.Visible = false
    frame.Parent = contentArea

    local pad = Instance.new("UIPadding")
    pad.PaddingTop = UDim.new(0, 12)
    pad.PaddingLeft = UDim.new(0, 20)
    pad.PaddingRight = UDim.new(0, 20)
    pad.Parent = frame

    local lay = Instance.new("UIListLayout")
    lay.Padding = UDim.new(0, 10)
    lay.SortOrder = Enum.SortOrder.LayoutOrder
    lay.Parent = frame

    tabFrames[name] = frame
    return frame
end

local function switchTab(name: string)
    for tabName, frame in tabFrames do
        frame.Visible = tabName == name
        local btn = tabButtons[tabName]
        btn.BackgroundColor3 = if tabName == name then C.tabActive else C.tab
        btn.TextColor3 = if tabName == name then C.text else C.textDim
    end
    activeTab = name
end

------------------------------------------------------------------------
-- SLIDER / TOGGLE FACTORIES
------------------------------------------------------------------------
local function makeSlider(parent: Frame, label: string, order: number, min: number, max: number, current: number, onChange: (number) -> ())
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 36)
    row.BackgroundTransparency = 1
    row.LayoutOrder = order
    row.Parent = parent

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(0.35, 0, 1, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = label
    lbl.TextColor3 = C.text
    lbl.TextSize = 14
    lbl.Font = Enum.Font.GothamMedium
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = row

    local track = Instance.new("Frame")
    track.AnchorPoint = Vector2.new(0, 0.5)
    track.Position = UDim2.new(0.37, 0, 0.5, 0)
    track.Size = UDim2.new(0.48, 0, 0, 8)
    track.BackgroundColor3 = C.sliderBg
    Instance.new("UICorner", track).CornerRadius = UDim.new(0, 4)
    track.Parent = row

    local ratio = (current - min) / (max - min)
    local fill = Instance.new("Frame")
    fill.Size = UDim2.new(ratio, 0, 1, 0)
    fill.BackgroundColor3 = C.sliderFill
    Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 4)
    fill.Parent = track

    local knob = Instance.new("Frame")
    knob.AnchorPoint = Vector2.new(0.5, 0.5)
    knob.Position = UDim2.new(ratio, 0, 0.5, 0)
    knob.Size = UDim2.new(0, 18, 0, 18)
    knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    Instance.new("UICorner", knob).CornerRadius = UDim.new(0, 9)
    knob.Parent = track

    local valLabel = Instance.new("TextLabel")
    valLabel.AnchorPoint = Vector2.new(1, 0.5)
    valLabel.Position = UDim2.new(1, 0, 0.5, 0)
    valLabel.Size = UDim2.new(0.12, 0, 1, 0)
    valLabel.BackgroundTransparency = 1
    valLabel.Text = tostring(math.floor(current))
    valLabel.TextColor3 = C.textDim
    valLabel.TextSize = 13
    valLabel.Font = Enum.Font.GothamMedium
    valLabel.Parent = row

    local dragging = false
    knob.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            if dragging then
                dragging = false
                -- Save on release
                saveSettingsRemote:InvokeServer(settings)
            end
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local r = math.clamp((input.Position.X - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
            knob.Position = UDim2.new(r, 0, 0.5, 0)
            fill.Size = UDim2.new(r, 0, 1, 0)
            local val = math.floor(min + r * (max - min))
            valLabel.Text = tostring(val)
            onChange(val)
        end
    end)
end

local function makeToggle(parent: Frame, label: string, order: number, current: boolean, onChange: (boolean) -> ())
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 36)
    row.BackgroundTransparency = 1
    row.LayoutOrder = order
    row.Parent = parent

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(0.7, 0, 1, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = label
    lbl.TextColor3 = C.text
    lbl.TextSize = 14
    lbl.Font = Enum.Font.GothamMedium
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = row

    local track = Instance.new("TextButton")
    track.AnchorPoint = Vector2.new(1, 0.5)
    track.Position = UDim2.new(1, 0, 0.5, 0)
    track.Size = UDim2.new(0, 46, 0, 24)
    track.BackgroundColor3 = if current then C.toggleOn else C.toggleOff
    track.Text = ""
    track.AutoButtonColor = false
    Instance.new("UICorner", track).CornerRadius = UDim.new(0, 12)
    track.Parent = row

    local knob = Instance.new("Frame")
    knob.AnchorPoint = Vector2.new(0.5, 0.5)
    knob.Position = UDim2.new(if current then 0.72 else 0.28, 0, 0.5, 0)
    knob.Size = UDim2.new(0, 18, 0, 18)
    knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    Instance.new("UICorner", knob).CornerRadius = UDim.new(0, 9)
    knob.Parent = track

    local state = current
    track.MouseButton1Click:Connect(function()
        state = not state
        TweenService:Create(knob, TweenInfo.new(0.2), { Position = UDim2.new(if state then 0.72 else 0.28, 0, 0.5, 0) }):Play()
        TweenService:Create(track, TweenInfo.new(0.2), { BackgroundColor3 = if state then C.toggleOn else C.toggleOff }):Play()
        onChange(state)
        saveSettingsRemote:InvokeServer(settings)
    end)
end

------------------------------------------------------------------------
-- CREATE TABS
------------------------------------------------------------------------
local graphicsTab = createTab("Graphics")
local audioTab = createTab("Audio")
local controlsTab = createTab("Controls")

-- Graphics tab
makeSlider(graphicsTab, "Quality Level", 1, 1, 10, settings.graphics.quality, function(val)
    settings.graphics.quality = val
    -- settings():GetService("") -- 실제 적용
end)
makeSlider(graphicsTab, "Render Distance", 2, 20, 200, settings.graphics.renderDistance, function(val)
    settings.graphics.renderDistance = val
end)
makeToggle(graphicsTab, "Shadows", 3, settings.graphics.shadows, function(val)
    settings.graphics.shadows = val
    Lighting.GlobalShadows = val
end)
makeToggle(graphicsTab, "Particles", 4, settings.graphics.particles, function(val)
    settings.graphics.particles = val
end)

-- Audio tab
makeSlider(audioTab, "Master Volume", 1, 0, 100, settings.audio.masterVolume, function(val)
    settings.audio.masterVolume = val
    SoundService.AmbientReverb = Enum.ReverbType.NoReverb -- placeholder
end)
makeSlider(audioTab, "Music Volume", 2, 0, 100, settings.audio.musicVolume, function(val)
    settings.audio.musicVolume = val
end)
makeSlider(audioTab, "SFX Volume", 3, 0, 100, settings.audio.sfxVolume, function(val)
    settings.audio.sfxVolume = val
end)

-- Controls tab
makeSlider(controlsTab, "Mouse Sensitivity", 1, 1, 100, settings.controls.sensitivity, function(val)
    settings.controls.sensitivity = val
    UserInputService.MouseDeltaSensitivity = val / 50
end)

-- Keybind display
local keybindTitle = Instance.new("TextLabel")
keybindTitle.Size = UDim2.new(1, 0, 0, 30)
keybindTitle.BackgroundTransparency = 1
keybindTitle.Text = "Keybinds"
keybindTitle.TextColor3 = C.accent
keybindTitle.TextSize = 16
keybindTitle.Font = Enum.Font.GothamBold
keybindTitle.TextXAlignment = Enum.TextXAlignment.Left
keybindTitle.LayoutOrder = 10
keybindTitle.Parent = controlsTab

local keybinds = {
    { key = "W/A/S/D", action = "Movement" },
    { key = "Space", action = "Jump" },
    { key = "Shift", action = "Sprint" },
    { key = "E", action = "Interact" },
    { key = "Tab", action = "Inventory" },
    { key = "Escape", action = "Pause Menu" },
}

for i, kb in keybinds do
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 22)
    row.BackgroundTransparency = 1
    row.LayoutOrder = 10 + i
    row.Parent = controlsTab

    local keyLabel = Instance.new("TextLabel")
    keyLabel.Size = UDim2.new(0.3, 0, 1, 0)
    keyLabel.BackgroundTransparency = 1
    keyLabel.Text = "[" .. kb.key .. "]"
    keyLabel.TextColor3 = C.accent
    keyLabel.TextSize = 12
    keyLabel.Font = Enum.Font.GothamMedium
    keyLabel.TextXAlignment = Enum.TextXAlignment.Left
    keyLabel.Parent = row

    local actionLabel = Instance.new("TextLabel")
    actionLabel.Position = UDim2.new(0.32, 0, 0, 0)
    actionLabel.Size = UDim2.new(0.68, 0, 1, 0)
    actionLabel.BackgroundTransparency = 1
    actionLabel.Text = kb.action
    actionLabel.TextColor3 = C.textDim
    actionLabel.TextSize = 12
    actionLabel.Font = Enum.Font.Gotham
    actionLabel.TextXAlignment = Enum.TextXAlignment.Left
    actionLabel.Parent = row
end

------------------------------------------------------------------------
-- TAB NAVIGATION
------------------------------------------------------------------------
for name, btn in tabButtons do
    btn.MouseButton1Click:Connect(function() switchTab(name) end)
end
switchTab("Graphics")

------------------------------------------------------------------------
-- OPEN/CLOSE
------------------------------------------------------------------------
closeBtn.MouseButton1Click:Connect(function()
    screenGui.Enabled = false
end)
overlay.MouseButton1Click:Connect(function()
    screenGui.Enabled = false
end)

-- F5 또는 Remote로 열기/닫기
UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == Enum.KeyCode.F5 then
        screenGui.Enabled = not screenGui.Enabled
    end
end)
```

## 사용 예시

```lua
-- F5 키로 설정 메뉴 열기/닫기 (기본 바인딩)

-- 서버에서 설정 로드
local settings = loadSettingsRemote:InvokeServer()

-- 서버에서 설정 저장
saveSettingsRemote:InvokeServer(settings)
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
