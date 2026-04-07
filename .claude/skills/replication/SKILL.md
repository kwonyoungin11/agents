---
name: replication
description: |
  Replication best practices for Roblox. ValueObjects for state sync, Attribute-based
  sync patterns, minimal RemoteEvent data payloads, client prediction, eventual
  consistency, and bandwidth optimization.
  복제 베스트 프랙티스, ValueObject 동기화, 속성 동기화, 최소 RemoteEvent 데이터, 대역폭 최적화
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
effort: high
---

# Replication Best Practices

Patterns and utilities for efficient state replication in Roblox: ValueObjects, Attributes, minimal RemoteEvent payloads, client prediction, and bandwidth optimization.

## Architecture Overview

```
ServerScriptService/
  ReplicationService.server.lua  -- Server-side state management and sync
ReplicatedStorage/
  ReplicationLib.lua             -- Shared replication utilities
  StateStore.lua                 -- Replicated state store (server writes, client reads)
  NetworkOptimizer.lua           -- Payload compression and batching
StarterPlayerScripts/
  ReplicationClient.lua          -- Client-side state reading and prediction
```

## Replication Strategy Reference

| Method | Direction | Auto-Replicates | Best For |
|--------|-----------|-----------------|----------|
| Attributes | Server->Client | Yes | Simple values on instances |
| ValueObjects | Server->Client | Yes | Typed values, .Changed event |
| RemoteEvent | Bi-directional | No (manual) | Actions, events, one-off data |
| RemoteFunction | Client->Server | No (manual) | Request-response patterns |
| ReplicatedStorage | Server->Client | Yes (children) | Shared modules, config |
| Player:SetAttribute | Server->Client | Yes | Per-player state |

## State Store (Attribute-Based Sync)

```lua
-- ReplicatedStorage/StateStore.lua
-- A replicated state store using Attributes on a shared folder.
-- Server writes attributes; clients read and listen for changes.
-- Attributes auto-replicate to all clients.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StateStore = {}

-- Namespace folders for organized state
local storeRoot = ReplicatedStorage:FindFirstChild("GameState")
if not storeRoot then
    storeRoot = Instance.new("Folder")
    storeRoot.Name = "GameState"
    storeRoot.Parent = ReplicatedStorage
end

--------------------------------------------------------------------------------
-- Get or create a namespace folder
--------------------------------------------------------------------------------
local function getNamespace(namespace: string): Folder
    local folder = storeRoot:FindFirstChild(namespace)
    if not folder then
        folder = Instance.new("Folder")
        folder.Name = namespace
        folder.Parent = storeRoot
    end
    return folder
end

--------------------------------------------------------------------------------
-- SERVER ONLY: Set a value in the state store
-- Attributes replicate automatically to all clients
--------------------------------------------------------------------------------
function StateStore.set(namespace: string, key: string, value: any)
    local folder = getNamespace(namespace)
    folder:SetAttribute(key, value)
end

--------------------------------------------------------------------------------
-- Read a value (works on both server and client)
--------------------------------------------------------------------------------
function StateStore.get(namespace: string, key: string): any
    local folder = storeRoot:FindFirstChild(namespace)
    if not folder then return nil end
    return folder:GetAttribute(key)
end

--------------------------------------------------------------------------------
-- Listen for changes to a specific key
--------------------------------------------------------------------------------
function StateStore.onChange(namespace: string, key: string, callback: (any) -> ()): RBXScriptConnection
    local folder = getNamespace(namespace)
    return folder:GetAttributeChangedSignal(key):Connect(function()
        callback(folder:GetAttribute(key))
    end)
end

--------------------------------------------------------------------------------
-- Listen for any change in a namespace
--------------------------------------------------------------------------------
function StateStore.onAnyChange(namespace: string, callback: (string, any) -> ()): RBXScriptConnection
    local folder = getNamespace(namespace)
    return folder.AttributeChanged:Connect(function(attributeName)
        callback(attributeName, folder:GetAttribute(attributeName))
    end)
end

--------------------------------------------------------------------------------
-- Get all key-value pairs in a namespace
--------------------------------------------------------------------------------
function StateStore.getAll(namespace: string): { [string]: any }
    local folder = storeRoot:FindFirstChild(namespace)
    if not folder then return {} end
    return folder:GetAttributes()
end

--------------------------------------------------------------------------------
-- Per-player state (stored on Player instance)
-- Auto-replicates to that specific player
--------------------------------------------------------------------------------
function StateStore.setPlayerState(player: Player, key: string, value: any)
    player:SetAttribute(key, value)
end

function StateStore.getPlayerState(player: Player, key: string): any
    return player:GetAttribute(key)
end

function StateStore.onPlayerStateChange(player: Player, key: string, callback: (any) -> ()): RBXScriptConnection
    return player:GetAttributeChangedSignal(key):Connect(function()
        callback(player:GetAttribute(key))
    end)
end

return StateStore
```

## ValueObject-Based Sync

```lua
-- ReplicatedStorage/ReplicationLib.lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ReplicationLib = {}

-- Container for all ValueObjects
local valueStore = ReplicatedStorage:FindFirstChild("ValueStore")
if not valueStore then
    valueStore = Instance.new("Folder")
    valueStore.Name = "ValueStore"
    valueStore.Parent = ReplicatedStorage
end

--------------------------------------------------------------------------------
-- Type map: Luau type -> ValueObject class
--------------------------------------------------------------------------------
local VALUE_CLASS_MAP = {
    string = "StringValue",
    number = "NumberValue",
    boolean = "BoolValue",
    Vector3 = "Vector3Value",
    CFrame = "CFrameValue",
    Color3 = "Color3Value",
    Instance = "ObjectValue",
    Ray = "RayValue",
    BrickColor = "BrickColorValue",
}

local function getValueClass(value: any): string
    local t = typeof(value)
    return VALUE_CLASS_MAP[t] or error("Unsupported type for ValueObject: " .. t)
end

--------------------------------------------------------------------------------
-- Create or get a replicated ValueObject
-- Server creates; client waits for it
--------------------------------------------------------------------------------
function ReplicationLib.createValue(name: string, initialValue: any): ValueBase
    local existing = valueStore:FindFirstChild(name)
    if existing then
        return existing
    end

    local className = getValueClass(initialValue)
    local valueObj = Instance.new(className)
    valueObj.Name = name
    valueObj.Value = initialValue
    valueObj.Parent = valueStore
    return valueObj
end

function ReplicationLib.getValue(name: string): any
    local obj = valueStore:FindFirstChild(name)
    return obj and obj.Value
end

function ReplicationLib.waitForValue(name: string): ValueBase
    return valueStore:WaitForChild(name)
end

function ReplicationLib.onValueChanged(name: string, callback: (any) -> ()): RBXScriptConnection
    local obj = valueStore:WaitForChild(name)
    return obj.Changed:Connect(callback)
end

--------------------------------------------------------------------------------
-- Per-player ValueObjects (stored under player in ReplicatedStorage)
-- Only replicates to the owning player
--------------------------------------------------------------------------------
function ReplicationLib.createPlayerValue(player: Player, name: string, initialValue: any): ValueBase
    local playerFolder = player:FindFirstChild("PlayerValues")
    if not playerFolder then
        playerFolder = Instance.new("Folder")
        playerFolder.Name = "PlayerValues"
        playerFolder.Parent = player
    end

    local className = getValueClass(initialValue)
    local valueObj = Instance.new(className)
    valueObj.Name = name
    valueObj.Value = initialValue
    valueObj.Parent = playerFolder
    return valueObj
end

return ReplicationLib
```

## Network Optimizer (Minimal Payloads)

```lua
-- ReplicatedStorage/NetworkOptimizer.lua
local RunService = game:GetService("RunService")

local NetworkOptimizer = {}

--------------------------------------------------------------------------------
-- Payload size estimation (for debugging)
--------------------------------------------------------------------------------
function NetworkOptimizer.estimateSize(data: any): number
    local t = typeof(data)
    if t == "nil" then return 1
    elseif t == "boolean" then return 1
    elseif t == "number" then return 8
    elseif t == "string" then return #data + 2
    elseif t == "Vector3" then return 12
    elseif t == "Vector2" then return 8
    elseif t == "CFrame" then return 48
    elseif t == "Color3" then return 12
    elseif t == "BrickColor" then return 4
    elseif t == "EnumItem" then return 4
    elseif t == "Instance" then return 8 -- reference
    elseif t == "table" then
        local size = 4 -- overhead
        for k, v in data do
            size += NetworkOptimizer.estimateSize(k) + NetworkOptimizer.estimateSize(v)
        end
        return size
    end
    return 16
end

--------------------------------------------------------------------------------
-- Delta compression: only send changed fields
--------------------------------------------------------------------------------
function NetworkOptimizer.computeDelta(previous: { [string]: any }, current: { [string]: any }): { [string]: any }?
    local delta = {}
    local hasChanges = false

    for key, value in current do
        if previous[key] ~= value then
            delta[key] = value
            hasChanges = true
        end
    end

    -- Mark removed keys
    for key in previous do
        if current[key] == nil then
            delta[key] = "__REMOVED__"
            hasChanges = true
        end
    end

    return if hasChanges then delta else nil
end

function NetworkOptimizer.applyDelta(state: { [string]: any }, delta: { [string]: any }): { [string]: any }
    local result = table.clone(state)
    for key, value in delta do
        if value == "__REMOVED__" then
            result[key] = nil
        else
            result[key] = value
        end
    end
    return result
end

--------------------------------------------------------------------------------
-- Event batching: accumulate events and send in batches
--------------------------------------------------------------------------------
export type EventBatcher = {
    flush: () -> (),
    add: (data: any) -> (),
    destroy: () -> (),
}

function NetworkOptimizer.createBatcher(
    remote: RemoteEvent,
    interval: number?, -- batch interval in seconds (default 0.1)
    isServer: boolean?
): EventBatcher
    local batchInterval = interval or 0.1
    local queue: { any } = {}
    local running = true

    local function flush()
        if #queue == 0 then return end
        local batch = queue
        queue = {}

        if isServer then
            remote:FireAllClients("Batch", batch)
        else
            remote:FireServer("Batch", batch)
        end
    end

    -- Auto-flush on interval
    task.spawn(function()
        while running do
            task.wait(batchInterval)
            flush()
        end
    end)

    return {
        add = function(data: any)
            table.insert(queue, data)
        end,
        flush = flush,
        destroy = function()
            running = false
            flush()
        end,
    }
end

--------------------------------------------------------------------------------
-- Rate limiter: throttle how often a remote can be fired
--------------------------------------------------------------------------------
export type RateLimiter = {
    canFire: () -> boolean,
    fire: (...any) -> boolean,
}

function NetworkOptimizer.createRateLimiter(
    remote: RemoteEvent,
    maxPerSecond: number,
    isServer: boolean?
): RateLimiter
    local minInterval = 1 / maxPerSecond
    local lastFired = 0

    return {
        canFire = function(): boolean
            return (tick() - lastFired) >= minInterval
        end,
        fire = function(...: any): boolean
            local now = tick()
            if now - lastFired < minInterval then
                return false
            end
            lastFired = now
            if isServer then
                remote:FireAllClients(...)
            else
                remote:FireServer(...)
            end
            return true
        end,
    }
end

--------------------------------------------------------------------------------
-- Quantize numbers to reduce precision (saves bandwidth)
--------------------------------------------------------------------------------
function NetworkOptimizer.quantize(value: number, precision: number): number
    return math.floor(value / precision + 0.5) * precision
end

function NetworkOptimizer.quantizeVector3(v: Vector3, precision: number): Vector3
    return Vector3.new(
        NetworkOptimizer.quantize(v.X, precision),
        NetworkOptimizer.quantize(v.Y, precision),
        NetworkOptimizer.quantize(v.Z, precision)
    )
end

return NetworkOptimizer
```

## Server: Replication Best Practices

```lua
-- ServerScriptService/ReplicationService.server.lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StateStore = require(ReplicatedStorage:WaitForChild("StateStore"))
local ReplicationLib = require(ReplicatedStorage:WaitForChild("ReplicationLib"))
local NetworkOptimizer = require(ReplicatedStorage:WaitForChild("NetworkOptimizer"))

-- Example: Game state via Attributes (auto-replicates)
StateStore.set("Game", "RoundNumber", 1)
StateStore.set("Game", "TimeRemaining", 300)
StateStore.set("Game", "GamePhase", "Lobby")

-- Example: Leaderboard via ValueObjects (auto-replicates)
local topScoreValue = ReplicationLib.createValue("TopScore", 0)

-- Example: Per-player state via Attributes on Player
Players.PlayerAdded:Connect(function(player)
    StateStore.setPlayerState(player, "Coins", 0)
    StateStore.setPlayerState(player, "Level", 1)
    StateStore.setPlayerState(player, "Team", "None")
end)

-- Example: Batched position updates for custom NPCs
local npcUpdateRemote = Instance.new("RemoteEvent")
npcUpdateRemote.Name = "NPCUpdates"
npcUpdateRemote.Parent = ReplicatedStorage

local npcBatcher = NetworkOptimizer.createBatcher(npcUpdateRemote, 0.1, true)

-- In your NPC update loop:
-- npcBatcher.add({ npcId = "Guard1", pos = quantizedPosition, rot = quantizedRotation })
-- The batcher auto-flushes every 0.1 seconds
```

## Client: Reading Replicated State

```lua
-- StarterPlayerScripts/ReplicationClient.lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StateStore = require(ReplicatedStorage:WaitForChild("StateStore"))
local ReplicationLib = require(ReplicatedStorage:WaitForChild("ReplicationLib"))
local NetworkOptimizer = require(ReplicatedStorage:WaitForChild("NetworkOptimizer"))

local player = Players.LocalPlayer

-- Read game state (auto-synced via Attributes)
local phase = StateStore.get("Game", "GamePhase")
print("Current phase:", phase)

-- Listen for game state changes
StateStore.onChange("Game", "GamePhase", function(newPhase)
    print("Game phase changed to:", newPhase)
end)

StateStore.onChange("Game", "TimeRemaining", function(timeLeft)
    -- Update timer UI
end)

-- Read per-player state
local coins = StateStore.getPlayerState(player, "Coins")

StateStore.onPlayerStateChange(player, "Coins", function(newCoins)
    print("Coins updated:", newCoins)
    -- Update coins UI
end)

-- Listen for ValueObject changes
ReplicationLib.onValueChanged("TopScore", function(newScore)
    print("New top score:", newScore)
end)

-- Handle batched NPC updates
local npcUpdateRemote = ReplicatedStorage:WaitForChild("NPCUpdates")
npcUpdateRemote.OnClientEvent:Connect(function(action, batch)
    if action == "Batch" then
        for _, update in batch do
            -- Apply NPC position updates
            local npc = workspace.NPCs:FindFirstChild(update.npcId)
            if npc then
                local rootPart = npc:FindFirstChild("HumanoidRootPart")
                if rootPart then
                    rootPart.CFrame = CFrame.new(update.pos)
                end
            end
        end
    end
end)
```

## Key Best Practices

### 1. Prefer Attributes Over RemoteEvents for State
```lua
-- BAD: Manually syncing with RemoteEvents
remote:FireAllClients("UpdateCoins", player, 100)

-- GOOD: Set attribute, it replicates automatically
player:SetAttribute("Coins", 100)
-- Client reads: player:GetAttribute("Coins")
```

### 2. Minimize RemoteEvent Payload
```lua
-- BAD: Sending full state every time
remote:FireAllClients("PlayerUpdate", {
    name = player.Name,
    health = 100,
    maxHealth = 100,
    position = rootPart.Position,
    rotation = rootPart.CFrame,
    -- ... 20 more fields
})

-- GOOD: Send only what changed, use IDs not strings
remote:FireAllClients(playerId, "H", 100) -- short action codes
```

### 3. Batch Frequent Updates
```lua
-- BAD: Firing remote every frame
RunService.Heartbeat:Connect(function()
    remote:FireAllClients("NPCPos", npc.Position)
end)

-- GOOD: Batch and throttle
local batcher = NetworkOptimizer.createBatcher(remote, 0.1, true)
RunService.Heartbeat:Connect(function()
    batcher.add({ id = npcId, p = quantizedPos })
end)
-- Batcher flushes every 100ms automatically
```

### 4. Use ValueObjects for Typed Auto-Replication
```lua
-- Good for simple values that need .Changed events
local roundValue = ReplicationLib.createValue("Round", 1)
-- Client: ReplicationLib.onValueChanged("Round", function(v) ... end)
```

### 5. Quantize Positions to Reduce Bandwidth
```lua
-- BAD: Full float precision (32 bits per component)
remote:FireAllClients(position)

-- GOOD: Quantize to 0.1 studs (sufficient for most games)
local q = NetworkOptimizer.quantizeVector3(position, 0.1)
remote:FireAllClients(q)
```

### 6. Rate-Limit Client-to-Server Remotes
```lua
-- Prevent clients from spamming the server
local limiter = NetworkOptimizer.createRateLimiter(actionRemote, 10) -- max 10/sec
-- limiter.fire("Attack", targetId) -- returns false if rate-limited
```

## 

---

## Learned Lessons

<!-- skill-evolve 에이전트가 자동으로 교훈 추가 -->

## Self-Evolution Protocol

이 스킬에서 에러가 발생하면:
1. 에러의 근본 원인을 분석한다
2. Learned Lessons 섹션에 교훈을 추가한다
3. 규칙화하여 반복 방지
4. SessionManager에 기록

```lua
local SM = require(game.ServerStorage._RobloxEngine.SessionManager)
SM.logAction("SKILL_ERROR", "[스킬명] | [에러]")
SM.logAction("SKILL_LEARNED", "[스킬명] | [교훈]")
```

**매 작업 시 Learned Lessons를 먼저 읽고 위반하지 않는지 확인.**

$ARGUMENTS

When the user asks about replication, ask:
- What data needs to be synchronized? (game state, player stats, positions)
- How frequently does the data change? (every frame, on events, rarely)
- Is it per-player data or global game state?
- Do you need client prediction for responsive feel?
- How many players will your game support? (affects bandwidth budget)
- Do you need delta compression for large state objects?
