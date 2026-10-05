--[[
    CombinedData / DataHandler (Multiplayer & Single-Player Edition)
    Description:
        Provides a unified API merging Tower Ownership, Golden Skin/Perks detection,
        Tower EXP progression, Skill‑tree extraction, Player Stats (Level/EXP/Coins/Gems),
        and Multiplayer server querying & cross-client synchronization.
        • checkPlayer("Username or ID"): Checks first if the player exists in the server;
          returns the Player instance if found, or "player does not exist" if not found.
        • Multiplayer Replicator Integration: Read any player's Level, Coins, Gems, EXP,
          Triumphs, Wins, Loses, Equipped Towers, Match Cash, Tower Count, and Skill Tree
          directly from replicated instances (Player ValueBases & StateReplicators).
        • PeerData & WebSocket Synchronization: Compatible with WebSocket relay servers
          for syncing unequipped inventories, owned skins, and trial statuses across party members.
        • Accurate Golden tower ownership (checks Inventory.Skins, not just equipped state).
        • Active Golden perks detector (checks if perk is enabled in loadout).
        • Full Tower EXP progression for all 8 towers (progress, required, max level, uncapped).
        • Fast Cache-based Player Stats: Values.Level, Values.Experience, Experience(level + 1),
          Values.Coins, and Values.Gems with safe fallback layers.
        • Skill‑tree extraction from Workspace["1"] … Workspace["17"] and GameStateReplicator.
        • Lightweight, synchronous, and safe for mobile/third-party executors.
]]--

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

-- ---------------------------------------------------------------------
-- Core helpers (LocalPlayer, PlayerGui, number parsing, player lookup)
-- ---------------------------------------------------------------------
local function getLocalPlayer()
    local lp = Players.LocalPlayer
    if not lp then
        pcall(function()
            Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
        end)
        lp = Players.LocalPlayer
    end
    return lp
end

local function getPlayerGui(timeout)
    timeout = timeout or 1
    local lp = getLocalPlayer()
    if not lp then return nil end
    local pgui = lp:FindFirstChild("PlayerGui")
    if not pgui and timeout > 0 then
        pgui = lp:WaitForChild("PlayerGui", timeout)
    end
    return pgui
end

local function parseNumber(str)
    if not str then return 0 end
    local cleaned = tostring(str):gsub("<[^>]+>", ""):match("[%d,]+")
    cleaned = cleaned and cleaned:gsub("%D", "") or ""
    return tonumber(cleaned) or 0
end

-- ---------------------------------------------------------------------
-- Internal Cache & Game Module Access
-- ---------------------------------------------------------------------
local Cache = nil
local Experience = nil
local TowerExpUtil = nil
local Content = nil
local InventoryController = nil
local MatchmakingTrialData = nil

pcall(function()
    Cache = require(ReplicatedStorage.Client.Modules.Cache)
end)
pcall(function()
    Experience = require(ReplicatedStorage.Shared.Modules.Experience)
end)
pcall(function()
    TowerExpUtil = require(ReplicatedStorage.Shared.Modules.TowerExpUtil)
end)
pcall(function()
    Content = require(ReplicatedStorage.Shared.Modules.Content)
end)
pcall(function()
    InventoryController = require(ReplicatedStorage.Client.Interfaces.LegacyInterface.Controllers.InventoryController)
end)
pcall(function()
    MatchmakingTrialData = require(ReplicatedStorage.Client.Interfaces.Lobby.Components.NewMatchmaking.MatchmakingTrialData)
end)

-- Helper to safely get value synchronously without yielding or dropping thread capability
local function getStat(name)
    if Cache and (type(Cache) == "table" or type(Cache) == "function") then
        local ok, val = pcall(function()
            local atom = Cache(name)
            if atom then
                -- 1. Check synchronous cached value directly
                if type(atom.GetValue) == "function" then
                    local fastVal = atom:GetValue()
                    if fastVal ~= nil then
                        return fastVal
                    end
                end
                -- NOTE: We NEVER call atom:Get():await() because yielding inside a Promise
                -- drops Luau thread identity and capability in executors.
            end
            return nil
        end)
        if ok and val ~= nil then
            return val
        end
    end
    return nil
end

local function getCacheValue(cacheName)
    return getStat(cacheName)
end

-- ---------------------------------------------------------------------
-- Main Module Definition
-- ---------------------------------------------------------------------
local CombinedData = {}
CombinedData.__index = CombinedData

local SkillTreeData = {
    [1] = { Name = "Enhanced Optics" },
    [2] = { Name = "Resourcefulness" },
    [3] = { Name = "Fortify" },
    [4] = { Name = "Over-Heal" },
    [5] = { Name = "Fight Dirty" },
    [6] = { Name = "Extreme Conditioning" },
    [7] = { Name = "Stonks" },
    [8] = { Name = "Expanded Barracks" },
    [9] = { Name = "Improved Gunpowder" },
    [10] = { Name = "Beefed Up Minions" },
    [11] = { Name = "Precision" },
    [12] = { Name = "Scavenger" },
    [13] = { Name = "Accelerator" },
    [14] = { Name = "Re-enforcements" },
    [15] = { Name = "Bigger Budget" },
    [16] = { Name = "Bandages" },
    [17] = { Name = "Scholar" },
}

CombinedData.SkillTreeData = SkillTreeData

-- List of all 8 towers with progression systems
CombinedData.ProgressionTowers = {
    "Scout",
    "Shotgunner",
    "Crook Boss",
    "Minigunner",
    "EvolvedOperator",
    "EvolvedEnforcer",
    "EvolvedKingpin",
    "EvolvedJuggernaut"
}

-- ---------------------------------------------------------------------
-- Multiplayer & Player Resolution System
-- ---------------------------------------------------------------------

--- Resolves a player from Players service by Username, DisplayName, UserId, or Player instance.
-- Returns Player instance if found in the server, or nil if not found.
local function resolvePlayer(target)
    if target == nil or target == "" then
        return nil
    end

    -- If target is already a Player instance
    if typeof(target) == "Instance" and target:IsA("Player") then
        if target.Parent == Players then
            return target
        end
        return nil
    end

    local targetStr = tostring(target):gsub("^%s+", ""):gsub("%s+$", "")
    if targetStr == "" then return nil end

    local targetNum = tonumber(targetStr)

    -- 1. Check UserId match
    if targetNum then
        for _, p in ipairs(Players:GetPlayers()) do
            if p.UserId == targetNum then
                return p
            end
        end
    end

    local targetLower = string.lower(targetStr)

    -- 2. Exact Name match (case-insensitive)
    for _, p in ipairs(Players:GetPlayers()) do
        if string.lower(p.Name) == targetLower then
            return p
        end
    end

    -- 3. Exact DisplayName match (case-insensitive)
    for _, p in ipairs(Players:GetPlayers()) do
        if string.lower(p.DisplayName) == targetLower then
            return p
        end
    end

    -- 4. Prefix Name match
    for _, p in ipairs(Players:GetPlayers()) do
        if string.sub(string.lower(p.Name), 1, #targetLower) == targetLower then
            return p
        end
    end

    -- 5. Prefix DisplayName match
    for _, p in ipairs(Players:GetPlayers()) do
        if string.sub(string.lower(p.DisplayName), 1, #targetLower) == targetLower then
            return p
        end
    end

    return nil
end

--- Checks if a player exists in the server by Username, DisplayName, or UserId.
-- If the player does NOT exist in the server, returns "player does not exist", false.
-- If the player DOES exist, returns playerInstance, true.
-- Can be called as checkPlayer("Username or ID") or CombinedData:CheckPlayer("Username or ID").
local function checkPlayer(selfOrTarget, maybeTarget)
    local target = (selfOrTarget == CombinedData or (type(selfOrTarget) == "table" and selfOrTarget.__index == CombinedData))
        and maybeTarget or selfOrTarget

    local player = resolvePlayer(target)
    if not player then
        return "player does not exist", false
    end
    return player, true
end

CombinedData.CheckPlayer = checkPlayer
CombinedData.checkPlayer = checkPlayer

--- Alternative player lookup returning playerInstance, nil on success or nil, "player does not exist" on failure.
function CombinedData:GetPlayer(playerOrTarget)
    local player = resolvePlayer(playerOrTarget)
    if not player then
        return nil, "player does not exist"
    end
    return player, nil
end

--- Resolves target player argument with support for both `:` and `.` syntax.
-- Defaults to LocalPlayer when target is omitted.
local function resolveTargetPlayer(self, playerOrTarget)
    if playerOrTarget == nil then
        if self and self ~= CombinedData and (typeof(self) == "Instance" or type(self) == "string" or type(self) == "number") then
            return resolvePlayer(self)
        end
        return getLocalPlayer()
    end
    return resolvePlayer(playerOrTarget)
end

-- ---------------------------------------------------------------------
-- StateReplicator Helpers (Multiplayer TDS Replicated Data)
-- ---------------------------------------------------------------------

local function getPlayerReplicator(player)
    if not player then return nil end
    local stateRep = ReplicatedStorage:FindFirstChild("StateReplicators")
    if not stateRep then return nil end

    local pUserId = player.UserId
    local pName = string.lower(player.Name)

    for _, folder in ipairs(stateRep:GetChildren()) do
        if folder.Name == "PlayerReplicator" then
            local uId = folder:GetAttribute("UserId")
            if uId and (uId == pUserId or tonumber(uId) == pUserId) then
                return folder
            end
            local fName = folder:GetAttribute("Name")
            if fName and string.lower(tostring(fName)) == pName then
                return folder
            end
        end
    end
    return nil
end

local function getGameStateReplicator()
    local stateRep = ReplicatedStorage:FindFirstChild("StateReplicators")
    return stateRep and stateRep:FindFirstChild("GameStateReplicator")
end

-- ---------------------------------------------------------------------
-- PeerData Management (Cross-client WebSocket synchronization)
-- ---------------------------------------------------------------------
CombinedData.PeerData = {}

--- Stores synced peer data received from WebSocket relay server
function CombinedData:SetPeerData(identifier, data)
    if not identifier or identifier == "" or type(data) ~= "table" then return end
    local clean = string.lower(string.gsub(tostring(identifier), "%s+", ""))
    CombinedData.PeerData[identifier] = data
    CombinedData.PeerData[clean] = data
    if data.UserId or data.userId then
        CombinedData.PeerData[tostring(data.UserId or data.userId)] = data
    end
    if data.Username or data.username then
        CombinedData.PeerData[string.lower(string.gsub(tostring(data.Username or data.username), "%s+", ""))] = data
    end
end

--- Clears cached peer data for a specific player or all peers
function CombinedData:ClearPeerData(identifier)
    if not identifier then
        CombinedData.PeerData = {}
        return
    end
    local clean = string.lower(string.gsub(tostring(identifier), "%s+", ""))
    CombinedData.PeerData[identifier] = nil
    CombinedData.PeerData[clean] = nil
end

--- Retrieves cached peer data by Username or UserId
function CombinedData:GetPeerData(identifier)
    if not identifier or identifier == "" then
        for _, peer in pairs(CombinedData.PeerData) do
            if type(peer) == "table" then return peer end
        end
        return nil
    end

    if typeof(identifier) == "Instance" and identifier:IsA("Player") then
        identifier = identifier.UserId
    end

    local clean = string.lower(string.gsub(tostring(identifier), "%s+", ""))
    if CombinedData.PeerData[identifier] then
        return CombinedData.PeerData[identifier]
    end
    if CombinedData.PeerData[clean] then
        return CombinedData.PeerData[clean]
    end

    for key, peer in pairs(CombinedData.PeerData) do
        if type(peer) == "table" then
            local uName = string.lower(string.gsub(tostring(peer.username or peer.Username or ""), "%s+", ""))
            local uId = tostring(peer.userId or peer.UserId or "")
            if uName == clean or uId == clean then
                return peer
            end
        end
    end
    return nil
end

-- ---------------------------------------------------------------------
-- Equipped Towers & Match Data (Multiplayer Replicated)
-- ---------------------------------------------------------------------

--- Returns the list of 5 equipped towers for any player in the server
function CombinedData:GetEquippedTowers(playerOrTarget)
    local player = resolveTargetPlayer(self, playerOrTarget)
    if not player then
        if playerOrTarget then
            return {}, "player does not exist"
        end
        player = getLocalPlayer()
    end
    if not player then return {} end

    -- 1. Check StateReplicators.PlayerReplicator (active match)
    local folder = getPlayerReplicator(player)
    if folder then
        local equipped = folder:GetAttribute("EquippedTowers")
        if type(equipped) == "string" then
            local cleanedJson = equipped:match("%[.*%]")
            if cleanedJson then
                local success, towerTable = pcall(function()
                    return HttpService:JSONDecode(cleanedJson)
                end)
                if success and type(towerTable) == "table" and #towerTable > 0 then
                    return towerTable
                end
            end
        end
    end

    -- 1b. Check direct Player attribute (if replicated in lobby)
    local directEquipped = player:GetAttribute("EquippedTowers")
    if type(directEquipped) == "string" then
        local cleaned = directEquipped:match("%[.*%]")
        if cleaned then
            local ok, decoded = pcall(function() return HttpService:JSONDecode(cleaned) end)
            if ok and type(decoded) == "table" and #decoded > 0 then
                return decoded
            end
        end
    end

    -- 2. If LocalPlayer and in lobby: check InventoryController
    if player == getLocalPlayer() and InventoryController and type(InventoryController.getItems) == "function" then
        local success, items = pcall(function() return InventoryController:getItems() end)
        if success and items then
            local equippedList = {}
            for _, item in pairs(items) do
                if type(item) == "table" and item.type == "tower" and item.equipped == true then
                    table.insert(equippedList, item.name)
                end
            end
            if #equippedList > 0 then
                return equippedList
            end
        end
    end

    -- 3. Check PeerData fallback
    local peer = self:GetPeerData(playerOrTarget or player)
    if peer and (peer.equippedTowers or peer.EquippedTowers) then
        return peer.equippedTowers or peer.EquippedTowers
    end

    return {}
end

--- Returns match-specific data for any player (Cash, TowerCount, Team, Consumables, etc.)
function CombinedData:GetMatchData(playerOrTarget)
    local player = resolveTargetPlayer(self, playerOrTarget)
    if not player then
        if playerOrTarget then
            return nil, "player does not exist"
        end
        player = getLocalPlayer()
    end
    if not player then return nil end

    local folder = getPlayerReplicator(player)
    if not folder then return nil end

    local cash = tonumber(folder:GetAttribute("Cash")) or 0
    local towerCount = tonumber(folder:GetAttribute("TowerCount")) or 0
    local canPlace = folder:GetAttribute("CanPlaceTowers") == true
    local team = folder:GetAttribute("Team")
    local legacyVip = folder:GetAttribute("LegacyVIP") == true
    local vipPlus = folder:GetAttribute("VIPPlus") == true
    local sessionLoaded = folder:GetAttribute("SessionLoaded") == true
    local streak = tonumber(folder:GetAttribute("Streak")) or 0
    local mapsCleared = tonumber(folder:GetAttribute("MapsCleared")) or 0

    local equippedTowers = self:GetEquippedTowers(player)

    local equippedConsumables = {}
    local rawConsumables = folder:GetAttribute("EquippedConsumables")
    if type(rawConsumables) == "string" then
        local clean = rawConsumables:match("%[.*%]")
        if clean then
            pcall(function() equippedConsumables = HttpService:JSONDecode(clean) end)
        end
    end

    return {
        Cash = cash,
        TowerCount = towerCount,
        CanPlaceTowers = canPlace,
        Team = team,
        LegacyVIP = legacyVip,
        VIPPlus = vipPlus,
        SessionLoaded = sessionLoaded,
        Streak = streak,
        MapsCleared = mapsCleared,
        EquippedTowers = equippedTowers,
        EquippedConsumables = equippedConsumables
    }
end

-- ---------------------------------------------------------------------
-- Tower Ownership (Cache -> InventoryController -> UI Scan -> PeerData)
-- ---------------------------------------------------------------------
local function getScrollingContainer(idx)
    local pgui = getPlayerGui()
    if not pgui then return nil end
    local path = {
        "ReactUniversalInventoryView",
        "Holder",
        "windowFrame",
        "towersInventoryFrame",
        "towerContainer",
        idx .. "scrolling"
    }
    local node = pgui
    for _, childName in ipairs(path) do
        node = node:FindFirstChild(childName)
        if not node then return nil end
    end
    return node
end

function CombinedData:IsTowerOwned(towerName, playerOrTarget)
    if not towerName or towerName == "" then return false end

    local player = resolveTargetPlayer(self, playerOrTarget)
    local isLocal = (player == nil or player == getLocalPlayer())
    local targetLower = string.lower(tostring(towerName))

    if isLocal then
        -- 1. Fast Cache Check
        local troops = getCacheValue("Inventory.Troops")
        if troops and type(troops) == "table" then
            if troops[towerName] ~= nil then
                return true
            end
            for tKey, _ in pairs(troops) do
                if string.lower(tostring(tKey)) == targetLower then
                    return true
                end
            end
        end

        -- 2. InventoryController Check
        if InventoryController and type(InventoryController.getItems) == "function" then
            local success, items = pcall(function() return InventoryController:getItems() end)
            if success and items then
                for _, item in pairs(items) do
                    if type(item) == "table" and item.type == "tower" and string.lower(tostring(item.name)) == targetLower then
                        return true
                    end
                end
            end
        end

        -- 3. UI Scrolling Container Fallback
        for i = 1, 7 do
            local container = getScrollingContainer(i)
            if container then
                local towerNode = container:FindFirstChild(towerName)
                if not towerNode then
                    for _, child in ipairs(container:GetChildren()) do
                        if string.lower(child.Name) == targetLower then
                            towerNode = child
                            break
                        end
                    end
                end
                if towerNode then
                    local main = towerNode:FindFirstChild("main")
                    if main and main:FindFirstChild("amountLeft") then
                        return true
                    end
                end
            end
        end
    else
        -- Multiplayer check for other players
        -- 1. Check peer synced inventory if available
        local peer = self:GetPeerData(playerOrTarget or player)
        if peer and (peer.troops or peer.Inventory or peer.towers) then
            local pTroops = peer.troops or peer.Inventory or peer.towers
            if type(pTroops) == "table" then
                if pTroops[towerName] ~= nil or table.find(pTroops, towerName) then
                    return true
                end
                for k, v in pairs(pTroops) do
                    if string.lower(tostring(k)) == targetLower or string.lower(tostring(v)) == targetLower then
                        return true
                    end
                end
            end
        end

        -- 2. Check their Equipped Towers in StateReplicators (if equipped, they definitely own it!)
        local equipped = self:GetEquippedTowers(player)
        if equipped and type(equipped) == "table" then
            for _, tName in ipairs(equipped) do
                if string.lower(tostring(tName)) == targetLower then
                    return true
                end
            end
        end
    end

    return false
end

-- ---------------------------------------------------------------------
-- Golden Towers Ownership & Active Perks
-- ---------------------------------------------------------------------

--- Checks if the player OWNS the Golden version of a tower (even if another skin is equipped)
function CombinedData:IsGoldenOwned(towerName, playerOrTarget)
    if not towerName or towerName == "" then return false end

    local player = resolveTargetPlayer(self, playerOrTarget)
    local isLocal = (player == nil or player == getLocalPlayer())

    if isLocal then
        -- 1. Check Inventory.Skins (Direct ownership list)
        local skins = getCacheValue("Inventory.Skins")
        if skins and type(skins) == "table" and skins[towerName] then
            for _, skin in ipairs(skins[towerName]) do
                if type(skin) == "table" and skin.Name == "Golden" then
                    return true
                end
            end
        end

        -- 2. Check Inventory.Troops (Equipped / Perk state)
        local troops = getCacheValue("Inventory.Troops")
        if troops and type(troops) == "table" and troops[towerName] then
            local tData = troops[towerName]
            if tData.GoldenPerks == true or tData.Skin == "Golden" then
                return true
            end
        end

        -- 3. InventoryController Fallback
        if InventoryController and type(InventoryController.getItems) == "function" then
            local success, items = pcall(function() return InventoryController:getItems() end)
            if success and items then
                for _, item in pairs(items) do
                    if type(item) == "table" and item.type == "tower" and item.name == towerName then
                        if item.golden == true or item.skin == "Golden" then
                            return true
                        end
                    end
                end
            end
        end
    else
        -- Multiplayer check for other players
        local peer = self:GetPeerData(playerOrTarget or player)
        if peer and (peer.goldenSkins or peer.GoldenSkins or peer.skins) then
            local pSkins = peer.goldenSkins or peer.GoldenSkins or peer.skins
            if type(pSkins) == "table" then
                if pSkins[towerName] == true or table.find(pSkins, towerName) then
                    return true
                end
            end
        end

        local folder = getPlayerReplicator(player)
        if folder then
            local equipped = self:GetEquippedTowers(player)
            for _, tName in ipairs(equipped) do
                if string.lower(tostring(tName)) == string.lower(tostring(towerName)) then
                    if string.find(string.lower(tostring(tName)), "golden") then
                        return true
                    end
                end
            end
        end
    end

    return false
end

--- Returns a list and a set of all Golden Towers owned by the player
function CombinedData:GetGoldenOwned()
    local list = {}
    local set = {}

    local skins = getCacheValue("Inventory.Skins")
    if skins and type(skins) == "table" then
        for tower, skinList in pairs(skins) do
            if type(skinList) == "table" then
                for _, skin in ipairs(skinList) do
                    if type(skin) == "table" and skin.Name == "Golden" then
                        table.insert(list, tower)
                        set[tower] = true
                        break
                    end
                end
            end
        end
    end

    local troops = getCacheValue("Inventory.Troops")
    if troops and type(troops) == "table" then
        for tower, data in pairs(troops) do
            if not set[tower] and type(data) == "table" and (data.GoldenPerks == true or data.Skin == "Golden") then
                table.insert(list, tower)
                set[tower] = true
            end
        end
    end

    table.sort(list)
    return list, set
end

--- Checks if a tower currently has its Golden Perk toggled ON
function CombinedData:IsGoldenPerkActive(towerName)
    if not towerName or towerName == "" then return false end

    local troops = getCacheValue("Inventory.Troops")
    if troops and type(troops) == "table" and troops[towerName] then
        return troops[towerName].GoldenPerks == true
    end

    if InventoryController and type(InventoryController.getItems) == "function" then
        local success, items = pcall(function() return InventoryController:getItems() end)
        if success and items then
            for _, item in pairs(items) do
                if type(item) == "table" and item.type == "tower" and item.name == towerName then
                    return item.golden == true
                end
            end
        end
    end

    return false
end

--- Returns a list of all towers that currently have Golden Perks enabled
function CombinedData:GetActiveGoldenPerks()
    local activeList = {}
    local troops = getCacheValue("Inventory.Troops")
    if troops and type(troops) == "table" then
        for tower, data in pairs(troops) do
            if type(data) == "table" and data.GoldenPerks == true then
                table.insert(activeList, tower)
            end
        end
    end
    table.sort(activeList)
    return activeList
end

-- ---------------------------------------------------------------------
-- Tower EXP & Progression System
-- ---------------------------------------------------------------------
local function calculateExpStats(currentExp, baseExp, growthRate, maxLevel)
    currentExp = currentExp or 0
    baseExp = baseExp or 50
    growthRate = growthRate or 1.09
    maxLevel = maxLevel or 20

    local totalRequiredForMax = 0
    local levelCosts = {}
    for i = 1, maxLevel do
        local cost = math.floor(baseExp * (growthRate ^ (i - 1)))
        totalRequiredForMax = totalRequiredForMax + cost
        levelCosts[i] = cost
    end

    local sum = 0
    local cappedLevel = 0
    for i = 1, maxLevel do
        sum = sum + levelCosts[i]
        if currentExp < sum then break end
        cappedLevel = i
    end

    local totalExpCurrentLevel = 0
    for i = 1, cappedLevel do
        totalExpCurrentLevel = totalExpCurrentLevel + levelCosts[i]
    end

    local nextLevelCost = 0
    if cappedLevel < maxLevel then
        nextLevelCost = math.floor(baseExp * (growthRate ^ cappedLevel))
    else
        nextLevelCost = levelCosts[maxLevel] or 0
    end

    local currentProgress = math.max(currentExp - totalExpCurrentLevel, 0)
    local isMax = cappedLevel >= maxLevel
    if isMax then
        currentProgress = nextLevelCost
    end

    local uncappedSum = 0
    local uncappedLevel = 0
    while true do
        local cost = math.floor(baseExp * (growthRate ^ uncappedLevel))
        if currentExp < uncappedSum + cost then break end
        uncappedSum = uncappedSum + cost
        uncappedLevel = uncappedLevel + 1
    end

    local progressDisplay = ""
    if isMax then
        progressDisplay = string.format("MAX (%d EXP)", currentExp)
    else
        progressDisplay = string.format("%d / %d EXP", currentProgress, nextLevelCost)
    end

    local overallDisplay = string.format("%d / %d EXP", currentExp, totalRequiredForMax)

    return {
        level = cappedLevel,
        uncappedLevel = uncappedLevel,
        totalRequiredForMax = totalRequiredForMax,
        currentProgress = currentProgress,
        nextLevelCost = nextLevelCost,
        progressDisplay = progressDisplay,
        overallDisplay = overallDisplay,
        isMax = isMax
    }
end

local towerProgressionStaticCache = {}

function CombinedData:GetTowerExp(towerName)
    if not towerName or towerName == "" then return nil end

    local expCache = getCacheValue("TowerExp") or {}
    local currentExp = expCache[towerName] or 0

    local staticData = towerProgressionStaticCache[towerName]
    if not staticData then
        local baseExp = 50
        local growthRate = 1.09
        local maxLevel = 20
        local evolvedTo = nil

        if Content then
            local ok, towerFolder = pcall(Content, "Tower")
            if ok and towerFolder then
                local towerInst = towerFolder:FindFirstChild(towerName)
                local stats = towerInst and towerInst:FindFirstChild("Stats")
                if stats and stats:IsA("ModuleScript") then
                    local success, mod = pcall(require, stats)
                    if success and mod and mod.Properties and mod.Properties.Progression then
                        local prog = mod.Properties.Progression
                        baseExp = prog.BaseExp or baseExp
                        growthRate = prog.GrowthRate or growthRate
                        maxLevel = prog.MaxLevel or maxLevel
                        evolvedTo = mod.Properties.EvolvedTo
                    end
                end
            end
        end

        staticData = {
            baseExp = baseExp,
            growthRate = growthRate,
            maxLevel = maxLevel,
            evolvedTo = evolvedTo,
        }
        towerProgressionStaticCache[towerName] = staticData
    end

    local statsData = calculateExpStats(currentExp, staticData.baseExp, staticData.growthRate, staticData.maxLevel)

    return {
        Name = tostring(towerName),
        Exp = currentExp,
        Level = statsData.level,
        MaxLevel = staticData.maxLevel,
        MaxExp = statsData.totalRequiredForMax,
        CurrentProgress = statsData.currentProgress,
        RequiredForNext = statsData.nextLevelCost,
        ProgressDisplay = statsData.progressDisplay or tostring(currentExp),
        OverallDisplay = statsData.overallDisplay or tostring(currentExp),
        UncappedLevel = statsData.uncappedLevel,
        IsMaxLevel = statsData.isMax,
        EvolvedTo = staticData.evolvedTo
    }
end

function CombinedData:GetAllTowerExp()
    local result = {}
    for _, towerName in ipairs(self.ProgressionTowers) do
        local data = self:GetTowerExp(towerName)
        if data then
            table.insert(result, data)
        end
    end
    table.sort(result, function(a, b) return a.Name < b.Name end)
    return result
end

function CombinedData:FormatTowerExp(towerName)
    local data = self:GetTowerExp(towerName)
    if not data then return tostring(towerName) .. ": Not found" end

    local evoText = data.EvolvedTo and (" -> Evolves to " .. data.EvolvedTo) or ""
    if data.IsMaxLevel then
        local uncapped = (data.UncappedLevel > data.MaxLevel) and string.format(" [Uncapped Lvl %d]", data.UncappedLevel) or ""
        return string.format("%-18s: Level %2d/%2d [MAX] | Total: %6d / %4d EXP%s%s",
            data.Name, data.Level, data.MaxLevel, data.Exp, data.MaxExp, uncapped, evoText)
    else
        return string.format("%-18s: Level %2d/%2d (%s to Lvl %d) | Total: %6d / %4d EXP%s",
            data.Name, data.Level, data.MaxLevel, data.ProgressDisplay, data.Level + 1, data.Exp, data.MaxExp, evoText)
    end
end

-- ---------------------------------------------------------------------
-- Coins / Gems / Level / Player EXP (Values.* Cache & Multiplayer ValueBases)
-- ---------------------------------------------------------------------
local function getLobbyHud()
    local pgui = getPlayerGui(2)
    if not pgui then return nil end
    return pgui:FindFirstChild("ReactLobbyHud") or pgui:WaitForChild("ReactLobbyHud", 2)
end

function CombinedData:GetLevel(playerOrTarget)
    local player = resolveTargetPlayer(self, playerOrTarget)
    local isLocal = (player == nil or player == getLocalPlayer())

    if isLocal then
        -- 1. Direct Cache lookup (Values.Level)
        local lvl = getStat("Values.Level")
        if lvl ~= nil and tonumber(lvl) then
            return tonumber(lvl), tostring(lvl)
        end

        -- 2. Fallback: Lobby HUD TextLabel
        local hud = getLobbyHud()
        if hud then
            local curLvl = hud:FindFirstChild("currentLevel", true)
                or (hud:FindFirstChild("Frame", true) and hud.Frame:FindFirstChild("centerElements", true) and hud.Frame.centerElements:FindFirstChild("level", true) and hud.Frame.centerElements.level:FindFirstChild("content", true) and hud.Frame.centerElements.level.content:FindFirstChild("currentLevel", true))

            if curLvl and curLvl:IsA("TextLabel") then
                local txt = curLvl.Text
                return parseNumber(txt), txt
            end
        end

        -- 3. Fallback: LocalPlayer ValueBase
        local lp = getLocalPlayer()
        if lp then
            local val = lp:FindFirstChild("Level")
            if val and val:IsA("ValueBase") then
                local v = val.Value
                return tonumber(v) or parseNumber(v), tostring(v)
            end
        end
    end

    -- Check replicated Player ValueBase for any server player
    if player then
        local val = player:FindFirstChild("Level")
        if val and val:IsA("ValueBase") then
            local v = val.Value
            return tonumber(v) or parseNumber(v), tostring(v)
        end
    end

    -- Check PeerData fallback
    local peer = self:GetPeerData(playerOrTarget or player)
    if peer and (peer.level or peer.Level) then
        local lvl = tonumber(peer.level or peer.Level) or 0
        return lvl, tostring(lvl)
    end

    if playerOrTarget and not player then
        return 0, "player does not exist"
    end

    return 0, "0"
end

function CombinedData:GetCoins(playerOrTarget)
    local player = resolveTargetPlayer(self, playerOrTarget)
    local isLocal = (player == nil or player == getLocalPlayer())

    if isLocal then
        -- 1. Direct Cache lookup (Values.Coins)
        local coins = getStat("Values.Coins")
        if coins ~= nil and tonumber(coins) then
            return tonumber(coins), tostring(coins)
        end

        -- 2. Fallback: Lobby HUD TextLabel
        local hud = getLobbyHud()
        if hud then
            local path = {"Frame", "leftElements", "currencies", "coins", "content", "currency", "currencyValue"}
            local node = hud
            for _, child in ipairs(path) do
                node = node:FindFirstChild(child, true) or (node and node:FindFirstChild(child))
                if not node then break end
            end
            if node and node:IsA("TextLabel") then
                local txt = node.Text
                return parseNumber(txt), txt
            end
        end

        -- 3. Fallback: LocalPlayer ValueBase
        local lp = getLocalPlayer()
        if lp then
            local val = lp:FindFirstChild("Coins") or lp:FindFirstChild("Gold")
            if val and val:IsA("ValueBase") then
                local v = val.Value
                return tonumber(v) or parseNumber(v), tostring(v)
            end
        end
    end

    if player then
        local val = player:FindFirstChild("Coins") or player:FindFirstChild("Gold")
        if val and val:IsA("ValueBase") then
            local v = val.Value
            return tonumber(v) or parseNumber(v), tostring(v)
        end
    end

    local peer = self:GetPeerData(playerOrTarget or player)
    if peer and (peer.coins or peer.Coins) then
        local c = tonumber(peer.coins or peer.Coins) or 0
        return c, tostring(c)
    end

    if playerOrTarget and not player then
        return 0, "player does not exist"
    end

    return 0, "0"
end

function CombinedData:GetGems(playerOrTarget)
    local player = resolveTargetPlayer(self, playerOrTarget)
    local isLocal = (player == nil or player == getLocalPlayer())

    if isLocal then
        -- 1. Direct Cache lookup (Values.Gems)
        local gems = getStat("Values.Gems")
        if gems ~= nil and tonumber(gems) then
            return tonumber(gems), tostring(gems)
        end

        -- 2. Fallback: Lobby HUD TextLabel
        local hud = getLobbyHud()
        if hud then
            local path = {"Frame", "leftElements", "currencies", "gems", "content", "currency", "currencyValue"}
            local node = hud
            for _, child in ipairs(path) do
                node = node:FindFirstChild(child, true) or (node and node:FindFirstChild(child))
                if not node then break end
            end
            if node and node:IsA("TextLabel") then
                local txt = node.Text
                return parseNumber(txt), txt
            end
        end

        -- 3. Fallback: LocalPlayer ValueBase
        local lp = getLocalPlayer()
        if lp then
            local val = lp:FindFirstChild("Gems") or lp:FindFirstChild("Diamonds")
            if val and val:IsA("ValueBase") then
                local v = val.Value
                return tonumber(v) or parseNumber(v), tostring(v)
            end
        end
    end

    if player then
        local val = player:FindFirstChild("Gems") or player:FindFirstChild("Diamonds")
        if val and val:IsA("ValueBase") then
            local v = val.Value
            return tonumber(v) or parseNumber(v), tostring(v)
        end
    end

    local peer = self:GetPeerData(playerOrTarget or player)
    if peer and (peer.gems or peer.Gems) then
        local g = tonumber(peer.gems or peer.Gems) or 0
        return g, tostring(g)
    end

    if playerOrTarget and not player then
        return 0, "player does not exist"
    end

    return 0, "0"
end

--- Returns current player EXP, required EXP for next level, and formatted string
function CombinedData:GetPlayerExp(playerOrTarget)
    local player = resolveTargetPlayer(self, playerOrTarget)
    local isLocal = (player == nil or player == getLocalPlayer())

    local exp = 0
    if isLocal then
        exp = getStat("Values.Experience") or 0
        if exp == 0 and player then
            local val = player:FindFirstChild("Experience")
            if val and val:IsA("ValueBase") then
                exp = tonumber(val.Value) or 0
            end
        end
    elseif player then
        local val = player:FindFirstChild("Experience")
        if val and val:IsA("ValueBase") then
            exp = tonumber(val.Value) or 0
        end
    end

    local level = self:GetLevel(player) or 0
    local nextLevelExp = 0

    if Experience then
        local ok, nExp = pcall(Experience, level + 1)
        if ok and nExp then
            nextLevelExp = nExp
        end
    end

    return exp, nextLevelExp, string.format("%d / %d", exp, nextLevelExp)
end

--- Returns a table containing Level, EXP, NextLevelExp, Coins, Gems, and game stats for any player
function CombinedData:GetPlayerStats(playerOrTarget)
    local player = resolveTargetPlayer(self, playerOrTarget)
    local isLocal = (player == nil or player == getLocalPlayer())

    local level = self:GetLevel(player)
    local exp, nextLevelExp, expDisplay = self:GetPlayerExp(player)
    local coins = self:GetCoins(player)
    local gems = self:GetGems(player)

    local triumphs = 0
    local wins = 0
    local loses = 0
    local timescaleTickets = 0
    local reviveTickets = 0
    local spinTickets = 0

    if player then
        local function readInt(name)
            local v = player:FindFirstChild(name)
            return (v and v:IsA("ValueBase") and tonumber(v.Value)) or 0
        end
        triumphs = readInt("Triumphs")
        wins = readInt("Wins")
        loses = readInt("Loses")
        timescaleTickets = readInt("TimescaleTickets")
        reviveTickets = readInt("ReviveTickets")
        spinTickets = readInt("SpinTickets")
    end

    return {
        Player = player,
        Name = player and player.Name or "Unknown",
        DisplayName = player and player.DisplayName or "Unknown",
        UserId = player and player.UserId or 0,
        IsLocalPlayer = isLocal,
        Level = level,
        Exp = exp,
        NextLevelExp = nextLevelExp,
        ExpDisplay = expDisplay,
        Coins = coins,
        Gems = gems,
        Triumphs = triumphs,
        Wins = wins,
        Loses = loses,
        TimescaleTickets = timescaleTickets,
        ReviveTickets = reviveTickets,
        SpinTickets = spinTickets
    }
end

-- ---------------------------------------------------------------------
-- Skill‑tree extraction (Workspace Tiles & GameStateReplicator Multiplayer)
-- ---------------------------------------------------------------------
local skillTreeCacheFile = "ProjectOptimazation/CachedSkillTree.json"
local inMemorySkillTreeCache = {}
local lastSkillTreeDiskWrite = 0
local lastSkillTreeJson = ""

function CombinedData:GetSkillTree(playerOrTarget)
    local player = resolveTargetPlayer(self, playerOrTarget)
    local isLocal = (player == nil or player == getLocalPlayer())

    -- 1. If in a Game Match: Check GameStateReplicator Skills attribute for any player!
    local gsr = getGameStateReplicator()
    if gsr and player then
        local skillsRaw = gsr:GetAttribute("Skills")
        if type(skillsRaw) == "string" then
            local clean = skillsRaw:match("{.+}")
            if clean then
                local ok, decoded = pcall(function() return HttpService:JSONDecode(clean) end)
                if ok and type(decoded) == "table" then
                    local pSkills = decoded[tostring(player.UserId)] or decoded[player.UserId]
                    if pSkills and type(pSkills) == "table" then
                        local list = {}
                        local seen = {}
                        for id, def in pairs(SkillTreeData) do
                            local lvl = pSkills[def.Name] or pSkills[def.Name:gsub("%s+", "")] or 0
                            table.insert(list, {
                                Id = tostring(id),
                                Name = def.Name,
                                Level = lvl,
                                IsMaxed = (lvl >= 10),
                                LevelFormatted = tostring(lvl)
                            })
                            seen[def.Name] = true
                        end
                        for sName, lvl in pairs(pSkills) do
                            if not seen[sName] then
                                table.insert(list, {
                                    Id = sName,
                                    Name = sName,
                                    Level = lvl,
                                    IsMaxed = (lvl >= 10),
                                    LevelFormatted = tostring(lvl)
                                })
                            end
                        end
                        return list
                    end
                end
            end
        end
    end

    -- 2. If PeerData is available for another player
    if not isLocal then
        local peer = self:GetPeerData(playerOrTarget or player)
        if peer and (peer.skills or peer.SkillTree) then
            return peer.skills or peer.SkillTree
        end
        if playerOrTarget and not player then
            return {}, "player does not exist"
        end
    end

    -- 3. If LocalPlayer in Lobby: Workspace tiles scan
    local list = {}
    for i = 1, 17 do
        pcall(function()
            local tile = Workspace:FindFirstChild(tostring(i))
            if tile then
                local surfaceGui = tile:FindFirstChild("TileSurfaceGui")
                if surfaceGui then
                    local frame = surfaceGui:FindFirstChild("Frame")
                    if frame then
                        local nameLabel  = frame:FindFirstChild("SkillName")
                        local levelLabel = frame:FindFirstChild("SkillLevel")

                        local name = nameLabel and nameLabel:IsA("TextLabel") and nameLabel.Text or ("Skill #" .. i)
                        local lvlStr = levelLabel and levelLabel:IsA("TextLabel") and levelLabel.Text or "0"

                        local formattedLvl = lvlStr
                        local numericLvl = parseNumber(lvlStr)
                        local maxLvl = nil
                        local isMaxed = false

                        local curMatch, maxMatch = lvlStr:match("(%d+)%s*/%s*(%d+)")
                        if curMatch and maxMatch then
                            numericLvl = tonumber(curMatch) or numericLvl
                            maxLvl = tonumber(maxMatch)
                            if numericLvl >= maxLvl then
                                isMaxed = true
                            end
                        end

                        if string.upper(lvlStr):find("MAX") then
                            isMaxed = true
                            local numInFmt = string.upper(lvlStr):match("(%d+)")
                            if numInFmt then
                                maxLvl = tonumber(numInFmt) or maxLvl
                                if numericLvl == 0 or numericLvl < (maxLvl or 0) then
                                    numericLvl = maxLvl or numericLvl
                                end
                            end
                            formattedLvl = "MAX" .. (numericLvl > 0 and numericLvl or "")
                        end

                        table.insert(list, {
                            Id = tostring(i),
                            Name = name,
                            Level = numericLvl,
                            MaxLevel = maxLvl,
                            IsMaxed = isMaxed,
                            LevelFormatted = formattedLvl,
                        })
                    end
                end
            end
        end)
    end

    if #list > 0 then
        inMemorySkillTreeCache = list
        local now = os.time()
        if now - lastSkillTreeDiskWrite >= 60 then
            lastSkillTreeDiskWrite = now
            pcall(function()
                if writefile and HttpService then
                    local encoded = HttpService:JSONEncode(list)
                    if encoded ~= lastSkillTreeJson then
                        lastSkillTreeJson = encoded
                        pcall(writefile, "[ATF]/CachedSkillTree.json", encoded)
                        pcall(writefile, skillTreeCacheFile, encoded)
                    end
                end
            end)
        end
        return list
    end

    if #inMemorySkillTreeCache > 0 then
        return inMemorySkillTreeCache
    end

    local cacheCandidates = {
        "[ATF]/CachedSkillTree.json",
        "[ATF]\\CachedSkillTree.json",
        skillTreeCacheFile,
        "ProjectOptimazation\\CachedSkillTree.json",
    }
    pcall(function()
        if not (isfile and readfile and HttpService) then return end
        for _, path in ipairs(cacheCandidates) do
            local ok, exists = pcall(isfile, path)
            if ok and exists then
                local rOk, raw = pcall(readfile, path)
                if rOk and raw and raw ~= "" then
                    local dOk, decoded = pcall(function() return HttpService:JSONDecode(raw) end)
                    if dOk and type(decoded) == "table" and #decoded > 0 then
                        inMemorySkillTreeCache = decoded
                        break
                    end
                end
            end
        end
    end)

    return inMemorySkillTreeCache
end

-- ---------------------------------------------------------------------
-- Comprehensive Player Profile & Server Overview
-- ---------------------------------------------------------------------

--- Returns a consolidated profile of any player (Stats, Match, Equipped Towers, Skills)
function CombinedData:GetPlayerData(playerOrTarget)
    local player = resolveTargetPlayer(self, playerOrTarget)
    if not player then
        return nil, "player does not exist"
    end

    local stats = self:GetPlayerStats(player)
    local matchData = self:GetMatchData(player)
    local equippedTowers = self:GetEquippedTowers(player)
    local skillTree = self:GetSkillTree(player)
    local peer = self:GetPeerData(player)

    local skillsMap = {}
    if type(skillTree) == "table" then
        for _, s in ipairs(skillTree) do
            if s.Name and s.Level then
                skillsMap[s.Name] = s.Level
            end
        end
    end

    return {
        Player = player,
        Name = player.Name,
        DisplayName = player.DisplayName,
        UserId = player.UserId,
        IsLocalPlayer = (player == getLocalPlayer()),
        Level = stats.Level,
        Exp = stats.Exp,
        NextLevelExp = stats.NextLevelExp,
        ExpDisplay = stats.ExpDisplay,
        Coins = stats.Coins,
        Gems = stats.Gems,
        Triumphs = stats.Triumphs,
        Wins = stats.Wins,
        Loses = stats.Loses,
        TimescaleTickets = stats.TimescaleTickets,
        ReviveTickets = stats.ReviveTickets,
        SpinTickets = stats.SpinTickets,
        EquippedTowers = equippedTowers,
        Skills = skillsMap,
        MatchData = matchData,
        PeerData = peer
    }
end

--- Returns data for all players currently in the server
function CombinedData:GetAllPlayersData()
    local list = {}
    local byId = {}
    for _, p in ipairs(Players:GetPlayers()) do
        local data = self:GetPlayerData(p)
        if data then
            table.insert(list, data)
            byId[p.UserId] = data
            byId[string.lower(p.Name)] = data
        end
    end
    return list, byId
end

-- ---------------------------------------------------------------------
-- Requirements Validation API (Supports LocalPlayer & Multiplayer)
-- ---------------------------------------------------------------------
function CombinedData:CheckRequirements(requirements, playerOrTarget)
    local missing = {}
    local passed = true

    local player = resolveTargetPlayer(self, playerOrTarget)
    if playerOrTarget and not player then
        return false, { "Player does not exist in server" }
    end

    -- 1. Check Player Level
    if requirements.Level then
        local currentLevel = self:GetLevel(player)
        if currentLevel < requirements.Level then
            passed = false
            table.insert(missing, string.format("Level: required %d, current %d", requirements.Level, currentLevel))
        end
    end

    -- 2. Check Skill Tree (supports both .Skill and .SkillTree)
    local skillReqs = requirements.SkillTree or requirements.Skill
    if skillReqs and type(skillReqs) == "table" then
        local currentSkills = {}
        for _, skill in ipairs(self:GetSkillTree(player)) do
            currentSkills[skill.Name] = skill.Level
        end

        for skillName, requiredLvl in pairs(skillReqs) do
            local currentLvl = currentSkills[skillName] or 0
            if currentLvl < requiredLvl then
                passed = false
                table.insert(missing, string.format("Skill '%s': required level %d, current %d", skillName, requiredLvl, currentLvl))
            end
        end
    end

    -- 3. Check Coins
    if requirements.Coins then
        local currentCoins = self:GetCoins(player)
        if currentCoins < requirements.Coins then
            passed = false
            table.insert(missing, string.format("Coins: required %d, current %d", requirements.Coins, currentCoins))
        end
    end

    -- 4. Check Gems
    if requirements.Gems then
        local currentGems = self:GetGems(player)
        if currentGems < requirements.Gems then
            passed = false
            table.insert(missing, string.format("Gems: required %d, current %d", requirements.Gems, currentGems))
        end
    end

    -- 5. Check Towers Owned
    if requirements.Towers and type(requirements.Towers) == "table" then
        for _, towerName in ipairs(requirements.Towers) do
            if not self:IsTowerOwned(towerName, player) then
                passed = false
                table.insert(missing, string.format("Missing Tower: %s", towerName))
            end
        end
    end

    -- 6. Check Golden Towers Owned
    if requirements.Golden and type(requirements.Golden) == "table" then
        for _, towerName in ipairs(requirements.Golden) do
            if not self:IsGoldenOwned(towerName, player) then
                passed = false
                table.insert(missing, string.format("Golden %s - not owned", towerName))
            end
        end
    end

    -- 7. Check Tower EXP / Levels
    if requirements.TowerExp and type(requirements.TowerExp) == "table" then
        for towerName, req in pairs(requirements.TowerExp) do
            local data = self:GetTowerExp(towerName)
            local currentExp = data and data.Exp or 0
            local currentLvl = data and data.Level or 0

            if type(req) == "number" then
                if currentExp < req then
                    passed = false
                    table.insert(missing, string.format("%s EXP: required %d, current %d", towerName, req, currentExp))
                end
            elseif type(req) == "table" then
                if req.Level and currentLvl < req.Level then
                    passed = false
                    table.insert(missing, string.format("%s Level: required %d, current %d", towerName, req.Level, currentLvl))
                end
                if req.Exp and currentExp < req.Exp then
                    passed = false
                    table.insert(missing, string.format("%s EXP: required %d, current %d", towerName, req.Exp, currentExp))
                end
            end
        end
    end

    return passed, missing
end

-- ---------------------------------------------------------------------
-- Trials Data & Progression
-- ---------------------------------------------------------------------
local currentTrialCacheFile = "ProjectOptimazation/CachedCurrentTrial.json"
local nextTrialCacheFile = "ProjectOptimazation/CachedNextTrial.json"
local inMemoryCurrentTrial = nil
local inMemoryNextTrial = nil

function CombinedData:GetCurrentTrial()
    if MatchmakingTrialData then
        local ok, res = pcall(function()
            local currentTime = os.time()
            local rotation = MatchmakingTrialData.getCurrentRotation(currentTime)
            local details = MatchmakingTrialData.resolve(rotation)
            if setthreadidentity then pcall(setthreadidentity, 8) end
            local secondsLeft = math.max(0, (rotation.expiresAt or currentTime) - currentTime)
            local formattedTimer = MatchmakingTrialData.formatSecondsLeft(secondsLeft)
            if setthreadidentity then pcall(setthreadidentity, 8) end

            return {
                Name = rotation and rotation.trialName,
                ExpiresAt = rotation and rotation.expiresAt,
                TimeRemaining = formattedTimer,
                Map = details and details.mapName,
                Title = details and details.title,
                Subtitle = details and details.subtitle
            }
        end)
        if ok and res and res.Title then
            inMemoryCurrentTrial = res
            pcall(function()
                if writefile and HttpService then
                    writefile(currentTrialCacheFile, HttpService:JSONEncode(res))
                end
            end)
            return res
        end
    end

    if inMemoryCurrentTrial then return inMemoryCurrentTrial end

    pcall(function()
        if isfile and readfile and HttpService and isfile(currentTrialCacheFile) then
            local raw = readfile(currentTrialCacheFile)
            if raw and raw ~= "" then
                local decoded = HttpService:JSONDecode(raw)
                if type(decoded) == "table" and decoded.Title then
                    inMemoryCurrentTrial = decoded
                end
            end
        end
    end)

    return inMemoryCurrentTrial
end

function CombinedData:GetNextTrial()
    if MatchmakingTrialData then
        local ok, res = pcall(function()
            local currentTime = os.time()
            local currentRotation = MatchmakingTrialData.getCurrentRotation(currentTime)
            local timeOfNextTrial = (currentRotation and currentRotation.expiresAt or currentTime) + 1 
            local nextRotation = MatchmakingTrialData.getCurrentRotation(timeOfNextTrial)
            local nextDetails = MatchmakingTrialData.resolve(nextRotation)
            if setthreadidentity then pcall(setthreadidentity, 8) end
            local secondsLeft = math.max(0, (currentRotation and currentRotation.expiresAt or currentTime) - currentTime)
            local formattedTimer = MatchmakingTrialData.formatSecondsLeft(secondsLeft)
            if setthreadidentity then pcall(setthreadidentity, 8) end

            return {
                Name = nextRotation and nextRotation.trialName,
                Map = nextDetails and nextDetails.mapName,
                Title = nextDetails and nextDetails.title,
                TimeRemaining = formattedTimer,
                ExpiresAt = nextRotation and nextRotation.expiresAt
            }
        end)
        if ok and res and res.Title then
            inMemoryNextTrial = res
            pcall(function()
                if writefile and HttpService then
                    writefile(nextTrialCacheFile, HttpService:JSONEncode(res))
                end
            end)
            return res
        end
    end

    if inMemoryNextTrial then return inMemoryNextTrial end

    pcall(function()
        if isfile and readfile and HttpService and isfile(nextTrialCacheFile) then
            local raw = readfile(nextTrialCacheFile)
            if raw and raw ~= "" then
                local decoded = HttpService:JSONDecode(raw)
                if type(decoded) == "table" and decoded.Title then
                    inMemoryNextTrial = decoded
                end
            end
        end
    end)

    return inMemoryNextTrial
end

local StaticTrialDefinitions = {
    { Name = "Broke", Title = "Broke", Map = "Medieval Times" },
    { Name = "Committed", Title = "Committed", Map = "Retro Zone" },
    { Name = "ExplodingEnemies", Title = "Exploding Enemies", Map = "Wrecked Battlefield II" },
    { Name = "FlyingEnemies", Title = "Flying Enemies", Map = "Sacred Mountains" },
    { Name = "Fog", Title = "Fog", Map = "Winter Abyss" },
    { Name = "Glass", Title = "Glass", Map = "Stained Temple" },
    { Name = "HealthyEnemies", Title = "Healthy Enemies", Map = "Four Seasons" },
    { Name = "HiddenEnemies", Title = "Hidden Enemies", Map = "Forgetten Docks" },
    { Name = "Inflation", Title = "Inflation", Map = "Cyber City" },
    { Name = "Jailed", Title = "Jailed", Map = "Night Station" },
    { Name = "Limitation", Title = "Limitation", Map = "Coral Deep" },
    { Name = "Quarantine", Title = "Quarantine", Map = "Dusty Bridges" },
    { Name = "SpeedyEnemies", Title = "Speedy Enemies", Map = "Wrecked Battlefield" },
}

CombinedData.StaticTrialDefinitions = StaticTrialDefinitions

function CombinedData:GetTrialsStatus()
    if setthreadidentity then pcall(setthreadidentity, 8) end
    local allTrials = nil
    if MatchmakingTrialData and type(MatchmakingTrialData.getTrialNames) == "function" then
        pcall(function()
            allTrials = MatchmakingTrialData.getTrialNames()
        end)
    end
    if setthreadidentity then pcall(setthreadidentity, 8) end

    if not allTrials or #allTrials == 0 then
        allTrials = {}
        for _, t in ipairs(StaticTrialDefinitions) do
            table.insert(allTrials, t.Name)
        end
    end

    local ownedModifiers = getCacheValue("Inventory.Modifiers") or {}
    if setthreadidentity then pcall(setthreadidentity, 8) end

    local lookup = {}
    for _, mod in ipairs(ownedModifiers) do
        lookup[mod] = true
    end

    local won = {}
    local notWon = {}

    for _, trialName in ipairs(allTrials) do
        if lookup[trialName] then
            table.insert(won, trialName)
        else
            table.insert(notWon, trialName)
        end
    end

    return {
        Won = won,
        NotWon = notWon
    }
end

function CombinedData:GetAllTrialsList()
    if setthreadidentity then pcall(setthreadidentity, 8) end
    local ownedModifiers = getCacheValue("Inventory.Modifiers") or {}
    if setthreadidentity then pcall(setthreadidentity, 8) end

    local lookup = {}
    for _, mod in ipairs(ownedModifiers) do
        lookup[mod] = true
    end

    local list = {}
    local trialNames = nil
    if MatchmakingTrialData and type(MatchmakingTrialData.getTrialNames) == "function" then
        pcall(function()
            trialNames = MatchmakingTrialData.getTrialNames()
        end)
    end
    if setthreadidentity then pcall(setthreadidentity, 8) end

    if trialNames and #trialNames > 0 then
        for _, trialName in ipairs(trialNames) do
            local resolved = nil
            pcall(function()
                resolved = MatchmakingTrialData.resolve({ trialName = trialName })
            end)
            if setthreadidentity then pcall(setthreadidentity, 8) end
            local title = resolved and resolved.title or trialName
            local mapName = resolved and resolved.mapName or "Unknown"
            local isWon = lookup[trialName] == true
            table.insert(list, {
                Name = trialName,
                Title = title,
                Map = mapName,
                IsWon = isWon,
                Status = isWon and "YES" or "NO"
            })
        end
    else
        for _, t in ipairs(StaticTrialDefinitions) do
            local isWon = lookup[t.Name] == true
            table.insert(list, {
                Name = t.Name,
                Title = t.Title,
                Map = t.Map,
                IsWon = isWon,
                Status = isWon and "YES" or "NO"
            })
        end
    end

    return list
end

function CombinedData:IsTrialWon(trialName, playerOrTarget)
    if not trialName or trialName == "" then return false end

    local player = resolveTargetPlayer(self, playerOrTarget)
    local isLocal = (player == nil or player == getLocalPlayer())

    if not isLocal then
        return self:IsPeerTrialWon(playerOrTarget or player, trialName) or false
    end

    if setthreadidentity then pcall(setthreadidentity, 8) end
    local ownedModifiers = getCacheValue("Inventory.Modifiers") or {}
    if setthreadidentity then pcall(setthreadidentity, 8) end

    local target = string.lower(trialName):gsub("%s+", "")
    for _, mod in ipairs(ownedModifiers) do
        local modClean = string.lower(mod):gsub("%s+", "")
        if modClean == target then
            return true
        end
    end
    -- Also check display titles
    for _, t in ipairs(StaticTrialDefinitions) do
        if string.lower(t.Name):gsub("%s+", "") == target or string.lower(t.Title):gsub("%s+", "") == target then
            for _, mod in ipairs(ownedModifiers) do
                if string.lower(mod):gsub("%s+", "") == string.lower(t.Name):gsub("%s+", "") then
                    return true
                end
            end
        end
    end
    return false
end

function CombinedData:IsPeerTrialWon(identifier, trialName)
    if not trialName or trialName == "" then return false end
    local peer = self:GetPeerData(identifier)
    if not peer then return nil end

    local target = string.lower(string.gsub(tostring(trialName), "%s+", ""))
    local ownedMap = peer.ownedModifiers or peer.OwnedModifiers or {}
    local normOwned = peer.normOwnedModifiers or peer.NormOwnedModifiers or {}

    if ownedMap[trialName] or normOwned[target] then
        return true
    end

    for _, t in ipairs(StaticTrialDefinitions) do
        local nNorm = string.lower(string.gsub(tostring(t.Name), "%s+", ""))
        local titNorm = string.lower(string.gsub(tostring(t.Title), "%s+", ""))
        local mNorm = string.lower(string.gsub(tostring(t.Map), "%s+", ""))
        if target == nNorm or target == titNorm or target == mNorm then
            if ownedMap[t.Name] or ownedMap[t.Title] or ownedMap[t.Map]
               or normOwned[nNorm] or normOwned[titNorm] or normOwned[mNorm] then
                return true
            end
        end
    end

    return false
end

function CombinedData:GetPartyTrialStatus(peerIdentifier, trialName)
    local localWon = self:IsTrialWon(trialName)
    local peerWon = self:IsPeerTrialWon(peerIdentifier, trialName)
    return {
        trialName = trialName,
        localWon = localWon,
        peerWon = peerWon,
        bothWon = (localWon == true and peerWon == true),
        anyNeeds = (localWon == false or peerWon == false),
        peerSynced = (peerWon ~= nil)
    }
end

-- Export checkPlayer globally to executor environment if available
if getgenv then
    pcall(function()
        getgenv().checkPlayer = checkPlayer
    end)
end

return CombinedData
