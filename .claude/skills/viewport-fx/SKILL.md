---
name: viewport-fx
description: |
  ViewportFrame 아이템 미리보기, 미니맵, 3D UI 요소, 뷰포트 내 카메라 제어, 3D 모델 렌더링.
  ViewportFrame for item previews, minimap rendering, 3D UI elements, camera control inside viewport, model rotation preview, inventory thumbnails.
allowed-tools:
  - Bash
  - Edit
  - Write
  - Read
  - Glob
  - Grep
effort: high
---

# ViewportFrame System (Item Previews, Minimap, 3D UI)

This skill covers ViewportFrame for rendering 3D models in UI, item preview panels, minimap systems, camera control within viewports, and interactive 3D UI elements.

---

## 1. ViewportFrame Builder

```luau
--!strict
-- ModuleScript: ViewportFrame creation with proper camera setup

local ViewportBuilder = {}

export type ViewportConfig = {
    size: UDim2?,
    position: UDim2?,
    backgroundColor: Color3?,
    backgroundTransparency: number?,
    imageTransparency: number?,
    lightColor: Color3?,
    lightDirection: Vector3?,
    ambient: Color3?,
    parent: GuiObject?,
}

--- Creates a ViewportFrame with camera and lighting.
function ViewportBuilder.create(config: ViewportConfig?): (ViewportFrame, Camera)
    local cfg = config or {}

    local viewport = Instance.new("ViewportFrame")
    viewport.Size = cfg.size or UDim2.fromOffset(200, 200)
    viewport.Position = cfg.position or UDim2.fromOffset(0, 0)
    viewport.BackgroundColor3 = cfg.backgroundColor or Color3.fromRGB(30, 30, 40)
    viewport.BackgroundTransparency = cfg.backgroundTransparency or 0
    viewport.ImageTransparency = cfg.imageTransparency or 0
    viewport.LightColor = cfg.lightColor or Color3.fromRGB(255, 255, 255)
    viewport.LightDirection = cfg.lightDirection or Vector3.new(-1, -1, -1).Unit
    viewport.Ambient = cfg.ambient or Color3.fromRGB(120, 120, 130)

    local camera = Instance.new("Camera")
    camera.FieldOfView = 50
    camera.Parent = viewport
    viewport.CurrentCamera = camera

    if cfg.parent then
        viewport.Parent = cfg.parent
    end

    return viewport, camera
end

--- Positions camera to frame a model within the viewport.
function ViewportBuilder.frameModel(camera: Camera, model: Model, distance: number?)
    local cf, size = model:GetBoundingBox()
    local maxDim = math.max(size.X, size.Y, size.Z)
    local dist = distance or (maxDim * 1.8)

    camera.CFrame = CFrame.new(
        cf.Position + Vector3.new(dist * 0.7, dist * 0.5, dist * 0.7),
        cf.Position
    )
end

return ViewportBuilder
```

---

## 2. Item Preview System

```luau
--!strict
-- ModuleScript: 3D item preview for inventories, shops, loot displays

local RunService = game:GetService("RunService")
local ViewportBuilder = require(script.Parent.ViewportBuilder)

local ItemPreview = {}

export type PreviewConfig = {
    size: UDim2?,
    position: UDim2?,
    backgroundColor: Color3?,
    autoRotate: boolean?,
    rotateSpeed: number?,
    parent: GuiObject?,
}

--- Creates an item preview viewport that displays a model clone.
function ItemPreview.create(model: Model, config: PreviewConfig?): ViewportFrame
    local cfg = config or {}

    local viewport, camera = ViewportBuilder.create({
        size = cfg.size or UDim2.fromOffset(150, 150),
        position = cfg.position,
        backgroundColor = cfg.backgroundColor or Color3.fromRGB(25, 25, 35),
        parent = cfg.parent,
    })

    -- Clone model into viewport
    local clone = model:Clone()
    clone.Parent = viewport

    -- Frame the camera on the model
    ViewportBuilder.frameModel(camera, clone)

    -- Auto-rotate
    if cfg.autoRotate ~= false then
        local speed = cfg.rotateSpeed or 30 -- degrees per second
        local angle = 0
        local cf, size = clone:GetBoundingBox()
        local center = cf.Position
        local maxDim = math.max(size.X, size.Y, size.Z)
        local dist = maxDim * 1.8

        local connection = RunService.RenderStepped:Connect(function(dt: number)
            if not viewport or not viewport.Parent then
                return
            end
            angle += speed * dt
            local rad = math.rad(angle)
            camera.CFrame = CFrame.new(
                center + Vector3.new(math.cos(rad) * dist, dist * 0.4, math.sin(rad) * dist),
                center
            )
        end)

        viewport.Destroying:Connect(function()
            connection:Disconnect()
        end)
    end

    return viewport
end

--- Swaps the displayed model in an existing preview viewport.
function ItemPreview.setModel(viewport: ViewportFrame, newModel: Model)
    -- Clear old models
    for _, child in viewport:GetChildren() do
        if child:IsA("Model") or child:IsA("BasePart") then
            child:Destroy()
        end
    end

    local clone = newModel:Clone()
    clone.Parent = viewport

    local camera = viewport.CurrentCamera
    if camera then
        ViewportBuilder.frameModel(camera, clone)
    end
end

return ItemPreview
```

---

## 3. Minimap System

```luau
--!strict
-- ModuleScript: Top-down minimap using ViewportFrame

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Minimap = {}

export type MinimapConfig = {
    size: UDim2?,
    position: UDim2?,
    height: number?,         -- Camera height above player
    radius: number?,         -- World radius to show
    backgroundColor: Color3?,
    showPlayerDot: boolean?,
    parent: GuiObject?,
}

--- Creates a minimap viewport that tracks the local player from above.
function Minimap.create(config: MinimapConfig?): ViewportFrame
    local cfg = config or {}
    local height = cfg.height or 100
    local radius = cfg.radius or 80

    local viewport = Instance.new("ViewportFrame")
    viewport.Size = cfg.size or UDim2.fromOffset(180, 180)
    viewport.Position = cfg.position or UDim2.new(1, -190, 0, 10)
    viewport.BackgroundColor3 = cfg.backgroundColor or Color3.fromRGB(20, 30, 20)
    viewport.BackgroundTransparency = 0
    viewport.Ambient = Color3.fromRGB(180, 180, 180)
    viewport.LightColor = Color3.fromRGB(255, 255, 255)
    viewport.LightDirection = Vector3.new(0, -1, 0)

    -- Circular mask
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0.5, 0)
    corner.Parent = viewport

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(100, 100, 100)
    stroke.Thickness = 3
    stroke.Parent = viewport

    -- Camera
    local camera = Instance.new("Camera")
    camera.FieldOfView = 40
    camera.Parent = viewport
    viewport.CurrentCamera = camera

    if cfg.parent then
        viewport.Parent = cfg.parent
    end

    -- Clone relevant world parts into the viewport
    -- (You must selectively clone static geometry into the viewport)

    -- Player indicator dot
    if cfg.showPlayerDot ~= false then
        local dot = Instance.new("Frame")
        dot.Name = "PlayerDot"
        dot.Size = UDim2.fromOffset(8, 8)
        dot.Position = UDim2.new(0.5, -4, 0.5, -4)
        dot.BackgroundColor3 = Color3.fromRGB(50, 200, 50)
        dot.BorderSizePixel = 0
        dot.ZIndex = 10
        dot.Parent = viewport

        local dotCorner = Instance.new("UICorner")
        dotCorner.CornerRadius = UDim.new(1, 0)
        dotCorner.Parent = dot
    end

    -- Update camera to follow player
    local connection = RunService.RenderStepped:Connect(function()
        local player = Players.LocalPlayer
        if not player or not player.Character then return end
        local rootPart = player.Character:FindFirstChild("HumanoidRootPart")
        if not rootPart or not rootPart:IsA("BasePart") then return end

        local pos = rootPart.Position
        camera.CFrame = CFrame.new(
            Vector3.new(pos.X, pos.Y + height, pos.Z),
            pos
        )
    end)

    viewport.Destroying:Connect(function()
        connection:Disconnect()
    end)

    return viewport
end

--- Clones world geometry into the minimap viewport for display.
function Minimap.loadWorldGeometry(viewport: ViewportFrame, folder: Folder)
    for _, obj in folder:GetChildren() do
        if obj:IsA("BasePart") or obj:IsA("Model") then
            local clone = obj:Clone()
            clone.Parent = viewport
        end
    end
end

return Minimap
```

---

## 4. 3D UI Element (Rotating Display)

```luau
--!strict
-- ModuleScript: Interactive 3D model display with drag-to-rotate

local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ViewportBuilder = require(script.Parent.ViewportBuilder)

local RotatingDisplay = {}

--- Creates a viewport with mouse drag-to-rotate functionality.
function RotatingDisplay.create(model: Model, config: {
    size: UDim2?,
    position: UDim2?,
    parent: GuiObject?,
    sensitivity: number?,
}?): ViewportFrame
    local cfg = config or {}

    local viewport, camera = ViewportBuilder.create({
        size = cfg.size or UDim2.fromOffset(250, 250),
        position = cfg.position,
        parent = cfg.parent,
    })

    local clone = model:Clone()
    clone.Parent = viewport

    local cf, size = clone:GetBoundingBox()
    local center = cf.Position
    local maxDim = math.max(size.X, size.Y, size.Z)
    local dist = maxDim * 2

    local angleX = 30
    local angleY = 45
    local dragging = false
    local lastMousePos = Vector2.zero
    local sensitivity = cfg.sensitivity or 0.5

    -- Input handling
    viewport.InputBegan:Connect(function(input: InputObject)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            lastMousePos = Vector2.new(input.Position.X, input.Position.Y)
        end
    end)

    viewport.InputEnded:Connect(function(input: InputObject)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)

    viewport.InputChanged:Connect(function(input: InputObject)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch) then
            local currentPos = Vector2.new(input.Position.X, input.Position.Y)
            local delta = currentPos - lastMousePos
            angleY += delta.X * sensitivity
            angleX = math.clamp(angleX - delta.Y * sensitivity, -80, 80)
            lastMousePos = currentPos
        end
    end)

    -- Render loop
    local connection = RunService.RenderStepped:Connect(function()
        if not viewport or not viewport.Parent then return end
        local radX = math.rad(angleX)
        local radY = math.rad(angleY)
        camera.CFrame = CFrame.new(
            center + Vector3.new(
                math.cos(radY) * math.cos(radX) * dist,
                math.sin(radX) * dist,
                math.sin(radY) * math.cos(radX) * dist
            ),
            center
        )
    end)

    viewport.Destroying:Connect(function()
        connection:Disconnect()
    end)

    return viewport
end

return RotatingDisplay
```

---

## 5. Inventory Thumbnail Generator

```luau
--!strict
-- ModuleScript: Generate static thumbnails for inventory items

local ViewportBuilder = require(script.Parent.ViewportBuilder)

local ThumbnailGen = {}

--- Creates a small viewport thumbnail for an item model.
function ThumbnailGen.createThumbnail(model: Model, parent: GuiObject, size: number?): ViewportFrame
    local thumbSize = size or 64

    local viewport, camera = ViewportBuilder.create({
        size = UDim2.fromOffset(thumbSize, thumbSize),
        backgroundColor = Color3.fromRGB(40, 40, 50),
        backgroundTransparency = 0,
        parent = parent,
    })

    local clone = model:Clone()
    clone.Parent = viewport
    ViewportBuilder.frameModel(camera, clone, nil)

    -- Add subtle rounded corners
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = viewport

    return viewport
end

--- Creates a grid of item thumbnails for an inventory display.
function ThumbnailGen.createGrid(items: { Model }, parent: GuiObject, columns: number?, thumbSize: number?): Frame
    local cols = columns or 4
    local tSize = thumbSize or 64
    local gap = 6

    local grid = Instance.new("Frame")
    grid.Size = UDim2.fromScale(1, 1)
    grid.BackgroundTransparency = 1
    grid.Parent = parent

    local gridLayout = Instance.new("UIGridLayout")
    gridLayout.CellSize = UDim2.fromOffset(tSize, tSize)
    gridLayout.CellPadding = UDim2.fromOffset(gap, gap)
    gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
    gridLayout.FillDirectionMaxCells = cols
    gridLayout.Parent = grid

    for i, model in items do
        local thumb = ThumbnailGen.createThumbnail(model, grid, tSize)
        thumb.LayoutOrder = i
    end

    return grid
end

return ThumbnailGen
```

---

## Key Considerations

1. **Performance**: ViewportFrame renders a separate scene; limit the number of active viewports (< 5 simultaneously)
2. **Cloning**: Always clone models into the viewport; never parent workspace objects directly
3. **Camera**: Each ViewportFrame needs its own Camera set as CurrentCamera
4. **Lighting**: Use `Ambient`, `LightColor`, and `LightDirection` on ViewportFrame (world lighting does not affect it)
5. **ImageTransparency**: Allows the viewport background to show through for layered effects
6. **RenderStepped**: Use for camera updates; prefer frame-skipping for many viewports

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

- `model` (Model) - The 3D model to display in the viewport
- `size` (UDim2) - Size of the ViewportFrame
- `position` (UDim2) - Position of the ViewportFrame
- `background_color` (Color3) - Background color of the viewport
- `auto_rotate` (boolean) - Whether the model auto-rotates (default: true)
- `rotate_speed` (number) - Degrees per second for auto-rotation (default: 30)
- `camera_distance` (number) - Distance from camera to model center
- `camera_fov` (number) - Camera field of view (default: 50)
- `light_color` (Color3) - Light color for the viewport scene
- `light_direction` (Vector3) - Direction of the light source
- `ambient_color` (Color3) - Ambient light color
- `minimap_height` (number) - Camera height for minimap mode
- `minimap_radius` (number) - World radius visible in minimap
- `drag_sensitivity` (number) - Mouse drag rotation sensitivity
