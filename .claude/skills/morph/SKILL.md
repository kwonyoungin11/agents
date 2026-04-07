---
name: morph
description: |
  Character morph system for Roblox. Swap character models, apply size changes,
  transformation VFX with particles and sound, temporary morphs with duration timers,
  and morph catalog management.
  캐릭터 변신 시스템, 모델 교체, 크기 변경, 변신 VFX, 일시적 변신
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
effort: high
---

# Character Morph System

Build a full character morph system for Roblox experiences. This skill covers model swapping, size transformations, visual effects during morphing, temporary morphs with automatic revert, and a morph catalog for managing available morphs.

## Architecture Overview

```
ServerScriptService/
  MorphService.server.lua        -- Core morph logic, handles RemoteEvent requests
ReplicatedStorage/
  Morphs/                        -- Folder of morph model templates
  MorphConfig.lua                -- ModuleScript with morph definitions
  MorphShared.lua                -- Shared types and constants
StarterPlayerScripts/
  MorphClient.lua                -- Client-side VFX, UI, and input
StarterGui/
  MorphUI/                       -- ScreenGui for morph selection wheel
```

## Server: MorphService

```lua
-- ServerScriptService/MorphService.server.lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MorphConfig = require(ReplicatedStorage:WaitForChild("MorphConfig"))
local MorphShared = require(ReplicatedStorage:WaitForChild("MorphShared"))

-- RemoteEvents
local MorphRemote = Instance.new("RemoteEvent")
MorphRemote.Name = "MorphRemote"
MorphRemote.Parent = ReplicatedStorage

local MorphRequestRemote = Instance.new("RemoteEvent")
MorphRequestRemote.Name = "MorphRequestRemote"
MorphRequestRemote.Parent = ReplicatedStorage

-- Track active morphs per player
local activeMorphs: { [Player]: MorphShared.ActiveMorph } = {}

-- Store original character descriptions for revert
local originalDescriptions: { [Player]: HumanoidDescription } = {}

--------------------------------------------------------------------------------
-- Utility: Deep-clone a Model template
--------------------------------------------------------------------------------
local function cloneMorphModel(morphName: string): Model?
    local morphsFolder = ReplicatedStorage:FindFirstChild("Morphs")
    if not morphsFolder then
        warn("[MorphService] Morphs folder not found in ReplicatedStorage")
        return nil
    end
    local template = morphsFolder:FindFirstChild(morphName)
    if not template then
        warn("[MorphService] Morph template not found:", morphName)
        return nil
    end
    return template:Clone()
end

--------------------------------------------------------------------------------
-- Save original appearance so we can revert later
--------------------------------------------------------------------------------
local function saveOriginalAppearance(player: Player)
    if originalDescriptions[player] then return end
    local character = player.Character
    if not character then return end
    local humanoid = character:FindFirstChildWhichIsA("Humanoid")
    if not humanoid then return end
    originalDescriptions[player] = humanoid:GetAppliedDescription()
end

--------------------------------------------------------------------------------
-- Apply body scale multiplier
--------------------------------------------------------------------------------
local function applyScale(humanoid: Humanoid, scale: number)
    local desc = humanoid:GetAppliedDescription()
    desc.HeadScale *= scale
    desc.BodyTypeScale = desc.BodyTypeScale
    desc.DepthScale *= scale
    desc.HeightScale *= scale
    desc.WidthScale *= scale
    desc.ProportionScale = desc.ProportionScale
    humanoid:ApplyDescription(desc)
end

--------------------------------------------------------------------------------
-- Full model swap morph
--------------------------------------------------------------------------------
local function applyModelSwap(player: Player, morphName: string, config: MorphShared.MorphDefinition)
    local character = player.Character
    if not character then return false end
    local humanoid = character:FindFirstChildWhichIsA("Humanoid")
    if not humanoid then return false end

    saveOriginalAppearance(player)

    local morphModel = cloneMorphModel(morphName)
    if not morphModel then return false end

    -- Transfer morph parts onto the existing character rig
    -- This preserves the Humanoid and animation controller
    for _, child in morphModel:GetChildren() do
        if child:IsA("BasePart") then
            local existing = character:FindFirstChild(child.Name)
            if existing and existing:IsA("BasePart") then
                existing.Size = child.Size
                existing.Color = child.Color
                existing.Material = child.Material
                existing.Transparency = child.Transparency
                local newMesh = child:FindFirstChildWhichIsA("SpecialMesh")
                local oldMesh = existing:FindFirstChildWhichIsA("SpecialMesh")
                if newMesh then
                    if oldMesh then oldMesh:Destroy() end
                    newMesh:Clone().Parent = existing
                end
            end
        elseif child:IsA("Accessory") then
            child:Clone().Parent = character
        end
    end

    if config.scale and config.scale ~= 1 then
        applyScale(humanoid, config.scale)
    end

    morphModel:Destroy()
    return true
end

--------------------------------------------------------------------------------
-- Description-based morph (uses HumanoidDescription)
--------------------------------------------------------------------------------
local function applyDescriptionMorph(player: Player, config: MorphShared.MorphDefinition)
    local character = player.Character
    if not character then return false end
    local humanoid = character:FindFirstChildWhichIsA("Humanoid")
    if not humanoid then return false end

    saveOriginalAppearance(player)

    if config.humanoidDescriptionId then
        local success, desc = pcall(function()
            return Players:GetHumanoidDescriptionFromUserId(config.humanoidDescriptionId)
        end)
        if success and desc then
            humanoid:ApplyDescription(desc)
        end
    end

    if config.scale and config.scale ~= 1 then
        applyScale(humanoid, config.scale)
    end

    return true
end

--------------------------------------------------------------------------------
-- Revert morph - restore original appearance
--------------------------------------------------------------------------------
local function revertMorph(player: Player)
    local character = player.Character
    if not character then return end
    local humanoid = character:FindFirstChildWhichIsA("Humanoid")
    if not humanoid then return end

    local desc = originalDescriptions[player]
    if desc then
        humanoid:ApplyDescription(desc)
    end

    -- Remove any extra accessories added by morph
    local activeMorph = activeMorphs[player]
    if activeMorph and activeMorph.addedAccessories then
        for _, acc in activeMorph.addedAccessories do
            if acc and acc.Parent then
                acc:Destroy()
            end
        end
    end

    activeMorphs[player] = nil
    MorphRemote:FireClient(player, "Reverted", nil)
end

--------------------------------------------------------------------------------
-- Temporary morph timer
--------------------------------------------------------------------------------
local function startMorphTimer(player: Player, duration: number)
    task.delay(duration, function()
        if activeMorphs[player] then
            revertMorph(player)
        end
    end)
end

--------------------------------------------------------------------------------
-- Main morph application entry point
--------------------------------------------------------------------------------
local function applyMorph(player: Player, morphName: string)
    local config = MorphConfig.getMorph(morphName)
    if not config then
        warn("[MorphService] Unknown morph:", morphName)
        return
    end

    local existing = activeMorphs[player]
    if existing and tick() - existing.appliedAt < (config.cooldown or 0) then
        MorphRemote:FireClient(player, "Cooldown", config.cooldown)
        return
    end

    if existing then
        revertMorph(player)
    end

    local success = false
    if config.morphType == "ModelSwap" then
        success = applyModelSwap(player, morphName, config)
    elseif config.morphType == "Description" then
        success = applyDescriptionMorph(player, config)
    elseif config.morphType == "ScaleOnly" then
        local character = player.Character
        local humanoid = character and character:FindFirstChildWhichIsA("Humanoid")
        if humanoid and config.scale then
            saveOriginalAppearance(player)
            applyScale(humanoid, config.scale)
            success = true
        end
    end

    if success then
        activeMorphs[player] = {
            morphName = morphName,
            appliedAt = tick(),
            addedAccessories = {},
        }
        MorphRemote:FireClient(player, "Applied", morphName)
        if config.duration and config.duration > 0 then
            startMorphTimer(player, config.duration)
        end
    end
end

--------------------------------------------------------------------------------
-- Listen for morph requests from clients
--------------------------------------------------------------------------------
MorphRequestRemote.OnServerEvent:Connect(function(player: Player, action: string, morphName: string?)
    if action == "Apply" and morphName then
        applyMorph(player, morphName)
    elseif action == "Revert" then
        revertMorph(player)
    end
end)

Players.PlayerRemoving:Connect(function(player)
    activeMorphs[player] = nil
    originalDescriptions[player] = nil
end)
```

## Shared Types and Config

```lua
-- ReplicatedStorage/MorphShared.lua
local MorphShared = {}

export type MorphDefinition = {
    morphType: "ModelSwap" | "Description" | "ScaleOnly",
    displayName: string,
    description: string,
    icon: string,
    scale: number?,
    duration: number?,
    cooldown: number?,
    humanoidDescriptionId: number?,
    vfxPreset: string?,
}

export type ActiveMorph = {
    morphName: string,
    appliedAt: number,
    addedAccessories: { Instance },
}

MorphShared.VFXPresets = {
    Default = "DefaultTransform",
    Fire = "FireTransform",
    Ice = "IceTransform",
    Shadow = "ShadowTransform",
    Holy = "HolyTransform",
}

return MorphShared
```

```lua
-- ReplicatedStorage/MorphConfig.lua
local MorphShared = require(script.Parent:WaitForChild("MorphShared"))

local MorphConfig = {}

local morphs: { [string]: MorphShared.MorphDefinition } = {
    Giant = {
        morphType = "ScaleOnly",
        displayName = "Giant Form",
        description = "Grow to 3x your normal size!",
        icon = "rbxassetid://0",
        scale = 3,
        duration = 30,
        cooldown = 60,
        vfxPreset = "Default",
    },
    Tiny = {
        morphType = "ScaleOnly",
        displayName = "Tiny Form",
        description = "Shrink to half size!",
        icon = "rbxassetid://0",
        scale = 0.5,
        duration = 20,
        cooldown = 30,
        vfxPreset = "Default",
    },
    Dragon = {
        morphType = "ModelSwap",
        displayName = "Dragon",
        description = "Transform into a fearsome dragon!",
        icon = "rbxassetid://0",
        scale = 2,
        duration = 60,
        cooldown = 120,
        vfxPreset = "Fire",
    },
}

function MorphConfig.getMorph(name: string): MorphShared.MorphDefinition?
    return morphs[name]
end

function MorphConfig.getAllMorphs(): { [string]: MorphShared.MorphDefinition }
    return morphs
end

return MorphConfig
```

## Client: VFX and UI

```lua
-- StarterPlayerScripts/MorphClient.lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local MorphConfig = require(ReplicatedStorage:WaitForChild("MorphConfig"))
local MorphShared = require(ReplicatedStorage:WaitForChild("MorphShared"))

local MorphRemote = ReplicatedStorage:WaitForChild("MorphRemote")
local MorphRequestRemote = ReplicatedStorage:WaitForChild("MorphRequestRemote")

local player = Players.LocalPlayer

--------------------------------------------------------------------------------
-- VFX: Transformation particle burst
--------------------------------------------------------------------------------
local function playTransformVFX(character: Model, presetName: string?)
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not rootPart then return end

    local preset = presetName or "Default"

    local attachment = Instance.new("Attachment")
    attachment.Parent = rootPart

    local emitter = Instance.new("ParticleEmitter")
    emitter.Rate = 0
    emitter.Lifetime = NumberRange.new(0.5, 1.5)
    emitter.Speed = NumberRange.new(10, 25)
    emitter.SpreadAngle = Vector2.new(180, 180)
    emitter.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 2),
        NumberSequenceKeypoint.new(0.5, 3),
        NumberSequenceKeypoint.new(1, 0),
    })
    emitter.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0),
        NumberSequenceKeypoint.new(0.7, 0.3),
        NumberSequenceKeypoint.new(1, 1),
    })

    if preset == "Fire" then
        emitter.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 170, 0)),
            ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 85, 0)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(170, 0, 0)),
        })
        emitter.LightEmission = 1
    elseif preset == "Ice" then
        emitter.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(200, 230, 255)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(100, 180, 255)),
        })
        emitter.LightEmission = 0.8
    elseif preset == "Shadow" then
        emitter.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(50, 0, 80)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(20, 0, 40)),
        })
        emitter.LightEmission = 0.2
    elseif preset == "Holy" then
        emitter.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 200)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 220, 100)),
        })
        emitter.LightEmission = 1
    else
        emitter.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(180, 180, 255)),
        })
        emitter.LightEmission = 0.6
    end

    emitter.Parent = attachment

    -- Flash ring effect
    local ring = Instance.new("Part")
    ring.Shape = Enum.PartType.Cylinder
    ring.Size = Vector3.new(0.2, 1, 1)
    ring.CFrame = rootPart.CFrame * CFrame.Angles(0, 0, math.rad(90))
    ring.Anchored = true
    ring.CanCollide = false
    ring.Material = Enum.Material.Neon
    ring.Color = Color3.fromRGB(255, 255, 255)
    ring.Transparency = 0.3
    ring.Parent = workspace

    emitter:Emit(60)

    local ringTween = TweenService:Create(ring, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Size = Vector3.new(0.2, 20, 20),
        Transparency = 1,
    })
    ringTween:Play()

    local sound = Instance.new("Sound")
    sound.SoundId = "rbxassetid://0" -- replace with transform sound
    sound.Volume = 0.8
    sound.Parent = rootPart
    sound:Play()

    task.delay(2, function()
        attachment:Destroy()
        ring:Destroy()
        sound:Destroy()
    end)
end

--------------------------------------------------------------------------------
-- VFX: Revert effect
--------------------------------------------------------------------------------
local function playRevertVFX(character: Model)
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not rootPart then return end

    local flash = Instance.new("PointLight")
    flash.Brightness = 5
    flash.Range = 30
    flash.Color = Color3.fromRGB(255, 255, 255)
    flash.Parent = rootPart

    local tween = TweenService:Create(flash, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Brightness = 0,
    })
    tween:Play()
    tween.Completed:Connect(function()
        flash:Destroy()
    end)
end

--------------------------------------------------------------------------------
-- Handle server notifications
--------------------------------------------------------------------------------
MorphRemote.OnClientEvent:Connect(function(action: string, morphName: string?)
    local character = player.Character
    if not character then return end

    if action == "Applied" and morphName then
        local config = MorphConfig.getMorph(morphName)
        local preset = config and config.vfxPreset or "Default"
        playTransformVFX(character, preset)
    elseif action == "Reverted" then
        playRevertVFX(character)
    elseif action == "Cooldown" then
        warn("Morph is on cooldown!")
    end
end)

--------------------------------------------------------------------------------
-- Public API for other client scripts
--------------------------------------------------------------------------------
local MorphClient = {}

function MorphClient.requestMorph(morphName: string)
    MorphRequestRemote:FireServer("Apply", morphName)
end

function MorphClient.requestRevert()
    MorphRequestRemote:FireServer("Revert")
end

return MorphClient
```

## Morph Selection UI

```lua
-- StarterGui/MorphUI (ScreenGui with LocalScript)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local MorphConfig = require(ReplicatedStorage:WaitForChild("MorphConfig"))
local MorphRequestRemote = ReplicatedStorage:WaitForChild("MorphRequestRemote")

local player = Players.LocalPlayer
local gui = script.Parent

local frame = Instance.new("Frame")
frame.Name = "MorphPanel"
frame.Size = UDim2.fromScale(0.5, 0.6)
frame.Position = UDim2.fromScale(0.25, 0.2)
frame.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
frame.BackgroundTransparency = 0.1
frame.Visible = false
frame.Parent = gui

local uiCorner = Instance.new("UICorner")
uiCorner.CornerRadius = UDim.new(0, 12)
uiCorner.Parent = frame

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 50)
title.BackgroundTransparency = 1
title.Text = "Select Morph"
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.TextSize = 24
title.Font = Enum.Font.GothamBold
title.Parent = frame

local scrollFrame = Instance.new("ScrollingFrame")
scrollFrame.Size = UDim2.new(1, -20, 1, -110)
scrollFrame.Position = UDim2.new(0, 10, 0, 55)
scrollFrame.BackgroundTransparency = 1
scrollFrame.ScrollBarThickness = 6
scrollFrame.Parent = frame

local gridLayout = Instance.new("UIGridLayout")
gridLayout.CellSize = UDim2.fromOffset(120, 140)
gridLayout.CellPadding = UDim2.fromOffset(10, 10)
gridLayout.SortOrder = Enum.SortOrder.Name
gridLayout.Parent = scrollFrame

local allMorphs = MorphConfig.getAllMorphs()
for name, config in allMorphs do
    local btn = Instance.new("TextButton")
    btn.Name = name
    btn.Size = UDim2.fromOffset(120, 140)
    btn.BackgroundColor3 = Color3.fromRGB(50, 50, 65)
    btn.Text = ""
    btn.Parent = scrollFrame

    local btnCorner = Instance.new("UICorner")
    btnCorner.CornerRadius = UDim.new(0, 8)
    btnCorner.Parent = btn

    local icon = Instance.new("ImageLabel")
    icon.Size = UDim2.new(1, -20, 0, 80)
    icon.Position = UDim2.fromOffset(10, 5)
    icon.BackgroundTransparency = 1
    icon.Image = config.icon
    icon.ScaleType = Enum.ScaleType.Fit
    icon.Parent = btn

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 0, 20)
    label.Position = UDim2.new(0, 0, 1, -40)
    label.BackgroundTransparency = 1
    label.Text = config.displayName
    label.TextColor3 = Color3.fromRGB(220, 220, 220)
    label.TextSize = 14
    label.Font = Enum.Font.GothamMedium
    label.Parent = btn

    if config.duration and config.duration > 0 then
        local durLabel = Instance.new("TextLabel")
        durLabel.Size = UDim2.new(1, 0, 0, 16)
        durLabel.Position = UDim2.new(0, 0, 1, -20)
        durLabel.BackgroundTransparency = 1
        durLabel.Text = config.duration .. "s"
        durLabel.TextColor3 = Color3.fromRGB(150, 150, 170)
        durLabel.TextSize = 12
        durLabel.Font = Enum.Font.Gotham
        durLabel.Parent = btn
    end

    btn.MouseButton1Click:Connect(function()
        MorphRequestRemote:FireServer("Apply", name)
        frame.Visible = false
    end)
end

-- Revert button
local revertBtn = Instance.new("TextButton")
revertBtn.Size = UDim2.new(0.4, 0, 0, 40)
revertBtn.Position = UDim2.new(0.3, 0, 1, -50)
revertBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
revertBtn.Text = "Revert to Normal"
revertBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
revertBtn.TextSize = 16
revertBtn.Font = Enum.Font.GothamBold
revertBtn.Parent = frame

local revertCorner = Instance.new("UICorner")
revertCorner.CornerRadius = UDim.new(0, 8)
revertCorner.Parent = revertBtn

revertBtn.MouseButton1Click:Connect(function()
    MorphRequestRemote:FireServer("Revert")
    frame.Visible = false
end)

-- Toggle with M key
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == Enum.KeyCode.M then
        frame.Visible = not frame.Visible
    end
end)
```

## Key Implementation Notes

1. **Model swap morphs**: Place morph template Models in `ReplicatedStorage/Morphs/`. Each template should have named parts matching the R15 rig (Head, UpperTorso, etc.) with desired meshes and textures.

2. **HumanoidDescription morphs**: Use `humanoidDescriptionId` in the config to apply a full avatar appearance from a user ID.

3. **Scale morphs**: Use `scale` field to uniformly scale the character via HumanoidDescription properties.

4. **Temporary morphs**: Set `duration` (seconds) in the morph config. The server automatically reverts after the timer expires.

5. **Cooldowns**: Set `cooldown` (seconds) to prevent spamming. The server tracks when each morph was last applied per player.

6. **VFX presets**: Fire, Ice, Shadow, Holy, and Default presets change particle colors. Extend `MorphShared.VFXPresets` for custom effects.

7. **Security**: All morph logic runs on the server. The client only sends requests and plays visual effects.

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

When the user asks for a morph system, ask:
- What morph types do you need? (model swap, scale, description-based)
- Should morphs be temporary (with duration) or permanent until manually reverted?
- Do you need a morph selection UI or will morphs be triggered by game events?
- What VFX style fits your game? (particle burst, flash, custom animation)
- Should morphs affect gameplay stats (speed, jump, health) or just appearance?
