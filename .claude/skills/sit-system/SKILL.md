---
name: sit-system
description: |
  Seat and sit system for Roblox. Sit on chairs, benches, and custom furniture,
  custom sit animations per seat type, occupied/available detection with indicators,
  stand-up mechanics, and proximity prompt integration.
  앉기 시스템, 의자, 벤치, 커스텀 앉기 애니메이션, 점유 감지, 일어서기
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
effort: high
---

# Seat / Sit System

Build a comprehensive seating system with custom sit animations, occupied detection, visual indicators, proximity prompts, and multi-seat furniture support.

## Architecture Overview

```
ServerScriptService/
  SeatService.server.lua         -- Manages seat state, occupancy, stand-up
ReplicatedStorage/
  SeatConfig.lua                 -- Seat type definitions and animations
  SeatShared.lua                 -- Shared types
StarterPlayerScripts/
  SeatClient.lua                 -- Proximity detection, UI prompts, animations
Workspace/
  Seating/                       -- Seat parts tagged "Seat" with attributes
```

## Shared Types and Config

```lua
-- ReplicatedStorage/SeatShared.lua
local SeatShared = {}

export type SeatType = "Chair" | "Bench" | "Throne" | "Stool" | "Ground" | "Couch"

export type SeatDefinition = {
    seatType: SeatType,
    sitAnimationId: string?,     -- custom sit animation (nil = default)
    sitCFrame: CFrame?,          -- offset from seat part for sit position
    canRotate: boolean,          -- can player look around while seated
    promptText: string,          -- "Sit" / "Take a seat" etc.
    promptDistance: number,       -- how far the prompt appears
    standUpOffset: Vector3?,     -- where player teleports when standing
}

export type SeatState = {
    seatPart: BasePart,
    occupant: Player?,
    seatType: SeatType,
    isOccupied: boolean,
}

return SeatShared
```

```lua
-- ReplicatedStorage/SeatConfig.lua
local SeatShared = require(script.Parent:WaitForChild("SeatShared"))

local SeatConfig = {}

local seatTypes: { [SeatShared.SeatType]: SeatShared.SeatDefinition } = {
    Chair = {
        seatType = "Chair",
        sitAnimationId = nil, -- uses Roblox default Sitting
        sitCFrame = CFrame.new(0, 0, 0),
        canRotate = false,
        promptText = "Sit",
        promptDistance = 8,
        standUpOffset = Vector3.new(0, 0, -3),
    },
    Bench = {
        seatType = "Bench",
        sitAnimationId = nil,
        sitCFrame = CFrame.new(0, 0, 0),
        canRotate = false,
        promptText = "Sit on Bench",
        promptDistance = 8,
        standUpOffset = Vector3.new(0, 0, -3),
    },
    Throne = {
        seatType = "Throne",
        sitAnimationId = "rbxassetid://0", -- regal sit animation
        sitCFrame = CFrame.new(0, 0.5, 0),
        canRotate = false,
        promptText = "Take the Throne",
        promptDistance = 10,
        standUpOffset = Vector3.new(0, 0, -4),
    },
    Stool = {
        seatType = "Stool",
        sitAnimationId = nil,
        sitCFrame = CFrame.new(0, 0, 0),
        canRotate = true,
        promptText = "Sit",
        promptDistance = 6,
        standUpOffset = Vector3.new(0, 0, -2),
    },
    Ground = {
        seatType = "Ground",
        sitAnimationId = "rbxassetid://0", -- cross-legged sit
        sitCFrame = CFrame.new(0, -1.5, 0),
        canRotate = true,
        promptText = "Sit Down",
        promptDistance = 6,
        standUpOffset = Vector3.new(0, 2, 0),
    },
    Couch = {
        seatType = "Couch",
        sitAnimationId = "rbxassetid://0", -- relaxed lean-back
        sitCFrame = CFrame.new(0, -0.2, 0.3),
        canRotate = false,
        promptText = "Sit on Couch",
        promptDistance = 8,
        standUpOffset = Vector3.new(0, 0, -3),
    },
}

function SeatConfig.getSeatType(seatType: SeatShared.SeatType): SeatShared.SeatDefinition?
    return seatTypes[seatType]
end

function SeatConfig.getDefault(): SeatShared.SeatDefinition
    return seatTypes.Chair
end

return SeatConfig
```

## Server: SeatService

```lua
-- ServerScriptService/SeatService.server.lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local SeatConfig = require(ReplicatedStorage:WaitForChild("SeatConfig"))
local SeatShared = require(ReplicatedStorage:WaitForChild("SeatShared"))

local SeatRemote = Instance.new("RemoteEvent")
SeatRemote.Name = "SeatRemote"
SeatRemote.Parent = ReplicatedStorage

local SeatRequestRemote = Instance.new("RemoteEvent")
SeatRequestRemote.Name = "SeatRequestRemote"
SeatRequestRemote.Parent = ReplicatedStorage

-- Track all seat states
local seatStates: { [BasePart]: SeatShared.SeatState } = {}

-- Track which seat each player is in
local playerSeats: { [Player]: BasePart } = {}

--------------------------------------------------------------------------------
-- Initialize seats from tagged parts
--------------------------------------------------------------------------------
local function initSeat(part: BasePart)
    local seatType = part:GetAttribute("SeatType") or "Chair"
    seatStates[part] = {
        seatPart = part,
        occupant = nil,
        seatType = seatType,
        isOccupied = false,
    }
    -- Set an attribute the client can read for indicators
    part:SetAttribute("IsOccupied", false)
    part:SetAttribute("OccupantName", "")
end

for _, part in CollectionService:GetTagged("CustomSeat") do
    initSeat(part)
end

CollectionService:GetInstanceAddedSignal("CustomSeat"):Connect(function(part)
    if part:IsA("BasePart") then
        initSeat(part)
    end
end)

CollectionService:GetInstanceRemovedSignal("CustomSeat"):Connect(function(part)
    if seatStates[part] then
        local occupant = seatStates[part].occupant
        if occupant then
            playerSeats[occupant] = nil
        end
        seatStates[part] = nil
    end
end)

--------------------------------------------------------------------------------
-- Sit a player in a seat
--------------------------------------------------------------------------------
local function sitPlayer(player: Player, seatPart: BasePart)
    local state = seatStates[seatPart]
    if not state then return end
    if state.isOccupied then
        SeatRemote:FireClient(player, "SeatOccupied", seatPart)
        return
    end

    local character = player.Character
    if not character then return end
    local humanoid = character:FindFirstChildWhichIsA("Humanoid")
    if not humanoid or humanoid.Health <= 0 then return end
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not rootPart then return end

    -- If player is already sitting somewhere, stand up first
    if playerSeats[player] then
        standPlayer(player)
    end

    -- Get seat config
    local config = SeatConfig.getSeatType(state.seatType) or SeatConfig.getDefault()

    -- Position character on the seat
    local sitOffset = config.sitCFrame or CFrame.new()
    rootPart.CFrame = seatPart.CFrame * sitOffset * CFrame.new(0, 2.5, 0)

    -- Use Roblox Seat if available, otherwise manually sit
    local seatInstance = seatPart:FindFirstChildWhichIsA("Seat")
    if seatInstance then
        seatInstance:Sit(humanoid)
    else
        humanoid.Sit = true
        -- Weld character to seat
        local weld = Instance.new("WeldConstraint")
        weld.Name = "SeatWeld"
        weld.Part0 = rootPart
        weld.Part1 = seatPart
        weld.Parent = rootPart
    end

    -- Update state
    state.occupant = player
    state.isOccupied = true
    playerSeats[player] = seatPart

    -- Update attributes for client-side indicators
    seatPart:SetAttribute("IsOccupied", true)
    seatPart:SetAttribute("OccupantName", player.Name)

    -- Notify clients
    SeatRemote:FireAllClients("PlayerSat", player, seatPart, state.seatType)
end

--------------------------------------------------------------------------------
-- Stand a player up from their seat
--------------------------------------------------------------------------------
function standPlayer(player: Player)
    local seatPart = playerSeats[player]
    if not seatPart then return end

    local state = seatStates[seatPart]
    local character = player.Character
    local humanoid = character and character:FindFirstChildWhichIsA("Humanoid")
    local rootPart = character and character:FindFirstChild("HumanoidRootPart")

    -- Remove weld
    if rootPart then
        local weld = rootPart:FindFirstChild("SeatWeld")
        if weld then weld:Destroy() end
    end

    -- Unsit
    if humanoid then
        humanoid.Sit = false
    end

    -- Teleport to stand-up position
    if rootPart and state then
        local config = SeatConfig.getSeatType(state.seatType) or SeatConfig.getDefault()
        local standOffset = config.standUpOffset or Vector3.new(0, 0, -3)
        rootPart.CFrame = seatPart.CFrame * CFrame.new(standOffset)
    end

    -- Update state
    if state then
        state.occupant = nil
        state.isOccupied = false
        seatPart:SetAttribute("IsOccupied", false)
        seatPart:SetAttribute("OccupantName", "")
    end

    playerSeats[player] = nil
    SeatRemote:FireAllClients("PlayerStood", player, seatPart)
end

--------------------------------------------------------------------------------
-- Listen for requests
--------------------------------------------------------------------------------
SeatRequestRemote.OnServerEvent:Connect(function(player: Player, action: string, seatPart: BasePart?)
    if action == "Sit" and seatPart then
        sitPlayer(player, seatPart)
    elseif action == "Stand" then
        standPlayer(player)
    end
end)

-- Auto-stand when player dies or leaves
Players.PlayerRemoving:Connect(function(player)
    if playerSeats[player] then
        standPlayer(player)
    end
end)

-- Handle character death
Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(function(character)
        local humanoid = character:WaitForChild("Humanoid")
        humanoid.Died:Connect(function()
            if playerSeats[player] then
                -- Just clean up state, don't teleport dead character
                local seatPart = playerSeats[player]
                local state = seatStates[seatPart]
                if state then
                    state.occupant = nil
                    state.isOccupied = false
                    seatPart:SetAttribute("IsOccupied", false)
                    seatPart:SetAttribute("OccupantName", "")
                end
                playerSeats[player] = nil
            end
        end)
    end)
end)
```

## Client: Seat Controller

```lua
-- StarterPlayerScripts/SeatClient.lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local UserInputService = game:GetService("UserInputService")

local SeatConfig = require(ReplicatedStorage:WaitForChild("SeatConfig"))
local SeatRemote = ReplicatedStorage:WaitForChild("SeatRemote")
local SeatRequestRemote = ReplicatedStorage:WaitForChild("SeatRequestRemote")

local player = Players.LocalPlayer

-- Custom sit animation tracks
local currentSitTrack: AnimationTrack? = nil
local isSitting = false

--------------------------------------------------------------------------------
-- Create ProximityPrompt for each seat
--------------------------------------------------------------------------------
local function setupSeatPrompt(part: BasePart)
    if part:FindFirstChildWhichIsA("ProximityPrompt") then return end

    local seatType = part:GetAttribute("SeatType") or "Chair"
    local config = SeatConfig.getSeatType(seatType) or SeatConfig.getDefault()

    local prompt = Instance.new("ProximityPrompt")
    prompt.ActionText = config.promptText
    prompt.ObjectText = config.seatType
    prompt.MaxActivationDistance = config.promptDistance
    prompt.HoldDuration = 0
    prompt.RequiresLineOfSight = false
    prompt.Parent = part

    prompt.Triggered:Connect(function(triggerPlayer)
        if triggerPlayer ~= player then return end
        if isSitting then
            SeatRequestRemote:FireServer("Stand")
        else
            SeatRequestRemote:FireServer("Sit", part)
        end
    end)

    -- Update prompt based on occupancy
    part:GetAttributeChangedSignal("IsOccupied"):Connect(function()
        local occupied = part:GetAttribute("IsOccupied")
        local occupantName = part:GetAttribute("OccupantName") or ""
        if occupied and occupantName ~= player.Name then
            prompt.Enabled = false
        else
            prompt.Enabled = true
            if occupied and occupantName == player.Name then
                prompt.ActionText = "Stand Up"
            else
                prompt.ActionText = config.promptText
            end
        end
    end)
end

-- Setup existing seats
for _, part in CollectionService:GetTagged("CustomSeat") do
    setupSeatPrompt(part)
end

CollectionService:GetInstanceAddedSignal("CustomSeat"):Connect(function(part)
    if part:IsA("BasePart") then
        setupSeatPrompt(part)
    end
end)

--------------------------------------------------------------------------------
-- Occupied indicator (billboard GUI showing "Occupied")
--------------------------------------------------------------------------------
local function createOccupiedIndicator(seatPart: BasePart)
    local existing = seatPart:FindFirstChild("OccupiedIndicator")
    if existing then return end

    local billboard = Instance.new("BillboardGui")
    billboard.Name = "OccupiedIndicator"
    billboard.Size = UDim2.fromOffset(100, 30)
    billboard.StudsOffset = Vector3.new(0, 4, 0)
    billboard.AlwaysOnTop = false
    billboard.Enabled = false
    billboard.Parent = seatPart

    local label = Instance.new("TextLabel")
    label.Size = UDim2.fromScale(1, 1)
    label.BackgroundTransparency = 0.3
    label.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    label.Text = "Occupied"
    label.TextColor3 = Color3.fromRGB(255, 100, 100)
    label.TextSize = 14
    label.Font = Enum.Font.GothamBold
    label.Parent = billboard

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = label

    seatPart:GetAttributeChangedSignal("IsOccupied"):Connect(function()
        billboard.Enabled = seatPart:GetAttribute("IsOccupied") == true
    end)
end

for _, part in CollectionService:GetTagged("CustomSeat") do
    createOccupiedIndicator(part)
end

--------------------------------------------------------------------------------
-- Custom sit animation playback
--------------------------------------------------------------------------------
local function playSitAnimation(seatType: string)
    local config = SeatConfig.getSeatType(seatType)
    if not config or not config.sitAnimationId then return end
    if config.sitAnimationId == "" or config.sitAnimationId == "rbxassetid://0" then return end

    local character = player.Character
    if not character then return end
    local humanoid = character:FindFirstChildWhichIsA("Humanoid")
    if not humanoid then return end

    local animator = humanoid:FindFirstChildWhichIsA("Animator")
    if not animator then return end

    local animation = Instance.new("Animation")
    animation.AnimationId = config.sitAnimationId

    local success, track = pcall(function()
        return animator:LoadAnimation(animation)
    end)

    if success and track then
        track.Priority = Enum.AnimationPriority.Action4
        track.Looped = true
        track:Play(0.3)
        currentSitTrack = track
    end
end

local function stopSitAnimation()
    if currentSitTrack and currentSitTrack.IsPlaying then
        currentSitTrack:Stop(0.3)
    end
    currentSitTrack = nil
end

--------------------------------------------------------------------------------
-- Handle server events
--------------------------------------------------------------------------------
SeatRemote.OnClientEvent:Connect(function(action: string, ...)
    if action == "PlayerSat" then
        local satPlayer, seatPart, seatType = ...
        if satPlayer == player then
            isSitting = true
            playSitAnimation(seatType)
        end

    elseif action == "PlayerStood" then
        local stoodPlayer, seatPart = ...
        if stoodPlayer == player then
            isSitting = false
            stopSitAnimation()
        end

    elseif action == "SeatOccupied" then
        -- Seat was already taken
        warn("[Seat] That seat is occupied!")
    end
end)

-- Jump to stand up
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if isSitting and input.KeyCode == Enum.KeyCode.Space then
        SeatRequestRemote:FireServer("Stand")
    end
end)
```

## Seat Setup Guide

To add a custom seat to your game:

1. Create a Part (or use a Model with a PrimaryPart)
2. Add the tag `CustomSeat` via CollectionService or Studio Tag Editor
3. Set attribute `SeatType` (string): `"Chair"`, `"Bench"`, `"Throne"`, `"Stool"`, `"Ground"`, or `"Couch"`
4. Optionally override defaults with attributes:
   - `PromptText` (string): custom prompt text
   - `PromptDistance` (number): interaction range

### Multi-Seat Furniture (Benches, Couches)

For furniture with multiple seat positions, create multiple invisible seat parts as children of the furniture model, each tagged `CustomSeat`. Position them at each seating spot.

```
BenchModel/
  BenchMesh (MeshPart, visual only)
  Seat1 (Part, tagged "CustomSeat", SeatType="Bench", transparent)
  Seat2 (Part, tagged "CustomSeat", SeatType="Bench", transparent)
  Seat3 (Part, tagged "CustomSeat", SeatType="Bench", transparent)
```

## Key Implementation Notes

1. **ProximityPrompt**: Each seat gets an auto-created ProximityPrompt. Text changes based on occupancy state.

2. **Weld-based sitting**: For parts without a built-in Seat instance, the system creates a WeldConstraint to anchor the player. This allows custom sit positions.

3. **Occupied detection**: Server sets `IsOccupied` and `OccupantName` attributes on the seat part. Clients read these for UI indicators and prompt toggling.

4. **Custom animations**: Each seat type can have its own sit animation. The animation plays at Action4 priority to override default sitting.

5. **Stand up**: Press Space to stand. The player is teleported to `standUpOffset` relative to the seat.

6. **Death cleanup**: If a player dies while seated, the state is cleaned up server-side without teleporting.

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

When the user asks for a sit system, ask:
- What types of seats do you need? (chairs, benches, ground, throne)
- Do you need custom sit animations per seat type?
- Should seats show occupied/available indicators?
- Do you need multi-seat furniture (benches with 3+ positions)?
- How should the player stand up? (jump key, prompt, auto after timer)
- Should sitting affect gameplay? (regen health, protect from damage)
