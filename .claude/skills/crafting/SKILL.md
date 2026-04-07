---
name: crafting
description: |
  Roblox 제작 시스템 (Crafting System) - 레시피, 재료 확인, 제작대, 결과 아이템, 잠금 해제 진행.
  Recipe-based crafting with ingredient checking, crafting stations, result items, unlock progression,
  crafting time, success rates, recipe discovery. 로블록스 Luau 크래프팅 시스템 구현.
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
effort: high
---

# Crafting System for Roblox (Luau)

Recipe-based crafting system with ingredient validation, crafting stations, unlock progression, crafting time, success rates, and recipe discovery.

## Architecture Overview

```
CraftingSystem (Server)
├── RecipeDatabase (recipes, ingredients, results)
├── CraftingManager (craft validation, execution)
├── StationManager (crafting station types)
├── UnlockTracker (recipe discovery/progression)
└── CraftingEvents (remote events)

CraftingClient (Client)
├── CraftingUI (recipe list, ingredient display)
├── StationUI (interaction prompt)
└── ProgressBar (crafting timer)
```

## Recipe Database

```luau
--!strict
-- ReplicatedStorage/Data/RecipeDatabase.luau

export type Ingredient = {
	ItemId: string,
	Quantity: number,
}

export type CraftingResult = {
	ItemId: string,
	Quantity: number,
	Chance: number?,  -- 0..1, nil = guaranteed. For bonus outputs.
}

export type RecipeTemplate = {
	Id: string,
	Name: string,
	Description: string,
	Category: string,            -- "Weapons", "Armor", "Potions", "Materials", "Tools"
	Ingredients: { Ingredient },
	Results: { CraftingResult },
	Station: string?,            -- required crafting station type, nil = craft anywhere
	CraftTime: number?,          -- seconds, nil = instant
	SuccessRate: number?,        -- 0..1, nil = always succeeds
	RequiredLevel: number?,      -- crafting skill level
	XPReward: number?,           -- crafting XP gained
	Unlocked: boolean?,          -- available by default? false = must discover
	UnlockCondition: string?,    -- e.g., "QuestComplete:main_005", "Level:10"
	CurrencyCost: number?,       -- additional currency cost
}

local RecipeDatabase: { [string]: RecipeTemplate } = {
	iron_sword_recipe = {
		Id = "iron_sword_recipe",
		Name = "Forge Iron Sword",
		Description = "Forge a basic iron sword at the anvil.",
		Category = "Weapons",
		Ingredients = {
			{ ItemId = "iron_ingot", Quantity = 3 },
			{ ItemId = "wood_plank", Quantity = 1 },
			{ ItemId = "leather_strip", Quantity = 1 },
		},
		Results = {
			{ ItemId = "iron_sword", Quantity = 1 },
		},
		Station = "Anvil",
		CraftTime = 5,
		SuccessRate = 1.0,
		RequiredLevel = 1,
		XPReward = 25,
		Unlocked = true,
	},
	health_potion_recipe = {
		Id = "health_potion_recipe",
		Name = "Brew Health Potion",
		Description = "Combine herbs to create a healing potion.",
		Category = "Potions",
		Ingredients = {
			{ ItemId = "red_herb", Quantity = 2 },
			{ ItemId = "spring_water", Quantity = 1 },
		},
		Results = {
			{ ItemId = "health_potion", Quantity = 2 },
		},
		Station = "AlchemyTable",
		CraftTime = 3,
		RequiredLevel = 1,
		XPReward = 15,
		Unlocked = true,
	},
	steel_ingot_recipe = {
		Id = "steel_ingot_recipe",
		Name = "Smelt Steel Ingot",
		Description = "Combine iron and coal to produce steel.",
		Category = "Materials",
		Ingredients = {
			{ ItemId = "iron_ingot", Quantity = 2 },
			{ ItemId = "coal", Quantity = 1 },
		},
		Results = {
			{ ItemId = "steel_ingot", Quantity = 1 },
			{ ItemId = "slag", Quantity = 1, Chance = 0.3 },  -- 30% bonus output
		},
		Station = "Furnace",
		CraftTime = 8,
		RequiredLevel = 5,
		XPReward = 30,
		Unlocked = false,
		UnlockCondition = "Level:5",
	},
	dragon_sword_recipe = {
		Id = "dragon_sword_recipe",
		Name = "Forge Dragon Blade",
		Description = "A legendary weapon forged from dragon scales.",
		Category = "Weapons",
		Ingredients = {
			{ ItemId = "dragon_scale", Quantity = 5 },
			{ ItemId = "steel_ingot", Quantity = 3 },
			{ ItemId = "enchanted_gem", Quantity = 1 },
		},
		Results = {
			{ ItemId = "dragon_sword", Quantity = 1 },
		},
		Station = "Anvil",
		CraftTime = 15,
		SuccessRate = 0.8,  -- 80% success
		RequiredLevel = 15,
		XPReward = 200,
		Unlocked = false,
		UnlockCondition = "QuestComplete:main_010",
	},
}

local module = {}

function module.GetRecipe(recipeId: string): RecipeTemplate?
	return RecipeDatabase[recipeId]
end

function module.GetRecipesByCategory(category: string): { RecipeTemplate }
	local results = {}
	for _, recipe in RecipeDatabase do
		if recipe.Category == category then
			table.insert(results, recipe)
		end
	end
	return results
end

function module.GetRecipesByStation(station: string): { RecipeTemplate }
	local results = {}
	for _, recipe in RecipeDatabase do
		if recipe.Station == station then
			table.insert(results, recipe)
		end
	end
	return results
end

function module.GetAllRecipes(): { RecipeTemplate }
	local results = {}
	for _, recipe in RecipeDatabase do
		table.insert(results, recipe)
	end
	return results
end

function module.Register(template: RecipeTemplate)
	assert(template.Id and template.Id ~= "", "Recipe must have an Id")
	RecipeDatabase[template.Id] = template
end

return module
```

## Crafting Manager (Server)

```luau
--!strict
-- ServerScriptService/Crafting/CraftingManager.luau

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RecipeDatabase = require(ReplicatedStorage.Data.RecipeDatabase)

export type CraftResult = {
	Success: boolean,
	Message: string,
	ItemsCreated: { { ItemId: string, Quantity: number } }?,
	XPGained: number?,
}

export type PlayerCraftingData = {
	UnlockedRecipes: { [string]: boolean },
	CraftingLevel: number,
	CraftingXP: number,
	ActiveCraft: {
		RecipeId: string,
		StartTime: number,
		EndTime: number,
	}?,
}

local CraftingManager = {}
CraftingManager.__index = CraftingManager

function CraftingManager.new()
	local self = setmetatable({}, CraftingManager)
	self._inventoryManager = nil :: any
	self._playerData = {} :: { [Player]: PlayerCraftingData }
	self._xpCurve = {} :: { number }  -- XP required per level
	self:_buildXPCurve(50)  -- max crafting level
	return self
end

function CraftingManager:SetInventoryManager(invManager: any)
	self._inventoryManager = invManager
end

function CraftingManager:_buildXPCurve(maxLevel: number)
	self._xpCurve = {}
	for i = 1, maxLevel do
		-- Quadratic scaling: 100, 250, 450, 700, ...
		self._xpCurve[i] = math.floor(100 * i + 50 * i * (i - 1) / 2)
	end
end

function CraftingManager:RegisterPlayer(player: Player)
	self._playerData[player] = {
		UnlockedRecipes = {},
		CraftingLevel = 1,
		CraftingXP = 0,
		ActiveCraft = nil,
	}

	-- Auto-unlock default recipes
	for _, recipe in RecipeDatabase.GetAllRecipes() do
		if recipe.Unlocked ~= false then
			self._playerData[player].UnlockedRecipes[recipe.Id] = true
		end
	end
end

function CraftingManager:UnregisterPlayer(player: Player)
	self._playerData[player] = nil
end

function CraftingManager:GetPlayerData(player: Player): PlayerCraftingData?
	return self._playerData[player]
end

---------------------------------------------------------------------
-- Recipe Unlock System
---------------------------------------------------------------------
function CraftingManager:UnlockRecipe(player: Player, recipeId: string): boolean
	local pData = self._playerData[player]
	if not pData then return false end

	local recipe = RecipeDatabase.GetRecipe(recipeId)
	if not recipe then return false end

	pData.UnlockedRecipes[recipeId] = true
	return true
end

function CraftingManager:IsRecipeUnlocked(player: Player, recipeId: string): boolean
	local pData = self._playerData[player]
	if not pData then return false end
	return pData.UnlockedRecipes[recipeId] == true
end

function CraftingManager:CheckUnlockConditions(player: Player)
	local pData = self._playerData[player]
	if not pData then return end

	for _, recipe in RecipeDatabase.GetAllRecipes() do
		if pData.UnlockedRecipes[recipe.Id] then continue end
		if not recipe.UnlockCondition then continue end

		local condType, condValue = recipe.UnlockCondition:match("^(%w+):(.+)$")
		if not condType then continue end

		local shouldUnlock = false

		if condType == "Level" then
			local reqLevel = tonumber(condValue) or 999
			shouldUnlock = pData.CraftingLevel >= reqLevel
		elseif condType == "QuestComplete" then
			-- Hook into quest system
			shouldUnlock = false  -- Override with quest check
		end

		if shouldUnlock then
			pData.UnlockedRecipes[recipe.Id] = true
		end
	end
end

---------------------------------------------------------------------
-- Crafting XP & Level
---------------------------------------------------------------------
function CraftingManager:AddCraftingXP(player: Player, xp: number): (number, boolean)
	local pData = self._playerData[player]
	if not pData then return 0, false end

	pData.CraftingXP += xp
	local leveledUp = false

	-- Check level up
	while pData.CraftingLevel < #self._xpCurve do
		local required = self._xpCurve[pData.CraftingLevel]
		if pData.CraftingXP >= required then
			pData.CraftingXP -= required
			pData.CraftingLevel += 1
			leveledUp = true
			-- Check new recipe unlocks
			self:CheckUnlockConditions(player)
		else
			break
		end
	end

	return pData.CraftingLevel, leveledUp
end

---------------------------------------------------------------------
-- Can Craft Check
---------------------------------------------------------------------
function CraftingManager:CanCraft(player: Player, recipeId: string, station: string?): (boolean, string?)
	local pData = self._playerData[player]
	if not pData then return false, "Player not registered" end

	-- Already crafting?
	if pData.ActiveCraft then
		return false, "Already crafting something"
	end

	local recipe = RecipeDatabase.GetRecipe(recipeId)
	if not recipe then return false, "Unknown recipe" end

	-- Unlocked?
	if not pData.UnlockedRecipes[recipeId] then
		return false, "Recipe not unlocked"
	end

	-- Level requirement
	if recipe.RequiredLevel and pData.CraftingLevel < recipe.RequiredLevel then
		return false, "Requires crafting level " .. recipe.RequiredLevel
	end

	-- Station requirement
	if recipe.Station and recipe.Station ~= station then
		return false, "Requires " .. recipe.Station .. " station"
	end

	-- Ingredient check
	if self._inventoryManager then
		for _, ingredient in recipe.Ingredients do
			if not self._inventoryManager:HasItem(player, ingredient.ItemId, ingredient.Quantity) then
				return false, "Missing ingredient: " .. ingredient.ItemId
			end
		end
	end

	-- Currency cost
	if recipe.CurrencyCost and recipe.CurrencyCost > 0 then
		if self._inventoryManager then
			local inv = self._inventoryManager:GetInventory(player)
			if inv and inv.Currency < recipe.CurrencyCost then
				return false, "Not enough currency (need " .. recipe.CurrencyCost .. ")"
			end
		end
	end

	-- Inventory space for results
	if self._inventoryManager then
		local freeSlots = self._inventoryManager:GetFreeSlots(player)
		local slotsNeeded = #recipe.Results
		if freeSlots < slotsNeeded then
			return false, "Not enough inventory space"
		end
	end

	return true, nil
end

---------------------------------------------------------------------
-- Start Craft
---------------------------------------------------------------------
function CraftingManager:StartCraft(player: Player, recipeId: string, station: string?): (boolean, string?, number?)
	local canCraft, reason = self:CanCraft(player, recipeId, station)
	if not canCraft then
		return false, reason, nil
	end

	local pData = self._playerData[player]
	if not pData then return false, "No data", nil end

	local recipe = RecipeDatabase.GetRecipe(recipeId)
	if not recipe then return false, "No recipe", nil end

	-- Consume ingredients
	if self._inventoryManager then
		for _, ingredient in recipe.Ingredients do
			self._inventoryManager:RemoveItem(player, ingredient.ItemId, ingredient.Quantity)
		end

		-- Consume currency
		if recipe.CurrencyCost and recipe.CurrencyCost > 0 then
			local inv = self._inventoryManager:GetInventory(player)
			if inv then
				inv.Currency -= recipe.CurrencyCost
			end
		end
	end

	local craftTime = recipe.CraftTime or 0

	if craftTime > 0 then
		-- Set up timed crafting
		pData.ActiveCraft = {
			RecipeId = recipeId,
			StartTime = tick(),
			EndTime = tick() + craftTime,
		}
		return true, nil, craftTime
	else
		-- Instant craft
		return true, nil, 0
	end
end

---------------------------------------------------------------------
-- Complete Craft
---------------------------------------------------------------------
function CraftingManager:CompleteCraft(player: Player, recipeId: string?): CraftResult
	local pData = self._playerData[player]
	if not pData then
		return { Success = false, Message = "Player not registered" }
	end

	-- If timed, use active craft
	local craftRecipeId = recipeId
	if pData.ActiveCraft then
		if tick() < pData.ActiveCraft.EndTime then
			return { Success = false, Message = "Crafting not finished yet" }
		end
		craftRecipeId = pData.ActiveCraft.RecipeId
		pData.ActiveCraft = nil
	end

	if not craftRecipeId then
		return { Success = false, Message = "No active craft" }
	end

	local recipe = RecipeDatabase.GetRecipe(craftRecipeId)
	if not recipe then
		return { Success = false, Message = "Unknown recipe" }
	end

	-- Success rate check
	local successRate = recipe.SuccessRate or 1.0
	if math.random() > successRate then
		-- Failed! Ingredients already consumed.
		return {
			Success = false,
			Message = "Crafting failed! Materials were lost.",
			XPGained = math.floor((recipe.XPReward or 0) * 0.25),  -- partial XP for failure
		}
	end

	-- Grant results
	local itemsCreated: { { ItemId: string, Quantity: number } } = {}
	if self._inventoryManager then
		for _, result in recipe.Results do
			local shouldGrant = true
			if result.Chance then
				shouldGrant = math.random() <= result.Chance
			end

			if shouldGrant then
				self._inventoryManager:AddItem(player, result.ItemId, result.Quantity)
				table.insert(itemsCreated, { ItemId = result.ItemId, Quantity = result.Quantity })
			end
		end
	end

	-- Grant XP
	local xpGained = recipe.XPReward or 0
	if xpGained > 0 then
		self:AddCraftingXP(player, xpGained)
	end

	return {
		Success = true,
		Message = "Crafting successful!",
		ItemsCreated = itemsCreated,
		XPGained = xpGained,
	}
end

-- Instant craft helper (for recipes with no craft time)
function CraftingManager:CraftInstant(player: Player, recipeId: string, station: string?): CraftResult
	local started, startMsg, craftTime = self:StartCraft(player, recipeId, station)
	if not started then
		return { Success = false, Message = startMsg or "Cannot craft" }
	end

	if craftTime and craftTime > 0 then
		return { Success = false, Message = "This recipe requires time. Use StartCraft + CompleteCraft." }
	end

	return self:CompleteCraft(player, recipeId)
end

---------------------------------------------------------------------
-- Get Available Recipes (for UI)
---------------------------------------------------------------------
function CraftingManager:GetAvailableRecipes(player: Player, station: string?): { {
	RecipeId: string,
	Name: string,
	Description: string,
	Category: string,
	CanCraft: boolean,
	Reason: string?,
	Ingredients: { { ItemId: string, Required: number, Have: number } },
	Results: { { ItemId: string, Quantity: number, Chance: number? } },
	CraftTime: number?,
	SuccessRate: number?,
} }
	local pData = self._playerData[player]
	if not pData then return {} end

	local recipes = {}

	for recipeId, isUnlocked in pData.UnlockedRecipes do
		if not isUnlocked then continue end

		local recipe = RecipeDatabase.GetRecipe(recipeId)
		if not recipe then continue end

		-- Filter by station if provided
		if station and recipe.Station and recipe.Station ~= station then continue end

		local canCraft, reason = self:CanCraft(player, recipeId, station)

		-- Build ingredient info with player's current counts
		local ingredientInfo = {}
		for _, ing in recipe.Ingredients do
			local have = if self._inventoryManager then self._inventoryManager:CountItem(player, ing.ItemId) else 0
			table.insert(ingredientInfo, {
				ItemId = ing.ItemId,
				Required = ing.Quantity,
				Have = have,
			})
		end

		table.insert(recipes, {
			RecipeId = recipeId,
			Name = recipe.Name,
			Description = recipe.Description,
			Category = recipe.Category,
			CanCraft = canCraft,
			Reason = reason,
			Ingredients = ingredientInfo,
			Results = recipe.Results,
			CraftTime = recipe.CraftTime,
			SuccessRate = recipe.SuccessRate,
		})
	end

	return recipes
end

---------------------------------------------------------------------
-- Serialization
---------------------------------------------------------------------
function CraftingManager:Serialize(player: Player): { UnlockedRecipes: { [string]: boolean }, Level: number, XP: number }?
	local pData = self._playerData[player]
	if not pData then return nil end
	return {
		UnlockedRecipes = pData.UnlockedRecipes,
		Level = pData.CraftingLevel,
		XP = pData.CraftingXP,
	}
end

function CraftingManager:Deserialize(player: Player, data: { UnlockedRecipes: { [string]: boolean }, Level: number, XP: number })
	self:RegisterPlayer(player)
	local pData = self._playerData[player]
	if not pData then return end

	for recipeId, unlocked in data.UnlockedRecipes do
		pData.UnlockedRecipes[recipeId] = unlocked
	end
	pData.CraftingLevel = data.Level or 1
	pData.CraftingXP = data.XP or 0
end

return CraftingManager
```

## Usage Example

```luau
-- Server setup:
local CraftingManager = require(ServerScriptService.Crafting.CraftingManager)
local crafting = CraftingManager.new()
crafting:SetInventoryManager(invManager)

-- When player joins:
crafting:RegisterPlayer(player)

-- Instant craft:
local result = crafting:CraftInstant(player, "health_potion_recipe", "AlchemyTable")
if result.Success then
    print("Crafted!", result.ItemsCreated)
end

-- Timed craft:
local started, msg, duration = crafting:StartCraft(player, "iron_sword_recipe", "Anvil")
if started then
    task.delay(duration, function()
        local result = crafting:CompleteCraft(player)
        print(result.Message)
    end)
end

-- Get recipes for UI:
local recipes = crafting:GetAvailableRecipes(player, "Anvil")
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

When the user asks to implement a crafting system, ask or infer:

- `$RECIPE_CATEGORIES` - Recipe categories: {"Weapons", "Armor", "Potions", "Materials", "Tools"}
- `$ENABLE_STATIONS` - Require crafting stations: true/false
- `$STATION_TYPES` - Station types available: {"Anvil", "Furnace", "AlchemyTable", "Workbench"}
- `$ENABLE_CRAFT_TIME` - Crafting takes time: true/false
- `$ENABLE_SUCCESS_RATE` - Crafting can fail: true/false
- `$ENABLE_CRAFTING_LEVEL` - Separate crafting skill level: true/false
- `$MAX_CRAFTING_LEVEL` - Maximum crafting level: 50
- `$ENABLE_RECIPE_UNLOCK` - Recipes must be discovered/unlocked: true/false
- `$ENABLE_BONUS_OUTPUTS` - Chance for extra outputs: true/false
- `$ENABLE_CURRENCY_COST` - Recipes cost currency too: true/false
- `$ENABLE_DATASTORE` - Persist crafting progress: true/false
- `$XP_CURVE` - XP scaling formula: "linear", "quadratic", "exponential"
