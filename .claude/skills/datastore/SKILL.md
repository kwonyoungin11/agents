---
name: datastore
description: >
  Roblox 데이터 저장/경제 전문가. DataStoreService, 플레이어 데이터 CRUD, 자동저장,
  OrderedDataStore 랭킹, 경제 시스템, GamePass/DevProduct, 데이터 마이그레이션.
  저장, 로드, 데이터, 골드, 경제, 상점, 게임패스, 랭킹, 리더보드 요청 시 자동 발동.
allowed-tools: Agent Read Grep Glob Bash
effort: high
---

# DataStore Agent — Roblox 데이터 저장 전문가

플레이어 데이터의 저장/로드/관리, 경제 시스템, 결제를 구현한다. **모든 DataStore 작업은 서버에서만.**

---

## 핵심 원칙

1. **pcall 필수** — 모든 DataStore 호출은 pcall로 감싸기
2. **캐시 사용** — 매번 GetAsync 대신 메모리 캐시 유지
3. **자동 저장** — 주기적 + PlayerRemoving + BindToClose
4. **키 규칙** — "Player_" .. UserId (50자 제한)
5. **Rate Limit** — 같은 키에 6초 간격, 초당 60+10*플레이어수

---

## 완전한 데이터 시스템

```lua
-- ServerScript
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local STORE_NAME = "PlayerData_v1"
local store = DataStoreService:GetDataStore(STORE_NAME)

-- 기본 데이터 (새 플레이어 템플릿)
local DEFAULT = {
    level = 1,
    exp = 0,
    gold = 100,
    gems = 0,
    inventory = {},
    equipment = {weapon = nil, armor = nil, accessory = nil},
    stats = {strength = 10, defense = 10, speed = 10, luck = 5},
    quests = {},
    achievements = {},
    settings = {musicVol = 0.5, sfxVol = 1.0, sensitivity = 0.5},
    dailyReward = {lastClaim = 0, streak = 0},
    playTime = 0,
    firstJoin = 0,
    lastJoin = 0,
}

-- 깊은 복사
local function deepCopy(t)
    if type(t) ~= "table" then return t end
    local c = {}
    for k, v in t do c[k] = deepCopy(v) end
    return c
end

-- 깊은 병합 (기존 데이터에 새 필드 추가)
local function deepMerge(base, override)
    local result = deepCopy(base)
    for k, v in override do
        if type(v) == "table" and type(result[k]) == "table" then
            result[k] = deepMerge(result[k], v)
        else
            result[k] = deepCopy(v)
        end
    end
    return result
end

-- 캐시
local cache = {}
local saveLock = {}  -- 동시 저장 방지

-- 로드
local function loadData(player)
    local key = "Player_" .. player.UserId
    local data = nil
    
    local ok, err = pcall(function()
        data = store:GetAsync(key)
    end)
    
    if ok and data then
        -- 기존 데이터 + 새 필드 병합
        cache[player.UserId] = deepMerge(DEFAULT, data)
    else
        if not ok then
            warn("[Data] Load failed for " .. player.Name .. ": " .. tostring(err))
        end
        cache[player.UserId] = deepCopy(DEFAULT)
        cache[player.UserId].firstJoin = os.time()
    end
    
    cache[player.UserId].lastJoin = os.time()
    return cache[player.UserId]
end

-- 저장
local function saveData(player)
    local data = cache[player.UserId]
    if not data then return false end
    if saveLock[player.UserId] then return false end
    
    saveLock[player.UserId] = true
    local key = "Player_" .. player.UserId
    
    local ok, err = pcall(function()
        store:SetAsync(key, data)
    end)
    
    saveLock[player.UserId] = nil
    
    if not ok then
        warn("[Data] Save failed for " .. player.Name .. ": " .. tostring(err))
        -- 재시도 (1회)
        task.wait(6)
        pcall(function() store:SetAsync(key, data) end)
        return false
    end
    return true
end

-- 데이터 접근
local function getData(player)
    return cache[player.UserId]
end

-- 이벤트 연결
Players.PlayerAdded:Connect(function(player)
    local data = loadData(player)
    -- 리더보드 설정
    local stats = Instance.new("Folder"); stats.Name = "leaderstats"; stats.Parent = player
    local lvl = Instance.new("IntValue"); lvl.Name = "Level"; lvl.Value = data.level; lvl.Parent = stats
    local gold = Instance.new("IntValue"); gold.Name = "Gold"; gold.Value = data.gold; gold.Parent = stats
end)

Players.PlayerRemoving:Connect(function(player)
    saveData(player)
    cache[player.UserId] = nil
end)

-- 서버 종료 시 전부 저장
game:BindToClose(function()
    if RunService:IsStudio() then task.wait(2); return end
    local threads = {}
    for _, player in Players:GetPlayers() do
        table.insert(threads, task.spawn(function()
            saveData(player)
        end))
    end
    task.wait(5)  -- 최대 5초 대기
end)

-- 자동 저장 (5분마다)
task.spawn(function()
    while true do
        task.wait(300)
        for _, player in Players:GetPlayers() do
            task.spawn(function() saveData(player) end)
        end
    end
end)
```

---

## 경제 시스템

```lua
local Economy = {}

function Economy.addGold(player, amount, reason)
    local data = getData(player)
    if not data then return false end
    data.gold += amount
    -- 리더보드
    local stats = player:FindFirstChild("leaderstats")
    if stats and stats:FindFirstChild("Gold") then
        stats.Gold.Value = data.gold
    end
    print(string.format("[Economy] %s +%d gold (%s) = %d", player.Name, amount, reason or "unknown", data.gold))
    return true
end

function Economy.removeGold(player, amount, reason)
    local data = getData(player)
    if not data or data.gold < amount then return false end
    data.gold -= amount
    local stats = player:FindFirstChild("leaderstats")
    if stats and stats:FindFirstChild("Gold") then stats.Gold.Value = data.gold end
    return true
end

function Economy.getGold(player)
    local data = getData(player)
    return data and data.gold or 0
end

function Economy.canAfford(player, amount)
    return Economy.getGold(player) >= amount
end
```

---

## GamePass / Developer Product

```lua
local MPS = game:GetService("MarketplaceService")

-- GamePass 확인
local function hasGamePass(player, passId)
    local ok, owns = pcall(function()
        return MPS:UserOwnsGamePassAsync(player.UserId, passId)
    end)
    return ok and owns
end

-- Developer Product 구매 처리 (서버)
MPS.ProcessReceipt = function(info)
    local player = Players:GetPlayerByUserId(info.PlayerId)
    if not player then return Enum.ProductPurchaseDecision.NotProcessedYet end
    
    local data = getData(player)
    if not data then return Enum.ProductPurchaseDecision.NotProcessedYet end
    
    -- 상품 ID별 처리
    local products = {
        [1234567] = function() Economy.addGold(player, 1000, "Purchase") end,
        [2345678] = function() data.gems += 100 end,
        [3456789] = function() data.inventory["VIP_Sword"] = 1 end,
    }
    
    local handler = products[info.ProductId]
    if handler then
        handler()
        saveData(player)
        return Enum.ProductPurchaseDecision.PurchaseGranted
    end
    
    return Enum.ProductPurchaseDecision.NotProcessedYet
end

-- 구매 프롬프트 (클라이언트에서 호출)
-- MPS:PromptProductPurchase(player, productId)
-- MPS:PromptGamePassPurchase(player, gamePassId)
```

---

## OrderedDataStore (글로벌 랭킹)

```lua
local function updateRanking(statName)
    local ordered = DataStoreService:GetOrderedDataStore("Ranking_" .. statName)
    
    for _, player in Players:GetPlayers() do
        local data = getData(player)
        if data then
            pcall(function()
                ordered:SetAsync(tostring(player.UserId), data[statName] or 0)
            end)
        end
    end
end

local function getTopPlayers(statName, count)
    local ordered = DataStoreService:GetOrderedDataStore("Ranking_" .. statName)
    local ok, pages = pcall(function()
        return ordered:GetSortedAsync(false, count or 10)
    end)
    if not ok then return {} end
    
    local rankings = {}
    for rank, entry in pages:GetCurrentPage() do
        table.insert(rankings, {
            rank = rank,
            userId = tonumber(entry.key),
            value = entry.value,
        })
    end
    return rankings
end
```

---

## DataStore 제한 사항 (반드시 준수)

| 제한 | 값 |
|---|---|
| GetAsync 빈도 | 60 + 10*플레이어수 /분 |
| SetAsync 빈도 | 60 + 10*플레이어수 /분 |
| 같은 키 간격 | 최소 6초 |
| 값 크기 | 최대 4MB |
| 키 길이 | 최대 50자 |
| 반드시 pcall | 네트워크 실패 가능 |

---

## 작업 완료 후 필수

1. 새 데이터 필드 추가 시 DEFAULT 테이블에도 추가
2. DataStore 키 이름 일관성 확인
3. BindToClose 존재 확인
4. SessionManager에 데이터 시스템 로그



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
