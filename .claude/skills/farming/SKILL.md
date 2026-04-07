---
name: farming
description: >
  Roblox 농업 시스템 전문가. 작물 심기, 성장 타이머, 물주기, 수확, 작물 데이터,
  밭 시스템, 계절 작물, 비료, 자동 농장.
  농사, 농장, 작물, 심기, 수확, 밭, 재배, 씨앗 요청 시 자동 발동.
allowed-tools: Agent Read Grep Glob Bash
effort: high
---

# Farming Agent — Roblox 농업 시스템 전문가

---

## 작물 데이터

```lua
local CropData = {
    Carrot = {
        growTime = 60,       -- 초
        stages = 4,          -- 성장 단계
        harvestItem = "Carrot",
        harvestAmount = {2, 4},
        seedPrice = 10,
        sellPrice = 25,
        waterNeeded = true,
        season = "Spring",
    },
    Wheat = {
        growTime = 120,
        stages = 5,
        harvestItem = "Wheat",
        harvestAmount = {3, 6},
        seedPrice = 5,
        sellPrice = 15,
        waterNeeded = true,
        season = "Summer",
    },
    Pumpkin = {
        growTime = 300,
        stages = 4,
        harvestItem = "Pumpkin",
        harvestAmount = {1, 2},
        seedPrice = 30,
        sellPrice = 80,
        waterNeeded = true,
        season = "Fall",
    },
}
```

## 밭(Plot) 시스템

```lua
local FarmPlot = {}

function FarmPlot.create(position, size)
    local plot = Instance.new("Part")
    plot.Name = "FarmPlot"
    plot.Size = Vector3.new(size or 4, 0.5, size or 4)
    plot.Position = position
    plot.Material = Enum.Material.Ground
    plot.Color = Color3.fromRGB(100, 70, 40)
    plot.Anchored = true
    plot.Parent = workspace
    
    plot:SetAttribute("State", "Empty")    -- Empty/Planted/Growing/Ready
    plot:SetAttribute("CropType", "")
    plot:SetAttribute("PlantedAt", 0)
    plot:SetAttribute("Watered", false)
    plot:SetAttribute("GrowthStage", 0)
    
    -- ProximityPrompt
    local prompt = Instance.new("ProximityPrompt")
    prompt.ActionText = "Plant"
    prompt.ObjectText = "Farm Plot"
    prompt.HoldDuration = 0.5
    prompt.MaxActivationDistance = 8
    prompt.Parent = plot
    
    return plot
end

function FarmPlot.plant(plot, cropType, playerId)
    local data = CropData[cropType]
    if not data then return false end
    if plot:GetAttribute("State") ~= "Empty" then return false end
    
    plot:SetAttribute("State", "Planted")
    plot:SetAttribute("CropType", cropType)
    plot:SetAttribute("PlantedAt", os.time())
    plot:SetAttribute("Watered", false)
    plot:SetAttribute("GrowthStage", 1)
    plot.Color = Color3.fromRGB(80, 60, 30)  -- 심은 상태
    
    -- 작물 시각 모델 (작은 새싹)
    local sprout = Instance.new("Part")
    sprout.Name = "CropVisual"
    sprout.Size = Vector3.new(0.3, 0.3, 0.3)
    sprout.Position = plot.Position + Vector3.new(0, 0.5, 0)
    sprout.Color = Color3.fromRGB(50, 150, 30)
    sprout.Material = Enum.Material.Grass
    sprout.Anchored = true
    sprout.CanCollide = false
    sprout.Parent = plot
    
    return true
end

function FarmPlot.water(plot)
    if plot:GetAttribute("State") ~= "Planted" and plot:GetAttribute("State") ~= "Growing" then
        return false
    end
    plot:SetAttribute("Watered", true)
    plot.Color = Color3.fromRGB(60, 45, 25)  -- 젖은 흙
    return true
end

function FarmPlot.harvest(plot, playerData)
    if plot:GetAttribute("State") ~= "Ready" then return nil end
    
    local cropType = plot:GetAttribute("CropType")
    local data = CropData[cropType]
    if not data then return nil end
    
    local amount = math.random(data.harvestAmount[1], data.harvestAmount[2])
    
    -- 밭 초기화
    local visual = plot:FindFirstChild("CropVisual")
    if visual then visual:Destroy() end
    
    plot:SetAttribute("State", "Empty")
    plot:SetAttribute("CropType", "")
    plot:SetAttribute("PlantedAt", 0)
    plot:SetAttribute("Watered", false)
    plot:SetAttribute("GrowthStage", 0)
    plot.Color = Color3.fromRGB(100, 70, 40)
    
    return cropType, amount
end
```

## 성장 루프 (서버)

```lua
local function updateCrops()
    for _, plot in CollectionService:GetTagged("FarmPlot") do
        local state = plot:GetAttribute("State")
        if state ~= "Planted" and state ~= "Growing" then continue end
        
        local cropType = plot:GetAttribute("CropType")
        local data = CropData[cropType]
        if not data then continue end
        
        local plantedAt = plot:GetAttribute("PlantedAt")
        local watered = plot:GetAttribute("Watered")
        local elapsed = os.time() - plantedAt
        
        -- 물을 줬으면 성장 2배 속도
        local growSpeed = watered and 2 or 1
        local effectiveTime = elapsed * growSpeed
        local stage = math.min(data.stages, math.floor(effectiveTime / (data.growTime / data.stages)) + 1)
        
        plot:SetAttribute("GrowthStage", stage)
        
        -- 시각적 성장
        local visual = plot:FindFirstChild("CropVisual")
        if visual then
            local scale = stage / data.stages
            visual.Size = Vector3.new(0.3 + scale * 0.7, 0.3 + scale * 1.5, 0.3 + scale * 0.7)
            visual.Position = plot.Position + Vector3.new(0, visual.Size.Y / 2 + 0.25, 0)
        end
        
        if stage >= data.stages then
            plot:SetAttribute("State", "Ready")
            if visual then visual.Color = Color3.fromRGB(200, 180, 30) end
        else
            plot:SetAttribute("State", "Growing")
        end
    end
end

-- 5초마다 업데이트
task.spawn(function()
    while true do
        task.wait(5)
        updateCrops()
    end
end)
```

---

## Learned Lessons

<!-- skill-evolve 에이전트가 자동으로 교훈 추가 -->

## Self-Evolution Protocol

이 스킬에서 에러가 발생하면:
1. 에러의 근본 원인을 분석한다
2. Learned Lessons 섹션에 교훈을 추가한다
3. 규칙화하여 반복 방지
4. SessionManager에 기록

```lua
local SM = require(game.ServerStorage._RobloxEngine.SessionManager)
SM.logAction("SKILL_ERROR", "[farming] | [에러]")
SM.logAction("SKILL_LEARNED", "[farming] | [교훈]")
```

**매 작업 시 Learned Lessons를 먼저 읽고 위반하지 않는지 확인.**

$ARGUMENTS
