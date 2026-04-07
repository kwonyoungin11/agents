---
name: spawn
description: |
  Roblox 스폰 시스템 (Spawn System) - 스폰 포인트, 리스폰, 사망 처리, 스폰 선택, 팀 스폰, 안전 지역.
  Spawn points and respawn system with death handling, spawn point selection strategies,
  team-based spawns, safe zone protection, spawn invulnerability. 로블록스 Luau 스폰 시스템 구현.
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
effort: high
---

# Spawn System for Roblox (Luau)

Complete spawn/respawn system with configurable spawn points, death handling, team spawns, safe zones, and spawn selection strategies.

## Architecture Overview

```
SpawnSystem (Server)
├── SpawnPointManager (register, configure points)
├── RespawnManager (death handling, timers, UI)
├── SpawnSelector (strategy-based selection)
├── SafeZoneManager (PvP protection areas)
├── TeamSpawnManager (team-based spawn logic)
└── SpawnEvents (remote events)

SpawnClient (Client)
├── DeathUI (respawn timer, spawn selection)
├── SafeZoneIndicator (HUD overlay)
└── SpawnEffects (visual effects on spawn)
```

## Spawn Point Configuration

```luau
--!strict
-- ReplicatedStorage/Data/SpawnConfig.luau

export type SpawnStrategy = "Default" | "Random" | "Nearest" | "FurthestFromEnemies" | "PlayerChoice" | "Sequential"

export type SpawnPointConfig = {
	Id: string,
	Name: string,
	Position: Vector3,
	Rotation: CFrame?,          -- spawn facing direction
	Team: string?,               -- team name, nil = any team
	Priority: number?,           -- higher = preferred (for Default strategy)
	Enabled: boolean?,           -- can be disabled dynamically
	RequiredLevel: number?,      -- minimum level to use this spawn
	MaxCapacity: number?,        -- max concurrent spawns at this point
	SafeZoneRadius: number?,     -- studs of PvP protection around spawn
	SpawnProtectionTime: number?, -- seconds of invulnerability after spawn
	Tags: { string }?,           -- "starter", "checkpoint", "boss", etc.
}

export type RespawnConfig = {
	RespawnDelay: number,        -- seconds before respawn
	EnablePlayerChoice: boolean, -- let player choose spawn point
	ChoiceTimeout: number?,      -- auto-spawn after this many seconds
	PenaltyOnDeath: {
		XPLoss: number?,         -- percentage of XP lost: 0.05 = 5%
		CurrencyLoss: number?,   -- percentage of currency lost
		DropItems: boolean?,     -- drop items on death
	}?,
	SpawnInvulnerability: number?, -- seconds of invuln after respawn
	EnableRevive: boolean?,      -- allow other players to revive
	ReviveTime: number?,         -- seconds to revive
	MaxDeathsBeforePenalty: number?, -- deaths before penalty kicks in
}

local SpawnConfig = {
	DefaultStrategy = "Default" :: SpawnStrategy,
	RespawnDelay = 5,
	EnablePlayerChoice = false,
	ChoiceTimeout = 15,
	SpawnInvulnerability = 3,
	EnableRevive = false,
	ReviveTime = 5,
}

return SpawnConfig
```

## Spawn Point Manager

```luau
--!strict
-- ServerScriptService/Spawn/SpawnPointManager.luau

local SpawnConfig = require(game.ReplicatedStorage.Data.SpawnConfig)

local SpawnPointManager = {}
SpawnPointManager.__index = SpawnPointManager

function SpawnPointManager.new()
	local self = setmetatable({}, SpawnPointManager)
	self._spawnPoints = {} :: { [string]: SpawnConfig.SpawnPointConfig }
	self._spawnCounts = {} :: { [string]: number }  -- current spawn count per point
	return self
end

function SpawnPointManager:RegisterSpawnPoint(config: SpawnConfig.SpawnPointConfig)
	assert(config.Id and config.Id ~= "", "Spawn point must have an Id")
	self._spawnPoints[config.Id] = config
	self._spawnCounts[config.Id] = 0
end

-- Auto-detect SpawnLocation instances in workspace
function SpawnPointManager:AutoRegisterFromWorkspace()
	for _, instance in workspace:GetDescendants() do
		if instance:IsA("SpawnLocation") then
			self:RegisterSpawnPoint({
				Id = instance.Name .. "_" .. tostring(instance:GetFullName():len()),
				Name = instance.Name,
				Position = instance.Position + Vector3.new(0, 3, 0), -- above spawn pad
				Rotation = instance.CFrame,
				Team = if instance.TeamColor ~= BrickColor.new("Medium stone grey")
					then instance.TeamColor.Name else nil,
				Enabled = instance.Enabled,
				Priority = 0,
			})
		end
	end
end

function SpawnPointManager:GetSpawnPoint(id: string): SpawnConfig.SpawnPointConfig?
	return self._spawnPoints[id]
end

function SpawnPointManager:SetEnabled(id: string, enabled: boolean)
	local sp = self._spawnPoints[id]
	if sp then
		sp.Enabled = enabled
	end
end

function SpawnPointManager:GetAvailableSpawns(team: string?, level: number?, tags: { string }?): { SpawnConfig.SpawnPointConfig }
	local available: { SpawnConfig.SpawnPointConfig } = {}

	for _, sp in self._spawnPoints do
		-- Enabled check
		if sp.Enabled == false then continue end

		-- Team check
		if sp.Team and team and sp.Team ~= team then continue end

		-- Level check
		if sp.RequiredLevel and level and level < sp.RequiredLevel then continue end

		-- Capacity check
		if sp.MaxCapacity then
			local count = self._spawnCounts[sp.Id] or 0
			if count >= sp.MaxCapacity then continue end
		end

		-- Tag check
		if tags then
			local hasTag = false
			if sp.Tags then
				for _, requiredTag in tags do
					for _, spTag in sp.Tags do
						if spTag == requiredTag then
							hasTag = true
							break
						end
					end
					if hasTag then break end
				end
			end
			if not hasTag then continue end
		end

		table.insert(available, sp)
	end

	return available
end

function SpawnPointManager:IncrementCount(id: string)
	self._spawnCounts[id] = (self._spawnCounts[id] or 0) + 1
end

function SpawnPointManager:DecrementCount(id: string)
	self._spawnCounts[id] = math.max(0, (self._spawnCounts[id] or 0) - 1)
end

return SpawnPointManager
```

## Spawn Selector (Strategy-Based)

```luau
--!strict
-- ServerScriptService/Spawn/SpawnSelector.luau

local Players = game:GetService("Players")
local SpawnConfig = require(game.ReplicatedStorage.Data.SpawnConfig)

local SpawnSelector = {}

-- Default: highest priority spawn
function SpawnSelector.Default(
	spawns: { SpawnConfig.SpawnPointConfig },
	_player: Player
): SpawnConfig.SpawnPointConfig?
	if #spawns == 0 then return nil end

	table.sort(spawns, function(a, b)
		return (a.Priority or 0) > (b.Priority or 0)
	end)

	return spawns[1]
end

-- Random: pick any available spawn
function SpawnSelector.Random(
	spawns: { SpawnConfig.SpawnPointConfig },
	_player: Player
): SpawnConfig.SpawnPointConfig?
	if #spawns == 0 then return nil end
	return spawns[math.random(1, #spawns)]
end

-- Nearest: closest to player's death position
function SpawnSelector.Nearest(
	spawns: { SpawnConfig.SpawnPointConfig },
	player: Player,
	deathPosition: Vector3?
): SpawnConfig.SpawnPointConfig?
	if #spawns == 0 then return nil end

	local refPos = deathPosition
	if not refPos then
		local character = player.Character
		if character then
			local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if rootPart then
				refPos = rootPart.Position
			end
		end
	end

	if not refPos then return spawns[1] end

	local closest: SpawnConfig.SpawnPointConfig? = nil
	local closestDist = math.huge

	for _, sp in spawns do
		local dist = (sp.Position - refPos).Magnitude
		if dist < closestDist then
			closestDist = dist
			closest = sp
		end
	end

	return closest
end

-- Furthest from enemies: maximize distance from enemy team
function SpawnSelector.FurthestFromEnemies(
	spawns: { SpawnConfig.SpawnPointConfig },
	player: Player
): SpawnConfig.SpawnPointConfig?
	if #spawns == 0 then return nil end

	local playerTeam = ""
	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		local teamValue = leaderstats:FindFirstChild("Team")
		if teamValue and teamValue:IsA("StringValue") then
			playerTeam = teamValue.Value
		end
	end

	-- Find all enemy positions
	local enemyPositions: { Vector3 } = {}
	for _, other in Players:GetPlayers() do
		if other == player then continue end
		local otherTeam = ""
		local otherStats = other:FindFirstChild("leaderstats")
		if otherStats then
			local tv = otherStats:FindFirstChild("Team")
			if tv and tv:IsA("StringValue") then
				otherTeam = tv.Value
			end
		end

		if otherTeam ~= playerTeam then
			local character = other.Character
			if character then
				local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if rootPart then
					table.insert(enemyPositions, rootPart.Position)
				end
			end
		end
	end

	if #enemyPositions == 0 then
		return SpawnSelector.Random(spawns, player)
	end

	local best: SpawnConfig.SpawnPointConfig? = nil
	local bestMinDist = -1

	for _, sp in spawns do
		local minDist = math.huge
		for _, enemyPos in enemyPositions do
			local dist = (sp.Position - enemyPos).Magnitude
			if dist < minDist then
				minDist = dist
			end
		end

		if minDist > bestMinDist then
			bestMinDist = minDist
			best = sp
		end
	end

	return best
end

-- Sequential: rotate through spawns in order
local _sequentialIndex = 0
function SpawnSelector.Sequential(
	spawns: { SpawnConfig.SpawnPointConfig },
	_player: Player
): SpawnConfig.SpawnPointConfig?
	if #spawns == 0 then return nil end
	_sequentialIndex = (_sequentialIndex % #spawns) + 1
	return spawns[_sequentialIndex]
end

-- Main selector that delegates to strategy
function SpawnSelector.Select(
	strategy: SpawnConfig.SpawnStrategy,
	spawns: { SpawnConfig.SpawnPointConfig },
	player: Player,
	deathPosition: Vector3?
): SpawnConfig.SpawnPointConfig?
	if strategy == "Random" then
		return SpawnSelector.Random(spawns, player)
	elseif strategy == "Nearest" then
		return SpawnSelector.Nearest(spawns, player, deathPosition)
	elseif strategy == "FurthestFromEnemies" then
		return SpawnSelector.FurthestFromEnemies(spawns, player)
	elseif strategy == "Sequential" then
		return SpawnSelector.Sequential(spawns, player)
	else
		return SpawnSelector.Default(spawns, player)
	end
end

return SpawnSelector
```

## Respawn Manager

```luau
--!strict
-- ServerScriptService/Spawn/RespawnManager.luau

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SpawnPointManager = require(script.Parent.SpawnPointManager)
local SpawnSelector = require(script.Parent.SpawnSelector)
local SpawnConfig = require(ReplicatedStorage.Data.SpawnConfig)

export type PlayerDeathData = {
	DeathPosition: Vector3,
	DeathTime: number,
	KillerPlayer: Player?,
	DeathCount: number,
	RespawnScheduled: boolean,
}

local RespawnManager = {}
RespawnManager.__index = RespawnManager

function RespawnManager.new()
	local self = setmetatable({}, RespawnManager)
	self._spawnManager = SpawnPointManager.new()
	self._deathData = {} :: { [Player]: PlayerDeathData }
	self._respawnConfig = {
		RespawnDelay = 5,
		EnablePlayerChoice = false,
		ChoiceTimeout = 15,
		PenaltyOnDeath = nil,
		SpawnInvulnerability = 3,
		EnableRevive = false,
		ReviveTime = 5,
	} :: SpawnConfig.RespawnConfig
	self._strategy = "Default" :: SpawnConfig.SpawnStrategy
	self._invulnerable = {} :: { [Player]: number }  -- timestamp when invuln ends
	self._onDeath = nil :: ((Player, PlayerDeathData) -> ())?
	self._onRespawn = nil :: ((Player, SpawnConfig.SpawnPointConfig) -> ())?
	return self
end

function RespawnManager:GetSpawnManager(): typeof(SpawnPointManager.new())
	return self._spawnManager
end

function RespawnManager:SetConfig(config: SpawnConfig.RespawnConfig)
	self._respawnConfig = config
end

function RespawnManager:SetStrategy(strategy: SpawnConfig.SpawnStrategy)
	self._strategy = strategy
end

---------------------------------------------------------------------
-- Death Handling
---------------------------------------------------------------------
function RespawnManager:Init()
	Players.PlayerAdded:Connect(function(player)
		self._deathData[player] = {
			DeathPosition = Vector3.zero,
			DeathTime = 0,
			KillerPlayer = nil,
			DeathCount = 0,
			RespawnScheduled = false,
		}

		player.CharacterAdded:Connect(function(character)
			local humanoid = character:WaitForChild("Humanoid") :: Humanoid
			humanoid.Died:Connect(function()
				self:_handleDeath(player, character)
			end)
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		self._deathData[player] = nil
		self._invulnerable[player] = nil
	end)
end

function RespawnManager:_handleDeath(player: Player, character: Model)
	local data = self._deathData[player]
	if not data then return end

	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	data.DeathPosition = if rootPart then rootPart.Position else Vector3.zero
	data.DeathTime = tick()
	data.DeathCount += 1
	data.RespawnScheduled = false

	-- Find killer (check for tag)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local creator = humanoid:FindFirstChild("creator")
		if creator and creator:IsA("ObjectValue") and creator.Value then
			local killerPlayer = creator.Value :: Player
			if killerPlayer:IsA("Player") then
				data.KillerPlayer = killerPlayer
			end
		end
	end

	-- Death penalty
	local penalty = self._respawnConfig.PenaltyOnDeath
	if penalty then
		self:_applyDeathPenalty(player, penalty)
	end

	-- Callback
	if self._onDeath then
		self._onDeath(player, data)
	end

	-- Auto-respawn after delay
	if not self._respawnConfig.EnablePlayerChoice then
		data.RespawnScheduled = true
		task.delay(self._respawnConfig.RespawnDelay, function()
			if not player.Parent then return end  -- player left
			self:RespawnPlayer(player)
		end)
	else
		-- Notify client to show spawn selection UI
		local remote = ReplicatedStorage:FindFirstChild("SpawnRemotes")
		if remote then
			local showSelect = remote:FindFirstChild("ShowSpawnSelect") :: RemoteEvent?
			if showSelect then
				local available = self._spawnManager:GetAvailableSpawns(nil, nil, nil)
				local spawnNames = {}
				for _, sp in available do
					table.insert(spawnNames, { Id = sp.Id, Name = sp.Name, Position = sp.Position })
				end
				showSelect:FireClient(player, spawnNames, self._respawnConfig.RespawnDelay, self._respawnConfig.ChoiceTimeout)
			end
		end

		-- Auto-spawn on timeout
		if self._respawnConfig.ChoiceTimeout then
			task.delay(self._respawnConfig.ChoiceTimeout + self._respawnConfig.RespawnDelay, function()
				if not player.Parent then return end
				if not data.RespawnScheduled then
					self:RespawnPlayer(player)
				end
			end)
		end
	end
end

function RespawnManager:_applyDeathPenalty(player: Player, penalty: SpawnConfig.RespawnConfig["PenaltyOnDeath"])
	if not penalty then return end
	-- XP and currency loss handled externally via callback
	-- This is a hook point for game-specific logic
end

---------------------------------------------------------------------
-- Respawn
---------------------------------------------------------------------
function RespawnManager:RespawnPlayer(player: Player, spawnPointId: string?)
	local data = self._deathData[player]
	if data then
		data.RespawnScheduled = true
	end

	-- Select spawn point
	local spawnPoint: SpawnConfig.SpawnPointConfig?

	if spawnPointId then
		spawnPoint = self._spawnManager:GetSpawnPoint(spawnPointId)
	end

	if not spawnPoint then
		local team = nil  -- TODO: get player team
		local level = nil -- TODO: get player level
		local available = self._spawnManager:GetAvailableSpawns(team, level)
		local deathPos = if data then data.DeathPosition else nil
		spawnPoint = SpawnSelector.Select(self._strategy, available, player, deathPos)
	end

	if not spawnPoint then
		-- Fallback: use Roblox default spawn
		player:LoadCharacter()
		return
	end

	-- Load character
	player:LoadCharacter()

	-- Wait for character then teleport
	local character = player.Character or player.CharacterAdded:Wait()
	local rootPart = character:WaitForChild("HumanoidRootPart", 5) :: BasePart?
	if rootPart then
		local spawnCF = spawnPoint.Rotation or CFrame.new(spawnPoint.Position)
		if not spawnPoint.Rotation then
			spawnCF = CFrame.new(spawnPoint.Position)
		end
		rootPart.CFrame = spawnCF
	end

	-- Update spawn count
	self._spawnManager:IncrementCount(spawnPoint.Id)
	task.delay(5, function()
		self._spawnManager:DecrementCount(spawnPoint.Id)
	end)

	-- Grant spawn invulnerability
	local invulnTime = spawnPoint.SpawnProtectionTime or self._respawnConfig.SpawnInvulnerability or 0
	if invulnTime > 0 then
		self:_grantInvulnerability(player, character, invulnTime)
	end

	-- Callback
	if self._onRespawn then
		self._onRespawn(player, spawnPoint)
	end
end

function RespawnManager:_grantInvulnerability(player: Player, character: Model, duration: number)
	self._invulnerable[player] = tick() + duration

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		-- Use ForceField for visual indication
		local forceField = Instance.new("ForceField")
		forceField.Visible = true
		forceField.Parent = character

		task.delay(duration, function()
			if forceField and forceField.Parent then
				forceField:Destroy()
			end
			self._invulnerable[player] = nil
		end)
	end
end

function RespawnManager:IsInvulnerable(player: Player): boolean
	local expires = self._invulnerable[player]
	return expires ~= nil and tick() < expires
end

---------------------------------------------------------------------
-- Safe Zones
---------------------------------------------------------------------
function RespawnManager:IsInSafeZone(position: Vector3): boolean
	for _, sp in self._spawnManager._spawnPoints do
		if sp.SafeZoneRadius and sp.SafeZoneRadius > 0 then
			local distance = (position - sp.Position).Magnitude
			if distance <= sp.SafeZoneRadius then
				return true
			end
		end
	end
	return false
end

function RespawnManager:IsPlayerInSafeZone(player: Player): boolean
	local character = player.Character
	if not character then return false end
	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then return false end
	return self:IsInSafeZone(rootPart.Position)
end

---------------------------------------------------------------------
-- Revive System
---------------------------------------------------------------------
function RespawnManager:TryRevive(reviver: Player, target: Player): boolean
	if not self._respawnConfig.EnableRevive then return false end

	local data = self._deathData[target]
	if not data then return false end
	if data.RespawnScheduled then return false end

	-- Check distance
	local reviverChar = reviver.Character
	if not reviverChar then return false end
	local reviverRoot = reviverChar:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not reviverRoot then return false end

	local targetChar = target.Character
	if not targetChar then return false end
	local targetRoot = targetChar:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not targetRoot then return false end

	local distance = (reviverRoot.Position - targetRoot.Position).Magnitude
	if distance > 10 then return false end

	-- Revive in place
	data.RespawnScheduled = true
	task.delay(self._respawnConfig.ReviveTime or 5, function()
		if not target.Parent then return end
		self:RespawnPlayer(target)
		-- Teleport to revive location
		local newChar = target.Character
		if newChar then
			local newRoot = newChar:FindFirstChild("HumanoidRootPart") :: BasePart?
			if newRoot and targetRoot then
				newRoot.CFrame = CFrame.new(targetRoot.Position + Vector3.new(0, 3, 0))
			end
		end
	end)

	return true
end

---------------------------------------------------------------------
-- Callbacks
---------------------------------------------------------------------
function RespawnManager:OnDeath(callback: (Player, PlayerDeathData) -> ())
	self._onDeath = callback
end

function RespawnManager:OnRespawn(callback: (Player, SpawnConfig.SpawnPointConfig) -> ())
	self._onRespawn = callback
end

---------------------------------------------------------------------
-- Get death data for UI
---------------------------------------------------------------------
function RespawnManager:GetDeathData(player: Player): PlayerDeathData?
	return self._deathData[player]
end

function RespawnManager:GetRespawnTimeRemaining(player: Player): number
	local data = self._deathData[player]
	if not data then return 0 end

	local elapsed = tick() - data.DeathTime
	local remaining = self._respawnConfig.RespawnDelay - elapsed
	return math.max(0, remaining)
end

return RespawnManager
```

## Usage Example

```luau
-- Server setup:
local RespawnManager = require(ServerScriptService.Spawn.RespawnManager)
local respawn = RespawnManager.new()

-- Configure
respawn:SetConfig({
    RespawnDelay = 5,
    EnablePlayerChoice = false,
    SpawnInvulnerability = 3,
    EnableRevive = true,
    ReviveTime = 5,
    PenaltyOnDeath = {
        XPLoss = 0.05,
    },
})
respawn:SetStrategy("Random")

-- Register spawn points
local spawnMgr = respawn:GetSpawnManager()
spawnMgr:RegisterSpawnPoint({
    Id = "main_spawn",
    Name = "Town Square",
    Position = Vector3.new(0, 5, 0),
    Priority = 10,
    SafeZoneRadius = 30,
    SpawnProtectionTime = 5,
    Tags = { "starter" },
})

spawnMgr:RegisterSpawnPoint({
    Id = "forest_spawn",
    Name = "Forest Clearing",
    Position = Vector3.new(200, 5, 100),
    Priority = 5,
    RequiredLevel = 5,
})

-- Initialize death handling
respawn:Init()

-- Callbacks
respawn:OnDeath(function(player, data)
    print(player.Name, "died at", data.DeathPosition)
end)

respawn:OnRespawn(function(player, spawnPoint)
    print(player.Name, "respawned at", spawnPoint.Name)
end)

-- Check safe zone in combat:
if respawn:IsPlayerInSafeZone(targetPlayer) then
    -- Don't allow damage
end
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

When the user asks to implement a spawn system, ask or infer:

- `$SPAWN_STRATEGY` - Spawn selection strategy: "Default", "Random", "Nearest", "FurthestFromEnemies", "PlayerChoice", "Sequential"
- `$RESPAWN_DELAY` - Seconds before respawn: 5
- `$ENABLE_PLAYER_CHOICE` - Let player choose spawn point: true/false
- `$CHOICE_TIMEOUT` - Auto-spawn timeout for choice: 15
- `$ENABLE_INVULNERABILITY` - Spawn protection: true/false
- `$INVULN_DURATION` - Seconds of spawn invulnerability: 3
- `$ENABLE_SAFE_ZONES` - PvP-free zones around spawns: true/false
- `$SAFE_ZONE_RADIUS` - Safe zone radius in studs: 30
- `$ENABLE_DEATH_PENALTY` - Penalties on death: true/false
- `$XP_LOSS_PERCENT` - XP lost on death: 0.05 (5%)
- `$ENABLE_REVIVE` - Player-to-player revive: true/false
- `$REVIVE_TIME` - Seconds to revive another player: 5
- `$ENABLE_TEAM_SPAWNS` - Team-specific spawn points: true/false
- `$AUTO_REGISTER` - Auto-detect SpawnLocations in workspace: true/false
- `$ENABLE_FORCE_FIELD` - Visual ForceField on spawn: true/false
