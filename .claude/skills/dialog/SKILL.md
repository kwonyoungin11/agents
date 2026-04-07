---
name: dialog
description: |
  Roblox NPC 대화 시스템 (Dialog System) - 선택지 트리, 타자기 효과, 대화 UI, 분기 대화, 조건부 대화.
  NPC dialog with choice trees, typewriter text effect, dialog UI, branching conversations,
  conditional dialog nodes, variable substitution, event triggers. 로블록스 Luau 대화 시스템 구현.
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
effort: high
---

# NPC Dialog System for Roblox (Luau)

Full dialog system with branching choice trees, typewriter text animation, conditional nodes, variable substitution, and event hooks.

## Architecture Overview

```
DialogSystem (Shared)
├── DialogDatabase (dialog trees, nodes)
├── DialogManager (server - state, conditions)
├── ConditionEvaluator (check player state)
└── DialogEvents (remote events)

DialogClient (Client)
├── DialogUI (frame, text, choices)
├── TypewriterEffect (animated text)
└── PortraitManager (NPC portraits)
```

## Dialog Data Structure

```luau
--!strict
-- ReplicatedStorage/Data/DialogDatabase.luau

export type DialogCondition = {
	Type: string,        -- "QuestCompleted", "HasItem", "LevelMin", "Flag", "QuestActive"
	Value: string,       -- quest id, item id, level number, flag name
	Amount: number?,     -- for item count checks
}

export type DialogChoice = {
	Text: string,
	NextNodeId: string?,          -- nil = end dialog
	Condition: DialogCondition?,  -- only show if condition met
	Action: string?,              -- "AcceptQuest:main_001", "GiveItem:health_potion:3", "SetFlag:talked_elder"
}

export type DialogNode = {
	Id: string,
	Speaker: string,              -- NPC name or "Player"
	Text: string,                 -- supports {player_name}, {variable} substitution
	Portrait: string?,            -- rbxassetid:// for speaker portrait
	Choices: { DialogChoice }?,   -- nil = auto-advance, empty = end
	NextNodeId: string?,          -- auto-advance to next node (when no choices)
	Condition: DialogCondition?,  -- skip this node if condition not met
	FallbackNodeId: string?,      -- go here if condition fails
	Delay: number?,               -- seconds to wait before auto-advance
	Animation: string?,           -- NPC animation to play during this node
	Sound: string?,               -- sound to play
	Event: string?,               -- event to fire: "OpenShop", "StartBattle", etc.
}

export type DialogTree = {
	Id: string,
	NPCName: string,
	StartNodeId: string,
	Nodes: { [string]: DialogNode },
	Priority: number?,            -- higher priority trees checked first
	Condition: DialogCondition?,  -- entire tree requires condition
}

local DialogDatabase: { [string]: DialogTree } = {
	elder_intro = {
		Id = "elder_intro",
		NPCName = "VillageElder",
		StartNodeId = "greeting",
		Nodes = {
			greeting = {
				Id = "greeting",
				Speaker = "Village Elder",
				Text = "Welcome, {player_name}. Dark times have befallen our village.",
				Portrait = "rbxassetid://0",
				Choices = {
					{
						Text = "What happened?",
						NextNodeId = "explain",
					},
					{
						Text = "I don't have time for this.",
						NextNodeId = "dismiss",
					},
				},
			},
			explain = {
				Id = "explain",
				Speaker = "Village Elder",
				Text = "Goblins from the Dark Forest have been raiding our farms. We need someone brave to stop them.",
				Choices = {
					{
						Text = "I'll help! (Accept Quest)",
						NextNodeId = "accept",
						Action = "AcceptQuest:main_002",
					},
					{
						Text = "I need to prepare first.",
						NextNodeId = "prepare",
					},
				},
			},
			accept = {
				Id = "accept",
				Speaker = "Village Elder",
				Text = "Thank you, brave adventurer! Defeat 5 goblins and bring back their tokens as proof.",
				NextNodeId = nil,  -- end dialog
			},
			prepare = {
				Id = "prepare",
				Speaker = "Village Elder",
				Text = "Of course. Come back when you are ready. The goblins won't wait forever though...",
				NextNodeId = nil,
			},
			dismiss = {
				Id = "dismiss",
				Speaker = "Village Elder",
				Text = "Please reconsider... our village depends on it.",
				NextNodeId = nil,
			},
		},
	},
	elder_quest_complete = {
		Id = "elder_quest_complete",
		NPCName = "VillageElder",
		StartNodeId = "turnin",
		Priority = 10,
		Condition = { Type = "QuestActive", Value = "main_002" },
		Nodes = {
			turnin = {
				Id = "turnin",
				Speaker = "Village Elder",
				Text = "Have you driven back the goblins, {player_name}?",
				Choices = {
					{
						Text = "Here are the goblin tokens. (Turn In)",
						NextNodeId = "reward",
						Condition = { Type = "QuestReady", Value = "main_002" },
						Action = "CompleteQuest:main_002",
					},
					{
						Text = "Not yet, still working on it.",
						NextNodeId = "encourage",
					},
				},
			},
			reward = {
				Id = "reward",
				Speaker = "Village Elder",
				Text = "Excellent! You've done our village a great service. Take this as a reward.",
				Event = "QuestReward:main_002",
				NextNodeId = nil,
			},
			encourage = {
				Id = "encourage",
				Speaker = "Village Elder",
				Text = "Stay strong. The forest goblins can be found along the eastern path.",
				NextNodeId = nil,
			},
		},
	},
}

local module = {}

function module.GetDialog(dialogId: string): DialogTree?
	return DialogDatabase[dialogId]
end

function module.GetDialogsForNPC(npcName: string): { DialogTree }
	local results = {}
	for _, tree in DialogDatabase do
		if tree.NPCName == npcName then
			table.insert(results, tree)
		end
	end
	-- Sort by priority (highest first)
	table.sort(results, function(a, b)
		return (a.Priority or 0) > (b.Priority or 0)
	end)
	return results
end

function module.Register(tree: DialogTree)
	assert(tree.Id and tree.Id ~= "", "Dialog tree must have an Id")
	DialogDatabase[tree.Id] = tree
end

return module
```

## Dialog Manager (Server)

```luau
--!strict
-- ServerScriptService/Dialog/DialogManager.luau

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DialogDatabase = require(ReplicatedStorage.Data.DialogDatabase)

export type DialogState = {
	TreeId: string,
	CurrentNodeId: string,
	NPCName: string,
}

local DialogManager = {}
DialogManager.__index = DialogManager

function DialogManager.new()
	local self = setmetatable({}, DialogManager)
	self._activeDialogs = {} :: { [Player]: DialogState }
	self._conditionCheckers = {} :: { [string]: (Player, string, number?) -> boolean }
	self._actionHandlers = {} :: { [string]: (Player, string) -> () }
	self._variables = {} :: { [Player]: { [string]: string } }
	self._flags = {} :: { [Player]: { [string]: boolean } }
	self:_registerDefaultConditions()
	return self
end

function DialogManager:RegisterPlayer(player: Player)
	self._variables[player] = { player_name = player.DisplayName }
	self._flags[player] = {}
end

function DialogManager:UnregisterPlayer(player: Player)
	self._activeDialogs[player] = nil
	self._variables[player] = nil
	self._flags[player] = nil
end

---------------------------------------------------------------------
-- Condition System
---------------------------------------------------------------------
function DialogManager:RegisterCondition(condType: string, checker: (Player, string, number?) -> boolean)
	self._conditionCheckers[condType] = checker
end

function DialogManager:CheckCondition(player: Player, condition: DialogDatabase.DialogCondition?): boolean
	if not condition then return true end

	local checker = self._conditionCheckers[condition.Type]
	if not checker then
		warn("[Dialog] Unknown condition type:", condition.Type)
		return false
	end

	return checker(player, condition.Value, condition.Amount)
end

function DialogManager:_registerDefaultConditions()
	-- Flag check
	self:RegisterCondition("Flag", function(player, flagName, _amount)
		local flags = self._flags[player]
		return flags ~= nil and flags[flagName] == true
	end)

	-- Level check (override with real leveling system)
	self:RegisterCondition("LevelMin", function(_player, levelStr, _amount)
		local _requiredLevel = tonumber(levelStr) or 1
		-- TODO: integrate with leveling system
		return true
	end)
end

---------------------------------------------------------------------
-- Action System
---------------------------------------------------------------------
function DialogManager:RegisterAction(actionType: string, handler: (Player, string) -> ())
	self._actionHandlers[actionType] = handler
end

function DialogManager:ExecuteAction(player: Player, actionString: string?)
	if not actionString then return end

	local actionType, params = actionString:match("^(%w+):(.+)$")
	if not actionType then return end

	-- Built-in: SetFlag
	if actionType == "SetFlag" then
		local flags = self._flags[player]
		if flags then
			flags[params] = true
		end
		return
	end

	local handler = self._actionHandlers[actionType]
	if handler then
		handler(player, params)
	else
		warn("[Dialog] Unknown action:", actionType)
	end
end

---------------------------------------------------------------------
-- Variable Substitution
---------------------------------------------------------------------
function DialogManager:SetVariable(player: Player, key: string, value: string)
	local vars = self._variables[player]
	if vars then
		vars[key] = value
	end
end

function DialogManager:SubstituteVariables(player: Player, text: string): string
	local vars = self._variables[player]
	if not vars then return text end

	return text:gsub("{(%w+)}", function(key)
		return vars[key] or ("{" .. key .. "}")
	end)
end

---------------------------------------------------------------------
-- Dialog Flow
---------------------------------------------------------------------
function DialogManager:StartDialog(player: Player, npcName: string): (boolean, DialogDatabase.DialogNode?)
	-- Find the best dialog tree for this NPC
	local trees = DialogDatabase.GetDialogsForNPC(npcName)

	for _, tree in trees do
		if self:CheckCondition(player, tree.Condition) then
			local startNode = tree.Nodes[tree.StartNodeId]
			if not startNode then continue end

			-- Check node condition
			if not self:CheckCondition(player, startNode.Condition) then
				if startNode.FallbackNodeId then
					startNode = tree.Nodes[startNode.FallbackNodeId]
					if not startNode then continue end
				else
					continue
				end
			end

			self._activeDialogs[player] = {
				TreeId = tree.Id,
				CurrentNodeId = startNode.Id,
				NPCName = npcName,
			}

			-- Execute node event
			if startNode.Event then
				self:ExecuteAction(player, startNode.Event)
			end

			return true, startNode
		end
	end

	return false, nil
end

function DialogManager:SelectChoice(player: Player, choiceIndex: number): (DialogDatabase.DialogNode?, boolean)
	local state = self._activeDialogs[player]
	if not state then return nil, true end

	local tree = DialogDatabase.GetDialog(state.TreeId)
	if not tree then
		self._activeDialogs[player] = nil
		return nil, true
	end

	local currentNode = tree.Nodes[state.CurrentNodeId]
	if not currentNode or not currentNode.Choices then
		self._activeDialogs[player] = nil
		return nil, true
	end

	-- Filter choices by conditions and get the visible list
	local visibleChoices: { DialogDatabase.DialogChoice } = {}
	for _, choice in currentNode.Choices do
		if self:CheckCondition(player, choice.Condition) then
			table.insert(visibleChoices, choice)
		end
	end

	if choiceIndex < 1 or choiceIndex > #visibleChoices then
		return nil, false
	end

	local selected = visibleChoices[choiceIndex]

	-- Execute choice action
	if selected.Action then
		self:ExecuteAction(player, selected.Action)
	end

	-- Navigate to next node
	if not selected.NextNodeId then
		self._activeDialogs[player] = nil
		return nil, true  -- dialog ended
	end

	local nextNode = tree.Nodes[selected.NextNodeId]
	if not nextNode then
		self._activeDialogs[player] = nil
		return nil, true
	end

	-- Check next node condition
	if not self:CheckCondition(player, nextNode.Condition) then
		if nextNode.FallbackNodeId then
			nextNode = tree.Nodes[nextNode.FallbackNodeId]
			if not nextNode then
				self._activeDialogs[player] = nil
				return nil, true
			end
		end
	end

	state.CurrentNodeId = nextNode.Id

	-- Execute node event
	if nextNode.Event then
		self:ExecuteAction(player, nextNode.Event)
	end

	return nextNode, false
end

function DialogManager:AdvanceDialog(player: Player): (DialogDatabase.DialogNode?, boolean)
	local state = self._activeDialogs[player]
	if not state then return nil, true end

	local tree = DialogDatabase.GetDialog(state.TreeId)
	if not tree then
		self._activeDialogs[player] = nil
		return nil, true
	end

	local currentNode = tree.Nodes[state.CurrentNodeId]
	if not currentNode or not currentNode.NextNodeId then
		self._activeDialogs[player] = nil
		return nil, true
	end

	local nextNode = tree.Nodes[currentNode.NextNodeId]
	if not nextNode then
		self._activeDialogs[player] = nil
		return nil, true
	end

	state.CurrentNodeId = nextNode.Id
	if nextNode.Event then
		self:ExecuteAction(player, nextNode.Event)
	end

	return nextNode, false
end

function DialogManager:EndDialog(player: Player)
	self._activeDialogs[player] = nil
end

function DialogManager:IsInDialog(player: Player): boolean
	return self._activeDialogs[player] ~= nil
end

-- Get filtered choices for current node
function DialogManager:GetVisibleChoices(player: Player): { DialogDatabase.DialogChoice }?
	local state = self._activeDialogs[player]
	if not state then return nil end

	local tree = DialogDatabase.GetDialog(state.TreeId)
	if not tree then return nil end

	local node = tree.Nodes[state.CurrentNodeId]
	if not node or not node.Choices then return nil end

	local visible: { DialogDatabase.DialogChoice } = {}
	for _, choice in node.Choices do
		if self:CheckCondition(player, choice.Condition) then
			table.insert(visible, choice)
		end
	end
	return visible
end

return DialogManager
```

## Dialog Client (UI + Typewriter)

```luau
--!strict
-- StarterPlayerScripts/DialogClient.luau

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local DialogClient = {}
DialogClient._isActive = false
DialogClient._typewriterSpeed = 0.03  -- seconds per character
DialogClient._skipRequested = false
DialogClient._isTyping = false

---------------------------------------------------------------------
-- UI Creation
---------------------------------------------------------------------
function DialogClient:CreateUI(): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "DialogUI"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 100

	-- Main frame
	local frame = Instance.new("Frame")
	frame.Name = "DialogFrame"
	frame.Size = UDim2.new(0.6, 0, 0.25, 0)
	frame.Position = UDim2.new(0.2, 0, 0.72, 0)
	frame.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
	frame.BackgroundTransparency = 0.1
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(180, 160, 100)
	stroke.Thickness = 2
	stroke.Parent = frame

	-- Portrait frame
	local portrait = Instance.new("ImageLabel")
	portrait.Name = "Portrait"
	portrait.Size = UDim2.new(0, 80, 0, 80)
	portrait.Position = UDim2.new(0, 15, 0, 15)
	portrait.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
	portrait.Image = ""
	portrait.ScaleType = Enum.ScaleType.Fit
	portrait.Parent = frame

	local portraitCorner = Instance.new("UICorner")
	portraitCorner.CornerRadius = UDim.new(0, 8)
	portraitCorner.Parent = portrait

	-- Speaker name
	local speakerLabel = Instance.new("TextLabel")
	speakerLabel.Name = "SpeakerName"
	speakerLabel.Size = UDim2.new(0.6, 0, 0, 25)
	speakerLabel.Position = UDim2.new(0, 110, 0, 10)
	speakerLabel.BackgroundTransparency = 1
	speakerLabel.TextColor3 = Color3.fromRGB(255, 220, 100)
	speakerLabel.TextSize = 18
	speakerLabel.Font = Enum.Font.GothamBold
	speakerLabel.TextXAlignment = Enum.TextXAlignment.Left
	speakerLabel.Parent = frame

	-- Dialog text
	local textLabel = Instance.new("TextLabel")
	textLabel.Name = "DialogText"
	textLabel.Size = UDim2.new(1, -125, 1, -50)
	textLabel.Position = UDim2.new(0, 110, 0, 38)
	textLabel.BackgroundTransparency = 1
	textLabel.TextColor3 = Color3.fromRGB(230, 230, 230)
	textLabel.TextSize = 16
	textLabel.Font = Enum.Font.Gotham
	textLabel.TextXAlignment = Enum.TextXAlignment.Left
	textLabel.TextYAlignment = Enum.TextYAlignment.Top
	textLabel.TextWrapped = true
	textLabel.RichText = true
	textLabel.Parent = frame

	-- Continue indicator
	local continueLabel = Instance.new("TextLabel")
	continueLabel.Name = "ContinueIndicator"
	continueLabel.Size = UDim2.new(0, 200, 0, 20)
	continueLabel.Position = UDim2.new(1, -210, 1, -25)
	continueLabel.BackgroundTransparency = 1
	continueLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
	continueLabel.TextSize = 12
	continueLabel.Font = Enum.Font.GothamMedium
	continueLabel.Text = "Click to continue..."
	continueLabel.TextXAlignment = Enum.TextXAlignment.Right
	continueLabel.Visible = false
	continueLabel.Parent = frame

	-- Choices container
	local choicesFrame = Instance.new("Frame")
	choicesFrame.Name = "ChoicesFrame"
	choicesFrame.Size = UDim2.new(0.6, 0, 0, 0)
	choicesFrame.Position = UDim2.new(0.2, 0, 0, -5)
	choicesFrame.AnchorPoint = Vector2.new(0, 1)
	choicesFrame.BackgroundTransparency = 1
	choicesFrame.AutomaticSize = Enum.AutomaticSize.Y
	choicesFrame.Parent = frame

	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 4)
	listLayout.Parent = choicesFrame

	gui.Parent = playerGui
	self._gui = gui
	self._frame = frame
	return gui
end

---------------------------------------------------------------------
-- Typewriter Effect
---------------------------------------------------------------------
function DialogClient:TypewriterText(text: string, textLabel: TextLabel)
	self._isTyping = true
	self._skipRequested = false
	textLabel.Text = ""

	local displayText = ""
	local i = 1
	local len = #text

	while i <= len do
		if self._skipRequested then
			textLabel.Text = text
			self._isTyping = false
			return
		end

		-- Handle rich text tags (skip over them instantly)
		if text:sub(i, i) == "<" then
			local tagEnd = text:find(">", i)
			if tagEnd then
				displayText ..= text:sub(i, tagEnd)
				i = tagEnd + 1
				textLabel.Text = displayText
				continue
			end
		end

		displayText ..= text:sub(i, i)
		textLabel.Text = displayText
		i += 1
		task.wait(self._typewriterSpeed)
	end

	self._isTyping = false
end

function DialogClient:SkipTypewriter()
	self._skipRequested = true
end

---------------------------------------------------------------------
-- Show Dialog Node
---------------------------------------------------------------------
function DialogClient:ShowNode(nodeData: {
	Speaker: string?,
	Text: string,
	Portrait: string?,
	Choices: { { Text: string } }?,
})
	if not self._frame then return end

	local frame = self._frame :: Frame
	frame.Visible = true
	self._isActive = true

	-- Set speaker
	local speakerLabel = frame:FindFirstChild("SpeakerName") :: TextLabel
	if speakerLabel then
		speakerLabel.Text = nodeData.Speaker or ""
	end

	-- Set portrait
	local portrait = frame:FindFirstChild("Portrait") :: ImageLabel
	if portrait then
		portrait.Image = nodeData.Portrait or ""
		portrait.Visible = (nodeData.Portrait ~= nil and nodeData.Portrait ~= "")
	end

	-- Clear choices
	local choicesFrame = frame:FindFirstChild("ChoicesFrame") :: Frame
	if choicesFrame then
		for _, child in choicesFrame:GetChildren() do
			if child:IsA("TextButton") then
				child:Destroy()
			end
		end
		choicesFrame.Visible = false
	end

	-- Hide continue indicator
	local continueInd = frame:FindFirstChild("ContinueIndicator") :: TextLabel
	if continueInd then
		continueInd.Visible = false
	end

	-- Typewriter the text
	local textLabel = frame:FindFirstChild("DialogText") :: TextLabel
	if textLabel then
		self:TypewriterText(nodeData.Text, textLabel)
	end

	-- Show choices or continue indicator after typing
	if nodeData.Choices and #nodeData.Choices > 0 then
		if choicesFrame then
			choicesFrame.Visible = true
			for i, choice in nodeData.Choices do
				local btn = Instance.new("TextButton")
				btn.Name = "Choice_" .. i
				btn.Size = UDim2.new(1, 0, 0, 30)
				btn.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
				btn.TextColor3 = Color3.fromRGB(220, 220, 220)
				btn.TextSize = 14
				btn.Font = Enum.Font.Gotham
				btn.Text = "  " .. i .. ". " .. choice.Text
				btn.TextXAlignment = Enum.TextXAlignment.Left
				btn.LayoutOrder = i
				btn.AutoButtonColor = true

				local btnCorner = Instance.new("UICorner")
				btnCorner.CornerRadius = UDim.new(0, 6)
				btnCorner.Parent = btn

				btn.MouseEnter:Connect(function()
					btn.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
				end)
				btn.MouseLeave:Connect(function()
					btn.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
				end)

				btn.Parent = choicesFrame
			end
		end
	else
		if continueInd then
			continueInd.Visible = true
		end
	end
end

function DialogClient:Hide()
	if self._frame then
		(self._frame :: Frame).Visible = false
	end
	self._isActive = false
end

return DialogClient
```

## Usage Example

```luau
-- Server: wire up dialog manager
local DialogManager = require(ServerScriptService.Dialog.DialogManager)
local dialog = DialogManager.new()

-- Register quest conditions
dialog:RegisterCondition("QuestCompleted", function(player, questId, _)
    return questTracker:IsQuestCompleted(player, questId)
end)

dialog:RegisterCondition("QuestActive", function(player, questId, _)
    return questTracker:IsQuestActive(player, questId)
end)

-- Register actions
dialog:RegisterAction("AcceptQuest", function(player, questId)
    questTracker:AcceptQuest(player, questId)
end)

dialog:RegisterAction("CompleteQuest", function(player, questId)
    questTracker:CompleteQuest(player, questId)
end)

-- Start dialog when player interacts with NPC
local success, firstNode = dialog:StartDialog(player, "VillageElder")
if success and firstNode then
    -- Send to client for display
    local text = dialog:SubstituteVariables(player, firstNode.Text)
    local choices = dialog:GetVisibleChoices(player)
    DialogRemote:FireClient(player, "ShowNode", {
        Speaker = firstNode.Speaker,
        Text = text,
        Portrait = firstNode.Portrait,
        Choices = choices,
    })
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

When the user asks to implement a dialog system, ask or infer:

- `$ENABLE_TYPEWRITER` - Typewriter text animation: true/false
- `$TYPEWRITER_SPEED` - Seconds per character: 0.03
- `$ENABLE_CHOICES` - Branching dialog choices: true/false
- `$ENABLE_CONDITIONS` - Conditional dialog nodes: true/false
- `$CONDITION_TYPES` - Condition types to support: {"QuestCompleted", "HasItem", "LevelMin", "Flag", "QuestActive"}
- `$ENABLE_PORTRAITS` - NPC portrait images: true/false
- `$ENABLE_VARIABLES` - Variable substitution in text: true/false
- `$ENABLE_ACTIONS` - Dialog choices trigger actions: true/false
- `$ACTION_TYPES` - Supported actions: {"AcceptQuest", "CompleteQuest", "GiveItem", "SetFlag", "OpenShop"}
- `$ENABLE_RICH_TEXT` - Rich text formatting in dialog: true/false
- `$ENABLE_SOUNDS` - Dialog sound effects: true/false
- `$ENABLE_ANIMATIONS` - NPC animations during dialog: true/false
- `$UI_POSITION` - Dialog UI position: "bottom" (default), "center", "top"
- `$ENABLE_SKIP` - Allow skipping typewriter: true/false
