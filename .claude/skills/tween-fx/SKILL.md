---
name: tween-fx
description: |
  Advanced TweenService patterns for Roblox. Chain tweens in sequence, parallel
  tween groups, tween on Model PivotTo, spring-like bounce tweens, elastic easing,
  and reusable tween utility library.
  고급 트윈 패턴, 체인 트윈, 병렬 트윈, 모델 피봇 트윈, 스프링 트윈, 탄성 이징
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
effort: high
---

# Advanced TweenService Patterns

Build reusable tween utilities for chained sequences, parallel groups, Model pivot tweening, spring-like physics tweens, and common UI/VFX animation patterns.

## Architecture Overview

```
ReplicatedStorage/
  TweenFX/
    TweenFX.lua            -- Main utility module
    TweenChain.lua         -- Sequential tween chains
    TweenGroup.lua         -- Parallel tween groups
    SpringTween.lua        -- Spring-physics based tweens
    ModelTween.lua         -- Tween Models via PivotTo
    UITween.lua            -- Common UI animation presets
```

## Core TweenFX Module

```lua
-- ReplicatedStorage/TweenFX/TweenFX.lua
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local TweenFX = {}

export type TweenFXOptions = {
    duration: number,
    easingStyle: Enum.EasingStyle?,
    easingDirection: Enum.EasingDirection?,
    repeatCount: number?,
    reverses: boolean?,
    delayTime: number?,
}

--------------------------------------------------------------------------------
-- Quick tween shorthand
--------------------------------------------------------------------------------
function TweenFX.tween(instance: Instance, options: TweenFXOptions, properties: { [string]: any }): Tween
    local info = TweenInfo.new(
        options.duration,
        options.easingStyle or Enum.EasingStyle.Quad,
        options.easingDirection or Enum.EasingDirection.Out,
        options.repeatCount or 0,
        options.reverses or false,
        options.delayTime or 0
    )
    local tween = TweenService:Create(instance, info, properties)
    tween:Play()
    return tween
end

--------------------------------------------------------------------------------
-- Tween and wait (yields until complete)
--------------------------------------------------------------------------------
function TweenFX.tweenAwait(instance: Instance, options: TweenFXOptions, properties: { [string]: any })
    local tween = TweenFX.tween(instance, options, properties)
    tween.Completed:Wait()
end

--------------------------------------------------------------------------------
-- Tween with callback
--------------------------------------------------------------------------------
function TweenFX.tweenThen(instance: Instance, options: TweenFXOptions, properties: { [string]: any }, callback: () -> ())
    local tween = TweenFX.tween(instance, options, properties)
    tween.Completed:Connect(callback)
    return tween
end

--------------------------------------------------------------------------------
-- Chain tweens (sequential)
--------------------------------------------------------------------------------
function TweenFX.chain(steps: { { instance: Instance, options: TweenFXOptions, properties: { [string]: any } } }): ()
    for _, step in ipairs(steps) do
        TweenFX.tweenAwait(step.instance, step.options, step.properties)
    end
end

--------------------------------------------------------------------------------
-- Chain tweens (sequential, non-yielding, returns cancel function)
--------------------------------------------------------------------------------
function TweenFX.chainAsync(steps: { { instance: Instance, options: TweenFXOptions, properties: { [string]: any } } }): () -> ()
    local cancelled = false

    task.spawn(function()
        for _, step in ipairs(steps) do
            if cancelled then break end
            TweenFX.tweenAwait(step.instance, step.options, step.properties)
        end
    end)

    return function()
        cancelled = true
    end
end

--------------------------------------------------------------------------------
-- Parallel tweens (all play simultaneously, yields until all complete)
--------------------------------------------------------------------------------
function TweenFX.parallel(tweens: { { instance: Instance, options: TweenFXOptions, properties: { [string]: any } } }): ()
    local activeTweens: { Tween } = {}
    local remaining = #tweens

    if remaining == 0 then return end

    local doneEvent = Instance.new("BindableEvent")

    for _, tweenDef in ipairs(tweens) do
        local tween = TweenFX.tween(tweenDef.instance, tweenDef.options, tweenDef.properties)
        table.insert(activeTweens, tween)

        tween.Completed:Connect(function()
            remaining -= 1
            if remaining <= 0 then
                doneEvent:Fire()
            end
        end)
    end

    doneEvent.Event:Wait()
    doneEvent:Destroy()
end

--------------------------------------------------------------------------------
-- Parallel (non-yielding, returns cancel function)
--------------------------------------------------------------------------------
function TweenFX.parallelAsync(tweens: { { instance: Instance, options: TweenFXOptions, properties: { [string]: any } } }): () -> ()
    local activeTweens: { Tween } = {}

    for _, tweenDef in ipairs(tweens) do
        local tween = TweenFX.tween(tweenDef.instance, tweenDef.options, tweenDef.properties)
        table.insert(activeTweens, tween)
    end

    return function()
        for _, tween in activeTweens do
            tween:Cancel()
        end
    end
end

--------------------------------------------------------------------------------
-- Staggered tweens (same animation on multiple instances with delay between)
--------------------------------------------------------------------------------
function TweenFX.stagger(
    instances: { Instance },
    options: TweenFXOptions,
    properties: { [string]: any },
    staggerDelay: number
): ()
    for i, instance in ipairs(instances) do
        local staggerOpts = table.clone(options)
        staggerOpts.delayTime = (staggerOpts.delayTime or 0) + (i - 1) * staggerDelay
        TweenFX.tween(instance, staggerOpts, properties)
    end
end

return TweenFX
```

## Model Tween (PivotTo)

```lua
-- ReplicatedStorage/TweenFX/ModelTween.lua
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local ModelTween = {}

--------------------------------------------------------------------------------
-- Tween a Model from its current pivot to a target CFrame
-- Models can't be tweened directly with TweenService, so we use
-- a CFrameValue proxy and update PivotTo each frame.
--------------------------------------------------------------------------------
function ModelTween.tweenModelPivot(
    model: Model,
    targetCFrame: CFrame,
    duration: number,
    easingStyle: Enum.EasingStyle?,
    easingDirection: Enum.EasingDirection?
): () -> ()
    local startCF = model:GetPivot()
    local style = easingStyle or Enum.EasingStyle.Quad
    local direction = easingDirection or Enum.EasingDirection.InOut

    -- Use a CFrameValue as a proxy to leverage TweenService
    local proxy = Instance.new("CFrameValue")
    proxy.Value = startCF

    local info = TweenInfo.new(duration, style, direction)
    local tween = TweenService:Create(proxy, info, { Value = targetCFrame })

    local connection: RBXScriptConnection
    connection = RunService.Heartbeat:Connect(function()
        if model and model.Parent then
            model:PivotTo(proxy.Value)
        end
    end)

    tween.Completed:Connect(function()
        connection:Disconnect()
        model:PivotTo(targetCFrame) -- Ensure exact final position
        proxy:Destroy()
    end)

    tween:Play()

    -- Return cancel function
    return function()
        tween:Cancel()
        connection:Disconnect()
        proxy:Destroy()
    end
end

--------------------------------------------------------------------------------
-- Tween a Model and yield until complete
--------------------------------------------------------------------------------
function ModelTween.tweenModelPivotAwait(
    model: Model,
    targetCFrame: CFrame,
    duration: number,
    easingStyle: Enum.EasingStyle?,
    easingDirection: Enum.EasingDirection?
)
    local startCF = model:GetPivot()
    local style = easingStyle or Enum.EasingStyle.Quad
    local direction = easingDirection or Enum.EasingDirection.InOut

    local proxy = Instance.new("CFrameValue")
    proxy.Value = startCF

    local info = TweenInfo.new(duration, style, direction)
    local tween = TweenService:Create(proxy, info, { Value = targetCFrame })

    local connection: RBXScriptConnection
    connection = RunService.Heartbeat:Connect(function()
        if model and model.Parent then
            model:PivotTo(proxy.Value)
        end
    end)

    tween:Play()
    tween.Completed:Wait()

    connection:Disconnect()
    model:PivotTo(targetCFrame)
    proxy:Destroy()
end

--------------------------------------------------------------------------------
-- Orbit a Model around a center point
--------------------------------------------------------------------------------
function ModelTween.orbit(
    model: Model,
    center: Vector3,
    radius: number,
    orbitDuration: number,
    axis: Vector3? -- default Y-axis
): () -> ()
    local rotAxis = (axis or Vector3.yAxis).Unit
    local elapsed = 0
    local running = true

    task.spawn(function()
        while running do
            local dt = RunService.Heartbeat:Wait()
            elapsed += dt
            local angle = (elapsed / orbitDuration) * math.pi * 2
            local offset = CFrame.fromAxisAngle(rotAxis, angle) * Vector3.new(radius, 0, 0)
            local pos = center + offset
            model:PivotTo(CFrame.new(pos, center))
        end
    end)

    return function()
        running = false
    end
end

--------------------------------------------------------------------------------
-- Bobbing hover effect for a Model
--------------------------------------------------------------------------------
function ModelTween.hover(
    model: Model,
    amplitude: number?,    -- studs of vertical movement (default 1)
    frequency: number?,    -- oscillations per second (default 0.5)
    rotationSpeed: number? -- degrees per second of Y rotation (default 0)
): () -> ()
    local amp = amplitude or 1
    local freq = frequency or 0.5
    local rotSpeed = rotationSpeed or 0
    local baseCF = model:GetPivot()
    local elapsed = 0
    local running = true

    task.spawn(function()
        while running do
            local dt = RunService.Heartbeat:Wait()
            elapsed += dt
            local yOffset = math.sin(elapsed * freq * math.pi * 2) * amp
            local rotation = CFrame.Angles(0, math.rad(rotSpeed * elapsed), 0)
            model:PivotTo(baseCF * rotation * CFrame.new(0, yOffset, 0))
        end
    end)

    return function()
        running = false
        model:PivotTo(baseCF)
    end
end

return ModelTween
```

## Spring Tween (Physics-Based)

```lua
-- ReplicatedStorage/TweenFX/SpringTween.lua
local RunService = game:GetService("RunService")

local SpringTween = {}

export type SpringConfig = {
    stiffness: number,    -- spring constant (higher = snappier), default 170
    damping: number,      -- damping ratio (higher = less bouncy), default 26
    mass: number?,        -- mass (default 1)
    precision: number?,   -- stop threshold (default 0.01)
}

local DEFAULT_CONFIG: SpringConfig = {
    stiffness = 170,
    damping = 26,
    mass = 1,
    precision = 0.01,
}

--------------------------------------------------------------------------------
-- 1D Spring simulation
--------------------------------------------------------------------------------
local function createSpring1D(from: number, to: number, config: SpringConfig?): (number, number, boolean)
    -- Returns: position, velocity, isAtRest
    local cfg = config or DEFAULT_CONFIG
    local stiffness = cfg.stiffness
    local damping = cfg.damping
    local mass = cfg.mass or 1
    local precision = cfg.precision or 0.01

    local position = from
    local velocity = 0

    return function(dt: number): (number, boolean)
        -- Spring force: F = -k * (x - target) - d * v
        local displacement = position - to
        local springForce = -stiffness * displacement
        local dampingForce = -damping * velocity
        local acceleration = (springForce + dampingForce) / mass

        velocity += acceleration * dt
        position += velocity * dt

        local atRest = math.abs(displacement) < precision and math.abs(velocity) < precision
        if atRest then
            position = to
            velocity = 0
        end

        return position, atRest
    end
end

--------------------------------------------------------------------------------
-- Spring tween a numeric property
--------------------------------------------------------------------------------
function SpringTween.springNumber(
    instance: Instance,
    property: string,
    target: number,
    config: SpringConfig?,
    callback: ((number) -> ())?
): () -> ()
    local current = (instance :: any)[property]
    local step = createSpring1D(current, target, config)
    local running = true

    task.spawn(function()
        while running do
            local dt = RunService.Heartbeat:Wait()
            local value, atRest = step(dt)
            if not running then break end

            (instance :: any)[property] = value
            if callback then callback(value) end

            if atRest then
                running = false
                break
            end
        end
    end)

    return function()
        running = false
    end
end

--------------------------------------------------------------------------------
-- Spring tween a Vector3 property (Position, Size, etc.)
--------------------------------------------------------------------------------
function SpringTween.springVector3(
    instance: Instance,
    property: string,
    target: Vector3,
    config: SpringConfig?
): () -> ()
    local current = (instance :: any)[property] :: Vector3
    local stepX = createSpring1D(current.X, target.X, config)
    local stepY = createSpring1D(current.Y, target.Y, config)
    local stepZ = createSpring1D(current.Z, target.Z, config)
    local running = true

    task.spawn(function()
        while running do
            local dt = RunService.Heartbeat:Wait()
            local x, restX = stepX(dt)
            local y, restY = stepY(dt)
            local z, restZ = stepZ(dt);

            if not running then break end

            (instance :: any)[property] = Vector3.new(x, y, z)

            if restX and restY and restZ then
                running = false
                break
            end
        end
    end)

    return function()
        running = false
    end
end

--------------------------------------------------------------------------------
-- Spring tween a UDim2 property (Position, Size for UI)
--------------------------------------------------------------------------------
function SpringTween.springUDim2(
    instance: GuiObject,
    property: string,
    target: UDim2,
    config: SpringConfig?
): () -> ()
    local current = (instance :: any)[property] :: UDim2
    local stepXS = createSpring1D(current.X.Scale, target.X.Scale, config)
    local stepXO = createSpring1D(current.X.Offset, target.X.Offset, config)
    local stepYS = createSpring1D(current.Y.Scale, target.Y.Scale, config)
    local stepYO = createSpring1D(current.Y.Offset, target.Y.Offset, config)
    local running = true

    task.spawn(function()
        while running do
            local dt = RunService.Heartbeat:Wait()
            local xs, rxs = stepXS(dt)
            local xo, rxo = stepXO(dt)
            local ys, rys = stepYS(dt)
            local yo, ryo = stepYO(dt);

            if not running then break end

            (instance :: any)[property] = UDim2.new(xs, xo, ys, yo)

            if rxs and rxo and rys and ryo then
                running = false
                break
            end
        end
    end)

    return function()
        running = false
    end
end

--------------------------------------------------------------------------------
-- Preset spring configs
--------------------------------------------------------------------------------
SpringTween.Presets = {
    Gentle = { stiffness = 120, damping = 14, mass = 1, precision = 0.01 },
    Wobbly = { stiffness = 180, damping = 12, mass = 1, precision = 0.01 },
    Stiff = { stiffness = 300, damping = 30, mass = 1, precision = 0.01 },
    Slow = { stiffness = 100, damping = 20, mass = 2, precision = 0.01 },
    Bouncy = { stiffness = 200, damping = 8, mass = 1, precision = 0.01 },
    Snappy = { stiffness = 400, damping = 35, mass = 1, precision = 0.01 },
}

return SpringTween
```

## UI Tween Presets

```lua
-- ReplicatedStorage/TweenFX/UITween.lua
local TweenService = game:GetService("TweenService")

local UITween = {}

--------------------------------------------------------------------------------
-- Fade in a GUI element
--------------------------------------------------------------------------------
function UITween.fadeIn(gui: GuiObject, duration: number?): Tween
    gui.Visible = true
    local tween = TweenService:Create(gui, TweenInfo.new(duration or 0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        BackgroundTransparency = gui:GetAttribute("TargetTransparency") or 0,
    })
    tween:Play()
    return tween
end

--------------------------------------------------------------------------------
-- Fade out a GUI element
--------------------------------------------------------------------------------
function UITween.fadeOut(gui: GuiObject, duration: number?): Tween
    local tween = TweenService:Create(gui, TweenInfo.new(duration or 0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
        BackgroundTransparency = 1,
    })
    tween:Play()
    tween.Completed:Connect(function()
        gui.Visible = false
    end)
    return tween
end

--------------------------------------------------------------------------------
-- Slide in from direction
--------------------------------------------------------------------------------
function UITween.slideIn(gui: GuiObject, from: "Left" | "Right" | "Top" | "Bottom", duration: number?): Tween
    local finalPos = gui.Position
    local offscreen: UDim2

    if from == "Left" then
        offscreen = UDim2.new(-1, 0, finalPos.Y.Scale, finalPos.Y.Offset)
    elseif from == "Right" then
        offscreen = UDim2.new(1.5, 0, finalPos.Y.Scale, finalPos.Y.Offset)
    elseif from == "Top" then
        offscreen = UDim2.new(finalPos.X.Scale, finalPos.X.Offset, -1, 0)
    else -- Bottom
        offscreen = UDim2.new(finalPos.X.Scale, finalPos.X.Offset, 1.5, 0)
    end

    gui.Position = offscreen
    gui.Visible = true

    local tween = TweenService:Create(gui, TweenInfo.new(duration or 0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        Position = finalPos,
    })
    tween:Play()
    return tween
end

--------------------------------------------------------------------------------
-- Pop-in scale effect (starts small, bounces to full size)
--------------------------------------------------------------------------------
function UITween.popIn(gui: GuiObject, duration: number?): Tween
    local finalSize = gui.Size
    gui.Size = UDim2.new(
        finalSize.X.Scale * 0.3, finalSize.X.Offset * 0.3,
        finalSize.Y.Scale * 0.3, finalSize.Y.Offset * 0.3
    )
    gui.Visible = true

    local tween = TweenService:Create(gui, TweenInfo.new(duration or 0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        Size = finalSize,
    })
    tween:Play()
    return tween
end

--------------------------------------------------------------------------------
-- Pop-out scale effect (shrinks and hides)
--------------------------------------------------------------------------------
function UITween.popOut(gui: GuiObject, duration: number?): Tween
    local tween = TweenService:Create(gui, TweenInfo.new(duration or 0.25, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
        Size = UDim2.new(0, 0, 0, 0),
    })
    tween:Play()
    tween.Completed:Connect(function()
        gui.Visible = false
    end)
    return tween
end

--------------------------------------------------------------------------------
-- Pulse effect (scale up then back, repeating)
--------------------------------------------------------------------------------
function UITween.pulse(gui: GuiObject, scale: number?, duration: number?): Tween
    local s = scale or 1.1
    local finalSize = gui.Size
    local bigSize = UDim2.new(
        finalSize.X.Scale * s, finalSize.X.Offset * s,
        finalSize.Y.Scale * s, finalSize.Y.Offset * s
    )

    local tween = TweenService:Create(gui, TweenInfo.new(
        duration or 0.5,
        Enum.EasingStyle.Sine,
        Enum.EasingDirection.InOut,
        -1, -- infinite repeat
        true -- reverses
    ), {
        Size = bigSize,
    })
    tween:Play()
    return tween
end

--------------------------------------------------------------------------------
-- Shake effect (rapid small position oscillations)
--------------------------------------------------------------------------------
function UITween.shake(gui: GuiObject, intensity: number?, duration: number?)
    local originalPos = gui.Position
    local shakeAmount = intensity or 5
    local shakeDuration = duration or 0.4
    local elapsed = 0

    task.spawn(function()
        while elapsed < shakeDuration do
            local dt = task.wait()
            elapsed += dt
            local offsetX = (math.random() - 0.5) * 2 * shakeAmount
            local offsetY = (math.random() - 0.5) * 2 * shakeAmount
            gui.Position = UDim2.new(
                originalPos.X.Scale, originalPos.X.Offset + offsetX,
                originalPos.Y.Scale, originalPos.Y.Offset + offsetY
            )
        end
        gui.Position = originalPos
    end)
end

--------------------------------------------------------------------------------
-- Typewriter text reveal
--------------------------------------------------------------------------------
function UITween.typewriter(label: TextLabel, text: string, charsPerSecond: number?): () -> ()
    local speed = charsPerSecond or 30
    local cancelled = false
    label.Text = ""

    task.spawn(function()
        for i = 1, #text do
            if cancelled then
                label.Text = text
                return
            end
            label.Text = string.sub(text, 1, i)
            task.wait(1 / speed)
        end
    end)

    return function()
        cancelled = true
        label.Text = text
    end
end

return UITween
```

## Usage Examples

```lua
-- Example: Chain tweens
local TweenFX = require(ReplicatedStorage.TweenFX.TweenFX)
local ModelTween = require(ReplicatedStorage.TweenFX.ModelTween)
local SpringTween = require(ReplicatedStorage.TweenFX.SpringTween)
local UITween = require(ReplicatedStorage.TweenFX.UITween)

-- Sequential chain: move right, then up, then scale
TweenFX.chain({
    { instance = part, options = { duration = 1 }, properties = { Position = Vector3.new(10, 0, 0) } },
    { instance = part, options = { duration = 0.5 }, properties = { Position = Vector3.new(10, 10, 0) } },
    { instance = part, options = { duration = 0.3, easingStyle = Enum.EasingStyle.Elastic }, properties = { Size = Vector3.new(4, 4, 4) } },
})

-- Parallel: fade and move simultaneously
TweenFX.parallel({
    { instance = part, options = { duration = 1 }, properties = { Transparency = 1 } },
    { instance = part, options = { duration = 1 }, properties = { Position = Vector3.new(0, 20, 0) } },
})

-- Stagger: cascade animation across multiple parts
local parts = { part1, part2, part3, part4, part5 }
TweenFX.stagger(parts, { duration = 0.5 }, { Transparency = 0 }, 0.1)

-- Spring tween a part's position (bouncy)
local cancel = SpringTween.springVector3(part, "Position", Vector3.new(0, 10, 0), SpringTween.Presets.Bouncy)

-- Model tween with PivotTo
local cancelHover = ModelTween.hover(doorModel, 0.5, 0.3, 15)
-- Later: cancelHover() to stop

-- UI animations
UITween.slideIn(menuFrame, "Left", 0.4)
UITween.popIn(notificationFrame, 0.3)
UITween.pulse(importantButton, 1.05, 0.6)
UITween.shake(damageFrame, 8, 0.3)
```

## Key Implementation Notes

1. **Chain tweens**: `chain()` yields through each step sequentially. `chainAsync()` runs in a background thread and returns a cancel function.

2. **Parallel tweens**: `parallel()` starts all tweens at once and yields until all finish. `parallelAsync()` returns a cancel function.

3. **Stagger**: Same animation applied to multiple instances with increasing delay. Great for list animations.

4. **Model PivotTo tweening**: Uses a CFrameValue proxy with TweenService, updating PivotTo on Heartbeat. This is the standard workaround since TweenService can't directly tween Model pivot.

5. **Spring physics**: Real damped spring simulation. Configure stiffness (snappiness), damping (bounciness), and mass. Use presets like Bouncy, Stiff, Wobbly for quick results.

6. **UI presets**: SlideIn, PopIn, FadeIn, Pulse, Shake, and Typewriter cover the most common UI animation needs.

7. **Cancel functions**: Most async methods return `() -> ()` cancel functions for cleanup.

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

When the user asks for tween/animation patterns, ask:
- What are you animating? (parts, models, UI, camera)
- Do you need sequential chains or parallel groups?
- Do you want spring/bounce physics or standard easing?
- Do you need hover/orbit effects for world objects?
- What UI animations do you need? (slide, pop, fade, shake)
- Should animations be cancellable?
