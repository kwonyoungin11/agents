---
name: checkpoint-system
description: |
  Checkpoint system for Roblox. Save spawn position per player, visual indicators
  (flag, glow, activation effects), auto-save on touch, per-player tracking with
  DataStore persistence, sequential and non-sequential modes.
  키워드: 체크포인트 시스템, 스폰 저장, 깃발 표시, 자동 저장, 플레이어 추적, 리스폰
allowed-tools:
  - Bash
  - Read
  - Edit
  - Write
  - Glob
  - Grep
effort: high
---

# Checkpoint System

Robust checkpoint system for Roblox: spawn position saving, visual indicators, auto-save on touch, per-player tracking, and DataStore persistence. All code is Luau.

---

## Architecture Overview

```
ReplicatedStorage/
  Shared/
    CheckpointConfig.luau     -- Settings, visual styles
ServerScriptService/
  Services/
    CheckpointService.luau    -- Server: checkpoint logic, persistence
StarterPlayerScripts/
  Controllers/
    CheckpointUI.luau         -- Client: activation effects, minimap markers
workspace/
  Checkpoints/
    Checkpoint_001/           -- Parts tagged "Checkpoint" with StageNumber attribute
    Checkpoint_002/
```

---

## 1. Checkpoint Configuration

```luau
-- ReplicatedStorage/Shared/CheckpointConfig.luau
--!strict

export type CheckpointStyle = "Flag" | "Beacon" | "Platform" | "Ring"

export type CheckpointVisualConfig = {
    style: CheckpointStyle,
    inactiveColor: Color3,
    activeColor: Color3,
    glowEnabled: boolean,
    particlesOnActivation: boolean,
    soundOnActivation: boolean,
    flagRaiseAnimation: boolean,
}

local CheckpointConfig = {}

CheckpointConfig.TAG_NAME = "Checkpoint"
CheckpointConfig.SEQUENTIAL_MODE = true        -- must reach checkpoints in order
CheckpointConfig.RESPAWN_DELAY = 1.0
CheckpointConfig.SAVE_DEBOUNCE = 0.5           -- min seconds between checkpoint saves
CheckpointConfig.AUTO_SAVE_TO_DATASTORE = true
CheckpointConfig.SPAWN_OFFSET = Vector3.new(0, 3, 0) -- offset above checkpoint part

CheckpointConfig.Visual: CheckpointVisualConfig = {
    style = "Flag",
    inactiveColor = Color3.fromRGB(180, 180, 180),
    activeColor = Color3.fromRGB(50, 255, 50),
    glowEnabled = true,
    particlesOnActivation = true,
    soundOnActivation = true,
    flagRaiseAnimation = true,
}

-- Beacon pulse configuration
CheckpointConfig.BEACON_HEIGHT = 50
CheckpointConfig.BEACON_WIDTH = 2
CheckpointConfig.BEACON_PULSE_SPEED = 1.5

return CheckpointConfig
```

---

## 2. Server Checkpoint Service

```luau
-- ServerScriptService/Services/CheckpointService.luau
--!strict

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CheckpointConfig = require(ReplicatedStorage.Shared.CheckpointConfig)

local CheckpointService = {}

local dataStore = DataStoreService:GetDataStore("Checkpoints_v1")

-- Checkpoint registry: stageNumber -> checkpoint data
type CheckpointData = {
    part: BasePart,
    spawnCFrame: CFrame,
    stageNumber: number,
}

local checkpoints: { [number]: CheckpointData } = {}

-- Player state
type PlayerCheckpointState = {
    currentCheckpoint: number,
    highestCheckpoint: number,
    activatedCheckpoints: { [number]: boolean },
    lastSaveTime: number,
}

local playerStates: { [Player]: PlayerCheckpointState } = {}

-------------------------------------------------
-- Persistence
-------------------------------------------------

local function loadPlayerState(player: Player): PlayerCheckpointState
    if not CheckpointConfig.AUTO_SAVE_TO_DATASTORE then
        return {
            currentCheckpoint = 1,
            highestCheckpoint = 1,
            activatedCheckpoints = { [1] = true },
            lastSaveTime = 0,
        }
    end

    local success, data = pcall(function()
        return dataStore:GetAsync("cp_" .. player.UserId)
    end)

    if success and data then
        return {
            currentCheckpoint = data.currentCheckpoint or 1,
            highestCheckpoint = data.highestCheckpoint or 1,
            activatedCheckpoints = data.activatedCheckpoints or { [1] = true },
            lastSaveTime = 0,
        }
    end

    return {
        currentCheckpoint = 1,
        highestCheckpoint = 1,
        activatedCheckpoints = { [1] = true },
        lastSaveTime = 0,
    }
end

local function savePlayerState(player: Player)
    if not CheckpointConfig.AUTO_SAVE_TO_DATASTORE then return end

    local state = playerStates[player]
    if not state then return end

    pcall(function()
        dataStore:SetAsync("cp_" .. player.UserId, {
            currentCheckpoint = state.currentCheckpoint,
            highestCheckpoint = state.highestCheckpoint,
            activatedCheckpoints = state.activatedCheckpoints,
        })
    end)
end

-------------------------------------------------
-- Checkpoint Registration
-------------------------------------------------

local function registerCheckpoint(instance: Instance)
    if not instance:IsA("BasePart") then return end

    local stageNumber = instance:GetAttribute("StageNumber") :: number?
    if not stageNumber then
        warn("[CheckpointService] Checkpoint missing StageNumber attribute:", instance:GetFullName())
        return
    end

    local spawnOffset = instance:GetAttribute("SpawnOffset") :: Vector3? or CheckpointConfig.SPAWN_OFFSET
    local spawnCFrame = instance.CFrame + spawnOffset

    checkpoints[stageNumber] = {
        part = instance,
        spawnCFrame = spawnCFrame,
        stageNumber = stageNumber,
    }

    -- Set initial visual state
    instance.Color = CheckpointConfig.Visual.inactiveColor
    instance:SetAttribute("Activated", false)

    -- Create flag pole if Flag style
    if CheckpointConfig.Visual.style == "Flag" then
        local existingPole = instance:FindFirstChild("FlagPole")
        if not existingPole then
            local pole = Instance.new("Part")
            pole.Name = "FlagPole"
            pole.Size = Vector3.new(0.3, 8, 0.3)
            pole.Color = Color3.fromRGB(100, 100, 100)
            pole.Material = Enum.Material.Metal
            pole.Anchored = true
            pole.CanCollide = false
            pole.CFrame = instance.CFrame * CFrame.new(instance.Size.X / 2 - 0.2, 4, 0)
            pole.Parent = instance

            local flag = Instance.new("Part")
            flag.Name = "Flag"
            flag.Size = Vector3.new(0.1, 2, 3)
            flag.Color = CheckpointConfig.Visual.inactiveColor
            flag.Material = Enum.Material.Fabric
            flag.Anchored = true
            flag.CanCollide = false
            flag.CFrame = pole.CFrame * CFrame.new(0, 3, 1.5)
            flag.Parent = instance
        end
    elseif CheckpointConfig.Visual.style == "Beacon" then
        local beam = Instance.new("Part")
        beam.Name = "Beacon"
        beam.Size = Vector3.new(CheckpointConfig.BEACON_WIDTH, CheckpointConfig.BEACON_HEIGHT, CheckpointConfig.BEACON_WIDTH)
        beam.Color = CheckpointConfig.Visual.inactiveColor
        beam.Material = Enum.Material.Neon
        beam.Transparency = 0.7
        beam.Anchored = true
        beam.CanCollide = false
        beam.CFrame = instance.CFrame + Vector3.new(0, CheckpointConfig.BEACON_HEIGHT / 2, 0)
        beam.Parent = instance
    end

    -- Touch detection
    instance.Touched:Connect(function(hit: BasePart)
        local character = hit.Parent :: Model?
        if not character then return end
        local player = Players:GetPlayerFromCharacter(character)
        if not player then return end

        CheckpointService.ActivateCheckpoint(player, stageNumber)
    end)
end

-------------------------------------------------
-- Checkpoint Activation
-------------------------------------------------

function CheckpointService.ActivateCheckpoint(player: Player, stageNumber: number)
    local state = playerStates[player]
    if not state then return end

    local checkpoint = checkpoints[stageNumber]
    if not checkpoint then return end

    -- Debounce
    if tick() - state.lastSaveTime < CheckpointConfig.SAVE_DEBOUNCE then return end

    -- Sequential mode: can only activate next checkpoint
    if CheckpointConfig.SEQUENTIAL_MODE then
        if stageNumber > state.currentCheckpoint + 1 then return end
        if stageNumber <= state.currentCheckpoint then return end -- already passed
    end

    -- Already activated this specific checkpoint
    if state.activatedCheckpoints[stageNumber] then
        -- Still update spawn if it is a higher checkpoint
        if stageNumber > state.currentCheckpoint then
            state.currentCheckpoint = stageNumber
        else
            return
        end
    end

    state.lastSaveTime = tick()
    state.currentCheckpoint = stageNumber
    state.activatedCheckpoints[stageNumber] = true

    if stageNumber > state.highestCheckpoint then
        state.highestCheckpoint = stageNumber
    end

    -- Update visuals for this player (checkpoint appears activated)
    CheckpointService._ActivateVisuals(checkpoint, player)

    -- Notify client
    local remotes = ReplicatedStorage:FindFirstChild("CheckpointRemotes")
    if remotes then
        local activatedEvent = remotes:FindFirstChild("CheckpointActivated") :: RemoteEvent
        if activatedEvent then
            activatedEvent:FireClient(player, stageNumber, checkpoint.part.Position)
        end
    end

    -- Save to DataStore
    savePlayerState(player)
end

-------------------------------------------------
-- Visual Activation
-------------------------------------------------

function CheckpointService._ActivateVisuals(checkpoint: CheckpointData, player: Player)
    local part = checkpoint.part

    -- Change color
    part.Color = CheckpointConfig.Visual.activeColor
    part:SetAttribute("Activated", true)

    -- Glow effect
    if CheckpointConfig.Visual.glowEnabled then
        local existingLight = part:FindFirstChildOfClass("PointLight")
        if not existingLight then
            local light = Instance.new("PointLight")
            light.Color = CheckpointConfig.Visual.activeColor
            light.Brightness = 2
            light.Range = 15
            light.Parent = part
        end
    end

    -- Flag raise animation
    if CheckpointConfig.Visual.style == "Flag" and CheckpointConfig.Visual.flagRaiseAnimation then
        local flag = part:FindFirstChild("Flag") :: BasePart?
        if flag then
            local pole = part:FindFirstChild("FlagPole") :: BasePart?
            if pole then
                flag.Color = CheckpointConfig.Visual.activeColor
                local targetCF = pole.CFrame * CFrame.new(0, 3, 1.5)
                TweenService:Create(flag, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
                    CFrame = targetCF,
                }):Play()
            end
        end
    end

    -- Beacon pulse
    if CheckpointConfig.Visual.style == "Beacon" then
        local beacon = part:FindFirstChild("Beacon") :: BasePart?
        if beacon then
            beacon.Color = CheckpointConfig.Visual.activeColor
            beacon.Transparency = 0.5
        end
    end

    -- Activation particles (fire from server, visible to all)
    if CheckpointConfig.Visual.particlesOnActivation then
        local particles = Instance.new("ParticleEmitter")
        particles.Color = ColorSequence.new(CheckpointConfig.Visual.activeColor)
        particles.Size = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(1, 0),
        })
        particles.Lifetime = NumberRange.new(0.5, 1.5)
        particles.Rate = 80
        particles.Speed = NumberRange.new(5, 15)
        particles.SpreadAngle = Vector2.new(360, 360)
        particles.Parent = part

        task.delay(2, function()
            particles.Rate = 0
            task.delay(2, function()
                particles:Destroy()
            end)
        end)
    end
end

-------------------------------------------------
-- Respawn at Checkpoint
-------------------------------------------------

function CheckpointService.RespawnAtCheckpoint(player: Player)
    local state = playerStates[player]
    if not state then return end

    local checkpoint = checkpoints[state.currentCheckpoint]
    if not checkpoint then
        -- Fallback: find first checkpoint
        checkpoint = checkpoints[1]
        if not checkpoint then return end
    end

    local character = player.Character
    if not character then return end

    local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
    if rootPart then
        rootPart.CFrame = checkpoint.spawnCFrame
        -- Reset velocity
        rootPart.AssemblyLinearVelocity = Vector3.zero
        rootPart.AssemblyAngularVelocity = Vector3.zero
    end
end

function CheckpointService.GetCurrentCheckpoint(player: Player): number
    local state = playerStates[player]
    return if state then state.currentCheckpoint else 1
end

function CheckpointService.GetHighestCheckpoint(player: Player): number
    local state = playerStates[player]
    return if state then state.highestCheckpoint else 1
end

-------------------------------------------------
-- Teleport to Specific Checkpoint
-------------------------------------------------

function CheckpointService.TeleportToCheckpoint(player: Player, stageNumber: number): boolean
    local state = playerStates[player]
    if not state then return false end

    -- Can only teleport to activated checkpoints
    if not state.activatedCheckpoints[stageNumber] then
        return false
    end

    local checkpoint = checkpoints[stageNumber]
    if not checkpoint then return false end

    state.currentCheckpoint = stageNumber

    local character = player.Character
    if character then
        local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
        if rootPart then
            rootPart.CFrame = checkpoint.spawnCFrame
            rootPart.AssemblyLinearVelocity = Vector3.zero
        end
    end

    return true
end

-------------------------------------------------
-- Init
-------------------------------------------------

function CheckpointService.Init()
    -- Create remotes
    local remotesFolder = Instance.new("Folder")
    remotesFolder.Name = "CheckpointRemotes"
    remotesFolder.Parent = ReplicatedStorage

    for _, name in { "CheckpointActivated", "TeleportRequest", "CheckpointList" } do
        local remote = Instance.new("RemoteEvent")
        remote.Name = name
        remote.Parent = remotesFolder
    end

    local getCheckpoints = Instance.new("RemoteFunction")
    getCheckpoints.Name = "GetCheckpoints"
    getCheckpoints.Parent = remotesFolder

    -- Teleport request from client
    local teleportReq = remotesFolder:FindFirstChild("TeleportRequest") :: RemoteEvent
    teleportReq.OnServerEvent:Connect(function(player: Player, stageNumber: number)
        CheckpointService.TeleportToCheckpoint(player, stageNumber)
    end)

    -- Get activated checkpoints for UI
    getCheckpoints.OnServerInvoke = function(player: Player)
        local state = playerStates[player]
        if not state then return {} end
        return {
            current = state.currentCheckpoint,
            highest = state.highestCheckpoint,
            activated = state.activatedCheckpoints,
        }
    end

    -- Register checkpoints
    for _, instance in CollectionService:GetTagged(CheckpointConfig.TAG_NAME) do
        registerCheckpoint(instance)
    end
    CollectionService:GetInstanceAddedSignal(CheckpointConfig.TAG_NAME):Connect(registerCheckpoint)

    -- Player lifecycle
    Players.PlayerAdded:Connect(function(player: Player)
        local state = loadPlayerState(player)
        playerStates[player] = state

        player.CharacterAdded:Connect(function(character: Model)
            task.wait(0.2)
            CheckpointService.RespawnAtCheckpoint(player)

            local humanoid = character:WaitForChild("Humanoid") :: Humanoid
            humanoid.Died:Connect(function()
                task.wait(CheckpointConfig.RESPAWN_DELAY)
                player:LoadCharacter()
            end)
        end)

        -- Activate already-visited checkpoints visually
        for stageNum, activated in state.activatedCheckpoints do
            if activated then
                local cp = checkpoints[stageNum]
                if cp then
                    CheckpointService._ActivateVisuals(cp, player)
                end
            end
        end
    end)

    Players.PlayerRemoving:Connect(function(player: Player)
        savePlayerState(player)
        playerStates[player] = nil
    end)

    -- Periodic save
    task.spawn(function()
        while true do
            task.wait(90)
            for plr, _ in playerStates do
                if plr.Parent then
                    savePlayerState(plr)
                end
            end
        end
    end)
end

return CheckpointService
```

---

## 3. Client Checkpoint UI

```luau
-- StarterPlayerScripts/Controllers/CheckpointUI.luau
--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local CheckpointUI = {}

function CheckpointUI.Init()
    local remotes = ReplicatedStorage:WaitForChild("CheckpointRemotes")

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "CheckpointUI"
    screenGui.ResetOnSpawn = false
    screenGui.Parent = playerGui

    -- Checkpoint reached notification
    local notification = Instance.new("TextLabel")
    notification.Name = "Notification"
    notification.Size = UDim2.fromOffset(400, 60)
    notification.Position = UDim2.new(0.5, -200, 0.3, 0)
    notification.BackgroundTransparency = 1
    notification.Text = ""
    notification.TextColor3 = Color3.fromRGB(50, 255, 50)
    notification.TextSize = 32
    notification.Font = Enum.Font.GothamBold
    notification.TextTransparency = 1
    notification.TextStrokeTransparency = 0.5
    notification.Parent = screenGui

    local activatedEvent = remotes:WaitForChild("CheckpointActivated") :: RemoteEvent
    activatedEvent.OnClientEvent:Connect(function(stageNumber: number, _position: Vector3)
        -- Show checkpoint notification
        notification.Text = "Checkpoint " .. tostring(stageNumber) .. " Reached!"
        notification.TextTransparency = 0

        -- Fade in
        local fadeIn = TweenService:Create(notification, TweenInfo.new(0.3), {
            TextTransparency = 0,
        })
        fadeIn:Play()

        -- Scale pop effect
        notification.TextSize = 40
        TweenService:Create(notification, TweenInfo.new(0.3, Enum.EasingStyle.Back), {
            TextSize = 32,
        }):Play()

        -- Hold, then fade out
        task.delay(2, function()
            TweenService:Create(notification, TweenInfo.new(0.5), {
                TextTransparency = 1,
            }):Play()
        end)

        -- Sound effect
        local sound = Instance.new("Sound")
        sound.SoundId = "rbxassetid://0" -- replace with checkpoint sound
        sound.Volume = 0.8
        sound.Parent = playerGui
        sound:Play()
        sound.Ended:Connect(function()
            sound:Destroy()
        end)
    end)
end

return CheckpointUI
```

---

## Key Implementation Notes

1. **Sequential mode**: When enabled, players must reach checkpoints in order (can not skip ahead). Disable for open-world exploration.
2. **Per-player tracking**: Each player has independent checkpoint progress stored in a DataStore.
3. **Visual styles**: Flag (pole + cloth), Beacon (vertical light beam), Platform (color-changing pad), Ring (glowing ring).
4. **Auto-save on touch**: Touching a checkpoint instantly saves it as the player's respawn point.
5. **Respawn handling**: On death, players auto-respawn after a delay and are teleported to their last checkpoint.
6. **Teleport API**: Players can teleport back to any previously activated checkpoint (useful for checkpoint select menus).
7. **Velocity reset**: On respawn, both linear and angular velocity are zeroed to prevent carry-over momentum.
8. **Debounce**: Prevents rapid re-triggering when standing on a checkpoint.

---

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

The user may specify:
- `$SEQUENTIAL` -- Whether checkpoints must be reached in order (default true)
- `$VISUAL_STYLE` -- "Flag", "Beacon", "Platform", or "Ring" (default "Flag")
- `$RESPAWN_DELAY` -- Seconds before auto-respawn (default 1.0)
- `$PERSISTENCE` -- "datastore" (default) or "none" for session-only
- `$TELEPORT_MENU` -- Whether to include a checkpoint teleport selection UI
- `$PARTICLES` -- Whether activation shows particle effects (default true)
- `$SOUND` -- Whether activation plays a sound (default true)
- `$GLOW` -- Whether activated checkpoints emit light (default true)
