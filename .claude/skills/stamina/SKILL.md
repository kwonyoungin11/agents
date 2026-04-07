---
name: stamina
description: |
  Stamina system for Roblox. Sprint stamina cost, dodge/roll cost, regen when idle,
  stamina bar UI, exhaustion state with debuffs, and configurable per-action costs.
  스태미나 시스템, 달리기 비용, 회피 비용, 유휴 시 재생, 스태미나 바, 탈진 상태
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
effort: high
---

# Stamina System

Build a stamina system with sprint drain, dodge cost, idle regeneration, exhaustion state, and a responsive stamina bar UI.

## Architecture Overview

```
ServerScriptService/
  StaminaService.server.lua      -- Authoritative stamina state, validation
ReplicatedStorage/
  StaminaConfig.lua              -- Costs, rates, thresholds
  StaminaShared.lua              -- Shared types
StarterPlayerScripts/
  StaminaClient.lua              -- Client prediction, UI, input handling
StarterGui/
  StaminaBarUI/                  -- Stamina bar ScreenGui
```

## Shared Types and Config

```lua
-- ReplicatedStorage/StaminaShared.lua
local StaminaShared = {}

export type StaminaConfig = {
    maxStamina: number,
    regenRate: number,             -- stamina per second when idle
    regenDelay: number,            -- seconds after action before regen starts
    sprintCostPerSecond: number,
    dodgeCost: number,
    jumpCost: number?,
    climbCost: number?,
    exhaustionThreshold: number,   -- below this, enter exhaustion
    exhaustionRecovery: number,    -- must regen to this amount to exit exhaustion
    exhaustionSpeedMultiplier: number,
}

export type StaminaState = {
    current: number,
    max: number,
    isExhausted: boolean,
    isSprinting: boolean,
    lastActionTime: number,
    isRegenerating: boolean,
    modifiers: { [string]: number },
}

export type StaminaAction = "Sprint" | "Dodge" | "Jump" | "Climb" | "Custom"

return StaminaShared
```

```lua
-- ReplicatedStorage/StaminaConfig.lua
local StaminaShared = require(script.Parent:WaitForChild("StaminaShared"))

local StaminaConfig = {}

StaminaConfig.Defaults: StaminaShared.StaminaConfig = {
    maxStamina = 100,
    regenRate = 15,                -- 15 stamina/second idle regen
    regenDelay = 1.5,              -- 1.5s after last action
    sprintCostPerSecond = 12,
    dodgeCost = 25,
    jumpCost = 5,
    climbCost = 8,                 -- per second of climbing
    exhaustionThreshold = 0,       -- enter exhaustion at 0
    exhaustionRecovery = 30,       -- must reach 30 to exit exhaustion
    exhaustionSpeedMultiplier = 0.6,
}

-- Speed settings
StaminaConfig.SprintSpeed = 24      -- WalkSpeed while sprinting
StaminaConfig.NormalSpeed = 16      -- WalkSpeed normally
StaminaConfig.ExhaustedSpeed = 10   -- WalkSpeed when exhausted

-- Dodge settings
StaminaConfig.DodgeForce = 60
StaminaConfig.DodgeDuration = 0.3
StaminaConfig.DodgeCooldown = 0.8
StaminaConfig.DodgeIFrames = true   -- invincibility during dodge

return StaminaConfig
```

## Server: StaminaService

```lua
-- ServerScriptService/StaminaService.server.lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local StaminaConfig = require(ReplicatedStorage:WaitForChild("StaminaConfig"))
local StaminaShared = require(ReplicatedStorage:WaitForChild("StaminaShared"))

local StaminaRemote = Instance.new("RemoteEvent")
StaminaRemote.Name = "StaminaRemote"
StaminaRemote.Parent = ReplicatedStorage

local StaminaRequestRemote = Instance.new("RemoteEvent")
StaminaRequestRemote.Name = "StaminaRequestRemote"
StaminaRequestRemote.Parent = ReplicatedStorage

local playerStates: { [Player]: StaminaShared.StaminaState } = {}
local playerConfigs: { [Player]: StaminaShared.StaminaConfig } = {}

--------------------------------------------------------------------------------
-- Initialize player
--------------------------------------------------------------------------------
local function initPlayer(player: Player)
    local config = table.clone(StaminaConfig.Defaults)
    playerConfigs[player] = config

    playerStates[player] = {
        current = config.maxStamina,
        max = config.maxStamina,
        isExhausted = false,
        isSprinting = false,
        lastActionTime = 0,
        isRegenerating = true,
        modifiers = {},
    }
end

--------------------------------------------------------------------------------
-- Get effective regen rate
--------------------------------------------------------------------------------
local function getEffectiveRegenRate(player: Player): number
    local state = playerStates[player]
    local config = playerConfigs[player]
    if not state or not config then return 0 end

    local rate = config.regenRate
    for _, mod in state.modifiers do
        rate *= mod
    end
    return rate
end

--------------------------------------------------------------------------------
-- Consume stamina for an action
--------------------------------------------------------------------------------
local function consumeStamina(player: Player, amount: number, actionName: string): boolean
    local state = playerStates[player]
    if not state then return false end

    if state.isExhausted then
        StaminaRemote:FireClient(player, "Exhausted", actionName)
        return false
    end

    if state.current < amount then
        StaminaRemote:FireClient(player, "NotEnough", actionName, amount)
        return false
    end

    state.current = math.max(state.current - amount, 0)
    state.lastActionTime = tick()
    state.isRegenerating = false

    -- Check exhaustion
    local config = playerConfigs[player]
    if config and state.current <= config.exhaustionThreshold then
        state.isExhausted = true
        -- Apply speed debuff
        local character = player.Character
        local humanoid = character and character:FindFirstChildWhichIsA("Humanoid")
        if humanoid then
            humanoid.WalkSpeed = StaminaConfig.ExhaustedSpeed
        end
        StaminaRemote:FireClient(player, "ExhaustionStart")
    end

    StaminaRemote:FireClient(player, "StaminaUpdate", state.current, state.max, state.isExhausted)
    return true
end

--------------------------------------------------------------------------------
-- Sprint handling
--------------------------------------------------------------------------------
local function startSprint(player: Player)
    local state = playerStates[player]
    if not state then return end
    if state.isExhausted then return end
    if state.current <= 0 then return end

    state.isSprinting = true

    local character = player.Character
    local humanoid = character and character:FindFirstChildWhichIsA("Humanoid")
    if humanoid then
        humanoid.WalkSpeed = StaminaConfig.SprintSpeed
    end

    StaminaRemote:FireClient(player, "SprintStart")
end

local function stopSprint(player: Player)
    local state = playerStates[player]
    if not state then return end

    state.isSprinting = false

    local character = player.Character
    local humanoid = character and character:FindFirstChildWhichIsA("Humanoid")
    if humanoid and not state.isExhausted then
        humanoid.WalkSpeed = StaminaConfig.NormalSpeed
    end

    StaminaRemote:FireClient(player, "SprintStop")
end

--------------------------------------------------------------------------------
-- Dodge
--------------------------------------------------------------------------------
local lastDodgeTime: { [Player]: number } = {}

local function performDodge(player: Player, direction: Vector3)
    local state = playerStates[player]
    local config = playerConfigs[player]
    if not state or not config then return end

    -- Cooldown check
    local now = tick()
    if lastDodgeTime[player] and now - lastDodgeTime[player] < StaminaConfig.DodgeCooldown then
        return
    end

    if not consumeStamina(player, config.dodgeCost, "Dodge") then
        return
    end

    lastDodgeTime[player] = now

    local character = player.Character
    local rootPart = character and character:FindFirstChild("HumanoidRootPart")
    if not rootPart then return end

    -- Apply dodge force
    local dodgeDir = direction.Unit
    local bodyVelocity = Instance.new("BodyVelocity")
    bodyVelocity.MaxForce = Vector3.new(math.huge, 0, math.huge)
    bodyVelocity.Velocity = dodgeDir * StaminaConfig.DodgeForce
    bodyVelocity.Parent = rootPart

    -- I-frames
    local humanoid = character:FindFirstChildWhichIsA("Humanoid")
    if StaminaConfig.DodgeIFrames and humanoid then
        local ff = Instance.new("ForceField")
        ff.Visible = false
        ff.Parent = character
        task.delay(StaminaConfig.DodgeDuration, function()
            ff:Destroy()
        end)
    end

    task.delay(StaminaConfig.DodgeDuration, function()
        bodyVelocity:Destroy()
    end)

    StaminaRemote:FireAllClients("DodgePerformed", player, direction)
end

--------------------------------------------------------------------------------
-- Main tick: sprint drain + regen
--------------------------------------------------------------------------------
RunService.Heartbeat:Connect(function(dt)
    local now = tick()

    for player, state in playerStates do
        local config = playerConfigs[player]
        if not state or not config then continue end

        -- Sprint drain
        if state.isSprinting and not state.isExhausted then
            local cost = config.sprintCostPerSecond * dt
            state.current = math.max(state.current - cost, 0)
            state.lastActionTime = now
            state.isRegenerating = false

            if state.current <= config.exhaustionThreshold then
                state.isExhausted = true
                stopSprint(player)
                StaminaRemote:FireClient(player, "ExhaustionStart")
                local character = player.Character
                local humanoid = character and character:FindFirstChildWhichIsA("Humanoid")
                if humanoid then
                    humanoid.WalkSpeed = StaminaConfig.ExhaustedSpeed
                end
            end
        end

        -- Regen
        if not state.isSprinting and now - state.lastActionTime >= config.regenDelay then
            if state.current < state.max then
                state.isRegenerating = true
                local rate = getEffectiveRegenRate(player)
                state.current = math.min(state.current + rate * dt, state.max)

                -- Check exhaustion recovery
                if state.isExhausted and state.current >= config.exhaustionRecovery then
                    state.isExhausted = false
                    local character = player.Character
                    local humanoid = character and character:FindFirstChildWhichIsA("Humanoid")
                    if humanoid then
                        humanoid.WalkSpeed = StaminaConfig.NormalSpeed
                    end
                    StaminaRemote:FireClient(player, "ExhaustionEnd")
                end
            else
                state.isRegenerating = false
            end
        end

        -- Periodic sync to client
        StaminaRemote:FireClient(player, "StaminaUpdate", state.current, state.max, state.isExhausted)
    end
end)

--------------------------------------------------------------------------------
-- Handle requests
--------------------------------------------------------------------------------
StaminaRequestRemote.OnServerEvent:Connect(function(player: Player, action: string, ...)
    if action == "StartSprint" then
        startSprint(player)
    elseif action == "StopSprint" then
        stopSprint(player)
    elseif action == "Dodge" then
        local direction: Vector3 = ...
        if direction then
            performDodge(player, direction)
        end
    elseif action == "Jump" then
        local config = playerConfigs[player]
        if config and config.jumpCost then
            consumeStamina(player, config.jumpCost, "Jump")
        end
    end
end)

Players.PlayerAdded:Connect(function(player)
    initPlayer(player)
    player.CharacterAdded:Connect(function(character)
        local humanoid = character:WaitForChild("Humanoid")
        humanoid.WalkSpeed = StaminaConfig.NormalSpeed
    end)
end)

Players.PlayerRemoving:Connect(function(player)
    playerStates[player] = nil
    playerConfigs[player] = nil
    lastDodgeTime[player] = nil
end)

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------
local StaminaService = {}

function StaminaService.consumeStamina(player: Player, amount: number, action: string): boolean
    return consumeStamina(player, amount, action)
end

function StaminaService.addModifier(player: Player, name: string, multiplier: number)
    local state = playerStates[player]
    if state then state.modifiers[name] = multiplier end
end

function StaminaService.removeModifier(player: Player, name: string)
    local state = playerStates[player]
    if state then state.modifiers[name] = nil end
end

function StaminaService.setMaxStamina(player: Player, maxStamina: number)
    local state = playerStates[player]
    local config = playerConfigs[player]
    if state then state.max = maxStamina end
    if config then config.maxStamina = maxStamina end
end

function StaminaService.getStamina(player: Player): number
    local state = playerStates[player]
    return state and state.current or 0
end

function StaminaService.isExhausted(player: Player): boolean
    local state = playerStates[player]
    return state and state.isExhausted or false
end

return StaminaService
```

## Client: Input and UI

```lua
-- StarterPlayerScripts/StaminaClient.lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local StaminaConfig = require(ReplicatedStorage:WaitForChild("StaminaConfig"))
local StaminaRemote = ReplicatedStorage:WaitForChild("StaminaRemote")
local StaminaRequestRemote = ReplicatedStorage:WaitForChild("StaminaRequestRemote")

local player = Players.LocalPlayer

local currentStamina = StaminaConfig.Defaults.maxStamina
local maxStamina = StaminaConfig.Defaults.maxStamina
local isExhausted = false
local isSprinting = false

--------------------------------------------------------------------------------
-- Create stamina bar UI
--------------------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "StaminaBarUI"
gui.Parent = player:WaitForChild("PlayerGui")

local container = Instance.new("Frame")
container.Name = "StaminaBar"
container.Size = UDim2.new(0.25, 0, 0, 10)
container.Position = UDim2.new(0.375, 0, 0.975, 0)
container.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
container.BackgroundTransparency = 0.3
container.Parent = gui

local containerCorner = Instance.new("UICorner")
containerCorner.CornerRadius = UDim.new(0, 5)
containerCorner.Parent = container

local staminaFill = Instance.new("Frame")
staminaFill.Name = "Fill"
staminaFill.Size = UDim2.fromScale(1, 1)
staminaFill.BackgroundColor3 = Color3.fromRGB(220, 200, 50)
staminaFill.Parent = container

local fillCorner = Instance.new("UICorner")
fillCorner.CornerRadius = UDim.new(0, 5)
fillCorner.Parent = staminaFill

-- Exhaustion overlay (red tint)
local exhaustionOverlay = Instance.new("Frame")
exhaustionOverlay.Name = "ExhaustionOverlay"
exhaustionOverlay.Size = UDim2.fromScale(1, 1)
exhaustionOverlay.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
exhaustionOverlay.BackgroundTransparency = 1
exhaustionOverlay.ZIndex = 0
exhaustionOverlay.Parent = gui

--------------------------------------------------------------------------------
-- Update UI
--------------------------------------------------------------------------------
local function updateStaminaBar()
    local ratio = maxStamina > 0 and (currentStamina / maxStamina) or 0
    ratio = math.clamp(ratio, 0, 1)

    TweenService:Create(staminaFill, TweenInfo.new(0.15), {
        Size = UDim2.fromScale(ratio, 1),
    }):Play()

    -- Color based on state
    if isExhausted then
        staminaFill.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
    elseif isSprinting then
        staminaFill.BackgroundColor3 = Color3.fromRGB(255, 180, 30)
    elseif ratio < 0.25 then
        staminaFill.BackgroundColor3 = Color3.fromRGB(200, 120, 30)
    else
        staminaFill.BackgroundColor3 = Color3.fromRGB(220, 200, 50)
    end

    -- Show/hide bar based on fullness (hide when full after delay)
    if ratio >= 1 and not isSprinting then
        task.delay(2, function()
            if currentStamina >= maxStamina and not isSprinting then
                TweenService:Create(container, TweenInfo.new(0.3), {
                    BackgroundTransparency = 1,
                }):Play()
                TweenService:Create(staminaFill, TweenInfo.new(0.3), {
                    BackgroundTransparency = 1,
                }):Play()
            end
        end)
    else
        container.BackgroundTransparency = 0.3
        staminaFill.BackgroundTransparency = 0
    end
end

--------------------------------------------------------------------------------
-- Sprint input (hold Shift)
--------------------------------------------------------------------------------
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end

    if input.KeyCode == Enum.KeyCode.LeftShift then
        if not isExhausted then
            isSprinting = true
            StaminaRequestRemote:FireServer("StartSprint")
        end
    end

    -- Dodge (double-tap direction or Q key)
    if input.KeyCode == Enum.KeyCode.Q then
        local character = player.Character
        local rootPart = character and character:FindFirstChild("HumanoidRootPart")
        if rootPart then
            local moveDir = rootPart.CFrame.LookVector
            local humanoid = character:FindFirstChildWhichIsA("Humanoid")
            if humanoid and humanoid.MoveDirection.Magnitude > 0 then
                moveDir = humanoid.MoveDirection
            end
            StaminaRequestRemote:FireServer("Dodge", moveDir)
        end
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.KeyCode == Enum.KeyCode.LeftShift then
        if isSprinting then
            isSprinting = false
            StaminaRequestRemote:FireServer("StopSprint")
        end
    end
end)

-- Jump stamina cost
local function onCharacterAdded(character: Model)
    local humanoid = character:WaitForChild("Humanoid")
    humanoid.Jumping:Connect(function(active)
        if active then
            StaminaRequestRemote:FireServer("Jump")
        end
    end)
end

if player.Character then onCharacterAdded(player.Character) end
player.CharacterAdded:Connect(onCharacterAdded)

--------------------------------------------------------------------------------
-- Handle server events
--------------------------------------------------------------------------------
StaminaRemote.OnClientEvent:Connect(function(action: string, ...)
    if action == "StaminaUpdate" then
        local stamina, max, exhausted = ...
        currentStamina = stamina
        maxStamina = max
        isExhausted = exhausted
        updateStaminaBar()

    elseif action == "ExhaustionStart" then
        isExhausted = true
        isSprinting = false
        -- Red screen tint
        TweenService:Create(exhaustionOverlay, TweenInfo.new(0.3), {
            BackgroundTransparency = 0.85,
        }):Play()
        updateStaminaBar()

    elseif action == "ExhaustionEnd" then
        isExhausted = false
        TweenService:Create(exhaustionOverlay, TweenInfo.new(0.5), {
            BackgroundTransparency = 1,
        }):Play()
        updateStaminaBar()

    elseif action == "SprintStart" then
        isSprinting = true
        updateStaminaBar()

    elseif action == "SprintStop" then
        isSprinting = false
        updateStaminaBar()

    elseif action == "DodgePerformed" then
        local dodgePlayer, direction = ...
        -- Play dodge animation/trail on the character
        local character = dodgePlayer and dodgePlayer.Character
        if not character then return end
        local rootPart = character:FindFirstChild("HumanoidRootPart")
        if not rootPart then return end

        -- Afterimage trail effect
        local trail = Instance.new("Trail")
        trail.Lifetime = 0.3
        trail.FaceCamera = true
        trail.Color = ColorSequence.new(Color3.fromRGB(200, 200, 255))
        trail.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.3),
            NumberSequenceKeypoint.new(1, 1),
        })
        local a0 = Instance.new("Attachment")
        a0.Position = Vector3.new(0, 2, 0)
        a0.Parent = rootPart
        local a1 = Instance.new("Attachment")
        a1.Position = Vector3.new(0, -2, 0)
        a1.Parent = rootPart
        trail.Attachment0 = a0
        trail.Attachment1 = a1
        trail.Parent = rootPart

        task.delay(0.5, function()
            trail:Destroy()
            a0:Destroy()
            a1:Destroy()
        end)

    elseif action == "Exhausted" then
        -- Tried to act while exhausted
        flashExhaustedWarning()

    elseif action == "NotEnough" then
        flashExhaustedWarning()
    end
end)

function flashExhaustedWarning()
    local flash = TweenService:Create(staminaFill, TweenInfo.new(0.1, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, 2, true), {
        BackgroundColor3 = Color3.fromRGB(255, 50, 50),
    })
    flash:Play()
end
```

## Key Implementation Notes

1. **Sprint**: Hold Left Shift to sprint. Drains `sprintCostPerSecond` stamina. Server adjusts WalkSpeed.

2. **Dodge**: Press Q to dodge in movement direction. Applies BodyVelocity for a quick dash. Optional i-frames via invisible ForceField.

3. **Exhaustion**: When stamina hits 0, the player enters exhaustion. Speed is reduced, sprinting is disabled, and a red screen tint appears. Must regen to `exhaustionRecovery` (default 30) to exit.

4. **Regen delay**: After any stamina-consuming action, regen pauses for `regenDelay` seconds.

5. **UI auto-hide**: The stamina bar fades out when full and not sprinting, and reappears when stamina changes.

6. **Dodge trail**: Afterimage trail effect on dodge using Trail instance with two Attachments.

7. **Server authoritative**: All stamina state is on the server. Client sends input, server validates and applies.

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

When the user asks for a stamina system, ask:
- What actions consume stamina? (sprint, dodge, jump, climb, attack)
- What are the costs for each action?
- Should there be an exhaustion state? What debuffs?
- How fast should stamina regenerate? With what delay?
- Do you need a dodge/roll mechanic with i-frames?
- Should the stamina bar auto-hide when full?
