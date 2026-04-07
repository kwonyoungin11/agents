---
name: racing
description: |
  Roblox 레이싱 시스템 - Race system, checkpoints, lap counter, position tracking, finish line, ghost replay, timer.
  로블록스 레이싱, 체크포인트, 랩 카운터, 순위 추적, 결승선, 고스트 리플레이, 타이머.
  Complete racing game framework for Roblox with checkpoint validation, anti-cheat, and ghost replay.
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Grep
  - Glob
effort: high
---

# Roblox Racing System

Full-featured racing system with checkpoint-based lap tracking, real-time position calculation, ghost replay, precision timers, and a finish-line ceremony. Server-authoritative with client-side prediction for responsive feel.

---

## Architecture Overview

```
RaceSystem
  ├── RaceManager (Server)         -- Orchestrates race lifecycle
  ├── CheckpointSystem             -- Validates checkpoint progression
  ├── LapCounter                   -- Tracks laps per racer
  ├── PositionTracker              -- Real-time race position (1st, 2nd, etc.)
  ├── RaceTimer                    -- High-precision timer with splits
  ├── GhostReplay                  -- Records & plays back best-time ghosts
  └── RaceHUD (Client)            -- Displays position, lap, timer, minimap
```

---

## 1. Race Data Types

```luau
--!strict
-- RaceTypes.lua (ReplicatedStorage/Shared)

export type RacerState = {
    playerId: number,
    currentCheckpoint: number,
    currentLap: number,
    totalTime: number,
    lapTimes: { number },
    splitTimes: { number },       -- Time at each checkpoint
    finished: boolean,
    finishTime: number?,
    position: number,             -- 1st, 2nd, etc.
    distanceToNext: number,       -- Distance to next checkpoint (for position calc)
}

export type CheckpointData = {
    index: number,
    part: BasePart,
    position: Vector3,
    isFinishLine: boolean,
}

export type RaceConfig = {
    trackName: string,
    totalLaps: number,
    maxRacers: number,
    countdownDuration: number,
    checkpoints: { CheckpointData },
    allowGhosts: boolean,
    dnfTimeout: number,           -- Seconds before DNF
}

export type GhostFrame = {
    timestamp: number,
    position: Vector3,
    rotation: CFrame,
}

export type GhostData = {
    playerId: number,
    playerName: string,
    totalTime: number,
    frames: { GhostFrame },
}

return nil
```

---

## 2. RaceManager (Server)

Orchestrates the full race lifecycle: lobby, countdown, race, finish.

```luau
--!strict
-- RaceManager.lua (ServerScriptService)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

export type RacerState = {
    playerId: number,
    currentCheckpoint: number,
    currentLap: number,
    totalTime: number,
    lapTimes: { number },
    splitTimes: { number },
    finished: boolean,
    finishTime: number?,
    position: number,
    distanceToNext: number,
}

export type CheckpointData = {
    index: number,
    part: BasePart,
    position: Vector3,
    isFinishLine: boolean,
}

export type RaceConfig = {
    trackName: string,
    totalLaps: number,
    maxRacers: number,
    countdownDuration: number,
    checkpoints: { CheckpointData },
    dnfTimeout: number,
}

export type RacePhase = "Lobby" | "Countdown" | "Racing" | "Finished"

local RaceManager = {}
RaceManager.__index = RaceManager

type RaceImpl = {
    _config: RaceConfig,
    _phase: RacePhase,
    _racers: { [number]: RacerState },  -- playerId -> state
    _finishOrder: { number },            -- ordered playerIds
    _raceStartTime: number,
    _connection: RBXScriptConnection?,
    _checkpointTouched: { [number]: RBXScriptConnection },
    _onPhaseChange: BindableEvent,
    _onRacerFinish: BindableEvent,
    _onPositionUpdate: BindableEvent,
}

export type RaceType = typeof(setmetatable({} :: RaceImpl, RaceManager))

function RaceManager.new(config: RaceConfig): RaceType
    local self = setmetatable({} :: RaceImpl, RaceManager)
    self._config = config
    self._phase = "Lobby"
    self._racers = {}
    self._finishOrder = {}
    self._raceStartTime = 0
    self._connection = nil
    self._checkpointTouched = {}
    self._onPhaseChange = Instance.new("BindableEvent")
    self._onRacerFinish = Instance.new("BindableEvent")
    self._onPositionUpdate = Instance.new("BindableEvent")
    return self
end

function RaceManager.AddRacer(self: RaceType, player: Player): boolean
    if self._phase ~= "Lobby" then return false end
    if self._racers[player.UserId] then return false end

    local count = 0
    for _ in self._racers do count += 1 end
    if count >= self._config.maxRacers then return false end

    self._racers[player.UserId] = {
        playerId = player.UserId,
        currentCheckpoint = 0,
        currentLap = 0,
        totalTime = 0,
        lapTimes = {},
        splitTimes = {},
        finished = false,
        finishTime = nil,
        position = count + 1,
        distanceToNext = 0,
    }
    return true
end

function RaceManager.RemoveRacer(self: RaceType, playerId: number): ()
    self._racers[playerId] = nil
end

function RaceManager.StartCountdown(self: RaceType): ()
    if self._phase ~= "Lobby" then return end
    self:_setPhase("Countdown")

    task.delay(self._config.countdownDuration, function()
        self:_startRace()
    end)
end

function RaceManager._startRace(self: RaceType): ()
    self:_setPhase("Racing")
    self._raceStartTime = tick()

    -- Set up checkpoint touch detection
    for _, cp in self._config.checkpoints do
        local conn = cp.part.Touched:Connect(function(hit)
            local character = hit.Parent
            if not character then return end
            local player = Players:GetPlayerFromCharacter(character)
            if not player then return end
            self:_onCheckpointHit(player.UserId, cp.index)
        end)
        self._checkpointTouched[cp.index] = conn
    end

    -- Update positions every frame
    self._connection = RunService.Heartbeat:Connect(function(dt)
        self:_updatePositions()
        self:_updateTimers(dt)
        self:_checkDNF()
    end)
end

function RaceManager._onCheckpointHit(self: RaceType, playerId: number, checkpointIndex: number): ()
    local racer = self._racers[playerId]
    if not racer or racer.finished then return end

    local totalCheckpoints = #self._config.checkpoints
    local expectedNext = (racer.currentCheckpoint % totalCheckpoints) + 1

    -- Anti-cheat: must hit checkpoints in order
    if checkpointIndex ~= expectedNext then return end

    racer.currentCheckpoint = checkpointIndex
    racer.splitTimes[checkpointIndex] = tick() - self._raceStartTime

    -- Check if crossed finish line (checkpoint 1 after completing a full loop)
    local finishCheckpoint = 1
    for _, cp in self._config.checkpoints do
        if cp.isFinishLine then
            finishCheckpoint = cp.index
            break
        end
    end

    if checkpointIndex == finishCheckpoint and racer.currentCheckpoint == totalCheckpoints then
        -- Completed a full loop, this checkpoint hit means crossing finish
        -- Actually: we track by modular index. If the racer just hit the last checkpoint:
    end

    -- Lap completion: hit all checkpoints and returned to finish
    if checkpointIndex == finishCheckpoint and #racer.splitTimes >= totalCheckpoints then
        racer.currentLap += 1
        local lapTime = tick() - self._raceStartTime
        if #racer.lapTimes > 0 then
            lapTime = lapTime - racer.lapTimes[#racer.lapTimes]
        end
        table.insert(racer.lapTimes, lapTime)
        racer.currentCheckpoint = 0
        racer.splitTimes = {}

        if racer.currentLap >= self._config.totalLaps then
            self:_finishRacer(playerId)
        end
    end
end

function RaceManager._finishRacer(self: RaceType, playerId: number): ()
    local racer = self._racers[playerId]
    if not racer or racer.finished then return end

    racer.finished = true
    racer.finishTime = tick() - self._raceStartTime
    racer.totalTime = racer.finishTime
    table.insert(self._finishOrder, playerId)
    racer.position = #self._finishOrder

    self._onRacerFinish:Fire(playerId, racer.position, racer.finishTime)

    -- Check if all racers finished
    local allFinished = true
    for _, r in self._racers do
        if not r.finished then
            allFinished = false
            break
        end
    end
    if allFinished then
        self:_endRace()
    end
end

function RaceManager._updatePositions(self: RaceType): ()
    -- Sort racers by progress (lap, then checkpoint, then distance to next)
    local sorted: { RacerState } = {}
    for _, racer in self._racers do
        if not racer.finished then
            -- Calculate distance to next checkpoint
            local player = Players:GetPlayerByUserId(racer.playerId)
            if player and player.Character then
                local hrp = player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
                if hrp then
                    local nextCP = (racer.currentCheckpoint % #self._config.checkpoints) + 1
                    local cpData = self._config.checkpoints[nextCP]
                    if cpData then
                        racer.distanceToNext = (hrp.Position - cpData.position).Magnitude
                    end
                end
            end
            table.insert(sorted, racer)
        end
    end

    table.sort(sorted, function(a, b)
        if a.currentLap ~= b.currentLap then
            return a.currentLap > b.currentLap
        end
        if a.currentCheckpoint ~= b.currentCheckpoint then
            return a.currentCheckpoint > b.currentCheckpoint
        end
        return a.distanceToNext < b.distanceToNext
    end)

    local finishedCount = #self._finishOrder
    for i, racer in sorted do
        racer.position = finishedCount + i
    end

    self._onPositionUpdate:Fire(self:GetRacerStates())
end

function RaceManager._updateTimers(self: RaceType, _dt: number): ()
    local elapsed = tick() - self._raceStartTime
    for _, racer in self._racers do
        if not racer.finished then
            racer.totalTime = elapsed
        end
    end
end

function RaceManager._checkDNF(self: RaceType): ()
    local elapsed = tick() - self._raceStartTime
    if elapsed < self._config.dnfTimeout then return end

    for playerId, racer in self._racers do
        if not racer.finished then
            racer.finished = true
            racer.finishTime = -1  -- DNF marker
            table.insert(self._finishOrder, playerId)
            racer.position = #self._finishOrder
        end
    end
    self:_endRace()
end

function RaceManager._endRace(self: RaceType): ()
    self:_setPhase("Finished")
    if self._connection then
        self._connection:Disconnect()
        self._connection = nil
    end
    for _, conn in self._checkpointTouched do
        conn:Disconnect()
    end
    table.clear(self._checkpointTouched)
end

function RaceManager._setPhase(self: RaceType, phase: RacePhase): ()
    self._phase = phase
    self._onPhaseChange:Fire(phase)
end

function RaceManager.GetPhase(self: RaceType): RacePhase
    return self._phase
end

function RaceManager.GetRacerStates(self: RaceType): { [number]: RacerState }
    return self._racers
end

function RaceManager.GetFinishOrder(self: RaceType): { number }
    return self._finishOrder
end

function RaceManager.OnPhaseChange(self: RaceType): RBXScriptSignal
    return self._onPhaseChange.Event
end

function RaceManager.OnRacerFinish(self: RaceType): RBXScriptSignal
    return self._onRacerFinish.Event
end

function RaceManager.OnPositionUpdate(self: RaceType): RBXScriptSignal
    return self._onPositionUpdate.Event
end

function RaceManager.Destroy(self: RaceType): ()
    self:_endRace()
    self._onPhaseChange:Destroy()
    self._onRacerFinish:Destroy()
    self._onPositionUpdate:Destroy()
end

return RaceManager
```

---

## 3. GhostReplay

Records the player's best run and renders a translucent ghost car/character for comparison.

```luau
--!strict
-- GhostReplay.lua

local RunService = game:GetService("RunService")

export type GhostFrame = {
    timestamp: number,
    position: Vector3,
    rotation: CFrame,
}

export type GhostData = {
    playerId: number,
    playerName: string,
    totalTime: number,
    frames: { GhostFrame },
}

local GhostReplay = {}
GhostReplay.__index = GhostReplay

type GhostImpl = {
    _isRecording: boolean,
    _isPlaying: boolean,
    _recordFrames: { GhostFrame },
    _recordStart: number,
    _playbackData: GhostData?,
    _ghostModel: Model?,
    _playbackTime: number,
    _recordConn: RBXScriptConnection?,
    _playConn: RBXScriptConnection?,
    _targetPart: BasePart?,
    _tickRate: number,
    _tickAccum: number,
}

export type GhostType = typeof(setmetatable({} :: GhostImpl, GhostReplay))

function GhostReplay.new(tickRate: number?): GhostType
    local self = setmetatable({} :: GhostImpl, GhostReplay)
    self._isRecording = false
    self._isPlaying = false
    self._recordFrames = {}
    self._recordStart = 0
    self._playbackData = nil
    self._ghostModel = nil
    self._playbackTime = 0
    self._recordConn = nil
    self._playConn = nil
    self._targetPart = nil
    self._tickRate = tickRate or 20
    self._tickAccum = 0
    return self
end

function GhostReplay.StartRecording(self: GhostType, targetPart: BasePart): ()
    if self._isRecording then return end
    self._isRecording = true
    self._recordFrames = {}
    self._recordStart = tick()
    self._targetPart = targetPart
    self._tickAccum = 0

    self._recordConn = RunService.Heartbeat:Connect(function(dt)
        self._tickAccum += dt
        local interval = 1.0 / self._tickRate
        if self._tickAccum >= interval then
            self._tickAccum -= interval
            if self._targetPart and self._targetPart.Parent then
                table.insert(self._recordFrames, {
                    timestamp = tick() - self._recordStart,
                    position = self._targetPart.Position,
                    rotation = self._targetPart.CFrame,
                })
            end
        end
    end)
end

function GhostReplay.StopRecording(self: GhostType, playerName: string?, playerId: number?): GhostData?
    if not self._isRecording then return nil end
    self._isRecording = false
    if self._recordConn then
        self._recordConn:Disconnect()
        self._recordConn = nil
    end

    if #self._recordFrames == 0 then return nil end

    local data: GhostData = {
        playerId = playerId or 0,
        playerName = playerName or "Ghost",
        totalTime = self._recordFrames[#self._recordFrames].timestamp,
        frames = self._recordFrames,
    }
    return data
end

function GhostReplay.PlayGhost(self: GhostType, data: GhostData, ghostTemplate: Model?): ()
    if self._isPlaying then self:StopPlayback() end
    self._playbackData = data
    self._playbackTime = 0
    self._isPlaying = true

    -- Create ghost model
    if ghostTemplate then
        self._ghostModel = ghostTemplate:Clone()
    else
        self._ghostModel = self:_createDefaultGhost()
    end

    if self._ghostModel then
        self._ghostModel.Name = "Ghost_" .. data.playerName
        self._ghostModel.Parent = workspace
    end

    self._playConn = RunService.RenderStepped:Connect(function(dt)
        self._playbackTime += dt
        self:_updateGhostPosition()

        if self._playbackData and self._playbackTime >= self._playbackData.totalTime then
            self:StopPlayback()
        end
    end)
end

function GhostReplay._updateGhostPosition(self: GhostType): ()
    local data = self._playbackData
    local model = self._ghostModel
    if not data or not model or not model.PrimaryPart then return end

    -- Find surrounding frames for interpolation
    local frameA: GhostFrame? = nil
    local frameB: GhostFrame? = nil

    for i, frame in data.frames do
        if frame.timestamp <= self._playbackTime then
            frameA = frame
            if i < #data.frames then
                frameB = data.frames[i + 1]
            end
        else
            break
        end
    end

    if not frameA then return end

    local targetCF: CFrame
    if frameB then
        local span = frameB.timestamp - frameA.timestamp
        local alpha = if span > 0 then (self._playbackTime - frameA.timestamp) / span else 0
        targetCF = frameA.rotation:Lerp(frameB.rotation, alpha)
    else
        targetCF = frameA.rotation
    end

    model:PivotTo(targetCF)
end

function GhostReplay._createDefaultGhost(self: GhostType): Model
    local model = Instance.new("Model")
    local body = Instance.new("Part")
    body.Name = "HumanoidRootPart"
    body.Size = Vector3.new(4, 2, 6)
    body.Anchored = true
    body.CanCollide = false
    body.Transparency = 0.6
    body.Color = Color3.fromRGB(0, 200, 255)
    body.Material = Enum.Material.ForceField
    body.Parent = model
    model.PrimaryPart = body

    local billboard = Instance.new("BillboardGui")
    billboard.Size = UDim2.new(0, 120, 0, 30)
    billboard.StudsOffset = Vector3.new(0, 3, 0)
    billboard.AlwaysOnTop = true
    billboard.Parent = body

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.TextColor3 = Color3.fromRGB(0, 200, 255)
    label.TextStrokeTransparency = 0.5
    label.Font = Enum.Font.GothamBold
    label.TextSize = 14
    label.Text = "GHOST"
    label.Parent = billboard

    return model
end

function GhostReplay.StopPlayback(self: GhostType): ()
    self._isPlaying = false
    if self._playConn then
        self._playConn:Disconnect()
        self._playConn = nil
    end
    if self._ghostModel then
        self._ghostModel:Destroy()
        self._ghostModel = nil
    end
end

function GhostReplay.Destroy(self: GhostType): ()
    self:StopPlayback()
    if self._recordConn then
        self._recordConn:Disconnect()
    end
end

return GhostReplay
```

---

## 4. RaceHUD (Client)

Displays real-time race information: position, lap counter, timer, and split times.

```luau
--!strict
-- RaceHUD.lua (StarterPlayerScripts)

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local RaceHUD = {}
RaceHUD.__index = RaceHUD

type HUDImpl = {
    _screenGui: ScreenGui?,
    _positionLabel: TextLabel?,
    _lapLabel: TextLabel?,
    _timerLabel: TextLabel?,
    _splitLabel: TextLabel?,
    _countdownLabel: TextLabel?,
}

export type HUDType = typeof(setmetatable({} :: HUDImpl, RaceHUD))

function RaceHUD.new(): HUDType
    local self = setmetatable({} :: HUDImpl, RaceHUD)
    self:_buildUI()
    return self
end

function RaceHUD._buildUI(self: HUDType): ()
    local player = Players.LocalPlayer
    if not player then return end
    local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

    local gui = Instance.new("ScreenGui")
    gui.Name = "RaceHUD"
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 50
    gui.IgnoreGuiInset = true
    gui.Parent = playerGui
    self._screenGui = gui

    -- Position indicator (top-left)
    local posFrame = Instance.new("Frame")
    posFrame.Name = "PositionFrame"
    posFrame.Position = UDim2.new(0, 20, 0, 20)
    posFrame.Size = UDim2.new(0, 120, 0, 80)
    posFrame.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
    posFrame.BackgroundTransparency = 0.3
    posFrame.Parent = gui

    local posCorner = Instance.new("UICorner")
    posCorner.CornerRadius = UDim.new(0, 12)
    posCorner.Parent = posFrame

    local posLabel = Instance.new("TextLabel")
    posLabel.Name = "Position"
    posLabel.Size = UDim2.new(1, 0, 1, 0)
    posLabel.BackgroundTransparency = 1
    posLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
    posLabel.Font = Enum.Font.GothamBold
    posLabel.TextSize = 48
    posLabel.Text = "1st"
    posLabel.Parent = posFrame
    self._positionLabel = posLabel

    -- Lap counter (top-center)
    local lapLabel = Instance.new("TextLabel")
    lapLabel.Name = "Lap"
    lapLabel.AnchorPoint = Vector2.new(0.5, 0)
    lapLabel.Position = UDim2.new(0.5, 0, 0, 20)
    lapLabel.Size = UDim2.new(0, 200, 0, 40)
    lapLabel.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
    lapLabel.BackgroundTransparency = 0.3
    lapLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    lapLabel.Font = Enum.Font.GothamBold
    lapLabel.TextSize = 24
    lapLabel.Text = "Lap 1 / 3"
    lapLabel.Parent = gui

    local lapCorner = Instance.new("UICorner")
    lapCorner.CornerRadius = UDim.new(0, 8)
    lapCorner.Parent = lapLabel
    self._lapLabel = lapLabel

    -- Timer (top-right)
    local timerLabel = Instance.new("TextLabel")
    timerLabel.Name = "Timer"
    timerLabel.AnchorPoint = Vector2.new(1, 0)
    timerLabel.Position = UDim2.new(1, -20, 0, 20)
    timerLabel.Size = UDim2.new(0, 200, 0, 50)
    timerLabel.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
    timerLabel.BackgroundTransparency = 0.3
    timerLabel.TextColor3 = Color3.fromRGB(0, 255, 100)
    timerLabel.Font = Enum.Font.Code
    timerLabel.TextSize = 32
    timerLabel.Text = "00:00.000"
    timerLabel.Parent = gui

    local timerCorner = Instance.new("UICorner")
    timerCorner.CornerRadius = UDim.new(0, 8)
    timerCorner.Parent = timerLabel
    self._timerLabel = timerLabel

    -- Split time (below timer, fades out)
    local splitLabel = Instance.new("TextLabel")
    splitLabel.Name = "Split"
    splitLabel.AnchorPoint = Vector2.new(1, 0)
    splitLabel.Position = UDim2.new(1, -20, 0, 75)
    splitLabel.Size = UDim2.new(0, 200, 0, 30)
    splitLabel.BackgroundTransparency = 1
    splitLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
    splitLabel.Font = Enum.Font.GothamMedium
    splitLabel.TextSize = 18
    splitLabel.TextTransparency = 1
    splitLabel.Text = ""
    splitLabel.Parent = gui
    self._splitLabel = splitLabel

    -- Countdown label (center, hidden by default)
    local cdLabel = Instance.new("TextLabel")
    cdLabel.Name = "Countdown"
    cdLabel.AnchorPoint = Vector2.new(0.5, 0.5)
    cdLabel.Position = UDim2.new(0.5, 0, 0.4, 0)
    cdLabel.Size = UDim2.new(0, 300, 0, 200)
    cdLabel.BackgroundTransparency = 1
    cdLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    cdLabel.Font = Enum.Font.GothamBold
    cdLabel.TextSize = 120
    cdLabel.TextTransparency = 1
    cdLabel.TextStrokeTransparency = 0.5
    cdLabel.Text = ""
    cdLabel.Parent = gui
    self._countdownLabel = cdLabel
end

function RaceHUD.UpdatePosition(self: HUDType, position: number, totalRacers: number): ()
    if not self._positionLabel then return end
    local suffix = "th"
    if position == 1 then suffix = "st"
    elseif position == 2 then suffix = "nd"
    elseif position == 3 then suffix = "rd" end

    self._positionLabel.Text = tostring(position) .. suffix

    -- Color based on position
    if position == 1 then
        self._positionLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
    elseif position == 2 then
        self._positionLabel.TextColor3 = Color3.fromRGB(192, 192, 192)
    elseif position == 3 then
        self._positionLabel.TextColor3 = Color3.fromRGB(205, 127, 50)
    else
        self._positionLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    end
end

function RaceHUD.UpdateLap(self: HUDType, currentLap: number, totalLaps: number): ()
    if not self._lapLabel then return end
    self._lapLabel.Text = string.format("Lap %d / %d", math.min(currentLap + 1, totalLaps), totalLaps)
end

function RaceHUD.UpdateTimer(self: HUDType, seconds: number): ()
    if not self._timerLabel then return end
    self._timerLabel.Text = self:_formatTime(seconds)
end

function RaceHUD.ShowSplit(self: HUDType, splitTime: number, bestSplit: number?): ()
    if not self._splitLabel then return end

    if bestSplit then
        local diff = splitTime - bestSplit
        if diff <= 0 then
            self._splitLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
            self._splitLabel.Text = string.format("-%s", self:_formatTime(math.abs(diff)))
        else
            self._splitLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
            self._splitLabel.Text = string.format("+%s", self:_formatTime(diff))
        end
    else
        self._splitLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
        self._splitLabel.Text = self:_formatTime(splitTime)
    end

    self._splitLabel.TextTransparency = 0
    task.delay(2, function()
        if self._splitLabel then
            local fade = TweenService:Create(self._splitLabel, TweenInfo.new(0.5), { TextTransparency = 1 })
            fade:Play()
        end
    end)
end

function RaceHUD.ShowCountdown(self: HUDType, number: number): ()
    if not self._countdownLabel then return end
    local label = self._countdownLabel

    label.Text = if number > 0 then tostring(number) else "GO!"
    label.TextColor3 = if number > 0
        then Color3.fromRGB(255, 255, 255)
        else Color3.fromRGB(0, 255, 100)
    label.TextTransparency = 0
    label.TextSize = 80

    -- Scale up and fade
    local tween = TweenService:Create(label, TweenInfo.new(0.8, Enum.EasingStyle.Back), {
        TextSize = 140,
        TextTransparency = 1,
    })
    tween:Play()
end

function RaceHUD._formatTime(self: HUDType, seconds: number): string
    local mins = math.floor(seconds / 60)
    local secs = math.floor(seconds % 60)
    local ms = math.floor((seconds % 1) * 1000)
    return string.format("%02d:%02d.%03d", mins, secs, ms)
end

function RaceHUD.SetVisible(self: HUDType, visible: boolean): ()
    if self._screenGui then
        self._screenGui.Enabled = visible
    end
end

function RaceHUD.Destroy(self: HUDType): ()
    if self._screenGui then self._screenGui:Destroy() end
end

return RaceHUD
```

---

## Usage Example

```luau
-- Server setup
local RaceManager = require(ServerScriptService.RaceManager)

local checkpoints = {}
for i, cp in workspace.Track.Checkpoints:GetChildren() do
    table.insert(checkpoints, {
        index = i,
        part = cp,
        position = cp.Position,
        isFinishLine = (i == 1),
    })
end
table.sort(checkpoints, function(a, b) return a.index < b.index end)

local race = RaceManager.new({
    trackName = "Desert Circuit",
    totalLaps = 3,
    maxRacers = 8,
    countdownDuration = 3,
    checkpoints = checkpoints,
    dnfTimeout = 300,
})

-- Add all players and start
for _, player in Players:GetPlayers() do
    race:AddRacer(player)
end
race:StartCountdown()

-- Client: Ghost replay
local GhostReplay = require(script.GhostReplay)
local ghost = GhostReplay.new(30)

-- Record during the race
ghost:StartRecording(localPlayer.Character.HumanoidRootPart)
-- ... after race ...
local ghostData = ghost:StopRecording(localPlayer.DisplayName, localPlayer.UserId)

-- Play the ghost on next race
if ghostData then
    ghost:PlayGhost(ghostData)
end
```

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

When using this skill, provide:

- `$TRACK_NAME` - Name of the race track.
- `$TOTAL_LAPS` - Number of laps for the race (default: 3).
- `$MAX_RACERS` - Maximum number of racers (default: 8).
- `$CHECKPOINT_FOLDER` - Path to the folder containing checkpoint parts in workspace.
- `$VEHICLE_TYPE` - Type of vehicle: "Car", "Kart", "Foot" (running race), "Boat".
- `$ENABLE_GHOST` - Whether to enable ghost replay: "true" or "false".
- `$DNF_TIMEOUT` - Seconds before a racer is marked DNF (default: 300).
- `$COUNTDOWN_DURATION` - Countdown duration in seconds (default: 3).
