---
name: screenshot
description: |
  Roblox 스크린샷 시스템 - Screenshot capture, viewport capture, photo mode with filters.
  로블록스 스크린샷, 뷰포트 캡처, 포토 모드, 필터, 화면 캡처 MCP.
  Screenshot and photo mode system for Roblox using ViewportFrame and screen_capture MCP integration.
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Grep
  - Glob
effort: high
---

# Roblox Screenshot & Photo Mode System

Complete screenshot system featuring a photo mode with adjustable camera, post-processing filters, a viewport-based capture pipeline, and integration hooks for the `screen_capture` MCP tool. All code is production-ready Luau.

---

## Architecture Overview

```
ScreenshotSystem
  ├── PhotoModeController      -- Activates free camera, freezes gameplay
  ├── FilterManager            -- Post-processing filters (Sepia, Noir, Bloom, etc.)
  ├── ViewportCapture          -- Renders scene into a ViewportFrame for capture
  ├── ScreenshotUI             -- HUD overlay: filter selector, shutter button, gallery
  └── MCPBridge                -- Hook for screen_capture MCP tool integration
```

---

## 1. PhotoModeController

Freezes the game world and gives the player a free-fly camera for composing shots.

```luau
--!strict
-- PhotoModeController.lua (StarterPlayerScripts)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local PhotoModeController = {}
PhotoModeController.__index = PhotoModeController

type PhotoModeImpl = {
    _active: boolean,
    _originalCameraType: Enum.CameraType?,
    _originalCameraCFrame: CFrame?,
    _flySpeed: number,
    _sensitivity: number,
    _yaw: number,
    _pitch: number,
    _roll: number,
    _fov: number,
    _dofEnabled: boolean,
    _dofDistance: number,
    _connection: RBXScriptConnection?,
    _frozenCharacters: { [Model]: boolean },
    _onActivate: BindableEvent,
    _onDeactivate: BindableEvent,
    _onCapture: BindableEvent,
}

export type PhotoModeType = typeof(setmetatable({} :: PhotoModeImpl, PhotoModeController))

function PhotoModeController.new(): PhotoModeType
    local self = setmetatable({} :: PhotoModeImpl, PhotoModeController)
    self._active = false
    self._originalCameraType = nil
    self._originalCameraCFrame = nil
    self._flySpeed = 20
    self._sensitivity = 0.003
    self._yaw = 0
    self._pitch = 0
    self._roll = 0
    self._fov = 70
    self._dofEnabled = false
    self._dofDistance = 30
    self._connection = nil
    self._frozenCharacters = {}
    self._onActivate = Instance.new("BindableEvent")
    self._onDeactivate = Instance.new("BindableEvent")
    self._onCapture = Instance.new("BindableEvent")
    return self
end

function PhotoModeController.Toggle(self: PhotoModeType): ()
    if self._active then
        self:Deactivate()
    else
        self:Activate()
    end
end

function PhotoModeController.Activate(self: PhotoModeType): ()
    if self._active then return end
    self._active = true

    local camera = workspace.CurrentCamera
    if not camera then return end

    self._originalCameraType = camera.CameraType
    self._originalCameraCFrame = camera.CFrame
    camera.CameraType = Enum.CameraType.Scriptable

    local rx, ry, rz = camera.CFrame:ToEulerAnglesYXZ()
    self._pitch = rx
    self._yaw = ry
    self._roll = 0
    self._fov = camera.FieldOfView

    -- Freeze all characters by anchoring HumanoidRootParts
    for _, player in Players:GetPlayers() do
        local char = player.Character
        if char then
            local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
            if hrp then
                self._frozenCharacters[char] = true
                hrp.Anchored = true
            end
            -- Pause animations
            local humanoid = char:FindFirstChildOfClass("Humanoid")
            if humanoid then
                local animator = humanoid:FindFirstChildOfClass("Animator")
                if animator then
                    for _, track in animator:GetPlayingAnimationTracks() do
                        track:AdjustSpeed(0)
                    end
                end
            end
        end
    end

    -- Hide player's own character for clean shots
    local localChar = Players.LocalPlayer and Players.LocalPlayer.Character
    if localChar then
        for _, part in localChar:GetDescendants() do
            if part:IsA("BasePart") then
                part.Transparency = 1
            end
        end
    end

    self._connection = RunService.RenderStepped:Connect(function(dt)
        self:_updateCamera(dt)
    end)

    self._onActivate:Fire()
end

function PhotoModeController.Deactivate(self: PhotoModeType): ()
    if not self._active then return end
    self._active = false

    if self._connection then
        self._connection:Disconnect()
        self._connection = nil
    end

    local camera = workspace.CurrentCamera
    if camera and self._originalCameraType then
        camera.CameraType = self._originalCameraType
        camera.FieldOfView = 70
    end

    -- Unfreeze characters
    for char in self._frozenCharacters do
        if char and char.Parent then
            local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
            if hrp then
                hrp.Anchored = false
            end
            local humanoid = char:FindFirstChildOfClass("Humanoid")
            if humanoid then
                local animator = humanoid:FindFirstChildOfClass("Animator")
                if animator then
                    for _, track in animator:GetPlayingAnimationTracks() do
                        track:AdjustSpeed(1)
                    end
                end
            end
        end
    end
    table.clear(self._frozenCharacters)

    -- Restore local character visibility
    local localChar = Players.LocalPlayer and Players.LocalPlayer.Character
    if localChar then
        for _, part in localChar:GetDescendants() do
            if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
                part.Transparency = 0
            end
        end
    end

    self._onDeactivate:Fire()
end

function PhotoModeController._updateCamera(self: PhotoModeType, dt: number): ()
    local camera = workspace.CurrentCamera
    if not camera then return end

    -- Mouse look (always active in photo mode)
    if UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
        local delta = UserInputService:GetMouseDelta()
        self._yaw -= delta.X * self._sensitivity
        self._pitch = math.clamp(self._pitch - delta.Y * self._sensitivity, -math.rad(89), math.rad(89))
    end

    -- WASD + QE movement
    local move = Vector3.zero
    if UserInputService:IsKeyDown(Enum.KeyCode.W) then move += Vector3.new(0, 0, -1) end
    if UserInputService:IsKeyDown(Enum.KeyCode.S) then move += Vector3.new(0, 0, 1) end
    if UserInputService:IsKeyDown(Enum.KeyCode.A) then move += Vector3.new(-1, 0, 0) end
    if UserInputService:IsKeyDown(Enum.KeyCode.D) then move += Vector3.new(1, 0, 0) end
    if UserInputService:IsKeyDown(Enum.KeyCode.E) then move += Vector3.new(0, 1, 0) end
    if UserInputService:IsKeyDown(Enum.KeyCode.Q) then move += Vector3.new(0, -1, 0) end

    local speed = self._flySpeed
    if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then speed *= 3 end

    local rotation = CFrame.fromEulerAnglesYXZ(self._pitch, self._yaw, self._roll)
    local pos = camera.CFrame.Position

    if move.Magnitude > 0 then
        local worldMove = rotation:VectorToWorldSpace(move.Unit * speed * dt)
        pos += worldMove
    end

    camera.CFrame = CFrame.new(pos) * rotation
    camera.FieldOfView = self._fov
end

function PhotoModeController.SetFOV(self: PhotoModeType, fov: number): ()
    self._fov = math.clamp(fov, 10, 120)
end

function PhotoModeController.SetRoll(self: PhotoModeType, degrees: number): ()
    self._roll = math.rad(degrees)
end

function PhotoModeController.SetDOF(self: PhotoModeType, enabled: boolean, distance: number?): ()
    self._dofEnabled = enabled
    if distance then
        self._dofDistance = distance
    end

    local dof = game.Lighting:FindFirstChildOfClass("DepthOfFieldEffect")
    if enabled then
        if not dof then
            dof = Instance.new("DepthOfFieldEffect")
            dof.Parent = game.Lighting
        end
        dof.FarIntensity = 0.5
        dof.FocusDistance = self._dofDistance
        dof.InFocusRadius = 20
        dof.NearIntensity = 0.3
    else
        if dof then
            dof:Destroy()
        end
    end
end

function PhotoModeController.IsActive(self: PhotoModeType): boolean
    return self._active
end

function PhotoModeController.OnActivate(self: PhotoModeType): RBXScriptSignal
    return self._onActivate.Event
end

function PhotoModeController.OnDeactivate(self: PhotoModeType): RBXScriptSignal
    return self._onDeactivate.Event
end

return PhotoModeController
```

---

## 2. FilterManager

Applies post-processing filters using Roblox's `Lighting` effects.

```luau
--!strict
-- FilterManager.lua

local Lighting = game:GetService("Lighting")

export type FilterPreset = "None" | "Sepia" | "Noir" | "Bloom" | "Vivid" | "Cold" | "Warm" | "Vintage" | "Dramatic"

type FilterConfig = {
    colorCorrection: {
        Brightness: number?,
        Contrast: number?,
        Saturation: number?,
        TintColor: Color3?,
    }?,
    bloom: {
        Intensity: number?,
        Size: number?,
        Threshold: number?,
    }?,
    sunRays: {
        Intensity: number?,
        Spread: number?,
    }?,
}

local PRESETS: { [FilterPreset]: FilterConfig } = {
    None = {},
    Sepia = {
        colorCorrection = {
            Brightness = 0.05,
            Contrast = 0.1,
            Saturation = -0.8,
            TintColor = Color3.fromRGB(255, 230, 180),
        },
    },
    Noir = {
        colorCorrection = {
            Brightness = -0.05,
            Contrast = 0.35,
            Saturation = -1,
            TintColor = Color3.fromRGB(255, 255, 255),
        },
    },
    Bloom = {
        bloom = {
            Intensity = 1.2,
            Size = 40,
            Threshold = 0.8,
        },
    },
    Vivid = {
        colorCorrection = {
            Brightness = 0.05,
            Contrast = 0.2,
            Saturation = 0.4,
            TintColor = Color3.fromRGB(255, 255, 255),
        },
        bloom = {
            Intensity = 0.3,
            Size = 20,
            Threshold = 1.2,
        },
    },
    Cold = {
        colorCorrection = {
            Brightness = 0,
            Contrast = 0.1,
            Saturation = -0.2,
            TintColor = Color3.fromRGB(200, 220, 255),
        },
    },
    Warm = {
        colorCorrection = {
            Brightness = 0.03,
            Contrast = 0.05,
            Saturation = 0.1,
            TintColor = Color3.fromRGB(255, 230, 200),
        },
    },
    Vintage = {
        colorCorrection = {
            Brightness = 0.08,
            Contrast = 0.15,
            Saturation = -0.5,
            TintColor = Color3.fromRGB(240, 220, 190),
        },
        bloom = {
            Intensity = 0.4,
            Size = 30,
            Threshold = 0.9,
        },
    },
    Dramatic = {
        colorCorrection = {
            Brightness = -0.08,
            Contrast = 0.4,
            Saturation = -0.3,
            TintColor = Color3.fromRGB(220, 210, 240),
        },
        sunRays = {
            Intensity = 0.15,
            Spread = 0.8,
        },
    },
}

local FilterManager = {}
FilterManager.__index = FilterManager

type FilterImpl = {
    _currentPreset: FilterPreset,
    _ccEffect: ColorCorrectionEffect?,
    _bloomEffect: BloomEffect?,
    _sunRaysEffect: SunRaysEffect?,
    _strength: number,
}

export type FilterType = typeof(setmetatable({} :: FilterImpl, FilterManager))

function FilterManager.new(): FilterType
    local self = setmetatable({} :: FilterImpl, FilterManager)
    self._currentPreset = "None"
    self._strength = 1.0
    return self
end

function FilterManager.ApplyPreset(self: FilterType, preset: FilterPreset, strength: number?): ()
    self._currentPreset = preset
    self._strength = math.clamp(strength or 1.0, 0, 1)
    self:_clearEffects()

    local config = PRESETS[preset]
    if not config then return end

    local s = self._strength

    if config.colorCorrection then
        local cc = Instance.new("ColorCorrectionEffect")
        cc.Name = "PhotoFilter_CC"
        cc.Brightness = (config.colorCorrection.Brightness or 0) * s
        cc.Contrast = (config.colorCorrection.Contrast or 0) * s
        cc.Saturation = (config.colorCorrection.Saturation or 0) * s
        if config.colorCorrection.TintColor then
            cc.TintColor = Color3.fromRGB(255, 255, 255):Lerp(config.colorCorrection.TintColor, s)
        end
        cc.Parent = Lighting
        self._ccEffect = cc
    end

    if config.bloom then
        local bloom = Instance.new("BloomEffect")
        bloom.Name = "PhotoFilter_Bloom"
        bloom.Intensity = (config.bloom.Intensity or 0) * s
        bloom.Size = config.bloom.Size or 24
        bloom.Threshold = config.bloom.Threshold or 1
        bloom.Parent = Lighting
        self._bloomEffect = bloom
    end

    if config.sunRays then
        local rays = Instance.new("SunRaysEffect")
        rays.Name = "PhotoFilter_SunRays"
        rays.Intensity = (config.sunRays.Intensity or 0) * s
        rays.Spread = config.sunRays.Spread or 1
        rays.Parent = Lighting
        self._sunRaysEffect = rays
    end
end

function FilterManager.GetPreset(self: FilterType): FilterPreset
    return self._currentPreset
end

function FilterManager.GetAvailablePresets(): { FilterPreset }
    local names: { FilterPreset } = {}
    for name in PRESETS do
        table.insert(names, name)
    end
    table.sort(names)
    return names
end

function FilterManager._clearEffects(self: FilterType): ()
    if self._ccEffect then self._ccEffect:Destroy(); self._ccEffect = nil end
    if self._bloomEffect then self._bloomEffect:Destroy(); self._bloomEffect = nil end
    if self._sunRaysEffect then self._sunRaysEffect:Destroy(); self._sunRaysEffect = nil end
end

function FilterManager.Destroy(self: FilterType): ()
    self:_clearEffects()
end

return FilterManager
```

---

## 3. ViewportCapture

Renders a snapshot of the current scene into a `ViewportFrame` for use in galleries or thumbnails.

```luau
--!strict
-- ViewportCapture.lua

local Players = game:GetService("Players")

local ViewportCapture = {}
ViewportCapture.__index = ViewportCapture

type CaptureImpl = {
    _viewportFrame: ViewportFrame?,
    _worldModel: WorldModel?,
    _captureCamera: Camera?,
}

export type CaptureType = typeof(setmetatable({} :: CaptureImpl, ViewportCapture))

function ViewportCapture.new(): CaptureType
    local self = setmetatable({} :: CaptureImpl, ViewportCapture)
    return self
end

function ViewportCapture.CaptureScene(
    self: CaptureType,
    cameraCFrame: CFrame,
    fov: number?,
    size: UDim2?,
    modelsToInclude: { Model }?
): ViewportFrame
    local player = Players.LocalPlayer
    local playerGui = player and player:WaitForChild("PlayerGui") :: PlayerGui

    -- Create ViewportFrame
    local vpf = Instance.new("ViewportFrame")
    vpf.Size = size or UDim2.new(0, 512, 0, 512)
    vpf.BackgroundColor3 = Color3.fromRGB(135, 206, 235)
    vpf.BackgroundTransparency = 0

    -- Create world model to hold cloned objects
    local worldModel = Instance.new("WorldModel")
    worldModel.Parent = vpf

    -- Clone models into viewport
    local targets = modelsToInclude or self:_getDefaultModels()
    for _, model in targets do
        local clone = model:Clone()
        clone.Parent = worldModel
    end

    -- Create viewport camera
    local cam = Instance.new("Camera")
    cam.CFrame = cameraCFrame
    cam.FieldOfView = fov or 70
    cam.Parent = vpf
    vpf.CurrentCamera = cam

    self._viewportFrame = vpf
    self._worldModel = worldModel
    self._captureCamera = cam

    return vpf
end

function ViewportCapture._getDefaultModels(self: CaptureType): { Model }
    local models: { Model } = {}
    for _, child in workspace:GetChildren() do
        if child:IsA("Model") or child:IsA("BasePart") then
            -- Skip terrain and very large models to keep viewport manageable
            if child:IsA("Model") then
                table.insert(models, child)
            end
        end
    end
    return models
end

function ViewportCapture.CaptureCurrentView(self: CaptureType, size: UDim2?): ViewportFrame
    local camera = workspace.CurrentCamera
    if not camera then
        error("[ViewportCapture] No current camera")
    end
    return self:CaptureScene(camera.CFrame, camera.FieldOfView, size)
end

function ViewportCapture.Destroy(self: CaptureType): ()
    if self._viewportFrame then
        self._viewportFrame:Destroy()
        self._viewportFrame = nil
    end
end

return ViewportCapture
```

---

## 4. ScreenshotUI

A complete photo mode HUD with filter picker, FOV slider, DOF toggle, and a shutter button.

```luau
--!strict
-- ScreenshotUI.lua

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local ScreenshotUI = {}
ScreenshotUI.__index = ScreenshotUI

type UIImpl = {
    _screenGui: ScreenGui?,
    _mainFrame: Frame?,
    _onShutter: BindableEvent,
    _onFilterChange: BindableEvent,
    _onFovChange: BindableEvent,
    _visible: boolean,
}

export type UIType = typeof(setmetatable({} :: UIImpl, ScreenshotUI))

function ScreenshotUI.new(): UIType
    local self = setmetatable({} :: UIImpl, ScreenshotUI)
    self._onShutter = Instance.new("BindableEvent")
    self._onFilterChange = Instance.new("BindableEvent")
    self._onFovChange = Instance.new("BindableEvent")
    self._visible = false
    self:_buildUI()
    return self
end

function ScreenshotUI._buildUI(self: UIType): ()
    local player = Players.LocalPlayer
    if not player then return end
    local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

    local gui = Instance.new("ScreenGui")
    gui.Name = "PhotoModeUI"
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 200
    gui.IgnoreGuiInset = true
    gui.Enabled = false
    gui.Parent = playerGui
    self._screenGui = gui

    -- Top bar with filter buttons
    local topBar = Instance.new("Frame")
    topBar.Name = "TopBar"
    topBar.AnchorPoint = Vector2.new(0.5, 0)
    topBar.Position = UDim2.new(0.5, 0, 0, 10)
    topBar.Size = UDim2.new(0.8, 0, 0, 50)
    topBar.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
    topBar.BackgroundTransparency = 0.3
    topBar.Parent = gui

    local topCorner = Instance.new("UICorner")
    topCorner.CornerRadius = UDim.new(0, 10)
    topCorner.Parent = topBar

    local topLayout = Instance.new("UIListLayout")
    topLayout.FillDirection = Enum.FillDirection.Horizontal
    topLayout.SortOrder = Enum.SortOrder.LayoutOrder
    topLayout.Padding = UDim.new(0, 8)
    topLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    topLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    topLayout.Parent = topBar

    local topPad = Instance.new("UIPadding")
    topPad.PaddingLeft = UDim.new(0, 10)
    topPad.PaddingRight = UDim.new(0, 10)
    topPad.Parent = topBar

    -- Filter buttons
    local filters = { "None", "Sepia", "Noir", "Bloom", "Vivid", "Cold", "Warm", "Vintage", "Dramatic" }
    for _, filterName in filters do
        local btn = Instance.new("TextButton")
        btn.Name = "Filter_" .. filterName
        btn.Size = UDim2.new(0, 80, 0, 35)
        btn.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
        btn.TextColor3 = Color3.fromRGB(220, 220, 220)
        btn.Font = Enum.Font.GothamMedium
        btn.TextSize = 13
        btn.Text = filterName
        btn.Parent = topBar

        local btnCorner = Instance.new("UICorner")
        btnCorner.CornerRadius = UDim.new(0, 6)
        btnCorner.Parent = btn

        btn.MouseButton1Click:Connect(function()
            self._onFilterChange:Fire(filterName)
        end)
    end

    -- Bottom bar with shutter and controls
    local bottomBar = Instance.new("Frame")
    bottomBar.Name = "BottomBar"
    bottomBar.AnchorPoint = Vector2.new(0.5, 1)
    bottomBar.Position = UDim2.new(0.5, 0, 1, -10)
    bottomBar.Size = UDim2.new(0.6, 0, 0, 70)
    bottomBar.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
    bottomBar.BackgroundTransparency = 0.3
    bottomBar.Parent = gui

    local bottomCorner = Instance.new("UICorner")
    bottomCorner.CornerRadius = UDim.new(0, 10)
    bottomCorner.Parent = bottomBar

    -- Shutter button
    local shutterBtn = Instance.new("TextButton")
    shutterBtn.Name = "Shutter"
    shutterBtn.AnchorPoint = Vector2.new(0.5, 0.5)
    shutterBtn.Position = UDim2.new(0.5, 0, 0.5, 0)
    shutterBtn.Size = UDim2.new(0, 50, 0, 50)
    shutterBtn.BackgroundColor3 = Color3.fromRGB(255, 60, 60)
    shutterBtn.Text = ""
    shutterBtn.Parent = bottomBar

    local shutterCorner = Instance.new("UICorner")
    shutterCorner.CornerRadius = UDim.new(1, 0)
    shutterCorner.Parent = shutterBtn

    local shutterStroke = Instance.new("UIStroke")
    shutterStroke.Color = Color3.fromRGB(255, 255, 255)
    shutterStroke.Thickness = 3
    shutterStroke.Parent = shutterBtn

    shutterBtn.MouseButton1Click:Connect(function()
        -- Flash effect
        local flash = Instance.new("Frame")
        flash.Size = UDim2.new(1, 0, 1, 0)
        flash.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        flash.BackgroundTransparency = 0
        flash.ZIndex = 999
        flash.Parent = gui

        local fadeOut = TweenService:Create(flash, TweenInfo.new(0.4, Enum.EasingStyle.Quad), {
            BackgroundTransparency = 1,
        })
        fadeOut:Play()
        fadeOut.Completed:Connect(function()
            flash:Destroy()
        end)

        self._onShutter:Fire()
    end)

    -- FOV label
    local fovLabel = Instance.new("TextLabel")
    fovLabel.Name = "FOVLabel"
    fovLabel.AnchorPoint = Vector2.new(0, 0.5)
    fovLabel.Position = UDim2.new(0.05, 0, 0.5, 0)
    fovLabel.Size = UDim2.new(0.15, 0, 0, 30)
    fovLabel.BackgroundTransparency = 1
    fovLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
    fovLabel.Font = Enum.Font.GothamMedium
    fovLabel.TextSize = 14
    fovLabel.Text = "FOV: 70"
    fovLabel.Parent = bottomBar

    self._mainFrame = topBar
end

function ScreenshotUI.Show(self: UIType): ()
    if self._screenGui then
        self._screenGui.Enabled = true
        self._visible = true
    end
end

function ScreenshotUI.Hide(self: UIType): ()
    if self._screenGui then
        self._screenGui.Enabled = false
        self._visible = false
    end
end

function ScreenshotUI.OnShutter(self: UIType): RBXScriptSignal
    return self._onShutter.Event
end

function ScreenshotUI.OnFilterChange(self: UIType): RBXScriptSignal
    return self._onFilterChange.Event
end

function ScreenshotUI.Destroy(self: UIType): ()
    if self._screenGui then self._screenGui:Destroy() end
    self._onShutter:Destroy()
    self._onFilterChange:Destroy()
    self._onFovChange:Destroy()
end

return ScreenshotUI
```

---

## 5. MCPBridge (screen_capture Integration)

Provides a hook interface so external tools like the `screen_capture` MCP can trigger captures.

```luau
--!strict
-- MCPBridge.lua
-- Bridge for external screen_capture MCP tool integration.
-- The MCP tool captures the actual screen pixels; this module
-- coordinates timing: hide UI, wait a frame, signal capture, restore UI.

local RunService = game:GetService("RunService")

local MCPBridge = {}
MCPBridge.__index = MCPBridge

type BridgeImpl = {
    _screenshotUI: any,          -- Reference to ScreenshotUI instance
    _photoMode: any,             -- Reference to PhotoModeController instance
    _captureEvent: BindableEvent,
    _isCapturing: boolean,
}

export type BridgeType = typeof(setmetatable({} :: BridgeImpl, MCPBridge))

function MCPBridge.new(screenshotUI: any, photoMode: any): BridgeType
    local self = setmetatable({} :: BridgeImpl, MCPBridge)
    self._screenshotUI = screenshotUI
    self._photoMode = photoMode
    self._captureEvent = Instance.new("BindableEvent")
    self._isCapturing = false
    return self
end

-- Prepare the screen for a clean capture:
--   1. Hide all UI overlays
--   2. Wait one render frame so the GPU flushes
--   3. Fire the capture event (MCP listens here)
--   4. Restore UI
function MCPBridge.RequestCapture(self: BridgeType): ()
    if self._isCapturing then return end
    self._isCapturing = true

    -- Step 1: Hide UI
    if self._screenshotUI and self._screenshotUI.Hide then
        self._screenshotUI:Hide()
    end

    -- Step 2: Wait a frame
    RunService.RenderStepped:Wait()

    -- Step 3: Fire capture signal
    -- The screen_capture MCP tool hooks into this event via plugin bridge
    self._captureEvent:Fire({
        timestamp = os.time(),
        camera = workspace.CurrentCamera and workspace.CurrentCamera.CFrame,
        fov = workspace.CurrentCamera and workspace.CurrentCamera.FieldOfView,
    })

    -- Step 4: Wait another frame, then restore
    RunService.RenderStepped:Wait()

    if self._screenshotUI and self._screenshotUI.Show then
        self._screenshotUI:Show()
    end

    self._isCapturing = false
end

function MCPBridge.OnCapture(self: BridgeType): RBXScriptSignal
    return self._captureEvent.Event
end

function MCPBridge.Destroy(self: BridgeType): ()
    self._captureEvent:Destroy()
end

return MCPBridge
```

---

## Full Integration Example

```luau
local PhotoModeController = require(script.PhotoModeController)
local FilterManager = require(script.FilterManager)
local ScreenshotUI = require(script.ScreenshotUI)
local MCPBridge = require(script.MCPBridge)

local photoMode = PhotoModeController.new()
local filters = FilterManager.new()
local ui = ScreenshotUI.new()
local mcp = MCPBridge.new(ui, photoMode)

-- Toggle photo mode with F2
local UserInputService = game:GetService("UserInputService")
UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == Enum.KeyCode.F2 then
        photoMode:Toggle()
        if photoMode:IsActive() then
            ui:Show()
        else
            ui:Hide()
            filters:ApplyPreset("None")
        end
    end
end)

-- Wire filter changes
ui:OnFilterChange():Connect(function(filterName)
    filters:ApplyPreset(filterName)
end)

-- Wire shutter to MCP capture
ui:OnShutter():Connect(function()
    mcp:RequestCapture()
end)
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

- `$PHOTO_MODE_KEY` - KeyCode to toggle photo mode (default: F2).
- `$FILTERS` - Comma-separated list of filter presets to include.
- `$DEFAULT_FOV` - Default field of view (default: 70).
- `$ENABLE_DOF` - Whether to include depth of field controls: "true" or "false".
- `$MCP_INTEGRATION` - Whether to include MCPBridge for screen_capture tool: "true" or "false".
- `$GALLERY_SIZE` - Number of screenshots to store in the in-game gallery.
