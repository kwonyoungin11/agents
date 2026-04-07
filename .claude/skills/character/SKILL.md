---
name: character
description: >
  Roblox 캐릭터 전문가. R6/R15 캐릭터 구조, HumanoidDescription 커스터마이징,
  Tool 도구 시스템, 악세사리, NPC 캐릭터 생성, Humanoid 속성 전체.
  캐릭터, 외형, 장비, 무기, 도구, NPC모델, 악세사리, 의상 요청 시 자동 발동.
allowed-tools: Agent Read Grep Glob Bash
effort: high
---

# Character Agent — Roblox 캐릭터 전문가

캐릭터의 생성, 커스터마이징, 장비, 도구를 구현한다.

---

## R15 캐릭터 구조

```
Model (Character)
├── HumanoidRootPart     ← PrimaryPart (보이지 않는 루트, 이동 기준)
├── Head
├── UpperTorso
├── LowerTorso
├── LeftUpperArm → LeftLowerArm → LeftHand
├── RightUpperArm → RightLowerArm → RightHand
├── LeftUpperLeg → LeftLowerLeg → LeftFoot
├── RightUpperLeg → RightLowerLeg → RightFoot
├── Humanoid
│   ├── Animator
│   └── HumanoidDescription
├── Animate (Script)
└── Health (Script)
```

파트 간 연결: **Motor6D** 조인트로 연결됨.

---

## Humanoid 속성 전체

```lua
local humanoid = character:FindFirstChildOfClass("Humanoid")

-- 체력
humanoid.MaxHealth = 100
humanoid.Health = 100

-- 이동
humanoid.WalkSpeed = 16         -- 기본 이동 속도 (studs/s)
humanoid.JumpHeight = 7.2       -- 점프 높이 (studs)
humanoid.JumpPower = 50         -- 점프 파워 (UseJumpPower=true일 때)
humanoid.UseJumpPower = false   -- false=JumpHeight 사용, true=JumpPower 사용
humanoid.HipHeight = 2          -- 지면에서의 높이
humanoid.AutoRotate = true      -- 이동 방향 자동 회전

-- 상태
humanoid.Sit = false            -- 앉기
humanoid.Jump = true            -- 즉시 점프
humanoid.PlatformStand = false  -- 래그돌 비슷

-- 표시
humanoid.DisplayName = "Player" -- 머리 위 이름
humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
humanoid.NameDisplayDistance = 100
humanoid.HealthDisplayDistance = 100
humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOn

-- 카메라
humanoid.CameraOffset = Vector3.new(0, 0, 0)
```

### Humanoid 이벤트
```lua
humanoid.Died:Connect(function()
    -- 사망 처리
end)

humanoid.Running:Connect(function(speed)
    -- 달리기 (speed > 0이면 움직이는 중)
end)

humanoid.Jumping:Connect(function(active)
    -- 점프 시작
end)

humanoid.FreeFalling:Connect(function(active)
    -- 낙하 중
end)

humanoid.Seated:Connect(function(active, seat)
    -- 앉기/일어서기
end)

humanoid.HealthChanged:Connect(function(health)
    -- 체력 변경
end)
```

---

## HumanoidDescription (외형 커스터마이징)

```lua
local function customizeCharacter(character, options)
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local desc = humanoid:GetAppliedDescription()
    
    -- 체형
    desc.HeadScale = options.headScale or 1
    desc.BodyTypeScale = options.bodyType or 0     -- 0=blocky, 1=슬림
    desc.HeightScale = options.height or 1
    desc.WidthScale = options.width or 1
    desc.DepthScale = options.depth or 1
    desc.ProportionScale = options.proportion or 0
    
    -- 피부색 (모든 파트 동일)
    local skin = options.skinColor or Color3.fromRGB(234, 184, 146)
    desc.HeadColor = skin
    desc.TorsoColor = skin
    desc.LeftArmColor = skin
    desc.RightArmColor = skin
    desc.LeftLegColor = skin
    desc.RightLegColor = skin
    
    -- 얼굴
    if options.face then desc.Face = options.face end
    
    -- 의상 (에셋 ID)
    if options.shirt then desc.Shirt = options.shirt end
    if options.pants then desc.Pants = options.pants end
    if options.tshirt then desc.GraphicTShirt = options.tshirt end
    
    -- 악세사리
    if options.hat then desc.HatAccessory = tostring(options.hat) end
    if options.hair then desc.HairAccessory = tostring(options.hair) end
    if options.back then desc.BackAccessory = tostring(options.back) end
    if options.front then desc.FrontAccessory = tostring(options.front) end
    if options.waist then desc.WaistAccessory = tostring(options.waist) end
    
    -- 애니메이션 번들
    if options.idle then desc.IdleAnimation = options.idle end
    if options.walk then desc.WalkAnimation = options.walk end
    if options.run then desc.RunAnimation = options.run end
    if options.jump then desc.JumpAnimation = options.jump end
    if options.fall then desc.FallAnimation = options.fall end
    
    humanoid:ApplyDescription(desc)
end
```

---

## NPC 캐릭터 생성 (서버)

```lua
local function createNPC(config)
    local desc = Instance.new("HumanoidDescription")
    
    -- 피부색
    local skin = config.skinColor or Color3.fromRGB(234, 184, 146)
    desc.HeadColor = skin; desc.TorsoColor = skin
    desc.LeftArmColor = skin; desc.RightArmColor = skin
    desc.LeftLegColor = skin; desc.RightLegColor = skin
    
    -- 의상
    if config.shirt then desc.Shirt = config.shirt end
    if config.pants then desc.Pants = config.pants end
    if config.hat then desc.HatAccessory = tostring(config.hat) end
    if config.hair then desc.HairAccessory = tostring(config.hair) end
    if config.face then desc.Face = config.face end
    
    -- 체형
    desc.BodyTypeScale = config.bodyType or 0
    desc.HeightScale = config.heightScale or 1
    desc.WidthScale = config.widthScale or 1
    
    -- 모델 생성
    local npc = Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
    npc.Name = config.name or "NPC"
    
    local humanoid = npc:FindFirstChildOfClass("Humanoid")
    humanoid.DisplayName = config.displayName or config.name or "NPC"
    humanoid.MaxHealth = config.maxHealth or 100
    humanoid.Health = config.maxHealth or 100
    humanoid.WalkSpeed = config.walkSpeed or 16
    
    -- 위치
    local position = config.position or Vector3.new(0, 5, 0)
    npc:SetPrimaryPartCFrame(CFrame.new(position))
    
    -- NPC는 기본 Anchored (움직이려면 Pathfinding 사용)
    if config.anchored then
        for _, part in npc:GetDescendants() do
            if part:IsA("BasePart") then part.Anchored = true end
        end
    end
    
    npc.Parent = workspace
    
    print(string.format("NPC created: %s at %s", npc.Name, tostring(position)))
    return npc
end
```

---

## Tool (도구) 시스템

```lua
local function createTool(config)
    local tool = Instance.new("Tool")
    tool.Name = config.name or "Tool"
    tool.RequiresHandle = true
    tool.CanBeDropped = config.droppable or false
    
    -- Handle 파트
    local handle = Instance.new("Part")
    handle.Name = "Handle"
    handle.Size = config.handleSize or Vector3.new(1, 1, 4)
    handle.Material = config.material or Enum.Material.SmoothPlastic
    handle.Color = config.color or Color3.fromRGB(150, 150, 150)
    handle.CanCollide = false
    handle.Massless = true
    handle.Parent = tool
    
    -- 그립 (캐릭터 손에서의 위치/각도)
    tool.Grip = config.grip or CFrame.new(0, 0, -config.handleSize.Z/2 if config.handleSize else -2)
        * CFrame.Angles(0, 0, 0)
    
    -- 이벤트
    tool.Activated:Connect(function()
        if config.onActivate then config.onActivate(tool) end
    end)
    tool.Deactivated:Connect(function()
        if config.onDeactivate then config.onDeactivate(tool) end
    end)
    tool.Equipped:Connect(function()
        if config.onEquip then config.onEquip(tool) end
    end)
    tool.Unequipped:Connect(function()
        if config.onUnequip then config.onUnequip(tool) end
    end)
    
    return tool
end

-- 검 예시
local sword = createTool({
    name = "IronSword",
    handleSize = Vector3.new(0.3, 0.3, 5),
    material = Enum.Material.Metal,
    color = Color3.fromRGB(180, 180, 200),
    grip = CFrame.new(0, 0, -1.5) * CFrame.Angles(-math.rad(90), 0, 0),
    onActivate = function(tool)
        local char = tool.Parent
        if not char then return end
        -- 슬래시 애니메이션 + 히트박스 (combat 에이전트와 연동)
    end,
})
-- 플레이어에게 지급: sword.Parent = player.Backpack
```

### Tool Grip 가이드
```lua
-- Grip = 손 기준에서 Handle의 CFrame 오프셋
-- CFrame.new(x, y, z) * CFrame.Angles(rx, ry, rz)

-- 검/막대: 세로로 들기
CFrame.new(0, 0, -1.5) * CFrame.Angles(-math.rad(90), 0, 0)

-- 총: 앞으로 향하게
CFrame.new(0, -0.5, -1) * CFrame.Angles(-math.rad(90), 0, 0)

-- 방패: 팔 앞에
CFrame.new(0, 0, 0.5) * CFrame.Angles(0, math.rad(90), 0)

-- 횃불: 위로 들기
CFrame.new(0, -0.8, 0) * CFrame.Angles(0, 0, 0)
```

---

## 캐릭터 이벤트 패턴

```lua
-- 서버: 모든 플레이어 캐릭터 관리
Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(function(character)
        local humanoid = character:WaitForChild("Humanoid")
        local root = character:WaitForChild("HumanoidRootPart")
        
        -- 스폰 위치
        root.CFrame = CFrame.new(getSpawnPoint())
        
        -- 사망 처리
        humanoid.Died:Connect(function()
            -- 경험치 손실, 아이템 드롭 등
            task.wait(3)
            player:LoadCharacter()
        end)
    end)
    
    -- 첫 캐릭터 로드
    player:LoadCharacter()
end)
```

---

## 작업 완료 후 필수

1. NPC 크기가 건축물 비율과 맞는지 확인 (문 통과 가능한지)
2. Tool의 Grip이 자연스러운지 확인
3. SessionManager에 캐릭터/NPC 기록



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
