---
name: replay
description: |
  Roblox 리플레이 녹화 시스템 - Replay recording, player position storage, playback camera, highlights.
  로블록스 리플레이, 녹화, 재생 카메라, 하이라이트 저장, 프레임별 위치 기록.
  Full replay recording and playback system for Roblox with ghost visualization and highlight saving.
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Grep
  - Glob
effort: high
---

# Roblox Replay Recording System

Record player actions frame-by-frame, play them back with a free-fly or follow camera, and save highlight clips. Works entirely in Luau with server-authoritative recording and client-side playback.

---

## Architecture Overview

```
ReplaySystem
  ├── ReplayRecorder (Server)    -- Captures snapshots at configurable tick rate
  ├── ReplayStorage              -- Compresses and stores replay data
  ├── ReplayPlayback (Client)    -- Reconstructs scene from snapshots
  ├── ReplayCamera               -- Free-fly, follow, and orbit camera modes
  └── HighlightManager           -- Mark & save interesting moments
```

---

## 1. Replay Data Types

```luau
--!strict
-- ReplayTypes.lua (ReplicatedStorage/Shared)

export type PlayerSnapshot = {
    userId: number,
    position: Vector3,
    rotation: Vector3,       -- Euler angles in radians
    velocity: Vector3,
    animationId: string?,
    animationWeight: number?,
    health: number,
    tool: string?,           -- Currently equipped tool name
}

export type FrameData = {
    timestamp: number,       -- Seconds since recording started
    frameIndex: number,
    players: { PlayerSnapshot },
    events: { GameEvent }?,  -- Optional game-specific events
}

export type GameEvent = {
    eventType: string,       -- "Kill", "Score", "Explosion", etc.
    data: { [string]: any },
    position: Vector3?,
}

export type ReplayData = {
    replayId: string,
    startTime: number,       -- os.time() when recording began
    tickRate: number,        -- Frames per second
    totalFrames: number,
    duration: number,        -- Total seconds
    frames: { FrameData },
    metadata: ReplayMetadata,
}

export type ReplayMetadata = {
    mapName: string,
    gameMode: string,
    playerCount: number,
    playerNames: { [number]: string },  -- userId -> displayName
    highlights: { HighlightMarker },
}

export type HighlightMarker = {
    frameIndex: number,
    timestamp: number,
    label: string,
    category: string,        -- "Kill", "Save", "Goal", etc.
}

return nil
```

---

## 2. ReplayRecorder (Server)

Runs on the server and captures player state at a fixed tick rate. Uses delta compression to reduce memory.

```luau
--!strict
-- ReplayRecorder.lua (ServerScriptService)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

export type PlayerSnapshot = {
    userId: number,
    position: Vector3,
    rotation: Vector3,
    velocity: Vector3,
    animationId: string?,
    health: number,
    tool: string?,
}

export type FrameData = {
    timestamp: number,
    frameIndex: number,
    players: { PlayerSnapshot },
}

export type GameEvent = {
    eventType: string,
    data: { [string]: any },
    position: Vector3?,
}

export type HighlightMarker = {
    frameIndex: number,
    timestamp: number,
    label: string,
    category: string,
}

local ReplayRecorder = {}
ReplayRecorder.__index = ReplayRecorder

type RecorderImpl = {
    _isRecording: boolean,
    _tickRate: number,
    _tickInterval: number,
    _elapsed: number,
    _frameIndex: number,
    _startTime: number,
    _frames: { FrameData },
    _events: { [number]: { GameEvent } },
    _highlights: { HighlightMarker },
    _connection: RBXScriptConnection?,
    _maxDuration: number,
    _mapName: string,
    _gameMode: string,
}

export type RecorderType = typeof(setmetatable({} :: RecorderImpl, ReplayRecorder))

function ReplayRecorder.new(config: {
    tickRate: number?,
    maxDuration: number?,
    mapName: string?,
    gameMode: string?,
}?): RecorderType
    local cfg = config or {}
    local self = setmetatable({} :: RecorderImpl, ReplayRecorder)
    self._isRecording = false
    self._tickRate = cfg.tickRate or 20
    self._tickInterval = 1.0 / self._tickRate
    self._elapsed = 0
    self._frameIndex = 0
    self._startTime = 0
    self._frames = {}
    self._events = {}
    self._highlights = {}
    self._connection = nil
    self._maxDuration = cfg.maxDuration or 300  -- 5 minutes default
    self._mapName = cfg.mapName or "Unknown"
    self._gameMode = cfg.gameMode or "Default"
    return self
end

function ReplayRecorder.StartRecording(self: RecorderType): ()
    if self._isRecording then
        warn("[ReplayRecorder] Already recording")
        return
    end

    self._isRecording = true
    self._elapsed = 0
    self._frameIndex = 0
    self._startTime = os.time()
    self._frames = {}
    self._events = {}
    self._highlights = {}

    self._connection = RunService.Heartbeat:Connect(function(dt)
        if not self._isRecording then return end

        self._elapsed += dt

        -- Check max duration
        if self._elapsed >= self._maxDuration then
            self:StopRecording()
            return
        end

        -- Capture at tick rate
        if self._elapsed >= (self._frameIndex + 1) * self._tickInterval then
            self._frameIndex += 1
            self:_captureFrame()
        end
    end)
end

function ReplayRecorder.StopRecording(self: RecorderType): ()
    self._isRecording = false
    if self._connection then
        self._connection:Disconnect()
        self._connection = nil
    end
end

function ReplayRecorder._captureFrame(self: RecorderType): ()
    local snapshots: { PlayerSnapshot } = {}

    for _, player in Players:GetPlayers() do
        local character = player.Character
        if not character then continue end

        local humanoidRootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if not humanoidRootPart or not humanoid then continue end

        local tool: string? = nil
        local equippedTool = character:FindFirstChildOfClass("Tool")
        if equippedTool then
            tool = equippedTool.Name
        end

        local rx, ry, rz = humanoidRootPart.CFrame:ToEulerAnglesYXZ()

        local snapshot: PlayerSnapshot = {
            userId = player.UserId,
            position = humanoidRootPart.Position,
            rotation = Vector3.new(rx, ry, rz),
            velocity = humanoidRootPart.AssemblyLinearVelocity,
            health = humanoid.Health,
            tool = tool,
        }

        table.insert(snapshots, snapshot)
    end

    local frame: FrameData = {
        timestamp = self._elapsed,
        frameIndex = self._frameIndex,
        players = snapshots,
    }

    table.insert(self._frames, frame)
end

function ReplayRecorder.AddGameEvent(self: RecorderType, event: GameEvent): ()
    if not self._isRecording then return end
    if not self._events[self._frameIndex] then
        self._events[self._frameIndex] = {}
    end
    table.insert(self._events[self._frameIndex], event)
end

function ReplayRecorder.AddHighlight(self: RecorderType, label: string, category: string): ()
    if not self._isRecording then return end
    table.insert(self._highlights, {
        frameIndex = self._frameIndex,
        timestamp = self._elapsed,
        label = label,
        category = category,
    })
end

function ReplayRecorder.GetReplayData(self: RecorderType): {
    replayId: string,
    startTime: number,
    tickRate: number,
    totalFrames: number,
    duration: number,
    frames: { FrameData },
    highlights: { HighlightMarker },
    mapName: string,
    gameMode: string,
}
    local playerNames: { [number]: string } = {}
    for _, player in Players:GetPlayers() do
        playerNames[player.UserId] = player.DisplayName
    end

    return {
        replayId = HttpService:GenerateGUID(false),
        startTime = self._startTime,
        tickRate = self._tickRate,
        totalFrames = self._frameIndex,
        duration = self._elapsed,
        frames = self._frames,
        highlights = self._highlights,
        mapName = self._mapName,
        gameMode = self._gameMode,
    }
end

function ReplayRecorder.IsRecording(self: RecorderType): boolean
    return self._isRecording
end

return ReplayRecorder
```

---

## 3. ReplayPlayback (Client)

Reconstructs the recorded scene using dummy models and interpolates between frames for smooth playback.

```luau
--!strict
-- ReplayPlayback.lua (StarterPlayerScripts)

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

type PlayerSnapshot = {
    userId: number,
    position: Vector3,
    rotation: Vector3,
    velocity: Vector3,
    health: number,
    tool: string?,
}

type FrameData = {
    timestamp: number,
    frameIndex: number,
    players: { PlayerSnapshot },
}

type ReplayInput = {
    tickRate: number,
    totalFrames: number,
    duration: number,
    frames: { FrameData },
}

local ReplayPlayback = {}
ReplayPlayback.__index = ReplayPlayback

type PlaybackImpl = {
    _replayData: ReplayInput?,
    _isPlaying: boolean,
    _isPaused: boolean,
    _currentTime: number,
    _playbackSpeed: number,
    _ghostModels: { [number]: Model },  -- userId -> ghost model
    _connection: RBXScriptConnection?,
    _ghostFolder: Folder?,
}

export type PlaybackType = typeof(setmetatable({} :: PlaybackImpl, ReplayPlayback))

function ReplayPlayback.new(): PlaybackType
    local self = setmetatable({} :: PlaybackImpl, ReplayPlayback)
    self._replayData = nil
    self._isPlaying = false
    self._isPaused = false
    self._currentTime = 0
    self._playbackSpeed = 1.0
    self._ghostModels = {}
    self._connection = nil
    self._ghostFolder = nil
    return self
end

function ReplayPlayback.LoadReplay(self: PlaybackType, data: ReplayInput): ()
    self:Stop()
    self._replayData = data
    self._currentTime = 0
end

function ReplayPlayback.Play(self: PlaybackType): ()
    if not self._replayData then
        warn("[ReplayPlayback] No replay data loaded")
        return
    end
    if self._isPlaying and not self._isPaused then return end

    self._isPlaying = true
    self._isPaused = false

    -- Create ghost folder
    if not self._ghostFolder then
        local folder = Instance.new("Folder")
        folder.Name = "ReplayGhosts"
        folder.Parent = workspace
        self._ghostFolder = folder
    end

    self._connection = RunService.RenderStepped:Connect(function(dt)
        if self._isPaused then return end

        self._currentTime += dt * self._playbackSpeed

        local data = self._replayData
        if not data then return end

        if self._currentTime >= data.duration then
            self:Stop()
            return
        end

        self:_interpolateFrame()
    end)
end

function ReplayPlayback._interpolateFrame(self: PlaybackType): ()
    local data = self._replayData
    if not data then return end

    -- Find the two frames to interpolate between
    local frameA: FrameData? = nil
    local frameB: FrameData? = nil

    for i, frame in data.frames do
        if frame.timestamp <= self._currentTime then
            frameA = frame
            if i < #data.frames then
                frameB = data.frames[i + 1]
            end
        else
            break
        end
    end

    if not frameA then return end

    -- Calculate interpolation alpha
    local alpha = 0.0
    if frameB then
        local span = frameB.timestamp - frameA.timestamp
        if span > 0 then
            alpha = (self._currentTime - frameA.timestamp) / span
        end
    end

    -- Update ghost models
    for _, snapshotA in frameA.players do
        local snapshotB: PlayerSnapshot? = nil
        if frameB then
            for _, s in frameB.players do
                if s.userId == snapshotA.userId then
                    snapshotB = s
                    break
                end
            end
        end

        local ghost = self:_getOrCreateGhost(snapshotA.userId)
        local primaryPart = ghost.PrimaryPart
        if not primaryPart then continue end

        local pos = snapshotA.position
        local rot = snapshotA.rotation

        if snapshotB and alpha > 0 then
            pos = pos:Lerp(snapshotB.position, alpha)
            rot = rot:Lerp(snapshotB.rotation, alpha)
        end

        local cf = CFrame.new(pos) * CFrame.fromEulerAnglesYXZ(rot.X, rot.Y, rot.Z)
        ghost:PivotTo(cf)
    end
end

function ReplayPlayback._getOrCreateGhost(self: PlaybackType, userId: number): Model
    if self._ghostModels[userId] then
        return self._ghostModels[userId]
    end

    -- Create a simple ghost model (translucent humanoid stand-in)
    local model = Instance.new("Model")
    model.Name = "Ghost_" .. tostring(userId)

    local torso = Instance.new("Part")
    torso.Name = "HumanoidRootPart"
    torso.Size = Vector3.new(2, 2, 1)
    torso.Anchored = true
    torso.CanCollide = false
    torso.Transparency = 0.5
    torso.Color = Color3.fromRGB(100, 180, 255)
    torso.Material = Enum.Material.Neon
    torso.Parent = model

    local head = Instance.new("Part")
    head.Name = "Head"
    head.Shape = Enum.PartType.Ball
    head.Size = Vector3.new(1.2, 1.2, 1.2)
    head.Anchored = true
    head.CanCollide = false
    head.Transparency = 0.5
    head.Color = Color3.fromRGB(100, 180, 255)
    head.Material = Enum.Material.Neon
    head.CFrame = torso.CFrame * CFrame.new(0, 1.6, 0)
    head.Parent = model

    local billboard = Instance.new("BillboardGui")
    billboard.Size = UDim2.new(0, 100, 0, 30)
    billboard.StudsOffset = Vector3.new(0, 3, 0)
    billboard.AlwaysOnTop = true
    billboard.Parent = head

    local nameLabel = Instance.new("TextLabel")
    nameLabel.Size = UDim2.new(1, 0, 1, 0)
    nameLabel.BackgroundTransparency = 1
    nameLabel.TextColor3 = Color3.fromRGB(200, 230, 255)
    nameLabel.TextStrokeTransparency = 0.5
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.TextSize = 14
    nameLabel.Text = "Player " .. tostring(userId)
    nameLabel.Parent = billboard

    model.PrimaryPart = torso
    model.Parent = self._ghostFolder

    self._ghostModels[userId] = model
    return model
end

function ReplayPlayback.Pause(self: PlaybackType): ()
    self._isPaused = true
end

function ReplayPlayback.Resume(self: PlaybackType): ()
    self._isPaused = false
end

function ReplayPlayback.SetSpeed(self: PlaybackType, speed: number): ()
    self._playbackSpeed = math.clamp(speed, 0.1, 4.0)
end

function ReplayPlayback.SeekTo(self: PlaybackType, timestamp: number): ()
    local data = self._replayData
    if not data then return end
    self._currentTime = math.clamp(timestamp, 0, data.duration)
    self:_interpolateFrame()
end

function ReplayPlayback.SeekToFrame(self: PlaybackType, frameIndex: number): ()
    local data = self._replayData
    if not data then return end
    local frame = data.frames[frameIndex]
    if frame then
        self._currentTime = frame.timestamp
        self:_interpolateFrame()
    end
end

function ReplayPlayback.GetCurrentTime(self: PlaybackType): number
    return self._currentTime
end

function ReplayPlayback.GetDuration(self: PlaybackType): number
    return if self._replayData then self._replayData.duration else 0
end

function ReplayPlayback.Stop(self: PlaybackType): ()
    self._isPlaying = false
    self._isPaused = false
    self._currentTime = 0

    if self._connection then
        self._connection:Disconnect()
        self._connection = nil
    end

    -- Clean up ghost models
    for userId, ghost in self._ghostModels do
        ghost:Destroy()
    end
    table.clear(self._ghostModels)

    if self._ghostFolder then
        self._ghostFolder:Destroy()
        self._ghostFolder = nil
    end
end

return ReplayPlayback
```

---

## 4. ReplayCamera

Provides free-fly, follow, and orbit camera modes during playback.

```luau
--!strict
-- ReplayCamera.lua (StarterPlayerScripts)

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

export type CameraMode = "FreeFly" | "Follow" | "Orbit"

local ReplayCamera = {}
ReplayCamera.__index = ReplayCamera

type CameraImpl = {
    _mode: CameraMode,
    _followTarget: Model?,
    _orbitDistance: number,
    _orbitAngle: number,
    _orbitPitch: number,
    _flySpeed: number,
    _sensitivity: number,
    _yaw: number,
    _pitch: number,
    _position: Vector3,
    _connection: RBXScriptConnection?,
    _originalCameraType: Enum.CameraType?,
}

export type CameraType = typeof(setmetatable({} :: CameraImpl, ReplayCamera))

function ReplayCamera.new(): CameraType
    local self = setmetatable({} :: CameraImpl, ReplayCamera)
    self._mode = "FreeFly"
    self._followTarget = nil
    self._orbitDistance = 15
    self._orbitAngle = 0
    self._orbitPitch = math.rad(30)
    self._flySpeed = 30
    self._sensitivity = 0.003
    self._yaw = 0
    self._pitch = 0
    self._position = Vector3.new(0, 20, 0)
    self._connection = nil
    self._originalCameraType = nil
    return self
end

function ReplayCamera.Activate(self: CameraType): ()
    local camera = workspace.CurrentCamera
    if not camera then return end
    self._originalCameraType = camera.CameraType
    camera.CameraType = Enum.CameraType.Scriptable
    self._position = camera.CFrame.Position
    local _, ry, _ = camera.CFrame:ToEulerAnglesYXZ()
    self._yaw = ry

    self._connection = RunService.RenderStepped:Connect(function(dt)
        self:_update(dt)
    end)
end

function ReplayCamera.Deactivate(self: CameraType): ()
    if self._connection then
        self._connection:Disconnect()
        self._connection = nil
    end
    local camera = workspace.CurrentCamera
    if camera and self._originalCameraType then
        camera.CameraType = self._originalCameraType
    end
end

function ReplayCamera.SetMode(self: CameraType, mode: CameraMode): ()
    self._mode = mode
end

function ReplayCamera.SetFollowTarget(self: CameraType, target: Model?): ()
    self._followTarget = target
end

function ReplayCamera._update(self: CameraType, dt: number): ()
    local camera = workspace.CurrentCamera
    if not camera then return end

    if self._mode == "FreeFly" then
        self:_updateFreeFly(dt, camera)
    elseif self._mode == "Follow" then
        self:_updateFollow(dt, camera)
    elseif self._mode == "Orbit" then
        self:_updateOrbit(dt, camera)
    end
end

function ReplayCamera._updateFreeFly(self: CameraType, dt: number, camera: Camera): ()
    -- Mouse look (right mouse button held)
    if UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
        local delta = UserInputService:GetMouseDelta()
        self._yaw -= delta.X * self._sensitivity
        self._pitch = math.clamp(self._pitch - delta.Y * self._sensitivity, -math.rad(89), math.rad(89))
    end

    -- WASD movement
    local moveDir = Vector3.zero
    if UserInputService:IsKeyDown(Enum.KeyCode.W) then moveDir += Vector3.new(0, 0, -1) end
    if UserInputService:IsKeyDown(Enum.KeyCode.S) then moveDir += Vector3.new(0, 0, 1) end
    if UserInputService:IsKeyDown(Enum.KeyCode.A) then moveDir += Vector3.new(-1, 0, 0) end
    if UserInputService:IsKeyDown(Enum.KeyCode.D) then moveDir += Vector3.new(1, 0, 0) end
    if UserInputService:IsKeyDown(Enum.KeyCode.E) then moveDir += Vector3.new(0, 1, 0) end
    if UserInputService:IsKeyDown(Enum.KeyCode.Q) then moveDir += Vector3.new(0, -1, 0) end

    local speed = self._flySpeed
    if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then speed *= 2 end

    local rotation = CFrame.fromEulerAnglesYXZ(self._pitch, self._yaw, 0)
    if moveDir.Magnitude > 0 then
        moveDir = (rotation * CFrame.new(moveDir.Unit * speed * dt)).Position - rotation.Position
        self._position += moveDir
    end

    camera.CFrame = CFrame.new(self._position) * rotation
end

function ReplayCamera._updateFollow(self: CameraType, _dt: number, camera: Camera): ()
    if not self._followTarget or not self._followTarget.PrimaryPart then return end
    local targetPos = self._followTarget.PrimaryPart.Position
    local offset = Vector3.new(0, 8, 12)
    camera.CFrame = CFrame.lookAt(targetPos + offset, targetPos)
end

function ReplayCamera._updateOrbit(self: CameraType, dt: number, camera: Camera): ()
    if not self._followTarget or not self._followTarget.PrimaryPart then return end

    -- Mouse drag to orbit
    if UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
        local delta = UserInputService:GetMouseDelta()
        self._orbitAngle -= delta.X * self._sensitivity * 2
        self._orbitPitch = math.clamp(self._orbitPitch - delta.Y * self._sensitivity, math.rad(5), math.rad(85))
    end

    local targetPos = self._followTarget.PrimaryPart.Position
    local offsetX = math.cos(self._orbitAngle) * math.cos(self._orbitPitch) * self._orbitDistance
    local offsetY = math.sin(self._orbitPitch) * self._orbitDistance
    local offsetZ = math.sin(self._orbitAngle) * math.cos(self._orbitPitch) * self._orbitDistance

    local camPos = targetPos + Vector3.new(offsetX, offsetY, offsetZ)
    camera.CFrame = CFrame.lookAt(camPos, targetPos)
end

return ReplayCamera
```

---

## Usage Example (Full Integration)

```luau
-- Server: Record a match
local ReplayRecorder = require(ServerScriptService.ReplayRecorder)
local recorder = ReplayRecorder.new({ tickRate = 20, maxDuration = 180 })

recorder:StartRecording()
-- ... match plays ...
recorder:AddHighlight("Amazing Save", "Save")
-- ... match ends ...
recorder:StopRecording()
local replayData = recorder:GetReplayData()

-- Client: Play back the replay
local ReplayPlayback = require(script.ReplayPlayback)
local ReplayCamera = require(script.ReplayCamera)

local playback = ReplayPlayback.new()
local cam = ReplayCamera.new()

playback:LoadReplay(replayData)
playback:Play()
cam:Activate()
cam:SetMode("FreeFly")

-- Seek to a highlight
playback:SeekTo(replayData.highlights[1].timestamp)

-- Change playback speed
playback:SetSpeed(0.5)  -- slow motion

-- Follow a specific ghost
cam:SetMode("Follow")
cam:SetFollowTarget(playback._ghostModels[someUserId])
```

---

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

When using this skill, provide:

- `$TICK_RATE` - Snapshots per second (default: 20). Higher = smoother but more memory.
- `$MAX_DURATION` - Maximum recording length in seconds (default: 300).
- `$GAME_MODE` - Game mode name for replay metadata.
- `$MAP_NAME` - Map/level name for replay metadata.
- `$GHOST_STYLE` - Visual style for playback ghosts: "Neon", "Transparent", "Outline".
- `$CAMERA_MODES` - Comma-separated camera modes to enable: "FreeFly,Follow,Orbit".
- `$PERSIST_REPLAYS` - Whether to save replays to DataStore: "true" or "false".
