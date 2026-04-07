--[[
    RobloxEngine - MCP run_code Templates

    Copy-paste these patterns into MCP run_code calls.
    Each template is self-contained and prints its results.

    For templates that use the engine modules, run EngineBootstrap first.
]]

--------------------------------------------------------------------------------
-- TEMPLATE: Read position of an object
--------------------------------------------------------------------------------
--[[
local target = workspace:FindFirstChild("PartName", true)
if target then
    print(string.format("Name: %s", target.Name))
    print(string.format("Position: (%.2f, %.2f, %.2f)", target.Position.X, target.Position.Y, target.Position.Z))
    print(string.format("Size: (%.2f, %.2f, %.2f)", target.Size.X, target.Size.Y, target.Size.Z))
    print(string.format("CFrame: %s", tostring(target.CFrame)))
    print(string.format("Material: %s", target.Material.Name))
    print(string.format("Color: (%d, %d, %d)",
        math.floor(target.Color.R * 255),
        math.floor(target.Color.G * 255),
        math.floor(target.Color.B * 255)))
else
    print("ERROR: Object not found")
end
]]

--------------------------------------------------------------------------------
-- TEMPLATE: Place part at relative offset
--------------------------------------------------------------------------------
--[[
local anchor = workspace:FindFirstChild("AnchorPartName")
if not anchor then
    print("ERROR: Anchor not found")
    return
end

local newPart = Instance.new("Part")
newPart.Name = "NewPartName"
newPart.Size = Vector3.new(4, 4, 4)
newPart.Material = Enum.Material.SmoothPlastic
newPart.Color = Color3.fromRGB(200, 200, 200)
newPart.Anchored = true

-- Place 5 studs to the right of anchor (in anchor's local space)
newPart.CFrame = anchor.CFrame * CFrame.new(5, 0, 0)
newPart.Parent = workspace

-- Validate
local dist = (newPart.Position - (anchor.CFrame * CFrame.new(5, 0, 0)).Position).Magnitude
print(string.format("Placed %s at (%.2f, %.2f, %.2f) - error: %.4f studs",
    newPart.Name, newPart.Position.X, newPart.Position.Y, newPart.Position.Z, dist))
]]

--------------------------------------------------------------------------------
-- TEMPLATE: Place adjacent to existing object
--------------------------------------------------------------------------------
--[[
local Engine = require(game.ServerStorage._RobloxEngine)

local existing = workspace:FindFirstChild("ExistingPart")
if not existing then print("ERROR: Part not found") return end

local newPart = Instance.new("Part")
newPart.Name = "AdjacentPart"
newPart.Size = Vector3.new(4, 2, 4)
newPart.Material = Enum.Material.Concrete
newPart.Parent = workspace

-- Place on the Right face with 0 gap
Engine.Coord.placeAdjacent(existing, newPart, "Right", 0)

print(string.format("Placed %s adjacent to %s on Right face", newPart.Name, existing.Name))
print(string.format("  Position: (%.2f, %.2f, %.2f)", newPart.Position.X, newPart.Position.Y, newPart.Position.Z))
]]

--------------------------------------------------------------------------------
-- TEMPLATE: Create VFX at position
--------------------------------------------------------------------------------
--[[
-- Fire effect on a part
local targetPart = workspace:FindFirstChild("FirePart")
if targetPart then
    local att = Instance.new("Attachment", targetPart)
    local emitter = Instance.new("ParticleEmitter")
    emitter.Rate = 100
    emitter.Speed = NumberRange.new(3, 8)
    emitter.Lifetime = NumberRange.new(0.5, 1.5)
    emitter.SpreadAngle = Vector2.new(15, 15)
    emitter.EmissionDirection = Enum.NormalId.Top
    emitter.LightEmission = 1
    emitter.LightInfluence = 0
    emitter.Acceleration = Vector3.new(0, 3, 0)
    emitter.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.8),
        NumberSequenceKeypoint.new(0.3, 2.5),
        NumberSequenceKeypoint.new(1, 0),
    })
    emitter.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.2),
        NumberSequenceKeypoint.new(0.8, 0.8),
        NumberSequenceKeypoint.new(1, 1),
    })
    emitter.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 230, 80)),
        ColorSequenceKeypoint.new(0.4, Color3.fromRGB(255, 140, 20)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(80, 15, 0)),
    })
    emitter.Parent = att

    local light = Instance.new("PointLight")
    light.Color = Color3.fromRGB(255, 150, 50)
    light.Brightness = 2
    light.Range = 16
    light.Parent = targetPart

    print("Fire effect created on " .. targetPart.Name)
else
    print("ERROR: Target part not found")
end
]]

--------------------------------------------------------------------------------
-- TEMPLATE: Scan workspace hierarchy
--------------------------------------------------------------------------------
--[[
local function scan(parent, indent)
    indent = indent or ""
    for _, child in parent:GetChildren() do
        if child.Name == "Camera" or child.Name == "Terrain" then continue end
        if child.Name:sub(1, 13) == "_RobloxEngine" then continue end

        local info = indent .. child.Name .. " [" .. child.ClassName .. "]"
        if child:IsA("BasePart") then
            info = info .. string.format(" Pos:(%.1f,%.1f,%.1f) Size:(%.1f,%.1f,%.1f)",
                child.Position.X, child.Position.Y, child.Position.Z,
                child.Size.X, child.Size.Y, child.Size.Z)
        elseif child:IsA("Model") then
            local cf, size = child:GetBoundingBox()
            info = info .. string.format(" BBox:(%.1f,%.1f,%.1f)", size.X, size.Y, size.Z)
        end
        print(info)
        scan(child, indent .. "  ")
    end
end
scan(workspace)
]]

--------------------------------------------------------------------------------
-- TEMPLATE: Validate all placements (check for gaps/overlaps)
--------------------------------------------------------------------------------
--[[
local function checkAlignment(parts, tolerance)
    tolerance = tolerance or 0.01
    local issues = {}

    for i = 1, #parts do
        for j = i + 1, #parts do
            local a = parts[i]
            local b = parts[j]

            -- Check if they should be adjacent (touching or very close)
            local dist = (a.Position - b.Position).Magnitude
            local combinedHalf = (a.Size + b.Size).Magnitude / 2

            if dist < combinedHalf * 1.1 then
                -- They're close enough to be adjacent - check for gaps
                for _, axis in {"X", "Y", "Z"} do
                    local aMin = a.Position[axis] - a.Size[axis] / 2
                    local aMax = a.Position[axis] + a.Size[axis] / 2
                    local bMin = b.Position[axis] - b.Size[axis] / 2
                    local bMax = b.Position[axis] + b.Size[axis] / 2

                    local gap = math.min(math.abs(aMax - bMin), math.abs(bMax - aMin))
                    if gap > tolerance and gap < a.Size[axis] and gap < b.Size[axis] then
                        table.insert(issues, string.format(
                            "Gap on %s axis between %s and %s: %.3f studs",
                            axis, a.Name, b.Name, gap
                        ))
                    end
                end
            end
        end
    end

    if #issues == 0 then
        print("All placements aligned correctly!")
    else
        print("Alignment issues found:")
        for _, issue in issues do
            print("  " .. issue)
        end
    end
end

-- Usage: collect all parts and check
local allParts = {}
for _, child in workspace:GetDescendants() do
    if child:IsA("BasePart") and child.Name:sub(1, 7) ~= "_Anchor" then
        table.insert(allParts, child)
    end
end
checkAlignment(allParts)
]]

--------------------------------------------------------------------------------
-- TEMPLATE: Build a room using engine
--------------------------------------------------------------------------------
--[[
local Engine = require(game.ServerStorage._RobloxEngine)

local room = Engine.Coord.buildRoom({
    center = Vector3.new(0, 10, 0),
    width = 20,
    height = 10,
    depth = 20,
    wallThickness = 1,
    material = Enum.Material.Concrete,
    color = Color3.fromRGB(180, 180, 180),
})

-- Set anchors at room corners for future reference
Engine.Coord.createAnchor("RoomCenter", Vector3.new(0, 10, 0))
Engine.Coord.createAnchor("RoomFloor", Vector3.new(0, 5.5, 0))

print("Room created with " .. 6 .. " parts")
for name, part in room do
    print(string.format("  %s: Pos(%.1f,%.1f,%.1f) Size(%.1f,%.1f,%.1f)",
        name, part.Position.X, part.Position.Y, part.Position.Z,
        part.Size.X, part.Size.Y, part.Size.Z))
end
]]

--------------------------------------------------------------------------------
-- TEMPLATE: Create grid of objects
--------------------------------------------------------------------------------
--[[
local Engine = require(game.ServerStorage._RobloxEngine)

local parts = Engine.Coord.createGrid({
    rows = 5,
    cols = 5,
    partSize = Vector3.new(4, 1, 4),
    origin = Vector3.new(-8, 0.5, -8),
    spacing = 0.2,
    material = Enum.Material.SmoothPlastic,
    color = Color3.fromRGB(100, 150, 200),
})

print(string.format("Created %d grid parts", #parts))
]]

--------------------------------------------------------------------------------
-- TEMPLATE: Setup dramatic lighting
--------------------------------------------------------------------------------
--[[
local Lighting = game:GetService("Lighting")

Lighting.Technology = Enum.Technology.Future
Lighting.Ambient = Color3.fromRGB(30, 30, 40)
Lighting.Brightness = 2
Lighting.ClockTime = 16

local bloom = Instance.new("BloomEffect")
bloom.Intensity = 0.5
bloom.Size = 24
bloom.Threshold = 0.8
bloom.Parent = Lighting

local cc = Instance.new("ColorCorrectionEffect")
cc.Brightness = 0.05
cc.Contrast = 0.15
cc.Saturation = 0.2
cc.TintColor = Color3.fromRGB(255, 245, 230)
cc.Parent = Lighting

local rays = Instance.new("SunRaysEffect")
rays.Intensity = 0.2
rays.Spread = 0.5
rays.Parent = Lighting

local atmo = Instance.new("Atmosphere")
atmo.Density = 0.3
atmo.Offset = 0.25
atmo.Color = Color3.fromRGB(199, 199, 210)
atmo.Decay = Color3.fromRGB(92, 100, 120)
atmo.Glare = 0.5
atmo.Haze = 1.5
atmo.Parent = Lighting

print("Dramatic lighting setup complete")
]]
