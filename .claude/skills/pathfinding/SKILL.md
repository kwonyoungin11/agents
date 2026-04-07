---
name: pathfinding
description: |
  Roblox PathfindingService 심화 - Agent parameters, waypoint handling, jump/climb, dynamic obstacles, path visualization.
  로블록스 길찾기, 경로 탐색, 에이전트 파라미터, 웨이포인트, 점프, 등반, 동적 장애물, 경로 시각화.
  Deep dive into Roblox PathfindingService with advanced agent config, obstacle avoidance, and debug visualization.
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Grep
  - Glob
effort: high
---

# Roblox PathfindingService Deep Dive

Advanced pathfinding framework built on top of `PathfindingService`. Covers agent parameter tuning, waypoint-by-waypoint traversal with jump/climb handling, dynamic obstacle re-pathing, path cost modifiers, and real-time debug visualization.

---

## Architecture Overview

```
PathfindingSystem
  ├── AgentConfig              -- Agent size, jump/climb capabilities, cost tables
  ├── PathNavigator            -- Core navigation loop with waypoint traversal
  ├── ObstacleDetector         -- Raycasts for dynamic obstacle detection & re-path
  ├── PathCostModifier         -- Assigns material/region costs via PathfindingModifier
  └── PathVisualizer           -- Debug beam/sphere rendering of computed paths
```

---

## 1. AgentConfig

Defines agent parameters that control how PathfindingService computes paths.

```luau
--!strict
-- AgentConfig.lua (ReplicatedStorage/Shared)

export type AgentParams = {
    AgentRadius: number,         -- How wide the agent is (studs)
    AgentHeight: number,         -- How tall the agent is (studs)
    AgentCanJump: boolean,       -- Whether the agent can jump over gaps
    AgentCanClimb: boolean,      -- Whether the agent can climb TrussParts
    WaypointSpacing: number,     -- Distance between waypoints (studs)
    Costs: { [string]: number }?, -- Material/label cost overrides
}

local PRESETS: { [string]: AgentParams } = {
    -- Standard humanoid NPC
    Humanoid = {
        AgentRadius = 2,
        AgentHeight = 5,
        AgentCanJump = true,
        AgentCanClimb = true,
        WaypointSpacing = 4,
        Costs = {
            Water = 20,       -- Avoid water
            Mud = 8,          -- Mud is slow
            DangerZone = math.huge,  -- Impassable labeled regions
        },
    },
    -- Large creature or vehicle
    Large = {
        AgentRadius = 4,
        AgentHeight = 8,
        AgentCanJump = false,
        AgentCanClimb = false,
        WaypointSpacing = 6,
        Costs = {
            Water = math.huge,
        },
    },
    -- Small pet or drone
    Small = {
        AgentRadius = 1,
        AgentHeight = 2,
        AgentCanJump = true,
        AgentCanClimb = true,
        WaypointSpacing = 2,
    },
    -- Flying agent (treats all surfaces equally)
    Flying = {
        AgentRadius = 2,
        AgentHeight = 3,
        AgentCanJump = true,
        AgentCanClimb = true,
        WaypointSpacing = 8,
    },
}

local AgentConfig = {}

function AgentConfig.GetPreset(name: string): AgentParams?
    return PRESETS[name]
end

function AgentConfig.Custom(overrides: AgentParams): AgentParams
    return {
        AgentRadius = overrides.AgentRadius or 2,
        AgentHeight = overrides.AgentHeight or 5,
        AgentCanJump = if overrides.AgentCanJump ~= nil then overrides.AgentCanJump else true,
        AgentCanClimb = if overrides.AgentCanClimb ~= nil then overrides.AgentCanClimb else false,
        WaypointSpacing = overrides.WaypointSpacing or 4,
        Costs = overrides.Costs,
    }
end

function AgentConfig.GetPresetNames(): { string }
    local names = {}
    for name in PRESETS do
        table.insert(names, name)
    end
    return names
end

return AgentConfig
```

---

## 2. PathNavigator

Core navigation module. Computes a path, then walks the agent through each waypoint, handling jumps and climbs at the appropriate action waypoints.

```luau
--!strict
-- PathNavigator.lua (ServerScriptService or per-NPC module)

local PathfindingService = game:GetService("PathfindingService")
local RunService = game:GetService("RunService")

export type AgentParams = {
    AgentRadius: number,
    AgentHeight: number,
    AgentCanJump: boolean,
    AgentCanClimb: boolean,
    WaypointSpacing: number,
    Costs: { [string]: number }?,
}

export type NavigationState = "Idle" | "Computing" | "Moving" | "Stuck" | "Arrived" | "Failed"

local PathNavigator = {}
PathNavigator.__index = PathNavigator

type NavigatorImpl = {
    _humanoid: Humanoid,
    _rootPart: BasePart,
    _agentParams: AgentParams,
    _path: Path?,
    _waypoints: { PathWaypoint },
    _currentWaypointIndex: number,
    _state: NavigationState,
    _blockedConn: RBXScriptConnection?,
    _moveConn: RBXScriptConnection?,
    _stuckTimer: number,
    _stuckThreshold: number,
    _lastPosition: Vector3,
    _retryCount: number,
    _maxRetries: number,
    _onStateChanged: BindableEvent,
    _onWaypointReached: BindableEvent,
    _onArrived: BindableEvent,
    _visualizer: any?,
}

export type NavigatorType = typeof(setmetatable({} :: NavigatorImpl, PathNavigator))

function PathNavigator.new(humanoid: Humanoid, rootPart: BasePart, agentParams: AgentParams): NavigatorType
    local self = setmetatable({} :: NavigatorImpl, PathNavigator)
    self._humanoid = humanoid
    self._rootPart = rootPart
    self._agentParams = agentParams
    self._path = nil
    self._waypoints = {}
    self._currentWaypointIndex = 0
    self._state = "Idle"
    self._blockedConn = nil
    self._moveConn = nil
    self._stuckTimer = 0
    self._stuckThreshold = 3.0  -- seconds before considering stuck
    self._lastPosition = rootPart.Position
    self._retryCount = 0
    self._maxRetries = 3
    self._onStateChanged = Instance.new("BindableEvent")
    self._onWaypointReached = Instance.new("BindableEvent")
    self._onArrived = Instance.new("BindableEvent")
    self._visualizer = nil
    return self
end

function PathNavigator.NavigateTo(self: NavigatorType, target: Vector3): ()
    self:Stop()
    self:_setState("Computing")
    self._retryCount = 0

    self:_computeAndFollow(target)
end

function PathNavigator._computeAndFollow(self: NavigatorType, target: Vector3): ()
    -- Create path with agent parameters
    local path = PathfindingService:CreatePath({
        AgentRadius = self._agentParams.AgentRadius,
        AgentHeight = self._agentParams.AgentHeight,
        AgentCanJump = self._agentParams.AgentCanJump,
        AgentCanClimb = self._agentParams.AgentCanClimb,
        WaypointSpacing = self._agentParams.WaypointSpacing,
        Costs = self._agentParams.Costs,
    })

    local success, errorMessage = pcall(function()
        path:ComputeAsync(self._rootPart.Position, target)
    end)

    if not success then
        warn("[PathNavigator] ComputeAsync failed: " .. tostring(errorMessage))
        self:_setState("Failed")
        return
    end

    if path.Status == Enum.PathStatus.NoPath then
        warn("[PathNavigator] No path found to target")
        self:_setState("Failed")
        return
    end

    self._path = path
    self._waypoints = path:GetWaypoints()
    self._currentWaypointIndex = 1

    -- Visualize if visualizer is attached
    if self._visualizer then
        self._visualizer:DrawPath(self._waypoints)
    end

    -- Listen for path blocked
    self._blockedConn = path.Blocked:Connect(function(blockedWaypointIndex)
        if blockedWaypointIndex >= self._currentWaypointIndex then
            -- Re-compute path
            self:_handleBlocked(target)
        end
    end)

    self:_setState("Moving")
    self:_followNextWaypoint(target)
end

function PathNavigator._followNextWaypoint(self: NavigatorType, finalTarget: Vector3): ()
    if self._currentWaypointIndex > #self._waypoints then
        self:_setState("Arrived")
        self._onArrived:Fire()
        self:_cleanup()
        return
    end

    local waypoint = self._waypoints[self._currentWaypointIndex]

    -- Handle special waypoint actions
    if waypoint.Action == Enum.PathWaypointAction.Jump then
        self._humanoid.Jump = true
        -- Small delay to let jump initiate
        task.wait(0.1)
    elseif waypoint.Action == Enum.PathWaypointAction.Custom then
        -- Custom actions (e.g., climb) - identified by label
        if waypoint.Label == "Climb" then
            -- The humanoid will automatically climb TrussParts
            -- but we ensure the state is correct
            self._humanoid:ChangeState(Enum.HumanoidStateType.Climbing)
        end
    end

    -- Move to waypoint
    self._humanoid:MoveTo(waypoint.Position)
    self._lastPosition = self._rootPart.Position
    self._stuckTimer = 0

    local reached = false

    -- Stuck detection via heartbeat
    self._moveConn = RunService.Heartbeat:Connect(function(dt)
        if self._state ~= "Moving" then return end

        local currentPos = self._rootPart.Position
        local moved = (currentPos - self._lastPosition).Magnitude

        if moved < 0.1 then
            self._stuckTimer += dt
        else
            self._stuckTimer = 0
            self._lastPosition = currentPos
        end

        if self._stuckTimer >= self._stuckThreshold then
            self:_handleStuck(finalTarget)
        end
    end)

    -- Wait for MoveToFinished
    local moveFinished = self._humanoid.MoveToFinished:Wait()

    if self._moveConn then
        self._moveConn:Disconnect()
        self._moveConn = nil
    end

    if not moveFinished then
        -- Timed out (8 second Roblox default)
        self:_handleStuck(finalTarget)
        return
    end

    self._onWaypointReached:Fire(self._currentWaypointIndex, waypoint)

    if self._visualizer then
        self._visualizer:MarkWaypointReached(self._currentWaypointIndex)
    end

    self._currentWaypointIndex += 1
    self:_followNextWaypoint(finalTarget)
end

function PathNavigator._handleBlocked(self: NavigatorType, target: Vector3): ()
    self._retryCount += 1
    if self._retryCount > self._maxRetries then
        self:_setState("Failed")
        self:_cleanup()
        return
    end

    self:_cleanup()
    self:_setState("Computing")
    task.wait(0.2)  -- Brief delay before re-computing
    self:_computeAndFollow(target)
end

function PathNavigator._handleStuck(self: NavigatorType, target: Vector3): ()
    self:_setState("Stuck")
    self._retryCount += 1

    if self._retryCount > self._maxRetries then
        self:_setState("Failed")
        self:_cleanup()
        return
    end

    -- Try jumping to unstick
    self._humanoid.Jump = true
    task.wait(0.5)

    self:_cleanup()
    self:_setState("Computing")
    self:_computeAndFollow(target)
end

function PathNavigator._setState(self: NavigatorType, state: NavigationState): ()
    if self._state == state then return end
    self._state = state
    self._onStateChanged:Fire(state)
end

function PathNavigator._cleanup(self: NavigatorType): ()
    if self._blockedConn then
        self._blockedConn:Disconnect()
        self._blockedConn = nil
    end
    if self._moveConn then
        self._moveConn:Disconnect()
        self._moveConn = nil
    end
end

function PathNavigator.Stop(self: NavigatorType): ()
    self:_cleanup()
    self._humanoid:MoveTo(self._rootPart.Position)  -- Stop moving
    self:_setState("Idle")
end

function PathNavigator.GetState(self: NavigatorType): NavigationState
    return self._state
end

function PathNavigator.SetVisualizer(self: NavigatorType, visualizer: any): ()
    self._visualizer = visualizer
end

function PathNavigator.OnStateChanged(self: NavigatorType): RBXScriptSignal
    return self._onStateChanged.Event
end

function PathNavigator.OnWaypointReached(self: NavigatorType): RBXScriptSignal
    return self._onWaypointReached.Event
end

function PathNavigator.OnArrived(self: NavigatorType): RBXScriptSignal
    return self._onArrived.Event
end

function PathNavigator.Destroy(self: NavigatorType): ()
    self:Stop()
    self._onStateChanged:Destroy()
    self._onWaypointReached:Destroy()
    self._onArrived:Destroy()
end

return PathNavigator
```

---

## 3. ObstacleDetector

Casts rays ahead of the agent to detect dynamic obstacles that PathfindingService might not account for (e.g., moving platforms, NPCs).

```luau
--!strict
-- ObstacleDetector.lua

local RunService = game:GetService("RunService")

local ObstacleDetector = {}
ObstacleDetector.__index = ObstacleDetector

type DetectorImpl = {
    _rootPart: BasePart,
    _agentRadius: number,
    _detectionRange: number,
    _rayCount: number,
    _connection: RBXScriptConnection?,
    _onObstacleDetected: BindableEvent,
    _ignoreList: { Instance },
    _lastDetected: BasePart?,
}

export type DetectorType = typeof(setmetatable({} :: DetectorImpl, ObstacleDetector))

function ObstacleDetector.new(rootPart: BasePart, agentRadius: number, detectionRange: number?): DetectorType
    local self = setmetatable({} :: DetectorImpl, ObstacleDetector)
    self._rootPart = rootPart
    self._agentRadius = agentRadius
    self._detectionRange = detectionRange or 10
    self._rayCount = 5          -- Fan of rays
    self._connection = nil
    self._onObstacleDetected = Instance.new("BindableEvent")
    self._ignoreList = { rootPart.Parent :: Instance }
    self._lastDetected = nil
    return self
end

function ObstacleDetector.Start(self: DetectorType): ()
    if self._connection then return end

    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    rayParams.FilterDescendantsInstances = self._ignoreList

    self._connection = RunService.Heartbeat:Connect(function()
        local origin = self._rootPart.Position
        local lookDir = self._rootPart.CFrame.LookVector
        local detected = false

        -- Cast a fan of rays
        for i = 0, self._rayCount - 1 do
            local angle = math.rad(-30 + (60 / math.max(self._rayCount - 1, 1)) * i)
            local direction = (CFrame.fromAxisAngle(Vector3.yAxis, angle) * CFrame.new(lookDir * self._detectionRange)).Position

            local result = workspace:Raycast(origin, direction, rayParams)
            if result and result.Instance then
                -- Check if it's a dynamic object (not anchored)
                local part = result.Instance
                if part:IsA("BasePart") and not part.Anchored then
                    if self._lastDetected ~= part then
                        self._lastDetected = part
                        self._onObstacleDetected:Fire(part, result.Position, result.Distance)
                    end
                    detected = true
                    break
                end
            end
        end

        if not detected then
            self._lastDetected = nil
        end
    end)
end

function ObstacleDetector.Stop(self: DetectorType): ()
    if self._connection then
        self._connection:Disconnect()
        self._connection = nil
    end
end

function ObstacleDetector.AddToIgnoreList(self: DetectorType, instance: Instance): ()
    table.insert(self._ignoreList, instance)
end

function ObstacleDetector.OnObstacleDetected(self: DetectorType): RBXScriptSignal
    return self._onObstacleDetected.Event
end

function ObstacleDetector.Destroy(self: DetectorType): ()
    self:Stop()
    self._onObstacleDetected:Destroy()
end

return ObstacleDetector
```

---

## 4. PathCostModifier

Utility for placing `PathfindingModifier` instances on parts to influence path costs.

```luau
--!strict
-- PathCostModifier.lua

local CollectionService = game:GetService("CollectionService")

local PathCostModifier = {}

-- Apply a PathfindingModifier to a part with a specific label
function PathCostModifier.SetLabel(part: BasePart, label: string): PathfindingModifier
    -- Remove existing modifier if any
    local existing = part:FindFirstChildOfClass("PathfindingModifier")
    if existing then
        existing:Destroy()
    end

    local modifier = Instance.new("PathfindingModifier")
    modifier.Label = label
    modifier.Parent = part
    return modifier
end

-- Make a part completely non-traversable
function PathCostModifier.SetPassthrough(part: BasePart, passthrough: boolean): PathfindingModifier
    local existing = part:FindFirstChildOfClass("PathfindingModifier")
    if existing then
        existing:Destroy()
    end

    local modifier = Instance.new("PathfindingModifier")
    modifier.PassThrough = passthrough
    modifier.Parent = part
    return modifier
end

-- Apply labels to all parts with a CollectionService tag
function PathCostModifier.TagToLabel(tag: string, label: string): ()
    for _, obj in CollectionService:GetTagged(tag) do
        if obj:IsA("BasePart") then
            PathCostModifier.SetLabel(obj, label)
        end
    end

    CollectionService:GetInstanceAddedSignal(tag):Connect(function(obj)
        if obj:IsA("BasePart") then
            PathCostModifier.SetLabel(obj, label)
        end
    end)
end

-- Create a PathfindingLink between two attachment points
function PathCostModifier.CreateLink(
    attachmentA: Attachment,
    attachmentB: Attachment,
    label: string,
    isBidirectional: boolean?
): PathfindingLink
    local link = Instance.new("PathfindingLink")
    link.Attachment0 = attachmentA
    link.Attachment1 = attachmentB
    link.Label = label
    link.IsBidirectional = if isBidirectional ~= nil then isBidirectional else true
    link.Parent = workspace
    return link
end

return PathCostModifier
```

---

## 5. PathVisualizer

Debug tool that renders the computed path as colored spheres and beams. Green = normal waypoint, yellow = jump, blue = climb, red = current target.

```luau
--!strict
-- PathVisualizer.lua

local Debris = game:GetService("Debris")

local PathVisualizer = {}
PathVisualizer.__index = PathVisualizer

type VisualizerImpl = {
    _folder: Folder,
    _spheres: { BasePart },
    _beams: { Beam },
    _enabled: boolean,
    _sphereSize: number,
    _lifetime: number,
}

export type VisualizerType = typeof(setmetatable({} :: VisualizerImpl, PathVisualizer))

local ACTION_COLORS = {
    [Enum.PathWaypointAction.Walk] = Color3.fromRGB(0, 200, 0),
    [Enum.PathWaypointAction.Jump] = Color3.fromRGB(255, 200, 0),
    [Enum.PathWaypointAction.Custom] = Color3.fromRGB(0, 150, 255),
}

function PathVisualizer.new(enabled: boolean?): VisualizerType
    local self = setmetatable({} :: VisualizerImpl, PathVisualizer)
    self._folder = Instance.new("Folder")
    self._folder.Name = "PathVisualization"
    self._folder.Parent = workspace
    self._spheres = {}
    self._beams = {}
    self._enabled = if enabled ~= nil then enabled else true
    self._sphereSize = 0.8
    self._lifetime = 10  -- Auto-cleanup after N seconds
    return self
end

function PathVisualizer.DrawPath(self: VisualizerType, waypoints: { PathWaypoint }): ()
    if not self._enabled then return end
    self:Clear()

    local prevAttachment: Attachment? = nil

    for i, waypoint in waypoints do
        local color = ACTION_COLORS[waypoint.Action] or Color3.fromRGB(200, 200, 200)

        -- Create sphere at waypoint
        local sphere = Instance.new("Part")
        sphere.Name = "WP_" .. tostring(i)
        sphere.Shape = Enum.PartType.Ball
        sphere.Size = Vector3.new(self._sphereSize, self._sphereSize, self._sphereSize)
        sphere.Position = waypoint.Position
        sphere.Anchored = true
        sphere.CanCollide = false
        sphere.CanQuery = false
        sphere.CanTouch = false
        sphere.Color = color
        sphere.Material = Enum.Material.Neon
        sphere.Transparency = 0.3
        sphere.Parent = self._folder

        table.insert(self._spheres, sphere)

        -- Create beam between consecutive waypoints
        local attachment = Instance.new("Attachment")
        attachment.WorldPosition = waypoint.Position
        attachment.Parent = workspace.Terrain

        if prevAttachment then
            local beam = Instance.new("Beam")
            beam.Attachment0 = prevAttachment
            beam.Attachment1 = attachment
            beam.Width0 = 0.3
            beam.Width1 = 0.3
            beam.Color = ColorSequence.new(color)
            beam.Transparency = NumberSequence.new(0.4)
            beam.FaceCamera = true
            beam.Parent = self._folder
            table.insert(self._beams, beam)
        end

        prevAttachment = attachment

        -- Label for action type
        if waypoint.Action ~= Enum.PathWaypointAction.Walk then
            local billboard = Instance.new("BillboardGui")
            billboard.Size = UDim2.new(0, 80, 0, 25)
            billboard.StudsOffset = Vector3.new(0, 1.5, 0)
            billboard.AlwaysOnTop = true
            billboard.Parent = sphere

            local label = Instance.new("TextLabel")
            label.Size = UDim2.new(1, 0, 1, 0)
            label.BackgroundTransparency = 1
            label.TextColor3 = color
            label.Font = Enum.Font.GothamBold
            label.TextSize = 12
            label.TextStrokeTransparency = 0.5
            label.Text = if waypoint.Action == Enum.PathWaypointAction.Jump then "JUMP"
                elseif waypoint.Label then waypoint.Label
                else "CUSTOM"
            label.Parent = billboard
        end
    end

    -- Auto-cleanup
    Debris:AddItem(self._folder, self._lifetime)
    -- Re-create folder for next path
    task.delay(self._lifetime, function()
        self._folder = Instance.new("Folder")
        self._folder.Name = "PathVisualization"
        self._folder.Parent = workspace
    end)
end

function PathVisualizer.MarkWaypointReached(self: VisualizerType, index: number): ()
    if not self._enabled then return end
    local sphere = self._spheres[index]
    if sphere and sphere.Parent then
        sphere.Color = Color3.fromRGB(100, 100, 100)
        sphere.Transparency = 0.7
        sphere.Size = Vector3.new(0.4, 0.4, 0.4)
    end
end

function PathVisualizer.HighlightCurrent(self: VisualizerType, index: number): ()
    if not self._enabled then return end
    local sphere = self._spheres[index]
    if sphere and sphere.Parent then
        sphere.Color = Color3.fromRGB(255, 50, 50)
        sphere.Size = Vector3.new(1.2, 1.2, 1.2)
    end
end

function PathVisualizer.Clear(self: VisualizerType): ()
    self._folder:ClearAllChildren()
    table.clear(self._spheres)
    table.clear(self._beams)
end

function PathVisualizer.SetEnabled(self: VisualizerType, enabled: boolean): ()
    self._enabled = enabled
    if not enabled then self:Clear() end
end

function PathVisualizer.Destroy(self: VisualizerType): ()
    self._folder:Destroy()
end

return PathVisualizer
```

---

## Usage Example

```luau
local AgentConfig = require(ReplicatedStorage.AgentConfig)
local PathNavigator = require(ServerScriptService.PathNavigator)
local ObstacleDetector = require(ServerScriptService.ObstacleDetector)
local PathCostModifier = require(ServerScriptService.PathCostModifier)
local PathVisualizer = require(ServerScriptService.PathVisualizer)

-- Setup cost modifiers on the map
PathCostModifier.TagToLabel("Water", "Water")
PathCostModifier.TagToLabel("LavaZone", "DangerZone")

-- Create an NPC navigator
local npc = workspace.NPC
local humanoid = npc:FindFirstChildOfClass("Humanoid")
local rootPart = npc:FindFirstChild("HumanoidRootPart") :: BasePart

local agentParams = AgentConfig.GetPreset("Humanoid")
local navigator = PathNavigator.new(humanoid, rootPart, agentParams)
local visualizer = PathVisualizer.new(true)
navigator:SetVisualizer(visualizer)

-- Obstacle detection with re-pathing
local detector = ObstacleDetector.new(rootPart, agentParams.AgentRadius)
detector:Start()
detector:OnObstacleDetected():Connect(function(part, position, distance)
    if distance < 5 then
        -- Force re-path
        navigator:NavigateTo(workspace.Target.Position)
    end
end)

-- Navigate to target
navigator:NavigateTo(workspace.Target.Position)

navigator:OnStateChanged():Connect(function(state)
    print("NPC state:", state)
end)

navigator:OnArrived():Connect(function()
    print("NPC arrived at destination!")
end)
```

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

When using this skill, provide:

- `$AGENT_PRESET` - Agent preset name: "Humanoid", "Large", "Small", "Flying", or "Custom".
- `$AGENT_RADIUS` - Custom agent radius in studs (used with Custom preset).
- `$AGENT_HEIGHT` - Custom agent height in studs.
- `$CAN_JUMP` - Whether the agent can jump: "true" or "false".
- `$CAN_CLIMB` - Whether the agent can climb: "true" or "false".
- `$COST_TABLE` - JSON object mapping label names to cost values.
- `$ENABLE_VISUALIZATION` - Show debug path visualization: "true" or "false".
- `$STUCK_THRESHOLD` - Seconds before agent is considered stuck (default: 3).
- `$MAX_RETRIES` - Maximum re-path attempts on failure (default: 3).
