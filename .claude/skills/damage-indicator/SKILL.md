---
name: damage-indicator
description: >
  Roblox 데미지 인디케이터 전문가. 플로팅 데미지 넘버, 타입별 색상(일반/크리티컬/힐),
  페이드 업 애니메이션, BillboardGui 월드 공간 표시 구현.
  데미지, 데미지숫자, 피해표시, 힐표시, 크리티컬, 플로팅넘버, damage 요청 시 자동 발동.
allowed-tools: Agent Read Grep Glob Bash
effort: high
---

# Damage Indicator Agent — Roblox 데미지 인디케이터 전문가

플로팅 데미지 넘버를 **즉시 실행 가능한 Luau 코드**로 구현한다.

---

## 절대 원칙

1. **BillboardGui** — 월드 공간에서 항상 카메라를 향하도록 표시
2. **오브젝트 풀링** — 매번 생성/파괴 대신 풀에서 재활용 (성능)
3. **타입별 스타일** — 일반(흰), 크리티컬(노랑+크게), 힐(초록), 독(보라) 등
4. **랜덤 오프셋** — 숫자가 겹치지 않도록 X축 랜덤 분산
5. **TweenService** — 위로 떠오르며 페이드 아웃 애니메이션

---

## 데미지 인디케이터 구조

```
workspace (월드 공간)
└── DamageNumber_Part (투명, 앵커드)
    └── BillboardGui (AlwaysOnTop, Size적절)
        └── TextLabel (데미지 숫자)
            └── UIStroke (외곽선)
```

---

## 완전한 데미지 인디케이터 구현

```lua
--!strict
-- DamageIndicator.luau — LocalScript under StarterPlayerScripts
-- 플로팅 데미지 넘버 + 오브젝트 풀링 + 타입별 스타일

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

------------------------------------------------------------------------
-- CONFIG
------------------------------------------------------------------------
local CONFIG = {
    FloatHeight = 4,          -- 위로 뜨는 높이 (studs)
    FloatDuration = 1.0,      -- 애니메이션 시간 (초)
    RandomOffsetX = 1.5,      -- X축 랜덤 오프셋 범위
    RandomOffsetZ = 0.5,
    PoolSize = 30,            -- 오브젝트 풀 크기
    BillboardSize = UDim2.new(0, 120, 0, 60),

    -- 타입별 설정
    Styles = {
        normal = {
            color = Color3.fromRGB(255, 255, 255),
            strokeColor = Color3.fromRGB(0, 0, 0),
            size = 22,
            font = Enum.Font.GothamBold,
            prefix = "",
        },
        crit = {
            color = Color3.fromRGB(255, 220, 50),
            strokeColor = Color3.fromRGB(180, 100, 0),
            size = 32,
            font = Enum.Font.GothamBlack,
            prefix = "",
        },
        heal = {
            color = Color3.fromRGB(80, 255, 80),
            strokeColor = Color3.fromRGB(0, 80, 0),
            size = 22,
            font = Enum.Font.GothamBold,
            prefix = "+",
        },
        poison = {
            color = Color3.fromRGB(170, 60, 255),
            strokeColor = Color3.fromRGB(60, 0, 100),
            size = 18,
            font = Enum.Font.GothamMedium,
            prefix = "",
        },
        fire = {
            color = Color3.fromRGB(255, 120, 30),
            strokeColor = Color3.fromRGB(120, 40, 0),
            size = 20,
            font = Enum.Font.GothamBold,
            prefix = "",
        },
        shield = {
            color = Color3.fromRGB(100, 180, 255),
            strokeColor = Color3.fromRGB(20, 60, 120),
            size = 20,
            font = Enum.Font.GothamBold,
            prefix = "",
        },
        miss = {
            color = Color3.fromRGB(150, 150, 150),
            strokeColor = Color3.fromRGB(50, 50, 50),
            size = 18,
            font = Enum.Font.GothamMedium,
            prefix = "",
        },
    },
}

------------------------------------------------------------------------
-- OBJECT POOL
------------------------------------------------------------------------
type PoolObject = {
    part: Part,
    billboard: BillboardGui,
    label: TextLabel,
    stroke: UIStroke,
    inUse: boolean,
}

local pool: { PoolObject } = {}

local poolFolder = Instance.new("Folder")
poolFolder.Name = "_DamageIndicators"
poolFolder.Parent = workspace

local function createPoolObject(): PoolObject
    local part = Instance.new("Part")
    part.Name = "DmgNum"
    part.Size = Vector3.new(0.1, 0.1, 0.1)
    part.Anchored = true
    part.CanCollide = false
    part.Transparency = 1
    part.CastShadow = false
    part.Parent = poolFolder

    local billboard = Instance.new("BillboardGui")
    billboard.Name = "DmgBillboard"
    billboard.Size = CONFIG.BillboardSize
    billboard.StudsOffset = Vector3.new(0, 0, 0)
    billboard.AlwaysOnTop = true
    billboard.MaxDistance = 100
    billboard.Parent = part

    local label = Instance.new("TextLabel")
    label.Name = "Label"
    label.Size = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.Text = "0"
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.TextSize = 22
    label.Font = Enum.Font.GothamBold
    label.TextStrokeTransparency = 1 -- UIStroke 사용
    label.TextTransparency = 1
    label.Parent = billboard

    local uiStroke = Instance.new("UIStroke")
    uiStroke.Color = Color3.fromRGB(0, 0, 0)
    uiStroke.Thickness = 2
    uiStroke.Transparency = 1
    uiStroke.Parent = label

    return {
        part = part,
        billboard = billboard,
        label = label,
        stroke = uiStroke,
        inUse = false,
    }
end

-- 풀 초기화
for i = 1, CONFIG.PoolSize do
    table.insert(pool, createPoolObject())
end

local function acquireFromPool(): PoolObject
    for _, obj in pool do
        if not obj.inUse then
            obj.inUse = true
            return obj
        end
    end
    -- 풀 부족 시 확장
    local newObj = createPoolObject()
    newObj.inUse = true
    table.insert(pool, newObj)
    return newObj
end

local function releaseToPool(obj: PoolObject)
    obj.inUse = false
    obj.label.TextTransparency = 1
    obj.stroke.Transparency = 1
    obj.part.Position = Vector3.new(0, -1000, 0)
end

------------------------------------------------------------------------
-- SHOW DAMAGE NUMBER
------------------------------------------------------------------------
local function showDamageNumber(position: Vector3, amount: number, damageType: string?)
    local style = CONFIG.Styles[damageType or "normal"] or CONFIG.Styles.normal
    local obj = acquireFromPool()

    -- 랜덤 오프셋
    local offsetX = (math.random() - 0.5) * 2 * CONFIG.RandomOffsetX
    local offsetZ = (math.random() - 0.5) * 2 * CONFIG.RandomOffsetZ
    local startPos = position + Vector3.new(offsetX, 0.5, offsetZ)

    -- 설정
    obj.part.Position = startPos
    obj.label.Text = style.prefix .. (if damageType == "miss" then "MISS" else tostring(math.floor(amount)))
    obj.label.TextColor3 = style.color
    obj.label.TextSize = style.size
    obj.label.Font = style.font
    obj.label.TextTransparency = 0
    obj.stroke.Color = style.strokeColor
    obj.stroke.Thickness = if damageType == "crit" then 3 else 2
    obj.stroke.Transparency = 0

    -- 크리티컬: 초기 스케일 업 효과
    if damageType == "crit" then
        obj.billboard.Size = UDim2.new(0, 180, 0, 90)
        TweenService:Create(obj.billboard,
            TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
            { Size = CONFIG.BillboardSize }):Play()
    else
        obj.billboard.Size = CONFIG.BillboardSize
    end

    -- 위로 떠오르기 애니메이션
    local endPos = startPos + Vector3.new(0, CONFIG.FloatHeight, 0)
    local floatTween = TweenService:Create(obj.part,
        TweenInfo.new(CONFIG.FloatDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { Position = endPos })
    floatTween:Play()

    -- 페이드 아웃 (후반부에서)
    task.delay(CONFIG.FloatDuration * 0.4, function()
        local fadeDuration = CONFIG.FloatDuration * 0.6
        TweenService:Create(obj.label,
            TweenInfo.new(fadeDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
            { TextTransparency = 1 }):Play()
        TweenService:Create(obj.stroke,
            TweenInfo.new(fadeDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
            { Transparency = 1 }):Play()
    end)

    -- 풀 반환
    task.delay(CONFIG.FloatDuration + 0.1, function()
        releaseToPool(obj)
    end)
end

------------------------------------------------------------------------
-- COMBO / ACCUMULATED DAMAGE
------------------------------------------------------------------------
local function showComboDamage(position: Vector3, hits: number, totalDamage: number)
    local obj = acquireFromPool()
    local startPos = position + Vector3.new(0, 2, 0)

    obj.part.Position = startPos
    obj.label.Text = string.format("%d HITS! %d", hits, totalDamage)
    obj.label.TextColor3 = Color3.fromRGB(255, 100, 50)
    obj.label.TextSize = 26
    obj.label.Font = Enum.Font.GothamBlack
    obj.label.TextTransparency = 0
    obj.stroke.Color = Color3.fromRGB(100, 30, 0)
    obj.stroke.Thickness = 3
    obj.stroke.Transparency = 0
    obj.billboard.Size = UDim2.new(0, 200, 0, 60)

    -- Scale pop animation
    obj.billboard.Size = UDim2.new(0, 60, 0, 20)
    TweenService:Create(obj.billboard,
        TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
        { Size = UDim2.new(0, 200, 0, 60) }):Play()

    local floatTween = TweenService:Create(obj.part,
        TweenInfo.new(1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { Position = startPos + Vector3.new(0, 5, 0) })
    floatTween:Play()

    task.delay(0.8, function()
        TweenService:Create(obj.label, TweenInfo.new(0.7), { TextTransparency = 1 }):Play()
        TweenService:Create(obj.stroke, TweenInfo.new(0.7), { Transparency = 1 }):Play()
    end)

    task.delay(1.6, function() releaseToPool(obj) end)
end

------------------------------------------------------------------------
-- REMOTE EVENT LISTENER
------------------------------------------------------------------------
local function safeListen(name: string, cb: (...any) -> ())
    local e = ReplicatedStorage:FindFirstChild(name)
    if e and e:IsA("RemoteEvent") then
        (e :: RemoteEvent).OnClientEvent:Connect(cb)
    end
end

safeListen("ShowDamageNumber", function(position: Vector3, amount: number, damageType: string?)
    showDamageNumber(position, amount, damageType)
end)

safeListen("ShowComboDamage", function(position: Vector3, hits: number, total: number)
    showComboDamage(position, hits, total)
end)

------------------------------------------------------------------------
-- PUBLIC API
------------------------------------------------------------------------
local DamageIndicator = {}
DamageIndicator.show = showDamageNumber
DamageIndicator.showCombo = showComboDamage
return DamageIndicator
```

## 서버측 RemoteEvent 생성

```lua
-- ServerScriptService > Script
local RS = game:GetService("ReplicatedStorage")
for _, name in {"ShowDamageNumber", "ShowComboDamage"} do
    if not RS:FindFirstChild(name) then
        local r = Instance.new("RemoteEvent"); r.Name = name; r.Parent = RS
    end
end
```

## 사용 예시

```lua
-- 클라이언트에서 직접
local DI = require(path.to.DamageIndicator)
DI.show(Vector3.new(0, 5, 0), 250, "crit")
DI.show(Vector3.new(0, 5, 0), 50, "normal")
DI.show(Vector3.new(0, 5, 0), 100, "heal")
DI.show(Vector3.new(0, 5, 0), 30, "poison")
DI.show(Vector3.new(0, 5, 0), 0, "miss")
DI.showCombo(Vector3.new(0, 5, 0), 5, 380)

-- 서버에서 모든 클라이언트로
RS.ShowDamageNumber:FireAllClients(hitPosition, 150, "crit")
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
