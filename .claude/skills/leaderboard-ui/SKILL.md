---
name: leaderboard-ui
description: >
  Roblox 커스텀 리더보드 UI 전문가. 기본 리더보드를 넘어서는 커스텀 탭 기반 리더보드,
  정렬 기능, 플레이어 통계 표시, 랭크 색상 구현.
  리더보드, 순위, 랭킹, 점수판, 스코어보드, leaderboard 요청 시 자동 발동.
allowed-tools: Agent Read Grep Glob Bash
effort: high
---

# Leaderboard UI Agent — Roblox 커스텀 리더보드 전문가

커스텀 리더보드 UI를 **즉시 실행 가능한 Luau 코드**로 구현한다.

---

## 절대 원칙

1. **기본 리더보드 숨기기** — StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
2. **Tab 기반** — 여러 통계를 탭으로 분리 (킬/데스/점수/레벨 등)
3. **정렬** — 컬럼 클릭으로 오름/내림차순 정렬
4. **랭크 색상** — 1~3위 금/은/동 색상, 본인 행 강조
5. **실시간 업데이트** — 서버에서 주기적으로 데이터 전송

---

## 리더보드 구조

```
ScreenGui "LeaderboardGui"
└── LeaderboardPanel (우상단, Tab 키로 토글)
    ├── Header
    │   ├── Title ("Leaderboard")
    │   └── TabBar (Kills | Level | Score)
    ├── ColumnHeaders (Rank | Player | Value)
    └── ScrollingFrame (플레이어 행 목록)
        ├── PlayerRow_1 (금색 — 1위)
        ├── PlayerRow_2 (은색 — 2위)
        ├── PlayerRow_3 (동색 — 3위)
        ├── PlayerRow_4 ...
        └── ...
```

---

## 완전한 커스텀 리더보드 구현

```lua
--!strict
-- LeaderboardUI.luau — LocalScript under StarterPlayerScripts
-- 커스텀 탭 리더보드 + 정렬 + 랭크 색상

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

------------------------------------------------------------------------
-- 기본 리더보드 숨기기
------------------------------------------------------------------------
pcall(function()
    StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
end)

------------------------------------------------------------------------
-- CONFIG
------------------------------------------------------------------------
local CONFIG = {
    PanelWidth = 340,
    PanelHeight = 450,
    RowHeight = 32,
    HeaderHeight = 36,

    RankColors = {
        [1] = Color3.fromRGB(255, 215, 60),  -- Gold
        [2] = Color3.fromRGB(192, 192, 210),  -- Silver
        [3] = Color3.fromRGB(205, 140, 60),   -- Bronze
    },
    SelfHighlight = Color3.fromRGB(40, 60, 100),
    DefaultRowColor = Color3.fromRGB(25, 25, 38),
    AltRowColor = Color3.fromRGB(30, 30, 45),
    AccentColor = Color3.fromRGB(70, 130, 255),
    TextColor = Color3.fromRGB(220, 220, 230),
    DimTextColor = Color3.fromRGB(140, 140, 160),
}

------------------------------------------------------------------------
-- HELPERS
------------------------------------------------------------------------
local function addCorner(p: GuiObject, r: number) Instance.new("UICorner", p).CornerRadius = UDim.new(0, r) end

------------------------------------------------------------------------
-- DATA
------------------------------------------------------------------------
type PlayerData = {
    userId: number,
    name: string,
    displayName: string,
    kills: number,
    deaths: number,
    score: number,
    level: number,
}

local leaderboardData: { PlayerData } = {}
local currentTab = "Score"
local sortAscending = false

------------------------------------------------------------------------
-- GUI
------------------------------------------------------------------------
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "LeaderboardGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 15
screenGui.Parent = playerGui

local panel = Instance.new("Frame")
panel.Name = "LeaderboardPanel"
panel.AnchorPoint = Vector2.new(1, 0)
panel.Position = UDim2.new(1, -12, 0, 50)
panel.Size = UDim2.new(0, CONFIG.PanelWidth, 0, CONFIG.PanelHeight)
panel.BackgroundColor3 = Color3.fromRGB(18, 18, 28)
panel.BackgroundTransparency = 0.05
panel.Visible = false
addCorner(panel, 10)
local panelStroke = Instance.new("UIStroke", panel)
panelStroke.Color = CONFIG.AccentColor; panelStroke.Thickness = 1.5
panel.Parent = screenGui

------------------------------------------------------------------------
-- HEADER + TABS
------------------------------------------------------------------------
local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 40)
header.BackgroundTransparency = 1
header.Parent = panel

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, 0, 1, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "LEADERBOARD"
titleLabel.TextColor3 = CONFIG.TextColor
titleLabel.TextSize = 16
titleLabel.Font = Enum.Font.GothamBold
titleLabel.Parent = header

-- Tab bar
local tabBar = Instance.new("Frame")
tabBar.Position = UDim2.new(0, 0, 0, 40)
tabBar.Size = UDim2.new(1, 0, 0, 30)
tabBar.BackgroundColor3 = Color3.fromRGB(22, 22, 34)
tabBar.Parent = panel

local tabLayout = Instance.new("UIListLayout")
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.Parent = tabBar

local tabs = { "Score", "Kills", "Level" }
local tabButtons: { [string]: TextButton } = {}

for _, tabName in tabs do
    local btn = Instance.new("TextButton")
    btn.Name = tabName
    btn.Size = UDim2.new(1 / #tabs, 0, 1, 0)
    btn.BackgroundColor3 = Color3.fromRGB(30, 30, 45)
    btn.Text = tabName
    btn.TextColor3 = CONFIG.DimTextColor
    btn.TextSize = 12
    btn.Font = Enum.Font.GothamMedium
    btn.AutoButtonColor = false
    btn.Parent = tabBar
    tabButtons[tabName] = btn
end

------------------------------------------------------------------------
-- COLUMN HEADERS
------------------------------------------------------------------------
local colHeader = Instance.new("Frame")
colHeader.Position = UDim2.new(0, 0, 0, 74)
colHeader.Size = UDim2.new(1, 0, 0, 24)
colHeader.BackgroundColor3 = Color3.fromRGB(15, 15, 25)
colHeader.Parent = panel

local colNames = { { "#", 0.12 }, { "Player", 0.55 }, { "Value", 0.33 } }
local xPos = 0
for _, col in colNames do
    local lbl = Instance.new("TextButton")
    lbl.Position = UDim2.new(xPos, 0, 0, 0)
    lbl.Size = UDim2.new(col[2] :: number, 0, 1, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = col[1] :: string
    lbl.TextColor3 = CONFIG.DimTextColor
    lbl.TextSize = 11
    lbl.Font = Enum.Font.GothamBold
    lbl.AutoButtonColor = false
    lbl.Parent = colHeader
    xPos += col[2] :: number

    if col[1] == "Value" then
        lbl.MouseButton1Click:Connect(function()
            sortAscending = not sortAscending
        end)
    end
end

------------------------------------------------------------------------
-- SCROLLING FRAME (rows)
------------------------------------------------------------------------
local scroll = Instance.new("ScrollingFrame")
scroll.Position = UDim2.new(0, 0, 0, 100)
scroll.Size = UDim2.new(1, 0, 1, -100)
scroll.BackgroundTransparency = 1
scroll.ScrollBarThickness = 4
scroll.ScrollBarImageColor3 = CONFIG.AccentColor
scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.Parent = panel

local scrollLayout = Instance.new("UIListLayout")
scrollLayout.Padding = UDim.new(0, 1)
scrollLayout.SortOrder = Enum.SortOrder.LayoutOrder
scrollLayout.Parent = scroll

------------------------------------------------------------------------
-- ROW CREATION
------------------------------------------------------------------------
local function getStatValue(data: PlayerData, stat: string): number
    if stat == "Kills" then return data.kills
    elseif stat == "Level" then return data.level
    elseif stat == "Score" then return data.score
    else return 0
    end
end

local function refreshLeaderboard()
    -- Clear existing rows
    for _, child in scroll:GetChildren() do
        if child:IsA("Frame") then child:Destroy() end
    end

    -- Sort data
    local sorted = table.clone(leaderboardData)
    table.sort(sorted, function(a, b)
        local va = getStatValue(a, currentTab)
        local vb = getStatValue(b, currentTab)
        if sortAscending then return va < vb else return va > vb end
    end)

    -- Create rows
    for rank, data in sorted do
        local row = Instance.new("Frame")
        row.Name = "Row_" .. rank
        row.Size = UDim2.new(1, 0, 0, CONFIG.RowHeight)
        row.LayoutOrder = rank

        -- Determine row color
        if data.userId == player.UserId then
            row.BackgroundColor3 = CONFIG.SelfHighlight
        elseif rank % 2 == 0 then
            row.BackgroundColor3 = CONFIG.AltRowColor
        else
            row.BackgroundColor3 = CONFIG.DefaultRowColor
        end
        row.Parent = scroll

        -- Rank
        local rankColor = CONFIG.RankColors[rank] or CONFIG.DimTextColor
        local rankLabel = Instance.new("TextLabel")
        rankLabel.Size = UDim2.new(0.12, 0, 1, 0)
        rankLabel.BackgroundTransparency = 1
        rankLabel.Text = if rank <= 3 then tostring(rank) else tostring(rank)
        rankLabel.TextColor3 = rankColor
        rankLabel.TextSize = if rank <= 3 then 16 else 13
        rankLabel.Font = if rank <= 3 then Enum.Font.GothamBlack else Enum.Font.GothamMedium
        rankLabel.Parent = row

        -- Player name
        local nameLabel = Instance.new("TextLabel")
        nameLabel.Position = UDim2.new(0.12, 0, 0, 0)
        nameLabel.Size = UDim2.new(0.55, 0, 1, 0)
        nameLabel.BackgroundTransparency = 1
        nameLabel.Text = data.displayName
        nameLabel.TextColor3 = if data.userId == player.UserId then Color3.fromRGB(100, 200, 255) else CONFIG.TextColor
        nameLabel.TextSize = 13
        nameLabel.Font = Enum.Font.GothamMedium
        nameLabel.TextXAlignment = Enum.TextXAlignment.Left
        nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
        nameLabel.Parent = row

        -- Value
        local value = getStatValue(data, currentTab)
        local valLabel = Instance.new("TextLabel")
        valLabel.Position = UDim2.new(0.67, 0, 0, 0)
        valLabel.Size = UDim2.new(0.33, 0, 1, 0)
        valLabel.BackgroundTransparency = 1
        valLabel.Text = tostring(value)
        valLabel.TextColor3 = rankColor
        valLabel.TextSize = 14
        valLabel.Font = Enum.Font.GothamBold
        valLabel.Parent = row
    end

    -- Update tab button styles
    for tabName, btn in tabButtons do
        btn.BackgroundColor3 = if tabName == currentTab then CONFIG.AccentColor else Color3.fromRGB(30, 30, 45)
        btn.TextColor3 = if tabName == currentTab then CONFIG.TextColor else CONFIG.DimTextColor
    end
end

------------------------------------------------------------------------
-- TAB CLICKS
------------------------------------------------------------------------
for tabName, btn in tabButtons do
    btn.MouseButton1Click:Connect(function()
        currentTab = tabName
        refreshLeaderboard()
    end)
end

------------------------------------------------------------------------
-- TAB KEY TOGGLE
------------------------------------------------------------------------
UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == Enum.KeyCode.Tab then
        panel.Visible = not panel.Visible
    end
end)

------------------------------------------------------------------------
-- COLLECT DATA FROM PLAYERS
------------------------------------------------------------------------
local function updateFromPlayers()
    leaderboardData = {}
    for _, p in Players:GetPlayers() do
        local leaderstats = p:FindFirstChild("leaderstats")
        local data: PlayerData = {
            userId = p.UserId,
            name = p.Name,
            displayName = p.DisplayName,
            kills = 0,
            deaths = 0,
            score = 0,
            level = 0,
        }
        if leaderstats then
            local kills = leaderstats:FindFirstChild("Kills")
            if kills and kills:IsA("IntValue") then data.kills = kills.Value end
            local deaths = leaderstats:FindFirstChild("Deaths")
            if deaths and deaths:IsA("IntValue") then data.deaths = deaths.Value end
            local score = leaderstats:FindFirstChild("Score")
            if score and score:IsA("IntValue") then data.score = score.Value end
            local level = leaderstats:FindFirstChild("Level")
            if level and level:IsA("IntValue") then data.level = level.Value end
        end
        table.insert(leaderboardData, data)
    end
    refreshLeaderboard()
end

-- 주기적 업데이트
task.spawn(function()
    while true do
        updateFromPlayers()
        task.wait(2)
    end
end)

-- Remote로 서버에서 푸시 데이터 받기
local function safeListen(name: string, cb: (...any) -> ())
    local e = ReplicatedStorage:FindFirstChild(name)
    if e and e:IsA("RemoteEvent") then
        (e :: RemoteEvent).OnClientEvent:Connect(cb)
    end
end

safeListen("UpdateLeaderboard", function(data: { PlayerData })
    leaderboardData = data
    refreshLeaderboard()
end)
```

## 서버측 leaderstats 생성 예시

```lua
-- ServerScriptService > Script
local Players = game:GetService("Players")

Players.PlayerAdded:Connect(function(player)
    local leaderstats = Instance.new("Folder")
    leaderstats.Name = "leaderstats"
    leaderstats.Parent = player

    local score = Instance.new("IntValue")
    score.Name = "Score"; score.Value = 0; score.Parent = leaderstats

    local kills = Instance.new("IntValue")
    kills.Name = "Kills"; kills.Value = 0; kills.Parent = leaderstats

    local level = Instance.new("IntValue")
    level.Name = "Level"; level.Value = 1; level.Parent = leaderstats
end)
```

## 사용 예시

```lua
-- Tab 키로 리더보드 토글
-- 탭 클릭으로 Score/Kills/Level 전환
-- Value 컬럼 클릭으로 정렬 방향 전환
-- 본인 행은 파란색 강조, 1~3위는 금/은/동색
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
