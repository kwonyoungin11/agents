---
name: dance
description: |
  Dance animation system for Roblox. Dance floor detection with zones, synchronized
  group dancing, dance emote list with categories, DJ booth integration, beat-matching
  animations, and dance move combos.
  댄스 애니메이션, 댄스 플로어 감지, 동기화 춤, 댄스 이모트, 리듬 동기화
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
effort: high
---

# Dance Animation System

Build a dance system with dance floor zones, synchronized group dancing, curated dance move lists, and optional music-beat synchronization.

## Architecture Overview

```
ServerScriptService/
  DanceService.server.lua        -- Manages dance zones, sync, player states
ReplicatedStorage/
  DanceConfig.lua                -- Dance definitions and playlist
  DanceShared.lua                -- Shared types
StarterPlayerScripts/
  DanceClient.lua                -- Animation playback, zone detection, UI
Workspace/
  DanceFloors/                   -- Parts tagged "DanceFloor" with attributes
```

## Shared Types and Config

```lua
-- ReplicatedStorage/DanceShared.lua
local DanceShared = {}

export type DanceDefinition = {
    displayName: string,
    animationId: string,
    icon: string,
    bpm: number?,           -- beats per minute for sync
    difficulty: "Easy" | "Medium" | "Hard",
    category: "Classic" | "Modern" | "Silly" | "Group",
    looping: boolean,
}

export type DanceFloorConfig = {
    musicId: string?,        -- optional background music
    bpm: number?,
    lightingEnabled: boolean,
    syncMode: "Free" | "Synced", -- Free = individual, Synced = everyone same timing
    maxDancers: number?,
}

export type DancerState = {
    player: Player,
    currentDance: string?,
    startedAt: number,
    floorId: string?,
}

return DanceShared
```

```lua
-- ReplicatedStorage/DanceConfig.lua
local DanceShared = require(script.Parent:WaitForChild("DanceShared"))

local DanceConfig = {}

local dances: { [string]: DanceShared.DanceDefinition } = {
    Disco = {
        displayName = "Disco",
        animationId = "rbxassetid://507771019",
        icon = "rbxassetid://0",
        bpm = 120,
        difficulty = "Easy",
        category = "Classic",
        looping = true,
    },
    Robot = {
        displayName = "Robot",
        animationId = "rbxassetid://507776043",
        icon = "rbxassetid://0",
        bpm = 110,
        difficulty = "Medium",
        category = "Classic",
        looping = true,
    },
    Floss = {
        displayName = "Floss",
        animationId = "rbxassetid://507776720",
        icon = "rbxassetid://0",
        bpm = 130,
        difficulty = "Medium",
        category = "Modern",
        looping = true,
    },
    Chicken = {
        displayName = "Chicken Dance",
        animationId = "rbxassetid://507770239",
        icon = "rbxassetid://0",
        bpm = 100,
        difficulty = "Easy",
        category = "Silly",
        looping = true,
    },
    Macarena = {
        displayName = "Macarena",
        animationId = "rbxassetid://507770453",
        icon = "rbxassetid://0",
        bpm = 103,
        difficulty = "Easy",
        category = "Classic",
        looping = true,
    },
    Synchronized = {
        displayName = "Group Wave",
        animationId = "rbxassetid://507770677",
        icon = "rbxassetid://0",
        bpm = 120,
        difficulty = "Easy",
        category = "Group",
        looping = true,
    },
}

function DanceConfig.getDance(name: string): DanceShared.DanceDefinition?
    return dances[name]
end

function DanceConfig.getAllDances(): { [string]: DanceShared.DanceDefinition }
    return dances
end

function DanceConfig.getDancesByCategory(category: string): { [string]: DanceShared.DanceDefinition }
    local result = {}
    for name, dance in dances do
        if dance.category == category then
            result[name] = dance
        end
    end
    return result
end

return DanceConfig
```

## Server: DanceService

```lua
-- ServerScriptService/DanceService.server.lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local DanceConfig = require(ReplicatedStorage:WaitForChild("DanceConfig"))
local DanceShared = require(ReplicatedStorage:WaitForChild("DanceShared"))

local DanceRemote = Instance.new("RemoteEvent")
DanceRemote.Name = "DanceRemote"
DanceRemote.Parent = ReplicatedStorage

local DanceRequestRemote = Instance.new("RemoteEvent")
DanceRequestRemote.Name = "DanceRequestRemote"
DanceRequestRemote.Parent = ReplicatedStorage

-- Active dancers
local dancers: { [Player]: DanceShared.DancerState } = {}

-- Dance floor data keyed by floor part name
local danceFloors: { [string]: DanceShared.DanceFloorConfig } = {}

-- Sync clock: a shared timestamp so all synced dancers start on the same beat
local syncEpoch = tick()

--------------------------------------------------------------------------------
-- Initialize dance floors from tagged parts
--------------------------------------------------------------------------------
local function initDanceFloors()
    for _, part in CollectionService:GetTagged("DanceFloor") do
        local config: DanceShared.DanceFloorConfig = {
            musicId = part:GetAttribute("MusicId"),
            bpm = part:GetAttribute("BPM") or 120,
            lightingEnabled = part:GetAttribute("LightingEnabled") ~= false,
            syncMode = part:GetAttribute("SyncMode") or "Free",
            maxDancers = part:GetAttribute("MaxDancers"),
        }
        danceFloors[part.Name] = config
    end
end

initDanceFloors()

--------------------------------------------------------------------------------
-- Get how many dancers are on a floor
--------------------------------------------------------------------------------
local function getDancerCountOnFloor(floorId: string): number
    local count = 0
    for _, state in dancers do
        if state.floorId == floorId then
            count += 1
        end
    end
    return count
end

--------------------------------------------------------------------------------
-- Get the sync time offset for a dance floor
-- This ensures all synced dancers are aligned to the beat grid
--------------------------------------------------------------------------------
local function getSyncTimeOffset(floorId: string): number
    local config = danceFloors[floorId]
    if not config or config.syncMode ~= "Synced" then
        return 0
    end
    local bpm = config.bpm or 120
    local beatInterval = 60 / bpm
    local elapsed = tick() - syncEpoch
    -- Calculate time until next beat
    local offset = beatInterval - (elapsed % beatInterval)
    return offset
end

--------------------------------------------------------------------------------
-- Handle dance requests
--------------------------------------------------------------------------------
DanceRequestRemote.OnServerEvent:Connect(function(player: Player, action: string, ...)
    if action == "StartDance" then
        local danceName: string, floorId: string? = ...
        local dance = DanceConfig.getDance(danceName)
        if not dance then return end

        -- Check floor capacity
        if floorId and danceFloors[floorId] then
            local config = danceFloors[floorId]
            if config.maxDancers and getDancerCountOnFloor(floorId) >= config.maxDancers then
                DanceRemote:FireClient(player, "FloorFull", floorId)
                return
            end
        end

        local syncOffset = 0
        if floorId then
            syncOffset = getSyncTimeOffset(floorId)
        end

        dancers[player] = {
            player = player,
            currentDance = danceName,
            startedAt = tick(),
            floorId = floorId,
        }

        -- Broadcast dance start to all clients
        DanceRemote:FireAllClients("DanceStarted", player, danceName, floorId, syncOffset)

    elseif action == "StopDance" then
        dancers[player] = nil
        DanceRemote:FireAllClients("DanceStopped", player)

    elseif action == "ChangeDance" then
        local danceName: string = ...
        local dance = DanceConfig.getDance(danceName)
        if not dance then return end
        if dancers[player] then
            dancers[player].currentDance = danceName
            dancers[player].startedAt = tick()
            DanceRemote:FireAllClients("DanceChanged", player, danceName)
        end

    elseif action == "QueryFloor" then
        local floorId: string = ...
        local config = danceFloors[floorId]
        local count = getDancerCountOnFloor(floorId)
        DanceRemote:FireClient(player, "FloorInfo", floorId, config, count)
    end
end)

Players.PlayerRemoving:Connect(function(player)
    if dancers[player] then
        dancers[player] = nil
        DanceRemote:FireAllClients("DanceStopped", player)
    end
end)
```

## Client: Dance Controller

```lua
-- StarterPlayerScripts/DanceClient.lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local DanceConfig = require(ReplicatedStorage:WaitForChild("DanceConfig"))
local DanceRemote = ReplicatedStorage:WaitForChild("DanceRemote")
local DanceRequestRemote = ReplicatedStorage:WaitForChild("DanceRequestRemote")

local player = Players.LocalPlayer

-- Animation track cache per humanoid
local trackCache: { [Humanoid]: { [string]: AnimationTrack } } = {}
local activeTracks: { [Player]: AnimationTrack } = {}

-- Current dance floor the local player is on
local currentFloorId: string? = nil
local isDancing = false

--------------------------------------------------------------------------------
-- Animation loading
--------------------------------------------------------------------------------
local function loadDanceTrack(humanoid: Humanoid, danceName: string): AnimationTrack?
    local dance = DanceConfig.getDance(danceName)
    if not dance then return nil end

    if not trackCache[humanoid] then
        trackCache[humanoid] = {}
    end
    if trackCache[humanoid][danceName] then
        return trackCache[humanoid][danceName]
    end

    local animator = humanoid:FindFirstChildWhichIsA("Animator")
    if not animator then
        animator = Instance.new("Animator")
        animator.Parent = humanoid
    end

    local animation = Instance.new("Animation")
    animation.AnimationId = dance.animationId

    local success, track = pcall(function()
        return animator:LoadAnimation(animation)
    end)

    if success and track then
        track.Priority = Enum.AnimationPriority.Action
        track.Looped = dance.looping
        trackCache[humanoid][danceName] = track
        return track
    end
    return nil
end

--------------------------------------------------------------------------------
-- Play dance animation on a player
--------------------------------------------------------------------------------
local function playDance(targetPlayer: Player, danceName: string, syncDelay: number?)
    local character = targetPlayer.Character
    if not character then return end
    local humanoid = character:FindFirstChildWhichIsA("Humanoid")
    if not humanoid then return end

    -- Stop existing dance
    local existingTrack = activeTracks[targetPlayer]
    if existingTrack and existingTrack.IsPlaying then
        existingTrack:Stop(0.2)
    end

    local track = loadDanceTrack(humanoid, danceName)
    if not track then return end

    -- Apply sync delay if needed (wait for next beat)
    if syncDelay and syncDelay > 0 then
        task.delay(syncDelay, function()
            track:Play(0.2)
        end)
    else
        track:Play(0.2)
    end

    activeTracks[targetPlayer] = track
end

--------------------------------------------------------------------------------
-- Stop dance animation
--------------------------------------------------------------------------------
local function stopDance(targetPlayer: Player)
    local track = activeTracks[targetPlayer]
    if track and track.IsPlaying then
        track:Stop(0.3)
    end
    activeTracks[targetPlayer] = nil
end

--------------------------------------------------------------------------------
-- Dance floor zone detection (check overlap with tagged parts)
--------------------------------------------------------------------------------
local function detectDanceFloor(): string?
    local character = player.Character
    if not character then return nil end
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not rootPart then return nil end

    local CollectionService = game:GetService("CollectionService")
    for _, floor in CollectionService:GetTagged("DanceFloor") do
        if floor:IsA("BasePart") then
            local floorCF = floor.CFrame
            local floorSize = floor.Size
            local localPos = floorCF:PointToObjectSpace(rootPart.Position)
            -- Check if inside the bounding box (with some Y tolerance)
            if math.abs(localPos.X) <= floorSize.X / 2
                and math.abs(localPos.Z) <= floorSize.Z / 2
                and localPos.Y >= -2 and localPos.Y <= floorSize.Y + 5
            then
                return floor.Name
            end
        end
    end
    return nil
end

-- Periodically check dance floor
RunService.Heartbeat:Connect(function()
    local floorId = detectDanceFloor()
    if floorId ~= currentFloorId then
        currentFloorId = floorId
        -- Could trigger UI changes or music when entering/leaving dance floor
    end
end)

--------------------------------------------------------------------------------
-- Handle server events
--------------------------------------------------------------------------------
DanceRemote.OnClientEvent:Connect(function(action: string, ...)
    if action == "DanceStarted" then
        local targetPlayer, danceName, floorId, syncOffset = ...
        playDance(targetPlayer, danceName, syncOffset)

    elseif action == "DanceStopped" then
        local targetPlayer = ...
        stopDance(targetPlayer)

    elseif action == "DanceChanged" then
        local targetPlayer, danceName = ...
        playDance(targetPlayer, danceName, 0)

    elseif action == "FloorFull" then
        warn("[Dance] Dance floor is full!")

    elseif action == "FloorInfo" then
        local floorId, config, count = ...
        print(string.format("[Dance] Floor '%s': %d dancers, mode=%s",
            floorId, count, config and config.syncMode or "?"))
    end
end)

-- Stop dance when player moves
local function onCharacterAdded(character: Model)
    local humanoid = character:WaitForChild("Humanoid")
    humanoid.Running:Connect(function(speed)
        if speed > 0.5 and isDancing then
            isDancing = false
            DanceRequestRemote:FireServer("StopDance")
        end
    end)
end

if player.Character then onCharacterAdded(player.Character) end
player.CharacterAdded:Connect(onCharacterAdded)

player.CharacterRemoving:Connect(function(character)
    local humanoid = character:FindFirstChildWhichIsA("Humanoid")
    if humanoid then trackCache[humanoid] = nil end
end)

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------
local DanceClient = {}

function DanceClient.startDance(danceName: string)
    isDancing = true
    DanceRequestRemote:FireServer("StartDance", danceName, currentFloorId)
end

function DanceClient.stopDance()
    isDancing = false
    DanceRequestRemote:FireServer("StopDance")
end

function DanceClient.changeDance(danceName: string)
    DanceRequestRemote:FireServer("ChangeDance", danceName)
end

function DanceClient.isOnDanceFloor(): boolean
    return currentFloorId ~= nil
end

function DanceClient.getCurrentFloor(): string?
    return currentFloorId
end

return DanceClient
```

## Dance Floor Setup

To create a dance floor in your place:

1. Create a Part in Workspace (e.g., a large flat block or cylinder)
2. Add the tag `DanceFloor` via CollectionService or Studio Tag Editor
3. Set these Attributes on the part:
   - `MusicId` (string): `rbxassetid://123456` for background music
   - `BPM` (number): beats per minute of the music
   - `LightingEnabled` (boolean): whether to spawn disco lights
   - `SyncMode` (string): `"Free"` or `"Synced"`
   - `MaxDancers` (number): optional capacity limit

## Disco Lighting Effect (Optional)

```lua
-- Attach this to a DanceFloor part as a child Script
local floor = script.Parent
local lightingEnabled = floor:GetAttribute("LightingEnabled") ~= false
if not lightingEnabled then return end

local TweenService = game:GetService("TweenService")

local colors = {
    Color3.fromRGB(255, 0, 0),
    Color3.fromRGB(0, 255, 0),
    Color3.fromRGB(0, 0, 255),
    Color3.fromRGB(255, 255, 0),
    Color3.fromRGB(255, 0, 255),
    Color3.fromRGB(0, 255, 255),
}

local light = Instance.new("PointLight")
light.Brightness = 3
light.Range = 40
light.Parent = floor

local colorIndex = 1
while true do
    colorIndex = colorIndex % #colors + 1
    local tween = TweenService:Create(light, TweenInfo.new(0.5), {
        Color = colors[colorIndex],
    })
    tween:Play()
    -- Also tween the floor color for a dance floor effect
    TweenService:Create(floor, TweenInfo.new(0.5), {
        Color = colors[colorIndex],
    }):Play()
    task.wait(0.5)
end
```

## Key Implementation Notes

1. **Synchronized dancing**: When `SyncMode` is `"Synced"`, the server calculates a beat-aligned delay so all dancers start on the same beat boundary. This creates a unified group dance feel.

2. **Dance floor detection**: Client-side bounding box check runs every heartbeat. When the player enters a tagged DanceFloor part, `currentFloorId` updates and can trigger UI/music changes.

3. **Floor capacity**: `MaxDancers` attribute limits how many players can dance on one floor simultaneously.

4. **Movement cancels dance**: Running at speed > 0.5 auto-stops the dance and notifies the server.

5. **Animation caching**: Tracks are cached per humanoid to avoid repeated loading.

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

When the user asks for a dance system, ask:
- Do you need synchronized group dancing or free-form individual dances?
- Should dance floors have background music?
- How many dance animations do you want? List specific styles if any.
- Do you need a dance selection UI or just chat commands?
- Should dancing give any gameplay benefits (XP, coins)?
- Do you need disco lighting effects on the dance floor?
