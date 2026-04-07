---
name: cutscene
description: |
  Cinematic cutscene system for Roblox. Camera waypoints with smooth interpolation,
  character animation sync, dialog display during cutscenes, skip button, letterbox
  bars, fade in/out transitions, and cutscene sequencing.
  시네마틱 컷신 시스템, 카메라 웨이포인트, 캐릭터 애니메이션, 대화, 스킵 버튼, 레터박스, 페이드
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
effort: high
---

# Cinematic Cutscene System

Build a full-featured cutscene system with camera waypoint paths, character animation synchronization, dialog overlays, skip button, letterbox bars, and fade transitions.

## Architecture Overview

```
ServerScriptService/
  CutsceneService.server.lua     -- Triggers cutscenes, syncs multiplayer
ReplicatedStorage/
  CutsceneConfig.lua             -- Cutscene definitions (waypoints, dialog, timing)
  CutsceneShared.lua             -- Shared types
StarterPlayerScripts/
  CutsceneClient.lua             -- Camera control, UI, animation playback
StarterGui/
  CutsceneUI/                    -- Letterbox, dialog, skip button, fade overlay
Workspace/
  CutsceneWaypoints/             -- Folder of Part waypoints per cutscene
```

## Shared Types

```lua
-- ReplicatedStorage/CutsceneShared.lua
local CutsceneShared = {}

export type CameraWaypoint = {
    position: Vector3,
    lookAt: Vector3,            -- point the camera looks at
    duration: number,            -- seconds to travel to this waypoint
    easingStyle: Enum.EasingStyle?,
    easingDirection: Enum.EasingDirection?,
    fov: number?,               -- field of view at this waypoint
    roll: number?,              -- camera roll in degrees
}

export type DialogLine = {
    speaker: string,
    text: string,
    duration: number,            -- how long to show this line
    voiceId: string?,           -- optional voice-over sound ID
    speakerImage: string?,      -- portrait image
}

export type CharacterAction = {
    targetName: string,          -- NPC or player name
    animationId: string?,
    moveTo: Vector3?,
    lookAt: Vector3?,
    timestamp: number,           -- when in the cutscene this happens (seconds)
    duration: number?,
}

export type CutsceneDefinition = {
    name: string,
    waypoints: { CameraWaypoint },
    dialog: { DialogLine }?,
    characterActions: { CharacterAction }?,
    totalDuration: number,
    canSkip: boolean,
    showLetterbox: boolean,
    fadeInDuration: number?,
    fadeOutDuration: number?,
    musicId: string?,
}

return CutsceneShared
```

## Cutscene Config

```lua
-- ReplicatedStorage/CutsceneConfig.lua
local CutsceneShared = require(script.Parent:WaitForChild("CutsceneShared"))

local CutsceneConfig = {}

local cutscenes: { [string]: CutsceneShared.CutsceneDefinition } = {
    Intro = {
        name = "Intro",
        totalDuration = 15,
        canSkip = true,
        showLetterbox = true,
        fadeInDuration = 1,
        fadeOutDuration = 1,
        musicId = "rbxassetid://0",
        waypoints = {
            {
                position = Vector3.new(0, 50, -100),
                lookAt = Vector3.new(0, 0, 0),
                duration = 0, -- starting position, no travel
                fov = 70,
            },
            {
                position = Vector3.new(0, 30, -50),
                lookAt = Vector3.new(0, 5, 0),
                duration = 4,
                easingStyle = Enum.EasingStyle.Sine,
                easingDirection = Enum.EasingDirection.InOut,
                fov = 60,
            },
            {
                position = Vector3.new(20, 15, -20),
                lookAt = Vector3.new(0, 5, 0),
                duration = 4,
                easingStyle = Enum.EasingStyle.Quad,
                easingDirection = Enum.EasingDirection.InOut,
                fov = 50,
            },
            {
                position = Vector3.new(5, 8, -10),
                lookAt = Vector3.new(0, 5, 0),
                duration = 3,
                easingStyle = Enum.EasingStyle.Sine,
                easingDirection = Enum.EasingDirection.Out,
                fov = 45,
            },
        },
        dialog = {
            {
                speaker = "Narrator",
                text = "Welcome to the world of adventure...",
                duration = 4,
                speakerImage = "rbxassetid://0",
            },
            {
                speaker = "Narrator",
                text = "A land where heroes are forged in battle.",
                duration = 4,
            },
            {
                speaker = "Guide",
                text = "Follow me. I'll show you the way.",
                duration = 3,
                speakerImage = "rbxassetid://0",
            },
        },
        characterActions = {
            {
                targetName = "Guide",
                animationId = "rbxassetid://0",
                timestamp = 8,
                duration = 3,
            },
            {
                targetName = "Guide",
                moveTo = Vector3.new(10, 0, 5),
                timestamp = 11,
                duration = 3,
            },
        },
    },
}

function CutsceneConfig.getCutscene(name: string): CutsceneShared.CutsceneDefinition?
    return cutscenes[name]
end

function CutsceneConfig.registerCutscene(name: string, definition: CutsceneShared.CutsceneDefinition)
    cutscenes[name] = definition
end

return CutsceneConfig
```

## Server: CutsceneService

```lua
-- ServerScriptService/CutsceneService.server.lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CutsceneConfig = require(ReplicatedStorage:WaitForChild("CutsceneConfig"))

local CutsceneRemote = Instance.new("RemoteEvent")
CutsceneRemote.Name = "CutsceneRemote"
CutsceneRemote.Parent = ReplicatedStorage

local CutsceneRequestRemote = Instance.new("RemoteEvent")
CutsceneRequestRemote.Name = "CutsceneRequestRemote"
CutsceneRequestRemote.Parent = ReplicatedStorage

-- Track active cutscenes per player
local activeCutscenes: { [Player]: string } = {}

--------------------------------------------------------------------------------
-- Trigger cutscene for a specific player
--------------------------------------------------------------------------------
local function playCutsceneForPlayer(player: Player, cutsceneName: string)
    local definition = CutsceneConfig.getCutscene(cutsceneName)
    if not definition then
        warn("[CutsceneService] Unknown cutscene:", cutsceneName)
        return
    end

    if activeCutscenes[player] then
        -- Already in a cutscene, skip
        return
    end

    activeCutscenes[player] = cutsceneName
    CutsceneRemote:FireClient(player, "Play", cutsceneName)
end

--------------------------------------------------------------------------------
-- Trigger cutscene for all players
--------------------------------------------------------------------------------
local function playCutsceneForAll(cutsceneName: string)
    local definition = CutsceneConfig.getCutscene(cutsceneName)
    if not definition then return end

    for _, player in Players:GetPlayers() do
        if not activeCutscenes[player] then
            activeCutscenes[player] = cutsceneName
        end
    end

    CutsceneRemote:FireAllClients("Play", cutsceneName)
end

--------------------------------------------------------------------------------
-- Handle client requests (skip, complete)
--------------------------------------------------------------------------------
CutsceneRequestRemote.OnServerEvent:Connect(function(player: Player, action: string, cutsceneName: string?)
    if action == "Skip" then
        if activeCutscenes[player] then
            activeCutscenes[player] = nil
            CutsceneRemote:FireClient(player, "Skip")
        end
    elseif action == "Complete" then
        activeCutscenes[player] = nil
        -- Fire completion callback or event
        CutsceneRemote:FireClient(player, "Completed", cutsceneName)
    end
end)

Players.PlayerRemoving:Connect(function(player)
    activeCutscenes[player] = nil
end)

--------------------------------------------------------------------------------
-- Public API (called from other server scripts)
--------------------------------------------------------------------------------
local CutsceneService = {}

function CutsceneService.playForPlayer(player: Player, cutsceneName: string)
    playCutsceneForPlayer(player, cutsceneName)
end

function CutsceneService.playForAll(cutsceneName: string)
    playCutsceneForAll(cutsceneName)
end

function CutsceneService.isPlayerInCutscene(player: Player): boolean
    return activeCutscenes[player] ~= nil
end

-- Expose for require() from other server scripts
return CutsceneService
```

## Client: Cutscene Controller

```lua
-- StarterPlayerScripts/CutsceneClient.lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")

local CutsceneConfig = require(ReplicatedStorage:WaitForChild("CutsceneConfig"))
local CutsceneShared = require(ReplicatedStorage:WaitForChild("CutsceneShared"))

local CutsceneRemote = ReplicatedStorage:WaitForChild("CutsceneRemote")
local CutsceneRequestRemote = ReplicatedStorage:WaitForChild("CutsceneRequestRemote")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- UI references (created below)
local cutsceneGui: ScreenGui
local letterboxTop: Frame
local letterboxBottom: Frame
local fadeOverlay: Frame
local dialogFrame: Frame
local dialogSpeaker: TextLabel
local dialogText: TextLabel
local dialogPortrait: ImageLabel
local skipButton: TextButton

local isPlaying = false
local skipRequested = false

--------------------------------------------------------------------------------
-- Create cutscene UI
--------------------------------------------------------------------------------
local function createUI()
    cutsceneGui = Instance.new("ScreenGui")
    cutsceneGui.Name = "CutsceneUI"
    cutsceneGui.IgnoreGuiInset = true
    cutsceneGui.DisplayOrder = 100
    cutsceneGui.Enabled = false
    cutsceneGui.Parent = player:WaitForChild("PlayerGui")

    -- Letterbox bars
    letterboxTop = Instance.new("Frame")
    letterboxTop.Name = "LetterboxTop"
    letterboxTop.Size = UDim2.new(1, 0, 0, 0)
    letterboxTop.Position = UDim2.new(0, 0, 0, 0)
    letterboxTop.BackgroundColor3 = Color3.new(0, 0, 0)
    letterboxTop.BorderSizePixel = 0
    letterboxTop.ZIndex = 10
    letterboxTop.Parent = cutsceneGui

    letterboxBottom = Instance.new("Frame")
    letterboxBottom.Name = "LetterboxBottom"
    letterboxBottom.Size = UDim2.new(1, 0, 0, 0)
    letterboxBottom.Position = UDim2.new(0, 0, 1, 0)
    letterboxBottom.AnchorPoint = Vector2.new(0, 1)
    letterboxBottom.BackgroundColor3 = Color3.new(0, 0, 0)
    letterboxBottom.BorderSizePixel = 0
    letterboxBottom.ZIndex = 10
    letterboxBottom.Parent = cutsceneGui

    -- Fade overlay
    fadeOverlay = Instance.new("Frame")
    fadeOverlay.Name = "FadeOverlay"
    fadeOverlay.Size = UDim2.fromScale(1, 1)
    fadeOverlay.BackgroundColor3 = Color3.new(0, 0, 0)
    fadeOverlay.BackgroundTransparency = 1
    fadeOverlay.ZIndex = 20
    fadeOverlay.Parent = cutsceneGui

    -- Dialog frame
    dialogFrame = Instance.new("Frame")
    dialogFrame.Name = "DialogFrame"
    dialogFrame.Size = UDim2.new(0.7, 0, 0, 100)
    dialogFrame.Position = UDim2.new(0.15, 0, 1, -130)
    dialogFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
    dialogFrame.BackgroundTransparency = 0.15
    dialogFrame.Visible = false
    dialogFrame.ZIndex = 15
    dialogFrame.Parent = cutsceneGui

    local dialogCorner = Instance.new("UICorner")
    dialogCorner.CornerRadius = UDim.new(0, 10)
    dialogCorner.Parent = dialogFrame

    dialogPortrait = Instance.new("ImageLabel")
    dialogPortrait.Name = "Portrait"
    dialogPortrait.Size = UDim2.fromOffset(70, 70)
    dialogPortrait.Position = UDim2.fromOffset(15, 15)
    dialogPortrait.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
    dialogPortrait.ScaleType = Enum.ScaleType.Fit
    dialogPortrait.ZIndex = 16
    dialogPortrait.Parent = dialogFrame

    local portraitCorner = Instance.new("UICorner")
    portraitCorner.CornerRadius = UDim.new(1, 0)
    portraitCorner.Parent = dialogPortrait

    dialogSpeaker = Instance.new("TextLabel")
    dialogSpeaker.Name = "Speaker"
    dialogSpeaker.Size = UDim2.new(1, -110, 0, 24)
    dialogSpeaker.Position = UDim2.fromOffset(100, 10)
    dialogSpeaker.BackgroundTransparency = 1
    dialogSpeaker.TextColor3 = Color3.fromRGB(255, 220, 100)
    dialogSpeaker.TextSize = 18
    dialogSpeaker.Font = Enum.Font.GothamBold
    dialogSpeaker.TextXAlignment = Enum.TextXAlignment.Left
    dialogSpeaker.ZIndex = 16
    dialogSpeaker.Parent = dialogFrame

    dialogText = Instance.new("TextLabel")
    dialogText.Name = "Text"
    dialogText.Size = UDim2.new(1, -110, 0, 60)
    dialogText.Position = UDim2.fromOffset(100, 35)
    dialogText.BackgroundTransparency = 1
    dialogText.TextColor3 = Color3.fromRGB(220, 220, 220)
    dialogText.TextSize = 16
    dialogText.Font = Enum.Font.Gotham
    dialogText.TextXAlignment = Enum.TextXAlignment.Left
    dialogText.TextYAlignment = Enum.TextYAlignment.Top
    dialogText.TextWrapped = true
    dialogText.ZIndex = 16
    dialogText.Parent = dialogFrame

    -- Skip button
    skipButton = Instance.new("TextButton")
    skipButton.Name = "SkipButton"
    skipButton.Size = UDim2.fromOffset(120, 36)
    skipButton.Position = UDim2.new(1, -140, 0, 20)
    skipButton.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
    skipButton.BackgroundTransparency = 0.3
    skipButton.Text = "Skip >>"
    skipButton.TextColor3 = Color3.fromRGB(200, 200, 200)
    skipButton.TextSize = 16
    skipButton.Font = Enum.Font.GothamBold
    skipButton.Visible = false
    skipButton.ZIndex = 15
    skipButton.Parent = cutsceneGui

    local skipCorner = Instance.new("UICorner")
    skipCorner.CornerRadius = UDim.new(0, 8)
    skipCorner.Parent = skipButton

    skipButton.MouseButton1Click:Connect(function()
        skipRequested = true
    end)
end

createUI()

--------------------------------------------------------------------------------
-- Letterbox animation
--------------------------------------------------------------------------------
local LETTERBOX_HEIGHT = 60

local function showLetterbox()
    TweenService:Create(letterboxTop, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Size = UDim2.new(1, 0, 0, LETTERBOX_HEIGHT),
    }):Play()
    TweenService:Create(letterboxBottom, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Size = UDim2.new(1, 0, 0, LETTERBOX_HEIGHT),
    }):Play()
end

local function hideLetterbox()
    TweenService:Create(letterboxTop, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
        Size = UDim2.new(1, 0, 0, 0),
    }):Play()
    TweenService:Create(letterboxBottom, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
        Size = UDim2.new(1, 0, 0, 0),
    }):Play()
end

--------------------------------------------------------------------------------
-- Fade transitions
--------------------------------------------------------------------------------
local function fadeIn(duration: number)
    fadeOverlay.BackgroundTransparency = 0
    local tween = TweenService:Create(fadeOverlay, TweenInfo.new(duration), {
        BackgroundTransparency = 1,
    })
    tween:Play()
    tween.Completed:Wait()
end

local function fadeOut(duration: number)
    fadeOverlay.BackgroundTransparency = 1
    local tween = TweenService:Create(fadeOverlay, TweenInfo.new(duration), {
        BackgroundTransparency = 0,
    })
    tween:Play()
    tween.Completed:Wait()
end

--------------------------------------------------------------------------------
-- Typewriter text effect
--------------------------------------------------------------------------------
local function typewriterText(label: TextLabel, fullText: string, charsPerSecond: number?)
    local speed = charsPerSecond or 30
    label.Text = ""
    for i = 1, #fullText do
        if skipRequested then
            label.Text = fullText
            return
        end
        label.Text = string.sub(fullText, 1, i)
        task.wait(1 / speed)
    end
end

--------------------------------------------------------------------------------
-- Dialog display
--------------------------------------------------------------------------------
local function showDialog(line: CutsceneShared.DialogLine)
    dialogFrame.Visible = true
    dialogSpeaker.Text = line.speaker
    dialogPortrait.Image = line.speakerImage or ""
    dialogPortrait.Visible = line.speakerImage ~= nil

    -- Play voice-over if available
    if line.voiceId then
        local sound = Instance.new("Sound")
        sound.SoundId = line.voiceId
        sound.Volume = 1
        sound.Parent = SoundService
        sound:Play()
        sound.Ended:Connect(function()
            sound:Destroy()
        end)
    end

    typewriterText(dialogText, line.text)
end

local function hideDialog()
    dialogFrame.Visible = false
end

--------------------------------------------------------------------------------
-- Camera interpolation between waypoints
--------------------------------------------------------------------------------
local function interpolateCamera(from: CutsceneShared.CameraWaypoint, to: CutsceneShared.CameraWaypoint)
    local duration = to.duration
    if duration <= 0 then
        camera.CFrame = CFrame.lookAt(to.position, to.lookAt)
        if to.fov then camera.FieldOfView = to.fov end
        return
    end

    local style = to.easingStyle or Enum.EasingStyle.Linear
    local direction = to.easingDirection or Enum.EasingDirection.InOut

    local startCF = CFrame.lookAt(from.position, from.lookAt)
    local endCF = CFrame.lookAt(to.position, to.lookAt)
    local startFOV = from.fov or 70
    local endFOV = to.fov or 70

    local elapsed = 0
    local connection
    connection = RunService.RenderStepped:Connect(function(dt)
        if skipRequested then
            connection:Disconnect()
            camera.CFrame = endCF
            camera.FieldOfView = endFOV
            return
        end

        elapsed += dt
        local alpha = math.clamp(elapsed / duration, 0, 1)
        -- Apply easing
        local easedAlpha = TweenService:GetValue(alpha, style, direction)

        camera.CFrame = startCF:Lerp(endCF, easedAlpha)
        camera.FieldOfView = startFOV + (endFOV - startFOV) * easedAlpha

        if alpha >= 1 then
            connection:Disconnect()
        end
    end)

    -- Wait for this segment to finish
    local waitTime = 0
    while waitTime < duration and not skipRequested do
        task.wait()
        waitTime += task.wait()
    end
end

--------------------------------------------------------------------------------
-- Execute character actions at their timestamps
--------------------------------------------------------------------------------
local function scheduleCharacterActions(actions: { CutsceneShared.CharacterAction }?)
    if not actions then return end

    for _, action in actions do
        task.delay(action.timestamp, function()
            if not isPlaying then return end

            -- Find target character/NPC
            local target = workspace:FindFirstChild(action.targetName)
            if not target then
                -- Try as player name
                local targetPlayer = Players:FindFirstChild(action.targetName)
                if targetPlayer then
                    target = targetPlayer.Character
                end
            end
            if not target then return end

            local humanoid = target:FindFirstChildWhichIsA("Humanoid")

            -- Play animation
            if action.animationId and humanoid then
                local animator = humanoid:FindFirstChildWhichIsA("Animator")
                if animator then
                    local anim = Instance.new("Animation")
                    anim.AnimationId = action.animationId
                    local ok, track = pcall(function()
                        return animator:LoadAnimation(anim)
                    end)
                    if ok and track then
                        track:Play()
                        if action.duration then
                            task.delay(action.duration, function()
                                track:Stop()
                            end)
                        end
                    end
                end
            end

            -- Move to position
            if action.moveTo and humanoid then
                humanoid:MoveTo(action.moveTo)
            end

            -- Look at position
            if action.lookAt then
                local rootPart = target:FindFirstChild("HumanoidRootPart")
                    or target:FindFirstChild("PrimaryPart")
                if rootPart then
                    rootPart.CFrame = CFrame.lookAt(rootPart.Position, action.lookAt)
                end
            end
        end)
    end
end

--------------------------------------------------------------------------------
-- Main cutscene playback
--------------------------------------------------------------------------------
local function playCutscene(cutsceneName: string)
    local definition = CutsceneConfig.getCutscene(cutsceneName)
    if not definition then return end

    isPlaying = true
    skipRequested = false
    cutsceneGui.Enabled = true

    -- Take over camera
    camera.CameraType = Enum.CameraType.Scriptable

    -- Show skip button if allowed
    skipButton.Visible = definition.canSkip

    -- Fade in
    if definition.fadeInDuration and definition.fadeInDuration > 0 then
        fadeOverlay.BackgroundTransparency = 0
        fadeIn(definition.fadeInDuration)
    end

    -- Show letterbox
    if definition.showLetterbox then
        showLetterbox()
    end

    -- Play music
    local music: Sound? = nil
    if definition.musicId then
        music = Instance.new("Sound")
        music.SoundId = definition.musicId
        music.Volume = 0.5
        music.Parent = SoundService
        music:Play()
    end

    -- Schedule character actions
    scheduleCharacterActions(definition.characterActions)

    -- Schedule dialog
    if definition.dialog then
        local dialogTime = 0
        for _, line in definition.dialog do
            task.delay(dialogTime, function()
                if isPlaying and not skipRequested then
                    showDialog(line)
                end
            end)
            dialogTime += line.duration
        end
        task.delay(dialogTime, function()
            hideDialog()
        end)
    end

    -- Play camera waypoints
    local waypoints = definition.waypoints
    if #waypoints > 0 then
        -- Set initial position
        local first = waypoints[1]
        camera.CFrame = CFrame.lookAt(first.position, first.lookAt)
        if first.fov then camera.FieldOfView = first.fov end

        -- Interpolate through remaining waypoints
        for i = 2, #waypoints do
            if skipRequested then break end
            interpolateCamera(waypoints[i - 1], waypoints[i])
        end
    end

    -- Wait for remaining duration if camera finished early
    if not skipRequested then
        -- Small wait to ensure everything completes
        task.wait(0.5)
    end

    -- Fade out
    if definition.fadeOutDuration and definition.fadeOutDuration > 0 and not skipRequested then
        fadeOut(definition.fadeOutDuration)
    end

    -- Clean up
    isPlaying = false
    hideDialog()
    hideLetterbox()
    skipButton.Visible = false
    cutsceneGui.Enabled = false

    -- Restore camera
    camera.CameraType = Enum.CameraType.Custom
    camera.FieldOfView = 70

    -- Stop music
    if music then
        TweenService:Create(music, TweenInfo.new(0.5), { Volume = 0 }):Play()
        task.delay(0.6, function()
            music:Destroy()
        end)
    end

    -- Reset fade
    fadeOverlay.BackgroundTransparency = 1

    -- Notify server
    CutsceneRequestRemote:FireServer("Complete", cutsceneName)
end

--------------------------------------------------------------------------------
-- Handle skip via keyboard
--------------------------------------------------------------------------------
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if not isPlaying then return end
    if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.Return then
        skipRequested = true
    end
end)

--------------------------------------------------------------------------------
-- Handle server events
--------------------------------------------------------------------------------
CutsceneRemote.OnClientEvent:Connect(function(action: string, ...)
    if action == "Play" then
        local cutsceneName = ...
        playCutscene(cutsceneName)
    elseif action == "Skip" then
        skipRequested = true
    end
end)
```

## Key Implementation Notes

1. **Camera waypoints**: Define a sequence of `CameraWaypoint` objects. The camera smoothly interpolates between them using configurable easing styles.

2. **Letterbox bars**: Animated black bars at top and bottom create a cinematic feel. Height is configurable via `LETTERBOX_HEIGHT`.

3. **Dialog system**: Typewriter text effect with speaker name, portrait image, and optional voice-over audio. Dialog lines are scheduled based on cumulative duration.

4. **Skip support**: Press Escape, Enter, or click the Skip button. The `skipRequested` flag short-circuits all animations and transitions.

5. **Fade transitions**: Configurable fade-in and fade-out durations. A black overlay frame animates its transparency.

6. **Character actions**: NPCs and players can be animated and moved during the cutscene on a timeline. Actions are scheduled via `task.delay`.

7. **Camera restoration**: After the cutscene, camera type reverts to `Custom` and FOV resets to 70.

8. **Multiplayer**: Server can trigger cutscenes for individual players or all players simultaneously.

## Waypoint Setup in Studio

Create waypoint parts in Workspace under a folder matching your cutscene name:

```
Workspace/
  CutsceneWaypoints/
    Intro/
      WP1 (Part at position 1, look-at encoded in Orientation)
      WP2
      WP3
```

Or define waypoints directly in `CutsceneConfig.lua` with `Vector3` coordinates.

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

When the user asks for a cutscene system, ask:
- How many cutscenes do you need? Describe each briefly.
- Should cutscenes be skippable?
- Do you need dialog/subtitles during cutscenes?
- Should NPCs animate or move during the cutscene?
- Do you need voice-over audio support?
- Should the cutscene play for one player or all players simultaneously?
- Do you want fade and letterbox effects?
