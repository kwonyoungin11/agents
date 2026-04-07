# Roblox Engine - Claude Code Instructions

You are controlling Roblox Studio via MCP to build games and experiences. Follow these rules strictly to ensure accurate coordinate placement, high-quality VFX, and maintained context across interactions.

---

## MASTER RULES (모든 작업에 적용, 절대 위반 금지)

### Rule A: 200% 스케일 사고
사용자가 X를 요청하면, X만 만들지 말고 X가 자연스럽게 존재하기 위한 부수적 요소도 함께 구현하라.
- "횃불 배치해줘" → 횃불 + 불 이펙트 + 벽 그림자 + 주변 조명 변화
- "NPC 만들어줘" → NPC + 대기 애니메이션 + 감지 범위 + 대화 시스템 기본 틀
- "방 만들어줘" → 방 + 바닥 재질 + 조명 + 분위기 연출 + 문/입구

### Rule B: 기존 작업 인식 (절대 잊지 말 것)
새로운 것을 만들기 전에 반드시:
1. `SessionManager.getRestorationReport()` 실행 — 이전에 뭘 만들었는지 확인
2. `ContextTracker.scanWorkspace()` 실행 — 현재 워크스페이스 상태 확인
3. 이전에 만든 것과 **조화**를 이루도록 설계 (스타일, 크기, 재질, 색상, 위치)
4. 이전 구조물 근처에 배치할 때는 반드시 기존 좌표를 읽고 상대 배치

**절대 이전 작업을 무시하고 독립적으로 만들지 마라. 모든 것은 하나의 세계관 안에서 연결된다.**

### Rule C: 단계별 제작 + 검증
하나를 만들 때마다:
1. **계획** — 무엇을 어디에 어떤 크기로 만들지 먼저 출력
2. **실행** — run_code로 배치
3. **검증** — screen_capture로 시각적 확인 또는 좌표 읽어서 오차 확인
4. **기록** — SessionManager에 로그
5. **다음 단계** — 검증 통과 후에만 다음 단계 진행

한 번에 대량으로 만들지 말고, 단계별로 확인하면서 진행.

### Rule D: 에이전트 옵시디언 구조 (그래프 네트워크)

모든 에이전트는 **노드**로 존재하며, 서로 자유롭게 연결된다. 고정 계층이 아니라, 요청에 따라 최적의 팀이 동적으로 구성된다.

```
                          ┌─────────────────────────────────────────────────┐
                          │              DIRECTOR (라우터)                   │
                          └────────┬──────────────┬─────────────┬──────────┘
                                   │              │             │
          ┌────────────────────────┼──────────────┼─────────────┼────────────────┐
          │                        │              │             │                │
  ┌───────▼────────┐    ┌─────────▼──────┐  ┌────▼─────┐  ┌───▼────┐   ┌───────▼───────┐
  │  WORLD CLUSTER  │    │ SYSTEM CLUSTER │  │ UI/UX    │  │ META   │   │ PLAYER ACTION │
  │                │    │                │  │ CLUSTER  │  │CLUSTER │   │   CLUSTER     │
  └───────┬────────┘    └────────┬───────┘  └────┬─────┘  └───┬────┘   └───────┬───────┘
          │                      │               │            │                │
 architect─terrain        scripter─combat       ui─hud     gamedesign    dash─double-jump
 lighting─materials      inventory─quest    menu-system    testing       wall-jump─grapple
 weather─water           dialog─shop        minimap        security      zipline─obby
 vegetation─props        crafting─leveling  notification   skill-evolve  checkpoint─trap
 doors─stairs            npc-ai─spawn       tooltip        analytics     elevator─racing
 interior─decals         character─morph    damage-ind     localization  vehicle─projectile
 mesh─color-palette      physics─ragdoll    settings-menu  accessibility destruction─boss
 surface-gui─billboard   destruction─boss   leaderboard    replay        puzzle─round-system
 vfx─tween-fx           datastore─network  loading─mobile  screenshot   wave─spectator
 audio─cutscene          team─trading       tutorial        marketplace  pet─building-system
 camera─constraint       achievement─daily  billboard-gui   social       fishing─farming
 proximity─viewport-fx   monetization       surface-gui     badge        stamina─mana
                         health-regen─mana  gamepad         teleport     health-regen─emote
                         stamina─emote      touch-input     matchmaking  dance─sit-system
                         collision-group    viewport-fx     server-hop
                         tag-system─attr                    chat-system
                         replication                        anti-exploit
                         instance-pool                      debris-cleanup
```

**113개 스킬 에이전트** — 모든 노드가 옵시디언처럼 자유롭게 연결. 요청에 따라 최적의 팀 동적 구성.

**DIRECTOR는 라우터** — 요청을 분석하고 그래프에서 관련 노드들을 활성화.

**전체 스킬 카탈로그 (113개):**

| 클러스터 | 스킬 목록 |
|---|---|
| **월드 구축** | architect, terrain, lighting, materials, weather, water, vegetation, props, doors, stairs, interior, decals, mesh, color-palette |
| **시각 연출** | vfx, tween-fx, surface-gui, billboard-gui, viewport-fx, cutscene, camera |
| **사운드** | audio |
| **캐릭터** | character, morph, emote, dance, sit-system, animation |
| **전투/액션** | combat, projectile, destruction, ragdoll, boss, wave |
| **게임 시스템** | scripter, inventory, quest, dialog, shop, crafting, leveling, npc-ai, spawn |
| **물리/이동** | physics, vehicle, dash-system, double-jump, wall-jump, grapple, zipline, elevator-system, constraint-build |
| **레벨 디자인** | obby, puzzle, trap, checkpoint, round-system, spectator, racing, pet, building-system, farming, fishing |
| **UI/UX** | ui, hud, menu-system, minimap, notification, tooltip, damage-indicator, settings-menu, leaderboard-ui, loading, tutorial, mobile, touch-input, gamepad |
| **데이터/경제** | datastore, network, replication, monetization, daily-reward, trading, achievement, badge |
| **인프라** | security, anti-exploit, collision-group, tag-system, attribute-system, instance-pool, debris-cleanup |
| **소셜/멀티** | team, social, chat-system, matchmaking, server-hop, teleport |
| **메타** | director, gamedesign, testing, skill-evolve, analytics, localization, accessibility, replay, screenshot, marketplace, health-regen, mana-system, stamina |

**자동 트리거: 사용자의 자연어 키워드 → 관련 스킬 자동 발동. 복합 요청 → 여러 스킬 병렬 실행.**

**모든 스킬에 자기발전(Learned Lessons + Self-Evolution Protocol) 내장.**

### Rule E: 자기발전 시스템

실수가 발생하면:
1. 에러 원인 분석
2. `/skill-evolve` 발동
3. 해당 스킬 파일의 `## Learned Lessons` 섹션에 교훈 추가
4. 같은 실수 절대 반복 금지
5. SessionManager에 에러 + 학습 내용 기록
6. 하위 에이전트도 자체 개선 가능 — 세부 스킬을 자기 판단으로 발전

### Rule F: 더 좋은 방향 적극 제시

사용자가 요청하면:
1. 요청대로 실행 + 더 나은 대안이 있으면 적극 제안
2. 단, **실제 구현 가능한 것만** 제안
3. 개념적/이론적 제안 금지 — 바로 코드로 만들 수 있는 것만
4. Roblox 최신 기술 적극 활용 (generate_mesh, screen_capture 등)

### Rule G: 극히 사실적 구현

- 개념도, 설명서가 아니라 **실행 가능한 코드** 생성
- "~하면 좋겠다" 수준이 아니라 "이 코드를 run_code로 실행하면 바로 동작" 수준
- 모든 스킬의 코드는 Roblox Studio에서 즉시 실행 가능해야 함

---

## MCP Servers Available

- **roblox-builtin**: `run_code`, `insert_model`, `generate_mesh`, `generate_material`, `screen_capture`, `start_stop_play`, `get_console_output`, `run_script_in_play_mode`
- **robloxstudio-mcp**: 39+ tools for instance inspection, property read/write, hierarchy navigation, bulk operations

## Session Startup Protocol

At the beginning of EVERY session, run the Engine Bootstrap:

1. Inject all engine modules via `run_code` (use the code from `src/init/EngineBootstrap.luau`)
2. Run SessionManager.getRestorationReport() to restore previous build context
3. Run a workspace context scan to understand existing state
4. Print restoration report to understand what was built before

If this is a CONTINUING session (modules already injected), skip step 1 and just run the restoration report.

## Long Session Management Protocol (CRITICAL)

### Every Build Action Must Be Logged

After EVERY creation/modification, record it:

```lua
local SM = require(game.ServerStorage._RobloxEngine.SessionManager)
SM.logAction("CREATED_ROOM", "Dungeon Room 1 at (0,10,0) size 20x10x20")
SM.registerBuild("Rooms", "DungeonRoom1", {
    position = {0, 10, 0},
    size = {20, 10, 20},
    status = "complete",
    description = "Main dungeon entrance room with stone walls"
})
```

### Design Decisions Must Be Documented

When the user describes game design intent, save it:

```lua
SM.updateDesignDoc("GameGenre", "Horror dungeon crawler with VFX-heavy atmosphere")
SM.updateDesignDoc("CoreMechanics", "Exploration, puzzle solving, combat with magic effects")
SM.updateDesignDoc("ArtStyle", "Dark stone dungeon, neon magic effects, cinematic lighting")
```

### Checkpoints Before Major Changes

Before starting a new major section, create a checkpoint:

```lua
SM.createCheckpoint("PreBossRoom", "Before building the boss arena")
```

### Session Restoration

When a new conversation starts or context is compressed, ALWAYS run:

```lua
local SM = require(game.ServerStorage._RobloxEngine.SessionManager)
print(SM.getRestorationReport())
```

This prints: design doc, build manifest, recent actions, workspace summary.
Claude can then understand the full project state even without prior conversation history.
3. Print a summary of what exists in workspace

If modules are already injected (check for `_RobloxEngine` in ServerStorage), skip injection and just run the context scan.

---

## COORDINATE ALIGNMENT PROTOCOL (CRITICAL)

### Rule 1: ALWAYS Read Before Write

Before placing ANY object, ALWAYS read the positions and sizes of nearby/related objects first:

```lua
-- WRONG: Guessing coordinates
local part = Instance.new("Part")
part.Position = Vector3.new(10, 5, 0) -- Where did these numbers come from?

-- RIGHT: Reading existing state first
local existingWall = workspace:FindFirstChild("Wall1")
local wallPos = existingWall.Position
local wallSize = existingWall.Size
-- Now calculate relative to known positions
local part = Instance.new("Part")
part.Position = wallPos + Vector3.new(wallSize.X/2 + part.Size.X/2, 0, 0)
```

### Rule 2: Use Relative Positioning (CFrame Math)

NEVER use absolute coordinates unless placing the FIRST object. Always position relative to existing objects:

```lua
-- Place object relative to another
local anchor = workspace.MainBuilding
local newPart = Instance.new("Part")
newPart.CFrame = anchor.CFrame * CFrame.new(5, 0, 0) -- 5 studs to the right of anchor
```

### Rule 3: Size-Aware Adjacent Placement

When placing objects next to each other, account for BOTH objects' sizes:

```lua
-- Adjacent placement formula:
-- newPos = existingPos + (existingSize/2 + newSize/2) * directionVector
local function placeAdjacent(existing, newPart, face)
    local dir = Vector3.new(0, 0, 0)
    if face == "Right" then dir = Vector3.new(1, 0, 0)
    elseif face == "Left" then dir = Vector3.new(-1, 0, 0)
    elseif face == "Top" then dir = Vector3.new(0, 1, 0)
    elseif face == "Bottom" then dir = Vector3.new(0, -1, 0)
    elseif face == "Front" then dir = Vector3.new(0, 0, -1)
    elseif face == "Back" then dir = Vector3.new(0, 0, 1)
    end
    
    local offset = (existing.Size/2 + newPart.Size/2) * dir
    newPart.CFrame = existing.CFrame * CFrame.new(offset.X, offset.Y, offset.Z)
end
```

### Rule 4: Grid Snapping

When building structures, snap to a consistent grid:

```lua
local GRID_SIZE = 1 -- 1 stud grid
local function snapToGrid(pos)
    return Vector3.new(
        math.round(pos.X / GRID_SIZE) * GRID_SIZE,
        math.round(pos.Y / GRID_SIZE) * GRID_SIZE,
        math.round(pos.Z / GRID_SIZE) * GRID_SIZE
    )
end
```

### Rule 5: Validate After Placement

After EVERY placement operation, read back the position and verify:

```lua
local part = Instance.new("Part")
part.Parent = workspace
part.CFrame = targetCFrame
part.Anchored = true

-- Validate
local actual = part.Position
local expected = targetCFrame.Position
local error = (actual - expected).Magnitude
if error > 0.01 then
    warn("Placement error: " .. error .. " studs off")
end
print("Placed at: " .. tostring(part.Position) .. " (error: " .. error .. ")")
```

### Rule 6: Use Named Anchors for Complex Builds

For multi-step builds, create invisible anchor points as references:

```lua
local function createAnchor(name, position)
    local anchor = Instance.new("Part")
    anchor.Name = "_Anchor_" .. name
    anchor.Size = Vector3.new(0.1, 0.1, 0.1)
    anchor.Transparency = 1
    anchor.CanCollide = false
    anchor.Anchored = true
    anchor.Position = position
    anchor.Parent = workspace._RobloxEngine_Anchors
    return anchor
end
```

### Rule 7: Wall/Floor/Ceiling Construction

For room construction, use consistent formulas:

```lua
-- Room parameters
local roomCenter = Vector3.new(0, 5, 0)
local roomWidth = 20   -- X axis
local roomHeight = 10  -- Y axis
local roomDepth = 20   -- Z axis
local wallThickness = 1

-- Floor
floor.Size = Vector3.new(roomWidth, wallThickness, roomDepth)
floor.Position = roomCenter - Vector3.new(0, roomHeight/2 - wallThickness/2, 0)

-- Ceiling
ceiling.Size = Vector3.new(roomWidth, wallThickness, roomDepth)
ceiling.Position = roomCenter + Vector3.new(0, roomHeight/2 - wallThickness/2, 0)

-- Left wall
leftWall.Size = Vector3.new(wallThickness, roomHeight, roomDepth)
leftWall.Position = roomCenter - Vector3.new(roomWidth/2 - wallThickness/2, 0, 0)

-- Right wall
rightWall.Size = Vector3.new(wallThickness, roomHeight, roomDepth)
rightWall.Position = roomCenter + Vector3.new(roomWidth/2 - wallThickness/2, 0, 0)
```

---

## CONTEXT MAINTENANCE PROTOCOL

### Rule 1: Scan Before Modifying

Before ANY modification to existing objects, run a context scan:

```lua
local function scanWorkspace(parent, indent)
    indent = indent or ""
    local result = {}
    for _, child in ipairs(parent:GetChildren()) do
        if child:IsA("BasePart") then
            table.insert(result, indent .. child.Name 
                .. " [" .. child.ClassName .. "]"
                .. " Pos:" .. tostring(child.Position)
                .. " Size:" .. tostring(child.Size)
                .. " CFrame:" .. tostring(child.CFrame))
        elseif child:IsA("Model") then
            table.insert(result, indent .. child.Name .. " [Model]")
            local sub = scanWorkspace(child, indent .. "  ")
            for _, s in ipairs(sub) do table.insert(result, s) end
        end
    end
    return result
end
local results = scanWorkspace(workspace)
print(table.concat(results, "\n"))
```

### Rule 2: State Persistence

Store build context in ServerStorage so it persists:

```lua
local function saveContext(key, data)
    local storage = game:GetService("ServerStorage")
    local engineFolder = storage:FindFirstChild("_RobloxEngine") 
        or Instance.new("Folder", storage)
    engineFolder.Name = "_RobloxEngine"
    
    local contextObj = engineFolder:FindFirstChild("_Context")
        or Instance.new("StringValue", engineFolder)
    contextObj.Name = "_Context"
    
    local existing = contextObj.Value ~= "" 
        and game:GetService("HttpService"):JSONDecode(contextObj.Value) 
        or {}
    existing[key] = data
    contextObj.Value = game:GetService("HttpService"):JSONEncode(existing)
end
```

### Rule 3: Reference Point System

For complex builds, maintain a reference point system:
- Create `_RobloxEngine_Anchors` folder in workspace
- Place named invisible anchors at key locations (room corners, structure origins, etc.)
- Always reference anchors when calculating new positions
- This prevents coordinate drift across multiple operations

---

## VFX TECHNIQUES REFERENCE

### Particle Systems

```lua
-- High-quality fire effect
local function createFire(parent)
    local attachment = Instance.new("Attachment", parent)
    local emitter = Instance.new("ParticleEmitter")
    emitter.Rate = 100
    emitter.Lifetime = NumberRange.new(0.5, 1.5)
    emitter.Speed = NumberRange.new(3, 8)
    emitter.SpreadAngle = Vector2.new(15, 15)
    emitter.EmissionDirection = Enum.NormalId.Top
    emitter.LightEmission = 1
    emitter.LightInfluence = 0
    emitter.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1),
        NumberSequenceKeypoint.new(0.3, 2.5),
        NumberSequenceKeypoint.new(1, 0)
    })
    emitter.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.3),
        NumberSequenceKeypoint.new(0.8, 0.8),
        NumberSequenceKeypoint.new(1, 1)
    })
    emitter.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 200, 50)),
        ColorSequenceKeypoint.new(0.4, Color3.fromRGB(255, 100, 20)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(100, 20, 0))
    })
    emitter.Acceleration = Vector3.new(0, 2, 0)
    emitter.RotSpeed = NumberRange.new(-90, 90)
    emitter.Parent = attachment
    return emitter
end
```

### Beam Effects

```lua
-- Energy beam between two points
local function createBeam(partA, partB, config)
    config = config or {}
    local att0 = Instance.new("Attachment", partA)
    local att1 = Instance.new("Attachment", partB)
    
    local beam = Instance.new("Beam")
    beam.Attachment0 = att0
    beam.Attachment1 = att1
    beam.Width0 = config.width or 2
    beam.Width1 = config.width or 2
    beam.LightEmission = config.lightEmission or 1
    beam.LightInfluence = config.lightInfluence or 0
    beam.TextureSpeed = config.textureSpeed or 1
    beam.TextureLength = config.textureLength or 1
    beam.FaceCamera = true
    beam.Segments = config.segments or 10
    beam.CurveSize0 = config.curveSize or 0
    beam.CurveSize1 = config.curveSize or 0
    beam.Color = ColorSequence.new(config.color or Color3.fromRGB(100, 180, 255))
    beam.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.2),
        NumberSequenceKeypoint.new(0.5, 0),
        NumberSequenceKeypoint.new(1, 0.2)
    })
    beam.Parent = partA
    return beam, att0, att1
end
```

### Lightning Effect (Advanced)

```lua
-- Procedural lightning between two points
local function createLightning(origin, target, config)
    config = config or {}
    local segments = config.segments or 12
    local jitter = config.jitter or 3
    local thickness = config.thickness or 0.3
    local color = config.color or Color3.fromRGB(150, 200, 255)
    
    local folder = Instance.new("Folder")
    folder.Name = "_Lightning"
    
    local direction = (target - origin)
    local length = direction.Magnitude
    local step = direction / segments
    
    local points = {origin}
    for i = 1, segments - 1 do
        local basePoint = origin + step * i
        local offset = Vector3.new(
            (math.random() - 0.5) * jitter,
            (math.random() - 0.5) * jitter,
            (math.random() - 0.5) * jitter
        )
        table.insert(points, basePoint + offset)
    end
    table.insert(points, target)
    
    for i = 1, #points - 1 do
        local p1 = points[i]
        local p2 = points[i + 1]
        local mid = (p1 + p2) / 2
        local dist = (p2 - p1).Magnitude
        
        local part = Instance.new("Part")
        part.Size = Vector3.new(thickness, thickness, dist)
        part.CFrame = CFrame.lookAt(mid, p2)
        part.Material = Enum.Material.Neon
        part.Color = color
        part.Anchored = true
        part.CanCollide = false
        part.CastShadow = false
        
        -- Add point light at each segment
        if i % 3 == 1 then
            local light = Instance.new("PointLight")
            light.Color = color
            light.Brightness = 2
            light.Range = 8
            light.Parent = part
        end
        
        part.Parent = folder
    end
    
    folder.Parent = workspace
    return folder
end
```

### Trail System

```lua
-- Motion trail for moving parts
local function createTrail(part, config)
    config = config or {}
    local att0 = Instance.new("Attachment", part)
    att0.Position = Vector3.new(0, 0, -part.Size.Z/2)
    local att1 = Instance.new("Attachment", part)
    att1.Position = Vector3.new(0, 0, part.Size.Z/2)
    
    local trail = Instance.new("Trail")
    trail.Attachment0 = att0
    trail.Attachment1 = att1
    trail.Lifetime = config.lifetime or 1
    trail.MinLength = config.minLength or 0.1
    trail.FaceCamera = true
    trail.LightEmission = config.lightEmission or 0.5
    trail.Color = ColorSequence.new(config.color or Color3.fromRGB(255, 255, 255))
    trail.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0),
        NumberSequenceKeypoint.new(1, 1)
    })
    trail.WidthScale = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1),
        NumberSequenceKeypoint.new(1, 0)
    })
    trail.Parent = part
    return trail
end
```

### Lighting & Atmosphere

```lua
-- Dramatic cinematic lighting setup
local function setupCinematicLighting(config)
    config = config or {}
    local lighting = game:GetService("Lighting")
    
    lighting.Technology = Enum.Technology.Future
    lighting.Ambient = config.ambient or Color3.fromRGB(30, 30, 40)
    lighting.OutdoorAmbient = config.outdoorAmbient or Color3.fromRGB(50, 50, 60)
    lighting.Brightness = config.brightness or 2
    lighting.ClockTime = config.clockTime or 14
    lighting.GeographicLatitude = config.latitude or 40
    
    -- Bloom
    local bloom = lighting:FindFirstChildOfClass("BloomEffect") 
        or Instance.new("BloomEffect", lighting)
    bloom.Intensity = config.bloomIntensity or 0.5
    bloom.Size = config.bloomSize or 24
    bloom.Threshold = config.bloomThreshold or 0.8
    
    -- Color correction
    local cc = lighting:FindFirstChildOfClass("ColorCorrectionEffect")
        or Instance.new("ColorCorrectionEffect", lighting)
    cc.Brightness = config.ccBrightness or 0.05
    cc.Contrast = config.ccContrast or 0.1
    cc.Saturation = config.ccSaturation or 0.2
    cc.TintColor = config.tintColor or Color3.fromRGB(255, 245, 230)
    
    -- Sun rays
    local sunRays = lighting:FindFirstChildOfClass("SunRaysEffect")
        or Instance.new("SunRaysEffect", lighting)
    sunRays.Intensity = config.sunRaysIntensity or 0.15
    sunRays.Spread = config.sunRaysSpread or 0.5
    
    -- Atmosphere
    local atmo = lighting:FindFirstChildOfClass("Atmosphere")
        or Instance.new("Atmosphere", lighting)
    atmo.Density = config.atmoDensity or 0.3
    atmo.Offset = config.atmoOffset or 0.25
    atmo.Color = config.atmoColor or Color3.fromRGB(199, 199, 210)
    atmo.Decay = config.atmoDecay or Color3.fromRGB(92, 100, 120)
    atmo.Glare = config.atmoGlare or 0.5
    atmo.Haze = config.atmoHaze or 1.5
    
    -- Depth of field
    local dof = lighting:FindFirstChildOfClass("DepthOfFieldEffect")
        or Instance.new("DepthOfFieldEffect", lighting)
    dof.FarIntensity = config.dofFar or 0.2
    dof.FocusDistance = config.dofFocus or 50
    dof.InFocusRadius = config.dofRadius or 30
    dof.NearIntensity = config.dofNear or 0.5
    
    print("Cinematic lighting configured")
    return lighting
end
```

### Neon Glow Effect

```lua
-- Neon glow on any part
local function setupNeonGlow(part, color, intensity)
    color = color or Color3.fromRGB(0, 170, 255)
    intensity = intensity or 2
    
    part.Material = Enum.Material.Neon
    part.Color = color
    
    local light = Instance.new("PointLight")
    light.Color = color
    light.Brightness = intensity
    light.Range = math.max(part.Size.X, part.Size.Y, part.Size.Z) * 3
    light.Parent = part
    
    -- Optional outer glow with billboard
    local billboard = Instance.new("BillboardGui")
    billboard.Size = UDim2.new(
        part.Size.X * 2, 0,
        part.Size.Y * 2, 0
    )
    billboard.StudsOffset = Vector3.new(0, 0, 0)
    billboard.LightInfluence = 0
    billboard.AlwaysOnTop = false
    
    local glow = Instance.new("ImageLabel")
    glow.Size = UDim2.new(1, 0, 1, 0)
    glow.BackgroundTransparency = 1
    glow.ImageColor3 = color
    glow.ImageTransparency = 0.5
    glow.Image = "rbxassetid://6238537240" -- radial gradient
    glow.Parent = billboard
    billboard.Parent = part
    
    return light
end
```

### Composite Effects

```lua
-- Portal effect (ring + particles + beams + lighting)
local function createPortal(position, config)
    config = config or {}
    local size = config.size or 8
    local color = config.color or Color3.fromRGB(100, 50, 255)
    
    local model = Instance.new("Model")
    model.Name = config.name or "Portal"
    
    -- Ring
    local ring = Instance.new("Part")
    ring.Shape = Enum.PartType.Cylinder
    ring.Size = Vector3.new(0.5, size, size)
    ring.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
    ring.Material = Enum.Material.Neon
    ring.Color = color
    ring.Anchored = true
    ring.CanCollide = false
    ring.Parent = model
    
    -- Inner glow
    local inner = ring:Clone()
    inner.Size = Vector3.new(0.3, size * 0.85, size * 0.85)
    inner.Transparency = 0.3
    inner.Color = Color3.new(1, 1, 1)
    inner.Parent = model
    inner.CFrame = ring.CFrame
    
    -- Particles around ring
    local att = Instance.new("Attachment", ring)
    local particles = Instance.new("ParticleEmitter")
    particles.Rate = 50
    particles.Speed = NumberRange.new(1, 3)
    particles.Lifetime = NumberRange.new(0.5, 1.5)
    particles.SpreadAngle = Vector2.new(360, 360)
    particles.LightEmission = 1
    particles.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.5),
        NumberSequenceKeypoint.new(1, 0)
    })
    particles.Color = ColorSequence.new(color)
    particles.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0),
        NumberSequenceKeypoint.new(1, 1)
    })
    particles.Parent = att
    
    -- Point light
    local light = Instance.new("PointLight")
    light.Color = color
    light.Brightness = 3
    light.Range = size * 2
    light.Parent = ring
    
    model.Parent = workspace
    return model
end
```

### TweenService for Animated VFX

```lua
-- Smooth pulsating effect
local function pulseEffect(part, config)
    config = config or {}
    local TweenService = game:GetService("TweenService")
    local originalSize = part.Size
    local scale = config.scale or 1.2
    local duration = config.duration or 1
    
    local tweenInfo = TweenInfo.new(
        duration,
        Enum.EasingStyle.Sine,
        Enum.EasingDirection.InOut,
        -1, -- repeat forever
        true -- reverse
    )
    
    local tween = TweenService:Create(part, tweenInfo, {
        Size = originalSize * scale,
        Transparency = config.maxTransparency or 0.3
    })
    tween:Play()
    return tween
end
```

---

## MCP INTERACTION RULES

### Error Handling

Always wrap `run_code` operations in pcall:

```lua
local success, result = pcall(function()
    -- your code here
end)

if success then
    print("SUCCESS: " .. tostring(result))
else
    print("ERROR: " .. tostring(result))
end
```

### Output Requirements

Every `run_code` call MUST `print()` its results. The MCP only returns printed output.

### Complex Operations

For operations requiring multiple steps:
1. First inject helper modules via EngineBootstrap
2. Then call module functions in subsequent `run_code` calls
3. Verify results with `screen_capture` after visual changes

### Batch Operations

When creating many objects, do it in a single `run_code` call to avoid context loss:

```lua
-- Create 10 pillars in a row
local pillars = {}
for i = 1, 10 do
    local pillar = Instance.new("Part")
    pillar.Size = Vector3.new(2, 10, 2)
    pillar.Position = Vector3.new(i * 4, 5, 0) -- 4-stud spacing
    pillar.Anchored = true
    pillar.Material = Enum.Material.Concrete
    pillar.Parent = workspace
    table.insert(pillars, pillar)
end
print("Created " .. #pillars .. " pillars")
```

---

## COMMON PATTERNS

### Building a Room

```lua
local function buildRoom(center, width, height, depth, wallThick, material)
    wallThick = wallThick or 1
    material = material or Enum.Material.SmoothPlastic
    local parts = {}
    
    local function makePart(name, size, pos)
        local p = Instance.new("Part")
        p.Name = name
        p.Size = size
        p.Position = pos
        p.Anchored = true
        p.Material = material
        p.Parent = workspace
        table.insert(parts, p)
        return p
    end
    
    makePart("Floor", 
        Vector3.new(width, wallThick, depth),
        center - Vector3.new(0, height/2 - wallThick/2, 0))
    makePart("Ceiling", 
        Vector3.new(width, wallThick, depth),
        center + Vector3.new(0, height/2 - wallThick/2, 0))
    makePart("WallLeft", 
        Vector3.new(wallThick, height - wallThick*2, depth),
        center - Vector3.new(width/2 - wallThick/2, 0, 0))
    makePart("WallRight", 
        Vector3.new(wallThick, height - wallThick*2, depth),
        center + Vector3.new(width/2 - wallThick/2, 0, 0))
    makePart("WallFront", 
        Vector3.new(width, height - wallThick*2, wallThick),
        center - Vector3.new(0, 0, depth/2 - wallThick/2))
    makePart("WallBack", 
        Vector3.new(width, height - wallThick*2, wallThick),
        center + Vector3.new(0, 0, depth/2 - wallThick/2))
    
    print("Room created: " .. #parts .. " parts at " .. tostring(center))
    return parts
end
```

### Placing Furniture Along a Wall

```lua
local function placeFurnitureAlongWall(wall, items, spacing)
    local wallCF = wall.CFrame
    local wallSize = wall.Size
    local startOffset = -wallSize.Z/2 + spacing
    
    for i, itemConfig in ipairs(items) do
        local item = Instance.new("Part")
        item.Name = itemConfig.name
        item.Size = itemConfig.size
        item.Anchored = true
        
        -- Calculate position relative to wall inner face
        local zOffset = startOffset + (i - 1) * spacing
        local yOffset = -wallSize.Y/2 + item.Size.Y/2  -- sit on floor level relative to wall
        local xOffset = wallSize.X/2 + item.Size.X/2    -- pushed against wall face
        
        item.CFrame = wallCF * CFrame.new(-xOffset, yOffset, zOffset)
        item.Parent = workspace
    end
end
```

---

## IMPORTANT REMINDERS

1. **NEVER guess coordinates** — always calculate from known positions
2. **ALWAYS anchor parts** unless they need physics
3. **Use Models** to group related parts — easier to move as a unit
4. **Name everything** — makes context scanning useful
5. **Verify with screen_capture** — visual confirmation after complex builds
6. **Use PrimaryPart** on Models for accurate model positioning
7. **CFrame multiplication order matters** — `baseCFrame * offset` not `offset * baseCFrame`
8. **NumberSequence keypoints** must start at time=0 and end at time=1
9. **ColorSequence keypoints** must start at time=0 and end at time=1
10. **Parent last** — set all properties before setting Parent to avoid unnecessary replication
