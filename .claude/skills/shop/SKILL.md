---
name: shop
description: |
  Roblox 상점 시스템 (Shop System) - 인게임 상점, 구매/판매, 가격표, 통화 확인, UI 통합, NPC 상점주인.
  In-game shop with buy/sell mechanics, price lists, currency validation, stock management,
  NPC shopkeeper integration, UI display with categories. 로블록스 Luau 상점 시스템 구현.
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
effort: high
---

# Shop System for Roblox (Luau)

In-game shop system with buy/sell, dynamic pricing, stock limits, NPC shopkeepers, category filtering, and UI integration.

## Architecture Overview

```
ShopSystem (Server)
├── ShopDatabase (shop definitions, listings)
├── ShopManager (buy/sell logic, validation)
├── PriceCalculator (dynamic pricing, discounts)
├── StockManager (limited stock, restock timers)
└── ShopEvents (remote events)

ShopClient (Client)
├── ShopUI (item grid, categories, buy/sell tabs)
├── ConfirmationDialog (purchase confirmation)
└── CurrencyDisplay (wallet display)
```

## Shop Data Templates

```luau
--!strict
-- ReplicatedStorage/Data/ShopDatabase.luau

export type ShopListing = {
	ItemId: string,
	BuyPrice: number?,           -- nil = not for sale
	SellPrice: number?,          -- nil = cannot sell to this shop
	Stock: number?,              -- nil = unlimited
	MaxStock: number?,
	RestockTime: number?,        -- seconds between restocks
	RequiredLevel: number?,
	Category: string?,           -- for UI filtering
	Featured: boolean?,          -- highlight in shop UI
	Discount: number?,           -- 0..1 discount percentage
	LimitPerPlayer: number?,     -- max purchases per player
}

export type ShopTemplate = {
	Id: string,
	Name: string,
	Description: string?,
	NPCName: string?,            -- associated NPC
	BuysFromPlayer: boolean,     -- whether shop accepts player selling
	SellPriceMultiplier: number, -- multiplier on item base sell price (0.5 = 50%)
	Currency: string,            -- "Gold", "Gems", "Tokens"
	Listings: { ShopListing },
	Categories: { string }?,     -- category order for UI
	RequiredLevel: number?,      -- minimum level to access shop
	OpenHours: { Start: number, End: number }?, -- in-game hour restriction
}

local ShopDatabase: { [string]: ShopTemplate } = {
	general_store = {
		Id = "general_store",
		Name = "General Store",
		Description = "Basic supplies for adventurers.",
		NPCName = "Merchant Bob",
		BuysFromPlayer = true,
		SellPriceMultiplier = 0.5,
		Currency = "Gold",
		Categories = { "Consumables", "Materials", "Equipment" },
		Listings = {
			{
				ItemId = "health_potion",
				BuyPrice = 25,
				SellPrice = 10,
				Category = "Consumables",
				Stock = nil,  -- unlimited
			},
			{
				ItemId = "mana_potion",
				BuyPrice = 30,
				SellPrice = 12,
				Category = "Consumables",
			},
			{
				ItemId = "iron_sword",
				BuyPrice = 100,
				SellPrice = 40,
				Category = "Equipment",
				Stock = 5,
				MaxStock = 5,
				RestockTime = 3600,  -- 1 hour
			},
			{
				ItemId = "iron_helmet",
				BuyPrice = 75,
				SellPrice = 30,
				Category = "Equipment",
				Stock = 3,
				MaxStock = 3,
				RestockTime = 3600,
			},
			{
				ItemId = "dragon_scale",
				BuyPrice = 500,
				SellPrice = 200,
				Category = "Materials",
				Stock = 1,
				MaxStock = 1,
				RestockTime = 86400,  -- 24 hours
				Featured = true,
			},
		},
	},
	blacksmith = {
		Id = "blacksmith",
		Name = "Blacksmith",
		Description = "Fine weapons and armor.",
		NPCName = "Smith Hilda",
		BuysFromPlayer = true,
		SellPriceMultiplier = 0.6,
		Currency = "Gold",
		Categories = { "Weapons", "Armor" },
		RequiredLevel = 5,
		Listings = {
			{
				ItemId = "steel_sword",
				BuyPrice = 300,
				SellPrice = 120,
				Category = "Weapons",
				RequiredLevel = 5,
			},
			{
				ItemId = "steel_armor",
				BuyPrice = 450,
				SellPrice = 180,
				Category = "Armor",
				RequiredLevel = 5,
			},
		},
	},
}

local module = {}

function module.GetShop(shopId: string): ShopTemplate?
	return ShopDatabase[shopId]
end

function module.GetShopByNPC(npcName: string): ShopTemplate?
	for _, shop in ShopDatabase do
		if shop.NPCName == npcName then
			return shop
		end
	end
	return nil
end

function module.Register(template: ShopTemplate)
	assert(template.Id and template.Id ~= "", "Shop must have an Id")
	ShopDatabase[template.Id] = template
end

return module
```

## Shop Manager (Server)

```luau
--!strict
-- ServerScriptService/Shop/ShopManager.luau

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ShopDatabase = require(ReplicatedStorage.Data.ShopDatabase)
local ItemDatabase = require(ReplicatedStorage.Data.ItemDatabase)

export type TransactionResult = {
	Success: boolean,
	Message: string,
	NewBalance: number?,
	ItemId: string?,
	Quantity: number?,
}

local ShopManager = {}
ShopManager.__index = ShopManager

function ShopManager.new()
	local self = setmetatable({}, ShopManager)
	self._inventoryManager = nil :: any  -- set externally
	self._levelingSystem = nil :: any    -- set externally
	self._stockState = {} :: { [string]: { [string]: { current: number, lastRestock: number } } }
	self._playerPurchases = {} :: { [Player]: { [string]: { [string]: number } } } -- player -> shopId -> itemId -> count
	return self
end

function ShopManager:SetInventoryManager(invManager: any)
	self._inventoryManager = invManager
end

function ShopManager:SetLevelingSystem(levelSystem: any)
	self._levelingSystem = levelSystem
end

function ShopManager:RegisterPlayer(player: Player)
	self._playerPurchases[player] = {}
end

function ShopManager:UnregisterPlayer(player: Player)
	self._playerPurchases[player] = nil
end

---------------------------------------------------------------------
-- Stock Management
---------------------------------------------------------------------
function ShopManager:InitializeStock(shopId: string)
	local shop = ShopDatabase.GetShop(shopId)
	if not shop then return end

	self._stockState[shopId] = {}
	for _, listing in shop.Listings do
		if listing.Stock then
			self._stockState[shopId][listing.ItemId] = {
				current = listing.Stock,
				lastRestock = tick(),
			}
		end
	end
end

function ShopManager:GetStock(shopId: string, itemId: string): number?
	local shopStock = self._stockState[shopId]
	if not shopStock then return nil end
	local itemStock = shopStock[itemId]
	if not itemStock then return nil end -- unlimited

	-- Check restock
	local shop = ShopDatabase.GetShop(shopId)
	if shop then
		for _, listing in shop.Listings do
			if listing.ItemId == itemId and listing.RestockTime then
				local elapsed = tick() - itemStock.lastRestock
				if elapsed >= listing.RestockTime then
					local restocks = math.floor(elapsed / listing.RestockTime)
					itemStock.current = math.min(
						itemStock.current + restocks,
						listing.MaxStock or listing.Stock or 999
					)
					itemStock.lastRestock = tick()
				end
				break
			end
		end
	end

	return itemStock.current
end

---------------------------------------------------------------------
-- Currency Helpers
---------------------------------------------------------------------
function ShopManager:GetPlayerCurrency(player: Player, _currencyType: string): number
	if not self._inventoryManager then return 0 end
	local inv = self._inventoryManager:GetInventory(player)
	if not inv then return 0 end
	return inv.Currency
end

function ShopManager:ModifyPlayerCurrency(player: Player, _currencyType: string, amount: number): boolean
	if not self._inventoryManager then return false end
	local inv = self._inventoryManager:GetInventory(player)
	if not inv then return false end

	local newBalance = inv.Currency + amount
	if newBalance < 0 then return false end
	inv.Currency = newBalance
	return true
end

---------------------------------------------------------------------
-- Buy Item
---------------------------------------------------------------------
function ShopManager:BuyItem(player: Player, shopId: string, itemId: string, quantity: number?): TransactionResult
	local qty = quantity or 1
	if qty < 1 then
		return { Success = false, Message = "Invalid quantity" }
	end

	local shop = ShopDatabase.GetShop(shopId)
	if not shop then
		return { Success = false, Message = "Shop not found" }
	end

	-- Find listing
	local listing: ShopDatabase.ShopListing? = nil
	for _, l in shop.Listings do
		if l.ItemId == itemId then
			listing = l
			break
		end
	end

	if not listing then
		return { Success = false, Message = "Item not available in this shop" }
	end

	if not listing.BuyPrice then
		return { Success = false, Message = "Item is not for sale" }
	end

	-- Level check
	local requiredLevel = listing.RequiredLevel or shop.RequiredLevel or 0
	if requiredLevel > 0 and self._levelingSystem then
		local playerLevel = self._levelingSystem:GetLevel(player) or 1
		if playerLevel < requiredLevel then
			return { Success = false, Message = "Requires level " .. requiredLevel }
		end
	end

	-- Stock check
	if listing.Stock then
		local stock = self:GetStock(shopId, itemId)
		if stock and stock < qty then
			return { Success = false, Message = "Not enough stock (available: " .. tostring(stock) .. ")" }
		end
	end

	-- Per-player limit check
	if listing.LimitPerPlayer then
		local purchases = self._playerPurchases[player]
		if purchases then
			local shopPurchases = purchases[shopId] or {}
			local bought = shopPurchases[itemId] or 0
			if bought + qty > listing.LimitPerPlayer then
				return { Success = false, Message = "Purchase limit reached" }
			end
		end
	end

	-- Calculate price with discount
	local unitPrice = listing.BuyPrice
	if listing.Discount then
		unitPrice = math.floor(unitPrice * (1 - listing.Discount))
	end
	local totalCost = unitPrice * qty

	-- Currency check
	local balance = self:GetPlayerCurrency(player, shop.Currency)
	if balance < totalCost then
		return { Success = false, Message = "Not enough " .. shop.Currency .. " (need " .. totalCost .. ", have " .. balance .. ")" }
	end

	-- Inventory space check
	if self._inventoryManager and self._inventoryManager:IsFull(player) then
		return { Success = false, Message = "Inventory is full" }
	end

	-- Execute transaction
	if not self:ModifyPlayerCurrency(player, shop.Currency, -totalCost) then
		return { Success = false, Message = "Transaction failed" }
	end

	if self._inventoryManager then
		local addResult = self._inventoryManager:AddItem(player, itemId, qty)
		if not addResult.Success then
			-- Refund
			self:ModifyPlayerCurrency(player, shop.Currency, totalCost)
			return { Success = false, Message = "Could not add item to inventory" }
		end
	end

	-- Reduce stock
	if listing.Stock then
		local shopStock = self._stockState[shopId]
		if shopStock and shopStock[itemId] then
			shopStock[itemId].current -= qty
		end
	end

	-- Track per-player purchases
	local purchases = self._playerPurchases[player]
	if purchases then
		if not purchases[shopId] then purchases[shopId] = {} end
		purchases[shopId][itemId] = (purchases[shopId][itemId] or 0) + qty
	end

	local newBalance = self:GetPlayerCurrency(player, shop.Currency)
	return {
		Success = true,
		Message = "Purchased " .. qty .. "x " .. itemId,
		NewBalance = newBalance,
		ItemId = itemId,
		Quantity = qty,
	}
end

---------------------------------------------------------------------
-- Sell Item
---------------------------------------------------------------------
function ShopManager:SellItem(player: Player, shopId: string, itemId: string, quantity: number?): TransactionResult
	local qty = quantity or 1
	if qty < 1 then
		return { Success = false, Message = "Invalid quantity" }
	end

	local shop = ShopDatabase.GetShop(shopId)
	if not shop then
		return { Success = false, Message = "Shop not found" }
	end

	if not shop.BuysFromPlayer then
		return { Success = false, Message = "This shop does not buy items" }
	end

	-- Determine sell price
	local sellPrice = 0
	-- Check if shop has a specific sell price for this item
	for _, listing in shop.Listings do
		if listing.ItemId == itemId and listing.SellPrice then
			sellPrice = listing.SellPrice
			break
		end
	end

	-- If no specific listing, use item base price * shop multiplier
	if sellPrice == 0 then
		local template = ItemDatabase.GetTemplate(itemId)
		if not template then
			return { Success = false, Message = "Unknown item" }
		end
		if not template.Sellable then
			return { Success = false, Message = "This item cannot be sold" }
		end
		sellPrice = math.floor(template.SellPrice * shop.SellPriceMultiplier)
	end

	if sellPrice <= 0 then
		return { Success = false, Message = "This item has no value" }
	end

	-- Check player has the items
	if self._inventoryManager then
		if not self._inventoryManager:HasItem(player, itemId, qty) then
			return { Success = false, Message = "You don't have enough of this item" }
		end
	end

	local totalPrice = sellPrice * qty

	-- Execute transaction
	if self._inventoryManager then
		local removed = self._inventoryManager:RemoveItem(player, itemId, qty)
		if not removed then
			return { Success = false, Message = "Could not remove item" }
		end
	end

	self:ModifyPlayerCurrency(player, shop.Currency, totalPrice)

	local newBalance = self:GetPlayerCurrency(player, shop.Currency)
	return {
		Success = true,
		Message = "Sold " .. qty .. "x " .. itemId .. " for " .. totalPrice .. " " .. shop.Currency,
		NewBalance = newBalance,
		ItemId = itemId,
		Quantity = qty,
	}
end

---------------------------------------------------------------------
-- Get Shop Info (for client display)
---------------------------------------------------------------------
function ShopManager:GetShopInfo(player: Player, shopId: string): {
	Name: string,
	Listings: { {
		ItemId: string,
		Name: string,
		BuyPrice: number?,
		SellPrice: number?,
		Stock: number?,
		Category: string?,
		Featured: boolean?,
		CanAfford: boolean,
		MeetsLevel: boolean,
	} },
	PlayerBalance: number,
	Categories: { string }?,
}?
	local shop = ShopDatabase.GetShop(shopId)
	if not shop then return nil end

	local balance = self:GetPlayerCurrency(player, shop.Currency)
	local playerLevel = if self._levelingSystem then (self._levelingSystem:GetLevel(player) or 1) else 99

	local listings = {}
	for _, listing in shop.Listings do
		local template = ItemDatabase.GetTemplate(listing.ItemId)
		local name = if template then template.Name else listing.ItemId
		local reqLevel = listing.RequiredLevel or 0

		local buyPrice = listing.BuyPrice
		if buyPrice and listing.Discount then
			buyPrice = math.floor(buyPrice * (1 - listing.Discount))
		end

		table.insert(listings, {
			ItemId = listing.ItemId,
			Name = name,
			BuyPrice = buyPrice,
			SellPrice = listing.SellPrice,
			Stock = if listing.Stock then self:GetStock(shopId, listing.ItemId) else nil,
			Category = listing.Category,
			Featured = listing.Featured,
			CanAfford = buyPrice ~= nil and balance >= buyPrice,
			MeetsLevel = playerLevel >= reqLevel,
		})
	end

	return {
		Name = shop.Name,
		Listings = listings,
		PlayerBalance = balance,
		Categories = shop.Categories,
	}
end

return ShopManager
```

## Remote Events Handler

```luau
--!strict
-- ServerScriptService/Shop/ShopRemotes.luau

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ShopManager = require(script.Parent.ShopManager)

local shop = ShopManager.new()

local ShopRemotes = Instance.new("Folder")
ShopRemotes.Name = "ShopRemotes"
ShopRemotes.Parent = ReplicatedStorage

local OpenShop = Instance.new("RemoteFunction")
OpenShop.Name = "OpenShop"
OpenShop.Parent = ShopRemotes

local BuyItem = Instance.new("RemoteFunction")
BuyItem.Name = "BuyItem"
BuyItem.Parent = ShopRemotes

local SellItem = Instance.new("RemoteFunction")
SellItem.Name = "SellItem"
SellItem.Parent = ShopRemotes

OpenShop.OnServerInvoke = function(player: Player, shopId: string)
	if typeof(shopId) ~= "string" then return nil end
	return shop:GetShopInfo(player, shopId)
end

BuyItem.OnServerInvoke = function(player: Player, shopId: string, itemId: string, quantity: number?)
	if typeof(shopId) ~= "string" or typeof(itemId) ~= "string" then
		return { Success = false, Message = "Invalid input" }
	end
	return shop:BuyItem(player, shopId, itemId, quantity)
end

SellItem.OnServerInvoke = function(player: Player, shopId: string, itemId: string, quantity: number?)
	if typeof(shopId) ~= "string" or typeof(itemId) ~= "string" then
		return { Success = false, Message = "Invalid input" }
	end
	return shop:SellItem(player, shopId, itemId, quantity)
end
```

## Usage Example

```luau
-- Server setup:
local ShopManager = require(ServerScriptService.Shop.ShopManager)
local shop = ShopManager.new()
shop:SetInventoryManager(invManager)
shop:SetLevelingSystem(levelSystem)
shop:InitializeStock("general_store")

-- Player buys an item:
local result = shop:BuyItem(player, "general_store", "health_potion", 5)
if result.Success then
    print("Bought! New balance:", result.NewBalance)
end

-- Player sells an item:
local sellResult = shop:SellItem(player, "general_store", "iron_sword", 1)
if sellResult.Success then
    print("Sold! Earned:", sellResult.Message)
end

-- Get shop display data for client:
local info = shop:GetShopInfo(player, "general_store")
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

When the user asks to implement a shop system, ask or infer:

- `$SHOP_TYPE` - Shop type: "general" (buy/sell), "buy_only", "sell_only"
- `$CURRENCY_NAME` - Currency used: "Gold", "Gems", "Coins"
- `$ENABLE_SELLING` - Players can sell items to shop: true/false
- `$SELL_MULTIPLIER` - Sell price as fraction of buy price: 0.5 (50%)
- `$ENABLE_STOCK` - Limited stock with restocking: true/false
- `$RESTOCK_INTERVAL` - Seconds between restocks: 3600
- `$ENABLE_DISCOUNTS` - Support item discounts: true/false
- `$ENABLE_LEVEL_REQUIREMENTS` - Items require player level: true/false
- `$ENABLE_PURCHASE_LIMITS` - Per-player purchase limits: true/false
- `$ENABLE_CATEGORIES` - Category tabs in UI: true/false
- `$NPC_SHOPKEEPER` - Associated NPC name: "Merchant Bob"
- `$ENABLE_CONFIRMATION` - Confirm before purchase: true/false
- `$ENABLE_BULK_BUY` - Buy multiple at once: true/false
