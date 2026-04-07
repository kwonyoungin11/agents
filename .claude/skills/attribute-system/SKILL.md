---
name: attribute-system
description: |
  인스턴스 기반 어트리뷰트 데이터, 자동 복제, UI 어트리뷰트 바인딩, 어트리뷰트 변경 감지, 데이터 저장.
  Attribute-based data on instances, automatic client-server replication, UI binding to attribute changes, attribute change listeners, type-safe attribute helpers, stat systems.
allowed-tools:
  - Bash
  - Edit
  - Write
  - Read
  - Glob
  - Grep
effort: high
---

# Attribute System

This skill covers Instance Attributes for data storage, automatic replication, UI binding to attribute values, change detection, type-safe helpers, and attribute-based stat/config systems in Roblox.

---

## 1. Attribute Utilities

```luau
--!strict
-- ModuleScript: Type-safe attribute helpers

local AttributeUtils = {}

--- Gets an attribute with a default fallback value.
function AttributeUtils.get(instance: Instance, name: string, default: any): any
    local value = instance:GetAttribute(name)
    if value == nil then
        return default
    end
    return value
end

--- Gets a number attribute with default.
function AttributeUtils.getNumber(instance: Instance, name: string, default: number): number
    local value = instance:GetAttribute(name)
    if typeof(value) == "number" then
        return value
    end
    return default
end

--- Gets a string attribute with default.
function AttributeUtils.getString(instance: Instance, name: string, default: string): string
    local value = instance:GetAttribute(name)
    if typeof(value) == "string" then
        return value
    end
    return default
end

--- Gets a boolean attribute with default.
function AttributeUtils.getBool(instance: Instance, name: string, default: boolean): boolean
    local value = instance:GetAttribute(name)
    if typeof(value) == "boolean" then
        return value
    end
    return default
end

--- Gets a Color3 attribute with default.
function AttributeUtils.getColor(instance: Instance, name: string, default: Color3): Color3
    local value = instance:GetAttribute(name)
    if typeof(value) == "Color3" then
        return value
    end
    return default
end

--- Sets an attribute only if the new value differs (avoids unnecessary replication).
function AttributeUtils.setIfChanged(instance: Instance, name: string, value: any): boolean
    local current = instance:GetAttribute(name)
    if current ~= value then
        instance:SetAttribute(name, value)
        return true
    end
    return false
end

--- Increments a numeric attribute by a delta amount.
function AttributeUtils.increment(instance: Instance, name: string, delta: number, min: number?, max: number?): number
    local current = instance:GetAttribute(name) or 0
    if typeof(current) ~= "number" then current = 0 end
    local newValue = current + delta
    if min then newValue = math.max(newValue, min) end
    if max then newValue = math.min(newValue, max) end
    instance:SetAttribute(name, newValue)
    return newValue
end

--- Sets multiple attributes at once from a dictionary.
function AttributeUtils.setMany(instance: Instance, attributes: { [string]: any })
    for name, value in attributes do
        instance:SetAttribute(name, value)
    end
end

--- Gets all attributes as a dictionary.
function AttributeUtils.getAll(instance: Instance): { [string]: any }
    return instance:GetAttributes()
end

--- Clears all attributes from an instance.
function AttributeUtils.clearAll(instance: Instance)
    for name, _ in instance:GetAttributes() do
        instance:SetAttribute(name, nil)
    end
end

return AttributeUtils
```

---

## 2. Attribute Change Observer

```luau
--!strict
-- ModuleScript: Reactive attribute change detection

local AttributeObserver = {}

--- Watches a specific attribute for changes.
--- Calls the callback immediately with the current value, then on each change.
function AttributeObserver.watch(instance: Instance, name: string, callback: (newValue: any, oldValue: any) -> ()): () -> ()
    local lastValue = instance:GetAttribute(name)

    -- Fire immediately with current value
    callback(lastValue, nil)

    local connection = instance:GetAttributeChangedSignal(name):Connect(function()
        local newValue = instance:GetAttribute(name)
        local oldValue = lastValue
        lastValue = newValue
        callback(newValue, oldValue)
    end)

    return function()
        connection:Disconnect()
    end
end

--- Watches multiple attributes on the same instance.
function AttributeObserver.watchMany(instance: Instance, names: { string }, callback: (changed: string, newValue: any) -> ()): () -> ()
    local connections: { () -> () } = {}

    for _, name in names do
        local disconnect = AttributeObserver.watch(instance, name, function(newValue)
            callback(name, newValue)
        end)
        table.insert(connections, disconnect)
    end

    return function()
        for _, disconnect in connections do
            disconnect()
        end
    end
end

--- Watches any attribute change on an instance.
function AttributeObserver.watchAll(instance: Instance, callback: (name: string, newValue: any) -> ()): () -> ()
    local lastValues: { [string]: any } = instance:GetAttributes()

    local connection = instance.AttributeChanged:Connect(function(name: string)
        local newValue = instance:GetAttribute(name)
        lastValues[name] = newValue
        callback(name, newValue)
    end)

    return function()
        connection:Disconnect()
    end
end

return AttributeObserver
```

---

## 3. UI Binding to Attributes

```luau
--!strict
-- LocalScript/ModuleScript: Bind UI elements to attribute values for auto-updating display

local TweenService = game:GetService("TweenService")
local AttributeObserver = require(script.Parent.AttributeObserver)

local AttributeUI = {}

--- Binds a TextLabel to display an attribute value.
function AttributeUI.bindText(label: TextLabel, instance: Instance, attributeName: string, formatFn: ((value: any) -> string)?): () -> ()
    return AttributeObserver.watch(instance, attributeName, function(value)
        if formatFn then
            label.Text = formatFn(value)
        else
            label.Text = tostring(value or "")
        end
    end)
end

--- Binds a health/progress bar (Frame) to a numeric attribute (0-max).
function AttributeUI.bindProgressBar(fillFrame: Frame, instance: Instance, attributeName: string, maxValue: number, animated: boolean?): () -> ()
    return AttributeObserver.watch(instance, attributeName, function(value)
        local fraction = math.clamp((value or 0) / maxValue, 0, 1)
        local targetSize = UDim2.new(fraction, 0, 1, 0)

        if animated then
            TweenService:Create(fillFrame, TweenInfo.new(0.3, Enum.EasingStyle.Quad), {
                Size = targetSize,
            }):Play()
        else
            fillFrame.Size = targetSize
        end
    end)
end

--- Binds a TextLabel color based on attribute value thresholds.
function AttributeUI.bindColorThreshold(label: TextLabel, instance: Instance, attributeName: string, thresholds: {
    { value: number, color: Color3 },
}): () -> ()
    -- Sort thresholds ascending
    table.sort(thresholds, function(a, b) return a.value < b.value end)

    return AttributeObserver.watch(instance, attributeName, function(value)
        if typeof(value) ~= "number" then return end
        local color = thresholds[1].color -- default to lowest
        for _, threshold in thresholds do
            if value >= threshold.value then
                color = threshold.color
            end
        end
        label.TextColor3 = color
    end)
end

--- Binds visibility of a GuiObject to a boolean attribute.
function AttributeUI.bindVisibility(guiObject: GuiObject, instance: Instance, attributeName: string, invert: boolean?): () -> ()
    return AttributeObserver.watch(instance, attributeName, function(value)
        local visible = if typeof(value) == "boolean" then value else (value ~= nil)
        if invert then visible = not visible end
        guiObject.Visible = visible
    end)
end

--- Binds an ImageLabel image to a string attribute (for dynamic icons).
function AttributeUI.bindImage(imageLabel: ImageLabel, instance: Instance, attributeName: string): () -> ()
    return AttributeObserver.watch(instance, attributeName, function(value)
        if typeof(value) == "string" then
            imageLabel.Image = value
        end
    end)
end

return AttributeUI
```

---

## 4. Stat System with Attributes

```luau
--!strict
-- ServerScript/ModuleScript: Player stat system using attributes on Player instance

local Players = game:GetService("Players")
local AttributeUtils = require(path.to.AttributeUtils)

local StatSystem = {}

export type StatDef = {
    name: string,
    default: number,
    min: number?,
    max: number?,
}

local STATS: { StatDef } = {
    { name = "Health", default = 100, min = 0, max = 100 },
    { name = "MaxHealth", default = 100, min = 1, max = 9999 },
    { name = "Mana", default = 50, min = 0, max = 50 },
    { name = "MaxMana", default = 50, min = 1, max = 9999 },
    { name = "Strength", default = 10, min = 0 },
    { name = "Defense", default = 5, min = 0 },
    { name = "Speed", default = 16, min = 0, max = 100 },
    { name = "Level", default = 1, min = 1, max = 999 },
    { name = "Experience", default = 0, min = 0 },
    { name = "Gold", default = 0, min = 0 },
}

--- Initializes all stats on a player (called on join).
function StatSystem.initPlayer(player: Player)
    for _, stat in STATS do
        if player:GetAttribute(stat.name) == nil then
            player:SetAttribute(stat.name, stat.default)
        end
    end
end

--- Gets a stat value from a player.
function StatSystem.getStat(player: Player, statName: string): number
    return AttributeUtils.getNumber(player, statName, 0)
end

--- Sets a stat value on a player (clamped to min/max if defined).
function StatSystem.setStat(player: Player, statName: string, value: number)
    for _, stat in STATS do
        if stat.name == statName then
            local clamped = value
            if stat.min then clamped = math.max(clamped, stat.min) end
            if stat.max then clamped = math.min(clamped, stat.max) end
            player:SetAttribute(statName, clamped)
            return
        end
    end
    -- Unknown stat, set without clamping
    player:SetAttribute(statName, value)
end

--- Modifies a stat by a delta (add/subtract).
function StatSystem.modifyStat(player: Player, statName: string, delta: number): number
    local current = StatSystem.getStat(player, statName)
    StatSystem.setStat(player, statName, current + delta)
    return StatSystem.getStat(player, statName)
end

--- Resets all stats to defaults.
function StatSystem.resetStats(player: Player)
    for _, stat in STATS do
        player:SetAttribute(stat.name, stat.default)
    end
end

-- Auto-initialize on player join
Players.PlayerAdded:Connect(function(player: Player)
    StatSystem.initPlayer(player)
end)

return StatSystem
```

---

## 5. Config System with Attributes

```luau
--!strict
-- ModuleScript: Use attributes on a Configuration instance for game settings

local AttributeUtils = require(path.to.AttributeUtils)

local ConfigSystem = {}

--- Creates a Configuration instance with default values.
function ConfigSystem.createConfig(name: string, defaults: { [string]: any }, parent: Instance): Configuration
    local config = Instance.new("Configuration")
    config.Name = name

    for attrName, value in defaults do
        config:SetAttribute(attrName, value)
    end

    config.Parent = parent
    return config
end

--- Reads a config value with type-safe default.
function ConfigSystem.getValue(config: Configuration, name: string, default: any): any
    return AttributeUtils.get(config, name, default)
end

--- Example: game settings configuration
function ConfigSystem.createGameSettings(parent: Instance): Configuration
    return ConfigSystem.createConfig("GameSettings", {
        RoundDuration = 300,
        MaxPlayers = 20,
        FriendlyFire = false,
        RespawnTime = 5,
        DamageMultiplier = 1.0,
        MapName = "Default",
        GravityMultiplier = 1.0,
        StartingGold = 100,
    }, parent)
end

return ConfigSystem
```

---

## Attribute Replication Behavior

| Set On | Visible To |
|---|---|
| Server sets on workspace child | All clients (automatic) |
| Server sets on Player | That player's client (automatic) |
| Client sets on local instance | Client only (NOT replicated to server) |

### Important Rules

- **Server-authoritative**: Always set gameplay attributes on the server
- **Client can read**: Client reads server-set attributes automatically
- **Client-only**: Client-set attributes are local and not replicated
- **Supported types**: string, number, boolean, Vector3, CFrame, Color3, BrickColor, UDim, UDim2, etc.

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

- `attribute_name` (string) - Name of the attribute to get/set
- `attribute_value` (any) - Value to set for the attribute
- `default_value` (any) - Default fallback value if attribute is nil
- `instance` (Instance) - Target instance for attribute operations
- `format_function` (string) - Format pattern for display (e.g., "$%d" for gold)
- `max_value` (number) - Maximum value for progress bar binding
- `animated` (boolean) - Whether UI binding uses tween animation
- `stat_name` (string) - Stat name from the stat system
- `stat_delta` (number) - Amount to add/subtract from a stat
- `threshold_colors` (table) - Array of {value, color} for color threshold binding
