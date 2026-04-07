---
name: doors
description: |
  Roblox 문/도어 시스템 스킬. 힌지 문, 슬라이딩 문, 자동문(근접 감지), 비밀 벽,
  열쇠 잠금 시스템, 벽에서 문 구멍 뚫기를 구현합니다.
  키워드: 문, 도어, 힌지, 슬라이딩, 자동문, 비밀문, 비밀벽, 잠금, 열쇠, 자물쇠,
  여닫이, 미닫이, 회전문, 게이트, 문틀, 출입구, 포탈,
  door, hinge, sliding, automatic, secret, wall, locked, key, gate, portal, entrance
allowed-tools:
  - Bash
  - Edit
  - Write
  - Read
  - Grep
  - Glob
  - WebFetch
  - WebSearch
  - mcp__roblox-mcp__execute_luau_in_studio
effort: high
---

# Doors Skill

Roblox에서 다양한 종류의 문(힌지, 슬라이딩, 자동, 비밀벽, 잠금)을 생성하는 스킬입니다.

## Door Frame Cutting

### Cut Door Opening from a Wall
```lua
local function cutDoorFromWall(wall: BasePart, config: {
    doorWidth: number?,
    doorHeight: number?,
    position: Vector3?,      -- center-bottom of doorway in world space
    wallThickness: number?,  -- override if known
}): { top: Part?, left: Part?, right: Part? }
    local doorW = config.doorWidth or 4
    local doorH = config.doorHeight or 7

    local wallSize = wall.Size
    local wallCF = wall.CFrame
    local wallThick = config.wallThickness or wallSize.Z

    -- Calculate door position relative to wall
    local doorPos = config.position or (wallCF.Position - Vector3.new(0, wallSize.Y / 2 - doorH / 2, 0))
    local localPos = wallCF:PointToObjectSpace(doorPos)

    -- The wall's local X is width, Y is height, Z is thickness
    local leftWidth = localPos.X + wallSize.X / 2 - doorW / 2
    local rightWidth = wallSize.X / 2 - localPos.X - doorW / 2
    local topHeight = wallSize.Y - doorH - (localPos.Y + wallSize.Y / 2)

    local results = {}

    -- Left section
    if leftWidth > 0.1 then
        local leftPart = Instance.new("Part")
        leftPart.Name = wall.Name .. "_Left"
        leftPart.Size = Vector3.new(leftWidth, wallSize.Y, wallThick)
        leftPart.CFrame = wallCF * CFrame.new(-wallSize.X / 2 + leftWidth / 2, 0, 0)
        leftPart.Material = wall.Material
        leftPart.Color = wall.Color
        leftPart.Anchored = true
        leftPart.Parent = wall.Parent
        results.left = leftPart
    end

    -- Right section
    if rightWidth > 0.1 then
        local rightPart = Instance.new("Part")
        rightPart.Name = wall.Name .. "_Right"
        rightPart.Size = Vector3.new(rightWidth, wallSize.Y, wallThick)
        rightPart.CFrame = wallCF * CFrame.new(wallSize.X / 2 - rightWidth / 2, 0, 0)
        rightPart.Material = wall.Material
        rightPart.Color = wall.Color
        rightPart.Anchored = true
        rightPart.Parent = wall.Parent
        results.right = rightPart
    end

    -- Top section (above door)
    if topHeight > 0.1 then
        local topPart = Instance.new("Part")
        topPart.Name = wall.Name .. "_Top"
        topPart.Size = Vector3.new(doorW, topHeight, wallThick)
        topPart.CFrame = wallCF * CFrame.new(localPos.X, wallSize.Y / 2 - topHeight / 2, 0)
        topPart.Material = wall.Material
        topPart.Color = wall.Color
        topPart.Anchored = true
        topPart.Parent = wall.Parent
        results.top = topPart
    end

    -- Remove original wall
    wall:Destroy()

    return results
end
```

## Hinge Door

### Basic Hinge Door with TweenService
```lua
local TweenService = game:GetService("TweenService")

local function createHingeDoor(config: {
    position: Vector3,
    size: Vector3?,          -- {width, height, thickness}
    material: Enum.Material?,
    color: Color3?,
    hingeDirection: string?, -- "left" | "right"
    openAngle: number?,      -- degrees
    openSpeed: number?,      -- seconds to open
    autoClose: boolean?,
    autoCloseDelay: number?,
    withFrame: boolean?,
    frameColor: Color3?,
}): Model
    local doorW = (config.size and config.size.X) or 4
    local doorH = (config.size and config.size.Y) or 7
    local doorT = (config.size and config.size.Z) or 0.4
    local mat = config.material or Enum.Material.Wood
    local col = config.color or Color3.fromRGB(120, 80, 40)
    local hingeSide = config.hingeDirection or "left"
    local openAngle = config.openAngle or 90
    local speed = config.openSpeed or 0.5

    local model = Instance.new("Model")
    model.Name = "HingeDoor"

    -- Door frame (optional)
    if config.withFrame ~= false then
        local frameCol = config.frameColor or Color3.fromRGB(90, 60, 30)
        local frameThick = 0.3

        -- Top frame
        local topFrame = Instance.new("Part")
        topFrame.Name = "FrameTop"
        topFrame.Size = Vector3.new(doorW + frameThick * 2, frameThick, doorT + 0.2)
        topFrame.CFrame = CFrame.new(config.position + Vector3.new(0, doorH + frameThick / 2, 0))
        topFrame.Material = mat
        topFrame.Color = frameCol
        topFrame.Anchored = true
        topFrame.Parent = model

        -- Side frames
        for _, side in ipairs({-1, 1}) do
            local sideFrame = Instance.new("Part")
            sideFrame.Name = "FrameSide"
            sideFrame.Size = Vector3.new(frameThick, doorH, doorT + 0.2)
            sideFrame.CFrame = CFrame.new(config.position + Vector3.new(
                side * (doorW / 2 + frameThick / 2), doorH / 2, 0
            ))
            sideFrame.Material = mat
            sideFrame.Color = frameCol
            sideFrame.Anchored = true
            sideFrame.Parent = model
        end
    end

    -- Hinge point (pivot)
    local hingeX = hingeSide == "left" and -doorW / 2 or doorW / 2
    local hingePart = Instance.new("Part")
    hingePart.Name = "HingePivot"
    hingePart.Size = Vector3.new(0.1, 0.1, 0.1)
    hingePart.CFrame = CFrame.new(config.position + Vector3.new(hingeX, doorH / 2, 0))
    hingePart.Transparency = 1
    hingePart.Anchored = true
    hingePart.CanCollide = false
    hingePart.Parent = model

    -- Door panel
    local door = Instance.new("Part")
    door.Name = "DoorPanel"
    door.Size = Vector3.new(doorW, doorH, doorT)
    door.CFrame = CFrame.new(config.position + Vector3.new(0, doorH / 2, 0))
    door.Material = mat
    door.Color = col
    door.Anchored = true
    door.Parent = model

    -- Door handle
    local handle = Instance.new("Part")
    handle.Name = "Handle"
    handle.Shape = Enum.PartType.Cylinder
    handle.Size = Vector3.new(0.15, 0.5, 0.5)
    local handleX = hingeSide == "left" and doorW / 2 - 0.6 or -doorW / 2 + 0.6
    handle.CFrame = CFrame.new(config.position + Vector3.new(handleX, doorH * 0.45, doorT / 2 + 0.25))
    handle.Material = Enum.Material.Metal
    handle.Color = Color3.fromRGB(180, 160, 100)
    handle.Anchored = true
    handle.Parent = model

    -- Door state
    local isOpen = false
    local isTweening = false

    local closedCF = door.CFrame
    local closedHandleCF = handle.CFrame

    -- Calculate open CFrame (rotate around hinge)
    local hingePos = hingePart.CFrame.Position
    local sign = hingeSide == "left" and 1 or -1
    local rotCF = CFrame.Angles(0, math.rad(openAngle * sign), 0)

    local function getOpenCF(part: BasePart, partClosedCF: CFrame): CFrame
        local relativeToHinge = CFrame.new(hingePos):Inverse() * partClosedCF
        return CFrame.new(hingePos) * rotCF * relativeToHinge
    end

    local openDoorCF = getOpenCF(door, closedCF)
    local openHandleCF = getOpenCF(handle, closedHandleCF)

    local function toggleDoor()
        if isTweening then return end
        isTweening = true
        isOpen = not isOpen

        local targetDoorCF = isOpen and openDoorCF or closedCF
        local targetHandleCF = isOpen and openHandleCF or closedHandleCF

        local tweenInfo = TweenInfo.new(speed, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
        local doorTween = TweenService:Create(door, tweenInfo, { CFrame = targetDoorCF })
        local handleTween = TweenService:Create(handle, tweenInfo, { CFrame = targetHandleCF })

        doorTween:Play()
        handleTween:Play()

        doorTween.Completed:Wait()
        isTweening = false

        -- Auto close
        if isOpen and config.autoClose then
            task.delay(config.autoCloseDelay or 3, function()
                if isOpen then
                    toggleDoor()
                end
            end)
        end
    end

    -- ClickDetector on door
    local clickDetector = Instance.new("ClickDetector")
    clickDetector.MaxActivationDistance = 10
    clickDetector.Parent = door
    clickDetector.MouseClick:Connect(function()
        toggleDoor()
    end)

    model.PrimaryPart = door
    model.Parent = workspace

    return model
end
```

## Sliding Door

```lua
local TweenService = game:GetService("TweenService")

local function createSlidingDoor(config: {
    position: Vector3,
    size: Vector3?,
    material: Enum.Material?,
    color: Color3?,
    slideDirection: string?,  -- "left" | "right" | "up" | "both"
    slideDistance: number?,
    speed: number?,
    withFrame: boolean?,
}): Model
    local doorW = (config.size and config.size.X) or 4
    local doorH = (config.size and config.size.Y) or 7
    local doorT = (config.size and config.size.Z) or 0.3
    local mat = config.material or Enum.Material.Metal
    local col = config.color or Color3.fromRGB(150, 155, 160)
    local slideDir = config.slideDirection or "left"
    local slideDist = config.slideDistance or doorW
    local speed = config.speed or 0.8

    local model = Instance.new("Model")
    model.Name = "SlidingDoor"

    if slideDir == "both" then
        -- Double sliding door
        local halfW = doorW / 2

        local leftPanel = Instance.new("Part")
        leftPanel.Name = "LeftPanel"
        leftPanel.Size = Vector3.new(halfW, doorH, doorT)
        leftPanel.CFrame = CFrame.new(config.position + Vector3.new(-halfW / 2, doorH / 2, 0))
        leftPanel.Material = mat
        leftPanel.Color = col
        leftPanel.Anchored = true
        leftPanel.Parent = model

        local rightPanel = Instance.new("Part")
        rightPanel.Name = "RightPanel"
        rightPanel.Size = Vector3.new(halfW, doorH, doorT)
        rightPanel.CFrame = CFrame.new(config.position + Vector3.new(halfW / 2, doorH / 2, 0))
        rightPanel.Material = mat
        rightPanel.Color = col
        rightPanel.Anchored = true
        rightPanel.Parent = model

        local isOpen = false
        local isTweening = false

        local leftClosedCF = leftPanel.CFrame
        local rightClosedCF = rightPanel.CFrame
        local leftOpenCF = leftClosedCF * CFrame.new(-halfW, 0, 0)
        local rightOpenCF = rightClosedCF * CFrame.new(halfW, 0, 0)

        local function toggle()
            if isTweening then return end
            isTweening = true
            isOpen = not isOpen

            local tweenInfo = TweenInfo.new(speed, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
            local lt = TweenService:Create(leftPanel, tweenInfo, {
                CFrame = isOpen and leftOpenCF or leftClosedCF,
            })
            local rt = TweenService:Create(rightPanel, tweenInfo, {
                CFrame = isOpen and rightOpenCF or rightClosedCF,
            })
            lt:Play()
            rt:Play()
            lt.Completed:Wait()
            isTweening = false
        end

        local detector = Instance.new("ClickDetector")
        detector.MaxActivationDistance = 10
        detector.Parent = leftPanel
        detector.MouseClick:Connect(toggle)

        local detector2 = Instance.new("ClickDetector")
        detector2.MaxActivationDistance = 10
        detector2.Parent = rightPanel
        detector2.MouseClick:Connect(toggle)
    else
        -- Single panel sliding door
        local door = Instance.new("Part")
        door.Name = "DoorPanel"
        door.Size = Vector3.new(doorW, doorH, doorT)
        door.CFrame = CFrame.new(config.position + Vector3.new(0, doorH / 2, 0))
        door.Material = mat
        door.Color = col
        door.Anchored = true
        door.Parent = model

        local closedCF = door.CFrame
        local slideOffset
        if slideDir == "left" then
            slideOffset = CFrame.new(-slideDist, 0, 0)
        elseif slideDir == "right" then
            slideOffset = CFrame.new(slideDist, 0, 0)
        else -- up
            slideOffset = CFrame.new(0, slideDist, 0)
        end
        local openCF = closedCF * slideOffset

        local isOpen = false
        local isTweening = false

        local function toggle()
            if isTweening then return end
            isTweening = true
            isOpen = not isOpen

            local tweenInfo = TweenInfo.new(speed, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
            local tween = TweenService:Create(door, tweenInfo, {
                CFrame = isOpen and openCF or closedCF,
            })
            tween:Play()
            tween.Completed:Wait()
            isTweening = false
        end

        local detector = Instance.new("ClickDetector")
        detector.MaxActivationDistance = 10
        detector.Parent = door
        detector.MouseClick:Connect(toggle)
    end

    -- Frame (optional)
    if config.withFrame ~= false then
        local frameCol = Color3.fromRGB(80, 80, 85)
        local ft = 0.3

        local topF = Instance.new("Part")
        topF.Name = "FrameTop"
        topF.Size = Vector3.new(doorW + ft * 2, ft, doorT + 0.2)
        topF.CFrame = CFrame.new(config.position + Vector3.new(0, doorH + ft / 2, 0))
        topF.Material = Enum.Material.Metal
        topF.Color = frameCol
        topF.Anchored = true
        topF.Parent = model

        for _, s in ipairs({-1, 1}) do
            local sF = Instance.new("Part")
            sF.Name = "FrameSide"
            sF.Size = Vector3.new(ft, doorH, doorT + 0.2)
            sF.CFrame = CFrame.new(config.position + Vector3.new(s * (doorW / 2 + ft / 2), doorH / 2, 0))
            sF.Material = Enum.Material.Metal
            sF.Color = frameCol
            sF.Anchored = true
            sF.Parent = model
        end
    end

    model.Parent = workspace
    return model
end
```

## Automatic Proximity Door

```lua
local function createAutoDoor(config: {
    position: Vector3,
    size: Vector3?,
    material: Enum.Material?,
    color: Color3?,
    triggerRadius: number?,
    slideDirection: string?,
    speed: number?,
    soundOpen: string?,
    soundClose: string?,
}): Model
    local doorW = (config.size and config.size.X) or 6
    local doorH = (config.size and config.size.Y) or 8
    local doorT = (config.size and config.size.Z) or 0.3
    local triggerRadius = config.triggerRadius or 15
    local speed = config.speed or 0.6

    local model = Instance.new("Model")
    model.Name = "AutoDoor"

    -- Create double sliding panels
    local halfW = doorW / 2
    local panels = {}

    for i, side in ipairs({-1, 1}) do
        local panel = Instance.new("Part")
        panel.Name = "Panel_" .. i
        panel.Size = Vector3.new(halfW, doorH, doorT)
        panel.CFrame = CFrame.new(config.position + Vector3.new(side * halfW / 2, doorH / 2, 0))
        panel.Material = config.material or Enum.Material.Glass
        panel.Color = config.color or Color3.fromRGB(180, 200, 220)
        panel.Transparency = 0.3
        panel.Anchored = true
        panel.Parent = model
        panels[i] = {
            part = panel,
            closedCF = panel.CFrame,
            openCF = panel.CFrame * CFrame.new(side * halfW, 0, 0),
        }
    end

    -- Proximity detection
    local isOpen = false
    local RunService = game:GetService("RunService")
    local TweenService = game:GetService("TweenService")
    local Players = game:GetService("Players")

    local function openDoor()
        if isOpen then return end
        isOpen = true

        if config.soundOpen then
            local s = Instance.new("Sound")
            s.SoundId = config.soundOpen
            s.Parent = model.PrimaryPart or panels[1].part
            s:Play()
            s.Ended:Once(function() s:Destroy() end)
        end

        for _, p in ipairs(panels) do
            TweenService:Create(p.part, TweenInfo.new(speed, Enum.EasingStyle.Quad), {
                CFrame = p.openCF,
            }):Play()
        end
    end

    local function closeDoor()
        if not isOpen then return end
        isOpen = false

        if config.soundClose then
            local s = Instance.new("Sound")
            s.SoundId = config.soundClose
            s.Parent = model.PrimaryPart or panels[1].part
            s:Play()
            s.Ended:Once(function() s:Destroy() end)
        end

        for _, p in ipairs(panels) do
            TweenService:Create(p.part, TweenInfo.new(speed, Enum.EasingStyle.Quad), {
                CFrame = p.closedCF,
            }):Play()
        end
    end

    local doorCenter = config.position + Vector3.new(0, doorH / 2, 0)

    RunService.Heartbeat:Connect(function()
        local anyoneNear = false
        for _, player in ipairs(Players:GetPlayers()) do
            local char = player.Character
            if char then
                local root = char:FindFirstChild("HumanoidRootPart")
                if root then
                    local dist = (root.Position - doorCenter).Magnitude
                    if dist <= triggerRadius then
                        anyoneNear = true
                        break
                    end
                end
            end
        end

        if anyoneNear and not isOpen then
            openDoor()
        elseif not anyoneNear and isOpen then
            closeDoor()
        end
    end)

    model.Parent = workspace
    return model
end
```

## Secret Wall / Hidden Door

```lua
local TweenService = game:GetService("TweenService")

local function createSecretWall(config: {
    wall: BasePart,              -- existing wall to make into a secret door
    revealMethod: string?,       -- "click" | "proximity" | "interaction"
    slideDirection: Vector3?,    -- direction the wall slides
    slideDistance: number?,
    speed: number?,
    hint: boolean?,              -- subtle visual hint
}): { toggle: () -> (), isOpen: () -> boolean }
    local slideDir = config.slideDirection or Vector3.new(1, 0, 0)
    local slideDist = config.slideDistance or config.wall.Size.X
    local speed = config.speed or 2

    local closedCF = config.wall.CFrame
    local openCF = closedCF + slideDir.Unit * slideDist

    local isOpen = false
    local isTweening = false

    -- Subtle hint (slightly different shade)
    if config.hint then
        config.wall.Color = Color3.new(
            config.wall.Color.R * 0.97,
            config.wall.Color.G * 0.97,
            config.wall.Color.B * 0.97
        )
    end

    local function toggle()
        if isTweening then return end
        isTweening = true
        isOpen = not isOpen

        local tweenInfo = TweenInfo.new(speed, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
        local tween = TweenService:Create(config.wall, tweenInfo, {
            CFrame = isOpen and openCF or closedCF,
        })
        tween:Play()
        tween.Completed:Wait()
        isTweening = false
    end

    if config.revealMethod == "click" or config.revealMethod == nil then
        local detector = Instance.new("ClickDetector")
        detector.MaxActivationDistance = 8
        detector.Parent = config.wall
        detector.MouseClick:Connect(toggle)
    elseif config.revealMethod == "proximity" then
        local triggerPart = Instance.new("Part")
        triggerPart.Name = "SecretTrigger"
        triggerPart.Size = Vector3.new(6, 6, 6)
        triggerPart.CFrame = config.wall.CFrame
        triggerPart.Transparency = 1
        triggerPart.CanCollide = false
        triggerPart.Anchored = true
        triggerPart.Parent = config.wall.Parent

        triggerPart.Touched:Connect(function(hit)
            local humanoid = hit.Parent:FindFirstChildOfClass("Humanoid")
            if humanoid and not isOpen then
                toggle()
            end
        end)
    end

    return {
        toggle = toggle,
        isOpen = function() return isOpen end,
    }
end
```

## Locked Door with Key System

```lua
local function createLockedDoor(config: {
    position: Vector3,
    size: Vector3?,
    material: Enum.Material?,
    color: Color3?,
    keyName: string,          -- name of the tool/item required
    lockedMessage: string?,
    unlockSound: string?,
    lockColor: Color3?,
}): Model
    local doorW = (config.size and config.size.X) or 4
    local doorH = (config.size and config.size.Y) or 7
    local doorT = (config.size and config.size.Z) or 0.4
    local mat = config.material or Enum.Material.Wood
    local col = config.color or Color3.fromRGB(100, 65, 30)

    local model = Instance.new("Model")
    model.Name = "LockedDoor"

    -- Door panel
    local door = Instance.new("Part")
    door.Name = "DoorPanel"
    door.Size = Vector3.new(doorW, doorH, doorT)
    door.CFrame = CFrame.new(config.position + Vector3.new(0, doorH / 2, 0))
    door.Material = mat
    door.Color = col
    door.Anchored = true
    door.Parent = model

    -- Lock indicator
    local lockPart = Instance.new("Part")
    lockPart.Name = "Lock"
    lockPart.Shape = Enum.PartType.Ball
    lockPart.Size = Vector3.new(0.6, 0.6, 0.6)
    lockPart.CFrame = CFrame.new(config.position + Vector3.new(doorW / 2 - 0.8, doorH * 0.45, doorT / 2 + 0.3))
    lockPart.Material = Enum.Material.Metal
    lockPart.Color = config.lockColor or Color3.fromRGB(200, 50, 50) -- Red = locked
    lockPart.Anchored = true
    lockPart.Parent = model

    local isLocked = true
    local isOpen = false
    local TweenService = game:GetService("TweenService")

    local closedCF = door.CFrame
    local hingePos = config.position + Vector3.new(-doorW / 2, doorH / 2, 0)

    local function openDoor()
        if isOpen then return end
        isOpen = true

        local relToHinge = CFrame.new(hingePos):Inverse() * closedCF
        local openCF = CFrame.new(hingePos) * CFrame.Angles(0, math.rad(90), 0) * relToHinge

        local relLock = CFrame.new(hingePos):Inverse() * lockPart.CFrame
        local openLockCF = CFrame.new(hingePos) * CFrame.Angles(0, math.rad(90), 0) * relLock

        TweenService:Create(door, TweenInfo.new(0.5), { CFrame = openCF }):Play()
        TweenService:Create(lockPart, TweenInfo.new(0.5), { CFrame = openLockCF }):Play()
    end

    local function closeDoorAction()
        if not isOpen then return end
        isOpen = false

        local originalLockCF = CFrame.new(config.position + Vector3.new(doorW / 2 - 0.8, doorH * 0.45, doorT / 2 + 0.3))
        TweenService:Create(door, TweenInfo.new(0.5), { CFrame = closedCF }):Play()
        TweenService:Create(lockPart, TweenInfo.new(0.5), { CFrame = originalLockCF }):Play()
    end

    -- ClickDetector
    local detector = Instance.new("ClickDetector")
    detector.MaxActivationDistance = 10
    detector.Parent = door

    detector.MouseClick:Connect(function(player)
        if isLocked then
            -- Check if player has the key
            local backpack = player:FindFirstChild("Backpack")
            local character = player.Character
            local hasKey = false

            if backpack and backpack:FindFirstChild(config.keyName) then
                hasKey = true
            end
            if character and character:FindFirstChild(config.keyName) then
                hasKey = true
            end

            if hasKey then
                -- Unlock
                isLocked = false
                lockPart.Color = Color3.fromRGB(50, 200, 50) -- Green = unlocked

                if config.unlockSound then
                    local s = Instance.new("Sound")
                    s.SoundId = config.unlockSound
                    s.Parent = door
                    s:Play()
                    s.Ended:Once(function() s:Destroy() end)
                end

                task.wait(0.3)
                openDoor()
            else
                -- Show locked message
                local msg = config.lockedMessage or ("Requires: " .. config.keyName)
                -- Shake the door briefly to indicate locked
                local originalCF = door.CFrame
                for _ = 1, 3 do
                    door.CFrame = originalCF * CFrame.new(0.1, 0, 0)
                    task.wait(0.05)
                    door.CFrame = originalCF * CFrame.new(-0.1, 0, 0)
                    task.wait(0.05)
                end
                door.CFrame = originalCF
            end
        else
            -- Already unlocked, toggle open/close
            if isOpen then
                closeDoorAction()
            else
                openDoor()
            end
        end
    end)

    model.PrimaryPart = door
    model.Parent = workspace
    return model
end
```

## Key Item Creator

```lua
local function createKeyItem(config: {
    keyName: string,
    position: Vector3?,        -- if placed in world
    color: Color3?,
    inStarterPack: boolean?,
}): Tool
    local tool = Instance.new("Tool")
    tool.Name = config.keyName
    tool.CanBeDropped = true
    tool.RequiresHandle = true

    local handle = Instance.new("Part")
    handle.Name = "Handle"
    handle.Size = Vector3.new(0.5, 0.2, 1.5)
    handle.Material = Enum.Material.Metal
    handle.Color = config.color or Color3.fromRGB(200, 180, 50)
    handle.Parent = tool

    -- Key teeth
    local teeth = Instance.new("Part")
    teeth.Name = "Teeth"
    teeth.Size = Vector3.new(0.3, 0.4, 0.6)
    teeth.CFrame = handle.CFrame * CFrame.new(0, 0, -0.9)
    teeth.Material = Enum.Material.Metal
    teeth.Color = config.color or Color3.fromRGB(200, 180, 50)

    local weld = Instance.new("WeldConstraint")
    weld.Part0 = handle
    weld.Part1 = teeth
    weld.Parent = teeth
    teeth.Parent = tool

    if config.inStarterPack then
        tool.Parent = game:GetService("StarterPack")
    elseif config.position then
        -- Place in world as pickup
        handle.Anchored = false
        handle.CFrame = CFrame.new(config.position)
        tool.Parent = workspace
    end

    return tool
end
```

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

- `doorType`: "hinge" | "sliding" | "auto" | "secret" | "locked" -- 문 타입
- `position`: {x: number, y: number, z: number} -- 위치
- `size`: {width: number, height: number, thickness: number} -- 크기
- `material`: string -- 재질 (Enum.Material 이름)
- `color`: {r: number, g: number, b: number} -- 색상
- `hingeDirection`: "left" | "right" -- 힌지 방향
- `slideDirection`: "left" | "right" | "up" | "both" -- 슬라이드 방향
- `openAngle`: number -- 열림 각도 (도)
- `speed`: number -- 개폐 속도 (초)
- `autoClose`: boolean -- 자동 닫힘
- `triggerRadius`: number -- 자동문 감지 반경 (studs)
- `keyName`: string -- 잠금 문의 열쇠 이름
- `lockedMessage`: string -- 잠금 시 표시 메시지
- `cutFromWall`: boolean -- 벽에서 문 구멍 뚫기
- `withFrame`: boolean -- 문틀 포함
