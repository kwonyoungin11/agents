---
name: leveling
description: |
  Roblox 레벨링 시스템 (Leveling System) - 경험치 곡선, 레벨업 보상, 스탯 배분, 스킬 트리, 환생/프레스티지.
  XP curve formulas, level-up rewards, stat allocation points, skill tree unlocks,
  prestige/rebirth system with multipliers. 로블록스 Luau 레벨 시스템 구현.
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
effort: high
---

# Leveling System for Roblox (Luau)

Complete leveling system with XP curves, stat allocation, skill trees, level-up rewards, and prestige/rebirth mechanics.

## Architecture Overview

```
LevelingSystem (Server)
├── XPManager (XP gain, curve calculation)
├── StatAllocator (stat points, distribution)
├── SkillTreeManager (skill nodes, prerequisites)
├── PrestigeManager (rebirth, multipliers)
├── RewardDistributor (per-level rewards)
└── LevelEvents (remote events)

LevelingClient (Client)
├── XPBarUI (progress display)
├── StatAllocationUI (point distribution)
├── SkillTreeUI (node graph)
└── PrestigeUI (rebirth confirmation)
```

## XP Curve Formulas

```luau
--!strict
-- ReplicatedStorage/Data/XPCurves.luau

export type CurveType = "Linear" | "Quadratic" | "Exponential" | "Custom"

local XPCurves = {}

-- Linear: XP = base * level
function XPCurves.Linear(level: number, base: number): number
	return math.floor(base * level)
end

-- Quadratic: XP = base * level^2 (RPG standard)
function XPCurves.Quadratic(level: number, base: number): number
	return math.floor(base * level * level)
end

-- Exponential: XP = base * multiplier^level
function XPCurves.Exponential(level: number, base: number, multiplier: number?): number
	local mult = multiplier or 1.15
	return math.floor(base * mult ^ level)
end

-- Polynomial: XP = base * level^exponent (flexible)
function XPCurves.Polynomial(level: number, base: number, exponent: number): number
	return math.floor(base * level ^ exponent)
end

-- RuneScape-style: sum-based formula
function XPCurves.SumBased(level: number): number
	local total = 0
	for i = 1, level do
		total += math.floor(i + 300 * 2 ^ (i / 7))
	end
	return math.floor(total / 4)
end

-- Build a full XP table for quick lookups
function XPCurves.BuildTable(maxLevel: number, curveType: CurveType, base: number, extra: number?): { number }
	local xpTable = {}
	for level = 1, maxLevel do
		if curveType == "Linear" then
			xpTable[level] = XPCurves.Linear(level, base)
		elseif curveType == "Quadratic" then
			xpTable[level] = XPCurves.Quadratic(level, base)
		elseif curveType == "Exponential" then
			xpTable[level] = XPCurves.Exponential(level, base, extra)
		else
			xpTable[level] = XPCurves.Quadratic(level, base)
		end
	end
	return xpTable
end

return XPCurves
```

## Core Leveling Module

```luau
--!strict
-- ServerScriptService/Leveling/LevelingSystem.luau

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local XPCurves = require(ReplicatedStorage.Data.XPCurves)

export type StatType = "Strength" | "Vitality" | "Agility" | "Intelligence" | "Luck"

export type PlayerStats = {
	Strength: number,      -- physical damage
	Vitality: number,      -- max HP
	Agility: number,       -- speed, dodge, crit
	Intelligence: number,  -- magic damage, mana
	Luck: number,          -- drop rate, crit chance
}

export type LevelReward = {
	StatPoints: number?,
	SkillPoints: number?,
	Items: { { ItemId: string, Quantity: number } }?,
	Currency: number?,
	UnlockAbility: string?,
	Title: string?,
}

export type PlayerLevelData = {
	Level: number,
	XP: number,
	TotalXP: number,
	StatPoints: number,
	SkillPoints: number,
	AllocatedStats: PlayerStats,
	PrestigeLevel: number,
	PrestigeMultiplier: number,
}

local LevelingSystem = {}
LevelingSystem.__index = LevelingSystem

function LevelingSystem.new(config: {
	MaxLevel: number?,
	CurveType: XPCurves.CurveType?,
	BaseXP: number?,
	CurveExtra: number?,
	StatPointsPerLevel: number?,
	SkillPointsPerLevel: number?,
	BaseStats: PlayerStats?,
}?)
	local self = setmetatable({}, LevelingSystem)
	local cfg = config or {}

	self._maxLevel = cfg.MaxLevel or 100
	self._statPointsPerLevel = cfg.StatPointsPerLevel or 3
	self._skillPointsPerLevel = cfg.SkillPointsPerLevel or 1
	self._baseStats = cfg.BaseStats or {
		Strength = 5,
		Vitality = 5,
		Agility = 5,
		Intelligence = 5,
		Luck = 5,
	}

	-- Build XP table
	self._xpTable = XPCurves.BuildTable(
		self._maxLevel,
		cfg.CurveType or "Quadratic",
		cfg.BaseXP or 100,
		cfg.CurveExtra
	)

	self._playerData = {} :: { [Player]: PlayerLevelData }
	self._levelRewards = {} :: { [number]: LevelReward }
	self._onLevelUp = nil :: ((Player, number, number) -> ())?  -- player, oldLevel, newLevel
	self._onXPGain = nil :: ((Player, number, number, number) -> ())?  -- player, amount, current, required

	-- Default level rewards
	self:_setupDefaultRewards()

	return self
end

function LevelingSystem:_setupDefaultRewards()
	-- Milestone rewards
	self._levelRewards[5] = {
		StatPoints = 5,
		Currency = 100,
		Title = "Novice",
	}
	self._levelRewards[10] = {
		StatPoints = 5,
		SkillPoints = 2,
		Currency = 250,
		Title = "Apprentice",
	}
	self._levelRewards[25] = {
		StatPoints = 10,
		SkillPoints = 3,
		Currency = 1000,
		UnlockAbility = "dash",
		Title = "Journeyman",
	}
	self._levelRewards[50] = {
		StatPoints = 15,
		SkillPoints = 5,
		Currency = 5000,
		Title = "Expert",
	}
	self._levelRewards[100] = {
		StatPoints = 25,
		SkillPoints = 10,
		Currency = 25000,
		Title = "Master",
	}
end

---------------------------------------------------------------------
-- Player Registration
---------------------------------------------------------------------
function LevelingSystem:RegisterPlayer(player: Player, existingData: PlayerLevelData?)
	if existingData then
		self._playerData[player] = existingData
	else
		self._playerData[player] = {
			Level = 1,
			XP = 0,
			TotalXP = 0,
			StatPoints = 0,
			SkillPoints = 0,
			AllocatedStats = table.clone(self._baseStats),
			PrestigeLevel = 0,
			PrestigeMultiplier = 1.0,
		}
	end
end

function LevelingSystem:UnregisterPlayer(player: Player)
	self._playerData[player] = nil
end

function LevelingSystem:GetPlayerData(player: Player): PlayerLevelData?
	return self._playerData[player]
end

function LevelingSystem:GetLevel(player: Player): number
	local data = self._playerData[player]
	return if data then data.Level else 1
end

---------------------------------------------------------------------
-- XP Management
---------------------------------------------------------------------
function LevelingSystem:GetXPForLevel(level: number): number
	if level < 1 then return 0 end
	if level > self._maxLevel then return self._xpTable[self._maxLevel] end
	return self._xpTable[level] or 0
end

function LevelingSystem:GetXPProgress(player: Player): (number, number, number)
	-- Returns: currentXP, requiredXP, percentage
	local data = self._playerData[player]
	if not data then return 0, 100, 0 end

	local required = self:GetXPForLevel(data.Level)
	local percentage = if required > 0 then (data.XP / required) else 0
	return data.XP, required, math.clamp(percentage, 0, 1)
end

function LevelingSystem:AddXP(player: Player, amount: number, source: string?)
	local data = self._playerData[player]
	if not data then return end
	if data.Level >= self._maxLevel then return end

	-- Apply prestige multiplier
	local adjustedAmount = math.floor(amount * data.PrestigeMultiplier)

	data.XP += adjustedAmount
	data.TotalXP += adjustedAmount

	-- Check level ups
	local oldLevel = data.Level
	while data.Level < self._maxLevel do
		local required = self:GetXPForLevel(data.Level)
		if data.XP >= required then
			data.XP -= required
			data.Level += 1

			-- Grant per-level points
			data.StatPoints += self._statPointsPerLevel
			data.SkillPoints += self._skillPointsPerLevel

			-- Check for milestone rewards
			local reward = self._levelRewards[data.Level]
			if reward then
				self:_grantLevelReward(player, data, reward)
			end
		else
			break
		end
	end

	-- Callbacks
	if data.Level > oldLevel and self._onLevelUp then
		self._onLevelUp(player, oldLevel, data.Level)
	end

	if self._onXPGain then
		local required = self:GetXPForLevel(data.Level)
		self._onXPGain(player, adjustedAmount, data.XP, required)
	end
end

function LevelingSystem:_grantLevelReward(player: Player, data: PlayerLevelData, reward: LevelReward)
	if reward.StatPoints then
		data.StatPoints += reward.StatPoints
	end
	if reward.SkillPoints then
		data.SkillPoints += reward.SkillPoints
	end
	-- Items and currency handled externally via callback
end

---------------------------------------------------------------------
-- Stat Allocation
---------------------------------------------------------------------
function LevelingSystem:AllocateStat(player: Player, stat: StatType, points: number?): (boolean, string?)
	local data = self._playerData[player]
	if not data then return false, "Player not registered" end

	local amount = points or 1
	if amount < 1 then return false, "Invalid amount" end
	if data.StatPoints < amount then return false, "Not enough stat points" end

	data.StatPoints -= amount
	data.AllocatedStats[stat] += amount

	return true, nil
end

function LevelingSystem:ResetStats(player: Player, cost: number?): (boolean, string?)
	local data = self._playerData[player]
	if not data then return false, "Player not registered" end

	-- Calculate total allocated points
	local totalAllocated = 0
	for stat, value in data.AllocatedStats do
		local baseValue = self._baseStats[stat] or 0
		totalAllocated += (value - baseValue)
	end

	-- Reset to base stats
	data.AllocatedStats = table.clone(self._baseStats)
	data.StatPoints += totalAllocated

	return true, nil
end

function LevelingSystem:GetTotalStats(player: Player): PlayerStats?
	local data = self._playerData[player]
	if not data then return nil end
	-- Returns allocated stats (base + player-allocated points)
	return table.clone(data.AllocatedStats)
end

function LevelingSystem:GetEffectiveStats(player: Player, equipBonus: { [string]: number }?): { [string]: number }
	local data = self._playerData[player]
	if not data then return {} end

	local effective: { [string]: number } = {}
	for stat, value in data.AllocatedStats do
		effective[stat] = value
	end

	-- Add equipment bonuses
	if equipBonus then
		for stat, bonus in equipBonus do
			effective[stat] = (effective[stat] or 0) + bonus
		end
	end

	return effective
end

---------------------------------------------------------------------
-- Skill Tree
---------------------------------------------------------------------
export type SkillNode = {
	Id: string,
	Name: string,
	Description: string,
	Icon: string?,
	MaxRank: number,
	PointCost: number,
	Prerequisites: { string }?,  -- other skill node IDs
	RequiredLevel: number?,
	Branch: string?,             -- "Combat", "Magic", "Utility"
	Effects: { { Type: string, Value: number } }?,
	Position: { X: number, Y: number }?,  -- for UI layout
}

export type PlayerSkillData = {
	Skills: { [string]: number },  -- nodeId -> current rank
}

function LevelingSystem:SetSkillTree(nodes: { SkillNode })
	self._skillNodes = {} :: { [string]: SkillNode }
	for _, node in nodes do
		self._skillNodes[node.Id] = node
	end
end

function LevelingSystem:GetPlayerSkills(player: Player): { [string]: number }
	local data = self._playerData[player]
	if not data then return {} end
	-- Stored separately to keep PlayerLevelData cleaner
	if not self._playerSkills then
		self._playerSkills = {} :: { [Player]: { [string]: number } }
	end
	return self._playerSkills[player] or {}
end

function LevelingSystem:LearnSkill(player: Player, nodeId: string): (boolean, string?)
	local data = self._playerData[player]
	if not data then return false, "Player not registered" end

	if not self._skillNodes then return false, "No skill tree configured" end
	local node = self._skillNodes[nodeId]
	if not node then return false, "Unknown skill" end

	if not self._playerSkills then
		self._playerSkills = {} :: { [Player]: { [string]: number } }
	end
	if not self._playerSkills[player] then
		self._playerSkills[player] = {}
	end

	local currentRank = self._playerSkills[player][nodeId] or 0

	-- Max rank check
	if currentRank >= node.MaxRank then
		return false, "Already at max rank"
	end

	-- Level requirement
	if node.RequiredLevel and data.Level < node.RequiredLevel then
		return false, "Requires level " .. node.RequiredLevel
	end

	-- Skill point cost
	if data.SkillPoints < node.PointCost then
		return false, "Not enough skill points"
	end

	-- Prerequisites
	if node.Prerequisites then
		for _, prereqId in node.Prerequisites do
			local prereqNode = self._skillNodes[prereqId]
			if prereqNode then
				local prereqRank = self._playerSkills[player][prereqId] or 0
				if prereqRank < prereqNode.MaxRank then
					return false, "Requires " .. prereqNode.Name .. " at max rank"
				end
			end
		end
	end

	-- Learn/rank up
	data.SkillPoints -= node.PointCost
	self._playerSkills[player][nodeId] = currentRank + 1

	return true, nil
end

function LevelingSystem:ResetSkills(player: Player): boolean
	local data = self._playerData[player]
	if not data then return false end

	if not self._playerSkills or not self._playerSkills[player] then return true end

	-- Refund all skill points
	local refunded = 0
	for nodeId, rank in self._playerSkills[player] do
		local node = self._skillNodes and self._skillNodes[nodeId]
		if node then
			refunded += node.PointCost * rank
		end
	end

	self._playerSkills[player] = {}
	data.SkillPoints += refunded
	return true
end

function LevelingSystem:HasSkill(player: Player, nodeId: string, minRank: number?): boolean
	local skills = self:GetPlayerSkills(player)
	local rank = skills[nodeId] or 0
	return rank >= (minRank or 1)
end

---------------------------------------------------------------------
-- Prestige / Rebirth System
---------------------------------------------------------------------
export type PrestigeConfig = {
	RequiredLevel: number,       -- must be max level to prestige
	XPMultiplierPerPrestige: number,  -- 0.1 = +10% per prestige
	MaxPrestige: number,
	KeepSkills: boolean,
	KeepStats: boolean,
	BonusStatPoints: number?,    -- extra stat points per prestige
	BonusCurrency: number?,
}

function LevelingSystem:SetPrestigeConfig(config: PrestigeConfig)
	self._prestigeConfig = config
end

function LevelingSystem:CanPrestige(player: Player): (boolean, string?)
	local data = self._playerData[player]
	if not data then return false, "Player not registered" end

	local cfg = self._prestigeConfig
	if not cfg then return false, "Prestige not configured" end

	if data.Level < cfg.RequiredLevel then
		return false, "Must be level " .. cfg.RequiredLevel
	end

	if data.PrestigeLevel >= cfg.MaxPrestige then
		return false, "Maximum prestige reached"
	end

	return true, nil
end

function LevelingSystem:Prestige(player: Player): (boolean, string?, number?)
	local canPrestige, reason = self:CanPrestige(player)
	if not canPrestige then return false, reason, nil end

	local data = self._playerData[player]
	if not data then return false, "No data", nil end

	local cfg = self._prestigeConfig
	if not cfg then return false, "No config", nil end

	local newPrestige = data.PrestigeLevel + 1

	-- Reset level and XP
	data.Level = 1
	data.XP = 0

	-- Reset stats unless configured to keep
	if not cfg.KeepStats then
		data.AllocatedStats = table.clone(self._baseStats)
		data.StatPoints = 0
	end

	-- Bonus stat points for prestige
	if cfg.BonusStatPoints then
		data.StatPoints += cfg.BonusStatPoints
	end

	-- Reset skills unless configured to keep
	if not cfg.KeepSkills then
		if self._playerSkills then
			self._playerSkills[player] = {}
		end
		data.SkillPoints = 0
	end

	-- Update prestige
	data.PrestigeLevel = newPrestige
	data.PrestigeMultiplier = 1.0 + (newPrestige * cfg.XPMultiplierPerPrestige)

	return true, nil, newPrestige
end

---------------------------------------------------------------------
-- Callbacks
---------------------------------------------------------------------
function LevelingSystem:OnLevelUp(callback: (Player, number, number) -> ())
	self._onLevelUp = callback
end

function LevelingSystem:OnXPGain(callback: (Player, number, number, number) -> ())
	self._onXPGain = callback
end

---------------------------------------------------------------------
-- Serialization
---------------------------------------------------------------------
export type SerializedLevelData = {
	Level: number,
	XP: number,
	TotalXP: number,
	StatPoints: number,
	SkillPoints: number,
	AllocatedStats: PlayerStats,
	PrestigeLevel: number,
	PrestigeMultiplier: number,
	Skills: { [string]: number }?,
}

function LevelingSystem:Serialize(player: Player): SerializedLevelData?
	local data = self._playerData[player]
	if not data then return nil end

	local skills = if self._playerSkills then self._playerSkills[player] else nil

	return {
		Level = data.Level,
		XP = data.XP,
		TotalXP = data.TotalXP,
		StatPoints = data.StatPoints,
		SkillPoints = data.SkillPoints,
		AllocatedStats = data.AllocatedStats,
		PrestigeLevel = data.PrestigeLevel,
		PrestigeMultiplier = data.PrestigeMultiplier,
		Skills = skills,
	}
end

function LevelingSystem:Deserialize(player: Player, data: SerializedLevelData)
	self._playerData[player] = {
		Level = data.Level,
		XP = data.XP,
		TotalXP = data.TotalXP,
		StatPoints = data.StatPoints,
		SkillPoints = data.SkillPoints,
		AllocatedStats = data.AllocatedStats,
		PrestigeLevel = data.PrestigeLevel or 0,
		PrestigeMultiplier = data.PrestigeMultiplier or 1.0,
	}
	if data.Skills then
		if not self._playerSkills then
			self._playerSkills = {} :: { [Player]: { [string]: number } }
		end
		self._playerSkills[player] = data.Skills
	end
end

return LevelingSystem
```

## Example Skill Tree Definition

```luau
-- ReplicatedStorage/Data/SkillTrees.luau
local SkillTrees = {
	Combat = {
		{ Id = "power_strike", Name = "Power Strike", Description = "+10% melee damage per rank", MaxRank = 5, PointCost = 1, Branch = "Combat", Effects = {{ Type = "MeleeDamage", Value = 0.1 }}, Position = { X = 0, Y = 0 } },
		{ Id = "critical_eye", Name = "Critical Eye", Description = "+5% crit chance per rank", MaxRank = 3, PointCost = 2, Prerequisites = {"power_strike"}, Branch = "Combat", Effects = {{ Type = "CritChance", Value = 0.05 }}, Position = { X = 1, Y = 0 } },
		{ Id = "berserker", Name = "Berserker", Description = "+20% damage when below 30% HP", MaxRank = 1, PointCost = 3, Prerequisites = {"critical_eye"}, RequiredLevel = 15, Branch = "Combat", Effects = {{ Type = "LowHPDamage", Value = 0.2 }}, Position = { X = 2, Y = 0 } },
	},
	Magic = {
		{ Id = "mana_flow", Name = "Mana Flow", Description = "+10% magic damage per rank", MaxRank = 5, PointCost = 1, Branch = "Magic", Effects = {{ Type = "MagicDamage", Value = 0.1 }}, Position = { X = 0, Y = 1 } },
		{ Id = "spell_haste", Name = "Spell Haste", Description = "-10% cooldown per rank", MaxRank = 3, PointCost = 2, Prerequisites = {"mana_flow"}, Branch = "Magic", Effects = {{ Type = "CooldownReduction", Value = 0.1 }}, Position = { X = 1, Y = 1 } },
		{ Id = "arcane_master", Name = "Arcane Master", Description = "Spells have 15% chance to not consume mana", MaxRank = 1, PointCost = 3, Prerequisites = {"spell_haste"}, RequiredLevel = 20, Branch = "Magic", Effects = {{ Type = "FreeCast", Value = 0.15 }}, Position = { X = 2, Y = 1 } },
	},
	Utility = {
		{ Id = "swift_feet", Name = "Swift Feet", Description = "+5% movement speed per rank", MaxRank = 3, PointCost = 1, Branch = "Utility", Effects = {{ Type = "MoveSpeed", Value = 0.05 }}, Position = { X = 0, Y = 2 } },
		{ Id = "treasure_hunter", Name = "Treasure Hunter", Description = "+10% drop rate per rank", MaxRank = 5, PointCost = 1, Branch = "Utility", Effects = {{ Type = "DropRate", Value = 0.1 }}, Position = { X = 1, Y = 2 } },
		{ Id = "second_wind", Name = "Second Wind", Description = "Revive once with 25% HP on death", MaxRank = 1, PointCost = 5, Prerequisites = {"swift_feet"}, RequiredLevel = 30, Branch = "Utility", Effects = {{ Type = "Revive", Value = 0.25 }}, Position = { X = 2, Y = 2 } },
	},
}

return SkillTrees
```

## Usage Example

```luau
-- Server setup:
local LevelingSystem = require(ServerScriptService.Leveling.LevelingSystem)
local leveling = LevelingSystem.new({
    MaxLevel = 100,
    CurveType = "Quadratic",
    BaseXP = 100,
    StatPointsPerLevel = 3,
    SkillPointsPerLevel = 1,
})

-- Configure prestige
leveling:SetPrestigeConfig({
    RequiredLevel = 100,
    XPMultiplierPerPrestige = 0.15,
    MaxPrestige = 10,
    KeepSkills = false,
    KeepStats = false,
    BonusStatPoints = 10,
})

-- Load skill tree
local SkillTrees = require(ReplicatedStorage.Data.SkillTrees)
local allNodes = {}
for _, branch in SkillTrees do
    for _, node in branch do table.insert(allNodes, node) end
end
leveling:SetSkillTree(allNodes)

-- When player gains XP:
leveling:AddXP(player, 150, "KillGoblin")

-- Allocate stats:
leveling:AllocateStat(player, "Strength", 2)

-- Learn skill:
leveling:LearnSkill(player, "power_strike")

-- Prestige:
local success, msg, newPrestige = leveling:Prestige(player)
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

When the user asks to implement a leveling system, ask or infer:

- `$MAX_LEVEL` - Maximum player level: 100
- `$XP_CURVE` - XP curve type: "Linear", "Quadratic", "Exponential"
- `$BASE_XP` - Base XP for level 1: 100
- `$STAT_POINTS_PER_LEVEL` - Stat points gained per level: 3
- `$SKILL_POINTS_PER_LEVEL` - Skill points per level: 1
- `$STAT_TYPES` - Available stats: {"Strength", "Vitality", "Agility", "Intelligence", "Luck"}
- `$BASE_STAT_VALUE` - Starting value for each stat: 5
- `$ENABLE_SKILL_TREE` - Include skill tree system: true/false
- `$SKILL_BRANCHES` - Skill tree branches: {"Combat", "Magic", "Utility"}
- `$ENABLE_PRESTIGE` - Include prestige/rebirth: true/false
- `$MAX_PRESTIGE` - Maximum prestige level: 10
- `$PRESTIGE_XP_BONUS` - XP multiplier per prestige: 0.15 (+15%)
- `$PRESTIGE_KEEP_SKILLS` - Keep skills after prestige: true/false
- `$ENABLE_STAT_RESET` - Allow stat respec: true/false
- `$ENABLE_MILESTONE_REWARDS` - Special rewards at milestone levels: true/false
- `$ENABLE_DATASTORE` - Persist leveling data: true/false
