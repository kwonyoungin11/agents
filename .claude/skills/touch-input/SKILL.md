---
name: touch-input
description: |
  모바일 터치 컨트롤, 가상 조이스틱, 터치 버튼, 스와이프 감지, 핀치 줌, 멀티터치 입력 처리.
  Mobile touch controls, virtual joystick implementation, touch buttons, swipe gesture detection, pinch-to-zoom, multi-touch handling, tap detection, touch regions.
allowed-tools:
  - Bash
  - Edit
  - Write
  - Read
  - Glob
  - Grep
effort: high
---

# Mobile Touch Input System

This skill covers mobile touch controls including virtual joysticks, touch buttons, swipe detection, pinch-to-zoom, and multi-touch input handling for Roblox mobile games.

---

## 1. Touch Detection Utilities

```luau
--!strict
-- ModuleScript: Core touch detection and platform check utilities

local UserInputService = game:GetService("UserInputService")

local TouchUtils = {}

--- Returns true if the device supports touch input.
function TouchUtils.isTouchDevice(): boolean
    return UserInputService.TouchEnabled
end

--- Returns true if the device is a phone (touch + small screen).
function TouchUtils.isPhone(): boolean
    if not UserInputService.TouchEnabled then return false end
    local camera = workspace.CurrentCamera
    if not camera then return false end
    local viewportSize = camera.ViewportSize
    return viewportSize.X < 600 or viewportSize.Y < 400
end

--- Returns true if the device is a tablet (touch + larger screen).
function TouchUtils.isTablet(): boolean
    if not UserInputService.TouchEnabled then return false end
    local camera = workspace.CurrentCamera
    if not camera then return false end
    local viewportSize = camera.ViewportSize
    return viewportSize.X >= 600 and not UserInputService.KeyboardEnabled
end

return TouchUtils
```

---

## 2. Virtual Joystick

```luau
--!strict
-- LocalScript/ModuleScript: Custom virtual joystick for mobile movement

local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

local VirtualJoystick = {}
VirtualJoystick.__index = VirtualJoystick

export type JoystickConfig = {
    position: UDim2?,           -- Center position of the joystick area
    outerSize: number?,         -- Diameter of the outer ring
    innerSize: number?,         -- Diameter of the thumb knob
    outerColor: Color3?,
    innerColor: Color3?,
    outerTransparency: number?,
    innerTransparency: number?,
    deadzone: number?,          -- 0-1, fraction of radius considered zero input
    parent: GuiObject?,
}

function VirtualJoystick.new(config: JoystickConfig?)
    local self = setmetatable({}, VirtualJoystick)

    local cfg = config or {}
    self._outerSize = cfg.outerSize or 120
    self._innerSize = cfg.innerSize or 50
    self._deadzone = cfg.deadzone or 0.1
    self._moveVector = Vector3.zero
    self._active = false
    self._touchId = nil :: InputObject?

    -- Create UI
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "VirtualJoystick"
    screenGui.ResetOnSpawn = false
    screenGui.DisplayOrder = 100

    -- Outer ring
    local outer = Instance.new("ImageLabel")
    outer.Name = "Outer"
    outer.Size = UDim2.fromOffset(self._outerSize, self._outerSize)
    outer.Position = cfg.position or UDim2.new(0, 60, 1, -180)
    outer.AnchorPoint = Vector2.new(0.5, 0.5)
    outer.BackgroundColor3 = cfg.outerColor or Color3.fromRGB(60, 60, 70)
    outer.BackgroundTransparency = cfg.outerTransparency or 0.5
    outer.Image = ""
    outer.Parent = screenGui

    local outerCorner = Instance.new("UICorner")
    outerCorner.CornerRadius = UDim.new(1, 0)
    outerCorner.Parent = outer

    local outerStroke = Instance.new("UIStroke")
    outerStroke.Color = Color3.fromRGB(120, 120, 140)
    outerStroke.Thickness = 2
    outerStroke.Transparency = 0.4
    outerStroke.Parent = outer

    -- Inner thumb
    local inner = Instance.new("ImageLabel")
    inner.Name = "Inner"
    inner.Size = UDim2.fromOffset(self._innerSize, self._innerSize)
    inner.Position = UDim2.fromScale(0.5, 0.5)
    inner.AnchorPoint = Vector2.new(0.5, 0.5)
    inner.BackgroundColor3 = cfg.innerColor or Color3.fromRGB(180, 180, 200)
    inner.BackgroundTransparency = cfg.innerTransparency or 0.3
    inner.Image = ""
    inner.Parent = outer

    local innerCorner = Instance.new("UICorner")
    innerCorner.CornerRadius = UDim.new(1, 0)
    innerCorner.Parent = inner

    self._screenGui = screenGui
    self._outer = outer
    self._inner = inner

    -- Touch input handling
    local maxRadius = self._outerSize / 2

    outer.InputBegan:Connect(function(input: InputObject)
        if input.UserInputType == Enum.UserInputType.Touch then
            self._active = true
            self._touchId = input
        end
    end)

    UserInputService.TouchMoved:Connect(function(input: InputObject)
        if not self._active or input ~= self._touchId then return end

        local outerCenter = outer.AbsolutePosition + outer.AbsoluteSize / 2
        local delta = Vector2.new(input.Position.X, input.Position.Y) - outerCenter
        local distance = delta.Magnitude
        local clamped = if distance > maxRadius then delta.Unit * maxRadius else delta

        -- Update thumb position
        inner.Position = UDim2.new(0.5, clamped.X, 0.5, clamped.Y)

        -- Calculate normalized move vector
        local normalized = clamped / maxRadius
        if normalized.Magnitude < self._deadzone then
            self._moveVector = Vector3.zero
        else
            self._moveVector = Vector3.new(normalized.X, 0, normalized.Y)
        end
    end)

    local function onRelease(input: InputObject)
        if input == self._touchId then
            self._active = false
            self._touchId = nil
            self._moveVector = Vector3.zero
            inner.Position = UDim2.fromScale(0.5, 0.5)
        end
    end

    UserInputService.TouchEnded:Connect(onRelease)

    -- Parent to PlayerGui
    local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
    screenGui.Parent = cfg.parent or playerGui

    return self
end

--- Returns the current movement vector (X = horizontal, Z = forward/back).
function VirtualJoystick.getMoveVector(self: any): Vector3
    return self._moveVector
end

--- Returns whether the joystick is currently being touched.
function VirtualJoystick.isActive(self: any): boolean
    return self._active
end

--- Destroys the joystick UI.
function VirtualJoystick.destroy(self: any)
    if self._screenGui then
        self._screenGui:Destroy()
    end
end

return VirtualJoystick
```

---

## 3. Touch Button System

```luau
--!strict
-- ModuleScript: Custom touch action buttons (jump, attack, ability, etc.)

local TweenService = game:GetService("TweenService")

local TouchButton = {}

export type TouchButtonConfig = {
    text: string?,
    imageId: string?,
    size: UDim2?,
    position: UDim2?,
    backgroundColor: Color3?,
    pressColor: Color3?,
    cornerRadius: number?,
    onPress: (() -> ())?,
    onRelease: (() -> ())?,
    parent: GuiObject,
}

--- Creates a touch-friendly action button.
function TouchButton.create(config: TouchButtonConfig): ImageButton
    local button = Instance.new("ImageButton")
    button.Size = config.size or UDim2.fromOffset(70, 70)
    button.Position = config.position or UDim2.new(1, -90, 1, -90)
    button.AnchorPoint = Vector2.new(0.5, 0.5)
    button.BackgroundColor3 = config.backgroundColor or Color3.fromRGB(60, 60, 80)
    button.BackgroundTransparency = 0.3
    button.AutoButtonColor = false
    button.Image = config.imageId or ""
    button.Parent = config.parent

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, config.cornerRadius or 12)
    corner.Parent = button

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(150, 150, 170)
    stroke.Thickness = 2
    stroke.Parent = button

    if config.text then
        local label = Instance.new("TextLabel")
        label.Size = UDim2.fromScale(1, 1)
        label.BackgroundTransparency = 1
        label.Text = config.text
        label.TextColor3 = Color3.fromRGB(255, 255, 255)
        label.TextScaled = true
        label.Font = Enum.Font.GothamBold
        label.Parent = button
    end

    local normalColor = config.backgroundColor or Color3.fromRGB(60, 60, 80)
    local pressColor = config.pressColor or Color3.fromRGB(100, 100, 140)

    button.InputBegan:Connect(function(input: InputObject)
        if input.UserInputType == Enum.UserInputType.Touch
        or input.UserInputType == Enum.UserInputType.MouseButton1 then
            TweenService:Create(button, TweenInfo.new(0.1), {
                BackgroundColor3 = pressColor,
                Size = (config.size or UDim2.fromOffset(70, 70)) - UDim2.fromOffset(4, 4),
            }):Play()
            if config.onPress then
                config.onPress()
            end
        end
    end)

    button.InputEnded:Connect(function(input: InputObject)
        if input.UserInputType == Enum.UserInputType.Touch
        or input.UserInputType == Enum.UserInputType.MouseButton1 then
            TweenService:Create(button, TweenInfo.new(0.1), {
                BackgroundColor3 = normalColor,
                Size = config.size or UDim2.fromOffset(70, 70),
            }):Play()
            if config.onRelease then
                config.onRelease()
            end
        end
    end)

    return button
end

return TouchButton
```

---

## 4. Swipe Detection

```luau
--!strict
-- ModuleScript: Swipe gesture detection (up, down, left, right)

local UserInputService = game:GetService("UserInputService")

local SwipeDetector = {}

export type SwipeDirection = "Up" | "Down" | "Left" | "Right"

export type SwipeConfig = {
    minDistance: number?,       -- Minimum swipe distance in pixels
    maxTime: number?,          -- Maximum swipe duration in seconds
    onSwipe: (direction: SwipeDirection, velocity: number) -> (),
}

--- Starts listening for swipe gestures.
function SwipeDetector.listen(config: SwipeConfig): () -> ()
    local minDist = config.minDistance or 50
    local maxTime = config.maxTime or 0.5
    local touchStart: { [InputObject]: { position: Vector2, time: number } } = {}

    local beganConn = UserInputService.TouchStarted:Connect(function(input: InputObject)
        touchStart[input] = {
            position = Vector2.new(input.Position.X, input.Position.Y),
            time = tick(),
        }
    end)

    local endedConn = UserInputService.TouchEnded:Connect(function(input: InputObject)
        local startData = touchStart[input]
        if not startData then return end
        touchStart[input] = nil

        local endPos = Vector2.new(input.Position.X, input.Position.Y)
        local delta = endPos - startData.position
        local elapsed = tick() - startData.time
        local distance = delta.Magnitude

        if distance < minDist or elapsed > maxTime then return end

        local velocity = distance / elapsed
        local direction: SwipeDirection

        if math.abs(delta.X) > math.abs(delta.Y) then
            direction = if delta.X > 0 then "Right" else "Left"
        else
            direction = if delta.Y > 0 then "Down" else "Up"
        end

        config.onSwipe(direction, velocity)
    end)

    -- Return disconnect function
    return function()
        beganConn:Disconnect()
        endedConn:Disconnect()
    end
end

return SwipeDetector
```

---

## 5. Pinch Zoom

```luau
--!strict
-- ModuleScript: Pinch-to-zoom gesture for camera or UI scaling

local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local PinchZoom = {}

export type PinchConfig = {
    minZoom: number?,
    maxZoom: number?,
    sensitivity: number?,
    onZoomChanged: (zoomLevel: number) -> (),
}

--- Starts listening for pinch-to-zoom gestures.
function PinchZoom.listen(config: PinchConfig): () -> ()
    local minZoom = config.minZoom or 0.5
    local maxZoom = config.maxZoom or 3.0
    local sensitivity = config.sensitivity or 0.01
    local currentZoom = 1.0

    local activeTouches: { InputObject } = {}
    local lastPinchDist: number? = nil

    local function getDistance(a: InputObject, b: InputObject): number
        local posA = Vector2.new(a.Position.X, a.Position.Y)
        local posB = Vector2.new(b.Position.X, b.Position.Y)
        return (posA - posB).Magnitude
    end

    local startConn = UserInputService.TouchStarted:Connect(function(input: InputObject)
        table.insert(activeTouches, input)
        if #activeTouches == 2 then
            lastPinchDist = getDistance(activeTouches[1], activeTouches[2])
        end
    end)

    local moveConn = UserInputService.TouchMoved:Connect(function(input: InputObject)
        if #activeTouches < 2 or not lastPinchDist then return end

        local currentDist = getDistance(activeTouches[1], activeTouches[2])
        local deltaDist = currentDist - lastPinchDist
        lastPinchDist = currentDist

        currentZoom = math.clamp(currentZoom + deltaDist * sensitivity, minZoom, maxZoom)
        config.onZoomChanged(currentZoom)
    end)

    local endConn = UserInputService.TouchEnded:Connect(function(input: InputObject)
        for i, touch in activeTouches do
            if touch == input then
                table.remove(activeTouches, i)
                break
            end
        end
        if #activeTouches < 2 then
            lastPinchDist = nil
        end
    end)

    return function()
        startConn:Disconnect()
        moveConn:Disconnect()
        endConn:Disconnect()
    end
end

return PinchZoom
```

---

## 6. Touch Region (Invisible Touch Zone)

```luau
--!strict
-- ModuleScript: Defines invisible touch regions on the screen

local TouchRegion = {}

export type RegionConfig = {
    position: UDim2,
    size: UDim2,
    onTouchBegan: ((position: Vector2) -> ())?,
    onTouchMoved: ((position: Vector2, delta: Vector2) -> ())?,
    onTouchEnded: (() -> ())?,
    parent: GuiObject,
}

--- Creates an invisible touch region that captures input.
function TouchRegion.create(config: RegionConfig): Frame
    local region = Instance.new("Frame")
    region.Size = config.size
    region.Position = config.position
    region.BackgroundTransparency = 1
    region.Parent = config.parent

    local lastPos: Vector2? = nil

    region.InputBegan:Connect(function(input: InputObject)
        if input.UserInputType ~= Enum.UserInputType.Touch then return end
        lastPos = Vector2.new(input.Position.X, input.Position.Y)
        if config.onTouchBegan then
            config.onTouchBegan(lastPos)
        end
    end)

    region.InputChanged:Connect(function(input: InputObject)
        if input.UserInputType ~= Enum.UserInputType.Touch then return end
        local currentPos = Vector2.new(input.Position.X, input.Position.Y)
        local delta = if lastPos then currentPos - lastPos else Vector2.zero
        lastPos = currentPos
        if config.onTouchMoved then
            config.onTouchMoved(currentPos, delta)
        end
    end)

    region.InputEnded:Connect(function(input: InputObject)
        if input.UserInputType ~= Enum.UserInputType.Touch then return end
        lastPos = nil
        if config.onTouchEnded then
            config.onTouchEnded()
        end
    end)

    return region
end

return TouchRegion
```

---

## Best Practices

- **Test on real devices**: Roblox Studio touch emulation is imperfect
- **Button size**: Minimum 44x44 pixels for touch targets (Apple HIG guideline)
- **Deadzone**: Always add 10-15% deadzone to joysticks to prevent drift
- **Visual feedback**: Always animate button presses; users need tactile confirmation
- **Conditional UI**: Only show touch controls on `UserInputService.TouchEnabled` devices
- **Safe areas**: Account for device notch and home indicator with `GuiService:GetGuiInset()`

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

- `joystick_position` (UDim2) - Position of the virtual joystick
- `joystick_size` (number) - Outer diameter of the joystick in pixels
- `deadzone` (number) - Joystick deadzone fraction 0-1 (default: 0.1)
- `button_text` (string) - Label for touch action button
- `button_image` (string) - rbxassetid:// image for touch button
- `button_position` (UDim2) - Position of the touch button
- `swipe_min_distance` (number) - Minimum swipe distance in pixels (default: 50)
- `pinch_min_zoom` (number) - Minimum zoom level (default: 0.5)
- `pinch_max_zoom` (number) - Maximum zoom level (default: 3.0)
- `pinch_sensitivity` (number) - Pinch zoom sensitivity (default: 0.01)
