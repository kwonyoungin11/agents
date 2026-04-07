---
name: instance-pool
description: |
  오브젝트 풀링 성능 최적화, 사전 생성 및 재사용, 탄환/이펙트 풀 매니저, 메모리 효율 인스턴스 관리.
  Object pooling for performance optimization, pre-create and reuse instances, pool manager for bullets/effects/particles, memory-efficient instance lifecycle management, dynamic pool sizing.
allowed-tools:
  - Bash
  - Edit
  - Write
  - Read
  - Glob
  - Grep
effort: high
---

# Instance Pool System

This skill covers object pooling patterns for performance optimization, pre-creating and reusing instances, pool managers for bullets, effects, and particles, dynamic pool sizing, and memory-efficient instance lifecycle management in Roblox.

---

## 1. Generic Object Pool

```luau
--!strict
-- ModuleScript: Generic reusable object pool

local ObjectPool = {}
ObjectPool.__index = ObjectPool

export type PoolConfig<T> = {
    create: () -> T,             -- Factory function to create a new instance
    reset: (obj: T) -> (),       -- Function to reset an instance for reuse
    initialSize: number?,        -- Number of instances to pre-create
    maxSize: number?,            -- Maximum pool size (0 = unlimited)
    expandSize: number?,         -- Number to create when pool is empty
    storageParent: Instance?,    -- Where to parent inactive instances
}

function ObjectPool.new<T>(config: PoolConfig<T>)
    local self = setmetatable({}, ObjectPool)

    self._create = config.create
    self._reset = config.reset
    self._maxSize = config.maxSize or 0
    self._expandSize = config.expandSize or 5
    self._storageParent = config.storageParent

    self._available = {} :: { T }     -- Pool of available instances
    self._inUse = {} :: { [T]: boolean }  -- Tracking active instances
    self._totalCreated = 0

    -- Pre-populate the pool
    local initialSize = config.initialSize or 10
    for _ = 1, initialSize do
        local obj = self:_createNew()
        table.insert(self._available, obj)
    end

    return self
end

function ObjectPool._createNew(self: any): any
    local obj = self._create()
    self._totalCreated += 1

    -- Move to storage if applicable
    if self._storageParent and typeof(obj) == "Instance" then
        (obj :: Instance).Parent = self._storageParent
    end

    return obj
end

--- Acquires an instance from the pool (creates new if pool is empty).
function ObjectPool.acquire(self: any): any
    local obj: any

    if #self._available > 0 then
        obj = table.remove(self._available)
    else
        -- Pool is empty, expand
        if self._maxSize > 0 and self._totalCreated >= self._maxSize then
            warn("[ObjectPool] Max pool size reached:", self._maxSize)
            return nil
        end

        -- Create a batch of new instances
        for _ = 1, self._expandSize - 1 do
            if self._maxSize > 0 and self._totalCreated >= self._maxSize then break end
            local newObj = self:_createNew()
            table.insert(self._available, newObj)
        end

        obj = self:_createNew()
    end

    self._inUse[obj] = true
    return obj
end

--- Returns an instance to the pool for reuse.
function ObjectPool.release(self: any, obj: any)
    if not self._inUse[obj] then
        warn("[ObjectPool] Attempted to release an object not from this pool")
        return
    end

    self._inUse[obj] = nil
    self._reset(obj)

    -- Move to storage
    if self._storageParent and typeof(obj) == "Instance" then
        (obj :: Instance).Parent = self._storageParent
    end

    table.insert(self._available, obj)
end

--- Returns the number of available instances.
function ObjectPool.getAvailable(self: any): number
    return #self._available
end

--- Returns the number of instances currently in use.
function ObjectPool.getInUse(self: any): number
    local count = 0
    for _ in self._inUse do
        count += 1
    end
    return count
end

--- Returns the total number of instances created.
function ObjectPool.getTotalCreated(self: any): number
    return self._totalCreated
end

--- Destroys all instances and clears the pool.
function ObjectPool.destroy(self: any)
    for _, obj in self._available do
        if typeof(obj) == "Instance" then
            (obj :: Instance):Destroy()
        end
    end
    for obj in self._inUse do
        if typeof(obj) == "Instance" then
            (obj :: Instance):Destroy()
        end
    end
    self._available = {}
    self._inUse = {}
end

return ObjectPool
```

---

## 2. Bullet Pool

```luau
--!strict
-- ModuleScript: Specialized bullet pool with auto-return

local ObjectPool = require(script.Parent.ObjectPool)

local BulletPool = {}

local BULLET_STORAGE = Instance.new("Folder")
BULLET_STORAGE.Name = "BulletPool"
BULLET_STORAGE.Parent = game:GetService("ReplicatedStorage")

--- Creates a bullet pool with pre-configured bullet parts.
function BulletPool.new(config: {
    initialSize: number?,
    maxSize: number?,
    bulletSize: Vector3?,
    bulletColor: Color3?,
    bulletMaterial: Enum.Material?,
    lifetime: number?, -- auto-return after this many seconds
}?)
    local cfg = config or {}
    local lifetime = cfg.lifetime or 5

    local pool = ObjectPool.new({
        create = function(): Part
            local bullet = Instance.new("Part")
            bullet.Name = "PooledBullet"
            bullet.Size = cfg.bulletSize or Vector3.new(0.3, 0.3, 1.5)
            bullet.Color = cfg.bulletColor or Color3.fromRGB(255, 200, 50)
            bullet.Material = cfg.bulletMaterial or Enum.Material.Neon
            bullet.Anchored = false
            bullet.CanCollide = false
            bullet.CastShadow = false
            bullet.Transparency = 1 -- Hidden when in pool

            -- Attachment for trail
            local attachment = Instance.new("Attachment")
            attachment.Parent = bullet

            return bullet
        end,

        reset = function(bullet: Part)
            bullet.Anchored = true
            bullet.Transparency = 1
            bullet.CFrame = CFrame.new(0, -1000, 0) -- Move offscreen
            bullet.Parent = BULLET_STORAGE

            -- Clear velocities
            for _, child in bullet:GetChildren() do
                if child:IsA("BodyMover") or child:IsA("LinearVelocity") then
                    child:Destroy()
                end
            end
        end,

        initialSize = cfg.initialSize or 50,
        maxSize = cfg.maxSize or 200,
        expandSize = 10,
        storageParent = BULLET_STORAGE,
    })

    local wrapper = {
        _pool = pool,
        _lifetime = lifetime,
    }

    --- Fires a bullet from the pool.
    function wrapper.fire(origin: CFrame, speed: number): Part?
        local bullet = pool:acquire()
        if not bullet then return nil end

        bullet.CFrame = origin
        bullet.Transparency = 0
        bullet.Anchored = false
        bullet.Parent = workspace

        -- Apply velocity
        local velocity = Instance.new("BodyVelocity")
        velocity.Velocity = origin.LookVector * speed
        velocity.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
        velocity.Parent = bullet

        -- Auto-return after lifetime
        task.delay(lifetime, function()
            if pool._inUse[bullet] then
                pool:release(bullet)
            end
        end)

        return bullet
    end

    --- Manually returns a bullet to the pool.
    function wrapper.returnBullet(bullet: Part)
        pool:release(bullet)
    end

    --- Gets pool statistics.
    function wrapper.getStats(): { available: number, inUse: number, total: number }
        return {
            available = pool:getAvailable(),
            inUse = pool:getInUse(),
            total = pool:getTotalCreated(),
        }
    end

    --- Destroys the entire pool.
    function wrapper.destroy()
        pool:destroy()
        BULLET_STORAGE:Destroy()
    end

    return wrapper
end

return BulletPool
```

---

## 3. VFX / Particle Pool

```luau
--!strict
-- ModuleScript: Pool for visual effects (explosions, hit effects, etc.)

local ObjectPool = require(script.Parent.ObjectPool)

local VFXPool = {}

--- Creates a pool for VFX instances cloned from a template.
function VFXPool.new(template: Instance, config: {
    initialSize: number?,
    maxSize: number?,
    defaultDuration: number?, -- how long VFX plays before auto-return
}?)
    local cfg = config or {}
    local defaultDuration = cfg.defaultDuration or 2

    local storage = Instance.new("Folder")
    storage.Name = template.Name .. "_VFXPool"
    storage.Parent = game:GetService("ReplicatedStorage")

    local pool = ObjectPool.new({
        create = function(): Instance
            local clone = template:Clone()
            -- Disable all emitters initially
            for _, desc in clone:GetDescendants() do
                if desc:IsA("ParticleEmitter") then
                    desc.Enabled = false
                end
            end
            return clone
        end,

        reset = function(obj: Instance)
            -- Disable emitters
            for _, desc in obj:GetDescendants() do
                if desc:IsA("ParticleEmitter") then
                    desc.Enabled = false
                    desc:Clear()
                end
                if desc:IsA("Light") then
                    desc.Enabled = false
                end
            end
            obj.Parent = storage
        end,

        initialSize = cfg.initialSize or 10,
        maxSize = cfg.maxSize or 50,
        expandSize = 5,
        storageParent = storage,
    })

    local wrapper = {}

    --- Plays a VFX at the specified position.
    function wrapper.play(position: Vector3, duration: number?): Instance?
        local vfx = pool:acquire()
        if not vfx then return nil end

        local dur = duration or defaultDuration

        -- Position the VFX
        if vfx:IsA("BasePart") then
            vfx.Position = position
        elseif vfx:IsA("Model") and vfx.PrimaryPart then
            vfx:PivotTo(CFrame.new(position))
        elseif vfx:IsA("Attachment") then
            vfx.WorldPosition = position
        end

        vfx.Parent = workspace

        -- Enable all emitters
        for _, desc in vfx:GetDescendants() do
            if desc:IsA("ParticleEmitter") then
                desc.Enabled = true
            end
            if desc:IsA("Light") then
                desc.Enabled = true
            end
        end

        -- Auto-return after duration
        task.delay(dur, function()
            -- Disable emitters first, wait for particles to fade
            for _, desc in vfx:GetDescendants() do
                if desc:IsA("ParticleEmitter") then
                    desc.Enabled = false
                end
            end
            task.wait(1) -- Wait for particles to fully fade
            if pool._inUse[vfx] then
                pool:release(vfx)
            end
        end)

        return vfx
    end

    function wrapper.destroy()
        pool:destroy()
        storage:Destroy()
    end

    return wrapper
end

return VFXPool
```

---

## 4. Sound Pool

```luau
--!strict
-- ModuleScript: Pool for Sound instances (avoids creating new Sounds per play)

local ObjectPool = require(script.Parent.ObjectPool)

local SoundPool = {}

--- Creates a pool of Sound instances for a single sound effect.
function SoundPool.new(soundId: string, config: {
    initialSize: number?,
    maxSize: number?,
    volume: number?,
    playbackSpeed: number?,
}?)
    local cfg = config or {}

    local storage = Instance.new("Folder")
    storage.Name = "SoundPool_" .. soundId:match("%d+") or "unknown"
    storage.Parent = game:GetService("SoundService")

    local pool = ObjectPool.new({
        create = function(): Sound
            local sound = Instance.new("Sound")
            sound.SoundId = soundId
            sound.Volume = cfg.volume or 1
            sound.PlaybackSpeed = cfg.playbackSpeed or 1
            return sound
        end,

        reset = function(sound: Sound)
            sound:Stop()
            sound.Parent = storage
        end,

        initialSize = cfg.initialSize or 5,
        maxSize = cfg.maxSize or 20,
        expandSize = 3,
        storageParent = storage,
    })

    local wrapper = {}

    --- Plays the sound at a position (3D sound) or globally.
    function wrapper.play(parent: Instance?): Sound?
        local sound = pool:acquire()
        if not sound then return nil end

        sound.Parent = parent or storage
        sound:Play()

        sound.Ended:Once(function()
            if pool._inUse[sound] then
                pool:release(sound)
            end
        end)

        return sound
    end

    function wrapper.destroy()
        pool:destroy()
        storage:Destroy()
    end

    return wrapper
end

return SoundPool
```

---

## 5. Pool Monitor (Debug)

```luau
--!strict
-- ModuleScript: Debug monitoring for pool statistics

local RunService = game:GetService("RunService")

local PoolMonitor = {}

export type PoolStats = {
    name: string,
    available: number,
    inUse: number,
    total: number,
}

local registeredPools: { { name: string, getStats: () -> PoolStats } } = {}

--- Registers a pool for monitoring.
function PoolMonitor.register(name: string, getStats: () -> { available: number, inUse: number, total: number })
    table.insert(registeredPools, {
        name = name,
        getStats = function(): PoolStats
            local stats = getStats()
            return {
                name = name,
                available = stats.available,
                inUse = stats.inUse,
                total = stats.total,
            }
        end,
    })
end

--- Returns current stats for all registered pools.
function PoolMonitor.getAllStats(): { PoolStats }
    local allStats: { PoolStats } = {}
    for _, pool in registeredPools do
        table.insert(allStats, pool.getStats())
    end
    return allStats
end

--- Prints pool stats to output (debug only).
function PoolMonitor.printStats()
    print("=== Pool Monitor ===")
    for _, pool in registeredPools do
        local stats = pool.getStats()
        print(string.format("  [%s] Available: %d | In Use: %d | Total: %d",
            stats.name, stats.available, stats.inUse, stats.total))
    end
    print("====================")
end

--- Starts periodic logging of pool stats.
function PoolMonitor.startLogging(intervalSeconds: number): () -> ()
    local running = true
    task.spawn(function()
        while running do
            PoolMonitor.printStats()
            task.wait(intervalSeconds)
        end
    end)
    return function()
        running = false
    end
end

return PoolMonitor
```

---

## When to Use Object Pooling

| Scenario | Pool? | Reason |
|---|---|---|
| Bullets fired rapidly | Yes | Hundreds created/destroyed per second |
| Particle VFX (hits, explosions) | Yes | Frequent short-lived instances |
| Sound effects | Yes | Avoids Sound:Play() overhead |
| NPCs spawning once | No | Infrequent creation |
| Static map parts | No | Created once, never destroyed |
| UI elements that toggle | Maybe | Only if creating/destroying frequently |

### Performance Rules

- Pool when creating > 5 instances per second
- Pre-allocate for the expected peak count
- Set maxSize to prevent memory leaks
- Always reset state completely on release
- Parent inactive items to nil or a storage folder (not workspace)

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

- `initial_size` (number) - Number of instances to pre-create (default: 10)
- `max_size` (number) - Maximum pool capacity (0 = unlimited)
- `expand_size` (number) - Batch size when pool is empty (default: 5)
- `lifetime` (number) - Auto-return duration in seconds for bullets/VFX
- `bullet_speed` (number) - Bullet velocity magnitude
- `bullet_color` (Color3) - Bullet part color
- `vfx_template` (Instance) - Template instance for VFX pool
- `vfx_duration` (number) - Default VFX play duration
- `sound_id` (string) - rbxassetid:// sound ID for sound pool
- `sound_volume` (number) - Sound volume 0-1
