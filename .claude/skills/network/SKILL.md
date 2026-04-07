---
name: network
description: >
  Roblox 네트워크/최적화 전문가. RemoteEvent/Function 설계, 대역폭 최적화,
  StreamingEnabled, Attribute 리플리케이션, Rate Limiting, 지연 보상.
  서버, 클라이언트, 동기화, 지연, 최적화, 네트워크, 렉, 대역폭 요청 시 자동 발동.
allowed-tools: Agent Read Grep Glob Bash
effort: high
---

# Network Agent — Roblox 네트워크 전문가

서버-클라이언트 통신을 최적화하고, 대역폭을 관리한다.

---

## Remote 설계 패턴

### 이벤트 생성 (서버 부팅 시)
```lua
local RS = game:GetService("ReplicatedStorage")
local remotes = Instance.new("Folder"); remotes.Name = "Remotes"; remotes.Parent = RS

local function remote(name, isFunc)
    local r = Instance.new(isFunc and "RemoteFunction" or "RemoteEvent")
    r.Name = name; r.Parent = remotes; return r
end

-- 게임별 Remote 목록
local Events = {
    Attack       = remote("Attack"),
    Interact     = remote("Interact"),
    UseItem      = remote("UseItem"),
    ShowDamage   = remote("ShowDamage"),
    Notification = remote("Notification"),
    PlaySound    = remote("PlaySound"),
    SyncState    = remote("SyncState"),
}

local Functions = {
    GetShopItems  = remote("GetShopItems", true),
    BuyItem       = remote("BuyItem", true),
    GetPlayerData = remote("GetPlayerData", true),
}
```

### 전송 최적화

```lua
-- ❌ BAD: 불필요한 데이터 전송
Events.ShowDamage:FireAllClients({
    target = targetInstance,    -- Instance를 직접 보내면 큼
    damage = 25,
    attacker = attackerInstance,
    weapon = weaponData,       -- 테이블 전체
    timestamp = os.time(),
})

-- ✅ GOOD: 최소 데이터만
Events.ShowDamage:FireAllClients(targetPartName, 25, isCritical)

-- ✅ BETTER: 근처 플레이어만
local function fireNearby(pos, radius, event, ...)
    for _, player in Players:GetPlayers() do
        local char = player.Character
        if char and char:FindFirstChild("HumanoidRootPart") then
            if (char.HumanoidRootPart.Position - pos).Magnitude <= radius then
                event:FireClient(player, ...)
            end
        end
    end
end
fireNearby(targetPos, 100, Events.ShowDamage, targetName, 25, true)
```

### 쓰로틀링 (Rate Limiting)
```lua
local throttle = {}

local function canSend(player, channel, interval)
    local key = player.UserId .. "_" .. channel
    local now = tick()
    if throttle[key] and now - throttle[key] < interval then
        return false
    end
    throttle[key] = now
    return true
end

-- 사용
Events.Attack.OnServerEvent:Connect(function(player, data)
    if not canSend(player, "attack", 0.3) then return end  -- 0.3초 쿨다운
    -- 처리...
end)
```

---

## Attribute 리플리케이션 (RemoteEvent 없이 동기화)

```lua
-- 서버에서 설정하면 자동으로 클라이언트에 복제됨
npc:SetAttribute("Health", 100)
npc:SetAttribute("State", "Patrol")
npc:SetAttribute("Level", 5)

-- 클라이언트에서 감지
npc:GetAttributeChangedSignal("Health"):Connect(function()
    local hp = npc:GetAttribute("Health")
    updateEnemyHealthBar(npc, hp)
end)

-- ★ Attribute의 장점:
-- 1. RemoteEvent 없이 자동 동기화
-- 2. 인스턴스에 직접 붙어서 관리 편함
-- 3. StreamingEnabled에서도 안정적
```

---

## StreamingEnabled (인스턴스 스트리밍)

```lua
-- 큰 맵에서 필수 — 가까운 것만 클라이언트에 로드
workspace.StreamingEnabled = true
workspace.StreamingMinRadius = 64      -- 최소 로드 반경 (studs)
workspace.StreamingTargetRadius = 256  -- 목표 로드 반경
workspace.StreamingPauseMode = Enum.StreamingPauseMode.Default

-- ★ 중요 오브젝트는 영구 스트리밍
model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
-- Persistent: 항상 로드
-- Default: 거리 기반
-- Atomic: 모델 전체가 같이 로드/언로드
```

### StreamingEnabled 주의사항
```lua
-- 클라이언트에서 멀리 있는 파트에 접근하면 nil일 수 있다!
-- ❌ BAD:
local part = workspace.FarAwayPart  -- nil 가능!

-- ✅ GOOD:
local part = workspace:WaitForChild("FarAwayPart", 10)  -- 10초까지 대기
if not part then
    warn("Part not streamed in")
end
```

---

## 지연 보상 (클라이언트 예측)

```lua
-- 클라이언트: 즉시 시각 피드백 (낙관적 업데이트)
local function clientAttack(target)
    -- 즉시 시각 효과 표시 (서버 응답 안 기다림)
    showAttackVFX(target)
    showDamageNumber(target, estimatedDamage)
    
    -- 서버에 요청
    Events.Attack:FireServer({targetName = target.Name})
end

-- 서버: 검증 + 실제 처리
Events.Attack.OnServerEvent:Connect(function(player, data)
    -- 검증...
    local actualDamage = calculateDamage(player)
    dealDamage(target, actualDamage)
    
    -- 모든 클라이언트에 실제 결과 동기화
    Events.ShowDamage:FireAllClients(target.Name, actualDamage)
end)

-- 클라이언트: 서버 결과로 보정
Events.ShowDamage.OnClientEvent:Connect(function(targetName, damage)
    -- 이전 예측과 다르면 보정
    updateDamageDisplay(targetName, damage)
end)
```

---

## 상태 동기화 패턴

```lua
-- 서버: 게임 상태를 주기적으로 동기화
local function syncGameState()
    local state = {
        roundTime = currentRoundTime,
        score = {red = redScore, blue = blueScore},
        phase = gamePhase,
    }
    Events.SyncState:FireAllClients(state)
end

-- 1초마다 동기화
task.spawn(function()
    while true do
        task.wait(1)
        syncGameState()
    end
end)
```

---

## 성능 모니터링

```lua
local function getNetworkStats()
    local stats = game:GetService("Stats")
    return {
        dataReceive = stats.DataReceiveKbps,
        dataSend = stats.DataSendKbps,
        physicsReceive = stats.PhysicsReceiveKbps,
        physicsSend = stats.PhysicsSendKbps,
    }
end
```

---

## 작업 완료 후 필수

1. 모든 Remote에 서버 검증 존재 확인
2. 불필요한 FireAllClients를 fireNearby로 교체 가능한지 확인
3. StreamingEnabled 환경에서 WaitForChild 사용 확인
4. SessionManager에 네트워크 시스템 로그



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
