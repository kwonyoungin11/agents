--!strict
-- CoordinateManager: CFrame/Vector3 alignment utilities for precise object placement
-- Injected via EngineBootstrap into ServerStorage._RobloxEngine

local CoordinateManager = {}

-- Tolerance for floating point comparison
local EPSILON = 0.001

--- Get world-space axis-aligned bounding box of any Instance (including Models)
function CoordinateManager.getWorldBounds(instance: Instance): (Vector3, Vector3)
	if instance:IsA("BasePart") then
		local cf = instance.CFrame
		local size = instance.Size
		local halfSize = size / 2

		-- Get all 8 corners and find min/max
		local corners = {}
		for _, sx in {-1, 1} do
			for _, sy in {-1, 1} do
				for _, sz in {-1, 1} do
					local corner = cf * CFrame.new(halfSize.X * sx, halfSize.Y * sy, halfSize.Z * sz)
					table.insert(corners, corner.Position)
				end
			end
		end

		local minV = corners[1]
		local maxV = corners[1]
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

--- Place a part relative to an existing anchor instance using local-space offset
function CoordinateManager.placeRelativeTo(anchor: BasePart, offset: Vector3, newPart: BasePart)
	newPart.CFrame = anchor.CFrame * CFrame.new(offset.X, offset.Y, offset.Z)
	newPart.Anchored = true
end

--- Place a part adjacent to another part on a specific face
--- face: "Right", "Left", "Top", "Bottom", "Front", "Back"
function CoordinateManager.placeAdjacent(existing: BasePart, newPart: BasePart, face: string, gap: number?)
	gap = gap or 0

	local directionMap = {
		Right  = Vector3.new(1, 0, 0),
		Left   = Vector3.new(-1, 0, 0),
		Top    = Vector3.new(0, 1, 0),
		Bottom = Vector3.new(0, -1, 0),
		Front  = Vector3.new(0, 0, -1),
		Back   = Vector3.new(0, 0, 1),
	}

	local dir = directionMap[face]
	if not dir then
		error("Invalid face: " .. face .. ". Use: Right, Left, Top, Bottom, Front, Back")
	end

	-- Calculate the offset in local space of the existing part
	local existingHalf = existing.Size / 2
	local newHalf = newPart.Size / 2

	local localOffset = (existingHalf + newHalf + Vector3.new(gap, gap, gap)) * dir
	newPart.CFrame = existing.CFrame * CFrame.new(localOffset.X, localOffset.Y, localOffset.Z)
	newPart.Anchored = true
end

--- Align a part flush against a face of another part (surface mount)
function CoordinateManager.alignToSurface(part: BasePart, target: BasePart, face: string)
	local normalMap = {
		Right  = Vector3.new(1, 0, 0),
		Left   = Vector3.new(-1, 0, 0),
		Top    = Vector3.new(0, 1, 0),
		Bottom = Vector3.new(0, -1, 0),
		Front  = Vector3.new(0, 0, -1),
		Back   = Vector3.new(0, 0, 1),
	}

	local normal = normalMap[face]
	if not normal then return end

	-- Surface point on target
	local surfaceOffset = (target.Size / 2) * normal
	local surfacePoint = target.CFrame * CFrame.new(surfaceOffset.X, surfaceOffset.Y, surfaceOffset.Z)

	-- Offset from surface by half of part's relevant dimension
	local partOffset = Vector3.zero
	if math.abs(normal.X) > 0 then
		partOffset = Vector3.new(normal.X * part.Size.X / 2, 0, 0)
	elseif math.abs(normal.Y) > 0 then
		partOffset = Vector3.new(0, normal.Y * part.Size.Y / 2, 0)
	elseif math.abs(normal.Z) > 0 then
		partOffset = Vector3.new(0, 0, normal.Z * part.Size.Z / 2)
	end

	part.CFrame = CFrame.new(surfacePoint.Position + partOffset)
	part.Anchored = true
end

--- Snap a Vector3 position to a grid
function CoordinateManager.snapToGrid(position: Vector3, gridSize: number): Vector3
	return Vector3.new(
		math.round(position.X / gridSize) * gridSize,
		math.round(position.Y / gridSize) * gridSize,
		math.round(position.Z / gridSize) * gridSize
	)
end

--- Center a part on another part (same position, keeps part's own rotation)
function CoordinateManager.centerOn(part: BasePart, target: BasePart)
	part.CFrame = CFrame.new(target.CFrame.Position) * (part.CFrame - part.CFrame.Position)
	part.Anchored = true
end

--- Distribute parts evenly along an axis
--- axis: "X", "Y", or "Z"
function CoordinateManager.distribute(parts: {BasePart}, axis: string, spacing: number, startPosition: Vector3?)
	if #parts == 0 then return end

	local start = startPosition or parts[1].Position

	for i, part in parts do
		local offset = Vector3.zero
		local dist = (i - 1) * spacing

		if axis == "X" then
			offset = Vector3.new(dist, 0, 0)
		elseif axis == "Y" then
			offset = Vector3.new(0, dist, 0)
		elseif axis == "Z" then
			offset = Vector3.new(0, 0, dist)
		end

		part.Position = start + offset
		part.Anchored = true
	end
end

--- Create a grid of parts
function CoordinateManager.createGrid(config: {
	rows: number,
	cols: number,
	partSize: Vector3,
	origin: Vector3,
	spacing: number?,
	material: Enum.Material?,
	color: Color3?,
	parent: Instance?,
}): {BasePart}
	local spacing = config.spacing or 0
	local parts = {}

	for row = 0, config.rows - 1 do
		for col = 0, config.cols - 1 do
			local part = Instance.new("Part")
			part.Size = config.partSize
			part.Anchored = true
			part.Material = config.material or Enum.Material.SmoothPlastic
			part.Color = config.color or Color3.fromRGB(200, 200, 200)

			local x = config.origin.X + col * (config.partSize.X + spacing)
			local y = config.origin.Y
			local z = config.origin.Z + row * (config.partSize.Z + spacing)

			part.Position = Vector3.new(x, y, z)
			part.Name = string.format("Grid_%d_%d", row + 1, col + 1)
			part.Parent = config.parent or workspace

			table.insert(parts, part)
		end
	end

	return parts
end

--- Get combined bounding box of multiple instances
function CoordinateManager.getBoundingBox(instances: {Instance}): (Vector3, Vector3, Vector3)
	local globalMin = Vector3.new(math.huge, math.huge, math.huge)
	local globalMax = Vector3.new(-math.huge, -math.huge, -math.huge)

	for _, inst in instances do
		local minV, maxV = CoordinateManager.getWorldBounds(inst)
		globalMin = Vector3.new(
			math.min(globalMin.X, minV.X),
			math.min(globalMin.Y, minV.Y),
			math.min(globalMin.Z, minV.Z)
		)
		globalMax = Vector3.new(
			math.max(globalMax.X, maxV.X),
			math.max(globalMax.Y, maxV.Y),
			math.max(globalMax.Z, maxV.Z)
		)
	end

	local center = (globalMin + globalMax) / 2
	local size = globalMax - globalMin
	return center, size, globalMin
end

--- Validate that a part is at its expected position
function CoordinateManager.validatePlacement(part: BasePart, expectedCFrame: CFrame): (boolean, number)
	local actualPos = part.Position
	local expectedPos = expectedCFrame.Position
	local posError = (actualPos - expectedPos).Magnitude

	return posError < EPSILON, posError
end

--- Create a named anchor point (invisible reference marker)
function CoordinateManager.createAnchor(name: string, position: Vector3): BasePart
	local anchorsFolder = workspace:FindFirstChild("_RobloxEngine_Anchors")
	if not anchorsFolder then
		anchorsFolder = Instance.new("Folder")
		anchorsFolder.Name = "_RobloxEngine_Anchors"
		anchorsFolder.Parent = workspace
	end

	-- Remove existing anchor with same name
	local existing = anchorsFolder:FindFirstChild("_Anchor_" .. name)
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
	anchor.Parent = anchorsFolder

	return anchor
end

--- Get an anchor by name
function CoordinateManager.getAnchor(name: string): BasePart?
	local anchorsFolder = workspace:FindFirstChild("_RobloxEngine_Anchors")
	if not anchorsFolder then return nil end
	return anchorsFolder:FindFirstChild("_Anchor_" .. name)
end

--- Build a room with precise wall alignment (no gaps)
function CoordinateManager.buildRoom(config: {
	center: Vector3,
	width: number,
	height: number,
	depth: number,
	wallThickness: number?,
	material: Enum.Material?,
	color: Color3?,
	parent: Instance?,
}): {[string]: BasePart}
	local t = config.wallThickness or 1
	local mat = config.material or Enum.Material.SmoothPlastic
	local col = config.color or Color3.fromRGB(200, 200, 200)
	local parent = config.parent or workspace
	local c = config.center
	local w, h, d = config.width, config.height, config.depth

	local parts = {}

	local function make(name: string, size: Vector3, pos: Vector3): BasePart
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Position = pos
		p.Anchored = true
		p.Material = mat
		p.Color = col
		p.Parent = parent
		parts[name] = p
		return p
	end

	-- Floor and ceiling span the full width and depth
	make("Floor",   Vector3.new(w, t, d), c - Vector3.new(0, h/2 - t/2, 0))
	make("Ceiling", Vector3.new(w, t, d), c + Vector3.new(0, h/2 - t/2, 0))

	-- Walls span the inner height (between floor and ceiling)
	local innerH = h - t * 2
	make("WallLeft",  Vector3.new(t, innerH, d), c - Vector3.new(w/2 - t/2, 0, 0))
	make("WallRight", Vector3.new(t, innerH, d), c + Vector3.new(w/2 - t/2, 0, 0))

	-- Front/back walls fit between left/right walls
	local innerW = w - t * 2
	make("WallFront", Vector3.new(innerW, innerH, t), c - Vector3.new(0, 0, d/2 - t/2))
	make("WallBack",  Vector3.new(innerW, innerH, t), c + Vector3.new(0, 0, d/2 - t/2))

	return parts
end

--- Calculate circular arrangement positions
function CoordinateManager.circularPositions(center: Vector3, radius: number, count: number, startAngle: number?): {CFrame}
	startAngle = startAngle or 0
	local positions = {}
	local angleStep = (2 * math.pi) / count

	for i = 0, count - 1 do
		local angle = startAngle + i * angleStep
		local x = center.X + math.cos(angle) * radius
		local z = center.Z + math.sin(angle) * radius
		local pos = Vector3.new(x, center.Y, z)
		-- Face inward toward center
		local cf = CFrame.lookAt(pos, center)
		table.insert(positions, cf)
	end

	return positions
end

return CoordinateManager
