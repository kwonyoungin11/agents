---
name: accessibility
description: |
  Roblox 접근성 시스템 - Colorblind modes, text scaling, subtitle system, control remapping, reduced motion.
  로블록스 접근성, 색맹 모드, 텍스트 크기 조절, 자막 시스템, 키 리매핑, 모션 감소 옵션.
  Accessibility features for inclusive Roblox game design with full Luau implementation.
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Grep
  - Glob
effort: high
---

# Roblox Accessibility System

Comprehensive accessibility system for Roblox experiences. Includes colorblind simulation/correction, dynamic text scaling, a subtitle/caption system, full control remapping, and a reduced motion toggle. All modules are production-ready Luau with proper type annotations.

---

## Architecture Overview

```
AccessibilityManager (orchestrator)
  ├── ColorblindModule        -- Protanopia / Deuteranopia / Tritanopia filters
  ├── TextScalingModule       -- Dynamic font size with min/max clamp
  ├── SubtitleModule          -- Queued subtitle rendering with speaker tags
  ├── ControlRemappingModule  -- Runtime key rebinding persisted to DataStore
  └── ReducedMotionModule     -- Global flag that dampens tweens & particles
```

---

## 1. ColorblindModule

Applies a color-correction overlay using `ColorCorrectionEffect` inside `Lighting`. Three clinical profiles are supported plus a custom-strength slider.

```luau
--!strict
-- ColorblindModule.lua  (StarterPlayerScripts or ReplicatedStorage)

local Lighting = game:GetService("Lighting")

export type ColorblindMode = "None" | "Protanopia" | "Deuteranopia" | "Tritanopia"

local COLOR_MATRICES: { [ColorblindMode]: { Brightness: number, Contrast: number, Saturation: number, TintColor: Color3 } } = {
    None = {
        Brightness = 0,
        Contrast = 0,
        Saturation = 0,
        TintColor = Color3.fromRGB(255, 255, 255),
    },
    Protanopia = {
        Brightness = 0.02,
        Contrast = 0.1,
        Saturation = -0.3,
        TintColor = Color3.fromRGB(230, 230, 255),
    },
    Deuteranopia = {
        Brightness = 0.02,
        Contrast = 0.15,
        Saturation = -0.25,
        TintColor = Color3.fromRGB(255, 240, 220),
    },
    Tritanopia = {
        Brightness = 0.03,
        Contrast = 0.12,
        Saturation = -0.35,
        TintColor = Color3.fromRGB(255, 220, 230),
    },
}

local ColorblindModule = {}
ColorblindModule.__index = ColorblindModule

type ColorblindModuleImpl = {
    _effect: ColorCorrectionEffect?,
    _currentMode: ColorblindMode,
    _strength: number,
}

export type ColorblindModuleType = typeof(setmetatable({} :: ColorblindModuleImpl, ColorblindModule))

function ColorblindModule.new(): ColorblindModuleType
    local self = setmetatable({} :: ColorblindModuleImpl, ColorblindModule)
    self._currentMode = "None"
    self._strength = 1.0
    self:_ensureEffect()
    return self
end

function ColorblindModule._ensureEffect(self: ColorblindModuleType): ()
    if not self._effect or not self._effect.Parent then
        local effect = Instance.new("ColorCorrectionEffect")
        effect.Name = "AccessibilityColorCorrection"
        effect.Parent = Lighting
        self._effect = effect
    end
end

function ColorblindModule.SetMode(self: ColorblindModuleType, mode: ColorblindMode, strength: number?): ()
    self._currentMode = mode
    self._strength = math.clamp(strength or 1.0, 0, 1)
    self:_applyCorrection()
end

function ColorblindModule.GetMode(self: ColorblindModuleType): ColorblindMode
    return self._currentMode
end

function ColorblindModule._applyCorrection(self: ColorblindModuleType): ()
    self:_ensureEffect()
    local profile = COLOR_MATRICES[self._currentMode]
    if not profile or not self._effect then
        return
    end
    local s = self._strength
    self._effect.Brightness = profile.Brightness * s
    self._effect.Contrast = profile.Contrast * s
    self._effect.Saturation = profile.Saturation * s
    self._effect.TintColor = Color3.fromRGB(255, 255, 255):Lerp(profile.TintColor, s)
end

function ColorblindModule.Destroy(self: ColorblindModuleType): ()
    if self._effect then
        self._effect:Destroy()
        self._effect = nil
    end
end

return ColorblindModule
```

---

## 2. TextScalingModule

Dynamically adjusts all `TextLabel`, `TextButton`, and `TextBox` sizes within a ScreenGui hierarchy. Respects a configurable min/max range and stores preference via player attributes.

```luau
--!strict
-- TextScalingModule.lua

local Players = game:GetService("Players")

local DEFAULT_SCALE = 1.0
local MIN_SCALE = 0.6
local MAX_SCALE = 2.5
local STEP = 0.1

local TextScalingModule = {}
TextScalingModule.__index = TextScalingModule

type TextScalingImpl = {
    _scale: number,
    _baselineSizes: { [TextLabel | TextButton | TextBox]: number },
    _screenGui: ScreenGui?,
}

export type TextScalingType = typeof(setmetatable({} :: TextScalingImpl, TextScalingModule))

function TextScalingModule.new(screenGui: ScreenGui?): TextScalingType
    local self = setmetatable({} :: TextScalingImpl, TextScalingModule)
    self._scale = DEFAULT_SCALE
    self._baselineSizes = {}
    self._screenGui = screenGui
    if screenGui then
        self:_cacheBaselines(screenGui)
    end
    return self
end

function TextScalingModule._cacheBaselines(self: TextScalingType, root: Instance): ()
    for _, desc in root:GetDescendants() do
        if desc:IsA("TextLabel") or desc:IsA("TextButton") or desc:IsA("TextBox") then
            local textObj = desc :: TextLabel
            if not self._baselineSizes[textObj] then
                self._baselineSizes[textObj] = textObj.TextSize
            end
        end
    end
end

function TextScalingModule.SetScale(self: TextScalingType, scale: number): ()
    self._scale = math.clamp(scale, MIN_SCALE, MAX_SCALE)
    self:_applyScale()
    local player = Players.LocalPlayer
    if player then
        player:SetAttribute("AccessibilityTextScale", self._scale)
    end
end

function TextScalingModule.Increase(self: TextScalingType): ()
    self:SetScale(self._scale + STEP)
end

function TextScalingModule.Decrease(self: TextScalingType): ()
    self:SetScale(self._scale - STEP)
end

function TextScalingModule.GetScale(self: TextScalingType): number
    return self._scale
end

function TextScalingModule._applyScale(self: TextScalingType): ()
    for obj, baseline in self._baselineSizes do
        if obj and obj.Parent then
            (obj :: TextLabel).TextSize = math.floor(baseline * self._scale + 0.5)
        end
    end
end

function TextScalingModule.RegisterGui(self: TextScalingType, screenGui: ScreenGui): ()
    self._screenGui = screenGui
    self:_cacheBaselines(screenGui)
    self:_applyScale()
    screenGui.DescendantAdded:Connect(function(desc)
        if desc:IsA("TextLabel") or desc:IsA("TextButton") or desc:IsA("TextBox") then
            local textObj = desc :: TextLabel
            self._baselineSizes[textObj] = textObj.TextSize
            textObj.TextSize = math.floor(textObj.TextSize * self._scale + 0.5)
        end
    end)
end

return TextScalingModule
```

---

## 3. SubtitleModule

Displays queued subtitles at the bottom of the screen with speaker name, color-coded tags, and configurable display duration.

```luau
--!strict
-- SubtitleModule.lua

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

export type SubtitleEntry = {
    speaker: string?,
    text: string,
    duration: number?,
    color: Color3?,
}

local DEFAULTS = {
    duration = 3.0,
    color = Color3.fromRGB(255, 255, 255),
    speakerColor = Color3.fromRGB(200, 200, 120),
    maxVisible = 3,
    fontSize = 18,
    padding = UDim.new(0, 6),
    fadeTime = 0.3,
    backgroundColor = Color3.fromRGB(0, 0, 0),
    backgroundTransparency = 0.4,
}

local SubtitleModule = {}
SubtitleModule.__index = SubtitleModule

type SubtitleImpl = {
    _queue: { SubtitleEntry },
    _activeLabels: { TextLabel },
    _container: Frame?,
    _screenGui: ScreenGui?,
    _enabled: boolean,
}

export type SubtitleType = typeof(setmetatable({} :: SubtitleImpl, SubtitleModule))

function SubtitleModule.new(): SubtitleType
    local self = setmetatable({} :: SubtitleImpl, SubtitleModule)
    self._queue = {}
    self._activeLabels = {}
    self._enabled = true
    self:_createUI()
    return self
end

function SubtitleModule._createUI(self: SubtitleType): ()
    local player = Players.LocalPlayer
    if not player then return end
    local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "SubtitleGui"
    screenGui.ResetOnSpawn = false
    screenGui.DisplayOrder = 100
    screenGui.IgnoreGuiInset = true
    screenGui.Parent = playerGui

    local container = Instance.new("Frame")
    container.Name = "SubtitleContainer"
    container.AnchorPoint = Vector2.new(0.5, 1)
    container.Position = UDim2.new(0.5, 0, 1, -60)
    container.Size = UDim2.new(0.6, 0, 0, 0)
    container.AutomaticSize = Enum.AutomaticSize.Y
    container.BackgroundTransparency = 1
    container.Parent = screenGui

    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Vertical
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = DEFAULTS.padding
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    layout.Parent = container

    self._screenGui = screenGui
    self._container = container
end

function SubtitleModule.Show(self: SubtitleType, entry: SubtitleEntry): ()
    if not self._enabled or not self._container then return end

    while #self._activeLabels >= DEFAULTS.maxVisible do
        local oldest = table.remove(self._activeLabels, 1)
        if oldest and oldest.Parent then oldest:Destroy() end
    end

    local label = Instance.new("TextLabel")
    label.AutomaticSize = Enum.AutomaticSize.XY
    label.BackgroundColor3 = DEFAULTS.backgroundColor
    label.BackgroundTransparency = DEFAULTS.backgroundTransparency
    label.TextColor3 = entry.color or DEFAULTS.color
    label.TextSize = DEFAULTS.fontSize
    label.Font = Enum.Font.GothamMedium
    label.TextWrapped = true
    label.RichText = true
    label.TextTransparency = 1
    label.Size = UDim2.new(1, 0, 0, 0)

    local padding = Instance.new("UIPadding")
    padding.PaddingLeft = UDim.new(0, 10)
    padding.PaddingRight = UDim.new(0, 10)
    padding.PaddingTop = UDim.new(0, 4)
    padding.PaddingBottom = UDim.new(0, 4)
    padding.Parent = label

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = label

    local displayText = ""
    if entry.speaker then
        local r = math.floor(DEFAULTS.speakerColor.R * 255)
        local g = math.floor(DEFAULTS.speakerColor.G * 255)
        local b = math.floor(DEFAULTS.speakerColor.B * 255)
        displayText = string.format('<font color="rgb(%d,%d,%d)"><b>[%s]</b></font> ', r, g, b, entry.speaker)
    end
    displayText ..= entry.text
    label.Text = displayText
    label.Parent = self._container
    table.insert(self._activeLabels, label)

    local fadeIn = TweenService:Create(label, TweenInfo.new(DEFAULTS.fadeTime), { TextTransparency = 0 })
    fadeIn:Play()

    local duration = entry.duration or DEFAULTS.duration
    task.delay(duration, function()
        if not label.Parent then return end
        local fadeOut = TweenService:Create(label, TweenInfo.new(DEFAULTS.fadeTime), { TextTransparency = 1 })
        fadeOut:Play()
        fadeOut.Completed:Wait()
        local idx = table.find(self._activeLabels, label)
        if idx then table.remove(self._activeLabels, idx) end
        label:Destroy()
    end)
end

function SubtitleModule.SetEnabled(self: SubtitleType, enabled: boolean): ()
    self._enabled = enabled
    if not enabled and self._container then
        for _, label in self._activeLabels do label:Destroy() end
        table.clear(self._activeLabels)
    end
end

function SubtitleModule.Destroy(self: SubtitleType): ()
    if self._screenGui then self._screenGui:Destroy() end
end

return SubtitleModule
```

---

## 4. ControlRemappingModule

Allows players to rebind actions to different keys at runtime. Bindings are serializable for DataStore persistence.

```luau
--!strict
-- ControlRemappingModule.lua

local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

export type ActionBinding = {
    actionName: string,
    displayName: string,
    defaultKey: Enum.KeyCode,
    currentKey: Enum.KeyCode,
    callback: (actionName: string, inputState: Enum.UserInputState, inputObject: InputObject) -> Enum.ContextActionResult?,
}

local ControlRemappingModule = {}
ControlRemappingModule.__index = ControlRemappingModule

type ControlRemapImpl = {
    _bindings: { [string]: ActionBinding },
    _isListeningForRebind: boolean,
    _rebindTarget: string?,
    _onRebindComplete: ((actionName: string, newKey: Enum.KeyCode) -> ())?,
}

export type ControlRemapType = typeof(setmetatable({} :: ControlRemapImpl, ControlRemappingModule))

function ControlRemappingModule.new(): ControlRemapType
    local self = setmetatable({} :: ControlRemapImpl, ControlRemappingModule)
    self._bindings = {}
    self._isListeningForRebind = false
    self._rebindTarget = nil
    self._onRebindComplete = nil

    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        if self._isListeningForRebind and self._rebindTarget then
            if input.UserInputType == Enum.UserInputType.Keyboard then
                self:_completeRebind(input.KeyCode)
            end
        end
    end)
    return self
end

function ControlRemappingModule.RegisterAction(
    self: ControlRemapType,
    actionName: string,
    displayName: string,
    defaultKey: Enum.KeyCode,
    callback: (string, Enum.UserInputState, InputObject) -> Enum.ContextActionResult?
): ()
    local binding: ActionBinding = {
        actionName = actionName,
        displayName = displayName,
        defaultKey = defaultKey,
        currentKey = defaultKey,
        callback = callback,
    }
    self._bindings[actionName] = binding
    ContextActionService:BindAction(actionName, callback, false, defaultKey)
end

function ControlRemappingModule.StartRebind(
    self: ControlRemapType,
    actionName: string,
    onComplete: ((actionName: string, newKey: Enum.KeyCode) -> ())?
): boolean
    if not self._bindings[actionName] then return false end
    self._isListeningForRebind = true
    self._rebindTarget = actionName
    self._onRebindComplete = onComplete
    return true
end

function ControlRemappingModule._completeRebind(self: ControlRemapType, newKey: Enum.KeyCode): ()
    local actionName = self._rebindTarget
    if not actionName then return end
    local binding = self._bindings[actionName]
    if not binding then return end

    ContextActionService:UnbindAction(actionName)
    binding.currentKey = newKey
    ContextActionService:BindAction(actionName, binding.callback, false, newKey)

    self._isListeningForRebind = false
    self._rebindTarget = nil
    if self._onRebindComplete then
        self._onRebindComplete(actionName, newKey)
    end
end

function ControlRemappingModule.ResetToDefault(self: ControlRemapType, actionName: string): ()
    local binding = self._bindings[actionName]
    if not binding then return end
    ContextActionService:UnbindAction(actionName)
    binding.currentKey = binding.defaultKey
    ContextActionService:BindAction(actionName, binding.callback, false, binding.defaultKey)
end

function ControlRemappingModule.ResetAll(self: ControlRemapType): ()
    for actionName in self._bindings do
        self:ResetToDefault(actionName)
    end
end

function ControlRemappingModule.Serialize(self: ControlRemapType): string
    local data: { [string]: number } = {}
    for actionName, binding in self._bindings do
        data[actionName] = binding.currentKey.Value
    end
    return HttpService:JSONEncode(data)
end

function ControlRemappingModule.Deserialize(self: ControlRemapType, json: string): ()
    local ok, data = pcall(function() return HttpService:JSONDecode(json) end)
    if not ok or type(data) ~= "table" then return end
    for actionName, keyValue in data :: { [string]: number } do
        local binding = self._bindings[actionName]
        if binding then
            for _, enumItem in Enum.KeyCode:GetEnumItems() do
                if enumItem.Value == keyValue then
                    ContextActionService:UnbindAction(actionName)
                    binding.currentKey = enumItem
                    ContextActionService:BindAction(actionName, binding.callback, false, enumItem)
                    break
                end
            end
        end
    end
end

return ControlRemappingModule
```

---

## 5. ReducedMotionModule

Provides a global toggle that tween-based systems and particle emitters can query. When enabled, tweens complete instantly and particle emission rates drop to zero.

```luau
--!strict
-- ReducedMotionModule.lua

local TweenService = game:GetService("TweenService")

local ReducedMotionModule = {}
ReducedMotionModule.__index = ReducedMotionModule

type ReducedMotionImpl = {
    _enabled: boolean,
    _originalEmissionRates: { [ParticleEmitter]: number },
    _trackedEmitters: { ParticleEmitter },
    _changedSignal: BindableEvent,
}

export type ReducedMotionType = typeof(setmetatable({} :: ReducedMotionImpl, ReducedMotionModule))

function ReducedMotionModule.new(): ReducedMotionType
    local self = setmetatable({} :: ReducedMotionImpl, ReducedMotionModule)
    self._enabled = false
    self._originalEmissionRates = {}
    self._trackedEmitters = {}
    self._changedSignal = Instance.new("BindableEvent")
    return self
end

function ReducedMotionModule.SetEnabled(self: ReducedMotionType, enabled: boolean): ()
    if self._enabled == enabled then return end
    self._enabled = enabled
    for _, emitter in self._trackedEmitters do
        if emitter and emitter.Parent then
            if enabled then
                self._originalEmissionRates[emitter] = emitter.Rate
                emitter.Rate = 0
            else
                local original = self._originalEmissionRates[emitter]
                if original then emitter.Rate = original end
            end
        end
    end
    self._changedSignal:Fire(enabled)
end

function ReducedMotionModule.IsEnabled(self: ReducedMotionType): boolean
    return self._enabled
end

function ReducedMotionModule.OnChanged(self: ReducedMotionType): RBXScriptSignal
    return self._changedSignal.Event
end

function ReducedMotionModule.TrackEmitter(self: ReducedMotionType, emitter: ParticleEmitter): ()
    if table.find(self._trackedEmitters, emitter) then return end
    table.insert(self._trackedEmitters, emitter)
    self._originalEmissionRates[emitter] = emitter.Rate
    if self._enabled then emitter.Rate = 0 end
end

function ReducedMotionModule.SafeTween(
    self: ReducedMotionType,
    instance: Instance,
    tweenInfo: TweenInfo,
    goals: { [string]: any }
): Tween
    if self._enabled then
        local tween = TweenService:Create(instance, TweenInfo.new(0), goals)
        tween:Play()
        return tween
    else
        local tween = TweenService:Create(instance, tweenInfo, goals)
        tween:Play()
        return tween
    end
end

function ReducedMotionModule.TrackAllEmittersIn(self: ReducedMotionType, root: Instance): ()
    for _, desc in root:GetDescendants() do
        if desc:IsA("ParticleEmitter") then self:TrackEmitter(desc) end
    end
    root.DescendantAdded:Connect(function(desc)
        if desc:IsA("ParticleEmitter") then self:TrackEmitter(desc) end
    end)
end

function ReducedMotionModule.Destroy(self: ReducedMotionType): ()
    self:SetEnabled(false)
    self._changedSignal:Destroy()
end

return ReducedMotionModule
```

---

## 6. AccessibilityManager (Orchestrator)

```luau
--!strict
-- AccessibilityManager.lua (StarterPlayerScripts)

local ColorblindModule = require(script.Parent:WaitForChild("ColorblindModule"))
local TextScalingModule = require(script.Parent:WaitForChild("TextScalingModule"))
local SubtitleModule = require(script.Parent:WaitForChild("SubtitleModule"))
local ControlRemappingModule = require(script.Parent:WaitForChild("ControlRemappingModule"))
local ReducedMotionModule = require(script.Parent:WaitForChild("ReducedMotionModule"))

local AccessibilityManager = {}

function AccessibilityManager.Init()
    local colorblind = ColorblindModule.new()
    local textScaling = TextScalingModule.new()
    local subtitles = SubtitleModule.new()
    local controls = ControlRemappingModule.new()
    local reducedMotion = ReducedMotionModule.new()
    reducedMotion:TrackAllEmittersIn(workspace)

    return {
        Colorblind = colorblind,
        TextScaling = textScaling,
        Subtitles = subtitles,
        Controls = controls,
        ReducedMotion = reducedMotion,
    }
end

return AccessibilityManager
```

### Usage Example

```luau
local manager = AccessibilityManager.Init()

manager.Colorblind:SetMode("Deuteranopia", 0.8)
manager.TextScaling:SetScale(1.4)
manager.Subtitles:Show({
    speaker = "Guard",
    text = "Halt! Who goes there?",
    duration = 4,
})
manager.ReducedMotion:SetEnabled(true)

manager.Controls:RegisterAction("Sprint", "Sprint", Enum.KeyCode.LeftShift, function(name, state, input)
    if state == Enum.UserInputState.Begin then
        -- sprint logic
    end
    return Enum.ContextActionResult.Pass
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

- `$GAME_TYPE` - The genre/type of game (e.g., RPG, FPS, platformer) to tailor accessibility defaults.
- `$TARGET_AUDIENCE` - The target audience age range to calibrate text sizes and default settings.
- `$COLORBLIND_MODES` - Comma-separated list of colorblind modes to support (default: Protanopia,Deuteranopia,Tritanopia).
- `$PERSIST_METHOD` - How to persist settings: "DataStore", "PlayerAttributes", or "None".
- `$SUBTITLE_POSITION` - Where subtitles appear: "Bottom", "Top", or "Custom" with UDim2.
- `$CUSTOM_ACTIONS` - JSON array of action names and default keys for the control remapping system.
