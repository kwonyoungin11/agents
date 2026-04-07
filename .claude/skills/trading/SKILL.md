---
name: trading
description: |
  Roblox Player-to-player trading system - 거래 시스템, 교환 요청, 교환 수락/거절, 거래 창 UI, 아이템 검증, 사기 방지.
  Trade request/accept/decline flow, trade window UI, item validation, anti-scam protection, and secure exchange.
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Grep
  - Glob
effort: high
---

# Trading System Skill

This skill generates a complete player-to-player trading system with request flow, validation, anti-scam measures, and UI.

## Architecture Overview

```
ServerScriptService/
  TradeManager.server.luau       -- Server-side trade logic, validation, execution
ReplicatedStorage/
  Shared/
    TradeConfig.luau             -- Trade settings and limits
    TradeTypes.luau              -- Shared type definitions
StarterGui/
  TradeUI/
    TradeWindow.client.luau      -- Trade window UI with item slots
    TradeRequest.client.luau     -- Incoming trade request popup
```

## Core Server: TradeManager

```luau
--!strict
-- ServerScriptService/TradeManager.server.luau
-- Authoritative trade logic: request, accept, decline, validate, execute.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TradeConfig = require(ReplicatedStorage.Shared.TradeConfig)

------------------------------------------------------------------------
-- Types
------------------------------------------------------------------------

export type TradeOffer = {
	items: { string },   -- item IDs from player's inventory
	currency: number,    -- optional currency offered
}

export type TradeSession = {
	id: string,
	initiator: Player,
	target: Player,
	initiatorOffer: TradeOffer,
	targetOffer: TradeOffer,
	initiatorConfirmed: boolean,
	targetConfirmed: boolean,
	status: "pending" | "open" | "confirmed" | "completed" | "cancelled",
	createdAt: number,
}

------------------------------------------------------------------------
-- Remote setup
------------------------------------------------------------------------

local tradeFolder = Instance.new("Folder")
tradeFolder.Name = "TradeEvents"
tradeFolder.Parent = ReplicatedStorage

local function makeRemote(name: string, className: string): Instance
	local r = Instance.new(className)
	r.Name = name
	r.Parent = tradeFolder
	return r
end

local sendRequest    = makeRemote("SendRequest", "RemoteEvent")
local respondRequest = makeRemote("RespondRequest", "RemoteEvent")
local updateOffer    = makeRemote("UpdateOffer", "RemoteEvent")
local confirmTrade   = makeRemote("ConfirmTrade", "RemoteEvent")
local cancelTrade    = makeRemote("CancelTrade", "RemoteEvent")

-- Server -> Client notifications
local tradeOpened    = makeRemote("TradeOpened", "RemoteEvent")
local tradeUpdated   = makeRemote("TradeUpdated", "RemoteEvent")
local tradeClosed    = makeRemote("TradeClosed", "RemoteEvent")
local requestIncoming = makeRemote("RequestIncoming", "RemoteEvent")

------------------------------------------------------------------------
-- State
------------------------------------------------------------------------

local activeTrades: { [string]: TradeSession } = {}
local playerTrade: { [Player]: string } = {}  -- player -> tradeId
local requestCooldowns: { [Player]: number } = {}

local tradeIdCounter = 0

local function generateTradeId(): string
	tradeIdCounter += 1
	return "trade_" .. tostring(tradeIdCounter) .. "_" .. tostring(os.time())
end

------------------------------------------------------------------------
-- Inventory helpers (integrate with your inventory system)
------------------------------------------------------------------------

local function playerOwnsItem(player: Player, itemId: string): boolean
	-- TODO: Replace with your inventory check
	-- Example: return InventoryManager.hasItem(player, itemId)
	return true
end

local function playerHasCurrency(player: Player, amount: number): boolean
	-- TODO: Replace with your currency check
	return amount >= 0
end

local function transferItems(from: Player, to: Player, items: { string })
	-- TODO: Replace with actual inventory transfer
	-- InventoryManager.removeItems(from, items)
	-- InventoryManager.addItems(to, items)
end

local function transferCurrency(from: Player, to: Player, amount: number)
	-- TODO: Replace with actual currency transfer
end

------------------------------------------------------------------------
-- Validation
------------------------------------------------------------------------

local function validateOffer(player: Player, offer: TradeOffer): (boolean, string?)
	if #offer.items > TradeConfig.MaxItemsPerTrade then
		return false, "Too many items (max " .. TradeConfig.MaxItemsPerTrade .. ")"
	end

	if offer.currency < 0 then
		return false, "Invalid currency amount"
	end

	if offer.currency > TradeConfig.MaxCurrencyPerTrade then
		return false, "Currency exceeds maximum"
	end

	-- Check item ownership
	for _, itemId in ipairs(offer.items) do
		if not playerOwnsItem(player, itemId) then
			return false, "You don't own item: " .. itemId
		end
	end

	-- Check duplicate items in offer
	local seen: { [string]: boolean } = {}
	for _, itemId in ipairs(offer.items) do
		if seen[itemId] then
			return false, "Duplicate item in offer"
		end
		seen[itemId] = true
	end

	if not playerHasCurrency(player, offer.currency) then
		return false, "Insufficient currency"
	end

	return true, nil
end

local function isAntiScamSafe(trade: TradeSession): boolean
	-- Check value disparity (anti-scam)
	local initiatorValue = #trade.initiatorOffer.items + trade.initiatorOffer.currency
	local targetValue = #trade.targetOffer.items + trade.targetOffer.currency

	-- Prevent completely one-sided trades with nothing offered
	if initiatorValue == 0 and targetValue == 0 then
		return false
	end

	return true
end

------------------------------------------------------------------------
-- Core Logic
------------------------------------------------------------------------

local function createTradeRequest(initiator: Player, target: Player)
	-- Cooldown check
	local now = os.time()
	if requestCooldowns[initiator] and now - requestCooldowns[initiator] < TradeConfig.RequestCooldown then
		return
	end
	requestCooldowns[initiator] = now

	-- Cannot trade with yourself
	if initiator == target then return end

	-- Check if either player is already in a trade
	if playerTrade[initiator] or playerTrade[target] then return end

	-- Check minimum level/requirements
	-- TODO: Add your own checks here

	requestIncoming:FireClient(target, initiator.Name, initiator.UserId)
end

local function acceptTradeRequest(initiator: Player, target: Player)
	if playerTrade[initiator] or playerTrade[target] then return end

	local tradeId = generateTradeId()
	local session: TradeSession = {
		id = tradeId,
		initiator = initiator,
		target = target,
		initiatorOffer = { items = {}, currency = 0 },
		targetOffer = { items = {}, currency = 0 },
		initiatorConfirmed = false,
		targetConfirmed = false,
		status = "open",
		createdAt = os.time(),
	}

	activeTrades[tradeId] = session
	playerTrade[initiator] = tradeId
	playerTrade[target] = tradeId

	tradeOpened:FireClient(initiator, tradeId, target.Name)
	tradeOpened:FireClient(target, tradeId, initiator.Name)

	-- Auto-cancel after timeout
	task.delay(TradeConfig.TradeTimeout, function()
		if activeTrades[tradeId] and activeTrades[tradeId].status == "open" then
			cancelTradeSession(tradeId, "timeout")
		end
	end)
end

function cancelTradeSession(tradeId: string, reason: string?)
	local session = activeTrades[tradeId]
	if not session then return end

	session.status = "cancelled"
	playerTrade[session.initiator] = nil
	playerTrade[session.target] = nil

	tradeClosed:FireClient(session.initiator, reason or "cancelled")
	tradeClosed:FireClient(session.target, reason or "cancelled")

	activeTrades[tradeId] = nil
end

local function updatePlayerOffer(player: Player, items: { string }, currency: number)
	local tradeId = playerTrade[player]
	if not tradeId then return end

	local session = activeTrades[tradeId]
	if not session or session.status ~= "open" then return end

	local offer: TradeOffer = { items = items, currency = currency }
	local valid, err = validateOffer(player, offer)
	if not valid then
		-- Notify player of validation error
		return
	end

	-- Reset confirmations when offer changes
	session.initiatorConfirmed = false
	session.targetConfirmed = false

	if player == session.initiator then
		session.initiatorOffer = offer
	elseif player == session.target then
		session.targetOffer = offer
	end

	-- Notify both players of updated offers
	tradeUpdated:FireClient(session.initiator, {
		initiatorOffer = session.initiatorOffer,
		targetOffer = session.targetOffer,
		initiatorConfirmed = session.initiatorConfirmed,
		targetConfirmed = session.targetConfirmed,
	})
	tradeUpdated:FireClient(session.target, {
		initiatorOffer = session.initiatorOffer,
		targetOffer = session.targetOffer,
		initiatorConfirmed = session.initiatorConfirmed,
		targetConfirmed = session.targetConfirmed,
	})
end

local function confirmPlayerTrade(player: Player)
	local tradeId = playerTrade[player]
	if not tradeId then return end

	local session = activeTrades[tradeId]
	if not session or session.status ~= "open" then return end

	if player == session.initiator then
		session.initiatorConfirmed = true
	elseif player == session.target then
		session.targetConfirmed = true
	end

	-- Notify both of confirmation state
	tradeUpdated:FireClient(session.initiator, {
		initiatorOffer = session.initiatorOffer,
		targetOffer = session.targetOffer,
		initiatorConfirmed = session.initiatorConfirmed,
		targetConfirmed = session.targetConfirmed,
	})
	tradeUpdated:FireClient(session.target, {
		initiatorOffer = session.initiatorOffer,
		targetOffer = session.targetOffer,
		initiatorConfirmed = session.initiatorConfirmed,
		targetConfirmed = session.targetConfirmed,
	})

	-- Execute trade if both confirmed
	if session.initiatorConfirmed and session.targetConfirmed then
		executeTrade(session)
	end
end

function executeTrade(session: TradeSession)
	-- Final validation before executing
	local v1, e1 = validateOffer(session.initiator, session.initiatorOffer)
	local v2, e2 = validateOffer(session.target, session.targetOffer)

	if not v1 or not v2 then
		cancelTradeSession(session.id, "validation_failed")
		return
	end

	if not isAntiScamSafe(session) then
		cancelTradeSession(session.id, "anti_scam")
		return
	end

	-- Perform the exchange
	transferItems(session.initiator, session.target, session.initiatorOffer.items)
	transferItems(session.target, session.initiator, session.targetOffer.items)
	transferCurrency(session.initiator, session.target, session.initiatorOffer.currency)
	transferCurrency(session.target, session.initiator, session.targetOffer.currency)

	session.status = "completed"
	playerTrade[session.initiator] = nil
	playerTrade[session.target] = nil

	tradeClosed:FireClient(session.initiator, "completed")
	tradeClosed:FireClient(session.target, "completed")

	activeTrades[session.id] = nil
end

------------------------------------------------------------------------
-- Event Connections
------------------------------------------------------------------------

sendRequest.OnServerEvent:Connect(function(player: Player, targetName: string)
	local target = Players:FindFirstChild(targetName)
	if target and target:IsA("Player") then
		createTradeRequest(player, target)
	end
end)

respondRequest.OnServerEvent:Connect(function(player: Player, initiatorName: string, accepted: boolean)
	local initiator = Players:FindFirstChild(initiatorName)
	if not initiator or not initiator:IsA("Player") then return end

	if accepted then
		acceptTradeRequest(initiator, player)
	end
end)

updateOffer.OnServerEvent:Connect(function(player: Player, items: { string }, currency: number)
	updatePlayerOffer(player, items, currency)
end)

confirmTrade.OnServerEvent:Connect(function(player: Player)
	confirmPlayerTrade(player)
end)

cancelTrade.OnServerEvent:Connect(function(player: Player)
	local tradeId = playerTrade[player]
	if tradeId then
		cancelTradeSession(tradeId, "player_cancelled")
	end
end)

Players.PlayerRemoving:Connect(function(player: Player)
	local tradeId = playerTrade[player]
	if tradeId then
		cancelTradeSession(tradeId, "player_left")
	end
	requestCooldowns[player] = nil
end)
```

## Trade Configuration

```luau
--!strict
-- ReplicatedStorage/Shared/TradeConfig.luau

local TradeConfig = {}

TradeConfig.MaxItemsPerTrade = 8
TradeConfig.MaxCurrencyPerTrade = 1000000
TradeConfig.RequestCooldown = 5          -- seconds between trade requests
TradeConfig.TradeTimeout = 120           -- seconds before auto-cancel
TradeConfig.MinLevelToTrade = 1          -- minimum player level to trade
TradeConfig.RequireSecondConfirm = true  -- double-confirm before execute

return TradeConfig
```

## Client Trade Window

```luau
--!strict
-- StarterGui/TradeUI/TradeWindow.client.luau
-- Full trade window with item slots, currency input, confirm/cancel buttons.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local tradeEvents = ReplicatedStorage:WaitForChild("TradeEvents")
local tradeOpened  = tradeEvents:WaitForChild("TradeOpened")
local tradeUpdated = tradeEvents:WaitForChild("TradeUpdated")
local tradeClosed  = tradeEvents:WaitForChild("TradeClosed")

local updateOffer  = tradeEvents:WaitForChild("UpdateOffer")
local confirmTrade = tradeEvents:WaitForChild("ConfirmTrade")
local cancelTrade  = tradeEvents:WaitForChild("CancelTrade")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

------------------------------------------------------------------------
-- UI Construction
------------------------------------------------------------------------

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "TradeWindow"
screenGui.ResetOnSpawn = false
screenGui.Enabled = false
screenGui.Parent = playerGui

local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.Size = UDim2.new(0, 600, 0, 400)
mainFrame.Position = UDim2.new(0.5, -300, 0.5, -200)
mainFrame.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
mainFrame.BorderSizePixel = 0
mainFrame.Parent = screenGui

local mainCorner = Instance.new("UICorner")
mainCorner.CornerRadius = UDim.new(0, 12)
mainCorner.Parent = mainFrame

-- Title
local titleLabel = Instance.new("TextLabel")
titleLabel.Name = "Title"
titleLabel.Size = UDim2.new(1, 0, 0, 40)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "Trade"
titleLabel.TextColor3 = Color3.new(1, 1, 1)
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextSize = 20
titleLabel.Parent = mainFrame

-- Your offer panel (left)
local yourPanel = Instance.new("Frame")
yourPanel.Name = "YourOffer"
yourPanel.Size = UDim2.new(0.48, 0, 0, 280)
yourPanel.Position = UDim2.new(0.01, 0, 0, 50)
yourPanel.BackgroundColor3 = Color3.fromRGB(45, 45, 60)
yourPanel.BorderSizePixel = 0
yourPanel.Parent = mainFrame

Instance.new("UICorner", yourPanel).CornerRadius = UDim.new(0, 8)

local yourLabel = Instance.new("TextLabel")
yourLabel.Size = UDim2.new(1, 0, 0, 30)
yourLabel.BackgroundTransparency = 1
yourLabel.Text = "Your Offer"
yourLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
yourLabel.Font = Enum.Font.GothamBold
yourLabel.TextSize = 14
yourLabel.Parent = yourPanel

-- Their offer panel (right)
local theirPanel = Instance.new("Frame")
theirPanel.Name = "TheirOffer"
theirPanel.Size = UDim2.new(0.48, 0, 0, 280)
theirPanel.Position = UDim2.new(0.51, 0, 0, 50)
theirPanel.BackgroundColor3 = Color3.fromRGB(45, 45, 60)
theirPanel.BorderSizePixel = 0
theirPanel.Parent = mainFrame

Instance.new("UICorner", theirPanel).CornerRadius = UDim.new(0, 8)

local theirLabel = Instance.new("TextLabel")
theirLabel.Size = UDim2.new(1, 0, 0, 30)
theirLabel.BackgroundTransparency = 1
theirLabel.Text = "Their Offer"
theirLabel.TextColor3 = Color3.fromRGB(255, 200, 100)
theirLabel.Font = Enum.Font.GothamBold
theirLabel.TextSize = 14
theirLabel.Parent = theirPanel

-- Confirm button
local confirmBtn = Instance.new("TextButton")
confirmBtn.Name = "ConfirmButton"
confirmBtn.Size = UDim2.new(0.3, 0, 0, 40)
confirmBtn.Position = UDim2.new(0.18, 0, 1, -50)
confirmBtn.BackgroundColor3 = Color3.fromRGB(0, 170, 0)
confirmBtn.Text = "Confirm"
confirmBtn.TextColor3 = Color3.new(1, 1, 1)
confirmBtn.Font = Enum.Font.GothamBold
confirmBtn.TextSize = 16
confirmBtn.Parent = mainFrame
Instance.new("UICorner", confirmBtn).CornerRadius = UDim.new(0, 6)

-- Cancel button
local cancelBtn = Instance.new("TextButton")
cancelBtn.Name = "CancelButton"
cancelBtn.Size = UDim2.new(0.3, 0, 0, 40)
cancelBtn.Position = UDim2.new(0.52, 0, 1, -50)
cancelBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
cancelBtn.Text = "Cancel"
cancelBtn.TextColor3 = Color3.new(1, 1, 1)
cancelBtn.Font = Enum.Font.GothamBold
cancelBtn.TextSize = 16
cancelBtn.Parent = mainFrame
Instance.new("UICorner", cancelBtn).CornerRadius = UDim.new(0, 6)

-- Status label
local statusLabel = Instance.new("TextLabel")
statusLabel.Name = "Status"
statusLabel.Size = UDim2.new(1, 0, 0, 20)
statusLabel.Position = UDim2.new(0, 0, 0, 335)
statusLabel.BackgroundTransparency = 1
statusLabel.Text = ""
statusLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
statusLabel.Font = Enum.Font.Gotham
statusLabel.TextSize = 12
statusLabel.Parent = mainFrame

------------------------------------------------------------------------
-- Logic
------------------------------------------------------------------------

local currentTradeId: string? = nil

tradeOpened.OnClientEvent:Connect(function(tradeId: string, partnerName: string)
	currentTradeId = tradeId
	titleLabel.Text = "Trade with " .. partnerName
	statusLabel.Text = "Add items to your offer, then confirm."
	screenGui.Enabled = true
end)

tradeUpdated.OnClientEvent:Connect(function(data)
	-- Update UI to reflect current offers and confirmation state
	if data.initiatorConfirmed and data.targetConfirmed then
		statusLabel.Text = "Both confirmed! Completing trade..."
	elseif data.initiatorConfirmed or data.targetConfirmed then
		statusLabel.Text = "Waiting for other player to confirm..."
	else
		statusLabel.Text = "Modify your offer and confirm when ready."
	end
end)

tradeClosed.OnClientEvent:Connect(function(reason: string)
	screenGui.Enabled = false
	currentTradeId = nil
	-- Show notification based on reason
end)

confirmBtn.MouseButton1Click:Connect(function()
	confirmTrade:FireServer()
	confirmBtn.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
	statusLabel.Text = "You confirmed. Waiting for partner..."
end)

cancelBtn.MouseButton1Click:Connect(function()
	cancelTrade:FireServer()
end)
```

## Trade Request Popup

```luau
--!strict
-- StarterGui/TradeUI/TradeRequest.client.luau
-- Shows incoming trade request with accept/decline buttons.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local tradeEvents = ReplicatedStorage:WaitForChild("TradeEvents")
local requestIncoming = tradeEvents:WaitForChild("RequestIncoming")
local respondRequest  = tradeEvents:WaitForChild("RespondRequest")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "TradeRequestPopup"
screenGui.ResetOnSpawn = false
screenGui.Enabled = false
screenGui.Parent = playerGui

local popup = Instance.new("Frame")
popup.Size = UDim2.new(0, 320, 0, 140)
popup.Position = UDim2.new(0.5, -160, 0, 20)
popup.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
popup.BorderSizePixel = 0
popup.Parent = screenGui
Instance.new("UICorner", popup).CornerRadius = UDim.new(0, 10)

local msgLabel = Instance.new("TextLabel")
msgLabel.Size = UDim2.new(1, 0, 0, 60)
msgLabel.BackgroundTransparency = 1
msgLabel.Text = ""
msgLabel.TextColor3 = Color3.new(1, 1, 1)
msgLabel.Font = Enum.Font.GothamBold
msgLabel.TextSize = 16
msgLabel.TextWrapped = true
msgLabel.Parent = popup

local acceptBtn = Instance.new("TextButton")
acceptBtn.Size = UDim2.new(0.4, 0, 0, 36)
acceptBtn.Position = UDim2.new(0.05, 0, 0, 75)
acceptBtn.BackgroundColor3 = Color3.fromRGB(0, 170, 0)
acceptBtn.Text = "Accept"
acceptBtn.TextColor3 = Color3.new(1, 1, 1)
acceptBtn.Font = Enum.Font.GothamBold
acceptBtn.TextSize = 14
acceptBtn.Parent = popup
Instance.new("UICorner", acceptBtn).CornerRadius = UDim.new(0, 6)

local declineBtn = Instance.new("TextButton")
declineBtn.Size = UDim2.new(0.4, 0, 0, 36)
declineBtn.Position = UDim2.new(0.55, 0, 0, 75)
declineBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
declineBtn.Text = "Decline"
declineBtn.TextColor3 = Color3.new(1, 1, 1)
declineBtn.Font = Enum.Font.GothamBold
declineBtn.TextSize = 14
declineBtn.Parent = popup
Instance.new("UICorner", declineBtn).CornerRadius = UDim.new(0, 6)

local currentInitiator: string? = nil

requestIncoming.OnClientEvent:Connect(function(initiatorName: string, initiatorId: number)
	currentInitiator = initiatorName
	msgLabel.Text = initiatorName .. " wants to trade with you!"
	screenGui.Enabled = true

	-- Auto-decline after 15 seconds
	task.delay(15, function()
		if screenGui.Enabled and currentInitiator == initiatorName then
			respondRequest:FireServer(initiatorName, false)
			screenGui.Enabled = false
		end
	end)
end)

acceptBtn.MouseButton1Click:Connect(function()
	if currentInitiator then
		respondRequest:FireServer(currentInitiator, true)
		screenGui.Enabled = false
	end
end)

declineBtn.MouseButton1Click:Connect(function()
	if currentInitiator then
		respondRequest:FireServer(currentInitiator, false)
		screenGui.Enabled = false
	end
end)
```

## Usage Guide

1. **Initiate trade**: Client fires `SendRequest` with target player name.
2. **Accept/decline**: Target sees popup, fires `RespondRequest`.
3. **Modify offers**: Both players add items via `UpdateOffer`.
4. **Confirm**: Both press confirm; trade executes after double validation.
5. **Integrate inventory**: Replace TODO stubs in `TradeManager` with your `InventoryManager`.

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

- `$MAX_ITEMS_PER_TRADE` (number) -- Maximum items each player can offer. Default: `8`.
- `$MAX_CURRENCY_PER_TRADE` (number) -- Maximum currency per trade. Default: `1000000`.
- `$REQUEST_COOLDOWN` (number) -- Seconds between trade requests. Default: `5`.
- `$TRADE_TIMEOUT` (number) -- Seconds before trade auto-cancels. Default: `120`.
- `$REQUIRE_SECOND_CONFIRM` (boolean) -- Require double-confirmation. Default: `true`.
- `$MIN_LEVEL_TO_TRADE` (number) -- Minimum player level required. Default: `1`.
