---
name: decals
description: |
  데칼 표면 배치, 텍스처 타일링, SurfaceGui 파트 적용, 이미지 배치, 빌보드 데칼 시스템.
  Decal placement on surfaces, Texture tiling and repeat, SurfaceGui-based image rendering on parts, billboard decals, dynamic image swapping.
allowed-tools:
  - Bash
  - Edit
  - Write
  - Read
  - Glob
  - Grep
  - WebFetch
  - WebSearch
effort: high
---

# Decals, Textures & Image Placement

This skill covers Decal application on part surfaces, Texture tiling/repeating, SurfaceGui-based image rendering, billboard decals, and dynamic image management in Roblox.

---

## 1. Decal Placement on Surfaces

```luau
--!strict
-- ModuleScript: Decal management system

local DecalSystem = {}

export type DecalConfig = {
    imageId: string,
    face: Enum.NormalId?,
    transparency: number?,
    color: Color3?,
    zIndex: number?,
}

--- Applies a single decal to a specific face of a part.
function DecalSystem.applyDecal(part: BasePart, config: DecalConfig): Decal
    local decal = Instance.new("Decal")
    decal.Texture = config.imageId
    decal.Face = config.face or Enum.NormalId.Front
    decal.Transparency = config.transparency or 0
    decal.Color3 = config.color or Color3.fromRGB(255, 255, 255)
    decal.ZIndex = config.zIndex or 1
    decal.Parent = part
    return decal
end

--- Applies decals to all 6 faces of a part (useful for crates, boxes).
function DecalSystem.wrapAllFaces(part: BasePart, imageId: string, transparency: number?): { Decal }
    local faces = {
        Enum.NormalId.Front,
        Enum.NormalId.Back,
        Enum.NormalId.Top,
        Enum.NormalId.Bottom,
        Enum.NormalId.Left,
        Enum.NormalId.Right,
    }

    local decals: { Decal } = {}
    for _, face in faces do
        local decal = DecalSystem.applyDecal(part, {
            imageId = imageId,
            face = face,
            transparency = transparency,
        })
        table.insert(decals, decal)
    end
    return decals
end

--- Applies different decals to different faces (e.g., labeled crate).
function DecalSystem.applyFaceMap(part: BasePart, faceMap: { [Enum.NormalId]: string }): { Decal }
    local decals: { Decal } = {}
    for face, imageId in faceMap do
        local decal = DecalSystem.applyDecal(part, {
            imageId = imageId,
            face = face,
        })
        table.insert(decals, decal)
    end
    return decals
end

--- Removes all decals from a part.
function DecalSystem.clearDecals(part: BasePart)
    for _, child in part:GetChildren() do
        if child:IsA("Decal") then
            child:Destroy()
        end
    end
end

return DecalSystem
```

---

## 2. Texture Tiling System

```luau
--!strict
-- ModuleScript: Texture tiling for repeating patterns on surfaces

local TextureTiling = {}

export type TileConfig = {
    imageId: string,
    face: Enum.NormalId?,
    studsPerTileU: number?,
    studsPerTileV: number?,
    offsetStudsU: number?,
    offsetStudsV: number?,
    transparency: number?,
    color: Color3?,
}

--- Applies a tiling Texture to a part face.
--- Unlike Decal, Texture repeats across the surface based on studs-per-tile.
function TextureTiling.applyTile(part: BasePart, config: TileConfig): Texture
    local texture = Instance.new("Texture")
    texture.Texture = config.imageId
    texture.Face = config.face or Enum.NormalId.Top
    texture.StudsPerTileU = config.studsPerTileU or 4
    texture.StudsPerTileV = config.studsPerTileV or 4
    texture.OffsetStudsU = config.offsetStudsU or 0
    texture.OffsetStudsV = config.offsetStudsV or 0
    texture.Transparency = config.transparency or 0
    texture.Color3 = config.color or Color3.fromRGB(255, 255, 255)
    texture.Parent = part
    return texture
end

--- Tiles all 6 faces with the same texture (floor/wall patterns).
function TextureTiling.tileAllFaces(part: BasePart, imageId: string, studsPerTile: number): { Texture }
    local faces = {
        Enum.NormalId.Front, Enum.NormalId.Back,
        Enum.NormalId.Top, Enum.NormalId.Bottom,
        Enum.NormalId.Left, Enum.NormalId.Right,
    }

    local textures: { Texture } = {}
    for _, face in faces do
        local tex = TextureTiling.applyTile(part, {
            imageId = imageId,
            face = face,
            studsPerTileU = studsPerTile,
            studsPerTileV = studsPerTile,
        })
        table.insert(textures, tex)
    end
    return textures
end

--- Animated scrolling texture (conveyor belt, water flow).
function TextureTiling.animateScroll(texture: Texture, speedU: number, speedV: number): RBXScriptConnection
    local RunService = game:GetService("RunService")
    return RunService.Heartbeat:Connect(function(dt: number)
        texture.OffsetStudsU += speedU * dt
        texture.OffsetStudsV += speedV * dt
    end)
end

return TextureTiling
```

---

## 3. SurfaceGui Image Placement

```luau
--!strict
-- ModuleScript: SurfaceGui-based image placement for high-quality rendering

local SurfaceImageSystem = {}

export type SurfaceImageConfig = {
    imageId: string,
    face: Enum.NormalId?,
    pixelsPerStud: number?,
    imageSize: UDim2?,
    imagePosition: UDim2?,
    imageTransparency: number?,
    backgroundColor: Color3?,
    backgroundTransparency: number?,
    alwaysOnTop: boolean?,
}

--- Places a high-quality image on a part via SurfaceGui.
--- SurfaceGui provides higher resolution than Decal for close-up viewing.
function SurfaceImageSystem.placeImage(part: BasePart, config: SurfaceImageConfig): (SurfaceGui, ImageLabel)
    local surfaceGui = Instance.new("SurfaceGui")
    surfaceGui.Face = config.face or Enum.NormalId.Front
    surfaceGui.PixelsPerStud = config.pixelsPerStud or 50
    surfaceGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
    surfaceGui.AlwaysOnTop = config.alwaysOnTop or false

    local imageLabel = Instance.new("ImageLabel")
    imageLabel.Image = config.imageId
    imageLabel.Size = config.imageSize or UDim2.fromScale(1, 1)
    imageLabel.Position = config.imagePosition or UDim2.fromScale(0, 0)
    imageLabel.ImageTransparency = config.imageTransparency or 0
    imageLabel.BackgroundColor3 = config.backgroundColor or Color3.fromRGB(0, 0, 0)
    imageLabel.BackgroundTransparency = config.backgroundTransparency or 1
    imageLabel.ScaleType = Enum.ScaleType.Stretch
    imageLabel.Parent = surfaceGui

    surfaceGui.Parent = part
    return surfaceGui, imageLabel
end

--- Creates a slideshow on a surface that cycles through images.
function SurfaceImageSystem.createSlideshow(part: BasePart, imageIds: { string }, intervalSeconds: number, face: Enum.NormalId?): () -> ()
    local surfaceGui, imageLabel = SurfaceImageSystem.placeImage(part, {
        imageId = imageIds[1],
        face = face,
    })

    local currentIndex = 1
    local running = true

    task.spawn(function()
        while running do
            task.wait(intervalSeconds)
            currentIndex = (currentIndex % #imageIds) + 1
            imageLabel.Image = imageIds[currentIndex]
        end
    end)

    -- Returns a stop function
    return function()
        running = false
    end
end

return SurfaceImageSystem
```

---

## 4. Billboard Decal System

```luau
--!strict
-- ModuleScript: Billboard-style decals that always face the camera

local BillboardDecal = {}

export type BillboardDecalConfig = {
    imageId: string,
    size: UDim2?,
    studOffset: Vector3?,
    maxDistance: number?,
    alwaysOnTop: boolean?,
    lightInfluence: number?,
    imageTransparency: number?,
}

--- Creates a BillboardGui with an image that always faces the camera.
function BillboardDecal.create(adornee: Instance, config: BillboardDecalConfig): BillboardGui
    local bbGui = Instance.new("BillboardGui")
    bbGui.Size = config.size or UDim2.fromScale(4, 4)
    bbGui.StudsOffset = config.studOffset or Vector3.new(0, 0, 0)
    bbGui.MaxDistance = config.maxDistance or 100
    bbGui.AlwaysOnTop = config.alwaysOnTop or false
    bbGui.LightInfluence = config.lightInfluence or 1
    bbGui.Adornee = adornee

    local imageLabel = Instance.new("ImageLabel")
    imageLabel.Image = config.imageId
    imageLabel.Size = UDim2.fromScale(1, 1)
    imageLabel.BackgroundTransparency = 1
    imageLabel.ImageTransparency = config.imageTransparency or 0
    imageLabel.Parent = bbGui

    bbGui.Parent = adornee
    return bbGui
end

--- Creates a floating icon above a part (quest markers, item indicators).
function BillboardDecal.createFloatingIcon(part: BasePart, imageId: string, heightOffset: number?): BillboardGui
    return BillboardDecal.create(part, {
        imageId = imageId,
        size = UDim2.fromOffset(48, 48),
        studOffset = Vector3.new(0, heightOffset or 3, 0),
        maxDistance = 50,
        alwaysOnTop = true,
    })
end

return BillboardDecal
```

---

## 5. Dynamic Image Swapping

```luau
--!strict
-- ModuleScript: Runtime image swapping for decals and textures

local TweenService = game:GetService("TweenService")

local DynamicImage = {}

--- Crossfade between two images on a part using layered decals.
function DynamicImage.crossfade(part: BasePart, newImageId: string, face: Enum.NormalId, duration: number)
    -- Find existing decal
    local oldDecal: Decal? = nil
    for _, child in part:GetChildren() do
        if child:IsA("Decal") and child.Face == face then
            oldDecal = child :: Decal
            break
        end
    end

    -- Create new decal on top
    local newDecal = Instance.new("Decal")
    newDecal.Texture = newImageId
    newDecal.Face = face
    newDecal.Transparency = 1
    newDecal.ZIndex = 2
    newDecal.Parent = part

    -- Fade in new, fade out old
    local fadeIn = TweenService:Create(newDecal, TweenInfo.new(duration), { Transparency = 0 })
    fadeIn:Play()

    if oldDecal then
        local fadeOut = TweenService:Create(oldDecal, TweenInfo.new(duration), { Transparency = 1 })
        fadeOut:Play()
        fadeOut.Completed:Connect(function()
            oldDecal:Destroy()
            newDecal.ZIndex = 1
        end)
    end
end

--- Tint a decal with color and transparency animation.
function DynamicImage.animateTint(decal: Decal, targetColor: Color3, targetTransparency: number, duration: number)
    local tween = TweenService:Create(decal, TweenInfo.new(duration), {
        Color3 = targetColor,
        Transparency = targetTransparency,
    })
    tween:Play()
    return tween
end

return DynamicImage
```

---

## Decal vs Texture vs SurfaceGui Comparison

| Feature | Decal | Texture | SurfaceGui |
|---|---|---|---|
| Repeating/Tiling | No | Yes | Manual |
| Resolution | Fixed | Fixed | High (PixelsPerStud) |
| Interactivity | No | No | Yes (buttons, etc.) |
| Performance | Best | Good | Heavier |
| Use Case | Logos, signs | Floors, walls | Screens, UI |

### Best Practices

- **Decal**: One-off images (logos, graffiti, labels)
- **Texture**: Repeating patterns (brick, tile, grass overlay)
- **SurfaceGui**: Interactive or high-res content (screens, buttons, displays)
- Keep image resolution reasonable (512x512 or 1024x1024 max for decals)
- Use `Transparency` to blend decals with the part material

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

- `image_id` (string) - rbxassetid:// image ID to apply
- `face` (string) - Surface face: "Front", "Back", "Top", "Bottom", "Left", "Right"
- `transparency` (number) - Decal/texture transparency 0-1
- `studs_per_tile` (number) - Texture tile repeat size in studs
- `scroll_speed_u` (number) - Horizontal scroll speed for animated textures
- `scroll_speed_v` (number) - Vertical scroll speed for animated textures
- `pixels_per_stud` (number) - SurfaceGui resolution (default: 50)
- `color_tint` (Color3) - Tint color for the decal
- `max_distance` (number) - Billboard visibility distance
- `always_on_top` (boolean) - Whether billboard renders on top of 3D geometry
- `slideshow_images` (table) - Array of image IDs for slideshow
- `slideshow_interval` (number) - Seconds between slideshow transitions
