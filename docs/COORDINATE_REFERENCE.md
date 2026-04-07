# Roblox Coordinate & CFrame Reference

Quick reference for Claude when working with Roblox positioning.

## Coordinate System

Roblox uses a **left-handed** coordinate system:
- **X**: Right (+) / Left (-)
- **Y**: Up (+) / Down (-)
- **Z**: Back (+) / Front (-)

## CFrame Basics

CFrame = Position (Vector3) + Rotation (3x3 matrix)

```lua
-- Create at position
CFrame.new(x, y, z)

-- Create looking at target
CFrame.lookAt(position, target)

-- Create with rotation (radians)
CFrame.Angles(rx, ry, rz)
CFrame.fromEulerAnglesYXZ(rx, ry, rz) -- preferred for Y-up rotation

-- Identity (origin, no rotation)
CFrame.identity
```

## CFrame Operations

```lua
-- Relative positioning (MOST IMPORTANT)
-- Move 5 studs right in PART'S local space:
part.CFrame = anchor.CFrame * CFrame.new(5, 0, 0)

-- Move 5 studs right in WORLD space:
part.CFrame = anchor.CFrame + Vector3.new(5, 0, 0)

-- Rotate 90 degrees on Y axis:
part.CFrame = part.CFrame * CFrame.Angles(0, math.rad(90), 0)

-- Get relative CFrame between two parts:
local relativeCF = partA.CFrame:ToObjectSpace(partB.CFrame)

-- Convert local point to world:
local worldPos = part.CFrame:PointToWorldSpace(Vector3.new(1, 0, 0))
```

## Adjacent Placement Formula

```
newPosition = existingPos + (existingSize/2 + newSize/2) * directionVector
```

Direction vectors:
| Face   | Direction Vector    |
|--------|-------------------|
| Right  | (1, 0, 0)        |
| Left   | (-1, 0, 0)       |
| Top    | (0, 1, 0)        |
| Bottom | (0, -1, 0)       |
| Front  | (0, 0, -1)       |
| Back   | (0, 0, 1)        |

## Grid Snapping

```lua
local function snap(value, gridSize)
    return math.round(value / gridSize) * gridSize
end

-- Snap Vector3:
local snapped = Vector3.new(
    snap(pos.X, GRID),
    snap(pos.Y, GRID),
    snap(pos.Z, GRID)
)
```

## Common Size Relationships

| Object Type    | Typical Size (studs)     |
|---------------|-------------------------|
| Character     | ~2 x 5 x 1             |
| Door          | 4 x 7 x 1              |
| Window        | 4 x 4 x 0.5            |
| Wall segment  | varies x height x 1    |
| Table         | 4 x 3 x 6              |
| Chair         | 2 x 4 x 2              |
| Stud (1 unit) | 1 x 1 x 1              |

## Room Construction Template

For a room at center `c` with dimensions `w` x `h` x `d` and wall thickness `t`:

```
Floor:     Size(w, t, d)      Pos = c - (0, h/2 - t/2, 0)
Ceiling:   Size(w, t, d)      Pos = c + (0, h/2 - t/2, 0)
WallLeft:  Size(t, h-2t, d)   Pos = c - (w/2 - t/2, 0, 0)
WallRight: Size(t, h-2t, d)   Pos = c + (w/2 - t/2, 0, 0)
WallFront: Size(w-2t, h-2t, t) Pos = c - (0, 0, d/2 - t/2)
WallBack:  Size(w-2t, h-2t, t) Pos = c + (0, 0, d/2 - t/2)
```

This ensures walls fit between floor/ceiling with no gaps or overlaps.

## Surface Normal to Face Mapping

```lua
local faceNormals = {
    [Enum.NormalId.Right]  = Vector3.new(1, 0, 0),
    [Enum.NormalId.Left]   = Vector3.new(-1, 0, 0),
    [Enum.NormalId.Top]    = Vector3.new(0, 1, 0),
    [Enum.NormalId.Bottom] = Vector3.new(0, -1, 0),
    [Enum.NormalId.Front]  = Vector3.new(0, 0, -1),
    [Enum.NormalId.Back]   = Vector3.new(0, 0, 1),
}
```

## Common Mistakes to Avoid

1. **World vs Local space**: `CFrame * CFrame.new()` is LOCAL offset, `CFrame + Vector3` is WORLD offset
2. **Size is total, not half**: A part with Size (4,4,4) extends 2 studs in each direction from center
3. **CFrame multiplication order**: `baseCFrame * offset` (NOT `offset * baseCFrame`)
4. **Angles are in radians**: Use `math.rad(degrees)` for degree-to-radian conversion
5. **Y=0 is ground level**: Parts with bottom at ground need Position.Y = Size.Y / 2
6. **Parts default to center origin**: Position refers to the CENTER of the part
7. **Model positioning**: Use PrimaryPart + Model:SetPrimaryPartCFrame() for moving models
