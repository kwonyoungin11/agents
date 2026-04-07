--!strict
-- GridSnap: Grid-based positioning and rotation snapping utilities
-- Ensures objects align to consistent grids for clean builds

local GridSnap = {}

-- Default grid size in studs
GridSnap.DefaultGridSize = 1
-- Default angle step in degrees
GridSnap.DefaultAngleStep = 90

--- Snap a Vector3 position to the nearest grid point
function GridSnap.snap(position: Vector3, gridSize: number?): Vector3
	local g = gridSize or GridSnap.DefaultGridSize
	return Vector3.new(
		math.round(position.X / g) * g,
		math.round(position.Y / g) * g,
		math.round(position.Z / g) * g
	)
end

--- Snap only specific axes (keep others unchanged)
--- axes: string like "XZ" or "XYZ" or "Y"
function GridSnap.snapAxes(position: Vector3, axes: string, gridSize: number?): Vector3
	local g = gridSize or GridSnap.DefaultGridSize
	local x = if string.find(axes, "X") then math.round(position.X / g) * g else position.X
	local y = if string.find(axes, "Y") then math.round(position.Y / g) * g else position.Y
	local z = if string.find(axes, "Z") then math.round(position.Z / g) * g else position.Z
	return Vector3.new(x, y, z)
end

--- Snap both position and rotation of a CFrame
function GridSnap.snapCFrame(cframe: CFrame, gridSize: number?, angleStep: number?): CFrame
	local g = gridSize or GridSnap.DefaultGridSize
	local a = angleStep or GridSnap.DefaultAngleStep
	local aRad = math.rad(a)

	-- Snap position
	local pos = GridSnap.snap(cframe.Position, g)

	-- Extract Euler angles, snap them, reconstruct
	local rx, ry, rz = cframe:ToEulerAnglesYXZ()
	rx = math.round(rx / aRad) * aRad
	ry = math.round(ry / aRad) * aRad
	rz = math.round(rz / aRad) * aRad

	return CFrame.new(pos) * CFrame.fromEulerAnglesYXZ(rx, ry, rz)
end

--- Snap position relative to a surface normal (useful for building on angled surfaces)
function GridSnap.snapToSurface(position: Vector3, surfaceNormal: Vector3, gridSize: number?): Vector3
	local g = gridSize or GridSnap.DefaultGridSize

	-- Project position onto the plane perpendicular to the normal
	-- Then snap the projected coordinates
	local absNormal = Vector3.new(math.abs(surfaceNormal.X), math.abs(surfaceNormal.Y), math.abs(surfaceNormal.Z))

	-- Determine which axis is the surface normal (dominant axis)
	local snapped = position
	if absNormal.Y > absNormal.X and absNormal.Y > absNormal.Z then
		-- Horizontal surface (floor/ceiling) - snap X and Z
		snapped = Vector3.new(
			math.round(position.X / g) * g,
			position.Y,
			math.round(position.Z / g) * g
		)
	elseif absNormal.X > absNormal.Z then
		-- X-facing wall - snap Y and Z
		snapped = Vector3.new(
			position.X,
			math.round(position.Y / g) * g,
			math.round(position.Z / g) * g
		)
	else
		-- Z-facing wall - snap X and Y
		snapped = Vector3.new(
			math.round(position.X / g) * g,
			math.round(position.Y / g) * g,
			position.Z
		)
	end

	return snapped
end

--- Calculate aligned CFrame for placing relative to a base with grid snapping
function GridSnap.getAlignedCFrame(baseCFrame: CFrame, localOffset: Vector3, gridSize: number?): CFrame
	local g = gridSize or GridSnap.DefaultGridSize

	-- Snap the local offset to grid
	local snappedOffset = GridSnap.snap(localOffset, g)

	-- Apply snapped offset in base's local space
	return baseCFrame * CFrame.new(snappedOffset.X, snappedOffset.Y, snappedOffset.Z)
end

--- Snap angle to nearest step (in degrees)
function GridSnap.snapAngle(angleDegrees: number, step: number?): number
	local s = step or GridSnap.DefaultAngleStep
	return math.round(angleDegrees / s) * s
end

--- Floor snap - snap Y coordinate so the bottom of the part sits on the grid
function GridSnap.snapToFloor(part: BasePart, floorY: number?, gridSize: number?): Vector3
	local g = gridSize or GridSnap.DefaultGridSize
	local floor = floorY or 0

	local pos = part.Position
	local halfHeight = part.Size.Y / 2

	return Vector3.new(
		math.round(pos.X / g) * g,
		floor + halfHeight,
		math.round(pos.Z / g) * g
	)
end

--- Stack snap - snap a part directly on top of another with grid alignment
function GridSnap.snapOnTop(basePart: BasePart, newPart: BasePart, gridSize: number?): CFrame
	local g = gridSize or GridSnap.DefaultGridSize

	local baseTop = basePart.Position.Y + basePart.Size.Y / 2
	local newHalfHeight = newPart.Size.Y / 2

	local x = math.round(basePart.Position.X / g) * g
	local z = math.round(basePart.Position.Z / g) * g

	return CFrame.new(x, baseTop + newHalfHeight, z)
end

--- Wall mount snap - snap a part flush against a wall face with grid alignment on the wall plane
function GridSnap.snapToWall(wall: BasePart, face: string, partSize: Vector3, gridSize: number?): CFrame
	local g = gridSize or GridSnap.DefaultGridSize
	local wallCF = wall.CFrame
	local wallSize = wall.Size

	local faceOffset, faceNormal
	if face == "Front" then
		faceOffset = Vector3.new(0, 0, -wallSize.Z/2)
		faceNormal = Vector3.new(0, 0, -1)
	elseif face == "Back" then
		faceOffset = Vector3.new(0, 0, wallSize.Z/2)
		faceNormal = Vector3.new(0, 0, 1)
	elseif face == "Left" then
		faceOffset = Vector3.new(-wallSize.X/2, 0, 0)
		faceNormal = Vector3.new(-1, 0, 0)
	elseif face == "Right" then
		faceOffset = Vector3.new(wallSize.X/2, 0, 0)
		faceNormal = Vector3.new(1, 0, 0)
	else
		faceOffset = Vector3.new(0, 0, -wallSize.Z/2)
		faceNormal = Vector3.new(0, 0, -1)
	end

	-- Surface point
	local surfaceWorld = wallCF * CFrame.new(faceOffset)

	-- Push out by half the part's depth along the face normal
	local pushOut
	if math.abs(faceNormal.X) > 0 then
		pushOut = faceNormal * (partSize.Z / 2)
	else
		pushOut = faceNormal * (partSize.X / 2)
	end

	local finalPos = surfaceWorld.Position + wallCF:VectorToWorldSpace(pushOut)

	-- Snap to grid on the wall plane
	finalPos = GridSnap.snapToSurface(finalPos, wallCF:VectorToWorldSpace(faceNormal), g)

	return CFrame.new(finalPos) * (wallCF - wallCF.Position)
end

return GridSnap
