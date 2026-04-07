---
name: combat
description: |
  Roblox 전투 시스템 (Combat System) - 근접/원거리/마법 전투, 히트박스, 데미지 계산, 쿨다운, 콤보, 크리티컬, 회피/방어.
  Melee, ranged, and magic combat with raycast/region hitboxes, damage formulas, cooldown management,
  combo chains, critical hit calculation, dodge/block mechanics. 로블록스 Luau 전투 구현.
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
effort: high
---

# Combat System for Roblox (Luau)

Comprehensive melee, ranged, and magic combat system with hitbox detection, damage calculation, cooldowns, combos, critical hits, and dodge/block mechanics.

## Architecture Overview

```
CombatSystem (Server)
├── HitboxManager (raycast + region detection)
├── DamageCalculator (formulas, crits, resistances)
├── CooldownTracker (per-player, per-ability)
├── ComboManager (chain tracking, timing windows)
└── DefenseManager (dodge, block, parry)

CombatClient (Client)
├── InputHandler (keybinds, combo buffering)
├── AnimationController (attack anims, hit reactions)
└── VFXController (particles, trails, impacts)
```

## Core Combat Module (Server)

```luau
--!strict
-- ServerScriptService/Combat/CombatSystem.luau

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

export type DamageType = "Physical" | "Magic" | "True"
export type AttackStyle = "Melee" | "Ranged" | "Magic"

export type WeaponStats = {
	Name: string,
	AttackStyle: AttackStyle,
	BaseDamage: number,
	AttackSpeed: number,       -- attacks per second
	Range: number,             -- studs
	CritChance: number,        -- 0..1
	CritMultiplier: number,    -- e.g. 1.5
	Knockback: number,         -- studs
	DamageType: DamageType,
	ComboPattern: { number }?, -- timing windows in seconds
}

export type CombatStats = {
	MaxHealth: number,
	Health: number,
	Attack: number,
	Defense: number,
	MagicAttack: number,
	MagicDefense: number,
	Speed: number,
	CritBonus: number,         -- added to weapon crit chance
	DodgeChance: number,       -- 0..1
	BlockReduction: number,    -- 0..1 damage reduction while blocking
}

export type HitResult = {
	Target: Model,
	Damage: number,
	IsCritical: boolean,
	WasDodged: boolean,
	WasBlocked: boolean,
	DamageType: DamageType,
	Knockback: Vector3?,
}

local CombatSystem = {}
CombatSystem.__index = CombatSystem

function CombatSystem.new()
	local self = setmetatable({}, CombatSystem)
	self._cooldowns = {} :: { [Player]: { [string]: number } }
	self._combos = {} :: { [Player]: { count: number, lastTime: number, weapon: string } }
	self._blocking = {} :: { [Player]: boolean }
	self._invulnerable = {} :: { [Player]: number }  -- timestamp when invuln ends
	self._stats = {} :: { [Player]: CombatStats }
	return self
end

-- Register a player's combat stats
function CombatSystem:RegisterPlayer(player: Player, stats: CombatStats)
	self._cooldowns[player] = {}
	self._combos[player] = { count = 0, lastTime = 0, weapon = "" }
	self._blocking[player] = false
	self._invulnerable[player] = 0
	self._stats[player] = stats
end

function CombatSystem:UnregisterPlayer(player: Player)
	self._cooldowns[player] = nil
	self._combos[player] = nil
	self._blocking[player] = nil
	self._invulnerable[player] = nil
	self._stats[player] = nil
end

function CombatSystem:GetStats(player: Player): CombatStats?
	return self._stats[player]
end

function CombatSystem:SetHealth(player: Player, health: number)
	local stats = self._stats[player]
	if stats then
		stats.Health = math.clamp(health, 0, stats.MaxHealth)
	end
end

---------------------------------------------------------------------
-- Cooldown Management
---------------------------------------------------------------------
function CombatSystem:IsOnCooldown(player: Player, abilityName: string): boolean
	local cds = self._cooldowns[player]
	if not cds then return true end
	local expires = cds[abilityName]
	if expires and tick() < expires then
		return true
	end
	return false
end

function CombatSystem:SetCooldown(player: Player, abilityName: string, duration: number)
	local cds = self._cooldowns[player]
	if cds then
		cds[abilityName] = tick() + duration
	end
end

function CombatSystem:GetCooldownRemaining(player: Player, abilityName: string): number
	local cds = self._cooldowns[player]
	if not cds then return 0 end
	local expires = cds[abilityName] or 0
	return math.max(0, expires - tick())
end

---------------------------------------------------------------------
-- Combo System
---------------------------------------------------------------------
function CombatSystem:AdvanceCombo(player: Player, weapon: WeaponStats): number
	local combo = self._combos[player]
	if not combo then return 1 end

	local now = tick()
	local pattern = weapon.ComboPattern or { 0.8, 0.8, 1.2 }
	local maxCombo = #pattern

	-- Check if within timing window of last attack
	local windowIndex = math.min(combo.count, maxCombo)
	local window = if windowIndex > 0 then pattern[windowIndex] else 1.0

	if combo.weapon == weapon.Name and (now - combo.lastTime) <= window and combo.count < maxCombo then
		combo.count += 1
	else
		combo.count = 1
	end

	combo.lastTime = now
	combo.weapon = weapon.Name
	return combo.count
end

function CombatSystem:GetComboMultiplier(comboCount: number): number
	-- Each combo hit deals escalating damage: 1.0, 1.1, 1.25, 1.5
	local multipliers = { 1.0, 1.1, 1.25, 1.5 }
	return multipliers[math.min(comboCount, #multipliers)] or 1.0
end

function CombatSystem:ResetCombo(player: Player)
	local combo = self._combos[player]
	if combo then
		combo.count = 0
		combo.lastTime = 0
		combo.weapon = ""
	end
end

---------------------------------------------------------------------
-- Dodge / Block / Parry
---------------------------------------------------------------------
function CombatSystem:SetBlocking(player: Player, isBlocking: boolean)
	self._blocking[player] = isBlocking
end

function CombatSystem:IsBlocking(player: Player): boolean
	return self._blocking[player] == true
end

function CombatSystem:GrantInvulnerability(player: Player, duration: number)
	self._invulnerable[player] = tick() + duration
end

function CombatSystem:IsInvulnerable(player: Player): boolean
	local expires = self._invulnerable[player]
	return expires ~= nil and tick() < expires
end

function CombatSystem:RollDodge(defender: Player): boolean
	local stats = self._stats[defender]
	if not stats then return false end
	return math.random() < stats.DodgeChance
end

---------------------------------------------------------------------
-- Damage Calculation
---------------------------------------------------------------------
function CombatSystem:CalculateDamage(
	attacker: Player,
	defender: Player,
	weapon: WeaponStats,
	comboCount: number
): HitResult?
	local atkStats = self._stats[attacker]
	local defStats = self._stats[defender]
	if not atkStats or not defStats then return nil end

	local defenderChar = defender.Character
	if not defenderChar then return nil end

	-- Check invulnerability
	if self:IsInvulnerable(defender) then return nil end

	-- Roll dodge
	local dodged = self:RollDodge(defender)
	if dodged then
		return {
			Target = defenderChar,
			Damage = 0,
			IsCritical = false,
			WasDodged = true,
			WasBlocked = false,
			DamageType = weapon.DamageType,
			Knockback = nil,
		}
	end

	-- Base damage from weapon + stat scaling
	local baseDmg: number
	if weapon.DamageType == "Physical" then
		baseDmg = weapon.BaseDamage + atkStats.Attack * 0.5
	elseif weapon.DamageType == "Magic" then
		baseDmg = weapon.BaseDamage + atkStats.MagicAttack * 0.6
	else -- True damage ignores defense
		baseDmg = weapon.BaseDamage
	end

	-- Apply combo multiplier
	local comboMult = self:GetComboMultiplier(comboCount)
	baseDmg *= comboMult

	-- Critical hit
	local critChance = math.clamp(weapon.CritChance + atkStats.CritBonus, 0, 0.8)
	local isCrit = math.random() < critChance
	if isCrit then
		baseDmg *= weapon.CritMultiplier
	end

	-- Defense reduction (not for True damage)
	if weapon.DamageType == "Physical" then
		local reduction = defStats.Defense / (defStats.Defense + 100)
		baseDmg *= (1 - reduction)
	elseif weapon.DamageType == "Magic" then
		local reduction = defStats.MagicDefense / (defStats.MagicDefense + 100)
		baseDmg *= (1 - reduction)
	end

	-- Block reduction
	local isBlocked = self:IsBlocking(defender)
	if isBlocked then
		baseDmg *= (1 - defStats.BlockReduction)
	end

	-- Variance +/- 5%
	baseDmg *= (0.95 + math.random() * 0.10)
	baseDmg = math.floor(math.max(1, baseDmg))

	-- Knockback direction
	local attackerChar = attacker.Character
	local knockbackVec: Vector3? = nil
	if attackerChar and defenderChar and weapon.Knockback > 0 and not isBlocked then
		local atkRoot = attackerChar:FindFirstChild("HumanoidRootPart") :: BasePart?
		local defRoot = defenderChar:FindFirstChild("HumanoidRootPart") :: BasePart?
		if atkRoot and defRoot then
			local dir = (defRoot.Position - atkRoot.Position).Unit
			knockbackVec = dir * weapon.Knockback
		end
	end

	return {
		Target = defenderChar,
		Damage = baseDmg,
		IsCritical = isCrit,
		WasDodged = false,
		WasBlocked = isBlocked,
		DamageType = weapon.DamageType,
		Knockback = knockbackVec,
	}
end

---------------------------------------------------------------------
-- Apply damage to target
---------------------------------------------------------------------
function CombatSystem:ApplyHit(hit: HitResult)
	if hit.WasDodged or hit.Damage <= 0 then return end

	local humanoid = hit.Target:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:TakeDamage(hit.Damage)
	end

	-- Apply knockback
	if hit.Knockback then
		local rootPart = hit.Target:FindFirstChild("HumanoidRootPart") :: BasePart?
		if rootPart then
			local bv = Instance.new("BodyVelocity")
			bv.Velocity = hit.Knockback
			bv.MaxForce = Vector3.new(1e5, 1e5, 1e5)
			bv.Parent = rootPart
			task.delay(0.2, function()
				bv:Destroy()
			end)
		end
	end
end

return CombatSystem
```

## Hitbox Manager (Raycast + Region)

```luau
--!strict
-- ServerScriptService/Combat/HitboxManager.luau

local Workspace = game:GetService("Workspace")

export type HitboxType = "Raycast" | "Region" | "Sphere"

export type HitboxParams = {
	Origin: Vector3,
	Direction: Vector3?,     -- for Raycast
	Size: Vector3?,          -- for Region
	Radius: number?,         -- for Sphere
	MaxTargets: number?,
	IgnoreList: { Instance }?,
	TeamCheck: boolean?,     -- if true, skip same-team targets
}

export type HitboxResult = {
	Hits: { Model },
	HitPositions: { Vector3 },
}

local HitboxManager = {}

-- Raycast-based hitbox (for ranged/piercing attacks)
function HitboxManager.Raycast(params: HitboxParams): HitboxResult
	local result: HitboxResult = { Hits = {}, HitPositions = {} }
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = params.IgnoreList or {}

	local maxTargets = params.MaxTargets or 1
	local direction = params.Direction or Vector3.new(0, 0, -1)
	local hits: { [Model]: boolean } = {}
	local currentOrigin = params.Origin
	local remaining = direction

	for _ = 1, maxTargets do
		local rayResult = Workspace:Raycast(currentOrigin, remaining, rayParams)
		if not rayResult then break end

		local hitPart = rayResult.Instance
		local model = hitPart:FindFirstAncestorOfClass("Model")
		if model and model:FindFirstChildOfClass("Humanoid") and not hits[model] then
			hits[model] = true
			table.insert(result.Hits, model)
			table.insert(result.HitPositions, rayResult.Position)

			-- For piercing, continue ray from hit point
			local traveled = (rayResult.Position - currentOrigin).Magnitude
			currentOrigin = rayResult.Position
			remaining = direction.Unit * (direction.Magnitude - traveled)

			-- Add hit part to ignore for piercing
			table.insert(rayParams.FilterDescendantsInstances, model)
		else
			break
		end
	end

	return result
end

-- Region-based hitbox (for melee swings, AoE)
function HitboxManager.Region(params: HitboxParams): HitboxResult
	local result: HitboxResult = { Hits = {}, HitPositions = {} }
	local size = params.Size or Vector3.new(5, 5, 5)
	local maxTargets = params.MaxTargets or 10

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = params.IgnoreList or {}

	local parts = Workspace:GetPartBoundsInBox(CFrame.new(params.Origin), size, overlapParams)

	local hits: { [Model]: boolean } = {}
	for _, part in parts do
		if #result.Hits >= maxTargets then break end

		local model = part:FindFirstAncestorOfClass("Model")
		if model and model:FindFirstChildOfClass("Humanoid") and not hits[model] then
			hits[model] = true
			table.insert(result.Hits, model)
			local rootPart = model:FindFirstChild("HumanoidRootPart") :: BasePart?
			table.insert(result.HitPositions, if rootPart then rootPart.Position else part.Position)
		end
	end

	return result
end

-- Sphere-based hitbox (for explosions, radial AoE)
function HitboxManager.Sphere(params: HitboxParams): HitboxResult
	local result: HitboxResult = { Hits = {}, HitPositions = {} }
	local radius = params.Radius or 10
	local maxTargets = params.MaxTargets or 20

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = params.IgnoreList or {}

	local parts = Workspace:GetPartBoundsInRadius(params.Origin, radius, overlapParams)

	local hits: { [Model]: boolean } = {}
	for _, part in parts do
		if #result.Hits >= maxTargets then break end

		local model = part:FindFirstAncestorOfClass("Model")
		if model and model:FindFirstChildOfClass("Humanoid") and not hits[model] then
			hits[model] = true
			table.insert(result.Hits, model)
			local rootPart = model:FindFirstChild("HumanoidRootPart") :: BasePart?
			table.insert(result.HitPositions, if rootPart then rootPart.Position else part.Position)
		end
	end

	return result
end

-- Convenience: melee swing hitbox in front of character
function HitboxManager.MeleeSwing(character: Model, range: number, width: number, height: number): HitboxResult
	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then
		return { Hits = {}, HitPositions = {} }
	end

	local origin = rootPart.Position + rootPart.CFrame.LookVector * (range / 2)
	return HitboxManager.Region({
		Origin = origin,
		Size = Vector3.new(width, height, range),
		IgnoreList = { character },
		MaxTargets = 5,
	})
end

return HitboxManager
```

## Combat Client (Input & Animation)

```luau
--!strict
-- StarterPlayerScripts/CombatClient.luau

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

-- Remote events (create in ReplicatedStorage)
local CombatRemotes = ReplicatedStorage:WaitForChild("CombatRemotes")
local AttackEvent = CombatRemotes:WaitForChild("Attack") :: RemoteEvent
local BlockEvent = CombatRemotes:WaitForChild("Block") :: RemoteEvent
local DodgeEvent = CombatRemotes:WaitForChild("Dodge") :: RemoteEvent

local CombatClient = {}
CombatClient._inputBuffer = {} :: { { action: string, time: number } }
CombatClient._bufferWindow = 0.3  -- seconds to buffer input
CombatClient._lastAttackTime = 0
CombatClient._isBlocking = false

-- Input binding
function CombatClient:Init()
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end

		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			self:BufferInput("Attack")
		elseif input.KeyCode == Enum.KeyCode.F then
			self:StartBlock()
		elseif input.KeyCode == Enum.KeyCode.Q then
			self:Dodge()
		end
	end)

	UserInputService.InputEnded:Connect(function(input, _gameProcessed)
		if input.KeyCode == Enum.KeyCode.F then
			self:EndBlock()
		end
	end)

	-- Process buffer each frame
	game:GetService("RunService").Heartbeat:Connect(function()
		self:ProcessBuffer()
	end)
end

function CombatClient:BufferInput(action: string)
	table.insert(self._inputBuffer, { action = action, time = tick() })
end

function CombatClient:ProcessBuffer()
	local now = tick()
	-- Remove stale inputs
	local i = 1
	while i <= #self._inputBuffer do
		if now - self._inputBuffer[i].time > self._bufferWindow then
			table.remove(self._inputBuffer, i)
		else
			i += 1
		end
	end

	-- Process first valid input
	if #self._inputBuffer > 0 then
		local input = self._inputBuffer[1]
		if input.action == "Attack" then
			table.remove(self._inputBuffer, 1)
			self:PerformAttack()
		end
	end
end

function CombatClient:PerformAttack()
	local character = player.Character
	if not character then return end

	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then return end

	-- Send aim direction (mouse world position for ranged)
	local mouse = player:GetMouse()
	local aimPosition = mouse.Hit and mouse.Hit.Position or (rootPart.Position + rootPart.CFrame.LookVector * 50)

	AttackEvent:FireServer(aimPosition)
	self._lastAttackTime = tick()
end

function CombatClient:StartBlock()
	if self._isBlocking then return end
	self._isBlocking = true
	BlockEvent:FireServer(true)
end

function CombatClient:EndBlock()
	if not self._isBlocking then return end
	self._isBlocking = false
	BlockEvent:FireServer(false)
end

function CombatClient:Dodge()
	local character = player.Character
	if not character then return end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	local moveDir = humanoid.MoveDirection
	if moveDir.Magnitude < 0.1 then
		-- Dodge backward if not moving
		local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if rootPart then
			moveDir = -rootPart.CFrame.LookVector
		end
	end

	DodgeEvent:FireServer(moveDir.Unit)
end

-- Play hit reaction animation
function CombatClient:PlayHitReaction(character: Model, isCritical: boolean)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then return end

	local animId = if isCritical then "rbxassetid://YOUR_CRIT_HIT_ANIM" else "rbxassetid://YOUR_HIT_ANIM"
	local anim = Instance.new("Animation")
	anim.AnimationId = animId
	local track = animator:LoadAnimation(anim)
	track:Play()
	track.Stopped:Once(function()
		anim:Destroy()
	end)
end

return CombatClient
```

## Server Attack Handler (Wiring It Together)

```luau
--!strict
-- ServerScriptService/Combat/AttackHandler.luau
-- Wires client requests to CombatSystem + HitboxManager

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatSystem = require(script.Parent.CombatSystem)
local HitboxManager = require(script.Parent.HitboxManager)

-- Create remotes
local CombatRemotes = Instance.new("Folder")
CombatRemotes.Name = "CombatRemotes"
CombatRemotes.Parent = ReplicatedStorage

local AttackEvent = Instance.new("RemoteEvent")
AttackEvent.Name = "Attack"
AttackEvent.Parent = CombatRemotes

local BlockEvent = Instance.new("RemoteEvent")
BlockEvent.Name = "Block"
BlockEvent.Parent = CombatRemotes

local DodgeEvent = Instance.new("RemoteEvent")
DodgeEvent.Name = "Dodge"
DodgeEvent.Parent = CombatRemotes

local HitFeedback = Instance.new("RemoteEvent")
HitFeedback.Name = "HitFeedback"
HitFeedback.Parent = CombatRemotes

-- Instantiate combat system
local combat = CombatSystem.new()

-- Default weapon for example
local DEFAULT_WEAPON: CombatSystem.WeaponStats = {
	Name = "BasicSword",
	AttackStyle = "Melee",
	BaseDamage = 20,
	AttackSpeed = 1.5,
	Range = 8,
	CritChance = 0.1,
	CritMultiplier = 1.5,
	Knockback = 5,
	DamageType = "Physical",
	ComboPattern = { 0.8, 0.8, 1.2 },
}

local DEFAULT_STATS: CombatSystem.CombatStats = {
	MaxHealth = 100,
	Health = 100,
	Attack = 10,
	Defense = 5,
	MagicAttack = 8,
	MagicDefense = 5,
	Speed = 16,
	CritBonus = 0.05,
	DodgeChance = 0.05,
	BlockReduction = 0.5,
}

Players.PlayerAdded:Connect(function(player)
	combat:RegisterPlayer(player, table.clone(DEFAULT_STATS))
end)

Players.PlayerRemoving:Connect(function(player)
	combat:UnregisterPlayer(player)
end)

AttackEvent.OnServerEvent:Connect(function(player: Player, aimPosition: Vector3)
	local character = player.Character
	if not character then return end

	local weapon = DEFAULT_WEAPON -- Replace with equipped weapon lookup
	local cooldownKey = weapon.Name .. "_attack"

	-- Check cooldown
	if combat:IsOnCooldown(player, cooldownKey) then return end
	combat:SetCooldown(player, cooldownKey, 1 / weapon.AttackSpeed)

	-- Advance combo
	local comboCount = combat:AdvanceCombo(player, weapon)

	-- Perform hitbox based on weapon style
	local hitResult: HitboxManager.HitboxResult

	if weapon.AttackStyle == "Melee" then
		hitResult = HitboxManager.MeleeSwing(character, weapon.Range, 6, 5)
	elseif weapon.AttackStyle == "Ranged" then
		local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not rootPart then return end
		hitResult = HitboxManager.Raycast({
			Origin = rootPart.Position,
			Direction = (aimPosition - rootPart.Position).Unit * weapon.Range,
			IgnoreList = { character },
			MaxTargets = 1,
		})
	else -- Magic
		hitResult = HitboxManager.Sphere({
			Origin = aimPosition,
			Radius = 8,
			IgnoreList = { character },
			MaxTargets = 5,
		})
	end

	-- Process each hit
	for _, hitModel in hitResult.Hits do
		-- Find the player who owns this character
		local targetPlayer = Players:GetPlayerFromCharacter(hitModel)
		if not targetPlayer then continue end

		local dmgResult = combat:CalculateDamage(player, targetPlayer, weapon, comboCount)
		if dmgResult then
			combat:ApplyHit(dmgResult)

			-- Send feedback to attacker
			HitFeedback:FireClient(player, {
				Target = hitModel,
				Damage = dmgResult.Damage,
				IsCritical = dmgResult.IsCritical,
				WasDodged = dmgResult.WasDodged,
				WasBlocked = dmgResult.WasBlocked,
			})
		end
	end
end)

BlockEvent.OnServerEvent:Connect(function(player: Player, isBlocking: boolean)
	combat:SetBlocking(player, isBlocking)
end)

DodgeEvent.OnServerEvent:Connect(function(player: Player, direction: Vector3)
	if combat:IsOnCooldown(player, "dodge") then return end
	combat:SetCooldown(player, "dodge", 1.5)
	combat:GrantInvulnerability(player, 0.4) -- i-frames

	local character = player.Character
	if not character then return end
	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then return end

	-- Dash in direction
	local bv = Instance.new("BodyVelocity")
	bv.Velocity = direction * 50
	bv.MaxForce = Vector3.new(1e5, 0, 1e5)
	bv.Parent = rootPart
	task.delay(0.25, function()
		bv:Destroy()
	end)
end)
```

## Weapon Templates

```luau
-- ReplicatedStorage/Data/WeaponTemplates.luau
local Weapons = {
	IronSword = {
		Name = "IronSword",
		AttackStyle = "Melee",
		BaseDamage = 25,
		AttackSpeed = 1.8,
		Range = 7,
		CritChance = 0.10,
		CritMultiplier = 1.5,
		Knockback = 4,
		DamageType = "Physical",
		ComboPattern = { 0.6, 0.6, 1.0 },
	},
	HunterBow = {
		Name = "HunterBow",
		AttackStyle = "Ranged",
		BaseDamage = 30,
		AttackSpeed = 0.8,
		Range = 120,
		CritChance = 0.20,
		CritMultiplier = 2.0,
		Knockback = 0,
		DamageType = "Physical",
		ComboPattern = nil,
	},
	FireStaff = {
		Name = "FireStaff",
		AttackStyle = "Magic",
		BaseDamage = 40,
		AttackSpeed = 0.6,
		Range = 60,
		CritChance = 0.15,
		CritMultiplier = 1.8,
		Knockback = 8,
		DamageType = "Magic",
		ComboPattern = nil,
	},
}

return Weapons
```

## Usage Example

```luau
-- Quick usage in a ServerScript:
local CombatSystem = require(ServerScriptService.Combat.CombatSystem)
local HitboxManager = require(ServerScriptService.Combat.HitboxManager)

local combat = CombatSystem.new()

-- When player joins:
combat:RegisterPlayer(player, {
    MaxHealth = 100, Health = 100,
    Attack = 15, Defense = 10,
    MagicAttack = 12, MagicDefense = 8,
    Speed = 16, CritBonus = 0.05,
    DodgeChance = 0.08, BlockReduction = 0.5,
})

-- On attack input:
if not combat:IsOnCooldown(player, "slash") then
    combat:SetCooldown(player, "slash", 0.5)
    local comboCount = combat:AdvanceCombo(player, weapon)
    local hits = HitboxManager.MeleeSwing(character, 8, 6, 5)
    for _, target in hits.Hits do
        local result = combat:CalculateDamage(player, targetPlayer, weapon, comboCount)
        if result then combat:ApplyHit(result) end
    end
end
```

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

When the user asks to implement a combat system, ask or infer:

- `$ATTACK_STYLES` - Which attack types to support: "Melee", "Ranged", "Magic", or any combination
- `$DAMAGE_FORMULA` - Damage calculation approach: "simple" (flat), "scaling" (stat-based), "mmo" (defense reduction formula)
- `$HITBOX_METHOD` - Hitbox detection: "raycast" (precise ranged), "region" (melee/AoE box), "sphere" (radial AoE)
- `$COMBO_ENABLED` - Whether to include combo chaining: true/false
- `$COMBO_PATTERN` - Timing windows in seconds for each combo hit, e.g. {0.6, 0.6, 1.0}
- `$CRIT_CHANCE` - Base critical hit chance as decimal: 0.1 (10%)
- `$CRIT_MULTIPLIER` - Critical damage multiplier: 1.5 (150% damage)
- `$DODGE_ENABLED` - Include dodge/i-frame mechanic: true/false
- `$BLOCK_ENABLED` - Include blocking mechanic: true/false
- `$BLOCK_REDUCTION` - Damage reduction while blocking: 0.5 (50%)
- `$KNOCKBACK` - Knockback force in studs on hit: 5
- `$MAX_HEALTH` - Default max health: 100
- `$PVP_ENABLED` - Allow player vs player combat: true/false
- `$PVE_ENABLED` - Allow player vs NPC combat: true/false
