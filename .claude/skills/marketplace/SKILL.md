---
name: marketplace
description: |
  MarketplaceService integration for Roblox. Catalog search, Developer Product and
  GamePass purchasing, insert Creator Store models via MCP tooling, asset management,
  receipt processing, and product info caching.
  마켓플레이스 서비스, 카탈로그 검색, 개발자 상품, 게임패스, 크리에이터 스토어, 에셋 관리
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
effort: high
---

# MarketplaceService Integration

Build a complete marketplace integration with GamePass/DevProduct purchasing, receipt processing, catalog browsing, Creator Store asset insertion via MCP, and product info caching.

## Architecture Overview

```
ServerScriptService/
  MarketplaceHandler.server.lua  -- Receipt processing, purchase validation
  AssetManager.server.lua        -- Server-side asset insertion and management
ReplicatedStorage/
  MarketplaceConfig.lua          -- Product definitions, price tables
  MarketplaceShared.lua          -- Shared types
StarterPlayerScripts/
  MarketplaceClient.lua          -- Purchase prompts, catalog UI, product info
StarterGui/
  ShopUI/                        -- In-game shop interface
```

## Shared Types and Config

```lua
-- ReplicatedStorage/MarketplaceShared.lua
local MarketplaceShared = {}

export type ProductType = "GamePass" | "DeveloperProduct" | "Asset" | "Bundle"

export type ProductDefinition = {
    id: number,                    -- Roblox product/gamepass/asset ID
    productType: ProductType,
    displayName: string,
    description: string,
    icon: string,
    category: string,
    robuxPrice: number?,           -- for display purposes
    serverAction: string?,         -- what to do on purchase
    grantItems: { string }?,      -- items to grant
    isConsumable: boolean?,        -- can be purchased multiple times
}

export type PurchaseRecord = {
    playerId: number,
    productId: number,
    productType: ProductType,
    purchaseTime: number,
    receiptId: string?,
}

return MarketplaceShared
```

```lua
-- ReplicatedStorage/MarketplaceConfig.lua
local MarketplaceShared = require(script.Parent:WaitForChild("MarketplaceShared"))

local MarketplaceConfig = {}

-- GamePasses (one-time purchases)
MarketplaceConfig.GamePasses: { [string]: MarketplaceShared.ProductDefinition } = {
    VIP = {
        id = 0, -- Replace with real GamePass ID
        productType = "GamePass",
        displayName = "VIP Pass",
        description = "Get exclusive VIP perks: 2x coins, special chat tag, VIP area access!",
        icon = "rbxassetid://0",
        category = "Premium",
        robuxPrice = 499,
        serverAction = "GrantVIP",
    },
    DoubleJump = {
        id = 0,
        productType = "GamePass",
        displayName = "Double Jump",
        description = "Jump again in mid-air!",
        icon = "rbxassetid://0",
        category = "Abilities",
        robuxPrice = 199,
        serverAction = "GrantDoubleJump",
    },
    SpeedBoost = {
        id = 0,
        productType = "GamePass",
        displayName = "Speed Boost",
        description = "Permanently move 25% faster!",
        icon = "rbxassetid://0",
        category = "Abilities",
        robuxPrice = 149,
        serverAction = "GrantSpeedBoost",
    },
}

-- Developer Products (consumable, can buy multiple times)
MarketplaceConfig.DeveloperProducts: { [string]: MarketplaceShared.ProductDefinition } = {
    Coins100 = {
        id = 0, -- Replace with real Developer Product ID
        productType = "DeveloperProduct",
        displayName = "100 Coins",
        description = "Get 100 coins instantly!",
        icon = "rbxassetid://0",
        category = "Currency",
        robuxPrice = 49,
        serverAction = "GrantCoins",
        grantItems = { "Coins:100" },
        isConsumable = true,
    },
    Coins500 = {
        id = 0,
        productType = "DeveloperProduct",
        displayName = "500 Coins",
        description = "Get 500 coins! Best value!",
        icon = "rbxassetid://0",
        category = "Currency",
        robuxPrice = 199,
        serverAction = "GrantCoins",
        grantItems = { "Coins:500" },
        isConsumable = true,
    },
    ExtraLife = {
        id = 0,
        productType = "DeveloperProduct",
        displayName = "Extra Life",
        description = "Respawn instantly without losing progress!",
        icon = "rbxassetid://0",
        category = "Utility",
        robuxPrice = 25,
        serverAction = "GrantExtraLife",
        isConsumable = true,
    },
}

-- Look up any product by its Roblox ID
function MarketplaceConfig.getProductById(id: number): MarketplaceShared.ProductDefinition?
    for _, product in MarketplaceConfig.GamePasses do
        if product.id == id then return product end
    end
    for _, product in MarketplaceConfig.DeveloperProducts do
        if product.id == id then return product end
    end
    return nil
end

-- Look up by name
function MarketplaceConfig.getProduct(name: string): MarketplaceShared.ProductDefinition?
    return MarketplaceConfig.GamePasses[name] or MarketplaceConfig.DeveloperProducts[name]
end

-- Get all products in a category
function MarketplaceConfig.getByCategory(category: string): { MarketplaceShared.ProductDefinition }
    local results = {}
    for _, product in MarketplaceConfig.GamePasses do
        if product.category == category then
            table.insert(results, product)
        end
    end
    for _, product in MarketplaceConfig.DeveloperProducts do
        if product.category == category then
            table.insert(results, product)
        end
    end
    return results
end

return MarketplaceConfig
```

## Server: Purchase Handler

```lua
-- ServerScriptService/MarketplaceHandler.server.lua
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MarketplaceConfig = require(ReplicatedStorage:WaitForChild("MarketplaceConfig"))

local MarketplaceRemote = Instance.new("RemoteEvent")
MarketplaceRemote.Name = "MarketplaceRemote"
MarketplaceRemote.Parent = ReplicatedStorage

local MarketplaceRequestRemote = Instance.new("RemoteEvent")
MarketplaceRequestRemote.Name = "MarketplaceRequestRemote"
MarketplaceRequestRemote.Parent = ReplicatedStorage

-- DataStore for purchase receipts (prevents double-granting)
local PurchaseStore = DataStoreService:GetDataStore("PurchaseReceipts_v1")

-- Cache for GamePass ownership checks
local gamePassCache: { [number]: { [number]: boolean } } = {} -- [userId][passId]

-- Product info cache
local productInfoCache: { [number]: any } = {}

--------------------------------------------------------------------------------
-- Purchase action handlers
--------------------------------------------------------------------------------
local PurchaseActions: { [string]: (Player, MarketplaceConfig.ProductDefinition) -> boolean } = {}

PurchaseActions.GrantVIP = function(player, product)
    player:SetAttribute("IsVIP", true)
    player:SetAttribute("CoinMultiplier", 2)
    -- Add VIP chat tag, unlock VIP area, etc.
    return true
end

PurchaseActions.GrantDoubleJump = function(player, product)
    player:SetAttribute("HasDoubleJump", true)
    return true
end

PurchaseActions.GrantSpeedBoost = function(player, product)
    player:SetAttribute("SpeedMultiplier", 1.25)
    local character = player.Character
    local humanoid = character and character:FindFirstChildWhichIsA("Humanoid")
    if humanoid then
        humanoid.WalkSpeed *= 1.25
    end
    return true
end

PurchaseActions.GrantCoins = function(player, product)
    if product.grantItems then
        for _, item in product.grantItems do
            local parts = string.split(item, ":")
            if parts[1] == "Coins" then
                local amount = tonumber(parts[2]) or 0
                local current = player:GetAttribute("Coins") or 0
                player:SetAttribute("Coins", current + amount)
            end
        end
    end
    return true
end

PurchaseActions.GrantExtraLife = function(player, product)
    local lives = player:GetAttribute("ExtraLives") or 0
    player:SetAttribute("ExtraLives", lives + 1)
    return true
end

--------------------------------------------------------------------------------
-- Check if receipt was already processed (idempotency)
--------------------------------------------------------------------------------
local function isReceiptProcessed(receiptId: string): boolean
    local success, result = pcall(function()
        return PurchaseStore:GetAsync("receipt_" .. receiptId)
    end)
    return success and result == true
end

local function markReceiptProcessed(receiptId: string)
    pcall(function()
        PurchaseStore:SetAsync("receipt_" .. receiptId, true)
    end)
end

--------------------------------------------------------------------------------
-- Process Developer Product receipts
--------------------------------------------------------------------------------
MarketplaceService.ProcessReceipt = function(receiptInfo)
    local playerId = receiptInfo.PlayerId
    local productId = receiptInfo.ProductId
    local receiptId = receiptInfo.PurchaseId

    -- Check if already processed
    if isReceiptProcessed(receiptId) then
        return Enum.ProductPurchaseDecision.PurchaseGranted
    end

    local player = Players:GetPlayerByUserId(playerId)
    if not player then
        -- Player left, don't acknowledge. They'll get it next time.
        return Enum.ProductPurchaseDecision.NotProcessedYet
    end

    -- Find product config
    local product = MarketplaceConfig.getProductById(productId)
    if not product then
        warn("[Marketplace] Unknown product ID:", productId)
        return Enum.ProductPurchaseDecision.NotProcessedYet
    end

    -- Execute the purchase action
    local actionHandler = product.serverAction and PurchaseActions[product.serverAction]
    if actionHandler then
        local success = actionHandler(player, product)
        if success then
            markReceiptProcessed(receiptId)
            MarketplaceRemote:FireClient(player, "PurchaseComplete", product.displayName)
            return Enum.ProductPurchaseDecision.PurchaseGranted
        end
    end

    return Enum.ProductPurchaseDecision.NotProcessedYet
end

--------------------------------------------------------------------------------
-- GamePass ownership checking (with cache)
--------------------------------------------------------------------------------
local function playerOwnsGamePass(player: Player, passId: number): boolean
    local userId = player.UserId

    if gamePassCache[userId] and gamePassCache[userId][passId] ~= nil then
        return gamePassCache[userId][passId]
    end

    local success, owns = pcall(function()
        return MarketplaceService:UserOwnsGamePassAsync(userId, passId)
    end)

    if success then
        if not gamePassCache[userId] then
            gamePassCache[userId] = {}
        end
        gamePassCache[userId][passId] = owns
        return owns
    end

    return false
end

--------------------------------------------------------------------------------
-- Grant GamePass perks on join and on purchase
--------------------------------------------------------------------------------
local function applyGamePassPerks(player: Player)
    for name, product in MarketplaceConfig.GamePasses do
        if product.id > 0 and playerOwnsGamePass(player, product.id) then
            local handler = product.serverAction and PurchaseActions[product.serverAction]
            if handler then
                handler(player, product)
            end
        end
    end
end

-- Listen for GamePass purchases during gameplay
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, wasPurchased)
    if not wasPurchased then return end

    -- Update cache
    if not gamePassCache[player.UserId] then
        gamePassCache[player.UserId] = {}
    end
    gamePassCache[player.UserId][passId] = true

    -- Find and apply
    local product = MarketplaceConfig.getProductById(passId)
    if product and product.serverAction then
        local handler = PurchaseActions[product.serverAction]
        if handler then
            handler(player, product)
            MarketplaceRemote:FireClient(player, "GamePassGranted", product.displayName)
        end
    end
end)

--------------------------------------------------------------------------------
-- Product info fetching (cached)
--------------------------------------------------------------------------------
local function getProductInfo(productId: number, infoType: Enum.InfoType?): any
    if productInfoCache[productId] then
        return productInfoCache[productId]
    end

    local success, info = pcall(function()
        return MarketplaceService:GetProductInfo(productId, infoType or Enum.InfoType.Product)
    end)

    if success and info then
        productInfoCache[productId] = info
        return info
    end

    return nil
end

--------------------------------------------------------------------------------
-- Handle client requests
--------------------------------------------------------------------------------
MarketplaceRequestRemote.OnServerEvent:Connect(function(player: Player, action: string, ...)
    if action == "PromptGamePass" then
        local passId: number = ...
        MarketplaceService:PromptGamePassPurchase(player, passId)

    elseif action == "PromptProduct" then
        local productId: number = ...
        MarketplaceService:PromptProductPurchase(player, productId)

    elseif action == "CheckOwnership" then
        local passId: number = ...
        local owns = playerOwnsGamePass(player, passId)
        MarketplaceRemote:FireClient(player, "OwnershipResult", passId, owns)

    elseif action == "GetProductInfo" then
        local productId: number = ...
        local info = getProductInfo(productId)
        MarketplaceRemote:FireClient(player, "ProductInfo", productId, info)
    end
end)

--------------------------------------------------------------------------------
-- Player setup
--------------------------------------------------------------------------------
Players.PlayerAdded:Connect(function(player)
    applyGamePassPerks(player)
end)

Players.PlayerRemoving:Connect(function(player)
    gamePassCache[player.UserId] = nil
end)
```

## Client: Shop UI and Prompts

```lua
-- StarterPlayerScripts/MarketplaceClient.lua
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local MarketplaceConfig = require(ReplicatedStorage:WaitForChild("MarketplaceConfig"))
local MarketplaceRemote = ReplicatedStorage:WaitForChild("MarketplaceRemote")
local MarketplaceRequestRemote = ReplicatedStorage:WaitForChild("MarketplaceRequestRemote")

local player = Players.LocalPlayer

--------------------------------------------------------------------------------
-- Create Shop UI
--------------------------------------------------------------------------------
local function createShopUI()
    local gui = Instance.new("ScreenGui")
    gui.Name = "ShopUI"
    gui.Parent = player:WaitForChild("PlayerGui")

    local mainFrame = Instance.new("Frame")
    mainFrame.Name = "ShopFrame"
    mainFrame.Size = UDim2.fromScale(0.6, 0.7)
    mainFrame.Position = UDim2.fromScale(0.2, 0.15)
    mainFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
    mainFrame.BackgroundTransparency = 0.05
    mainFrame.Visible = false
    mainFrame.Parent = gui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 12)
    corner.Parent = mainFrame

    -- Title
    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, 0, 0, 50)
    title.BackgroundTransparency = 1
    title.Text = "Shop"
    title.TextColor3 = Color3.fromRGB(255, 220, 100)
    title.TextSize = 28
    title.Font = Enum.Font.GothamBold
    title.Parent = mainFrame

    -- Close button
    local closeBtn = Instance.new("TextButton")
    closeBtn.Size = UDim2.fromOffset(36, 36)
    closeBtn.Position = UDim2.new(1, -46, 0, 7)
    closeBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
    closeBtn.Text = "X"
    closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    closeBtn.TextSize = 18
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.Parent = mainFrame

    local closeCorner = Instance.new("UICorner")
    closeCorner.CornerRadius = UDim.new(0, 8)
    closeCorner.Parent = closeBtn

    closeBtn.MouseButton1Click:Connect(function()
        mainFrame.Visible = false
    end)

    -- Category tabs
    local tabFrame = Instance.new("Frame")
    tabFrame.Size = UDim2.new(1, -20, 0, 35)
    tabFrame.Position = UDim2.fromOffset(10, 55)
    tabFrame.BackgroundTransparency = 1
    tabFrame.Parent = mainFrame

    local tabLayout = Instance.new("UIListLayout")
    tabLayout.FillDirection = Enum.FillDirection.Horizontal
    tabLayout.Padding = UDim.new(0, 5)
    tabLayout.Parent = tabFrame

    -- Scrolling product list
    local productScroll = Instance.new("ScrollingFrame")
    productScroll.Size = UDim2.new(1, -20, 1, -110)
    productScroll.Position = UDim2.fromOffset(10, 100)
    productScroll.BackgroundTransparency = 1
    productScroll.ScrollBarThickness = 6
    productScroll.Parent = mainFrame

    local productGrid = Instance.new("UIGridLayout")
    productGrid.CellSize = UDim2.fromOffset(170, 200)
    productGrid.CellPadding = UDim2.fromOffset(10, 10)
    productGrid.Parent = productScroll

    -- Build product cards
    local function showCategory(category: string)
        -- Clear existing
        for _, child in productScroll:GetChildren() do
            if child:IsA("Frame") then child:Destroy() end
        end

        local products = MarketplaceConfig.getByCategory(category)
        for _, product in products do
            local card = Instance.new("Frame")
            card.Size = UDim2.fromOffset(170, 200)
            card.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
            card.Parent = productScroll

            local cardCorner = Instance.new("UICorner")
            cardCorner.CornerRadius = UDim.new(0, 8)
            cardCorner.Parent = card

            local icon = Instance.new("ImageLabel")
            icon.Size = UDim2.new(1, -20, 0, 90)
            icon.Position = UDim2.fromOffset(10, 10)
            icon.BackgroundTransparency = 1
            icon.Image = product.icon
            icon.ScaleType = Enum.ScaleType.Fit
            icon.Parent = card

            local nameLabel = Instance.new("TextLabel")
            nameLabel.Size = UDim2.new(1, -10, 0, 22)
            nameLabel.Position = UDim2.fromOffset(5, 105)
            nameLabel.BackgroundTransparency = 1
            nameLabel.Text = product.displayName
            nameLabel.TextColor3 = Color3.fromRGB(240, 240, 240)
            nameLabel.TextSize = 14
            nameLabel.Font = Enum.Font.GothamBold
            nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
            nameLabel.Parent = card

            local descLabel = Instance.new("TextLabel")
            descLabel.Size = UDim2.new(1, -10, 0, 30)
            descLabel.Position = UDim2.fromOffset(5, 128)
            descLabel.BackgroundTransparency = 1
            descLabel.Text = product.description
            descLabel.TextColor3 = Color3.fromRGB(160, 160, 170)
            descLabel.TextSize = 11
            descLabel.Font = Enum.Font.Gotham
            descLabel.TextWrapped = true
            descLabel.TextTruncate = Enum.TextTruncate.AtEnd
            descLabel.Parent = card

            local buyBtn = Instance.new("TextButton")
            buyBtn.Size = UDim2.new(1, -20, 0, 30)
            buyBtn.Position = UDim2.new(0, 10, 1, -40)
            buyBtn.BackgroundColor3 = Color3.fromRGB(50, 170, 50)
            buyBtn.Text = product.robuxPrice and ("R$ " .. product.robuxPrice) or "Buy"
            buyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
            buyBtn.TextSize = 14
            buyBtn.Font = Enum.Font.GothamBold
            buyBtn.Parent = card

            local buyCorner = Instance.new("UICorner")
            buyCorner.CornerRadius = UDim.new(0, 6)
            buyCorner.Parent = buyBtn

            buyBtn.MouseButton1Click:Connect(function()
                if product.productType == "GamePass" then
                    MarketplaceRequestRemote:FireServer("PromptGamePass", product.id)
                elseif product.productType == "DeveloperProduct" then
                    MarketplaceRequestRemote:FireServer("PromptProduct", product.id)
                end
            end)
        end
    end

    -- Create category tabs
    local categories = { "Premium", "Abilities", "Currency", "Utility" }
    for _, cat in categories do
        local tab = Instance.new("TextButton")
        tab.Size = UDim2.fromOffset(100, 30)
        tab.BackgroundColor3 = Color3.fromRGB(50, 50, 65)
        tab.Text = cat
        tab.TextColor3 = Color3.fromRGB(200, 200, 200)
        tab.TextSize = 13
        tab.Font = Enum.Font.GothamMedium
        tab.Parent = tabFrame

        local tabCorner = Instance.new("UICorner")
        tabCorner.CornerRadius = UDim.new(0, 6)
        tabCorner.Parent = tab

        tab.MouseButton1Click:Connect(function()
            showCategory(cat)
        end)
    end

    -- Show first category by default
    showCategory(categories[1])

    return mainFrame
end

local shopFrame = createShopUI()

-- Toggle shop with keybind
local UserInputService = game:GetService("UserInputService")
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == Enum.KeyCode.P then
        shopFrame.Visible = not shopFrame.Visible
    end
end)

--------------------------------------------------------------------------------
-- Handle server responses
--------------------------------------------------------------------------------
MarketplaceRemote.OnClientEvent:Connect(function(action: string, ...)
    if action == "PurchaseComplete" then
        local productName = ...
        -- Show purchase success notification
        print("[Shop] Purchase complete:", productName)

    elseif action == "GamePassGranted" then
        local passName = ...
        print("[Shop] GamePass granted:", passName)

    elseif action == "OwnershipResult" then
        local passId, owns = ...
        print(string.format("[Shop] Ownership check: %d -> %s", passId, tostring(owns)))

    elseif action == "ProductInfo" then
        local productId, info = ...
        if info then
            print(string.format("[Shop] Product %d: %s - R$%d", productId, info.Name, info.PriceInRobux or 0))
        end
    end
end)

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------
local MarketplaceClient = {}

function MarketplaceClient.openShop()
    shopFrame.Visible = true
end

function MarketplaceClient.closeShop()
    shopFrame.Visible = false
end

function MarketplaceClient.promptGamePass(passId: number)
    MarketplaceRequestRemote:FireServer("PromptGamePass", passId)
end

function MarketplaceClient.promptProduct(productId: number)
    MarketplaceRequestRemote:FireServer("PromptProduct", productId)
end

function MarketplaceClient.checkOwnership(passId: number)
    MarketplaceRequestRemote:FireServer("CheckOwnership", passId)
end

return MarketplaceClient
```

## Creator Store Asset Insertion via MCP

When using Claude with MCP (Model Context Protocol) tools connected to Roblox Studio, you can search and insert Creator Store assets programmatically:

```lua
-- This pattern is used when Claude has MCP access to Roblox Studio
-- The MCP tool can:
-- 1. Search the Creator Store catalog for models, meshes, audio, etc.
-- 2. Insert assets into the game by asset ID
-- 3. Configure inserted models (position, properties)

-- Example MCP workflow (conceptual):
-- User: "Add a medieval castle to the map"
-- Claude uses MCP to:
--   1. Search Creator Store for "medieval castle" models
--   2. Present options to user
--   3. Insert selected model via InsertService
--   4. Position and configure the model

-- Server-side asset insertion utility
local InsertService = game:GetService("InsertService")

local function insertAsset(assetId: number, parent: Instance?, position: Vector3?): Model?
    local success, model = pcall(function()
        return InsertService:LoadAsset(assetId)
    end)

    if success and model then
        if position then
            model:PivotTo(CFrame.new(position))
        end
        model.Parent = parent or workspace
        return model
    end

    warn("[AssetManager] Failed to insert asset:", assetId)
    return nil
end
```

## Key Implementation Notes

1. **ProcessReceipt**: This callback MUST return `PurchaseGranted` only after successfully granting the item. Return `NotProcessedYet` if the player left or an error occurred -- Roblox will retry.

2. **Idempotency**: Use DataStore to track processed receipt IDs. This prevents double-granting if `ProcessReceipt` is called multiple times for the same purchase.

3. **GamePass caching**: `UserOwnsGamePassAsync` is rate-limited. Cache results per player to avoid hitting limits.

4. **Product info caching**: `GetProductInfo` calls are also rate-limited. Cache responses for the session.

5. **Purchase prompts**: Always prompt from the server side via `MarketplaceService:PromptGamePassPurchase` or `PromptProductPurchase`. The client sends a request, server validates and prompts.

6. **Categories**: Organize products into categories for the shop UI. Use `MarketplaceConfig.getByCategory()` to filter.

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

When the user asks about marketplace integration, ask:
- What products do you need? (GamePasses, Developer Products, or both)
- List each product with name, price, and what it grants
- Do you need a shop UI or just programmatic purchasing?
- Should purchases persist across sessions? (GamePasses auto-persist; DevProducts need DataStore)
- Do you need Creator Store asset insertion?
- Any promotional pricing or bundles?
