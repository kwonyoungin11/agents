---
name: tutorial
description: >
  Roblox 튜토리얼 시스템 전문가. 단계별 튜토리얼, 하이라이트 강조, 화살표 인디케이터,
  건너뛰기 옵션, 완료 추적, DataStore 저장 구현.
  튜토리얼, 가이드, 안내, 초보자, 도움말, 튜토, 설명, tutorial 요청 시 자동 발동.
allowed-tools: Agent Read Grep Glob Bash
effort: high
---

# Tutorial Agent — Roblox 튜토리얼 시스템 전문가

단계별 튜토리얼 시스템을 **즉시 실행 가능한 Luau 코드**로 구현한다.

---

## 절대 원칙

1. **단계별 진행** — 각 단계는 독립적으로 정의, 순서대로 또는 조건부 진행
2. **하이라이트** — 현재 단계에서 주목할 UI/오브젝트를 반투명 오버레이로 강조
3. **화살표 인디케이터** — 대상을 가리키는 애니메이션 화살표
4. **건너뛰기** — 언제든지 튜토리얼 건너뛸 수 있는 옵션
5. **완료 저장** — DataStore에 완료 상태 저장, 다시 보지 않기

---

## 튜토리얼 구조

```
ScreenGui "TutorialGui"
├── DarkOverlay (반투명 검정, 클릭 차단)
├── HighlightCutout (하이라이트 할 영역만 투명)
├── DialogBox (하단 또는 대상 근처)
│   ├── StepTitle
│   ├── StepDescription
│   ├── NextButton
│   ├── SkipButton
│   └── StepIndicator ("2/5")
├── ArrowIndicator (대상을 가리키는 화살표)
└── WorldHighlight (Highlight 인스턴스 — 3D 오브젝트 강조)
```

---

## 완전한 튜토리얼 시스템 구현

```lua
--!strict
-- TutorialSystem.luau — LocalScript under StarterPlayerScripts
-- 단계별 튜토리얼 + 하이라이트 + 화살표 + 건너뛰기 + DataStore 저장

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

------------------------------------------------------------------------
-- CONFIG
------------------------------------------------------------------------
local CONFIG = {
    OverlayTransparency = 0.6,
    DialogWidth = 420,
    DialogHeight = 160,
    ArrowSize = 40,
    ArrowBobAmount = 8,      -- 화살표 위아래 흔들림 (px)
    ArrowBobSpeed = 1.5,      -- 흔들림 속도
    AccentColor = Color3.fromRGB(70, 180, 255),
    BgColor = Color3.fromRGB(20, 20, 32),
    TextColor = Color3.fromRGB(230, 230, 240),
    SkipColor = Color3.fromRGB(150, 150, 170),
}

------------------------------------------------------------------------
-- STEP DEFINITION TYPE
------------------------------------------------------------------------
export type TutorialStep = {
    title: string,
    description: string,
    -- UI 하이라이트 (ScreenGui 내 GuiObject 경로)
    highlightGui: GuiObject?,
    -- 3D 월드 하이라이트 (Highlight 인스턴스 사용)
    highlightModel: Instance?,
    -- 화살표 대상 (GuiObject의 경우 2D, Part의 경우 BillboardGui)
    arrowTarget: (GuiObject | BasePart)?,
    arrowDirection: string?,  -- "up"|"down"|"left"|"right"
    -- 진행 조건 (nil이면 Next 버튼 클릭으로 진행)
    waitForEvent: string?,    -- RemoteEvent 이름
    autoAdvanceDelay: number?, -- N초 후 자동 진행
}

------------------------------------------------------------------------
-- HELPERS
------------------------------------------------------------------------
local function addCorner(p: GuiObject, r: number) Instance.new("UICorner", p).CornerRadius = UDim.new(0, r) end

------------------------------------------------------------------------
-- SCREEN GUI
------------------------------------------------------------------------
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "TutorialGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.DisplayOrder = 150
screenGui.Enabled = false
screenGui.Parent = playerGui

------------------------------------------------------------------------
-- DARK OVERLAY
------------------------------------------------------------------------
local overlay = Instance.new("Frame")
overlay.Name = "DarkOverlay"
overlay.Size = UDim2.new(1, 0, 1, 0)
overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
overlay.BackgroundTransparency = CONFIG.OverlayTransparency
overlay.ZIndex = 50
overlay.Parent = screenGui

------------------------------------------------------------------------
-- ARROW INDICATOR
------------------------------------------------------------------------
local arrowFrame = Instance.new("ImageLabel")
arrowFrame.Name = "Arrow"
arrowFrame.AnchorPoint = Vector2.new(0.5, 0.5)
arrowFrame.Size = UDim2.new(0, CONFIG.ArrowSize, 0, CONFIG.ArrowSize)
arrowFrame.BackgroundTransparency = 1
arrowFrame.Image = "rbxassetid://6034818375" -- arrow/triangle
arrowFrame.ImageColor3 = CONFIG.AccentColor
arrowFrame.ZIndex = 60
arrowFrame.Visible = false
arrowFrame.Parent = screenGui

-- Arrow bob animation
local arrowBobTween: Tween? = nil
local function startArrowBob()
    if arrowBobTween then arrowBobTween:Cancel() end
    local basePos = arrowFrame.Position
    arrowBobTween = TweenService:Create(arrowFrame,
        TweenInfo.new(0.5 / CONFIG.ArrowBobSpeed, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
        { Position = basePos + UDim2.new(0, 0, 0, -CONFIG.ArrowBobAmount) })
    arrowBobTween:Play()
end

------------------------------------------------------------------------
-- DIALOG BOX
------------------------------------------------------------------------
local dialog = Instance.new("Frame")
dialog.Name = "DialogBox"
dialog.AnchorPoint = Vector2.new(0.5, 1)
dialog.Position = UDim2.new(0.5, 0, 1, -30)
dialog.Size = UDim2.new(0, CONFIG.DialogWidth, 0, CONFIG.DialogHeight)
dialog.BackgroundColor3 = CONFIG.BgColor
dialog.BackgroundTransparency = 0.05
dialog.ZIndex = 70
addCorner(dialog, 12)
local dialogStroke = Instance.new("UIStroke", dialog)
dialogStroke.Color = CONFIG.AccentColor; dialogStroke.Thickness = 2
dialog.Parent = screenGui

local dialogPad = Instance.new("UIPadding")
dialogPad.PaddingTop = UDim.new(0, 14)
dialogPad.PaddingBottom = UDim.new(0, 14)
dialogPad.PaddingLeft = UDim.new(0, 18)
dialogPad.PaddingRight = UDim.new(0, 18)
dialogPad.Parent = dialog

-- Step title
local stepTitle = Instance.new("TextLabel")
stepTitle.Name = "StepTitle"
stepTitle.Size = UDim2.new(1, 0, 0, 24)
stepTitle.BackgroundTransparency = 1
stepTitle.Text = "Step Title"
stepTitle.TextColor3 = CONFIG.AccentColor
stepTitle.TextSize = 18
stepTitle.Font = Enum.Font.GothamBold
stepTitle.TextXAlignment = Enum.TextXAlignment.Left
stepTitle.ZIndex = 71
stepTitle.Parent = dialog

-- Step description
local stepDesc = Instance.new("TextLabel")
stepDesc.Name = "StepDesc"
stepDesc.Position = UDim2.new(0, 0, 0, 30)
stepDesc.Size = UDim2.new(1, 0, 0, 60)
stepDesc.BackgroundTransparency = 1
stepDesc.Text = "Description text here..."
stepDesc.TextColor3 = CONFIG.TextColor
stepDesc.TextSize = 14
stepDesc.Font = Enum.Font.Gotham
stepDesc.TextWrapped = true
stepDesc.TextXAlignment = Enum.TextXAlignment.Left
stepDesc.TextYAlignment = Enum.TextYAlignment.Top
stepDesc.ZIndex = 71
stepDesc.Parent = dialog

-- Step indicator (e.g., "2 / 5")
local stepIndicator = Instance.new("TextLabel")
stepIndicator.Name = "StepIndicator"
stepIndicator.AnchorPoint = Vector2.new(0, 1)
stepIndicator.Position = UDim2.new(0, 0, 1, 0)
stepIndicator.Size = UDim2.new(0.3, 0, 0, 20)
stepIndicator.BackgroundTransparency = 1
stepIndicator.Text = "1 / 5"
stepIndicator.TextColor3 = CONFIG.SkipColor
stepIndicator.TextSize = 12
stepIndicator.Font = Enum.Font.GothamMedium
stepIndicator.TextXAlignment = Enum.TextXAlignment.Left
stepIndicator.ZIndex = 71
stepIndicator.Parent = dialog

-- Next button
local nextBtn = Instance.new("TextButton")
nextBtn.Name = "NextButton"
nextBtn.AnchorPoint = Vector2.new(1, 1)
nextBtn.Position = UDim2.new(1, 0, 1, 0)
nextBtn.Size = UDim2.new(0, 100, 0, 34)
nextBtn.BackgroundColor3 = CONFIG.AccentColor
nextBtn.Text = "Next"
nextBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
nextBtn.TextSize = 15
nextBtn.Font = Enum.Font.GothamBold
nextBtn.AutoButtonColor = false
nextBtn.ZIndex = 71
addCorner(nextBtn, 8)
nextBtn.Parent = dialog

-- Hover effect
nextBtn.MouseEnter:Connect(function()
    TweenService:Create(nextBtn, TweenInfo.new(0.15), { BackgroundColor3 = Color3.fromRGB(100, 200, 255) }):Play()
end)
nextBtn.MouseLeave:Connect(function()
    TweenService:Create(nextBtn, TweenInfo.new(0.15), { BackgroundColor3 = CONFIG.AccentColor }):Play()
end)

-- Skip button
local skipBtn = Instance.new("TextButton")
skipBtn.Name = "SkipButton"
skipBtn.AnchorPoint = Vector2.new(1, 1)
skipBtn.Position = UDim2.new(1, -110, 1, 0)
skipBtn.Size = UDim2.new(0, 80, 0, 34)
skipBtn.BackgroundTransparency = 1
skipBtn.Text = "Skip"
skipBtn.TextColor3 = CONFIG.SkipColor
skipBtn.TextSize = 13
skipBtn.Font = Enum.Font.GothamMedium
skipBtn.ZIndex = 71
skipBtn.Parent = dialog

------------------------------------------------------------------------
-- HIGHLIGHT SYSTEM
------------------------------------------------------------------------
local currentHighlight: Highlight? = nil

local function clearHighlights()
    if currentHighlight then
        currentHighlight:Destroy()
        currentHighlight = nil
    end
    arrowFrame.Visible = false
    if arrowBobTween then arrowBobTween:Cancel() end
end

local function highlightWorldObject(instance: Instance)
    clearHighlights()
    local highlight = Instance.new("Highlight")
    highlight.Adornee = instance
    highlight.FillColor = CONFIG.AccentColor
    highlight.FillTransparency = 0.7
    highlight.OutlineColor = CONFIG.AccentColor
    highlight.OutlineTransparency = 0
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.Parent = instance
    currentHighlight = highlight
end

local function positionArrowAtGui(target: GuiObject, direction: string?)
    arrowFrame.Visible = true
    local dir = direction or "down"
    local pos = target.AbsolutePosition
    local size = target.AbsoluteSize

    if dir == "down" then
        arrowFrame.Rotation = 180
        arrowFrame.Position = UDim2.new(0, pos.X + size.X / 2, 0, pos.Y - CONFIG.ArrowSize)
    elseif dir == "up" then
        arrowFrame.Rotation = 0
        arrowFrame.Position = UDim2.new(0, pos.X + size.X / 2, 0, pos.Y + size.Y + CONFIG.ArrowSize)
    elseif dir == "left" then
        arrowFrame.Rotation = 90
        arrowFrame.Position = UDim2.new(0, pos.X + size.X + CONFIG.ArrowSize, 0, pos.Y + size.Y / 2)
    elseif dir == "right" then
        arrowFrame.Rotation = 270
        arrowFrame.Position = UDim2.new(0, pos.X - CONFIG.ArrowSize, 0, pos.Y + size.Y / 2)
    end

    startArrowBob()
end

------------------------------------------------------------------------
-- TUTORIAL STATE
------------------------------------------------------------------------
local steps: { TutorialStep } = {}
local currentStepIndex = 0
local isRunning = false
local advanceSignal: BindableEvent = Instance.new("BindableEvent")

local function displayStep(index: number)
    local step = steps[index]
    if not step then return end

    clearHighlights()

    -- Update dialog
    stepTitle.Text = step.title
    stepDesc.Text = step.description
    stepIndicator.Text = string.format("%d / %d", index, #steps)
    nextBtn.Text = if index == #steps then "Finish" else "Next"

    -- Highlight GUI element
    if step.highlightGui then
        -- 해당 GUI 요소의 ZIndex를 높여서 오버레이 위에 표시
        step.highlightGui.ZIndex = 55
    end

    -- Highlight 3D object
    if step.highlightModel then
        highlightWorldObject(step.highlightModel)
    end

    -- Arrow pointing at target
    if step.arrowTarget then
        if typeof(step.arrowTarget) == "Instance" and (step.arrowTarget :: Instance):IsA("GuiObject") then
            positionArrowAtGui(step.arrowTarget :: GuiObject, step.arrowDirection)
        end
    end

    -- Auto advance
    if step.autoAdvanceDelay then
        task.delay(step.autoAdvanceDelay, function()
            if currentStepIndex == index and isRunning then
                advanceSignal:Fire()
            end
        end)
    end

    -- Wait for event
    if step.waitForEvent then
        local remote = ReplicatedStorage:FindFirstChild(step.waitForEvent)
        if remote and remote:IsA("RemoteEvent") then
            local conn
            conn = (remote :: RemoteEvent).OnClientEvent:Connect(function()
                conn:Disconnect()
                if currentStepIndex == index and isRunning then
                    advanceSignal:Fire()
                end
            end)
        end
    end

    -- Slide-in animation
    dialog.Position = UDim2.new(0.5, 0, 1, 50)
    TweenService:Create(dialog, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
        { Position = UDim2.new(0.5, 0, 1, -30) }):Play()
end

------------------------------------------------------------------------
-- ADVANCE / SKIP
------------------------------------------------------------------------
local function advanceStep()
    if not isRunning then return end
    -- Restore previous step's GUI ZIndex
    if steps[currentStepIndex] and steps[currentStepIndex].highlightGui then
        steps[currentStepIndex].highlightGui.ZIndex = 1
    end

    currentStepIndex += 1
    if currentStepIndex > #steps then
        -- Tutorial complete
        isRunning = false
        clearHighlights()
        screenGui.Enabled = false
        -- Notify server of completion
        local completeRemote = ReplicatedStorage:FindFirstChild("TutorialComplete")
        if completeRemote and completeRemote:IsA("RemoteEvent") then
            (completeRemote :: RemoteEvent):FireServer()
        end
        return
    end
    displayStep(currentStepIndex)
end

local function skipTutorial()
    -- Restore all GUI ZIndex
    for _, step in steps do
        if step.highlightGui then
            step.highlightGui.ZIndex = 1
        end
    end
    isRunning = false
    clearHighlights()
    screenGui.Enabled = false
    -- Notify server
    local skipRemote = ReplicatedStorage:FindFirstChild("TutorialSkipped")
    if skipRemote and skipRemote:IsA("RemoteEvent") then
        (skipRemote :: RemoteEvent):FireServer()
    end
end

nextBtn.MouseButton1Click:Connect(advanceStep)
skipBtn.MouseButton1Click:Connect(skipTutorial)
advanceSignal.Event:Connect(advanceStep)

------------------------------------------------------------------------
-- PUBLIC API
------------------------------------------------------------------------
local TutorialSystem = {}

function TutorialSystem.start(tutorialSteps: { TutorialStep })
    steps = tutorialSteps
    currentStepIndex = 0
    isRunning = true
    screenGui.Enabled = true
    advanceStep() -- Show first step
end

function TutorialSystem.isRunning(): boolean
    return isRunning
end

function TutorialSystem.getCurrentStep(): number
    return currentStepIndex
end

return TutorialSystem
```

## 서버측 완료 추적 (DataStore 저장)

```lua
--!strict
-- TutorialTracker.luau — Script under ServerScriptService
-- 튜토리얼 완료/건너뛰기 DataStore 저장

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local tutorialStore = DataStoreService:GetDataStore("TutorialProgress_v1")

-- RemoteEvents
local completeRemote = Instance.new("RemoteEvent")
completeRemote.Name = "TutorialComplete"
completeRemote.Parent = ReplicatedStorage

local skipRemote = Instance.new("RemoteEvent")
skipRemote.Name = "TutorialSkipped"
skipRemote.Parent = ReplicatedStorage

local checkRemote = Instance.new("RemoteFunction")
checkRemote.Name = "CheckTutorialDone"
checkRemote.Parent = ReplicatedStorage

-- Save completion
local function markComplete(player: Player)
    pcall(function()
        tutorialStore:SetAsync("tutorial_" .. player.UserId, {
            completed = true,
            timestamp = os.time(),
        })
    end)
end

completeRemote.OnServerEvent:Connect(function(player)
    markComplete(player)
    print("[Tutorial]", player.Name, "completed tutorial")
end)

skipRemote.OnServerEvent:Connect(function(player)
    markComplete(player)
    print("[Tutorial]", player.Name, "skipped tutorial")
end)

-- Check if already done
checkRemote.OnServerInvoke = function(player: Player): boolean
    local success, data = pcall(function()
        return tutorialStore:GetAsync("tutorial_" .. player.UserId)
    end)
    if success and data and data.completed then
        return true
    end
    return false
end
```

## 사용 예시

```lua
local TutorialSystem = require(path.to.TutorialSystem)
local RS = game:GetService("ReplicatedStorage")
local checkRemote = RS:WaitForChild("CheckTutorialDone") :: RemoteFunction

-- 튜토리얼 이미 완료했는지 확인
local alreadyDone = checkRemote:InvokeServer()
if not alreadyDone then
    TutorialSystem.start({
        {
            title = "Welcome!",
            description = "Welcome to the game! Let's learn the basics.",
            autoAdvanceDelay = 3,
        },
        {
            title = "Movement",
            description = "Use W/A/S/D to move around. Try it now!",
            arrowTarget = nil, -- 3D 월드에서 플레이어 하이라이트
        },
        {
            title = "Inventory",
            description = "Press TAB to open your inventory.",
            highlightGui = playerGui:FindFirstChild("InventoryButton"),
            arrowTarget = playerGui:FindFirstChild("InventoryButton"),
            arrowDirection = "down",
        },
        {
            title = "Combat",
            description = "Click to attack enemies. Defeat the training dummy!",
            highlightModel = workspace:FindFirstChild("TrainingDummy"),
            waitForEvent = "DummyDefeated",
        },
        {
            title = "You're Ready!",
            description = "Tutorial complete. Good luck on your adventure!",
            autoAdvanceDelay = 4,
        },
    })
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
