---
name: mana-system
description: |
  Mana/energy resource system for Roblox. Mana cost for abilities, mana regeneration
  over time, mana bar UI with smooth transitions, mana potion items, and mana modifier
  buffs/debuffs.
  마나 시스템, 에너지 자원, 마나 비용, 마나 재생, 마나 바 UI, 마나 포션
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
effort: high
---

# Mana / Energy Resource System

Build a mana/energy system with ability cost management, regeneration, UI display, potions, and buff integration.

## Architecture Overview

```
ServerScriptService/
  ManaService.server.lua         -- Core mana logic, cost deduction, regen
ReplicatedStorage/
  ManaConfig.lua                 -- Default settings, ability costs
  ManaShared.lua                 -- Shared types
StarterPlayerScripts/
  ManaClient.lua                 -- Mana bar UI, VFX, low-mana warnings
StarterGui/
  ManaBarUI/                     -- ScreenGui with mana bar
```

## Shared Types and Config

```lua
-- ReplicatedStorage/ManaShared.lua
local ManaShared = {}

export type ManaConfig = {
    maxMana: number,
    startingMana: number,
    baseRegenRate: number,         -- mana per second
    regenTickInterval: number,
    regenDelay: number,            -- seconds after mana spend before regen resumes
    allowOvercharge: boolean,      -- can mana exceed max?
    overchargeMax: number?,        -- if allowOvercharge, the cap
}

export type ManaState = {
    currentMana: number,
    maxMana: number,
    regenRate: number,
    isRegenerating: boolean,
    lastSpendTime: number,
    modifiers: { [string]: number },
}

export type AbilityCost = {
    manaCost: number,
    cooldown: number?,
    channelCost: number?,        -- mana per second while channeling
}

return ManaShared
```

```lua
-- ReplicatedStorage/ManaConfig.lua
local ManaShared = require(script.Parent:WaitForChild("ManaShared"))

local ManaConfig = {}

ManaConfig.Defaults: ManaShared.ManaConfig = {
    maxMana = 100,
    startingMana = 100,
    baseRegenRate = 3,           -- 3 mana per second
    regenTickInterval = 0.25,
    regenDelay = 2,              -- 2 seconds after spending mana
    allowOvercharge = false,
    overchargeMax = 150,
}

-- Ability mana costs
ManaConfig.AbilityCosts: { [string]: ManaShared.AbilityCost } = {
    Fireball = { manaCost = 25, cooldown = 3 },
    Heal = { manaCost = 40, cooldown = 8 },
    Shield = { manaCost = 30, cooldown = 10 },
    Lightning = { manaCost = 50, cooldown = 5 },
    Teleport = { manaCost = 35, cooldown = 6 },
    ChannelBeam = { manaCost = 10, channelCost = 15, cooldown = 1 },
}

-- Mana potion definitions
ManaConfig.Potions = {
    SmallManaPotion = { restoreAmount = 25, cooldown = 10 },
    MediumManaPotion = { restoreAmount = 50, cooldown = 15 },
    LargeManaPotion = { restoreAmount = 100, cooldown = 30 },
    ManaElixir = { restorePercent = 1.0, cooldown = 60 }, -- full restore
}

return ManaConfig
```

## Server: ManaService

```lua
-- ServerScriptService/ManaService.server.lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ManaConfig = require(ReplicatedStorage:WaitForChild("ManaConfig"))
local ManaShared = require(ReplicatedStorage:WaitForChild("ManaShared"))

local ManaRemote = Instance.new("RemoteEvent")
ManaRemote.Name = "ManaRemote"
ManaRemote.Parent = ReplicatedStorage

local ManaRequestRemote = Instance.new("RemoteEvent")
ManaRequestRemote.Name = "ManaRequestRemote"
ManaRequestRemote.Parent = ReplicatedStorage

-- Per-player mana state
local playerStates: { [Player]: ManaShared.ManaState } = {}
local playerConfigs: { [Player]: ManaShared.ManaConfig } = {}
local abilityCooldowns: { [Player]: { [string]: number } } = {}

local tickAccumulator = 0

--------------------------------------------------------------------------------
-- Initialize player
--------------------------------------------------------------------------------
local function initPlayer(player: Player)
    local config = table.clone(ManaConfig.Defaults)
    playerConfigs[player] = config

    playerStates[player] = {
        currentMana = config.startingMana,
        maxMana = config.maxMana,
        regenRate = config.baseRegenRate,
        isRegenerating = true,
        lastSpendTime = 0,
        modifiers = {},
    }

    abilityCooldowns[player] = {}

    -- Sync initial state to client
    ManaRemote:FireClient(player, "Init", config.startingMana, config.maxMana)
end

--------------------------------------------------------------------------------
-- Calculate effective regen rate
--------------------------------------------------------------------------------
local function getEffectiveRegenRate(player: Player): number
    local state = playerStates[player]
    local config = playerConfigs[player]
    if not state or not config then return 0 end

    local rate = config.baseRegenRate

    for _, modifier in state.modifiers do
        rate *= modifier
    end

    return rate
end

--------------------------------------------------------------------------------
-- Spend mana for an ability
--------------------------------------------------------------------------------
local function spendMana(player: Player, abilityName: string): boolean
    local state = playerStates[player]
    if not state then return false end

    local abilityCost = ManaConfig.AbilityCosts[abilityName]
    if not abilityCost then
        warn("[ManaService] Unknown ability:", abilityName)
        return false
    end

    -- Check cooldown
    local cooldowns = abilityCooldowns[player]
    if cooldowns and cooldowns[abilityName] then
        if tick() - cooldowns[abilityName] < (abilityCost.cooldown or 0) then
            ManaRemote:FireClient(player, "OnCooldown", abilityName)
            return false
        end
    end

    -- Check mana
    if state.currentMana < abilityCost.manaCost then
        ManaRemote:FireClient(player, "NotEnoughMana", abilityName, abilityCost.manaCost)
        return false
    end

    -- Deduct mana
    state.currentMana -= abilityCost.manaCost
    state.lastSpendTime = tick()
    state.isRegenerating = false

    -- Set cooldown
    if abilityCost.cooldown then
        cooldowns[abilityName] = tick()
    end

    -- Sync to client
    ManaRemote:FireClient(player, "ManaSpent", state.currentMana, abilityCost.manaCost, abilityName)

    return true
end

--------------------------------------------------------------------------------
-- Channel mana (continuous drain)
--------------------------------------------------------------------------------
local function channelMana(player: Player, abilityName: string, dt: number): boolean
    local state = playerStates[player]
    if not state then return false end

    local abilityCost = ManaConfig.AbilityCosts[abilityName]
    if not abilityCost or not abilityCost.channelCost then return false end

    local cost = abilityCost.channelCost * dt
    if state.currentMana < cost then
        ManaRemote:FireClient(player, "ChannelInterrupted", abilityName)
        return false
    end

    state.currentMana -= cost
    state.lastSpendTime = tick()
    state.isRegenerating = false

    return true
end

--------------------------------------------------------------------------------
-- Use mana potion
--------------------------------------------------------------------------------
local function useManaPotion(player: Player, potionName: string): boolean
    local state = playerStates[player]
    local config = playerConfigs[player]
    if not state or not config then return false end

    local potion = ManaConfig.Potions[potionName]
    if not potion then return false end

    -- Check potion cooldown
    local cooldowns = abilityCooldowns[player]
    local potionKey = "Potion_" .. potionName
    if cooldowns[potionKey] and tick() - cooldowns[potionKey] < potion.cooldown then
        ManaRemote:FireClient(player, "PotionCooldown", potionName)
        return false
    end

    local restoreAmount: number
    if potion.restorePercent then
        restoreAmount = state.maxMana * potion.restorePercent
    else
        restoreAmount = potion.restoreAmount
    end

    local cap = config.allowOvercharge and (config.overchargeMax or state.maxMana) or state.maxMana
    state.currentMana = math.min(state.currentMana + restoreAmount, cap)
    cooldowns[potionKey] = tick()

    ManaRemote:FireClient(player, "PotionUsed", potionName, state.currentMana, restoreAmount)
    return true
end

--------------------------------------------------------------------------------
-- Mana regeneration tick
--------------------------------------------------------------------------------
RunService.Heartbeat:Connect(function(dt)
    tickAccumulator += dt
    local tickInterval = ManaConfig.Defaults.regenTickInterval
    if tickAccumulator < tickInterval then return end
    tickAccumulator -= tickInterval

    local now = tick()

    for player, state in playerStates do
        local config = playerConfigs[player]
        if not state or not config then continue end

        -- Check regen delay
        if not state.isRegenerating then
            if now - state.lastSpendTime >= config.regenDelay then
                state.isRegenerating = true
                ManaRemote:FireClient(player, "RegenStarted")
            end
        end

        -- Apply regen
        if state.isRegenerating and state.currentMana < state.maxMana then
            local rate = getEffectiveRegenRate(player)
            local regenAmount = rate * tickInterval
            local cap = config.allowOvercharge and (config.overchargeMax or state.maxMana) or state.maxMana
            state.currentMana = math.min(state.currentMana + regenAmount, cap)

            -- Periodic sync (every few ticks to reduce network traffic)
            ManaRemote:FireClient(player, "ManaSync", state.currentMana)
        end
    end
end)

--------------------------------------------------------------------------------
-- Handle client requests
--------------------------------------------------------------------------------
ManaRequestRemote.OnServerEvent:Connect(function(player: Player, action: string, ...)
    if action == "SpendMana" then
        local abilityName: string = ...
        spendMana(player, abilityName)
    elseif action == "UsePotion" then
        local potionName: string = ...
        useManaPotion(player, potionName)
    end
end)

Players.PlayerAdded:Connect(function(player)
    initPlayer(player)
end)

Players.PlayerRemoving:Connect(function(player)
    playerStates[player] = nil
    playerConfigs[player] = nil
    abilityCooldowns[player] = nil
end)

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------
local ManaService = {}

function ManaService.spendMana(player: Player, abilityName: string): boolean
    return spendMana(player, abilityName)
end

function ManaService.addMana(player: Player, amount: number)
    local state = playerStates[player]
    local config = playerConfigs[player]
    if not state or not config then return end
    local cap = config.allowOvercharge and (config.overchargeMax or state.maxMana) or state.maxMana
    state.currentMana = math.min(state.currentMana + amount, cap)
    ManaRemote:FireClient(player, "ManaSync", state.currentMana)
end

function ManaService.setMaxMana(player: Player, maxMana: number)
    local state = playerStates[player]
    local config = playerConfigs[player]
    if state then state.maxMana = maxMana end
    if config then config.maxMana = maxMana end
    ManaRemote:FireClient(player, "MaxManaChanged", maxMana)
end

function ManaService.addModifier(player: Player, name: string, multiplier: number)
    local state = playerStates[player]
    if state then state.modifiers[name] = multiplier end
end

function ManaService.removeModifier(player: Player, name: string)
    local state = playerStates[player]
    if state then state.modifiers[name] = nil end
end

function ManaService.getMana(player: Player): number
    local state = playerStates[player]
    return state and state.currentMana or 0
end

function ManaService.getMaxMana(player: Player): number
    local state = playerStates[player]
    return state and state.maxMana or 0
end

return ManaService
```

## Client: Mana Bar UI

```lua
-- StarterPlayerScripts/ManaClient.lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local ManaRemote = ReplicatedStorage:WaitForChild("ManaRemote")
local ManaRequestRemote = ReplicatedStorage:WaitForChild("ManaRequestRemote")

local player = Players.LocalPlayer

local currentMana = 100
local maxMana = 100
local isRegenerating = false

--------------------------------------------------------------------------------
-- Create Mana Bar UI
--------------------------------------------------------------------------------
local function createManaBarUI()
    local gui = Instance.new("ScreenGui")
    gui.Name = "ManaBarUI"
    gui.Parent = player:WaitForChild("PlayerGui")

    local container = Instance.new("Frame")
    container.Name = "ManaBarContainer"
    container.Size = UDim2.new(0.3, 0, 0, 22)
    container.Position = UDim2.new(0.35, 0, 0.955, 0)
    container.BackgroundColor3 = Color3.fromRGB(20, 20, 35)
    container.BackgroundTransparency = 0.2
    container.Parent = gui

    local containerCorner = Instance.new("UICorner")
    containerCorner.CornerRadius = UDim.new(0, 6)
    containerCorner.Parent = container

    -- Mana fill bar
    local manaBar = Instance.new("Frame")
    manaBar.Name = "ManaFill"
    manaBar.Size = UDim2.fromScale(1, 1)
    manaBar.BackgroundColor3 = Color3.fromRGB(50, 100, 220)
    manaBar.Parent = container

    local manaCorner = Instance.new("UICorner")
    manaCorner.CornerRadius = UDim.new(0, 6)
    manaCorner.Parent = manaBar

    -- Shimmer effect when regenerating
    local shimmer = Instance.new("Frame")
    shimmer.Name = "Shimmer"
    shimmer.Size = UDim2.fromScale(0, 1)
    shimmer.BackgroundColor3 = Color3.fromRGB(120, 170, 255)
    shimmer.BackgroundTransparency = 0.6
    shimmer.Visible = false
    shimmer.Parent = manaBar

    -- Mana text
    local manaText = Instance.new("TextLabel")
    manaText.Name = "ManaText"
    manaText.Size = UDim2.fromScale(1, 1)
    manaText.BackgroundTransparency = 1
    manaText.Text = "100 / 100"
    manaText.TextColor3 = Color3.fromRGB(200, 220, 255)
    manaText.TextStrokeTransparency = 0.5
    manaText.TextSize = 12
    manaText.Font = Enum.Font.GothamBold
    manaText.ZIndex = 5
    manaText.Parent = container

    -- Mana icon
    local manaIcon = Instance.new("TextLabel")
    manaIcon.Size = UDim2.fromOffset(20, 22)
    manaIcon.Position = UDim2.new(0, -25, 0, 0)
    manaIcon.BackgroundTransparency = 1
    manaIcon.Text = "MP"
    manaIcon.TextColor3 = Color3.fromRGB(100, 150, 255)
    manaIcon.TextSize = 12
    manaIcon.Font = Enum.Font.GothamBold
    manaIcon.Parent = container

    return manaBar, manaText, shimmer
end

local manaBar, manaText, shimmer = createManaBarUI()

--------------------------------------------------------------------------------
-- Update mana bar display
--------------------------------------------------------------------------------
local function updateManaBar()
    local ratio = maxMana > 0 and (currentMana / maxMana) or 0
    ratio = math.clamp(ratio, 0, 1)

    TweenService:Create(manaBar, TweenInfo.new(0.3, Enum.EasingStyle.Quad), {
        Size = UDim2.fromScale(ratio, 1),
    }):Play()

    manaText.Text = string.format("%d / %d", math.ceil(currentMana), maxMana)

    -- Low mana warning color
    if ratio <= 0.2 then
        manaBar.BackgroundColor3 = Color3.fromRGB(150, 50, 50)
    elseif ratio <= 0.4 then
        manaBar.BackgroundColor3 = Color3.fromRGB(100, 80, 180)
    else
        manaBar.BackgroundColor3 = Color3.fromRGB(50, 100, 220)
    end

    shimmer.Visible = isRegenerating
end

--------------------------------------------------------------------------------
-- Low mana flash effect
--------------------------------------------------------------------------------
local function flashLowMana()
    local flash = TweenService:Create(manaBar, TweenInfo.new(0.15, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, 2, true), {
        BackgroundTransparency = 0.5,
    })
    flash:Play()
end

--------------------------------------------------------------------------------
-- Mana spend burst VFX on character
--------------------------------------------------------------------------------
local function playManaSpendVFX(amount: number)
    local character = player.Character
    if not character then return end
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not rootPart then return end

    -- Small blue particle burst
    local attachment = Instance.new("Attachment")
    attachment.Parent = rootPart

    local emitter = Instance.new("ParticleEmitter")
    emitter.Rate = 0
    emitter.Lifetime = NumberRange.new(0.3, 0.6)
    emitter.Speed = NumberRange.new(3, 8)
    emitter.SpreadAngle = Vector2.new(180, 180)
    emitter.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.5),
        NumberSequenceKeypoint.new(1, 0),
    })
    emitter.Color = ColorSequence.new(Color3.fromRGB(80, 140, 255))
    emitter.LightEmission = 0.8
    emitter.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.2),
        NumberSequenceKeypoint.new(1, 1),
    })
    emitter.Parent = attachment

    emitter:Emit(math.clamp(amount / 5, 5, 30))

    task.delay(1, function()
        attachment:Destroy()
    end)
end

--------------------------------------------------------------------------------
-- Handle server events
--------------------------------------------------------------------------------
ManaRemote.OnClientEvent:Connect(function(action: string, ...)
    if action == "Init" then
        local mana, max = ...
        currentMana = mana
        maxMana = max
        updateManaBar()

    elseif action == "ManaSpent" then
        local newMana, costAmount, abilityName = ...
        currentMana = newMana
        updateManaBar()
        playManaSpendVFX(costAmount)

    elseif action == "ManaSync" then
        local newMana = ...
        currentMana = newMana
        updateManaBar()

    elseif action == "MaxManaChanged" then
        local newMax = ...
        maxMana = newMax
        updateManaBar()

    elseif action == "NotEnoughMana" then
        local abilityName, cost = ...
        flashLowMana()
        warn(string.format("[Mana] Not enough mana for %s (need %d, have %d)", abilityName, cost, math.ceil(currentMana)))

    elseif action == "OnCooldown" then
        local abilityName = ...
        warn("[Mana] " .. abilityName .. " is on cooldown")

    elseif action == "RegenStarted" then
        isRegenerating = true
        updateManaBar()

    elseif action == "PotionUsed" then
        local potionName, newMana, amount = ...
        currentMana = newMana
        updateManaBar()
        -- Blue healing flash
        local character = player.Character
        if character then
            local rootPart = character:FindFirstChild("HumanoidRootPart")
            if rootPart then
                local flash = Instance.new("PointLight")
                flash.Color = Color3.fromRGB(80, 140, 255)
                flash.Brightness = 3
                flash.Range = 15
                flash.Parent = rootPart
                TweenService:Create(flash, TweenInfo.new(0.5), { Brightness = 0 }):Play()
                task.delay(0.6, function() flash:Destroy() end)
            end
        end

    elseif action == "PotionCooldown" then
        warn("[Mana] Potion is on cooldown")

    elseif action == "ChannelInterrupted" then
        local abilityName = ...
        warn("[Mana] Channel interrupted: " .. abilityName .. " (out of mana)")
    end
end)

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------
local ManaClient = {}

function ManaClient.requestAbility(abilityName: string)
    ManaRequestRemote:FireServer("SpendMana", abilityName)
end

function ManaClient.usePotion(potionName: string)
    ManaRequestRemote:FireServer("UsePotion", potionName)
end

function ManaClient.getCurrentMana(): number
    return currentMana
end

function ManaClient.getMaxMana(): number
    return maxMana
end

return ManaClient
```

## Key Implementation Notes

1. **Ability costs**: Define mana costs per ability in `ManaConfig.AbilityCosts`. The server validates cost and cooldown before deducting.

2. **Channel abilities**: Use `channelCost` for abilities that drain mana per second while active (beams, shields, etc.).

3. **Mana potions**: Restore flat amounts or percentages. Each potion has its own cooldown.

4. **Regen delay**: After spending mana, regen pauses for `regenDelay` seconds before resuming.

5. **Modifiers**: Named multipliers stack multiplicatively. Use for equipment bonuses, buffs, or debuffs.

6. **UI**: Blue mana bar below the health bar with smooth transitions, low-mana color warning, and shimmer during regen.

7. **VFX**: Blue particle burst on mana spend, flash effect for potions, low-mana bar flash warning.

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

When the user asks for a mana system, ask:
- What is the max mana and regen rate?
- What abilities need mana costs? List them with costs.
- Do you need mana potions? What sizes/amounts?
- Should mana regen pause after spending? For how long?
- Do you need channeling abilities (continuous mana drain)?
- Should the mana bar be part of a combined HUD or standalone?
