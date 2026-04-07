---
name: testing
description: >
  Roblox 테스트/QA 전문가. MCP를 통한 자동 테스트, 배치 검증, 성능 프로파일링,
  스크립트 에러 체크, 플레이테스트, 품질 보증.
  테스트, 버그, 확인, 품질, 성능, 디버그, 검증, QA 요청 시 자동 발동.
allowed-tools: Agent Read Grep Glob Bash
effort: high
---

# Testing Agent — Roblox QA 전문가

모든 구현물의 품질을 보장한다. MCP 도구(`start_stop_play`, `run_script_in_play_mode`, `get_console_output`, `screen_capture`)를 적극 활용.

---

## 자동 품질 검사

```lua
local function fullQAReport()
    local report = {"╔══ QA REPORT ══╗"}
    local warnings = 0
    local errors = 0
    
    -- 1. Anchored 체크 (의도치 않게 떠있는 파트)
    local unanchored = {}
    for _, p in workspace:GetDescendants() do
        if p:IsA("BasePart") and not p.Anchored 
            and not p:FindFirstAncestorOfClass("Model") then
            table.insert(unanchored, p:GetFullName())
        end
    end
    if #unanchored > 0 then
        warnings += #unanchored
        table.insert(report, "⚠️ Unanchored parts: " .. #unanchored)
        for i = 1, math.min(5, #unanchored) do
            table.insert(report, "   " .. unanchored[i])
        end
    end
    
    -- 2. 이름 없는 파트
    local unnamed = 0
    for _, p in workspace:GetDescendants() do
        if p:IsA("BasePart") and p.Name == "Part" then unnamed += 1 end
    end
    if unnamed > 0 then
        warnings += 1
        table.insert(report, "⚠️ Unnamed parts (\"Part\"): " .. unnamed)
    end
    
    -- 3. 라이트 수
    local lights = 0; local shadowLights = 0
    for _, l in workspace:GetDescendants() do
        if l:IsA("Light") then
            lights += 1
            if l.Shadows then shadowLights += 1 end
        end
    end
    table.insert(report, "💡 Lights: " .. lights .. " (shadows: " .. shadowLights .. ")")
    if lights > 20 then warnings += 1; table.insert(report, "⚠️ Too many lights") end
    if shadowLights > 5 then warnings += 1; table.insert(report, "⚠️ Too many shadow lights") end
    
    -- 4. 파티클 수
    local particles = 0; local totalRate = 0
    for _, e in workspace:GetDescendants() do
        if e:IsA("ParticleEmitter") then
            particles += 1
            totalRate += e.Rate
        end
    end
    table.insert(report, "✨ Particles: " .. particles .. " (total rate: " .. totalRate .. "/s)")
    if totalRate > 2000 then warnings += 1; table.insert(report, "⚠️ High particle rate") end
    
    -- 5. 바닥 아래 파트
    local underground = 0
    for _, p in workspace:GetDescendants() do
        if p:IsA("BasePart") and p.Position.Y < -500 then underground += 1 end
    end
    if underground > 0 then
        errors += 1
        table.insert(report, "❌ Parts below Y=-500: " .. underground)
    end
    
    -- 6. 겹친 파트 (같은 위치)
    local parts = {}
    for _, p in workspace:GetDescendants() do
        if p:IsA("BasePart") and p.Anchored then
            local key = string.format("%.0f,%.0f,%.0f", p.Position.X, p.Position.Y, p.Position.Z)
            parts[key] = (parts[key] or 0) + 1
        end
    end
    local overlaps = 0
    for _, count in parts do if count > 1 then overlaps += count - 1 end end
    if overlaps > 0 then
        warnings += 1
        table.insert(report, "⚠️ Overlapping parts: " .. overlaps)
    end
    
    -- 7. Script 에러 확인
    local logService = game:GetService("LogService")
    local logs = logService:GetLogHistory()
    local scriptErrors = 0
    for _, log in logs do
        if log.messageType == Enum.MessageType.MessageError then
            scriptErrors += 1
        end
    end
    if scriptErrors > 0 then
        errors += scriptErrors
        table.insert(report, "❌ Script errors: " .. scriptErrors)
    end
    
    -- 8. 총계
    table.insert(report, "")
    table.insert(report, "━━━━━━━━━━━━━━━━━━")
    table.insert(report, "Total counts:")
    
    local totalParts = 0; local totalModels = 0; local totalScripts = 0
    for _, inst in workspace:GetDescendants() do
        if inst:IsA("BasePart") then totalParts += 1
        elseif inst:IsA("Model") then totalModels += 1
        elseif inst:IsA("BaseScript") then totalScripts += 1 end
    end
    table.insert(report, "  Parts: " .. totalParts)
    table.insert(report, "  Models: " .. totalModels)
    table.insert(report, "  Scripts: " .. totalScripts)
    table.insert(report, "")
    table.insert(report, "Result: " .. errors .. " errors, " .. warnings .. " warnings")
    table.insert(report, "╚══════════════════╝")
    
    print(table.concat(report, "\n"))
    return errors, warnings
end
```

---

## 배치 정확도 테스트

```lua
local function testBuildAlignment()
    local issues = {}
    
    -- 방 구조 검증: Floor/Ceiling/Wall 이름 패턴
    for _, model in workspace:GetDescendants() do
        if model:IsA("Model") then
            local floor = model:FindFirstChild("Floor")
            local ceiling = model:FindFirstChild("Ceiling")
            if floor and ceiling then
                -- 바닥과 천장이 같은 X,Z에 있는지
                local xDiff = math.abs(floor.Position.X - ceiling.Position.X)
                local zDiff = math.abs(floor.Position.Z - ceiling.Position.Z)
                if xDiff > 0.1 or zDiff > 0.1 then
                    table.insert(issues, model.Name .. ": floor/ceiling misaligned")
                end
                -- 같은 크기인지
                if math.abs(floor.Size.X - ceiling.Size.X) > 0.1 then
                    table.insert(issues, model.Name .. ": floor/ceiling size mismatch")
                end
            end
        end
    end
    
    if #issues > 0 then
        print("BUILD ALIGNMENT ISSUES:")
        for _, issue in issues do print("  " .. issue) end
    else
        print("BUILD ALIGNMENT: ALL OK")
    end
    return issues
end
```

---

## 성능 프로파일

```lua
local function perfProfile()
    local stats = game:GetService("Stats")
    print(string.format([[
=== PERFORMANCE ===
Heartbeat: %.1f ms
Instances: %d
Primitives: %d
Moving: %d
Memory: %.0f MB
]],
        stats.HeartbeatTimeMs,
        stats.InstanceCount,
        stats.PrimitivesCount,
        stats.MovingPrimitivesCount,
        stats:GetTotalMemoryUsageMb()
    ))
end
```

---

## MCP 플레이테스트 절차

1. `start_stop_play` — Play 모드 시작
2. `run_script_in_play_mode` — 테스트 스크립트 실행
3. `get_console_output` — 에러 확인
4. `screen_capture` — 시각적 확인
5. `start_stop_play` — Play 모드 종료

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
