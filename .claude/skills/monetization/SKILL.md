---
name: monetization
description: |
  Roblox Monetization system - 게임패스, 개발자 상품, ProcessReceipt, 프리미엄 혜택, 구매 프롬프트, 수익화.
  GamePass checking, DevProduct purchase flow, ProcessReceipt callback, premium benefits, and purchase prompts.
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Grep
  - Glob
effort: high
---

# Monetization System Skill

Complete Roblox monetization system covering GamePasses, Developer Products, ProcessReceipt, premium benefits, and purchase prompts.

## Architecture Overview

```
ServerScriptService/
  MonetizationManager.server.luau   -- ProcessReceipt, GamePass validation, premium detection
ReplicatedStorage/
  Shared/
    ProductConfig.luau              -- Product/GamePass ID definitions
StarterGui/
  ShopUI/
    ShopWindow.client.luau          -- Purchase prompts and shop display
```

## Core Server: MonetizationManager

```luau
--!strict
-- ServerScriptService/MonetizationManager.server.luau
-- Handles all server-side monetization: GamePass ownership, DevProduct purchases, ProcessReceipt, premium.

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ProductConfig = require(ReplicatedStorage.Shared.ProductConfig)

local purchaseStore = DataStoreService:GetDataStore("PurchaseHistory_v1")

------------------------------------------------------------------------
-- Types
------------------------------------------------------------------------

export type PurchaseRecord = {
	productId: number,
	purchaseId: string,
	timestamp: number,
	granted: boolean,
}

------------------------------------------------------------------------
-- Remote setup
------------------------------------------------------------------------

local monetizationFolder = Instance.new("Folder")
monetizationFolder.Name = "MonetizationEvents"
monetizationFolder.Parent = ReplicatedStorage

local promptPurchase = Instance.new("RemoteEvent")
promptPurchase.Name = "PromptPurchase"
promptPurchase.Parent = monetizationFolder

local purchaseCompleted = Instance.new("RemoteEvent")
purchaseCompleted.Name = "PurchaseCompleted"
purchaseCompleted.Parent = monetizationFolder

local checkGamePass = Instance.new("RemoteFunction")
checkGamePass.Name = "CheckGamePass"
checkGamePass.Parent = monetizationFolder

local getPlayerProducts = Instance.new("RemoteFunction")
getPlayerProducts.Name = "GetPlayerProducts"
getPlayerProducts.Parent = monetizationFolder

------------------------------------------------------------------------
-- GamePass Cache
------------------------------------------------------------------------

local gamePassCache: { [number]: { [number]: boolean } } = {} -- userId -> { passId -> owned }

local MonetizationManager = {}

function MonetizationManager.ownsGamePass(player: Player, gamePassId: number): boolean
	local userId = player.UserId
	if not gamePassCache[userId] then
		gamePassCache[userId] = {}
	end

	-- Check cache first
	if gamePassCache[userId][gamePassId] ~= nil then
		return gamePassCache[userId][gamePassId]
	end

	-- Query MarketplaceService
	local success, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(userId, gamePassId)
	end)

	if success then
		gamePassCache[userId][gamePassId] = owns
		return owns
	end

	warn("[Monetization] Failed to check GamePass:", gamePassId)
	return false
end

function MonetizationManager.clearGamePassCache(player: Player)
	gamePassCache[player.UserId] = nil
end

------------------------------------------------------------------------
-- Premium Membership
------------------------------------------------------------------------

function MonetizationManager.isPremium(player: Player): boolean
	return player.MembershipType == Enum.MembershipType.Premium
end

function MonetizationManager.getPremiumBenefits(player: Player): { string }
	if not MonetizationManager.isPremium(player) then
		return {}
	end

	local benefits = {}
	for _, benefit in ipairs(ProductConfig.PremiumBenefits) do
		table.insert(benefits, benefit)
	end
	return benefits
end

------------------------------------------------------------------------
-- Developer Product Processing (ProcessReceipt)
------------------------------------------------------------------------

local function recordPurchase(userId: number, purchaseId: string, productId: number): boolean
	local key = "receipt_" .. purchaseId
	local success, _ = pcall(function()
		purchaseStore:SetAsync(key, {
			userId = userId,
			productId = productId,
			timestamp = os.time(),
			granted = true,
		})
	end)
	return success
end

local function isPurchaseRecorded(purchaseId: string): boolean
	local success, data = pcall(function()
		return purchaseStore:GetAsync("receipt_" .. purchaseId)
	end)
	return success and data ~= nil and data.granted == true
end

local function grantProduct(player: Player, productId: number): boolean
	local productDef = ProductConfig.DevProducts[productId]
	if not productDef then
		warn("[Monetization] Unknown product ID:", productId)
		return false
	end

	-- Grant based on product type
	if productDef.type == "currency" then
		-- TODO: integrate with currency system
		-- CurrencyManager.add(player, productDef.amount)
		print("[Monetization] Granted", productDef.amount, "currency to", player.Name)
	elseif productDef.type == "item" then
		-- TODO: integrate with inventory system
		-- InventoryManager.addItem(player, productDef.itemId)
		print("[Monetization] Granted item", productDef.itemId, "to", player.Name)
	elseif productDef.type == "boost" then
		-- TODO: apply temporary boost
		print("[Monetization] Granted boost", productDef.boostType, "to", player.Name)
	end

	purchaseCompleted:FireClient(player, {
		productId = productId,
		name = productDef.name,
		type = productDef.type,
	})

	return true
end

-- The critical ProcessReceipt callback
MarketplaceService.ProcessReceipt = function(receiptInfo): Enum.ProductPurchaseDecision
	local userId = receiptInfo.PlayerId
	local productId = receiptInfo.ProductId
	local purchaseId = receiptInfo.PurchaseId

	-- Check if already processed (idempotency)
	if isPurchaseRecorded(purchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	-- Find the player
	local player = Players:GetPlayerByUserId(userId)
	if not player then
		-- Player left; return NotProcessedYet so Roblox retries
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- Grant the product
	local granted = grantProduct(player, productId)
	if not granted then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- Record the purchase for idempotency
	local recorded = recordPurchase(userId, purchaseId, productId)
	if not recorded then
		-- Still grant since the item was given, but log the issue
		warn("[Monetization] Failed to record purchase:", purchaseId)
	end

	return Enum.ProductPurchaseDecision.PurchaseGranted
end

------------------------------------------------------------------------
-- GamePass Purchase Handling
------------------------------------------------------------------------

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, gamePassId: number, wasPurchased: boolean)
	if wasPurchased then
		-- Update cache
		if not gamePassCache[player.UserId] then
			gamePassCache[player.UserId] = {}
		end
		gamePassCache[player.UserId][gamePassId] = true

		-- Grant GamePass benefits
		local passDef = ProductConfig.GamePasses[gamePassId]
		if passDef and passDef.onPurchase then
			passDef.onPurchase(player)
		end

		purchaseCompleted:FireClient(player, {
			productId = gamePassId,
			name = if passDef then passDef.name else "GamePass",
			type = "gamepass",
		})
	end
end)

------------------------------------------------------------------------
-- Premium Changed
------------------------------------------------------------------------

Players.PlayerMembershipChanged:Connect(function(player: Player)
	if MonetizationManager.isPremium(player) then
		-- Grant premium benefits
		-- TODO: apply premium perks
		print("[Monetization] Player became premium:", player.Name)
	end
end)

------------------------------------------------------------------------
-- Remote Handlers
------------------------------------------------------------------------

promptPurchase.OnServerEvent:Connect(function(player: Player, productType: string, productId: number)
	if productType == "gamepass" then
		MarketplaceService:PromptGamePassPurchase(player, productId)
	elseif productType == "devproduct" then
		MarketplaceService:PromptProductPurchase(player, productId)
	elseif productType == "premium" then
		MarketplaceService:PromptPremiumPurchase(player)
	end
end)

checkGamePass.OnServerInvoke = function(player: Player, gamePassId: number)
	return MonetizationManager.ownsGamePass(player, gamePassId)
end

getPlayerProducts.OnServerInvoke = function(player: Player)
	local owned = {}
	for passId, passDef in pairs(ProductConfig.GamePasses) do
		owned[passId] = {
			name = passDef.name,
			owned = MonetizationManager.ownsGamePass(player, passId),
		}
	end
	return {
		gamePasses = owned,
		isPremium = MonetizationManager.isPremium(player),
	}
end

------------------------------------------------------------------------
-- Cleanup
------------------------------------------------------------------------

Players.PlayerRemoving:Connect(function(player: Player)
	MonetizationManager.clearGamePassCache(player)
end)

return MonetizationManager
```

## Product Configuration

```luau
--!strict
-- ReplicatedStorage/Shared/ProductConfig.luau

local ProductConfig = {}

export type DevProductDef = {
	name: string,
	type: "currency" | "item" | "boost",
	amount: number?,
	itemId: string?,
	boostType: string?,
	boostDuration: number?,
}

export type GamePassDef = {
	name: string,
	description: string,
	icon: string?,
	onPurchase: ((Player) -> ())?,
}

-- Developer Products (consumable purchases)
-- Key = Product ID from Roblox Creator Dashboard
ProductConfig.DevProducts: { [number]: DevProductDef } = {
	[0] = { name = "100 Coins", type = "currency", amount = 100 },       -- Replace 0 with real ID
	[1] = { name = "500 Coins", type = "currency", amount = 500 },
	[2] = { name = "2x XP Boost (30min)", type = "boost", boostType = "xp_2x", boostDuration = 1800 },
}

-- GamePasses (one-time purchases)
-- Key = GamePass ID from Roblox Creator Dashboard
ProductConfig.GamePasses: { [number]: GamePassDef } = {
	[0] = {  -- Replace 0 with real ID
		name = "VIP Pass",
		description = "Get VIP perks: 2x coins, exclusive items, VIP tag",
		onPurchase = function(player: Player)
			-- Grant VIP benefits
		end,
	},
	[1] = {
		name = "Extra Inventory",
		description = "Double your inventory space",
	},
}

-- Premium membership benefits
ProductConfig.PremiumBenefits = {
	"10% bonus coins on all purchases",
	"Exclusive premium-only shop items",
	"Priority matchmaking queue",
	"Premium badge display",
}

return ProductConfig
```

## Client Shop UI

```luau
--!strict
-- StarterGui/ShopUI/ShopWindow.client.luau
-- Displays purchasable items with prompt buttons.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local monetizationEvents = ReplicatedStorage:WaitForChild("MonetizationEvents")
local promptPurchase = monetizationEvents:WaitForChild("PromptPurchase")
local purchaseCompleted = monetizationEvents:WaitForChild("PurchaseCompleted")
local getPlayerProducts = monetizationEvents:WaitForChild("GetPlayerProducts")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ShopWindow"
screenGui.ResetOnSpawn = false
screenGui.Enabled = false
screenGui.Parent = playerGui

local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(0, 500, 0, 450)
mainFrame.Position = UDim2.new(0.5, -250, 0.5, -225)
mainFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 40)
mainFrame.BorderSizePixel = 0
mainFrame.Parent = screenGui
Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 12)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 45)
title.BackgroundTransparency = 1
title.Text = "Shop"
title.TextColor3 = Color3.fromRGB(255, 215, 0)
title.Font = Enum.Font.GothamBold
title.TextSize = 22
title.Parent = mainFrame

local scrollFrame = Instance.new("ScrollingFrame")
scrollFrame.Size = UDim2.new(1, -20, 1, -55)
scrollFrame.Position = UDim2.new(0, 10, 0, 50)
scrollFrame.BackgroundTransparency = 1
scrollFrame.ScrollBarThickness = 6
scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
scrollFrame.Parent = mainFrame

local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 8)
listLayout.Parent = scrollFrame

local function createShopItem(name: string, description: string, productType: string, productId: number, owned: boolean?)
	local item = Instance.new("Frame")
	item.Size = UDim2.new(1, 0, 0, 65)
	item.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
	item.BorderSizePixel = 0
	item.Parent = scrollFrame
	Instance.new("UICorner", item).CornerRadius = UDim.new(0, 8)

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(0.6, 0, 0, 24)
	nameLabel.Position = UDim2.new(0, 12, 0, 8)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = name
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 14
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Parent = item

	local descLabel = Instance.new("TextLabel")
	descLabel.Size = UDim2.new(0.6, 0, 0, 18)
	descLabel.Position = UDim2.new(0, 12, 0, 32)
	descLabel.BackgroundTransparency = 1
	descLabel.Text = description
	descLabel.TextColor3 = Color3.fromRGB(160, 160, 160)
	descLabel.Font = Enum.Font.Gotham
	descLabel.TextSize = 11
	descLabel.TextXAlignment = Enum.TextXAlignment.Left
	descLabel.TextTruncate = Enum.TextTruncate.AtEnd
	descLabel.Parent = item

	local buyBtn = Instance.new("TextButton")
	buyBtn.Size = UDim2.new(0, 100, 0, 35)
	buyBtn.Position = UDim2.new(1, -115, 0.5, -17)
	buyBtn.Font = Enum.Font.GothamBold
	buyBtn.TextSize = 14
	buyBtn.TextColor3 = Color3.new(1, 1, 1)
	buyBtn.Parent = item
	Instance.new("UICorner", buyBtn).CornerRadius = UDim.new(0, 6)

	if owned then
		buyBtn.Text = "Owned"
		buyBtn.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
	else
		buyBtn.Text = "Buy"
		buyBtn.BackgroundColor3 = Color3.fromRGB(0, 150, 255)
		buyBtn.MouseButton1Click:Connect(function()
			promptPurchase:FireServer(productType, productId)
		end)
	end
end

local function refreshShop()
	for _, child in ipairs(scrollFrame:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end

	local data = getPlayerProducts:InvokeServer()
	if data then
		for passId, info in pairs(data.gamePasses) do
			createShopItem(info.name, "GamePass", "gamepass", passId, info.owned)
		end
	end
end

purchaseCompleted.OnClientEvent:Connect(function(data)
	-- Show purchase confirmation
	refreshShop()
end)
```

## Usage Guide

1. **Set real product IDs** in `ProductConfig.luau` from the Roblox Creator Dashboard.
2. **ProcessReceipt** is idempotent -- safe for retries if player disconnects mid-purchase.
3. **Check GamePass** from any server script:
   ```luau
   local MonetizationManager = require(ServerScriptService.MonetizationManager)
   if MonetizationManager.ownsGamePass(player, 12345) then ... end
   ```
4. **Premium detection**: `MonetizationManager.isPremium(player)` returns true for Roblox Premium members.

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

- `$GAME_PASS_IDS` (table) -- Map of GamePass IDs to definitions. Replace defaults with real IDs.
- `$DEV_PRODUCT_IDS` (table) -- Map of Developer Product IDs to definitions. Replace defaults with real IDs.
- `$PREMIUM_BENEFITS` (string[]) -- List of premium benefit descriptions.
- `$DATASTORE_NAME` (string) -- DataStore for purchase records. Default: `"PurchaseHistory_v1"`.
- `$ENABLE_PREMIUM_PROMPTS` (boolean) -- Show premium upsell prompts. Default: `true`.
