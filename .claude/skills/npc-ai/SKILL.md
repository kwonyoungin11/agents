---
name: npc-ai
description: |
  Roblox NPC AI 시스템 (NPC AI System) - 상태 머신 (대기/순찰/추적/공격/도주/사망), PathfindingService, 감지 반경, 어그로 테이블, 순찰 경로, 보스 페이즈.
  State machine AI (Idle/Patrol/Chase/Attack/Flee/Dead), PathfindingService navigation, detection radius,
  aggro table management, patrol waypoints, boss phase transitions. 로블록스 Luau NPC AI 구현.
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
effort: high
---

# NPC AI System for Roblox (Luau)

Full NPC AI with finite state machine, pathfinding, aggro tables, patrol routes, detection, and boss phases.

## Architecture Overview

```
NPCAISystem (Server)
├── StateMachine (state transitions, update loop)
├── PathfindingController (PathfindingService wrapper)
├── DetectionSystem (radius checks, line of sight)
├── AggroManager (threat table, target priority)
├── PatrolManager (waypoint routes, timing)
├── BossPhaseManager (HP thresholds, phase abilities)
└── NPCSpawner (spawn/despawn, respawn timers)
```

## State Machine

```luau
--!strict
-- ServerScriptService/AI/StateMachine.luau

export type StateId = "Idle" | "Patrol" | "Chase" | "Attack" | "Flee" | "Dead" | "Return" | "BossPhase" | string

export type StateCallbacks = {
	Enter: ((npc: any) -> ())?,
	Update: ((npc: any, dt: number) -> StateId?)?,  -- return new state or nil to stay
	Exit: ((npc: any) -> ())?,
}

local StateMachine = {}
StateMachine.__index = StateMachine

function StateMachine.new()
	local self = setmetatable({}, StateMachine)
	self._states = {} :: { [StateId]: StateCallbacks }
	self._currentState = "Idle" :: StateId
	self._previousState = "Idle" :: StateId
	self._stateTime = 0
	return self
end

function StateMachine:AddState(stateId: StateId, callbacks: StateCallbacks)
	self._states[stateId] = callbacks
end

function StateMachine:SetState(npc: any, newState: StateId)
	if newState == self._currentState then return end

	-- Exit current state
	local currentCallbacks = self._states[self._currentState]
	if currentCallbacks and currentCallbacks.Exit then
		currentCallbacks.Exit(npc)
	end

	self._previousState = self._currentState
	self._currentState = newState
	self._stateTime = 0

	-- Enter new state
	local newCallbacks = self._states[newState]
	if newCallbacks and newCallbacks.Enter then
		newCallbacks.Enter(npc)
	end
end

function StateMachine:Update(npc: any, dt: number)
	self._stateTime += dt

	local callbacks = self._states[self._currentState]
	if callbacks and callbacks.Update then
		local nextState = callbacks.Update(npc, dt)
		if nextState then
			self:SetState(npc, nextState)
		end
	end
end

function StateMachine:GetCurrentState(): StateId
	return self._currentState
end

function StateMachine:GetStateTime(): number
	return self._stateTime
end

function StateMachine:GetPreviousState(): StateId
	return self._previousState
end

return StateMachine
```

## Detection System

```luau
--!strict
-- ServerScriptService/AI/DetectionSystem.luau

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

export type DetectionConfig = {
	SightRange: number,        -- studs
	SightAngle: number,        -- degrees (half-angle of vision cone)
	HearingRange: number,      -- studs (360-degree detection)
	AttackRange: number,       -- studs
	LoseTargetRange: number,   -- studs (disengage distance)
	LineOfSight: boolean,      -- require unobstructed view
}

local DetectionSystem = {}

local DEFAULT_CONFIG: DetectionConfig = {
	SightRange = 40,
	SightAngle = 60,
	HearingRange = 15,
	AttackRange = 5,
	LoseTargetRange = 60,
	LineOfSight = true,
}

function DetectionSystem.GetNearbyPlayers(position: Vector3, radius: number): { Player }
	local nearby: { Player } = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if not character then continue end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then continue end
		local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not rootPart then continue end

		local distance = (rootPart.Position - position).Magnitude
		if distance <= radius then
			table.insert(nearby, player)
		end
	end
	return nearby
end

function DetectionSystem.CanSeeTarget(
	npcRoot: BasePart,
	targetRoot: BasePart,
	config: DetectionConfig?
): boolean
	local cfg = config or DEFAULT_CONFIG
	local direction = targetRoot.Position - npcRoot.Position
	local distance = direction.Magnitude

	-- Range check
	if distance > cfg.SightRange then return false end

	-- Angle check (vision cone)
	local lookDir = npcRoot.CFrame.LookVector
	local toTarget = direction.Unit
	local angle = math.deg(math.acos(math.clamp(lookDir:Dot(toTarget), -1, 1)))
	if angle > cfg.SightAngle then return false end

	-- Line of sight check
	if cfg.LineOfSight then
		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		rayParams.FilterDescendantsInstances = { npcRoot.Parent :: Instance }

		local result = Workspace:Raycast(npcRoot.Position, direction, rayParams)
		if result then
			-- Check if the ray hit the target or something else
			local hitModel = result.Instance:FindFirstAncestorOfClass("Model")
			if hitModel ~= targetRoot.Parent then
				return false  -- blocked by obstacle
			end
		end
	end

	return true
end

function DetectionSystem.CanHearTarget(
	npcPosition: Vector3,
	targetPosition: Vector3,
	config: DetectionConfig?
): boolean
	local cfg = config or DEFAULT_CONFIG
	local distance = (targetPosition - npcPosition).Magnitude
	return distance <= cfg.HearingRange
end

function DetectionSystem.IsInAttackRange(
	npcPosition: Vector3,
	targetPosition: Vector3,
	config: DetectionConfig?
): boolean
	local cfg = config or DEFAULT_CONFIG
	local distance = (targetPosition - npcPosition).Magnitude
	return distance <= cfg.AttackRange
end

function DetectionSystem.ShouldLoseTarget(
	npcPosition: Vector3,
	targetPosition: Vector3,
	config: DetectionConfig?
): boolean
	local cfg = config or DEFAULT_CONFIG
	local distance = (targetPosition - npcPosition).Magnitude
	return distance > cfg.LoseTargetRange
end

-- Find best target based on distance and angle
function DetectionSystem.FindBestTarget(
	npcRoot: BasePart,
	config: DetectionConfig?
): (Player?, number?)
	local cfg = config or DEFAULT_CONFIG
	local position = npcRoot.Position
	local candidates = DetectionSystem.GetNearbyPlayers(position, math.max(cfg.SightRange, cfg.HearingRange))

	local bestTarget: Player? = nil
	local bestScore = math.huge

	for _, player in candidates do
		local character = player.Character
		if not character then continue end
		local targetRoot = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not targetRoot then continue end

		local distance = (targetRoot.Position - position).Magnitude

		-- Can we detect them?
		local detected = false
		if DetectionSystem.CanSeeTarget(npcRoot, targetRoot, cfg) then
			detected = true
		elseif DetectionSystem.CanHearTarget(position, targetRoot.Position, cfg) then
			detected = true
		end

		if detected and distance < bestScore then
			bestTarget = player
			bestScore = distance
		end
	end

	return bestTarget, bestScore
end

return DetectionSystem
```

## Aggro Table

```luau
--!strict
-- ServerScriptService/AI/AggroManager.luau

export type AggroEntry = {
	Player: Player,
	Threat: number,
	LastDamageTime: number,
}

local AggroManager = {}
AggroManager.__index = AggroManager

function AggroManager.new()
	local self = setmetatable({}, AggroManager)
	self._aggroTable = {} :: { [Player]: AggroEntry }
	self._decayRate = 5         -- threat decay per second
	self._decayDelay = 10       -- seconds before decay starts
	return self
end

function AggroManager:AddThreat(player: Player, amount: number)
	local entry = self._aggroTable[player]
	if entry then
		entry.Threat += amount
		entry.LastDamageTime = tick()
	else
		self._aggroTable[player] = {
			Player = player,
			Threat = amount,
			LastDamageTime = tick(),
		}
	end
end

function AggroManager:RemoveThreat(player: Player)
	self._aggroTable[player] = nil
end

function AggroManager:GetHighestThreat(): (Player?, number)
	local highestPlayer: Player? = nil
	local highestThreat = 0

	for _, entry in self._aggroTable do
		-- Validate player is still valid
		local character = entry.Player.Character
		if not character then continue end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then continue end

		if entry.Threat > highestThreat then
			highestPlayer = entry.Player
			highestThreat = entry.Threat
		end
	end

	return highestPlayer, highestThreat
end

function AggroManager:Update(dt: number)
	local now = tick()
	local toRemove: { Player } = {}

	for player, entry in self._aggroTable do
		-- Validate player
		local character = player.Character
		if not character or not character:FindFirstChildOfClass("Humanoid") then
			table.insert(toRemove, player)
			continue
		end

		-- Decay threat after delay
		if (now - entry.LastDamageTime) > self._decayDelay then
			entry.Threat -= self._decayRate * dt
			if entry.Threat <= 0 then
				table.insert(toRemove, player)
			end
		end
	end

	for _, player in toRemove do
		self._aggroTable[player] = nil
	end
end

function AggroManager:HasAggro(): boolean
	for _, entry in self._aggroTable do
		if entry.Threat > 0 then return true end
	end
	return false
end

function AggroManager:Clear()
	table.clear(self._aggroTable)
end

function AggroManager:GetThreatList(): { AggroEntry }
	local list: { AggroEntry } = {}
	for _, entry in self._aggroTable do
		table.insert(list, entry)
	end
	table.sort(list, function(a, b) return a.Threat > b.Threat end)
	return list
end

return AggroManager
```

## NPC Controller (Combines All Systems)

```luau
--!strict
-- ServerScriptService/AI/NPCController.luau

local PathfindingService = game:GetService("PathfindingService")
local RunService = game:GetService("RunService")

local StateMachine = require(script.Parent.StateMachine)
local DetectionSystem = require(script.Parent.DetectionSystem)
local AggroManager = require(script.Parent.AggroManager)

export type NPCConfig = {
	Model: Model,
	SpawnPosition: Vector3,
	DetectionConfig: DetectionSystem.DetectionConfig?,
	MaxHealth: number,
	Damage: number,
	AttackSpeed: number,        -- attacks per second
	MoveSpeed: number,          -- walkspeed
	FleeHealthPercent: number?, -- flee below this % HP
	PatrolWaypoints: { Vector3 }?,
	PatrolWaitTime: number?,    -- seconds at each waypoint
	LeashRange: number?,        -- max distance from spawn before returning
	IsBoss: boolean?,
	BossPhases: { { HPPercent: number, Callback: (any) -> () } }?,
	RespawnTime: number?,       -- nil = no respawn
	LootTable: { { ItemId: string, Chance: number, MinQty: number?, MaxQty: number? } }?,
}

export type NPCInstance = {
	Config: NPCConfig,
	Model: Model,
	Humanoid: Humanoid,
	RootPart: BasePart,
	StateMachine: typeof(StateMachine.new()),
	AggroManager: typeof(AggroManager.new()),
	Target: Player?,
	CurrentWaypoint: number,
	LastAttackTime: number,
	IsDead: boolean,
	CurrentBossPhase: number,
	Path: Path?,
}

local NPCController = {}
NPCController.__index = NPCController

function NPCController.new()
	local self = setmetatable({}, NPCController)
	self._npcs = {} :: { NPCInstance }
	self._running = false
	return self
end

function NPCController:CreateNPC(config: NPCConfig): NPCInstance?
	local model = config.Model
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local rootPart = model:FindFirstChild("HumanoidRootPart") :: BasePart?

	if not humanoid or not rootPart then
		warn("[NPC AI] Model missing Humanoid or HumanoidRootPart")
		return nil
	end

	humanoid.MaxHealth = config.MaxHealth
	humanoid.Health = config.MaxHealth
	humanoid.WalkSpeed = config.MoveSpeed

	local sm = StateMachine.new()
	local aggro = AggroManager.new()

	local npc: NPCInstance = {
		Config = config,
		Model = model,
		Humanoid = humanoid,
		RootPart = rootPart,
		StateMachine = sm,
		AggroManager = aggro,
		Target = nil,
		CurrentWaypoint = 1,
		LastAttackTime = 0,
		IsDead = false,
		CurrentBossPhase = 0,
		Path = nil,
	}

	-- Register states
	self:_setupStates(npc)

	-- Listen for damage
	humanoid.HealthChanged:Connect(function(newHealth)
		if npc.IsDead then return end

		if newHealth <= 0 then
			npc.IsDead = true
			sm:SetState(npc, "Dead")
		else
			-- Check flee threshold
			local fleePercent = config.FleeHealthPercent or 0
			if fleePercent > 0 and (newHealth / config.MaxHealth) <= fleePercent then
				if sm:GetCurrentState() ~= "Flee" and sm:GetCurrentState() ~= "Dead" then
					sm:SetState(npc, "Flee")
				end
			end

			-- Check boss phases
			if config.IsBoss and config.BossPhases then
				local hpPercent = newHealth / config.MaxHealth
				for i, phase in config.BossPhases do
					if i > npc.CurrentBossPhase and hpPercent <= phase.HPPercent then
						npc.CurrentBossPhase = i
						phase.Callback(npc)
						break
					end
				end
			end
		end
	end)

	table.insert(self._npcs, npc)
	return npc
end

---------------------------------------------------------------------
-- State Definitions
---------------------------------------------------------------------
function NPCController:_setupStates(npc: NPCInstance)
	local sm = npc.StateMachine
	local config = npc.Config
	local detection = config.DetectionConfig

	-- IDLE state
	sm:AddState("Idle", {
		Enter = function(_npc)
			npc.Humanoid.WalkSpeed = 0
		end,
		Update = function(_npc, _dt): StateMachine.StateId?
			-- Check for targets
			local target = DetectionSystem.FindBestTarget(npc.RootPart, detection)
			if target then
				npc.Target = target
				npc.AggroManager:AddThreat(target, 10)
				return "Chase"
			end

			-- Switch to patrol if waypoints exist
			if config.PatrolWaypoints and #config.PatrolWaypoints > 0 then
				if sm:GetStateTime() > (config.PatrolWaitTime or 3) then
					return "Patrol"
				end
			end

			return nil
		end,
	})

	-- PATROL state
	sm:AddState("Patrol", {
		Enter = function(_npc)
			npc.Humanoid.WalkSpeed = config.MoveSpeed * 0.5  -- walk slower on patrol
		end,
		Update = function(_npc, _dt): StateMachine.StateId?
			-- Check for targets
			local target = DetectionSystem.FindBestTarget(npc.RootPart, detection)
			if target then
				npc.Target = target
				npc.AggroManager:AddThreat(target, 10)
				return "Chase"
			end

			-- Move to next waypoint
			local waypoints = config.PatrolWaypoints
			if not waypoints or #waypoints == 0 then return "Idle" end

			local targetPos = waypoints[npc.CurrentWaypoint]
			local distance = (npc.RootPart.Position - targetPos).Magnitude

			if distance < 3 then
				npc.CurrentWaypoint = (npc.CurrentWaypoint % #waypoints) + 1
				return "Idle"  -- pause at waypoint
			else
				npc.Humanoid:MoveTo(targetPos)
			end

			return nil
		end,
	})

	-- CHASE state
	sm:AddState("Chase", {
		Enter = function(_npc)
			npc.Humanoid.WalkSpeed = config.MoveSpeed
		end,
		Update = function(_npc, dt): StateMachine.StateId?
			npc.AggroManager:Update(dt)

			-- Get highest threat target
			local highTarget = npc.AggroManager:GetHighestThreat()
			if highTarget then
				npc.Target = highTarget
			end

			if not npc.Target then return "Return" end

			local targetChar = npc.Target.Character
			if not targetChar then return "Return" end
			local targetRoot = targetChar:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not targetRoot then return "Return" end

			local targetHumanoid = targetChar:FindFirstChildOfClass("Humanoid")
			if not targetHumanoid or targetHumanoid.Health <= 0 then
				npc.AggroManager:RemoveThreat(npc.Target)
				npc.Target = nil
				return "Return"
			end

			-- Leash check
			local distFromSpawn = (npc.RootPart.Position - config.SpawnPosition).Magnitude
			if config.LeashRange and distFromSpawn > config.LeashRange then
				npc.AggroManager:Clear()
				npc.Target = nil
				return "Return"
			end

			-- Lose target check
			if DetectionSystem.ShouldLoseTarget(npc.RootPart.Position, targetRoot.Position, detection) then
				npc.AggroManager:RemoveThreat(npc.Target)
				npc.Target = nil
				return "Return"
			end

			-- Attack range check
			if DetectionSystem.IsInAttackRange(npc.RootPart.Position, targetRoot.Position, detection) then
				return "Attack"
			end

			-- Navigate to target using PathfindingService
			self:_navigateToTarget(npc, targetRoot.Position)

			return nil
		end,
	})

	-- ATTACK state
	sm:AddState("Attack", {
		Enter = function(_npc)
			npc.Humanoid.WalkSpeed = 0
		end,
		Update = function(_npc, _dt): StateMachine.StateId?
			if not npc.Target then return "Return" end

			local targetChar = npc.Target.Character
			if not targetChar then return "Return" end
			local targetRoot = targetChar:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not targetRoot then return "Return" end

			local targetHumanoid = targetChar:FindFirstChildOfClass("Humanoid")
			if not targetHumanoid or targetHumanoid.Health <= 0 then
				npc.AggroManager:RemoveThreat(npc.Target)
				npc.Target = nil
				return "Return"
			end

			-- Check still in attack range
			if not DetectionSystem.IsInAttackRange(npc.RootPart.Position, targetRoot.Position, detection) then
				return "Chase"
			end

			-- Face target
			local direction = (targetRoot.Position - npc.RootPart.Position) * Vector3.new(1, 0, 1)
			if direction.Magnitude > 0.1 then
				npc.RootPart.CFrame = CFrame.lookAt(npc.RootPart.Position, npc.RootPart.Position + direction)
			end

			-- Attack on cooldown
			local now = tick()
			local cooldown = 1 / config.AttackSpeed
			if (now - npc.LastAttackTime) >= cooldown then
				npc.LastAttackTime = now
				targetHumanoid:TakeDamage(config.Damage)
				npc.AggroManager:AddThreat(npc.Target, config.Damage)
			end

			return nil
		end,
	})

	-- FLEE state
	sm:AddState("Flee", {
		Enter = function(_npc)
			npc.Humanoid.WalkSpeed = config.MoveSpeed * 1.3  -- run faster
		end,
		Update = function(_npc, _dt): StateMachine.StateId?
			if not npc.Target then return "Return" end

			local targetChar = npc.Target.Character
			if not targetChar then return "Return" end
			local targetRoot = targetChar:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not targetRoot then return "Return" end

			-- Run away from target
			local fleeDir = (npc.RootPart.Position - targetRoot.Position).Unit
			local fleePos = npc.RootPart.Position + fleeDir * 20
			npc.Humanoid:MoveTo(fleePos)

			-- Stop fleeing if far enough away
			local distance = (npc.RootPart.Position - targetRoot.Position).Magnitude
			if distance > (detection and detection.LoseTargetRange or 60) then
				npc.AggroManager:Clear()
				npc.Target = nil
				return "Return"
			end

			return nil
		end,
	})

	-- RETURN state (go back to spawn)
	sm:AddState("Return", {
		Enter = function(_npc)
			npc.Humanoid.WalkSpeed = config.MoveSpeed
			npc.Target = nil
		end,
		Update = function(_npc, _dt): StateMachine.StateId?
			-- Check for new targets while returning
			local target = DetectionSystem.FindBestTarget(npc.RootPart, detection)
			if target then
				npc.Target = target
				npc.AggroManager:AddThreat(target, 10)
				return "Chase"
			end

			local distFromSpawn = (npc.RootPart.Position - config.SpawnPosition).Magnitude
			if distFromSpawn < 3 then
				-- Heal to full when returning home
				npc.Humanoid.Health = npc.Humanoid.MaxHealth
				npc.AggroManager:Clear()
				return "Idle"
			end

			npc.Humanoid:MoveTo(config.SpawnPosition)
			return nil
		end,
	})

	-- DEAD state
	sm:AddState("Dead", {
		Enter = function(_npc)
			npc.Humanoid.WalkSpeed = 0
			npc.IsDead = true
			npc.AggroManager:Clear()

			-- Drop loot
			if config.LootTable then
				self:_dropLoot(npc)
			end

			-- Ragdoll / death animation
			task.delay(3, function()
				if config.RespawnTime then
					npc.Model.Parent = nil  -- hide model
					task.delay(config.RespawnTime, function()
						self:_respawnNPC(npc)
					end)
				else
					npc.Model:Destroy()
				end
			end)
		end,
	})
end

---------------------------------------------------------------------
-- Pathfinding
---------------------------------------------------------------------
function NPCController:_navigateToTarget(npc: NPCInstance, targetPosition: Vector3)
	local path = PathfindingService:CreatePath({
		AgentRadius = 2,
		AgentHeight = 5,
		AgentCanJump = true,
		AgentCanClimb = false,
		WaypointSpacing = 4,
	})

	local success, _ = pcall(function()
		path:ComputeAsync(npc.RootPart.Position, targetPosition)
	end)

	if success and path.Status == Enum.PathStatus.Success then
		local waypoints = path:GetWaypoints()
		-- Move to next waypoint (skip first as it's current position)
		if #waypoints >= 2 then
			local nextWP = waypoints[2]
			if nextWP.Action == Enum.PathWaypointAction.Jump then
				npc.Humanoid.Jump = true
			end
			npc.Humanoid:MoveTo(nextWP.Position)
		end
	else
		-- Fallback: move directly
		npc.Humanoid:MoveTo(targetPosition)
	end
end

---------------------------------------------------------------------
-- Loot Drops
---------------------------------------------------------------------
function NPCController:_dropLoot(npc: NPCInstance)
	if not npc.Config.LootTable then return end

	local drops: { { ItemId: string, Quantity: number } } = {}
	for _, loot in npc.Config.LootTable do
		if math.random() <= loot.Chance then
			local qty = math.random(loot.MinQty or 1, loot.MaxQty or 1)
			table.insert(drops, { ItemId = loot.ItemId, Quantity = qty })
		end
	end

	-- Distribute to aggro table (top threat gets loot)
	local topThreat = npc.AggroManager:GetHighestThreat()
	if topThreat and #drops > 0 then
		-- Fire event for inventory system to handle
		-- (connect externally)
		if self._onLootDrop then
			self._onLootDrop(topThreat, drops, npc.RootPart.Position)
		end
	end
end

---------------------------------------------------------------------
-- Respawn
---------------------------------------------------------------------
function NPCController:_respawnNPC(npc: NPCInstance)
	local model = npc.Config.Model
	if not model then return end

	-- Reset model
	model.Parent = workspace
	local rootPart = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if rootPart then
		rootPart.CFrame = CFrame.new(npc.Config.SpawnPosition)
	end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Health = humanoid.MaxHealth
	end

	npc.IsDead = false
	npc.CurrentBossPhase = 0
	npc.AggroManager:Clear()
	npc.Target = nil
	npc.StateMachine:SetState(npc, "Idle")
end

---------------------------------------------------------------------
-- Update Loop
---------------------------------------------------------------------
function NPCController:Start()
	if self._running then return end
	self._running = true

	self._heartbeat = RunService.Heartbeat:Connect(function(dt)
		for _, npc in self._npcs do
			if not npc.IsDead then
				npc.StateMachine:Update(npc, dt)
			end
		end
	end)
end

function NPCController:Stop()
	self._running = false
	if self._heartbeat then
		self._heartbeat:Disconnect()
		self._heartbeat = nil
	end
end

-- Callback when loot drops
function NPCController:OnLootDrop(callback: (Player, { { ItemId: string, Quantity: number } }, Vector3) -> ())
	self._onLootDrop = callback
end

-- Add threat from external source (e.g., combat system)
function NPCController:AddThreatToNPC(npc: NPCInstance, player: Player, amount: number)
	npc.AggroManager:AddThreat(player, amount)
	if not npc.Target and npc.StateMachine:GetCurrentState() ~= "Dead" then
		npc.Target = player
		npc.StateMachine:SetState(npc, "Chase")
	end
end

return NPCController
```

## Usage Example

```luau
-- Server setup:
local NPCController = require(ServerScriptService.AI.NPCController)
local controller = NPCController.new()

-- Create a goblin NPC:
local goblinModel = workspace.Enemies.Goblin
local goblin = controller:CreateNPC({
    Model = goblinModel,
    SpawnPosition = goblinModel.HumanoidRootPart.Position,
    DetectionConfig = {
        SightRange = 30,
        SightAngle = 60,
        HearingRange = 15,
        AttackRange = 5,
        LoseTargetRange = 50,
        LineOfSight = true,
    },
    MaxHealth = 100,
    Damage = 15,
    AttackSpeed = 1.2,
    MoveSpeed = 14,
    FleeHealthPercent = 0.15,
    PatrolWaypoints = { Vector3.new(0,0,0), Vector3.new(20,0,0), Vector3.new(20,0,20) },
    PatrolWaitTime = 3,
    LeashRange = 60,
    RespawnTime = 30,
    LootTable = {
        { ItemId = "goblin_token", Chance = 0.8, MinQty = 1, MaxQty = 2 },
        { ItemId = "health_potion", Chance = 0.3 },
    },
})

-- Create a boss:
local bossModel = workspace.Enemies.DragonBoss
local boss = controller:CreateNPC({
    Model = bossModel,
    SpawnPosition = bossModel.HumanoidRootPart.Position,
    MaxHealth = 5000,
    Damage = 50,
    AttackSpeed = 0.8,
    MoveSpeed = 10,
    IsBoss = true,
    LeashRange = 100,
    BossPhases = {
        { HPPercent = 0.75, Callback = function(npc)
            print("Boss Phase 2: Enrage!")
            npc.Config.Damage = 70
            npc.Config.AttackSpeed = 1.2
        end },
        { HPPercent = 0.25, Callback = function(npc)
            print("Boss Phase 3: Desperate!")
            npc.Config.Damage = 100
            npc.Humanoid.WalkSpeed = 18
        end },
    },
    RespawnTime = 300,
})

-- When player deals damage to NPC externally:
controller:AddThreatToNPC(goblin, player, damageDealt)

-- Start AI loop:
controller:Start()
```

## 

---

## Learned Lessons

<!-- skill-evolve 에이전트가 자동으로 교훈 추가 -->

## Self-Evolution Protocol

이 스킬에서 에러가 발생하면:
1. 에러의 근본 원인을 분석한다
2. Learned Lessons 섹션에 교훈을 추가한다
3. 규칙화하여 반복 방지
4. SessionManager에 기록

```lua
local SM = require(game.ServerStorage._RobloxEngine.SessionManager)
SM.logAction("SKILL_ERROR", "[스킬명] | [에러]")
SM.logAction("SKILL_LEARNED", "[스킬명] | [교훈]")
```

**매 작업 시 Learned Lessons를 먼저 읽고 위반하지 않는지 확인.**

$ARGUMENTS

When the user asks to implement NPC AI, ask or infer:

- `$AI_STATES` - States to include: {"Idle", "Patrol", "Chase", "Attack", "Flee", "Dead", "Return"}
- `$SIGHT_RANGE` - Detection sight range in studs: 40
- `$SIGHT_ANGLE` - Vision cone half-angle in degrees: 60
- `$HEARING_RANGE` - Hearing range in studs: 15
- `$ATTACK_RANGE` - Melee attack range: 5
- `$ENABLE_LINE_OF_SIGHT` - Require unobstructed view: true/false
- `$ENABLE_AGGRO_TABLE` - Threat/aggro management: true/false
- `$ENABLE_PATROL` - Patrol waypoint routes: true/false
- `$PATROL_WAIT_TIME` - Seconds paused at each waypoint: 3
- `$ENABLE_FLEE` - Flee at low HP: true/false
- `$FLEE_HP_PERCENT` - HP threshold to flee: 0.15 (15%)
- `$ENABLE_LEASH` - Return to spawn if too far: true/false
- `$LEASH_RANGE` - Maximum distance from spawn: 60
- `$ENABLE_BOSS_PHASES` - Boss phase transitions: true/false
- `$BOSS_PHASE_COUNT` - Number of boss phases: 3
- `$ENABLE_PATHFINDING` - Use PathfindingService: true/false
- `$ENABLE_LOOT` - Drop loot on death: true/false
- `$RESPAWN_TIME` - Seconds to respawn: 30 (nil = no respawn)
