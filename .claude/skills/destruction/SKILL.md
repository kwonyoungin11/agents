---
name: destruction-system
description: |
  Destruction system for Roblox: breakable parts that shatter into debris, explosion force,
  chain destruction, debris cleanup with Debris service. Use when the user asks about
  destructible objects, breaking parts, shattering, explosions, debris, chain reactions,
  breakable walls, environmental destruction, or physics destruction.
  파괴, 부서지는, 폭발, 잔해, 연쇄 파괴, 벽 부수기, 환경 파괴.
  Triggers on: destruction, destructible, breakable, shatter, debris, explosion, chain
  destruction, break apart, fragment, rubble, Debris service, crumble, destroy.
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
effort: high
---

# Destruction System Skill

Production-quality destructible environment system for Roblox with shatter effects,
explosion forces, chain reactions, and automatic debris cleanup.

---

## Architecture Overview

```
Breakable Part (tagged with "Breakable" CollectionService tag)
 ├─ Attribute: Health (number)
 ├─ Attribute: FragmentCount (number)
 ├─ Attribute: ChainReaction (boolean)
 └─ On break → spawns N fragment parts + applies explosion force → Debris cleanup
```

---

## 1. Destruction Service (Server Module)

```luau
--!strict
-- ServerScriptService/DestructionService.lua
-- Core module for breakable objects, shattering, and chain reactions.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local DestructionService = {}

export type BreakableConfig = {
    health: number,
    fragmentCount: number,       -- how many pieces to shatter into
    fragmentLifetime: number,    -- seconds before fragments are cleaned up
    explosionForce: number,      -- force applied to fragments
    explosionRadius: number,     -- radius of force application
    chainReaction: boolean,      -- whether breaking this triggers nearby breakables
    chainRadius: number,         -- radius for chain reaction detection
    chainDamage: number,         -- damage dealt to nearby breakables
    chainDelay: number,          -- seconds before chain reaction triggers
    fragmentMaterial: Enum.Material,
    fragmentColor: Color3?,      -- nil = inherit from original part
    soundId: string?,            -- break sound effect
    particleCount: number,       -- dust/debris particles on break
}

local DEFAULT_CONFIG: BreakableConfig = {
    health = 100,
    fragmentCount = 8,
    fragmentLifetime = 5,
    explosionForce = 50,
    explosionRadius = 10,
    chainReaction = false,
    chainRadius = 15,
    chainDamage = 80,
    chainDelay = 0.1,
    fragmentMaterial = Enum.Material.Slate,
    fragmentColor = nil,
    soundId = nil,
    particleCount = 20,
}

-- Internal registry of breakable parts
local breakables: { [BasePart]: BreakableConfig } = {}

-- Register a part as breakable
function DestructionService.register(part: BasePart, config: BreakableConfig?)
    local cfg = config or table.clone(DEFAULT_CONFIG)
    breakables[part] = cfg

    -- Store health as attribute for external access
    part:SetAttribute("Health", cfg.health)
    part:SetAttribute("MaxHealth", cfg.health)
    part:SetAttribute("Breakable", true)

    -- Tag with CollectionService for easy querying
    CollectionService:AddTag(part, "Breakable")
end

-- Auto-register all parts tagged "Breakable" in workspace
function DestructionService.autoRegister()
    for _, part in CollectionService:GetTagged("Breakable") do
        if part:IsA("BasePart") and not breakables[part] then
            local config = table.clone(DEFAULT_CONFIG)
            -- Read overrides from attributes
            config.health = part:GetAttribute("Health") or config.health
            config.fragmentCount = part:GetAttribute("FragmentCount") or config.fragmentCount
            config.chainReaction = part:GetAttribute("ChainReaction") or config.chainReaction
            config.explosionForce = part:GetAttribute("ExplosionForce") or config.explosionForce
            breakables[part] = config
            part:SetAttribute("MaxHealth", config.health)
        end
    end

    -- Listen for new tagged parts
    CollectionService:GetInstanceAddedSignal("Breakable"):Connect(function(instance)
        if instance:IsA("BasePart") and not breakables[instance] then
            DestructionService.register(instance)
        end
    end)
end

-- Apply damage to a breakable part
function DestructionService.damage(part: BasePart, amount: number, sourcePosition: Vector3?): boolean
    local cfg = breakables[part]
    if not cfg then return false end

    local health = (part:GetAttribute("Health") :: number) - amount
    part:SetAttribute("Health", math.max(health, 0))

    if health <= 0 then
        DestructionService.shatter(part, sourcePosition)
        return true -- part was destroyed
    end

    return false
end

-- Shatter a part into fragments
function DestructionService.shatter(part: BasePart, sourcePosition: Vector3?)
    local cfg = breakables[part]
    if not cfg then
        -- Not registered, just destroy
        part:Destroy()
        return
    end

    local partCFrame = part.CFrame
    local partSize = part.Size
    local partColor = cfg.fragmentColor or part.Color
    local explosionCenter = sourcePosition or part.Position

    -- Play break sound
    if cfg.soundId then
        local sound = Instance.new("Sound")
        sound.SoundId = cfg.soundId
        sound.PlayOnRemove = false
        sound.Volume = 1
        sound.Parent = workspace.Terrain
        sound:Play()
        Debris:AddItem(sound, 3)
    end

    -- Create dust/debris particles
    DestructionService._createBreakParticles(part.Position, partColor, cfg.particleCount)

    -- Calculate fragment size
    local totalVolume = partSize.X * partSize.Y * partSize.Z
    local fragmentVolume = totalVolume / cfg.fragmentCount
    local fragmentScale = fragmentVolume ^ (1/3)

    -- Generate fragments
    local fragments: { BasePart } = {}
    for i = 1, cfg.fragmentCount do
        local fragment = Instance.new("Part")
        fragment.Name = "Fragment_" .. i

        -- Randomized fragment size (not uniform)
        local sizeVariation = 0.5 + math.random() * 1.0
        fragment.Size = Vector3.new(
            fragmentScale * sizeVariation * (0.5 + math.random()),
            fragmentScale * sizeVariation * (0.5 + math.random()),
            fragmentScale * sizeVariation * (0.5 + math.random())
        )

        -- Clamp minimum size
        fragment.Size = fragment.Size:Max(Vector3.one * 0.3)

        fragment.Color = partColor
        fragment.Material = cfg.fragmentMaterial
        fragment.Anchored = false
        fragment.CanCollide = true

        -- Position randomly within the original part's volume
        local offset = Vector3.new(
            (math.random() - 0.5) * partSize.X,
            (math.random() - 0.5) * partSize.Y,
            (math.random() - 0.5) * partSize.Z
        )
        fragment.CFrame = partCFrame * CFrame.new(offset) * CFrame.Angles(
            math.random() * math.pi * 2,
            math.random() * math.pi * 2,
            math.random() * math.pi * 2
        )

        fragment.Parent = workspace

        -- Apply explosion force
        local direction = (fragment.Position - explosionCenter)
        if direction.Magnitude < 0.1 then
            direction = Vector3.new(math.random() - 0.5, 1, math.random() - 0.5)
        end
        local force = direction.Unit * cfg.explosionForce * (1 + math.random())
        force = force + Vector3.new(0, cfg.explosionForce * 0.5, 0) -- upward bias
        fragment:ApplyImpulse(force * fragment:GetMass())

        -- Angular impulse for tumbling
        fragment:ApplyAngularImpulse(Vector3.new(
            (math.random() - 0.5) * 20,
            (math.random() - 0.5) * 20,
            (math.random() - 0.5) * 20
        ))

        table.insert(fragments, fragment)

        -- Schedule cleanup with fade
        task.delay(cfg.fragmentLifetime - 1, function()
            if fragment.Parent then
                TweenService:Create(
                    fragment,
                    TweenInfo.new(1, Enum.EasingStyle.Linear),
                    { Transparency = 1 }
                ):Play()
            end
        end)
        Debris:AddItem(fragment, cfg.fragmentLifetime)
    end

    -- Chain reaction: damage nearby breakables
    if cfg.chainReaction then
        task.delay(cfg.chainDelay, function()
            DestructionService._triggerChainReaction(
                part.Position,
                cfg.chainRadius,
                cfg.chainDamage,
                part
            )
        end)
    end

    -- Remove original part
    breakables[part] = nil
    part:Destroy()
end

-- Internal: trigger chain reactions on nearby breakables
function DestructionService._triggerChainReaction(
    center: Vector3,
    radius: number,
    damage: number,
    sourcePart: BasePart
)
    local nearby = workspace:GetPartBoundsInRadius(center, radius)

    for _, part in nearby do
        if part:IsA("BasePart") and breakables[part] and part ~= sourcePart then
            local distance = (part.Position - center).Magnitude
            local falloff = 1 - math.clamp(distance / radius, 0, 1)
            local actualDamage = damage * falloff
            DestructionService.damage(part, actualDamage, center)
        end
    end
end

-- Internal: create particle burst on break
function DestructionService._createBreakParticles(position: Vector3, color: Color3, count: number)
    local emitterPart = Instance.new("Part")
    emitterPart.Size = Vector3.one * 0.1
    emitterPart.Transparency = 1
    emitterPart.Anchored = true
    emitterPart.CanCollide = false
    emitterPart.CanQuery = false
    emitterPart.Position = position
    emitterPart.Parent = workspace

    local emitter = Instance.new("ParticleEmitter")
    emitter.Color = ColorSequence.new(color)
    emitter.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1),
        NumberSequenceKeypoint.new(1, 0),
    })
    emitter.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0),
        NumberSequenceKeypoint.new(0.8, 0.5),
        NumberSequenceKeypoint.new(1, 1),
    })
    emitter.Lifetime = NumberRange.new(0.5, 1.5)
    emitter.Speed = NumberRange.new(5, 20)
    emitter.SpreadAngle = Vector2.new(180, 180)
    emitter.Rate = 0  -- burst only
    emitter.Parent = emitterPart

    emitter:Emit(count)

    Debris:AddItem(emitterPart, 2)
end

return DestructionService
```

---

## 2. Explosion Force Utility

```luau
--!strict
-- ServerScriptService/ExplosionForce.lua
-- Applies radial explosion force to all parts in radius, damages breakables.

local DestructionService = require(script.Parent:WaitForChild("DestructionService"))

local ExplosionForce = {}

export type ExplosionConfig = {
    force: number,
    radius: number,
    damage: number,
    upwardBias: number,        -- 0-1, how much force pushes upward
    affectAnchored: boolean,   -- whether to unanchor and push anchored parts
    damageBreakables: boolean,
    damageCharacters: boolean,
    characterDamage: number,
}

local DEFAULT_EXPLOSION: ExplosionConfig = {
    force = 100,
    radius = 20,
    damage = 80,
    upwardBias = 0.3,
    affectAnchored = false,
    damageBreakables = true,
    damageCharacters = true,
    characterDamage = 40,
}

function ExplosionForce.apply(center: Vector3, config: ExplosionConfig?)
    local cfg = config or DEFAULT_EXPLOSION

    local parts = workspace:GetPartBoundsInRadius(center, cfg.radius)
    local processedModels: { Model } = {}

    for _, part in parts do
        if not part:IsA("BasePart") then continue end

        local distance = (part.Position - center).Magnitude
        local falloff = 1 - math.clamp(distance / cfg.radius, 0, 1)

        -- Direction from center to part
        local direction = (part.Position - center)
        if direction.Magnitude < 0.01 then
            direction = Vector3.new(0, 1, 0)
        end
        direction = direction.Unit

        -- Add upward bias
        direction = (direction + Vector3.new(0, cfg.upwardBias, 0)).Unit

        -- Unanchor if configured
        if cfg.affectAnchored and part.Anchored then
            part.Anchored = false
        end

        -- Apply force to unanchored parts
        if not part.Anchored then
            local impulse = direction * cfg.force * falloff * part:GetMass()
            part:ApplyImpulse(impulse)
        end

        -- Damage breakables
        if cfg.damageBreakables and part:GetAttribute("Breakable") then
            DestructionService.damage(part, cfg.damage * falloff, center)
        end

        -- Damage characters
        if cfg.damageCharacters then
            local model = part:FindFirstAncestorOfClass("Model")
            if model then
                local humanoid = model:FindFirstChildWhichIsA("Humanoid")
                if humanoid and humanoid.Health > 0 then
                    local alreadyDamaged = false
                    for _, m in processedModels do
                        if m == model then alreadyDamaged = true; break end
                    end
                    if not alreadyDamaged then
                        humanoid:TakeDamage(cfg.characterDamage * falloff)
                        table.insert(processedModels, model)
                    end
                end
            end
        end
    end
end

-- Convenience: create visual + force explosion
function ExplosionForce.explode(center: Vector3, config: ExplosionConfig?)
    local cfg = config or DEFAULT_EXPLOSION

    -- Visual explosion
    local explosion = Instance.new("Explosion")
    explosion.Position = center
    explosion.BlastRadius = cfg.radius
    explosion.BlastPressure = 0  -- we handle force manually
    explosion.DestroyJointRadiusPercent = 0
    explosion.Parent = workspace

    -- Apply our custom force
    ExplosionForce.apply(center, cfg)
end

return ExplosionForce
```

---

## 3. Debris Cleanup Manager

```luau
--!strict
-- ServerScriptService/DebrisManager.lua
-- Manages debris count limits and performance-aware cleanup.

local Debris = game:GetService("Debris")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local DebrisManager = {}

local MAX_DEBRIS_COUNT = 200
local CLEANUP_CHECK_INTERVAL = 2 -- seconds
local DEBRIS_TAG = "DestructionDebris"

local debrisParts: { { part: BasePart, spawnTime: number } } = {}
local lastCleanup = 0

-- Register a fragment as managed debris
function DebrisManager.register(part: BasePart, lifetime: number)
    CollectionService:AddTag(part, DEBRIS_TAG)
    table.insert(debrisParts, {
        part = part,
        spawnTime = tick(),
    })

    -- Also use Debris service as a safety net
    Debris:AddItem(part, lifetime + 1)

    -- Check if we need to cull
    if #debrisParts > MAX_DEBRIS_COUNT then
        DebrisManager.cullOldest(#debrisParts - MAX_DEBRIS_COUNT)
    end
end

-- Remove the oldest N debris parts immediately
function DebrisManager.cullOldest(count: number)
    local removed = 0
    while removed < count and #debrisParts > 0 do
        local entry = table.remove(debrisParts, 1)
        if entry and entry.part and entry.part.Parent then
            entry.part:Destroy()
        end
        removed += 1
    end
end

-- Clean up all debris
function DebrisManager.cleanupAll()
    for _, entry in debrisParts do
        if entry.part and entry.part.Parent then
            entry.part:Destroy()
        end
    end
    table.clear(debrisParts)
end

-- Periodic cleanup of already-destroyed references
function DebrisManager.prune()
    local pruned: { { part: BasePart, spawnTime: number } } = {}
    for _, entry in debrisParts do
        if entry.part and entry.part.Parent then
            table.insert(pruned, entry)
        end
    end
    debrisParts = pruned
end

-- Get current debris count
function DebrisManager.getCount(): number
    return #debrisParts
end

-- Set maximum debris limit
function DebrisManager.setMaxDebris(max: number)
    MAX_DEBRIS_COUNT = max
end

-- Automatic periodic pruning
RunService.Heartbeat:Connect(function()
    local now = tick()
    if now - lastCleanup > CLEANUP_CHECK_INTERVAL then
        lastCleanup = now
        DebrisManager.prune()
    end
end)

return DebrisManager
```

---

## 4. Breakable Wall Example Setup

```luau
--!strict
-- ServerScriptService/BreakableWallSetup.server.lua
-- Example: creates a breakable wall of bricks that shatter on impact.

local DestructionService = require(script.Parent:WaitForChild("DestructionService"))

local function createBreakableWall(origin: CFrame, rows: number, columns: number, brickSize: Vector3)
    local wallFolder = Instance.new("Folder")
    wallFolder.Name = "BreakableWall"
    wallFolder.Parent = workspace

    for row = 0, rows - 1 do
        for col = 0, columns - 1 do
            local brick = Instance.new("Part")
            brick.Name = "Brick_" .. row .. "_" .. col
            brick.Size = brickSize
            brick.Anchored = true
            brick.Material = Enum.Material.Brick
            brick.Color = Color3.fromRGB(
                150 + math.random(-20, 20),
                80 + math.random(-15, 15),
                50 + math.random(-10, 10)
            )

            -- Offset for alternating brick pattern
            local xOffset = (col * brickSize.X)
            if row % 2 == 1 then
                xOffset += brickSize.X * 0.5
            end
            local yOffset = row * brickSize.Y

            brick.CFrame = origin * CFrame.new(
                xOffset - (columns * brickSize.X) / 2,
                yOffset,
                0
            )

            brick.Parent = wallFolder

            -- Register as breakable with chain reactions
            DestructionService.register(brick, {
                health = 50,
                fragmentCount = 4,
                fragmentLifetime = 4,
                explosionForce = 30,
                explosionRadius = 5,
                chainReaction = true,
                chainRadius = brickSize.X * 2,
                chainDamage = 60,
                chainDelay = 0.05,
                fragmentMaterial = Enum.Material.Brick,
                fragmentColor = nil,
                soundId = nil,
                particleCount = 10,
            })
        end
    end
end

-- Create a sample wall
createBreakableWall(
    CFrame.new(0, 0, -20),
    6,   -- rows
    10,  -- columns
    Vector3.new(3, 1.5, 1.5)
)

-- Auto-register any pre-placed breakable parts
DestructionService.autoRegister()
```

---

## Guidelines

- **Tag breakable parts** with CollectionService tag "Breakable" for easy querying and auto-registration.
- **Use attributes** (Health, FragmentCount, etc.) to configure breakable parts in Studio without code changes.
- **Fragment count** should balance visual fidelity vs. performance; 4-12 fragments per part is typical.
- **Chain reactions** use `task.delay` to create a cascading effect. Keep `chainDelay` small (0.05-0.2s).
- **Always use `Debris:AddItem()`** as a safety net for fragment cleanup, even with the DebrisManager.
- **Cap total debris count** globally to prevent performance degradation in heavy destruction scenarios.
- **Explosion force** should include an upward bias to make debris look dramatic.
- For multiplayer: run destruction on the server; physics replication handles fragment visuals on clients.
- **Anchored parts** should be unanchored before applying impulse forces.

---

## 

---

## Learned Lessons

<!-- skill-evolve 에이전트가 자동으로 이 섹션에 교훈을 추가합니다 -->

## Self-Evolution Protocol

이 스킬에서 에러가 발생하면:
1. 에러의 근본 원인을 분석한다
2. 이 파일의 Learned Lessons 섹션에 교훈을 추가한다
3. 같은 실수가 반복되지 않도록 규칙화한다
4. SessionManager에 에러와 학습 내용을 기록한다

```lua
local SM = require(game.ServerStorage._RobloxEngine.SessionManager)
SM.logAction("SKILL_ERROR", "[스킬명] | [에러]")
SM.logAction("SKILL_LEARNED", "[스킬명] | [교훈]")
```

**매 작업 시 반드시 Learned Lessons를 먼저 읽고 기존 교훈을 위반하지 않는지 확인한다.**

$ARGUMENTS

When generating destruction code, adapt to these user-specified parameters:

- `$HEALTH` - Base health of breakable parts (default: 100)
- `$FRAGMENT_COUNT` - Number of fragments per break (default: 8)
- `$FRAGMENT_LIFETIME` - Seconds before cleanup (default: 5)
- `$EXPLOSION_FORCE` - Force magnitude for fragment scatter (default: 50)
- `$CHAIN_REACTION` - Whether to enable chain destruction (default: false)
- `$CHAIN_RADIUS` - Radius for chain reaction (default: 15)
- `$MAX_DEBRIS` - Global maximum debris parts (default: 200)
- `$MATERIAL` - Fragment material type (default: "Slate")
- `$INCLUDE_SOUND` - Whether to include break sound (default: false)
- `$INCLUDE_PARTICLES` - Whether to include dust particles (default: true)
