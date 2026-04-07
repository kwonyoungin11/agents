---
name: quest
description: |
  Roblox 퀘스트 시스템 (Quest System) - 목표 (킬/수집/대화/탐험), 추적, 완료 보상, 퀘스트 체인, UI 통합.
  Quest management with objectives (kill/collect/talk/explore), progress tracking, completion rewards,
  quest chains and prerequisites, UI integration hooks. 로블록스 Luau 퀘스트 구현.
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
effort: high
---

# Quest System for Roblox (Luau)

Complete quest system with multiple objective types, progress tracking, rewards, quest chains, prerequisites, and UI integration.

## Architecture Overview

```
QuestSystem (Server)
├── QuestDatabase (quest templates, objectives)
├── QuestTracker (per-player progress)
├── ObjectiveHandlers (kill/collect/talk/explore)
├── RewardDistributor (XP, items, currency)
└── QuestEvents (remote events for UI)

QuestClient (Client)
├── QuestLogUI (active/completed quests)
├── ObjectiveTracker (HUD display)
└── QuestDialogUI (accept/turnin prompts)
```

## Quest Data Templates

```luau
--!strict
-- ReplicatedStorage/Data/QuestDatabase.luau

export type ObjectiveType = "Kill" | "Collect" | "Talk" | "Explore" | "Interact" | "Escort" | "Survive"

export type QuestObjective = {
	Id: string,
	Type: ObjectiveType,
	Description: string,
	TargetId: string,          -- mob name, item id, NPC name, zone name
	RequiredAmount: number,
	Optional: boolean?,        -- bonus objectives
}

export type QuestReward = {
	XP: number?,
	Currency: number?,
	Items: { { ItemId: string, Quantity: number } }?,
	UnlockQuest: string?,      -- next quest in chain
	CustomReward: string?,     -- e.g., "unlock_ability:dash"
}

export type QuestStatus = "NotStarted" | "Active" | "ReadyToTurnIn" | "Completed" | "Failed"

export type QuestTemplate = {
	Id: string,
	Name: string,
	Description: string,
	Category: string,          -- "Main", "Side", "Daily", "Weekly"
	Level: number?,            -- recommended/required level
	Prerequisites: { string }?, -- quest IDs that must be completed first
	Objectives: { QuestObjective },
	Rewards: QuestReward,
	TimeLimit: number?,        -- seconds, nil = no limit
	Repeatable: boolean?,
	AutoComplete: boolean?,    -- complete immediately when objectives done
	TurnInNPC: string?,        -- NPC to turn in to
	GiverNPC: string?,         -- NPC that gives this quest
	ChainGroup: string?,       -- group name for quest chain display
	ChainOrder: number?,       -- order within chain
}

local QuestDatabase: { [string]: QuestTemplate } = {
	main_001 = {
		Id = "main_001",
		Name = "The Beginning",
		Description = "Speak to the Village Elder to learn about the threat.",
		Category = "Main",
		Level = 1,
		Prerequisites = {},
		Objectives = {
			{
				Id = "talk_elder",
				Type = "Talk",
				Description = "Talk to Village Elder",
				TargetId = "VillageElder",
				RequiredAmount = 1,
			},
		},
		Rewards = {
			XP = 50,
			Currency = 10,
			UnlockQuest = "main_002",
		},
		AutoComplete = false,
		TurnInNPC = "VillageElder",
		GiverNPC = "VillageElder",
		ChainGroup = "MainStory",
		ChainOrder = 1,
	},
	main_002 = {
		Id = "main_002",
		Name = "Goblin Threat",
		Description = "Defeat goblins in the forest and collect their tokens.",
		Category = "Main",
		Level = 2,
		Prerequisites = { "main_001" },
		Objectives = {
			{
				Id = "kill_goblins",
				Type = "Kill",
				Description = "Defeat Goblins",
				TargetId = "Goblin",
				RequiredAmount = 5,
			},
			{
				Id = "collect_tokens",
				Type = "Collect",
				Description = "Collect Goblin Tokens",
				TargetId = "goblin_token",
				RequiredAmount = 3,
			},
		},
		Rewards = {
			XP = 150,
			Currency = 50,
			Items = {
				{ ItemId = "iron_sword", Quantity = 1 },
				{ ItemId = "health_potion", Quantity = 3 },
			},
			UnlockQuest = "main_003",
		},
		TurnInNPC = "VillageElder",
		GiverNPC = "VillageElder",
		ChainGroup = "MainStory",
		ChainOrder = 2,
	},
	side_explore_001 = {
		Id = "side_explore_001",
		Name = "Wanderer's Path",
		Description = "Discover hidden locations across the land.",
		Category = "Side",
		Level = 1,
		Objectives = {
			{
				Id = "find_cave",
				Type = "Explore",
				Description = "Discover the Hidden Cave",
				TargetId = "HiddenCave",
				RequiredAmount = 1,
			},
			{
				Id = "find_tower",
				Type = "Explore",
				Description = "Discover the Ancient Tower",
				TargetId = "AncientTower",
				RequiredAmount = 1,
			},
		},
		Rewards = {
			XP = 100,
			Currency = 30,
		},
		AutoComplete = true,
	},
	daily_hunt_001 = {
		Id = "daily_hunt_001",
		Name = "Daily Hunt",
		Description = "Defeat any 10 enemies today.",
		Category = "Daily",
		Level = 1,
		Objectives = {
			{
				Id = "kill_any",
				Type = "Kill",
				Description = "Defeat any enemies",
				TargetId = "*",  -- wildcard: any enemy
				RequiredAmount = 10,
			},
		},
		Rewards = {
			XP = 75,
			Currency = 25,
		},
		Repeatable = true,
		AutoComplete = true,
	},
}

local module = {}

function module.GetQuest(questId: string): QuestTemplate?
	return QuestDatabase[questId]
end

function module.GetQuestsByCategory(category: string): { QuestTemplate }
	local results = {}
	for _, quest in QuestDatabase do
		if quest.Category == category then
			table.insert(results, quest)
		end
	end
	return results
end

function module.GetQuestChain(chainGroup: string): { QuestTemplate }
	local results = {}
	for _, quest in QuestDatabase do
		if quest.ChainGroup == chainGroup then
			table.insert(results, quest)
		end
	end
	table.sort(results, function(a, b)
		return (a.ChainOrder or 0) < (b.ChainOrder or 0)
	end)
	return results
end

function module.GetQuestsByNPC(npcName: string): { QuestTemplate }
	local results = {}
	for _, quest in QuestDatabase do
		if quest.GiverNPC == npcName then
			table.insert(results, quest)
		end
	end
	return results
end

function module.Register(template: QuestTemplate)
	assert(template.Id and template.Id ~= "", "Quest must have an Id")
	QuestDatabase[template.Id] = template
end

return module
```

## Quest Tracker (Server)

```luau
--!strict
-- ServerScriptService/Quest/QuestTracker.luau

local QuestDatabase = require(game.ReplicatedStorage.Data.QuestDatabase)

export type ObjectiveProgress = {
	ObjectiveId: string,
	Current: number,
	Required: number,
	Completed: boolean,
}

export type ActiveQuest = {
	QuestId: string,
	Status: QuestDatabase.QuestStatus,
	Objectives: { [string]: ObjectiveProgress },
	StartTime: number,
	CompletedTime: number?,
}

export type PlayerQuestData = {
	Active: { [string]: ActiveQuest },
	Completed: { [string]: boolean },    -- questId -> true
	CompletedCount: { [string]: number }, -- for repeatable quests
}

local QuestTracker = {}
QuestTracker.__index = QuestTracker

function QuestTracker.new()
	local self = setmetatable({}, QuestTracker)
	self._playerData = {} :: { [Player]: PlayerQuestData }
	self._onObjectiveUpdate = nil :: ((Player, string, string, ObjectiveProgress) -> ())?
	self._onQuestComplete = nil :: ((Player, string) -> ())?
	return self
end

function QuestTracker:RegisterPlayer(player: Player)
	self._playerData[player] = {
		Active = {},
		Completed = {},
		CompletedCount = {},
	}
end

function QuestTracker:UnregisterPlayer(player: Player)
	self._playerData[player] = nil
end

function QuestTracker:GetPlayerData(player: Player): PlayerQuestData?
	return self._playerData[player]
end

---------------------------------------------------------------------
-- Accept / Start Quest
---------------------------------------------------------------------
function QuestTracker:AcceptQuest(player: Player, questId: string): (boolean, string?)
	local pData = self._playerData[player]
	if not pData then return false, "Player not registered" end

	-- Already active?
	if pData.Active[questId] then return false, "Quest already active" end

	-- Already completed (non-repeatable)?
	local template = QuestDatabase.GetQuest(questId)
	if not template then return false, "Unknown quest" end

	if pData.Completed[questId] and not template.Repeatable then
		return false, "Quest already completed"
	end

	-- Check prerequisites
	if template.Prerequisites then
		for _, prereqId in template.Prerequisites do
			if not pData.Completed[prereqId] then
				return false, "Prerequisites not met: " .. prereqId
			end
		end
	end

	-- Initialize objectives
	local objectives: { [string]: ObjectiveProgress } = {}
	for _, obj in template.Objectives do
		objectives[obj.Id] = {
			ObjectiveId = obj.Id,
			Current = 0,
			Required = obj.RequiredAmount,
			Completed = false,
		}
	end

	pData.Active[questId] = {
		QuestId = questId,
		Status = "Active",
		Objectives = objectives,
		StartTime = tick(),
	}

	return true, nil
end

---------------------------------------------------------------------
-- Update Objectives
---------------------------------------------------------------------
function QuestTracker:UpdateObjective(
	player: Player,
	objectiveType: QuestDatabase.ObjectiveType,
	targetId: string,
	amount: number?
)
	local pData = self._playerData[player]
	if not pData then return end

	local increment = amount or 1

	for questId, activeQuest in pData.Active do
		if activeQuest.Status ~= "Active" then continue end

		local template = QuestDatabase.GetQuest(questId)
		if not template then continue end

		-- Check time limit
		if template.TimeLimit and (tick() - activeQuest.StartTime) > template.TimeLimit then
			activeQuest.Status = "Failed"
			continue
		end

		for _, objTemplate in template.Objectives do
			if objTemplate.Type ~= objectiveType then continue end

			-- Match target (wildcard "*" matches anything)
			if objTemplate.TargetId ~= targetId and objTemplate.TargetId ~= "*" then continue end

			local progress = activeQuest.Objectives[objTemplate.Id]
			if not progress or progress.Completed then continue end

			progress.Current = math.min(progress.Current + increment, progress.Required)
			if progress.Current >= progress.Required then
				progress.Completed = true
			end

			-- Callback for UI updates
			if self._onObjectiveUpdate then
				self._onObjectiveUpdate(player, questId, objTemplate.Id, progress)
			end
		end

		-- Check if all required objectives are complete
		local allDone = true
		for _, objTemplate in template.Objectives do
			if objTemplate.Optional then continue end
			local progress = activeQuest.Objectives[objTemplate.Id]
			if not progress or not progress.Completed then
				allDone = false
				break
			end
		end

		if allDone then
			if template.AutoComplete then
				self:CompleteQuest(player, questId)
			else
				activeQuest.Status = "ReadyToTurnIn"
			end
		end
	end
end

-- Convenience methods for specific objective types
function QuestTracker:OnKill(player: Player, enemyName: string, count: number?)
	self:UpdateObjective(player, "Kill", enemyName, count)
end

function QuestTracker:OnCollect(player: Player, itemId: string, count: number?)
	self:UpdateObjective(player, "Collect", itemId, count)
end

function QuestTracker:OnTalk(player: Player, npcName: string)
	self:UpdateObjective(player, "Talk", npcName, 1)
end

function QuestTracker:OnExplore(player: Player, zoneName: string)
	self:UpdateObjective(player, "Explore", zoneName, 1)
end

---------------------------------------------------------------------
-- Complete / Turn In Quest
---------------------------------------------------------------------
function QuestTracker:CompleteQuest(player: Player, questId: string): (boolean, QuestDatabase.QuestReward?)
	local pData = self._playerData[player]
	if not pData then return false, nil end

	local activeQuest = pData.Active[questId]
	if not activeQuest then return false, nil end

	local template = QuestDatabase.GetQuest(questId)
	if not template then return false, nil end

	-- Verify objectives are done (for manual turn-in)
	if activeQuest.Status == "Active" then
		for _, objTemplate in template.Objectives do
			if objTemplate.Optional then continue end
			local progress = activeQuest.Objectives[objTemplate.Id]
			if not progress or not progress.Completed then
				return false, nil
			end
		end
	end

	-- Mark completed
	activeQuest.Status = "Completed"
	activeQuest.CompletedTime = tick()
	pData.Completed[questId] = true
	pData.CompletedCount[questId] = (pData.CompletedCount[questId] or 0) + 1

	-- Remove from active
	pData.Active[questId] = nil

	-- Callback
	if self._onQuestComplete then
		self._onQuestComplete(player, questId)
	end

	return true, template.Rewards
end

function QuestTracker:AbandonQuest(player: Player, questId: string): boolean
	local pData = self._playerData[player]
	if not pData then return false end

	if pData.Active[questId] then
		pData.Active[questId] = nil
		return true
	end
	return false
end

---------------------------------------------------------------------
-- Query Methods
---------------------------------------------------------------------
function QuestTracker:GetActiveQuests(player: Player): { ActiveQuest }
	local pData = self._playerData[player]
	if not pData then return {} end

	local quests = {}
	for _, quest in pData.Active do
		table.insert(quests, quest)
	end
	return quests
end

function QuestTracker:IsQuestCompleted(player: Player, questId: string): boolean
	local pData = self._playerData[player]
	if not pData then return false end
	return pData.Completed[questId] == true
end

function QuestTracker:IsQuestActive(player: Player, questId: string): boolean
	local pData = self._playerData[player]
	if not pData then return false end
	return pData.Active[questId] ~= nil
end

function QuestTracker:GetAvailableQuests(player: Player, npcName: string?): { QuestDatabase.QuestTemplate }
	local pData = self._playerData[player]
	if not pData then return {} end

	local available = {}
	local allQuests = if npcName then QuestDatabase.GetQuestsByNPC(npcName) else {}

	-- If no NPC filter, check all quests (expensive, use sparingly)
	if not npcName then
		for _, cat in { "Main", "Side", "Daily", "Weekly" } do
			for _, q in QuestDatabase.GetQuestsByCategory(cat) do
				table.insert(allQuests, q)
			end
		end
	end

	for _, quest in allQuests do
		-- Skip if already active or completed (non-repeatable)
		if pData.Active[quest.Id] then continue end
		if pData.Completed[quest.Id] and not quest.Repeatable then continue end

		-- Check prerequisites
		local prereqsMet = true
		if quest.Prerequisites then
			for _, prereqId in quest.Prerequisites do
				if not pData.Completed[prereqId] then
					prereqsMet = false
					break
				end
			end
		end

		if prereqsMet then
			table.insert(available, quest)
		end
	end

	return available
end

---------------------------------------------------------------------
-- Callbacks for UI
---------------------------------------------------------------------
function QuestTracker:OnObjectiveUpdated(callback: (Player, string, string, ObjectiveProgress) -> ())
	self._onObjectiveUpdate = callback
end

function QuestTracker:OnQuestCompleted(callback: (Player, string) -> ())
	self._onQuestComplete = callback
end

---------------------------------------------------------------------
-- Serialization
---------------------------------------------------------------------
export type SerializedQuestData = {
	Active: { [string]: {
		QuestId: string,
		Status: string,
		Objectives: { [string]: { Current: number, Required: number, Completed: boolean } },
		StartTime: number,
	} },
	Completed: { [string]: boolean },
	CompletedCount: { [string]: number },
}

function QuestTracker:Serialize(player: Player): SerializedQuestData?
	local pData = self._playerData[player]
	if not pData then return nil end

	local activeData: { [string]: any } = {}
	for questId, quest in pData.Active do
		local objData: { [string]: any } = {}
		for objId, progress in quest.Objectives do
			objData[objId] = {
				Current = progress.Current,
				Required = progress.Required,
				Completed = progress.Completed,
			}
		end
		activeData[questId] = {
			QuestId = quest.QuestId,
			Status = quest.Status,
			Objectives = objData,
			StartTime = quest.StartTime,
		}
	end

	return {
		Active = activeData,
		Completed = pData.Completed,
		CompletedCount = pData.CompletedCount,
	}
end

function QuestTracker:Deserialize(player: Player, data: SerializedQuestData)
	self:RegisterPlayer(player)
	local pData = self._playerData[player]
	if not pData then return end

	pData.Completed = data.Completed or {}
	pData.CompletedCount = data.CompletedCount or {}

	for questId, questData in data.Active do
		local objectives: { [string]: ObjectiveProgress } = {}
		for objId, objData in questData.Objectives do
			objectives[objId] = {
				ObjectiveId = objId,
				Current = objData.Current,
				Required = objData.Required,
				Completed = objData.Completed,
			}
		end
		pData.Active[questId] = {
			QuestId = questData.QuestId,
			Status = questData.Status :: QuestDatabase.QuestStatus,
			Objectives = objectives,
			StartTime = questData.StartTime,
		}
	end
end

return QuestTracker
```

## Reward Distributor

```luau
--!strict
-- ServerScriptService/Quest/RewardDistributor.luau

local QuestDatabase = require(game.ReplicatedStorage.Data.QuestDatabase)

local RewardDistributor = {}

-- These should be set to your actual system references
RewardDistributor.InventoryManager = nil :: any  -- set at init
RewardDistributor.LevelingSystem = nil :: any     -- set at init

function RewardDistributor:DistributeRewards(player: Player, rewards: QuestDatabase.QuestReward)
	-- XP reward
	if rewards.XP and rewards.XP > 0 and self.LevelingSystem then
		self.LevelingSystem:AddXP(player, rewards.XP)
	end

	-- Currency reward
	if rewards.Currency and rewards.Currency > 0 and self.InventoryManager then
		local inv = self.InventoryManager:GetInventory(player)
		if inv then
			inv.Currency += rewards.Currency
		end
	end

	-- Item rewards
	if rewards.Items and self.InventoryManager then
		for _, itemReward in rewards.Items do
			self.InventoryManager:AddItem(player, itemReward.ItemId, itemReward.Quantity)
		end
	end

	-- Custom rewards (handle game-specific rewards)
	if rewards.CustomReward then
		self:HandleCustomReward(player, rewards.CustomReward)
	end
end

function RewardDistributor:HandleCustomReward(player: Player, rewardString: string)
	-- Parse "action:value" format
	local action, value = rewardString:match("^(%w+):(.+)$")
	if not action then return end

	if action == "unlock_ability" then
		-- Fire a bindable event or call ability system
		print("[Quest] Unlocked ability:", value, "for", player.Name)
	elseif action == "unlock_area" then
		print("[Quest] Unlocked area:", value, "for", player.Name)
	elseif action == "title" then
		print("[Quest] Granted title:", value, "to", player.Name)
	end
end

return RewardDistributor
```

## Usage Example

```luau
-- Server setup:
local QuestTracker = require(ServerScriptService.Quest.QuestTracker)
local tracker = QuestTracker.new()

-- When player joins:
tracker:RegisterPlayer(player)
tracker:AcceptQuest(player, "main_001")

-- When player talks to an NPC:
tracker:OnTalk(player, "VillageElder")

-- When player kills an enemy:
tracker:OnKill(player, "Goblin")

-- When player picks up an item:
tracker:OnCollect(player, "goblin_token")

-- When player enters a zone:
tracker:OnExplore(player, "HiddenCave")

-- Turn in a quest:
local success, rewards = tracker:CompleteQuest(player, "main_002")
if success and rewards then
    RewardDistributor:DistributeRewards(player, rewards)
end

-- Get available quests at an NPC:
local available = tracker:GetAvailableQuests(player, "VillageElder")
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

When the user asks to implement a quest system, ask or infer:

- `$OBJECTIVE_TYPES` - Which objective types to support: {"Kill", "Collect", "Talk", "Explore", "Interact", "Escort", "Survive"}
- `$QUEST_CATEGORIES` - Quest categories: {"Main", "Side", "Daily", "Weekly"}
- `$ENABLE_CHAINS` - Support quest chains/prerequisites: true/false
- `$ENABLE_TIME_LIMIT` - Timed quests: true/false
- `$ENABLE_REPEATABLE` - Repeatable quests (dailies): true/false
- `$AUTO_COMPLETE` - Auto-complete when objectives done vs require turn-in: true/false
- `$REWARD_TYPES` - What rewards to support: {"XP", "Currency", "Items", "CustomReward"}
- `$ENABLE_TRACKING_UI` - Show objective tracker on HUD: true/false
- `$ENABLE_QUEST_LOG` - Full quest log UI: true/false
- `$MAX_ACTIVE_QUESTS` - Maximum simultaneous active quests: 10
- `$ENABLE_NPC_INDICATORS` - Show quest markers above NPCs: true/false
- `$ENABLE_DATASTORE` - Persist quest progress to DataStore: true/false
