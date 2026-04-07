---
name: emote
description: |
  Emote system for Roblox. Play animations on command, emote wheel UI with radial
  selection, custom animation support, emote chat commands (/e dance, /e wave),
  and emote ownership tracking.
  이모트 시스템, 애니메이션 재생, 이모트 휠 UI, 커스텀 애니메이션, 채팅 명령어
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
effort: high
---

# Emote System

Build a complete emote system for Roblox with a radial emote wheel, chat command integration, custom animations, and ownership/unlock tracking.

## Architecture Overview

```
ServerScriptService/
  EmoteService.server.lua        -- Validates emote requests, manages ownership
ReplicatedStorage/
  EmoteConfig.lua                -- Emote definitions (animation IDs, categories)
  EmoteShared.lua                -- Shared types
StarterPlayerScripts/
  EmoteClient.lua                -- Plays animations, handles input
StarterGui/
  EmoteWheelUI/                  -- Radial emote selector ScreenGui
```

## Emote Config and Shared Types

```lua
-- ReplicatedStorage/EmoteShared.lua
local EmoteShared = {}

export type EmoteDefinition = {
    displayName: string,
    animationId: string,         -- rbxassetid://...
    icon: string,                -- thumbnail asset ID
    category: "Greeting" | "Dance" | "Action" | "Mood" | "Celebration",
    looping: boolean,
    priority: Enum.AnimationPriority,
    isDefault: boolean,          -- available to all players
    duration: number?,           -- auto-stop after N seconds (nil = manual stop)
}

export type EmoteSlot = {
    slotIndex: number,
    emoteName: string,
}

return EmoteShared
```

```lua
-- ReplicatedStorage/EmoteConfig.lua
local EmoteShared = require(script.Parent:WaitForChild("EmoteShared"))

local EmoteConfig = {}

local emotes: { [string]: EmoteShared.EmoteDefinition } = {
    Wave = {
        displayName = "Wave",
        animationId = "rbxassetid://507770239",
        icon = "rbxassetid://0",
        category = "Greeting",
        looping = false,
        priority = Enum.AnimationPriority.Action,
        isDefault = true,
        duration = 2,
    },
    Salute = {
        displayName = "Salute",
        animationId = "rbxassetid://507770453",
        icon = "rbxassetid://0",
        category = "Greeting",
        looping = false,
        priority = Enum.AnimationPriority.Action,
        isDefault = true,
        duration = 2.5,
    },
    Laugh = {
        displayName = "Laugh",
        animationId = "rbxassetid://507770818",
        icon = "rbxassetid://0",
        category = "Mood",
        looping = true,
        priority = Enum.AnimationPriority.Action,
        isDefault = true,
    },
    Cheer = {
        displayName = "Cheer",
        animationId = "rbxassetid://507770677",
        icon = "rbxassetid://0",
        category = "Celebration",
        looping = false,
        priority = Enum.AnimationPriority.Action,
        isDefault = true,
        duration = 3,
    },
    Point = {
        displayName = "Point",
        animationId = "rbxassetid://507770453",
        icon = "rbxassetid://0",
        category = "Action",
        looping = false,
        priority = Enum.AnimationPriority.Action,
        isDefault = true,
        duration = 2,
    },
    Dance1 = {
        displayName = "Dance 1",
        animationId = "rbxassetid://507771019",
        icon = "rbxassetid://0",
        category = "Dance",
        looping = true,
        priority = Enum.AnimationPriority.Action,
        isDefault = true,
    },
    Dance2 = {
        displayName = "Dance 2",
        animationId = "rbxassetid://507776043",
        icon = "rbxassetid://0",
        category = "Dance",
        looping = true,
        priority = Enum.AnimationPriority.Action,
        isDefault = true,
    },
    Dance3 = {
        displayName = "Dance 3",
        animationId = "rbxassetid://507776720",
        icon = "rbxassetid://0",
        category = "Dance",
        looping = true,
        priority = Enum.AnimationPriority.Action,
        isDefault = true,
    },
}

function EmoteConfig.getEmote(name: string): EmoteShared.EmoteDefinition?
    return emotes[name]
end

function EmoteConfig.getAllEmotes(): { [string]: EmoteShared.EmoteDefinition }
    return emotes
end

function EmoteConfig.getEmotesByCategory(category: string): { [string]: EmoteShared.EmoteDefinition }
    local result = {}
    for name, emote in emotes do
        if emote.category == category then
            result[name] = emote
        end
    end
    return result
end

return EmoteConfig
```

## Server: EmoteService

```lua
-- ServerScriptService/EmoteService.server.lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Chat = game:GetService("Chat")

local EmoteConfig = require(ReplicatedStorage:WaitForChild("EmoteConfig"))

-- Remote events
local EmoteRemote = Instance.new("RemoteEvent")
EmoteRemote.Name = "EmoteRemote"
EmoteRemote.Parent = ReplicatedStorage

local EmoteRequestRemote = Instance.new("RemoteEvent")
EmoteRequestRemote.Name = "EmoteRequestRemote"
EmoteRequestRemote.Parent = ReplicatedStorage

-- Track owned emotes per player (loaded from DataStore in production)
local playerOwnedEmotes: { [Player]: { [string]: boolean } } = {}

-- Track currently playing emote per player for server-side awareness
local activeEmotes: { [Player]: string } = {}

--------------------------------------------------------------------------------
-- Initialize player emote ownership
--------------------------------------------------------------------------------
local function initializePlayer(player: Player)
    playerOwnedEmotes[player] = {}
    -- Grant all default emotes
    for name, emote in EmoteConfig.getAllEmotes() do
        if emote.isDefault then
            playerOwnedEmotes[player][name] = true
        end
    end
    -- TODO: Load additional owned emotes from DataStore
end

--------------------------------------------------------------------------------
-- Check if player owns an emote
--------------------------------------------------------------------------------
local function playerOwnsEmote(player: Player, emoteName: string): boolean
    local owned = playerOwnedEmotes[player]
    return owned ~= nil and owned[emoteName] == true
end

--------------------------------------------------------------------------------
-- Grant emote to player
--------------------------------------------------------------------------------
local function grantEmote(player: Player, emoteName: string)
    if not playerOwnedEmotes[player] then return end
    playerOwnedEmotes[player][emoteName] = true
    -- Notify client of new emote
    EmoteRemote:FireClient(player, "EmoteGranted", emoteName)
end

--------------------------------------------------------------------------------
-- Handle emote request
--------------------------------------------------------------------------------
local function handleEmoteRequest(player: Player, action: string, emoteName: string?)
    if action == "Play" and emoteName then
        local emote = EmoteConfig.getEmote(emoteName)
        if not emote then return end
        if not playerOwnsEmote(player, emoteName) then
            EmoteRemote:FireClient(player, "NotOwned", emoteName)
            return
        end
        -- Check if player is alive and not already in a state that blocks emotes
        local character = player.Character
        if not character then return end
        local humanoid = character:FindFirstChildWhichIsA("Humanoid")
        if not humanoid or humanoid.Health <= 0 then return end

        activeEmotes[player] = emoteName
        -- Broadcast to all clients so others can see the emote
        EmoteRemote:FireAllClients("PlayEmote", player, emoteName)

    elseif action == "Stop" then
        activeEmotes[player] = nil
        EmoteRemote:FireAllClients("StopEmote", player)
    end
end

--------------------------------------------------------------------------------
-- Chat command integration: /e emoteName
--------------------------------------------------------------------------------
local function onPlayerChatted(player: Player, message: string)
    local lower = string.lower(message)
    -- Match /e <emotename> or /emote <emotename>
    local emoteName = lower:match("^/e%s+(%S+)") or lower:match("^/emote%s+(%S+)")
    if not emoteName then return end

    -- Find emote by display name (case-insensitive)
    for name, emote in EmoteConfig.getAllEmotes() do
        if string.lower(name) == emoteName or string.lower(emote.displayName) == emoteName then
            handleEmoteRequest(player, "Play", name)
            return
        end
    end
end

--------------------------------------------------------------------------------
-- Connections
--------------------------------------------------------------------------------
EmoteRequestRemote.OnServerEvent:Connect(function(player, action, emoteName)
    handleEmoteRequest(player, action, emoteName)
end)

Players.PlayerAdded:Connect(function(player)
    initializePlayer(player)
    player.Chatted:Connect(function(message)
        onPlayerChatted(player, message)
    end)
end)

Players.PlayerRemoving:Connect(function(player)
    playerOwnedEmotes[player] = nil
    activeEmotes[player] = nil
end)
```

## Client: Emote Player

```lua
-- StarterPlayerScripts/EmoteClient.lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local EmoteConfig = require(ReplicatedStorage:WaitForChild("EmoteConfig"))
local EmoteRemote = ReplicatedStorage:WaitForChild("EmoteRemote")
local EmoteRequestRemote = ReplicatedStorage:WaitForChild("EmoteRequestRemote")

local player = Players.LocalPlayer

-- Cache loaded AnimationTracks per humanoid
local animationCache: { [Humanoid]: { [string]: AnimationTrack } } = {}
local currentTrack: AnimationTrack? = nil

--------------------------------------------------------------------------------
-- Load or retrieve animation track
--------------------------------------------------------------------------------
local function getAnimationTrack(humanoid: Humanoid, emoteName: string): AnimationTrack?
    local emote = EmoteConfig.getEmote(emoteName)
    if not emote then return nil end

    if not animationCache[humanoid] then
        animationCache[humanoid] = {}
    end

    if animationCache[humanoid][emoteName] then
        return animationCache[humanoid][emoteName]
    end

    local animator = humanoid:FindFirstChildWhichIsA("Animator")
    if not animator then
        animator = Instance.new("Animator")
        animator.Parent = humanoid
    end

    local animation = Instance.new("Animation")
    animation.AnimationId = emote.animationId

    local success, track = pcall(function()
        return animator:LoadAnimation(animation)
    end)

    if success and track then
        track.Priority = emote.priority
        track.Looped = emote.looping
        animationCache[humanoid][emoteName] = track
        return track
    end

    return nil
end

--------------------------------------------------------------------------------
-- Play emote on a character
--------------------------------------------------------------------------------
local function playEmoteOnCharacter(targetPlayer: Player, emoteName: string)
    local character = targetPlayer.Character
    if not character then return end
    local humanoid = character:FindFirstChildWhichIsA("Humanoid")
    if not humanoid then return end

    local emote = EmoteConfig.getEmote(emoteName)
    if not emote then return end

    local track = getAnimationTrack(humanoid, emoteName)
    if not track then return end

    -- If this is the local player, track the current emote for stopping
    if targetPlayer == player then
        if currentTrack and currentTrack.IsPlaying then
            currentTrack:Stop(0.2)
        end
        currentTrack = track
    end

    track:Play(0.2)

    -- Auto-stop after duration for non-looping emotes
    if emote.duration and emote.duration > 0 then
        task.delay(emote.duration, function()
            if track.IsPlaying then
                track:Stop(0.3)
            end
        end)
    end
end

--------------------------------------------------------------------------------
-- Stop current emote
--------------------------------------------------------------------------------
local function stopCurrentEmote()
    if currentTrack and currentTrack.IsPlaying then
        currentTrack:Stop(0.3)
        currentTrack = nil
    end
end

--------------------------------------------------------------------------------
-- Handle server events
--------------------------------------------------------------------------------
EmoteRemote.OnClientEvent:Connect(function(action: string, ...)
    if action == "PlayEmote" then
        local targetPlayer, emoteName = ...
        playEmoteOnCharacter(targetPlayer, emoteName)
    elseif action == "StopEmote" then
        local targetPlayer = ...
        if targetPlayer == player then
            stopCurrentEmote()
        end
    elseif action == "EmoteGranted" then
        local emoteName = ...
        -- Could show a notification: "New emote unlocked!"
        print("[Emote] Unlocked:", emoteName)
    elseif action == "NotOwned" then
        local emoteName = ...
        warn("[Emote] You don't own:", emoteName)
    end
end)

-- Stop emote when player moves
local function onCharacterAdded(character: Model)
    local humanoid = character:WaitForChild("Humanoid")
    humanoid.Running:Connect(function(speed)
        if speed > 0.5 and currentTrack and currentTrack.IsPlaying then
            stopCurrentEmote()
            EmoteRequestRemote:FireServer("Stop")
        end
    end)
end

if player.Character then
    onCharacterAdded(player.Character)
end
player.CharacterAdded:Connect(onCharacterAdded)

-- Clean up cache when character is removed
player.CharacterRemoving:Connect(function(character)
    local humanoid = character:FindFirstChildWhichIsA("Humanoid")
    if humanoid then
        animationCache[humanoid] = nil
    end
    currentTrack = nil
end)

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------
local EmoteClient = {}

function EmoteClient.playEmote(emoteName: string)
    EmoteRequestRemote:FireServer("Play", emoteName)
end

function EmoteClient.stopEmote()
    stopCurrentEmote()
    EmoteRequestRemote:FireServer("Stop")
end

return EmoteClient
```

## Emote Wheel UI (Radial Selection)

```lua
-- StarterGui/EmoteWheelUI/EmoteWheel.client.lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local EmoteConfig = require(ReplicatedStorage:WaitForChild("EmoteConfig"))
local EmoteRequestRemote = ReplicatedStorage:WaitForChild("EmoteRequestRemote")

local player = Players.LocalPlayer
local gui = script.Parent

-- Main wheel container
local wheelFrame = Instance.new("Frame")
wheelFrame.Name = "EmoteWheel"
wheelFrame.Size = UDim2.fromOffset(300, 300)
wheelFrame.Position = UDim2.fromScale(0.5, 0.5)
wheelFrame.AnchorPoint = Vector2.new(0.5, 0.5)
wheelFrame.BackgroundTransparency = 1
wheelFrame.Visible = false
wheelFrame.Parent = gui

-- Center circle (shows selected emote name)
local centerCircle = Instance.new("Frame")
centerCircle.Name = "Center"
centerCircle.Size = UDim2.fromOffset(80, 80)
centerCircle.Position = UDim2.fromScale(0.5, 0.5)
centerCircle.AnchorPoint = Vector2.new(0.5, 0.5)
centerCircle.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
centerCircle.Parent = wheelFrame

local centerCorner = Instance.new("UICorner")
centerCorner.CornerRadius = UDim.new(1, 0)
centerCorner.Parent = centerCircle

local centerLabel = Instance.new("TextLabel")
centerLabel.Size = UDim2.fromScale(1, 1)
centerLabel.BackgroundTransparency = 1
centerLabel.Text = "Emotes"
centerLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
centerLabel.TextSize = 14
centerLabel.Font = Enum.Font.GothamBold
centerLabel.TextWrapped = true
centerLabel.Parent = centerCircle

-- Build wheel slots
local WHEEL_SLOTS = 8
local WHEEL_RADIUS = 120
local slotButtons: { TextButton } = {}
local slotEmoteNames: { string } = {}

-- Assign first 8 default emotes to slots
local slotIndex = 1
for name, emote in EmoteConfig.getAllEmotes() do
    if slotIndex > WHEEL_SLOTS then break end
    slotEmoteNames[slotIndex] = name

    local angle = (slotIndex - 1) * (math.pi * 2 / WHEEL_SLOTS) - math.pi / 2
    local x = math.cos(angle) * WHEEL_RADIUS
    local y = math.sin(angle) * WHEEL_RADIUS

    local btn = Instance.new("TextButton")
    btn.Name = "Slot" .. slotIndex
    btn.Size = UDim2.fromOffset(64, 64)
    btn.Position = UDim2.new(0.5, x - 32, 0.5, y - 32)
    btn.BackgroundColor3 = Color3.fromRGB(50, 50, 70)
    btn.Text = ""
    btn.Parent = wheelFrame

    local btnCorner = Instance.new("UICorner")
    btnCorner.CornerRadius = UDim.new(1, 0)
    btnCorner.Parent = btn

    -- Icon
    local icon = Instance.new("ImageLabel")
    icon.Size = UDim2.new(1, -10, 1, -10)
    icon.Position = UDim2.fromOffset(5, 5)
    icon.BackgroundTransparency = 1
    icon.Image = emote.icon
    icon.ScaleType = Enum.ScaleType.Fit
    icon.Parent = btn

    -- Name label below
    local nameLabel = Instance.new("TextLabel")
    nameLabel.Size = UDim2.new(1, 10, 0, 16)
    nameLabel.Position = UDim2.new(0, -5, 1, 2)
    nameLabel.BackgroundTransparency = 1
    nameLabel.Text = emote.displayName
    nameLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
    nameLabel.TextSize = 11
    nameLabel.Font = Enum.Font.Gotham
    nameLabel.Parent = btn

    local idx = slotIndex
    btn.MouseButton1Click:Connect(function()
        local emoteName = slotEmoteNames[idx]
        if emoteName then
            EmoteRequestRemote:FireServer("Play", emoteName)
            wheelFrame.Visible = false
        end
    end)

    -- Hover effect
    btn.MouseEnter:Connect(function()
        centerLabel.Text = emote.displayName
        TweenService:Create(btn, TweenInfo.new(0.15), {
            BackgroundColor3 = Color3.fromRGB(80, 80, 110),
            Size = UDim2.fromOffset(72, 72),
        }):Play()
    end)

    btn.MouseLeave:Connect(function()
        centerLabel.Text = "Emotes"
        TweenService:Create(btn, TweenInfo.new(0.15), {
            BackgroundColor3 = Color3.fromRGB(50, 50, 70),
            Size = UDim2.fromOffset(64, 64),
        }):Play()
    end)

    slotButtons[slotIndex] = btn
    slotIndex += 1
end

-- Toggle wheel with B key or period key
local isOpen = false

local function toggleWheel()
    isOpen = not isOpen
    wheelFrame.Visible = isOpen
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == Enum.KeyCode.B or input.KeyCode == Enum.KeyCode.Period then
        toggleWheel()
    end
end)

-- Close wheel when clicking outside
UserInputService.InputBegan:Connect(function(input)
    if not isOpen then return end
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        -- Check if click is outside the wheel
        local mousePos = UserInputService:GetMouseLocation()
        local center = wheelFrame.AbsolutePosition + wheelFrame.AbsoluteSize / 2
        local dist = (mousePos - center).Magnitude
        if dist > WHEEL_RADIUS + 50 then
            isOpen = false
            wheelFrame.Visible = false
        end
    end
end)
```

## Key Implementation Notes

1. **Animation IDs**: Replace placeholder `rbxassetid://0` with actual uploaded animation asset IDs. Animations must be owned by the game owner or be public.

2. **Chat commands**: The server listens for `/e <name>` and `/emote <name>` chat messages. Matching is case-insensitive against both internal name and displayName.

3. **Movement cancels emotes**: When the player starts running (speed > 0.5), looping emotes auto-stop. Non-looping emotes with a set duration stop on their own.

4. **Emote ownership**: Default emotes (`isDefault = true`) are granted to all players. Additional emotes can be granted via `grantEmote()` -- integrate with your shop or reward system.

5. **Animation caching**: AnimationTracks are cached per Humanoid to avoid reloading. Cache is cleaned up on CharacterRemoving.

6. **Radial wheel**: 8 emote slots arranged in a circle. Press B or period to toggle. Hover shows emote name in center. Click to play.

7. **Replication**: Emotes are broadcast to all clients via `FireAllClients` so everyone sees the animation.

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

When the user asks for an emote system, ask:
- How many emote slots do you need in the wheel? (default: 8)
- Should emotes be purchasable or all unlocked by default?
- Do you need chat command support (/e dance)?
- Should movement cancel looping emotes?
- Do you need emote categories (dance, greeting, mood)?
- Should emotes be visible to other players (replicated)?
