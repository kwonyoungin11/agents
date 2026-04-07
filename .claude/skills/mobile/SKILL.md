---
name: mobile
description: |
  Roblox 모바일 UI 시스템 - Mobile UI scaling, virtual joystick, touch buttons, device detection, responsive layouts.
  로블록스 모바일, 가상 조이스틱, 터치 버튼, 디바이스 감지, 반응형 레이아웃, UI 스케일링.
  Mobile-optimized UI framework for Roblox with touch controls, adaptive layouts, and device-aware scaling.
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Grep
  - Glob
effort: high
---

# Roblox Mobile UI System

Production-ready mobile interface framework: device detection, DPI-aware scaling, virtual joystick, touch action buttons, and responsive layout utilities. All modules are strictly typed Luau.

---

## Architecture Overview

```
MobileUISystem
  ├── DeviceDetector           -- Identifies platform, screen size, touch capability
  ├── ResponsiveScaler         -- DPI-aware UI scaling with breakpoints
  ├── VirtualJoystick          -- Draggable on-screen joystick with dead zone
  ├── TouchButtonManager       -- Configurable action buttons with cooldowns
  └── ResponsiveLayout         -- Adaptive grid/stack layout for mixed devices
```

---

## 1. DeviceDetector

Identifies the current device platform, screen dimensions, and input capabilities at runtime.

```luau
--!strict
-- DeviceDetector.lua (ReplicatedStorage or StarterPlayerScripts)

local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

export type DeviceType = "Phone" | "Tablet" | "Desktop" | "Console" | "VR"

export type DeviceInfo = {
    deviceType: DeviceType,
    screenSize: Vector2,
    isTouchEnabled: boolean,
    isKeyboardEnabled: boolean,
    isGamepadEnabled: boolean,
    isAccelerometerEnabled: boolean,
    isGyroscopeEnabled: boolean,
    pixelDensity: number,        -- Approximate DPI scale factor
    safeAreaInsets: {             -- Notch / status bar insets
        top: number,
        bottom: number,
        left: number,
        right: number,
    },
}

local DeviceDetector = {}

function DeviceDetector.Detect(): DeviceInfo
    local viewportSize = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1920, 1080)
    local touchEnabled = UserInputService.TouchEnabled
    local keyboardEnabled = UserInputService.KeyboardEnabled
    local gamepadEnabled = UserInputService.GamepadEnabled
    local accelEnabled = UserInputService.AccelerometerEnabled
    local gyroEnabled = UserInputService.GyroscopeEnabled

    -- Determine device type
    local deviceType: DeviceType = "Desktop"
    if UserInputService.VREnabled then
        deviceType = "VR"
    elseif gamepadEnabled and not keyboardEnabled and not touchEnabled then
        deviceType = "Console"
    elseif touchEnabled then
        local diagonal = viewportSize.Magnitude
        -- Rough heuristic: phones have smaller viewports
        if diagonal < 1400 then
            deviceType = "Phone"
        else
            deviceType = "Tablet"
        end
    end

    -- Approximate pixel density
    local pixelDensity = 1.0
    if touchEnabled then
        if viewportSize.X > 2000 then
            pixelDensity = 3.0  -- Retina / high-DPI phone
        elseif viewportSize.X > 1200 then
            pixelDensity = 2.0
        else
            pixelDensity = 1.5
        end
    end

    -- Safe area insets (approximate for common devices)
    local insetTop = 0
    local insetBottom = 0
    local guiInset = GuiService:GetGuiInset()
    insetTop = guiInset.Y

    -- iPhones with notch/dynamic island
    if deviceType == "Phone" and viewportSize.Y > 800 then
        insetBottom = 34  -- Home indicator
    end

    return {
        deviceType = deviceType,
        screenSize = viewportSize,
        isTouchEnabled = touchEnabled,
        isKeyboardEnabled = keyboardEnabled,
        isGamepadEnabled = gamepadEnabled,
        isAccelerometerEnabled = accelEnabled,
        isGyroscopeEnabled = gyroEnabled,
        pixelDensity = pixelDensity,
        safeAreaInsets = {
            top = insetTop,
            bottom = insetBottom,
            left = 0,
            right = 0,
        },
    }
end

function DeviceDetector.IsMobile(): boolean
    local info = DeviceDetector.Detect()
    return info.deviceType == "Phone" or info.deviceType == "Tablet"
end

function DeviceDetector.IsPhone(): boolean
    return DeviceDetector.Detect().deviceType == "Phone"
end

function DeviceDetector.IsTablet(): boolean
    return DeviceDetector.Detect().deviceType == "Tablet"
end

function DeviceDetector.IsDesktop(): boolean
    return DeviceDetector.Detect().deviceType == "Desktop"
end

function DeviceDetector.IsConsole(): boolean
    return DeviceDetector.Detect().deviceType == "Console"
end

return DeviceDetector
```

---

## 2. ResponsiveScaler

Scales UI elements based on device DPI and screen breakpoints. Provides a global scale factor that all UI elements can reference.

```luau
--!strict
-- ResponsiveScaler.lua

local Players = game:GetService("Players")

export type Breakpoint = {
    name: string,
    minWidth: number,
    scale: number,
    fontSize: number,
    padding: number,
}

local DEFAULT_BREAKPOINTS: { Breakpoint } = {
    { name = "phone_small", minWidth = 0,    scale = 0.7, fontSize = 12, padding = 4 },
    { name = "phone",       minWidth = 375,  scale = 0.85, fontSize = 14, padding = 6 },
    { name = "tablet",      minWidth = 768,  scale = 1.0, fontSize = 16, padding = 8 },
    { name = "desktop",     minWidth = 1024, scale = 1.0, fontSize = 16, padding = 10 },
    { name = "desktop_xl",  minWidth = 1440, scale = 1.1, fontSize = 18, padding = 12 },
}

local ResponsiveScaler = {}
ResponsiveScaler.__index = ResponsiveScaler

type ScalerImpl = {
    _breakpoints: { Breakpoint },
    _currentBreakpoint: Breakpoint,
    _globalScale: number,
    _onBreakpointChange: BindableEvent,
}

export type ScalerType = typeof(setmetatable({} :: ScalerImpl, ResponsiveScaler))

function ResponsiveScaler.new(customBreakpoints: { Breakpoint }?): ScalerType
    local self = setmetatable({} :: ScalerImpl, ResponsiveScaler)
    self._breakpoints = customBreakpoints or DEFAULT_BREAKPOINTS
    table.sort(self._breakpoints, function(a, b) return a.minWidth < b.minWidth end)
    self._currentBreakpoint = self._breakpoints[1]
    self._globalScale = 1.0
    self._onBreakpointChange = Instance.new("BindableEvent")

    self:_evaluate()

    -- Re-evaluate on viewport resize
    local camera = workspace.CurrentCamera
    if camera then
        camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
            self:_evaluate()
        end)
    end

    return self
end

function ResponsiveScaler._evaluate(self: ScalerType): ()
    local camera = workspace.CurrentCamera
    if not camera then return end
    local width = camera.ViewportSize.X

    local matched = self._breakpoints[1]
    for _, bp in self._breakpoints do
        if width >= bp.minWidth then
            matched = bp
        end
    end

    if matched.name ~= self._currentBreakpoint.name then
        self._currentBreakpoint = matched
        self._globalScale = matched.scale
        self._onBreakpointChange:Fire(matched)
    end
    self._globalScale = matched.scale
end

function ResponsiveScaler.GetScale(self: ScalerType): number
    return self._globalScale
end

function ResponsiveScaler.GetBreakpoint(self: ScalerType): Breakpoint
    return self._currentBreakpoint
end

function ResponsiveScaler.GetFontSize(self: ScalerType, baseSize: number?): number
    local base = baseSize or self._currentBreakpoint.fontSize
    return math.floor(base * self._globalScale + 0.5)
end

function ResponsiveScaler.GetPadding(self: ScalerType): number
    return self._currentBreakpoint.padding
end

-- Scale a UDim2 by the global scale factor
function ResponsiveScaler.ScaleUDim2(self: ScalerType, original: UDim2): UDim2
    local s = self._globalScale
    return UDim2.new(
        original.X.Scale, math.floor(original.X.Offset * s + 0.5),
        original.Y.Scale, math.floor(original.Y.Offset * s + 0.5)
    )
end

function ResponsiveScaler.OnBreakpointChange(self: ScalerType): RBXScriptSignal
    return self._onBreakpointChange.Event
end

function ResponsiveScaler.Destroy(self: ScalerType): ()
    self._onBreakpointChange:Destroy()
end

return ResponsiveScaler
```

---

## 3. VirtualJoystick

A draggable on-screen joystick with configurable dead zone, max radius, and visual feedback. Returns a normalized direction vector.

```luau
--!strict
-- VirtualJoystick.lua

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local VirtualJoystick = {}
VirtualJoystick.__index = VirtualJoystick

type JoystickImpl = {
    _outerCircle: Frame,
    _innerCircle: Frame,
    _screenGui: ScreenGui,
    _center: Vector2,
    _radius: number,
    _deadZone: number,
    _isDragging: boolean,
    _touchId: number?,
    _direction: Vector2,
    _magnitude: number,
    _visible: boolean,
    _dynamicPosition: boolean,
    _connections: { RBXScriptConnection },
}

export type JoystickType = typeof(setmetatable({} :: JoystickImpl, VirtualJoystick))

export type JoystickConfig = {
    position: UDim2?,
    outerSize: number?,
    innerSize: number?,
    deadZone: number?,
    outerColor: Color3?,
    innerColor: Color3?,
    outerTransparency: number?,
    innerTransparency: number?,
    dynamicPosition: boolean?,   -- Joystick appears where finger touches
    side: ("Left" | "Right")?,
}

function VirtualJoystick.new(config: JoystickConfig?): JoystickType
    local cfg = config or {}
    local player = Players.LocalPlayer
    local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

    local outerSize = cfg.outerSize or 150
    local innerSize = cfg.innerSize or 60

    local gui = Instance.new("ScreenGui")
    gui.Name = "VirtualJoystickGui"
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 150
    gui.IgnoreGuiInset = true
    gui.Parent = playerGui

    local defaultPos = cfg.position or UDim2.new(0, 100, 1, -100 - outerSize / 2)

    -- Outer circle (background)
    local outer = Instance.new("Frame")
    outer.Name = "JoystickOuter"
    outer.AnchorPoint = Vector2.new(0.5, 0.5)
    outer.Position = defaultPos
    outer.Size = UDim2.new(0, outerSize, 0, outerSize)
    outer.BackgroundColor3 = cfg.outerColor or Color3.fromRGB(50, 50, 50)
    outer.BackgroundTransparency = cfg.outerTransparency or 0.5
    outer.Parent = gui

    local outerCorner = Instance.new("UICorner")
    outerCorner.CornerRadius = UDim.new(1, 0)
    outerCorner.Parent = outer

    local outerStroke = Instance.new("UIStroke")
    outerStroke.Color = Color3.fromRGB(100, 100, 100)
    outerStroke.Thickness = 2
    outerStroke.Transparency = 0.5
    outerStroke.Parent = outer

    -- Inner circle (thumb)
    local inner = Instance.new("Frame")
    inner.Name = "JoystickInner"
    inner.AnchorPoint = Vector2.new(0.5, 0.5)
    inner.Position = UDim2.new(0.5, 0, 0.5, 0)
    inner.Size = UDim2.new(0, innerSize, 0, innerSize)
    inner.BackgroundColor3 = cfg.innerColor or Color3.fromRGB(180, 180, 180)
    inner.BackgroundTransparency = cfg.innerTransparency or 0.3
    inner.Parent = outer

    local innerCorner = Instance.new("UICorner")
    innerCorner.CornerRadius = UDim.new(1, 0)
    innerCorner.Parent = inner

    local self = setmetatable({} :: JoystickImpl, VirtualJoystick)
    self._outerCircle = outer
    self._innerCircle = inner
    self._screenGui = gui
    self._center = Vector2.new(0, 0)
    self._radius = outerSize / 2
    self._deadZone = cfg.deadZone or 0.15
    self._isDragging = false
    self._touchId = nil
    self._direction = Vector2.zero
    self._magnitude = 0
    self._visible = true
    self._dynamicPosition = cfg.dynamicPosition or false
    self._connections = {}

    self:_setupInput(cfg.side or "Left")
    return self
end

function VirtualJoystick._setupInput(self: JoystickType, side: "Left" | "Right"): ()
    local conn1 = UserInputService.TouchStarted:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        if self._isDragging then return end

        local pos = input.Position
        local screenWidth = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize.X or 1920
        local isCorrectSide = if side == "Left" then pos.X < screenWidth / 2 else pos.X >= screenWidth / 2

        if not isCorrectSide then return end

        if self._dynamicPosition then
            self._outerCircle.Position = UDim2.new(0, pos.X, 0, pos.Y)
            self._center = Vector2.new(pos.X, pos.Y)
        else
            local absPos = self._outerCircle.AbsolutePosition
            local absSize = self._outerCircle.AbsoluteSize
            self._center = absPos + absSize / 2
        end

        local dist = (Vector2.new(pos.X, pos.Y) - self._center).Magnitude
        if self._dynamicPosition or dist <= self._radius then
            self._isDragging = true
            self._touchId = input.UserInputState.Value -- track the touch
            self:_updateThumb(Vector2.new(pos.X, pos.Y))
        end
    end)

    local conn2 = UserInputService.TouchMoved:Connect(function(input, _)
        if not self._isDragging then return end
        self:_updateThumb(Vector2.new(input.Position.X, input.Position.Y))
    end)

    local conn3 = UserInputService.TouchEnded:Connect(function(input, _)
        if not self._isDragging then return end
        self._isDragging = false
        self._touchId = nil
        self._direction = Vector2.zero
        self._magnitude = 0
        self._innerCircle.Position = UDim2.new(0.5, 0, 0.5, 0)
    end)

    table.insert(self._connections, conn1)
    table.insert(self._connections, conn2)
    table.insert(self._connections, conn3)
end

function VirtualJoystick._updateThumb(self: JoystickType, touchPos: Vector2): ()
    local delta = touchPos - self._center
    local dist = delta.Magnitude
    local maxDist = self._radius

    -- Clamp to outer circle
    if dist > maxDist then
        delta = delta.Unit * maxDist
        dist = maxDist
    end

    -- Update inner circle position
    self._innerCircle.Position = UDim2.new(0.5, delta.X, 0.5, delta.Y)

    -- Calculate normalized direction with dead zone
    local normalized = dist / maxDist
    if normalized < self._deadZone then
        self._direction = Vector2.zero
        self._magnitude = 0
    else
        -- Remap so dead zone maps to 0 and max maps to 1
        local remapped = (normalized - self._deadZone) / (1 - self._deadZone)
        self._direction = delta.Unit
        self._magnitude = remapped
    end
end

function VirtualJoystick.GetDirection(self: JoystickType): Vector2
    return self._direction
end

function VirtualJoystick.GetMagnitude(self: JoystickType): number
    return self._magnitude
end

-- Returns a Vector3 suitable for character movement (X = left/right, Z = forward/back)
function VirtualJoystick.GetMoveVector(self: JoystickType): Vector3
    if self._magnitude < 0.01 then
        return Vector3.zero
    end
    return Vector3.new(self._direction.X, 0, self._direction.Y) * self._magnitude
end

function VirtualJoystick.SetVisible(self: JoystickType, visible: boolean): ()
    self._visible = visible
    self._screenGui.Enabled = visible
end

function VirtualJoystick.SetEnabled(self: JoystickType, enabled: boolean): ()
    self._screenGui.Enabled = enabled
    if not enabled then
        self._isDragging = false
        self._direction = Vector2.zero
        self._magnitude = 0
        self._innerCircle.Position = UDim2.new(0.5, 0, 0.5, 0)
    end
end

function VirtualJoystick.Destroy(self: JoystickType): ()
    for _, conn in self._connections do
        conn:Disconnect()
    end
    self._screenGui:Destroy()
end

return VirtualJoystick
```

---

## 4. TouchButtonManager

Creates configurable on-screen action buttons for mobile players with cooldown support and visual feedback.

```luau
--!strict
-- TouchButtonManager.lua

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

export type TouchButtonConfig = {
    name: string,
    icon: string?,           -- Image asset ID
    text: string?,           -- Fallback text if no icon
    position: UDim2,
    size: UDim2?,
    color: Color3?,
    cooldown: number?,       -- Seconds before button can be pressed again
    holdable: boolean?,      -- If true, fires continuously while held
    callback: (isPressed: boolean) -> (),
}

local TouchButtonManager = {}
TouchButtonManager.__index = TouchButtonManager

type ManagerImpl = {
    _screenGui: ScreenGui?,
    _container: Frame?,
    _buttons: { [string]: {
        frame: Frame,
        config: TouchButtonConfig,
        cooldownRemaining: number,
        isPressed: boolean,
    } },
}

export type ManagerType = typeof(setmetatable({} :: ManagerImpl, TouchButtonManager))

function TouchButtonManager.new(): ManagerType
    local self = setmetatable({} :: ManagerImpl, TouchButtonManager)
    self._buttons = {}
    self:_createContainer()
    return self
end

function TouchButtonManager._createContainer(self: ManagerType): ()
    local player = Players.LocalPlayer
    if not player then return end
    local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

    local gui = Instance.new("ScreenGui")
    gui.Name = "TouchButtonsGui"
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 140
    gui.IgnoreGuiInset = true
    gui.Parent = playerGui
    self._screenGui = gui

    local container = Instance.new("Frame")
    container.Name = "ButtonContainer"
    container.Size = UDim2.new(1, 0, 1, 0)
    container.BackgroundTransparency = 1
    container.Parent = gui
    self._container = container
end

function TouchButtonManager.AddButton(self: ManagerType, config: TouchButtonConfig): ()
    if not self._container then return end

    local size = config.size or UDim2.new(0, 70, 0, 70)

    local frame = Instance.new("Frame")
    frame.Name = "TouchBtn_" .. config.name
    frame.AnchorPoint = Vector2.new(0.5, 0.5)
    frame.Position = config.position
    frame.Size = size
    frame.BackgroundColor3 = config.color or Color3.fromRGB(60, 60, 70)
    frame.BackgroundTransparency = 0.3
    frame.Parent = self._container

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0.3, 0)
    corner.Parent = frame

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(150, 150, 160)
    stroke.Thickness = 2
    stroke.Transparency = 0.4
    stroke.Parent = frame

    -- Icon or text
    if config.icon then
        local img = Instance.new("ImageLabel")
        img.Name = "Icon"
        img.Size = UDim2.new(0.6, 0, 0.6, 0)
        img.AnchorPoint = Vector2.new(0.5, 0.5)
        img.Position = UDim2.new(0.5, 0, 0.5, 0)
        img.BackgroundTransparency = 1
        img.Image = config.icon
        img.ImageColor3 = Color3.fromRGB(255, 255, 255)
        img.Parent = frame
    elseif config.text then
        local label = Instance.new("TextLabel")
        label.Name = "Label"
        label.Size = UDim2.new(1, 0, 1, 0)
        label.BackgroundTransparency = 1
        label.TextColor3 = Color3.fromRGB(255, 255, 255)
        label.Font = Enum.Font.GothamBold
        label.TextSize = 16
        label.Text = config.text
        label.Parent = frame
    end

    -- Cooldown overlay
    local cooldownOverlay = Instance.new("Frame")
    cooldownOverlay.Name = "CooldownOverlay"
    cooldownOverlay.Size = UDim2.new(1, 0, 0, 0)
    cooldownOverlay.AnchorPoint = Vector2.new(0, 1)
    cooldownOverlay.Position = UDim2.new(0, 0, 1, 0)
    cooldownOverlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    cooldownOverlay.BackgroundTransparency = 0.5
    cooldownOverlay.ZIndex = 2
    cooldownOverlay.Parent = frame

    local overlayCorner = Instance.new("UICorner")
    overlayCorner.CornerRadius = UDim.new(0.3, 0)
    overlayCorner.Parent = cooldownOverlay

    -- Input detection via invisible button
    local btn = Instance.new("TextButton")
    btn.Name = "HitArea"
    btn.Size = UDim2.new(1, 0, 1, 0)
    btn.BackgroundTransparency = 1
    btn.Text = ""
    btn.ZIndex = 3
    btn.Parent = frame

    local buttonData = {
        frame = frame,
        config = config,
        cooldownRemaining = 0,
        isPressed = false,
    }
    self._buttons[config.name] = buttonData

    btn.MouseButton1Down:Connect(function()
        if buttonData.cooldownRemaining > 0 then return end
        buttonData.isPressed = true
        config.callback(true)

        -- Visual feedback: scale down
        TweenService:Create(frame, TweenInfo.new(0.1), { Size = size - UDim2.new(0, 6, 0, 6) }):Play()

        -- Start cooldown if specified
        if config.cooldown and config.cooldown > 0 then
            buttonData.cooldownRemaining = config.cooldown
            local cd = config.cooldown
            -- Animate cooldown overlay
            cooldownOverlay.Size = UDim2.new(1, 0, 1, 0)
            TweenService:Create(cooldownOverlay, TweenInfo.new(cd, Enum.EasingStyle.Linear), {
                Size = UDim2.new(1, 0, 0, 0),
            }):Play()

            task.delay(cd, function()
                buttonData.cooldownRemaining = 0
            end)
        end
    end)

    btn.MouseButton1Up:Connect(function()
        buttonData.isPressed = false
        config.callback(false)
        TweenService:Create(frame, TweenInfo.new(0.1), { Size = size }):Play()
    end)
end

function TouchButtonManager.RemoveButton(self: ManagerType, name: string): ()
    local data = self._buttons[name]
    if data then
        data.frame:Destroy()
        self._buttons[name] = nil
    end
end

function TouchButtonManager.SetButtonEnabled(self: ManagerType, name: string, enabled: boolean): ()
    local data = self._buttons[name]
    if data then
        data.frame.Visible = enabled
    end
end

function TouchButtonManager.IsPressed(self: ManagerType, name: string): boolean
    local data = self._buttons[name]
    return if data then data.isPressed else false
end

function TouchButtonManager.SetVisible(self: ManagerType, visible: boolean): ()
    if self._screenGui then
        self._screenGui.Enabled = visible
    end
end

function TouchButtonManager.Destroy(self: ManagerType): ()
    if self._screenGui then self._screenGui:Destroy() end
end

return TouchButtonManager
```

---

## 5. ResponsiveLayout

Adaptive container that switches between grid and stack layouts based on available space.

```luau
--!strict
-- ResponsiveLayout.lua

export type LayoutMode = "Grid" | "HorizontalStack" | "VerticalStack" | "Wrap"

export type ResponsiveLayoutConfig = {
    mode: LayoutMode,
    cellSize: UDim2?,
    spacing: UDim?,
    columns: number?,
    maxColumns: number?,
    padding: UDim?,
    autoSwitch: boolean?,    -- Auto-switch between grid and stack based on width
    switchThreshold: number?, -- Width below which we switch to VerticalStack
}

local ResponsiveLayout = {}
ResponsiveLayout.__index = ResponsiveLayout

type LayoutImpl = {
    _container: Frame,
    _config: ResponsiveLayoutConfig,
    _layoutObject: UIGridLayout | UIListLayout,
    _resizeConn: RBXScriptConnection?,
}

export type LayoutType = typeof(setmetatable({} :: LayoutImpl, ResponsiveLayout))

function ResponsiveLayout.new(container: Frame, config: ResponsiveLayoutConfig): LayoutType
    local self = setmetatable({} :: LayoutImpl, ResponsiveLayout)
    self._container = container
    self._config = config
    self._layoutObject = nil :: any

    self:_applyLayout()

    if config.autoSwitch then
        self._resizeConn = container:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
            self:_evaluateAutoSwitch()
        end)
    end

    return self
end

function ResponsiveLayout._applyLayout(self: LayoutType): ()
    -- Remove existing layout
    for _, child in self._container:GetChildren() do
        if child:IsA("UIGridLayout") or child:IsA("UIListLayout") then
            child:Destroy()
        end
    end

    local mode = self._config.mode
    local spacing = self._config.spacing or UDim.new(0, 8)

    if mode == "Grid" then
        local grid = Instance.new("UIGridLayout")
        grid.CellSize = self._config.cellSize or UDim2.new(0, 100, 0, 100)
        grid.CellPadding = UDim2.new(spacing.Scale, spacing.Offset, spacing.Scale, spacing.Offset)
        grid.SortOrder = Enum.SortOrder.LayoutOrder
        grid.FillDirectionMaxCells = self._config.maxColumns or 0
        grid.Parent = self._container
        self._layoutObject = grid
    elseif mode == "HorizontalStack" then
        local list = Instance.new("UIListLayout")
        list.FillDirection = Enum.FillDirection.Horizontal
        list.SortOrder = Enum.SortOrder.LayoutOrder
        list.Padding = spacing
        list.Parent = self._container
        self._layoutObject = list
    elseif mode == "VerticalStack" then
        local list = Instance.new("UIListLayout")
        list.FillDirection = Enum.FillDirection.Vertical
        list.SortOrder = Enum.SortOrder.LayoutOrder
        list.Padding = spacing
        list.Parent = self._container
        self._layoutObject = list
    elseif mode == "Wrap" then
        local grid = Instance.new("UIGridLayout")
        grid.CellSize = self._config.cellSize or UDim2.new(0, 100, 0, 100)
        grid.CellPadding = UDim2.new(spacing.Scale, spacing.Offset, spacing.Scale, spacing.Offset)
        grid.SortOrder = Enum.SortOrder.LayoutOrder
        grid.FillDirection = Enum.FillDirection.Horizontal
        grid.Parent = self._container
        self._layoutObject = grid
    end

    -- Add padding if specified
    if self._config.padding then
        local existing = self._container:FindFirstChildOfClass("UIPadding")
        if not existing then
            local pad = Instance.new("UIPadding")
            pad.PaddingTop = self._config.padding
            pad.PaddingBottom = self._config.padding
            pad.PaddingLeft = self._config.padding
            pad.PaddingRight = self._config.padding
            pad.Parent = self._container
        end
    end
end

function ResponsiveLayout._evaluateAutoSwitch(self: LayoutType): ()
    local threshold = self._config.switchThreshold or 500
    local width = self._container.AbsoluteSize.X

    local newMode: LayoutMode
    if width < threshold then
        newMode = "VerticalStack"
    else
        newMode = self._config.mode  -- Restore original
    end

    if newMode ~= self._config.mode then
        local originalMode = self._config.mode
        self._config.mode = newMode
        self:_applyLayout()
        self._config.mode = originalMode  -- Keep original for future switches back
    end
end

function ResponsiveLayout.SetMode(self: LayoutType, mode: LayoutMode): ()
    self._config.mode = mode
    self:_applyLayout()
end

function ResponsiveLayout.Destroy(self: LayoutType): ()
    if self._resizeConn then
        self._resizeConn:Disconnect()
    end
end

return ResponsiveLayout
```

---

## Usage Example

```luau
local DeviceDetector = require(script.DeviceDetector)
local ResponsiveScaler = require(script.ResponsiveScaler)
local VirtualJoystick = require(script.VirtualJoystick)
local TouchButtonManager = require(script.TouchButtonManager)

local device = DeviceDetector.Detect()
local scaler = ResponsiveScaler.new()

-- Only show touch controls on mobile
if device.isTouchEnabled then
    local joystick = VirtualJoystick.new({
        side = "Left",
        dynamicPosition = true,
        deadZone = 0.2,
    })

    local buttons = TouchButtonManager.new()
    buttons:AddButton({
        name = "Jump",
        text = "JUMP",
        position = UDim2.new(1, -80, 1, -160),
        size = UDim2.new(0, 70, 0, 70),
        color = Color3.fromRGB(50, 120, 200),
        callback = function(pressed)
            if pressed then
                local humanoid = Players.LocalPlayer.Character
                    and Players.LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
                if humanoid then humanoid:ChangeState(Enum.HumanoidStateType.Jumping) end
            end
        end,
    })

    buttons:AddButton({
        name = "Attack",
        text = "ATK",
        position = UDim2.new(1, -170, 1, -110),
        size = UDim2.new(0, 65, 0, 65),
        color = Color3.fromRGB(200, 50, 50),
        cooldown = 0.5,
        callback = function(pressed)
            if pressed then print("Attack!") end
        end,
    })

    -- Use joystick input to move character
    RunService.RenderStepped:Connect(function()
        local moveVector = joystick:GetMoveVector()
        -- Apply to humanoid MoveDirection or vehicle throttle
    end)
end
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

- `$GAME_TYPE` - Game genre to tailor default button layouts (e.g., "RPG", "FPS", "Platformer").
- `$JOYSTICK_SIDE` - Which side the joystick appears on: "Left" or "Right".
- `$DYNAMIC_JOYSTICK` - Whether joystick appears at touch point: "true" or "false".
- `$ACTION_BUTTONS` - JSON array of action button configs (name, position, cooldown).
- `$BREAKPOINTS` - Custom breakpoint definitions or "default".
- `$SAFE_AREA` - Whether to respect device safe areas (notch, etc.): "true" or "false".
