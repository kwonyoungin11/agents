---
name: debris-cleanup
description: |
  Debris 서비스, 자동 정리 시스템, 메모리 관리, 비활성 인스턴스 감지, 가비지 컬렉션 패턴.
  Debris service usage, automatic cleanup system, memory management, stale instance detection, garbage collection patterns, instance lifecycle tracking, leak prevention.
allowed-tools:
  - Bash
  - Edit
  - Write
  - Read
  - Glob
  - Grep
effort: high
---

# Debris & Cleanup System

This skill covers the Debris service, automatic cleanup systems, memory management patterns, stale instance detection, instance lifecycle tracking, and leak prevention in Roblox.

---

## 1. Debris Service Basics

```luau
--!strict
-- The built-in Debris service schedules instance destruction after a delay.

local Debris = game:GetService("Debris")

-- Basic usage: destroy a part after 5 seconds
local part = Instance.new("Part")
part.Parent = workspace
Debris:AddItem(part, 5) -- Destroyed after 5 seconds

-- Common patterns:
-- Bullet cleanup
Debris:AddItem(bulletPart, 3)

-- VFX cleanup
Debris:AddItem(explosionEffect, 2)

-- Temporary sound
Debris:AddItem(soundInstance, soundInstance.TimeLength + 0.1)
```

---

## 2. Advanced Cleanup Manager

```luau
--!strict
-- ModuleScript: Comprehensive cleanup manager beyond basic Debris

local RunService = game:GetService("RunService")

local CleanupManager = {}
CleanupManager.__index = CleanupManager

export type CleanupEntry = {
    instance: Instance,
    addedAt: number,
    lifetime: number,
    onCleanup: ((Instance) -> ())?,
    tags: { string }?,
}

function CleanupManager.new(config: {
    checkInterval: number?,    -- Seconds between cleanup checks
    maxInstances: number?,     -- Hard cap on tracked instances
}?)
    local self = setmetatable({}, CleanupManager)
    local cfg = config or {}

    self._entries = {} :: { CleanupEntry }
    self._checkInterval = cfg.checkInterval or 1
    self._maxInstances = cfg.maxInstances or 5000
    self._running = true
    self._totalCleaned = 0

    -- Start cleanup loop
    task.spawn(function()
        while self._running do
            self:_processCleanup()
            task.wait(self._checkInterval)
        end
    end)

    return self
end

--- Registers an instance for automatic cleanup after a lifetime.
function CleanupManager.register(self: any, instance: Instance, lifetime: number, onCleanup: ((Instance) -> ())?, tags: { string }?)
    -- Enforce max instances
    if #self._entries >= self._maxInstances then
        -- Force-clean oldest entry
        local oldest = table.remove(self._entries, 1)
        if oldest then
            self:_cleanEntry(oldest)
        end
    end

    table.insert(self._entries, {
        instance = instance,
        addedAt = tick(),
        lifetime = lifetime,
        onCleanup = onCleanup,
        tags = tags,
    })
end

--- Immediately cleans all instances with a specific tag.
function CleanupManager.cleanByTag(self: any, tag: string)
    local remaining: { CleanupEntry } = {}
    for _, entry in self._entries do
        local hasTag = false
        if entry.tags then
            for _, t in entry.tags do
                if t == tag then
                    hasTag = true
                    break
                end
            end
        end

        if hasTag then
            self:_cleanEntry(entry)
        else
            table.insert(remaining, entry)
        end
    end
    self._entries = remaining
end

--- Immediately cleans all tracked instances.
function CleanupManager.cleanAll(self: any)
    for _, entry in self._entries do
        self:_cleanEntry(entry)
    end
    self._entries = {}
end

function CleanupManager._processCleanup(self: any)
    local now = tick()
    local remaining: { CleanupEntry } = {}

    for _, entry in self._entries do
        if not entry.instance or not entry.instance.Parent then
            -- Already destroyed externally, skip
            continue
        end

        if now - entry.addedAt >= entry.lifetime then
            self:_cleanEntry(entry)
        else
            table.insert(remaining, entry)
        end
    end

    self._entries = remaining
end

function CleanupManager._cleanEntry(self: any, entry: CleanupEntry)
    if entry.onCleanup then
        entry.onCleanup(entry.instance)
    end
    if entry.instance and entry.instance.Parent then
        entry.instance:Destroy()
    end
    self._totalCleaned += 1
end

--- Returns cleanup statistics.
function CleanupManager.getStats(self: any): { tracked: number, totalCleaned: number }
    return {
        tracked = #self._entries,
        totalCleaned = self._totalCleaned,
    }
end

--- Stops the cleanup loop and destroys all tracked instances.
function CleanupManager.shutdown(self: any)
    self._running = false
    self:cleanAll()
end

return CleanupManager
```

---

## 3. Stale Instance Detector

```luau
--!strict
-- ModuleScript: Detects and cleans up stale/orphaned instances

local RunService = game:GetService("RunService")

local StaleDetector = {}

export type StaleConfig = {
    scanFolder: Instance,          -- Folder to scan for stale instances
    maxAge: number?,               -- Seconds before an instance is considered stale
    checkInterval: number?,        -- Seconds between scans
    whitelist: { string }?,        -- Instance names to never clean
    onStaleFound: ((Instance) -> boolean)?, -- Return true to allow cleanup
}

--- Starts monitoring a folder for stale instances.
function StaleDetector.monitor(config: StaleConfig): () -> ()
    local maxAge = config.maxAge or 60
    local interval = config.checkInterval or 10
    local whitelist = {}
    if config.whitelist then
        for _, name in config.whitelist do
            whitelist[name] = true
        end
    end

    -- Track when instances were first seen
    local firstSeen: { [Instance]: number } = {}
    local running = true

    task.spawn(function()
        while running do
            local now = tick()

            for _, child in config.scanFolder:GetChildren() do
                if whitelist[child.Name] then continue end

                if not firstSeen[child] then
                    firstSeen[child] = now
                elseif now - firstSeen[child] >= maxAge then
                    local shouldClean = true
                    if config.onStaleFound then
                        shouldClean = config.onStaleFound(child)
                    end
                    if shouldClean then
                        child:Destroy()
                        firstSeen[child] = nil
                    end
                end
            end

            -- Clean up tracking for destroyed instances
            for instance in firstSeen do
                if not instance.Parent then
                    firstSeen[instance] = nil
                end
            end

            task.wait(interval)
        end
    end)

    return function()
        running = false
    end
end

return StaleDetector
```

---

## 4. Connection Cleanup (Maid/Janitor Pattern)

```luau
--!strict
-- ModuleScript: Manages cleanup of connections, instances, and callbacks

local Janitor = {}
Janitor.__index = Janitor

type CleanupItem = Instance | RBXScriptConnection | () -> () | { Destroy: (any) -> () }

function Janitor.new()
    local self = setmetatable({}, Janitor)
    self._items = {} :: { [string]: CleanupItem }
    self._itemList = {} :: { CleanupItem }
    return self
end

--- Adds an item to the janitor with an optional key.
--- Supports: Instances (destroyed), Connections (disconnected), Functions (called), tables with Destroy method.
function Janitor.add(self: any, item: CleanupItem, key: string?): CleanupItem
    if key then
        -- If key already exists, clean up the old item first
        if self._items[key] then
            self:_cleanItem(self._items[key])
        end
        self._items[key] = item
    else
        table.insert(self._itemList, item)
    end
    return item
end

--- Adds a connection to the janitor.
function Janitor.addConnection(self: any, connection: RBXScriptConnection, key: string?): RBXScriptConnection
    self:add(connection, key)
    return connection
end

--- Removes and cleans up an item by key.
function Janitor.remove(self: any, key: string)
    local item = self._items[key]
    if item then
        self:_cleanItem(item)
        self._items[key] = nil
    end
end

--- Cleans up all registered items.
function Janitor.cleanup(self: any)
    for key, item in self._items do
        self:_cleanItem(item)
    end
    for _, item in self._itemList do
        self:_cleanItem(item)
    end
    self._items = {}
    self._itemList = {}
end

--- Alias for cleanup + prevents further use.
function Janitor.destroy(self: any)
    self:cleanup()
end

function Janitor._cleanItem(self: any, item: CleanupItem)
    local itemType = typeof(item)

    if itemType == "RBXScriptConnection" then
        (item :: RBXScriptConnection):Disconnect()
    elseif itemType == "Instance" then
        (item :: Instance):Destroy()
    elseif itemType == "function" then
        (item :: () -> ())()
    elseif itemType == "table" then
        local tbl = item :: any
        if tbl.Destroy then
            tbl:Destroy()
        elseif tbl.Disconnect then
            tbl:Disconnect()
        end
    end
end

--- Links the janitor to an instance: auto-cleanup when instance is destroyed.
function Janitor.linkToInstance(self: any, instance: Instance): ()
    instance.Destroying:Connect(function()
        self:cleanup()
    end)
end

return Janitor
```

---

## 5. Memory Leak Prevention Patterns

```luau
--!strict
-- Example: Common patterns that cause memory leaks and their fixes

-- BAD: Connection never disconnected
local function badPattern()
    local part = Instance.new("Part")
    part.Parent = workspace

    -- This connection keeps the part alive even after Destroy
    part.Touched:Connect(function() end)
    -- If part is destroyed but the connection is held in a table, it leaks
end

-- GOOD: Use Janitor to track connections
local function goodPattern()
    local Janitor = require(path.to.Janitor)
    local janitor = Janitor.new()

    local part = Instance.new("Part")
    janitor:add(part)
    part.Parent = workspace

    janitor:addConnection(part.Touched:Connect(function() end))

    -- Later, when done:
    janitor:cleanup() -- Destroys part AND disconnects the event
end

-- BAD: RunService connection without cleanup
local function badHeartbeat()
    RunService.Heartbeat:Connect(function()
        -- This runs FOREVER, even if the associated object is gone
    end)
end

-- GOOD: Track and disconnect
local function goodHeartbeat()
    local connection = RunService.Heartbeat:Connect(function()
        -- Process
    end)

    -- When done:
    connection:Disconnect()
end

-- BAD: Storing references to destroyed instances
local cache = {}
local function badCache(part: Part)
    cache[part] = { data = "something" }
    -- Even after part:Destroy(), the cache holds a reference
end

-- GOOD: Clean up cache when instances are destroyed
local function goodCache(part: Part)
    cache[part] = { data = "something" }
    part.Destroying:Connect(function()
        cache[part] = nil
    end)
end
```

---

## 6. Workspace Sweeper

```luau
--!strict
-- ServerScript: Periodic workspace cleanup for unanchored debris

local Debris = game:GetService("Debris")

local WorkspaceSweeper = {}

--- Sweeps workspace for fallen/unanchored parts below a Y threshold.
function WorkspaceSweeper.start(config: {
    yThreshold: number?,     -- Parts below this Y are cleaned up
    interval: number?,       -- Seconds between sweeps
    ignoreTags: { string }?, -- CollectionService tags to ignore
}?): () -> ()
    local cfg = config or {}
    local yThreshold = cfg.yThreshold or -200
    local interval = cfg.interval or 15
    local ignoreTags = {}
    local CollectionService = game:GetService("CollectionService")

    if cfg.ignoreTags then
        for _, tag in cfg.ignoreTags do
            ignoreTags[tag] = true
        end
    end

    local running = true

    task.spawn(function()
        while running do
            task.wait(interval)

            local cleaned = 0
            for _, obj in workspace:GetDescendants() do
                if obj:IsA("BasePart") and not obj.Anchored then
                    if obj.Position.Y < yThreshold then
                        -- Check for ignore tags
                        local skip = false
                        for tag in ignoreTags do
                            if CollectionService:HasTag(obj, tag) then
                                skip = true
                                break
                            end
                        end

                        if not skip then
                            obj:Destroy()
                            cleaned += 1
                        end
                    end
                end
            end

            if cleaned > 0 then
                -- Optional: log cleanup
            end
        end
    end)

    return function()
        running = false
    end
end

return WorkspaceSweeper
```

---

## Best Practices

1. **Debris:AddItem for simple cases**: Use when you just need timed destruction
2. **CleanupManager for complex cases**: Use when you need callbacks, tags, or batch operations
3. **Janitor for component lifecycle**: Pair with tag-based components for clean teardown
4. **Always disconnect events**: Connections are the #1 source of memory leaks
5. **Monitor instance counts**: Track `workspace:GetDescendantCount()` over time
6. **Use Instance.Destroying**: Modern replacement for polling; fires before destruction

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

- `lifetime` (number) - Seconds before automatic cleanup
- `check_interval` (number) - Seconds between cleanup checks
- `max_instances` (number) - Hard cap on tracked instances
- `cleanup_tag` (string) - Tag for batch cleanup operations
- `y_threshold` (number) - Y position below which parts are cleaned (default: -200)
- `sweep_interval` (number) - Seconds between workspace sweeps
- `max_age` (number) - Seconds before an instance is considered stale
- `scan_folder` (Instance) - Folder to scan for stale instances
- `whitelist` (table) - Instance names exempt from cleanup
