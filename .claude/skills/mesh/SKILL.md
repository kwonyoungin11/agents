---
name: mesh
description: |
  MCP generate_mesh 도구 활용, 텍스트-투-3D 메시 생성, MeshPart 속성 설정, 메시 스케일링, 메시 VFX 이펙트.
  Text-to-3D mesh generation using MCP tools, MeshPart configuration, mesh scaling, collision fidelity, mesh-based VFX and particle attachment.
allowed-tools:
  - Bash
  - Edit
  - Write
  - Read
  - Glob
  - Grep
  - WebFetch
  - WebSearch
  - mcp: generate_mesh
effort: high
---

# Mesh Generation & MeshPart System

This skill covers text-to-3D mesh generation via the MCP `generate_mesh` tool, MeshPart property configuration, mesh scaling best practices, collision fidelity settings, and mesh-based VFX techniques in Roblox.

---

## 1. MCP generate_mesh Tool Usage

Use the MCP `generate_mesh` tool to create 3D meshes from text descriptions. The tool returns a mesh asset that can be applied to a MeshPart.

### Workflow

1. Call `generate_mesh` with a descriptive prompt
2. Receive the mesh asset ID
3. Create a MeshPart in the workspace and assign the mesh ID
4. Configure physical and visual properties

### Prompt Best Practices

- Be specific: "a medieval iron sword with leather-wrapped handle" not "sword"
- Include style: "low-poly", "stylized", "realistic", "cartoon"
- Mention topology needs: "game-ready, under 5000 triangles"
- Specify orientation: "facing forward along Z-axis"

---

## 2. MeshPart Creation & Properties

```luau
--!strict
-- ServerScript: MeshPart factory with full property configuration

local ServerStorage = game:GetService("ServerStorage")

export type MeshPartConfig = {
    meshId: string,
    position: Vector3?,
    size: Vector3?,
    material: Enum.Material?,
    color: Color3?,
    anchored: boolean?,
    canCollide: boolean?,
    collisionFidelity: Enum.CollisionFidelity?,
    renderFidelity: Enum.RenderFidelity?,
    doubleSided: boolean?,
    parent: Instance?,
}

local MeshFactory = {}

--- Creates a fully configured MeshPart from a config table.
function MeshFactory.create(config: MeshPartConfig): MeshPart
    local meshPart = Instance.new("MeshPart")
    meshPart.MeshId = config.meshId
    meshPart.Size = config.size or Vector3.new(4, 4, 4)
    meshPart.Position = config.position or Vector3.new(0, 5, 0)
    meshPart.Material = config.material or Enum.Material.SmoothPlastic
    meshPart.Color = config.color or Color3.fromRGB(200, 200, 200)
    meshPart.Anchored = if config.anchored ~= nil then config.anchored else true
    meshPart.CanCollide = if config.canCollide ~= nil then config.canCollide else true

    -- Collision fidelity: Box (fastest), Hull, Default, PreciseConvexDecomposition (most accurate)
    meshPart.CollisionFidelity = config.collisionFidelity or Enum.CollisionFidelity.Default
    meshPart.RenderFidelity = config.renderFidelity or Enum.RenderFidelity.Automatic
    meshPart.DoubleSided = config.doubleSided or false

    meshPart.Parent = config.parent or workspace
    return meshPart
end

--- Creates a MeshPart with physics enabled (unanchored with mass properties).
function MeshFactory.createPhysics(config: MeshPartConfig, density: number?, friction: number?, elasticity: number?): MeshPart
    local meshPart = MeshFactory.create(config)
    meshPart.Anchored = false

    local physProperties = PhysicalProperties.new(
        density or 1.0,
        friction or 0.3,
        elasticity or 0.5
    )
    meshPart.CustomPhysicalProperties = physProperties

    return meshPart
end

return MeshFactory
```

---

## 3. Mesh Scaling System

```luau
--!strict
-- ModuleScript: Advanced mesh scaling with proportion preservation

local TweenService = game:GetService("TweenService")

local MeshScaler = {}

--- Uniformly scales a MeshPart while preserving aspect ratio.
function MeshScaler.scaleUniform(meshPart: MeshPart, scaleFactor: number)
    meshPart.Size = meshPart.Size * scaleFactor
end

--- Scales a MeshPart to fit within a bounding box while keeping proportions.
function MeshScaler.fitToBounds(meshPart: MeshPart, maxBounds: Vector3)
    local currentSize = meshPart.Size
    local scaleX = maxBounds.X / currentSize.X
    local scaleY = maxBounds.Y / currentSize.Y
    local scaleZ = maxBounds.Z / currentSize.Z
    local minScale = math.min(scaleX, scaleY, scaleZ)
    meshPart.Size = currentSize * minScale
end

--- Animates mesh scale with smooth tweening.
function MeshScaler.tweenScale(meshPart: MeshPart, targetSize: Vector3, duration: number)
    local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    local tween = TweenService:Create(meshPart, tweenInfo, { Size = targetSize })
    tween:Play()
    return tween
end

--- Pulse scale effect (grows then shrinks back).
function MeshScaler.pulseEffect(meshPart: MeshPart, pulseScale: number, duration: number)
    local originalSize = meshPart.Size
    local peakSize = originalSize * pulseScale

    local tweenUp = TweenService:Create(meshPart, TweenInfo.new(
        duration / 2, Enum.EasingStyle.Back, Enum.EasingDirection.Out
    ), { Size = peakSize })

    local tweenDown = TweenService:Create(meshPart, TweenInfo.new(
        duration / 2, Enum.EasingStyle.Quad, Enum.EasingDirection.In
    ), { Size = originalSize })

    tweenUp:Play()
    tweenUp.Completed:Connect(function()
        tweenDown:Play()
    end)
end

return MeshScaler
```

---

## 4. Mesh VFX System

```luau
--!strict
-- ModuleScript: Mesh-based visual effects (glow, dissolve, trail)

local TweenService = game:GetService("TweenService")

local MeshVFX = {}

--- Adds a glow effect using Highlight and PointLight.
function MeshVFX.addGlow(meshPart: MeshPart, color: Color3, brightness: number?)
    local highlight = Instance.new("Highlight")
    highlight.FillColor = color
    highlight.FillTransparency = 0.5
    highlight.OutlineColor = color
    highlight.OutlineTransparency = 0
    highlight.Parent = meshPart

    local light = Instance.new("PointLight")
    light.Color = color
    light.Brightness = brightness or 2
    light.Range = meshPart.Size.Magnitude * 1.5
    light.Parent = meshPart

    return { highlight = highlight, light = light }
end

--- Dissolve effect: fades transparency and shrinks the mesh.
function MeshVFX.dissolve(meshPart: MeshPart, duration: number, onComplete: (() -> ())?)
    local tween = TweenService:Create(meshPart, TweenInfo.new(
        duration, Enum.EasingStyle.Sine, Enum.EasingDirection.In
    ), {
        Transparency = 1,
        Size = meshPart.Size * 0.1,
    })

    tween:Play()
    tween.Completed:Connect(function()
        meshPart:Destroy()
        if onComplete then
            onComplete()
        end
    end)
end

--- Attaches a ParticleEmitter to a MeshPart for ambient VFX.
function MeshVFX.addParticles(meshPart: MeshPart, config: {
    texture: string?,
    color: ColorSequence?,
    rate: number?,
    lifetime: NumberRange?,
    speed: NumberRange?,
    size: NumberSequence?,
    spreadAngle: Vector2?,
}): ParticleEmitter
    local emitter = Instance.new("ParticleEmitter")
    emitter.Texture = config.texture or "rbxassetid://6490035152"
    emitter.Color = config.color or ColorSequence.new(Color3.fromRGB(255, 255, 255))
    emitter.Rate = config.rate or 20
    emitter.Lifetime = config.lifetime or NumberRange.new(1, 2)
    emitter.Speed = config.speed or NumberRange.new(1, 3)
    emitter.Size = config.size or NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.5),
        NumberSequenceKeypoint.new(0.5, 1),
        NumberSequenceKeypoint.new(1, 0),
    })
    emitter.SpreadAngle = config.spreadAngle or Vector2.new(360, 360)
    emitter.Parent = meshPart
    return emitter
end

--- Trail effect attached to a mesh via two Attachments.
function MeshVFX.addTrail(meshPart: MeshPart, color: ColorSequence?, width: NumberSequence?): Trail
    local attach0 = Instance.new("Attachment")
    attach0.Position = Vector3.new(0, meshPart.Size.Y / 2, 0)
    attach0.Parent = meshPart

    local attach1 = Instance.new("Attachment")
    attach1.Position = Vector3.new(0, -meshPart.Size.Y / 2, 0)
    attach1.Parent = meshPart

    local trail = Instance.new("Trail")
    trail.Attachment0 = attach0
    trail.Attachment1 = attach1
    trail.Color = color or ColorSequence.new(Color3.fromRGB(255, 200, 50), Color3.fromRGB(255, 50, 50))
    trail.Lifetime = 0.5
    trail.MinLength = 0.1
    trail.WidthScale = width or NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1),
        NumberSequenceKeypoint.new(1, 0),
    })
    trail.LightEmission = 0.8
    trail.Parent = meshPart
    return trail
end

--- Spawn mesh with dramatic entrance: scale up from zero.
function MeshVFX.spawnEntrance(meshPart: MeshPart, duration: number)
    local targetSize = meshPart.Size
    meshPart.Size = Vector3.new(0.01, 0.01, 0.01)
    meshPart.Transparency = 0.8

    local tween = TweenService:Create(meshPart, TweenInfo.new(
        duration, Enum.EasingStyle.Back, Enum.EasingDirection.Out
    ), {
        Size = targetSize,
        Transparency = 0,
    })
    tween:Play()
    return tween
end

return MeshVFX
```

---

## 5. Collision Fidelity Guide

| Fidelity Level | Use Case | Performance |
|---|---|---|
| `Box` | Simple props, items far from camera | Fastest |
| `Hull` | Convex shapes, vehicles | Fast |
| `Default` | General meshes | Balanced |
| `PreciseConvexDecomposition` | Complex walkable terrain, precise interaction | Slowest |

### Rules of Thumb

- Use `Box` for decorative objects that players never walk on
- Use `Hull` for convex shapes like barrels, crates
- Use `PreciseConvexDecomposition` only for terrain or walkable surfaces
- Never use Precise on high-poly meshes (causes lag on import)

---

## 6. Mesh LOD (Level of Detail)

```luau
--!strict
-- ModuleScript: Simple LOD system for meshes based on camera distance

local RunService = game:GetService("RunService")

local MeshLOD = {}

export type LODEntry = {
    meshId: string,
    maxDistance: number,
}

--- Attaches an LOD system to a MeshPart.
--- lodLevels should be sorted by maxDistance ascending.
function MeshLOD.attach(meshPart: MeshPart, lodLevels: { LODEntry }, camera: Camera?)
    local cam = camera or workspace.CurrentCamera
    local currentLOD = 1

    local connection = RunService.Heartbeat:Connect(function()
        if not meshPart or not meshPart.Parent then
            return
        end
        local distance = (cam.CFrame.Position - meshPart.Position).Magnitude
        local newLOD = #lodLevels

        for i, lod in ipairs(lodLevels) do
            if distance <= lod.maxDistance then
                newLOD = i
                break
            end
        end

        if newLOD ~= currentLOD then
            currentLOD = newLOD
            meshPart.MeshId = lodLevels[currentLOD].meshId
        end
    end)

    meshPart.Destroying:Connect(function()
        connection:Disconnect()
    end)

    return connection
end

return MeshLOD
```

---

## Common Patterns

### After generate_mesh MCP Call
```luau
-- After receiving meshId from generate_mesh MCP tool:
local MeshFactory = require(path.to.MeshFactory)

local config: MeshFactory.MeshPartConfig = {
    meshId = "rbxassetid://GENERATED_MESH_ID",
    position = Vector3.new(0, 10, 0),
    size = Vector3.new(6, 6, 6),
    material = Enum.Material.SmoothPlastic,
    color = Color3.fromRGB(120, 80, 200),
    collisionFidelity = Enum.CollisionFidelity.Hull,
    anchored = true,
}

local myMesh = MeshFactory.create(config)
```

### Mesh with VFX Combo
```luau
local MeshVFX = require(path.to.MeshVFX)
local MeshScaler = require(path.to.MeshScaler)

-- Create glowing pulsing crystal
local crystal = MeshFactory.create({
    meshId = "rbxassetid://CRYSTAL_MESH_ID",
    position = Vector3.new(0, 3, 0),
    material = Enum.Material.Neon,
    color = Color3.fromRGB(100, 200, 255),
})

MeshVFX.addGlow(crystal, Color3.fromRGB(100, 200, 255), 3)
MeshVFX.addParticles(crystal, {
    color = ColorSequence.new(Color3.fromRGB(100, 200, 255)),
    rate = 10,
    speed = NumberRange.new(0.5, 1),
})

-- Continuous pulse
task.spawn(function()
    while crystal and crystal.Parent do
        MeshScaler.pulseEffect(crystal, 1.15, 2)
        task.wait(2.2)
    end
end)
```

---

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

- `mesh_prompt` (string) - Text description for generate_mesh MCP tool (e.g. "low-poly medieval castle tower")
- `mesh_id` (string) - Existing rbxassetid:// mesh ID to apply to MeshPart
- `scale` (number) - Uniform scale factor for the mesh (default: 1)
- `target_size` (Vector3) - Target bounding box size for fitToBounds
- `collision_fidelity` (string) - One of: "Box", "Hull", "Default", "PreciseConvexDecomposition"
- `material` (string) - Roblox material name (e.g. "Neon", "SmoothPlastic", "Metal")
- `color_rgb` (table) - {r, g, b} color values 0-255
- `vfx_type` (string) - VFX to apply: "glow", "dissolve", "particles", "trail", "entrance"
- `vfx_color` (Color3) - Color for VFX effects
- `anchored` (boolean) - Whether the mesh is anchored (default: true)
- `position` (Vector3) - World position for the mesh
