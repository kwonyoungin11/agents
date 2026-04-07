---
name: fishing
description: >
  Roblox 낚시 시스템 전문가. 낚싯대 Tool, 캐스팅, 물고기 입질 대기, 릴링 미니게임,
  물고기 희귀도 테이블, 낚시 포인트, 도감 시스템.
  낚시, 물고기, 낚싯대, 릴링, 캐스팅 요청 시 자동 발동.
allowed-tools: Agent Read Grep Glob Bash
effort: high
---

# Fishing Agent — Roblox 낚시 시스템 전문가

---

## 물고기 데이터

```lua
local FishData = {
    Sardine   = {rarity = "Common",    weight = {0.1, 0.5}, sellPrice = 5,   biteTime = {2, 5}},
    Bass      = {rarity = "Common",    weight = {0.5, 2.0}, sellPrice = 15,  biteTime = {3, 7}},
    Trout     = {rarity = "Uncommon",  weight = {1.0, 3.0}, sellPrice = 30,  biteTime = {5, 10}},
    Salmon    = {rarity = "Uncommon",  weight = {2.0, 5.0}, sellPrice = 50,  biteTime = {5, 12}},
    Swordfish = {rarity = "Rare",      weight = {5.0, 15},  sellPrice = 150, biteTime = {8, 20}},
    GoldFish  = {rarity = "Epic",      weight = {0.2, 0.5}, sellPrice = 500, biteTime = {15, 30}},
    Kraken    = {rarity = "Legendary", weight = {50, 100},  sellPrice = 5000,biteTime = {20, 45}},
}

local RarityWeights = {
    Common = 50, Uncommon = 25, Rare = 12, Epic = 5, Legendary = 1,
}
```

## 낚시 로직 (서버)

```lua
local FishingService = {}

function FishingService.rollFish(luckBonus)
    luckBonus = luckBonus or 0
    local total = 0
    for _, w in RarityWeights do total += w end
    
    local roll = math.random() * total - luckBonus
    local cumulative = 0
    local selectedRarity = "Common"
    
    for rarity, weight in RarityWeights do
        cumulative += weight
        if roll <= cumulative then
            selectedRarity = rarity
            break
        end
    end
    
    -- 해당 희귀도의 물고기 중 랜덤 선택
    local candidates = {}
    for name, data in FishData do
        if data.rarity == selectedRarity then
            table.insert(candidates, name)
        end
    end
    
    if #candidates == 0 then return "Sardine" end
    return candidates[math.random(#candidates)]
end

function FishingService.startFishing(player)
    local char = player.Character
    if not char then return end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return end
    
    -- 물 근처인지 확인 (전방 레이캐스트)
    local lookDir = root.CFrame.LookVector
    local ray = workspace:Raycast(root.Position, lookDir * 30)
    -- Terrain Water 감지는 별도 로직 필요
    
    -- 상태 설정
    char:SetAttribute("Fishing", true)
    char:SetAttribute("FishingState", "Casting") -- Casting/Waiting/Bite/Reeling
    
    -- 입질 대기 시간
    local waitTime = math.random(3, 15)
    task.delay(waitTime, function()
        if not char:GetAttribute("Fishing") then return end
        char:SetAttribute("FishingState", "Bite")
        -- 클라이언트에 입질 알림
        Remotes.FishBite:FireClient(player)
        
        -- 반응 시간 (2초 안에 릴링 안 하면 놓침)
        task.delay(2, function()
            if char:GetAttribute("FishingState") == "Bite" then
                char:SetAttribute("Fishing", false)
                Remotes.FishMissed:FireClient(player)
            end
        end)
    end)
end

function FishingService.reel(player)
    local char = player.Character
    if not char or char:GetAttribute("FishingState") ~= "Bite" then return nil end
    
    char:SetAttribute("FishingState", "Reeling")
    
    local fishName = FishingService.rollFish()
    local data = FishData[fishName]
    local weight = data.weight[1] + math.random() * (data.weight[2] - data.weight[1])
    weight = math.floor(weight * 100) / 100
    
    char:SetAttribute("Fishing", false)
    
    return {
        name = fishName,
        rarity = data.rarity,
        weight = weight,
        sellPrice = data.sellPrice,
    }
end
```

## 낚싯대 Tool

```lua
local function createFishingRod()
    local tool = Instance.new("Tool")
    tool.Name = "FishingRod"
    tool.RequiresHandle = true
    tool.CanBeDropped = false
    
    local handle = Instance.new("Part")
    handle.Name = "Handle"
    handle.Size = Vector3.new(0.3, 0.3, 6)
    handle.Material = Enum.Material.Wood
    handle.Color = Color3.fromRGB(120, 80, 30)
    handle.Parent = tool
    
    tool.Grip = CFrame.new(0, 0, -2) * CFrame.Angles(math.rad(-30), 0, 0)
    
    return tool
end
```

## 클라이언트 UI (입질 알림)

```lua
-- LocalScript
Remotes.FishBite.OnClientEvent:Connect(function()
    -- "!" 표시 + 화면 흔들림
    local alert = Instance.new("TextLabel")
    alert.Text = "!"
    alert.TextColor3 = Color3.fromRGB(255, 50, 50)
    alert.TextScaled = true
    alert.Size = UDim2.new(0.1, 0, 0.15, 0)
    alert.Position = UDim2.new(0.45, 0, 0.35, 0)
    alert.BackgroundTransparency = 1
    alert.Font = Enum.Font.GothamBold
    alert.Parent = player.PlayerGui:FindFirstChild("FishingUI")
    
    -- 사운드 + 카메라 쉐이크
    game:GetService("Debris"):AddItem(alert, 2)
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

**매 작업 시 Learned Lessons를 먼저 읽고 위반하지 않는지 확인.**

$ARGUMENTS
