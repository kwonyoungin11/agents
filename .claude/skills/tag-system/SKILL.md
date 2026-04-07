---
name: tag-system
description: |
  CollectionService 태그 시스템, 태그 기반 컴포넌트 시스템, 태그된 인스턴스 자동 설정, 태그 이벤트 리스너.
  CollectionService tags, tag-based component architecture, auto-setup on tagged instances, tag event listeners, dynamic tagging, tag queries, ECS-lite patterns.
allowed-tools:
  - Bash
  - Edit
  - Write
  - Read
  - Glob
  - Grep
effort: high
---

# Tag System (CollectionService)

This skill covers CollectionService tag-based patterns, component-like architecture using tags, auto-setup systems for tagged instances, and efficient tag-based queries in Roblox.

---

## 1. Tag Manager

```luau
--!strict
-- ModuleScript: Centralized tag management utilities

local CollectionService = game:GetService("CollectionService")

local TagManager = {}

--- Adds a tag to an instance.
function TagManager.addTag(instance: Instance, tag: string)
    CollectionService:AddTag(instance, tag)
end

--- Removes a tag from an instance.
function TagManager.removeTag(instance: Instance, tag: string)
    CollectionService:RemoveTag(instance, tag)
end

--- Returns true if the instance has the specified tag.
function TagManager.hasTag(instance: Instance, tag: string): boolean
    return CollectionService:HasTag(instance, tag)
end

--- Returns all instances with the given tag.
function TagManager.getTagged(tag: string): { Instance }
    return CollectionService:GetTagged(tag)
end

--- Returns all tags on an instance.
function TagManager.getTags(instance: Instance): { string }
    return CollectionService:GetTags(instance)
end

--- Toggles a tag on an instance.
function TagManager.toggleTag(instance: Instance, tag: string): boolean
    if CollectionService:HasTag(instance, tag) then
        CollectionService:RemoveTag(instance, tag)
        return false
    else
        CollectionService:AddTag(instance, tag)
        return true
    end
end

--- Adds multiple tags to an instance.
function TagManager.addTags(instance: Instance, tags: { string })
    for _, tag in tags do
        CollectionService:AddTag(instance, tag)
    end
end

--- Finds instances that have ALL specified tags.
function TagManager.getWithAllTags(tags: { string }): { Instance }
    if #tags == 0 then return {} end

    local candidates = CollectionService:GetTagged(tags[1])
    local results: { Instance } = {}

    for _, instance in candidates do
        local hasAll = true
        for i = 2, #tags do
            if not CollectionService:HasTag(instance, tags[i]) then
                hasAll = false
                break
            end
        end
        if hasAll then
            table.insert(results, instance)
        end
    end

    return results
end

--- Finds instances that have ANY of the specified tags.
function TagManager.getWithAnyTag(tags: { string }): { Instance }
    local seen: { [Instance]: boolean } = {}
    local results: { Instance } = {}

    for _, tag in tags do
        for _, instance in CollectionService:GetTagged(tag) do
            if not seen[instance] then
                seen[instance] = true
                table.insert(results, instance)
            end
        end
    end

    return results
end

return TagManager
```

---

## 2. Component System (Tag-Based)

```luau
--!strict
-- ModuleScript: ECS-lite component system using CollectionService tags

local CollectionService = game:GetService("CollectionService")

export type ComponentDef = {
    tag: string,
    onAdded: (instance: Instance) -> (() -> ())?, -- returns optional cleanup function
}

local ComponentSystem = {}
ComponentSystem._registered = {} :: { [string]: ComponentDef }
ComponentSystem._cleanups = {} :: { [Instance]: { [string]: () -> () } }

--- Registers a component definition.
--- The onAdded callback is called for every instance with this tag.
--- It can return a cleanup function that runs when the tag is removed.
function ComponentSystem.register(def: ComponentDef)
    ComponentSystem._registered[def.tag] = def

    -- Handle existing instances
    for _, instance in CollectionService:GetTagged(def.tag) do
        ComponentSystem._initComponent(instance, def)
    end

    -- Handle future instances
    CollectionService:GetInstanceAddedSignal(def.tag):Connect(function(instance: Instance)
        ComponentSystem._initComponent(instance, def)
    end)

    CollectionService:GetInstanceRemovedSignal(def.tag):Connect(function(instance: Instance)
        ComponentSystem._cleanupComponent(instance, def.tag)
    end)
end

function ComponentSystem._initComponent(instance: Instance, def: ComponentDef)
    local cleanup = def.onAdded(instance)
    if cleanup then
        if not ComponentSystem._cleanups[instance] then
            ComponentSystem._cleanups[instance] = {}
        end
        ComponentSystem._cleanups[instance][def.tag] = cleanup
    end

    -- Auto-cleanup when instance is destroyed
    instance.Destroying:Connect(function()
        ComponentSystem._cleanupComponent(instance, def.tag)
    end)
end

function ComponentSystem._cleanupComponent(instance: Instance, tag: string)
    local instanceCleanups = ComponentSystem._cleanups[instance]
    if instanceCleanups and instanceCleanups[tag] then
        instanceCleanups[tag]()
        instanceCleanups[tag] = nil
        if next(instanceCleanups) == nil then
            ComponentSystem._cleanups[instance] = nil
        end
    end
end

return ComponentSystem
```

---

## 3. Practical Component Examples

```luau
--!strict
-- ServerScript: Example component registrations

local ComponentSystem = require(path.to.ComponentSystem)
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

-- ============================================
-- Spinning Component: Tag = "Spin"
-- Any part tagged "Spin" will rotate continuously
-- ============================================
ComponentSystem.register({
    tag = "Spin",
    onAdded = function(instance: Instance): (() -> ())?
        if not instance:IsA("BasePart") then return nil end
        local part = instance :: BasePart
        local speed = part:GetAttribute("SpinSpeed") or 90 -- degrees/sec

        local connection = RunService.Heartbeat:Connect(function(dt: number)
            part.CFrame = part.CFrame * CFrame.Angles(0, math.rad(speed * dt), 0)
        end)

        return function()
            connection:Disconnect()
        end
    end,
})

-- ============================================
-- KillBrick Component: Tag = "KillBrick"
-- Any part tagged "KillBrick" kills players on touch
-- ============================================
ComponentSystem.register({
    tag = "KillBrick",
    onAdded = function(instance: Instance): (() -> ())?
        if not instance:IsA("BasePart") then return nil end
        local part = instance :: BasePart

        local connection = part.Touched:Connect(function(hit: BasePart)
            local character = hit:FindFirstAncestorOfClass("Model")
            if not character then return end
            local humanoid = character:FindFirstChildOfClass("Humanoid")
            if humanoid and humanoid.Health > 0 then
                humanoid.Health = 0
            end
        end)

        return function()
            connection:Disconnect()
        end
    end,
})

-- ============================================
-- Bobbing Component: Tag = "Bob"
-- Parts float up and down
-- ============================================
ComponentSystem.register({
    tag = "Bob",
    onAdded = function(instance: Instance): (() -> ())?
        if not instance:IsA("BasePart") then return nil end
        local part = instance :: BasePart
        local origin = part.Position
        local amplitude = part:GetAttribute("BobAmplitude") or 1
        local frequency = part:GetAttribute("BobFrequency") or 1
        local elapsed = 0

        local connection = RunService.Heartbeat:Connect(function(dt: number)
            elapsed += dt
            part.Position = origin + Vector3.new(0, math.sin(elapsed * frequency * math.pi * 2) * amplitude, 0)
        end)

        return function()
            connection:Disconnect()
        end
    end,
})

-- ============================================
-- Glow Component: Tag = "Glow"
-- Adds a highlight glow effect
-- ============================================
ComponentSystem.register({
    tag = "Glow",
    onAdded = function(instance: Instance): (() -> ())?
        local color = instance:GetAttribute("GlowColor")
        if not color then
            color = Color3.fromRGB(255, 200, 50)
        end

        local highlight = Instance.new("Highlight")
        highlight.FillColor = color :: Color3
        highlight.FillTransparency = 0.6
        highlight.OutlineColor = color :: Color3
        highlight.OutlineTransparency = 0
        highlight.Parent = instance

        return function()
            highlight:Destroy()
        end
    end,
})

-- ============================================
-- Collectible Component: Tag = "Collectible"
-- Item that can be picked up by touching
-- ============================================
ComponentSystem.register({
    tag = "Collectible",
    onAdded = function(instance: Instance): (() -> ())?
        if not instance:IsA("BasePart") then return nil end
        local part = instance :: BasePart
        local collected = false

        local connection = part.Touched:Connect(function(hit: BasePart)
            if collected then return end
            local character = hit:FindFirstAncestorOfClass("Model")
            if not character then return end
            local humanoid = character:FindFirstChildOfClass("Humanoid")
            if humanoid then
                collected = true
                -- Award item, coins, etc. via attributes
                local value = instance:GetAttribute("Value") or 1
                -- Fire collection event here
                instance:Destroy()
            end
        end)

        return function()
            connection:Disconnect()
        end
    end,
})
```

---

## 4. Tag Event Listener

```luau
--!strict
-- ModuleScript: Listen for tag add/remove events

local CollectionService = game:GetService("CollectionService")

local TagListener = {}

export type ListenerCallbacks = {
    onAdded: ((instance: Instance) -> ())?,
    onRemoved: ((instance: Instance) -> ())?,
}

--- Creates a listener that fires callbacks when instances gain or lose a tag.
--- Returns a cleanup function.
function TagListener.listen(tag: string, callbacks: ListenerCallbacks): () -> ()
    local connections: { RBXScriptConnection } = {}

    if callbacks.onAdded then
        -- Fire for existing instances
        for _, instance in CollectionService:GetTagged(tag) do
            callbacks.onAdded(instance)
        end

        table.insert(connections, CollectionService:GetInstanceAddedSignal(tag):Connect(callbacks.onAdded))
    end

    if callbacks.onRemoved then
        table.insert(connections, CollectionService:GetInstanceRemovedSignal(tag):Connect(callbacks.onRemoved))
    end

    return function()
        for _, conn in connections do
            conn:Disconnect()
        end
    end
end

return TagListener
```

---

## 5. Tag-Based Zone System

```luau
--!strict
-- ServerScript: Zone detection using tagged trigger parts

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local TagZone = {}

--- Sets up zone detection for parts tagged with a specific tag.
--- Players entering/exiting the zone trigger callbacks.
function TagZone.setup(zoneTag: string, callbacks: {
    onEnter: ((player: Player, zonePart: BasePart) -> ())?,
    onExit: ((player: Player, zonePart: BasePart) -> ())?,
})
    local playersInZone: { [Player]: { [BasePart]: boolean } } = {}

    local function setupZonePart(zonePart: Instance)
        if not zonePart:IsA("BasePart") then return end
        local part = zonePart :: BasePart
        part.Transparency = 1
        part.CanCollide = false

        part.Touched:Connect(function(hit: BasePart)
            local character = hit:FindFirstAncestorOfClass("Model")
            if not character then return end
            local player = Players:GetPlayerFromCharacter(character)
            if not player then return end

            if not playersInZone[player] then
                playersInZone[player] = {}
            end

            if not playersInZone[player][part] then
                playersInZone[player][part] = true
                if callbacks.onEnter then
                    callbacks.onEnter(player, part)
                end
            end
        end)

        part.TouchEnded:Connect(function(hit: BasePart)
            local character = hit:FindFirstAncestorOfClass("Model")
            if not character then return end
            local player = Players:GetPlayerFromCharacter(character)
            if not player then return end

            if playersInZone[player] and playersInZone[player][part] then
                playersInZone[player][part] = nil
                if callbacks.onExit then
                    callbacks.onExit(player, part)
                end
            end
        end)
    end

    for _, instance in CollectionService:GetTagged(zoneTag) do
        setupZonePart(instance)
    end

    CollectionService:GetInstanceAddedSignal(zoneTag):Connect(setupZonePart)
end

return TagZone
```

---

## Best Practices

- **Tag naming**: Use PascalCase for tags (e.g., "KillBrick", "SpinPart", "Collectible")
- **Attribute integration**: Pair tags with Attributes for per-instance config (e.g., tag "Spin" + Attribute "SpinSpeed")
- **Cleanup**: Always return cleanup functions from component onAdded callbacks
- **Idempotency**: Check for existing children before creating new ones in onAdded
- **Server vs Client**: Register server-side components in ServerScriptService; client-side in StarterPlayerScripts

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

- `tag` (string) - CollectionService tag name
- `tags` (table) - Array of tag names for multi-tag queries
- `component_name` (string) - Name of the component to register
- `attribute_name` (string) - Attribute to read from tagged instances for configuration
- `zone_tag` (string) - Tag identifying zone trigger parts
- `spin_speed` (number) - Rotation speed in degrees/second for Spin component
- `bob_amplitude` (number) - Vertical bobbing distance for Bob component
- `bob_frequency` (number) - Bobbing cycles per second
- `glow_color` (Color3) - Color for the Glow component highlight
