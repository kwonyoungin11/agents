---
name: gamepad
description: |
  컨트롤러 지원, 게임패드 입력 매핑, 진동 피드백, 썸스틱 UI 네비게이션, Xbox/PlayStation 호환.
  Controller support, gamepad input mapping, vibration/haptic feedback, thumbstick UI navigation, Xbox/PlayStation compatibility, button icons, analog trigger input.
allowed-tools:
  - Bash
  - Edit
  - Write
  - Read
  - Glob
  - Grep
effort: high
---

# Gamepad Input System

This skill covers gamepad/controller support including input mapping, vibration feedback, thumbstick-based UI navigation, button icon display, and analog input handling for Roblox.

---

## 1. Gamepad Detection & State

```luau
--!strict
-- ModuleScript: Gamepad detection and connection management

local UserInputService = game:GetService("UserInputService")

local GamepadDetector = {}

--- Returns true if any gamepad is currently connected.
function GamepadDetector.isGamepadConnected(): boolean
    return UserInputService.GamepadEnabled
end

--- Returns a list of connected gamepad UserInputTypes.
function GamepadDetector.getConnectedGamepads(): { Enum.UserInputType }
    return UserInputService:GetConnectedGamepads()
end

--- Returns the primary gamepad (usually Gamepad1).
function GamepadDetector.getPrimaryGamepad(): Enum.UserInputType?
    local gamepads = UserInputService:GetConnectedGamepads()
    if #gamepads > 0 then
        table.sort(gamepads, function(a, b)
            return a.Value < b.Value
        end)
        return gamepads[1]
    end
    return nil
end

--- Listens for gamepad connection/disconnection events.
function GamepadDetector.onConnectionChanged(callback: (gamepad: Enum.UserInputType, connected: boolean) -> ()): () -> ()
    local c1 = UserInputService.GamepadConnected:Connect(function(gamepad)
        callback(gamepad, true)
    end)
    local c2 = UserInputService.GamepadDisconnected:Connect(function(gamepad)
        callback(gamepad, false)
    end)
    return function()
        c1:Disconnect()
        c2:Disconnect()
    end
end

return GamepadDetector
```

---

## 2. Gamepad Input Mapper

```luau
--!strict
-- ModuleScript: Maps gamepad buttons/axes to game actions

local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local GamepadMapper = {}
GamepadMapper.__index = GamepadMapper

export type ActionBinding = {
    keyCode: Enum.KeyCode,
    onPressed: (() -> ())?,
    onReleased: (() -> ())?,
    isHeld: (() -> ())?,  -- Called every frame while held
}

function GamepadMapper.new()
    local self = setmetatable({}, GamepadMapper)
    self._bindings = {} :: { [string]: ActionBinding }
    self._heldKeys = {} :: { [Enum.KeyCode]: boolean }
    self._connections = {} :: { RBXScriptConnection }

    -- Track button presses
    local pressConn = UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
        if processed then return end
        if input.UserInputType ~= Enum.UserInputType.Gamepad1 then return end

        self._heldKeys[input.KeyCode] = true

        for _, binding in self._bindings do
            if binding.keyCode == input.KeyCode and binding.onPressed then
                binding.onPressed()
            end
        end
    end)

    local releaseConn = UserInputService.InputEnded:Connect(function(input: InputObject)
        if input.UserInputType ~= Enum.UserInputType.Gamepad1 then return end

        self._heldKeys[input.KeyCode] = nil

        for _, binding in self._bindings do
            if binding.keyCode == input.KeyCode and binding.onReleased then
                binding.onReleased()
            end
        end
    end)

    -- Per-frame held check
    local heartbeatConn = RunService.Heartbeat:Connect(function()
        for _, binding in self._bindings do
            if self._heldKeys[binding.keyCode] and binding.isHeld then
                binding.isHeld()
            end
        end
    end)

    table.insert(self._connections, pressConn)
    table.insert(self._connections, releaseConn)
    table.insert(self._connections, heartbeatConn)

    return self
end

--- Binds a game action to a gamepad button.
function GamepadMapper.bind(self: any, actionName: string, binding: ActionBinding)
    self._bindings[actionName] = binding
end

--- Unbinds a game action.
function GamepadMapper.unbind(self: any, actionName: string)
    self._bindings[actionName] = nil
end

--- Returns the current value of a thumbstick axis.
function GamepadMapper.getThumbstick(self: any, thumbstick: Enum.KeyCode): Vector2
    local state = UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1)
    for _, input in state do
        if input.KeyCode == thumbstick then
            return Vector2.new(input.Position.X, input.Position.Y)
        end
    end
    return Vector2.zero
end

--- Returns the current trigger value (0-1).
function GamepadMapper.getTrigger(self: any, trigger: Enum.KeyCode): number
    local state = UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1)
    for _, input in state do
        if input.KeyCode == trigger then
            return input.Position.Z
        end
    end
    return 0
end

--- Destroys all connections.
function GamepadMapper.destroy(self: any)
    for _, conn in self._connections do
        conn:Disconnect()
    end
end

return GamepadMapper
```

---

## 3. Vibration / Haptic Feedback

```luau
--!strict
-- ModuleScript: Controller vibration and haptic feedback system

local HapticService = game:GetService("HapticService")

local Vibration = {}

--- Checks if the gamepad supports vibration.
function Vibration.isSupported(gamepad: Enum.UserInputType?): boolean
    local gp = gamepad or Enum.UserInputType.Gamepad1
    return HapticService:IsVibrationSupported(gp)
end

--- Checks if a specific vibration motor is supported.
function Vibration.isMotorSupported(motor: Enum.VibrationMotor, gamepad: Enum.UserInputType?): boolean
    local gp = gamepad or Enum.UserInputType.Gamepad1
    if not HapticService:IsVibrationSupported(gp) then return false end
    return HapticService:IsMotorSupported(gp, motor)
end

--- Sets vibration on a specific motor (0-1 intensity).
function Vibration.setMotor(motor: Enum.VibrationMotor, intensity: number, gamepad: Enum.UserInputType?)
    local gp = gamepad or Enum.UserInputType.Gamepad1
    if not Vibration.isMotorSupported(motor, gp) then return end
    HapticService:SetMotor(gp, motor, math.clamp(intensity, 0, 1))
end

--- Stops all vibration motors.
function Vibration.stopAll(gamepad: Enum.UserInputType?)
    local gp = gamepad or Enum.UserInputType.Gamepad1
    local motors = {
        Enum.VibrationMotor.Large,
        Enum.VibrationMotor.Small,
        Enum.VibrationMotor.LeftTrigger,
        Enum.VibrationMotor.RightTrigger,
        Enum.VibrationMotor.LeftHand,
        Enum.VibrationMotor.RightHand,
    }
    for _, motor in motors do
        if Vibration.isMotorSupported(motor, gp) then
            HapticService:SetMotor(gp, motor, 0)
        end
    end
end

--- Quick vibration pulse (vibrate then stop after duration).
function Vibration.pulse(intensity: number, duration: number, motor: Enum.VibrationMotor?)
    local m = motor or Enum.VibrationMotor.Large
    Vibration.setMotor(m, intensity)
    task.delay(duration, function()
        Vibration.setMotor(m, 0)
    end)
end

--- Impact vibration pattern (sharp hit feedback).
function Vibration.impact(strength: number)
    -- strength: 0-1, where 1 is max impact
    local s = math.clamp(strength, 0, 1)
    Vibration.setMotor(Enum.VibrationMotor.Large, s * 0.8)
    Vibration.setMotor(Enum.VibrationMotor.Small, s * 1.0)
    task.delay(0.08, function()
        Vibration.setMotor(Enum.VibrationMotor.Large, s * 0.3)
        Vibration.setMotor(Enum.VibrationMotor.Small, s * 0.5)
    end)
    task.delay(0.15, function()
        Vibration.stopAll()
    end)
end

--- Continuous rumble effect (for ongoing actions like driving).
function Vibration.rumble(intensity: number): () -> ()
    local running = true
    Vibration.setMotor(Enum.VibrationMotor.Large, intensity * 0.6)
    Vibration.setMotor(Enum.VibrationMotor.Small, intensity * 0.3)

    return function()
        running = false
        Vibration.stopAll()
    end
end

--- Damage feedback pattern (sharp then fading vibration).
function Vibration.damageFeedback(damagePercent: number)
    local s = math.clamp(damagePercent, 0, 1)
    Vibration.setMotor(Enum.VibrationMotor.Large, s)
    Vibration.setMotor(Enum.VibrationMotor.Small, s * 0.8)
    task.delay(0.1, function()
        Vibration.setMotor(Enum.VibrationMotor.Large, s * 0.5)
    end)
    task.delay(0.2, function()
        Vibration.setMotor(Enum.VibrationMotor.Large, s * 0.2)
        Vibration.setMotor(Enum.VibrationMotor.Small, s * 0.3)
    end)
    task.delay(0.35, function()
        Vibration.stopAll()
    end)
end

return Vibration
```

---

## 4. Thumbstick UI Navigation

```luau
--!strict
-- LocalScript/ModuleScript: Navigate UI menus using gamepad thumbstick

local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")

local ThumbstickNav = {}

export type NavConfig = {
    repeatDelay: number?,        -- Seconds before repeat starts
    repeatRate: number?,         -- Seconds between repeats
    deadzone: number?,           -- Thumbstick deadzone 0-1
    selectButton: Enum.KeyCode?, -- Button to confirm selection
    backButton: Enum.KeyCode?,   -- Button to go back
}

--- Creates a thumbstick-based UI navigation controller.
function ThumbstickNav.create(selectableButtons: { GuiButton }, config: NavConfig?)
    local cfg = config or {}
    local deadzone = cfg.deadzone or 0.5
    local repeatDelay = cfg.repeatDelay or 0.4
    local repeatRate = cfg.repeatRate or 0.15
    local selectKey = cfg.selectButton or Enum.KeyCode.ButtonA
    local backKey = cfg.backButton or Enum.KeyCode.ButtonB

    local currentIndex = 1
    local lastMoveTime = 0
    local moveHeld = false
    local connections: { RBXScriptConnection } = {}

    -- Highlight the currently selected button
    local function highlightCurrent()
        for i, btn in selectableButtons do
            if btn:IsA("GuiButton") then
                if i == currentIndex then
                    btn.BorderSizePixel = 3
                    btn.BorderColor3 = Color3.fromRGB(255, 200, 50)
                    -- Set as GuiService selected object for built-in gamepad support
                    GuiService.SelectedObject = btn
                else
                    btn.BorderSizePixel = 0
                end
            end
        end
    end

    local function navigate(direction: number)
        currentIndex = math.clamp(currentIndex + direction, 1, #selectableButtons)
        highlightCurrent()
    end

    -- Thumbstick navigation
    local navConn = RunService.Heartbeat:Connect(function()
        local state = UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1)
        local thumbY = 0
        for _, input in state do
            if input.KeyCode == Enum.KeyCode.Thumbstick1 then
                thumbY = input.Position.Y
                break
            end
        end

        if math.abs(thumbY) > deadzone then
            local now = tick()
            local direction = if thumbY > 0 then -1 else 1

            if not moveHeld then
                navigate(direction)
                moveHeld = true
                lastMoveTime = now
            elseif now - lastMoveTime > (if moveHeld then repeatRate else repeatDelay) then
                navigate(direction)
                lastMoveTime = now
            end
        else
            moveHeld = false
        end
    end)

    -- Button press for selection
    local selectConn = UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
        if processed then return end
        if input.UserInputType ~= Enum.UserInputType.Gamepad1 then return end

        if input.KeyCode == selectKey then
            local btn = selectableButtons[currentIndex]
            if btn and btn:IsA("GuiButton") then
                -- Simulate click
                local clickEvent = btn:FindFirstChild("MouseButton1Click")
                -- Programmatic activation
                btn.Active = true
            end
        end
    end)

    table.insert(connections, navConn)
    table.insert(connections, selectConn)

    highlightCurrent()

    -- Return cleanup function
    return function()
        for _, conn in connections do
            conn:Disconnect()
        end
        GuiService.SelectedObject = nil
    end
end

return ThumbstickNav
```

---

## 5. Button Icon Reference

```luau
--!strict
-- ModuleScript: Gamepad button icon mapping for Xbox and PlayStation

local ButtonIcons = {}

-- Xbox button icons (rbxassetid or text fallback)
ButtonIcons.Xbox = {
    [Enum.KeyCode.ButtonA] = { label = "A", color = Color3.fromRGB(96, 186, 64) },
    [Enum.KeyCode.ButtonB] = { label = "B", color = Color3.fromRGB(228, 50, 50) },
    [Enum.KeyCode.ButtonX] = { label = "X", color = Color3.fromRGB(50, 120, 228) },
    [Enum.KeyCode.ButtonY] = { label = "Y", color = Color3.fromRGB(255, 186, 0) },
    [Enum.KeyCode.ButtonL1] = { label = "LB", color = Color3.fromRGB(180, 180, 180) },
    [Enum.KeyCode.ButtonR1] = { label = "RB", color = Color3.fromRGB(180, 180, 180) },
    [Enum.KeyCode.ButtonL2] = { label = "LT", color = Color3.fromRGB(180, 180, 180) },
    [Enum.KeyCode.ButtonR2] = { label = "RT", color = Color3.fromRGB(180, 180, 180) },
    [Enum.KeyCode.ButtonL3] = { label = "LS", color = Color3.fromRGB(150, 150, 150) },
    [Enum.KeyCode.ButtonR3] = { label = "RS", color = Color3.fromRGB(150, 150, 150) },
    [Enum.KeyCode.ButtonStart] = { label = "Menu", color = Color3.fromRGB(200, 200, 200) },
    [Enum.KeyCode.ButtonSelect] = { label = "View", color = Color3.fromRGB(200, 200, 200) },
    [Enum.KeyCode.DPadUp] = { label = "D-Up", color = Color3.fromRGB(200, 200, 200) },
    [Enum.KeyCode.DPadDown] = { label = "D-Down", color = Color3.fromRGB(200, 200, 200) },
    [Enum.KeyCode.DPadLeft] = { label = "D-Left", color = Color3.fromRGB(200, 200, 200) },
    [Enum.KeyCode.DPadRight] = { label = "D-Right", color = Color3.fromRGB(200, 200, 200) },
}

--- Creates a button prompt label for UI display.
function ButtonIcons.createPromptLabel(keyCode: Enum.KeyCode, parent: GuiObject, size: UDim2?): TextLabel
    local info = ButtonIcons.Xbox[keyCode]
    if not info then
        info = { label = keyCode.Name, color = Color3.fromRGB(180, 180, 180) }
    end

    local label = Instance.new("TextLabel")
    label.Size = size or UDim2.fromOffset(32, 32)
    label.BackgroundColor3 = info.color
    label.BackgroundTransparency = 0.1
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.Text = info.label
    label.TextScaled = true
    label.Font = Enum.Font.GothamBold
    label.Parent = parent

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0.3, 0)
    corner.Parent = label

    return label
end

return ButtonIcons
```

---

## Common Gamepad KeyCodes Reference

| KeyCode | Xbox | PlayStation |
|---|---|---|
| ButtonA | A | Cross |
| ButtonB | B | Circle |
| ButtonX | X | Square |
| ButtonY | Y | Triangle |
| ButtonL1 | LB | L1 |
| ButtonR1 | RB | R1 |
| ButtonL2 | LT | L2 |
| ButtonR2 | RT | R2 |
| Thumbstick1 | Left Stick | Left Stick |
| Thumbstick2 | Right Stick | Right Stick |

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

- `action_name` (string) - Name of the game action to bind
- `key_code` (string) - Gamepad KeyCode name (e.g., "ButtonA", "ButtonR1")
- `vibration_intensity` (number) - Vibration strength 0-1
- `vibration_duration` (number) - Vibration duration in seconds
- `vibration_motor` (string) - Motor: "Large", "Small", "LeftTrigger", "RightTrigger"
- `thumbstick_deadzone` (number) - Deadzone threshold 0-1 (default: 0.5)
- `nav_repeat_delay` (number) - Seconds before repeat navigation starts
- `nav_repeat_rate` (number) - Seconds between repeated navigation moves
- `select_button` (string) - KeyCode for selection (default: "ButtonA")
- `back_button` (string) - KeyCode for back/cancel (default: "ButtonB")
