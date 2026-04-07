---
name: double-jump-system
description: |
  Multi-jump system for Roblox: double jump, triple jump, jump count tracking,
  VFX on extra jumps, configurable max jumps. Use when the user asks about double jump,
  multi jump, extra jumps, air jump, jump abilities, jump VFX, or jump count.
  더블 점프, 멀티 점프, 추가 점프, 에어 점프, 점프 능력.
  Triggers on: double jump, multi jump, triple jump, extra jump, air jump, jump count,
  jump effect, jump VFX, jump ability, midair jump.
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
effort: high
---

# Double Jump / Multi-Jump System Skill

Complete multi-jump system with jump counting, per-jump VFX, sound, and configurable
maximum jumps. Client-driven with server validation.

---

## 1. Multi-Jump Controller (Client Script)

```luau
--!strict
-- StarterPlayerScripts/MultiJumpController.client.lua
-- Handles multi-jump input, VFX, and sound on the client.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

-- Configuration
local MAX_JUMPS = 2               -- total jumps (1 = normal, 2 = double, 3 = triple, etc.)
local EXTRA_JUMP_POWER = 55       -- velocity for extra jumps (studs/s upward)
local JUMP_COOLDOWN = 0.15        -- minimum time between jumps
local VFX_ENABLED = true
local VFX_COLOR = Color3.fromRGB(255, 255, 255)
local VFX_RING_ENABLED = true     -- expanding ring on extra jumps
local VFX_PARTICLES_ENABLED = true
local SOUND_ENABLED = true
local SOUND_ID = "rbxassetid://0"  -- replace with your jump sound ID

-- State
local jumpCount = 0
local lastJumpTime = 0
local isGrounded = false

-- Remote for server sync
local jumpRemote = ReplicatedStorage:WaitForChild("MultiJumpRemote", 10) :: RemoteEvent?

-- VFX: expanding ring effect at character's feet
local function createJumpRing(position: Vector3, jumpIndex: number)
    if not VFX_RING_ENABLED then return end

    local ring = Instance.new("Part")
    ring.Name = "JumpRing"
    ring.Shape = Enum.PartType.Cylinder
    ring.Anchored = true
    ring.CanCollide = false
    ring.CanQuery = false
    ring.Material = Enum.Material.Neon
    ring.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))

    -- Color varies by jump index for visual feedback
    local hue = (jumpIndex - 1) / MAX_JUMPS
    ring.Color = Color3.fromHSV(hue * 0.6, 0.5, 1) -- cycle through cool colors

    local startSize = Vector3.new(0.2, 1, 1)
    local endSize = Vector3.new(0.2, 8 + jumpIndex * 3, 8 + jumpIndex * 3)

    ring.Size = startSize
    ring.Transparency = 0.3
    ring.Parent = workspace

    -- Expand and fade
    TweenService:Create(
        ring,
        TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { Size = endSize, Transparency = 1 }
    ):Play()

    Debris:AddItem(ring, 0.5)
end

-- VFX: burst particles at feet
local function createJumpParticles(character: Model, jumpIndex: number)
    if not VFX_PARTICLES_ENABLED then return end

    local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
    if not rootPart then return end

    local emitterPart = Instance.new("Part")
    emitterPart.Size = Vector3.one * 0.1
    emitterPart.Transparency = 1
    emitterPart.Anchored = true
    emitterPart.CanCollide = false
    emitterPart.CanQuery = false
    emitterPart.Position = rootPart.Position - Vector3.new(0, 3, 0)
    emitterPart.Parent = workspace

    local emitter = Instance.new("ParticleEmitter")
    local hue = (jumpIndex - 1) / MAX_JUMPS
    local particleColor = Color3.fromHSV(hue * 0.6, 0.3, 1)

    emitter.Color = ColorSequence.new(particleColor)
    emitter.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.5 + jumpIndex * 0.3),
        NumberSequenceKeypoint.new(1, 0),
    })
    emitter.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0),
        NumberSequenceKeypoint.new(1, 1),
    })
    emitter.Lifetime = NumberRange.new(0.3, 0.6)
    emitter.Speed = NumberRange.new(5, 15)
    emitter.SpreadAngle = Vector2.new(180, 30)  -- mostly horizontal burst
    emitter.Rate = 0
    emitter.Parent = emitterPart

    emitter:Emit(15 + jumpIndex * 5) -- more particles for higher jumps

    Debris:AddItem(emitterPart, 1)
end

-- Play jump sound
local function playJumpSound(character: Model, jumpIndex: number)
    if not SOUND_ENABLED or SOUND_ID == "rbxassetid://0" then return end

    local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
    if not rootPart then return end

    local sound = Instance.new("Sound")
    sound.SoundId = SOUND_ID
    sound.Volume = 0.5
    -- Pitch increases slightly with each jump
    sound.PlaybackSpeed = 1.0 + (jumpIndex - 1) * 0.15
    sound.Parent = rootPart
    sound:Play()
    Debris:AddItem(sound, 2)
end

-- Perform the extra jump
local function performExtraJump(character: Model, humanoid: Humanoid)
    local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
    if not rootPart then return end

    -- Apply upward velocity
    local currentVel = rootPart.AssemblyLinearVelocity
    rootPart.AssemblyLinearVelocity = Vector3.new(
        currentVel.X,
        math.max(EXTRA_JUMP_POWER, 0), -- ensure positive upward velocity
        currentVel.Z
    )

    -- VFX
    if VFX_ENABLED then
        createJumpRing(rootPart.Position - Vector3.new(0, 3, 0), jumpCount)
        createJumpParticles(character, jumpCount)
    end

    -- Sound
    playJumpSound(character, jumpCount)

    -- Notify server
    if jumpRemote then
        jumpRemote:FireServer(jumpCount)
    end
end

-- Track grounded state
local function updateGroundedState(humanoid: Humanoid)
    local state = humanoid:GetState()
    local wasGrounded = isGrounded

    isGrounded = (
        state == Enum.HumanoidStateType.Running
        or state == Enum.HumanoidStateType.Landed
    )

    -- Reset jump count when landing
    if isGrounded and not wasGrounded then
        jumpCount = 0
    end

    -- Count the initial jump
    if not isGrounded and wasGrounded then
        jumpCount = 1
    end
end

-- Setup for character
local function onCharacterAdded(character: Model)
    local humanoid = character:WaitForChild("Humanoid") :: Humanoid
    jumpCount = 0
    isGrounded = true

    -- Track state changes
    humanoid.StateChanged:Connect(function(_old, new)
        updateGroundedState(humanoid)
    end)

    -- Input handling for extra jumps
    -- (First jump is handled by Roblox's built-in jump; we handle 2nd+ jumps)
end

-- Input handler
UserInputService.JumpRequest:Connect(function()
    local character = player.Character
    if not character then return end

    local humanoid = character:FindFirstChildWhichIsA("Humanoid")
    if not humanoid or humanoid.Health <= 0 then return end

    -- Cooldown check
    local now = tick()
    if now - lastJumpTime < JUMP_COOLDOWN then return end

    -- If already in the air and have jumps remaining
    if not isGrounded and jumpCount < MAX_JUMPS then
        jumpCount += 1
        lastJumpTime = now
        performExtraJump(character, humanoid)
    elseif isGrounded and jumpCount == 0 then
        -- First jump handled by engine, just track it
        jumpCount = 1
        lastJumpTime = now
    end
end)

-- Character setup
player.CharacterAdded:Connect(onCharacterAdded)
if player.Character then
    onCharacterAdded(player.Character)
end
```

---

## 2. Multi-Jump Server Handler

```luau
--!strict
-- ServerScriptService/MultiJumpServer.server.lua
-- Server validation for multi-jump system.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Create remote
local jumpRemote = Instance.new("RemoteEvent")
jumpRemote.Name = "MultiJumpRemote"
jumpRemote.Parent = ReplicatedStorage

-- Configuration
local MAX_JUMPS = 2
local EXTRA_JUMP_POWER = 55
local JUMP_COOLDOWN = 0.1

-- Per-player tracking
local playerState: { [Player]: { lastJump: number, jumpCount: number } } = {}

jumpRemote.OnServerEvent:Connect(function(player: Player, jumpIndex: any)
    -- Validate input type
    if typeof(jumpIndex) ~= "number" then return end
    jumpIndex = math.floor(jumpIndex)
    if jumpIndex < 1 or jumpIndex > MAX_JUMPS then return end

    local character = player.Character
    if not character then return end

    local humanoid = character:FindFirstChildWhichIsA("Humanoid")
    if not humanoid or humanoid.Health <= 0 then return end

    -- Rate limiting
    local state = playerState[player]
    if not state then
        state = { lastJump = 0, jumpCount = 0 }
        playerState[player] = state
    end

    local now = tick()
    if now - state.lastJump < JUMP_COOLDOWN then return end

    -- Validate the character is actually in the air
    local hState = humanoid:GetState()
    local inAir = (
        hState == Enum.HumanoidStateType.Freefall
        or hState == Enum.HumanoidStateType.Jumping
    )

    if not inAir then
        state.jumpCount = 0
        return
    end

    -- Validate jump count
    if jumpIndex > MAX_JUMPS then return end

    state.lastJump = now
    state.jumpCount = jumpIndex

    -- Server-side: apply the velocity (redundant with client but authoritative)
    local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
    if rootPart then
        local vel = rootPart.AssemblyLinearVelocity
        rootPart.AssemblyLinearVelocity = Vector3.new(vel.X, EXTRA_JUMP_POWER, vel.Z)
    end
end)

-- Reset on landing (tracked via Humanoid state)
local function setupCharacter(player: Player, character: Model)
    local humanoid = character:WaitForChild("Humanoid") :: Humanoid
    humanoid.StateChanged:Connect(function(_old, new)
        if new == Enum.HumanoidStateType.Landed or new == Enum.HumanoidStateType.Running then
            local state = playerState[player]
            if state then
                state.jumpCount = 0
            end
        end
    end)
end

Players.PlayerAdded:Connect(function(player: Player)
    playerState[player] = { lastJump = 0, jumpCount = 0 }
    player.CharacterAdded:Connect(function(character)
        setupCharacter(player, character)
    end)
    if player.Character then
        setupCharacter(player, player.Character)
    end
end)

Players.PlayerRemoving:Connect(function(player: Player)
    playerState[player] = nil
end)
```

---

## 3. Jump Count HUD (Client)

```luau
--!strict
-- StarterPlayerScripts/JumpCountHUD.client.lua
-- Displays available jumps as dots/pips above the hotbar area.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local MAX_JUMPS = 2
local DOT_SIZE = 12
local DOT_SPACING = 6
local ACTIVE_COLOR = Color3.fromRGB(100, 255, 150)
local USED_COLOR = Color3.fromRGB(80, 80, 80)

-- Create UI
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "JumpCountHUD"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

local container = Instance.new("Frame")
container.Name = "JumpDots"
container.Size = UDim2.fromOffset(
    MAX_JUMPS * DOT_SIZE + (MAX_JUMPS - 1) * DOT_SPACING,
    DOT_SIZE
)
container.Position = UDim2.new(0.5, 0, 1, -130)
container.AnchorPoint = Vector2.new(0.5, 0)
container.BackgroundTransparency = 1
container.Parent = screenGui

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Horizontal
layout.Padding = UDim.new(0, DOT_SPACING)
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.Parent = container

-- Create dots
local dots: { Frame } = {}
for i = 1, MAX_JUMPS do
    local dot = Instance.new("Frame")
    dot.Name = "Dot_" .. i
    dot.Size = UDim2.fromOffset(DOT_SIZE, DOT_SIZE)
    dot.BackgroundColor3 = ACTIVE_COLOR
    dot.Parent = container

    local dotCorner = Instance.new("UICorner")
    dotCorner.CornerRadius = UDim.new(0.5, 0)
    dotCorner.Parent = dot

    table.insert(dots, dot)
end

-- Update display based on jump state
-- This reads from a shared module or attribute on the character
RunService.RenderStepped:Connect(function()
    local character = player.Character
    if not character then return end

    local jumpsUsed = character:GetAttribute("JumpsUsed") or 0
    local jumpsAvailable = MAX_JUMPS - jumpsUsed

    for i, dot in dots do
        local targetColor = if i <= jumpsAvailable then ACTIVE_COLOR else USED_COLOR
        if dot.BackgroundColor3 ~= targetColor then
            TweenService:Create(
                dot,
                TweenInfo.new(0.15, Enum.EasingStyle.Quad),
                { BackgroundColor3 = targetColor }
            ):Play()

            -- Pop animation when a jump is used
            if targetColor == USED_COLOR then
                local originalSize = dot.Size
                dot.Size = UDim2.fromOffset(DOT_SIZE * 1.5, DOT_SIZE * 1.5)
                TweenService:Create(
                    dot,
                    TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
                    { Size = originalSize }
                ):Play()
            end
        end
    end
end)
```

---

## Guidelines

- **First jump is handled by Roblox's Humanoid**; the multi-jump system only intercepts `JumpRequest` for subsequent jumps.
- **Track `HumanoidStateType`** changes to detect landing (reset jump count) and airborne state.
- **Apply velocity directly** to `HumanoidRootPart.AssemblyLinearVelocity` for extra jumps. Set the Y component, don't add to it, to ensure consistent jump height.
- **Server validates** that the player is actually airborne before accepting extra jump requests.
- **VFX should scale** with jump index (bigger ring, more particles, higher pitch sound for later jumps).
- **Jump cooldown** prevents rapid-fire jumps from being exploited.
- Use `Debris:AddItem()` on all VFX parts and sounds.

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

When generating multi-jump code, adapt to these user-specified parameters:

- `$MAX_JUMPS` - Total number of allowed jumps (default: 2)
- `$EXTRA_JUMP_POWER` - Upward velocity for extra jumps in studs/s (default: 55)
- `$JUMP_COOLDOWN` - Minimum seconds between jumps (default: 0.15)
- `$VFX_ENABLED` - Whether to show visual effects (default: true)
- `$VFX_RING` - Whether to show expanding ring effect (default: true)
- `$VFX_PARTICLES` - Whether to show particle burst (default: true)
- `$VFX_COLOR` - Base color for VFX (default: "255,255,255")
- `$SOUND_ENABLED` - Whether to play jump sounds (default: true)
- `$SOUND_ID` - Sound asset ID for extra jumps (default: "")
- `$SHOW_HUD` - Whether to show jump count indicator (default: true)
