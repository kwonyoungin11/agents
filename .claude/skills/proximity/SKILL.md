---
name: proximity
description: |
  ProximityPrompt 상호작용 시스템, 커스텀 스타일링, 홀드-투-인터랙트, 거리 설정, 키 오버라이드, NPC 대화 트리거.
  ProximityPrompt for interaction, custom prompt styling, hold-to-interact mechanic, distance configuration, key override, triggered events, NPC dialogue, door open, item pickup.
allowed-tools:
  - Bash
  - Edit
  - Write
  - Read
  - Glob
  - Grep
effort: high
---

# ProximityPrompt Interaction System

This skill covers ProximityPrompt creation, custom styling, hold-to-interact mechanics, distance configuration, keybind overrides, and common interaction patterns (doors, NPCs, items).

---

## 1. ProximityPrompt Builder

```luau
--!strict
-- ModuleScript: ProximityPrompt creation and configuration

local ProximityPromptBuilder = {}

export type PromptConfig = {
    actionText: string?,
    objectText: string?,
    holdDuration: number?,
    maxActivationDistance: number?,
    requiresLineOfSight: boolean?,
    keyboardKeyCode: Enum.KeyCode?,
    gamepadKeyCode: Enum.KeyCode?,
    exclusivity: Enum.ProximityPromptExclusivity?,
    style: Enum.ProximityPromptStyle?,
    enabled: boolean?,
    clickablePrompt: boolean?,
    uiOffset: Vector2?,
}

--- Creates a ProximityPrompt with full configuration.
function ProximityPromptBuilder.create(parent: Instance, config: PromptConfig?): ProximityPrompt
    local cfg = config or {}

    local prompt = Instance.new("ProximityPrompt")
    prompt.ActionText = cfg.actionText or "Interact"
    prompt.ObjectText = cfg.objectText or ""
    prompt.HoldDuration = cfg.holdDuration or 0
    prompt.MaxActivationDistance = cfg.maxActivationDistance or 10
    prompt.RequiresLineOfSight = if cfg.requiresLineOfSight ~= nil then cfg.requiresLineOfSight else true
    prompt.KeyboardKeyCode = cfg.keyboardKeyCode or Enum.KeyCode.E
    prompt.GamepadKeyCode = cfg.gamepadKeyCode or Enum.KeyCode.ButtonX
    prompt.Exclusivity = cfg.exclusivity or Enum.ProximityPromptExclusivity.OnePerButton
    prompt.Style = cfg.style or Enum.ProximityPromptStyle.Default
    prompt.Enabled = if cfg.enabled ~= nil then cfg.enabled else true
    prompt.ClickablePrompt = if cfg.clickablePrompt ~= nil then cfg.clickablePrompt else true
    prompt.UIOffset = cfg.uiOffset or Vector2.zero
    prompt.Parent = parent

    return prompt
end

--- Creates a quick interact prompt (tap E).
function ProximityPromptBuilder.quickInteract(parent: Instance, actionText: string, distance: number?): ProximityPrompt
    return ProximityPromptBuilder.create(parent, {
        actionText = actionText,
        holdDuration = 0,
        maxActivationDistance = distance or 8,
    })
end

--- Creates a hold-to-interact prompt.
function ProximityPromptBuilder.holdInteract(parent: Instance, actionText: string, holdTime: number, distance: number?): ProximityPrompt
    return ProximityPromptBuilder.create(parent, {
        actionText = actionText,
        holdDuration = holdTime,
        maxActivationDistance = distance or 6,
    })
end

return ProximityPromptBuilder
```

---

## 2. Custom Prompt Styling

```luau
--!strict
-- LocalScript: Custom ProximityPrompt UI styling (replaces default UI)

local ProximityPromptService = game:GetService("ProximityPromptService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local CustomPromptStyle = {}

export type StyleConfig = {
    backgroundColor: Color3?,
    textColor: Color3?,
    progressColor: Color3?,
    font: Enum.Font?,
    cornerRadius: number?,
    size: UDim2?,
}

--- Installs a custom ProximityPrompt renderer that replaces the default UI.
function CustomPromptStyle.install(config: StyleConfig?)
    local cfg = config or {}

    local bgColor = cfg.backgroundColor or Color3.fromRGB(30, 30, 45)
    local textColor = cfg.textColor or Color3.fromRGB(255, 255, 255)
    local progressColor = cfg.progressColor or Color3.fromRGB(80, 180, 255)
    local font = cfg.font or Enum.Font.GothamBold
    local radius = cfg.cornerRadius or 8
    local promptSize = cfg.size or UDim2.fromOffset(220, 60)

    -- Store active prompt GUIs
    local activePrompts: { [ProximityPrompt]: ScreenGui } = {}

    ProximityPromptService.PromptShown:Connect(function(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType)
        -- Create custom UI
        local screenGui = Instance.new("ScreenGui")
        screenGui.Name = "CustomProximityPrompt"
        screenGui.ResetOnSpawn = false
        screenGui.Parent = playerGui

        local billboardGui = Instance.new("BillboardGui")
        billboardGui.Size = promptSize
        billboardGui.StudsOffset = Vector3.new(0, 2, 0)
        billboardGui.AlwaysOnTop = true
        billboardGui.MaxDistance = prompt.MaxActivationDistance + 5
        billboardGui.Adornee = prompt.Parent
        billboardGui.Parent = screenGui

        -- Main frame
        local frame = Instance.new("Frame")
        frame.Size = UDim2.fromScale(1, 1)
        frame.BackgroundColor3 = bgColor
        frame.BackgroundTransparency = 0.1
        frame.Parent = billboardGui

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, radius)
        corner.Parent = frame

        local stroke = Instance.new("UIStroke")
        stroke.Color = progressColor
        stroke.Thickness = 2
        stroke.Transparency = 0.3
        stroke.Parent = frame

        -- Key indicator
        local keyLabel = Instance.new("TextLabel")
        keyLabel.Size = UDim2.new(0.25, 0, 0.8, 0)
        keyLabel.Position = UDim2.new(0.02, 0, 0.1, 0)
        keyLabel.BackgroundColor3 = progressColor
        keyLabel.BackgroundTransparency = 0.3
        keyLabel.TextColor3 = textColor
        keyLabel.Text = prompt.KeyboardKeyCode.Name
        keyLabel.TextScaled = true
        keyLabel.Font = font
        keyLabel.Parent = frame

        local keyCorner = Instance.new("UICorner")
        keyCorner.CornerRadius = UDim.new(0, 6)
        keyCorner.Parent = keyLabel

        -- Action text
        local actionLabel = Instance.new("TextLabel")
        actionLabel.Size = UDim2.new(0.65, 0, 0.45, 0)
        actionLabel.Position = UDim2.new(0.3, 0, 0.05, 0)
        actionLabel.BackgroundTransparency = 1
        actionLabel.TextColor3 = textColor
        actionLabel.Text = prompt.ActionText
        actionLabel.TextScaled = true
        actionLabel.Font = font
        actionLabel.TextXAlignment = Enum.TextXAlignment.Left
        actionLabel.Parent = frame

        -- Object text
        local objectLabel = Instance.new("TextLabel")
        objectLabel.Size = UDim2.new(0.65, 0, 0.4, 0)
        objectLabel.Position = UDim2.new(0.3, 0, 0.5, 0)
        objectLabel.BackgroundTransparency = 1
        objectLabel.TextColor3 = Color3.fromRGB(180, 180, 190)
        objectLabel.Text = prompt.ObjectText
        objectLabel.TextScaled = true
        objectLabel.Font = Enum.Font.Gotham
        objectLabel.TextXAlignment = Enum.TextXAlignment.Left
        objectLabel.Parent = frame

        -- Progress bar (for hold prompts)
        if prompt.HoldDuration > 0 then
            local progressBg = Instance.new("Frame")
            progressBg.Size = UDim2.new(0.95, 0, 0, 4)
            progressBg.Position = UDim2.new(0.025, 0, 0.9, 0)
            progressBg.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
            progressBg.BorderSizePixel = 0
            progressBg.Parent = frame

            local progressFill = Instance.new("Frame")
            progressFill.Name = "ProgressFill"
            progressFill.Size = UDim2.new(0, 0, 1, 0)
            progressFill.BackgroundColor3 = progressColor
            progressFill.BorderSizePixel = 0
            progressFill.Parent = progressBg
        end

        -- Entrance animation
        frame.BackgroundTransparency = 1
        TweenService:Create(frame, TweenInfo.new(0.2), { BackgroundTransparency = 0.1 }):Play()

        activePrompts[prompt] = screenGui
    end)

    ProximityPromptService.PromptHidden:Connect(function(prompt: ProximityPrompt)
        local gui = activePrompts[prompt]
        if gui then
            gui:Destroy()
            activePrompts[prompt] = nil
        end
    end)

    -- Update hold progress
    ProximityPromptService.PromptButtonHoldBegan:Connect(function(prompt: ProximityPrompt)
        local gui = activePrompts[prompt]
        if not gui then return end
        local progressFill = gui:FindFirstChild("ProgressFill", true)
        if progressFill and progressFill:IsA("Frame") then
            TweenService:Create(progressFill, TweenInfo.new(prompt.HoldDuration), {
                Size = UDim2.new(1, 0, 1, 0),
            }):Play()
        end
    end)

    ProximityPromptService.PromptButtonHoldEnded:Connect(function(prompt: ProximityPrompt)
        local gui = activePrompts[prompt]
        if not gui then return end
        local progressFill = gui:FindFirstChild("ProgressFill", true)
        if progressFill and progressFill:IsA("Frame") then
            TweenService:Create(progressFill, TweenInfo.new(0.15), {
                Size = UDim2.new(0, 0, 1, 0),
            }):Play()
        end
    end)
end

return CustomPromptStyle
```

---

## 3. Interaction Handlers (Server)

```luau
--!strict
-- ServerScript: Common ProximityPrompt interaction patterns

local Players = game:GetService("Players")

local InteractionHandlers = {}

--- Sets up a door that opens/closes on interaction.
function InteractionHandlers.setupDoor(doorPart: BasePart, openCFrame: CFrame, closedCFrame: CFrame)
    local TweenService = game:GetService("TweenService")
    local prompt = Instance.new("ProximityPrompt")
    prompt.ActionText = "Open Door"
    prompt.ObjectText = "Door"
    prompt.MaxActivationDistance = 8
    prompt.Parent = doorPart

    local isOpen = false

    prompt.Triggered:Connect(function(player: Player)
        isOpen = not isOpen
        prompt.ActionText = if isOpen then "Close Door" else "Open Door"

        local targetCFrame = if isOpen then openCFrame else closedCFrame
        TweenService:Create(doorPart, TweenInfo.new(0.5, Enum.EasingStyle.Quad), {
            CFrame = targetCFrame,
        }):Play()
    end)
end

--- Sets up an item that can be picked up (destroyed on pickup).
function InteractionHandlers.setupPickup(itemPart: BasePart, itemName: string, onPickup: (Player) -> ())
    local prompt = Instance.new("ProximityPrompt")
    prompt.ActionText = "Pick Up"
    prompt.ObjectText = itemName
    prompt.MaxActivationDistance = 6
    prompt.HoldDuration = 0
    prompt.Parent = itemPart

    prompt.Triggered:Connect(function(player: Player)
        prompt.Enabled = false
        onPickup(player)
        itemPart:Destroy()
    end)
end

--- Sets up an NPC dialogue trigger.
function InteractionHandlers.setupNPCTalk(npcModel: Model, npcName: string, onTalk: (Player) -> ())
    local rootPart = npcModel:FindFirstChild("HumanoidRootPart") or npcModel.PrimaryPart
    if not rootPart then return end

    local prompt = Instance.new("ProximityPrompt")
    prompt.ActionText = "Talk"
    prompt.ObjectText = npcName
    prompt.MaxActivationDistance = 10
    prompt.HoldDuration = 0
    prompt.RequiresLineOfSight = true
    prompt.Parent = rootPart

    prompt.Triggered:Connect(function(player: Player)
        onTalk(player)
    end)
end

--- Sets up a chest that requires holding to open.
function InteractionHandlers.setupChest(chestPart: BasePart, holdTime: number, onOpen: (Player) -> ())
    local prompt = Instance.new("ProximityPrompt")
    prompt.ActionText = "Open Chest"
    prompt.ObjectText = "Treasure Chest"
    prompt.MaxActivationDistance = 6
    prompt.HoldDuration = holdTime
    prompt.Parent = chestPart

    local opened = false

    prompt.Triggered:Connect(function(player: Player)
        if opened then return end
        opened = true
        prompt.Enabled = false
        onOpen(player)
    end)
end

--- Cooldown wrapper: prevents re-triggering for a set duration.
function InteractionHandlers.addCooldown(prompt: ProximityPrompt, cooldownSeconds: number)
    local originalConnection: RBXScriptConnection? = nil

    prompt.Triggered:Connect(function()
        prompt.Enabled = false
        task.delay(cooldownSeconds, function()
            if prompt and prompt.Parent then
                prompt.Enabled = true
            end
        end)
    end)
end

return InteractionHandlers
```

---

## 4. Multi-Option Prompt System

```luau
--!strict
-- ServerScript: Multiple prompts on a single object (e.g., "Buy" / "Inspect" / "Equip")

local MultiPrompt = {}

export type PromptOption = {
    actionText: string,
    objectText: string?,
    keyCode: Enum.KeyCode?,
    holdDuration: number?,
    callback: (Player) -> (),
}

--- Attaches multiple ProximityPrompts to a single part with different keys.
function MultiPrompt.setup(part: BasePart, options: { PromptOption }): { ProximityPrompt }
    local prompts: { ProximityPrompt } = {}

    local keyCodes = { Enum.KeyCode.E, Enum.KeyCode.F, Enum.KeyCode.G, Enum.KeyCode.R }

    for i, option in options do
        local prompt = Instance.new("ProximityPrompt")
        prompt.ActionText = option.actionText
        prompt.ObjectText = option.objectText or ""
        prompt.KeyboardKeyCode = option.keyCode or keyCodes[i] or Enum.KeyCode.E
        prompt.HoldDuration = option.holdDuration or 0
        prompt.MaxActivationDistance = 8
        prompt.Exclusivity = Enum.ProximityPromptExclusivity.AlwaysShow
        prompt.UIOffset = Vector2.new(0, (i - 1) * 50) -- Stack vertically
        prompt.Parent = part

        prompt.Triggered:Connect(option.callback)
        table.insert(prompts, prompt)
    end

    return prompts
end

return MultiPrompt
```

---

## 5. Proximity Prompt Events Reference

```luau
-- All ProximityPrompt signals:

prompt.Triggered:Connect(function(player: Player)
    -- Fires when interaction completes (after hold if applicable)
end)

prompt.TriggerEnded:Connect(function(player: Player)
    -- Fires when the player stops interacting
end)

prompt.PromptShown:Connect(function(player: Player)
    -- Fires when the prompt appears to a player (client enters range)
end)

prompt.PromptHidden:Connect(function(player: Player)
    -- Fires when the prompt disappears from a player
end)

-- Service-level events (LocalScript):
local PPS = game:GetService("ProximityPromptService")

PPS.PromptShown:Connect(function(prompt, inputType) end)
PPS.PromptHidden:Connect(function(prompt) end)
PPS.PromptTriggered:Connect(function(prompt, player) end)
PPS.PromptButtonHoldBegan:Connect(function(prompt) end)
PPS.PromptButtonHoldEnded:Connect(function(prompt) end)
```

---

## Best Practices

- **MaxActivationDistance**: 6-10 studs for items, 10-15 for NPCs, 4-6 for buttons
- **HoldDuration**: 0 for quick actions, 0.5-1.5 for important actions, 2-3 for irreversible actions
- **RequiresLineOfSight**: true for world objects, false for objects behind walls (like switches)
- **Exclusivity**: `OnePerButton` for standard, `AlwaysShow` for multi-option prompts
- **Cooldowns**: Always add cooldowns to prevent spam (especially for item pickups)

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

- `action_text` (string) - Text shown on the prompt (e.g., "Open", "Talk", "Pick Up")
- `object_text` (string) - Description text below action (e.g., "Wooden Door")
- `hold_duration` (number) - Seconds to hold for interaction (0 = instant)
- `max_distance` (number) - Activation distance in studs (default: 10)
- `key_code` (string) - Keyboard key override (e.g., "E", "F", "G")
- `requires_line_of_sight` (boolean) - Whether player must see the prompt (default: true)
- `cooldown` (number) - Seconds before prompt can be triggered again
- `style_bg_color` (Color3) - Custom style background color
- `style_text_color` (Color3) - Custom style text color
- `style_progress_color` (Color3) - Custom style progress bar color
- `interaction_type` (string) - "door", "pickup", "npc", "chest", "multi"
