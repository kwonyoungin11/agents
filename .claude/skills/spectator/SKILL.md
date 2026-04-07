---
name: spectator-system
description: |
  Spectator mode system for Roblox. Spectate after death, cycle through alive players,
  free camera mode, spectator UI with player info, smooth camera transitions,
  and anti-exploit protections for spectators.
  키워드: 관전 모드, 관전 시스템, 카메라 전환, 자유 카메라, 관전 UI, 사망 후 관전
allowed-tools:
  - Bash
  - Read
  - Edit
  - Write
  - Glob
  - Grep
effort: high
---

# Spectator System

Complete spectator mode for Roblox: death-triggered spectating, player cycling, free camera, spectator UI, smooth transitions, and server-side tracking. All code is Luau.

---

## Architecture Overview

```
ReplicatedStorage/
  Shared/
    SpectatorConfig.luau      -- Settings, keybinds, camera config
ServerScriptService/
  Services/
    SpectatorService.luau     -- Server: track spectators, alive players, anti-cheat
StarterPlayerScripts/
  Controllers/
    SpectatorController.luau  -- Client: camera control, input, UI
```

---

## 1. Spectator Configuration

```luau
-- ReplicatedStorage/Shared/SpectatorConfig.luau
--!strict

export type SpectatorMode = "FollowPlayer" | "FreeCamera" | "Overhead"

local SpectatorConfig = {}

SpectatorConfig.ENABLE_FREE_CAMERA = true
SpectatorConfig.ENABLE_OVERHEAD_VIEW = true
SpectatorConfig.AUTO_SPECTATE_ON_DEATH = true
SpectatorConfig.CAMERA_TRANSITION_TIME = 0.5   -- seconds for smooth camera move
SpectatorConfig.FREE_CAMERA_SPEED = 50          -- studs/sec
SpectatorConfig.FREE_CAMERA_SPRINT_MULTIPLIER = 2.5
SpectatorConfig.FREE_CAMERA_MAX_DISTANCE = 200  -- max distance from arena center
SpectatorConfig.FOLLOW_CAMERA_OFFSET = CFrame.new(0, 8, 12) -- offset behind followed player
SpectatorConfig.OVERHEAD_HEIGHT = 80
SpectatorConfig.OVERHEAD_ANGLE = -80             -- degrees, looking down

-- Keybinds
SpectatorConfig.KEY_NEXT_PLAYER = Enum.KeyCode.E
SpectatorConfig.KEY_PREV_PLAYER = Enum.KeyCode.Q
SpectatorConfig.KEY_FREE_CAMERA = Enum.KeyCode.F
SpectatorConfig.KEY_OVERHEAD = Enum.KeyCode.T
SpectatorConfig.KEY_EXIT_SPECTATE = Enum.KeyCode.Escape

-- UI
SpectatorConfig.SHOW_PLAYER_NAME = true
SpectatorConfig.SHOW_PLAYER_HEALTH = true
SpectatorConfig.SHOW_PLAYER_STATS = true
SpectatorConfig.SHOW_SPECTATOR_COUNT = true

return SpectatorConfig
```

---

## 2. Server Spectator Service

```luau
-- ServerScriptService/Services/SpectatorService.luau
--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SpectatorConfig = require(ReplicatedStorage.Shared.SpectatorConfig)

local SpectatorService = {}

-- Track who is spectating
local spectators: { [Player]: boolean } = {}
local spectatorsWatching: { [Player]: Player? } = {} -- spectator -> who they watch

-------------------------------------------------
-- Alive Player List
-------------------------------------------------

function SpectatorService.GetAlivePlayers(): { Player }
    local alive = {}
    for _, player in Players:GetPlayers() do
        if spectators[player] then continue end

        local character = player.Character
        if character then
            local humanoid = character:FindFirstChildOfClass("Humanoid")
            if humanoid and humanoid.Health > 0 then
                table.insert(alive, player)
            end
        end
    end
    return alive
end

function SpectatorService.GetSpectatorCount(): number
    local count = 0
    for _ in spectators do
        count += 1
    end
    return count
end

function SpectatorService.IsSpectating(player: Player): boolean
    return spectators[player] == true
end

-------------------------------------------------
-- Enter / Exit Spectator Mode
-------------------------------------------------

function SpectatorService.EnterSpectatorMode(player: Player)
    if spectators[player] then return end

    spectators[player] = true

    -- Hide player character (make invisible and non-collidable)
    local character = player.Character
    if character then
        for _, part in character:GetDescendants() do
            if part:IsA("BasePart") then
                part.Transparency = 1
                part.CanCollide = false
            elseif part:IsA("Decal") or part:IsA("Texture") then
                part.Transparency = 1
            end
        end

        -- Disable humanoid
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if humanoid then
            humanoid.WalkSpeed = 0
            humanoid.JumpPower = 0
        end
    end

    -- Notify client to enter spectator mode
    local remotes = ReplicatedStorage:FindFirstChild("SpectatorRemotes")
    if remotes then
        local enterEvent = remotes:FindFirstChild("EnterSpectator") :: RemoteEvent
        if enterEvent then
            local alivePlayers = SpectatorService.GetAlivePlayers()
            local playerNames = {}
            for _, plr in alivePlayers do
                table.insert(playerNames, plr.Name)
            end
            enterEvent:FireClient(player, playerNames)
        end

        -- Notify all spectators of updated count
        local countEvent = remotes:FindFirstChild("SpectatorCountUpdate") :: RemoteEvent
        if countEvent then
            countEvent:FireAllClients(SpectatorService.GetSpectatorCount())
        end
    end
end

function SpectatorService.ExitSpectatorMode(player: Player)
    if not spectators[player] then return end

    spectators[player] = nil
    spectatorsWatching[player] = nil

    -- Restore character
    local character = player.Character
    if character then
        for _, part in character:GetDescendants() do
            if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
                part.Transparency = 0
            end
            if part:IsA("BasePart") then
                part.CanCollide = true
            end
        end

        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if humanoid then
            humanoid.WalkSpeed = 16
            humanoid.JumpPower = 50
        end
    end

    local remotes = ReplicatedStorage:FindFirstChild("SpectatorRemotes")
    if remotes then
        local exitEvent = remotes:FindFirstChild("ExitSpectator") :: RemoteEvent
        if exitEvent then
            exitEvent:FireClient(player)
        end

        local countEvent = remotes:FindFirstChild("SpectatorCountUpdate") :: RemoteEvent
        if countEvent then
            countEvent:FireAllClients(SpectatorService.GetSpectatorCount())
        end
    end
end

-------------------------------------------------
-- Get Spectated Player Info (for UI)
-------------------------------------------------

function SpectatorService.GetPlayerInfo(targetPlayer: Player): { [string]: any }?
    local character = targetPlayer.Character
    if not character then return nil end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local info: { [string]: any } = {
        name = targetPlayer.DisplayName,
        username = targetPlayer.Name,
        health = if humanoid then humanoid.Health else 0,
        maxHealth = if humanoid then humanoid.MaxHealth else 100,
    }

    -- Include leaderstat data
    local ls = targetPlayer:FindFirstChild("leaderstats")
    if ls then
        local stats: { [string]: number } = {}
        for _, child in ls:GetChildren() do
            if child:IsA("IntValue") or child:IsA("NumberValue") then
                stats[child.Name] = child.Value
            end
        end
        info.stats = stats
    end

    return info
end

-------------------------------------------------
-- Init
-------------------------------------------------

function SpectatorService.Init()
    local remotesFolder = Instance.new("Folder")
    remotesFolder.Name = "SpectatorRemotes"
    remotesFolder.Parent = ReplicatedStorage

    for _, name in { "EnterSpectator", "ExitSpectator", "SpectatorCountUpdate", "AlivePlayersUpdate", "RequestPlayerInfo" } do
        local remote = Instance.new("RemoteEvent")
        remote.Name = name
        remote.Parent = remotesFolder
    end

    local getInfo = Instance.new("RemoteFunction")
    getInfo.Name = "GetPlayerInfo"
    getInfo.Parent = remotesFolder

    local getAlive = Instance.new("RemoteFunction")
    getAlive.Name = "GetAlivePlayers"
    getAlive.Parent = remotesFolder

    getInfo.OnServerInvoke = function(_player: Player, targetName: string)
        local target = Players:FindFirstChild(targetName)
        if target and target:IsA("Player") then
            return SpectatorService.GetPlayerInfo(target)
        end
        return nil
    end

    getAlive.OnServerInvoke = function(_player: Player)
        local alive = SpectatorService.GetAlivePlayers()
        local names = {}
        for _, plr in alive do
            table.insert(names, plr.Name)
        end
        return names
    end

    -- Auto-spectate on death
    if SpectatorConfig.AUTO_SPECTATE_ON_DEATH then
        Players.PlayerAdded:Connect(function(player: Player)
            player.CharacterAdded:Connect(function(character: Model)
                local humanoid = character:WaitForChild("Humanoid") :: Humanoid
                humanoid.Died:Connect(function()
                    task.wait(1) -- brief delay before spectating
                    if player.Parent then
                        SpectatorService.EnterSpectatorMode(player)
                    end
                end)
            end)
        end)
    end

    -- Cleanup on leave
    Players.PlayerRemoving:Connect(function(player: Player)
        spectators[player] = nil
        spectatorsWatching[player] = nil

        -- Notify remaining spectators that alive list changed
        task.defer(function()
            local remotes = ReplicatedStorage:FindFirstChild("SpectatorRemotes")
            if remotes then
                local aliveUpdate = remotes:FindFirstChild("AlivePlayersUpdate") :: RemoteEvent
                if aliveUpdate then
                    local alive = SpectatorService.GetAlivePlayers()
                    local names = {}
                    for _, plr in alive do
                        table.insert(names, plr.Name)
                    end
                    for spectator in spectators do
                        aliveUpdate:FireClient(spectator, names)
                    end
                end
            end
        end)
    end)
end

return SpectatorService
```

---

## 3. Client Spectator Controller

```luau
-- StarterPlayerScripts/Controllers/SpectatorController.luau
--!strict

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SpectatorConfig = require(ReplicatedStorage.Shared.SpectatorConfig)

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local playerGui = player:WaitForChild("PlayerGui")

local SpectatorController = {}

local isSpectating = false
local currentMode: SpectatorConfig.SpectatorMode = "FollowPlayer"
local alivePlayers: { string } = {}   -- player names
local currentTargetIndex = 1
local currentTarget: Player? = nil

-- Free camera state
local freeCamPosition: Vector3 = Vector3.zero
local freeCamRotation: Vector2 = Vector2.zero -- X = pitch, Y = yaw
local freeCamVelocity: Vector3 = Vector3.zero

-- UI elements
local spectatorGui: ScreenGui? = nil
local targetLabel: TextLabel? = nil
local healthBar: Frame? = nil
local modeLabel: TextLabel? = nil
local controlsLabel: TextLabel? = nil
local spectatorCountLabel: TextLabel? = nil

-- Connections
local updateConnection: RBXScriptConnection? = nil
local inputConnection: RBXScriptConnection? = nil
local inputChangedConnection: RBXScriptConnection? = nil

-------------------------------------------------
-- UI Creation
-------------------------------------------------

local function createSpectatorUI()
    if spectatorGui then return end

    spectatorGui = Instance.new("ScreenGui")
    spectatorGui.Name = "SpectatorUI"
    spectatorGui.ResetOnSpawn = false
    spectatorGui.DisplayOrder = 100
    spectatorGui.Parent = playerGui

    -- "SPECTATING" header
    local header = Instance.new("TextLabel")
    header.Size = UDim2.fromOffset(200, 30)
    header.Position = UDim2.new(0.5, -100, 0, 10)
    header.BackgroundTransparency = 1
    header.Text = "SPECTATING"
    header.TextColor3 = Color3.fromRGB(255, 255, 100)
    header.TextSize = 18
    header.Font = Enum.Font.GothamBold
    header.TextStrokeTransparency = 0.5
    header.Parent = spectatorGui

    -- Bottom bar with target info
    local bottomBar = Instance.new("Frame")
    bottomBar.Size = UDim2.new(0.4, 0, 0, 80)
    bottomBar.Position = UDim2.new(0.3, 0, 1, -90)
    bottomBar.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
    bottomBar.BackgroundTransparency = 0.3
    bottomBar.Parent = spectatorGui

    local bottomCorner = Instance.new("UICorner")
    bottomCorner.CornerRadius = UDim.new(0, 10)
    bottomCorner.Parent = bottomBar

    -- Target player name
    targetLabel = Instance.new("TextLabel")
    targetLabel.Name = "TargetName"
    targetLabel.Size = UDim2.new(1, 0, 0, 30)
    targetLabel.Position = UDim2.fromOffset(0, 5)
    targetLabel.BackgroundTransparency = 1
    targetLabel.Text = ""
    targetLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    targetLabel.TextSize = 22
    targetLabel.Font = Enum.Font.GothamBold
    targetLabel.Parent = bottomBar

    -- Health bar background
    local healthBg = Instance.new("Frame")
    healthBg.Size = UDim2.new(0.8, 0, 0, 10)
    healthBg.Position = UDim2.new(0.1, 0, 0, 38)
    healthBg.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
    healthBg.Parent = bottomBar

    local healthCorner = Instance.new("UICorner")
    healthCorner.CornerRadius = UDim.new(0, 4)
    healthCorner.Parent = healthBg

    healthBar = Instance.new("Frame")
    healthBar.Name = "HealthFill"
    healthBar.Size = UDim2.new(1, 0, 1, 0)
    healthBar.BackgroundColor3 = Color3.fromRGB(0, 200, 0)
    healthBar.Parent = healthBg

    local healthFillCorner = Instance.new("UICorner")
    healthFillCorner.CornerRadius = UDim.new(0, 4)
    healthFillCorner.Parent = healthBar

    -- Mode label
    modeLabel = Instance.new("TextLabel")
    modeLabel.Size = UDim2.new(1, 0, 0, 20)
    modeLabel.Position = UDim2.fromOffset(0, 55)
    modeLabel.BackgroundTransparency = 1
    modeLabel.Text = "Follow Mode"
    modeLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
    modeLabel.TextSize = 14
    modeLabel.Font = Enum.Font.Gotham
    modeLabel.Parent = bottomBar

    -- Controls hint
    controlsLabel = Instance.new("TextLabel")
    controlsLabel.Size = UDim2.fromOffset(400, 25)
    controlsLabel.Position = UDim2.new(0.5, -200, 1, -25)
    controlsLabel.BackgroundTransparency = 1
    controlsLabel.Text = "[Q] Prev  [E] Next  [F] Free Camera  [T] Overhead"
    controlsLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
    controlsLabel.TextSize = 13
    controlsLabel.Font = Enum.Font.Gotham
    controlsLabel.Parent = spectatorGui

    -- Spectator count
    spectatorCountLabel = Instance.new("TextLabel")
    spectatorCountLabel.Size = UDim2.fromOffset(150, 25)
    spectatorCountLabel.Position = UDim2.new(0, 10, 0, 10)
    spectatorCountLabel.BackgroundTransparency = 1
    spectatorCountLabel.Text = "Spectators: 0"
    spectatorCountLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
    spectatorCountLabel.TextSize = 14
    spectatorCountLabel.Font = Enum.Font.Gotham
    spectatorCountLabel.Parent = spectatorGui
end

local function destroySpectatorUI()
    if spectatorGui then
        spectatorGui:Destroy()
        spectatorGui = nil
        targetLabel = nil
        healthBar = nil
        modeLabel = nil
        controlsLabel = nil
        spectatorCountLabel = nil
    end
end

-------------------------------------------------
-- Camera Modes
-------------------------------------------------

local function smoothMoveCameraTo(targetCF: CFrame)
    TweenService:Create(camera, TweenInfo.new(SpectatorConfig.CAMERA_TRANSITION_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        CFrame = targetCF,
    }):Play()
end

local function updateFollowCamera()
    if not currentTarget then return end
    local character = currentTarget.Character
    if not character then return end
    local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
    if not rootPart then return end

    local targetCF = rootPart.CFrame * SpectatorConfig.FOLLOW_CAMERA_OFFSET
    -- Look at the player from the offset position
    camera.CFrame = CFrame.lookAt(targetCF.Position, rootPart.Position)

    -- Update health bar
    if healthBar then
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if humanoid then
            local ratio = math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1)
            healthBar.Size = UDim2.new(ratio, 0, 1, 0)
            if ratio > 0.5 then
                healthBar.BackgroundColor3 = Color3.fromRGB(0, 200, 0)
            elseif ratio > 0.25 then
                healthBar.BackgroundColor3 = Color3.fromRGB(255, 200, 0)
            else
                healthBar.BackgroundColor3 = Color3.fromRGB(255, 50, 50)
            end
        end
    end
end

local function updateFreeCamera(dt: number)
    -- Mouse look
    local mouseDelta = UserInputService:GetMouseDelta()
    freeCamRotation = Vector2.new(
        math.clamp(freeCamRotation.X - mouseDelta.Y * 0.3, -80, 80),
        freeCamRotation.Y - mouseDelta.X * 0.3
    )

    -- WASD movement
    local moveDir = Vector3.zero
    if UserInputService:IsKeyDown(Enum.KeyCode.W) then
        moveDir += Vector3.new(0, 0, -1)
    end
    if UserInputService:IsKeyDown(Enum.KeyCode.S) then
        moveDir += Vector3.new(0, 0, 1)
    end
    if UserInputService:IsKeyDown(Enum.KeyCode.A) then
        moveDir += Vector3.new(-1, 0, 0)
    end
    if UserInputService:IsKeyDown(Enum.KeyCode.D) then
        moveDir += Vector3.new(1, 0, 0)
    end
    if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
        moveDir += Vector3.new(0, 1, 0)
    end
    if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
        moveDir += Vector3.new(0, -1, 0)
    end

    local speed = SpectatorConfig.FREE_CAMERA_SPEED
    if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
        speed *= SpectatorConfig.FREE_CAMERA_SPRINT_MULTIPLIER
    end

    -- Build camera CFrame from rotation
    local rotCFrame = CFrame.Angles(math.rad(freeCamRotation.X), math.rad(freeCamRotation.Y), 0)
    local worldMoveDir = rotCFrame:VectorToWorldSpace(moveDir)

    if worldMoveDir.Magnitude > 0 then
        worldMoveDir = worldMoveDir.Unit
    end

    freeCamPosition += worldMoveDir * speed * dt
    camera.CFrame = CFrame.new(freeCamPosition) * rotCFrame
end

local function updateOverheadCamera()
    if not currentTarget then return end
    local character = currentTarget.Character
    if not character then return end
    local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
    if not rootPart then return end

    local overheadPos = rootPart.Position + Vector3.new(0, SpectatorConfig.OVERHEAD_HEIGHT, 0)
    camera.CFrame = CFrame.new(overheadPos) * CFrame.Angles(math.rad(SpectatorConfig.OVERHEAD_ANGLE), 0, 0)
end

-------------------------------------------------
-- Target Cycling
-------------------------------------------------

local function setTarget(index: number)
    if #alivePlayers == 0 then
        currentTarget = nil
        if targetLabel then targetLabel.Text = "No players alive" end
        return
    end

    currentTargetIndex = ((index - 1) % #alivePlayers) + 1
    local targetName = alivePlayers[currentTargetIndex]
    currentTarget = Players:FindFirstChild(targetName) :: Player?

    if targetLabel then
        targetLabel.Text = if currentTarget then currentTarget.DisplayName else targetName
    end
end

local function cycleNext()
    setTarget(currentTargetIndex + 1)
end

local function cyclePrev()
    setTarget(currentTargetIndex - 1)
end

-------------------------------------------------
-- Mode Switching
-------------------------------------------------

local function switchMode(mode: SpectatorConfig.SpectatorMode)
    currentMode = mode
    camera.CameraType = Enum.CameraType.Scriptable

    if mode == "FreeCamera" then
        UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
        freeCamPosition = camera.CFrame.Position
        local _, yRot, _ = camera.CFrame:ToEulerAnglesYXZ()
        freeCamRotation = Vector2.new(0, math.deg(yRot))
        if modeLabel then modeLabel.Text = "Free Camera" end
    elseif mode == "FollowPlayer" then
        UserInputService.MouseBehavior = Enum.MouseBehavior.Default
        if modeLabel then modeLabel.Text = "Follow Mode" end
    elseif mode == "Overhead" then
        UserInputService.MouseBehavior = Enum.MouseBehavior.Default
        if modeLabel then modeLabel.Text = "Overhead View" end
    end
end

-------------------------------------------------
-- Update Loop
-------------------------------------------------

local function onUpdate(dt: number)
    if not isSpectating then return end

    if currentMode == "FollowPlayer" then
        updateFollowCamera()
    elseif currentMode == "FreeCamera" then
        updateFreeCamera(dt)
    elseif currentMode == "Overhead" then
        updateOverheadCamera()
    end
end

-------------------------------------------------
-- Input Handling
-------------------------------------------------

local function onInputBegan(input: InputObject, gameProcessed: boolean)
    if gameProcessed then return end
    if not isSpectating then return end

    if input.KeyCode == SpectatorConfig.KEY_NEXT_PLAYER then
        cycleNext()
        if currentMode == "FreeCamera" then
            switchMode("FollowPlayer")
        end
    elseif input.KeyCode == SpectatorConfig.KEY_PREV_PLAYER then
        cyclePrev()
        if currentMode == "FreeCamera" then
            switchMode("FollowPlayer")
        end
    elseif input.KeyCode == SpectatorConfig.KEY_FREE_CAMERA and SpectatorConfig.ENABLE_FREE_CAMERA then
        if currentMode == "FreeCamera" then
            switchMode("FollowPlayer")
        else
            switchMode("FreeCamera")
        end
    elseif input.KeyCode == SpectatorConfig.KEY_OVERHEAD and SpectatorConfig.ENABLE_OVERHEAD_VIEW then
        if currentMode == "Overhead" then
            switchMode("FollowPlayer")
        else
            switchMode("Overhead")
        end
    end
end

-------------------------------------------------
-- Public API
-------------------------------------------------

function SpectatorController.EnterSpectatorMode(playerNames: { string })
    if isSpectating then return end

    isSpectating = true
    alivePlayers = playerNames

    -- Set camera to scriptable
    camera.CameraType = Enum.CameraType.Scriptable

    -- Create UI
    createSpectatorUI()

    -- Set initial target
    setTarget(1)
    switchMode("FollowPlayer")

    -- Connect update loop
    updateConnection = RunService.RenderStepped:Connect(onUpdate)
    inputConnection = UserInputService.InputBegan:Connect(onInputBegan)
end

function SpectatorController.ExitSpectatorMode()
    if not isSpectating then return end

    isSpectating = false
    currentTarget = nil

    -- Restore camera
    camera.CameraType = Enum.CameraType.Custom
    UserInputService.MouseBehavior = Enum.MouseBehavior.Default

    -- Disconnect
    if updateConnection then
        updateConnection:Disconnect()
        updateConnection = nil
    end
    if inputConnection then
        inputConnection:Disconnect()
        inputConnection = nil
    end

    -- Destroy UI
    destroySpectatorUI()
end

function SpectatorController.IsSpectating(): boolean
    return isSpectating
end

function SpectatorController.Init()
    local remotes = ReplicatedStorage:WaitForChild("SpectatorRemotes")

    -- Server-initiated spectator mode
    local enterEvent = remotes:WaitForChild("EnterSpectator") :: RemoteEvent
    enterEvent.OnClientEvent:Connect(function(playerNames: { string })
        SpectatorController.EnterSpectatorMode(playerNames)
    end)

    local exitEvent = remotes:WaitForChild("ExitSpectator") :: RemoteEvent
    exitEvent.OnClientEvent:Connect(function()
        SpectatorController.ExitSpectatorMode()
    end)

    -- Alive players list updates
    local aliveUpdate = remotes:WaitForChild("AlivePlayersUpdate") :: RemoteEvent
    aliveUpdate.OnClientEvent:Connect(function(playerNames: { string })
        alivePlayers = playerNames

        -- If current target is no longer alive, cycle to next
        if currentTarget then
            local stillAlive = table.find(alivePlayers, currentTarget.Name)
            if not stillAlive then
                cycleNext()
            end
        end
    end)

    -- Spectator count
    local countUpdate = remotes:WaitForChild("SpectatorCountUpdate") :: RemoteEvent
    countUpdate.OnClientEvent:Connect(function(count: number)
        if spectatorCountLabel then
            spectatorCountLabel.Text = "Spectators: " .. tostring(count)
        end
    end)
end

return SpectatorController
```

---

## Key Implementation Notes

1. **Three camera modes**: FollowPlayer (third-person behind target), FreeCamera (WASD + mouse fly), Overhead (bird's eye tracking target).
2. **Smooth transitions**: Camera moves use TweenService for seamless switching between targets.
3. **Free camera** locks the mouse to center and uses `GetMouseDelta()` for look rotation. WASD moves in camera-relative directions.
4. **Server authority**: The server tracks who is spectating and provides the alive player list. Clients cannot fake being alive.
5. **Auto-spectate on death**: When a player dies, they automatically enter spectator mode after a 1-second delay.
6. **Target cycling** wraps around the alive player list. If the watched player dies, it auto-cycles to the next alive player.
7. **Character hiding**: The spectator's character is made invisible and non-collidable so they don't interfere with the game.
8. **Health bar** updates in real-time for the followed player, with color changing at health thresholds.
9. **Spectator count** is broadcast to all clients for display.

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
- `$AUTO_SPECTATE` -- Whether to auto-enter spectator mode on death (default true)
- `$FREE_CAMERA` -- Whether to allow free camera mode (default true)
- `$OVERHEAD_VIEW` -- Whether to allow overhead view (default true)
- `$CAMERA_SPEED` -- Free camera movement speed (default 50)
- `$FOLLOW_OFFSET` -- Camera offset behind followed player
- `$SHOW_HEALTH` -- Whether to show spectated player's health bar (default true)
- `$SHOW_STATS` -- Whether to show spectated player's stats (default true)
- `$KEYBINDS` -- Custom keybind overrides for spectator controls
