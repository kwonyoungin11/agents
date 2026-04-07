---
name: social
description: |
  Roblox Social system - 소셜 시스템, 친구 목록 표시, 게임 초대, 파티 시스템, 소셜 알림, 친구 초대.
  Friends list display, invite to game, party system, social notifications, and friend management.
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Grep
  - Glob
effort: high
---

# Social System Skill

Complete social system with friends list, game invites, party system, and social notifications.

## Architecture Overview

```
ServerScriptService/
  SocialManager.server.luau        -- Party management, invite handling, friend data
ReplicatedStorage/
  Shared/
    SocialConfig.luau              -- Party limits, invite settings
StarterGui/
  SocialUI/
    FriendsList.client.luau        -- Friends list panel
    PartyPanel.client.luau         -- Party management UI
    SocialNotification.client.luau -- Invite and notification popups
```

## Core Server: SocialManager

```luau
--!strict
-- ServerScriptService/SocialManager.server.luau
-- Manages parties, game invites, and friend-related features.

local Players = game:GetService("Players")
local SocialService = game:GetService("SocialService")
local TeleportService = game:GetService("TeleportService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SocialConfig = require(ReplicatedStorage.Shared.SocialConfig)

------------------------------------------------------------------------
-- Types
------------------------------------------------------------------------

export type Party = {
	id: string,
	leaderId: number,
	leaderName: string,
	members: { { userId: number, name: string } },
	maxSize: number,
	createdAt: number,
}

export type GameInvite = {
	fromUserId: number,
	fromName: string,
	partyId: string?,
	timestamp: number,
}

------------------------------------------------------------------------
-- Remote setup
------------------------------------------------------------------------

local socialFolder = Instance.new("Folder")
socialFolder.Name = "SocialEvents"
socialFolder.Parent = ReplicatedStorage

local createParty     = Instance.new("RemoteEvent")
createParty.Name = "CreateParty"
createParty.Parent = socialFolder

local inviteToParty   = Instance.new("RemoteEvent")
inviteToParty.Name = "InviteToParty"
inviteToParty.Parent = socialFolder

local respondInvite   = Instance.new("RemoteEvent")
respondInvite.Name = "RespondInvite"
respondInvite.Parent = socialFolder

local leaveParty      = Instance.new("RemoteEvent")
leaveParty.Name = "LeaveParty"
leaveParty.Parent = socialFolder

local kickFromParty   = Instance.new("RemoteEvent")
kickFromParty.Name = "KickFromParty"
kickFromParty.Parent = socialFolder

local promoteLeader   = Instance.new("RemoteEvent")
promoteLeader.Name = "PromoteLeader"
promoteLeader.Parent = socialFolder

local sendGameInvite  = Instance.new("RemoteEvent")
sendGameInvite.Name = "SendGameInvite"
sendGameInvite.Parent = socialFolder

-- Server -> Client
local partyUpdated    = Instance.new("RemoteEvent")
partyUpdated.Name = "PartyUpdated"
partyUpdated.Parent = socialFolder

local inviteReceived  = Instance.new("RemoteEvent")
inviteReceived.Name = "InviteReceived"
inviteReceived.Parent = socialFolder

local socialNotification = Instance.new("RemoteEvent")
socialNotification.Name = "SocialNotification"
socialNotification.Parent = socialFolder

local getFriendsList  = Instance.new("RemoteFunction")
getFriendsList.Name = "GetFriendsList"
getFriendsList.Parent = socialFolder

local getPartyInfo    = Instance.new("RemoteFunction")
getPartyInfo.Name = "GetPartyInfo"
getPartyInfo.Parent = socialFolder

------------------------------------------------------------------------
-- State
------------------------------------------------------------------------

local parties: { [string]: Party } = {}
local playerParty: { [number]: string } = {}  -- userId -> partyId
local pendingInvites: { [number]: { GameInvite } } = {}  -- targetUserId -> invites

local partyStore = MemoryStoreService:GetSortedMap("Parties_v1")

local SocialManager = {}

------------------------------------------------------------------------
-- Party Management
------------------------------------------------------------------------

local function generatePartyId(): string
	return "party_" .. HttpService:GenerateGUID(false)
end

function SocialManager.createParty(leader: Player): Party?
	local userId = leader.UserId

	-- Already in a party
	if playerParty[userId] then
		SocialManager.leaveParty(leader)
	end

	local partyId = generatePartyId()
	local party: Party = {
		id = partyId,
		leaderId = userId,
		leaderName = leader.Name,
		members = { { userId = userId, name = leader.Name } },
		maxSize = SocialConfig.MaxPartySize,
		createdAt = os.time(),
	}

	parties[partyId] = party
	playerParty[userId] = partyId

	-- Store in MemoryStore for cross-server
	pcall(function()
		partyStore:SetAsync(partyId, party, SocialConfig.PartyTTL)
	end)

	SocialManager.broadcastPartyUpdate(partyId)
	socialNotification:FireClient(leader, "Party created! Invite friends to join.")

	return party
end

function SocialManager.joinParty(player: Player, partyId: string): boolean
	local party = parties[partyId]
	if not party then return false end

	if #party.members >= party.maxSize then
		socialNotification:FireClient(player, "Party is full.")
		return false
	end

	-- Leave existing party
	if playerParty[player.UserId] then
		SocialManager.leaveParty(player)
	end

	table.insert(party.members, { userId = player.UserId, name = player.Name })
	playerParty[player.UserId] = partyId

	SocialManager.broadcastPartyUpdate(partyId)

	-- Notify party members
	for _, member in ipairs(party.members) do
		local memberPlayer = Players:GetPlayerByUserId(member.userId)
		if memberPlayer and memberPlayer ~= player then
			socialNotification:FireClient(memberPlayer, player.Name .. " joined the party!")
		end
	end

	return true
end

function SocialManager.leaveParty(player: Player)
	local partyId = playerParty[player.UserId]
	if not partyId then return end

	local party = parties[partyId]
	if not party then
		playerParty[player.UserId] = nil
		return
	end

	-- Remove from members
	for i, member in ipairs(party.members) do
		if member.userId == player.UserId then
			table.remove(party.members, i)
			break
		end
	end

	playerParty[player.UserId] = nil

	if #party.members == 0 then
		-- Disband empty party
		parties[partyId] = nil
		pcall(function()
			partyStore:RemoveAsync(partyId)
		end)
	else
		-- Transfer leadership if leader left
		if party.leaderId == player.UserId then
			party.leaderId = party.members[1].userId
			party.leaderName = party.members[1].name
		end

		SocialManager.broadcastPartyUpdate(partyId)

		-- Notify remaining members
		for _, member in ipairs(party.members) do
			local memberPlayer = Players:GetPlayerByUserId(member.userId)
			if memberPlayer then
				socialNotification:FireClient(memberPlayer, player.Name .. " left the party.")
			end
		end
	end
end

function SocialManager.kickMember(leader: Player, targetUserId: number)
	local partyId = playerParty[leader.UserId]
	if not partyId then return end

	local party = parties[partyId]
	if not party or party.leaderId ~= leader.UserId then return end

	local targetPlayer = Players:GetPlayerByUserId(targetUserId)
	if targetPlayer then
		SocialManager.leaveParty(targetPlayer)
		socialNotification:FireClient(targetPlayer, "You were removed from the party.")
	end
end

function SocialManager.transferLeadership(currentLeader: Player, newLeaderId: number)
	local partyId = playerParty[currentLeader.UserId]
	if not partyId then return end

	local party = parties[partyId]
	if not party or party.leaderId ~= currentLeader.UserId then return end

	-- Verify new leader is in party
	for _, member in ipairs(party.members) do
		if member.userId == newLeaderId then
			party.leaderId = newLeaderId
			party.leaderName = member.name
			SocialManager.broadcastPartyUpdate(partyId)
			return
		end
	end
end

function SocialManager.broadcastPartyUpdate(partyId: string)
	local party = parties[partyId]
	if not party then return end

	local partyData = {
		id = party.id,
		leaderId = party.leaderId,
		leaderName = party.leaderName,
		members = party.members,
		maxSize = party.maxSize,
	}

	for _, member in ipairs(party.members) do
		local memberPlayer = Players:GetPlayerByUserId(member.userId)
		if memberPlayer then
			partyUpdated:FireClient(memberPlayer, partyData)
		end
	end

	-- Update MemoryStore
	pcall(function()
		partyStore:SetAsync(partyId, party, SocialConfig.PartyTTL)
	end)
end

------------------------------------------------------------------------
-- Invites
------------------------------------------------------------------------

function SocialManager.sendPartyInvite(from: Player, targetPlayer: Player)
	local partyId = playerParty[from.UserId]
	if not partyId then
		-- Auto-create party
		SocialManager.createParty(from)
		partyId = playerParty[from.UserId]
	end

	if not partyId then return end

	-- Check if target already in a party
	if playerParty[targetPlayer.UserId] == partyId then
		socialNotification:FireClient(from, targetPlayer.Name .. " is already in your party.")
		return
	end

	local invite: GameInvite = {
		fromUserId = from.UserId,
		fromName = from.Name,
		partyId = partyId,
		timestamp = os.time(),
	}

	inviteReceived:FireClient(targetPlayer, {
		type = "party",
		fromName = from.Name,
		fromUserId = from.UserId,
		partyId = partyId,
	})

	socialNotification:FireClient(from, "Invite sent to " .. targetPlayer.Name .. "!")
end

function SocialManager.sendGameInvite(from: Player, targetUserId: number)
	-- Use SocialService for official game invites
	local success, err = pcall(function()
		SocialService:PromptGameInvite(from)
	end)

	if not success then
		warn("[Social] Game invite failed:", err)
	end
end

------------------------------------------------------------------------
-- Friends
------------------------------------------------------------------------

function SocialManager.getFriendsInGame(player: Player): { { userId: number, name: string, isInParty: boolean } }
	local friends: { { userId: number, name: string, isInParty: boolean } } = {}

	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		if otherPlayer ~= player then
			local isFriend = false
			pcall(function()
				isFriend = player:IsFriendsWith(otherPlayer.UserId)
			end)

			if isFriend then
				table.insert(friends, {
					userId = otherPlayer.UserId,
					name = otherPlayer.Name,
					isInParty = playerParty[otherPlayer.UserId] ~= nil,
				})
			end
		end
	end

	return friends
end

function SocialManager.getOnlineFriends(player: Player): { { userId: number, name: string, inGame: boolean } }
	local result: { { userId: number, name: string, inGame: boolean } } = {}

	-- Get friends in this server
	local inGameFriends = SocialManager.getFriendsInGame(player)
	for _, friend in ipairs(inGameFriends) do
		table.insert(result, {
			userId = friend.userId,
			name = friend.name,
			inGame = true,
		})
	end

	return result
end

------------------------------------------------------------------------
-- Remote Handlers
------------------------------------------------------------------------

createParty.OnServerEvent:Connect(function(player: Player)
	SocialManager.createParty(player)
end)

inviteToParty.OnServerEvent:Connect(function(player: Player, targetName: string)
	local target = Players:FindFirstChild(targetName)
	if target and target:IsA("Player") then
		SocialManager.sendPartyInvite(player, target)
	end
end)

respondInvite.OnServerEvent:Connect(function(player: Player, partyId: string, accepted: boolean)
	if accepted then
		SocialManager.joinParty(player, partyId)
	end
end)

leaveParty.OnServerEvent:Connect(function(player: Player)
	SocialManager.leaveParty(player)
end)

kickFromParty.OnServerEvent:Connect(function(player: Player, targetUserId: number)
	SocialManager.kickMember(player, targetUserId)
end)

promoteLeader.OnServerEvent:Connect(function(player: Player, targetUserId: number)
	SocialManager.transferLeadership(player, targetUserId)
end)

sendGameInvite.OnServerEvent:Connect(function(player: Player)
	SocialManager.sendGameInvite(player, 0)
end)

getFriendsList.OnServerInvoke = function(player: Player)
	return SocialManager.getOnlineFriends(player)
end

getPartyInfo.OnServerInvoke = function(player: Player)
	local partyId = playerParty[player.UserId]
	if not partyId then return nil end

	local party = parties[partyId]
	if not party then return nil end

	return {
		id = party.id,
		leaderId = party.leaderId,
		leaderName = party.leaderName,
		members = party.members,
		maxSize = party.maxSize,
	}
end

Players.PlayerRemoving:Connect(function(player: Player)
	SocialManager.leaveParty(player)
	pendingInvites[player.UserId] = nil
end)

return SocialManager
```

## Social Configuration

```luau
--!strict
-- ReplicatedStorage/Shared/SocialConfig.luau

local SocialConfig = {}

SocialConfig.MaxPartySize = 4
SocialConfig.InviteExpiration = 60     -- seconds before invite expires
SocialConfig.PartyTTL = 3600          -- MemoryStore TTL for party data (1 hour)
SocialConfig.MaxPendingInvites = 5    -- max invites per player at once
SocialConfig.InviteCooldown = 10      -- seconds between invites to same player

return SocialConfig
```

## Client Friends List

```luau
--!strict
-- StarterGui/SocialUI/FriendsList.client.luau
-- Friends panel showing online friends with invite buttons.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local socialEvents = ReplicatedStorage:WaitForChild("SocialEvents")
local getFriendsList = socialEvents:WaitForChild("GetFriendsList")
local inviteToParty = socialEvents:WaitForChild("InviteToParty")
local sendGameInvite = socialEvents:WaitForChild("SendGameInvite")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "FriendsPanel"
screenGui.ResetOnSpawn = false
screenGui.Enabled = false
screenGui.Parent = playerGui

local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(0, 300, 0, 420)
mainFrame.Position = UDim2.new(0, 10, 0.5, -210)
mainFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 40)
mainFrame.BorderSizePixel = 0
mainFrame.Parent = screenGui
Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 12)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 40)
title.BackgroundTransparency = 1
title.Text = "Friends In Server"
title.TextColor3 = Color3.new(1, 1, 1)
title.Font = Enum.Font.GothamBold
title.TextSize = 18
title.Parent = mainFrame

-- Invite all button
local inviteAllBtn = Instance.new("TextButton")
inviteAllBtn.Size = UDim2.new(0, 100, 0, 28)
inviteAllBtn.Position = UDim2.new(1, -110, 0, 8)
inviteAllBtn.BackgroundColor3 = Color3.fromRGB(0, 150, 255)
inviteAllBtn.Text = "Invite All"
inviteAllBtn.TextColor3 = Color3.new(1, 1, 1)
inviteAllBtn.Font = Enum.Font.GothamBold
inviteAllBtn.TextSize = 12
inviteAllBtn.Parent = mainFrame
Instance.new("UICorner", inviteAllBtn).CornerRadius = UDim.new(0, 6)

local scrollFrame = Instance.new("ScrollingFrame")
scrollFrame.Size = UDim2.new(1, -16, 1, -55)
scrollFrame.Position = UDim2.new(0, 8, 0, 48)
scrollFrame.BackgroundTransparency = 1
scrollFrame.ScrollBarThickness = 5
scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
scrollFrame.Parent = mainFrame

local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 5)
listLayout.Parent = scrollFrame

local function refresh()
	for _, child in ipairs(scrollFrame:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end

	local friends = getFriendsList:InvokeServer()
	if not friends or #friends == 0 then
		local emptyLabel = Instance.new("TextLabel")
		emptyLabel.Size = UDim2.new(1, 0, 0, 40)
		emptyLabel.BackgroundTransparency = 1
		emptyLabel.Text = "No friends in this server"
		emptyLabel.TextColor3 = Color3.fromRGB(120, 120, 120)
		emptyLabel.Font = Enum.Font.Gotham
		emptyLabel.TextSize = 13
		emptyLabel.Parent = scrollFrame
		return
	end

	for _, friend in ipairs(friends) do
		local card = Instance.new("Frame")
		card.Size = UDim2.new(1, 0, 0, 48)
		card.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
		card.BorderSizePixel = 0
		card.Parent = scrollFrame
		Instance.new("UICorner", card).CornerRadius = UDim.new(0, 8)

		-- Avatar thumbnail
		local avatar = Instance.new("ImageLabel")
		avatar.Size = UDim2.new(0, 34, 0, 34)
		avatar.Position = UDim2.new(0, 7, 0.5, -17)
		avatar.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
		avatar.Parent = card
		Instance.new("UICorner", avatar).CornerRadius = UDim.new(1, 0)

		pcall(function()
			local thumbUrl = Players:GetUserThumbnailAsync(
				friend.userId,
				Enum.ThumbnailType.HeadShot,
				Enum.ThumbnailSize.Size48x48
			)
			avatar.Image = thumbUrl
		end)

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Size = UDim2.new(0.5, 0, 0, 20)
		nameLabel.Position = UDim2.new(0, 48, 0.5, -10)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Text = friend.name
		nameLabel.TextColor3 = Color3.new(1, 1, 1)
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.TextSize = 13
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.Parent = card

		local invBtn = Instance.new("TextButton")
		invBtn.Size = UDim2.new(0, 70, 0, 28)
		invBtn.Position = UDim2.new(1, -80, 0.5, -14)
		invBtn.BackgroundColor3 = Color3.fromRGB(0, 150, 255)
		invBtn.Text = "Invite"
		invBtn.TextColor3 = Color3.new(1, 1, 1)
		invBtn.Font = Enum.Font.GothamBold
		invBtn.TextSize = 12
		invBtn.Parent = card
		Instance.new("UICorner", invBtn).CornerRadius = UDim.new(0, 6)

		invBtn.MouseButton1Click:Connect(function()
			inviteToParty:FireServer(friend.name)
			invBtn.Text = "Sent!"
			invBtn.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
			task.delay(3, function()
				invBtn.Text = "Invite"
				invBtn.BackgroundColor3 = Color3.fromRGB(0, 150, 255)
			end)
		end)
	end
end

inviteAllBtn.MouseButton1Click:Connect(function()
	sendGameInvite:FireServer()
end)
```

## Client Party Panel

```luau
--!strict
-- StarterGui/SocialUI/PartyPanel.client.luau
-- Party member display, leave/kick buttons, leadership controls.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local socialEvents = ReplicatedStorage:WaitForChild("SocialEvents")
local createPartyEvent = socialEvents:WaitForChild("CreateParty")
local leavePartyEvent = socialEvents:WaitForChild("LeaveParty")
local kickFromPartyEvent = socialEvents:WaitForChild("KickFromParty")
local partyUpdatedEvent = socialEvents:WaitForChild("PartyUpdated")
local getPartyInfo = socialEvents:WaitForChild("GetPartyInfo")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "PartyPanel"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

local partyFrame = Instance.new("Frame")
partyFrame.Size = UDim2.new(0, 220, 0, 200)
partyFrame.Position = UDim2.new(1, -230, 0.5, -100)
partyFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 40)
partyFrame.BackgroundTransparency = 0.1
partyFrame.BorderSizePixel = 0
partyFrame.Visible = false
partyFrame.Parent = screenGui
Instance.new("UICorner", partyFrame).CornerRadius = UDim.new(0, 10)

local partyTitle = Instance.new("TextLabel")
partyTitle.Size = UDim2.new(1, 0, 0, 30)
partyTitle.BackgroundTransparency = 1
partyTitle.Text = "Party"
partyTitle.TextColor3 = Color3.new(1, 1, 1)
partyTitle.Font = Enum.Font.GothamBold
partyTitle.TextSize = 15
partyTitle.Parent = partyFrame

local memberList = Instance.new("Frame")
memberList.Size = UDim2.new(1, -12, 1, -70)
memberList.Position = UDim2.new(0, 6, 0, 32)
memberList.BackgroundTransparency = 1
memberList.Parent = partyFrame

local memberLayout = Instance.new("UIListLayout")
memberLayout.Padding = UDim.new(0, 4)
memberLayout.Parent = memberList

local leaveBtn = Instance.new("TextButton")
leaveBtn.Size = UDim2.new(1, -12, 0, 30)
leaveBtn.Position = UDim2.new(0, 6, 1, -36)
leaveBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
leaveBtn.Text = "Leave Party"
leaveBtn.TextColor3 = Color3.new(1, 1, 1)
leaveBtn.Font = Enum.Font.GothamBold
leaveBtn.TextSize = 13
leaveBtn.Parent = partyFrame
Instance.new("UICorner", leaveBtn).CornerRadius = UDim.new(0, 6)

-- No party: show create button
local createBtn = Instance.new("TextButton")
createBtn.Size = UDim2.new(0, 140, 0, 35)
createBtn.Position = UDim2.new(1, -150, 0.5, 120)
createBtn.BackgroundColor3 = Color3.fromRGB(0, 150, 255)
createBtn.Text = "Create Party"
createBtn.TextColor3 = Color3.new(1, 1, 1)
createBtn.Font = Enum.Font.GothamBold
createBtn.TextSize = 14
createBtn.Visible = true
createBtn.Parent = screenGui
Instance.new("UICorner", createBtn).CornerRadius = UDim.new(0, 8)

local function updatePartyUI(data: { [string]: any }?)
	-- Clear member list
	for _, child in ipairs(memberList:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end

	if not data then
		partyFrame.Visible = false
		createBtn.Visible = true
		return
	end

	partyFrame.Visible = true
	createBtn.Visible = false
	partyTitle.Text = "Party (" .. tostring(#data.members) .. "/" .. tostring(data.maxSize) .. ")"

	for _, member in ipairs(data.members) do
		local memberFrame = Instance.new("Frame")
		memberFrame.Size = UDim2.new(1, 0, 0, 26)
		memberFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
		memberFrame.BorderSizePixel = 0
		memberFrame.Parent = memberList
		Instance.new("UICorner", memberFrame).CornerRadius = UDim.new(0, 5)

		local isLeader = member.userId == data.leaderId
		local nameText = if isLeader then member.name .. " (Leader)" else member.name

		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, -10, 1, 0)
		label.Position = UDim2.new(0, 8, 0, 0)
		label.BackgroundTransparency = 1
		label.Text = nameText
		label.TextColor3 = if isLeader then Color3.fromRGB(255, 215, 0) else Color3.new(1, 1, 1)
		label.Font = Enum.Font.Gotham
		label.TextSize = 12
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.Parent = memberFrame

		-- Kick button (only for leader, not self)
		if data.leaderId == player.UserId and member.userId ~= player.UserId then
			local kickBtn = Instance.new("TextButton")
			kickBtn.Size = UDim2.new(0, 22, 0, 22)
			kickBtn.Position = UDim2.new(1, -28, 0.5, -11)
			kickBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
			kickBtn.Text = "X"
			kickBtn.TextColor3 = Color3.new(1, 1, 1)
			kickBtn.Font = Enum.Font.GothamBold
			kickBtn.TextSize = 10
			kickBtn.Parent = memberFrame
			Instance.new("UICorner", kickBtn).CornerRadius = UDim.new(0, 4)

			kickBtn.MouseButton1Click:Connect(function()
				kickFromPartyEvent:FireServer(member.userId)
			end)
		end
	end
end

createBtn.MouseButton1Click:Connect(function()
	createPartyEvent:FireServer()
end)

leaveBtn.MouseButton1Click:Connect(function()
	leavePartyEvent:FireServer()
	updatePartyUI(nil)
end)

partyUpdatedEvent.OnClientEvent:Connect(function(data)
	updatePartyUI(data)
end)

-- Initial check
task.delay(1, function()
	local info = getPartyInfo:InvokeServer()
	updatePartyUI(info)
end)
```

## Social Notification

```luau
--!strict
-- StarterGui/SocialUI/SocialNotification.client.luau
-- Shows invite popups and social notifications.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local socialEvents = ReplicatedStorage:WaitForChild("SocialEvents")
local inviteReceived = socialEvents:WaitForChild("InviteReceived")
local respondInvite = socialEvents:WaitForChild("RespondInvite")
local socialNotification = socialEvents:WaitForChild("SocialNotification")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "SocialNotifications"
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 8
screenGui.Parent = playerGui

local notifContainer = Instance.new("Frame")
notifContainer.Size = UDim2.new(0, 320, 1, 0)
notifContainer.Position = UDim2.new(1, -330, 0, 0)
notifContainer.BackgroundTransparency = 1
notifContainer.Parent = screenGui

local notifLayout = Instance.new("UIListLayout")
notifLayout.VerticalAlignment = Enum.VerticalAlignment.Top
notifLayout.Padding = UDim.new(0, 6)
notifLayout.Parent = notifContainer

local function showNotification(text: string, duration: number?)
	local dur = duration or 4

	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(1, 0, 0, 45)
	frame.BackgroundColor3 = Color3.fromRGB(30, 30, 45)
	frame.BorderSizePixel = 0
	frame.BackgroundTransparency = 1
	frame.Parent = notifContainer
	Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -16, 1, 0)
	label.Position = UDim2.new(0, 8, 0, 0)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Font = Enum.Font.Gotham
	label.TextSize = 13
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextWrapped = true
	label.Parent = frame

	TweenService:Create(frame, TweenInfo.new(0.3), { BackgroundTransparency = 0 }):Play()

	task.delay(dur, function()
		local tween = TweenService:Create(frame, TweenInfo.new(0.3), { BackgroundTransparency = 1 })
		tween:Play()
		tween.Completed:Wait()
		frame:Destroy()
	end)
end

local function showInvitePopup(data: { [string]: any })
	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(1, 0, 0, 75)
	frame.BackgroundColor3 = Color3.fromRGB(30, 40, 55)
	frame.BorderSizePixel = 0
	frame.Parent = notifContainer
	Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)

	local msgLabel = Instance.new("TextLabel")
	msgLabel.Size = UDim2.new(1, -10, 0, 30)
	msgLabel.Position = UDim2.new(0, 8, 0, 5)
	msgLabel.BackgroundTransparency = 1
	msgLabel.Text = data.fromName .. " invited you to their party!"
	msgLabel.TextColor3 = Color3.new(1, 1, 1)
	msgLabel.Font = Enum.Font.GothamBold
	msgLabel.TextSize = 13
	msgLabel.TextXAlignment = Enum.TextXAlignment.Left
	msgLabel.TextWrapped = true
	msgLabel.Parent = frame

	local acceptBtn = Instance.new("TextButton")
	acceptBtn.Size = UDim2.new(0, 70, 0, 28)
	acceptBtn.Position = UDim2.new(0, 8, 0, 40)
	acceptBtn.BackgroundColor3 = Color3.fromRGB(0, 170, 0)
	acceptBtn.Text = "Accept"
	acceptBtn.TextColor3 = Color3.new(1, 1, 1)
	acceptBtn.Font = Enum.Font.GothamBold
	acceptBtn.TextSize = 12
	acceptBtn.Parent = frame
	Instance.new("UICorner", acceptBtn).CornerRadius = UDim.new(0, 5)

	local declineBtn = Instance.new("TextButton")
	declineBtn.Size = UDim2.new(0, 70, 0, 28)
	declineBtn.Position = UDim2.new(0, 86, 0, 40)
	declineBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
	declineBtn.Text = "Decline"
	declineBtn.TextColor3 = Color3.new(1, 1, 1)
	declineBtn.Font = Enum.Font.GothamBold
	declineBtn.TextSize = 12
	declineBtn.Parent = frame
	Instance.new("UICorner", declineBtn).CornerRadius = UDim.new(0, 5)

	acceptBtn.MouseButton1Click:Connect(function()
		respondInvite:FireServer(data.partyId, true)
		frame:Destroy()
	end)

	declineBtn.MouseButton1Click:Connect(function()
		respondInvite:FireServer(data.partyId, false)
		frame:Destroy()
	end)

	-- Auto-expire
	task.delay(15, function()
		if frame.Parent then
			frame:Destroy()
		end
	end)
end

inviteReceived.OnClientEvent:Connect(function(data)
	if data.type == "party" then
		showInvitePopup(data)
	end
end)

socialNotification.OnClientEvent:Connect(function(message: string)
	showNotification(message)
end)
```

## Usage Guide

1. **Create party**: `SocialManager.createParty(player)` or client fires `CreateParty`.
2. **Invite friends**: client fires `InviteToParty` with target player name.
3. **Party teleport**: combine with matchmaking/teleport skills to move the whole party.
4. **Friends list**: `SocialManager.getFriendsInGame(player)` returns friends in the current server.
5. **Game invites**: uses `SocialService:PromptGameInvite()` for official Roblox invites.

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

- `$MAX_PARTY_SIZE` (number) -- Maximum party members. Default: `4`.
- `$INVITE_EXPIRATION` (number) -- Seconds before invite expires. Default: `60`.
- `$PARTY_TTL` (number) -- MemoryStore TTL for party data. Default: `3600`.
- `$INVITE_COOLDOWN` (number) -- Seconds between invites to same player. Default: `10`.
- `$ENABLE_GAME_INVITES` (boolean) -- Enable SocialService game invites. Default: `true`.
