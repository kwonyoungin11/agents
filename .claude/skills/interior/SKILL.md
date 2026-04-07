---
name: interior
description: >
  Roblox 인테리어 전문가. 방 내부 장식, 가구 벽면 배치, 조명 배치, 창문 프레임,
  바닥 패턴, 천장 장식, 커튼, 카펫, 벽 장식.
  인테리어, 실내, 장식, 꾸미기, 가구배치, 실내장식 요청 시 자동 발동.
allowed-tools: Agent Read Grep Glob Bash
effort: high
---

# Interior Agent — Roblox 인테리어 전문가

방 내부를 자연스럽고 풍성하게 꾸민다. /architect가 만든 방 구조 위에 작업.

---

## 핵심: 벽면 가구 배치 공식

```lua
-- 벽 안쪽 면에 가구를 정렬하여 배치
local function placeAlongWall(wall, items, floorY)
    local wallCF = wall.CFrame
    local wallSize = wall.Size
    
    -- 벽의 안쪽 면 방향 (방 중심을 향하는 면)
    -- 벽 두께의 절반만큼 안쪽으로 오프셋
    
    local totalWidth = 0
    for _, item in items do totalWidth += item.size.X + 1 end  -- 1스터드 간격
    
    local startOffset = -totalWidth / 2
    local currentX = startOffset
    
    for _, item in items do
        local furniture = Instance.new("Part")
        furniture.Name = item.name
        furniture.Size = item.size
        furniture.Material = item.material or Enum.Material.WoodPlanks
        furniture.Color = item.color or Color3.fromRGB(139, 90, 43)
        furniture.Anchored = true
        
        -- 벽 안쪽 면에서 가구 깊이의 절반만큼 떨어져 배치
        local xOff = currentX + item.size.X / 2
        local yOff = -wallSize.Y/2 + item.size.Y/2  -- 바닥 기준
        local zOff = wallSize.Z/2 + item.size.Z/2    -- 벽 안쪽
        
        furniture.CFrame = wallCF * CFrame.new(xOff, yOff, -zOff)
        furniture.Parent = workspace
        
        currentX += item.size.X + 1
    end
end
```

## 조명 배치 패턴

```lua
-- 방 천장에 균등하게 조명 배치
local function lightRoom(ceiling, count, config)
    config = config or {}
    local lights = {}
    local cx, cy, cz = ceiling.Position.X, ceiling.Position.Y, ceiling.Position.Z
    local w, d = ceiling.Size.X * 0.6, ceiling.Size.Z * 0.6
    
    if count == 1 then
        -- 중앙 1개
        local bulb = Instance.new("Part")
        bulb.Shape = Enum.PartType.Ball
        bulb.Size = Vector3.new(1, 1, 1)
        bulb.Position = Vector3.new(cx, cy - 0.7, cz)
        bulb.Material = Enum.Material.Neon
        bulb.Color = config.color or Color3.fromRGB(255, 240, 220)
        bulb.Anchored = true; bulb.CanCollide = false
        bulb.Parent = workspace
        
        local pl = Instance.new("PointLight")
        pl.Brightness = config.brightness or 1.5
        pl.Range = config.range or 20
        pl.Color = config.color or Color3.fromRGB(255, 240, 220)
        pl.Parent = bulb
        table.insert(lights, bulb)
    else
        -- 균등 분포
        local cols = math.ceil(math.sqrt(count))
        local rows = math.ceil(count / cols)
        for r = 0, rows - 1 do
            for c = 0, cols - 1 do
                if #lights >= count then break end
                local x = cx - w/2 + (c + 0.5) * (w / cols)
                local z = cz - d/2 + (r + 0.5) * (d / rows)
                
                local bulb = Instance.new("Part")
                bulb.Shape = Enum.PartType.Ball
                bulb.Size = Vector3.new(0.6, 0.6, 0.6)
                bulb.Position = Vector3.new(x, cy - 0.5, z)
                bulb.Material = Enum.Material.Neon
                bulb.Color = config.color or Color3.fromRGB(255, 240, 220)
                bulb.Anchored = true; bulb.CanCollide = false
                bulb.Parent = workspace
                
                local pl = Instance.new("PointLight")
                pl.Brightness = config.brightness or 1
                pl.Range = config.range or 12
                pl.Color = bulb.Color
                pl.Parent = bulb
                table.insert(lights, bulb)
            end
        end
    end
    return lights
end
```

## 바닥 패턴 (체크/줄무늬)

```lua
local function checkerFloor(floor, color1, color2, tileSize)
    color1 = color1 or Color3.fromRGB(200, 200, 200)
    color2 = color2 or Color3.fromRGB(50, 50, 50)
    tileSize = tileSize or 4
    
    local floorPos = floor.Position
    local floorSize = floor.Size
    local floorCF = floor.CFrame
    floor:Destroy()  -- 기존 바닥 제거
    
    local cols = math.ceil(floorSize.X / tileSize)
    local rows = math.ceil(floorSize.Z / tileSize)
    
    for r = 0, rows - 1 do
        for c = 0, cols - 1 do
            local tile = Instance.new("Part")
            tile.Name = string.format("Tile_%d_%d", r, c)
            tile.Size = Vector3.new(tileSize, floorSize.Y, tileSize)
            tile.Anchored = true
            tile.Material = Enum.Material.Marble
            tile.Color = ((r + c) % 2 == 0) and color1 or color2
            
            local xOff = -floorSize.X/2 + c * tileSize + tileSize/2
            local zOff = -floorSize.Z/2 + r * tileSize + tileSize/2
            tile.CFrame = floorCF * CFrame.new(xOff, 0, zOff)
            tile.Parent = workspace
        end
    end
end
```

## 인테리어 프리셋

```lua
local presets = {
    Medieval = {
        wallMat = Enum.Material.Cobblestone,
        floorMat = Enum.Material.WoodPlanks,
        furnitureMat = Enum.Material.Wood,
        lightColor = Color3.fromRGB(255, 180, 80),  -- 따뜻한 촛불
        props = {"Torch", "Table", "Chair", "Barrel", "Bookshelf"},
    },
    Modern = {
        wallMat = Enum.Material.SmoothPlastic,
        floorMat = Enum.Material.Marble,
        furnitureMat = Enum.Material.SmoothPlastic,
        lightColor = Color3.fromRGB(255, 255, 255),  -- 백색 LED
        props = {"Sofa", "CoffeeTable", "TV", "Plant", "Lamp"},
    },
    SciFi = {
        wallMat = Enum.Material.DiamondPlate,
        floorMat = Enum.Material.Metal,
        furnitureMat = Enum.Material.Metal,
        lightColor = Color3.fromRGB(100, 200, 255),  -- 파란 네온
        props = {"Console", "HoloScreen", "CryoPod", "Scanner"},
    },
}
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
