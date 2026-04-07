--!strict
-- ContextTracker: Workspace state tracking and spatial context management
-- Maintains awareness of the current build state across MCP interactions

local ContextTracker = {}

local HttpService = game:GetService("HttpService")
local ServerStorage = game:GetService("ServerStorage")

local MAX_SCAN_DEPTH = 10
local CONTEXT_STORE_NAME = "_RobloxEngine"
local CONTEXT_VALUE_NAME = "_Context"

--------------------------------------------------------------------------------
-- WORKSPACE SCANNING
--------------------------------------------------------------------------------

--- Scan workspace hierarchy and return structured data with positions
function ContextTracker.scanWorkspace(parent: Instance?, maxDepth: number?): string
	parent = parent or workspace
	maxDepth = maxDepth or MAX_SCAN_DEPTH

	local lines = {}

	local function scan(inst: Instance, depth: number, indent: string)
		if depth > maxDepth then return end
		-- Skip engine-internal folders
		if inst.Name:sub(1, 13) == "_RobloxEngine" then return end

		local info = indent .. inst.Name .. " [" .. inst.ClassName .. "]"

		if inst:IsA("BasePart") then
			info = info .. string.format(
				" Pos:(%.1f, %.1f, %.1f) Size:(%.1f, %.1f, %.1f) Mat:%s Col:(%d,%d,%d)",
				inst.Position.X, inst.Position.Y, inst.Position.Z,
				inst.Size.X, inst.Size.Y, inst.Size.Z,
				inst.Material.Name,
				math.floor(inst.Color.R * 255),
				math.floor(inst.Color.G * 255),
				math.floor(inst.Color.B * 255)
			)
			if inst.Transparency > 0 then
				info = info .. string.format(" Trans:%.1f", inst.Transparency)
			end
			if not inst.Anchored then
				info = info .. " [Unanchored]"
			end
		elseif inst:IsA("Model") then
			if inst.PrimaryPart then
				local pp = inst.PrimaryPart
				info = info .. string.format(
					" PrimaryPart:%s Pos:(%.1f, %.1f, %.1f)",
					pp.Name, pp.Position.X, pp.Position.Y, pp.Position.Z
				)
			end
			local cf, size = inst:GetBoundingBox()
			info = info .. string.format(
				" BBox:(%.1f, %.1f, %.1f)",
				size.X, size.Y, size.Z
			)
		elseif inst:IsA("Script") or inst:IsA("LocalScript") or inst:IsA("ModuleScript") then
			info = info .. " [Script:" .. #inst.Source .. " chars]"
		elseif inst:IsA("ParticleEmitter") then
			info = info .. string.format(" Rate:%d", inst.Rate)
		elseif inst:IsA("PointLight") or inst:IsA("SpotLight") or inst:IsA("SurfaceLight") then
			info = info .. string.format(" Bright:%.1f Range:%.1f", inst.Brightness, inst.Range)
		elseif inst:IsA("Beam") then
			info = info .. " [Beam]"
		elseif inst:IsA("Trail") then
			info = info .. " [Trail]"
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

--- Compact scan - returns only BaseParts with positions (faster for large workspaces)
function ContextTracker.scanParts(parent: Instance?): {{name: string, class: string, position: Vector3, size: Vector3, path: string}}
	parent = parent or workspace
	local parts = {}

	local function scan(inst: Instance, path: string)
		if inst.Name:sub(1, 13) == "_RobloxEngine" then return end

		if inst:IsA("BasePart") then
			table.insert(parts, {
				name = inst.Name,
				class = inst.ClassName,
				position = inst.Position,
				size = inst.Size,
				path = path .. "." .. inst.Name,
			})
		end

		for _, child in inst:GetChildren() do
			scan(child, path .. "." .. inst.Name)
		end
	end

	for _, child in parent:GetChildren() do
		if child.Name ~= "Camera" and child.Name ~= "Terrain" then
			scan(child, "workspace")
		end
	end

	return parts
end

--- Find all objects near a position within a radius
function ContextTracker.findNearby(position: Vector3, radius: number, parent: Instance?): {BasePart}
	parent = parent or workspace
	local results = {}

	local function scan(inst: Instance)
		if inst:IsA("BasePart") then
			local dist = (inst.Position - position).Magnitude
			if dist <= radius then
				table.insert(results, inst)
			end
		end
		for _, child in inst:GetChildren() do
			scan(child)
		end
	end

	scan(parent)

	-- Sort by distance
	table.sort(results, function(a, b)
		return (a.Position - position).Magnitude < (b.Position - position).Magnitude
	end)

	return results
end

--- Print nearby objects (for MCP output)
function ContextTracker.printNearby(position: Vector3, radius: number): string
	local nearby = ContextTracker.findNearby(position, radius)
	local lines = {}
	table.insert(lines, string.format("Objects within %.1f studs of (%.1f, %.1f, %.1f):", radius, position.X, position.Y, position.Z))

	for _, part in nearby do
		local dist = (part.Position - position).Magnitude
		table.insert(lines, string.format(
			"  %.1f studs: %s [%s] Pos:(%.1f, %.1f, %.1f) Size:(%.1f, %.1f, %.1f)",
			dist, part:GetFullName(), part.ClassName,
			part.Position.X, part.Position.Y, part.Position.Z,
			part.Size.X, part.Size.Y, part.Size.Z
		))
	end

	if #nearby == 0 then
		table.insert(lines, "  (none found)")
	end

	return table.concat(lines, "\n")
end

--------------------------------------------------------------------------------
-- NAMED ANCHORS
--------------------------------------------------------------------------------

local ANCHORS_FOLDER = "_RobloxEngine_Anchors"

--- Get or create anchors folder
local function getAnchorsFolder(): Folder
	local folder = workspace:FindFirstChild(ANCHORS_FOLDER)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = ANCHORS_FOLDER
		folder.Parent = workspace
	end
	return folder
end

--- Get all named anchor points
function ContextTracker.getNamedAnchors(): {[string]: Vector3}
	local folder = workspace:FindFirstChild(ANCHORS_FOLDER)
	if not folder then return {} end

	local anchors = {}
	for _, child in folder:GetChildren() do
		if child:IsA("BasePart") and child.Name:sub(1, 8) == "_Anchor_" then
			local name = child.Name:sub(9)
			anchors[name] = child.Position
		end
	end
	return anchors
end

--- Set (create or update) a named anchor
function ContextTracker.setAnchor(name: string, position: Vector3): BasePart
	local folder = getAnchorsFolder()
	local fullName = "_Anchor_" .. name

	local existing = folder:FindFirstChild(fullName)
	if existing then
		existing.Position = position
		return existing
	end

	local anchor = Instance.new("Part")
	anchor.Name = fullName
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

--- Get anchor position by name
function ContextTracker.getAnchorPosition(name: string): Vector3?
	local folder = workspace:FindFirstChild(ANCHORS_FOLDER)
	if not folder then return nil end

	local anchor = folder:FindFirstChild("_Anchor_" .. name)
	if anchor and anchor:IsA("BasePart") then
		return anchor.Position
	end
	return nil
end

--- Remove an anchor
function ContextTracker.removeAnchor(name: string): boolean
	local folder = workspace:FindFirstChild(ANCHORS_FOLDER)
	if not folder then return false end

	local anchor = folder:FindFirstChild("_Anchor_" .. name)
	if anchor then
		anchor:Destroy()
		return true
	end
	return false
end

--- Print all anchors (for MCP output)
function ContextTracker.printAnchors(): string
	local anchors = ContextTracker.getNamedAnchors()
	local lines = {"Named Anchors:"}

	local count = 0
	for name, pos in anchors do
		table.insert(lines, string.format("  %s: (%.1f, %.1f, %.1f)", name, pos.X, pos.Y, pos.Z))
		count += 1
	end

	if count == 0 then
		table.insert(lines, "  (none)")
	end

	return table.concat(lines, "\n")
end

--------------------------------------------------------------------------------
-- PERSISTENT CONTEXT STORAGE
--------------------------------------------------------------------------------

--- Get or create the engine storage folder
local function getEngineStorage(): Folder
	local folder = ServerStorage:FindFirstChild(CONTEXT_STORE_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = CONTEXT_STORE_NAME
		folder.Parent = ServerStorage
	end
	return folder
end

--- Save a key-value pair to persistent context
function ContextTracker.saveContext(key: string, value: any)
	local folder = getEngineStorage()
	local contextObj = folder:FindFirstChild(CONTEXT_VALUE_NAME)

	if not contextObj then
		contextObj = Instance.new("StringValue")
		contextObj.Name = CONTEXT_VALUE_NAME
		contextObj.Parent = folder
	end

	local data = {}
	if contextObj.Value ~= "" then
		local success, decoded = pcall(function()
			return HttpService:JSONDecode(contextObj.Value)
		end)
		if success and type(decoded) == "table" then
			data = decoded
		end
	end

	data[key] = value
	contextObj.Value = HttpService:JSONEncode(data)
end

--- Load a value from persistent context
function ContextTracker.loadContext(key: string): any
	local folder = ServerStorage:FindFirstChild(CONTEXT_STORE_NAME)
	if not folder then return nil end

	local contextObj = folder:FindFirstChild(CONTEXT_VALUE_NAME)
	if not contextObj or contextObj.Value == "" then return nil end

	local success, data = pcall(function()
		return HttpService:JSONDecode(contextObj.Value)
	end)

	if success and type(data) == "table" then
		return data[key]
	end
	return nil
end

--- Get full persistent context
function ContextTracker.getFullContext(): {[string]: any}
	local folder = ServerStorage:FindFirstChild(CONTEXT_STORE_NAME)
	if not folder then return {} end

	local contextObj = folder:FindFirstChild(CONTEXT_VALUE_NAME)
	if not contextObj or contextObj.Value == "" then return {} end

	local success, data = pcall(function()
		return HttpService:JSONDecode(contextObj.Value)
	end)

	if success and type(data) == "table" then
		return data
	end
	return {}
end

--- Clear all persistent context
function ContextTracker.clearContext()
	local folder = ServerStorage:FindFirstChild(CONTEXT_STORE_NAME)
	if not folder then return end

	local contextObj = folder:FindFirstChild(CONTEXT_VALUE_NAME)
	if contextObj then
		contextObj.Value = ""
	end
end

--------------------------------------------------------------------------------
-- FULL STATE REPORT
--------------------------------------------------------------------------------

--- Get comprehensive state report (workspace + anchors + context)
function ContextTracker.getState(): string
	local lines = {}

	table.insert(lines, "=== WORKSPACE STATE ===")
	table.insert(lines, ContextTracker.scanWorkspace())
	table.insert(lines, "")
	table.insert(lines, "=== ANCHORS ===")
	table.insert(lines, ContextTracker.printAnchors())
	table.insert(lines, "")
	table.insert(lines, "=== PERSISTENT CONTEXT ===")

	local ctx = ContextTracker.getFullContext()
	if next(ctx) then
		for k, v in ctx do
			table.insert(lines, string.format("  %s: %s", k, tostring(v)))
		end
	else
		table.insert(lines, "  (empty)")
	end

	return table.concat(lines, "\n")
end

--- Quick summary: counts of objects by type
function ContextTracker.getSummary(): string
	local counts = {
		Parts = 0,
		Models = 0,
		Scripts = 0,
		Lights = 0,
		Effects = 0,
		Attachments = 0,
	}

	local function scan(inst: Instance)
		if inst.Name:sub(1, 13) == "_RobloxEngine" then return end

		if inst:IsA("BasePart") then
			counts.Parts += 1
		elseif inst:IsA("Model") then
			counts.Models += 1
		elseif inst:IsA("Script") or inst:IsA("LocalScript") or inst:IsA("ModuleScript") then
			counts.Scripts += 1
		elseif inst:IsA("PointLight") or inst:IsA("SpotLight") or inst:IsA("SurfaceLight") then
			counts.Lights += 1
		elseif inst:IsA("ParticleEmitter") or inst:IsA("Beam") or inst:IsA("Trail") then
			counts.Effects += 1
		elseif inst:IsA("Attachment") then
			counts.Attachments += 1
		end

		for _, child in inst:GetChildren() do
			scan(child)
		end
	end

	for _, child in workspace:GetChildren() do
		if child.Name ~= "Camera" and child.Name ~= "Terrain" then
			scan(child)
		end
	end

	local lines = {"Workspace Summary:"}
	for category, count in counts do
		if count > 0 then
			table.insert(lines, string.format("  %s: %d", category, count))
		end
	end

	return table.concat(lines, "\n")
end

return ContextTracker
