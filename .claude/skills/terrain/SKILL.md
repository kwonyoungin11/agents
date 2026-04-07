---
name: terrain
description: >
  Roblox 지형 전문가. Terrain API로 산, 계곡, 호수, 동굴, 섬, 사막, 절벽을 프로시저럴
  생성하고, 지형 재질을 자연스럽게 배치. 지형, 산, 호수, 나무, 숲, 물, 동굴, 바다, 섬,
  사막, 절벽, 계곡, 언덕, 강 요청 시 자동 발동.
allowed-tools: Agent Read Grep Glob Bash
effort: high
---

# Terrain Agent — Roblox 지형 전문가

Roblox Terrain API를 활용하여 자연 지형을 **프로시저럴**하게 생성한다.

---

## Terrain API 핵심

Roblox Terrain은 4스터드 단위 복셀(voxel) 기반. `workspace.Terrain` 객체를 통해 조작.

### 기본 채우기 함수

```lua
local terrain = workspace.Terrain

-- 직육면체 채우기
terrain:FillBlock(
    CFrame.new(0, -10, 0),       -- 중심 CFrame (위치 + 방향)
    Vector3.new(200, 20, 200),    -- 크기 (X, Y, Z)
    Enum.Material.Grass           -- 재질
)

-- 구체 채우기
terrain:FillBall(
    Vector3.new(0, 5, 0),   -- 중심 Vector3
    20,                       -- 반지름
    Enum.Material.Rock        -- 재질
)

-- 실린더 채우기
terrain:FillCylinder(
    CFrame.new(0, 0, 0),    -- 중심 CFrame
    30,                       -- 높이
    15,                       -- 반지름
    Enum.Material.Sand        -- 재질
)

-- 쐐기형 (경사면)
terrain:FillWedge(
    CFrame.new(0, 10, 0),   -- CFrame
    Vector3.new(20, 10, 20), -- 크기
    Enum.Material.Rock        -- 재질
)

-- 영역 삭제 (Air로 대체)
terrain:FillBlock(CFrame.new(0, -5, 0), Vector3.new(50, 10, 50), Enum.Material.Air)

-- 전체 초기화
terrain:Clear()
```

---

## Terrain Material 전체 목록 & 용도

| Material | 한국어 | 주요 용도 |
|---|---|---|
| Grass | 잔디 | 평원, 초원 |
| LeafyGrass | 풍성한 잔디 | 숲 바닥, 정원 |
| Ground | 흙 | 산길, 밭 |
| Mud | 진흙 | 습지, 강가 |
| Sand | 모래 | 해변, 사막 |
| Snow | 눈 | 설원, 산 정상 |
| Ice | 얼음 | 빙하, 호수 표면 |
| Glacier | 빙하 | 극지방 |
| Rock | 바위 | 절벽, 동굴 |
| Slate | 암석 | 산, 낭떠러지 |
| Basalt | 현무암 | 화산 지역 |
| Limestone | 석회암 | 카르스트 지형 |
| Sandstone | 사암 | 사막 절벽 |
| Salt | 소금 | 소금 평원 |
| CrackedLava | 용암 | 화산, 지옥 |
| Cobblestone | 조약돌 | 강바닥 |
| Asphalt | 아스팔트 | 도로 |
| Concrete | 콘크리트 | 인공 구조물 기초 |
| Pavement | 포장도로 | 도시 도로 |
| WoodPlanks | 나무판자 | 나무 다리, 부두 |
| Water | 물 | 강, 호수, 바다 |

---

## 프로시저럴 지형 생성

### 평탄한 지면 (기본 베이스)
```lua
local function createFlatGround(centerX, centerZ, sizeX, sizeZ, height, material)
    material = material or Enum.Material.Grass
    height = height or 10
    terrain:FillBlock(
        CFrame.new(centerX, -height/2, centerZ),
        Vector3.new(sizeX, height, sizeZ),
        material
    )
    print(string.format("Ground: %dx%d at (%d, %d)", sizeX, sizeZ, centerX, centerZ))
end
```

### 산 (다층 실린더 스택)
```lua
local function createMountain(cx, cz, radius, height, material)
    material = material or Enum.Material.Rock
    local layers = math.ceil(height / 4)
    
    for i = 0, layers do
        local t = i / layers  -- 0(바닥) ~ 1(정상)
        local r = radius * (1 - t^0.8)  -- 위로 갈수록 좁아짐
        local h = 4
        local y = i * 4
        
        if r < 2 then r = 2 end
        
        -- 아래쪽은 Rock, 중간은 Slate, 위는 Snow
        local mat = material
        if t > 0.7 then mat = Enum.Material.Snow
        elseif t > 0.4 then mat = Enum.Material.Slate end
        
        terrain:FillCylinder(
            CFrame.new(cx, y + h/2, cz),
            h, r, mat
        )
    end
    
    -- 정상에 눈 캡
    terrain:FillBall(Vector3.new(cx, height * 0.9, cz), radius * 0.25, Enum.Material.Snow)
    print(string.format("Mountain: radius=%d height=%d at (%d, %d)", radius, height, cx, cz))
end
```

### 호수
```lua
local function createLake(cx, cz, radiusX, radiusZ, depth)
    depth = depth or 8
    -- 웅덩이 파기
    terrain:FillBlock(
        CFrame.new(cx, -depth/2, cz),
        Vector3.new(radiusX*2, depth, radiusZ*2),
        Enum.Material.Air
    )
    -- 물 채우기 (약간 작게, 둑 유지)
    terrain:FillBlock(
        CFrame.new(cx, -depth/2 - 0.5, cz),
        Vector3.new(radiusX*2 - 2, depth - 1, radiusZ*2 - 2),
        Enum.Material.Water
    )
    -- 가장자리 모래
    terrain:FillBlock(
        CFrame.new(cx, -0.5, cz),
        Vector3.new(radiusX*2 + 6, 1, radiusZ*2 + 6),
        Enum.Material.Sand
    )
    print(string.format("Lake: %dx%d depth=%d at (%d, %d)", radiusX*2, radiusZ*2, depth, cx, cz))
end
```

### 강 (점 배열을 따라)
```lua
local function createRiver(points, width, depth)
    depth = depth or 4; width = width or 8
    for i = 1, #points - 1 do
        local p1, p2 = points[i], points[i + 1]
        local mid = (p1 + p2) / 2
        local dist = (p2 - p1).Magnitude
        local cf = CFrame.lookAt(mid, p2)
        
        -- 강바닥 파기
        terrain:FillBlock(cf * CFrame.new(0, -depth/2, 0),
            Vector3.new(width, depth + 2, dist + 2), Enum.Material.Air)
        -- 물
        terrain:FillBlock(cf * CFrame.new(0, -depth/2 - 1, 0),
            Vector3.new(width - 2, depth, dist + 2), Enum.Material.Water)
        -- 강둑 (양쪽)
        terrain:FillBlock(cf * CFrame.new(width/2 + 1, -depth/2, 0),
            Vector3.new(3, depth, dist + 2), Enum.Material.Mud)
        terrain:FillBlock(cf * CFrame.new(-width/2 - 1, -depth/2, 0),
            Vector3.new(3, depth, dist + 2), Enum.Material.Mud)
    end
end
```

### 동굴
```lua
local function createCave(start, direction, length, radius, segments)
    segments = segments or 20
    local step = length / segments
    
    for i = 0, segments do
        local t = i / segments
        local pos = start + direction.Unit * (step * i)
        -- 랜덤 오프셋으로 자연스러운 굴곡
        pos = pos + Vector3.new(
            (math.random() - 0.5) * radius * 0.4,
            (math.random() - 0.5) * radius * 0.3,
            (math.random() - 0.5) * radius * 0.4
        )
        -- 변하는 반지름
        local r = radius * (1 + math.sin(t * math.pi * 3) * 0.3)
        terrain:FillBall(pos, r, Enum.Material.Air)
    end
    print(string.format("Cave: length=%d radius=%d", length, radius))
end
```

### 절벽
```lua
local function createCliff(startX, startZ, length, height, direction)
    direction = direction or Vector3.new(1, 0, 0)
    local segments = math.ceil(length / 8)
    
    for i = 0, segments do
        local t = i / segments
        local pos = Vector3.new(startX, 0, startZ) + direction.Unit * (t * length)
        -- 절벽 높이에 약간의 변화
        local h = height * (0.8 + math.random() * 0.4)
        
        terrain:FillBlock(
            CFrame.new(pos.X, h/2, pos.Z),
            Vector3.new(8, h, 12),
            Enum.Material.Rock
        )
        -- 절벽 위에 잔디
        terrain:FillBlock(
            CFrame.new(pos.X, h + 1, pos.Z),
            Vector3.new(12, 2, 16),
            Enum.Material.Grass
        )
    end
end
```

### 섬
```lua
local function createIsland(cx, cz, radius, height, waterLevel)
    waterLevel = waterLevel or 0
    
    -- 바다
    terrain:FillBlock(
        CFrame.new(cx, waterLevel - 5, cz),
        Vector3.new(radius * 4, 10, radius * 4),
        Enum.Material.Water
    )
    
    -- 섬 본체 (여러 겹)
    for i = 0, 5 do
        local t = i / 5
        local r = radius * (1 - t * 0.7)
        local y = waterLevel + i * (height / 5)
        terrain:FillCylinder(CFrame.new(cx, y, cz), height/5, r,
            t < 0.3 and Enum.Material.Sand or Enum.Material.Grass)
    end
    
    -- 해변 (가장자리 모래)
    terrain:FillCylinder(CFrame.new(cx, waterLevel, cz), 3, radius + 5, Enum.Material.Sand)
end
```

### 사막 언덕
```lua
local function createDunes(cx, cz, areaSize, duneCount)
    -- 기본 모래 바닥
    terrain:FillBlock(CFrame.new(cx, -2, cz), Vector3.new(areaSize, 4, areaSize), Enum.Material.Sand)
    
    for i = 1, duneCount do
        local x = cx + (math.random() - 0.5) * areaSize * 0.8
        local z = cz + (math.random() - 0.5) * areaSize * 0.8
        local h = 5 + math.random() * 15
        local r = 10 + math.random() * 20
        
        -- 비대칭 언덕 (한쪽이 더 가파름)
        terrain:FillBall(Vector3.new(x, h * 0.3, z), r, Enum.Material.Sand)
        terrain:FillBall(Vector3.new(x + r * 0.3, h * 0.5, z), r * 0.7, Enum.Material.Sand)
    end
end
```

---

## Water 속성

```lua
terrain.WaterWaveSize = 0.15        -- 파도 크기 (0~1)
terrain.WaterWaveSpeed = 10          -- 파도 속도
terrain.WaterTransparency = 0.3      -- 투명도 (0=불투명, 1=투명)
terrain.WaterReflectance = 0.5       -- 반사율
terrain.WaterColor = Color3.fromRGB(30, 80, 120)  -- 물 색상
```

### 환경별 Water 설정
```lua
local waterPresets = {
    Ocean    = {color={20,60,100},  trans=0.4, wave=0.25, speed=12},
    Lake     = {color={30,80,120},  trans=0.3, wave=0.1,  speed=6},
    River    = {color={40,90,110},  trans=0.35, wave=0.15, speed=15},
    Swamp    = {color={50,70,40},   trans=0.15, wave=0.05, speed=3},
    Lava     = {color={200,50,0},   trans=0.1, wave=0.3,  speed=5},
    Crystal  = {color={100,200,255},trans=0.6, wave=0.05, speed=4},
}
```

---

## 레이캐스트로 지면 높이 찾기

구조물, 나무, NPC 배치 시 지면 높이를 찾아야 한다:

```lua
local function getGroundY(x, z)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Include
    params.FilterDescendantsInstances = {workspace.Terrain}
    
    local ray = workspace:Raycast(
        Vector3.new(x, 1000, z),
        Vector3.new(0, -2000, 0),
        params
    )
    if ray then
        return ray.Position.Y, ray.Material
    end
    return 0, Enum.Material.Air
end
```

---

## 조합 레시피: 완성된 환경

### 숲 계곡
```lua
local function createForestValley(cx, cz, size)
    -- 바닥
    createFlatGround(cx, cz, size, size, 10, Enum.Material.Grass)
    -- 양쪽 절벽
    createCliff(cx - size/2, cz, size, 30, Vector3.new(0, 0, 1))
    createCliff(cx + size/2, cz, size, 25, Vector3.new(0, 0, 1))
    -- 중앙 강
    local points = {}
    for i = 0, 10 do
        table.insert(points, Vector3.new(cx + (math.random()-0.5)*10, -2, cz - size/2 + i*(size/10)))
    end
    createRiver(points, 6, 3)
end
```

---

## 작업 완료 후 필수

1. 지형 변경 좌표/크기 SessionManager에 기록
2. 주요 지점(산 정상, 호수 중심 등)에 앵커 설정
3. `screen_capture`로 결과 확인
4. 지면 높이가 변경되었으면 근처 구조물 좌표 재확인 필요



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
