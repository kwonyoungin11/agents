---
name: pet-follow-system
description: |
  Pet follow system for Roblox experiences. Covers AlignPosition-based following,
  pet inventory with DataStore persistence, pet leveling and XP, pet abilities,
  equip/unequip mechanics, and pet hatching/acquisition.
  키워드: 펫 시스템, 따라오기, 펫 인벤토리, 펫 레벨, 펫 능력, 장착 해제
allowed-tools:
  - Bash
  - Read
  - Edit
  - Write
  - Glob
  - Grep
effort: high
---

# Pet Follow System

Complete pet system for Roblox: physics-based following with AlignPosition, inventory management, leveling, abilities, and equip/unequip. All code is Luau (Roblox's typed Lua variant).

---

## Architecture Overview

```
ReplicatedStorage/
  Shared/
    PetConfig.luau          -- Pet definitions, stats, rarities
    PetTypes.luau           -- Type definitions
  Remotes/
    PetRemotes/             -- RemoteEvents and RemoteFunctions
ServerScriptService/
  Services/
    PetService.luau         -- Server authority: inventory, equip, leveling
ServerStorage/
  PetModels/                -- Pet model assets (MeshParts)
StarterPlayerScripts/
  Controllers/
    PetController.luau      -- Client: follow logic, rendering, UI bridge
```

---

## 1. Pet Configuration (Shared)

```luau
-- ReplicatedStorage/Shared/PetConfig.luau
--!strict

export type PetRarity = "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary" | "Mythic"

export type PetAbility = {
    name: string,
    description: string,
    unlockLevel: number,
    cooldown: number,
    effect: string, -- key looked up by ability system
}

export type PetDefinition = {
    id: string,
    displayName: string,
    rarity: PetRarity,
    modelName: string,          -- maps to ServerStorage.PetModels child
    baseSpeed: number,          -- follow speed multiplier
    followDistance: number,      -- studs behind player
    floatHeight: number,        -- studs above ground
    maxLevel: number,
    xpPerLevel: (level: number) -> number,
    abilities: { PetAbility },
    passiveBonus: string?,      -- e.g. "+10% coins"
}

export type OwnedPet = {
    uuid: string,               -- unique instance id
    petId: string,              -- references PetDefinition.id
    level: number,
    xp: number,
    equipped: boolean,
    acquiredTimestamp: number,
    nickname: string?,
}

local PetConfig = {}

PetConfig.MAX_EQUIPPED = 3
PetConfig.MAX_INVENTORY = 50

PetConfig.RARITY_WEIGHTS: { [PetRarity]: number } = {
    Common = 50,
    Uncommon = 25,
    Rare = 15,
    Epic = 7,
    Legendary = 2.5,
    Mythic = 0.5,
}

PetConfig.RARITY_COLORS: { [PetRarity]: Color3 } = {
    Common = Color3.fromRGB(180, 180, 180),
    Uncommon = Color3.fromRGB(0, 200, 0),
    Rare = Color3.fromRGB(0, 120, 255),
    Epic = Color3.fromRGB(180, 0, 255),
    Legendary = Color3.fromRGB(255, 200, 0),
    Mythic = Color3.fromRGB(255, 50, 50),
}

PetConfig.Pets: { [string]: PetDefinition } = {
    fire_dragon = {
        id = "fire_dragon",
        displayName = "Fire Dragon",
        rarity = "Legendary",
        modelName = "FireDragon",
        baseSpeed = 1.2,
        followDistance = 6,
        floatHeight = 3,
        maxLevel = 50,
        xpPerLevel = function(level: number): number
            return math.floor(100 * (1.15 ^ level))
        end,
        abilities = {
            {
                name = "Flame Aura",
                description = "Damages nearby enemies for 5% max HP/sec",
                unlockLevel = 5,
                cooldown = 30,
                effect = "flame_aura",
            },
            {
                name = "Fire Breath",
                description = "Cone attack dealing AoE damage",
                unlockLevel = 15,
                cooldown = 45,
                effect = "fire_breath",
            },
        },
        passiveBonus = "+15% damage",
    },
    crystal_cat = {
        id = "crystal_cat",
        displayName = "Crystal Cat",
        rarity = "Rare",
        modelName = "CrystalCat",
        baseSpeed = 1.0,
        followDistance = 4,
        floatHeight = 2,
        maxLevel = 30,
        xpPerLevel = function(level: number): number
            return math.floor(80 * (1.12 ^ level))
        end,
        abilities = {
            {
                name = "Gem Magnet",
                description = "Increases pickup range by 50%",
                unlockLevel = 3,
                cooldown = 0,
                effect = "gem_magnet",
            },
        },
        passiveBonus = "+20% coins",
    },
}

return PetConfig
```

---

## 2. Server Pet Service

```luau
-- ServerScriptService/Services/PetService.luau
--!strict

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local PetConfig = require(ReplicatedStorage.Shared.PetConfig)

type OwnedPet = PetConfig.OwnedPet

local PetService = {}
PetService.__index = PetService

local petDataStore = DataStoreService:GetDataStore("PetData_v1")

-- In-memory cache: player -> owned pets
local playerPets: { [Player]: { OwnedPet } } = {}

-- Active pet models in workspace
local activePetModels: { [string]: Model } = {} -- uuid -> Model

-------------------------------------------------
-- Data Persistence
-------------------------------------------------

local function loadPlayerPets(player: Player): { OwnedPet }
    local success, data = pcall(function()
        return petDataStore:GetAsync("pets_" .. player.UserId)
    end)
    if success and data then
        return data :: { OwnedPet }
    end
    return {}
end

local function savePlayerPets(player: Player)
    local pets = playerPets[player]
    if not pets then return end

    local success, err = pcall(function()
        petDataStore:SetAsync("pets_" .. player.UserId, pets)
    end)
    if not success then
        warn("[PetService] Failed to save pets for", player.Name, err)
    end
end

-------------------------------------------------
-- Inventory Management
-------------------------------------------------

function PetService.GetInventory(player: Player): { OwnedPet }
    return playerPets[player] or {}
end

function PetService.GetEquippedPets(player: Player): { OwnedPet }
    local pets = playerPets[player] or {}
    local equipped = {}
    for _, pet in pets do
        if pet.equipped then
            table.insert(equipped, pet)
        end
    end
    return equipped
end

function PetService.FindPetByUUID(player: Player, uuid: string): OwnedPet?
    local pets = playerPets[player] or {}
    for _, pet in pets do
        if pet.uuid == uuid then
            return pet
        end
    end
    return nil
end

function PetService.AddPet(player: Player, petId: string): OwnedPet?
    local definition = PetConfig.Pets[petId]
    if not definition then
        warn("[PetService] Unknown pet id:", petId)
        return nil
    end

    local pets = playerPets[player]
    if not pets then return nil end

    if #pets >= PetConfig.MAX_INVENTORY then
        local remotes = ReplicatedStorage:FindFirstChild("PetRemotes")
        if remotes then
            local notify = remotes:FindFirstChild("Notify")
            if notify and notify:IsA("RemoteEvent") then
                notify:FireClient(player, "InventoryFull", "Pet inventory is full!")
            end
        end
        return nil
    end

    local newPet: OwnedPet = {
        uuid = HttpService:GenerateGUID(false),
        petId = petId,
        level = 1,
        xp = 0,
        equipped = false,
        acquiredTimestamp = os.time(),
        nickname = nil,
    }

    table.insert(pets, newPet)
    return newPet
end

function PetService.RemovePet(player: Player, uuid: string): boolean
    local pets = playerPets[player]
    if not pets then return false end

    for i, pet in pets do
        if pet.uuid == uuid then
            if pet.equipped then
                PetService.UnequipPet(player, uuid)
            end
            table.remove(pets, i)
            return true
        end
    end
    return false
end

-------------------------------------------------
-- Equip / Unequip
-------------------------------------------------

function PetService.EquipPet(player: Player, uuid: string): boolean
    local pet = PetService.FindPetByUUID(player, uuid)
    if not pet then return false end
    if pet.equipped then return true end

    local equipped = PetService.GetEquippedPets(player)
    if #equipped >= PetConfig.MAX_EQUIPPED then
        return false
    end

    pet.equipped = true
    PetService._SpawnPetModel(player, pet)

    local remotes = ReplicatedStorage:FindFirstChild("PetRemotes")
    if remotes then
        local equipEvent = remotes:FindFirstChild("PetEquipped")
        if equipEvent and equipEvent:IsA("RemoteEvent") then
            equipEvent:FireClient(player, pet)
        end
    end

    return true
end

function PetService.UnequipPet(player: Player, uuid: string): boolean
    local pet = PetService.FindPetByUUID(player, uuid)
    if not pet then return false end
    if not pet.equipped then return true end

    pet.equipped = false
    PetService._DespawnPetModel(uuid)

    local remotes = ReplicatedStorage:FindFirstChild("PetRemotes")
    if remotes then
        local unequipEvent = remotes:FindFirstChild("PetUnequipped")
        if unequipEvent and unequipEvent:IsA("RemoteEvent") then
            unequipEvent:FireClient(player, uuid)
        end
    end

    return true
end

-------------------------------------------------
-- Leveling & XP
-------------------------------------------------

function PetService.AddXP(player: Player, uuid: string, amount: number): boolean
    local pet = PetService.FindPetByUUID(player, uuid)
    if not pet then return false end

    local definition = PetConfig.Pets[pet.petId]
    if not definition then return false end

    if pet.level >= definition.maxLevel then return false end

    pet.xp += amount
    local leveled = false

    while pet.level < definition.maxLevel do
        local needed = definition.xpPerLevel(pet.level)
        if pet.xp >= needed then
            pet.xp -= needed
            pet.level += 1
            leveled = true

            for _, ability in definition.abilities do
                if ability.unlockLevel == pet.level then
                    local remotes = ReplicatedStorage:FindFirstChild("PetRemotes")
                    if remotes then
                        local abilityEvent = remotes:FindFirstChild("AbilityUnlocked")
                        if abilityEvent and abilityEvent:IsA("RemoteEvent") then
                            abilityEvent:FireClient(player, pet.uuid, ability.name)
                        end
                    end
                end
            end
        else
            break
        end
    end

    if leveled then
        local remotes = ReplicatedStorage:FindFirstChild("PetRemotes")
        if remotes then
            local levelEvent = remotes:FindFirstChild("PetLevelUp")
            if levelEvent and levelEvent:IsA("RemoteEvent") then
                levelEvent:FireClient(player, pet.uuid, pet.level)
            end
        end
    end

    return true
end

-------------------------------------------------
-- Pet Model Spawn / Despawn
-------------------------------------------------

function PetService._SpawnPetModel(player: Player, pet: OwnedPet)
    local definition = PetConfig.Pets[pet.petId]
    if not definition then return end

    local modelsFolder = ServerStorage:FindFirstChild("PetModels")
    if not modelsFolder then
        warn("[PetService] ServerStorage.PetModels not found")
        return
    end

    local template = modelsFolder:FindFirstChild(definition.modelName)
    if not template then
        warn("[PetService] Pet model not found:", definition.modelName)
        return
    end

    local model = template:Clone() :: Model
    model.Name = "Pet_" .. pet.uuid

    model:SetAttribute("OwnerUserId", player.UserId)
    model:SetAttribute("PetUUID", pet.uuid)
    model:SetAttribute("PetId", pet.petId)
    model:SetAttribute("Level", pet.level)

    local character = player.Character
    if character then
        local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
        if rootPart then
            local primaryPart = model.PrimaryPart
            if primaryPart then
                model:PivotTo(rootPart.CFrame * CFrame.new(3, definition.floatHeight, -definition.followDistance))

                -- AlignPosition for smooth following
                local attachment0 = Instance.new("Attachment")
                attachment0.Name = "PetAttachment"
                attachment0.Parent = primaryPart

                local alignPos = Instance.new("AlignPosition")
                alignPos.Mode = Enum.PositionAlignmentMode.OneAttachment
                alignPos.Attachment0 = attachment0
                alignPos.MaxForce = 50000
                alignPos.MaxVelocity = definition.baseSpeed * 50
                alignPos.Responsiveness = 15
                alignPos.Parent = primaryPart

                local alignOri = Instance.new("AlignOrientation")
                alignOri.Mode = Enum.OrientationAlignmentMode.OneAttachment
                alignOri.Attachment0 = attachment0
                alignOri.MaxTorque = 20000
                alignOri.Responsiveness = 10
                alignOri.Parent = primaryPart

                for _, part in model:GetDescendants() do
                    if part:IsA("BasePart") then
                        part.CanCollide = false
                        part.Anchored = false
                    end
                end
            end
        end
    end

    local petFolder = workspace:FindFirstChild("ActivePets")
    if not petFolder then
        petFolder = Instance.new("Folder")
        petFolder.Name = "ActivePets"
        petFolder.Parent = workspace
    end
    model.Parent = petFolder

    activePetModels[pet.uuid] = model
end

function PetService._DespawnPetModel(uuid: string)
    local model = activePetModels[uuid]
    if model then
        model:Destroy()
        activePetModels[uuid] = nil
    end
end

-------------------------------------------------
-- Follow Update Loop (server-side position target)
-------------------------------------------------

local function updatePetPositions()
    for uuid, model in activePetModels do
        local ownerUserId = model:GetAttribute("OwnerUserId")
        local petId = model:GetAttribute("PetId")
        if not ownerUserId or not petId then continue end

        local definition = PetConfig.Pets[petId]
        if not definition then continue end

        local player = Players:GetPlayerByUserId(ownerUserId)
        if not player or not player.Character then continue end

        local rootPart = player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
        if not rootPart then continue end

        local primaryPart = model.PrimaryPart
        if not primaryPart then continue end

        local alignPos = primaryPart:FindFirstChildOfClass("AlignPosition")
        if alignPos then
            -- Distribute pets in a semicircle behind the player
            local equippedPets = {}
            for otherUuid, otherModel in activePetModels do
                if otherModel:GetAttribute("OwnerUserId") == ownerUserId then
                    table.insert(equippedPets, otherUuid)
                end
            end
            table.sort(equippedPets)

            local index = table.find(equippedPets, uuid) or 1
            local count = #equippedPets
            local angle = math.rad(-90 + (180 / (count + 1)) * index)
            local offset = CFrame.new(
                math.cos(angle) * definition.followDistance,
                definition.floatHeight,
                math.sin(angle) * definition.followDistance
            )

            local targetPos = (rootPart.CFrame * offset).Position
            alignPos.Position = targetPos
        end

        local alignOri = primaryPart:FindFirstChildOfClass("AlignOrientation")
        if alignOri then
            local lookDir = (rootPart.Position - primaryPart.Position)
            if lookDir.Magnitude > 0.1 then
                alignOri.CFrame = CFrame.lookAt(Vector3.zero, lookDir.Unit)
            end
        end
    end
end

-------------------------------------------------
-- Remote Setup & Player Lifecycle
-------------------------------------------------

function PetService.Init()
    local remotesFolder = Instance.new("Folder")
    remotesFolder.Name = "PetRemotes"
    remotesFolder.Parent = ReplicatedStorage

    local remoteNames = {
        "EquipRequest", "UnequipRequest", "UseAbility",
        "PetEquipped", "PetUnequipped", "PetLevelUp",
        "AbilityUnlocked", "Notify", "InventoryUpdate",
    }
    for _, name in remoteNames do
        local remote = Instance.new("RemoteEvent")
        remote.Name = name
        remote.Parent = remotesFolder
    end

    local getInventory = Instance.new("RemoteFunction")
    getInventory.Name = "GetInventory"
    getInventory.Parent = remotesFolder

    local equip = remotesFolder:FindFirstChild("EquipRequest") :: RemoteEvent
    equip.OnServerEvent:Connect(function(player: Player, uuid: string)
        PetService.EquipPet(player, uuid)
        local invEvent = remotesFolder:FindFirstChild("InventoryUpdate") :: RemoteEvent
        invEvent:FireClient(player, PetService.GetInventory(player))
    end)

    local unequip = remotesFolder:FindFirstChild("UnequipRequest") :: RemoteEvent
    unequip.OnServerEvent:Connect(function(player: Player, uuid: string)
        PetService.UnequipPet(player, uuid)
        local invEvent = remotesFolder:FindFirstChild("InventoryUpdate") :: RemoteEvent
        invEvent:FireClient(player, PetService.GetInventory(player))
    end)

    getInventory.OnServerInvoke = function(player: Player)
        return PetService.GetInventory(player)
    end

    Players.PlayerAdded:Connect(function(player: Player)
        local pets = loadPlayerPets(player)
        playerPets[player] = pets

        player.CharacterAdded:Connect(function(_character: Model)
            task.wait(1)
            local equippedPets = PetService.GetEquippedPets(player)
            for _, pet in equippedPets do
                PetService._DespawnPetModel(pet.uuid)
                PetService._SpawnPetModel(player, pet)
            end
        end)
    end)

    Players.PlayerRemoving:Connect(function(player: Player)
        savePlayerPets(player)

        for uuid, model in activePetModels do
            if model:GetAttribute("OwnerUserId") == player.UserId then
                model:Destroy()
                activePetModels[uuid] = nil
            end
        end

        playerPets[player] = nil
    end)

    -- Periodic save
    task.spawn(function()
        while true do
            task.wait(120)
            for player, _ in playerPets do
                if player.Parent then
                    savePlayerPets(player)
                end
            end
        end
    end)

    -- Follow update heartbeat
    game:GetService("RunService").Heartbeat:Connect(function()
        updatePetPositions()
    end)
end

return PetService
```

---

## 3. Client Pet Controller

```luau
-- StarterPlayerScripts/Controllers/PetController.luau
--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PetConfig = require(ReplicatedStorage.Shared.PetConfig)

local player = Players.LocalPlayer
local petRemotes = ReplicatedStorage:WaitForChild("PetRemotes")

local PetController = {}

local cachedInventory: { PetConfig.OwnedPet } = {}

function PetController.RequestEquip(uuid: string)
    local equipRemote = petRemotes:FindFirstChild("EquipRequest") :: RemoteEvent
    equipRemote:FireServer(uuid)
end

function PetController.RequestUnequip(uuid: string)
    local unequipRemote = petRemotes:FindFirstChild("UnequipRequest") :: RemoteEvent
    unequipRemote:FireServer(uuid)
end

function PetController.GetInventory(): { PetConfig.OwnedPet }
    return cachedInventory
end

function PetController.FetchInventory(): { PetConfig.OwnedPet }
    local getInv = petRemotes:FindFirstChild("GetInventory") :: RemoteFunction
    cachedInventory = getInv:InvokeServer()
    return cachedInventory
end

function PetController.Init()
    local invUpdate = petRemotes:FindFirstChild("InventoryUpdate") :: RemoteEvent
    invUpdate.OnClientEvent:Connect(function(inventory: { PetConfig.OwnedPet })
        cachedInventory = inventory
        local bindable = ReplicatedStorage:FindFirstChild("PetInventoryChanged")
        if not bindable then
            bindable = Instance.new("BindableEvent")
            bindable.Name = "PetInventoryChanged"
            bindable.Parent = ReplicatedStorage
        end
        (bindable :: BindableEvent):Fire(cachedInventory)
    end)

    -- Level up VFX
    local levelUp = petRemotes:FindFirstChild("PetLevelUp") :: RemoteEvent
    levelUp.OnClientEvent:Connect(function(uuid: string, newLevel: number)
        local petFolder = workspace:FindFirstChild("ActivePets")
        if not petFolder then return end

        local petModel = petFolder:FindFirstChild("Pet_" .. uuid)
        if petModel and petModel:IsA("Model") and petModel.PrimaryPart then
            local particles = Instance.new("ParticleEmitter")
            particles.Color = ColorSequence.new(Color3.fromRGB(255, 255, 100))
            particles.Size = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 0.5),
                NumberSequenceKeypoint.new(1, 0),
            })
            particles.Lifetime = NumberRange.new(0.5, 1)
            particles.Rate = 50
            particles.Speed = NumberRange.new(5, 10)
            particles.SpreadAngle = Vector2.new(360, 360)
            particles.Parent = petModel.PrimaryPart

            task.delay(1.5, function()
                particles:Destroy()
            end)
        end
    end)

    task.spawn(function()
        PetController.FetchInventory()
    end)
end

return PetController
```

---

## 4. Pet Ability System

```luau
-- ServerScriptService/Services/PetAbilityService.luau
--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PetConfig = require(ReplicatedStorage.Shared.PetConfig)

local PetAbilityService = {}

local cooldowns: { [string]: { [string]: number } } = {}

local abilityHandlers: { [string]: (player: Player, petModel: Model, level: number) -> () } = {}

abilityHandlers["flame_aura"] = function(player: Player, petModel: Model, level: number)
    local primaryPart = petModel.PrimaryPart
    if not primaryPart then return end

    local radius = 15 + level * 0.5
    local damage = 5 + level * 2

    local fire = Instance.new("Fire")
    fire.Size = radius / 2
    fire.Heat = 5
    fire.Parent = primaryPart

    task.spawn(function()
        for _ = 1, 10 do
            task.wait(1)
            for _, model in workspace:GetChildren() do
                if model:IsA("Model") and model:FindFirstChild("Humanoid") then
                    local humanoid = model:FindFirstChild("Humanoid") :: Humanoid
                    local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
                    if root and humanoid.Health > 0 then
                        local ownerChar = player.Character
                        if model ~= ownerChar then
                            local dist = (root.Position - primaryPart.Position).Magnitude
                            if dist <= radius then
                                humanoid:TakeDamage(damage)
                            end
                        end
                    end
                end
            end
        end
        fire:Destroy()
    end)
end

abilityHandlers["gem_magnet"] = function(_player: Player, petModel: Model, _level: number)
    petModel:SetAttribute("GemMagnetActive", true)
end

function PetAbilityService.UseAbility(player: Player, uuid: string, abilityName: string): boolean
    local petFolder = workspace:FindFirstChild("ActivePets")
    if not petFolder then return false end

    local petModel = petFolder:FindFirstChild("Pet_" .. uuid)
    if not petModel or not petModel:IsA("Model") then return false end

    local petId = petModel:GetAttribute("PetId") :: string?
    local level = petModel:GetAttribute("Level") :: number? or 1
    if not petId then return false end

    local definition = PetConfig.Pets[petId]
    if not definition then return false end

    local abilityDef: PetConfig.PetAbility? = nil
    for _, ability in definition.abilities do
        if ability.name == abilityName then
            abilityDef = ability
            break
        end
    end
    if not abilityDef then return false end

    if level < abilityDef.unlockLevel then return false end

    if not cooldowns[uuid] then cooldowns[uuid] = {} end
    local lastUsed = cooldowns[uuid][abilityName] or 0
    if tick() - lastUsed < abilityDef.cooldown then return false end

    local handler = abilityHandlers[abilityDef.effect]
    if handler then
        cooldowns[uuid][abilityName] = tick()
        handler(player, petModel :: Model, level)
        return true
    end

    return false
end

return PetAbilityService
```

---

## Key Implementation Notes

1. **AlignPosition** is the core physics constraint for smooth following. `Responsiveness` controls how snappy the pet tracks. Higher = more rigid; lower = floaty.
2. **Server authority**: All pet data (inventory, equip state, XP) is owned by the server. The client only sends requests and receives updates.
3. **DataStore throttling**: Periodic saves every 120 seconds plus save on PlayerRemoving. Use `UpdateAsync` in production for conflict safety.
4. **Pet orbit**: Multiple equipped pets spread in a semicircle behind the player using trigonometric offset calculation.
5. **Ability system** uses a handler registry pattern -- add new abilities by registering a function keyed to the effect string.
6. **Network optimization**: Only fire RemoteEvents when state actually changes.

---

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

The user may specify:
- `$PET_NAMES` -- Custom list of pet definitions to generate instead of the defaults
- `$MAX_EQUIPPED` -- Override for maximum simultaneously equipped pets (default 3)
- `$MAX_INVENTORY` -- Override for maximum inventory size (default 50)
- `$FOLLOW_STYLE` -- "orbit" (semicircle behind player) or "trail" (single-file line behind player) or "formation" (fixed grid)
- `$PERSISTENCE` -- "datastore" (default) or "profileservice" for ProfileService-based saving
- `$ABILITIES` -- Whether to include the ability system (default true)
- `$HATCHING` -- Whether to include egg hatching mechanics (default false)
