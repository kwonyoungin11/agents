---
name: puzzle-system
description: |
  Puzzle mechanics system for Roblox. Pressure plates, levers, combination locks,
  moving platforms, laser grids, timed sequences, logic gates, and puzzle state
  management with reset capability.
  키워드: 퍼즐 시스템, 압력판, 레버, 조합 잠금, 이동 플랫폼, 레이저, 타이머 퍼즐
allowed-tools:
  - Bash
  - Read
  - Edit
  - Write
  - Glob
  - Grep
effort: high
---

# Puzzle System

Comprehensive puzzle mechanics for Roblox: pressure plates, levers, combination locks, moving platforms, laser grids, timed sequences, and puzzle orchestration. All code is Luau.

---

## Architecture Overview

```
ReplicatedStorage/
  Shared/
    PuzzleConfig.luau         -- Puzzle element types, timing constants
ServerScriptService/
  Services/
    PuzzleService.luau        -- Server: puzzle state, signal routing, reset
StarterPlayerScripts/
  Controllers/
    PuzzleUI.luau             -- Client: hints, combination input, timer display
workspace/
  Puzzles/
    PuzzleRoom_01/            -- Tagged puzzle elements with attributes
```

---

## 1. Puzzle Configuration

```luau
-- ReplicatedStorage/Shared/PuzzleConfig.luau
--!strict

export type PuzzleElementType = "PressurePlate" | "Lever" | "CombinationLock" | "MovingPlatform" | "LaserGrid" | "TimedButton" | "Door" | "LogicGate"

export type SignalState = "On" | "Off" | "Pulse"

export type PuzzleElement = {
    elementType: PuzzleElementType,
    puzzleId: string,         -- which puzzle group this belongs to
    elementId: string,        -- unique within the puzzle
    outputSignal: string?,    -- signal name this element emits
    inputSignals: { string }?, -- signals this element listens to
    logicMode: string?,       -- "AND", "OR", "XOR" for LogicGate; "Toggle" or "Momentary" for others
}

local PuzzleConfig = {}

PuzzleConfig.PRESSURE_PLATE_DEBOUNCE = 0.3
PuzzleConfig.LEVER_COOLDOWN = 0.5
PuzzleConfig.TIMED_BUTTON_DURATION = 5.0
PuzzleConfig.COMBINATION_MAX_DIGITS = 6
PuzzleConfig.PLATFORM_SPEED = 8           -- studs per second
PuzzleConfig.LASER_DAMAGE = 10
PuzzleConfig.LASER_DAMAGE_INTERVAL = 0.5
PuzzleConfig.RESET_DELAY = 3.0            -- seconds after failure before auto-reset

PuzzleConfig.SIGNAL_COLORS: { [SignalState]: Color3 } = {
    On = Color3.fromRGB(0, 255, 0),
    Off = Color3.fromRGB(255, 0, 0),
    Pulse = Color3.fromRGB(255, 255, 0),
}

return PuzzleConfig
```

---

## 2. Server Puzzle Service

```luau
-- ServerScriptService/Services/PuzzleService.luau
--!strict

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local PuzzleConfig = require(ReplicatedStorage.Shared.PuzzleConfig)

local PuzzleService = {}

-- Signal state per puzzle: puzzleId -> signalName -> state
local signalStates: { [string]: { [string]: boolean } } = {}

-- Element instances indexed by puzzleId_elementId
local elementInstances: { [string]: BasePart | Model } = {}

-- Combination lock state: puzzleId_elementId -> entered digits
local combinationInputs: { [string]: { number } } = {}

-- Timed button expiry: puzzleId_elementId -> expiry tick
local timedExpiry: { [string]: number } = {}

-- Moving platform tweens
local activeTweens: { [string]: Tween } = {}

-------------------------------------------------
-- Signal System
-------------------------------------------------

local function getSignal(puzzleId: string, signalName: string): boolean
    if not signalStates[puzzleId] then return false end
    return signalStates[puzzleId][signalName] or false
end

local function setSignal(puzzleId: string, signalName: string, value: boolean)
    if not signalStates[puzzleId] then
        signalStates[puzzleId] = {}
    end
    local prev = signalStates[puzzleId][signalName]
    signalStates[puzzleId][signalName] = value

    if prev ~= value then
        -- Propagate to all listeners
        PuzzleService._EvaluateAllElements(puzzleId)
    end
end

-------------------------------------------------
-- Pressure Plate
-------------------------------------------------

local function setupPressurePlate(part: BasePart)
    local puzzleId = part:GetAttribute("PuzzleId") :: string
    local elementId = part:GetAttribute("ElementId") :: string
    local outputSignal = part:GetAttribute("OutputSignal") :: string
    if not puzzleId or not elementId or not outputSignal then return end

    local key = puzzleId .. "_" .. elementId
    elementInstances[key] = part

    local playersOnPlate: { [Player]: boolean } = {}

    -- Visual indicator
    local originalColor = part.Color

    part.Touched:Connect(function(hit: BasePart)
        local character = hit.Parent :: Model?
        if not character then return end
        local player = Players:GetPlayerFromCharacter(character)
        if not player then return end

        playersOnPlate[player] = true
        setSignal(puzzleId, outputSignal, true)
        part.Color = PuzzleConfig.SIGNAL_COLORS.On
        part:SetAttribute("Active", true)
    end)

    part.TouchEnded:Connect(function(hit: BasePart)
        local character = hit.Parent :: Model?
        if not character then return end
        local player = Players:GetPlayerFromCharacter(character)
        if not player then return end

        playersOnPlate[player] = nil

        -- Check if any player still on plate
        local anyOn = false
        for _ in playersOnPlate do
            anyOn = true
            break
        end

        if not anyOn then
            setSignal(puzzleId, outputSignal, false)
            part.Color = originalColor
            part:SetAttribute("Active", false)
        end
    end)
end

-------------------------------------------------
-- Lever
-------------------------------------------------

local function setupLever(part: BasePart)
    local puzzleId = part:GetAttribute("PuzzleId") :: string
    local elementId = part:GetAttribute("ElementId") :: string
    local outputSignal = part:GetAttribute("OutputSignal") :: string
    if not puzzleId or not elementId or not outputSignal then return end

    local key = puzzleId .. "_" .. elementId
    elementInstances[key] = part

    local isOn = false
    local lastToggle = 0

    -- Use ClickDetector for lever interaction
    local clickDetector = part:FindFirstChildOfClass("ClickDetector")
    if not clickDetector then
        clickDetector = Instance.new("ClickDetector")
        clickDetector.MaxActivationDistance = 10
        clickDetector.Parent = part
    end

    clickDetector.MouseClick:Connect(function(player: Player)
        if tick() - lastToggle < PuzzleConfig.LEVER_COOLDOWN then return end
        lastToggle = tick()

        isOn = not isOn
        setSignal(puzzleId, outputSignal, isOn)
        part:SetAttribute("Active", isOn)

        -- Animate lever rotation
        local hinge = part:FindFirstChild("Hinge") :: BasePart?
        if hinge then
            local targetAngle = if isOn then 45 else -45
            TweenService:Create(hinge, TweenInfo.new(0.3), {
                CFrame = hinge.CFrame * CFrame.Angles(math.rad(targetAngle), 0, 0),
            }):Play()
        end

        -- Color feedback
        part.Color = if isOn then PuzzleConfig.SIGNAL_COLORS.On else PuzzleConfig.SIGNAL_COLORS.Off
    end)
end

-------------------------------------------------
-- Combination Lock
-------------------------------------------------

local function setupCombinationLock(part: BasePart)
    local puzzleId = part:GetAttribute("PuzzleId") :: string
    local elementId = part:GetAttribute("ElementId") :: string
    local outputSignal = part:GetAttribute("OutputSignal") :: string
    local correctCode = part:GetAttribute("Code") :: string -- e.g. "1234"
    if not puzzleId or not elementId or not outputSignal or not correctCode then return end

    local key = puzzleId .. "_" .. elementId
    elementInstances[key] = part
    combinationInputs[key] = {}

    -- Remote for client to submit digits
    local remotes = ReplicatedStorage:FindFirstChild("PuzzleRemotes")
    if not remotes then return end

    local submitDigit = remotes:FindFirstChild("SubmitCombinationDigit") :: RemoteEvent
    if not submitDigit then return end

    -- The client sends (puzzleId, elementId, digit)
    -- We handle it in the global listener in Init()
end

local function handleCombinationDigit(player: Player, puzzleId: string, elementId: string, digit: number)
    local key = puzzleId .. "_" .. elementId
    local part = elementInstances[key]
    if not part then return end

    local correctCode = (part :: BasePart):GetAttribute("Code") :: string
    local outputSignal = (part :: BasePart):GetAttribute("OutputSignal") :: string
    if not correctCode or not outputSignal then return end

    if not combinationInputs[key] then
        combinationInputs[key] = {}
    end

    table.insert(combinationInputs[key], digit)

    -- Check if code length reached
    if #combinationInputs[key] >= #correctCode then
        local entered = table.concat(combinationInputs[key], "")
        if entered == correctCode then
            setSignal(puzzleId, outputSignal, true);
            (part :: BasePart).Color = PuzzleConfig.SIGNAL_COLORS.On

            -- Notify success
            local remotes = ReplicatedStorage:FindFirstChild("PuzzleRemotes")
            if remotes then
                local notify = remotes:FindFirstChild("CombinationResult") :: RemoteEvent
                if notify then
                    notify:FireClient(player, puzzleId, elementId, true)
                end
            end
        else
            -- Wrong code, reset
            combinationInputs[key] = {};
            (part :: BasePart).Color = PuzzleConfig.SIGNAL_COLORS.Off

            local remotes = ReplicatedStorage:FindFirstChild("PuzzleRemotes")
            if remotes then
                local notify = remotes:FindFirstChild("CombinationResult") :: RemoteEvent
                if notify then
                    notify:FireClient(player, puzzleId, elementId, false)
                end
            end
        end
    end
end

-------------------------------------------------
-- Moving Platform
-------------------------------------------------

local function setupMovingPlatform(part: BasePart)
    local puzzleId = part:GetAttribute("PuzzleId") :: string
    local elementId = part:GetAttribute("ElementId") :: string
    local inputSignal = part:GetAttribute("InputSignal") :: string
    local targetOffset = part:GetAttribute("TargetOffset") :: Vector3 -- relative movement
    if not puzzleId or not elementId or not inputSignal then return end

    local key = puzzleId .. "_" .. elementId
    elementInstances[key] = part

    local startCFrame = part.CFrame
    local endCFrame = startCFrame + (targetOffset or Vector3.new(0, 10, 0))
    local moveTime = if targetOffset then targetOffset.Magnitude / PuzzleConfig.PLATFORM_SPEED else 2

    -- The signal evaluation will call this
    part:SetAttribute("_StartCFrame", startCFrame)
    part:SetAttribute("_MoveTime", moveTime)

    -- Store original position for reset
    part:SetAttribute("OriginalPosition", startCFrame.Position)
end

local function activateMovingPlatform(key: string, active: boolean)
    local part = elementInstances[key] :: BasePart?
    if not part then return end

    -- Cancel existing tween
    if activeTweens[key] then
        activeTweens[key]:Cancel()
    end

    local startCFrame = part.CFrame
    local targetOffset = part:GetAttribute("TargetOffset") :: Vector3 or Vector3.new(0, 10, 0)
    local origPos = part:GetAttribute("OriginalPosition") :: Vector3

    local targetCFrame: CFrame
    if active then
        targetCFrame = CFrame.new(origPos + targetOffset) * (startCFrame - startCFrame.Position)
    else
        targetCFrame = CFrame.new(origPos) * (startCFrame - startCFrame.Position)
    end

    local moveTime = part:GetAttribute("_MoveTime") :: number or 2
    local tween = TweenService:Create(part, TweenInfo.new(moveTime, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), {
        CFrame = targetCFrame,
    })
    activeTweens[key] = tween
    tween:Play()
end

-------------------------------------------------
-- Laser Grid
-------------------------------------------------

local function setupLaserGrid(part: BasePart)
    local puzzleId = part:GetAttribute("PuzzleId") :: string
    local elementId = part:GetAttribute("ElementId") :: string
    local inputSignal = part:GetAttribute("InputSignal") :: string
    if not puzzleId or not elementId then return end

    local key = puzzleId .. "_" .. elementId
    elementInstances[key] = part

    -- Laser beams are child Parts named "LaserBeam"
    local beams = {}
    for _, child in part:GetDescendants() do
        if child:IsA("BasePart") and child.Name == "LaserBeam" then
            table.insert(beams, child)
        end
    end

    -- Damage loop
    task.spawn(function()
        while part.Parent do
            task.wait(PuzzleConfig.LASER_DAMAGE_INTERVAL)

            local active = part:GetAttribute("Active")
            if active == false then continue end -- lasers disabled by signal

            for _, beam in beams do
                if not beam.Parent then continue end
                -- Check for players touching laser beams
                local touching = beam:GetTouchingParts()
                for _, touchPart in touching do
                    local character = touchPart.Parent :: Model?
                    if character then
                        local humanoid = character:FindFirstChildOfClass("Humanoid")
                        if humanoid and humanoid.Health > 0 then
                            humanoid:TakeDamage(PuzzleConfig.LASER_DAMAGE)
                        end
                    end
                end
            end
        end
    end)
end

local function setLaserGridActive(key: string, active: boolean)
    local part = elementInstances[key]
    if not part then return end

    (part :: BasePart):SetAttribute("Active", active)

    -- Toggle beam visibility
    for _, child in (part :: Instance):GetDescendants() do
        if child:IsA("BasePart") and child.Name == "LaserBeam" then
            child.Transparency = if active then 0.3 else 1
            child.CanCollide = active
        end
    end
end

-------------------------------------------------
-- Timed Button (holds signal for limited duration)
-------------------------------------------------

local function setupTimedButton(part: BasePart)
    local puzzleId = part:GetAttribute("PuzzleId") :: string
    local elementId = part:GetAttribute("ElementId") :: string
    local outputSignal = part:GetAttribute("OutputSignal") :: string
    local duration = part:GetAttribute("Duration") :: number or PuzzleConfig.TIMED_BUTTON_DURATION
    if not puzzleId or not elementId or not outputSignal then return end

    local key = puzzleId .. "_" .. elementId
    elementInstances[key] = part

    local clickDetector = part:FindFirstChildOfClass("ClickDetector")
    if not clickDetector then
        clickDetector = Instance.new("ClickDetector")
        clickDetector.MaxActivationDistance = 10
        clickDetector.Parent = part
    end

    clickDetector.MouseClick:Connect(function(_player: Player)
        setSignal(puzzleId, outputSignal, true)
        part.Color = PuzzleConfig.SIGNAL_COLORS.On
        part:SetAttribute("Active", true)

        timedExpiry[key] = tick() + duration
    end)
end

-------------------------------------------------
-- Door (output element, opened by signals)
-------------------------------------------------

local function setupDoor(part: BasePart)
    local puzzleId = part:GetAttribute("PuzzleId") :: string
    local elementId = part:GetAttribute("ElementId") :: string
    local inputSignal = part:GetAttribute("InputSignal") :: string
    local logicMode = part:GetAttribute("LogicMode") :: string or "AND"
    if not puzzleId or not elementId then return end

    local key = puzzleId .. "_" .. elementId
    elementInstances[key] = part
    part:SetAttribute("OriginalPosition", part.Position)
end

local function setDoorOpen(key: string, open: boolean)
    local part = elementInstances[key] :: BasePart?
    if not part then return end

    if activeTweens[key] then
        activeTweens[key]:Cancel()
    end

    local origPos = part:GetAttribute("OriginalPosition") :: Vector3
    local targetPos = if open then origPos + Vector3.new(0, part.Size.Y + 1, 0) else origPos

    local tween = TweenService:Create(part, TweenInfo.new(1, Enum.EasingStyle.Quad), {
        Position = targetPos,
    })
    activeTweens[key] = tween
    tween:Play()

    part.CanCollide = not open
end

-------------------------------------------------
-- Signal Evaluation (Logic Gates & Input Processing)
-------------------------------------------------

function PuzzleService._EvaluateAllElements(puzzleId: string)
    for fullKey, instance in elementInstances do
        if not string.find(fullKey, puzzleId .. "_") then continue end

        local inst = instance :: BasePart
        local elemType = inst:GetAttribute("ElementType") :: string
        local inputSignalRaw = inst:GetAttribute("InputSignal") :: string?
        local inputSignalsRaw = inst:GetAttribute("InputSignals") :: string? -- comma-separated
        local logicMode = inst:GetAttribute("LogicMode") :: string or "AND"

        if not inputSignalRaw and not inputSignalsRaw then continue end

        -- Gather input signal values
        local inputValues: { boolean } = {}
        if inputSignalRaw then
            table.insert(inputValues, getSignal(puzzleId, inputSignalRaw))
        end
        if inputSignalsRaw then
            for signalName in string.gmatch(inputSignalsRaw, "[^,]+") do
                signalName = string.gsub(signalName, "^%s+", "")
                signalName = string.gsub(signalName, "%s+$", "")
                table.insert(inputValues, getSignal(puzzleId, signalName))
            end
        end

        -- Evaluate logic
        local result = false
        if logicMode == "AND" then
            result = true
            for _, v in inputValues do
                if not v then result = false; break end
            end
        elseif logicMode == "OR" then
            for _, v in inputValues do
                if v then result = true; break end
            end
        elseif logicMode == "XOR" then
            local trueCount = 0
            for _, v in inputValues do
                if v then trueCount += 1 end
            end
            result = (trueCount % 2 == 1)
        end

        -- Apply result to element
        if elemType == "Door" then
            setDoorOpen(fullKey, result)
        elseif elemType == "MovingPlatform" then
            activateMovingPlatform(fullKey, result)
        elseif elemType == "LaserGrid" then
            -- Laser grids: signal ON = lasers OFF (signal disables them)
            setLaserGridActive(fullKey, not result)
        elseif elemType == "LogicGate" then
            -- Logic gate outputs its own signal
            local outputSignal = inst:GetAttribute("OutputSignal") :: string?
            if outputSignal then
                setSignal(puzzleId, outputSignal, result)
            end
        end
    end
end

-------------------------------------------------
-- Puzzle Reset
-------------------------------------------------

function PuzzleService.ResetPuzzle(puzzleId: string)
    -- Clear all signals
    signalStates[puzzleId] = {}

    -- Reset all elements
    for fullKey, instance in elementInstances do
        if not string.find(fullKey, puzzleId .. "_") then continue end
        local inst = instance :: BasePart
        inst:SetAttribute("Active", false)

        -- Reset combination inputs
        if combinationInputs[fullKey] then
            combinationInputs[fullKey] = {}
        end

        -- Reset visual state
        local elemType = inst:GetAttribute("ElementType") :: string
        if elemType == "Door" then
            setDoorOpen(fullKey, false)
        elseif elemType == "LaserGrid" then
            setLaserGridActive(fullKey, true)
        end
    end
end

-------------------------------------------------
-- Init
-------------------------------------------------

function PuzzleService.Init()
    -- Create remotes
    local remotesFolder = Instance.new("Folder")
    remotesFolder.Name = "PuzzleRemotes"
    remotesFolder.Parent = ReplicatedStorage

    for _, name in { "SubmitCombinationDigit", "CombinationResult", "PuzzleReset", "PuzzleComplete" } do
        local remote = Instance.new("RemoteEvent")
        remote.Name = name
        remote.Parent = remotesFolder
    end

    -- Combination digit handler
    local submitDigit = remotesFolder:FindFirstChild("SubmitCombinationDigit") :: RemoteEvent
    submitDigit.OnServerEvent:Connect(function(player: Player, puzzleId: string, elementId: string, digit: number)
        handleCombinationDigit(player, puzzleId, elementId, digit)
    end)

    -- Scan workspace for puzzle elements using CollectionService tags
    local function registerElement(instance: Instance)
        if not instance:IsA("BasePart") then return end
        local elemType = instance:GetAttribute("ElementType") :: string?
        if not elemType then return end

        if elemType == "PressurePlate" then
            setupPressurePlate(instance :: BasePart)
        elseif elemType == "Lever" then
            setupLever(instance :: BasePart)
        elseif elemType == "CombinationLock" then
            setupCombinationLock(instance :: BasePart)
        elseif elemType == "MovingPlatform" then
            setupMovingPlatform(instance :: BasePart)
        elseif elemType == "LaserGrid" then
            setupLaserGrid(instance :: BasePart)
        elseif elemType == "TimedButton" then
            setupTimedButton(instance :: BasePart)
        elseif elemType == "Door" then
            setupDoor(instance :: BasePart)
        end
    end

    -- Register existing tagged elements
    for _, instance in CollectionService:GetTagged("PuzzleElement") do
        registerElement(instance)
    end

    -- Register newly added elements
    CollectionService:GetInstanceAddedSignal("PuzzleElement"):Connect(registerElement)

    -- Timed button expiry loop
    RunService.Heartbeat:Connect(function()
        local now = tick()
        for key, expiry in timedExpiry do
            if now >= expiry then
                timedExpiry[key] = nil
                local part = elementInstances[key] :: BasePart?
                if part then
                    local puzzleId = part:GetAttribute("PuzzleId") :: string
                    local outputSignal = part:GetAttribute("OutputSignal") :: string
                    if puzzleId and outputSignal then
                        setSignal(puzzleId, outputSignal, false)
                        part.Color = PuzzleConfig.SIGNAL_COLORS.Off
                        part:SetAttribute("Active", false)
                    end
                end
            end
        end
    end)
end

return PuzzleService
```

---

## Key Implementation Notes

1. **Signal-based architecture**: Every puzzle element communicates via named signals within a puzzle group. This allows complex chain reactions.
2. **Logic gates**: AND, OR, XOR combine multiple input signals. A door requiring two levers uses AND logic with two input signals.
3. **Attribute-driven setup**: Puzzle elements are configured via Roblox Instance attributes (PuzzleId, ElementId, ElementType, InputSignal, OutputSignal, LogicMode). No code changes needed to add new puzzles -- just set attributes in Studio.
4. **CollectionService tags**: All puzzle elements are tagged "PuzzleElement" for automatic discovery.
5. **Timed buttons** emit a signal for a limited duration, then auto-reset. Multiple timed buttons with AND logic create timed sequence puzzles.
6. **Laser grids** deal continuous damage. They are disabled when their input signal is ON (inverted logic).
7. **Combination locks** accept digit-by-digit input from clients. The correct code is stored as an attribute.
8. **Moving platforms** use TweenService for smooth movement. The target offset is defined per-platform via attribute.
9. **Reset** clears all signals and returns elements to default state. Can be triggered by timer or manually.

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
- `$PUZZLE_ELEMENTS` -- Which puzzle element types to include (default: all)
- `$LOGIC_GATES` -- Whether to include logic gate chaining (default true)
- `$DAMAGE_ENABLED` -- Whether lasers and traps deal damage (default true)
- `$RESET_MODE` -- "manual", "auto_on_fail", or "timed" puzzle reset behavior
- `$COMBINATION_LENGTH` -- Default combination lock code length (default 4)
- `$PLATFORM_SPEED` -- Moving platform speed in studs/sec (default 8)
- `$MULTIPLAYER_PUZZLES` -- Whether puzzles require multiple simultaneous players
- `$HINT_SYSTEM` -- Whether to include a progressive hint system for stuck players
