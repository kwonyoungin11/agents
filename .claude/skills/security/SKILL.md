---
name: security
description: >
  Roblox 보안 전문가. 서버 사이드 검증, 안티 익스플로잇, RemoteEvent 보안,
  속도해킹 감지, 데미지 검증, Rate Limiting, 데이터 무결성.
  보안, 치트, 해킹, 검증, 익스플로잇, 안티치트 요청 시 자동 발동.
allowed-tools: Agent Read Grep Glob Bash
effort: high
---

# Security Agent — Roblox 보안 전문가

**클라이언트를 절대 신뢰하지 마라.** 모든 중요 검증은 서버에서.

---

## 핵심 원칙

| 항목 | 서버에서 해야 | 클라이언트에서 해도 됨 |
|---|---|---|
| 데미지 계산 | ✅ | ❌ |
| 아이템 지급 | ✅ | ❌ |
| 골드 증감 | ✅ | ❌ |
| 거리 검증 | ✅ | ❌ |
| 쿨다운 검증 | ✅ | 보조적 |
| 입력 감지 | ❌ | ✅ |
| UI 표시 | ❌ | ✅ |
| 사운드 재생 | ❌ | ✅ |

---

## RemoteEvent 검증 프레임워크

```lua
local Validate = {}

function Validate.type(value, expected)
    return typeof(value) == expected
end

function Validate.range(value, min, max)
    return type(value) == "number" and value >= min and value <= max
end

function Validate.string(value, maxLen)
    return type(value) == "string" and #value <= (maxLen or 100)
end

function Validate.alive(player)
    local char = player.Character
    if not char then return false end
    local hum = char:FindFirstChildOfClass("Humanoid")
    return hum and hum.Health > 0
end

function Validate.distance(player, targetPos, maxDist)
    local char = player.Character
    if not char then return false end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return false end
    return (root.Position - targetPos).Magnitude <= maxDist
end

function Validate.cooldown(player, action, cooldownTime)
    local key = player.UserId .. "_" .. action
    Validate._cooldowns = Validate._cooldowns or {}
    local now = tick()
    if Validate._cooldowns[key] and now - Validate._cooldowns[key] < cooldownTime then
        return false
    end
    Validate._cooldowns[key] = now
    return true
end

function Validate.rateLimit(player, action, maxPerSecond)
    local key = player.UserId .. "_" .. action
    Validate._rates = Validate._rates or {}
    local entry = Validate._rates[key]
    if not entry or tick() > entry.reset then
        Validate._rates[key] = {count = 0, reset = tick() + 1}
        entry = Validate._rates[key]
    end
    entry.count += 1
    return entry.count <= maxPerSecond
end

-- 사용 예시
AttackEvent.OnServerEvent:Connect(function(player, data)
    if not Validate.type(data, "table") then return end
    if not Validate.alive(player) then return end
    if not Validate.cooldown(player, "attack", 0.5) then return end
    if not Validate.rateLimit(player, "attack", 5) then return end
    
    local target = workspace:FindFirstChild(data.targetName)
    if not target then return end
    if not Validate.distance(player, target:GetPivot().Position, 15) then return end
    
    -- 서버에서 데미지 계산 (클라이언트 값 무시)
    local damage = serverCalculateDamage(player)
    dealDamage(target, damage)
end)
```

---

## 속도 해킹 감지

```lua
local function monitorSpeed(player)
    local lastPos, lastTime = nil, nil
    local violations = 0
    
    task.spawn(function()
        while player.Parent do
            task.wait(0.5)
            local char = player.Character
            if not char then continue end
            local root = char:FindFirstChild("HumanoidRootPart")
            if not root then continue end
            
            local pos = root.Position
            local now = tick()
            
            if lastPos and lastTime then
                local dist = (pos - lastPos).Magnitude
                local dt = now - lastTime
                local speed = dist / dt
                
                local hum = char:FindFirstChildOfClass("Humanoid")
                local maxAllowed = (hum and hum.WalkSpeed or 16) * 1.5 + 30
                
                if speed > maxAllowed then
                    violations += 1
                    if violations >= 5 then
                        root.CFrame = CFrame.new(lastPos + Vector3.new(0, 3, 0))
                        warn("[Security] Speed hack: " .. player.Name .. " speed=" .. math.floor(speed))
                        violations = 0
                    end
                else
                    violations = math.max(0, violations - 1)
                end
            end
            
            lastPos = pos; lastTime = now
        end
    end)
end

Players.PlayerAdded:Connect(monitorSpeed)
```

---

## 텔레포트 해킹 감지

```lua
local function monitorTeleport(player)
    local lastPos = nil
    
    task.spawn(function()
        while player.Parent do
            task.wait(1)
            local char = player.Character
            if not char then lastPos = nil; continue end
            local root = char:FindFirstChild("HumanoidRootPart")
            if not root then lastPos = nil; continue end
            
            local pos = root.Position
            if lastPos then
                local dist = (pos - lastPos).Magnitude
                -- 1초에 100스터드 이상 이동 = 텔레포트 해킹 의심
                if dist > 100 then
                    warn("[Security] Teleport suspect: " .. player.Name .. " dist=" .. math.floor(dist))
                    root.CFrame = CFrame.new(lastPos + Vector3.new(0, 3, 0))
                end
            end
            lastPos = pos
        end
    end)
end
```

---

## 서버 사이드 데미지 검증

```lua
-- 무기 데이터는 서버에서만 관리
local ServerWeapons = {
    IronSword = {damage = 25, range = 8, cooldown = 0.5},
    FireStaff = {damage = 40, range = 20, cooldown = 1.5},
}

local function serverDealDamage(attacker, target, weaponId)
    local weapon = ServerWeapons[weaponId]
    if not weapon then return end
    
    -- 거리 확인
    local attackerRoot = attacker:FindFirstChild("HumanoidRootPart")
    if not attackerRoot then return end
    local targetRoot = target:FindFirstChild("HumanoidRootPart")
        or target:IsA("BasePart") and target
    if not targetRoot then return end
    
    if (attackerRoot.Position - targetRoot.Position).Magnitude > weapon.range * 1.2 then
        return  -- 사정거리 초과 (20% 여유)
    end
    
    local damage = weapon.damage  -- 서버 데이터에서 직접
    -- 스탯 적용
    local data = getPlayerData(attacker)
    if data then damage += data.stats.strength end
    
    local hum = target:FindFirstChildOfClass("Humanoid")
    if hum then hum:TakeDamage(damage) end
end
```

---

## 보안 체크리스트

```
- [ ] 모든 RemoteEvent에 서버 검증 존재?
- [ ] 클라이언트에서 온 damage/gold 값을 그대로 사용하는 곳 없음?
- [ ] 데미지/경제 계산이 서버에서만?
- [ ] 속도 감지 활성화?
- [ ] Rate Limiting 적용?
- [ ] DataStore 키에 사용자 입력이 들어가지 않음?
- [ ] RemoteFunction 반환값을 클라이언트가 조작 못하게 되어있음?
```

---



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
