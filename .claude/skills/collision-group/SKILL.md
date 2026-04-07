---
name: collision-group
description: |
  PhysicsService 충돌 그룹, 플레이어-NPC 무충돌, 탄환 아군 관통, 커스텀 충돌 필터링 시스템.
  PhysicsService collision groups, player-NPC no-clip, bullet pass-through allies, custom collision filtering, ragdoll collision, vehicle collision layers.
allowed-tools:
  - Bash
  - Edit
  - Write
  - Read
  - Glob
  - Grep
effort: high
---

# Collision Group System

This skill covers PhysicsService collision group management, player-NPC no-clip setups, bullet pass-through systems, custom collision layer configuration, and common collision group patterns.

---

## 1. Collision Group Manager

```luau
--!strict
-- ServerScript/ModuleScript: Collision group management system

local PhysicsService = game:GetService("PhysicsService")

local CollisionGroupManager = {}

--- Registers a collision group (safe to call multiple times; idempotent).
function CollisionGroupManager.register(groupName: string)
    -- PhysicsService:RegisterCollisionGroup is idempotent in modern Roblox
    PhysicsService:RegisterCollisionGroup(groupName)
end

--- Sets whether two groups can collide with each other.
function CollisionGroupManager.setCollidable(group1: string, group2: string, canCollide: boolean)
    PhysicsService:CollisionGroupSetCollidable(group1, group2, canCollide)
end

--- Assigns a part to a collision group.
function CollisionGroupManager.assignPart(part: BasePart, groupName: string)
    part.CollisionGroup = groupName
end

--- Assigns all BaseParts in a model to a collision group.
function CollisionGroupManager.assignModel(model: Instance, groupName: string)
    for _, descendant in model:GetDescendants() do
        if descendant:IsA("BasePart") then
            descendant.CollisionGroup = groupName
        end
    end

    -- Also handle future parts added to the model
    model.DescendantAdded:Connect(function(descendant)
        if descendant:IsA("BasePart") then
            descendant.CollisionGroup = groupName
        end
    end)
end

--- Batch-registers multiple groups and their relationships.
function CollisionGroupManager.setup(config: {
    groups: { string },
    rules: { { group1: string, group2: string, collide: boolean } },
})
    for _, groupName in config.groups do
        CollisionGroupManager.register(groupName)
    end

    for _, rule in config.rules do
        CollisionGroupManager.setCollidable(rule.group1, rule.group2, rule.collide)
    end
end

return CollisionGroupManager
```

---

## 2. Standard Game Collision Setup

```luau
--!strict
-- ServerScript: Common collision group configuration for a typical game

local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local CollisionGroupManager = require(path.to.CollisionGroupManager)

-- Register standard groups
CollisionGroupManager.setup({
    groups = {
        "Players",
        "NPCs",
        "Bullets",
        "Projectiles",
        "Loot",
        "Ragdoll",
        "Vehicles",
        "Triggers",     -- invisible trigger volumes
    },
    rules = {
        -- Players don't collide with each other (no player-stacking)
        { group1 = "Players", group2 = "Players", collide = false },

        -- Players don't collide with NPCs (no blocking)
        { group1 = "Players", group2 = "NPCs", collide = false },

        -- Bullets pass through players on the same team (handled per-bullet)
        { group1 = "Bullets", group2 = "Players", collide = false },
        { group1 = "Bullets", group2 = "NPCs", collide = true },
        { group1 = "Bullets", group2 = "Bullets", collide = false },

        -- Projectiles collide with everything except triggers
        { group1 = "Projectiles", group2 = "Triggers", collide = false },

        -- Loot doesn't collide with players (prevents physics pushing)
        { group1 = "Loot", group2 = "Players", collide = false },
        { group1 = "Loot", group2 = "NPCs", collide = false },

        -- Ragdoll doesn't collide with players or NPCs
        { group1 = "Ragdoll", group2 = "Players", collide = false },
        { group1 = "Ragdoll", group2 = "NPCs", collide = false },
        { group1 = "Ragdoll", group2 = "Ragdoll", collide = false },

        -- Triggers don't collide with anything physical
        { group1 = "Triggers", group2 = "Players", collide = false },
        { group1 = "Triggers", group2 = "NPCs", collide = false },
        { group1 = "Triggers", group2 = "Vehicles", collide = false },
    },
})

-- Auto-assign players to collision group when they spawn
Players.PlayerAdded:Connect(function(player: Player)
    player.CharacterAdded:Connect(function(character: Model)
        -- Wait for the character to fully load
        task.defer(function()
            CollisionGroupManager.assignModel(character, "Players")
        end)
    end)
end)
```

---

## 3. Team-Aware Bullet Collision

```luau
--!strict
-- ServerScript: Bullets pass through allies but hit enemies

local PhysicsService = game:GetService("PhysicsService")
local CollisionGroupManager = require(path.to.CollisionGroupManager)

local TeamBullets = {}

-- Register per-team bullet groups
CollisionGroupManager.register("Bullets_Team1")
CollisionGroupManager.register("Bullets_Team2")
CollisionGroupManager.register("Players_Team1")
CollisionGroupManager.register("Players_Team2")

-- Team1 bullets pass through Team1 players, hit Team2
CollisionGroupManager.setCollidable("Bullets_Team1", "Players_Team1", false)
CollisionGroupManager.setCollidable("Bullets_Team1", "Players_Team2", true)

-- Team2 bullets pass through Team2 players, hit Team1
CollisionGroupManager.setCollidable("Bullets_Team2", "Players_Team2", false)
CollisionGroupManager.setCollidable("Bullets_Team2", "Players_Team1", true)

-- Bullets never collide with other bullets
CollisionGroupManager.setCollidable("Bullets_Team1", "Bullets_Team1", false)
CollisionGroupManager.setCollidable("Bullets_Team2", "Bullets_Team2", false)
CollisionGroupManager.setCollidable("Bullets_Team1", "Bullets_Team2", false)

--- Creates a bullet part assigned to the correct team collision group.
function TeamBullets.createBullet(teamId: number, position: Vector3, velocity: Vector3): BasePart
    local bullet = Instance.new("Part")
    bullet.Size = Vector3.new(0.3, 0.3, 1)
    bullet.Position = position
    bullet.Anchored = false
    bullet.CanCollide = true
    bullet.Material = Enum.Material.Neon
    bullet.Color = if teamId == 1 then Color3.fromRGB(50, 150, 255) else Color3.fromRGB(255, 80, 80)

    -- Assign to team bullet group
    bullet.CollisionGroup = if teamId == 1 then "Bullets_Team1" else "Bullets_Team2"

    -- Apply velocity
    local bodyVelocity = Instance.new("BodyVelocity")
    bodyVelocity.Velocity = velocity
    bodyVelocity.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
    bodyVelocity.Parent = bullet

    bullet.Parent = workspace

    -- Auto-cleanup
    game:GetService("Debris"):AddItem(bullet, 5)

    return bullet
end

--- Assigns a player character to their team collision group.
function TeamBullets.assignPlayerTeam(character: Model, teamId: number)
    local groupName = if teamId == 1 then "Players_Team1" else "Players_Team2"
    CollisionGroupManager.assignModel(character, groupName)
end

return TeamBullets
```

---

## 4. NPC No-Clip System

```luau
--!strict
-- ServerScript: NPCs that players can walk through but still interact with

local CollisionGroupManager = require(path.to.CollisionGroupManager)
local CollectionService = game:GetService("CollectionService")

local NPCNoClip = {}

--- Sets up the NPC no-clip system using CollectionService tags.
function NPCNoClip.init()
    -- Register groups
    CollisionGroupManager.register("NPCs")
    CollisionGroupManager.register("Players")

    -- NPCs don't collide with players
    CollisionGroupManager.setCollidable("NPCs", "Players", false)

    -- NPCs still collide with world geometry (Default group)
    -- NPCs still collide with each other
    CollisionGroupManager.setCollidable("NPCs", "NPCs", true)

    -- Auto-assign tagged NPCs
    local function setupNPC(npc: Instance)
        if npc:IsA("Model") then
            CollisionGroupManager.assignModel(npc, "NPCs")
        end
    end

    for _, npc in CollectionService:GetTagged("NPC") do
        setupNPC(npc)
    end

    CollectionService:GetInstanceAddedSignal("NPC"):Connect(setupNPC)
end

return NPCNoClip
```

---

## 5. Vehicle Collision Layer

```luau
--!strict
-- ServerScript: Vehicle collision setup (passengers don't collide with vehicle)

local CollisionGroupManager = require(path.to.CollisionGroupManager)

local VehicleCollision = {}

function VehicleCollision.init()
    CollisionGroupManager.register("Vehicles")
    CollisionGroupManager.register("VehiclePassengers")

    -- Passengers don't collide with the vehicle they're in
    CollisionGroupManager.setCollidable("VehiclePassengers", "Vehicles", false)

    -- Passengers don't collide with each other inside vehicle
    CollisionGroupManager.setCollidable("VehiclePassengers", "VehiclePassengers", false)

    -- Vehicles collide with world and other vehicles
    CollisionGroupManager.setCollidable("Vehicles", "Vehicles", true)
end

--- Call when a player enters a vehicle.
function VehicleCollision.onPlayerEnterVehicle(character: Model, vehicleModel: Model)
    CollisionGroupManager.assignModel(character, "VehiclePassengers")
    CollisionGroupManager.assignModel(vehicleModel, "Vehicles")
end

--- Call when a player exits a vehicle.
function VehicleCollision.onPlayerExitVehicle(character: Model)
    CollisionGroupManager.assignModel(character, "Players")
end

return VehicleCollision
```

---

## 6. Raycast Collision Filtering

```luau
--!strict
-- ModuleScript: Raycast with collision group awareness

local RaycastFiltering = {}

--- Performs a raycast that respects a specific collision group.
function RaycastFiltering.castWithGroup(origin: Vector3, direction: Vector3, collisionGroup: string, filterInstances: { Instance }?): RaycastResult?
    local params = RaycastParams.new()
    params.CollisionGroup = collisionGroup
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = filterInstances or {}
    params.IgnoreWater = true

    return workspace:Raycast(origin, direction, params)
end

--- Bullet raycast that uses team-based collision filtering.
function RaycastFiltering.bulletRaycast(origin: Vector3, direction: Vector3, shooterTeamId: number): RaycastResult?
    local groupName = if shooterTeamId == 1 then "Bullets_Team1" else "Bullets_Team2"
    return RaycastFiltering.castWithGroup(origin, direction, groupName)
end

return RaycastFiltering
```

---

## Collision Group Summary Table

| Group | Collides With Players | Collides With NPCs | Collides With World |
|---|---|---|---|
| Players | No (configurable) | No | Yes |
| NPCs | No | Yes | Yes |
| Bullets | No (same team) | Yes | Yes |
| Loot | No | No | Yes |
| Ragdoll | No | No | Yes |
| Triggers | No | No | No |
| Vehicles | Yes | Yes | Yes |

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

- `groups` (table) - List of collision group names to register
- `rules` (table) - Array of {group1, group2, collide} collision rules
- `team_id` (number) - Team identifier for team-based collision
- `npc_tag` (string) - CollectionService tag for NPCs (default: "NPC")
- `player_group` (string) - Collision group name for players (default: "Players")
- `npc_group` (string) - Collision group name for NPCs (default: "NPCs")
- `bullet_group` (string) - Collision group name for bullets (default: "Bullets")
