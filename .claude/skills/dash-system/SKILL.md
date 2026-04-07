---
name: dash-system
description: |
  Dash system for Roblox: directional dash, cooldown, invincibility frames (i-frames),
  VFX trail during dash, camera FOV punch effect. Use when the user asks about dashing,
  dodge, dodge roll, i-frames, invincibility frames, dash cooldown, movement ability,
  FOV effect, speed boost, quick movement, or directional dodge.
  대시, 회피, 무적 프레임, 쿨다운, FOV, 이동 능력, 순간이동.
  Triggers on: dash, dodge, roll, i-frame, invincibility frame, cooldown, FOV punch,
  dash trail, speed dash, directional dash, movement ability, evade.
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
effort: high
---

# Dash System Skill

Complete directional dash system with cooldowns, invincibility frames, visual trails,
and camera FOV punch. Client-predicted with server validation.

---

## 1. Dash Controller (Client Script)

```luau
--!strict
-- StarterPlayerScripts/DashController.client.lua
-- Handles dash input, direction, VFX, and camera effects.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- Configuration
local DASH_KEY = Enum.KeyCode.Q
local DASH_DISTANCE = 30           -- studs
local DASH_DURATION = 0.2          -- seconds
local DASH_COOLDOWN = 1.5          -- seconds
local IFRAMES_DURATION = 0.25      -- seconds of invincibility
local FOV_PUNCH_AMOUNT = 15        -- additional FOV degrees
local FOV_PUNCH_DURATION = 0.15    -- seconds for FOV increase
local FOV_RECOVER_DURATION = 0.3   -- seconds for FOV to return
local TRAIL_DURATION = 0.3         -- seconds trail persists
local TRAIL_COLOR = Color3.fromRGB(100, 180, 255)
local DASH_SOUND_ID = ""           -- optional sound asset ID

-- State
local lastDashTime = 0
local isDashing = false
local baseFOV = 70

-- Remote for server validation
local dashRemote = ReplicatedStorage:WaitForChild("DashRemote", 10) :: RemoteEvent?

-- Get movement direction from input
local function getMovementDirection(): Vector3
    local humanoid = player.Character and player.Character:FindFirstChildWhichIsA("Humanoid")
    if not humanoid then return Vector3.zero end

    local moveDir = humanoid.MoveDirection
    if moveDir.Magnitude < 0.1 then
        -- If not moving, dash forward (camera look direction)
        local camCF = camera.CFrame
        local forward = camCF.LookVector
        moveDir = Vector3.new(forward.X, 0, forward.Z).Unit
    end

    return moveDir.Unit
end

-- Create afterimage ghost effect
local function createAfterimage(character: Model)
    for _, part in character:GetDescendants() do
        if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
            local ghost = Instance.new("Part")
            ghost.Size = part.Size
            ghost.CFrame = part.CFrame
            ghost.Anchored = true
            ghost.CanCollide = false
            ghost.CanQuery = false
            ghost.CanTouch = false
            ghost.Material = Enum.Material.Neon
            ghost.Color = TRAIL_COLOR
            ghost.Transparency = 0.5
            ghost.Parent = workspace

            -- Fade out
            TweenService:Create(
                ghost,
                TweenInfo.new(TRAIL_DURATION, Enum.EasingStyle.Linear),
                { Transparency = 1 }
            ):Play()

            Debris:AddItem(ghost, TRAIL_DURATION + 0.1)
        end
    end
end

-- Apply trail attachment to character during dash
local function createDashTrail(character: Model): { Trail }
    local trails: { Trail } = {}
    local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
    if not rootPart then return trails end

    -- Create trail on the torso area
    local partsToTrail = { "UpperTorso", "LowerTorso", "Head" }
    for _, partName in partsToTrail do
        local part = character:FindFirstChild(partName) :: BasePart?
        if not part then continue end

        local att0 = Instance.new("Attachment")
        att0.Name = "DashTrailAtt0"
        att0.Position = Vector3.new(0, part.Size.Y / 2, 0)
        att0.Parent = part

        local att1 = Instance.new("Attachment")
        att1.Name = "DashTrailAtt1"
        att1.Position = Vector3.new(0, -part.Size.Y / 2, 0)
        att1.Parent = part

        local trail = Instance.new("Trail")
        trail.Attachment0 = att0
        trail.Attachment1 = att1
        trail.Color = ColorSequence.new(TRAIL_COLOR, TRAIL_COLOR)
        trail.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.3),
            NumberSequenceKeypoint.new(1, 1),
        })
        trail.Lifetime = TRAIL_DURATION
        trail.LightEmission = 0.8
        trail.WidthScale = NumberSequence.new(1)
        trail.MinLength = 0.05
        trail.Parent = part

        table.insert(trails, trail)
    end

    return trails
end

local function cleanupTrails(character: Model, trails: { Trail })
    -- Remove trail objects and attachments
    task.delay(TRAIL_DURATION + 0.1, function()
        for _, trail in trails do
            if trail.Parent then
                local att0 = trail.Attachment0
                local att1 = trail.Attachment1
                trail:Destroy()
                if att0 then att0:Destroy() end
                if att1 then att1:Destroy() end
            end
        end
    end)
end

-- Camera FOV punch effect
local function fovPunch()
    baseFOV = camera.FieldOfView

    -- Punch out
    TweenService:Create(
        camera,
        TweenInfo.new(FOV_PUNCH_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { FieldOfView = baseFOV + FOV_PUNCH_AMOUNT }
    ):Play()

    -- Recover
    task.delay(FOV_PUNCH_DURATION, function()
        TweenService:Create(
            camera,
            TweenInfo.new(FOV_RECOVER_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
            { FieldOfView = baseFOV }
        ):Play()
    end)
end

-- Execute dash
local function performDash()
    local character = player.Character
    if not character then return end

    local humanoid = character:FindFirstChildWhichIsA("Humanoid")
    local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
    if not humanoid or not rootPart or humanoid.Health <= 0 then return end

    -- Cooldown check
    local now = tick()
    if now - lastDashTime < DASH_COOLDOWN then return end
    if isDashing then return end

    lastDashTime = now
    isDashing = true

    local direction = getMovementDirection()
    local startPos = rootPart.Position
    local endPos = startPos + direction * DASH_DISTANCE

    -- Raycast to prevent dashing through walls
    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    rayParams.FilterDescendantsInstances = { character }

    local ray = workspace:Raycast(startPos, direction * DASH_DISTANCE, rayParams)
    if ray then
        endPos = ray.Position - direction * 2 -- stop short of wall
    end

    -- Notify server
    if dashRemote then
        dashRemote:FireServer(direction)
    end

    -- VFX: trail
    local trails = createDashTrail(character)

    -- VFX: FOV punch
    fovPunch()

    -- VFX: play sound
    if DASH_SOUND_ID ~= "" then
        local sound = Instance.new("Sound")
        sound.SoundId = DASH_SOUND_ID
        sound.Volume = 0.5
        sound.Parent = rootPart
        sound:Play()
        Debris:AddItem(sound, 2)
    end

    -- Execute dash movement using LinearVelocity
    local attachment = Instance.new("Attachment")
    attachment.Parent = rootPart

    local linearVelocity = Instance.new("LinearVelocity")
    linearVelocity.Attachment0 = attachment
    linearVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
    linearVelocity.MaxForce = math.huge
    linearVelocity.VectorVelocity = direction * (DASH_DISTANCE / DASH_DURATION)
    linearVelocity.Parent = rootPart

    -- Afterimage trail during dash
    local afterimageCount = 3
    for i = 1, afterimageCount do
        task.delay(DASH_DURATION * (i / afterimageCount), function()
            if character.Parent then
                createAfterimage(character)
            end
        end)
    end

    -- End dash
    task.delay(DASH_DURATION, function()
        linearVelocity:Destroy()
        attachment:Destroy()
        isDashing = false
        cleanupTrails(character, trails)
    end)
end

-- Input handling
UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
    if gameProcessed then return end
    if input.KeyCode == DASH_KEY then
        performDash()
    end
end)

-- Mobile support: double-tap to dash
local lastTapTime = 0
UserInputService.TouchTapInWorld:Connect(function()
    local now = tick()
    if now - lastTapTime < 0.3 then
        performDash()
    end
    lastTapTime = now
end)
```

---

## 2. Dash Server Handler (Server Script)

```luau
--!strict
-- ServerScriptService/DashServer.server.lua
-- Server-side validation and i-frame management for dashes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Create remote
local dashRemote = Instance.new("RemoteEvent")
dashRemote.Name = "DashRemote"
dashRemote.Parent = ReplicatedStorage

-- Configuration (must match client)
local DASH_COOLDOWN = 1.5
local IFRAMES_DURATION = 0.25

-- Per-player state
local playerCooldowns: { [Player]: number } = {}

-- Apply invincibility frames
local function applyIFrames(character: Model)
    -- Store original collision states
    local originalCollision: { [BasePart]: boolean } = {}
    for _, part in character:GetDescendants() do
        if part:IsA("BasePart") then
            originalCollision[part] = part.CanCollide
        end
    end

    -- Make character temporarily invincible
    character:SetAttribute("IFrames", true)

    -- ForceField for visual indicator (optional, subtle)
    local forceField = Instance.new("ForceField")
    forceField.Visible = false  -- set to true for visible shield
    forceField.Parent = character

    -- Remove i-frames after duration
    task.delay(IFRAMES_DURATION, function()
        character:SetAttribute("IFrames", false)
        if forceField.Parent then
            forceField:Destroy()
        end
    end)
end

dashRemote.OnServerEvent:Connect(function(player: Player, direction: Vector3)
    -- Validate
    if typeof(direction) ~= "Vector3" then return end
    if direction.Magnitude < 0.1 or direction.Magnitude > 2 then return end

    -- Cooldown check
    local now = tick()
    local lastDash = playerCooldowns[player]
    if lastDash and now - lastDash < DASH_COOLDOWN * 0.9 then -- small tolerance
        return
    end
    playerCooldowns[player] = now

    local character = player.Character
    if not character then return end

    local humanoid = character:FindFirstChildWhichIsA("Humanoid")
    if not humanoid or humanoid.Health <= 0 then return end

    -- Apply i-frames
    applyIFrames(character)
end)

-- Check i-frames before applying damage (hook into your damage system)
-- Example: in your damage module, check character:GetAttribute("IFrames") == true

-- Cleanup
Players.PlayerRemoving:Connect(function(player: Player)
    playerCooldowns[player] = nil
end)
```

---

## 3. Dash Cooldown UI (Client)

```luau
--!strict
-- StarterPlayerScripts/DashCooldownUI.client.lua
-- Shows dash cooldown indicator on screen.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local DASH_COOLDOWN = 1.5

-- Create UI
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "DashCooldownUI"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

local container = Instance.new("Frame")
container.Name = "DashIcon"
container.Size = UDim2.fromOffset(50, 50)
container.Position = UDim2.new(0.5, -25, 1, -160)
container.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
container.BackgroundTransparency = 0.3
container.Parent = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0.5, 0)  -- circle
corner.Parent = container

local label = Instance.new("TextLabel")
label.Name = "KeyLabel"
label.Size = UDim2.fromScale(1, 1)
label.BackgroundTransparency = 1
label.TextColor3 = Color3.fromRGB(255, 255, 255)
label.TextScaled = true
label.Font = Enum.Font.GothamBold
label.Text = "Q"
label.Parent = container

-- Cooldown overlay (fills from bottom to top)
local cooldownOverlay = Instance.new("Frame")
cooldownOverlay.Name = "CooldownOverlay"
cooldownOverlay.Size = UDim2.fromScale(1, 0)  -- 0 = ready, 1 = on cooldown
cooldownOverlay.Position = UDim2.fromScale(0, 1)
cooldownOverlay.AnchorPoint = Vector2.new(0, 1)
cooldownOverlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
cooldownOverlay.BackgroundTransparency = 0.4
cooldownOverlay.ZIndex = 2
cooldownOverlay.Parent = container

local overlayCorner = Instance.new("UICorner")
overlayCorner.CornerRadius = UDim.new(0.5, 0)
overlayCorner.Parent = cooldownOverlay

-- Track cooldown state
local lastDashTime = 0

-- Listen for dash attribute on the local character to sync timing
local function onDash()
    lastDashTime = tick()
    cooldownOverlay.Size = UDim2.fromScale(1, 1)

    -- Flash effect
    TweenService:Create(
        container,
        TweenInfo.new(0.1, Enum.EasingStyle.Quad),
        { BackgroundColor3 = Color3.fromRGB(100, 180, 255) }
    ):Play()

    task.delay(0.1, function()
        TweenService:Create(
            container,
            TweenInfo.new(0.3, Enum.EasingStyle.Quad),
            { BackgroundColor3 = Color3.fromRGB(40, 40, 40) }
        ):Play()
    end)
end

RunService.RenderStepped:Connect(function()
    local elapsed = tick() - lastDashTime
    local progress = math.clamp(elapsed / DASH_COOLDOWN, 0, 1)
    cooldownOverlay.Size = UDim2.fromScale(1, 1 - progress)

    -- Change text color based on ready state
    label.TextColor3 = if progress >= 1
        then Color3.fromRGB(100, 255, 100)
        else Color3.fromRGB(180, 180, 180)
end)

-- Export function for DashController to call
return { onDash = onDash }
```

---

## Guidelines

- **Client predicts dash movement** for responsive feel; server validates cooldown and applies i-frames.
- **LinearVelocity** is preferred over BodyVelocity for dash movement (BodyVelocity is deprecated).
- **Raycast before dash** to prevent clipping through walls.
- **I-frames** should be checked in your damage system: `if character:GetAttribute("IFrames") then return end`.
- **Afterimage ghosts** are anchored copies of body parts that fade out. Keep them lightweight.
- **FOV punch** creates a sense of speed. Tween out quickly, recover smoothly.
- **Trail attachments** should be cleaned up after dash ends (with slight delay for trail to fade).
- Mobile support: use double-tap detection for touch devices.

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

When generating dash code, adapt to these user-specified parameters:

- `$DASH_KEY` - Input key for dash (default: "Q")
- `$DASH_DISTANCE` - Distance in studs (default: 30)
- `$DASH_DURATION` - Seconds the dash movement takes (default: 0.2)
- `$DASH_COOLDOWN` - Seconds between dashes (default: 1.5)
- `$IFRAMES` - Whether to include invincibility frames (default: true)
- `$IFRAMES_DURATION` - Seconds of invincibility (default: 0.25)
- `$FOV_PUNCH` - Whether to include FOV camera effect (default: true)
- `$FOV_AMOUNT` - Extra FOV degrees during dash (default: 15)
- `$TRAIL_ENABLED` - Whether to show trail VFX (default: true)
- `$TRAIL_COLOR` - Trail color as RGB (default: "100,180,255")
- `$AFTERIMAGES` - Whether to show afterimage ghosts (default: true)
- `$AFTERIMAGE_COUNT` - Number of afterimage ghosts (default: 3)
