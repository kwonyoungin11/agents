---
name: building-system
description: |
  Player building and placement system for Roblox. Grid-snapped placement,
  ghost preview, rotation controls, placement validation with collision/terrain checks,
  object removal, and server-authoritative placement persistence.
  키워드: 건축 시스템, 배치, 그리드 스냅, 미리보기, 회전, 건물 설치, 오브젝트 제거
allowed-tools:
  - Bash
  - Read
  - Edit
  - Write
  - Glob
  - Grep
effort: high
---

# Building / Placement System

Full building system for Roblox: client-side preview with ghost model, grid snapping, rotation, collision validation, server-authoritative placement, and removal. All code is Luau.

---

## Architecture Overview

```
ReplicatedStorage/
  Shared/
    BuildConfig.luau          -- Grid size, build limits, item definitions
  Assets/
    BuildItems/               -- Model templates for placeable items
ServerScriptService/
  Services/
    BuildService.luau         -- Server: validate & persist placements
StarterPlayerScripts/
  Controllers/
    BuildController.luau      -- Client: preview, input, placement requests
```

---

## 1. Build Configuration

```luau
-- ReplicatedStorage/Shared/BuildConfig.luau
--!strict

export type BuildItemDefinition = {
    id: string,
    displayName: string,
    modelName: string,
    category: string,
    gridSize: Vector3,       -- how many grid cells this item occupies (x, y, z)
    canRotate: boolean,
    canStack: boolean,        -- can be placed on top of other items
    maxPerPlayer: number?,    -- nil = unlimited
    cost: number?,
    snapToGround: boolean,
    allowedSurfaces: { string }?, -- nil = all; e.g. {"Ground", "Wall", "Ceiling"}
}

local BuildConfig = {}

BuildConfig.GRID_UNIT = 4               -- studs per grid cell
BuildConfig.MAX_PLACED_PER_PLAYER = 200
BuildConfig.BUILD_RANGE = 100            -- max studs from character
BuildConfig.ROTATION_INCREMENT = 90      -- degrees per rotation press
BuildConfig.GHOST_TRANSPARENCY = 0.6
BuildConfig.VALID_COLOR = Color3.fromRGB(0, 200, 0)
BuildConfig.INVALID_COLOR = Color3.fromRGB(255, 0, 0)

BuildConfig.Items: { [string]: BuildItemDefinition } = {
    wooden_wall = {
        id = "wooden_wall",
        displayName = "Wooden Wall",
        modelName = "WoodenWall",
        category = "Structure",
        gridSize = Vector3.new(1, 2, 1),
        canRotate = true,
        canStack = false,
        maxPerPlayer = 50,
        cost = 10,
        snapToGround = true,
        allowedSurfaces = nil,
    },
    wooden_floor = {
        id = "wooden_floor",
        displayName = "Wooden Floor",
        modelName = "WoodenFloor",
        category = "Structure",
        gridSize = Vector3.new(2, 0, 2),
        canRotate = true,
        canStack = true,
        maxPerPlayer = 100,
        cost = 5,
        snapToGround = false,
        allowedSurfaces = nil,
    },
    torch = {
        id = "torch",
        displayName = "Torch",
        modelName = "Torch",
        category = "Decoration",
        gridSize = Vector3.new(1, 1, 1),
        canRotate = false,
        canStack = false,
        maxPerPlayer = nil,
        cost = 2,
        snapToGround = false,
        allowedSurfaces = { "Wall" },
    },
}

return BuildConfig
```

---

## 2. Client Build Controller (Preview + Input)

```luau
-- StarterPlayerScripts/Controllers/BuildController.luau
--!strict

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BuildConfig = require(ReplicatedStorage.Shared.BuildConfig)

local player = Players.LocalPlayer
local mouse = player:GetMouse()
local camera = workspace.CurrentCamera

local BuildController = {}

local isBuilding = false
local currentItemId: string? = nil
local currentRotation = 0  -- degrees (0, 90, 180, 270)
local ghostModel: Model? = nil
local isValidPlacement = false
local updateConnection: RBXScriptConnection? = nil

-------------------------------------------------
-- Grid Snap Helper
-------------------------------------------------

local function snapToGrid(position: Vector3): Vector3
    local unit = BuildConfig.GRID_UNIT
    return Vector3.new(
        math.round(position.X / unit) * unit,
        math.round(position.Y / unit) * unit,
        math.round(position.Z / unit) * unit
    )
end

-------------------------------------------------
-- Ghost Model Management
-------------------------------------------------

local function createGhostModel(itemId: string): Model?
    local definition = BuildConfig.Items[itemId]
    if not definition then return nil end

    local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
    if not assetsFolder then return nil end
    local buildItems = assetsFolder:FindFirstChild("BuildItems")
    if not buildItems then return nil end

    local template = buildItems:FindFirstChild(definition.modelName)
    if not template or not template:IsA("Model") then return nil end

    local ghost = template:Clone() :: Model

    -- Make ghost transparent and non-collidable
    for _, descendant in ghost:GetDescendants() do
        if descendant:IsA("BasePart") then
            descendant.Transparency = BuildConfig.GHOST_TRANSPARENCY
            descendant.CanCollide = false
            descendant.Anchored = true
            descendant.CastShadow = false
            -- Selection box visual
            local selBox = Instance.new("SelectionBox")
            selBox.Adornee = descendant
            selBox.Color3 = BuildConfig.VALID_COLOR
            selBox.LineThickness = 0.03
            selBox.Parent = descendant
        end
    end

    ghost.Name = "BuildGhost"
    ghost.Parent = workspace

    return ghost
end

local function setGhostColor(color: Color3)
    if not ghostModel then return end
    for _, descendant in ghostModel:GetDescendants() do
        if descendant:IsA("SelectionBox") then
            descendant.Color3 = color
        end
    end
end

local function destroyGhost()
    if ghostModel then
        ghostModel:Destroy()
        ghostModel = nil
    end
end

-------------------------------------------------
-- Collision Validation
-------------------------------------------------

local function checkCollision(model: Model, cframe: CFrame): boolean
    if not model.PrimaryPart then return false end

    local itemId = currentItemId
    if not itemId then return false end
    local definition = BuildConfig.Items[itemId]
    if not definition then return false end

    local size = definition.gridSize * BuildConfig.GRID_UNIT

    -- OverlapParams to detect existing objects
    local params = OverlapParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { model, player.Character }

    local parts = workspace:GetPartBoundsInBox(cframe, size, params)

    -- Filter: ignore terrain and ground
    for _, part in parts do
        if part:IsA("BasePart") and not part:IsA("Terrain") then
            -- Check if it belongs to a placed building
            if part:GetAttribute("BuildItem") then
                return true -- collision with another placed item
            end
        end
    end

    return false
end

local function validatePlacement(position: Vector3, rotation: number): (boolean, CFrame)
    local itemId = currentItemId
    if not itemId then return false, CFrame.new() end
    local definition = BuildConfig.Items[itemId]
    if not definition then return false, CFrame.new() end

    local snapped = snapToGrid(position)
    local rotCFrame = CFrame.new(snapped) * CFrame.Angles(0, math.rad(rotation), 0)

    -- Range check
    local character = player.Character
    if character then
        local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
        if rootPart then
            local dist = (snapped - rootPart.Position).Magnitude
            if dist > BuildConfig.BUILD_RANGE then
                return false, rotCFrame
            end
        end
    end

    -- Ground snap via raycast
    if definition.snapToGround then
        local rayOrigin = snapped + Vector3.new(0, 50, 0)
        local rayDirection = Vector3.new(0, -100, 0)
        local rayParams = RaycastParams.new()
        rayParams.FilterType = Enum.RaycastFilterType.Exclude
        rayParams.FilterDescendantsInstances = { ghostModel :: Instance, player.Character :: Instance }

        local result = workspace:Raycast(rayOrigin, rayDirection, rayParams)
        if result then
            local groundY = result.Position.Y
            local halfHeight = (definition.gridSize.Y * BuildConfig.GRID_UNIT) / 2
            snapped = Vector3.new(snapped.X, groundY + halfHeight, snapped.Z)
            rotCFrame = CFrame.new(snapped) * CFrame.Angles(0, math.rad(rotation), 0)
        else
            return false, rotCFrame -- no ground found
        end
    end

    -- Collision check
    if ghostModel and checkCollision(ghostModel, rotCFrame) then
        return false, rotCFrame
    end

    return true, rotCFrame
end

-------------------------------------------------
-- Update Loop (runs while in build mode)
-------------------------------------------------

local function onUpdate()
    if not isBuilding or not ghostModel or not currentItemId then return end

    -- Raycast from mouse into world
    local unitRay = camera:ScreenPointToRay(mouse.X, mouse.Y)
    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    rayParams.FilterDescendantsInstances = { ghostModel :: Instance, player.Character :: Instance }

    local result = workspace:Raycast(unitRay.Origin, unitRay.Direction * 500, rayParams)
    if result then
        local valid, cframe = validatePlacement(result.Position, currentRotation)
        isValidPlacement = valid
        ghostModel:PivotTo(cframe)
        setGhostColor(if valid then BuildConfig.VALID_COLOR else BuildConfig.INVALID_COLOR)
    end
end

-------------------------------------------------
-- Input Handling
-------------------------------------------------

local function onInputBegan(input: InputObject, gameProcessed: boolean)
    if gameProcessed then return end
    if not isBuilding then return end

    -- R key to rotate
    if input.KeyCode == Enum.KeyCode.R then
        currentRotation = (currentRotation + BuildConfig.ROTATION_INCREMENT) % 360
    end

    -- Q key to cancel
    if input.KeyCode == Enum.KeyCode.Q then
        BuildController.CancelBuild()
    end

    -- Left click to place
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        if isValidPlacement and ghostModel and currentItemId then
            local cframe = ghostModel:GetPivot()
            -- Send placement request to server
            local remotes = ReplicatedStorage:FindFirstChild("BuildRemotes")
            if remotes then
                local placeRemote = remotes:FindFirstChild("PlaceRequest") :: RemoteEvent
                if placeRemote then
                    placeRemote:FireServer(currentItemId, cframe)
                end
            end
        end
    end

    -- Right click to remove
    if input.UserInputType == Enum.UserInputType.MouseButton2 then
        local target = mouse.Target
        if target and target:GetAttribute("BuildItem") then
            local placedId = target:GetAttribute("PlacementId")
            if placedId then
                local remotes = ReplicatedStorage:FindFirstChild("BuildRemotes")
                if remotes then
                    local removeRemote = remotes:FindFirstChild("RemoveRequest") :: RemoteEvent
                    if removeRemote then
                        removeRemote:FireServer(placedId)
                    end
                end
            end
        end
    end
end

-------------------------------------------------
-- Public API
-------------------------------------------------

function BuildController.StartBuild(itemId: string)
    if isBuilding then
        BuildController.CancelBuild()
    end

    local definition = BuildConfig.Items[itemId]
    if not definition then
        warn("[BuildController] Unknown item:", itemId)
        return
    end

    currentItemId = itemId
    currentRotation = 0
    isBuilding = true

    ghostModel = createGhostModel(itemId)
    updateConnection = RunService.RenderStepped:Connect(onUpdate)
end

function BuildController.CancelBuild()
    isBuilding = false
    currentItemId = nil
    isValidPlacement = false
    destroyGhost()

    if updateConnection then
        updateConnection:Disconnect()
        updateConnection = nil
    end
end

function BuildController.IsBuilding(): boolean
    return isBuilding
end

function BuildController.Init()
    UserInputService.InputBegan:Connect(onInputBegan)

    -- Listen for server confirmation
    local remotes = ReplicatedStorage:WaitForChild("BuildRemotes")
    local placeConfirm = remotes:WaitForChild("PlaceConfirm") :: RemoteEvent
    placeConfirm.OnClientEvent:Connect(function(success: boolean, message: string?)
        if not success and message then
            warn("[Build]", message)
        end
    end)
end

return BuildController
```

---

## 3. Server Build Service

```luau
-- ServerScriptService/Services/BuildService.luau
--!strict

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BuildConfig = require(ReplicatedStorage.Shared.BuildConfig)

local BuildService = {}

local buildDataStore = DataStoreService:GetDataStore("BuildData_v1")

-- Tracking: player -> list of placement records
type PlacementRecord = {
    placementId: string,
    itemId: string,
    cframe: { number },   -- serialized CFrame components
    timestamp: number,
}

local playerPlacements: { [Player]: { PlacementRecord } } = {}
local placedModels: { [string]: Model } = {} -- placementId -> Model

-------------------------------------------------
-- CFrame Serialization
-------------------------------------------------

local function serializeCFrame(cf: CFrame): { number }
    return { cf:GetComponents() }
end

local function deserializeCFrame(data: { number }): CFrame
    return CFrame.new(unpack(data))
end

-------------------------------------------------
-- Placement Validation (Server)
-------------------------------------------------

local function validateServerSide(player: Player, itemId: string, cframe: CFrame): (boolean, string?)
    local definition = BuildConfig.Items[itemId]
    if not definition then
        return false, "Invalid item"
    end

    -- Range check
    local character = player.Character
    if not character then return false, "No character" end
    local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
    if not rootPart then return false, "No root part" end

    local dist = (cframe.Position - rootPart.Position).Magnitude
    if dist > BuildConfig.BUILD_RANGE + 10 then -- small tolerance
        return false, "Too far away"
    end

    -- Count check
    local placements = playerPlacements[player] or {}
    if #placements >= BuildConfig.MAX_PLACED_PER_PLAYER then
        return false, "Build limit reached"
    end

    -- Per-item limit check
    if definition.maxPerPlayer then
        local count = 0
        for _, record in placements do
            if record.itemId == itemId then
                count += 1
            end
        end
        if count >= definition.maxPerPlayer then
            return false, "Item limit reached for " .. definition.displayName
        end
    end

    -- Collision check (server-side)
    local size = definition.gridSize * BuildConfig.GRID_UNIT
    local params = OverlapParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { character }

    local parts = workspace:GetPartBoundsInBox(cframe, size, params)
    for _, part in parts do
        if part:IsA("BasePart") and part:GetAttribute("BuildItem") then
            return false, "Overlapping with another building"
        end
    end

    return true, nil
end

-------------------------------------------------
-- Spawn Placed Model
-------------------------------------------------

local function spawnPlacedModel(record: PlacementRecord, ownerId: number): Model?
    local definition = BuildConfig.Items[record.itemId]
    if not definition then return nil end

    local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
    if not assetsFolder then return nil end
    local buildItems = assetsFolder:FindFirstChild("BuildItems")
    if not buildItems then return nil end

    local template = buildItems:FindFirstChild(definition.modelName)
    if not template or not template:IsA("Model") then return nil end

    local model = template:Clone() :: Model
    model.Name = "Placed_" .. record.placementId

    local cframe = deserializeCFrame(record.cframe)
    model:PivotTo(cframe)

    -- Mark all parts
    for _, part in model:GetDescendants() do
        if part:IsA("BasePart") then
            part.Anchored = true
            part:SetAttribute("BuildItem", record.itemId)
            part:SetAttribute("PlacementId", record.placementId)
            part:SetAttribute("OwnerId", ownerId)
        end
    end

    local buildFolder = workspace:FindFirstChild("PlayerBuilds")
    if not buildFolder then
        buildFolder = Instance.new("Folder")
        buildFolder.Name = "PlayerBuilds"
        buildFolder.Parent = workspace
    end
    model.Parent = buildFolder

    placedModels[record.placementId] = model
    return model
end

-------------------------------------------------
-- Persistence
-------------------------------------------------

local function loadPlacements(player: Player): { PlacementRecord }
    local success, data = pcall(function()
        return buildDataStore:GetAsync("builds_" .. player.UserId)
    end)
    if success and data then
        return data :: { PlacementRecord }
    end
    return {}
end

local function savePlacements(player: Player)
    local records = playerPlacements[player]
    if not records then return end

    pcall(function()
        buildDataStore:SetAsync("builds_" .. player.UserId, records)
    end)
end

-------------------------------------------------
-- Init
-------------------------------------------------

function BuildService.Init()
    local remotesFolder = Instance.new("Folder")
    remotesFolder.Name = "BuildRemotes"
    remotesFolder.Parent = ReplicatedStorage

    local placeRequest = Instance.new("RemoteEvent")
    placeRequest.Name = "PlaceRequest"
    placeRequest.Parent = remotesFolder

    local removeRequest = Instance.new("RemoteEvent")
    removeRequest.Name = "RemoveRequest"
    removeRequest.Parent = remotesFolder

    local placeConfirm = Instance.new("RemoteEvent")
    placeConfirm.Name = "PlaceConfirm"
    placeConfirm.Parent = remotesFolder

    -- Handle place requests
    placeRequest.OnServerEvent:Connect(function(player: Player, itemId: string, cframe: CFrame)
        local valid, reason = validateServerSide(player, itemId, cframe)
        if not valid then
            placeConfirm:FireClient(player, false, reason)
            return
        end

        local record: PlacementRecord = {
            placementId = HttpService:GenerateGUID(false),
            itemId = itemId,
            cframe = serializeCFrame(cframe),
            timestamp = os.time(),
        }

        if not playerPlacements[player] then
            playerPlacements[player] = {}
        end
        table.insert(playerPlacements[player], record)

        spawnPlacedModel(record, player.UserId)
        placeConfirm:FireClient(player, true, nil)
    end)

    -- Handle remove requests
    removeRequest.OnServerEvent:Connect(function(player: Player, placementId: string)
        local records = playerPlacements[player]
        if not records then return end

        for i, record in records do
            if record.placementId == placementId then
                -- Verify ownership via model attribute
                local model = placedModels[placementId]
                if model then
                    model:Destroy()
                    placedModels[placementId] = nil
                end
                table.remove(records, i)
                placeConfirm:FireClient(player, true, "Removed")
                return
            end
        end

        placeConfirm:FireClient(player, false, "Not found or not yours")
    end)

    -- Player lifecycle
    Players.PlayerAdded:Connect(function(player: Player)
        local records = loadPlacements(player)
        playerPlacements[player] = records

        -- Respawn existing buildings
        for _, record in records do
            spawnPlacedModel(record, player.UserId)
        end
    end)

    Players.PlayerRemoving:Connect(function(player: Player)
        savePlacements(player)

        -- Optionally remove buildings when player leaves (for plot-based games)
        -- Uncomment if buildings should disappear:
        -- local records = playerPlacements[player]
        -- if records then
        --     for _, record in records do
        --         local model = placedModels[record.placementId]
        --         if model then model:Destroy() end
        --         placedModels[record.placementId] = nil
        --     end
        -- end

        playerPlacements[player] = nil
    end)

    -- Periodic save
    task.spawn(function()
        while true do
            task.wait(180)
            for plr, _ in playerPlacements do
                if plr.Parent then
                    savePlacements(plr)
                end
            end
        end
    end)
end

return BuildService
```

---

## Key Implementation Notes

1. **Grid snapping** uses `math.round(pos / unit) * unit` for each axis. Adjust `GRID_UNIT` (default 4 studs) per game needs.
2. **Ghost preview** is a cloned model with transparency and SelectionBox. Color changes green/red based on validity.
3. **Rotation** increments by 90 degrees on R key. The ghost model pivots in real-time.
4. **Collision detection** uses `workspace:GetPartBoundsInBox()` both client-side (preview) and server-side (validation).
5. **Server authority**: The server re-validates every placement request. Never trust client CFrame blindly -- range and collision are checked again.
6. **Persistence**: CFrame is serialized as 12 floats via `GetComponents()`. Stored per-player in DataStore.
7. **Removal**: Right-click on a placed object sends the placementId to the server, which verifies ownership before destroying.

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

The user may specify:
- `$GRID_SIZE` -- Override grid unit in studs (default 4)
- `$MAX_PLACED` -- Override max placements per player (default 200)
- `$BUILD_RANGE` -- Override max build distance (default 100)
- `$ROTATION_INCREMENT` -- Degrees per rotation step (default 90)
- `$PERSISTENCE` -- "datastore" (default) or "none" for session-only builds
- `$PLOT_BASED` -- If true, constrain placement to a designated plot area per player
- `$UNDO_SUPPORT` -- If true, add undo/redo stack for placements
- `$CATEGORIES` -- Custom item categories to include
