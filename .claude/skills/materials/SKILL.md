---
name: materials
description: |
  Roblox 재질(Material) 시스템 스킬. 모든 Enum.Material 값과 용도, 테마별 재질 조합
  (중세/SF/공포/판타지/현대), SurfaceAppearance PBR 텍스처, MCP generate_material 활용.
  키워드: 재질, 머티리얼, 텍스처, PBR, 표면, 벽돌, 나무, 돌, 금속, 콘크리트, 네온,
  중세, SF, 공포, 판타지, 현대, 유리, 대리석, 잔디, 얼음, 용암, 모래, 흙,
  material, texture, surface, brick, wood, stone, metal, neon, marble, ice
allowed-tools:
  - Bash
  - Edit
  - Write
  - Read
  - Grep
  - Glob
  - WebFetch
  - WebSearch
  - mcp__roblox-mcp__execute_luau_in_studio
  - mcp__roblox-mcp__generate_material
effort: high
---

# Materials Skill

Roblox의 모든 Material enum, 테마별 재질 조합, SurfaceAppearance PBR 텍스처를 다루는 스킬입니다.

## Complete Materials Enum Reference

### Natural Materials
```lua
local NATURAL_MATERIALS = {
    -- 지면/토양
    { enum = Enum.Material.Grass,       name = "Grass",       use = "잔디밭, 공원, 들판" },
    { enum = Enum.Material.Ground,      name = "Ground",      use = "비포장 도로, 황무지" },
    { enum = Enum.Material.Mud,         name = "Mud",         use = "진흙탕, 늪지대, 비 온 뒤 땅" },
    { enum = Enum.Material.Sand,        name = "Sand",        use = "해변, 사막, 모래밭" },
    { enum = Enum.Material.Snow,        name = "Snow",        use = "눈 덮인 지형, 겨울 테마" },
    { enum = Enum.Material.Ice,         name = "Ice",         use = "빙하, 얼음 동굴, 겨울 호수" },
    { enum = Enum.Material.Salt,        name = "Salt",        use = "소금 사막, 결정 동굴" },
    { enum = Enum.Material.Limestone,   name = "Limestone",   use = "석회암 절벽, 고대 건축" },
    { enum = Enum.Material.Sandstone,   name = "Sandstone",   use = "사암 절벽, 사막 건축" },
    { enum = Enum.Material.Slate,       name = "Slate",       use = "슬레이트 지붕, 바위 표면" },
    { enum = Enum.Material.Rock,        name = "Rock",        use = "바위, 절벽, 동굴 벽면" },
    { enum = Enum.Material.Basalt,      name = "Basalt",      use = "화산 지형, 현무암 기둥" },
    { enum = Enum.Material.CrackedLava, name = "CrackedLava", use = "균열 용암, 화산 분화구" },
    { enum = Enum.Material.Glacier,     name = "Glacier",     use = "빙하, 거대 얼음 구조물" },
    { enum = Enum.Material.LeafyGrass,  name = "LeafyGrass",  use = "무성한 풀, 숲 바닥" },

    -- 나무
    { enum = Enum.Material.Wood,        name = "Wood",        use = "목재 구조물, 가구, 울타리" },
    { enum = Enum.Material.WoodPlanks,  name = "WoodPlanks",  use = "나무 바닥, 선박 갑판, 오두막" },
}
```

### Construction Materials
```lua
local CONSTRUCTION_MATERIALS = {
    { enum = Enum.Material.Brick,         name = "Brick",         use = "벽돌 벽, 굴뚝, 건물 외벽" },
    { enum = Enum.Material.Cobblestone,   name = "Cobblestone",   use = "중세 도로, 성벽, 보도" },
    { enum = Enum.Material.Concrete,      name = "Concrete",      use = "현대 건물, 도로, 방벽" },
    { enum = Enum.Material.Granite,       name = "Granite",       use = "화강암 바닥, 기념비, 조리대" },
    { enum = Enum.Material.Marble,        name = "Marble",        use = "대리석 바닥, 궁전, 신전" },
    { enum = Enum.Material.Pavement,      name = "Pavement",      use = "보도, 인도, 포장도로" },
    { enum = Enum.Material.Asphalt,       name = "Asphalt",       use = "아스팔트 도로, 주차장" },
    { enum = Enum.Material.Cement,        name = "Cement",        use = "시멘트 벽, 미완성 건물" },
    { enum = Enum.Material.Plaster,       name = "Plaster",       use = "실내 벽, 천장" },
    { enum = Enum.Material.Ceramic,       name = "Ceramic",       use = "타일 바닥, 도자기, 화장실" },
}
```

### Metal & Industrial Materials
```lua
local METAL_MATERIALS = {
    { enum = Enum.Material.Metal,            name = "Metal",            use = "금속 구조물, 파이프" },
    { enum = Enum.Material.CorrodedMetal,    name = "CorrodedMetal",    use = "녹슨 금속, 폐허, 포스트아포칼립스" },
    { enum = Enum.Material.DiamondPlate,     name = "DiamondPlate",     use = "산업용 바닥, 엘리베이터, 공장" },
    { enum = Enum.Material.Foil,             name = "Foil",             use = "반사 표면, 거울, 장식" },
    { enum = Enum.Material.CastIron,         name = "CastIron",         use = "주철 울타리, 난로, 중세 무기" },
    { enum = Enum.Material.Copper,           name = "Copper",           use = "구리 지붕, 파이프, 동상" },
    { enum = Enum.Material.Aluminum,         name = "Aluminum",         use = "알루미늄 패널, 현대 건축" },
    { enum = Enum.Material.Gold,             name = "Gold",             use = "금 장식, 보물, 왕좌" },
    { enum = Enum.Material.Silver,           name = "Silver",           use = "은 장식, 갑옷, 무기" },
    { enum = Enum.Material.Bronze,           name = "Bronze",           use = "청동 동상, 고대 유물" },
    { enum = Enum.Material.Iron,             name = "Iron",             use = "철제 문, 갑옷, 격자" },
    { enum = Enum.Material.Steel,            name = "Steel",            use = "강철 빔, 현대 구조물" },
    { enum = Enum.Material.Chrome,           name = "Chrome",           use = "크롬 장식, SF 건축" },
    { enum = Enum.Material.Titanium,         name = "Titanium",        use = "티타늄 갑옷, SF 우주선" },
}
```

### Special Materials
```lua
local SPECIAL_MATERIALS = {
    { enum = Enum.Material.Neon,             name = "Neon",             use = "발광 효과, 네온 사인, 마법" },
    { enum = Enum.Material.ForceField,       name = "ForceField",       use = "방어막, 에너지 쉴드" },
    { enum = Enum.Material.Glass,            name = "Glass",            use = "창문, 유리병, 온실" },
    { enum = Enum.Material.SmoothPlastic,    name = "SmoothPlastic",    use = "깔끔한 표면, 장난감, UI 요소" },
    { enum = Enum.Material.Plastic,          name = "Plastic",          use = "기본 표면, 가구" },
    { enum = Enum.Material.Fabric,           name = "Fabric",           use = "천, 커튼, 텐트, 카펫" },
    { enum = Enum.Material.Leather,          name = "Leather",          use = "가죽 의자, 갑옷, 책 표지" },
    { enum = Enum.Material.Rubber,           name = "Rubber",           use = "타이어, 매트, 놀이터 바닥" },
    { enum = Enum.Material.Cardboard,        name = "Cardboard",        use = "골판지 상자, 임시 구조물" },
    { enum = Enum.Material.Carpet,           name = "Carpet",           use = "카펫 바닥, 실내 장식" },
    { enum = Enum.Material.Wax,              name = "Wax",              use = "양초, 밀랍 바닥" },
}
```

## Theme Material Combinations

### Medieval (중세) Theme
```lua
local function applyMedievalMaterials(model: Model)
    local MEDIEVAL_MAPPING = {
        Wall = { material = Enum.Material.Cobblestone, color = Color3.fromRGB(140, 130, 120) },
        Floor = { material = Enum.Material.WoodPlanks, color = Color3.fromRGB(120, 80, 50) },
        Roof = { material = Enum.Material.Slate, color = Color3.fromRGB(80, 75, 70) },
        Door = { material = Enum.Material.Wood, color = Color3.fromRGB(100, 65, 35) },
        Window = { material = Enum.Material.Glass, color = Color3.fromRGB(180, 200, 220) },
        Pillar = { material = Enum.Material.Granite, color = Color3.fromRGB(150, 145, 140) },
        Trim = { material = Enum.Material.CastIron, color = Color3.fromRGB(50, 50, 55) },
        Foundation = { material = Enum.Material.Rock, color = Color3.fromRGB(100, 95, 90) },
        Fence = { material = Enum.Material.Wood, color = Color3.fromRGB(90, 60, 30) },
        Path = { material = Enum.Material.Cobblestone, color = Color3.fromRGB(120, 115, 110) },
    }

    for _, part in ipairs(model:GetDescendants()) do
        if part:IsA("BasePart") then
            local mapping = MEDIEVAL_MAPPING[part.Name]
            if mapping then
                part.Material = mapping.material
                part.Color = mapping.color
            end
        end
    end
end
```

### SciFi (SF) Theme
```lua
local function applySciFiMaterials(model: Model)
    local SCIFI_MAPPING = {
        Wall = { material = Enum.Material.DiamondPlate, color = Color3.fromRGB(180, 185, 190) },
        Floor = { material = Enum.Material.Metal, color = Color3.fromRGB(100, 105, 110) },
        Roof = { material = Enum.Material.Metal, color = Color3.fromRGB(120, 125, 130) },
        Door = { material = Enum.Material.Chrome, color = Color3.fromRGB(200, 205, 210) },
        Window = { material = Enum.Material.Glass, color = Color3.fromRGB(100, 180, 255) },
        Pillar = { material = Enum.Material.Titanium, color = Color3.fromRGB(160, 165, 170) },
        Trim = { material = Enum.Material.Neon, color = Color3.fromRGB(0, 170, 255) },
        Panel = { material = Enum.Material.SmoothPlastic, color = Color3.fromRGB(60, 65, 70) },
        Pipe = { material = Enum.Material.Aluminum, color = Color3.fromRGB(140, 145, 150) },
        Screen = { material = Enum.Material.Neon, color = Color3.fromRGB(0, 200, 150) },
    }

    for _, part in ipairs(model:GetDescendants()) do
        if part:IsA("BasePart") then
            local mapping = SCIFI_MAPPING[part.Name]
            if mapping then
                part.Material = mapping.material
                part.Color = mapping.color
            end
        end
    end
end
```

### Horror (공포) Theme
```lua
local function applyHorrorMaterials(model: Model)
    local HORROR_MAPPING = {
        Wall = { material = Enum.Material.Concrete, color = Color3.fromRGB(60, 55, 50) },
        Floor = { material = Enum.Material.WoodPlanks, color = Color3.fromRGB(50, 35, 25) },
        Roof = { material = Enum.Material.CorrodedMetal, color = Color3.fromRGB(70, 50, 40) },
        Door = { material = Enum.Material.Wood, color = Color3.fromRGB(40, 30, 20) },
        Window = { material = Enum.Material.Glass, color = Color3.fromRGB(60, 60, 80) },
        Pillar = { material = Enum.Material.Cement, color = Color3.fromRGB(80, 75, 70) },
        Trim = { material = Enum.Material.CorrodedMetal, color = Color3.fromRGB(90, 60, 40) },
        Pipe = { material = Enum.Material.CorrodedMetal, color = Color3.fromRGB(80, 55, 35) },
        Debris = { material = Enum.Material.Rock, color = Color3.fromRGB(50, 45, 40) },
        Stain = { material = Enum.Material.Mud, color = Color3.fromRGB(40, 15, 10) },
    }

    for _, part in ipairs(model:GetDescendants()) do
        if part:IsA("BasePart") then
            local mapping = HORROR_MAPPING[part.Name]
            if mapping then
                part.Material = mapping.material
                part.Color = mapping.color
            end
        end
    end
end
```

### Modern (현대) Theme
```lua
local function applyModernMaterials(model: Model)
    local MODERN_MAPPING = {
        Wall = { material = Enum.Material.Concrete, color = Color3.fromRGB(220, 220, 220) },
        Floor = { material = Enum.Material.Marble, color = Color3.fromRGB(240, 235, 230) },
        Roof = { material = Enum.Material.Concrete, color = Color3.fromRGB(180, 180, 180) },
        Door = { material = Enum.Material.SmoothPlastic, color = Color3.fromRGB(245, 245, 245) },
        Window = { material = Enum.Material.Glass, color = Color3.fromRGB(200, 220, 240) },
        Pillar = { material = Enum.Material.Concrete, color = Color3.fromRGB(200, 200, 200) },
        Trim = { material = Enum.Material.Steel, color = Color3.fromRGB(160, 160, 165) },
        Counter = { material = Enum.Material.Granite, color = Color3.fromRGB(50, 50, 55) },
        Cabinet = { material = Enum.Material.SmoothPlastic, color = Color3.fromRGB(250, 250, 250) },
        Accent = { material = Enum.Material.Wood, color = Color3.fromRGB(160, 120, 80) },
    }

    for _, part in ipairs(model:GetDescendants()) do
        if part:IsA("BasePart") then
            local mapping = MODERN_MAPPING[part.Name]
            if mapping then
                part.Material = mapping.material
                part.Color = mapping.color
            end
        end
    end
end
```

### Fantasy (판타지) Theme
```lua
local function applyFantasyMaterials(model: Model)
    local FANTASY_MAPPING = {
        Wall = { material = Enum.Material.Marble, color = Color3.fromRGB(200, 190, 210) },
        Floor = { material = Enum.Material.Marble, color = Color3.fromRGB(220, 210, 230) },
        Roof = { material = Enum.Material.Slate, color = Color3.fromRGB(100, 80, 120) },
        Door = { material = Enum.Material.Wood, color = Color3.fromRGB(130, 90, 60) },
        Window = { material = Enum.Material.Glass, color = Color3.fromRGB(180, 150, 220) },
        Pillar = { material = Enum.Material.Marble, color = Color3.fromRGB(230, 220, 240) },
        Trim = { material = Enum.Material.Gold, color = Color3.fromRGB(255, 200, 50) },
        Crystal = { material = Enum.Material.Neon, color = Color3.fromRGB(150, 100, 255) },
        MagicRune = { material = Enum.Material.Neon, color = Color3.fromRGB(100, 200, 255) },
        Path = { material = Enum.Material.Cobblestone, color = Color3.fromRGB(160, 150, 170) },
    }

    for _, part in ipairs(model:GetDescendants()) do
        if part:IsA("BasePart") then
            local mapping = FANTASY_MAPPING[part.Name]
            if mapping then
                part.Material = mapping.material
                part.Color = mapping.color
            end
        end
    end
end
```

## SurfaceAppearance PBR Texturing

### Creating PBR Material
```lua
local function applyPBR(part: BasePart, textures: {
    colorMap: string?,       -- ColorMap (Albedo) texture ID
    normalMap: string?,      -- NormalMap texture ID
    metalMap: string?,       -- MetalnessMap texture ID
    roughnessMap: string?,   -- RoughnessMap texture ID
}): SurfaceAppearance
    -- Remove existing SurfaceAppearance
    local existing = part:FindFirstChildOfClass("SurfaceAppearance")
    if existing then existing:Destroy() end

    local sa = Instance.new("SurfaceAppearance")

    if textures.colorMap then
        sa.ColorMap = textures.colorMap
    end
    if textures.normalMap then
        sa.NormalMap = textures.normalMap
    end
    if textures.metalMap then
        sa.MetalnessMap = textures.metalMap
    end
    if textures.roughnessMap then
        sa.RoughnessMap = textures.roughnessMap
    end

    sa.Parent = part
    return sa
end
```

### PBR with MaterialVariant
```lua
local function createMaterialVariant(config: {
    name: string,
    baseMaterial: Enum.Material,
    colorMap: string?,
    normalMap: string?,
    metalnessMap: string?,
    roughnessMap: string?,
    studsPerTile: number?,
}): MaterialVariant
    local MaterialService = game:GetService("MaterialService")

    local variant = Instance.new("MaterialVariant")
    variant.Name = config.name
    variant.BaseMaterial = config.baseMaterial

    if config.colorMap then variant.ColorMap = config.colorMap end
    if config.normalMap then variant.NormalMap = config.normalMap end
    if config.metalnessMap then variant.MetalnessMap = config.metalnessMap end
    if config.roughnessMap then variant.RoughnessMap = config.roughnessMap end
    if config.studsPerTile then variant.StudsPerTile = config.studsPerTile end

    variant.Parent = MaterialService
    return variant
end

-- Apply a MaterialVariant to a part
local function applyMaterialVariant(part: BasePart, variantName: string)
    part.MaterialVariant = variantName
end
```

## MCP generate_material Usage

When using the MCP tool to generate materials, call it like this:

```lua
-- The MCP generate_material tool creates PBR textures procedurally.
-- Use via the mcp__roblox-mcp__generate_material tool call with parameters:
-- prompt: A descriptive text for the material (e.g. "worn medieval stone wall with moss")
-- materialType: The base Enum.Material to use
-- resolution: Texture resolution (256, 512, 1024)

-- After generation, apply the returned texture IDs:
local generatedTextures = {
    colorMap = "rbxassetid://GENERATED_COLOR_MAP_ID",
    normalMap = "rbxassetid://GENERATED_NORMAL_MAP_ID",
    metalMap = "rbxassetid://GENERATED_METAL_MAP_ID",
    roughnessMap = "rbxassetid://GENERATED_ROUGHNESS_MAP_ID",
}
applyPBR(targetPart, generatedTextures)
```

## Utility: Apply Material to Model

```lua
local function applyMaterialToModel(model: Model, material: Enum.Material, color: Color3?)
    for _, part in ipairs(model:GetDescendants()) do
        if part:IsA("BasePart") then
            part.Material = material
            if color then
                part.Color = color
            end
        end
    end
end
```

## Utility: Set Transparency and Reflectance

```lua
local function setPartAppearance(part: BasePart, config: {
    material: Enum.Material?,
    color: Color3?,
    transparency: number?,
    reflectance: number?,
})
    if config.material then part.Material = config.material end
    if config.color then part.Color = config.color end
    if config.transparency then part.Transparency = config.transparency end
    if config.reflectance then part.Reflectance = config.reflectance end
end
```

## 

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

- `theme`: "medieval" | "scifi" | "horror" | "modern" | "fantasy" -- 테마별 재질 조합
- `material`: string -- Enum.Material 이름 (예: "Brick", "Wood", "Metal")
- `color`: {r: number, g: number, b: number} -- 재질 색상 RGB
- `pbr`: { colorMap: string?, normalMap: string?, metalMap: string?, roughnessMap: string? } -- PBR 텍스처 ID
- `target`: string -- 적용 대상 (모델명 또는 파트명)
- `generatePrompt`: string -- MCP generate_material 프롬프트
