---
name: physics
description: >
  Roblox 물리/제약 전문가. Constraints 전종류(Hinge, Spring, Rope, BallSocket, Prismatic,
  Weld, Rod, Align, VectorForce), 차량 물리, 래그돌, 파괴 시스템, PhysicalProperties.
  물리, 파괴, 폭발, 차량, 래그돌, 스프링, 밧줄, 관절, 제약, 힌지 요청 시 자동 발동.
allowed-tools: Agent Read Grep Glob Bash
effort: high
---

# Physics Agent — Roblox 물리/제약 전문가

모든 물리 시뮬레이션과 Constraint 시스템을 구현한다.

---

## Constraint 기본 규칙

**모든 Constraint는 2개의 Attachment가 필요하다:**
```lua
local att0 = Instance.new("Attachment", part0)
att0.Position = Vector3.new(0, part0.Size.Y/2, 0)  -- 파트 윗면
att0.Name = "Att0"

local att1 = Instance.new("Attachment", part1)
att1.Position = Vector3.new(0, -part1.Size.Y/2, 0)  -- 파트 아랫면
att1.Name = "Att1"

constraint.Attachment0 = att0
constraint.Attachment1 = att1
constraint.Parent = part0  -- 어느 파트에든 상관없음
```

**Attachment.Position** = 부모 파트의 **로컬 좌표** 기준 위치.

---

## Constraint 전종류

### WeldConstraint — 고정 결합 (가장 기본)
```lua
local weld = Instance.new("WeldConstraint")
weld.Part0 = partA
weld.Part1 = partB
weld.Parent = partA
-- Attachment 불필요! Part0/Part1만 설정
-- 두 파트가 현재 상대 위치 그대로 고정됨
```

### HingeConstraint — 경첩 (문, 뚜껑, 팔)
```lua
local hinge = Instance.new("HingeConstraint")
hinge.Attachment0 = att0; hinge.Attachment1 = att1

-- 자유 회전
hinge.ActuatorType = Enum.ActuatorType.None

-- 모터 (자동 회전)
hinge.ActuatorType = Enum.ActuatorType.Motor
hinge.AngularVelocity = 2    -- rad/s 회전 속도
hinge.MotorMaxTorque = 1000  -- 최대 토크

-- 서보 (특정 각도로)
hinge.ActuatorType = Enum.ActuatorType.Servo
hinge.TargetAngle = 90        -- 목표 각도
hinge.AngularSpeed = 2        -- 회전 속도
hinge.ServoMaxTorque = 1000

-- 각도 제한
hinge.LimitsEnabled = true
hinge.LowerAngle = -90
hinge.UpperAngle = 90

hinge.Parent = part0
```

### SpringConstraint — 스프링
```lua
local spring = Instance.new("SpringConstraint")
spring.Attachment0 = att0; spring.Attachment1 = att1
spring.Stiffness = 100     -- 강성 (높을수록 단단)
spring.Damping = 10        -- 감쇠 (높을수록 빨리 안정)
spring.FreeLength = 5      -- 자연 길이 (이 길이로 돌아가려 함)
spring.LimitsEnabled = true
spring.MinLength = 2
spring.MaxLength = 10
spring.Visible = true      -- 스프링 시각화
spring.Coils = 5           -- 코일 수 (시각)
spring.Radius = 0.5        -- 코일 반지름 (시각)
spring.Parent = part0
```

### RopeConstraint — 밧줄
```lua
local rope = Instance.new("RopeConstraint")
rope.Attachment0 = att0; rope.Attachment1 = att1
rope.Length = 20             -- 밧줄 길이 (이 이상 늘어나지 않음)
rope.Restitution = 0.5      -- 반발 계수 (0=늘어지지않음, 1=통통 튐)
rope.Visible = true
rope.Thickness = 0.2
rope.Parent = part0
```

### RodConstraint — 고정 거리 막대
```lua
local rod = Instance.new("RodConstraint")
rod.Attachment0 = att0; rod.Attachment1 = att1
rod.Length = 10              -- 두 점 사이 고정 거리
rod.Visible = true
rod.Thickness = 0.3
rod.Parent = part0
```

### PrismaticConstraint — 슬라이더 (엘리베이터, 피스톤)
```lua
local slider = Instance.new("PrismaticConstraint")
slider.Attachment0 = att0; slider.Attachment1 = att1

slider.ActuatorType = Enum.ActuatorType.Motor
slider.Velocity = 5              -- 이동 속도 (studs/s)
slider.MotorMaxForce = 10000     -- 최대 힘

slider.LimitsEnabled = true
slider.LowerLimit = 0            -- 최소 위치
slider.UpperLimit = 20           -- 최대 위치

slider.Parent = part0
```

### BallSocketConstraint — 볼 조인트 (래그돌의 핵심)
```lua
local ball = Instance.new("BallSocketConstraint")
ball.Attachment0 = att0; ball.Attachment1 = att1
ball.LimitsEnabled = true
ball.UpperAngle = 45       -- 최대 회전 각도 (0~180)
ball.TwistLimitsEnabled = true
ball.TwistLowerAngle = -45
ball.TwistUpperAngle = 45
ball.Parent = part0
```

### AlignPosition — 위치 정렬 (부드러운 추적)
```lua
local align = Instance.new("AlignPosition")
align.Attachment0 = att0    -- 이동할 파트
align.Attachment1 = att1    -- 목표 위치 (nil이면 Attachment0 월드 위치 사용)
align.MaxForce = 50000      -- 최대 힘
align.Responsiveness = 50   -- 반응 속도 (높을수록 빠름)
align.Mode = Enum.PositionAlignmentMode.TwoAttachment
align.Parent = part0
```

### AlignOrientation — 회전 정렬
```lua
local alignRot = Instance.new("AlignOrientation")
alignRot.Attachment0 = att0
alignRot.Attachment1 = att1
alignRot.MaxTorque = 50000
alignRot.Responsiveness = 50
alignRot.Parent = part0
```

### VectorForce — 방향 힘 (호버, 제트팩)
```lua
local force = Instance.new("VectorForce")
force.Attachment0 = att0
-- 중력 상쇄 = 호버
force.Force = Vector3.new(0, workspace.Gravity * part:GetMass(), 0)
force.RelativeTo = Enum.ActuatorRelativeTo.World  -- World/Attachment0/Attachment1
force.Parent = part
```

### LinearVelocity — 일정 속도 (컨베이어 벨트)
```lua
local lv = Instance.new("LinearVelocity")
lv.Attachment0 = att0
lv.VectorVelocity = Vector3.new(10, 0, 0)  -- 초당 10스터드 X방향
lv.MaxForce = 10000
lv.RelativeTo = Enum.ActuatorRelativeTo.World
lv.Parent = part
```

### AngularVelocity — 일정 회전 (팬, 프로펠러)
```lua
local av = Instance.new("AngularVelocity")
av.Attachment0 = att0
av.AngularVelocity = Vector3.new(0, 5, 0)  -- Y축 회전
av.MaxTorque = 10000
av.RelativeTo = Enum.ActuatorRelativeTo.World
av.Parent = part
```

---

## PhysicalProperties (물리 재질)

```lua
part.CustomPhysicalProperties = PhysicalProperties.new(
    density,      -- 밀도 (무게에 영향)
    friction,     -- 마찰 (0~1)
    elasticity,   -- 탄성 (0~1, 1=완전 반발)
    frictionWeight,
    elasticityWeight
)

-- 프리셋
local presets = {
    Heavy_Metal  = PhysicalProperties.new(7, 0.4, 0.2, 1, 1),
    Light_Wood   = PhysicalProperties.new(0.5, 0.5, 0.3, 1, 1),
    Bouncy_Ball  = PhysicalProperties.new(1, 0.2, 1.0, 1, 1),
    Ice_Surface  = PhysicalProperties.new(1, 0.02, 0.1, 1, 1),
    Rubber       = PhysicalProperties.new(1.2, 0.8, 0.7, 1, 1),
    Feather      = PhysicalProperties.new(0.05, 0.3, 0.5, 1, 1),
}
```

---

## 래그돌 시스템

```lua
local function enableRagdoll(character)
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)
    humanoid:ChangeState(Enum.HumanoidStateType.Physics)
    
    for _, joint in character:GetDescendants() do
        if joint:IsA("Motor6D") and joint.Part0 and joint.Part1 then
            local socket = Instance.new("BallSocketConstraint")
            socket.LimitsEnabled = true
            socket.UpperAngle = 45
            
            local a0 = Instance.new("Attachment", joint.Part0)
            a0.CFrame = joint.C0
            local a1 = Instance.new("Attachment", joint.Part1)
            a1.CFrame = joint.C1
            
            socket.Attachment0 = a0; socket.Attachment1 = a1
            socket.Parent = joint.Part0
            
            joint.Enabled = false
        end
    end
    
    -- 모든 파트 충돌 활성화
    for _, part in character:GetDescendants() do
        if part:IsA("BasePart") then
            part.CanCollide = true
        end
    end
end

local function disableRagdoll(character)
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, true)
    humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
    
    for _, joint in character:GetDescendants() do
        if joint:IsA("Motor6D") then
            joint.Enabled = true
        end
        if joint:IsA("BallSocketConstraint") then
            joint:Destroy()
        end
    end
end
```

---

## 파괴 시스템

```lua
local function shatter(part, pieces, force)
    pieces = pieces or 8; force = force or 50
    local pos = part.Position
    local size = part.Size
    local color = part.Color
    local material = part.Material
    
    part:Destroy()
    
    for i = 1, pieces do
        local debris = Instance.new("Part")
        debris.Size = size * (0.3 + math.random() * 0.4)
        debris.Position = pos + Vector3.new(
            (math.random()-0.5)*size.X,
            (math.random()-0.5)*size.Y,
            (math.random()-0.5)*size.Z
        )
        debris.Color = color; debris.Material = material
        debris.Anchored = false; debris.Parent = workspace
        
        local dir = (debris.Position - pos).Unit
        debris:ApplyImpulse(dir * force * debris:GetMass()
            + Vector3.new(0, force * 0.5, 0))
        
        game:GetService("Debris"):AddItem(debris, 5)
    end
end
```

---

## 작업 완료 후 필수

1. 물리 객체 수 성능 확인 (Anchored=false 파트 최소화)
2. 파괴 이펙트의 Debris 타이머 확인
3. SessionManager에 물리 시스템 로그



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
