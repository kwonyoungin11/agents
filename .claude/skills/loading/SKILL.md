---
name: loading
description: >
  Roblox 로딩 시스템 전문가. 로딩 화면, 프로그레스 바, 팁 표시, TeleportService
  장소 이동, ReservedServer 비공개 서버 생성 구현.
  로딩, 로딩화면, 텔레포트, 이동, 서버이동, 로딩스크린, loading 요청 시 자동 발동.
allowed-tools: Agent Read Grep Glob Bash
effort: high
---

# Loading Agent — Roblox 로딩 시스템 전문가

로딩 화면, 텔레포트, ReservedServer를 **즉시 실행 가능한 Luau 코드**로 구현한다.

---

## 절대 원칙

1. **ReplicatedFirst** — 로딩 화면은 ReplicatedFirst LocalScript로 가장 먼저 실행
2. **ContentProvider:PreloadAsync** — 에셋 사전 로딩으로 실제 프로그레스 표시
3. **TeleportService** — 장소 간 이동, 데이터 전달, 에러 핸들링
4. **ReservedServer** — 비공개 서버 생성 및 접근 코드 관리
5. **game.Loaded** — 게임 로딩 완료 감지

---

## 로딩 구조

```
ReplicatedFirst/
└── LoadingScreen (LocalScript)
    └── ScreenGui "LoadingGui"
        ├── Background (전체 화면 배경)
        ├── Logo (게임 로고 이미지)
        ├── ProgressBarBg > ProgressFill
        ├── ProgressText ("Loading... 45%")
        ├── TipText ("Tip: ...")
        └── SkipButton (선택사항)

ServerScriptService/
└── TeleportManager (Script)
    ├── TeleportService 래핑
    ├── ReservedServer 관리
    └── 에러 핸들링 + 재시도
```

---

## 완전한 로딩 화면 구현

```lua
--!strict
-- LoadingScreen.luau — LocalScript under ReplicatedFirst
-- 로딩 화면 + 프로그레스 바 + 팁 표시

local Players = game:GetService("Players")
local ContentProvider = game:GetService("ContentProvider")
local TweenService = game:GetService("TweenService")
local ReplicatedFirst = game:GetService("ReplicatedFirst")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

------------------------------------------------------------------------
-- CONFIG
------------------------------------------------------------------------
local CONFIG = {
    BgColor = Color3.fromRGB(12, 12, 20),
    BarColor = Color3.fromRGB(80, 140, 255),
    BarBgColor = Color3.fromRGB(40, 40, 55),
    BarWidth = 400,
    BarHeight = 12,
    BarCornerRadius = 6,
    LogoImage = "", -- "rbxassetid://YOUR_LOGO_ID"
    LogoSize = UDim2.new(0, 200, 0, 200),
    MinDisplayTime = 3, -- 최소 로딩 화면 표시 시간

    Tips = {
        "Tip: Press E to interact with NPCs!",
        "Tip: Collect gems to unlock new abilities.",
        "Tip: Hold Shift to sprint.",
        "Tip: Visit the shop for powerful items!",
        "Tip: Team up with friends for boss battles.",
        "Tip: Explore hidden areas for rare loot.",
    },
    TipRotateInterval = 3,
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
-- REMOVE DEFAULT LOADING SCREEN
------------------------------------------------------------------------
ReplicatedFirst:RemoveDefaultLoadingScreen()

------------------------------------------------------------------------
-- LOADING GUI
------------------------------------------------------------------------
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "LoadingGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.DisplayOrder = 999
screenGui.Parent = playerGui

-- Background
local bg = Instance.new("Frame")
bg.Name = "Background"
bg.Size = UDim2.new(1, 0, 1, 0)
bg.BackgroundColor3 = CONFIG.BgColor
bg.BorderSizePixel = 0
bg.Parent = screenGui

local bgGrad = Instance.new("UIGradient")
bgGrad.Rotation = 135
bgGrad.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(15, 15, 30)),
    ColorSequenceKeypoint.new(0.5, Color3.fromRGB(10, 10, 18)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(20, 15, 35)),
})
bgGrad.Parent = bg

-- Logo
local logo = Instance.new("ImageLabel")
logo.Name = "Logo"
logo.AnchorPoint = Vector2.new(0.5, 0.5)
logo.Position = UDim2.new(0.5, 0, 0.35, 0)
logo.Size = CONFIG.LogoSize
logo.BackgroundTransparency = 1
logo.Image = CONFIG.LogoImage
logo.Parent = bg

-- Game title (shown if no logo)
local titleLabel = Instance.new("TextLabel")
titleLabel.Name = "Title"
titleLabel.AnchorPoint = Vector2.new(0.5, 0.5)
titleLabel.Position = UDim2.new(0.5, 0, 0.35, 0)
titleLabel.Size = UDim2.new(0.8, 0, 0, 60)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "LOADING..."
titleLabel.TextColor3 = Color3.fromRGB(240, 240, 240)
titleLabel.TextSize = 42
titleLabel.Font = Enum.Font.GothamBlack
titleLabel.TextStrokeTransparency = 0.6
titleLabel.Visible = CONFIG.LogoImage == ""
titleLabel.Parent = bg

-- Progress bar background
local barBg = Instance.new("Frame")
barBg.Name = "ProgressBarBg"
barBg.AnchorPoint = Vector2.new(0.5, 0)
barBg.Position = UDim2.new(0.5, 0, 0.62, 0)
barBg.Size = UDim2.new(0, CONFIG.BarWidth, 0, CONFIG.BarHeight)
barBg.BackgroundColor3 = CONFIG.BarBgColor
addCorner(barBg, CONFIG.BarCornerRadius)
barBg.Parent = bg

-- Progress fill
local barFill = Instance.new("Frame")
barFill.Name = "Fill"
barFill.Size = UDim2.new(0, 0, 1, 0)
barFill.BackgroundColor3 = CONFIG.BarColor
addCorner(barFill, CONFIG.BarCornerRadius)
barFill.Parent = barBg

-- Glow effect on fill
local barGlow = Instance.new("UIGradient")
barGlow.Rotation = 90
barGlow.Transparency = NumberSequence.new({
    NumberSequenceKeypoint.new(0, 0),
    NumberSequenceKeypoint.new(0.5, 0.2),
    NumberSequenceKeypoint.new(1, 0.4),
})
barGlow.Parent = barFill

-- Progress text
local progressText = Instance.new("TextLabel")
progressText.Name = "ProgressText"
progressText.AnchorPoint = Vector2.new(0.5, 0)
progressText.Position = UDim2.new(0.5, 0, 0.62, CONFIG.BarHeight + 8)
progressText.Size = UDim2.new(0, CONFIG.BarWidth, 0, 20)
progressText.BackgroundTransparency = 1
progressText.Text = "Loading... 0%"
progressText.TextColor3 = Color3.fromRGB(180, 180, 200)
progressText.TextSize = 14
progressText.Font = Enum.Font.GothamMedium
progressText.Parent = bg

-- Tip text
local tipText = Instance.new("TextLabel")
tipText.Name = "TipText"
tipText.AnchorPoint = Vector2.new(0.5, 1)
tipText.Position = UDim2.new(0.5, 0, 1, -40)
tipText.Size = UDim2.new(0.7, 0, 0, 30)
tipText.BackgroundTransparency = 1
tipText.Text = CONFIG.Tips[1] or ""
tipText.TextColor3 = Color3.fromRGB(140, 140, 160)
tipText.TextSize = 14
tipText.Font = Enum.Font.Gotham
tipText.Parent = bg

-- Spinner animation
local spinner = Instance.new("ImageLabel")
spinner.Name = "Spinner"
spinner.AnchorPoint = Vector2.new(0.5, 0.5)
spinner.Position = UDim2.new(0.5, 0, 0.52, 0)
spinner.Size = UDim2.new(0, 40, 0, 40)
spinner.BackgroundTransparency = 1
spinner.Image = "rbxassetid://6034818372" -- circle asset
spinner.ImageColor3 = CONFIG.BarColor
spinner.Parent = bg

-- Rotate spinner
task.spawn(function()
    while spinner.Parent do
        spinner.Rotation += 5
        task.wait()
    end
end)

------------------------------------------------------------------------
-- TIP ROTATION
------------------------------------------------------------------------
task.spawn(function()
    local index = 1
    while screenGui.Parent do
        task.wait(CONFIG.TipRotateInterval)
        index = index % #CONFIG.Tips + 1
        -- Fade out, change, fade in
        TweenService:Create(tipText, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
        task.wait(0.3)
        tipText.Text = CONFIG.Tips[index]
        TweenService:Create(tipText, TweenInfo.new(0.3), { TextTransparency = 0 }):Play()
    end
end)

------------------------------------------------------------------------
-- PROGRESS TRACKING
------------------------------------------------------------------------
local function setProgress(ratio: number, statusText: string?)
    ratio = math.clamp(ratio, 0, 1)
    TweenService:Create(barFill, TweenInfo.new(0.3, Enum.EasingStyle.Quad),
        { Size = UDim2.new(ratio, 0, 1, 0) }):Play()
    progressText.Text = (statusText or "Loading...") .. " " .. math.floor(ratio * 100) .. "%"
end

------------------------------------------------------------------------
-- PRELOAD ASSETS
------------------------------------------------------------------------
local startTime = tick()

task.spawn(function()
    -- Gather assets to preload
    local assets: { Instance } = {}
    for _, desc in game:GetDescendants() do
        if desc:IsA("Decal") or desc:IsA("Texture") or desc:IsA("Sound")
            or desc:IsA("Animation") or desc:IsA("ImageLabel") or desc:IsA("ImageButton") then
            table.insert(assets, desc)
        end
    end

    local total = #assets
    local loaded = 0

    if total > 0 then
        ContentProvider:PreloadAsync(assets, function(assetId, status)
            loaded += 1
            setProgress(loaded / total, "Loading assets...")
        end)
    end

    setProgress(1, "Complete!")

    -- Wait for minimum display time
    local elapsed = tick() - startTime
    if elapsed < CONFIG.MinDisplayTime then
        task.wait(CONFIG.MinDisplayTime - elapsed)
    end

    -- Wait for game to be loaded
    if not game:IsLoaded() then
        game.Loaded:Wait()
    end

    -- Fade out loading screen
    TweenService:Create(bg, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
        { BackgroundTransparency = 1 }):Play()
    for _, child in bg:GetDescendants() do
        if child:IsA("GuiObject") then
            pcall(function()
                TweenService:Create(child, TweenInfo.new(0.8),
                    { BackgroundTransparency = 1, TextTransparency = 1, ImageTransparency = 1 }):Play()
            end)
        end
    end
    task.wait(0.9)
    screenGui:Destroy()
end)
```

## TeleportService 텔레포트 매니저

```lua
--!strict
-- TeleportManager.luau — Script under ServerScriptService
-- 장소 이동 + ReservedServer 관리

local TeleportService = game:GetService("TeleportService")
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

------------------------------------------------------------------------
-- TELEPORT TO PLACE
------------------------------------------------------------------------
local function teleportToPlace(player: Player, placeId: number, teleportData: { [string]: any }?)
    local success, err
    local attempts = 0
    local MAX_ATTEMPTS = 3

    repeat
        attempts += 1
        success, err = pcall(function()
            local options = Instance.new("TeleportOptions")
            if teleportData then
                options:SetTeleportData(teleportData)
            end
            TeleportService:TeleportAsync(placeId, { player }, options)
        end)
        if not success then
            warn("[TeleportManager] Attempt " .. attempts .. " failed: " .. tostring(err))
            task.wait(1)
        end
    until success or attempts >= MAX_ATTEMPTS

    if not success then
        warn("[TeleportManager] Failed to teleport after " .. MAX_ATTEMPTS .. " attempts")
    end
end

------------------------------------------------------------------------
-- TELEPORT PARTY
------------------------------------------------------------------------
local function teleportParty(players: { Player }, placeId: number, teleportData: { [string]: any }?)
    local success, err = pcall(function()
        local options = Instance.new("TeleportOptions")
        options.ShouldReserveServer = true
        if teleportData then
            options:SetTeleportData(teleportData)
        end
        TeleportService:TeleportAsync(placeId, players, options)
    end)
    if not success then
        warn("[TeleportManager] Party teleport failed: " .. tostring(err))
    end
end

------------------------------------------------------------------------
-- RESERVED SERVER
------------------------------------------------------------------------
local function createReservedServer(placeId: number): string?
    local success, accessCode = pcall(function()
        return TeleportService:ReserveServer(placeId)
    end)
    if success then
        return accessCode
    else
        warn("[TeleportManager] ReserveServer failed: " .. tostring(accessCode))
        return nil
    end
end

local function teleportToReservedServer(players: { Player }, placeId: number, accessCode: string)
    local success, err = pcall(function()
        local options = Instance.new("TeleportOptions")
        options.ReservedServerAccessCode = accessCode
        TeleportService:TeleportAsync(placeId, players, options)
    end)
    if not success then
        warn("[TeleportManager] Reserved teleport failed: " .. tostring(err))
    end
end

------------------------------------------------------------------------
-- HANDLE TELEPORT ARRIVAL (read data sent from previous place)
------------------------------------------------------------------------
local function onPlayerAdded(player: Player)
    local joinData = player:GetJoinData()
    local teleportData = joinData.TeleportData
    if teleportData then
        -- Process incoming teleport data
        print("[TeleportManager] Player arrived with data:", teleportData)
    end
end

Players.PlayerAdded:Connect(onPlayerAdded)

------------------------------------------------------------------------
-- TELEPORT FAILURE HANDLING
------------------------------------------------------------------------
TeleportService.TeleportInitFailed:Connect(function(player, result, errorMessage, placeId, teleportOptions)
    warn("[TeleportManager] Teleport failed for", player.Name, ":", errorMessage)
    -- Retry once
    task.wait(2)
    pcall(function()
        TeleportService:TeleportAsync(placeId, { player }, teleportOptions)
    end)
end)
```

## 사용 예시

```lua
-- 서버에서 플레이어를 다른 장소로 이동
teleportToPlace(player, 123456789, { level = 5, gold = 100 })

-- 파티 텔레포트 (자동 예약 서버)
teleportParty({ player1, player2, player3 }, 123456789)

-- 수동 예약 서버
local code = createReservedServer(123456789)
if code then
    teleportToReservedServer({ player }, 123456789, code)
end
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
