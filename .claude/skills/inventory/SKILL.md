---
name: inventory
description: |
  Roblox 인벤토리 시스템 (Inventory System) - 아이템 추가/제거/스택, 장비 슬롯, 아이템 데이터 템플릿, 최대 용량, DataStore 직렬화.
  Item management with add/remove/stack operations, equipment slots, item data templates,
  max capacity enforcement, and serialization for DataStore persistence. 로블록스 Luau 인벤토리 구현.
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
effort: high
---

# Inventory System for Roblox (Luau)

Full-featured inventory system with item stacking, equipment slots, templates, capacity limits, and DataStore serialization.

## Architecture Overview

```
InventorySystem (Server)
├── InventoryManager (add/remove/stack/swap)
├── EquipmentManager (equip/unequip slots)
├── ItemDatabase (templates, rarity, stats)
├── SerializationLayer (DataStore save/load)
└── InventoryEvents (remote events for UI sync)

InventoryClient (Client)
├── InventoryUI (grid display, drag & drop)
├── TooltipManager (item info popups)
└── EquipmentUI (paper doll display)
```

## Item Data Templates

```luau
--!strict
-- ReplicatedStorage/Data/ItemDatabase.luau

export type ItemRarity = "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary"
export type ItemCategory = "Weapon" | "Armor" | "Consumable" | "Material" | "Quest" | "Misc"
export type EquipSlot = "Head" | "Chest" | "Legs" | "Feet" | "MainHand" | "OffHand" | "Accessory1" | "Accessory2"

export type ItemTemplate = {
	Id: string,
	Name: string,
	Description: string,
	Category: ItemCategory,
	Rarity: ItemRarity,
	MaxStack: number,
	Sellable: boolean,
	SellPrice: number,
	Icon: string,                    -- rbxassetid://
	EquipSlot: EquipSlot?,           -- nil if not equippable
	Stats: { [string]: number }?,    -- bonus stats when equipped
	UseEffect: string?,              -- effect name for consumables
	UseValue: number?,               -- heal amount, buff duration, etc.
	Level: number?,                  -- required level
	Tradeable: boolean?,
}

local ItemDatabase: { [string]: ItemTemplate } = {
	iron_sword = {
		Id = "iron_sword",
		Name = "Iron Sword",
		Description = "A sturdy iron blade.",
		Category = "Weapon",
		Rarity = "Common",
		MaxStack = 1,
		Sellable = true,
		SellPrice = 50,
		Icon = "rbxassetid://0",
		EquipSlot = "MainHand",
		Stats = { Attack = 10, CritChance = 0.05 },
		Level = 1,
		Tradeable = true,
	},
	health_potion = {
		Id = "health_potion",
		Name = "Health Potion",
		Description = "Restores 50 HP.",
		Category = "Consumable",
		Rarity = "Common",
		MaxStack = 99,
		Sellable = true,
		SellPrice = 10,
		Icon = "rbxassetid://0",
		UseEffect = "Heal",
		UseValue = 50,
		Tradeable = true,
	},
	dragon_scale = {
		Id = "dragon_scale",
		Name = "Dragon Scale",
		Description = "A shimmering scale from a dragon. Used in crafting.",
		Category = "Material",
		Rarity = "Epic",
		MaxStack = 50,
		Sellable = true,
		SellPrice = 200,
		Icon = "rbxassetid://0",
		Tradeable = true,
	},
	iron_helmet = {
		Id = "iron_helmet",
		Name = "Iron Helmet",
		Description = "Basic iron head protection.",
		Category = "Armor",
		Rarity = "Common",
		MaxStack = 1,
		Sellable = true,
		SellPrice = 30,
		Icon = "rbxassetid://0",
		EquipSlot = "Head",
		Stats = { Defense = 5 },
		Level = 1,
		Tradeable = true,
	},
	quest_amulet = {
		Id = "quest_amulet",
		Name = "Ancient Amulet",
		Description = "A mysterious amulet needed by the village elder.",
		Category = "Quest",
		Rarity = "Rare",
		MaxStack = 1,
		Sellable = false,
		SellPrice = 0,
		Icon = "rbxassetid://0",
		Tradeable = false,
	},
}

-- Lookup helper
local module = {}

function module.GetTemplate(itemId: string): ItemTemplate?
	return ItemDatabase[itemId]
end

function module.GetAllByCategory(category: ItemCategory): { ItemTemplate }
	local results = {}
	for _, template in ItemDatabase do
		if template.Category == category then
			table.insert(results, template)
		end
	end
	return results
end

function module.GetAllByRarity(rarity: ItemRarity): { ItemTemplate }
	local results = {}
	for _, template in ItemDatabase do
		if template.Rarity == rarity then
			table.insert(results, template)
		end
	end
	return results
end

-- Register a new item template at runtime (e.g., from ModuleScripts)
function module.Register(template: ItemTemplate)
	assert(template.Id and template.Id ~= "", "Item must have an Id")
	assert(not ItemDatabase[template.Id], "Item ID already registered: " .. template.Id)
	ItemDatabase[template.Id] = template
end

return module
```

## Core Inventory Module (Server)

```luau
--!strict
-- ServerScriptService/Inventory/InventoryManager.luau

local ItemDatabase = require(game.ReplicatedStorage.Data.ItemDatabase)

export type InventorySlot = {
	ItemId: string,
	Quantity: number,
	Metadata: { [string]: any }?,  -- enchantments, durability, etc.
}

export type Equipment = {
	Head: InventorySlot?,
	Chest: InventorySlot?,
	Legs: InventorySlot?,
	Feet: InventorySlot?,
	MainHand: InventorySlot?,
	OffHand: InventorySlot?,
	Accessory1: InventorySlot?,
	Accessory2: InventorySlot?,
}

export type PlayerInventory = {
	Slots: { InventorySlot? },  -- array with nil gaps for empty slots
	MaxSlots: number,
	Equipment: Equipment,
	Currency: number,
}

export type AddResult = {
	Success: boolean,
	Remainder: number,       -- items that couldn't fit
	SlotsAffected: { number },
}

local InventoryManager = {}
InventoryManager.__index = InventoryManager

function InventoryManager.new()
	local self = setmetatable({}, InventoryManager)
	self._inventories = {} :: { [Player]: PlayerInventory }
	return self
end

function InventoryManager:CreateInventory(player: Player, maxSlots: number?): PlayerInventory
	local inv: PlayerInventory = {
		Slots = table.create(maxSlots or 30),
		MaxSlots = maxSlots or 30,
		Equipment = {},
		Currency = 0,
	}
	self._inventories[player] = inv
	return inv
end

function InventoryManager:GetInventory(player: Player): PlayerInventory?
	return self._inventories[player]
end

function InventoryManager:RemoveInventory(player: Player)
	self._inventories[player] = nil
end

---------------------------------------------------------------------
-- Add Items (with stacking)
---------------------------------------------------------------------
function InventoryManager:AddItem(player: Player, itemId: string, quantity: number, metadata: { [string]: any }?): AddResult
	local inv = self._inventories[player]
	if not inv then
		return { Success = false, Remainder = quantity, SlotsAffected = {} }
	end

	local template = ItemDatabase.GetTemplate(itemId)
	if not template then
		warn("Unknown item ID: " .. itemId)
		return { Success = false, Remainder = quantity, SlotsAffected = {} }
	end

	local remaining = quantity
	local affected: { number } = {}

	-- First pass: fill existing stacks
	if template.MaxStack > 1 then
		for i = 1, inv.MaxSlots do
			if remaining <= 0 then break end
			local slot = inv.Slots[i]
			if slot and slot.ItemId == itemId and slot.Quantity < template.MaxStack then
				local canAdd = math.min(remaining, template.MaxStack - slot.Quantity)
				slot.Quantity += canAdd
				remaining -= canAdd
				table.insert(affected, i)
			end
		end
	end

	-- Second pass: use empty slots
	while remaining > 0 do
		local emptyIndex = self:_findEmptySlot(inv)
		if not emptyIndex then break end

		local stackSize = math.min(remaining, template.MaxStack)
		inv.Slots[emptyIndex] = {
			ItemId = itemId,
			Quantity = stackSize,
			Metadata = if metadata then table.clone(metadata) else nil,
		}
		remaining -= stackSize
		table.insert(affected, emptyIndex)
	end

	return {
		Success = remaining == 0,
		Remainder = remaining,
		SlotsAffected = affected,
	}
end

---------------------------------------------------------------------
-- Remove Items
---------------------------------------------------------------------
function InventoryManager:RemoveItem(player: Player, itemId: string, quantity: number): boolean
	local inv = self._inventories[player]
	if not inv then return false end

	-- Check if we have enough
	local totalOwned = self:CountItem(player, itemId)
	if totalOwned < quantity then return false end

	local remaining = quantity

	-- Remove from slots (last to first to preserve stacks)
	for i = inv.MaxSlots, 1, -1 do
		if remaining <= 0 then break end
		local slot = inv.Slots[i]
		if slot and slot.ItemId == itemId then
			local toRemove = math.min(remaining, slot.Quantity)
			slot.Quantity -= toRemove
			remaining -= toRemove
			if slot.Quantity <= 0 then
				inv.Slots[i] = nil
			end
		end
	end

	return remaining == 0
end

-- Remove item at specific slot index
function InventoryManager:RemoveItemAtSlot(player: Player, slotIndex: number, quantity: number?): InventorySlot?
	local inv = self._inventories[player]
	if not inv then return nil end

	local slot = inv.Slots[slotIndex]
	if not slot then return nil end

	local removeCount = quantity or slot.Quantity
	if removeCount >= slot.Quantity then
		inv.Slots[slotIndex] = nil
		return slot
	else
		slot.Quantity -= removeCount
		return { ItemId = slot.ItemId, Quantity = removeCount, Metadata = slot.Metadata }
	end
end

---------------------------------------------------------------------
-- Count / Check
---------------------------------------------------------------------
function InventoryManager:CountItem(player: Player, itemId: string): number
	local inv = self._inventories[player]
	if not inv then return 0 end

	local count = 0
	for _, slot in inv.Slots do
		if slot and slot.ItemId == itemId then
			count += slot.Quantity
		end
	end
	return count
end

function InventoryManager:HasItem(player: Player, itemId: string, quantity: number?): boolean
	return self:CountItem(player, itemId) >= (quantity or 1)
end

function InventoryManager:IsFull(player: Player): boolean
	local inv = self._inventories[player]
	if not inv then return true end
	return self:_findEmptySlot(inv) == nil
end

function InventoryManager:GetFreeSlots(player: Player): number
	local inv = self._inventories[player]
	if not inv then return 0 end

	local free = 0
	for i = 1, inv.MaxSlots do
		if not inv.Slots[i] then
			free += 1
		end
	end
	return free
end

---------------------------------------------------------------------
-- Swap / Move Slots
---------------------------------------------------------------------
function InventoryManager:SwapSlots(player: Player, fromIndex: number, toIndex: number): boolean
	local inv = self._inventories[player]
	if not inv then return false end

	if fromIndex < 1 or fromIndex > inv.MaxSlots then return false end
	if toIndex < 1 or toIndex > inv.MaxSlots then return false end

	local fromSlot = inv.Slots[fromIndex]
	local toSlot = inv.Slots[toIndex]

	-- Try to merge stacks if same item
	if fromSlot and toSlot and fromSlot.ItemId == toSlot.ItemId then
		local template = ItemDatabase.GetTemplate(fromSlot.ItemId)
		if template and template.MaxStack > 1 then
			local canMove = math.min(fromSlot.Quantity, template.MaxStack - toSlot.Quantity)
			if canMove > 0 then
				toSlot.Quantity += canMove
				fromSlot.Quantity -= canMove
				if fromSlot.Quantity <= 0 then
					inv.Slots[fromIndex] = nil
				end
				return true
			end
		end
	end

	-- Otherwise just swap
	inv.Slots[fromIndex] = toSlot
	inv.Slots[toIndex] = fromSlot
	return true
end

---------------------------------------------------------------------
-- Equipment
---------------------------------------------------------------------
function InventoryManager:EquipItem(player: Player, slotIndex: number): boolean
	local inv = self._inventories[player]
	if not inv then return false end

	local slot = inv.Slots[slotIndex]
	if not slot then return false end

	local template = ItemDatabase.GetTemplate(slot.ItemId)
	if not template or not template.EquipSlot then return false end

	local equipSlot = template.EquipSlot :: string

	-- Unequip current item in that slot (put back in inventory)
	local currentEquip = (inv.Equipment :: any)[equipSlot] :: InventorySlot?
	if currentEquip then
		local addResult = self:AddItem(player, currentEquip.ItemId, currentEquip.Quantity, currentEquip.Metadata)
		if not addResult.Success then return false end  -- No room to unequip
	end

	-- Move item from inventory to equipment
	local item = self:RemoveItemAtSlot(player, slotIndex)
	if not item then return false end

	;(inv.Equipment :: any)[equipSlot] = {
		ItemId = item.ItemId,
		Quantity = 1,
		Metadata = item.Metadata,
	}

	return true
end

function InventoryManager:UnequipItem(player: Player, equipSlot: string): boolean
	local inv = self._inventories[player]
	if not inv then return false end

	local equipped = (inv.Equipment :: any)[equipSlot] :: InventorySlot?
	if not equipped then return false end

	local addResult = self:AddItem(player, equipped.ItemId, 1, equipped.Metadata)
	if not addResult.Success then return false end

	;(inv.Equipment :: any)[equipSlot] = nil
	return true
end

function InventoryManager:GetEquippedStats(player: Player): { [string]: number }
	local inv = self._inventories[player]
	if not inv then return {} end

	local totalStats: { [string]: number } = {}

	for _, equipSlot in { "Head", "Chest", "Legs", "Feet", "MainHand", "OffHand", "Accessory1", "Accessory2" } do
		local equipped = (inv.Equipment :: any)[equipSlot] :: InventorySlot?
		if equipped then
			local template = ItemDatabase.GetTemplate(equipped.ItemId)
			if template and template.Stats then
				for stat, value in template.Stats do
					totalStats[stat] = (totalStats[stat] or 0) + value
				end
			end
		end
	end

	return totalStats
end

---------------------------------------------------------------------
-- Use Consumable
---------------------------------------------------------------------
function InventoryManager:UseItem(player: Player, slotIndex: number): (boolean, string?, number?)
	local inv = self._inventories[player]
	if not inv then return false, nil, nil end

	local slot = inv.Slots[slotIndex]
	if not slot then return false, nil, nil end

	local template = ItemDatabase.GetTemplate(slot.ItemId)
	if not template or template.Category ~= "Consumable" then
		return false, nil, nil
	end

	-- Consume one
	slot.Quantity -= 1
	if slot.Quantity <= 0 then
		inv.Slots[slotIndex] = nil
	end

	return true, template.UseEffect, template.UseValue
end

---------------------------------------------------------------------
-- Serialization (for DataStore)
---------------------------------------------------------------------
export type SerializedInventory = {
	Slots: { { id: string, qty: number, meta: { [string]: any }? }? },
	MaxSlots: number,
	Equipment: { [string]: { id: string, qty: number, meta: { [string]: any }? } },
	Currency: number,
}

function InventoryManager:Serialize(player: Player): SerializedInventory?
	local inv = self._inventories[player]
	if not inv then return nil end

	local serializedSlots: { any } = {}
	for i = 1, inv.MaxSlots do
		local slot = inv.Slots[i]
		if slot then
			serializedSlots[i] = {
				id = slot.ItemId,
				qty = slot.Quantity,
				meta = slot.Metadata,
			}
		end
	end

	local serializedEquip: { [string]: any } = {}
	for _, equipSlot in { "Head", "Chest", "Legs", "Feet", "MainHand", "OffHand", "Accessory1", "Accessory2" } do
		local equipped = (inv.Equipment :: any)[equipSlot] :: InventorySlot?
		if equipped then
			serializedEquip[equipSlot] = {
				id = equipped.ItemId,
				qty = equipped.Quantity,
				meta = equipped.Metadata,
			}
		end
	end

	return {
		Slots = serializedSlots,
		MaxSlots = inv.MaxSlots,
		Equipment = serializedEquip,
		Currency = inv.Currency,
	}
end

function InventoryManager:Deserialize(player: Player, data: SerializedInventory)
	local inv = self:CreateInventory(player, data.MaxSlots)
	inv.Currency = data.Currency or 0

	for i, slotData in data.Slots do
		if slotData then
			inv.Slots[i] = {
				ItemId = slotData.id,
				Quantity = slotData.qty,
				Metadata = slotData.meta,
			}
		end
	end

	for equipSlot, equipData in data.Equipment do
		if equipData then
			(inv.Equipment :: any)[equipSlot] = {
				ItemId = equipData.id,
				Quantity = equipData.qty,
				Metadata = equipData.meta,
			}
		end
	end
end

---------------------------------------------------------------------
-- Internal helpers
---------------------------------------------------------------------
function InventoryManager:_findEmptySlot(inv: PlayerInventory): number?
	for i = 1, inv.MaxSlots do
		if not inv.Slots[i] then
			return i
		end
	end
	return nil
end

return InventoryManager
```

## DataStore Integration

```luau
--!strict
-- ServerScriptService/Inventory/InventoryDataStore.luau

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local InventoryManager = require(script.Parent.InventoryManager)

local DATASTORE_NAME = "PlayerInventory_v1"
local dataStore = DataStoreService:GetDataStore(DATASTORE_NAME)

local invManager = InventoryManager.new()

local function getKey(player: Player): string
	return "inv_" .. tostring(player.UserId)
end

local function loadInventory(player: Player)
	local key = getKey(player)
	local success, data = pcall(function()
		return dataStore:GetAsync(key)
	end)

	if success and data then
		invManager:Deserialize(player, data)
		print("[Inventory] Loaded for", player.Name)
	else
		invManager:CreateInventory(player, 30)
		-- Give starter items
		invManager:AddItem(player, "iron_sword", 1)
		invManager:AddItem(player, "health_potion", 5)
		print("[Inventory] Created new inventory for", player.Name)
	end
end

local function saveInventory(player: Player)
	local key = getKey(player)
	local serialized = invManager:Serialize(player)
	if not serialized then return end

	local success, err = pcall(function()
		dataStore:SetAsync(key, serialized)
	end)

	if success then
		print("[Inventory] Saved for", player.Name)
	else
		warn("[Inventory] Failed to save for", player.Name, ":", err)
	end
end

Players.PlayerAdded:Connect(loadInventory)

Players.PlayerRemoving:Connect(function(player)
	saveInventory(player)
	invManager:RemoveInventory(player)
end)

-- Auto-save every 5 minutes
task.spawn(function()
	while true do
		task.wait(300)
		for _, player in Players:GetPlayers() do
			task.spawn(saveInventory, player)
		end
	end
end)

-- Bind to close for server shutdown
game:BindToClose(function()
	for _, player in Players:GetPlayers() do
		saveInventory(player)
	end
end)

return invManager
```

## Remote Events Handler

```luau
--!strict
-- ServerScriptService/Inventory/InventoryRemotes.luau

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local invManager = require(script.Parent.InventoryDataStore)  -- returns the shared instance

local InventoryRemotes = Instance.new("Folder")
InventoryRemotes.Name = "InventoryRemotes"
InventoryRemotes.Parent = ReplicatedStorage

local SwapSlots = Instance.new("RemoteEvent")
SwapSlots.Name = "SwapSlots"
SwapSlots.Parent = InventoryRemotes

local EquipItem = Instance.new("RemoteEvent")
EquipItem.Name = "EquipItem"
EquipItem.Parent = InventoryRemotes

local UnequipItem = Instance.new("RemoteEvent")
UnequipItem.Name = "UnequipItem"
UnequipItem.Parent = InventoryRemotes

local UseItem = Instance.new("RemoteEvent")
UseItem.Name = "UseItem"
UseItem.Parent = InventoryRemotes

local SyncInventory = Instance.new("RemoteFunction")
SyncInventory.Name = "SyncInventory"
SyncInventory.Parent = InventoryRemotes

SwapSlots.OnServerEvent:Connect(function(player, fromIndex: number, toIndex: number)
	if typeof(fromIndex) ~= "number" or typeof(toIndex) ~= "number" then return end
	invManager:SwapSlots(player, fromIndex, toIndex)
end)

EquipItem.OnServerEvent:Connect(function(player, slotIndex: number)
	if typeof(slotIndex) ~= "number" then return end
	invManager:EquipItem(player, slotIndex)
end)

UnequipItem.OnServerEvent:Connect(function(player, equipSlot: string)
	if typeof(equipSlot) ~= "string" then return end
	invManager:UnequipItem(player, equipSlot)
end)

UseItem.OnServerEvent:Connect(function(player, slotIndex: number)
	if typeof(slotIndex) ~= "number" then return end
	local success, effect, value = invManager:UseItem(player, slotIndex)
	if success and effect then
		-- Apply effect server-side
		local character = player.Character
		if not character then return end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid then return end

		if effect == "Heal" and value then
			humanoid.Health = math.min(humanoid.Health + value, humanoid.MaxHealth)
		end
	end
end)

SyncInventory.OnServerInvoke = function(player)
	return invManager:Serialize(player)
end
```

## Usage Example

```luau
-- Server usage:
local invManager = require(ServerScriptService.Inventory.InventoryManager).new()
invManager:CreateInventory(player, 30)

-- Add items
local result = invManager:AddItem(player, "iron_sword", 1)
if result.Success then print("Added iron sword!") end

invManager:AddItem(player, "health_potion", 10)

-- Check items
print("Has sword?", invManager:HasItem(player, "iron_sword"))
print("Potions:", invManager:CountItem(player, "health_potion"))
print("Free slots:", invManager:GetFreeSlots(player))

-- Equip
invManager:EquipItem(player, 1)  -- equip slot 1
local stats = invManager:GetEquippedStats(player)
print("Bonus attack:", stats.Attack or 0)

-- Save to DataStore
local serialized = invManager:Serialize(player)
-- Later: invManager:Deserialize(player, savedData)
```

## 

---

## Learned Lessons

<!-- skill-evolve 에이전트가 자동으로 이 섹션에 교훈을 추가합니다 -->

## Self-Evolution Protocol

이 스킬에서 에러가 발생하면:
1. 에러의 근본 원인을 분석한다
2. 이 파일의 Learned Lessons 섹션에 교훈을 추가한다
3. 같은 실수가 반복되지 않도록 규칙화한다
4. SessionManager에 에러와 학습 내용을 기록한다

```lua
local SM = require(game.ServerStorage._RobloxEngine.SessionManager)
SM.logAction("SKILL_ERROR", "[스킬명] | [에러]")
SM.logAction("SKILL_LEARNED", "[스킬명] | [교훈]")
```

**매 작업 시 반드시 Learned Lessons를 먼저 읽고 기존 교훈을 위반하지 않는지 확인한다.**

$ARGUMENTS

When the user asks to implement an inventory system, ask or infer:

- `$MAX_SLOTS` - Maximum inventory capacity: 30 (default), 50, 100
- `$ENABLE_STACKING` - Whether items can stack: true/false
- `$EQUIPMENT_SLOTS` - Equipment slots to include: {"Head","Chest","Legs","Feet","MainHand","OffHand","Accessory1","Accessory2"}
- `$ENABLE_EQUIPMENT` - Include equipment system: true/false
- `$CURRENCY_TYPE` - Currency field name: "Gold", "Coins", "Gems"
- `$ENABLE_DATASTORE` - Persist inventory to DataStore: true/false
- `$DATASTORE_KEY_PREFIX` - DataStore key prefix: "inv_"
- `$AUTO_SAVE_INTERVAL` - Auto-save interval in seconds: 300
- `$STARTER_ITEMS` - Items given to new players: {{"iron_sword", 1}, {"health_potion", 5}}
- `$ENABLE_CONSUMABLES` - Allow using consumable items: true/false
- `$ENABLE_TRADING` - Support player-to-player trading: true/false
- `$ITEM_METADATA` - Track extra data per item (durability, enchantments): true/false
- `$ENABLE_DRAG_DROP` - Client-side drag and drop UI: true/false
