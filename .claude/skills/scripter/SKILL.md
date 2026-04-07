---
name: scripter
description: >
  Roblox 게임 스크립트 전문가. 서버/클라이언트 아키텍처, 게임 루프, 이벤트 시스템,
  모듈 설계, 서비스 활용을 완벽히 구현. NPC, AI, 전투, 인벤토리, 스크립트, 로직,
  시스템, 코드, 함수, 이벤트 요청 시 자동 발동.
allowed-tools: Agent Read Grep Glob Bash
effort: high
---

# Scripter Agent — Roblox 게임 스크립트 전문가

모든 게임 로직을 **보안적으로 안전하고, 구조적으로 깔끔한** Luau 코드로 구현한다.

---

## 절대 원칙

1. **서버/클라이언트 분리** — 데미지, 경제, 아이템 등 중요 로직은 반드시 Server(Script)에서
2. **RemoteEvent 입력 검증** — 클라이언트 데이터를 절대 신뢰하지 않음
3. **ModuleScript 활용** — 재사용 로직은 모듈화
4. **pcall 필수** — 외부 서비스(DataStore, HTTP) 호출 시 반드시 pcall
5. **메모리 누수 방지** — 연결(Connection)은 필요 없을 때 :Disconnect()

---

## Roblox 스크립트 아키텍처

```
게임 구조:
├── ServerScriptService/       ← Script (서버만 실행, 클라이언트 접근 불가)
│   ├── GameManager.lua        ← 게임 상태, 라운드 관리
│   ├── CombatHandler.lua      ← 데미지, 사망 처리
│   └── DataManager.lua        ← 데이터 저장/로드
│
├── ServerStorage/             ← 서버 전용 저장소 (클라이언트 접근 불가)
│   ├── _RobloxEngine/         ← 엔진 모듈
│   └── Modules/               ← 서버 전용 ModuleScript
│
├── ReplicatedStorage/         ← 서버+클라이언트 공유
│   ├── Modules/               ← 공유 ModuleScript (데이터 정의, 유틸)
│   ├── Remotes/               ← RemoteEvent, RemoteFunction
│   └── Assets/                ← 공유 에셋
│
├── StarterPlayerScripts/      ← LocalScript (클라이언트 실행)
│   ├── InputController.lua    ← 키보드/마우스 입력
│   ├── UIController.lua       ← UI 로직
│   └── CameraController.lua   ← 카메라 제어
│
└── StarterGui/                ← UI ScreenGui
```

### 어디에 무엇을?
| 로직 | 위치 | 이유 |
|---|---|---|
| 데미지 계산 | ServerScriptService | 치트 방지 |
| 아이템 지급 | ServerScriptService | 치트 방지 |
| 골드 증감 | ServerScriptService | 치트 방지 |
| DataStore | ServerScriptService | 서버 전용 API |
| 키 입력 감지 | StarterPlayerScripts | 클라이언트 전용 API |
| UI 애니메이션 | StarterPlayerScripts/StarterGui | 클라이언트 전용 |
| 카메라 제어 | StarterPlayerScripts | 클라이언트 전용 |
| 공유 데이터 정의 | ReplicatedStorage | 양쪽 접근 필요 |
| RemoteEvent | ReplicatedStorage | 양쪽 접근 필요 |

---

## 서비스 완전 레퍼런스

```lua
-- 가장 많이 쓰는 서비스
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local UserInputService = game:GetService("UserInputService")          -- 클라이언트
local DataStoreService = game:GetService("DataStoreService")          -- 서버
local PathfindingService = game:GetService("PathfindingService")
local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")
local SoundService = game:GetService("SoundService")
local MarketplaceService = game:GetService("MarketplaceService")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")                    -- JSON 유틸
local Debris = game:GetService("Debris")                              -- 자동 삭제
```

---

## RemoteEvent/Function 패턴

### 생성 (서버)
```lua
local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
remotes.Parent = ReplicatedStorage

local function createRemote(name, isFunction)
    local r = Instance.new(isFunction and "RemoteFunction" or "RemoteEvent")
    r.Name = name; r.Parent = remotes; return r
end

local AttackEvent = createRemote("Attack")
local InteractEvent = createRemote("Interact")
local ShowDamageEvent = createRemote("ShowDamage")
local GetDataFunc = createRemote("GetData", true)
```

### 서버 수신 + 검증
```lua
AttackEvent.OnServerEvent:Connect(function(player, data)
    -- 1. 타입 검증
    if typeof(data) ~= "table" then return end
    if typeof(data.targetName) ~= "string" then return end
    
    -- 2. 생존 검증
    local char = player.Character
    if not char then return end
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 then return end
    
    -- 3. 쿨다운 검증
    local lastAttack = char:GetAttribute("_LastAttack") or 0
    if tick() - lastAttack < 0.5 then return end
    char:SetAttribute("_LastAttack", tick())
    
    -- 4. 거리 검증
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return end
    local target = workspace:FindFirstChild(data.targetName)
    if not target then return end
    local dist = (root.Position - target:GetPivot().Position).Magnitude
    if dist > 15 then return end  -- 최대 공격 거리
    
    -- 5. 서버에서 데미지 계산 (클라이언트 값 절대 사용 금지!)
    local damage = getWeaponDamage(player)  -- 서버 데이터 참조
    dealDamage(target, damage, player)
end)
```

### 클라이언트 송신
```lua
-- LocalScript
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local AttackEvent = Remotes:WaitForChild("Attack")

UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        AttackEvent:FireServer({targetName = getTargetUnderMouse()})
    end
end)
```

### 서버→클라이언트 (전체/개인/근처)
```lua
-- 전체 클라이언트
ShowDamageEvent:FireAllClients(targetName, damage)

-- 특정 플레이어만
ShowDamageEvent:FireClient(player, targetName, damage)

-- 근처 플레이어만 (대역폭 최적화)
local function fireNearby(position, radius, remote, ...)
    for _, p in Players:GetPlayers() do
        local c = p.Character
        if c and c:FindFirstChild("HumanoidRootPart") then
            if (c.HumanoidRootPart.Position - position).Magnitude <= radius then
                remote:FireClient(p, ...)
            end
        end
    end
end
```

---

## 게임 루프 패턴

### 라운드 시스템
```lua
local function gameLoop()
    while true do
        -- 대기 단계
        updateStatus("Waiting for players...")
        repeat task.wait(1) until #Players:GetPlayers() >= 2
        
        -- 카운트다운
        for i = 10, 1, -1 do
            updateStatus("Starting in " .. i .. "...")
            task.wait(1)
        end
        
        -- 게임 시작
        local roundTime = 120  -- 2분
        startRound()
        
        -- 라운드 진행
        local elapsed = 0
        repeat
            task.wait(1)
            elapsed += 1
            updateTimer(roundTime - elapsed)
        until elapsed >= roundTime or checkWinCondition()
        
        -- 라운드 종료
        local winner = getWinner()
        endRound(winner)
        
        -- 결과 표시
        task.wait(5)
        resetMap()
    end
end
task.spawn(gameLoop)
```

### 이벤트 기반 시스템
```lua
-- 플레이어 입장/퇴장
Players.PlayerAdded:Connect(function(player)
    -- 데이터 로드
    local data = loadPlayerData(player)
    setupLeaderboard(player, data)
    
    player.CharacterAdded:Connect(function(character)
        local humanoid = character:WaitForChild("Humanoid")
        
        -- 스폰 위치 설정
        character:SetPrimaryPartCFrame(getSpawnPoint())
        
        -- 사망 처리
        humanoid.Died:Connect(function()
            onPlayerDied(player, character)
            task.wait(5)
            player:LoadCharacter()
        end)
    end)
end)

Players.PlayerRemoving:Connect(function(player)
    savePlayerData(player)
end)

-- 서버 종료 시 전부 저장
game:BindToClose(function()
    for _, p in Players:GetPlayers() do
        savePlayerData(p)
    end
end)
```

---

## ModuleScript 패턴

```lua
-- ReplicatedStorage/Modules/ItemData.lua
local ItemData = {}

ItemData.Items = {
    IronSword = {
        name = "Iron Sword",
        type = "Weapon",
        damage = 25,
        speed = 1.2,
        rarity = "Common",
        price = 100,
    },
    HealthPotion = {
        name = "Health Potion",
        type = "Consumable",
        healAmount = 50,
        stackable = true,
        maxStack = 99,
        price = 30,
    },
}

function ItemData.get(itemId)
    return ItemData.Items[itemId]
end

return ItemData
```

```lua
-- 사용법 (어디서든)
local ItemData = require(ReplicatedStorage.Modules.ItemData)
local sword = ItemData.get("IronSword")
print(sword.damage)  -- 25
```

---

## Attribute 시스템 (네트워크 자동 동기화)

```lua
-- 서버에서 설정
part:SetAttribute("Health", 100)
part:SetAttribute("MaxHealth", 100)
part:SetAttribute("Team", "Red")
part:SetAttribute("IsShielded", false)

-- 어디서든 읽기
local hp = part:GetAttribute("Health")

-- 변경 감지 (클라이언트에서 UI 업데이트 등)
part:GetAttributeChangedSignal("Health"):Connect(function()
    local hp = part:GetAttribute("Health")
    updateHealthBar(hp)
end)
```

---

## CollectionService (태그 시스템)

```lua
local CS = game:GetService("CollectionService")

-- 태그 추가
CS:AddTag(part, "Damageable")
CS:AddTag(npc, "Enemy")

-- 태그로 검색
local enemies = CS:GetTagged("Enemy")
for _, enemy in enemies do
    -- 적 처리
end

-- 태그 추가/제거 감지
CS:GetInstanceAddedSignal("Enemy"):Connect(function(inst)
    setupEnemy(inst)
end)
CS:GetInstanceRemovedSignal("Enemy"):Connect(function(inst)
    cleanupEnemy(inst)
end)
```

---

## RunService 프레임 루프

```lua
-- 서버: 매 물리 프레임 (Heartbeat)
RunService.Heartbeat:Connect(function(dt)
    -- dt = 이전 프레임과의 시간 차이 (초)
    updateNPCs(dt)
    updateProjectiles(dt)
end)

-- 클라이언트: 매 렌더 프레임 (RenderStepped)
RunService.RenderStepped:Connect(function(dt)
    updateCamera(dt)
    updateUI(dt)
end)

-- 서버인지 클라이언트인지 확인
if RunService:IsServer() then
    -- 서버 코드
elseif RunService:IsClient() then
    -- 클라이언트 코드
end
```

---

## Debris (자동 삭제)

```lua
-- N초 후 자동 삭제
Debris:AddItem(part, 5)       -- 5초 후 삭제
Debris:AddItem(effect, 2)     -- 2초 후 삭제
-- Destroy()를 수동 호출할 필요 없음
```

---

## task 라이브러리

```lua
task.wait(1)           -- 1초 대기 (wait()보다 정확)
task.delay(2, func)    -- 2초 후 func 실행
task.defer(func)       -- 현재 프레임 끝에 실행
task.spawn(func)       -- 새 스레드에서 즉시 실행
task.cancel(thread)    -- 스레드 취소
```

---

## 에러 핸들링

```lua
-- 외부 서비스 호출 시 반드시
local success, result = pcall(function()
    return DataStoreService:GetDataStore("Test"):GetAsync("key")
end)

if success then
    print("Data: " .. tostring(result))
else
    warn("Error: " .. tostring(result))
end

-- xpcall: 에러 핸들러 지정
local success, result = xpcall(function()
    return riskyOperation()
end, function(err)
    warn("Caught: " .. err)
    return nil
end)
```

---

## 작업 완료 후 필수

1. 서버/클라이언트 분리 확인
2. 모든 RemoteEvent에 입력 검증 존재 확인
3. pcall 래핑 확인 (외부 서비스)
4. SessionManager에 로그
5. 스크립트 위치 (ServerScriptService/StarterPlayerScripts) 정확한지 확인



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
