---
name: ui
description: >
  Roblox UI 전문가. ScreenGui, Frame, TextLabel, TextButton, ImageLabel, UIListLayout,
  UIGridLayout, UICorner, UIStroke, UIGradient, UIPadding, 반응형 UI.
  UI, 인터페이스, 화면, 레이아웃 요청 시 자동 발동.
allowed-tools: Agent Read Grep Glob Bash
effort: high
---

# UI Agent — Roblox UI 전문가

## UI 구조
```
ScreenGui (ResetOnSpawn=false, ZIndexBehavior=Sibling)
└── Frame (컨테이너)
    ├── UICorner (둥근 모서리)
    ├── UIStroke (테두리)
    ├── UIGradient (그라데이션)
    ├── UIPadding (내부 여백)
    ├── UIListLayout / UIGridLayout (자동 정렬)
    └── 자식 요소들
```

## UDim2 규칙
```lua
UDim2.new(scaleX, offsetX, scaleY, offsetY)
-- Scale: 0~1 부모 비율, Offset: 픽셀 고정
-- 중앙: AnchorPoint=Vector2.new(0.5,0.5), Position=UDim2.new(0.5,0,0.5,0)
```

## 레이아웃
```lua
-- UIListLayout: 수직/수평 자동정렬
local list = Instance.new("UIListLayout")
list.FillDirection = Enum.FillDirection.Vertical
list.HorizontalAlignment = Enum.HorizontalAlignment.Center
list.Padding = UDim.new(0, 5)
list.SortOrder = Enum.SortOrder.LayoutOrder

-- UIGridLayout: 그리드 (인벤토리)
local grid = Instance.new("UIGridLayout")
grid.CellSize = UDim2.new(0, 64, 0, 64)
grid.CellPadding = UDim2.new(0, 4, 0, 4)

-- UICorner (둥근 모서리)
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)

-- UIStroke (테두리)
local stroke = Instance.new("UIStroke", frame)
stroke.Color = Color3.fromRGB(100,150,255); stroke.Thickness = 2

-- UIGradient (그라데이션)
local grad = Instance.new("UIGradient", frame)
grad.Color = ColorSequence.new(Color3.fromRGB(40,40,60), Color3.fromRGB(20,20,30))
grad.Rotation = 90

-- UIPadding
local pad = Instance.new("UIPadding", frame)
pad.PaddingLeft = UDim.new(0,10); pad.PaddingRight = UDim.new(0,10)
pad.PaddingTop = UDim.new(0,5); pad.PaddingBottom = UDim.new(0,5)
```

## 체력바
```lua
local function createHealthBar(parent)
    local bg = Instance.new("Frame")
    bg.Size = UDim2.new(0.25,0,0,30); bg.Position = UDim2.new(0.01,0,0.95,0)
    bg.AnchorPoint = Vector2.new(0,1); bg.BackgroundColor3 = Color3.fromRGB(30,30,30)
    bg.BorderSizePixel = 0; Instance.new("UICorner",bg).CornerRadius = UDim.new(0,6)
    
    local fill = Instance.new("Frame")
    fill.Name = "Fill"; fill.Size = UDim2.new(1,0,1,0)
    fill.BackgroundColor3 = Color3.fromRGB(50,200,50); fill.BorderSizePixel = 0
    Instance.new("UICorner",fill).CornerRadius = UDim.new(0,6)
    fill.Parent = bg
    
    local txt = Instance.new("TextLabel")
    txt.Size = UDim2.new(1,0,1,0); txt.Text = "100/100"
    txt.TextColor3 = Color3.new(1,1,1); txt.Font = Enum.Font.GothamBold
    txt.TextScaled = true; txt.BackgroundTransparency = 1; txt.ZIndex = 2
    txt.Parent = bg; bg.Parent = parent
    return bg, fill, txt
end

local function updateHealthBar(fill, txt, current, max)
    local ratio = math.clamp(current/max, 0, 1)
    TweenService:Create(fill, TweenInfo.new(0.3), {
        Size = UDim2.new(ratio,0,1,0),
        BackgroundColor3 = Color3.fromRGB(255*(1-ratio), 200*ratio, 50)
    }):Play()
    txt.Text = math.floor(current) .. "/" .. max
end
```

## UI 애니메이션
```lua
local function slideIn(frame, from, dur)
    local endPos = frame.Position
    local dirs = {Left=UDim2.new(-1,0,endPos.Y.Scale,endPos.Y.Offset),
        Right=UDim2.new(1,0,endPos.Y.Scale,endPos.Y.Offset),
        Top=UDim2.new(endPos.X.Scale,endPos.X.Offset,-1,0),
        Bottom=UDim2.new(endPos.X.Scale,endPos.X.Offset,1,0)}
    frame.Position = dirs[from or "Left"]; frame.Visible = true
    TweenService:Create(frame, TweenInfo.new(dur or 0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
        {Position = endPos}):Play()
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
