--!strict
--[[
    RobloxEngine Bootstrap Script

    Run this via MCP run_code at the start of each session.
    It injects all engine modules into ServerStorage._RobloxEngine
    and makes them available via require().

    Usage (via MCP run_code):
        -- Paste this entire file content into run_code
        -- Or if already bootstrapped, just run:
        --   local engine = require(game.ServerStorage._RobloxEngine)
]]

local ServerStorage = game:GetService("ServerStorage")
local HttpService = game:GetService("HttpService")

-- Check if already bootstrapped
local existing = ServerStorage:FindFirstChild("_RobloxEngine")
if existing and existing:FindFirstChild("_Bootstrapped") then
    print("[RobloxEngine] Already bootstrapped. Running context scan...")

    -- Run quick context scan
    local partCount = 0
    local modelCount = 0
    local function quickScan(parent)
        for _, child in parent:GetChildren() do
            if child.Name:sub(1, 13) ~= "_RobloxEngine" then
                if child:IsA("BasePart") then
                    partCount += 1
                elseif child:IsA("Model") then
                    modelCount += 1
                end
                quickScan(child)
            end
        end
    end
    quickScan(workspace)

    print(string.format("[RobloxEngine] Workspace: %d parts, %d models", partCount, modelCount))

    -- Print anchors
    local anchorsFolder = workspace:FindFirstChild("_RobloxEngine_Anchors")
    if anchorsFolder then
        local anchors = {}
        for _, a in anchorsFolder:GetChildren() do
            if a:IsA("BasePart") and a.Name:sub(1, 8) == "_Anchor_" then
                table.insert(anchors, string.format("  %s: (%.1f, %.1f, %.1f)",
                    a.Name:sub(9), a.Position.X, a.Position.Y, a.Position.Z))
            end
        end
        if #anchors > 0 then
            print("[RobloxEngine] Anchors:\n" .. table.concat(anchors, "\n"))
        end
    end

    return
end

print("[RobloxEngine] Bootstrapping engine modules...")

-- Create engine folder
local engineFolder = Instance.new("Folder")
engineFolder.Name = "_RobloxEngine"

-- Create module loader (main entry point)
local mainModule = Instance.new("ModuleScript")
mainModule.Name = "_RobloxEngine"
mainModule.Source = [[
local Engine = {}

-- Module references (populated after injection)
Engine.Coord = nil      -- CoordinateManager
Engine.Grid = nil       -- GridSnap
Engine.VFX = nil        -- VFXLibrary
Engine.Presets = nil    -- VFXPresets
Engine.Context = nil    -- ContextTracker

-- Initialize by finding injected modules
local folder = game:GetService("ServerStorage"):FindFirstChild("_RobloxEngine")
if folder then
    local coordMod = folder:FindFirstChild("CoordinateManager")
    if coordMod then Engine.Coord = require(coordMod) end

    local gridMod = folder:FindFirstChild("GridSnap")
    if gridMod then Engine.Grid = require(gridMod) end

    local vfxMod = folder:FindFirstChild("VFXLibrary")
    if vfxMod then Engine.VFX = require(vfxMod) end

    local presetsMod = folder:FindFirstChild("VFXPresets")
    if presetsMod then Engine.Presets = require(presetsMod) end

    local contextMod = folder:FindFirstChild("ContextTracker")
    if contextMod then Engine.Context = require(contextMod) end
end

return Engine
]]
mainModule.Parent = engineFolder

--------------------------------------------------------------------------------
-- INJECT MODULE: CoordinateManager
--------------------------------------------------------------------------------

local coordModule = Instance.new("ModuleScript")
coordModule.Name = "CoordinateManager"
coordModule.Source = [==[
local CoordinateManager = {}
local EPSILON = 0.001

function CoordinateManager.getWorldBounds(instance)
    if instance:IsA("BasePart") then
        local cf = instance.CFrame
        local size = instance.Size
        local halfSize = size / 2
        local corners = {}
        for _, sx in {-1, 1} do
            for _, sy in {-1, 1} do
                for _, sz in {-1, 1} do
                    local corner = cf * CFrame.new(halfSize.X * sx, halfSize.Y * sy, halfSize.Z * sz)
                    table.insert(corners, corner.Position)
                end
            end
        end
        local minV, maxV = corners[1], corners[1]
        for _, c in corners do
            minV = Vector3.new(math.min(minV.X, c.X), math.min(minV.Y, c.Y), math.min(minV.Z, c.Z))
            maxV = Vector3.new(math.max(maxV.X, c.X), math.max(maxV.Y, c.Y), math.max(maxV.Z, c.Z))
        end
        return minV, maxV
    elseif instance:IsA("Model") then
        local cf, size = instance:GetBoundingBox()
        local halfSize = size / 2
        return cf.Position - halfSize, cf.Position + halfSize
    end
    return Vector3.zero, Vector3.zero
end

function CoordinateManager.placeRelativeTo(anchor, offset, newPart)
    newPart.CFrame = anchor.CFrame * CFrame.new(offset.X, offset.Y, offset.Z)
    newPart.Anchored = true
end

function CoordinateManager.placeAdjacent(existing, newPart, face, gap)
    gap = gap or 0
    local dirMap = {
        Right = Vector3.new(1,0,0), Left = Vector3.new(-1,0,0),
        Top = Vector3.new(0,1,0), Bottom = Vector3.new(0,-1,0),
        Front = Vector3.new(0,0,-1), Back = Vector3.new(0,0,1),
    }
    local dir = dirMap[face]
    if not dir then error("Invalid face: " .. face) end
    local localOffset = (existing.Size/2 + newPart.Size/2 + Vector3.new(gap,gap,gap)) * dir
    newPart.CFrame = existing.CFrame * CFrame.new(localOffset.X, localOffset.Y, localOffset.Z)
    newPart.Anchored = true
end

function CoordinateManager.snapToGrid(position, gridSize)
    return Vector3.new(
        math.round(position.X / gridSize) * gridSize,
        math.round(position.Y / gridSize) * gridSize,
        math.round(position.Z / gridSize) * gridSize
    )
end

function CoordinateManager.centerOn(part, target)
    part.CFrame = CFrame.new(target.CFrame.Position) * (part.CFrame - part.CFrame.Position)
    part.Anchored = true
end

function CoordinateManager.distribute(parts, axis, spacing, startPosition)
    if #parts == 0 then return end
    local start = startPosition or parts[1].Position
    for i, part in parts do
        local offset = Vector3.zero
        local dist = (i - 1) * spacing
        if axis == "X" then offset = Vector3.new(dist, 0, 0)
        elseif axis == "Y" then offset = Vector3.new(0, dist, 0)
        elseif axis == "Z" then offset = Vector3.new(0, 0, dist)
        end
        part.Position = start + offset
        part.Anchored = true
    end
end

function CoordinateManager.getBoundingBox(instances)
    local gMin = Vector3.new(math.huge, math.huge, math.huge)
    local gMax = Vector3.new(-math.huge, -math.huge, -math.huge)
    for _, inst in instances do
        local minV, maxV = CoordinateManager.getWorldBounds(inst)
        gMin = Vector3.new(math.min(gMin.X, minV.X), math.min(gMin.Y, minV.Y), math.min(gMin.Z, minV.Z))
        gMax = Vector3.new(math.max(gMax.X, maxV.X), math.max(gMax.Y, maxV.Y), math.max(gMax.Z, maxV.Z))
    end
    return (gMin + gMax) / 2, gMax - gMin, gMin
end

function CoordinateManager.validatePlacement(part, expectedCFrame)
    local err = (part.Position - expectedCFrame.Position).Magnitude
    return err < EPSILON, err
end

function CoordinateManager.createAnchor(name, position)
    local folder = workspace:FindFirstChild("_RobloxEngine_Anchors")
    if not folder then
        folder = Instance.new("Folder")
        folder.Name = "_RobloxEngine_Anchors"
        folder.Parent = workspace
    end
    local existing = folder:FindFirstChild("_Anchor_" .. name)
    if existing then existing:Destroy() end
    local anchor = Instance.new("Part")
    anchor.Name = "_Anchor_" .. name
    anchor.Size = Vector3.new(0.1, 0.1, 0.1)
    anchor.Transparency = 1
    anchor.CanCollide = false
    anchor.CanTouch = false
    anchor.CanQuery = false
    anchor.Anchored = true
    anchor.Position = position
    anchor.Parent = folder
    return anchor
end

function CoordinateManager.getAnchor(name)
    local folder = workspace:FindFirstChild("_RobloxEngine_Anchors")
    if not folder then return nil end
    return folder:FindFirstChild("_Anchor_" .. name)
end

function CoordinateManager.buildRoom(config)
    local t = config.wallThickness or 1
    local mat = config.material or Enum.Material.SmoothPlastic
    local col = config.color or Color3.fromRGB(200, 200, 200)
    local parent = config.parent or workspace
    local c, w, h, d = config.center, config.width, config.height, config.depth
    local parts = {}
    local function make(name, size, pos)
        local p = Instance.new("Part")
        p.Name = name; p.Size = size; p.Position = pos
        p.Anchored = true; p.Material = mat; p.Color = col
        p.Parent = parent; parts[name] = p
        return p
    end
    make("Floor", Vector3.new(w, t, d), c - Vector3.new(0, h/2 - t/2, 0))
    make("Ceiling", Vector3.new(w, t, d), c + Vector3.new(0, h/2 - t/2, 0))
    local innerH = h - t * 2
    make("WallLeft", Vector3.new(t, innerH, d), c - Vector3.new(w/2 - t/2, 0, 0))
    make("WallRight", Vector3.new(t, innerH, d), c + Vector3.new(w/2 - t/2, 0, 0))
    local innerW = w - t * 2
    make("WallFront", Vector3.new(innerW, innerH, t), c - Vector3.new(0, 0, d/2 - t/2))
    make("WallBack", Vector3.new(innerW, innerH, t), c + Vector3.new(0, 0, d/2 - t/2))
    return parts
end

function CoordinateManager.circularPositions(center, radius, count, startAngle)
    startAngle = startAngle or 0
    local positions = {}
    local step = (2 * math.pi) / count
    for i = 0, count - 1 do
        local angle = startAngle + i * step
        local x = center.X + math.cos(angle) * radius
        local z = center.Z + math.sin(angle) * radius
        local pos = Vector3.new(x, center.Y, z)
        table.insert(positions, CFrame.lookAt(pos, center))
    end
    return positions
end

function CoordinateManager.createGrid(config)
    local spacing = config.spacing or 0
    local parts = {}
    for row = 0, config.rows - 1 do
        for col = 0, config.cols - 1 do
            local part = Instance.new("Part")
            part.Size = config.partSize
            part.Anchored = true
            part.Material = config.material or Enum.Material.SmoothPlastic
            part.Color = config.color or Color3.fromRGB(200, 200, 200)
            part.Position = Vector3.new(
                config.origin.X + col * (config.partSize.X + spacing),
                config.origin.Y,
                config.origin.Z + row * (config.partSize.Z + spacing)
            )
            part.Name = string.format("Grid_%d_%d", row+1, col+1)
            part.Parent = config.parent or workspace
            table.insert(parts, part)
        end
    end
    return parts
end

return CoordinateManager
]==]
coordModule.Parent = engineFolder

--------------------------------------------------------------------------------
-- INJECT MODULE: GridSnap
--------------------------------------------------------------------------------

local gridModule = Instance.new("ModuleScript")
gridModule.Name = "GridSnap"
gridModule.Source = [==[
local GridSnap = {}
GridSnap.DefaultGridSize = 1
GridSnap.DefaultAngleStep = 90

function GridSnap.snap(position, gridSize)
    local g = gridSize or GridSnap.DefaultGridSize
    return Vector3.new(
        math.round(position.X / g) * g,
        math.round(position.Y / g) * g,
        math.round(position.Z / g) * g
    )
end

function GridSnap.snapAxes(position, axes, gridSize)
    local g = gridSize or GridSnap.DefaultGridSize
    local x = if string.find(axes, "X") then math.round(position.X / g) * g else position.X
    local y = if string.find(axes, "Y") then math.round(position.Y / g) * g else position.Y
    local z = if string.find(axes, "Z") then math.round(position.Z / g) * g else position.Z
    return Vector3.new(x, y, z)
end

function GridSnap.snapCFrame(cframe, gridSize, angleStep)
    local g = gridSize or GridSnap.DefaultGridSize
    local a = math.rad(angleStep or GridSnap.DefaultAngleStep)
    local pos = GridSnap.snap(cframe.Position, g)
    local rx, ry, rz = cframe:ToEulerAnglesYXZ()
    rx = math.round(rx / a) * a
    ry = math.round(ry / a) * a
    rz = math.round(rz / a) * a
    return CFrame.new(pos) * CFrame.fromEulerAnglesYXZ(rx, ry, rz)
end

function GridSnap.snapToFloor(part, floorY, gridSize)
    local g = gridSize or GridSnap.DefaultGridSize
    local floor = floorY or 0
    return Vector3.new(
        math.round(part.Position.X / g) * g,
        floor + part.Size.Y / 2,
        math.round(part.Position.Z / g) * g
    )
end

function GridSnap.snapOnTop(basePart, newPart, gridSize)
    local g = gridSize or GridSnap.DefaultGridSize
    local baseTop = basePart.Position.Y + basePart.Size.Y / 2
    return CFrame.new(
        math.round(basePart.Position.X / g) * g,
        baseTop + newPart.Size.Y / 2,
        math.round(basePart.Position.Z / g) * g
    )
end

return GridSnap
]==]
gridModule.Parent = engineFolder

--------------------------------------------------------------------------------
-- INJECT MODULE: ContextTracker (compact version)
--------------------------------------------------------------------------------

local contextModule = Instance.new("ModuleScript")
contextModule.Name = "ContextTracker"
contextModule.Source = [==[
local ContextTracker = {}
local HttpService = game:GetService("HttpService")
local ServerStorage = game:GetService("ServerStorage")

function ContextTracker.scanWorkspace(parent, maxDepth)
    parent = parent or workspace
    maxDepth = maxDepth or 10
    local lines = {}
    local function scan(inst, depth, indent)
        if depth > maxDepth then return end
        if inst.Name:sub(1, 13) == "_RobloxEngine" then return end
        local info = indent .. inst.Name .. " [" .. inst.ClassName .. "]"
        if inst:IsA("BasePart") then
            info = info .. string.format(" Pos:(%.1f,%.1f,%.1f) Size:(%.1f,%.1f,%.1f)",
                inst.Position.X, inst.Position.Y, inst.Position.Z,
                inst.Size.X, inst.Size.Y, inst.Size.Z)
        elseif inst:IsA("Model") then
            local cf, size = inst:GetBoundingBox()
            info = info .. string.format(" BBox:(%.1f,%.1f,%.1f)", size.X, size.Y, size.Z)
        end
        table.insert(lines, info)
        for _, child in inst:GetChildren() do
            scan(child, depth + 1, indent .. "  ")
        end
    end
    for _, child in parent:GetChildren() do
        if child.Name ~= "Camera" and child.Name ~= "Terrain" then
            scan(child, 1, "")
        end
    end
    return table.concat(lines, "\n")
end

function ContextTracker.findNearby(position, radius, parent)
    parent = parent or workspace
    local results = {}
    local function scan(inst)
        if inst:IsA("BasePart") then
            if (inst.Position - position).Magnitude <= radius then
                table.insert(results, inst)
            end
        end
        for _, child in inst:GetChildren() do scan(child) end
    end
    scan(parent)
    table.sort(results, function(a, b)
        return (a.Position - position).Magnitude < (b.Position - position).Magnitude
    end)
    return results
end

function ContextTracker.getNamedAnchors()
    local folder = workspace:FindFirstChild("_RobloxEngine_Anchors")
    if not folder then return {} end
    local anchors = {}
    for _, child in folder:GetChildren() do
        if child:IsA("BasePart") and child.Name:sub(1, 8) == "_Anchor_" then
            anchors[child.Name:sub(9)] = child.Position
        end
    end
    return anchors
end

function ContextTracker.setAnchor(name, position)
    local folder = workspace:FindFirstChild("_RobloxEngine_Anchors")
    if not folder then
        folder = Instance.new("Folder")
        folder.Name = "_RobloxEngine_Anchors"
        folder.Parent = workspace
    end
    local existing = folder:FindFirstChild("_Anchor_" .. name)
    if existing then existing:Destroy() end
    local a = Instance.new("Part")
    a.Name = "_Anchor_" .. name
    a.Size = Vector3.new(0.1,0.1,0.1)
    a.Transparency = 1; a.CanCollide = false
    a.Anchored = true; a.Position = position
    a.Parent = folder
    return a
end

function ContextTracker.saveContext(key, value)
    local folder = ServerStorage:FindFirstChild("_RobloxEngine")
    if not folder then return end
    local obj = folder:FindFirstChild("_Context")
    if not obj then
        obj = Instance.new("StringValue")
        obj.Name = "_Context"; obj.Parent = folder
    end
    local data = {}
    if obj.Value ~= "" then
        pcall(function() data = HttpService:JSONDecode(obj.Value) end)
    end
    data[key] = value
    obj.Value = HttpService:JSONEncode(data)
end

function ContextTracker.loadContext(key)
    local folder = ServerStorage:FindFirstChild("_RobloxEngine")
    if not folder then return nil end
    local obj = folder:FindFirstChild("_Context")
    if not obj or obj.Value == "" then return nil end
    local ok, data = pcall(function() return HttpService:JSONDecode(obj.Value) end)
    if ok and type(data) == "table" then return data[key] end
    return nil
end

function ContextTracker.getState()
    local lines = {"=== WORKSPACE ===", ContextTracker.scanWorkspace(), "", "=== ANCHORS ==="}
    local anchors = ContextTracker.getNamedAnchors()
    local count = 0
    for name, pos in anchors do
        table.insert(lines, string.format("  %s: (%.1f,%.1f,%.1f)", name, pos.X, pos.Y, pos.Z))
        count += 1
    end
    if count == 0 then table.insert(lines, "  (none)") end
    return table.concat(lines, "\n")
end

return ContextTracker
]==]
contextModule.Parent = engineFolder

--------------------------------------------------------------------------------
-- Mark as bootstrapped
--------------------------------------------------------------------------------

local marker = Instance.new("BoolValue")
marker.Name = "_Bootstrapped"
marker.Value = true
marker.Parent = engineFolder

-- Parent to ServerStorage (triggers all instances to replicate)
engineFolder.Parent = ServerStorage

-- Create anchors folder in workspace
local anchorsFolder = workspace:FindFirstChild("_RobloxEngine_Anchors")
if not anchorsFolder then
    anchorsFolder = Instance.new("Folder")
    anchorsFolder.Name = "_RobloxEngine_Anchors"
    anchorsFolder.Parent = workspace
end

-- Initial context scan
local partCount = 0
local modelCount = 0
local scriptCount = 0
local function countScan(parent)
    for _, child in parent:GetChildren() do
        if child.Name:sub(1, 13) ~= "_RobloxEngine" then
            if child:IsA("BasePart") then partCount += 1
            elseif child:IsA("Model") then modelCount += 1
            elseif child:IsA("BaseScript") then scriptCount += 1
            end
            countScan(child)
        end
    end
end
countScan(workspace)

print("[RobloxEngine] Bootstrap complete!")
print(string.format("[RobloxEngine] Modules: CoordinateManager, GridSnap, ContextTracker"))
print(string.format("[RobloxEngine] VFX modules available via inline injection"))
print(string.format("[RobloxEngine] Workspace: %d parts, %d models, %d scripts", partCount, modelCount, scriptCount))
print("[RobloxEngine] Usage: local Engine = require(game.ServerStorage._RobloxEngine)")
print("[RobloxEngine]   Engine.Coord.placeAdjacent(partA, partB, 'Right')")
print("[RobloxEngine]   Engine.Grid.snap(position, 2)")
print("[RobloxEngine]   Engine.Context.scanWorkspace()")
