---
name: projectile-system
description: |
  Projectile system for Roblox: bullet raycast (hitscan), physics projectile (arrow),
  magic orb, homing missile, grenade arc, trail on projectiles. Use when the user asks
  about projectiles, bullets, raycasting, shooting, hitscan, arrows, magic attacks,
  missiles, grenades, trails, or ranged combat.
  투사체, 총알, 레이캐스트, 사격, 화살, 마법, 미사일, 수류탄, 트레일, 원거리.
  Triggers on: projectile, bullet, raycast, hitscan, shoot, arrow, magic orb, missile,
  homing, grenade, arc, trail, ranged, fire, launch.
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
effort: high
---

# Projectile System Skill

Complete projectile system covering hitscan bullets, physics-based projectiles, homing
missiles, grenades with arcs, and visual trail effects. All Luau, server-authoritative.

---

## 1. Hitscan Bullet (Raycast)

```luau
--!strict
-- ServerScriptService/HitscanBullet.lua
-- Instant raycast-based bullet with damage, penetration, and visual tracer.

local Debris = game:GetService("Debris")

local HitscanBullet = {}

export type HitscanConfig = {
    damage: number,
    maxDistance: number,
    penetrationCount: number,    -- how many parts it can go through
    penetrationDamageFalloff: number, -- multiplier per penetration (0.5 = 50% less each)
    tracerColor: Color3,
    tracerWidth: number,
    tracerDuration: number,
    filterDescendants: { Instance }?, -- raycast ignore list
}

local DEFAULT_CONFIG: HitscanConfig = {
    damage = 25,
    maxDistance = 500,
    penetrationCount = 0,
    penetrationDamageFalloff = 0.5,
    tracerColor = Color3.fromRGB(255, 200, 50),
    tracerWidth = 0.05,
    tracerDuration = 0.15,
    filterDescendants = nil,
}

export type HitResult = {
    hit: boolean,
    instance: BasePart?,
    position: Vector3,
    normal: Vector3?,
    distance: number,
    humanoid: Humanoid?,
}

function HitscanBullet.fire(
    origin: Vector3,
    direction: Vector3,  -- normalized
    config: HitscanConfig?
): { HitResult }
    local cfg = config or DEFAULT_CONFIG
    local results: { HitResult } = {}

    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    rayParams.FilterDescendantsInstances = cfg.filterDescendants or {}
    rayParams.IgnoreWater = true

    local currentOrigin = origin
    local remainingDistance = cfg.maxDistance
    local currentDamage = cfg.damage
    local penetrations = 0

    repeat
        local rayResult = workspace:Raycast(currentOrigin, direction * remainingDistance, rayParams)

        if rayResult then
            local hitPos = rayResult.Position
            local hitDist = (hitPos - currentOrigin).Magnitude

            -- Find humanoid
            local hitHumanoid: Humanoid? = nil
            local model = rayResult.Instance:FindFirstAncestorOfClass("Model")
            if model then
                hitHumanoid = model:FindFirstChildWhichIsA("Humanoid")
            end

            -- Apply damage
            if hitHumanoid and hitHumanoid.Health > 0 then
                hitHumanoid:TakeDamage(currentDamage)
            end

            table.insert(results, {
                hit = true,
                instance = rayResult.Instance,
                position = hitPos,
                normal = rayResult.Normal,
                distance = hitDist,
                humanoid = hitHumanoid,
            })

            -- Penetration logic
            penetrations += 1
            if penetrations > cfg.penetrationCount then
                break
            end

            -- Move origin past the hit object, reduce damage
            currentOrigin = hitPos + direction * 0.1
            remainingDistance -= hitDist
            currentDamage *= cfg.penetrationDamageFalloff

            -- Add hit instance to filter so we don't hit it again
            local newFilter = table.clone(rayParams.FilterDescendantsInstances)
            table.insert(newFilter, rayResult.Instance)
            rayParams.FilterDescendantsInstances = newFilter
        else
            -- No hit, bullet traveled full distance
            table.insert(results, {
                hit = false,
                instance = nil,
                position = currentOrigin + direction * remainingDistance,
                normal = nil,
                distance = remainingDistance,
                humanoid = nil,
            })
            break
        end
    until remainingDistance <= 0

    -- Create visual tracer
    HitscanBullet.createTracer(origin, results[#results].position, cfg)

    return results
end

-- Visual tracer beam
function HitscanBullet.createTracer(startPos: Vector3, endPos: Vector3, config: HitscanConfig)
    local distance = (endPos - startPos).Magnitude
    local midPoint = (startPos + endPos) / 2

    local tracer = Instance.new("Part")
    tracer.Name = "BulletTracer"
    tracer.Anchored = true
    tracer.CanCollide = false
    tracer.CanQuery = false
    tracer.CanTouch = false
    tracer.Material = Enum.Material.Neon
    tracer.Color = config.tracerColor
    tracer.Size = Vector3.new(config.tracerWidth, config.tracerWidth, distance)
    tracer.CFrame = CFrame.lookAt(midPoint, endPos)
    tracer.Parent = workspace

    Debris:AddItem(tracer, config.tracerDuration)
end

return HitscanBullet
```

---

## 2. Physics Projectile (Arrow / Slow Bullet)

```luau
--!strict
-- ServerScriptService/PhysicsProjectile.lua
-- Gravity-affected projectile that physically travels through the world.

local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local PhysicsProjectile = {}

export type ProjectileConfig = {
    speed: number,
    gravity: number,           -- studs/s^2 (negative = downward)
    damage: number,
    lifetime: number,          -- seconds
    size: Vector3,
    color: Color3,
    material: Enum.Material,
    stickOnHit: boolean,       -- arrow sticks into target
    piercing: boolean,         -- goes through targets
    onHit: ((hit: BasePart, position: Vector3, normal: Vector3) -> ())?,
}

local DEFAULT_CONFIG: ProjectileConfig = {
    speed = 150,
    gravity = -workspace.Gravity,
    damage = 40,
    lifetime = 5,
    size = Vector3.new(0.2, 0.2, 2),
    color = Color3.fromRGB(139, 90, 43),
    material = Enum.Material.Wood,
    stickOnHit = true,
    piercing = false,
    onHit = nil,
}

function PhysicsProjectile.fire(
    origin: Vector3,
    direction: Vector3,        -- normalized
    owner: Player?,            -- for filtering
    config: ProjectileConfig?
): Part
    local cfg = config or DEFAULT_CONFIG

    -- Create projectile part
    local projectile = Instance.new("Part")
    projectile.Name = "Projectile"
    projectile.Size = cfg.size
    projectile.Color = cfg.color
    projectile.Material = cfg.material
    projectile.Anchored = false
    projectile.CanCollide = false
    projectile.CanQuery = false
    projectile.CFrame = CFrame.lookAt(origin, origin + direction)
    projectile.Parent = workspace

    -- Set initial velocity
    projectile.AssemblyLinearVelocity = direction * cfg.speed

    -- Raycast params for hit detection
    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    local filterList: { Instance } = { projectile }
    if owner and owner.Character then
        table.insert(filterList, owner.Character)
    end
    rayParams.FilterDescendantsInstances = filterList

    local velocity = direction * cfg.speed
    local alive = true
    local hitTargets: { Model } = {}

    -- Physics simulation via Heartbeat
    local connection: RBXScriptConnection
    connection = RunService.Heartbeat:Connect(function(dt: number)
        if not alive or not projectile.Parent then
            connection:Disconnect()
            return
        end

        -- Apply gravity
        velocity = velocity + Vector3.new(0, cfg.gravity * dt, 0)
        local displacement = velocity * dt

        -- Raycast ahead for collision detection
        local ray = workspace:Raycast(projectile.Position, displacement, rayParams)

        if ray then
            local hitPart = ray.Instance
            local hitPos = ray.Position
            local hitNormal = ray.Normal

            -- Check if it's a character
            local model = hitPart:FindFirstAncestorOfClass("Model")
            local humanoid: Humanoid? = nil
            if model then
                humanoid = model:FindFirstChildWhichIsA("Humanoid")
            end

            -- Avoid hitting same target twice (for piercing)
            local alreadyHit = false
            if model and cfg.piercing then
                for _, m in hitTargets do
                    if m == model then
                        alreadyHit = true
                        break
                    end
                end
            end

            if not alreadyHit then
                -- Deal damage
                if humanoid and humanoid.Health > 0 then
                    humanoid:TakeDamage(cfg.damage)
                end

                -- Custom callback
                if cfg.onHit then
                    cfg.onHit(hitPart, hitPos, hitNormal)
                end

                if model then
                    table.insert(hitTargets, model)
                end

                if not cfg.piercing then
                    alive = false
                    connection:Disconnect()

                    if cfg.stickOnHit then
                        -- Stick arrow into the surface
                        projectile.Anchored = true
                        projectile.CFrame = CFrame.lookAt(hitPos - velocity.Unit * (cfg.size.Z / 2), hitPos)

                        -- Weld to hit part for moving targets
                        local weld = Instance.new("WeldConstraint")
                        weld.Part0 = projectile
                        weld.Part1 = hitPart
                        weld.Parent = projectile
                        projectile.Anchored = false

                        Debris:AddItem(projectile, 5)
                    else
                        projectile:Destroy()
                    end
                    return
                end
            end
        end

        -- Move projectile
        projectile.CFrame = CFrame.lookAt(
            projectile.Position + displacement,
            projectile.Position + displacement + velocity
        )
    end)

    -- Lifetime cleanup
    Debris:AddItem(projectile, cfg.lifetime)
    task.delay(cfg.lifetime, function()
        alive = false
    end)

    return projectile
end

return PhysicsProjectile
```

---

## 3. Magic Orb Projectile

```luau
--!strict
-- ServerScriptService/MagicOrb.lua
-- Glowing energy orb with particle effects, travels in a straight line.

local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")

local MagicOrb = {}

export type OrbConfig = {
    speed: number,
    damage: number,
    radius: number,             -- explosion/hit radius
    lifetime: number,
    color: Color3,
    secondaryColor: Color3,
    size: number,
    aoeOnImpact: boolean,
    aoeDamage: number,
    aoeRadius: number,
}

local DEFAULT_ORB: OrbConfig = {
    speed = 80,
    damage = 30,
    radius = 2,
    lifetime = 4,
    color = Color3.fromRGB(100, 50, 255),
    secondaryColor = Color3.fromRGB(200, 150, 255),
    size = 1.5,
    aoeOnImpact = true,
    aoeDamage = 15,
    aoeRadius = 10,
}

function MagicOrb.fire(
    origin: Vector3,
    direction: Vector3,
    owner: Player?,
    config: OrbConfig?
): Part
    local cfg = config or DEFAULT_ORB

    -- Orb body
    local orb = Instance.new("Part")
    orb.Name = "MagicOrb"
    orb.Shape = Enum.PartType.Ball
    orb.Size = Vector3.one * cfg.size
    orb.Color = cfg.color
    orb.Material = Enum.Material.Neon
    orb.Anchored = true
    orb.CanCollide = false
    orb.CanQuery = false
    orb.CFrame = CFrame.new(origin)
    orb.Parent = workspace

    -- Point light
    local light = Instance.new("PointLight")
    light.Color = cfg.color
    light.Brightness = 3
    light.Range = 15
    light.Parent = orb

    -- Particle emitter for trailing sparks
    local particles = Instance.new("ParticleEmitter")
    particles.Color = ColorSequence.new(cfg.color, cfg.secondaryColor)
    particles.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, cfg.size * 0.5),
        NumberSequenceKeypoint.new(1, 0),
    })
    particles.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0),
        NumberSequenceKeypoint.new(1, 1),
    })
    particles.Lifetime = NumberRange.new(0.3, 0.6)
    particles.Rate = 60
    particles.Speed = NumberRange.new(2, 5)
    particles.SpreadAngle = Vector2.new(180, 180)
    particles.Parent = orb

    -- Raycast params
    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    local filterList: { Instance } = { orb }
    if owner and owner.Character then
        table.insert(filterList, owner.Character)
    end
    rayParams.FilterDescendantsInstances = filterList

    local alive = true

    local connection = RunService.Heartbeat:Connect(function(dt: number)
        if not alive or not orb.Parent then return end

        local movement = direction * cfg.speed * dt
        local ray = workspace:Raycast(orb.Position, movement, rayParams)

        if ray then
            alive = false

            -- Direct hit damage
            local model = ray.Instance:FindFirstAncestorOfClass("Model")
            if model then
                local humanoid = model:FindFirstChildWhichIsA("Humanoid")
                if humanoid and humanoid.Health > 0 then
                    humanoid:TakeDamage(cfg.damage)
                end
            end

            -- AOE damage on impact
            if cfg.aoeOnImpact then
                local hitPos = ray.Position
                local parts = workspace:GetPartBoundsInRadius(hitPos, cfg.aoeRadius)
                local damagedModels: { Model } = {}

                for _, part in parts do
                    local m = part:FindFirstAncestorOfClass("Model")
                    if m and m ~= (owner and owner.Character) then
                        local h = m:FindFirstChildWhichIsA("Humanoid")
                        if h and h.Health > 0 then
                            local alreadyDamaged = false
                            for _, dm in damagedModels do
                                if dm == m then alreadyDamaged = true; break end
                            end
                            if not alreadyDamaged then
                                h:TakeDamage(cfg.aoeDamage)
                                table.insert(damagedModels, m)
                            end
                        end
                    end
                end

                -- Explosion visual
                local explosion = Instance.new("Part")
                explosion.Shape = Enum.PartType.Ball
                explosion.Size = Vector3.one * cfg.aoeRadius * 2
                explosion.Color = cfg.color
                explosion.Material = Enum.Material.Neon
                explosion.Anchored = true
                explosion.CanCollide = false
                explosion.Transparency = 0.5
                explosion.CFrame = CFrame.new(hitPos)
                explosion.Parent = workspace

                game:GetService("TweenService"):Create(
                    explosion,
                    TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                    { Size = Vector3.one * cfg.aoeRadius * 3, Transparency = 1 }
                ):Play()

                Debris:AddItem(explosion, 0.5)
            end

            orb:Destroy()
            return
        end

        orb.CFrame = CFrame.new(orb.Position + movement)
    end)

    Debris:AddItem(orb, cfg.lifetime)
    task.delay(cfg.lifetime, function()
        alive = false
    end)

    return orb
end

return MagicOrb
```

---

## 4. Homing Missile

```luau
--!strict
-- ServerScriptService/HomingMissile.lua
-- Missile that tracks a target with configurable tracking strength.

local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local HomingMissile = {}

export type MissileConfig = {
    speed: number,
    turnRate: number,           -- radians per second
    damage: number,
    explosionRadius: number,
    explosionDamage: number,
    lifetime: number,
    lockOnDelay: number,        -- seconds before homing kicks in
    size: Vector3,
    color: Color3,
    trailColor: Color3,
}

local DEFAULT_MISSILE: MissileConfig = {
    speed = 100,
    turnRate = 3.0,
    damage = 50,
    explosionRadius = 15,
    explosionDamage = 30,
    lifetime = 8,
    lockOnDelay = 0.5,
    size = Vector3.new(0.5, 0.5, 2),
    color = Color3.fromRGB(200, 200, 200),
    trailColor = Color3.fromRGB(255, 150, 50),
}

function HomingMissile.fire(
    origin: Vector3,
    initialDirection: Vector3,
    target: BasePart,           -- part to home in on (e.g., HumanoidRootPart)
    owner: Player?,
    config: MissileConfig?
): Part
    local cfg = config or DEFAULT_MISSILE

    local missile = Instance.new("Part")
    missile.Name = "HomingMissile"
    missile.Size = cfg.size
    missile.Color = cfg.color
    missile.Material = Enum.Material.Metal
    missile.Anchored = true
    missile.CanCollide = false
    missile.CanQuery = false
    missile.CFrame = CFrame.lookAt(origin, origin + initialDirection)
    missile.Parent = workspace

    -- Smoke trail
    local smoke = Instance.new("ParticleEmitter")
    smoke.Color = ColorSequence.new(cfg.trailColor, Color3.fromRGB(100, 100, 100))
    smoke.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.5),
        NumberSequenceKeypoint.new(1, 2),
    })
    smoke.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0),
        NumberSequenceKeypoint.new(1, 1),
    })
    smoke.Lifetime = NumberRange.new(0.5, 1.0)
    smoke.Rate = 80
    smoke.Speed = NumberRange.new(0, 2)
    smoke.Parent = missile

    -- Trail attachment
    local att0 = Instance.new("Attachment")
    att0.Position = Vector3.new(0, 0, cfg.size.Z / 2)
    att0.Parent = missile

    local att1 = Instance.new("Attachment")
    att1.Position = Vector3.new(0, 0, -cfg.size.Z / 2)
    att1.Parent = missile

    local trail = Instance.new("Trail")
    trail.Attachment0 = att0
    trail.Attachment1 = att1
    trail.Color = ColorSequence.new(cfg.trailColor)
    trail.Lifetime = 0.5
    trail.MinLength = 0.1
    trail.WidthScale = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1),
        NumberSequenceKeypoint.new(1, 0),
    })
    trail.Parent = missile

    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    local filterList: { Instance } = { missile }
    if owner and owner.Character then
        table.insert(filterList, owner.Character)
    end
    rayParams.FilterDescendantsInstances = filterList

    local currentDir = initialDirection.Unit
    local startTime = tick()
    local alive = true

    local connection = RunService.Heartbeat:Connect(function(dt: number)
        if not alive or not missile.Parent then return end

        -- Homing logic (after lock-on delay)
        if tick() - startTime > cfg.lockOnDelay and target and target.Parent then
            local toTarget = (target.Position - missile.Position).Unit
            local angle = math.acos(math.clamp(currentDir:Dot(toTarget), -1, 1))
            local maxTurn = cfg.turnRate * dt

            if angle > 0.001 then
                local t = math.min(maxTurn / angle, 1)
                currentDir = currentDir:Lerp(toTarget, t).Unit
            end
        end

        local movement = currentDir * cfg.speed * dt
        local ray = workspace:Raycast(missile.Position, movement, rayParams)

        if ray then
            alive = false

            -- Create explosion
            local explosion = Instance.new("Explosion")
            explosion.Position = ray.Position
            explosion.BlastRadius = cfg.explosionRadius
            explosion.BlastPressure = 0 -- we handle damage manually
            explosion.Parent = workspace

            -- Manual AOE damage
            local parts = workspace:GetPartBoundsInRadius(ray.Position, cfg.explosionRadius)
            local damagedModels: { Model } = {}

            for _, part in parts do
                local model = part:FindFirstAncestorOfClass("Model")
                if model and model ~= (owner and owner.Character) then
                    local humanoid = model:FindFirstChildWhichIsA("Humanoid")
                    if humanoid and humanoid.Health > 0 then
                        local found = false
                        for _, m in damagedModels do
                            if m == model then found = true; break end
                        end
                        if not found then
                            local dist = (part.Position - ray.Position).Magnitude
                            local falloff = 1 - math.clamp(dist / cfg.explosionRadius, 0, 1)
                            humanoid:TakeDamage(cfg.explosionDamage * falloff)
                            table.insert(damagedModels, model)
                        end
                    end
                end
            end

            missile:Destroy()
            return
        end

        missile.CFrame = CFrame.lookAt(missile.Position + movement, missile.Position + movement + currentDir)
    end)

    Debris:AddItem(missile, cfg.lifetime)
    task.delay(cfg.lifetime, function()
        alive = false
    end)

    return missile
end

return HomingMissile
```

---

## 5. Grenade with Arc

```luau
--!strict
-- ServerScriptService/GrenadeArc.lua
-- Thrown grenade with physics arc, bounce, and timed detonation.

local Debris = game:GetService("Debris")

local GrenadeArc = {}

export type GrenadeConfig = {
    throwForce: number,
    upwardAngle: number,       -- degrees added above aim direction
    damage: number,
    explosionRadius: number,
    fuseTime: number,          -- seconds before detonation
    bounceElasticity: number,
    size: number,
    color: Color3,
}

local DEFAULT_GRENADE: GrenadeConfig = {
    throwForce = 80,
    upwardAngle = 30,
    damage = 60,
    explosionRadius = 20,
    fuseTime = 3.0,
    bounceElasticity = 0.4,
    size = 0.8,
    color = Color3.fromRGB(50, 80, 50),
}

function GrenadeArc.throw(
    origin: Vector3,
    aimDirection: Vector3,
    owner: Player?,
    config: GrenadeConfig?
): Part
    local cfg = config or DEFAULT_GRENADE

    local grenade = Instance.new("Part")
    grenade.Name = "Grenade"
    grenade.Shape = Enum.PartType.Ball
    grenade.Size = Vector3.one * cfg.size
    grenade.Color = cfg.color
    grenade.Material = Enum.Material.Metal
    grenade.CFrame = CFrame.new(origin)
    grenade.CustomPhysicalProperties = PhysicalProperties.new(
        3,                      -- density (heavy)
        0,                      -- friction
        cfg.bounceElasticity,   -- elasticity
        1, 1
    )
    grenade.Parent = workspace

    -- Collision filter: don't hit owner initially
    if owner and owner.Character then
        local noCollision = Instance.new("NoCollisionConstraint")
        noCollision.Part0 = grenade
        local rootPart = owner.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
        if rootPart then
            noCollision.Part1 = rootPart
            noCollision.Parent = grenade
            Debris:AddItem(noCollision, 0.5) -- allow collision after 0.5s
        end
    end

    -- Calculate throw velocity with upward angle
    local horizontalDir = Vector3.new(aimDirection.X, 0, aimDirection.Z).Unit
    local upAngleRad = math.rad(cfg.upwardAngle)
    local throwDir = (horizontalDir * math.cos(upAngleRad) + Vector3.yAxis * math.sin(upAngleRad)).Unit
    grenade.AssemblyLinearVelocity = throwDir * cfg.throwForce

    -- Add spin
    grenade.AssemblyAngularVelocity = Vector3.new(
        math.random() * 10 - 5,
        math.random() * 10 - 5,
        math.random() * 10 - 5
    )

    -- Blinking indicator (visual fuse)
    local light = Instance.new("PointLight")
    light.Color = Color3.fromRGB(255, 0, 0)
    light.Brightness = 2
    light.Range = 8
    light.Parent = grenade

    -- Blink faster as fuse runs out
    task.spawn(function()
        local elapsed = 0
        while elapsed < cfg.fuseTime and grenade.Parent do
            local blinkRate = 0.5 * (1 - elapsed / cfg.fuseTime) + 0.05
            light.Enabled = not light.Enabled
            task.wait(blinkRate)
            elapsed += blinkRate
        end
    end)

    -- Detonation
    task.delay(cfg.fuseTime, function()
        if not grenade.Parent then return end

        local pos = grenade.Position

        -- Create explosion
        local explosion = Instance.new("Explosion")
        explosion.Position = pos
        explosion.BlastRadius = cfg.explosionRadius
        explosion.BlastPressure = 500
        explosion.DestroyJointRadiusPercent = 0
        explosion.Parent = workspace

        -- Manual damage with distance falloff
        explosion.Hit:Connect(function(hitPart: BasePart, distance: number)
            local model = hitPart:FindFirstAncestorOfClass("Model")
            if model then
                local humanoid = model:FindFirstChildWhichIsA("Humanoid")
                if humanoid and humanoid.Health > 0 then
                    local falloff = 1 - math.clamp(distance / cfg.explosionRadius, 0, 1)
                    humanoid:TakeDamage(cfg.damage * falloff)
                end
            end
        end)

        grenade:Destroy()
    end)

    return grenade
end

-- Utility: predict grenade arc for UI display
function GrenadeArc.predictArc(
    origin: Vector3,
    aimDirection: Vector3,
    config: GrenadeConfig?,
    steps: number?
): { Vector3 }
    local cfg = config or DEFAULT_GRENADE
    local numSteps = steps or 30

    local horizontalDir = Vector3.new(aimDirection.X, 0, aimDirection.Z).Unit
    local upAngleRad = math.rad(cfg.upwardAngle)
    local throwDir = (horizontalDir * math.cos(upAngleRad) + Vector3.yAxis * math.sin(upAngleRad)).Unit

    local velocity = throwDir * cfg.throwForce
    local gravity = Vector3.new(0, -workspace.Gravity, 0)
    local dt = cfg.fuseTime / numSteps

    local points: { Vector3 } = {}
    local pos = origin

    for i = 1, numSteps do
        table.insert(points, pos)
        velocity = velocity + gravity * dt
        pos = pos + velocity * dt
    end

    return points
end

return GrenadeArc
```

---

## 6. Trail Effect for Any Projectile

```luau
--!strict
-- ReplicatedStorage/ProjectileTrail.lua
-- Attaches a trail effect to any projectile part.

local ProjectileTrail = {}

export type TrailConfig = {
    color: Color3,
    secondaryColor: Color3?,
    width: number,
    lifetime: number,
    transparency: NumberSequence?,
    lightEmission: number,
    textureId: string?,
}

local DEFAULT_TRAIL: TrailConfig = {
    color = Color3.fromRGB(255, 200, 100),
    secondaryColor = nil,
    width = 0.5,
    lifetime = 0.3,
    transparency = nil,
    lightEmission = 1,
    textureId = nil,
}

function ProjectileTrail.attach(projectile: BasePart, config: TrailConfig?): Trail
    local cfg = config or DEFAULT_TRAIL

    -- Create two attachments offset along the projectile's width
    local att0 = Instance.new("Attachment")
    att0.Name = "TrailAtt0"
    att0.Position = Vector3.new(0, cfg.width / 2, 0)
    att0.Parent = projectile

    local att1 = Instance.new("Attachment")
    att1.Name = "TrailAtt1"
    att1.Position = Vector3.new(0, -cfg.width / 2, 0)
    att1.Parent = projectile

    local trail = Instance.new("Trail")
    trail.Name = "ProjectileTrail"
    trail.Attachment0 = att0
    trail.Attachment1 = att1
    trail.Lifetime = cfg.lifetime
    trail.LightEmission = cfg.lightEmission
    trail.MinLength = 0.05

    -- Color
    local color2 = cfg.secondaryColor or cfg.color
    trail.Color = ColorSequence.new(cfg.color, color2)

    -- Transparency
    trail.Transparency = cfg.transparency or NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0),
        NumberSequenceKeypoint.new(1, 1),
    })

    -- Width
    trail.WidthScale = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1),
        NumberSequenceKeypoint.new(1, 0),
    })

    if cfg.textureId then
        trail.Texture = cfg.textureId
    end

    trail.Parent = projectile

    return trail
end

-- Convenience: fire-style trail
function ProjectileTrail.attachFireTrail(projectile: BasePart): Trail
    return ProjectileTrail.attach(projectile, {
        color = Color3.fromRGB(255, 100, 0),
        secondaryColor = Color3.fromRGB(255, 50, 0),
        width = 0.8,
        lifetime = 0.4,
        lightEmission = 1,
    })
end

-- Convenience: ice-style trail
function ProjectileTrail.attachIceTrail(projectile: BasePart): Trail
    return ProjectileTrail.attach(projectile, {
        color = Color3.fromRGB(100, 200, 255),
        secondaryColor = Color3.fromRGB(200, 240, 255),
        width = 0.6,
        lifetime = 0.5,
        lightEmission = 0.5,
    })
end

return ProjectileTrail
```

---

## Guidelines

- **Hitscan** is instant and best for fast bullets; use `workspace:Raycast()`.
- **Physics projectiles** simulate movement each frame; use Heartbeat + manual position updates for server-authoritative control.
- **Always filter the shooter's character** from raycast params to prevent self-hits.
- **Homing missiles** use angular interpolation (`Lerp`) with a `turnRate` to smoothly track targets.
- **Grenade arcs** can be predicted client-side for trajectory UI using kinematic equations.
- **Trails** require two `Attachment`s on the projectile part. `Trail.Lifetime` controls how long the trail persists behind the moving object.
- Use `Debris:AddItem()` on all projectiles for guaranteed cleanup.
- For multiplayer, fire projectiles on the server; replicate visuals via RemoteEvents to clients.

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

When generating projectile code, adapt to these user-specified parameters:

- `$PROJECTILE_TYPE` - "hitscan" | "physics" | "magic" | "homing" | "grenade" (default: "hitscan")
- `$DAMAGE` - Damage on hit (default: 25)
- `$SPEED` - Projectile speed in studs/s (default: 150)
- `$LIFETIME` - Max seconds before auto-destroy (default: 5)
- `$HAS_TRAIL` - Whether to attach a trail effect (default: true)
- `$TRAIL_COLOR` - Trail color as RGB string (default: "255,200,100")
- `$PENETRATION` - Number of targets to pierce through (default: 0)
- `$AOE_RADIUS` - Area of effect radius on impact, 0 for none (default: 0)
- `$GRAVITY_AFFECTED` - Whether gravity applies (default: depends on type)
- `$STICK_ON_HIT` - Whether projectile sticks to target (default: false)
