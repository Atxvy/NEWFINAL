--!strict
--==============================================================================
-- Service Hub v9.8 [Integrated API Version]
-- Self-contained API build (API.lua embedded; no API file or API download required)
--
-- Optimized Tower Defense Simulator (TDS) Automation Suite (Mobile & Low-End Performance Boosted)
-- Auto Coins/Gems, Auto Trials, Smart Matchmaking & Fallback System
-- Featuring Trial Farm Mode (Farm Mode | Progression Mode) & Farm Only Mode
-- Integrated with CoreRevampNewAPI & Remote Strategy Cache
--==============================================================================
-- Prevent Execution Crashes on Teleport
if not game:IsLoaded() then
    local loadedConn
    local isLoaded = false
    loadedConn = game.Loaded:Connect(function()
        isLoaded = true
        if loadedConn then loadedConn:Disconnect() end
    end)
    local t0 = tick()
    while not game:IsLoaded() and not isLoaded and (tick() - t0 < 10) do
        task.wait(0.5)
    end
    if loadedConn then pcall(function() loadedConn:Disconnect() end) end
    task.wait(0.5)
else
    task.wait(0.1) -- Fast buffer when already loaded
end

-- Global Environment Initialization
local Globals = getgenv()
Globals.GatlingManagedByMain = true
Globals.DisableAPIGatling = true

-- Forward declarations used by the unload callback. Declaring these here keeps
-- the callback from accidentally resolving nil globals on re-execution.
local Players, UserInputService, ReplicatedStorage, HttpService, TeleportService, MarketplaceService
local LocalPlayer, PlayerGui
local activeStratThread: thread? = nil
local attemptBuyMissingTowersList: (({string}?) -> boolean)? = nil
local sendEvoPurchaseWebhook: ((string, string) -> ())? = nil
local AutoGatlingRunning = false
local AutoReloadRunning = false

--==============================================================================
--==============================================================================
-- Filesystem & Network Helpers (Cloud Loadstring Engine)
--==============================================================================
local function ensureFolder(folderPath: string)
    pcall(function()
        if isfolder and not isfolder(folderPath) and makefolder then
            makefolder(folderPath)
        elseif not isfolder and makefolder then
            makefolder(folderPath)
        end
    end)
end

local function safeHttpGet(url: string, retries: number?): string?
    local maxTries = retries or 3
    for attempt = 1, maxTries do
        local success, result = pcall(function()
            return game:HttpGet(url)
        end)
        if success and type(result) == "string" and #result > 0 then
            return result
        end
        if attempt < maxTries then
            task.wait(1.5)
        end
    end
    return nil
end
local function readLocalFile(fileName: string, fallbackPaths: {string}?): (string?, string?)
    if type(readfile) ~= "function" then
        return nil, nil
    end

    local candidates = { fileName }
    if type(fallbackPaths) == "table" then
        for _, path in ipairs(fallbackPaths) do
            if type(path) == "string" and path ~= "" and path ~= fileName then
                table.insert(candidates, path)
            end
        end
    end

    for _, path in ipairs(candidates) do
        local ok, content = pcall(function()
            if type(isfile) == "function" and not isfile(path) then
                return nil
            end
            return readfile(path)
        end)
        if ok and type(content) == "string" and #content > 0 then
            return content, path
        end
    end
    return nil, nil
end

--==============================================================================
-- Embedded TDS API
-- The API is intentionally in this file so execution never depends on API.lua,
-- a filesystem read, or a remote API download. The wrapper isolates API locals
-- from Service Hub locals and memoizes a successful initialization.
--==============================================================================
local function loadEmbeddedTDSAPI(): any
    local existing = Globals.TDS
    if type(existing) == "table" and type(existing.Loadout) == "function" then
        return existing
    end

    Globals.GatlingManagedByMain = true
    Globals.DisableAPIGatling = true

    local function initializeEmbeddedTDSAPI(): any
        local Globals = getgenv()
        local ModuleRunning = true
        local errorMessageConnection = nil
        local idleConnection = nil
        
        -- Patched shared.TDSTable check
        
        local Players = game:GetService("Players")
        local TeleportService = game:GetService("TeleportService")
        local GuiService = game:GetService("GuiService")
        local UserInputService = game:GetService("UserInputService")
        local LocalPlayer = Players.LocalPlayer
        if not LocalPlayer then
            local t0 = tick()
            while not Players.LocalPlayer and (tick() - t0 < 10) do
                task.wait(0.1)
            end
            LocalPlayer = Players.LocalPlayer
        end
        
        local function SmartTeleportToLobby()
            local lobbyId = 3260590327
            pcall(function()
                local platform = UserInputService:GetPlatform()
                local IsMobile = (platform == Enum.Platform.IOS or platform == Enum.Platform.Android)
                
                if not IsMobile and Globals.PrivateCode and Globals.PrivateCode ~= "" then
                    game:GetService("ExperienceService"):LaunchExperience({
                        placeId = lobbyId, 
                        linkCode = Globals.PrivateCode
                    })
                else
                    TeleportService:Teleport(lobbyId)
                end
            end)
        end
        
        local function Reconnect()
            local initialCode = GuiService:GetErrorCode()
            
            if initialCode and initialCode ~= Enum.ConnectionError.OK then
                task.wait(5)
                
                if GuiService:GetErrorCode() == initialCode then
                    pcall(function()
                        TeleportService:TeleportReconnect()
                    end)
                end
            end
        end
        
        local function AntiStuck()
            task.spawn(function()
                local secondsStuck = 0
        
                while ModuleRunning do 
                    task.wait(1)
                    
                    local attrLoading = LocalPlayer:GetAttribute("Loading") == true
                    local attrTeleporting = LocalPlayer:GetAttribute("Teleporting") == true
                    
                    local pg = LocalPlayer:FindFirstChild("PlayerGui")
                    local loadScreen = pg and pg:FindFirstChild("LoadingScreen")
                    local loadContent = loadScreen and loadScreen:FindFirstChild("content")
                    local isLoadVisible = loadContent and loadContent.Visible == true
                    
                    local countScreen = pg and pg:FindFirstChild("PlayerCountdown")
                    local countFrame = countScreen and countScreen:FindFirstChild("Frame")
                    local isCountVisible = countFrame and countFrame.Visible == true
        
                    if attrLoading or attrTeleporting or isLoadVisible or isCountVisible then
                        secondsStuck = secondsStuck + 1
                        if secondsStuck >= 60 then
                            pcall(SmartTeleportToLobby)
                            secondsStuck = 0 
                        end
                    else
                        secondsStuck = 0 
                    end
                end
            end)
        end
        
        AntiStuck()
        task.spawn(Reconnect)
        errorMessageConnection = GuiService.ErrorMessageChanged:Connect(Reconnect)
        
        if not game:IsLoaded() then game.Loaded:Wait() end
        
        local VirtualUser = game:GetService("VirtualUser")
        local RunService = game:GetService("RunService")
        local MarketplaceService = game:GetService("MarketplaceService")
        local ReplicatedStorage = game:GetService("ReplicatedStorage")
        local PathfindingService = game:GetService("PathfindingService")
        local HttpService = game:GetService("HttpService")
        local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
        local mouse = LocalPlayer:GetMouse()
        local RemoteFunc = ReplicatedStorage:WaitForChild("RemoteFunction")
        local RemoteEvent = ReplicatedStorage:WaitForChild("RemoteEvent")
        local FileName = "API.json"
        local Logger
        local StartBackToLobby
        local platform = UserInputService:GetPlatform()
        local IsMobile = (platform == Enum.Platform.IOS or platform == Enum.Platform.Android)
        
        idleConnection = LocalPlayer.Idled:Connect(function()
            if not ModuleRunning then return end
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new(0, 0))
        end)
        
        task.spawn(function()
            pcall(function()
                RemoteFunc:InvokeServer("Settings", "Update", "Show Nametags", false)
            end)
        end)
        
        local function IdentifyGameState()
            if game.PlaceId == 3260590327 then
                return "LOBBY"
            else
                return "GAME"
            end
        end
        
        local GameState = IdentifyGameState()
        
        local function StartAntiAfk()
            task.spawn(function()
                local LobbyTimer = 0
                while ModuleRunning and GameState == "LOBBY" do 
                    task.wait(1)
                    LobbyTimer = LobbyTimer + 1
                    if LobbyTimer >= 600 then
                        SmartTeleportToLobby()
                        break 
                    end
                end
            end)
        end
        
        StartAntiAfk()
        
        local SendRequest = request or http_request or httprequest
            or GetDevice and GetDevice().request
        
        if not SendRequest then 
            warn("failure: no http function") 
            return 
        end
        
        local BackToLobbyRunning = false
        local AutoSkipRunning = false
        local AntiLagRunning = false
        local AutoChainRunning = false
        local AutoDjRunning = false
        local AutoNecroRunning = false
        local AutoMercenaryBaseRunning = false
        local AutoMilitaryBaseRunning = false
        local AutoGatlingRunning = false
        local IsCurrentlyLoading = false
        local LastLoadTime = 0
        local IsEquippingLoadout = false
        
        local MaxPathDistance = 300
        local MilMarker = nil
        local MercMarker = nil
        
        local CurrentEquippedTowers = {"None"}
        
        local AutoMedicRunning = false
        
        local AllModifiers = {
            "HiddenEnemies", "Glass", "ExplodingEnemies", "Limitation", 
            "Committed", "HealthyEnemies", "Fog", "FlyingEnemies", 
            "Broke", "SpeedyEnemies", "Quarantine", "JailedTowers", "Inflation"
        }
        
        local DefaultSettings = {
            AutoSkip = false,
            AutoReady = false,
            AutoChain = false,
            AutoGatling = false,
            SupportCaravan = false,
            AutoDJ = false,
            AutoNecro = false,
            AutoRejoin = false,
            AutoRestart = false,
            AutoMercenary = false,
            AutoMilitary = false,
            AntiLag = false,
            Disable3DRendering = false,
            NoRecoil = false,
            AutoMedic = false,
        	AutoReset = false,
        	AutoBack = false,
        	PrivateCode = "",
        }
        
        local ItemNames = {
            ["17438486690"] = "Range Flag(s)",
            ["17438486138"] = "Damage Flag(s)",
            ["17438487774"] = "Cooldown Flag(s)",
            ["17429537022"] = "Blizzard(s)",
            ["17448596749"] = "Napalm Strike(s)",
            ["18493073533"] = "Spin Ticket(s)",
            ["17429548305"] = "Supply Drop(s)",
            ["18443277308"] = "Low Grade Consumable Crate(s)",
            ["136180382135048"] = "Santa Radio(s)",
            ["18443277106"] = "Mid Grade Consumable Crate(s)",
            ["18443277591"] = "High Grade Consumable Crate(s)",
            ["132155797622156"] = "Christmas Tree(s)",
            ["124065875200929"] = "Fruit Cake(s)",
            ["17429541513"] = "Barricade(s)",
            ["110415073436604"] = "Holy Hand Grenade(s)",
            ["17429533728"] = "Frag Grenade(s)",
            ["17437703262"] = "Molotov(s)",
            ["139414922355803"] = "Present Clusters(s)"
        }
        
        local executed_actions = {}
        
        TDS = {
            PlacedTowers = {},
            ActiveStrat = true,
            IsEquippingLoadout = false,
            LoadoutPending = false,
            MatchmakingMap = {
                ["PizzaParty"] = "halloween",
                ["Badlands"] = "badlands",
                ["PollutedWasteland"] = "polluted",
                ["DuckyEasy"] = "ducky2025",
                ["DuckyHard"] = "ducky2025"
            }
        }
        TDS["placed_towers"] = TDS.PlacedTowers
        TDS["active_strat"] = TDS.ActiveStrat
        TDS["matchmaking_map"] = TDS.MatchmakingMap
        
        local UpgradeHistory = {}
        
        shared.TDSTable = TDS
        shared["TDS_Table"] = TDS
        
        function TDS:ResetAllStates()
            table.clear(self.PlacedTowers)
            table.clear(UpgradeHistory)
            table.clear(executed_actions)
            if Logger and Logger.Clear then
                pcall(function()
                    Logger:Clear()
                end)
            end
        end
        
        function TDS:RunStrategy()
            if Globals.activeStrategyThread then
                pcall(task.cancel, Globals.activeStrategyThread)
                Globals.activeStrategyThread = nil
            end
        
            Globals.activeStrategyThread = task.spawn(function()
                Globals.tdsReplaying = true
                pcall(function()
                    loadstring(readfile("ADS_LastStrat.lua"))()
                end)
                Globals.tdsReplaying = false
                Globals.activeStrategyThread = nil
            end)
        end
        
        local function SaveSettings()
            local DataToSave = {}
            for key, _ in pairs(DefaultSettings) do
                DataToSave[key] = Globals[key]
            end
            writefile(FileName, HttpService:JSONEncode(DataToSave))
        end
        
        local function LoadSettings()
            local data = {}
            if isfile(FileName) then
                pcall(function()
                    data = HttpService:JSONDecode(readfile(FileName))
                end)
            end
        
            for key, DefaultVal in pairs(DefaultSettings) do
                if Globals[key] == nil then
                    if data[key] ~= nil then
                        Globals[key] = data[key]
                    else
                        Globals[key] = DefaultVal
                    end
                end
            end
            
            SaveSettings()
        end
        
        local function SetSetting(name, value)
            if DefaultSettings[name] ~= nil then
                Globals[name] = value
                SaveSettings()
            end
        end
        
        local function Apply3dRendering()
            if Globals.Disable3DRendering then
                game:GetService("RunService"):Set3dRenderingEnabled(false)
            else
                RunService:Set3dRenderingEnabled(true)
            end
            local PlayerGui = LocalPlayer:FindFirstChild("PlayerGui")
            local gui = PlayerGui and PlayerGui:FindFirstChild("ADS_BlackScreen")
            if Globals.Disable3DRendering then
                if PlayerGui and not gui then
                    gui = Instance.new("ScreenGui")
                    gui.Name = "ADS_BlackScreen"
                    gui.IgnoreGuiInset = true
                    gui.ResetOnSpawn = false
                    gui.DisplayOrder = -1000
                    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
                    gui.Parent = PlayerGui
                    local frame = Instance.new("Frame")
                    frame.Name = "Cover"
                    frame.BackgroundColor3 = Color3.new(0, 0, 0)
                    frame.BorderSizePixel = 0
                    frame.Size = UDim2.fromScale(1, 1)
                    frame.ZIndex = 0
                    frame.Parent = gui
                end
                gui.Enabled = true
            else
                if gui then
                    gui.Enabled = false
                end
            end
        end
        
        LoadSettings()
        Apply3dRendering()
        
        local function FindPath()
            local MapFolder = workspace:FindFirstChild("Map")
            if not MapFolder then return nil end
            local PathsFolder = MapFolder:FindFirstChild("Paths")
            if not PathsFolder then return nil end
            local PathFolder = PathsFolder:GetChildren()[1]
            if not PathFolder then return nil end
        
            local PathNodes = {}
            for _, node in ipairs(PathFolder:GetChildren()) do
                if node:IsA("BasePart") then
                    table.insert(PathNodes, node)
                end
            end
        
            table.sort(PathNodes, function(a, b)
                local NumA = tonumber(a.Name:match("%d+"))
                local NumB = tonumber(b.Name:match("%d+"))
                if NumA and NumB then return NumA < NumB end
                return a.Name < b.Name
            end)
        
            return PathNodes
        end
        
        local function TotalLength(PathNodes)
            local TotalLength = 0
            for i = 1, #PathNodes - 1 do
                TotalLength = TotalLength + (PathNodes[i + 1].Position - PathNodes[i].Position).Magnitude
            end
            return TotalLength
        end
        
        local MercenarySlider
        local MilitarySlider
        local MaxLenght
        
        local function CalcLength()
            local map = workspace:FindFirstChild("Map")
        
            if GameState == "GAME" and map then
                local PathNodes = FindPath()
        
                if PathNodes and #PathNodes > 0 then
                    MaxPathDistance = TotalLength(PathNodes)
        
                    if MercenarySlider then
                        MercenarySlider:SetMax(MaxPathDistance) 
                    end
        
                    if MilitarySlider then
                        MilitarySlider:SetMax(MaxPathDistance)
                    end
        
                    if MaxLenght then
                        MaxLenght = MaxPathDistance
                    end
                    return true
                end
            end
            return false
        end
        
        local function GetPointAtDistance(PathNodes, distance)
            if not PathNodes or #PathNodes < 2 then return nil end
        
            local CurrentDist = 0
            for i = 1, #PathNodes - 1 do
                local StartPos = PathNodes[i].Position
                local EndPos = PathNodes[i+1].Position
                local SegmentLen = (EndPos - StartPos).Magnitude
        
                if CurrentDist + SegmentLen >= distance then
                    local remaining = distance - CurrentDist
                    local direction = (EndPos - StartPos).Unit
                    return StartPos + (direction * remaining)
                end
                CurrentDist = CurrentDist + SegmentLen
            end
            return PathNodes[#PathNodes].Position
        end
        
        local function UpdatePathVisuals()
            if not Globals.PathVisuals then
                if MilMarker then 
                    MilMarker:Destroy() 
                    MilMarker = nil 
                end
                if MercMarker then 
                    MercMarker:Destroy() 
                    MercMarker = nil 
                end
                return
            end
        
            local PathNodes = FindPath()
            if not PathNodes then return end
        
            if not MilMarker then
                MilMarker = Instance.new("Part")
                MilMarker.Name = "MilVisual"
                MilMarker.Shape = Enum.PartType.Cylinder
                MilMarker.Size = Vector3.new(0.3, 3, 3)
                MilMarker.Color = Color3.fromRGB(0, 255, 0)
                MilMarker.Material = Enum.Material.Plastic
                MilMarker.Anchored = true
                MilMarker.CanCollide = false
                MilMarker.Orientation = Vector3.new(0, 0, 90)
                MilMarker.Parent = workspace
            end
        
            if not MercMarker then
                MercMarker = MilMarker:Clone()
                MercMarker.Name = "MercVisual"
                MercMarker.Color = Color3.fromRGB(255, 0, 0)
                MercMarker.Parent = workspace
            end
        
            local MilPos = GetPointAtDistance(PathNodes, Globals.MilitaryPath or 0)
            local MercPos = GetPointAtDistance(PathNodes, Globals.MercenaryPath or 0)
        
            if MilPos then
                MilMarker.Position = MilPos + Vector3.new(0, 0.2, 0)
                MilMarker.Transparency = 0.7
            end
            if MercPos then
                MercMarker.Position = MercPos + Vector3.new(0, 0.2, 0)
                MercMarker.Transparency = 0.7
            end
        end
        
        local function MissionsUIFix()
            task.spawn(function()
                while task.wait(1) do
                    pcall(function()
                        local MissionsScrollingFrame = game:GetService("Players").LocalPlayer.PlayerGui.ReactLobbyQuests.quests.missions.scrollingFrame
                        local MissionsListLayout = MissionsScrollingFrame.listLayout
                        local MissionFrame = MissionsScrollingFrame["1"]
                        if MissionFrame.AbsoluteSize.Y > 0 then
                            local UIScaleRatio = MissionFrame.AbsoluteSize.Y / MissionFrame.Size.Y.Offset
                            local CurrentCanvasSize = MissionsScrollingFrame.CanvasSize
                            local CanvasHeight = (MissionsListLayout.AbsoluteContentSize.Y / UIScaleRatio) + 25
                            MissionsScrollingFrame.CanvasSize = UDim2.new(CurrentCanvasSize.X.Scale, CurrentCanvasSize.X.Offset, CurrentCanvasSize.Y.Scale, CanvasHeight)
                        end
                    end)
                end
            end)
        end
        
        local function GetEquippedTowers()
            local towers = {}
            local StateReplicators = ReplicatedStorage:FindFirstChild("StateReplicators")
        
            if StateReplicators then
                for _, folder in ipairs(StateReplicators:GetChildren()) do
                    if folder.Name == "PlayerReplicator" and folder:GetAttribute("UserId") == LocalPlayer.UserId then
                        local equipped = folder:GetAttribute("EquippedTowers")
                        if type(equipped) == "string" then
                            local CleanedJson = equipped:match("%[.*%]") 
                            local success, TowerTable = pcall(function()
                                return HttpService:JSONDecode(CleanedJson)
                            end)
        
                            if success and type(TowerTable) == "table" then
                                for i = 1, 5 do
                                    if TowerTable[i] then
                                        table.insert(towers, TowerTable[i])
                                    end
                                end
                            end
                        end
                    end
                end
            end
            return #towers > 0 and towers or {"None"}
        end
        
        CurrentEquippedTowers = GetEquippedTowers()
        
        local function RunVoteSkip()
            while true do
                local success = pcall(function()
                    RemoteFunc:InvokeServer("Voting", "Skip")
                end)
                if success then break end
                task.wait(0.1)
            end
        end
        
        AutoReadyRunning = false
        
        local function StartAutoReady()
            if AutoReadyRunning or not Globals.AutoReady or GameState ~= "GAME" then return end
            AutoReadyRunning = true
        
            task.spawn(function()
                local voteReplicator = ReplicatedStorage:WaitForChild("StateReplicators"):WaitForChild("VoteReplicator")
                
                repeat 
                    task.wait(0.1) 
                    if not Globals.AutoReady then 
                        AutoReadyRunning = false
                        return 
                    end
                until voteReplicator:GetAttribute("Enabled") == true and voteReplicator:GetAttribute("Title") == "Ready?"
                
                if not Globals.AutoReady then
                    AutoReadyRunning = false
                    return
                end
        
                RunVoteSkip()
                
                repeat 
                    task.wait(0.1) 
                until voteReplicator:GetAttribute("Enabled") == false or not Globals.AutoReady
                
                AutoReadyRunning = false
            end)
        end
        
        local function CheckResOk(data)
            if data == true then return true end
            if type(data) == "table" and data.Success == true then return true end
        
            local success, IsModel = pcall(function()
                return data and data:IsA("Model")
            end)
        
            if success and IsModel then return true end
            if type(data) == "userdata" then return true end
        
            return false
        end
        
        local function RejoinMatch()
            local remote = game:GetService("ReplicatedStorage"):WaitForChild("RemoteFunction")
            local success = false
            local res
        
            if Globals.PrivateCode and Globals.PrivateCode ~= "" and not IsMobile then
                SmartTeleportToLobby()
                task.wait(9e9)
                return
            end
        
            repeat
                local StateFolder = ReplicatedStorage:FindFirstChild("State")
                local CurrentMode = StateFolder and StateFolder.Difficulty.Value
                if not CurrentMode or CurrentMode == "" then
                    CurrentMode = TDS.SavedDifficulty
                end
        
                if CurrentMode and CurrentMode ~= "" then
                    local ok, result = pcall(function()
                        local payload
                        local EventMode = StateFolder:FindFirstChild("Mode") and StateFolder.Mode.Value
        
                        if CurrentMode == "PizzaParty" then
                            payload = {
                                mode = "halloween",
                                count = 1
                            }
                        elseif tostring(EventMode or ""):lower() == "hardcore" then
                            payload = {
                                difficulty = CurrentMode,
                                mode = "hardcore",
                                count = 1
                            }
                        elseif CurrentMode == "PollutedWasteland" then
                            payload = {
                                mode = "polluted",
                                count = 1
                            }
                        elseif CurrentMode == "Badlands" then
                            payload = {
                                mode = "badlands",
                                count = 1
                            }
                        elseif EventMode == "DuckEvent" then
                            payload = {
                                difficulty = CurrentMode,
                                mode = "ducky2025",
                                count = 1
                            }
                        elseif CurrentMode == "Trial" then
                            SmartTeleportToLobby()
                            return true
                        else
                            payload = {
                                difficulty = CurrentMode,
                                mode = "survival",
                                count = 1
                            }
                        end
        
                        return remote:InvokeServer("Multiplayer", "v2:start", payload)
                    end)
        
                    if ok and CheckResOk(result) then
                        success = true
                        res = result
                    else
                        task.wait(0.5) 
                    end
                else
                    task.wait(1)
                end
            until success
        
            return res
        end
        
        local function MatchReadyUp()
            local stateReplicators = ReplicatedStorage:WaitForChild("StateReplicators")
            local voteReplicator = stateReplicators:WaitForChild("VoteReplicator")
            local gameStateReplicator = stateReplicators:WaitForChild("GameStateReplicator")
        
            if gameStateReplicator:GetAttribute("GameStarted") == true then
                return
            end
            
            local voteTitle = voteReplicator:GetAttribute("Title")
            if voteTitle == "Ready?" and voteReplicator:GetAttribute("Enabled") == true then
                RunVoteSkip()
                return
            end
        
            local yieldSignal = Instance.new("BindableEvent")
            local voteConnection
            local gameStartedConnection
        
            voteConnection = voteReplicator.AttributeChanged:Connect(function(attributeName)
                if attributeName == "Enabled" and voteReplicator:GetAttribute("Enabled") == true then
                    if voteReplicator:GetAttribute("Title") == "Ready?" then
                        RunVoteSkip()
                        yieldSignal:Fire()
                    end
                elseif attributeName == "Title" and voteReplicator:GetAttribute("Title") ~= "Ready?" then
                    yieldSignal:Fire()
                elseif attributeName == "VoteCount" or attributeName == "MaxVotes" then
                    local currentVotes = voteReplicator:GetAttribute("VoteCount")
                    local maxVotesRequired = voteReplicator:GetAttribute("MaxVotes")
                    if currentVotes and maxVotesRequired and maxVotesRequired > 0 and currentVotes >= maxVotesRequired then
                        yieldSignal:Fire()
                    end
                end
            end)
        
            gameStartedConnection = gameStateReplicator:GetAttributeChangedSignal("GameStarted"):Connect(function()
                if gameStateReplicator:GetAttribute("GameStarted") == true then
                    yieldSignal:Fire()
                end
            end)
        
            yieldSignal.Event:Wait()
        
            if voteConnection then
                voteConnection:Disconnect()
            end
            if gameStartedConnection then
                gameStartedConnection:Disconnect()
            end
            yieldSignal:Destroy()
        end
        
        local function CastMapVote(MapId, PosVec)
            local TargetMap = MapId or "Simplicity"
            local TargetPos = PosVec or Vector3.new(0,0,0)
            RemoteEvent:FireServer("LobbyVoting", "Vote", TargetMap, TargetPos)
        end
        
        local function LobbyReadyUp()
            pcall(function()
                RemoteEvent:FireServer("LobbyVoting", "Ready")
            end)
        end
        
        local function SelectMapOverride(MapId, ...)
            local args = {...}
        
            if args[#args] == "vip" then
                RemoteFunc:InvokeServer("LobbyVoting", "Override", MapId)
            end
        
            task.wait(3)
            CastMapVote(MapId, Vector3.new(12.59, 10.64, 52.01))
            task.wait(1)
            LobbyReadyUp()
        end
        
        local function CastModifierVote(ModsTable)
            local BulkModifiers = ReplicatedStorage:WaitForChild("Network"):WaitForChild("Modifiers"):WaitForChild("RF:BulkVoteModifiers")
            local ModRep = ReplicatedStorage:WaitForChild("StateReplicators"):FindFirstChild("ModifierReplicator")
        
            local Available = {}
            if ModRep then
                local raw = ModRep:GetAttribute("Available")
                if type(raw) == "string" then
                    local clean = raw:match("{.+}")
                    if clean then
                        pcall(function()
                            Available = HttpService:JSONDecode(clean)
                        end)
                    end
                end
            end
        
            local SelectedMods = {}
            local missingMods = {}
        
            if ModsTable then
                for k, v in pairs(ModsTable) do
                    local modName = type(k) == "string" and k or v
                    
                    if type(modName) == "string" then
                        if Available[modName] == true then
                            SelectedMods[modName] = true
                        else
                            table.insert(missingMods, modName)
                        end
                    end
                end
            end
        
            if next(SelectedMods) then
                pcall(function()
                    BulkModifiers:InvokeServer(SelectedMods)
                end)
            end
        end
        
        local function IsMapAvailable(name)
            for _, g in ipairs(workspace:GetDescendants()) do
                if g:IsA("SurfaceGui") and g.Name == "MapDisplay" then
                    local t = g:FindFirstChild("Title")
                    if t and t.Text == name then return true end
                end
            end
        
            local hasVoted = false
        
            repeat
                local IntermissionFrame = PlayerGui:WaitForChild("ReactGameIntermission"):WaitForChild("Frame")
                local VetoValue = IntermissionFrame.buttons.veto.value
                local VetoText = VetoValue.Text
                
                if VetoText ~= "" then
                    if not VetoText:find("Veto") then
                        return false 
                    end
        
                    local currentStr, totalStr = VetoText:match("(%d+)/(%d+)")
                    local current, total = tonumber(currentStr), tonumber(totalStr)
        
                    if not hasVoted and total and total > 0 and current == 0 then
                        RemoteEvent:FireServer("LobbyVoting", "Veto")
                        hasVoted = true
                    end
                end
        
                local found = false
                for _, g in ipairs(workspace:GetDescendants()) do
                    if g:IsA("SurfaceGui") and g.Name == "MapDisplay" then
                        local t = g:FindFirstChild("Title")
                        if t and t.Text == name then
                            found = true
                            break
                        end
                    end
                end
        
                task.wait(1)
        
                local TotalPlayer = #Players:GetChildren()
                local isFull = VetoText == "Veto ("..TotalPlayer.."/"..TotalPlayer..")"
        
            until found or isFull
        
            for _, g in ipairs(workspace:GetDescendants()) do
                if g:IsA("SurfaceGui") and g.Name == "MapDisplay" then
                    local t = g:FindFirstChild("Title")
                    if t and t.Text == name then return true end
                end
            end
        
            return false
        end
        
        local function TriggerRestart()
            local UiRoot = PlayerGui:WaitForChild("ReactGameNewRewards")
            local FoundSection = false
        
            repeat
                task.wait(0.3)
                local f = UiRoot:FindFirstChild("Frame")
                local g = f and f:FindFirstChild("gameOver")
                local s = g and g:FindFirstChild("RewardsScreen")
                if s and s:FindFirstChild("RewardsSection") then
                    FoundSection = true
                end
            until FoundSection
        
            task.wait(3)
            RunVoteSkip()
        end
        
        local function GetCurrentWave()
            local label
        
            repeat
                task.wait(0.5)
                label = PlayerGui:FindFirstChild("ReactGameTopGameDisplay", true) 
                    and PlayerGui.ReactGameTopGameDisplay.Frame.wave.container:FindFirstChild("value")
            until label ~= nil
        
            local text = label.Text
            local WaveNum = text:match("(%d+)")
        
            return tonumber(WaveNum) or 0
        end
        
        local function DoPlaceTower(TName, TPos)
            local retries = 0
            while true do
                local ok, res = pcall(function()
                    return RemoteFunc:InvokeServer("Troops", "Place", {
                        Rotation = CFrame.new(),
                        Position = TPos
                    }, TName)
                end)
         
                if ok and CheckResOk(res) then return true end
                retries = retries + 1
                if retries == 10 or (retries > 10 and retries % 20 == 0) then
                    warn(string.format("[TDS:Place] Waiting to place '%s' (attempt %d)...", tostring(TName), retries))
                end
                task.wait(0.25)
            end
        end
        
        local function DoUpgradeTower(TObj, PathId)
            if not TObj then
                warn("[TDS:Upgrade] Error: Attempted to upgrade a nil tower object!")
                return false
            end
            local retries = 0
            while true do
                local ok, res = pcall(function()
                    return RemoteFunc:InvokeServer("Troops", "Upgrade", "Set", {
                        Troop = TObj,
                        Path = PathId
                    })
                end)
                if ok and CheckResOk(res) then return true end
                retries = retries + 1
                if retries == 10 or (retries > 10 and retries % 20 == 0) then
                    warn(string.format("[TDS:Upgrade] Waiting to upgrade tower (attempt %d)...", retries))
                end
                task.wait(0.25)
            end
        end
        
        local function DoSellTower(TObj)
            while true do
                local ok, res = pcall(function()
                    return RemoteFunc:InvokeServer("Troops", "Sell", { Troop = TObj })
                end)
                if ok and CheckResOk(res) then return true end
                task.wait(0.25)
            end
        end
        
        local function DoSetOption(TObj, OptName, OptVal, ReqWave)
            if ReqWave then
                repeat task.wait(0.3) until GetCurrentWave() >= ReqWave
            end
        
            while true do
                local ok, res = pcall(function()
                    return RemoteFunc:InvokeServer("Troops", "Option", "Set", {
                        Troop = TObj,
                        Name = OptName,
                        Value = OptVal
                    })
                end)
                if ok and CheckResOk(res) then return true end
                task.wait(0.25)
            end
        end
        
        local function DoActivateAbility(TObj, AbName, AbData, IsLooping)
            if type(AbData) == "boolean" then
                IsLooping = AbData
                AbData = nil
            end
        
            AbData = type(AbData) == "table" and AbData or nil
        
            local positions
            if AbData and type(AbData.towerPosition) == "table" then
                positions = AbData.towerPosition
            end
        
            local CloneIdx = AbData and AbData.towerToClone
            local TargetIdx = AbData and AbData.towerTarget
        
            local function attempt()
                while true do
                    local ok, res = pcall(function()
                        local data
        
                        if AbData then
                            data = table.clone(AbData)
        
                            if positions and #positions > 0 then
                                data.towerPosition = positions[math.random(#positions)]
                            end
        
                            if type(CloneIdx) == "number" then
                                data.towerToClone = TDS.PlacedTowers[CloneIdx]
                            end
        
                            if type(TargetIdx) == "number" then
                                data.towerTarget = TDS.PlacedTowers[TargetIdx]
                            end
                        end
        
                        return RemoteFunc:InvokeServer(
                            "Troops",
                            "Abilities",
                            "Activate",
                            {
                                Troop = TObj,
                                Name = AbName,
                                Data = data
                            }
                        )
                    end)
        
                    if ok and CheckResOk(res) then
                        return true
                    end
        
                    task.wait(0.25)
                end
            end
        
            if IsLooping then
                local active = true
                task.spawn(function()
                    while active do
                        attempt()
                        task.wait(1)
                    end
                end)
                return function() active = false end
            end
        
            return attempt()
        end
        
        function TDS:Mode(difficulty, code)
            self.SavedDifficulty = difficulty
            local targetCode = ""
        
            if IsMobile then
                if (code and code ~= "") or (Globals.PrivateCode and Globals.PrivateCode ~= "") then
                end
            else
                if code and code ~= "" then
                    targetCode = code
                elseif Globals.PrivateCode then
                    targetCode = Globals.PrivateCode
                end
            end
        
            self.PrivateCode = tostring(targetCode)
        
            if GameState ~= "LOBBY" then 
                return false 
            end
        
            if targetCode ~= "" and not MarketplaceService:UserOwnsGamePassAsync(LocalPlayer.UserId, 10518590) then
                local ServerType = game:GetService('RobloxReplicatedStorage').GetServerType:InvokeServer()
                
                if ServerType ~= "VIPServer" then
                    game:GetService("ExperienceService"):LaunchExperience({
                        placeId = game.PlaceId, 
                        linkCode = tostring(targetCode)
                    })
                    return true
                end
            end
        
            if difficulty == "Trial" then
                local Elevators = workspace:WaitForChild("TrialElevators")
                local Network = ReplicatedStorage:WaitForChild("Network")
                
                if Elevators and Network then
                    local targetElevator = nil
                    
                    repeat
                        for _, v in pairs(Elevators:GetChildren()) do
                            if v.Name:match("Elevator") then
                                targetElevator = v
                                break
                            end
                        end
                        if not targetElevator then task.wait(0.5) end
                    until targetElevator
        
                    task.spawn(function()
                        local ElevatorsNet = Network:WaitForChild("Elevators")
                        local EnterRemote = ElevatorsNet:WaitForChild("RF:Enter")
                        local SetSizeRemote = ElevatorsNet:WaitForChild("RF:SetSize")
                        local SetReadyRemote = ElevatorsNet:WaitForChild("RF:SetReady")
                        
                        pcall(function() EnterRemote:InvokeServer(targetElevator) end)
                        pcall(function() SetSizeRemote:InvokeServer(1) end)
                        pcall(function() SetReadyRemote:InvokeServer(true) end)
                    end)
                    
                    return true
                end
            end
        
            local LobbyHud = PlayerGui:WaitForChild("ReactLobbyHud", 30)
            local frame = LobbyHud and LobbyHud:WaitForChild("Frame", 30)
            local MatchMaking = frame and frame:WaitForChild("matchmaking", 30)
        
            if MatchMaking then
                local remote = game:GetService("ReplicatedStorage"):WaitForChild("RemoteFunction")
                local success = false
                repeat
                    local ok, result = pcall(function()
                        local mode = TDS.MatchmakingMap[difficulty]
                        local payload
        
                        if difficulty == "Hardcore" then
                            payload = {
                                mode = "hardcore",
                                difficulty = "Easy",
                                count = 1
                            }
                        elseif difficulty == "Voidcore" then
                            payload = {
                                mode = "hardcore",
                                difficulty = "Hard",
                                count = 1
                            }
                        elseif mode then
                            payload = {
                                mode = mode,
                                count = 1
                            }
                            if difficulty:match("Ducky") then
                                payload.difficulty = difficulty:gsub("Ducky", "")
                            end
                        else
                            payload = {
                                difficulty = difficulty,
                                mode = "survival",
                                count = 1
                            }
                        end
        
                        return remote:InvokeServer("Multiplayer", "v2:start", payload)
                    end)
        
                    if ok and CheckResOk(result) then
                        success = true
                    else
                        task.wait(0.5) 
                    end
                until success
            end
        
            return true
        end
        
        function TDS:Loadout(...)
            while IsCurrentlyLoading do
                task.wait(0.2)
            end
        
            if self.MultiplayerLoadoutLocked then
                warn("[TDS:Loadout] Multiplayer loadout already applied; skipping duplicate Loadout call.")
                return true
            end
        
            IsCurrentlyLoading = true
            IsEquippingLoadout = true
            self.IsEquippingLoadout = true
        
            local rawArgs = {...}
            local towers = {}
            if #rawArgs == 1 and type(rawArgs[1]) == "table" then
                towers = rawArgs[1]
            else
                towers = rawArgs
            end
            local remote = game:GetService("ReplicatedStorage"):WaitForChild("RemoteEvent")
            local StateReplicators = ReplicatedStorage:FindFirstChild("StateReplicators")
        
            local success = pcall(function()
                local CurrentlyEquipped = {}
        
                if StateReplicators then
                    for _, folder in ipairs(StateReplicators:GetChildren()) do
                        if folder.Name == "PlayerReplicator" and folder:GetAttribute("UserId") == LocalPlayer.UserId then
                            local EquippedAttr = folder:GetAttribute("EquippedTowers")
                            if type(EquippedAttr) == "string" then
                                local CleanedJson = EquippedAttr:match("%[.*%]") 
                                local DecodeSuccess, decoded = pcall(function()
                                    return HttpService:JSONDecode(CleanedJson)
                                end)
        
                                if DecodeSuccess and type(decoded) == "table" then
                                    CurrentlyEquipped = decoded
                                end
                            end
                        end
                    end
                end
        
                -- Fallback for Lobby where StateReplicators might not exist
                if #CurrentlyEquipped == 0 then
                    pcall(function()
                        local InvCtrl = require(ReplicatedStorage.Client.Interfaces.LegacyInterface.Controllers.InventoryController)
                        if InvCtrl and type(InvCtrl.getItems) == "function" then
                            local items = InvCtrl:getItems()
                            if items then
                                for _, item in pairs(items) do
                                    if type(item) == "table" and item.type == "tower" and item.equipped == true then
                                        table.insert(CurrentlyEquipped, item.name)
                                    end
                                end
                            end
                        end
                    end)
                end
        
                if #CurrentlyEquipped == 0 then
                    pcall(function()
                        local Cache = require(ReplicatedStorage.Client.Modules.Cache)
                        local atom = Cache and Cache("Inventory.Troops")
                        local troops = atom and atom:GetValue()
                        if type(troops) == "table" then
                            for tName, tData in pairs(troops) do
                                if type(tData) == "table" and tData.Equipped == true then
                                    table.insert(CurrentlyEquipped, tName)
                                end
                            end
                        end
                    end)
                end
        
                local function getExactTowerName(tName)
                    if not tName or tName == "" or tName == "None" then return tName end
                    local lowerT = string.lower(tostring(tName))
                    pcall(function()
                        local Cache = require(ReplicatedStorage.Client.Modules.Cache)
                        local atom = Cache and Cache("Inventory.Troops")
                        local troops = atom and atom:GetValue()
                        if type(troops) == "table" then
                            for realName, _ in pairs(troops) do
                                if string.lower(tostring(realName)) == lowerT then
                                    tName = realName
                                    return
                                end
                            end
                        end
                    end)
                    pcall(function()
                        local InvCtrl = require(ReplicatedStorage.Client.Interfaces.LegacyInterface.Controllers.InventoryController)
                        if InvCtrl and type(InvCtrl.getItems) == "function" then
                            local items = InvCtrl:getItems()
                            if items then
                                for _, item in pairs(items) do
                                    if type(item) == "table" and item.type == "tower" and string.lower(tostring(item.name)) == lowerT then
                                        tName = item.name
                                        return
                                    end
                                end
                            end
                        end
                    end)
                    return tName
                end
        
                local targetLookup = {}
                for _, t in ipairs(towers) do
                    if t and t ~= "" and t ~= "None" then
                        targetLookup[string.lower(tostring(t))] = true
                    end
                end
        
                local equippedLookup = {}
                for _, cur in ipairs(CurrentlyEquipped) do
                    if cur and cur ~= "" and cur ~= "None" then
                        equippedLookup[string.lower(tostring(cur))] = true
                    end
                end
        
                -- Unequip towers that are not needed
                for _, CurrentTower in ipairs(CurrentlyEquipped) do
                    if CurrentTower ~= "None" and not targetLookup[string.lower(tostring(CurrentTower))] then
                        local UnequipDone = false
                        local tries = 0
                        repeat
                            tries = tries + 1
                            local ok = pcall(function()
                                remote:FireServer("Inventory", "Unequip", "Tower", CurrentTower)
                                task.wait(0.25)
                            end)
                            if ok then UnequipDone = true else task.wait(0.2) end
                        until UnequipDone or tries >= 3
                    end
                end
        
                task.wait(0.3)
        
                -- Equip target towers
                for _, rawTowerName in ipairs(towers) do
                    if rawTowerName and rawTowerName ~= "" and rawTowerName ~= "None" and not equippedLookup[string.lower(tostring(rawTowerName))] then
                        local TowerName = getExactTowerName(rawTowerName)
                        local EquipSuccess = false
                        local tries = 0
                        repeat
                            tries = tries + 1
                            local ok = pcall(function()
                                remote:FireServer("Inventory", "Equip", "Tower", TowerName)
                                task.wait(0.25)
                            end)
                            if ok then EquipSuccess = true else task.wait(0.2) end
                        until EquipSuccess or tries >= 3
                    end
                end
        
                task.wait(0.3)
            end)
        
            IsCurrentlyLoading = false
            IsEquippingLoadout = false
            self.IsEquippingLoadout = false
            self.LoadoutPending = false
            LastLoadTime = os.clock()
        
            return success
        end
        
        function TDS:VoteSkip(StartWave, EndWave)
            task.spawn(function()
                local CurrentWave = GetCurrentWave()
                
                self.LastVoteSkipTarget = self.LastVoteSkipTarget or 0
                
                if not StartWave then
                    if self.LastVoteSkipTarget < CurrentWave then
                        self.LastVoteSkipTarget = CurrentWave
                    else
                        self.LastVoteSkipTarget = self.LastVoteSkipTarget + 1
                    end
                    StartWave = self.LastVoteSkipTarget
                    EndWave = StartWave
                else
                    EndWave = EndWave or StartWave
                    self.LastVoteSkipTarget = EndWave
                end
        
                for wave = StartWave, EndWave do
                    while GetCurrentWave() < wave do
                        task.wait(1)
                    end
        
                    local TargetNextWave = wave + 1
                    
                    while GetCurrentWave() < TargetNextWave do
                        local VoteUi = PlayerGui:FindFirstChild("ReactOverridesVote")
                        local VoteButton = VoteUi 
                            and VoteUi:FindFirstChild("Frame") 
                            and VoteUi.Frame:FindFirstChild("votes") 
                            and VoteUi.Frame.votes:FindFirstChild("vote", true)
        
                        if VoteButton and VoteButton.Position == UDim2.new(0.5, 0, 0.5, 0) then
                            pcall(function()
                                RemoteFunc:InvokeServer("Voting", "Skip")
                            end)
                        end
                        
                        task.wait(0.5)
                    end
                end
            end)
        end
        
        function TDS:GameInfo(name, list)
            if game.PlaceId == 3260590327 then return false end
        
            local VoteGui = PlayerGui:WaitForChild("ReactGameIntermission", 30)
            if not (VoteGui and VoteGui.Enabled and VoteGui:WaitForChild("Frame", 5)) then return end
        
            local modifiers = (list and next(list)) and list or Globals.Modifiers
        
            CastModifierVote(modifiers)
        
            local stateReplicators = game:GetService("ReplicatedStorage"):WaitForChild("StateReplicators", 5)
            local gameStateReplicator = stateReplicators and stateReplicators:FindFirstChild("GameStateReplicator")
        
            if MarketplaceService:UserOwnsGamePassAsync(LocalPlayer.UserId, 10518590) or (gameStateReplicator and gameStateReplicator:GetAttribute("IsPrivateServer") == true) then
                SelectMapOverride(name, "vip")
                repeat task.wait(1) until PlayerGui:FindFirstChild("ReactUniversalHotbar")
                return true 
            elseif IsMapAvailable(name) then
                SelectMapOverride(name)
                repeat task.wait(1) until PlayerGui:FindFirstChild("ReactUniversalHotbar")
                return true
            else
                RejoinMatch()
                repeat task.wait(9999) until false
            end
        end
        
        function TDS:StartGame()
            LobbyReadyUp()
        end
        
        function TDS:Ready()
            if game.PlaceId == 3260590327 then
                return false 
            end
            MatchReadyUp()
            return true
        end
        
        function TDS:GetWave()
            return GetCurrentWave()
        end
        
        function TDS:WaitForWave(targetWave)
            if game.PlaceId == 3260590327 then return false end
            while self:GetWave() < targetWave do
                task.wait(0.5)
            end
            return true
        end
        
        function TDS:RestartGame()
            TriggerRestart()
        end
        
        function TDS:Place(TName, px, py, pz, ...)
            local args = {...}
            local stack = false
         
            if args[#args] == "stack" or args[#args] == true then
                py = py+25
            end
            if game.PlaceId == 3260590327 then
                return false 
            end
         
            local towersFolder = workspace:FindFirstChild("Towers") or workspace:WaitForChild("Towers", 5)
            local existing = {}
            if towersFolder then
                for _, child in ipairs(towersFolder:GetChildren()) do
                    for _, SubChild in ipairs(child:GetChildren()) do
                        if SubChild.Name == "Owner" and SubChild.Value == LocalPlayer.UserId then
                            existing[child] = true
                            break
                        end
                    end
                end
            end
         
            DoPlaceTower(TName, Vector3.new(px, py, pz))
         
            local NewT
            local waitStart = os.time()
            repeat
                local curTowers = workspace:FindFirstChild("Towers")
                if curTowers then
                    for _, child in ipairs(curTowers:GetChildren()) do
                        if not existing[child] then
                            for _, SubChild in ipairs(child:GetChildren()) do
                                if SubChild.Name == "Owner" and SubChild.Value == LocalPlayer.UserId then
                                    NewT = child
                                    break
                                end
                            end
                        end
                        if NewT then break end
                    end
                end
                if not NewT then task.wait(0.05) end
            until NewT or (os.time() - waitStart > 10)
         
            if NewT then
                table.insert(self.PlacedTowers, NewT)
            end
            return #self.PlacedTowers
        end
        
        function TDS:Upgrade(idx, PId)
            local t = self.PlacedTowers[idx]
            if t then
                DoUpgradeTower(t, PId or 1)
                UpgradeHistory[idx] = (UpgradeHistory[idx] or 0) + 1
            end
        end
        
        function TDS:SetTarget(idx, TargetType, ReqWave)
            if ReqWave then
                repeat task.wait(0.5) until GetCurrentWave() >= ReqWave
            end
        
            local t = self.PlacedTowers[idx]
            if not t then return end
        
            pcall(function()
                RemoteFunc:InvokeServer("Troops", "Target", "Set", {
                    Troop = t,
                    Target = TargetType
                })
            end)
        end
        
        function TDS:Sell(idx, ReqWave)
            if ReqWave then
                repeat task.wait(0.5) until GetCurrentWave() >= ReqWave
            end
            local t = self.PlacedTowers[idx]
            if t and DoSellTower(t) then
                return true
            end
            return false
        end
        
        function TDS:SellAll(ReqWave)
            task.spawn(function()
                if ReqWave then
                    repeat task.wait(0.5) until GetCurrentWave() >= ReqWave
                end
        
                local TowersCopy = {unpack(self.PlacedTowers)}
                for idx, t in ipairs(TowersCopy) do
                    if DoSellTower(t) then
                        for i, OrigT in ipairs(self.PlacedTowers) do
                            if OrigT == t then
                                table.remove(self.PlacedTowers, i)
                                break
                            end
                        end
                    end
                end
        
                return true
            end)
        end
        
        function TDS:Ability(idx, name, data, loop)
            local t = self.PlacedTowers[idx]
            if not t then return false end
            return DoActivateAbility(t, name, data, loop)
        end
        
        function TDS:AutoChain(...)
            local TowerIndices = {...}
            if #TowerIndices == 0 then return end
        
            local running = true
        
            task.spawn(function()
                local i = 1
                while running do
                    local idx = TowerIndices[i]
                    local tower = TDS.PlacedTowers[idx]
        
                    if tower then
                        DoActivateAbility(tower, "Call Of Arms")
                    end
        
                    task.wait(10.5)
        
                    i += 1
                    if i > #TowerIndices then
                        i = 1
                    end
                end
            end)
        
            return function()
                running = false
            end
        end
        
        function TDS:SetOption(idx, name, val, ReqWave)
            local t = self.PlacedTowers[idx]
            if t then
                return DoSetOption(t, name, val, ReqWave)
            end
            return false
        end
        
        if GameState == "LOBBY" and Globals.AutoRejoin and isfile("ADS_LastStrat.lua") then
            pcall(delfile, "ADS_LastStrat.lua")
        end
        
        if GameState == "GAME" and Globals.AutoRejoin and isfile("ADS_LastStrat.lua") then
            local stratContent = pcall(readfile, "ADS_LastStrat.lua") and readfile("ADS_LastStrat.lua") or ""
            if stratContent:find(":Loadout%(") then
                TDS.LoadoutPending = true
            end
            task.spawn(function()
                task.wait(2)
                TDS:RunStrategy()
            end)
        end
        
        local function IsVoidCharm(obj)
            return math.abs(obj.Position.Y) > 999999
        end
        
        local function GetRoot()
            local char = LocalPlayer.Character
            return char and char:FindFirstChild("HumanoidRootPart")
        end
        
        local function StartAutoGatling()
            if Globals.DisableAPIGatling or Globals.GatlingManagedByMain or Globals.GatlingLoaderLoaded then return end
            if AutoGatlingRunning or not Globals.AutoGatling then return end
            AutoGatlingRunning = true
            task.spawn(function()
                while Globals.AutoGatling and not Globals.DisableAPIGatling and not Globals.GatlingManagedByMain do
                    if GameState == "GAME" then
                        if not GatlingExecuted and not Globals.GatlingLoaderLoaded then
                            GatlingExecuted = true 
                            Globals.GatlingLoaderLoaded = true
                            task.spawn(function()
                                pcall(function()
                                    local selected = Globals.SelectedGatling or "Gatlify"
                                    if selected == "Gatling Gun" then
                                        loadstring(game:HttpGet("https://raw.githubusercontent.com/avtryxz/autogutlin/refs/heads/main/autogutlin.lua"))()
                                    else
                                        loadstring(game:HttpGet("https://raw.githubusercontent.com/avtryxz/Gatlify/refs/heads/main/Gatlify.lua"))()
                                    end
                                end)
                            end)
                        end
                    else
                        GatlingExecuted = false 
                    end
                    task.wait(1)
                end
                AutoGatlingRunning = false
            end)
        end
        
        local function StartAutoSkip()
            if AutoSkipRunning or not Globals.AutoSkip then return end
            AutoSkipRunning = true
        
            task.spawn(function()
                while Globals.AutoSkip do
                    local SkipVisible =
                        PlayerGui:FindFirstChild("ReactOverridesVote")
                        and PlayerGui.ReactOverridesVote:FindFirstChild("Frame")
                        and PlayerGui.ReactOverridesVote.Frame:FindFirstChild("votes")
                        and PlayerGui.ReactOverridesVote.Frame.votes:FindFirstChild("vote")
        
                    if SkipVisible and SkipVisible.Position == UDim2.new(0.5, 0, 0.5, 0) then
                        RunVoteSkip()
                    end
        
                    task.wait(0.1)
                end
        
                AutoSkipRunning = false
            end)
        end
        
        local function HandlePostMatch(forceRestart)
            if forceRestart == true or Globals.AutoRestart then
                TriggerRestart()
            else
                SmartTeleportToLobby()
            end
        end
        
        function StartBackToLobby()
            if game.PlaceId == 3260590327 then return end
            if BackToLobbyRunning then return end
            BackToLobbyRunning = true
        
            task.spawn(function()
                local stateReplicators = ReplicatedStorage:WaitForChild("StateReplicators", 30)
                local gameStateReplicator = stateReplicators and stateReplicators:WaitForChild("GameStateReplicator", 30)
                local voteReplicator = stateReplicators and stateReplicators:WaitForChild("VoteReplicator", 30)
                
                if not gameStateReplicator or not voteReplicator then
                    while true do
                        if not Globals.AutoRejoin and not Globals.AutoRestart then break end
                        pcall(HandlePostMatch)
                        task.wait(1)
                    end
                    BackToLobbyRunning = false
                    return
                end
        
                while Globals.AutoRejoin or Globals.AutoRestart do
                    local isGameOver = gameStateReplicator:GetAttribute("GameOver") == true
                    if isGameOver then
                        local health = gameStateReplicator:GetAttribute("Health") or 0
                        if health > 0 then
                            if Globals.AutoRejoin then
                                if isfile("ADS_LastStrat.lua") then
                                    pcall(delfile, "ADS_LastStrat.lua")
                                end
                                pcall(HandlePostMatch)
                                break
                            end
                        else
                            if Globals.AutoRestart then
                                task.spawn(pcall, HandlePostMatch, true)
                                local lastVoteTime = 0
                                while Globals.AutoRestart do
                                    local title = voteReplicator:GetAttribute("Title")
                                    local enabled = voteReplicator:GetAttribute("Enabled")
                                    
                                    if enabled == true and title == "Restart?" then
                                        if os.clock() - lastVoteTime > 3 then
                                            pcall(function()
                                                RemoteFunc:InvokeServer("Voting", "Skip")
                                            end)
                                            lastVoteTime = os.clock()
                                        end
                                    end
                                    
                                    if title == "Ready?" or gameStateReplicator:GetAttribute("GameOver") == false then
                                        break
                                    end
                                    task.wait(0.5)
                                end
                                
                                if not Globals.AutoRestart then break end
                                
                                if isfile("ADS_LastStrat.lua") then
                                    task.spawn(function()
                                        repeat
                                            task.wait(0.1)
                                            local towersFolder = workspace:FindFirstChild("Towers")
                                        until (towersFolder and #towersFolder:GetChildren() == 0) or not Globals.AutoRestart
                                        
                                        if not Globals.AutoRestart then return end
                                        TDS:ResetAllStates()
                                        TDS:RunStrategy()
                                    end)
                                end
                                
                                repeat task.wait(1) until gameStateReplicator:GetAttribute("GameOver") == false or not Globals.AutoRestart
                            elseif Globals.AutoRejoin then
                                if isfile("ADS_LastStrat.lua") then
                                    pcall(delfile, "ADS_LastStrat.lua")
                                end
                                pcall(HandlePostMatch)
                                break
                            end
                        end
                    end
                    task.wait(1)
                end
                BackToLobbyRunning = false
            end)
        end
        
        local function StartAntiLag()
            if AntiLagRunning or not Globals.AntiLag then return end
            AntiLagRunning = true
        
            local settings = settings().Rendering
            settings.QualityLevel = Enum.QualityLevel.Level01
        
            task.spawn(function()
                while Globals.AntiLag do
                    local TowersFolder = workspace:FindFirstChild("Towers")
                    local ClientUnits = workspace:FindFirstChild("ClientUnits")
        
                    if TowersFolder then
                        for _, tower in ipairs(TowersFolder:GetChildren()) do
                            local anims = tower:FindFirstChild("Animations")
                            local weapon = tower:FindFirstChild("Weapon")
                            local projectiles = tower:FindFirstChild("Projectiles")
        
                            if anims then anims:Destroy() end
                            if projectiles then projectiles:Destroy() end
                            if weapon then weapon:Destroy() end
                        end
                    end
                    if ClientUnits then
                        for _, unit in ipairs(ClientUnits:GetChildren()) do
                            unit:Destroy()
                        end
                    end
                    
                    task.wait(0.5)
                end
                AntiLagRunning = false
            end)
        end
        
        local function StartAutoChain()
            if AutoChainRunning or not Globals.AutoChain then return end
            AutoChainRunning = true
        
            task.spawn(function()
                local idx = 1
        
                while Globals.AutoChain do
                    local commander = {}
                    local TowersFolder = workspace:FindFirstChild("Towers")
        
                    if TowersFolder then
                        for _, towers in ipairs(TowersFolder:GetDescendants()) do
                            if not Globals.AutoChain then break end
                            if towers:IsA("Folder") and towers.Name == "TowerReplicator"
                            and towers:GetAttribute("Name") == "Commander"
                            and towers:GetAttribute("OwnerId") == game.Players.LocalPlayer.UserId
                            and (towers:GetAttribute("Upgrade") or 0) >= 2 then
                                commander[#commander + 1] = towers.Parent
                            end
                        end
                    end
        
                    if not Globals.AutoChain then break end
        
                    if #commander >= 3 then
                        if idx > #commander then idx = 1 end
        
                        local CurrentCommander = commander[idx]
                        local replicator = CurrentCommander and CurrentCommander:FindFirstChild("TowerReplicator")
                        local UpgradeLevel = replicator and replicator:GetAttribute("Upgrade") or 0
        
                        if UpgradeLevel >= 4 and Globals.SupportCaravan then
                            RemoteFunc:InvokeServer(
                                "Troops",
                                "Abilities",
                                "Activate",
                                { Troop = CurrentCommander, Name = "Support Caravan", Data = {} }
                            )
                            task.wait(0.1) 
                        end
        
                        if not Globals.AutoChain then break end
        
                        local response = RemoteFunc:InvokeServer(
                            "Troops",
                            "Abilities",
                            "Activate",
                            { Troop = CurrentCommander, Name = "Call Of Arms", Data = {} }
                        )
        
                        if response then
                            idx += 1
                            task.wait(10.3)
                        else
                            task.wait(0.5)
                        end
                    else
                        task.wait(1)
                    end
                end
        
                AutoChainRunning = false
            end)
        end
        
        local function StartAutoDjBooth()
            if AutoDjRunning or not Globals.AutoDJ then return end
            AutoDjRunning = true
        
            task.spawn(function()
                while Globals.AutoDJ do
                    local DJ = nil
                    local TowersFolder = workspace:FindFirstChild("Towers")
        
                    if TowersFolder then
                        for _, towers in ipairs(TowersFolder:GetDescendants()) do
                            if not Globals.AutoDJ then break end
                            if towers:IsA("Folder") and towers.Name == "TowerReplicator"
                            and towers:GetAttribute("Name") == "DJ Booth"
                            and towers:GetAttribute("OwnerId") == game.Players.LocalPlayer.UserId
                            and (towers:GetAttribute("Upgrade") or 0) >= 3 then
                                DJ = towers.Parent
                            end
                        end
                    end
        
                    if not Globals.AutoDJ then break end
        
                    if DJ then
                        RemoteFunc:InvokeServer(
                            "Troops",
                            "Abilities",
                            "Activate",
                            { Troop = DJ, Name = "Drop The Beat", Data = {} }
                        )
                    end
        
                    task.wait(1)
                end
        
                AutoDjRunning = false
            end)
        end
        
        local function StartAutoNecro()
            if AutoNecroRunning or not Globals.AutoNecro then return end
            AutoNecroRunning = true
        
            local lastActivation = 0
            local ownerId = game.Players.LocalPlayer.UserId
        
            local function getNecros(towersFolder)
                local list = {}
                if not towersFolder then
                    return list
                end
                for _, rep in ipairs(towersFolder:GetDescendants()) do
                    if not Globals.AutoNecro then break end
                    if rep:IsA("Folder") and rep.Name == "TowerReplicator"
                    and rep:GetAttribute("Name") == "Necromancer"
                    and rep:GetAttribute("OwnerId") == ownerId then
                        list[#list + 1] = rep.Parent
                    end
                end
                return list
            end
        
            local function pickMaxGraves(rep, graveStore, up)
                local maxGraves = rep and rep:GetAttribute("Max_Graves")
                if graveStore then
                    local gMax = graveStore:GetAttribute("Max_Graves")
                    if type(gMax) == "number" and gMax > 0 then
                        maxGraves = gMax
                    end
                end
                if not maxGraves or maxGraves < 2 then
                    if up >= 4 then
                        maxGraves = 9
                    elseif up >= 2 then
                        maxGraves = 6
                    else
                        maxGraves = 3
                    end
                end
                return maxGraves
            end
        
            local function countGraves(graveStore)
                if not graveStore then
                    return 0
                end
                local cnt = 0
                for k, v in pairs(graveStore:GetAttributes()) do
                    if type(k) == "string" and #k > 20 then
                        local isDestroy = false
                        if type(v) == "table" then
                            for _, elem in pairs(v) do
                                if tostring(elem) == "Destroy" then
                                    isDestroy = true
                                    break
                                end
                            end
                        elseif tostring(v):find("Destroy") then
                            isDestroy = true
                        end
                        if isDestroy then
                            graveStore:SetAttribute(k, nil)
                        else
                            cnt += 1
                        end
                    end
                end
                return cnt
            end
        
            local function cleanAllGraves(list)
                for _, necro in ipairs(list) do
                    if not Globals.AutoNecro then break end
                    local rep = necro and necro:FindFirstChild("TowerReplicator")
                    local store = rep and rep:FindFirstChild("GraveStone")
                    if store then
                        countGraves(store)
                    end
                end
            end
        
            task.spawn(function()
                local idx = 1
        
                while Globals.AutoNecro do
                    local TowersFolder = workspace:FindFirstChild("Towers")
                    local necromancer = getNecros(TowersFolder)
                    cleanAllGraves(necromancer)
        
                    if not Globals.AutoNecro then break end
        
                    if #necromancer >= 1 then
                        if idx > #necromancer then idx = 1 end
                        local CurrentNecromancer = necromancer[idx]
                        local replicator = CurrentNecromancer and CurrentNecromancer:FindFirstChild("TowerReplicator")
        
                        local up = replicator and (replicator:GetAttribute("Upgrade") or 0) or 0
                        local graveStore = replicator and replicator:FindFirstChild("GraveStone")
                        local maxGraves = pickMaxGraves(replicator, graveStore, up)
                        local graveCount = countGraves(graveStore)
                        local debounce = (replicator and replicator:GetAttribute("AbilityDebounce")) or 5
                        local now = os.clock()
        
                        if maxGraves and graveCount >= maxGraves and (now - lastActivation >= debounce) then
                            if not Globals.AutoNecro then break end
                            local response = RemoteFunc:InvokeServer(
                                "Troops",
                                "Abilities",
                                "Activate",
                                { Troop = CurrentNecromancer, Name = "Raise The Dead", Data = {} }
                            )
        
                            if response then 
                                lastActivation = now
                                idx += 1
                                task.wait(1)
                            else
                                task.wait(0.5)
                            end
                        else
                            task.wait(0.1)
                        end
                    else
                        task.wait(1)
                    end
                end
        
                AutoNecroRunning = false
            end)
        end
        
        local function StartAutoMercenary()
            if not Globals.AutoMercenary then return end
        
            if AutoMercenaryBaseRunning then return end
            AutoMercenaryBaseRunning = true
        
            task.spawn(function()
                while Globals.AutoMercenary do
                    local TowersFolder = workspace:FindFirstChild("Towers")
        
                    if TowersFolder then
                        for _, towers in ipairs(TowersFolder:GetDescendants()) do
                            if not Globals.AutoMercenary then break end
                            if towers:IsA("Folder") and towers.Name == "TowerReplicator"
                            and towers:GetAttribute("Name") == "Mercenary Base"
                            and towers:GetAttribute("OwnerId") == game.Players.LocalPlayer.UserId
                            and (towers:GetAttribute("Upgrade") or 0) >= 5 then
        
                                RemoteFunc:InvokeServer(
                                    "Troops",
                                    "Abilities",
                                    "Activate",
                                    { 
                                        Troop = towers.Parent, 
                                        Name = "Air-Drop", 
                                        Data = {
                                            pathName = 1, 
                                            directionCFrame = CFrame.new(), 
                                            dist = Globals.MercenaryPath or 195
                                        } 
                                    }
                                )
        
                                task.wait(0.5)
        
                                if not Globals.AutoMercenary then break end
                            end
                        end
                    end
        
                    task.wait(0.5)
                end
        
                AutoMercenaryBaseRunning = false
            end)
        end
        
        local function StartAutoMilitary()
            if not Globals.AutoMilitary then return end
        
            if AutoMilitaryBaseRunning then return end
            AutoMilitaryBaseRunning = true
        
            task.spawn(function()
                while Globals.AutoMilitary do
                    local TowersFolder = workspace:FindFirstChild("Towers")
                    if TowersFolder then
                        for _, towers in ipairs(TowersFolder:GetDescendants()) do
                            if not Globals.AutoMilitary then break end
                            if towers:IsA("Folder") and towers.Name == "TowerReplicator"
                            and towers:GetAttribute("Name") == "Military Base"
                            and towers:GetAttribute("OwnerId") == game.Players.LocalPlayer.UserId
                            and (towers:GetAttribute("Upgrade") or 0) >= 4 then
        
                                RemoteFunc:InvokeServer(
                                    "Troops",
                                    "Abilities",
                                    "Activate",
                                    { 
                                        Troop = towers.Parent, 
                                        Name = "Airstrike", 
                                        Data = {
                                            pathName = 1, 
                                            pointToEnd = CFrame.new(), 
                                            dist = Globals.MilitaryPath or 195
                                        } 
                                    }
                                )
        
                                task.wait(0.5)
        
                                if not Globals.AutoMilitary then break end
                            end
                        end
                    end
        
                    task.wait(0.5)
                end
        
                AutoMilitaryBaseRunning = false
            end)
        end
        
        local AutoMedicModule = nil
        
        local function StartMedicChain()
            if Globals.AutoMedic then
                if AutoMedicModule and AutoMedicModule.State and AutoMedicModule.State.Running then 
                    return 
                end
        
                local myMedics = {}
                repeat
                    if not Globals.AutoMedic then return end
                    myMedics = {}
                    local towersFolder = game:GetService("Workspace"):FindFirstChild("Towers")
                    
                    if towersFolder then
                        for _, tower in ipairs(towersFolder:GetChildren()) do
                            if not Globals.AutoMedic then return end
                            local replicator = tower:FindFirstChild("TowerReplicator")
                            if replicator then
                                local ownerId = replicator:GetAttribute("OwnerId")
                                local ownerName = replicator:GetAttribute("OwnerName")
                                local towerName = replicator:GetAttribute("Name")
        
                                local localPlayer = game:GetService("Players").LocalPlayer
                                local isOwner = (ownerId and ownerId == localPlayer.UserId) or (ownerName and ownerName == localPlayer.Name)
        
                                if isOwner and towerName and string.lower(towerName) == "medic" then
                                    table.insert(myMedics, tower)
                                end
                            end
                        end
                    end
        
                    if #myMedics < 4 then
                        task.wait(1)
                    end
                until #myMedics >= 4 or not Globals.AutoMedic
        
                if not Globals.AutoMedic then return end
        
                if not AutoMedicModule then
                    local success, loadedLib = pcall(function()
                        local url = "https://raw.githubusercontent.com/AmonguszzZ/ModdedAether/refs/heads/main/AutoAbilities/AutoMedicNew.lua"
                        return loadstring(game:HttpGet(url))()
                    end)
                    if success and loadedLib then
                        AutoMedicModule = loadedLib
                    end
                end
                if AutoMedicModule and Globals.AutoMedic then
                    AutoMedicModule.Chaining()
                end
            else
                if AutoMedicModule and AutoMedicModule.State then
                    AutoMedicModule.State.Running = false
                end
            end
        end
        
        function TDS:Rejoin()
            SmartTeleportToLobby()
        end
        
        function TDS:RemoveIndex()
        	self.PlacedTowers = {}
            self.PlacedTraps = {}
            self.MapInteractions = {}
          
            if UpgradeHistory then
                table.clear(UpgradeHistory)
            end
        
            ModuleRunning = true
            if not idleConnection then
                idleConnection = LocalPlayer.Idled:Connect(function()
                    if not ModuleRunning then return end
                    VirtualUser:CaptureController()
                    VirtualUser:ClickButton2(Vector2.new(0, 0))
                end)
            end
        end
        
        task.spawn(function()
            task.wait(2)
            while ModuleRunning do
        
                if Globals.AutoSkip and not AutoSkipRunning then
                    StartAutoSkip()
                end
        
                if Globals.AutoChain and not AutoChainRunning then
                    StartAutoChain()
                end
        
                if Globals.AutoDJ and not AutoDjRunning then
                    StartAutoDjBooth()
                end
        
                if Globals.AutoNecro and not AutoNecroRunning then
                    StartAutoNecro()
                end
        
                if Globals.AutoMercenary and not AutoMercenaryBaseRunning then
                    StartAutoMercenary()
                end
        
                if Globals.AutoMilitary and not AutoMilitaryBaseRunning then
                    StartAutoMilitary()
                end
        
                if Globals.AntiLag and not AntiLagRunning then
                    StartAntiLag()
                end
        
                if (Globals.AutoRejoin or Globals.AutoRestart) and not BackToLobbyRunning then
                    StartBackToLobby()
                end
        
                if Globals.AutoGatling and not AutoGatlingRunning and not Globals.DisableAPIGatling and not Globals.GatlingManagedByMain then
                    StartAutoGatling()
                end
        
                if Globals.AutoReady and not AutoReadyRunning then
                    StartAutoReady()
                end
        
                if Globals.AutoMedic and not AutoMedicRunning then
                    StartMedicChain()
                end
        		
                task.wait(1)
            end
        end)
        
        MissionsUIFix()
        
        return TDS
    end

    local ok, result = pcall(initializeEmbeddedTDSAPI)
    if not ok then
        warn("[ServiceHub] Embedded TDS API failed to initialize: " .. tostring(result))
        return nil
    end
    if type(result) ~= "table" then
        warn("[ServiceHub] Embedded TDS API returned an invalid module.")
        return nil
    end
    return result
end

local TDS: any = loadEmbeddedTDSAPI()
if TDS then
    Globals.TDS = TDS
    pcall(function() getgenv().TDS = TDS end)
    pcall(function() _G.TDS = TDS end)
end

if Globals.ServiceHub_Unload then
    pcall(Globals.ServiceHub_Unload)
end

local isRunning = true
Globals.IsConfigDirty = false
Globals.ServiceHub_Unload = function()
    isRunning = false
    Globals.ServiceHub_Running = false
    if activeStratThread and coroutine.status(activeStratThread) ~= "dead" then
        pcall(task.cancel, activeStratThread)
        activeStratThread = nil
    end
    if TDS and typeof(TDS.RemoveIndex) == "function" then
        pcall(function() TDS:RemoveIndex() end)
    end
    if Globals.ServiceHub_ScreenGui then
        pcall(function() Globals.ServiceHub_ScreenGui:Destroy() end)
        Globals.ServiceHub_ScreenGui = nil
    end
    pcall(function()
        local getParent = function()
            if gethui then
                local ok, h = pcall(gethui)
                if ok and h then return h end
            end
            local ok, parent = pcall(function() return game:GetService("CoreGui") end)
            if ok and parent then return parent end
            return Players.LocalPlayer and Players.LocalPlayer:FindFirstChild("PlayerGui")
        end
        local parentGui = getParent()
        if parentGui then
            for _, name in ipairs({ "ServiceHub_Window", "CyberNeon_Window", "SkyBlueUI_Window" }) do
                pcall(function()
                    local found = parentGui:FindFirstChild(name)
                    if found then found:Destroy() end
                end)
            end
        end
        local lp = Players.LocalPlayer
        local pg = lp and lp:FindFirstChild("PlayerGui")
        if pg then
            for _, name in ipairs({ "ServiceHub_Window", "CyberNeon_Window", "SkyBlueUI_Window" }) do
                pcall(function()
                    local found = pg:FindFirstChild(name)
                    if found then found:Destroy() end
                end)
            end
        end
    end)
end

do
    local defaultGlobals = {
        AutoSkip = false,
        AutoSkips = false,
        AutoRestart = false,
        AutoReady = false,
        AutoMedic = false,
        AutoChain = false,
        SupportCaravan = false,
        AutoGatling = true,
        SelectedGatling = "Gatlify",
        AutoDJ = false,
        AutoNecro = false,
        AutoRejoin = false,
        AutoMercenary = false,
        AutoReset = false,
        AutoBack = false,
        TimeScaleEnabled = false,
        TimeScaleValue = 2,
        TrialFarmMode = "Farm Mode",
        FarmOnly = "Disabled",
        MultiplayerEnabled = false,
        MultiplayerMode = "Trial Mode",
        MultiplayerFarmStrategy = "Molten",
        MultiplayerSelectedTrial = "Current Rotation",
        MultiplayerRole = "Host",
        MultiplayerIsHost = false,
        MultiplayerHostIdentifier = "",
        MultiplayerTargetP2 = "",
        MultiplayerIsP2 = false,
        MultiplayerTargetHost = "",
        PrivateServerCode = "",
        LobbyWatcherEnabled = true,
        PreferredAccessTier = "Keyless",
        BuyMissingCoinsTower = false,
        BuyMissingGemTower = false,
        BuyMissingEvoTower = false,
        BuyMissingGoldSkins = false,
        BuySkillTree = false,
        AutoEvo = false,
        TargetEvo = "All",
        EvoStrat = "Lose",
    }
    for k, v in pairs(defaultGlobals) do
        if Globals[k] == nil then
            Globals[k] = v
        end
    end
end

-- Roblox Engine Services
Players = game:GetService("Players")
UserInputService = game:GetService("UserInputService")
ReplicatedStorage = game:GetService("ReplicatedStorage")
HttpService = game:GetService("HttpService")
TeleportService = game:GetService("TeleportService")
MarketplaceService = game:GetService("MarketplaceService")

LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    local t0 = tick()
    while not Players.LocalPlayer and (tick() - t0 < 10) do
        task.wait(0.1)
    end
    LocalPlayer = Players.LocalPlayer
end
if not LocalPlayer then
    error("[ServiceHub] LocalPlayer was unavailable after waiting 10 seconds")
end
PlayerGui = LocalPlayer:WaitForChild("PlayerGui", 10) or LocalPlayer:FindFirstChild("PlayerGui")
if not PlayerGui then
    error("[ServiceHub] PlayerGui was unavailable after waiting 10 seconds")
end
local LOBBY_PLACE_ID = 3260590327

-- Configuration Directory & File Paths ([ATF] Configuration Suite)
local CONFIG_FOLDER = "[ATF]"
local TRIAL_STATE_FILE_NAME = tostring(LocalPlayer.UserId) .. "_trialstate.txt"
local SETTINGS_FILE_NAME = tostring(LocalPlayer.UserId) .. ".json"

local TRIAL_STATE_FILE = CONFIG_FOLDER .. "/" .. TRIAL_STATE_FILE_NAME
local SETTINGS_FILE = CONFIG_FOLDER .. "/" .. SETTINGS_FILE_NAME
local ACTIVE_MODE_FILE = CONFIG_FOLDER .. "/" .. tostring(LocalPlayer.UserId) .. "_active_mode.txt"
local ACTIVE_FARM_TYPE_FILE = CONFIG_FOLDER .. "/" .. tostring(LocalPlayer.UserId) .. "_active_farm_type.txt"
local VERIFIED_KEY_FILE = CONFIG_FOLDER .. "/verified_key.txt"

local TimeScaleRunning = false
local TimeScaleNoTicketsWarned = false

--==============================================================================
--==============================================================================
-- PlayerDataHandler (Loaded First as Required via Readfile / Cloud Fallback)
--==============================================================================
local PlayerDataHandler: any = nil
local playerDataLoading = false

local function createEmbeddedPlayerDataHandler(): any
--[[
    Embedded DataHandler Suite (Clean, Synchronous, Capability-Safe)
    Eliminates external network dependencies and prevents Centurion obfuscation crashes.
]]--
--[[
    CombinedData
    Description:
        Provides a single API that merges Tower Ownership, Golden Skin/Perks detection,
        Tower EXP progression, Skill‑tree extraction, and Player Stats (Level/EXP/Coins/Gems).
        • Accurate Golden tower ownership (checks Inventory.Skins, not just equipped state).
        • Active Golden perks detector (checks if perk is enabled in loadout).
        • Full Tower EXP progression for all 8 towers (progress, required, max level, uncapped).
        • Fast Cache-based Player Stats: Values.Level, Values.Experience, Experience(level + 1),
          Values.Coins, and Values.Gems with safe fallback layers.
        • Skill‑tree extraction from Workspace["1"] … Workspace["17"].
        • Lightweight, synchronous, and safe for mobile/third-party executors.
]]--

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

-- ---------------------------------------------------------------------
-- Core helpers (LocalPlayer, PlayerGui, number parsing)
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
            if atom ~= nil then
                if type(atom) == "function" then
                    local fastVal = atom()
                    if fastVal ~= nil then return fastVal end
                end
                if type(atom) == "table" then
                    if type(atom.GetValue) == "function" then
                        local fastVal = atom:GetValue()
                        if fastVal ~= nil then return fastVal end
                    end
                    if type(atom.get) == "function" then
                        local fastVal = atom:get()
                        if fastVal ~= nil then return fastVal end
                    end
                    if type(atom.getState) == "function" then
                        local fastVal = atom:getState()
                        if fastVal ~= nil then return fastVal end
                    end
                    if atom._value ~= nil then return atom._value end
                    if atom.value ~= nil then return atom.value end
                    if atom.state ~= nil then return atom.state end
                end
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
-- Tower Ownership (Cache -> InventoryController -> UI Scan)
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

function CombinedData:IsTowerOwned(towerName)
    if not towerName or towerName == "" then return false end

    -- 1. Fast Cache Check
    local troops = getCacheValue("Inventory.Troops")
    if troops and type(troops) == "table" then
        if troops[towerName] ~= nil then
            return true
        end
    end

    -- 2. InventoryController Check
    if InventoryController and type(InventoryController.getItems) == "function" then
        local success, items = pcall(function() return InventoryController:getItems() end)
        if success and items then
            for _, item in pairs(items) do
                if type(item) == "table" and item.type == "tower" and item.name == towerName then
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
            if towerNode then
                local main = towerNode:FindFirstChild("main")
                if main and main:FindFirstChild("amountLeft") then
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
function CombinedData:IsGoldenOwned(towerName)
    if not towerName or towerName == "" then return false end

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
-- Coins / Gems / Level / Player EXP (Values.* Cache with Fallbacks)
-- ---------------------------------------------------------------------
local function getLobbyHud()
    local pgui = getPlayerGui(2)
    if not pgui then return nil end
    return pgui:FindFirstChild("ReactLobbyHud") or pgui:WaitForChild("ReactLobbyHud", 2)
end

function CombinedData:GetLevel()
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

    return 0, "0"
end

function CombinedData:GetCoins()
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

    return 0, "0"
end

function CombinedData:GetGems()
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

    return 0, "0"
end

--- Returns current player EXP, required EXP for next level, and formatted string
function CombinedData:GetPlayerExp()
    local exp = getStat("Values.Experience") or 0
    local level = self:GetLevel() or 0
    local nextLevelExp = 0

    if Experience then
        local ok, nExp = pcall(Experience, level + 1)
        if ok and nExp then
            nextLevelExp = nExp
        end
    end

    return exp, nextLevelExp, string.format("%d / %d", exp, nextLevelExp)
end

--- Returns a table containing Level, EXP, NextLevelExp, Coins, and Gems
function CombinedData:GetPlayerStats()
    local level = self:GetLevel()
    local exp, nextLevelExp, expDisplay = self:GetPlayerExp()
    local coins = self:GetCoins()
    local gems = self:GetGems()

    return {
        Level = level,
        Exp = exp,
        NextLevelExp = nextLevelExp,
        ExpDisplay = expDisplay,
        Coins = coins,
        Gems = gems
    }
end

-- ---------------------------------------------------------------------
-- Skill‑tree extraction
-- ---------------------------------------------------------------------
local skillTreeCacheFile = "ProjectOptimazation/CachedSkillTree.json"
local inMemorySkillTreeCache = {}
local lastSkillTreeDiskWrite = 0
local lastSkillTreeJson = ""

function CombinedData:GetSkillTree()
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
-- Requirements Validation API
-- ---------------------------------------------------------------------
function CombinedData:CheckRequirements(requirements)
    local missing = {}
    local passed = true

    -- 1. Check Player Level
    if requirements.Level then
        local currentLevel = self:GetLevel()
        if currentLevel < requirements.Level then
            passed = false
            table.insert(missing, string.format("Level: required %d, current %d", requirements.Level, currentLevel))
        end
    end

    -- 2. Check Skill Tree (supports both .Skill and .SkillTree)
    local skillReqs = requirements.SkillTree or requirements.Skill
    if skillReqs and type(skillReqs) == "table" then
        local currentSkills = {}
        for _, skill in ipairs(self:GetSkillTree()) do
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
        local currentCoins = self:GetCoins()
        if currentCoins < requirements.Coins then
            passed = false
            table.insert(missing, string.format("Coins: required %d, current %d", requirements.Coins, currentCoins))
        end
    end

    -- 4. Check Gems
    if requirements.Gems then
        local currentGems = self:GetGems()
        if currentGems < requirements.Gems then
            passed = false
            table.insert(missing, string.format("Gems: required %d, current %d", requirements.Gems, currentGems))
        end
    end

    -- 5. Check Towers Owned
    if requirements.Towers and type(requirements.Towers) == "table" then
        for _, towerName in ipairs(requirements.Towers) do
            if not self:IsTowerOwned(towerName) then
                passed = false
                table.insert(missing, string.format("Missing Tower: %s", towerName))
            end
        end
    end

    -- 6. Check Golden Towers Owned
    if requirements.Golden and type(requirements.Golden) == "table" then
        for _, towerName in ipairs(requirements.Golden) do
            if not self:IsGoldenOwned(towerName) then
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

local inMemoryOwnedModifiers = nil

local function getSavedOwnedModifiers()
    local candidateFiles = {
        "ServiceHub/CachedTrialsStatus.json",
        "CachedTrialsStatus.json",
        "ProjectOptimazation/CachedTrialsStatus.json"
    }
    for _, path in ipairs(candidateFiles) do
        local ok, content = pcall(function()
            if isfile and isfile(path) and readfile and HttpService then
                local raw = readfile(path)
                if raw and raw ~= "" then
                    return HttpService:JSONDecode(raw)
                end
            end
            return nil
        end)
        if ok and type(content) == "table" then
            if content.Modifiers and type(content.Modifiers) == "table" and #content.Modifiers > 0 then
                return content.Modifiers
            elseif #content > 0 then
                return content
            end
        end
    end
    return nil
end

local function persistOwnedModifiers(modsList)
    if not modsList or #modsList == 0 then return end
    pcall(function()
        if writefile and HttpService then
            local payload = HttpService:JSONEncode({ Modifiers = modsList })
            pcall(function() writefile("CachedTrialsStatus.json", payload) end)
            pcall(function()
                if makefolder and not isfolder("ServiceHub") then makefolder("ServiceHub") end
                writefile("ServiceHub/CachedTrialsStatus.json", payload)
            end)
        end
    end)
end

local function extractOwnedModifiers(): ({ [string]: boolean }, { [string]: boolean })
    local lookup: { [string]: boolean } = {}
    local normLookup: { [string]: boolean } = {}

    local function addModifier(name: any)
        if not name or name == "" then return end
        local str = tostring(name)
        lookup[str] = true
        normLookup[string.lower(string.gsub(str, "%s+", ""))] = true
    end

    local function scanTbl(tbl: any)
        if type(tbl) ~= "table" then return end
        for k, v in pairs(tbl) do
            if type(k) == "string" and tonumber(k) == nil and (v == true or v == 1 or type(v) == "table" or type(v) == "number") then
                addModifier(k)
            end
            if type(v) == "string" then
                addModifier(v)
            elseif type(v) == "table" then
                if v.Name then addModifier(v.Name) end
                if v.name then addModifier(v.name) end
                if v.Title then addModifier(v.Title) end
                if v.title then addModifier(v.title) end
                if v.Id then addModifier(v.Id) end
                if v.id then addModifier(v.id) end
                if v.Modifier then addModifier(v.Modifier) end
                if v.modifier then addModifier(v.modifier) end
                if v.Item then addModifier(v.Item) end
                if v.item then addModifier(v.item) end
            end
        end
    end

    -- 1. Scan persistent cache file (instant recognition on startup/lobby)
    local savedMods = inMemoryOwnedModifiers or getSavedOwnedModifiers()
    if savedMods then
        inMemoryOwnedModifiers = savedMods
        scanTbl(savedMods)
    end

    -- 2. Scan internal client cache
    if setthreadidentity then pcall(setthreadidentity, 8) end
    local ownedModifiers = getCacheValue("Inventory.Modifiers")
    scanTbl(ownedModifiers)
    scanTbl(getCacheValue("Modifiers"))
    scanTbl(getCacheValue("Inventory.Items"))
    scanTbl(getCacheValue("Items"))
    scanTbl(getCacheValue("Trials"))
    scanTbl(getCacheValue("OwnedTrials"))
    scanTbl(getCacheValue("OwnedModifiers"))
    local inv = getCacheValue("Inventory")
    if type(inv) == "table" then
        scanTbl(inv.Modifiers or inv.modifiers or inv.Items or inv.items or inv.Trials or inv.trials)
    end
    if setthreadidentity then pcall(setthreadidentity, 8) end

    -- 3. Scan InventoryController
    if InventoryController then
        if type(InventoryController.getItems) == "function" then
            local ok, items = pcall(function() return InventoryController:getItems() end)
            if ok and type(items) == "table" then
                for _, item in pairs(items) do
                    if type(item) == "table" then
                        local iType = tostring(item.type or item.Type or item.category or item.Category or ""):lower()
                        local iName = tostring(item.name or item.Name or item.id or item.Id or item.Modifier or item.modifier or item.Item or item.item or "")
                        if iName ~= "" then
                            if iType == "modifier" or iType == "trial" or iType == "modifiers" or iType:find("mod") then
                                addModifier(iName)
                            else
                                for _, t in ipairs(StaticTrialDefinitions) do
                                    local nNorm = string.lower(string.gsub(tostring(t.Name), "%s+", ""))
                                    local tNorm = string.lower(string.gsub(tostring(t.Title), "%s+", ""))
                                    local curNorm = string.lower(string.gsub(iName, "%s+", ""))
                                    if curNorm == nNorm or curNorm == tNorm then
                                        addModifier(iName)
                                        break
                                    end
                                end
                            end
                        end
                    elseif type(item) == "string" then
                        addModifier(item)
                    end
                end
            end
        end
        if type(InventoryController.getModifiers) == "function" then
            local ok, m = pcall(function() return InventoryController:getModifiers() end)
            if ok and type(m) == "table" then scanTbl(m) end
        end
        if type(InventoryController.getInventory) == "function" then
            local ok, invTbl = pcall(function() return InventoryController:getInventory() end)
            if ok and type(invTbl) == "table" then
                scanTbl(invTbl.Modifiers or invTbl.modifiers or invTbl.Items or invTbl.items or invTbl)
            end
        end
    end

    -- 4. Scan StateReplicators (ModifierReplicator)
    pcall(function()
        local sr = ReplicatedStorage:FindFirstChild("StateReplicators")
        local modRep = sr and sr:FindFirstChild("ModifierReplicator")
        if modRep then
            local raw = modRep:GetAttribute("Available")
            if type(raw) == "string" then
                local clean = raw:match("{.+}") or raw
                local ok, decoded = pcall(function() return HttpService:JSONDecode(clean) end)
                if ok and type(decoded) == "table" then
                    scanTbl(decoded)
                end
            elseif type(raw) == "table" then
                scanTbl(raw)
            end
            local attrs = modRep:GetAttributes()
            if attrs and type(attrs) == "table" then
                scanTbl(attrs)
            end
        end
    end)

    -- 5. Cross-match with StaticTrialDefinitions and build discovered list
    local discoveredList = {}
    for _, t in ipairs(StaticTrialDefinitions) do
        local nNorm = string.lower(string.gsub(tostring(t.Name), "%s+", ""))
        local tNorm = string.lower(string.gsub(tostring(t.Title), "%s+", ""))
        local mNorm = string.lower(string.gsub(tostring(t.Map), "%s+", ""))
        if lookup[t.Name] or lookup[t.Title] or normLookup[nNorm] or normLookup[tNorm] or normLookup[mNorm] then
            lookup[t.Name] = true
            lookup[t.Title] = true
            normLookup[nNorm] = true
            normLookup[tNorm] = true
            normLookup[mNorm] = true
            table.insert(discoveredList, t.Name)
        end
    end

    -- Persist discovered modifiers to cache files
    if #discoveredList > 0 then
        inMemoryOwnedModifiers = discoveredList
        persistOwnedModifiers(discoveredList)
    end

    return lookup, normLookup
end

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

    local lookup, normLookup = extractOwnedModifiers()

    local won = {}
    local notWon = {}

    for _, trialName in ipairs(allTrials) do
        local tNorm = string.lower(string.gsub(tostring(trialName), "%s+", ""))
        if lookup[trialName] or normLookup[tNorm] then
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
    local lookup, normLookup = extractOwnedModifiers()

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
            local tNorm = string.lower(string.gsub(tostring(trialName), "%s+", ""))
            local titNorm = string.lower(string.gsub(tostring(title), "%s+", ""))
            local isWon = lookup[trialName] == true or lookup[title] == true or normLookup[tNorm] == true or normLookup[titNorm] == true
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
            local tNorm = string.lower(string.gsub(tostring(t.Name), "%s+", ""))
            local titNorm = string.lower(string.gsub(tostring(t.Title), "%s+", ""))
            local isWon = lookup[t.Name] == true or lookup[t.Title] == true or normLookup[tNorm] == true or normLookup[titNorm] == true
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

function CombinedData:IsTrialWon(trialName)
    if not trialName or trialName == "" then return false end
    local lookup, normLookup = extractOwnedModifiers()
    local target = string.lower(string.gsub(tostring(trialName), "%s+", ""))
    if lookup[trialName] or normLookup[target] then
        return true
    end

    for _, t in ipairs(StaticTrialDefinitions) do
        local nNorm = string.lower(string.gsub(tostring(t.Name), "%s+", ""))
        local titNorm = string.lower(string.gsub(tostring(t.Title), "%s+", ""))
        local mNorm = string.lower(string.gsub(tostring(t.Map), "%s+", ""))
        if target == nNorm or target == titNorm or target == mNorm then
            if lookup[t.Name] or lookup[t.Title] or normLookup[nNorm] or normLookup[titNorm] or normLookup[mNorm] then
                return true
            end
        end
    end

    return false
end

CombinedData.PeerData = {}

function CombinedData:GetPeerData(identifier)
    if not identifier or identifier == "" then
        for _, peer in pairs(CombinedData.PeerData) do
            if type(peer) == "table" then return peer end
        end
        return nil
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

local function resolvePlayer(target)
    if target == nil or target == "" then
        return nil
    end

    if typeof(target) == "Instance" and target:IsA("Player") then
        if target.Parent == Players then
            return target
        end
        return nil
    end

    local targetStr = tostring(target):gsub("^%s+", ""):gsub("%s+$", "")
    if targetStr == "" then return nil end

    local targetNum = tonumber(targetStr)

    if targetNum then
        for _, p in ipairs(Players:GetPlayers()) do
            if p.UserId == targetNum then
                return p
            end
        end
    end

    local targetLower = string.lower(targetStr)
    for _, p in ipairs(Players:GetPlayers()) do
        if string.lower(p.Name) == targetLower then
            return p
        end
    end
    for _, p in ipairs(Players:GetPlayers()) do
        if string.lower(p.DisplayName) == targetLower then
            return p
        end
    end
    for _, p in ipairs(Players:GetPlayers()) do
        if string.sub(string.lower(p.Name), 1, #targetLower) == targetLower then
            return p
        end
    end
    for _, p in ipairs(Players:GetPlayers()) do
        if string.sub(string.lower(p.DisplayName), 1, #targetLower) == targetLower then
            return p
        end
    end

    return nil
end

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

return CombinedData


end

local function loadPlayerDataHandler(): any
    if PlayerDataHandler then return PlayerDataHandler end
    if playerDataLoading then return nil end
    playerDataLoading = true

    -- 0. Local file check (prefers local DataHandler.lua)
    local localCandidates = {
        "[STAY]/Multiplayer/DataHandler.lua",
        "[STAY]\\Multiplayer\\DataHandler.lua",
        "Multiplayer/DataHandler.lua",
        "DataHandler.lua",
        "[STAY]/New folder/DataHandler.lua",
        "[ATF]/DataHandler.lua",
    }
    pcall(function()
        if not (isfile and readfile) then return end
        for _, path in ipairs(localCandidates) do
            local ok, exists = pcall(isfile, path)
            if ok and exists then
                local rOk, content = pcall(readfile, path)
                if rOk and content and #content > 0 and not content:find("Centurion") then
                    local fn = loadstring(content)
                    if fn then
                        local execOk, mod = pcall(fn)
                        if execOk and type(mod) == "table" then
                            PlayerDataHandler = mod
                            return
                        end
                    end
                end
            end
        end
    end)
    if PlayerDataHandler then
        playerDataLoading = false
        return PlayerDataHandler
    end

    -- 1. Embedded clean DataHandler (Guaranteed capability-safe fallback)
    if typeof(createEmbeddedPlayerDataHandler) == "function" then
        local embOk, embMod = pcall(function()
            if setthreadidentity then pcall(setthreadidentity, 8) end
            return createEmbeddedPlayerDataHandler()
        end)
        if embOk and type(embMod) == "table" then
            PlayerDataHandler = embMod
            playerDataLoading = false
            return embMod
        end
    end

    -- 2. Cloud fallback via loadstring (strictly non-Centurion)
    local urls = {
        "https://raw.githubusercontent.com/Atxvy/-ATF-/refs/heads/main/DataHandler.lua",
    }
    for _, url in ipairs(urls) do
        local chunk = safeHttpGet(url, 3)
        if chunk and type(chunk) == "string" and #chunk > 0 then
            -- Strictly reject Centurion-obfuscated chunks that crash executors with lacking capability Plugin
            if not chunk:find("Centurion") then
                local execSuccess, module = pcall(function()
                    if setthreadidentity then pcall(setthreadidentity, 8) end
                    local fn, compileErr = loadstring(chunk)
                    if not fn then error(compileErr) end
                    return fn()
                end)
                if execSuccess and type(module) == "table" then
                    PlayerDataHandler = module
                    playerDataLoading = false
                    return module
                end
            end
        end
    end

    playerDataLoading = false
    return nil
end

PlayerDataHandler = loadPlayerDataHandler()
local function ensurePlayerDataReady(maxAttempts: number?): boolean
    local maxTries = maxAttempts or 20
    for _ = 1, maxTries do
        if not PlayerDataHandler then
            PlayerDataHandler = loadPlayerDataHandler()
        end
        if PlayerDataHandler then
            local ok, lvl = pcall(function()
                return PlayerDataHandler:GetLevel()
            end)
            if ok and type(lvl) == "number" and lvl > 0 then
                return true
            end
        end
        task.wait(0.1)
    end
    return PlayerDataHandler ~= nil
end

pcall(ensurePlayerDataReady, 10)

--==============================================================================
--==============================================================================
-- UI Framework Loader (CoreRevampNewAPI / UICore) - Readfile First & Cloud Fallback
--==============================================================================
local UILibrary: any
do
    local function sanitizeUIChunk(code: string): string
        local patched = code
        if patched:find("animConn = RunService.RenderStepped:Connect%(function%(dt%)") then
            patched = patched:gsub(
                "animConn = RunService.RenderStepped:Connect%(function%(dt%)",
                "animConn = RunService.RenderStepped:Connect(function(dt)\n        if setthreadidentity then pcall(setthreadidentity, 8) end"
            )
        end
        if patched:find("if not screenGui%.Parent then") then
            patched = patched:gsub(
                "if not screenGui%.Parent then",
                "local _pOk, _hasP = pcall(function() return screenGui and screenGui.Parent ~= nil end)\n        if not _pOk or not _hasP then"
            )
        end
        if patched:find("while screenGui%.Parent do") then
            patched = patched:gsub(
                "while screenGui%.Parent do",
                "while (function() local ok, p = pcall(function() return screenGui and screenGui.Parent ~= nil end); return ok and p end)() do"
            )
        end
        return patched
    end

    local function loadUILibrary(): any
        local urls = {
            "https://raw.githubusercontent.com/Atxvy/-ATF-/refs/heads/main/CoreRevampNewAPI.lua",
        }
        for _, url in ipairs(urls) do
            local chunk = safeHttpGet(url, 3)
            if chunk and type(chunk) == "string" and #chunk > 0 then
                -- Reject Centurion-obfuscated chunks that cause lag and capability issues
                if not chunk:find("Centurion") then
                    local success, lib = pcall(function()
                        if setthreadidentity then pcall(setthreadidentity, 8) end
                        local sanitized = sanitizeUIChunk(chunk)
                        local fn, compileErr = loadstring(sanitized)
                        if not fn then error(compileErr) end
                        return fn()
                    end)
                    if success and type(lib) == "table" then
                        return lib
                    end
                end
            end
        end
        return nil
    end

    UILibrary = loadUILibrary()
end
if not UILibrary then
    error("[ServiceHub] Failed to load UI Library (readfile and cloud both failed)!")
end
local UI: { [string]: any } = {}

local function logActivity(msg: string, msgType: string?)
    pcall(function()
        if UI and UI.LogConsole then
            if msgType == "warn" then
                UI.LogConsole:Warn(msg)
            elseif msgType == "error" then
                UI.LogConsole:Error(msg)
            elseif msgType == "success" then
                UI.LogConsole:Success(msg)
            elseif msgType == "info" then
                UI.LogConsole:Info(msg)
            else
                UI.LogConsole:Log(msg)
            end
        end
    end)
end

local function RunAsExecutor(fn)
    local be = Instance.new("BindableEvent")
    be.Event:Connect(function(args)
        if setthreadidentity then pcall(setthreadidentity, 8) end
        fn(unpack(args))
    end)
    return function(...) be:Fire({...}) end
end

--==============================================================================
-- Helper Utilities
--==============================================================================
local function formatNumberWithCommas(amount: number): string
    local formatted = tostring(amount or 0)
    local k
    while true do
        if not isRunning then break end
        formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1,%2")
        if k == 0 then break end
    end
    return formatted
end

local function normalizeString(str: any): string
    if not str then return "" end
    return string.lower(string.gsub(tostring(str), "%s+", ""))
end

ensureFolder = function(folderPath: string)
    if makefolder and not isfolder(folderPath) then
        pcall(makefolder, folderPath)
    end
end

local function ensureParentFolder(filePath: string)
    local folderPath = filePath:match("^(.*)/[^/]+$")
    if folderPath and folderPath ~= "" then
        ensureFolder(folderPath)
    end
end

--==============================================================================
--==============================================================================
-- Junkie SDK Integration & Key Management (Cloud Instance)
--==============================================================================
local cachedJunkieSDK: any = nil

local function getJunkieSDK(): any
    if cachedJunkieSDK then return cachedJunkieSDK end
    local sdkChunk = readLocalFile("JunkieSDK.lua", {
    })
    if not sdkChunk or #sdkChunk == 0 then
        sdkChunk = safeHttpGet("https://jnkie.com/sdk/library.lua", 3)
    end
    if not sdkChunk then return nil end
    local success, junkie = pcall(function()
        return loadstring(sdkChunk)()
    end)
    if success and type(junkie) == "table" then
        junkie.service = "[ATF]"
        junkie.identifier = "1083049"
        junkie.provider = "[ATF]"
        cachedJunkieSDK = junkie
        return junkie
    end
    return nil
end
local fileSystemSupported = (function()
    local okWrite, hasWrite = pcall(function() return type(writefile) == "function" end)
    local okRead, hasRead = pcall(function() return type(readfile) == "function" end)
    local okIs, hasIs = pcall(function() return type(isfile) == "function" end)
    local okDel, hasDel = pcall(function() return type(delfile) == "function" end)
    return okWrite and hasWrite and okRead and hasRead and okIs and hasIs and okDel and hasDel
end)()

local function loadVerifiedKey(): string?
    if not fileSystemSupported then return nil end
    local ok, content = pcall(function()
        if isfile and isfile(VERIFIED_KEY_FILE) then
            return readfile(VERIFIED_KEY_FILE)
        elseif isfile and isfile("[AT]/verified_key.txt") then
            return readfile("[AT]/verified_key.txt")
        elseif isfile and isfile("verified_key.txt") then
            return readfile("verified_key.txt")
        end
        return nil
    end)
    if ok and content and content ~= "" then
        return (content:gsub("^%s*(.-)%s*$", "%1"))
    end
    return nil
end

local function saveVerifiedKey(key: string): boolean
    if not fileSystemSupported then return false end
    ensureFolder(CONFIG_FOLDER)
    local ok = pcall(function() writefile(VERIFIED_KEY_FILE, key) end)
    return ok
end

local isPremiumUser = false
local isKeyUser = false

pcall(function()
    local savedKey = loadVerifiedKey()
    local keyToCheck = savedKey or Globals.SCRIPT_KEY

    -- If no key exists, automatically run Keyless Mode
    if not keyToCheck or keyToCheck == "" or keyToCheck == "No Key Found" then
        Globals.PreferredAccessTier = "Keyless"
        Globals.IS_JD_PREMIUM = false
        isPremiumUser = false
        isKeyUser = false
        return
    end

    local checkKeyOnce = function(): (boolean, boolean)
        local Junkie = getJunkieSDK()
        if not Junkie then return false, false end

        local success, result = pcall(function()
            return Junkie.check_key(keyToCheck)
        end)

        if success and result and (result.valid == true) then
            saveVerifiedKey(keyToCheck)
            Globals.SCRIPT_KEY = keyToCheck
            Globals.IS_JD_PREMIUM = (result.is_premium == true or result.premium == true)
            Globals.JD_EXPIRES_AT = result.expires_at or result.expiresAt
            isKeyUser = true
            isPremiumUser = (Globals.IS_JD_PREMIUM == true)
            Globals.PreferredAccessTier = isPremiumUser and "Premium" or "Key"
            return true, isPremiumUser
        end
        return false, false
    end

    -- Fast single check for instant startup:
    -- If key exists and is valid -> Standard Mode (or Premium Mode if premium key)
    -- If key is expired or invalid -> automatically switch to Keyless Mode!
    local ok, isPrem = checkKeyOnce()
    if ok then
        isKeyUser = true
        isPremiumUser = (Globals.IS_JD_PREMIUM == true)
        Globals.PreferredAccessTier = isPremiumUser and "Premium" or "Key"
    else
        -- Key is expired or invalid -> automatically switch to Keyless Mode!
        Globals.PreferredAccessTier = "Keyless"
        Globals.IS_JD_PREMIUM = false
        isPremiumUser = false
        isKeyUser = false

        -- Non-blocking background retry in case network was temporarily slow on startup
        task.spawn(function()
            for attempt = 1, 3 do
                task.wait(2)
                if not isRunning then break end
                local retryOk, retryPrem = checkKeyOnce()
                if retryOk then
                    isKeyUser = true
                    isPremiumUser = (retryPrem == true)
                    Globals.PreferredAccessTier = isPremiumUser and "Premium" or "Key"
                    if UI and UI.Window and typeof(UI.Window.Notify) == "function" then
                        UI.Window:Notify({
                            Title = "Key Validated",
                            Desc = isPremiumUser and "Premium status unlocked in background!" or "Standard Key Mode unlocked in background! (Farms current trial over and over)",
                            Duration = 3,
                        })
                    end
                    task.defer(function()
                        pcall(function() if UI.ScreenGui then UI.ScreenGui:Destroy() end end)
                        task.wait(0.1)
                        pcall(function()
                            if setthreadidentity then pcall(setthreadidentity, 8) end
                            buildInterface()
                        end)
                    end)
                    break
                end
            end
        end)
    end
end)

local function getSavedKey(): string
    local key = loadVerifiedKey()
    return key or "No Key Found"
end

local function checkRuntimeKeyExpiration(): boolean
    if not isKeyUser and not isPremiumUser then return false end
    local expiresAt = Globals.JD_EXPIRES_AT
    if expiresAt and type(expiresAt) == "number" and expiresAt > 0 then
        if os.time() >= expiresAt then
            isKeyUser = false
            isPremiumUser = false
            Globals.IS_JD_PREMIUM = false
            Globals.PreferredAccessTier = "Keyless"
            logActivity("Key license expired -> automatically switched to Keyless Mode.", "warn")
            if UI and UI.Window and typeof(UI.Window.Notify) == "function" then
                UI.Window:Notify({
                    Title = "License Expired",
                    Desc = "Your key has expired. Automatically switched to Keyless Mode (farming unowned trials only).",
                    Duration = 6,
                    Type = "warning"
                })
            end
            task.defer(function()
                pcall(function() if UI.ScreenGui then UI.ScreenGui:Destroy() end end)
                task.wait(0.1)
                pcall(function()
                    if setthreadidentity then pcall(setthreadidentity, 8) end
                    buildInterface()
                end)
            end)
            return true
        end
    end
    return false
end

local function formatTimeRemaining(): string
    local expiresAt = Globals.JD_EXPIRES_AT
    if not expiresAt or type(expiresAt) ~= "number" then
        return "Permanent / N/A"
    end

    local diff = expiresAt - os.time()
    if diff <= 0 then
        if isKeyUser or isPremiumUser then
            checkRuntimeKeyExpiration()
        end
        return "Expired (Switched to Keyless)"
    end

    local days = math.floor(diff / 86400)
    local hours = math.floor((diff % 86400) / 3600)
    local minutes = math.floor((diff % 3600) / 60)
    local seconds = diff % 60

    if days > 0 then
        return string.format("%dd %dh %dm", days, hours, minutes)
    elseif hours > 0 then
        return string.format("%dh %dm %ds", hours, minutes, seconds)
    else
        return string.format("%dm %ds", minutes, seconds)
    end
end


--==============================================================================
--==============================================================================
-- Remote Strategy & Match Configuration Loader (Cloud Loadstring)
--==============================================================================
isPremiumUser = (Globals.IS_JD_PREMIUM == true)

local function loadConfigRequirements(): any
    local urls = {
        "https://raw.githubusercontent.com/Atxvy/AutoTrials/refs/heads/main/PremConfig.lua?nocache=" .. tick(),
    }
    for _, url in ipairs(urls) do
        local chunk = safeHttpGet(url, 3)
        if chunk and type(chunk) == "string" and #chunk > 0 then
            local success, req = pcall(function()
                local fn, compileErr = loadstring(chunk)
                if not fn then error(compileErr) end
                return fn()
            end)
            if success and type(req) == "table" then
                return req
            end
        end
    end

    local allowedPaths = {
        "[STAY]/Multiplayer/PremConfigs.lua",
        "[STAY]\\Multiplayer\\PremConfigs.lua",
        "Multiplayer/PremConfigs.lua",
        "PremConfigs.lua",
        "[STAY]/[AutoTrailsFInal]/FinalVersion/files/PremConfigs.lua",
        "[STAY]/[AutoTrailsFInal]/files/PremConfigs.lua",
        "files/PremConfigs.lua",
    }
    for _, path in ipairs(allowedPaths) do
        local ok, content = pcall(function()
            if isfile and isfile(path) and readfile then
                return readfile(path)
            end
            return nil
        end)
        if ok and type(content) == "string" and #content > 0 then
            local s, req = pcall(function()
                local fn, err = loadstring(content)
                if not fn then error(err) end
                return fn()
            end)
            if s and type(req) == "table" then return req end
        end
    end

    return {
        trialScripts = {},
        trialConfigs = {},
        allTrialOptions = {},
        fallbackModesList = {},
        fallbackConfigs = {},
        CrateConfigs = {},
        AutoEvoConfigs = {},
    }
end
local Requirements = loadConfigRequirements()
local RevampAutoTrials = Requirements.RevampAutoTrials
if type(RevampAutoTrials) ~= "table" or next(RevampAutoTrials) == nil then
    RevampAutoTrials = Requirements.trialConfigs or {}
end
local allTrialOptions = Requirements.allTrialOptions or {}
local fallbackModesList = Requirements.fallbackModesList or {}
local FallbackConfigs = Requirements.RevampedFallbackConfigs or Requirements.FallbackConfigs or Requirements.fallbackConfigs or {}
local CrateConfigs = Requirements.CrateConfigs or {}
local AutoEvoConfigs = Requirements.AutoEvoConfigs or (getgenv and getgenv().AutoEvoConfigs) or (shared and shared.AutoEvoConfigs) or {}

-- Forward Declarations for Priority & Fallback System
local isCoinTowersMaxed: (() -> boolean)? = nil
local isGemTowersMaxed: (() -> boolean)? = nil
local isEvoTowersMaxed: (() -> boolean)? = nil
local isGoldenSkinsMaxed: (() -> boolean)? = nil
local isSkillTreeMaxed: (() -> boolean)? = nil
local areSelectedPrioritiesMaxed: (() -> boolean)? = nil
local checkIsEverythingMaxed: (() -> boolean)? = nil
local resolveCoinFarmFallback: (() -> string)? = nil

-- Dynamic Fallback Registration (syncs Lose strat gems from PremConfig to FallbackConfigs)
local function ensureDynamicHardcoreFallback()
    if not FallbackConfigs then FallbackConfigs = {} end
    local gemsLose = (CrateConfigs and CrateConfigs.Gems and CrateConfigs.Gems.Lose)
        or (Requirements and Requirements.CrateConfigs and Requirements.CrateConfigs.Gems and Requirements.CrateConfigs.Gems.Lose)
    if gemsLose then
        FallbackConfigs["Hardcore"] = {
            Level = gemsLose.Level or 50,
            Mode = gemsLose.Mode or "hardcore",
            Towers = gemsLose.Towers or {"Farm", "Boomerang", "Crook Boss"},
            Golden = gemsLose.Golden or {},
            SkillTree = gemsLose.SkillTree or {},
            Maps = gemsLose.Maps or {"Wretched Front"},
            Scripts = gemsLose.Scripts or {
                ["Wretched Front"] = "https://raw.githubusercontent.com/Atxvy/Main/refs/heads/main/Currency/Gems/Lose/WretchedFront.lua",
            },
        }
    end

    if not fallbackModesList or #fallbackModesList == 0 then
        fallbackModesList = { "Smart Auto", "Hardcore", "Fallen", "Molten" }
    else
        local hasHc = false
        for _, m in ipairs(fallbackModesList) do
            if m == "Hardcore" then hasHc = true; break end
        end
        if not hasHc then
            table.insert(fallbackModesList, 2, "Hardcore")
        end
    end
end
ensureDynamicHardcoreFallback()

local TowerList = Requirements.TowerList or {
    ["Coins"] = {
        { Name = "Scout", Cost = 0, LevelReq = 0 },
        { Name = "Sniper", Cost = 50, LevelReq = 0 },
        { Name = "Paintballer", Cost = 100, LevelReq = 0 },
        { Name = "Demoman", Cost = 200, LevelReq = 0 },
        { Name = "Boomerang", Cost = 300, LevelReq = 0 },
        { Name = "Slime Trooper", Cost = 300, LevelReq = 0 },
        { Name = "Soldier", Cost = 350, LevelReq = 0 },
        { Name = "Freezer", Cost = 650, LevelReq = 0 },
        { Name = "Militant", Cost = 800, LevelReq = 0 },
        { Name = "Assassin", Cost = 800, LevelReq = 0 },
        { Name = "Shotgunner", Cost = 850, LevelReq = 0 },
        { Name = "Hunter", Cost = 1000, LevelReq = 0 },
        { Name = "Pyromancer", Cost = 1250, LevelReq = 0 },
        { Name = "Ace Pilot", Cost = 1500, LevelReq = 0 },
        { Name = "Farm", Cost = 2000, LevelReq = 0 },
        { Name = "Medic", Cost = 2000, LevelReq = 0 },
        { Name = "Rocketeer", Cost = 2500, LevelReq = 0 },
        { Name = "Electroshocker", Cost = 2500, LevelReq = 0 },
        { Name = "Trapper", Cost = 3000, LevelReq = 0 },
        { Name = "Pulse Trooper", Cost = 3250, LevelReq = 0 },
        { Name = "Commander", Cost = 4000, LevelReq = 0 },
        { Name = "Military Base", Cost = 4000, LevelReq = 0 },
        { Name = "DJ Booth", Cost = 5000, LevelReq = 0 },
        { Name = "Tesla", Cost = 6000, LevelReq = 0 },
        { Name = "Minigunner", Cost = 8000, LevelReq = 0 },
        { Name = "Ranger", Cost = 12000, LevelReq = 0 },
        { Name = "Pursuit", Cost = 15000, LevelReq = 100 },
        { Name = "Gatling Gun", Cost = 35000, LevelReq = 175 },
    },
    ["Claim"] = {
        { Name = "Crook Boss", LevelReq = 30, Cost = 0 },
        { Name = "Turret", LevelReq = 50, Cost = 0 },
        { Name = "Mortar", LevelReq = 75, Cost = 0 },
        { Name = "Mercenary Base", LevelReq = 150, Cost = 0 },
    },
    ["Gems"] = {
        { Name = "Brawler", Cost = 1250, LevelReq = 25 },
        { Name = "Necromancer", Cost = 2250, LevelReq = 40 },
        { Name = "Accelerator", Cost = 2500, LevelReq = 50 },
        { Name = "Engineer", Cost = 4500, LevelReq = 70 },
        { Name = "Hacker", Cost = 5500, LevelReq = 80 },
    },
    ["Evo"] = {
        { Name = "EvolvedOperator", Coins = 15000, Gems = 4500 },
        { Name = "EvolvedEnforcer", Coins = 15000, Gems = 5000 },
        { Name = "EvolvedKingpin", Coins = 15000, Gems = 5500 },
        { Name = "EvolvedJuggernaut", Coins = 15000, Gems = 6000 },
    },
    ["Golden"] = {
        { Name = "Golden Scout", Cost = 50000 },
        { Name = "Golden Demoman", Cost = 50000 },
        { Name = "Golden Soldier", Cost = 50000 },
        { Name = "Golden Pyromancer", Cost = 50000 },
        { Name = "Golden Crook Boss", Cost = 50000 },
        { Name = "Golden Minigunner", Cost = 50000 },
        { Name = "Golden Cowboy", Cost = 50000 },
    },
}

local ClaimTowers = {
    ["Crook Boss"] = { Name = "Crook Boss", LevelReq = 30, Cost = 0 },
    ["Turret"] = { Name = "Turret", LevelReq = 50, Cost = 0 },
    ["Mortar"] = { Name = "Mortar", LevelReq = 75, Cost = 0 },
    ["Mercenary Base"] = { Name = "Mercenary Base", LevelReq = 150, Cost = 0 },
}

local LevelCoinTowers = {
    ["Pursuit"] = { Name = "Pursuit", LevelReq = 100, Cost = 15000 },
    ["Gatling Gun"] = { Name = "Gatling Gun", LevelReq = 175, Cost = 35000 },
}

local function getTowerClassification(rawName: string)
    local clean = normalizeString(rawName)
    if clean == "crookboss" or clean == "croockboos" or clean == "croockboss" then
        return { Type = "Claim", CanonicalName = "Crook Boss", LevelReq = 30, Cost = 0, Currency = "Coins" }
    elseif clean == "turret" then
        return { Type = "Claim", CanonicalName = "Turret", LevelReq = 50, Cost = 0, Currency = "Coins" }
    elseif clean == "mortar" then
        return { Type = "Claim", CanonicalName = "Mortar", LevelReq = 75, Cost = 0, Currency = "Coins" }
    elseif clean == "mercenarybase" or clean == "mercnerarybase" then
        return { Type = "Claim", CanonicalName = "Mercenary Base", LevelReq = 150, Cost = 0, Currency = "Coins" }
    end

    if clean == "pursuit" then
        return { Type = "LevelCoins", CanonicalName = "Pursuit", LevelReq = 100, Cost = 15000, Currency = "Coins" }
    elseif clean == "gatlinggun" or clean == "gatling" then
        return { Type = "LevelCoins", CanonicalName = "Gatling Gun", LevelReq = 175, Cost = 35000, Currency = "Coins" }
    end

    if clean == "brawler" then
        return { Type = "Gems", CanonicalName = "Brawler", LevelReq = 25, Cost = 1250, Currency = "Gems" }
    elseif clean == "necromancer" then
        return { Type = "Gems", CanonicalName = "Necromancer", LevelReq = 40, Cost = 2250, Currency = "Gems" }
    elseif clean == "accelerator" then
        return { Type = "Gems", CanonicalName = "Accelerator", LevelReq = 50, Cost = 2500, Currency = "Gems" }
    elseif clean == "engineer" then
        return { Type = "Gems", CanonicalName = "Engineer", LevelReq = 70, Cost = 4500, Currency = "Gems" }
    elseif clean == "hacker" then
        return { Type = "Gems", CanonicalName = "Hacker", LevelReq = 80, Cost = 5500, Currency = "Gems" }
    end

    if string.find(clean, "golden") then
        return { Type = "Golden", CanonicalName = rawName, Cost = 50000, Currency = "Coins", LevelReq = 0 }
    end

    if TowerList and TowerList.Coins then
        for _, t in ipairs(TowerList.Coins) do
            if normalizeString(t.Name) == clean then
                return { Type = "Coins", CanonicalName = t.Name, Cost = t.Cost or 0, LevelReq = t.LevelReq or 0, Currency = "Coins" }
            end
        end
    end

    return { Type = "Coins", CanonicalName = rawName, Cost = 0, LevelReq = 0, Currency = "Coins" }
end

local function tryClaimRewardsAndTowers()
    if game.PlaceId ~= LOBBY_PLACE_ID then return end
    local pLevel = 0
    pcall(function()
        if PlayerDataHandler and typeof(PlayerDataHandler.GetLevel) == "function" then
            pLevel = PlayerDataHandler:GetLevel() or 0
        end
    end)
    local rf = ReplicatedStorage:FindFirstChild("RemoteFunction")
    if not (rf and rf:IsA("RemoteFunction")) then return end

    pcall(function() rf:InvokeServer("LevelRewards", "ClaimAll") end)
    pcall(function() rf:InvokeServer("Rewards", "ClaimAll") end)
    pcall(function() rf:InvokeServer("LogBook", "ClaimAll") end)

    local claimDefs = {
        { Name = "Crook Boss", LevelReq = 30 },
        { Name = "Turret", LevelReq = 50 },
        { Name = "Mortar", LevelReq = 75 },
        { Name = "Mercenary Base", LevelReq = 150 },
    }
    for _, ct in ipairs(claimDefs) do
        local isOwned = false
        pcall(function()
            if PlayerDataHandler and typeof(PlayerDataHandler.IsTowerOwned) == "function" then
                isOwned = PlayerDataHandler:IsTowerOwned(ct.Name)
            end
        end)
        if not isOwned and pLevel >= ct.LevelReq then
            pcall(function() rf:InvokeServer("LevelRewards", "Claim", ct.Name) end)
            pcall(function() rf:InvokeServer("Rewards", "Claim", ct.Name) end)
            task.wait(0.3)
            pcall(function()
                if PlayerDataHandler and typeof(PlayerDataHandler.GetTowers) == "function" then
                    PlayerDataHandler:GetTowers()
                end
            end)
            local ownedAfter = false
            pcall(function()
                if PlayerDataHandler and typeof(PlayerDataHandler.IsTowerOwned) == "function" then
                    ownedAfter = PlayerDataHandler:IsTowerOwned(ct.Name)
                end
            end)
            if ownedAfter then
                logActivity(string.format("[Auto Claim] Successfully claimed reward tower '%s' (Level %d Reached)!", ct.Name, ct.LevelReq), "success")
                if UI and UI.Window and typeof(UI.Window.Notify) == "function" then
                    UI.Window:Notify({
                        Title = "Tower Unlocked",
                        Desc = string.format("Unlocked %s (Level %d Reward)!", ct.Name, ct.LevelReq),
                        Duration = 5,
                        Type = "success"
                    })
                end
            end
        end
    end
end

local EvoData = {
    ["Scout"] = { Evo = "EvolvedOperator", Coins = 15000, Gems = 4500 },
    ["Shotgunner"] = { Evo = "EvolvedEnforcer", Coins = 15000, Gems = 5000 },
    ["Crook Boss"] = { Evo = "EvolvedKingpin", Coins = 15000, Gems = 5500 },
    ["Minigunner"] = { Evo = "EvolvedJuggernaut", Coins = 15000, Gems = 6000 }
}

local EvoToTower = {
    ["EvolvedOperator"] = "Scout",
    ["EvolvedEnforcer"] = "Shotgunner",
    ["EvolvedKingpin"] = "Crook Boss",
    ["EvolvedJuggernaut"] = "Minigunner"
}

--==============================================================================
-- Settings Persistence System (Debounced to prevent disk thrashing)
--==============================================================================
local DefaultSettings = {
    AutoSkip = false,
    AutoRestart = true,
    AutoTrials = false,
    AutoGold = false,
    AutoEvo = false,
    TargetEvo = "All",
    EvoStrat = "Lose",
    CurrentEvoFarmType = "Coins",
    CurrentEvoGrindState = "Grinding coins...",
    CurrentEvoActiveTower = "Scout",
    Target = 1,
    Strat = "Lose",
    AutoFarmType = "Coins",
    SelectedTrials = { "Fog" },
    SelectedFallback = "Smart Auto",
    TrialFarmMode = "Farm Mode",
    FarmOnly = "Disabled",
    MultiplayerEnabled = false,
    MultiplayerMode = "Trial Mode",
    MultiplayerFarmStrategy = "Molten",
    MultiplayerSelectedTrial = "Current Rotation",
    MultiplayerRole = "Host",
    MultiplayerIsHost = false,
    MultiplayerHostIdentifier = "",
    MultiplayerTargetP2 = "",
    MultiplayerIsP2 = false,
    MultiplayerTargetHost = "",
    PrivateServerCode = "",
    LobbyWatcherEnabled = true,
    PreferredAccessTier = "Keyless",
    BuyMissingCoinsTower = false,
    BuyMissingGemTower = false,
    BuyMissingEvoTower = false,
    BuyMissingGoldSkins = false,
    BuySkillTree = false,
    PrivateCode = "",
    AutoReloadGatling = false,
    GatlingReloadPercent = 100,
    AutoGatling = true,
    SelectedGatling = "Gatlify",
    TimeScaleEnabled = false,
    TimeScaleValue = 2,
    TargetCoins = 0,
    TargetGems = 0,
    WebhookURL = "",
    AutoSkins = false,
    TargetCrate = "Basic Crate",
    TargetSkin = "Any",
    AutoSpecial = false,
    TargetSpecialMode = "Badlands II",
    MobileBoost = false,
}

local saveDebounceTimer: thread? = nil

local function SaveSettings(immediate: boolean?)
    local function executeSave()
        ensureFolder(CONFIG_FOLDER)
        ensureParentFolder(SETTINGS_FILE)
        local dataToSave = {}
        for key in pairs(DefaultSettings) do
            dataToSave[key] = Globals[key]
        end
        if writefile and HttpService then
            pcall(function()
                writefile(SETTINGS_FILE, HttpService:JSONEncode(dataToSave))
            end)
        end
    end

    if immediate then
        if saveDebounceTimer then
            task.cancel(saveDebounceTimer)
            saveDebounceTimer = nil
        end
        executeSave()
    else
        if saveDebounceTimer then
            task.cancel(saveDebounceTimer)
        end
        saveDebounceTimer = task.delay(0.5, function()
            saveDebounceTimer = nil
            executeSave()
        end)
    end
end

local function LoadSettings()
    ensureFolder(CONFIG_FOLDER)
    local data = {}
    local targetPath = isfile and isfile(SETTINGS_FILE) and SETTINGS_FILE or nil
    if not targetPath and isfile then
        if isfile("[AT]/" .. SETTINGS_FILE_NAME) then
            targetPath = "[AT]/" .. SETTINGS_FILE_NAME
        elseif isfile("ServiceHub/" .. SETTINGS_FILE_NAME) then
            targetPath = "ServiceHub/" .. SETTINGS_FILE_NAME
        end
    end

    if targetPath then
        local success, content = pcall(readfile, targetPath)
        if success and content and content ~= "" then
            pcall(function()
                data = HttpService:JSONDecode(content)
            end)
        end
    end

    for key, defaultVal in pairs(DefaultSettings) do
        if data[key] ~= nil then
            Globals[key] = data[key]
        elseif Globals[key] == nil then
            Globals[key] = defaultVal
        end
    end

    -- Backward compatibility for settings saved before Owned Mode was renamed.
    if Globals.TrialFarmMode == "Owned Mode" then
        Globals.TrialFarmMode = "Progression Mode"
    end

    -- Synchronize MultiplayerTargetP2 and MultiplayerHostIdentifier for backward compatibility
    if (not Globals.MultiplayerTargetP2 or Globals.MultiplayerTargetP2 == "") and (Globals.MultiplayerHostIdentifier and Globals.MultiplayerHostIdentifier ~= "") then
        Globals.MultiplayerTargetP2 = Globals.MultiplayerHostIdentifier
    elseif (Globals.MultiplayerTargetP2 and Globals.MultiplayerTargetP2 ~= "") and (not Globals.MultiplayerHostIdentifier or Globals.MultiplayerHostIdentifier == "") then
        Globals.MultiplayerHostIdentifier = Globals.MultiplayerTargetP2
    end

    -- Synchronize PrivateServerCode and PrivateCode
    if (not Globals.PrivateServerCode or Globals.PrivateServerCode == "") and (Globals.PrivateCode and Globals.PrivateCode ~= "") then
        Globals.PrivateServerCode = Globals.PrivateCode
    elseif (Globals.PrivateServerCode and Globals.PrivateServerCode ~= "") and (not Globals.PrivateCode or Globals.PrivateCode == "") then
        Globals.PrivateCode = Globals.PrivateServerCode
    end

    -- Role Assignment based strictly on user configuration and textboxes (no hardcoded names)
    if Globals.MultiplayerIsHost and Globals.MultiplayerIsP2 then
        Globals.MultiplayerIsP2 = false
    elseif not Globals.MultiplayerIsHost and not Globals.MultiplayerIsP2 then
        if Globals.MultiplayerTargetHost and #Globals.MultiplayerTargetHost > 0 then
            Globals.MultiplayerIsP2 = true
        elseif Globals.MultiplayerTargetP2 and #Globals.MultiplayerTargetP2 > 0 then
            Globals.MultiplayerIsHost = true
        end
    end

    if Globals.MultiplayerMode == nil or Globals.MultiplayerMode == "" then
        Globals.MultiplayerMode = "Trial Mode"
    end
    if Globals.MultiplayerFarmStrategy == nil or Globals.MultiplayerFarmStrategy == "" then
        Globals.MultiplayerFarmStrategy = "Molten"
    end
    if Globals.MultiplayerSelectedTrial == nil or Globals.MultiplayerSelectedTrial == "" then
        Globals.MultiplayerSelectedTrial = "Current Rotation"
    end

    if Globals.AutoEvo == nil then
        Globals.AutoEvo = false
    end
    if not Globals.TargetEvo or Globals.TargetEvo == "" then
        Globals.TargetEvo = "All"
    end
    if not Globals.EvoStrat or Globals.EvoStrat == "" then
        Globals.EvoStrat = "Lose"
    end

    if not Globals.AutoTrials then
        Globals.AutoGold = false
    end

    SaveSettings(true)
end

LoadSettings()

-- Saved configurations in .json are strictly preserved across sessions (even if Premium expires).
-- Server / runtime checks (isPremiumUser) prevent unauthorized triggers without wiping the user's saved .json file.

--==============================================================================
-- Helper: Dynamically resolve Player instance by Username, DisplayName, or UserId
--==============================================================================
local function GetPlayerFromIdentifier(identifier)
    if not identifier or identifier == "" then return nil end
    local clean = string.gsub(tostring(identifier), "%s+", "")
    if clean == "" then return nil end

    -- 1. Exact name match
    local p = Players:FindFirstChild(clean)
    if p and p:IsA("Player") then return p end

    -- 2. User ID match (if numeric)
    local uid = tonumber(clean)
    if uid then
        local pByUid = Players:GetPlayerByUserId(uid)
        if pByUid then return pByUid end
    end

    -- 3. Case-insensitive Name or DisplayName match
    local lower = string.lower(clean)
    for _, plr in ipairs(Players:GetPlayers()) do
        if string.lower(plr.Name) == lower or (plr.DisplayName and string.lower(plr.DisplayName) == lower) then
            return plr
        end
    end

    return nil
end

--==============================================================================
-- Local Multiplayer, Party Formation & Private Server Watcher System
-- Operates directly locally on Roblox client APIs without WebSockets
--==============================================================================
local function extractPrivateCode(input)
    if not input or input == "" then return "" end
    local str = tostring(input):gsub("^%s*(.-)%s*$", "%1")
    local codeMatch = str:match("[?&]code=([%w%-]+)")
    if codeMatch then return codeMatch end
    local linkMatch = str:match("privateServerLinkCode=([%w%-]+)")
    if linkMatch then return linkMatch end
    return str
end

local function teleportToPrivateServer(code)
    local clean = extractPrivateCode(code)
    if clean == "" then return false end

    -- 1. Try ExperienceService (standard Windows client)
    local expService = game:GetService("ExperienceService")
    if expService then
        local ok = pcall(function()
            expService:LaunchExperience({
                placeId = LOBBY_PLACE_ID,
                linkCode = clean
            })
        end)
        if ok then return true end
    end

    -- 2. Try TeleportService Private Server
    local ts = game:GetService("TeleportService")
    local ok1 = pcall(function()
        ts:TeleportToPrivateServer(LOBBY_PLACE_ID, clean, { Players.LocalPlayer })
    end)
    if ok1 then return true end

    -- 3. Try TeleportToPlaceInstance
    local ok2 = pcall(function()
        ts:TeleportToPlaceInstance(LOBBY_PLACE_ID, clean, Players.LocalPlayer)
    end)
    return ok2
end

local LocalPartyManager = {
    InPartyWith = {},
    PartyStatusText = "No Party",
    PeerStatusText = "Checking server...",
    WatcherStatusText = "Idle",
    LastInviteAttempt = 0,
    LastAcceptAttempt = 0,
    LastWatcherCheck = 0,
}

function LocalPartyManager:SetPartyStatus(text)
    self.PartyStatusText = text
    if UI and UI.MultiplayerPartyStatusLabel then
        pcall(function() UI.MultiplayerPartyStatusLabel:SetDesc(text) end)
    end
end

function LocalPartyManager:SetPeerStatus(text)
    self.PeerStatusText = text
    if UI and UI.MultiplayerPeerPresenceLabel then
        pcall(function() UI.MultiplayerPeerPresenceLabel:SetDesc(text) end)
    end
end

function LocalPartyManager:SetWatcherStatus(text)
    self.WatcherStatusText = text
    if UI and UI.MultiplayerWatcherStatusLabel then
        pcall(function() UI.MultiplayerWatcherStatusLabel:SetDesc(text) end)
    end
end

local function isPlayerInPartyList(partyPlayers, targetPlayer)
    if type(partyPlayers) ~= "table" or not targetPlayer then return false end
    local targetName = (typeof(targetPlayer) == "Instance" and targetPlayer.Name) or tostring(targetPlayer)
    for _, p in ipairs(partyPlayers) do
        if p == targetPlayer then return true end
        if typeof(p) == "Instance" and string.lower(p.Name) == string.lower(targetName) then
            return true
        end
        if type(p) == "string" and string.lower(p) == string.lower(targetName) then
            return true
        end
    end
    return false
end

function LocalPartyManager:CreateAndInvite(targetIdentifier)
    if not targetIdentifier or targetIdentifier == "" then return false end
    local p2Obj = GetPlayerFromIdentifier(targetIdentifier)
    if not p2Obj then
        self:SetPeerStatus(string.format("P2 '%s' not in this lobby", targetIdentifier))
        self.InPartyWith[tostring(targetIdentifier)] = nil
        return false
    end

    self:SetPeerStatus(string.format("P2 '%s' is present in this lobby", p2Obj.Name))

    local rf = ReplicatedStorage:FindFirstChild("RemoteFunction")
    if rf and rf:IsA("RemoteFunction") then
        pcall(function() rf:InvokeServer("Party", "CreateParty", nil) end)
        task.wait(0.1)
        local ok, res = pcall(function()
            return rf:InvokeServer("Party", "InvitePlayer", p2Obj)
        end)

        if ok and type(res) == "table" then
            local partyData = res.party
            local playersInParty = partyData and partyData.players
            local invitedList = partyData and partyData.invited

            if isPlayerInPartyList(playersInParty, p2Obj) then
                self.InPartyWith[p2Obj.Name] = true
                self:SetPartyStatus(string.format("In Party with %s (Accepted)", p2Obj.Name))
                print(string.format("[Local Multiplayer] P2 %s has ACCEPTED party invite!", p2Obj.Name))
                return true
            elseif isPlayerInPartyList(invitedList, p2Obj) then
                self.InPartyWith[p2Obj.Name] = false
                self:SetPartyStatus(string.format("Invited %s (Waiting for accept...)", p2Obj.Name))
                print(string.format("[Local Multiplayer] Host invited %s; waiting for acceptance", p2Obj.Name))
                return false
            end
        end
    end
    return false
end

function LocalPartyManager:AcceptInviteFrom(hostIdentifier)
    if not hostIdentifier or hostIdentifier == "" then return false end
    local hostObj = GetPlayerFromIdentifier(hostIdentifier)
    if not hostObj then
        self:SetPeerStatus(string.format("Host '%s' not in this lobby", hostIdentifier))
        self.InPartyWith[tostring(hostIdentifier)] = nil
        return false
    end

    self:SetPeerStatus(string.format("Host '%s' is present in this lobby", hostObj.Name))

    local rf = ReplicatedStorage:FindFirstChild("RemoteFunction")
    if rf and rf:IsA("RemoteFunction") then
        local ok, res = pcall(function()
            return rf:InvokeServer("Party", "AcceptInvite", hostObj)
        end)

        if ok and type(res) == "table" then
            local partyData = res.party
            local playersInParty = partyData and partyData.players

            if res.success == true and isPlayerInPartyList(playersInParty, hostObj) and isPlayerInPartyList(playersInParty, Players.LocalPlayer) then
                self.InPartyWith[hostObj.Name] = true
                self:SetPartyStatus("In Party with " .. hostObj.Name)
                print(string.format("[Local Multiplayer] P2 accepted party invite from Host %s!", hostObj.Name))
                return true
            else
                self.InPartyWith[hostObj.Name] = false
                self:SetPartyStatus(string.format("Waiting for invite from Host %s...", hostObj.Name))
            end
        end
    end
    return false
end

function LocalPartyManager:LeaveParty()
    local rf = ReplicatedStorage:FindFirstChild("RemoteFunction")
    if rf and rf:IsA("RemoteFunction") then
        pcall(function() rf:InvokeServer("Party", "LeaveParty") end)
    end
    self.InPartyWith = {}
    self:SetPartyStatus("No Party")
    print("[Local Multiplayer] Left party.")
end

-- Fast lobby party loop: keeps inviting / accepting until confirmed in party
task.spawn(function()
    while true do
        task.wait(1.5)
        if game.PlaceId == LOBBY_PLACE_ID and Globals.MultiplayerEnabled then
            if Globals.MultiplayerIsHost then
                local targetP2 = tostring(Globals.MultiplayerTargetP2 or Globals.MultiplayerHostIdentifier or ""):gsub("^%s*(.-)%s*$", "%1")
                if targetP2 ~= "" then
                    local p2Obj = GetPlayerFromIdentifier(targetP2)
                    if p2Obj then
                        if not LocalPartyManager.InPartyWith[p2Obj.Name] and (os.time() - LocalPartyManager.LastInviteAttempt >= 2) then
                            LocalPartyManager.LastInviteAttempt = os.time()
                            LocalPartyManager:CreateAndInvite(targetP2)
                        end
                    else
                        LocalPartyManager.InPartyWith[targetP2] = nil
                        LocalPartyManager:SetPeerStatus(string.format("P2 '%s' not found in lobby", targetP2))
                    end
                end
            elseif Globals.MultiplayerIsP2 then
                local targetHost = tostring(Globals.MultiplayerTargetHost or ""):gsub("^%s*(.-)%s*$", "%1")
                if targetHost ~= "" then
                    local hostObj = GetPlayerFromIdentifier(targetHost)
                    if hostObj then
                        if not LocalPartyManager.InPartyWith[hostObj.Name] and (os.time() - LocalPartyManager.LastAcceptAttempt >= 2) then
                            LocalPartyManager.LastAcceptAttempt = os.time()
                            LocalPartyManager:AcceptInviteFrom(targetHost)
                        end
                    else
                        LocalPartyManager.InPartyWith[targetHost] = nil
                        LocalPartyManager:SetPeerStatus(string.format("Host '%s' not found in lobby", targetHost))
                    end
                end
            end
        end
    end
end)

-- Early lobby loadout equip logic for Host & P2
local lastMultiplayerEquipAttempt = 0
local function ensureMultiplayerLobbyLoadout(): ()
    if game.PlaceId ~= LOBBY_PLACE_ID or not Globals.MultiplayerEnabled then return end

    local role = Globals.MultiplayerIsHost and "Host" or "P2"
    local mpMode = Globals.MultiplayerMode or "Trial Mode"
    local myReqTowers = nil

    if mpMode == "Trial Mode" then
        local mpConfig = Requirements and Requirements.MultiplayerConfig or (getgenv and getgenv().MultiplayerConfig) or {}
        local mpTrialMode = mpConfig.TrialMode or {}
        local trialName = nil
        if Globals.MultiplayerSelectedTrial and Globals.MultiplayerSelectedTrial ~= "" and Globals.MultiplayerSelectedTrial ~= "Current Rotation" and ((RevampAutoTrials and RevampAutoTrials[Globals.MultiplayerSelectedTrial]) or mpTrialMode[Globals.MultiplayerSelectedTrial] or mpTrialMode[Globals.MultiplayerSelectedTrial:gsub(" Enemies", "")]) then
            trialName = Globals.MultiplayerSelectedTrial
        else
            local analysis = (typeof(analyzeCurrentTrial) == "function") and analyzeCurrentTrial()
            trialName = analysis and analysis.trialName or "Speedy Enemies"
        end

        local trialEntry = mpTrialMode[trialName] or mpTrialMode[trialName:gsub(" Enemies", "")] or mpTrialMode[trialName .. " Enemies"] or mpTrialMode["Speedy Enemies"]

        if trialEntry and trialEntry.Towers then
            myReqTowers = trialEntry.Towers[role] or trialEntry.Towers[role:lower()]
        end
    elseif mpMode == "Farm Mode" then
        local farmStrat = Globals.MultiplayerFarmStrategy or "Molten"
        if farmStrat == "Smart Auto" and typeof(resolveSmartFallback) == "function" then
            farmStrat = resolveSmartFallback()
        end
        local fallbackModeConfig = FallbackConfigs and FallbackConfigs[farmStrat]
        if fallbackModeConfig and fallbackModeConfig.Towers then
            myReqTowers = fallbackModeConfig.Towers
        end
    end

    if myReqTowers and type(myReqTowers) == "table" and #myReqTowers > 0 then
        local currentlyEquipped = {}
        if PlayerDataHandler and typeof(PlayerDataHandler.GetEquippedTowers) == "function" then
            currentlyEquipped = PlayerDataHandler:GetEquippedTowers(LocalPlayer) or {}
        end

        local allEquipped = true
        if #currentlyEquipped < #myReqTowers then
            allEquipped = false
        else
            for _, reqName in ipairs(myReqTowers) do
                local found = false
                for _, eqName in ipairs(currentlyEquipped) do
                    if string.lower(tostring(eqName)) == string.lower(tostring(reqName)) then
                        found = true
                        break
                    end
                end
                if not found then
                    allEquipped = false
                    break
                end
            end
        end

        if not allEquipped and (os.time() - lastMultiplayerEquipAttempt >= 4) then
            lastMultiplayerEquipAttempt = os.time()
            if TDS and typeof(TDS.Loadout) == "function" then
                print(string.format("[Multiplayer Lobby] Equipping towers early for %s: %s", role, table.concat(myReqTowers, ", ")))
                pcall(function()
                    TDS:Loadout(unpack(myReqTowers))
                end)
                if PlayerDataHandler and typeof(PlayerDataHandler.SetPeerData) == "function" then
                    pcall(function()
                        PlayerDataHandler:SetPeerData(LocalPlayer.Name, {
                            Username = LocalPlayer.Name,
                            UserId = LocalPlayer.UserId,
                            equippedTowers = myReqTowers,
                            troops = myReqTowers
                        })
                    end)
                end
            end
        end
    end
end

-- 30-Second Private Server / In-Game Disconnect Watcher Loop
task.spawn(function()
    local missingSince = 0
    while true do
        task.wait(2)
        if Globals.MultiplayerEnabled and Globals.LobbyWatcherEnabled ~= false then
            local isLobby = (game.PlaceId == LOBBY_PLACE_ID)
            local pvCode = tostring(Globals.PrivateServerCode or Globals.PrivateCode or ""):gsub("^%s*(.-)%s*$", "%1")

            local targetFound = false
            local targetName = ""

            if Globals.MultiplayerIsHost then
                targetName = tostring(Globals.MultiplayerTargetP2 or Globals.MultiplayerHostIdentifier or ""):gsub("^%s*(.-)%s*$", "%1")
                if targetName ~= "" and GetPlayerFromIdentifier(targetName) then
                    targetFound = true
                end
            elseif Globals.MultiplayerIsP2 then
                targetName = tostring(Globals.MultiplayerTargetHost or ""):gsub("^%s*(.-)%s*$", "%1")
                if targetName ~= "" and GetPlayerFromIdentifier(targetName) then
                    targetFound = true
                end
            end

            if targetName ~= "" then
                if targetFound then
                    missingSince = 0
                    LocalPartyManager:SetWatcherStatus(string.format("Together with %s in %s", targetName, isLobby and "Lobby" or "Game"))
                else
                    if missingSince == 0 then
                        missingSince = os.time()
                    end

                    local elapsed = os.time() - missingSince
                    local remaining = math.max(0, 30 - elapsed)
                    LocalPartyManager:SetWatcherStatus(string.format("%s disconnected | %s in %ds", 
                        targetName, 
                        isLobby and "TP" or "Leave", 
                        remaining))

                    if elapsed >= 30 and (os.time() - LocalPartyManager.LastWatcherCheck >= 20) then
                        LocalPartyManager.LastWatcherCheck = os.time()
                        missingSince = os.time()
                        LocalPartyManager:SetWatcherStatus(isLobby and "Teleporting to Private Server..." or "Partner disconnected! Leaving match...")
                        print(string.format("[30s Watcher] %s %s for 30s. %s", 
                            targetName, 
                            isLobby and "missing from lobby" or "disconnected from match", 
                            pvCode ~= "" and ("Teleporting to private server: " .. pvCode) or "Returning to lobby"))

                        if isLobby then
                            if pvCode ~= "" then
                                teleportToPrivateServer(pvCode)
                            end
                        else
                            -- In-game disconnect handler: return to private server or lobby
                            if pvCode ~= "" then
                                local tpOk = teleportToPrivateServer(pvCode)
                                if not tpOk then
                                    SmartTeleportToLobby()
                                end
                            else
                                SmartTeleportToLobby()
                            end
                        end
                    end
                end
            else
                missingSince = 0
                LocalPartyManager:SetWatcherStatus("No target username configured")
            end
        else
            missingSince = 0
            if LocalPartyManager then
                LocalPartyManager:SetWatcherStatus("Watcher Idle (Multiplayer disabled)")
            end
        end
    end
end)

--==============================================================================
-- Timescale Handlers & Helper Functions
--==============================================================================
local CoerceTimeScaleValue: (val: any, fallback: number) -> number
local ApplyTimeScaleOnce: () -> ()
local StartTimeScale: () -> ()
do
    local TimeScaleValues = { 0.5, 1, 1.5, 2 }

    local function NormalizeTimeScaleValue(val: any): number?
        local num = tonumber(val)
        if not num then return nil end
        for _, v in ipairs(TimeScaleValues) do
            if v == num then return v end
        end
        return nil
    end

    CoerceTimeScaleValue = function(val: any, fallback: number): number
        return NormalizeTimeScaleValue(val) or fallback
    end

    local function GetTimescaleFrame(): GuiObject?
        local hotbar = PlayerGui:FindFirstChild("ReactUniversalHotbar")
        local frame = hotbar and hotbar:FindFirstChild("Frame")
        return frame and frame:FindFirstChild("timescale")
    end

    local function SetGameTimescale(targetVal: number)
        if game.PlaceId == LOBBY_PLACE_ID then return end

        local speedList = { 0, 0.5, 1, 1.5, 2 }
        local targetIdx = nil
        for i, v in ipairs(speedList) do
            if v == targetVal then
                targetIdx = i
                break
            end
        end
        if not targetIdx then return end

        local frame = GetTimescaleFrame()
        if not frame then return end

        local speedLabel = frame:FindFirstChild("Speed")
        if not (speedLabel and speedLabel:IsA("TextLabel")) then return end

        local currentVal = tonumber(speedLabel.Text:match("x([%d%.]+)"))
        if not currentVal then return end

        local currentIdx = nil
        for i, v in ipairs(speedList) do
            if v == currentVal then
                currentIdx = i
                break
            end
        end
        if not currentIdx or currentIdx == targetIdx then return end

        local diff = targetIdx - currentIdx
        if diff < 0 then
            diff = #speedList + diff
        end

        local rf = ReplicatedStorage:FindFirstChild("RemoteFunction")
        if not rf then return end

        for _ = 1, diff do
            pcall(function()
                rf:InvokeServer("TicketsManager", "CycleTimeScale")
            end)
            task.wait(0.5)
        end
    end

    local function UnlockSpeedTickets()
        if game.PlaceId == LOBBY_PLACE_ID then return end

        local tickets = LocalPlayer:FindFirstChild("TimescaleTickets")
        if tickets and tickets.Value >= 1 then
            local frame = GetTimescaleFrame()
            local lockIcon = frame and frame:FindFirstChild("Lock")

            if lockIcon and lockIcon.Visible then
                local rf = ReplicatedStorage:FindFirstChild("RemoteFunction")
                if rf then
                    pcall(function()
                        rf:InvokeServer("TicketsManager", "UnlockTimeScale")
                    end)
                    ----print(("[ServiceHub] Unlocked timescale tickets")
                end
            end
        else
            ----print(("[ServiceHub] No timescale tickets left")
        end
    end

    ApplyTimeScaleOnce = function()
        if not Globals.TimeScaleEnabled then return end

        local stateReplicators = ReplicatedStorage:FindFirstChild("StateReplicators")
        local gameStateReplicator = stateReplicators and stateReplicators:FindFirstChild("GameStateReplicator")
        if not gameStateReplicator or gameStateReplicator:GetAttribute("GameStarted") ~= true then return end

        local frame = GetTimescaleFrame()
        if not frame or not frame.Visible then return end

        local desired = CoerceTimeScaleValue(Globals.TimeScaleValue, 2)
        local lock = frame:FindFirstChild("Lock")

        if lock and lock.Visible then
            local tickets = LocalPlayer:FindFirstChild("TimescaleTickets")
            if tickets and tickets.Value < 1 then
                if not TimeScaleNoTicketsWarned then
                    ----print(("[ServiceHub] No timescale tickets left")
                    TimeScaleNoTicketsWarned = true
                end
                return
            end
            UnlockSpeedTickets()
            task.wait(0.4)
        else
            TimeScaleNoTicketsWarned = false
        end

        SetGameTimescale(desired)
    end

    StartTimeScale = function()
        if TimeScaleRunning or not Globals.TimeScaleEnabled then return end
        TimeScaleRunning = true

        task.spawn(function()
            while Globals.TimeScaleEnabled do
                if not isRunning then break end
                ApplyTimeScaleOnce()
                task.wait(3)
            end
            TimeScaleNoTicketsWarned = false
            TimeScaleRunning = false
        end)
    end
end

local isMatchConfigDirty: () -> boolean

local function SetSetting(name: string, value: any)
    if DefaultSettings[name] ~= nil then
        if name == "TimeScaleValue" then
            value = CoerceTimeScaleValue(value, Globals.TimeScaleValue or 2)
        end
        if Globals[name] == value then
            return
        end
        Globals[name] = value
        SaveSettings()

        if game.PlaceId ~= LOBBY_PLACE_ID and isMatchConfigDirty and isMatchConfigDirty() then
            if not Globals.IsConfigDirty then
                Globals.IsConfigDirty = true
                if UI and UI.Window and typeof(UI.Window.Notify) == "function" then
                    RunAsExecutor(function()
                        UI.Window:Notify({
                            Title = "CONFIG QUEUED",
                            Desc = "Change saved! Current match will finish before returning to lobby.",
                            Duration = 5,
                            Type = "info"
                        })
                    end)()
                end
            end
        end
    end
end

Globals.TimeScaleValue = CoerceTimeScaleValue(Globals.TimeScaleValue, 2)

--==============================================================================
-- State & Active Mode Persistence
--==============================================================================
local function saveTrialState(trialName: string)
    ensureFolder(CONFIG_FOLDER)
    ensureParentFolder(TRIAL_STATE_FILE)
    if writefile then
        pcall(writefile, TRIAL_STATE_FILE, trialName)
    end
end

local function loadTrialState(): string?
    local targetPath = (isfile and isfile(TRIAL_STATE_FILE)) and TRIAL_STATE_FILE or nil
    if not targetPath and isfile then
        if isfile("[ATF]/" .. TRIAL_STATE_FILE_NAME) then
            targetPath = "[ATF]/" .. TRIAL_STATE_FILE_NAME
        elseif isfile("[AT]/" .. TRIAL_STATE_FILE_NAME) then
            targetPath = "[AT]/" .. TRIAL_STATE_FILE_NAME
        elseif isfile("ServiceHub/" .. TRIAL_STATE_FILE_NAME) then
            targetPath = "ServiceHub/" .. TRIAL_STATE_FILE_NAME
        end
    end
    if targetPath and isfile and readfile then
        local ok, content = pcall(readfile, targetPath)
        if ok and content and content ~= "" then
            return content:gsub("^%s+", ""):gsub("%s+$", "")
        end
    end
    return nil
end

-- [ServiceHub] clearTrialState removed (unused)

local function saveActiveMode(mode: string)
    ensureFolder(CONFIG_FOLDER)
    ensureParentFolder(ACTIVE_MODE_FILE)
    if writefile then
        pcall(writefile, ACTIVE_MODE_FILE, mode)
    end
end

local function loadActiveMode(): string?
    if isfile and isfile(ACTIVE_MODE_FILE) then
        local ok, content = pcall(readfile, ACTIVE_MODE_FILE)
        if ok and content and content ~= "" then
            return content:gsub("%s+", "")
        end
    end
    return nil
end

local function clearActiveMode()
    if delfile and isfile and isfile(ACTIVE_MODE_FILE) then
        pcall(delfile, ACTIVE_MODE_FILE)
    end
end

local function saveActiveFarmType(farmType: string)
    ensureFolder(CONFIG_FOLDER)
    ensureParentFolder(ACTIVE_FARM_TYPE_FILE)
    if writefile then
        pcall(writefile, ACTIVE_FARM_TYPE_FILE, farmType)
    end
end

local function loadActiveFarmType(): string?
    if isfile and isfile(ACTIVE_FARM_TYPE_FILE) then
        local ok, content = pcall(readfile, ACTIVE_FARM_TYPE_FILE)
        if ok and content and content ~= "" then
            return content:gsub("%s+", "")
        end
    end
    return nil
end

local function clearActiveFarmType()
    if delfile and isfile and isfile(ACTIVE_FARM_TYPE_FILE) then
        pcall(delfile, ACTIVE_FARM_TYPE_FILE)
    end
end

-- Match Mode Detection in Game
local currentMatchMode: string? = nil

--==============================================================================
-- In-Game Match State & Dirty Configuration Tracking
--==============================================================================
local originalMatchConfig: { [string]: any }? = nil
local isLateExecution = false
local initialExecutionWave = 0

local isTowerEvoComplete: (towerName: string) -> boolean
local isTowerOrEvoOwned: (towerName: string) -> boolean

local function snapshotMatchConfig()
    if game.PlaceId == LOBBY_PLACE_ID then
        originalMatchConfig = nil
        return
    end

    local startStage = nil
    local startTower = nil
    local startCoins = 0
    local startGems = 0
    local startBaseLevel = 0
    local startEvoLevel = 0

    pcall(function()
        if PlayerDataHandler then
            pcall(function() startCoins = PlayerDataHandler:GetCoins() or 0 end)
            pcall(function() startGems = PlayerDataHandler:GetGems() or 0 end)
        end

        local selected = tostring(Globals.TargetEvo or "All")
        local tList = (selected == "All") and { "Scout", "Shotgunner", "Crook Boss", "Minigunner" } or { selected }
        for _, tName in ipairs(tList) do
            if not isTowerEvoComplete(tName) then
                if selected ~= "All" or (isTowerOrEvoOwned and isTowerOrEvoOwned(tName)) then
                    startTower = tName
                    break
                end
            end
        end

        if startTower and EvoData and EvoData[startTower] then
            local eData = EvoData[startTower]
            local evoName = eData.Evo or startTower
            local ownsEvo = false
            if PlayerDataHandler and typeof(PlayerDataHandler.IsTowerOwned) == "function" then
                ownsEvo = PlayerDataHandler:IsTowerOwned(evoName)
            end

            if ownsEvo then
                startStage = "EvoLevel"
                local evoExp = nil
                if PlayerDataHandler and typeof(PlayerDataHandler.GetTowerExp) == "function" then
                    evoExp = PlayerDataHandler:GetTowerExp(evoName)
                end
                startEvoLevel = (evoExp and type(evoExp.Level) == "number") and evoExp.Level or 0
            else
                local ownsBase = false
                if PlayerDataHandler and typeof(PlayerDataHandler.IsTowerOwned) == "function" then
                    ownsBase = PlayerDataHandler:IsTowerOwned(startTower)
                end
                if not ownsBase then
                    startStage = "Coins"
                else
                    local targetCoins = eData.Coins or 0
                    local targetGems = eData.Gems or 0
                    local coinsNeed = math.max(0, targetCoins - startCoins)
                    local gemsNeed = math.max(0, targetGems - startGems)
                    local expData = nil
                    if PlayerDataHandler and typeof(PlayerDataHandler.GetTowerExp) == "function" then
                        expData = PlayerDataHandler:GetTowerExp(startTower)
                    end
                    startBaseLevel = (expData and type(expData.Level) == "number") and expData.Level or 0

                    if startBaseLevel < 20 then
                        startStage = "BaseLevel"
                    elseif coinsNeed > 0 then
                        startStage = "Coins"
                    elseif gemsNeed > 0 then
                        startStage = "Gems"
                    else
                        startStage = "ReadyToBuy"
                    end
                end
            end
        end
    end)

    originalMatchConfig = {
        AutoTrials = Globals.AutoTrials,
        AutoGold = Globals.AutoGold,
        AutoEvo = Globals.AutoEvo,
        AutoFarmType = tostring(Globals.AutoFarmType or "Coins"),
        TargetMode = tostring(Globals.TargetMode or "Molten"),
        Strat = tostring(Globals.Strat or "Lose"),
        TargetEvo = tostring(Globals.TargetEvo or "All"),
        EvoStrat = tostring(Globals.EvoStrat or "Lose"),
        SelectedFallback = tostring(Globals.SelectedFallback or "Smart Auto"),
        TrialFarmMode = tostring(Globals.TrialFarmMode or "Farm Mode"),
        FarmOnly = tostring(Globals.FarmOnly or "Disabled"),
        SelectedTrials = (type(Globals.SelectedTrials) == "table") and table.concat(Globals.SelectedTrials, ",") or tostring(Globals.SelectedTrials or ""),
        ActiveMode = tostring(currentMatchMode or loadActiveMode() or ""),
        EvoStartStage = startStage,
        EvoStartTower = startTower,
        EvoStartBaseLevel = startBaseLevel,
        EvoStartEvoLevel = startEvoLevel,
    }
end

isMatchConfigDirty = function(): boolean
    if game.PlaceId == LOBBY_PLACE_ID then return false end
    if Globals.IsConfigDirty then return true end
    if not originalMatchConfig then return false end

    if originalMatchConfig.AutoTrials ~= Globals.AutoTrials then return true end
    if originalMatchConfig.AutoGold ~= Globals.AutoGold then return true end
    if originalMatchConfig.AutoEvo ~= Globals.AutoEvo then return true end
    if originalMatchConfig.AutoFarmType ~= tostring(Globals.AutoFarmType or "Coins") then return true end
    if originalMatchConfig.TargetMode ~= tostring(Globals.TargetMode or "Molten") then return true end
    if originalMatchConfig.Strat ~= tostring(Globals.Strat or "Lose") then return true end
    if originalMatchConfig.TargetEvo ~= tostring(Globals.TargetEvo or "All") then return true end
    if originalMatchConfig.EvoStrat ~= tostring(Globals.EvoStrat or "Lose") then return true end
    if originalMatchConfig.SelectedFallback ~= tostring(Globals.SelectedFallback or "Smart Auto") then return true end
    if originalMatchConfig.TrialFarmMode ~= tostring(Globals.TrialFarmMode or "Farm Mode") then return true end
    if originalMatchConfig.FarmOnly ~= tostring(Globals.FarmOnly or "Disabled") then return true end
    
    local currentTrialsStr = (type(Globals.SelectedTrials) == "table") and table.concat(Globals.SelectedTrials, ",") or tostring(Globals.SelectedTrials or "")
    if originalMatchConfig.SelectedTrials ~= currentTrialsStr then return true end

    local curMode = tostring(currentMatchMode or loadActiveMode() or "")
    if originalMatchConfig.ActiveMode ~= "" and curMode ~= "" and originalMatchConfig.ActiveMode ~= curMode then
        return true
    end

    return false
end
if game.PlaceId ~= LOBBY_PLACE_ID then
    currentMatchMode = loadActiveMode()
    local isOwnedModeWithOther = (Globals.TrialFarmMode == "Progression Mode" and (Globals.AutoEvo or Globals.AutoGold))

    local isTrial = false
    local liveTrial = ""
    pcall(function()
        local gsr = ReplicatedStorage:FindFirstChild("StateReplicators")
            and ReplicatedStorage.StateReplicators:FindFirstChild("GameStateReplicator")
        if gsr then
            local gt = gsr:GetAttribute("GlobalTrial")
            if gt and tostring(gt) ~= "" and tostring(gt) ~= "None" then
                isTrial = true
                liveTrial = tostring(gt)
            end
        end
    end)

    if Globals.MultiplayerEnabled or currentMatchMode == "Multiplayer" then
        currentMatchMode = "Multiplayer"
    elseif not isTrial and Globals.AutoEvo then
        currentMatchMode = "AutoEvo"
    elseif not isTrial and Globals.AutoGold and not isOwnedModeWithOther then
        currentMatchMode = "AutoGold"
    elseif not currentMatchMode or currentMatchMode == "" or (isOwnedModeWithOther and currentMatchMode == "AutoTrials") then
        if isTrial and not isOwnedModeWithOther then
            currentMatchMode = "AutoTrials"
        elseif isOwnedModeWithOther then
            if Globals.AutoEvo then
                currentMatchMode = "AutoEvo"
            else
                currentMatchMode = "AutoGold"
            end
        elseif isTrial then
            currentMatchMode = "AutoTrials"
        elseif Globals.AutoEvo then
            currentMatchMode = "AutoEvo"
        elseif Globals.AutoGold then
            currentMatchMode = "AutoGold"
        elseif Globals.AutoTrials then
            currentMatchMode = "AutoTrials"
        else
            currentMatchMode = "AutoTrials"
        end
    end
    ----print((`[ServiceHub] In-Game Active Match Mode detected: {currentMatchMode}`)
end

--==============================================================================
-- Smart Teleport & Lobby Handlers
--==============================================================================
local isTeleporting = false
local loadoutApplied = false
local teleportRetryThread = nil


--==============================================================================
-- Trial Modifier Voting System
--==============================================================================
local RemoteFunc = nil

local function CastModifierVote(ModsTable)
    if type(ModsTable) == "table" and #ModsTable == 1 and type(ModsTable[1]) == "table" then
        ModsTable = ModsTable[1]
    end

    local BulkModifiers = nil
    pcall(function()
        local net = ReplicatedStorage:WaitForChild("Network", 5)
        local mods = net and net:WaitForChild("Modifiers", 5)
        BulkModifiers = mods and mods:WaitForChild("RF:BulkVoteModifiers", 5)
    end)

    local ModRep = nil
    pcall(function()
        local sr = ReplicatedStorage:WaitForChild("StateReplicators", 5)
        ModRep = sr and sr:FindFirstChild("ModifierReplicator")
    end)

    local Available = {}
    if ModRep then
        local raw = ModRep:GetAttribute("Available")
        if type(raw) == "string" then
            local clean = raw:match("{.+}")
            if clean then
                pcall(function()
                    Available = HttpService:JSONDecode(clean)
                end)
            end
        end
    end

    local SelectedMods = {}
    local missingMods = {}

    if ModsTable then
        for k, v in pairs(ModsTable) do
            local modName = type(k) == "string" and k or v
            
            if type(modName) == "string" then
                if Available[modName] == true then
                    SelectedMods[modName] = true
                else
                    table.insert(missingMods, modName)
                end
            end
        end
    end

    if #missingMods > 0 then
        pcall(function()
            if UI and UI.Window and typeof(UI.Window.Notify) == "function" then
                UI.Window:Notify({
                    Title = "ADS",
                    Desc = "Locked (Skipped) modifiers: " .. table.concat(missingMods, ", "),
                    Time = 50,
                    Duration = 10,
                    Type = "error"
                })
            end
        end)
    end

    if next(SelectedMods) and BulkModifiers then
        pcall(function()
            BulkModifiers:InvokeServer(SelectedMods)
            logActivity("Successfully casted modifier votes.", "success")
        end)
    end
end

local isMapIntermissionHandling = false
local intermissionMapHandled = false
local lastVotedIntermissionMap: string? = nil

local function SmartTeleportToLobby()
    if isTeleporting then return end
    isTeleporting = true
    loadoutApplied = false
    if TDS then TDS.MultiplayerLoadoutLocked = false end
    intermissionMapHandled = false
    isMapIntermissionHandling = false
    lastVotedIntermissionMap = nil
    ----warn([ServiceHub] SmartTeleportToLobby initiating...")

    pcall(clearActiveMode)
    pcall(clearActiveFarmType)

    if teleportRetryThread then
        pcall(task.cancel, teleportRetryThread)
        teleportRetryThread = nil
    end

    teleportRetryThread = task.spawn(function()
        while true do
            if not isRunning then break end
            if game.PlaceId == LOBBY_PLACE_ID then break end

            pcall(function()
                local platform = UserInputService:GetPlatform()
                local isMobile = (platform == Enum.Platform.IOS or platform == Enum.Platform.Android)

                if not isMobile and Globals.PrivateCode and Globals.PrivateCode ~= "" then
                    pcall(function()
                        local expService = game:GetService("ExperienceService")
                        if expService then
                            expService:LaunchExperience({
                                placeId = LOBBY_PLACE_ID,
                                linkCode = Globals.PrivateCode
                            })
                        end
                    end)
                else
                    pcall(function()
                        local shared = ReplicatedStorage:FindFirstChild("Shared")
                        local modules = shared and shared:FindFirstChild("Modules")
                        local newNet = modules and modules:FindFirstChild("NewNetwork")
                        if newNet then
                            local NewNetwork = require(newNet)
                            NewNetwork.Channel("Teleport"):fireServer("backToLobby")
                        end
                    end)

                    pcall(function()
                        local remoteEvent = ReplicatedStorage:FindFirstChild("RemoteEvent")
                        local remoteFunc = ReplicatedStorage:FindFirstChild("RemoteFunction")
                        if remoteEvent and remoteEvent:IsA("RemoteEvent") then
                            remoteEvent:FireServer("Teleport", "backToLobby")
                        elseif remoteFunc and remoteFunc:IsA("RemoteFunction") then
                            remoteFunc:InvokeServer("Teleport", "backToLobby")
                        end
                    end)

                    task.delay(1.5, function()
                        pcall(function()
                            TeleportService:Teleport(LOBBY_PLACE_ID, LocalPlayer)
                        end)
                    end)
                end
            end)
            
            task.wait(10) -- Retry teleport every 10 seconds until they are back in the lobby
        end
    end)

    task.delay(30, function()
        isTeleporting = false
    end)
end

--==============================================================================

--==============================================================================
-- Mobile & Low-End Device Performance Optimizer
--==============================================================================
local mobileBoostActive = false
local function applyMobileOptimizations(enable: boolean)
    mobileBoostActive = enable
    if not enable then return end
    pcall(function()
        settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
    end)
    pcall(function()
        local lighting = game:GetService("Lighting")
        lighting.GlobalShadows = false
        lighting.FogEnd = 9e9
        for _, effect in ipairs(lighting:GetChildren()) do
            if effect:IsA("PostEffect") or effect:IsA("Atmosphere") or effect:IsA("Clouds") or effect:IsA("Sky") then
                effect.Enabled = false
            end
        end
    end)
    pcall(function()
        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Smoke") or obj:IsA("Fire") then
                obj.Enabled = false
            end
        end
    end)
end

-- AutoGoldModule & Map Prioritization Handlers (High-Performance Single-Pass Scan)
--==============================================================================
local AutoGoldModule = {}
AutoGoldModule.Configs = FallbackConfigs
AutoGoldModule.CrateConfigs = CrateConfigs

local function resolveSmartFallback(): string
    ensureDynamicHardcoreFallback()
    if not FallbackConfigs or not next(FallbackConfigs) then
        return "Molten"
    end
    local pLevel = PlayerDataHandler and PlayerDataHandler:GetLevel() or 0
    local function checkEligible(cfgName: string): boolean
        local cfg = FallbackConfigs[cfgName]
        if not cfg then return false end
        local reqLvl = cfg.Level or cfg.level or 0
        if pLevel < reqLvl then return false end
        if cfg.Towers and type(cfg.Towers) == "table" and PlayerDataHandler then
            for _, tow in ipairs(cfg.Towers) do
                if tow and tow ~= "" and not PlayerDataHandler:IsTowerOwned(tow) then
                    return false
                end
            end
        end
        return true
    end

    -- Rule: If coin towers are all owned, MOVE to Hardcore gems fallback!
    local coinTowersOwned = false
    if typeof(isCoinTowersMaxed) == "function" then
        pcall(function()
            coinTowersOwned = isCoinTowersMaxed()
        end)
    end

    if coinTowersOwned then
        if checkEligible("Hardcore") then
            return "Hardcore"
        elseif FallbackConfigs["Hardcore"] then
            return "Hardcore"
        end
    end

    -- If coins towers are not yet all owned, prefer Fallen / Molten for coins
    if checkEligible("Fallen") then
        return "Fallen"
    elseif checkEligible("Molten") then
        return "Molten"
    end

    if FallbackConfigs["Fallen"] then
        return "Fallen"
    elseif FallbackConfigs["Molten"] then
        return "Molten"
    end
    for k in pairs(FallbackConfigs) do
        if type(k) == "string" then return k end
    end
    return "Molten"
end

resolveCoinFarmFallback = function(): string
    ensureDynamicHardcoreFallback()
    local pLevel = PlayerDataHandler and PlayerDataHandler:GetLevel() or 0
    local function checkEligible(cfgName: string): boolean
        local cfg = FallbackConfigs and FallbackConfigs[cfgName]
        if not cfg then return false end
        local reqLvl = cfg.Level or cfg.level or 0
        if pLevel < reqLvl then return false end
        if cfg.Towers and type(cfg.Towers) == "table" and PlayerDataHandler then
            for _, tow in ipairs(cfg.Towers) do
                if tow and tow ~= "" and not PlayerDataHandler:IsTowerOwned(tow) then
                    return false
                end
            end
        end
        return true
    end

    if checkEligible("Fallen") then
        return "Fallen"
    elseif checkEligible("Molten") then
        return "Molten"
    end

    if FallbackConfigs and FallbackConfigs["Fallen"] then
        return "Fallen"
    end
    return "Molten"
end

local analyzeAutoEvoRequirements: ((optTargetEvo: string?, optStrat: string?) -> AutoEvoAnalysis)? = nil

local function getCurrentCrateConfig(optFarmType: string?): any
    local liveGameMode = ""
    pcall(function()
        local gsr = ReplicatedStorage:FindFirstChild("StateReplicators")
            and ReplicatedStorage.StateReplicators:FindFirstChild("GameStateReplicator")
        if gsr then
            liveGameMode = tostring(gsr:GetAttribute("GameMode") or gsr:GetAttribute("Mode") or ""):lower()
        end
    end)
    local isHardcoreMatch = (liveGameMode == "hardcore")
    local savedFarmType = (typeof(loadActiveFarmType) == "function") and loadActiveFarmType() or nil

    local isAutoEvoActive = (Globals.AutoEvo or currentMatchMode == "AutoEvo") and not Globals.AutoGold
    if Globals.TrialFarmMode == "Progression Mode" and (Globals.AutoEvo or currentMatchMode == "AutoEvo") then
        isAutoEvoActive = true
    end

    if isAutoEvoActive then
        if not optFarmType and not Globals.CurrentEvoFarmType and typeof(analyzeAutoEvoRequirements) == "function" then
            local ok, evoAnalysis = pcall(analyzeAutoEvoRequirements)
            if ok and evoAnalysis then
                if evoAnalysis.activeTower then
                    Globals.CurrentEvoActiveTower = evoAnalysis.activeTower
                end
                if evoAnalysis.farmType then
                    Globals.CurrentEvoFarmType = evoAnalysis.farmType
                end
            end
        end

        local needType = optFarmType or (isHardcoreMatch and "Gems") or Globals.CurrentEvoFarmType or savedFarmType or "Coins"
        
        local evoStratPref = tostring(Globals.EvoStrat or "Lose")
        local stratChoice = (needType == "Gems" or isHardcoreMatch) and "Lose" or evoStratPref
        
        local category = AutoEvoConfigs[needType]
        if category and category[stratChoice] then
            return category[stratChoice]
        end
        if category and category["Lose"] then return category["Lose"] end
        if category and category["Win"] then return category["Win"] end
        return nil
    end

    if Globals.MultiplayerEnabled and Globals.MultiplayerMode == "Farm Mode" then
        local mpStrat = Globals.MultiplayerFarmStrategy or "Molten"
        if mpStrat == "Smart Auto" and typeof(resolveSmartFallback) == "function" then
            mpStrat = resolveSmartFallback()
        end
        if FallbackConfigs and FallbackConfigs[mpStrat] then
            return FallbackConfigs[mpStrat]
        end
        local cat = AutoGoldModule.CrateConfigs and AutoGoldModule.CrateConfigs[farmType] or (CrateConfigs and CrateConfigs[farmType])
        if cat and cat[mpStrat] then return cat[mpStrat] end
    end

    local farmType = optFarmType or (isHardcoreMatch and "Gems") or savedFarmType or Globals.AutoFarmType or "Coins"

    -- Check if live match difficulty or saved trial state matches FallbackConfigs (e.g. Fallen or Molten with Lay By)
    local liveDiff = ""
    pcall(function()
        local gsr = ReplicatedStorage:FindFirstChild("StateReplicators")
            and ReplicatedStorage.StateReplicators:FindFirstChild("GameStateReplicator")
        if gsr then
            liveDiff = tostring(gsr:GetAttribute("Difficulty") or "")
        end
    end)
    local savedTrial = ""
    if typeof(loadTrialState) == "function" then
        pcall(function() savedTrial = tostring(loadTrialState() or "") end)
    end
    if FallbackConfigs then
        for modeName, modeConfig in pairs(FallbackConfigs) do
            if (liveDiff ~= "" and normalizeString(modeName) == normalizeString(liveDiff))
                or (savedTrial ~= "" and normalizeString(modeName) == normalizeString(savedTrial)) then
                return modeConfig
            end
        end
    end

    local stratChoice = Globals.Strat or "Lose"
    if farmType == "Gems" or isHardcoreMatch then
        stratChoice = "Lose"
    elseif stratChoice == "Fallen" then
        stratChoice = "Win"
    elseif stratChoice == "Molten" then
        stratChoice = "Lose"
    end

    local category = AutoGoldModule.CrateConfigs and AutoGoldModule.CrateConfigs[farmType] or CrateConfigs[farmType]
    if category and category[stratChoice] then
        return category[stratChoice]
    end
    if category and category["Lose"] then return category["Lose"] end
    if category and category["Win"] then return category["Win"] end

    if AutoGoldModule.CrateConfigs and AutoGoldModule.CrateConfigs[stratChoice] then
        return AutoGoldModule.CrateConfigs[stratChoice]
    end

    -- Direct fallback for Hardcore / Gems from FallbackConfigs
    if farmType == "Gems" or isHardcoreMatch then
        if FallbackConfigs and FallbackConfigs["Hardcore"] then
            return FallbackConfigs["Hardcore"]
        end
    end

    return nil
end

export type AutoGoldAnalysis = {
    farmType: string,
    stratChoice: string,
    targetMode: string,
    configFound: boolean,
    requiredLevel: number,
    playerLevel: number,
    levelPassed: boolean,
    missingTowers: { string },
    missingGold: { string },
    missingSkills: { string },
    missingParts: { string },
    isEligible: boolean,
}

local function analyzeAutoGoldRequirements(optFarmType: string?, optStrat: string?): AutoGoldAnalysis
    local farmType = optFarmType or Globals.AutoFarmType or "Coins"
    local stratChoice = optStrat or Globals.Strat or "Lose"

    local playerLevel = PlayerDataHandler and PlayerDataHandler:GetLevel() or 0
    local category = AutoGoldModule.CrateConfigs and AutoGoldModule.CrateConfigs[farmType] or CrateConfigs[farmType]
    local config = category and category[stratChoice]

    if not config and AutoGoldModule.CrateConfigs then
        config = AutoGoldModule.CrateConfigs[stratChoice]
    end

    local result: AutoGoldAnalysis = {
        farmType = farmType,
        stratChoice = stratChoice,
        targetMode = config and (config.Mode or config.mode) or "Unknown",
        configFound = (config ~= nil),
        requiredLevel = config and (config.Level or config.level) or 0,
        playerLevel = playerLevel,
        levelPassed = true,
        missingTowers = {},
        missingGold = {},
        missingSkills = {},
        missingParts = {},
        isEligible = false,
    }

    if not config then
        table.insert(result.missingParts, "Config Missing")
        return result
    end

    -- 1. Level Check
    local reqLevel = config.Level or config.level or 0
    result.requiredLevel = reqLevel
    result.levelPassed = (playerLevel >= reqLevel)
    if not result.levelPassed then
        table.insert(result.missingParts, string.format("Level %d (You: %d)", reqLevel, playerLevel))
    end

    -- 2. Towers Check
    local towersConfig = config.Towers or config.towers
    if type(towersConfig) == "table" and PlayerDataHandler then
        for _, tower in ipairs(towersConfig) do
            if tower and tower ~= "" and not PlayerDataHandler:IsTowerOwned(tower) then
                table.insert(result.missingTowers, tower)
            end
        end
        if #result.missingTowers > 0 and game.PlaceId == LOBBY_PLACE_ID then
            local boughtAny = attemptBuyMissingTowersList(result.missingTowers)
            if boughtAny then
                local remaining = {}
                for _, tower in ipairs(towersConfig) do
                    if tower and tower ~= "" and not PlayerDataHandler:IsTowerOwned(tower) then
                        table.insert(remaining, tower)
                    end
                end
                result.missingTowers = remaining
            end
        end
    end
    if #result.missingTowers > 0 then
        table.insert(result.missingParts, "Towers: " .. table.concat(result.missingTowers, ", "))
    end

    -- 3. Golden Check
    local goldReqs = config.Golden or config.golden
    if type(goldReqs) == "table" and #goldReqs > 0 and PlayerDataHandler then
        for _, goldTower in ipairs(goldReqs) do
            if goldTower and goldTower ~= "" and not PlayerDataHandler:IsGoldenOwned(goldTower) then
                table.insert(result.missingGold, goldTower)
            end
        end
    end
    if #result.missingGold > 0 then
        table.insert(result.missingParts, "Golden: " .. table.concat(result.missingGold, ", "))
    end

    -- 4. Skill Tree Check
    local skillReqs = config.SkillTree or config["Skill Tree"] or config.skillTree
    if type(skillReqs) == "table" and next(skillReqs) and PlayerDataHandler then
        local currentSkills = {}
        if type(PlayerDataHandler.GetSkillTree) == "function" then
            pcall(function()
                for _, skill in ipairs(PlayerDataHandler:GetSkillTree()) do
                    currentSkills[skill.Name] = skill.Level
                end
            end)
        end
        for skillName, reqNodeLevel in pairs(skillReqs) do
            local haveLevel = currentSkills[skillName] or 0
            if haveLevel < reqNodeLevel then
                table.insert(result.missingSkills, string.format("%s (Need %d, Have %d)", skillName, reqNodeLevel, haveLevel))
            end
        end
    end
    if #result.missingSkills > 0 then
        table.insert(result.missingParts, "Skill Tree: " .. table.concat(result.missingSkills, ", "))
    end

    result.isEligible = result.levelPassed and (#result.missingTowers == 0) and (#result.missingGold == 0) and (#result.missingSkills == 0)
    return result
end

function AutoGoldModule.AnalyzeRequirements(stratType: string): (boolean, string)
    local analysis = analyzeAutoGoldRequirements(nil, stratType)
    if not analysis.configFound then
        return false, "Invalid strategy configuration"
    end
    if not analysis.isEligible then
        return false, table.concat(analysis.missingParts, " | ")
    end
    return true, "All strategy requirements successfully met"
end

export type AutoEvoAnalysis = {
    targetEvo: string,
    stratChoice: string,
    activeTower: string?,
    farmType: string?,
    targetMode: string?,
    configFound: boolean,
    allFinished: boolean,
    readyToBuy: boolean,
    isEligible: boolean,
    missingBase: { string },
    missingTowers: { string },
    missingGold: { string },
    missingSkills: { string },
    requiredLevel: number,
    playerLevel: number,
    levelPassed: boolean,
    missingParts: { string },
}

isTowerOrEvoOwned = function(towerName: string): boolean
    local eData = EvoData[towerName]
    local evoName = eData and eData.Evo or towerName
    if PlayerDataHandler and typeof(PlayerDataHandler.IsTowerOwned) == "function" then
        local ownsBase = false
        local ownsEvo = false
        pcall(function() ownsBase = PlayerDataHandler:IsTowerOwned(towerName) end)
        pcall(function() ownsEvo = PlayerDataHandler:IsTowerOwned(evoName) end)
        return (ownsBase == true) or (ownsEvo == true)
    end
    return true
end

isTowerEvoComplete = function(towerName: string): boolean
    local eData = EvoData[towerName]
    local evoName = eData and eData.Evo or towerName
    if PlayerDataHandler and typeof(PlayerDataHandler.IsTowerOwned) == "function" then
        local ownsEvo = false
        pcall(function() ownsEvo = PlayerDataHandler:IsTowerOwned(evoName) end)
        if ownsEvo then
            local expData = nil
            if typeof(PlayerDataHandler.GetTowerExp) == "function" then
                pcall(function() expData = PlayerDataHandler:GetTowerExp(evoName) end)
            end
            local evoLevel = (expData and type(expData.Level) == "number") and expData.Level or 0
            return evoLevel >= 20
        end
    end
    return false
end

analyzeAutoEvoRequirements = function(optTargetEvo: string?, optStrat: string?): AutoEvoAnalysis
    local target = optTargetEvo or Globals.TargetEvo or "All"
    local stratChoice = optStrat or Globals.EvoStrat or "Lose"

    local playerLevel = PlayerDataHandler and PlayerDataHandler:GetLevel() or 0
    local coins = 0
    local gems = 0
    if PlayerDataHandler then
        if typeof(PlayerDataHandler.GetCoins) == "function" then
            pcall(function() coins = PlayerDataHandler:GetCoins() or 0 end)
        end
        if typeof(PlayerDataHandler.GetGems) == "function" then
            pcall(function() gems = PlayerDataHandler:GetGems() or 0 end)
        end
    end

    local toCheck = {}
    if target == "All" then
        for _, tName in ipairs({ "Scout", "Shotgunner", "Crook Boss", "Minigunner" }) do
            if not isTowerEvoComplete(tName) and isTowerOrEvoOwned(tName) then
                table.insert(toCheck, tName)
            end
        end
    elseif EvoData[target] then
        toCheck = { target }
    end

    local result: AutoEvoAnalysis = {
        targetEvo = target,
        stratChoice = stratChoice,
        activeTower = nil,
        farmType = nil,
        targetMode = "Unknown",
        configFound = false,
        allFinished = (#toCheck == 0),
        readyToBuy = false,
        isEligible = false,
        missingBase = {},
        missingTowers = {},
        missingGold = {},
        missingSkills = {},
        requiredLevel = 0,
        playerLevel = playerLevel,
        levelPassed = true,
        missingParts = {},
    }

    if #toCheck == 0 then
        if target == "All" then
            result.allFinished = true
            result.configFound = true
            result.isEligible = false
            return result
        else
            table.insert(result.missingParts, "No Target Selected")
            return result
        end
    end

    local activeTower = nil
    local activeFarmType = nil
    local activeReadyToBuy = false
    local missingBaseMap = {}

    for _, towerName in ipairs(toCheck) do
        local eData = EvoData[towerName]
        local evoName = eData and eData.Evo or towerName

        local ownsEvo = false
        if PlayerDataHandler and typeof(PlayerDataHandler.IsTowerOwned) == "function" then
            pcall(function() ownsEvo = PlayerDataHandler:IsTowerOwned(evoName) end)
        end

        if not ownsEvo then
            result.allFinished = false
            local ownsBase = false
            if PlayerDataHandler and typeof(PlayerDataHandler.IsTowerOwned) == "function" then
                pcall(function() ownsBase = PlayerDataHandler:IsTowerOwned(towerName) end)
            end

            if not ownsBase then
                missingBaseMap[towerName] = true
                table.insert(result.missingBase, towerName)
                if not activeTower then
                    activeTower = towerName
                end
            else
                local expData = nil
                if PlayerDataHandler and typeof(PlayerDataHandler.GetTowerExp) == "function" then
                    pcall(function() expData = PlayerDataHandler:GetTowerExp(towerName) end)
                end
                local baseLevel = expData and expData.Level or 0
                local reqCoins = eData and (eData.Coins or 15000) or 15000
                local reqGems = eData and (eData.Gems or 4500) or 4500
                local coinsNeed = math.max(0, reqCoins - coins)
                local gemsNeed = math.max(0, reqGems - gems)

                if not activeTower then
                    activeTower = towerName
                    if baseLevel < 20 then
                        -- Must reach Level 20 first! Farms Coins/EXP with this tower
                        activeFarmType = "Coins"
                    elseif coinsNeed > 0 then
                        activeFarmType = "Coins"
                    elseif gemsNeed > 0 then
                        activeFarmType = "Gems"
                    else
                        activeReadyToBuy = true
                    end
                end
            end
            -- Strictly sequential: Complete active target before moving to the next!
            break
        else
            -- Evolved tower is owned but level < 20: Farm Coins/EXP with this tower
            result.allFinished = false
            if not activeTower then
                activeTower = towerName
                activeFarmType = "Coins"
            end
            break
        end
    end

    result.activeTower = activeTower
    result.farmType = activeFarmType
    result.readyToBuy = activeReadyToBuy

    -- If all targets are completely evolved & level 20:
    if result.allFinished then
        result.isEligible = false
        result.configFound = true
        return result
    end

    -- If the active tower's base tower is not owned:
    if activeTower and missingBaseMap[activeTower] then
        table.insert(result.missingParts, "Base Tower: " .. activeTower)
        result.isEligible = false
        result.configFound = true
        return result
    end

    -- If ready to evolve/buy directly in lobby:
    if activeReadyToBuy then
        result.isEligible = true
        result.configFound = true
        return result
    end

    -- Needs to farm either Coins or Gems:
    local farmType = activeFarmType or "Coins"
    local actualStrat = (farmType == "Gems") and "Lose" or (stratChoice or "Lose")
    result.farmType = farmType
    result.stratChoice = actualStrat

    local category = AutoEvoConfigs and AutoEvoConfigs[farmType]
    local config = category and (category[actualStrat] or category["Lose"] or category["Win"])

    if not config then
        table.insert(result.missingParts, "Config Missing (" .. farmType .. " " .. actualStrat .. ")")
        result.isEligible = false
        return result
    end

    result.configFound = true
    result.targetMode = config.Mode or "Unknown"

    -- 1. Level Check
    local reqLevel = config.Level or 0
    result.requiredLevel = reqLevel
    result.levelPassed = (playerLevel >= reqLevel)
    if not result.levelPassed then
        table.insert(result.missingParts, string.format("Level %d (You: %d)", reqLevel, playerLevel))
    end

    -- 2. Towers Check (Strategy Loadout)
    local towersConfig = config.Towers
    local stratTowers = {}
    if type(towersConfig) == "table" then
        if activeTower and towersConfig[activeTower] then
            stratTowers = towersConfig[activeTower]
        elseif #towersConfig > 0 then
            stratTowers = towersConfig
        end
    end

    if type(stratTowers) == "table" and PlayerDataHandler then
        for _, tower in ipairs(stratTowers) do
            if tower and tower ~= "" and not PlayerDataHandler:IsTowerOwned(tower) then
                table.insert(result.missingTowers, tower)
            end
        end
    end
    if #result.missingTowers > 0 then
        table.insert(result.missingParts, "Towers: " .. table.concat(result.missingTowers, ", "))
    end

    -- 3. Golden Check
    local goldReqs = config.Golden or config.golden
    if type(goldReqs) == "table" and #goldReqs > 0 and PlayerDataHandler then
        for _, goldTower in ipairs(goldReqs) do
            if goldTower and goldTower ~= "" and not PlayerDataHandler:IsGoldenOwned(goldTower) then
                table.insert(result.missingGold, goldTower)
            end
        end
    end
    if #result.missingGold > 0 then
        table.insert(result.missingParts, "Golden: " .. table.concat(result.missingGold, ", "))
    end

    -- 4. Skill Tree Check
    local skillReqs = config.SkillTree or config["Skill Tree"] or config.skillTree
    if type(skillReqs) == "table" and next(skillReqs) and PlayerDataHandler then
        local currentSkills = {}
        if type(PlayerDataHandler.GetSkillTree) == "function" then
            pcall(function()
                for _, skill in ipairs(PlayerDataHandler:GetSkillTree()) do
                    currentSkills[skill.Name] = skill.Level
                end
            end)
        end
        for skillName, reqNodeLevel in pairs(skillReqs) do
            local haveLevel = currentSkills[skillName] or 0
            if haveLevel < reqNodeLevel then
                table.insert(result.missingSkills, string.format("%s (Need %d, Have %d)", skillName, reqNodeLevel, haveLevel))
            end
        end
    end
    if #result.missingSkills > 0 then
        table.insert(result.missingParts, "Skill Tree: " .. table.concat(result.missingSkills, ", "))
    end

    result.isEligible = result.levelPassed and (#result.missingTowers == 0) and (#result.missingGold == 0) and (#result.missingSkills == 0) and (#result.missingBase == 0)
    return result
end

local function checkAutoEvoMilestonesReached(): (boolean, string?)
    if not Globals.AutoEvo then return false, nil end

    local coins = 0
    local gems = 0
    if PlayerDataHandler then
        if typeof(PlayerDataHandler.GetCoins) == "function" then
            pcall(function() coins = PlayerDataHandler:GetCoins() or 0 end)
        end
        if typeof(PlayerDataHandler.GetGems) == "function" then
            pcall(function() gems = PlayerDataHandler:GetGems() or 0 end)
        end
    end

    local selected = tostring(Globals.TargetEvo or "All")
    local activeTower = nil

    if selected == "All" then
        for _, tName in ipairs({ "Scout", "Shotgunner", "Crook Boss", "Minigunner" }) do
            if not isTowerEvoComplete(tName) and isTowerOrEvoOwned(tName) then
                activeTower = tName
                break
            end
        end
        if not activeTower then
            return true, "All Evolutions Complete (Level 20 Maxed)"
        end
    elseif EvoData and EvoData[selected] then
        activeTower = selected
        if isTowerEvoComplete(selected) then
            return true, string.format("%s Evolution Complete (Level 20 Maxed)", selected)
        end
    end

    if not activeTower or not EvoData or not EvoData[activeTower] then
        return false, nil
    end

    local eData = EvoData[activeTower]
    local evoName = eData.Evo or activeTower
    local targetCoins = eData.Coins or 0
    local targetGems = eData.Gems or 0

    -- Check evolved tower ownership
    local ownsEvo = false
    if PlayerDataHandler and typeof(PlayerDataHandler.IsTowerOwned) == "function" then
        pcall(function() ownsEvo = PlayerDataHandler:IsTowerOwned(evoName) end)
    end

    if ownsEvo then
        -- Milestone 4: evo exp 20 reached (Evolved tower level 20 maxed)
        local evoExp = nil
        if PlayerDataHandler and typeof(PlayerDataHandler.GetTowerExp) == "function" then
            pcall(function() evoExp = PlayerDataHandler:GetTowerExp(evoName) end)
        end
        local evoLevel = (evoExp and type(evoExp.Level) == "number") and evoExp.Level or 0
        if evoLevel >= 20 then
            return true, string.format("%s: evo exp 20 reached (Level %d/20)", evoName, evoLevel)
        end
        -- Still grinding evolved tower exp -> Milestone NOT reached yet!
        return false, nil
    end

    -- Check base tower ownership
    local ownsBase = false
    if PlayerDataHandler and typeof(PlayerDataHandler.IsTowerOwned) == "function" then
        pcall(function() ownsBase = PlayerDataHandler:IsTowerOwned(activeTower) end)
    end

    if not ownsBase then
        return false, nil
    end

    local expData = nil
    if PlayerDataHandler and typeof(PlayerDataHandler.GetTowerExp) == "function" then
        pcall(function() expData = PlayerDataHandler:GetTowerExp(activeTower) end)
    end
    local baseLevel = (expData and type(expData.Level) == "number") and expData.Level or 0

    -- Check match start snapshot stage if recorded
    local startStage = originalMatchConfig and originalMatchConfig.EvoStartStage
    local startTower = originalMatchConfig and originalMatchConfig.EvoStartTower

    if startStage and (startTower == nil or startTower == activeTower) then
        if startStage == "Coins" then
            -- Milestone 2: Coins Reach smart Lobby
            if coins >= targetCoins then
                return true, string.format("%s: Coins Reach (%s / %s Coins)", activeTower, formatNumberWithCommas(coins), formatNumberWithCommas(targetCoins))
            end
            return false, nil
        elseif startStage == "Gems" then
            -- Milestone 3: Gems Reach smartlobby
            if gems >= targetGems then
                return true, string.format("%s: Gems Reach (%s / %s Gems)", activeTower, formatNumberWithCommas(gems), formatNumberWithCommas(targetGems))
            end
            return false, nil
        elseif startStage == "BaseLevel" then
            -- Milestone 1: Level reach 20 smart lobby
            if baseLevel >= 20 then
                return true, string.format("%s: Level reach 20 (Base Tower Level %d/20)", activeTower, baseLevel)
            end
            return false, nil
        elseif startStage == "ReadyToBuy" then
            return true, string.format("%s: Ready to Evolve (Coins, Gems & Level 20 Reached)", activeTower)
        elseif startStage == "EvoLevel" then
            return false, nil
        end
    end

    -- Fallback dynamic stage evaluation (mutually exclusive sequential progression):
    local coinsNeed = math.max(0, targetCoins - coins)
    local gemsNeed = math.max(0, targetGems - gems)

    if coinsNeed > 0 then
        -- Milestone 2: Coins Reach
        if coins >= targetCoins then
            return true, string.format("%s: Coins Reach (%s / %s Coins)", activeTower, formatNumberWithCommas(coins), formatNumberWithCommas(targetCoins))
        end
        return false, nil
    elseif gemsNeed > 0 then
        -- Milestone 3: Gems Reach
        if gems >= targetGems then
            return true, string.format("%s: Gems Reach (%s / %s Gems)", activeTower, formatNumberWithCommas(gems), formatNumberWithCommas(targetGems))
        end
        return false, nil
    elseif baseLevel < 20 then
        -- Milestone 1: Level reach 20
        if baseLevel >= 20 then
            return true, string.format("%s: Level reach 20 (Base Tower Level %d/20)", activeTower, baseLevel)
        end
        return false, nil
    else
        -- Ready to evolve in lobby!
        return true, string.format("%s: Ready to Evolve (Coins, Gems & Level 20 Reached)", activeTower)
    end
end

function AutoGoldModule.LobbyReadyUp()
    if not Globals.AutoGold and not Globals.AutoTrials and not Globals.AutoEvo and not Globals.MultiplayerEnabled then return end

    pcall(function()
        local remoteEvent = ReplicatedStorage:FindFirstChild("RemoteEvent")
        local remoteFunc = ReplicatedStorage:FindFirstChild("RemoteFunction")
        if remoteEvent then
            remoteEvent:FireServer("LobbyVoting", "Ready")
        elseif remoteFunc then
            remoteFunc:InvokeServer("LobbyVoting", "Ready")
        end

        local gm = ReplicatedStorage:FindFirstChild("Network") and ReplicatedStorage.Network:FindFirstChild("GameManager")
        local readyRemote = gm and (gm:FindFirstChild("Ready") or gm:FindFirstChild("RE:Ready"))
        if readyRemote then
            if readyRemote:IsA("RemoteEvent") then
                readyRemote:FireServer()
            elseif readyRemote:IsA("RemoteFunction") then
                readyRemote:InvokeServer()
            end
        end
    end)
end

local cachedVipStatus: boolean? = nil

local function isVipOrPrivateServer(): boolean
    if cachedVipStatus ~= nil then
        return cachedVipStatus
    end

    local isVip = false

    -- 0. Explicit globals or configuration overrides
    pcall(function()
        if Globals.VIP == true or Globals.IsVIP == true or Globals.ForceVIP == true then
            isVip = true
        end
    end)
    if isVip then
        cachedVipStatus = true
        return true
    end

    -- 1. Standard Roblox engine properties for private / reserved servers
    pcall(function()
        if game.PrivateServerId and type(game.PrivateServerId) == "string" and game.PrivateServerId ~= "" then
            isVip = true
        end
        if game.PrivateServerOwnerId and type(game.PrivateServerOwnerId) == "number" and game.PrivateServerOwnerId ~= 0 then
            isVip = true
        end
    end)
    if isVip then
        cachedVipStatus = true
        return true
    end

    -- 2. TDS GameStateReplicator attributes
    pcall(function()
        local stateReplicators = ReplicatedStorage:FindFirstChild("StateReplicators")
        local gsr = stateReplicators and stateReplicators:FindFirstChild("GameStateReplicator")
        if gsr then
            if gsr:GetAttribute("IsPrivateServer") == true
                or gsr:GetAttribute("PrivateServer") == true
                or gsr:GetAttribute("VIP") == true
                or gsr:GetAttribute("VIPServer") == true then
                isVip = true
            end
        end
    end)
    if isVip then
        cachedVipStatus = true
        return true
    end

    -- 3. LocalPlayer attributes
    pcall(function()
        if LocalPlayer:GetAttribute("VIP") == true
            or LocalPlayer:GetAttribute("HasVIP") == true
            or LocalPlayer:GetAttribute("IsVIP") == true then
            isVip = true
        end
    end)
    if isVip then
        cachedVipStatus = true
        return true
    end

    -- 4. MarketplaceService Gamepass 10518590 (TDS VIP Pass)
    pcall(function()
        if MarketplaceService:UserOwnsGamePassAsync(LocalPlayer.UserId, 10518590) then
            isVip = true
        end
    end)
    if isVip then
        cachedVipStatus = true
        return true
    end

    -- 5. Intermission UI Override button check (direct visual/client proof of VIP override ability)
    pcall(function()
        local intermission = PlayerGui:FindFirstChild("ReactGameIntermission")
        if intermission then
            for _, desc in ipairs(intermission:GetDescendants()) do
                if desc:IsA("GuiButton") then
                    local dName = desc.Name:lower()
                    local dText = (desc:IsA("TextButton") and desc.Text:lower()) or ""
                    if dName:find("override") or dText:find("override") or dName:find("vip") then
                        isVip = true
                        break
                    end
                end
            end
        end
    end)
    if isVip then
        cachedVipStatus = true
        return true
    end

    -- 6. PlayerDataHandler gamepass check
    pcall(function()
        if PlayerDataHandler and typeof(PlayerDataHandler.GetPlayerData) == "function" then
            local pData = PlayerDataHandler:GetPlayerData()
            if pData and pData.Gamepasses and (pData.Gamepasses[10518590] or pData.Gamepasses["10518590"] or pData.Gamepasses["VIP"]) then
                isVip = true
            end
        end
    end)

    if isVip then
        cachedVipStatus = true
    end
    return isVip
end

-- Intermission Map & Modifier Voting Engine
do
    local Logger = {
        Log = function(self, msg: string)
            logActivity(tostring(msg), "info")
        end
    }

    local function CastMapVote(MapId, PosVec)
        local TargetMap = MapId or "Simplicity"
        local TargetPos = PosVec or Vector3.new(0, 0, 0)
        pcall(function()
            local RemoteEvent = ReplicatedStorage:FindFirstChild("RemoteEvent") or ReplicatedStorage:WaitForChild("RemoteEvent", 5)
            if RemoteEvent then
                RemoteEvent:FireServer("LobbyVoting", "Vote", TargetMap, TargetPos)
            end
        end)
        Logger:Log("Cast map vote: " .. TargetMap)
    end

    local function LobbyReadyUp()
        pcall(function()
            local RemoteEvent = ReplicatedStorage:FindFirstChild("RemoteEvent") or ReplicatedStorage:WaitForChild("RemoteEvent", 5)
            if RemoteEvent then
                RemoteEvent:FireServer("LobbyVoting", "Ready")
            end
            Logger:Log("Lobby ready up sent")
        end)
    end

    local function SelectMapOverride(MapId, ...)
        local args = { ... }

        if args[#args] == "vip" or isVipOrPrivateServer() then
            pcall(function()
                local RemoteFunc = ReplicatedStorage:FindFirstChild("RemoteFunction") or ReplicatedStorage:WaitForChild("RemoteFunction", 5)
                if RemoteFunc then
                    RemoteFunc:InvokeServer("LobbyVoting", "Override", MapId)
                end
            end)
        end

        task.wait(3)
        CastMapVote(MapId, Vector3.new(12.59, 10.64, 52.01))
        task.wait(1)
        LobbyReadyUp()
    end

    local function IsMapAvailable(name)
        for _, g in ipairs(workspace:GetDescendants()) do
            if g:IsA("SurfaceGui") and g.Name == "MapDisplay" then
                local t = g:FindFirstChild("Title")
                if t and (t.Text == name or normalizeString(t.Text) == normalizeString(name)) then return true end
            end
        end

        local hasVoted = false
        local startTime = os.time()

        repeat
            local IntermissionFrame = nil
            pcall(function()
                local igui = PlayerGui:WaitForChild("ReactGameIntermission", 5)
                IntermissionFrame = igui and igui:WaitForChild("Frame", 5)
            end)
            if not IntermissionFrame then break end

            local buttons = IntermissionFrame:FindFirstChild("buttons")
            local veto = buttons and buttons:FindFirstChild("veto")
            local VetoValue = veto and (veto:FindFirstChild("value") or veto:FindFirstChildWhichIsA("TextLabel"))
            local VetoText = VetoValue and VetoValue.Text or ""
            local current, total = nil, nil
            
            if VetoText ~= "" then
                if not VetoText:find("Veto") then
                    return false 
                end

                local currentStr, totalStr = VetoText:match("(%d+)/(%d+)")
                current, total = tonumber(currentStr), tonumber(totalStr)

                if not hasVoted and total and total > 0 and (current == 0 or current < total) then
                    pcall(function()
                        local RemoteEvent = ReplicatedStorage:FindFirstChild("RemoteEvent") or ReplicatedStorage:WaitForChild("RemoteEvent", 5)
                        if RemoteEvent then
                            RemoteEvent:FireServer("LobbyVoting", "Veto")
                        end
                    end)
                    hasVoted = true
                end
            end

            local found = false
            for _, g in ipairs(workspace:GetDescendants()) do
                if g:IsA("SurfaceGui") and g.Name == "MapDisplay" then
                    local t = g:FindFirstChild("Title")
                    if t and (t.Text == name or normalizeString(t.Text) == normalizeString(name)) then
                        found = true
                        break
                    end
                end
            end

            task.wait(1)

            local TotalPlayer = #Players:GetChildren()
            local isFull = (VetoText == "Veto (" .. TotalPlayer .. "/" .. TotalPlayer .. ")")
                or (total and total > 0 and current and current >= total)

        until found or isFull or (os.time() - startTime > 35)

        for _, g in ipairs(workspace:GetDescendants()) do
            if g:IsA("SurfaceGui") and g.Name == "MapDisplay" then
                local t = g:FindFirstChild("Title")
                if t and (t.Text == name or normalizeString(t.Text) == normalizeString(name)) then return true end
            end
        end

        return false
    end

    local function GetAvailableMaps()
        local available = {}
        pcall(function()
            for _, g in ipairs(workspace:GetDescendants()) do
                if g:IsA("SurfaceGui") and g.Name == "MapDisplay" then
                    local t = g:FindFirstChild("Title")
                    if t and t:IsA("TextLabel") and t.Text and t.Text ~= "" then
                        local mapName = t.Text:gsub("^%s+", ""):gsub("%s+$", "")
                        available[mapName] = true
                        available[mapName:lower()] = true
                        available[normalizeString(mapName)] = true
                    end
                end
            end
        end)
        return available
    end

    AutoGoldModule.CastMapVote = CastMapVote
    AutoGoldModule.LobbyReadyUp = LobbyReadyUp
    AutoGoldModule.SelectMapOverride = SelectMapOverride
    AutoGoldModule.IsMapAvailable = IsMapAvailable
    AutoGoldModule.GetAvailableMaps = GetAvailableMaps
end

function AutoGoldModule.GameInfo(name: string?, list: { any }?): string?
    if not Globals.AutoGold and not Globals.AutoTrials and not Globals.AutoEvo and not Globals.MultiplayerEnabled then
        return nil
    end

    if isMapIntermissionHandling then
        while isMapIntermissionHandling do
            task.wait(0.5)
        end
        return lastVotedIntermissionMap
    end

    if intermissionMapHandled and lastVotedIntermissionMap then
        return lastVotedIntermissionMap
    end

    local voteGui = PlayerGui:WaitForChild("ReactGameIntermission", 20)
    if not (voteGui and voteGui.Enabled and voteGui:WaitForChild("Frame", 5)) then return nil end
    if not Globals.AutoGold and not Globals.AutoTrials and not Globals.AutoEvo and not Globals.MultiplayerEnabled then return nil end

    isMapIntermissionHandling = true

    local stratChoice = Globals.SelectedFallback
    if stratChoice == "Smart Auto" then
        stratChoice = resolveSmartFallback()
    end
    local isHardcoreRequest = (name and normalizeString(tostring(name)) == "hardcore")

    -- 1. Resolve matching configuration
    local config = nil
    if name and FallbackConfigs and FallbackConfigs[name] then
        config = FallbackConfigs[name]
    elseif name and AutoGoldModule.Configs and AutoGoldModule.Configs[name] then
        config = AutoGoldModule.Configs[name]
    end

    -- Do not overwrite fallback config with crate config if a specific mode is requested!
    if not config and (Globals.AutoGold or Globals.AutoEvo or currentMatchMode == "AutoGold" or currentMatchMode == "AutoEvo") then
        local crateCfg = getCurrentCrateConfig(isHardcoreRequest and "Gems" or nil)
        if crateCfg then config = crateCfg end
    end

    if not config and isHardcoreRequest then
        local crateCfg = getCurrentCrateConfig("Gems")
        if crateCfg then config = crateCfg end
    end

    if not config then
        if FallbackConfigs and FallbackConfigs[stratChoice] then
            config = FallbackConfigs[stratChoice]
        elseif AutoGoldModule.Configs and AutoGoldModule.Configs[stratChoice] then
            config = AutoGoldModule.Configs[stratChoice]
        end
    end

    -- 1b. Check if 'name' corresponds to a Trial definition in StaticTrialDefinitions
    local trialTargetMap = nil
    local trialDefinitions = PlayerDataHandler and PlayerDataHandler.StaticTrialDefinitions
    if name and type(trialDefinitions) == "table" then
        local normName = normalizeString(tostring(name))
        for _, def in ipairs(trialDefinitions) do
            if normalizeString(def.Name) == normName or normalizeString(def.Title) == normName then
                trialTargetMap = def.Map
                break
            end
        end
    end

    -- 2. Determine strictly selected map
    local selectedMap = nil
    if trialTargetMap then
        selectedMap = trialTargetMap
    elseif name and not (FallbackConfigs and FallbackConfigs[name]) and not (AutoGoldModule.Configs and AutoGoldModule.Configs[name]) and name ~= "" and normalizeString(tostring(name)) ~= "hardcore" then
        selectedMap = name
    elseif config and config.Maps and #config.Maps > 0 then
        selectedMap = config.Maps[1]
        for _, m in ipairs(config.Maps) do
            for _, g in ipairs(workspace:GetDescendants()) do
                if g:IsA("SurfaceGui") and g.Name == "MapDisplay" then
                    local t = g:FindFirstChild("Title")
                    if t and (t.Text == m or normalizeString(t.Text) == normalizeString(m)) then
                        selectedMap = m
                        break
                    end
                end
            end
            if selectedMap == m then break end
        end
    elseif isHardcoreRequest then
        selectedMap = "Wretched Front"
    else
        selectedMap = "Lay By"
    end

    -- 3. Cast modifier votes
    local modifiers = (list and next(list)) and list or (config and (config.Modifiers or config.Modifers)) or Globals.Modifiers
    if typeof(CastModifierVote) == "function" then
        pcall(CastModifierVote, modifiers)
    end

    local vipActive = isVipOrPrivateServer()

    if vipActive then
        warn(string.format("[ServiceHub Map Check] VIP / Private Server detected. Overriding map: %s", tostring(selectedMap)))
        AutoGoldModule.SelectMapOverride(selectedMap, "vip")

        intermissionMapHandled = true
        isMapIntermissionHandling = false
        lastVotedIntermissionMap = selectedMap
        return selectedMap
    else
        warn(string.format("[ServiceHub Map Check] Checking availability / Vetoing for map '%s'...", tostring(selectedMap)))
        logActivity(string.format("Intermission: Checking availability for '%s'...", tostring(selectedMap)), "info")

        local isAvailable = AutoGoldModule.IsMapAvailable(selectedMap)

        if isAvailable then
            warn(string.format("[ServiceHub Map Check] Found map '%s'. Casting vote...", tostring(selectedMap)))
            logActivity(string.format("Intermission: Voting for selected map '%s'", tostring(selectedMap)), "info")
            AutoGoldModule.SelectMapOverride(selectedMap)

            intermissionMapHandled = true
            isMapIntermissionHandling = false
            lastVotedIntermissionMap = selectedMap
            return selectedMap
        else
            warn(string.format("[ServiceHub Map Check] Selected map '%s' not available after Veto. Returning to Smart Lobby...", tostring(selectedMap)))
            logActivity(string.format("Intermission: Map '%s' missing after Veto. Teleporting to Smart Lobby...", tostring(selectedMap)), "warn")
            isMapIntermissionHandling = false
            intermissionMapHandled = false
            SmartTeleportToLobby()
            return nil
        end
    end
end

function AutoGoldModule.QueueGold(stratChoice: string?, optFarmType: string?)
    if (not Globals.AutoTrials and not Globals.AutoGold and not Globals.AutoEvo and not Globals.MultiplayerEnabled) or game.PlaceId ~= LOBBY_PLACE_ID then return end
    local farmType = optFarmType or Globals.AutoFarmType or "Coins"
    if Globals.AutoEvo and not Globals.AutoGold and not Globals.AutoTrials then
        farmType = optFarmType or Globals.CurrentEvoFarmType or "Coins"
    end
    if farmType and typeof(saveActiveFarmType) == "function" then
        saveActiveFarmType(farmType)
    end
    Globals.AutoFarmType = farmType
    local config = getCurrentCrateConfig(farmType)
    if not config then return end

    local isMultiHost = Globals.MultiplayerEnabled and Globals.MultiplayerIsHost
    local partyCount = isMultiHost and 2 or 1

    local remoteFunction = ReplicatedStorage:FindFirstChild("RemoteFunction")

    if remoteFunction and remoteFunction:IsA("RemoteFunction") then
        pcall(function()
            remoteFunction:InvokeServer("Multiplayer", "v2:stop")
        end)
        task.wait(0.1)
        pcall(function()
            if farmType == "Gems" then
                return remoteFunction:InvokeServer(
                    "Multiplayer",
                    "v2:start",
                    {
                        difficulty = "Easy",
                        mode = "hardcore",
                        count = partyCount
                    }
                )
            else
                return remoteFunction:InvokeServer(
                    "Multiplayer",
                    "v2:start",
                    {
                        difficulty = config.Mode,
                        mode = "survival",
                        count = partyCount
                    }
                )
            end
        end)
    end
end

--==============================================================================
-- Match Status & Strategy Execution Handlers
--==============================================================================
local function GetMatchStatus(): string?
    local uiRoot = PlayerGui:FindFirstChild("ReactGameNewRewards")
    if not uiRoot then return nil end

    local mainFrame = uiRoot:FindFirstChild("Frame")
    if not mainFrame or not mainFrame.Visible then return nil end

    local gameOver = mainFrame:FindFirstChild("gameOver")
    if not gameOver or not gameOver.Visible then return nil end

    local rewardsScreen = gameOver:FindFirstChild("RewardsScreen")
    if not rewardsScreen or not rewardsScreen.Visible then return nil end

    local topBanner = rewardsScreen:FindFirstChild("RewardBanner")
    if not topBanner then return nil end

    local label = topBanner:FindFirstChild("textLabel") or topBanner:FindFirstChildOfClass("TextLabel")
    if not label then return nil end

    local success, txt = pcall(function() return label.Text:upper() end)
    if not success or not txt or txt == "" then return nil end

    if txt:find("TRIUMPH") or txt:find("VICTORY") or txt:find("WIN") then
        return "WIN"
    elseif txt:find("LOST") or txt:find("DEFEAT") or txt:find("FAIL") then
        return "LOSS"
    end
    return nil
end

--==============================================================================
-- Trial & Rotation Check Helpers
--==============================================================================
local function checkIsTrialWon(trialName: string?): boolean
    if not trialName or trialName == "" then return false end
    local normTarget = normalizeString(trialName)
    if PlayerDataHandler and typeof(PlayerDataHandler.IsTrialWon) == "function" then
        local ok, won = pcall(function()
            return PlayerDataHandler:IsTrialWon(trialName)
        end)
        if ok and won == true then return true end
    end
    if PlayerDataHandler and typeof(PlayerDataHandler.GetTrialsStatus) == "function" then
        local ok, status = pcall(function()
            return PlayerDataHandler:GetTrialsStatus()
        end)
        if ok and status and type(status) == "table" and status.Won then
            for _, n in ipairs(status.Won) do
                if normalizeString(n) == normTarget then
                    return true
                end
            end
        end
    end
    local trialDefs = (PlayerDataHandler and typeof(PlayerDataHandler.StaticTrialDefinitions) == "table" and PlayerDataHandler.StaticTrialDefinitions)
        or StaticTrialDefinitions
    if type(trialDefs) == "table" then
        for _, t in ipairs(trialDefs) do
            if normalizeString(t.Name) == normTarget or normalizeString(t.Title) == normTarget or normalizeString(t.Map) == normTarget then
                if PlayerDataHandler and typeof(PlayerDataHandler.IsTrialWon) == "function" then
                    local ok, won = pcall(function()
                        return PlayerDataHandler:IsTrialWon(t.Name) or PlayerDataHandler:IsTrialWon(t.Title)
                    end)
                    if ok and won == true then return true end
                end
            end
        end
    end
    return false
end

local function shouldSwitchToUnownedTrial(): boolean
    if not (isPremiumUser and Globals.AutoTrials and Globals.TrialFarmMode == "Progression Mode") then
        return false
    end
    if not PlayerDataHandler then return false end
    local curTrial = nil
    if typeof(PlayerDataHandler.GetCurrentTrial) == "function" then
        local ok, res = pcall(function() return PlayerDataHandler:GetCurrentTrial() end)
        if ok and res and type(res) == "table" then
            curTrial = res.Name or res.title or res.Title
        end
    end
    if not curTrial then return false end
    local isWon = checkIsTrialWon(curTrial)
    if isWon then return false end

    -- Check filter
    local selectedTrials = Globals.SelectedTrials or {}
    local inFilter = false
    local normCur = normalizeString(curTrial)
    if type(selectedTrials) == "table" then
        for _, s in ipairs(selectedTrials) do
            if normalizeString(s) == normCur then
                inFilter = true
                break
            end
        end
    end
    if not inFilter then return false end

    -- Check requirements
    local config = RevampAutoTrials and (RevampAutoTrials[curTrial] or RevampAutoTrials[normCur])
    if not config then return false end
    local reqLvl = config.Level or config.level or 175
    local pLvl = PlayerDataHandler:GetLevel() or 0
    if pLvl < reqLvl then return false end

    -- Check towers
    local towersConfig = config.Towers or config.towers
    if type(towersConfig) == "table" then
        local hasDeck = false
        local decksToCheck = {}
        if towersConfig[1] then
            table.insert(decksToCheck, towersConfig)
        else
            for _, deck in pairs(towersConfig) do
                if type(deck) == "table" then
                    table.insert(decksToCheck, deck)
                end
            end
        end
        for _, deck in ipairs(decksToCheck) do
            local allOwned = true
            for _, tName in ipairs(deck) do
                if tName and tName ~= "" and not PlayerDataHandler:IsTowerOwned(tName) then
                    allOwned = false
                    break
                end
            end
            if allOwned then
                hasDeck = true
                break
            end
        end
        if not hasDeck then return false end
    end

    return true
end

local function fireSkipVoteUntilTrue(): boolean
    local Event = game:GetService("ReplicatedStorage"):FindFirstChild("RemoteFunction")
    if not Event then return false end

    local success, result = pcall(function()
        local Result = table.pack(Event:InvokeServer(
            "Voting",
            "Skip"
        ))

        local ExpectedResult = table.unpack({
            true
        })

        return Result[1] == ExpectedResult
    end)

    return success and (result == true)
end

local function triggerRematchVote(): boolean
    local fired = false
    -- 1. Fire RemoteEvent RE:Rematch
    pcall(function()
        local gm = ReplicatedStorage:FindFirstChild("Network") and ReplicatedStorage.Network:FindFirstChild("GameManager")
        local reMatch = gm and gm:FindFirstChild("RE:Rematch")
        if reMatch and reMatch:IsA("RemoteEvent") then
            reMatch:FireServer()
            fired = true
        end
    end)

    -- 2. Click PlayAgain / Retry / Restart button in ReactGameNewRewards GUI
    pcall(function()
        local gui = PlayerGui:FindFirstChild("ReactGameNewRewards")
        if gui then
            local candidateNames = { "PlayAgain", "Retry", "Restart" }
            for _, cName in ipairs(candidateNames) do
                local elem = gui:FindFirstChild(cName, true)
                if elem then
                    local btn = elem:FindFirstChild("button")
                        or elem:FindFirstChildOfClass("ImageButton")
                        or elem:FindFirstChildOfClass("TextButton")
                        or (elem:IsA("GuiButton") and elem)
                    if btn and getconnections then
                        for _, conn in ipairs(getconnections(btn.Activated)) do conn:Fire(); fired = true end
                        for _, conn in ipairs(getconnections(btn.MouseButton1Click)) do conn:Fire(); fired = true end
                    end
                end
            end
        end
    end)

    -- 3. Invoke RemoteFunction voting commands
    pcall(function()
        local rf = ReplicatedStorage:FindFirstChild("RemoteFunction")
        if rf then
            pcall(function() rf:InvokeServer("Voting", "Skip") end)
            pcall(function() rf:InvokeServer("Voting", "Restart") end)
            pcall(function() rf:InvokeServer("Voting", "Retry") end)
            pcall(function() rf:InvokeServer("Voting", "Rematch") end)
            fired = true
        end
    end)

    return fired
end

local function isGemsLoseMatch(): boolean
    local liveGameMode = ""
    local liveDifficulty = ""
    pcall(function()
        local gsr = game.ReplicatedStorage:FindFirstChild("StateReplicators") and game.ReplicatedStorage.StateReplicators:FindFirstChild("GameStateReplicator")
        if gsr then
            liveGameMode = tostring(gsr:GetAttribute("GameMode") or gsr:GetAttribute("Mode") or ""):lower()
            liveDifficulty = tostring(gsr:GetAttribute("Difficulty") or ""):lower()
        end
    end)
    if liveGameMode == "hardcore" or liveDifficulty == "hardcore" then
        return true
    end

    local savedTrial = ""
    if typeof(loadTrialState) == "function" then
        pcall(function() savedTrial = tostring(loadTrialState() or ""):lower() end)
    end
    if savedTrial == "hardcore" then return true end

    local savedFarm = (typeof(loadActiveFarmType) == "function") and tostring(loadActiveFarmType() or ""):lower() or ""
    if savedFarm == "gems" then return true end

    if tostring(Globals.AutoFarmType or ""):lower() == "gems" then return true end
    if tostring(Globals.CurrentEvoFarmType or ""):lower() == "gems" then return true end

    return false
end

-- Returns true only for an active Auto Evo run that is intentionally farming a
-- loss strategy and has not reached its current progression milestone yet.
-- Keep this decision independent of volatile UI state: it is used by every
-- match-end path to prevent a loss from falling through to SmartLobby.
local function shouldRetryAutoEvoLoss(status: string): boolean
    if status ~= "LOSS" then
        return false
    end

    local isEvoActive = (Globals.AutoEvo == true) or (currentMatchMode == "AutoEvo")
    if not isEvoActive then
        local savedMode = (typeof(loadActiveMode) == "function") and loadActiveMode() or ""
        if savedMode == "AutoEvo" then
            isEvoActive = true
        end
    end
    if not isEvoActive then
        return false
    end

    -- Determine if this Auto Evo match is running a Lose strategy:
    local usesLoseStrategy = false
    local evoStratLower = tostring(Globals.EvoStrat or "Lose"):lower()
    local stratLower = tostring(Globals.Strat or ""):lower()
    local farmTypeLower = tostring(Globals.CurrentEvoFarmType or Globals.AutoFarmType or ""):lower()

    if evoStratLower == "lose" or stratLower == "lose" or farmTypeLower == "gems" then
        usesLoseStrategy = true
    elseif typeof(isGemsLoseMatch) == "function" and isGemsLoseMatch() then
        usesLoseStrategy = true
    elseif typeof(analyzeAutoEvoRequirements) == "function" then
        local ok, analysis = pcall(analyzeAutoEvoRequirements)
        if ok and analysis and (tostring(analysis.stratChoice or ""):lower() == "lose" or tostring(analysis.farmType or ""):lower() == "gems") then
            usesLoseStrategy = true
        end
    end

    if not usesLoseStrategy then
        return false
    end

    local reachedMilestone = false
    if typeof(checkAutoEvoMilestonesReached) == "function" then
        local ok, reached = pcall(checkAutoEvoMilestonesReached)
        reachedMilestone = ok and (reached == true)
    end

    return not reachedMilestone
end

local getCurrencyAndTargets: () -> (number, number, number, number, string, string)
do
    local cachedDynamicTargetCoins = 0
    local cachedDynamicTargetGems = 0
    local lastDynamicTargetCalcTick = 0

    getCurrencyAndTargets = function(): (number, number, number, number, string, string)
    local coins = 0
    local gems = 0
    if PlayerDataHandler then
        pcall(function()
            if typeof(PlayerDataHandler.GetCoins) == "function" then
                coins = PlayerDataHandler:GetCoins() or 0
            end
            if typeof(PlayerDataHandler.GetGems) == "function" then
                gems = PlayerDataHandler:GetGems() or 0
            end
        end)
    end

    local targetCoins = tonumber(Globals.TargetCoins) or 0
    local targetGems = tonumber(Globals.TargetGems) or 0

    local nowClock = os.clock()
    if targetCoins <= 0 and targetGems <= 0 and (nowClock - lastDynamicTargetCalcTick < 4) and lastDynamicTargetCalcTick > 0 then
        targetCoins = cachedDynamicTargetCoins
        targetGems = cachedDynamicTargetGems
    else
        lastDynamicTargetCalcTick = nowClock
        -- Dynamic Target Coins resolution if manual target not specified
    if targetCoins <= 0 and PlayerDataHandler then
        if (Globals.BuyMissingCoinsTower or Globals.TrialFarmMode == "Progression Mode") and TowerList and TowerList.Coins then
            for _, t in ipairs(TowerList.Coins) do
                local clean = normalizeString(t.Name)
                if clean ~= "warden" and clean ~= "cowboy" and clean ~= "saboteur" and clean ~= "sabboteur" then
                    local isOwned = false
                    pcall(function() isOwned = PlayerDataHandler:IsTowerOwned(t.Name) end)
                    if not isOwned then
                        targetCoins = tonumber(t.Cost) or 0
                        break
                    end
                end
            end
        end
        if targetCoins <= 0 and (Globals.AutoEvo or Globals.BuyMissingEvoTower) and TowerList and TowerList.Evo then
            for _, e in ipairs(TowerList.Evo) do
                local isOwned = false
                pcall(function()
                    if PlayerDataHandler:IsTowerOwned(e.Name) then
                        isOwned = true
                    elseif typeof(isTowerEvoComplete) == "function" then
                        local base = (EvoToTower and EvoToTower[e.Name]) or e.Name:gsub("^Evolved%s*", "")
                        if isTowerEvoComplete(e.Name) or isTowerEvoComplete(base) then
                            isOwned = true
                        end
                    end
                end)
                if not isOwned then
                    targetCoins = tonumber(e.Coins) or 15000
                    break
                end
            end
        end
        if targetCoins <= 0 and Globals.BuyMissingGoldSkins then
            local hasUnownedGold = false
            if TowerList and TowerList.Golden then
                for _, g in ipairs(TowerList.Golden) do
                    local base = g.Name:gsub("^Golden%s+", "")
                    local isOwned = false
                    pcall(function()
                        isOwned = PlayerDataHandler:IsGoldenOwned(g.Name) or PlayerDataHandler:IsGoldenOwned(base)
                    end)
                    if not isOwned then
                        hasUnownedGold = true
                        break
                    end
                end
            end
            if hasUnownedGold then
                targetCoins = 50000
            end
        end
    end

    -- Dynamic Target Gems resolution if manual target not specified
    if targetGems <= 0 and PlayerDataHandler then
        if (Globals.BuyMissingGemTower or Globals.TrialFarmMode == "Progression Mode") and TowerList and TowerList.Gems then
            for _, t in ipairs(TowerList.Gems) do
                local isOwned = false
                pcall(function() isOwned = PlayerDataHandler:IsTowerOwned(t.Name) end)
                if not isOwned then
                    targetGems = tonumber(t.Cost) or 0
                    break
                end
            end
        end
        if targetGems <= 0 and (Globals.AutoEvo or Globals.BuyMissingEvoTower) and TowerList and TowerList.Evo then
            for _, e in ipairs(TowerList.Evo) do
                local isOwned = false
                pcall(function()
                    if PlayerDataHandler:IsTowerOwned(e.Name) then
                        isOwned = true
                    elseif typeof(isTowerEvoComplete) == "function" then
                        local base = (EvoToTower and EvoToTower[e.Name]) or e.Name:gsub("^Evolved%s*", "")
                        if isTowerEvoComplete(e.Name) or isTowerEvoComplete(base) then
                            isOwned = true
                        end
                    end
                end)
                if not isOwned then
                    targetGems = tonumber(e.Gems) or 4500
                    break
                end
            end
        end
    end
    cachedDynamicTargetCoins = targetCoins
    cachedDynamicTargetGems = targetGems
end

    local coinsStr = string.format("%s / %s", formatNumberWithCommas(coins), targetCoins > 0 and formatNumberWithCommas(targetCoins) or "0")
    local gemsStr = string.format("%s / %s", formatNumberWithCommas(gems), targetGems > 0 and formatNumberWithCommas(targetGems) or "0")

    return coins, targetCoins, gems, targetGems, coinsStr, gemsStr
    end
end

local function checkShouldExitGemsLose(): (boolean, string?)
    local isOwnedActive = (Globals.TrialFarmMode == "Progression Mode" and Globals.AutoTrials)
    if not Globals.AutoGold and not Globals.AutoEvo and not Globals.AutoTrials and not isOwnedActive and not Globals.MultiplayerEnabled and currentMatchMode ~= "AutoGold" and currentMatchMode ~= "AutoEvo" and currentMatchMode ~= "AutoTrials" then
        return true, "Automation stopped by user"
    end

    if Globals.IsConfigDirty or (isMatchConfigDirty and isMatchConfigDirty()) then
        Globals.IsConfigDirty = false
        return true, "Configuration changed mid-match"
    end

    -- "or when the next trial is up wait until get match statys check first if the trial is owned if yes stay of course"
    if typeof(shouldSwitchToUnownedTrial) == "function" and shouldSwitchToUnownedTrial() then
        return true, "Unowned rotation trial is ready in lobby!"
    end

    -- "until it reach the gems it needed"
    local coins, targetCoins, currentWalletGems, targetGems, coinsDisplay, gemsDisplay = getCurrencyAndTargets()

    if targetGems > 0 and currentWalletGems >= targetGems then
        return true, string.format("Target Gems reached (%s)", gemsDisplay)
    end

    if Globals.BuyMissingGemTower and TowerList and TowerList.Gems and PlayerDataHandler then
        local allGemOwned = (typeof(isGemTowersMaxed) == "function") and isGemTowersMaxed() or false
        if allGemOwned then
            return true, "All hardcore gem towers are owned!"
        else
            for _, t in ipairs(TowerList.Gems) do
                local owned = false
                pcall(function() owned = PlayerDataHandler:IsTowerOwned(t.Name) end)
                if not owned then
                    local cost = tonumber(t.Cost) or 0
                    if cost > 0 and currentWalletGems >= cost then
                        return true, string.format("Reached %d gems needed for %s!", cost, t.Name)
                    end
                    break
                end
            end
        end
    end

    if (Globals.AutoEvo or Globals.BuyMissingEvoTower) then
        if typeof(checkAutoEvoMilestonesReached) == "function" then
            local milestone, reason = checkAutoEvoMilestonesReached()
            if milestone then
                return true, tostring(reason)
            end
        end
        if typeof(analyzeAutoEvoRequirements) == "function" then
            local ok, evoAnalysis = pcall(analyzeAutoEvoRequirements)
            if ok and evoAnalysis and evoAnalysis.farmType == "Gems" and evoAnalysis.gemCost then
                if currentWalletGems >= evoAnalysis.gemCost then
                    return true, string.format("Reached %d gems needed for %s evo!", evoAnalysis.gemCost, tostring(evoAnalysis.activeTower))
                end
            end
        end
    end

    return false, nil
end

local function handleMultiplayerMatchEnd(status: string): boolean
    local role = Globals.MultiplayerIsHost and "Host" or "P2"
    local mpMode = tostring(Globals.MultiplayerMode or "Trial Mode")
    sendDiscordWebhook(status, string.format("Multiplayer %s (%s)", role, mpMode))
    logActivity(string.format("[Multiplayer %s] Match ended (%s). Returning to lobby / private server.", role, status), "info")
    warn(string.format("[ServiceHub Multiplayer] Match finished with status '%s'. Coordinating exit...", tostring(status)))

    local pvCode = extractPrivateCode(Globals.MultiplayerPrivateServerCode or "")
    if pvCode ~= "" then
        local tpOk = teleportToPrivateServer(pvCode)
        if not tpOk then
            SmartTeleportToLobby()
        end
    else
        SmartTeleportToLobby()
    end
    return true
end

local function handleAutoEvoMatchEnd(status: string): boolean
    sendDiscordWebhook(status, "AutoEvo")

    -- 1. Auto Evo Milestone Check
    local milestoneReached, milestoneReason = checkAutoEvoMilestonesReached()
    if milestoneReached then
        logActivity("Auto Evo Milestone: " .. tostring(milestoneReason) .. "! Returning to Smart Lobby.", "success")
        if UI and UI.Window and typeof(UI.Window.Notify) == "function" then
            RunAsExecutor(function()
                UI.Window:Notify({
                    Title = "AUTO EVO MILESTONE",
                    Desc = tostring(milestoneReason) .. "! Teleporting to Smart Lobby.",
                    Duration = 8,
                    Type = "success"
                })
            end)()
        end
        Globals.IsConfigDirty = false
        Globals.AutoEvoMilestoneReached = false
        SmartTeleportToLobby()
        return true
    end

    -- 2. Win Strategy on WIN -> Always Smart Lobby
    if status == "WIN" then
        logActivity("[AutoEvo Win] Match won! Returning to Smart Lobby.", "success")
        SmartTeleportToLobby()
        return true
    end

    -- 3. In Progression Mode: If an unowned rotation trial is waiting, return to lobby to beat it
    if typeof(shouldSwitchToUnownedTrial) == "function" and shouldSwitchToUnownedTrial() then
        logActivity("[Progression Mode] Unowned rotation trial ready! Teleporting to lobby to queue trial.", "info")
        SmartTeleportToLobby()
        return true
    end

    -- 4. User Changed Settings mid-match
    if Globals.IsConfigDirty or (isMatchConfigDirty and isMatchConfigDirty()) then
        Globals.IsConfigDirty = false
        Globals.AutoEvoMilestoneReached = false
        if UI and UI.Window and typeof(UI.Window.Notify) == "function" then
            RunAsExecutor(function()
                UI.Window:Notify({
                    Title = "CONFIG CHANGED",
                    Desc = "Settings updated mid-match. Returning to Smart Lobby.",
                    Duration = 6,
                    Type = "info"
                })
            end)()
        end
        SmartTeleportToLobby()
        return true
    end

    -- 5. Lose Strategy on LOSS -> STAY IN GAME, DO NOT SMART LOBBY!
    if shouldRetryAutoEvoLoss(status) then
        logActivity("[AutoEvo Lose] Milestone not reached; staying in-game to vote restart & re-execute strategy.", "info")
        warn("[ServiceHub AutoEvo] Match ended (LOSS) -> Auto Evo milestone not reached. Initiating in-game retry without SmartLobby.")
        return false
    end

    -- 6. Fallback (e.g. Win strategy that suffered a loss)
    SmartTeleportToLobby()
    return true
end

local function handleAutoTrialsMatchEnd(status: string): boolean
    sendDiscordWebhook(status, "AutoTrials")

    if Globals.IsConfigDirty or (isMatchConfigDirty and isMatchConfigDirty()) then
        Globals.IsConfigDirty = false
        if UI and UI.Window and typeof(UI.Window.Notify) == "function" then
            RunAsExecutor(function()
                UI.Window:Notify({
                    Title = "CONFIG CHANGED",
                    Desc = "Settings updated mid-match. Teleporting to Smart Lobby for a clean fresh match.",
                    Duration = 8,
                    Type = "warning"
                })
            end)()
        end
        SmartTeleportToLobby()
        return true
    end

    local isPlayingFallback = false
    pcall(function()
        local gsr = game.ReplicatedStorage:FindFirstChild("StateReplicators") and game.ReplicatedStorage.StateReplicators:FindFirstChild("GameStateReplicator")
        if gsr then
            local liveTrial = tostring(gsr:GetAttribute("GlobalTrial") or "None")
            if liveTrial == "None" or liveTrial == "" then
                isPlayingFallback = true
            end
        end
    end)
    
    if isPlayingFallback then
        SmartTeleportToLobby()
        return true
    end

    if not Globals.AutoTrials then
        SmartTeleportToLobby()
        return true
    end

    -- Free user in Auto Trials:
    -- Win -> SmartLobby, Lose -> Smart Lobby
    if not isPremiumUser then
        SmartTeleportToLobby()
        return true
    end

    -- If Farm Only or Progression Mode is active, winning the trial means it has been beaten.
    -- Return to lobby instead of rematching endlessly.
    if (Globals.FarmOnly == "Farm Only" or Globals.TrialFarmMode == "Progression Mode") and status == "WIN" then
        SmartTeleportToLobby()
        return true
    end

    -- Premium User ONLY in Auto Trials:
    -- Win -> stay in-game for RE:Rematch
    -- Lose -> stay in-game for attempts 1/5
    return false
end

local function handleAutoGoldMatchEnd(status: string): boolean
    sendDiscordWebhook(status, "AutoGold")

    if not isPremiumUser or not Globals.AutoGold then
        SmartTeleportToLobby()
        return true
    end

    -- Auto Gold: Win ALWAYS Smart Lobby
    if status == "WIN" then
        SmartTeleportToLobby()
        return true
    end

    -- In Progression Mode: If an unowned trial is waiting in rotation, return to lobby to beat it!
    if typeof(shouldSwitchToUnownedTrial) == "function" and shouldSwitchToUnownedTrial() then
        logActivity("[Progression Mode] Unowned rotation trial ready! Teleporting to lobby to queue trial.", "info")
        SmartTeleportToLobby()
        return true
    end

    local tc = tonumber(Globals.TargetCoins) or 0
    local tg = tonumber(Globals.TargetGems) or 0
    local currentWalletCoins = 0
    local currentWalletGems = 0
    if PlayerDataHandler then
        pcall(function() currentWalletCoins = PlayerDataHandler:GetCoins() or 0 end)
        pcall(function() currentWalletGems = PlayerDataHandler:GetGems() or 0 end)
    end

    -- Check Coins Reach & Gems Reach for AutoGold (Active Premium Users Only):
    if isPremiumUser and ((tc > 0 and currentWalletCoins >= tc) or (tg > 0 and currentWalletGems >= tg)) then
        Globals.AutoGold = false
        SetSetting("AutoGold", false)
        if UI and UI.AutoGoldToggle then UI.AutoGoldToggle:SetValue(false) end
        local reachedMsg = (tc > 0 and currentWalletCoins >= tc)
            and string.format("Coins Reach (%s / %s Coins)", formatNumberWithCommas(currentWalletCoins), formatNumberWithCommas(tc))
            or string.format("Gems Reach (%s / %s Gems)", formatNumberWithCommas(currentWalletGems), formatNumberWithCommas(tg))
        logActivity("AutoGold target reached (" .. reachedMsg .. ")! Teleporting to lobby.", "success")
        if UI and UI.Window and typeof(UI.Window.Notify) == "function" then
            RunAsExecutor(function()
                UI.Window:Notify({
                    Title = "TARGET REACHED",
                    Desc = reachedMsg .. "! Teleporting to Smart Lobby.",
                    Duration = 8,
                    Type = "success"
                })
            end)()
        end
        Globals.IsConfigDirty = false
        SmartTeleportToLobby()
        return true
    end

    if Globals.IsConfigDirty or (isMatchConfigDirty and isMatchConfigDirty()) then
        Globals.IsConfigDirty = false
        if UI and UI.Window and typeof(UI.Window.Notify) == "function" then
            RunAsExecutor(function()
                UI.Window:Notify({
                    Title = "CONFIG CHANGED",
                    Desc = "Settings updated mid-match. Returning to Smart Lobby.",
                    Duration = 6,
                    Type = "info"
                })
            end)()
        end
        SmartTeleportToLobby()
        return true
    end

    -- IF LOSE strat on LOSS: it should NOT SMART lobby !! instead it will just RETRY until target reached!
    if (Globals.Strat == "Lose" or isGemsLoseMatch()) and status == "LOSS" then
        return false
    end

    SmartTeleportToLobby()
    return true
end

local function shouldTeleportOnMatchEnd(status: string): boolean
    if isLateExecution then
        local reason = string.format("Mid-game re-execution at Wave %d finished", initialExecutionWave)
        if UI and UI.Window and typeof(UI.Window.Notify) == "function" then
            RunAsExecutor(function()
                UI.Window:Notify({
                    Title = "RE-EXECUTION RESET",
                    Desc = reason .. "! Teleporting to Smart Lobby for a clean fresh match.",
                    Duration = 8,
                    Type = "warning"
                })
            end)()
        end
        Globals.IsConfigDirty = false
        isLateExecution = false
        SmartTeleportToLobby()
        return true
    end

    if Globals.MultiplayerEnabled or currentMatchMode == "Multiplayer" then
        return handleMultiplayerMatchEnd(status)
    elseif Globals.AutoEvo or currentMatchMode == "AutoEvo" then
        return handleAutoEvoMatchEnd(status)
    elseif Globals.AutoTrials or currentMatchMode == "AutoTrials" then
        return handleAutoTrialsMatchEnd(status)
    elseif Globals.AutoGold or currentMatchMode == "AutoGold" then
        return handleAutoGoldMatchEnd(status)
    end

    SmartTeleportToLobby()
    return true
end

activeStratThread = nil
local matchStratExecuted = false
local isStrategyExecuting = false
local failureCount = 0
local MAX_FAILURES = 5
local isHandlingEndMatch = false
local trialWatcherRunning = false
local autoGoldWatcherRunning = false
local autoEvoWatcherRunning = false
local multiplayerWatcherRunning = false
local scriptCache: { [string]: string } = {}

local function fetchStrategyScript(url: string): string?
    if not url or url == "" then return nil end
    if scriptCache[url] and #scriptCache[url] > 0 then
        return scriptCache[url]
    end

    -- 1. Try reading via readfile first if url matches a local file or local script path
    local okDirect, directContent = pcall(function()
        if (type(isfile) == "function" and isfile(url)) or (type(readfile) == "function" and not isfile) then
            return readfile(url)
        end
        return nil
    end)
    if okDirect and type(directContent) == "string" and #directContent > 0 then
        scriptCache[url] = directContent
        return directContent
    end

    local scriptName = url:match("([^/]+%.lua)$")
    local relativePath = url:match("main/(.+%.lua)$")
    local candidatePaths = {}
    if scriptName then
        table.insert(candidatePaths, scriptName)
    end
    if relativePath then
        table.insert(candidatePaths, relativePath)
    end

    for _, cand in ipairs(candidatePaths) do
        local localContent, pathUsed = readLocalFile(cand, {
            "[STAY]/[AutoTrailsFInal]/" .. cand,
            "[STAY]/" .. cand,
            cand,
            "Strategies/" .. cand,
            "[STAY]/Strategies/" .. cand,
        })
        if localContent and type(localContent) == "string" and #localContent > 0 then
            scriptCache[url] = localContent
            return localContent
        end
    end

    -- 2. Cloud fallback via safeHttpGet (secondary)
    local chunk = safeHttpGet(url, 3)
    if chunk and #chunk > 0 then
        scriptCache[url] = chunk
        return chunk
    end
    return nil
end

local compiledMacroCache = {}

local function executeActiveStrategy(mapName: string)
    local isEvoMatch = (currentMatchMode == "AutoEvo") or Globals.AutoEvo
    local isMultiFarm = Globals.MultiplayerEnabled and (Globals.MultiplayerMode == "Farm Mode")
    if not Globals.AutoGold and not Globals.AutoEvo and not isOwnedActive and not isMultiFarm and currentMatchMode ~= "AutoGold" and currentMatchMode ~= "AutoEvo" and currentMatchMode ~= "Multiplayer" then return end
    if isStrategyExecuting or matchStratExecuted then
        warn(string.format("[ServiceHub Strategy] Strategy already active/executed for '%s', skipping duplicate execution.", tostring(mapName)))
        return
    end
    isStrategyExecuting = true
    matchStratExecuted = true

    -- Detect if this match is Hardcore or on Wretched Front
    local normMap = string.lower(string.gsub(mapName or "", "[%s%p]+", ""))
    local isHardcoreMap = (normMap == "wretchedfront" or string.find(normMap, "wretched") ~= nil)
    local isHardcoreMode = false
    pcall(function()
        local gsr = ReplicatedStorage:FindFirstChild("StateReplicators")
            and ReplicatedStorage.StateReplicators:FindFirstChild("GameStateReplicator")
        if gsr then
            local gMode = tostring(gsr:GetAttribute("GameMode") or gsr:GetAttribute("Mode") or ""):lower()
            if gMode == "hardcore" then isHardcoreMode = true end
        end
    end)
    local isHardcoreMatch = isHardcoreMap or isHardcoreMode

    local config = getCurrentCrateConfig(isHardcoreMatch and "Gems" or nil)
    if not config and isHardcoreMatch then
        config = FallbackConfigs and FallbackConfigs["Hardcore"] or (CrateConfigs and CrateConfigs.Gems and CrateConfigs.Gems.Lose)
    end

    -- Ensure TDS API is loaded and globally accessible
    if not TDS or not getgenv().TDS then
        TDS = loadEmbeddedTDSAPI()
        if TDS then
            Globals.TDS = TDS
            pcall(function() getgenv().TDS = TDS end)
            pcall(function() _G.TDS = TDS end)
        end
    end

    -- Dynamically resolve active tower for AutoEvo if missing
    local activeTower = Globals.CurrentEvoActiveTower
    if isEvoMatch and not activeTower and typeof(analyzeAutoEvoRequirements) == "function" then
        local ok, evoAnalysis = pcall(analyzeAutoEvoRequirements)
        if ok and evoAnalysis and evoAnalysis.activeTower then
            activeTower = evoAnalysis.activeTower
            Globals.CurrentEvoActiveTower = activeTower
            if evoAnalysis.farmType then
                Globals.CurrentEvoFarmType = evoAnalysis.farmType
            end
        end
    end

    local scriptUrl: string? = nil
    local resolvedTowers: {string}? = nil

    -- 1. Try resolving from config directly
    if config and config.Scripts then
        if isEvoMatch and activeTower and config.Scripts[activeTower] then
            local towerScripts = config.Scripts[activeTower]
            if type(towerScripts) == "string" then
                scriptUrl = towerScripts
            elseif type(towerScripts) == "table" then
                scriptUrl = towerScripts[mapName]
                if not scriptUrl then
                    local normTarget = string.lower(string.gsub(mapName or "", "[%s%p]+", ""))
                    for mKey, mUrl in pairs(towerScripts) do
                        local normKey = string.lower(string.gsub(tostring(mKey), "[%s%p]+", ""))
                        if normKey == normTarget or string.find(normTarget, normKey) or string.find(normKey, normTarget) then
                            scriptUrl = mUrl
                            break
                        end
                    end
                end
                if not scriptUrl then
                    for _, mUrl in pairs(towerScripts) do
                        if type(mUrl) == "string" and #mUrl > 0 then
                            scriptUrl = mUrl
                            break
                        end
                    end
                end
            end
        else
            scriptUrl = config.Scripts[mapName]
            if not scriptUrl and type(config.Scripts) == "table" then
                local normTarget = string.lower(string.gsub(mapName or "", "[%s%p]+", ""))
                for mKey, mUrl in pairs(config.Scripts) do
                    if type(mUrl) == "string" then
                        local normKey = string.lower(string.gsub(tostring(mKey), "[%s%p]+", ""))
                        if normKey == normTarget or string.find(normTarget, normKey) or string.find(normKey, normTarget) then
                            scriptUrl = mUrl
                            break
                        end
                    elseif type(mUrl) == "table" then
                        if mUrl[mapName] then
                            scriptUrl = mUrl[mapName]
                            break
                        end
                        for innerKey, innerUrl in pairs(mUrl) do
                            local normKey = string.lower(string.gsub(tostring(innerKey), "[%s%p]+", ""))
                            if normKey == normTarget or string.find(normTarget, normKey) or string.find(normKey, normTarget) then
                                scriptUrl = innerUrl
                                break
                            end
                        end
                        if scriptUrl then break end
                    end
                end
            end
        end

        if config.Towers then
            if isEvoMatch and activeTower and type(config.Towers) == "table" and config.Towers[activeTower] then
                resolvedTowers = config.Towers[activeTower]
            else
                resolvedTowers = config.Towers
            end
        end
    end

    if type(scriptUrl) == "table" then
        scriptUrl = scriptUrl[mapName] or next(scriptUrl)
    end

    -- 2. Resilient Universal Fallbacks across PremConfigs for the specific map
    if not scriptUrl or scriptUrl == "" then
        local normTarget = string.lower(string.gsub(mapName or "", "[%s%p]+", ""))

        -- Special Handling: Wretched Front (Hardcore / Gems)
        if normTarget == "wretchedfront" or string.find(normTarget, "wretched") or isHardcoreMatch then
            if isEvoMatch and AutoEvoConfigs and AutoEvoConfigs.Gems and AutoEvoConfigs.Gems.Lose then
                local evoCfg = AutoEvoConfigs.Gems.Lose
                local tKey = activeTower
                if not tKey or not evoCfg.Scripts or not evoCfg.Scripts[tKey] then
                    tKey = evoCfg.Scripts and next(evoCfg.Scripts)
                end
                if tKey and evoCfg.Scripts and evoCfg.Scripts[tKey] then
                    local sTbl = evoCfg.Scripts[tKey]
                    scriptUrl = type(sTbl) == "string" and sTbl or (sTbl[mapName] or sTbl["Wretched Front"] or next(sTbl))
                    if evoCfg.Towers and evoCfg.Towers[tKey] then
                        resolvedTowers = evoCfg.Towers[tKey]
                    end
                end
            end
            if not scriptUrl and CrateConfigs and CrateConfigs.Gems and CrateConfigs.Gems.Lose then
                local cfg = CrateConfigs.Gems.Lose
                scriptUrl = cfg.Scripts and (cfg.Scripts[mapName] or cfg.Scripts["Wretched Front"] or next(cfg.Scripts))
                if not resolvedTowers and cfg.Towers then resolvedTowers = cfg.Towers end
            end
            if not scriptUrl and CrateConfigs and CrateConfigs.Gems and CrateConfigs.Gems.Win then
                local cfg = CrateConfigs.Gems.Win
                scriptUrl = cfg.Scripts and (cfg.Scripts[mapName] or cfg.Scripts["Wretched Front"] or next(cfg.Scripts))
                if not resolvedTowers and cfg.Towers then resolvedTowers = cfg.Towers end
            end
            if not scriptUrl and FallbackConfigs and FallbackConfigs["Hardcore"] then
                local cfg = FallbackConfigs["Hardcore"]
                scriptUrl = cfg.Scripts and (cfg.Scripts[mapName] or cfg.Scripts["Wretched Front"] or next(cfg.Scripts))
                if not resolvedTowers and cfg.Towers then resolvedTowers = cfg.Towers end
            end
            if not scriptUrl then
                scriptUrl = "https://raw.githubusercontent.com/Atxvy/Main/refs/heads/main/Currency/Gems/Lose/WretchedFront.lua"
            end
            if not resolvedTowers then
                resolvedTowers = {"Farm", "Boomerang", "Crook Boss"}
            end
        -- Special Handling: Lay By (Fallen / Coins Win)
        elseif normTarget == "layby" or string.find(normTarget, "layby") then
            if isEvoMatch and AutoEvoConfigs and AutoEvoConfigs.Coins and AutoEvoConfigs.Coins.Win then
                local evoCfg = AutoEvoConfigs.Coins.Win
                local tKey = activeTower
                if not tKey or not evoCfg.Scripts or not evoCfg.Scripts[tKey] then
                    tKey = evoCfg.Scripts and next(evoCfg.Scripts)
                end
                if tKey and evoCfg.Scripts and evoCfg.Scripts[tKey] then
                    local sTbl = evoCfg.Scripts[tKey]
                    scriptUrl = type(sTbl) == "string" and sTbl or (sTbl[mapName] or sTbl["Lay By"] or next(sTbl))
                    if evoCfg.Towers and evoCfg.Towers[tKey] then
                        resolvedTowers = evoCfg.Towers[tKey]
                    end
                end
            end
            if not scriptUrl and CrateConfigs and CrateConfigs.Coins and CrateConfigs.Coins.Win then
                local cfg = CrateConfigs.Coins.Win
                scriptUrl = cfg.Scripts and (cfg.Scripts[mapName] or cfg.Scripts["Lay By"] or next(cfg.Scripts))
                if not resolvedTowers and cfg.Towers then resolvedTowers = cfg.Towers end
            end
            if not scriptUrl and FallbackConfigs and FallbackConfigs["Fallen"] then
                local cfg = FallbackConfigs["Fallen"]
                scriptUrl = cfg.Scripts and (cfg.Scripts[mapName] or cfg.Scripts["Lay By"] or next(cfg.Scripts))
                if not resolvedTowers and cfg.Towers then resolvedTowers = cfg.Towers end
            end
            if not scriptUrl and FallbackConfigs and FallbackConfigs["Molten"] then
                local cfg = FallbackConfigs["Molten"]
                scriptUrl = cfg.Scripts and (cfg.Scripts[mapName] or cfg.Scripts["Lay By"] or next(cfg.Scripts))
                if not resolvedTowers and cfg.Towers then resolvedTowers = cfg.Towers end
            end
            if not scriptUrl then
                scriptUrl = "https://raw.githubusercontent.com/Atxvy/Main/refs/heads/main/Trials/Fallbacks/FallenLayby.lua"
            end
            if not resolvedTowers then
                resolvedTowers = {"Gatling Gun", "Trapper", "Medic", "Mercenary Base", "Hacker"}
            end
        -- Special Handling: Simplicity (Coins Lose)
        elseif normTarget == "simplicity" or string.find(normTarget, "simplicity") then
            if isEvoMatch and AutoEvoConfigs and AutoEvoConfigs.Coins and AutoEvoConfigs.Coins.Lose then
                local evoCfg = AutoEvoConfigs.Coins.Lose
                local tKey = activeTower or (evoCfg.Scripts and next(evoCfg.Scripts))
                if tKey and evoCfg.Scripts and evoCfg.Scripts[tKey] then
                    local sTbl = evoCfg.Scripts[tKey]
                    scriptUrl = type(sTbl) == "string" and sTbl or (sTbl[mapName] or sTbl["Simplicity"] or next(sTbl))
                    if evoCfg.Towers and evoCfg.Towers[tKey] then resolvedTowers = evoCfg.Towers[tKey] end
                end
            end
            if not scriptUrl and CrateConfigs and CrateConfigs.Coins and CrateConfigs.Coins.Lose then
                local cfg = CrateConfigs.Coins.Lose
                scriptUrl = cfg.Scripts and (cfg.Scripts[mapName] or cfg.Scripts["Simplicity"] or next(cfg.Scripts))
                if not resolvedTowers and cfg.Towers then resolvedTowers = cfg.Towers end
            end
            if not scriptUrl then
                scriptUrl = "https://raw.githubusercontent.com/Atxvy/Main/refs/heads/main/Currency/Coins/Lose/Simplicity.lua"
            end
            if not resolvedTowers then
                resolvedTowers = {"Assassin", "Soldier"}
            end
        -- Special Handling: Winter Abyss (Coins Lose)
        elseif normTarget == "winterabyss" or string.find(normTarget, "winter") then
            if CrateConfigs and CrateConfigs.Coins and CrateConfigs.Coins.Lose then
                local cfg = CrateConfigs.Coins.Lose
                scriptUrl = cfg.Scripts and (cfg.Scripts[mapName] or cfg.Scripts["Winter Abyss"] or next(cfg.Scripts))
                if not resolvedTowers and cfg.Towers then resolvedTowers = cfg.Towers end
            end
            if not scriptUrl then
                scriptUrl = "https://raw.githubusercontent.com/Atxvy/Main/refs/heads/main/Currency/Coins/Lose/WinterAbyss.lua"
            end
            if not resolvedTowers then
                resolvedTowers = {"Assassin", "Soldier"}
            end
        end
    end

    if type(scriptUrl) == "table" then
        scriptUrl = scriptUrl[mapName] or next(scriptUrl)
    end
    
    if not scriptUrl or scriptUrl == "" then
        warn(string.format("[ServiceHub Strategy] No script URL resolved for map '%s' (ActiveTower: %s)", tostring(mapName), tostring(activeTower)))
        logActivity(string.format("[Strategy] Missing script URL for %s", tostring(mapName)), "warn")
        return
    end

    if isEvoMatch and activeTower then
        warn(string.format("[ServiceHub AutoEvo] Active Tower: %s | Map: %s | Executing Script: %s", tostring(activeTower), tostring(mapName), tostring(scriptUrl)))
        logActivity(string.format("[AutoEvo] Strategy: %s (%s)", tostring(activeTower), tostring(mapName)), "info")
    else
        warn(string.format("[ServiceHub AutoGold] Map: %s | Executing Script: %s", tostring(mapName), tostring(scriptUrl)))
        logActivity(string.format("[AutoGold] Strategy: %s", tostring(mapName)), "info")
    end

    -- Call TDS:Loadout only once per match session
    if not loadoutApplied then
        pcall(function()
            local activeTowers = resolvedTowers or (config and config.Towers)
            if isEvoMatch and activeTower and type(activeTowers) == "table" and activeTowers[activeTower] then
                activeTowers = activeTowers[activeTower]
            end
            
            if TDS and typeof(TDS.Loadout) == "function" and activeTowers and #activeTowers > 0 then
                local lOk, lErr = pcall(function()
                    TDS:Loadout(unpack(activeTowers))
                    loadoutApplied = true
                    warn("[ServiceHub Loadout] TDS:Loadout equipped once successfully: " .. table.concat(activeTowers, ", "))
                    logActivity("[Loadout] Equipped: " .. table.concat(activeTowers, ", "), "success")
                end)
                if not lOk then
                    warn("[ServiceHub Loadout] TDS:Loadout failed: " .. tostring(lErr))
                end
            end
        end)
    end

    -- Keep executing the loadstring strategy with explicit error capture
    local stratOk, stratErr = pcall(function()
        local fn = compiledMacroCache[scriptUrl]
        if not fn then
            local chunk = fetchStrategyScript(scriptUrl)
            if chunk then
                local loadedFn, compileErr = loadstring(chunk)
                if loadedFn then
                    fn = loadedFn
                    compiledMacroCache[scriptUrl] = fn
                else
                    warn(string.format("[ServiceHub Strategy] Failed to parse/compile script from %s: %s", tostring(scriptUrl), tostring(compileErr)))
                    logActivity("[Strategy] Script syntax error", "error")
                end
            else
                warn(string.format("[ServiceHub Strategy] Failed to fetch strategy script from: %s", tostring(scriptUrl)))
                logActivity("[Strategy] Failed to fetch script", "error")
            end
        end

        if fn then
            if TDS and typeof(TDS.RemoveIndex) == "function" then
                pcall(function() TDS:RemoveIndex() end)
            end
            warn(string.format("[ServiceHub Strategy] Running strategy macro for %s...", tostring(activeTower or mapName)))
            logActivity("[Strategy] Running macro...", "info")
            
            local execOk, execErr = pcall(fn)
            if not execOk then
                warn(string.format("[ServiceHub Strategy] Runtime error in strategy script: %s", tostring(execErr)))
                logActivity(string.format("[Strategy Error] %s", tostring(execErr)), "error")
            else
                warn("[ServiceHub Strategy] Strategy executed cleanly.")
                logActivity("[Strategy] Strategy active / executed", "success")
            end
        end
    end)

    if not stratOk then
        warn(string.format("[ServiceHub Strategy] Execution supervisor error: %s", tostring(stratErr)))
        logActivity("[Strategy] Supervisor error: " .. tostring(stratErr), "error")
    end
end

local function isReadyPressedOrGameStarted(): boolean
    local sr = ReplicatedStorage:FindFirstChild("StateReplicators")
    if not sr then return false end

    local gsr = sr:FindFirstChild("GameStateReplicator")
    if gsr and (gsr:GetAttribute("GameStarted") == true or (gsr:GetAttribute("Wave") or 0) > 0) then
        return true
    end

    local vr = sr:FindFirstChild("VoteReplicator")
    if vr and (vr:GetAttribute("Enabled") == false or (vr:GetAttribute("VoteCount") or 0) > 0) then
        return true
    end

    return false
end

-- Mobile-optimized direct ready prompt detection (avoids scanning thousands of UI descendants)
local function isReadyPromptVisible(): boolean
    local found = false
    pcall(function()
        local intermission = PlayerGui:FindFirstChild("ReactGameIntermission")
        if intermission and intermission:IsA("ScreenGui") and intermission.Enabled then
            local frame = intermission:FindFirstChild("Frame")
            if frame and frame.Visible then
                found = true
                return
            end
        end

        local promptGui = PlayerGui:FindFirstChild("ReadyPrompt") or PlayerGui:FindFirstChild("PromptOverlay")
        if promptGui and promptGui:IsA("ScreenGui") and promptGui.Enabled then
            found = true
            return
        end

        -- Fast targeted check without recursive descendant tree traversal
        for _, sg in ipairs(PlayerGui:GetChildren()) do
            if sg:IsA("ScreenGui") and sg.Enabled and sg ~= UI.ScreenGui then
                local sName = sg.Name
                if sName:find("Intermission") or sName:find("Ready") or sName:find("Vote") then
                    local frame = sg:FindFirstChild("Frame") or sg:FindFirstChildWhichIsA("Frame")
                    if frame and frame.Visible then
                        found = true
                        return
                    end
                end
            end
        end
    end)
    return found
end

--==============================================================================
-- Webhook Integration
--==============================================================================
EvoData = EvoData or {
    ["Scout"] = { Evo = "EvolvedOperator", Coins = 15000, Gems = 4500 },
    ["Shotgunner"] = { Evo = "EvolvedEnforcer", Coins = 15000, Gems = 5000 },
    ["Crook Boss"] = { Evo = "EvolvedKingpin", Coins = 15000, Gems = 5500 },
    ["Minigunner"] = { Evo = "EvolvedJuggernaut", Coins = 15000, Gems = 6000 }
}

Globals.SessionStartTime = Globals.SessionStartTime or os.time()
Globals.SessionMatchesPlayed = Globals.SessionMatchesPlayed or 0
Globals.SessionTotalCoins = Globals.SessionTotalCoins or 0
Globals.SessionTotalGems = Globals.SessionTotalGems or 0

local function GetAllRewards()
    local ItemNames = {}
    local results = {
        Coins = 0, Gems = 0, XP = 0, Wave = 0, Level = 0, Time = "00:00", Status = "UNKNOWN", Others = {}
    }
    local UiRoot = PlayerGui:FindFirstChild("ReactGameNewRewards")
    local MainFrame = UiRoot and UiRoot:FindFirstChild("Frame")
    local GameOver = MainFrame and MainFrame:FindFirstChild("gameOver")
    local RewardsScreen = GameOver and GameOver:FindFirstChild("RewardsScreen")
    local GameStats = RewardsScreen and RewardsScreen:FindFirstChild("gameStats")
    local StatsList = GameStats and GameStats:FindFirstChild("stats")

    if StatsList then
        for _, frame in ipairs(StatsList:GetChildren()) do
            local l1 = frame:FindFirstChild("textLabel")
            local l2 = frame:FindFirstChild("textLabel2")
            local refLabel = l2 and l2:FindFirstChild("refLabel")
            if l1 and refLabel and l1.Text:find("Time Completed:") then
                results.Time = refLabel.Text
                break
            end
        end
    end

    local TopBanner = RewardsScreen and RewardsScreen:FindFirstChild("RewardBanner")
    if TopBanner and TopBanner:FindFirstChild("textLabel") then
        local txt = TopBanner.textLabel.Text:upper()
        results.Status = txt:find("TRIUMPH") and "WIN" or (txt:find("LOST") and "LOSS" or "UNKNOWN")
    end

    if PlayerDataHandler and typeof(PlayerDataHandler.GetLevel) == "function" then
        pcall(function() results.Level = PlayerDataHandler:GetLevel() or 0 end)
    end

    local topGameDisplay = PlayerGui:FindFirstChild("ReactGameTopGameDisplay")
    if topGameDisplay then
        pcall(function()
            local label = topGameDisplay.Frame.wave.container.value
            local WaveNum = label.Text:match("^(%d+)")
            if WaveNum then results.Wave = tonumber(WaveNum) or 0 end
        end)
    end

    local SectionRewards = RewardsScreen and RewardsScreen:FindFirstChild("RewardsSection")
    if SectionRewards then
        for _, item in ipairs(SectionRewards:GetChildren()) do
            if tonumber(item.Name) then 
                local IconId = "0"
                local img = item:FindFirstChildWhichIsA("ImageLabel", true)
                if img then IconId = img.Image:match("%d+") or "0" end
                for _, child in ipairs(item:GetDescendants()) do
                    if child:IsA("TextLabel") then
                        local text = child.Text
                        local amt = tonumber(text:match("(%d+)")) or 0
                        if text:find("Coins") then results.Coins = amt
                        elseif text:find("Gems") then results.Gems = amt
                        elseif text:find("XP") then results.XP = amt
                        elseif text:lower():find("x%d+") then 
                            local displayName = ItemNames[IconId] or "Unknown Item (" .. IconId .. ")"
                            table.insert(results.Others, {Amount = text:match("x%d+"), Name = displayName})
                        end
                    end
                end
            end
        end
    end
    return results
end

local function sendDiscordWebhook(matchStatus: string, mode: string)
    local url = Globals.WebhookURL
    if type(url) ~= "string" or url == "" then return end

    local httprequest = (syn and syn.request) or (http and http.request) or http_request or (fluxus and fluxus.request) or request
    if not httprequest then return end

    pcall(function()
        local matchData = GetAllRewards()
        matchData.Status = matchStatus
        
        Globals.SessionMatchesPlayed = Globals.SessionMatchesPlayed + 1
        Globals.SessionTotalCoins = Globals.SessionTotalCoins + matchData.Coins
        Globals.SessionTotalGems = Globals.SessionTotalGems + matchData.Gems

        local currentWalletCoins, targetCoinsVal, currentWalletGems, targetGemsVal, coinsDisplay, gemsDisplay = getCurrencyAndTargets()

        local isWin = matchStatus == "WIN"
        local modeName = mode
        if mode == "AutoTrials" then modeName = "Auto Trials"
        elseif mode == "AutoGold" then modeName = "Auto Gold"
        elseif mode == "AutoEvo" then modeName = "Auto Evo" end

        local stratType = Globals.Strat or "Unknown"
        if mode == "AutoEvo" then stratType = Globals.EvoStrat or "Unknown" end

        local timeElapsedSecs = os.time() - Globals.SessionStartTime
        local hours = math.floor(timeElapsedSecs / 3600)
        local minutes = math.floor((timeElapsedSecs % 3600) / 60)
        local sessionTimeStr = string.format("%02d:%02d:%02d", hours, minutes, timeElapsedSecs % 60)

        local missingCoins = 0
        local missingGems = 0
        local missingLvl = 0

        if mode == "AutoEvo" then
            local activeTower = Globals.CurrentEvoActiveTower or "Unknown"
            local eData = EvoData and EvoData[activeTower]
            if eData then
                missingCoins = math.max(0, eData.Coins - currentWalletCoins)
                missingGems = math.max(0, eData.Gems - currentWalletGems)
                local baseLevel = 0
                if PlayerDataHandler and typeof(PlayerDataHandler.GetTowerExp) == "function" then
                    pcall(function() local d = PlayerDataHandler:GetTowerExp(activeTower); if d and type(d)=="table" then baseLevel = d.Level or 0 end end)
                end
                missingLvl = math.max(0, 20 - baseLevel)
            end
        elseif mode == "AutoGold" then
            local tc = tonumber(Globals.TargetCoins) or 0
            local tg = tonumber(Globals.TargetGems) or 0
            if tc > 0 then missingCoins = math.max(0, tc - currentWalletCoins) end
            if tg > 0 then missingGems = math.max(0, tg - currentWalletGems) end
        end

        local function formatK(num)
            if num >= 1000 then return string.format("%.1fk", num / 1000):gsub("%.0k", "k") end
            return tostring(num)
        end

        local BonusString = ""
        if #matchData.Others > 0 then
            for _, res in ipairs(matchData.Others) do BonusString = BonusString .. "🎁 **" .. res.Amount .. " " .. res.Name .. "**\n" end
        else
            BonusString = string.format("❌ **Missing:**\n🪙 Coins: `%s`\n💎 Gems: `%s`\n⭐ Tower Lvl: `%s`", formatK(missingCoins), formatK(missingGems), tostring(missingLvl))
        end

        local currentLocation = (game.PlaceId == LOBBY_PLACE_ID) and "Lobby" or "Ingame"

        local embed = {
            ["title"] = isWin and "🏆 Match Victory!" or "💀 Match Defeat...",
            ["description"] = "### 📋 Match Overview\n> **Status:** `" .. matchData.Status .. "`\n> **Time:** `" .. matchData.Time .. "`\n> **Current Level:** `" .. matchData.Level .. "`\n> **Wave:** `" .. matchData.Wave .. "`\n",
            ["color"] = isWin and 3066993 or 15158332,
            ["timestamp"] = DateTime.now():ToIsoDate(),
            ["footer"] = { ["text"] = "ServiceHub V2 • Play Smart, Not Hard", ["icon_url"] = "https://i.imgur.com/W35kZkU.png" },
            ["thumbnail"] = { ["url"] = "https://i.imgur.com/W35kZkU.png" },
            ["fields"] = {
                { ["name"] = "⚙️ Settings", ["value"] = "Mode: `" .. modeName .. "`\nStrat: `" .. stratType .. "`", ["inline"] = true },
                { ["name"] = "📈 Session Info", ["value"] = "Matches: `" .. Globals.SessionMatchesPlayed .. "`\nTime: `" .. sessionTimeStr .. "`", ["inline"] = true },
                { ["name"] = "🌍 Location", ["value"] = "State: `" .. currentLocation .. "`", ["inline"] = true },
                { ["name"] = "✨ Rewards", ["value"] = "```ansi\n\27[2;33mCoins:\27[0m +" .. matchData.Coins .. "\n\27[2;34mGems: \27[0m +" .. matchData.Gems .. "\n\27[2;32mXP:   \27[0m +" .. matchData.XP .. "```", ["inline"] = false },
                { ["name"] = "🎁 Bonus Items", ["value"] = BonusString, ["inline"] = true },
                { ["name"] = "📊 Session Totals", ["value"] = "```py\n# Total Earned\nCoins: " .. Globals.SessionTotalCoins .. "\nGems:  " .. Globals.SessionTotalGems .. "\n# User Current / Target\nCoins: " .. coinsDisplay .. "\nGems:  " .. gemsDisplay .. "```", ["inline"] = true }
            }
        }

        if mode == "AutoGold" then
            local targetCoins = tonumber(Globals.TargetCoins) or 0
            local targetGems = tonumber(Globals.TargetGems) or 0
            
            if targetCoins == 0 and targetGems == 0 then
                table.insert(embed.fields, { ["name"] = "🪙 User Current Coins", ["value"] = string.format("`%s`", coinsDisplay), ["inline"] = true })
                table.insert(embed.fields, { ["name"] = "💎 User Current Gems", ["value"] = string.format("`%s`", gemsDisplay), ["inline"] = true })
            else
                if targetCoins > 0 then
                    local current = currentWalletCoins
                    local percent = math.clamp(current / targetCoins, 0, 1)
                    local filled = math.floor(percent * 10)
                    local progressBar = string.rep("🟩", filled) .. string.rep("⬛", 10 - filled)
                    
                    local etaString = ""
                    if Globals.SessionTotalCoins > 0 and timeElapsedSecs > 60 and targetCoins > current then
                        local rate = Globals.SessionTotalCoins / timeElapsedSecs
                        local secondsLeft = (targetCoins - current) / rate
                        local hLeft = math.floor(secondsLeft / 3600)
                        local mLeft = math.floor((secondsLeft % 3600) / 60)
                        etaString = string.format("\n⏳ **ETA:** `%dh %dm`", hLeft, mLeft)
                    end
                    table.insert(embed.fields, { ["name"] = "🎯 Target Coins", ["value"] = string.format("`%s` / `%s`\n%s **%.1f%%**%s", formatNumberWithCommas(current), formatNumberWithCommas(targetCoins), progressBar, percent * 100, etaString), ["inline"] = false })
                end
                
                if targetGems > 0 then
                    local current = currentWalletGems
                    local percent = math.clamp(current / targetGems, 0, 1)
                    local filled = math.floor(percent * 10)
                    local progressBar = string.rep("🟩", filled) .. string.rep("⬛", 10 - filled)
                    
                    local etaString = ""
                    if Globals.SessionTotalGems > 0 and timeElapsedSecs > 60 and targetGems > current then
                        local rate = Globals.SessionTotalGems / timeElapsedSecs
                        local secondsLeft = (targetGems - current) / rate
                        local hLeft = math.floor(secondsLeft / 3600)
                        local mLeft = math.floor((secondsLeft % 3600) / 60)
                        etaString = string.format("\n⏳ **ETA:** `%dh %dm`", hLeft, mLeft)
                    end
                    table.insert(embed.fields, { ["name"] = "🎯 Target Gems", ["value"] = string.format("`%s` / `%s`\n%s **%.1f%%**%s", formatNumberWithCommas(current), formatNumberWithCommas(targetGems), progressBar, percent * 100, etaString), ["inline"] = false })
                end
            end
        elseif mode == "AutoTrials" then
            table.insert(embed.fields, { ["name"] = "🪙 User Current Coins", ["value"] = string.format("`%s`", coinsDisplay), ["inline"] = true })
            table.insert(embed.fields, { ["name"] = "💎 User Current Gems", ["value"] = string.format("`%s`", gemsDisplay), ["inline"] = true })
        elseif mode == "AutoEvo" then
            local activeTower = Globals.CurrentEvoActiveTower or "Unknown"
            local needType = Globals.CurrentEvoFarmType or "Coins"
            table.insert(embed.fields, { ["name"] = "🎯 Active Target", ["value"] = string.format("`%s`", activeTower), ["inline"] = true })
            
            local stateText = "Unknown"
            if needType == "Coins" then stateText = "Grinding coins / level..."
            elseif needType == "Gems" then stateText = "Grinding gems..." end
            table.insert(embed.fields, { ["name"] = "🔄 Current State", ["value"] = string.format("`%s`", stateText), ["inline"] = true })
            table.insert(embed.fields, { ["name"] = "🪙 User Current Coins", ["value"] = string.format("`%s`", coinsDisplay), ["inline"] = true })
            table.insert(embed.fields, { ["name"] = "💎 User Current Gems", ["value"] = string.format("`%s`", gemsDisplay), ["inline"] = true })

            local eData = EvoData and EvoData[activeTower]
            if eData then
                local evoName = eData.Evo
                local ownsBase = true; local baseLevel = 0; local ownsEvo = false; local evoLevel = 0
                if PlayerDataHandler then
                    if typeof(PlayerDataHandler.IsTowerOwned) == "function" then
                        pcall(function() ownsBase = PlayerDataHandler:IsTowerOwned(activeTower) end)
                        pcall(function() ownsEvo = PlayerDataHandler:IsTowerOwned(evoName) end)
                    end
                    if typeof(PlayerDataHandler.GetTowerExp) == "function" then
                        pcall(function() local d = PlayerDataHandler:GetTowerExp(activeTower); if d and type(d)=="table" then baseLevel = d.Level or 0 end end)
                        pcall(function() local d = PlayerDataHandler:GetTowerExp(evoName); if d and type(d)=="table" then evoLevel = d.Level or 0 end end)
                    end
                end
                
                local overallPercent = 0; local cIcon, gIcon, bIcon, eIcon; local cStr, gStr, bStr, eStr
                if ownsEvo then
                    overallPercent = 75 + math.clamp((evoLevel / 20) * 25, 0, 25)
                    cIcon = "✅"; gIcon = "✅"; bIcon = "✅"; eIcon = evoLevel >= 20 and "✅" or "📊"
                    cStr = "`Paid`"; gStr = "`Paid`"; bStr = "`Maxed (20 / 20)`"; eStr = string.format("`Level %d / 20`", evoLevel)
                else
                    if ownsBase then overallPercent += 5 end
                    overallPercent += math.clamp((baseLevel / 20) * 25, 0, 25)
                    overallPercent += math.clamp((currentWalletCoins / eData.Coins) * 20, 0, 20)
                    overallPercent += math.clamp((currentWalletGems / eData.Gems) * 20, 0, 20)
                    cIcon = currentWalletCoins >= eData.Coins and "✅" or "🪙"
                    gIcon = currentWalletGems >= eData.Gems and "✅" or "💎"
                    bIcon = baseLevel >= 20 and "✅" or (ownsBase and "📊" or "❌")
                    eIcon = "🔒"
                    cStr = string.format("`%s / %s`", formatNumberWithCommas(currentWalletCoins), formatNumberWithCommas(eData.Coins))
                    gStr = string.format("`%s / %s`", formatNumberWithCommas(currentWalletGems), formatNumberWithCommas(eData.Gems))
                    bStr = ownsBase and string.format("`Level %d / 20`", baseLevel) or "`Not Owned`"
                    eStr = "`Locked`"
                end
                
                local overallFilled = math.floor((overallPercent / 100) * 10)
                local overallBar = string.rep("🟩", overallFilled) .. string.rep("⬛", 10 - overallFilled)
                
                local etaString = ""
                if Globals.EvoStartPercent == nil then Globals.EvoStartPercent = overallPercent end
                local percentGained = overallPercent - Globals.EvoStartPercent
                if percentGained > 0 and overallPercent < 100 and timeElapsedSecs > 60 then
                    local rate = percentGained / timeElapsedSecs
                    local secondsLeft = (100 - overallPercent) / rate
                    local hLeft = math.floor(secondsLeft / 3600)
                    local mLeft = math.floor((secondsLeft % 3600) / 60)
                    etaString = string.format("\n⏳ **ETA:** `%dh %dm`", hLeft, mLeft)
                end

                local desc = string.format("%s **Base (%s):** %s\n", bIcon, activeTower, bStr)
                desc = desc .. string.format("%s **Coins:** %s\n", cIcon, cStr)
                desc = desc .. string.format("%s **Gems:** %s\n", gIcon, gStr)
                desc = desc .. string.format("%s **Evo (%s):** %s\n\n", eIcon, evoName, eStr)
                desc = desc .. string.format("**Total Progress:** %s **%.1f%%**%s", overallBar, overallPercent, etaString)
                
                table.insert(embed.fields, { ["name"] = "📈 Evolution Progress Map", ["value"] = desc, ["inline"] = false })
            end
        end

        httprequest({
            Url = url, Method = "POST", Headers = { ["Content-Type"] = "application/json" },
            Body = game:GetService("HttpService"):JSONEncode({ ["username"] = "ServiceHub", ["avatar_url"] = "https://i.imgur.com/W35kZkU.png", ["embeds"] = { embed } })
        })
    end)
end

--==============================================================================
-- Disconnect Tracking
--==============================================================================
local function sendDisconnectWebhook(reason)
    local url = Globals.WebhookURL
    if type(url) ~= "string" or url == "" then return end
    local httprequest = (syn and syn.request) or (http and http.request) or http_request or (fluxus and fluxus.request) or request
    if not httprequest then return end

    local title = "⚠️ Disconnected"
    local lowerReason = reason:lower()
    if lowerReason:find("game guard") or lowerReason:find("unexpected client behavior") then 
        title = "🛡️ Game Guard Activated"
    elseif lowerReason:find("idle") or lowerReason:find("afk") or lowerReason:find("20 minutes") then 
        title = "💤 AFK / Idle Kick"
    end

    pcall(function()
        local embed = {
            ["title"] = title,
            ["description"] = "```\n" .. tostring(reason) .. "\n```",
            ["color"] = 16711680,
            ["timestamp"] = DateTime.now():ToIsoDate(),
            ["footer"] = { ["text"] = "ServiceHub V2 • Play Smart, Not Hard", ["icon_url"] = "https://i.imgur.com/W35kZkU.png" }
        }
        httprequest({
            Url = url, Method = "POST", Headers = { ["Content-Type"] = "application/json" },
            Body = game:GetService("HttpService"):JSONEncode({ ["username"] = "ServiceHub", ["avatar_url"] = "https://i.imgur.com/W35kZkU.png", ["embeds"] = { embed } })
        })
    end)
end

task.spawn(function()
    pcall(function()
        local CoreGui = game:GetService("CoreGui")
        local promptOverlay = CoreGui:WaitForChild("RobloxPromptGui", 10)
        if promptOverlay then promptOverlay = promptOverlay:WaitForChild("promptOverlay", 10) end
        
        if promptOverlay then
            local function checkPrompt(child)
                if child.Name == "ErrorPrompt" then
                    task.wait(0.5)
                    local msgLabel = child:FindFirstChild("ErrorMessage", true)
                    local reason = msgLabel and msgLabel.Text or "Unknown Disconnection"
                    sendDisconnectWebhook(reason)
                end
            end
            promptOverlay.ChildAdded:Connect(checkPrompt)
            for _, child in ipairs(promptOverlay:GetChildren()) do checkPrompt(child) end
        end
    end)
    pcall(function()
        game:GetService("GuiService").ErrorMessageChanged:Connect(function(msg)
            sendDisconnectWebhook(msg)
        end)
    end)
end)

--==============================================================================
-- Strategy Execution & Match-End Listener for Auto Trials
--==============================================================================
local function runMatchStrategyIfSaved()
    if game.PlaceId == LOBBY_PLACE_ID then return end

    -- v9.8 Progression Mode Guard (Solo only):
    -- If Progression Mode is active, ignore trial strat execution when:
    -- 1) AutoEvo or AutoGold is enabled (prioritizing currency/evo farm)
    -- 2) The trial is already won/owned
    if not Globals.MultiplayerEnabled and currentMatchMode ~= "Multiplayer" and Globals.TrialFarmMode == "Progression Mode" then
        if Globals.AutoEvo or Globals.AutoGold then
            warn("[ServiceHub AutoTrials v9.8] Progression Mode: AutoEvo/AutoGold is active -> ignoring trial strat execution.")
            logActivity("[Progression Mode] Ignored trial strategy execution (AutoEvo/AutoGold active)", "info")
            return
        end

        local liveTrial = ""
        pcall(function()
            local gsr = ReplicatedStorage:FindFirstChild("StateReplicators")
                and ReplicatedStorage.StateReplicators:FindFirstChild("GameStateReplicator")
            if gsr then
                liveTrial = tostring(gsr:GetAttribute("GlobalTrial") or "")
            end
        end)

        if liveTrial ~= "" and typeof(checkIsTrialWon) == "function" and checkIsTrialWon(liveTrial) then
            warn(string.format("[ServiceHub AutoTrials v9.8] Progression Mode: Trial '%s' is already owned -> ignoring trial strat execution.", liveTrial))
            logActivity(string.format("[Progression Mode] Ignored trial strategy (Already owned: %s)", liveTrial), "info")
            return
        end
    end

    -- Keyless Mode in-game guard (Solo only):
    if not Globals.MultiplayerEnabled and currentMatchMode ~= "Multiplayer" and not isKeyUser and not isPremiumUser then
        local liveTrial = ""
        pcall(function()
            local gsr = ReplicatedStorage:FindFirstChild("StateReplicators")
                and ReplicatedStorage.StateReplicators:FindFirstChild("GameStateReplicator")
            if gsr then
                liveTrial = tostring(gsr:GetAttribute("GlobalTrial") or "")
            end
            if liveTrial == "" or liveTrial == "None" then
                local tsr = ReplicatedStorage:FindFirstChild("StateReplicators")
                    and ReplicatedStorage.StateReplicators:FindFirstChild("TrialsStateReplicator")
                if tsr then
                    liveTrial = tostring(tsr:GetAttribute("GlobalTrial") or "")
                end
            end
            if (liveTrial == "" or liveTrial == "None") and typeof(loadTrialState) == "function" then
                liveTrial = tostring(loadTrialState() or "")
            end
        end)

        local isOwnedMatch = false
        if liveTrial ~= "" and typeof(checkIsTrialWon) == "function" and checkIsTrialWon(liveTrial) then
            isOwnedMatch = true
        else
            for configName in pairs(RevampAutoTrials) do
                if normalizeString(configName) == normalizeString(liveTrial) then
                    if checkIsTrialWon(configName) then
                        isOwnedMatch = true
                        break
                    end
                end
            end
        end

        if isOwnedMatch then
            warn(string.format("[ServiceHub AutoTrials v9.8] Keyless Mode: Trial '%s' is already owned -> returning to lobby.", liveTrial))
            logActivity(string.format("[Keyless Mode] Trial '%s' already owned -> returning to lobby", liveTrial), "info")
            pcall(function()
                if typeof(SmartTeleportToLobby) == "function" then
                    SmartTeleportToLobby()
                end
            end)
            return
        end
    end

    -- Keyless and Key modes are trial-only. Premium farming flags are ignored outside Premium.
    if (not Globals.AutoTrials and currentMatchMode ~= "AutoTrials") or (isPremiumUser and Globals.TrialFarmMode ~= "Progression Mode" and (Globals.AutoGold or Globals.AutoEvo)) or matchStratExecuted or isStrategyExecuting then return end
    isStrategyExecuting = true

    local liveTrial = ""
    local liveDifficulty = ""
    local liveGameMode = ""

    pcall(function()
        local gsr = ReplicatedStorage:FindFirstChild("StateReplicators")
            and ReplicatedStorage.StateReplicators:FindFirstChild("GameStateReplicator")
        if gsr then
            liveTrial = tostring(gsr:GetAttribute("GlobalTrial") or "")
            liveDifficulty = tostring(gsr:GetAttribute("Difficulty") or "")
            liveGameMode = tostring(gsr:GetAttribute("GameMode") or gsr:GetAttribute("Mode") or "")
        end
        if liveTrial == "" or liveTrial == "None" then
            local tsr = ReplicatedStorage:FindFirstChild("StateReplicators")
                and ReplicatedStorage.StateReplicators:FindFirstChild("TrialsStateReplicator")
            if tsr then
                liveTrial = tostring(tsr:GetAttribute("GlobalTrial") or "")
            end
        end
        if (liveTrial == "" or liveTrial == "None") and typeof(loadTrialState) == "function" then
            liveTrial = tostring(loadTrialState() or "")
        end
    end)

    local targetKey: string? = nil
    local normalizedTarget = normalizeString(liveTrial ~= "" and liveTrial or liveDifficulty)

    for configName in pairs(RevampAutoTrials) do
        if normalizeString(configName) == normalizedTarget then
            targetKey = configName
            break
        end
    end

    local currentTrialConfig = targetKey and RevampAutoTrials[targetKey] or nil
    local activeSlot = Globals.ActiveTrialSlot
    local scriptUrl = nil

    if not activeSlot and currentTrialConfig and currentTrialConfig.Towers then
        -- Fallback if they manually walked into elevator bypassing Lobby Validator
        if isPremiumUser and (currentTrialConfig.Towers["Tower Config 2"] or currentTrialConfig.Towers["Tower 2"]) then
            activeSlot = currentTrialConfig.Towers["Tower Config 2"] and "Tower Config 2" or "Tower 2"
        else
            activeSlot = currentTrialConfig.Towers["Tower Config 1"] and "Tower Config 1" or "Tower 1"
        end
    end
    activeSlot = activeSlot or "Tower Config 1"
    scriptUrl = currentTrialConfig and currentTrialConfig.scripts and currentTrialConfig.scripts[activeSlot] or nil

    if not scriptUrl and isPremiumUser then
        ensureDynamicHardcoreFallback()
        local savedTrial = ""
        if typeof(loadTrialState) == "function" then
            pcall(function() savedTrial = tostring(loadTrialState() or "") end)
        end
        for modeName, modeConfig in pairs(FallbackConfigs) do
            local match = (normalizeString(modeName) == normalizedTarget)
                or (normalizeString(modeName) == normalizeString(savedTrial))
                or (normalizeString(modeName) == "hardcore" and (normalizeString(liveGameMode) == "hardcore" or normalizeString(savedTrial) == "hardcore"))
            if match then
                local availableMaps = AutoGoldModule.GetAvailableMaps()
                local mapName = modeConfig.Maps and modeConfig.Maps[1] or "Lay By"
                for _, m in ipairs(modeConfig.Maps or {}) do
                    if availableMaps[m] then
                        mapName = m
                        break
                    end
                end
                if modeConfig.Scripts then
                    scriptUrl = modeConfig.Scripts[mapName]
                    if not scriptUrl then
                        for _, sUrl in pairs(modeConfig.Scripts) do
                            if type(sUrl) == "string" and #sUrl > 0 then
                                scriptUrl = sUrl
                                break
                            end
                        end
                    end
                end
                currentTrialConfig = modeConfig
                break
            end
        end
    end

    if not scriptUrl or scriptUrl == "" then
        isStrategyExecuting = false
        return
    end

    matchStratExecuted = true
    activeStratThread = task.spawn(function()
            pcall(function()
                local fn = compiledMacroCache[scriptUrl]
                if not fn then
                    local chunk = fetchStrategyScript(scriptUrl)
                    if chunk then
                        local loadedFn, compileErr = loadstring(chunk)
                        if loadedFn then
                            fn = loadedFn
                            compiledMacroCache[scriptUrl] = fn
                        else
                            warn(string.format("[ServiceHub Execution] Failed to parse script via loadstring: %s", tostring(compileErr)))
                        end
                    else
                        --warn(`[ServiceHub Execution] Failed to fetch strategy URL: {scriptUrl}`)
                    end
                end

                if fn then
                    -- 1. TDS:Loadout
                    local activeTowers = nil
                    if currentTrialConfig and currentTrialConfig.Towers then
                        activeTowers = currentTrialConfig.Towers
                        if type(activeTowers) == "table" and not activeTowers[1] then
                            activeTowers = currentTrialConfig.Towers[activeSlot] or currentTrialConfig.Towers["Tower Config 1"] or currentTrialConfig.Towers["Tower 1"]
                        end
                    end

                    if TDS and typeof(TDS.Loadout) == "function" and type(activeTowers) == "table" and #activeTowers > 0 then
                        warn(string.format("[ServiceHub Loadout] TDS:Loadout equipping: %s", table.concat(activeTowers, ", ")))
                        logActivity(string.format("[Loadout] Equipped: %s", table.concat(activeTowers, ", ")), "info")
                        pcall(function()
                            TDS:Loadout(unpack(activeTowers))
                        end)
                        loadoutApplied = true
                    end

                    -- 2. TDS:RemoveIndex
                    if TDS and typeof(TDS.RemoveIndex) == "function" then
                        pcall(function() TDS:RemoveIndex() end)
                    end

                    -- 3. Execute the script
                    fn()
                end
            end)
        end)

    if not trialWatcherRunning then
        trialWatcherRunning = true
        task.spawn(function()
            while task.wait(1) do
                if not isRunning then break end
                if game.PlaceId == LOBBY_PLACE_ID then break end

                local status = GetMatchStatus()
                if (status == "WIN" or status == "LOSS") and not isHandlingEndMatch then
                    isHandlingEndMatch = true
                    sendDiscordWebhook(status, "AutoTrials")
                    if shouldTeleportOnMatchEnd(status) then
                        isHandlingEndMatch = false
                        break
                    end

                    if activeStratThread and coroutine.status(activeStratThread) ~= "dead" then
                        pcall(task.cancel, activeStratThread)
                        activeStratThread = nil
                    end

                    if status == "WIN" then
                        pcall(function()
                            local gm = ReplicatedStorage:FindFirstChild("Network") and ReplicatedStorage.Network:FindFirstChild("GameManager")
                            local reMatch = gm and gm:FindFirstChild("RE:Rematch")
                            if reMatch and reMatch:IsA("RemoteEvent") then
                                reMatch:FireServer()
                            end
                        end)
                        pcall(function()
                            local gui = PlayerGui:FindFirstChild("ReactGameNewRewards")
                            local playAgain = gui and gui:FindFirstChild("PlayAgain", true)
                            local btn = playAgain and (playAgain:FindFirstChild("button") or playAgain:FindFirstChildOfClass("ImageButton") or playAgain:FindFirstChildOfClass("TextButton"))
                            if btn and getconnections then
                                for _, conn in ipairs(getconnections(btn.Activated)) do conn:Fire() end
                                for _, conn in ipairs(getconnections(btn.MouseButton1Click)) do conn:Fire() end
                            end
                        end)

                        local restartStartTime = tick()
                        local restartSuccess = false
                        while isRunning and (tick() - restartStartTime < 35) do
                            local stateReps = ReplicatedStorage:FindFirstChild("StateReplicators")
                            local gsr = stateReps and stateReps:FindFirstChild("GameStateReplicator")
                            local isGameOver = gsr and (gsr:GetAttribute("GameOver") == true)
                            local wave = gsr and (gsr:GetAttribute("Wave") or 0) or 0
                            local hotbar = PlayerGui:FindFirstChild("ReactUniversalHotbar") ~= nil

                            if (gsr and not isGameOver and (wave > 0 or hotbar)) or (GetMatchStatus() == nil and hotbar) then
                                restartSuccess = true
                                break
                            end
                            task.wait(1)
                        end

                        if not restartSuccess then
                            SmartTeleportToLobby()
                            break
                        end

                        task.wait(2) -- Buffer to allow map models to fully render
                        snapshotMatchConfig()
                        isLateExecution = false
                        initialExecutionWave = 0
                        Globals.IsConfigDirty = false

                        if not Globals.AutoTrials then
                            SmartTeleportToLobby()
                            break
                        end

                        matchStratExecuted = false
                        isStrategyExecuting = false
                        isHandlingEndMatch = false
                        runMatchStrategyIfSaved()
                    elseif status == "LOSS" then
                        failureCount += 1

                        if failureCount >= MAX_FAILURES then
                            SmartTeleportToLobby()
                            break
                        else
                            task.spawn(function()
                                local startVoteTime = tick()
                                while isRunning and (tick() - startVoteTime < 30) do
                                    if GetMatchStatus() == nil then break end
                                    triggerRematchVote()
                                    task.wait(0.5)
                                end
                            end)

                            local restartStartTime = tick()
                            local restartSuccess = false
                            while isRunning and (tick() - restartStartTime < 35) do
                                if GetMatchStatus() == nil then
                                    restartSuccess = true
                                    break
                                end
                                triggerRematchVote()
                                local stateReps = ReplicatedStorage:FindFirstChild("StateReplicators")
                                local gsr = stateReps and stateReps:FindFirstChild("GameStateReplicator")
                                local isGameOver = gsr and (gsr:GetAttribute("GameOver") == true)
                                local wave = gsr and (gsr:GetAttribute("Wave") or 0) or 0
                                local hotbar = PlayerGui:FindFirstChild("ReactUniversalHotbar") ~= nil

                                if (gsr and not isGameOver and (wave > 0 or hotbar)) or (GetMatchStatus() == nil and hotbar) then
                                    restartSuccess = true
                                    break
                                end
                                task.wait(0.5)
                            end

                            if not restartSuccess then
                                SmartTeleportToLobby()
                                break
                            end

                            task.wait(2) -- Buffer to allow map models to fully render
                            snapshotMatchConfig()
                            isLateExecution = false
                            initialExecutionWave = 0
                            Globals.IsConfigDirty = false

                            if not Globals.AutoTrials then
                                SmartTeleportToLobby()
                                break
                            end

                            loadoutApplied = false
                            matchStratExecuted = false
                            isStrategyExecuting = false
                            isHandlingEndMatch = false
                            runMatchStrategyIfSaved()
                        end
                    end
                end
            end
            trialWatcherRunning = false
            isHandlingEndMatch = false
        end)
    end
end
handleAutoTrialsExecution = runMatchStrategyIfSaved

-- Helper function to attempt purchasing a missing tower from the Shop
local attemptBuyMissingTower: (towerName: string) -> boolean
do
    local towerPurchaseDebounce: { [string]: number } = {}

    attemptBuyMissingTower = function(towerName: string): boolean
    if not isPremiumUser or not Globals.AutoTrials then return false end
    if not towerName or towerName == "" then return false end
    if game.PlaceId ~= LOBBY_PLACE_ID then return false end

    -- Avoid trying to buy golden tower variants or special non-shop items
    local clean = normalizeString(towerName)
    if string.find(clean, "golden") then return false end
    if clean == "warden" or clean == "cowboy" or clean == "saboteur" or clean == "sabboteur" then return false end

    ensurePlayerData()
    -- Check if already owned first
    if PlayerDataHandler and typeof(PlayerDataHandler.IsTowerOwned) == "function" then
        if PlayerDataHandler:IsTowerOwned(towerName) then
            return true
        end
    end

    local playerCoins = 0
    local playerGems = 0
    local playerLevel = 0
    pcall(function()
        if typeof(PlayerDataHandler.GetCoins) == "function" then playerCoins = PlayerDataHandler:GetCoins() or 0 end
        if typeof(PlayerDataHandler.GetGems) == "function" then playerGems = PlayerDataHandler:GetGems() or 0 end
        if typeof(PlayerDataHandler.GetLevel) == "function" then playerLevel = PlayerDataHandler:GetLevel() or 0 end
    end)

    local info = getTowerClassification(towerName)
    local targetCanonical = info.CanonicalName or towerName

    -- Double check canonical name ownership
    if PlayerDataHandler and typeof(PlayerDataHandler.IsTowerOwned) == "function" then
        if PlayerDataHandler:IsTowerOwned(targetCanonical) then
            return true
        end
    end

    -- 1. CLAIM TYPE TOWERS: Crook Boss, Turret, Mortar, Mercenary Base (Level rewards, Cost = 0)
    if info.Type == "Claim" then
        if playerLevel < info.LevelReq then
            logActivity(string.format("[Tower Unlock] '%s' is a Claim-type tower requiring Level %d (Current Level: %d). Cannot claim yet.", targetCanonical, info.LevelReq, playerLevel), "warn")
            return false
        end

        local lastAttempt = towerPurchaseDebounce[clean] or 0
        if os.time() - lastAttempt < 15 then return false end
        towerPurchaseDebounce[clean] = os.time()

        local rf = ReplicatedStorage:FindFirstChild("RemoteFunction")
        if rf and rf:IsA("RemoteFunction") then
            logActivity(string.format("[Tower Claim] Level %d reached! Attempting to claim '%s'...", playerLevel, targetCanonical), "info")
            pcall(function() rf:InvokeServer("LevelRewards", "Claim", targetCanonical) end)
            pcall(function() rf:InvokeServer("Rewards", "Claim", targetCanonical) end)
            pcall(function() rf:InvokeServer("LevelRewards", "ClaimAll") end)
            pcall(function() rf:InvokeServer("Rewards", "ClaimAll") end)
            pcall(function() rf:InvokeServer("LogBook", "ClaimAll") end)

            task.wait(0.5)
            if PlayerDataHandler and typeof(PlayerDataHandler.GetTowers) == "function" then
                pcall(function() PlayerDataHandler:GetTowers() end)
            end
            local isOwnedNow = false
            if PlayerDataHandler and typeof(PlayerDataHandler.IsTowerOwned) == "function" then
                isOwnedNow = PlayerDataHandler:IsTowerOwned(targetCanonical)
            end

            if isOwnedNow then
                logActivity(string.format("[Tower Claim] Successfully claimed tower '%s'!", targetCanonical), "success")
                if UI and UI.Window and typeof(UI.Window.Notify) == "function" then
                    RunAsExecutor(function()
                        UI.Window:Notify({
                            Title = "TOWER CLAIMED",
                            Desc = string.format("Claimed %s (Level %d Milestone)!", targetCanonical, info.LevelReq),
                            Duration = 6,
                            Type = "success",
                        })
                    end)()
                end
                return true
            else
                logActivity(string.format("[Tower Claim] Could not claim '%s' yet (server pending).", targetCanonical), "warn")
                return false
            end
        end
        return false
    end

    -- 2. LEVEL + COIN TOWERS: Pursuit (Lvl 100, 15k coins), Gatling Gun (Lvl 175, 35k coins)
    if info.Type == "LevelCoins" then
        if playerLevel < info.LevelReq then
            logActivity(string.format("[Shop Lock] '%s' requires Level %d (Current Level: %d)! Skipping purchase.", targetCanonical, info.LevelReq, playerLevel), "warn")
            return false
        end
        if playerCoins < info.Cost then
            logActivity(string.format("[Shop] Insufficient Coins for '%s' (Requires %s Coins, have %s Coins). Skipping purchase.", targetCanonical, formatNumberWithCommas(info.Cost), formatNumberWithCommas(playerCoins)), "warn")
            return false
        end
    end

    -- 3. REGULAR COIN SHOP TOWERS
    if info.Type == "Coins" then
        if playerCoins < info.Cost then
            logActivity(string.format("[Shop] Insufficient Coins for '%s' (Requires %s Coins, have %s Coins). Skipping purchase.", targetCanonical, formatNumberWithCommas(info.Cost), formatNumberWithCommas(playerCoins)), "warn")
            return false
        end
    end

    -- 4. HARDCORE GEM TOWERS
    if info.Type == "Gems" then
        if playerLevel < (info.LevelReq or 0) then
            logActivity(string.format("[Shop Lock] '%s' requires Level %d (Current Level: %d)! Skipping purchase.", targetCanonical, info.LevelReq, playerLevel), "warn")
            return false
        end
        if playerGems < info.Cost then
            logActivity(string.format("[Shop] Insufficient Gems for '%s' (Requires %s Gems, have %s Gems). Skipping purchase.", targetCanonical, formatNumberWithCommas(info.Cost), formatNumberWithCommas(playerGems)), "warn")
            return false
        end
    end

    -- Debounce: Don't spam the shop remote for the same tower (try once every 15 seconds)
    local lastAttempt = towerPurchaseDebounce[clean] or 0
    if os.time() - lastAttempt < 15 then return false end
    towerPurchaseDebounce[clean] = os.time()

    local remoteFunction = ReplicatedStorage:FindFirstChild("RemoteFunction")
    if not (remoteFunction and remoteFunction:IsA("RemoteFunction")) then
        return false
    end

    local costStr = (info.Currency == "Gems") and (formatNumberWithCommas(info.Cost) .. " Gems") or (formatNumberWithCommas(info.Cost) .. " Coins")
    logActivity(string.format("[Shop] Missing tower '%s' detected! Purchasing for %s...", targetCanonical, costStr), "info")
    if UI and UI.Window and typeof(UI.Window.Notify) == "function" then
        RunAsExecutor(function()
            UI.Window:Notify({
                Title = "SHOP PURCHASE",
                Desc = string.format("Attempting to purchase %s (%s)...", targetCanonical, costStr),
                Duration = 4,
                Type = "info",
            })
        end)()
    end

    local success, result = pcall(function()
        return remoteFunction:InvokeServer("Shop", "Purchase", "Tower", targetCanonical)
    end)

    if success then
        task.wait(0.5)
        -- Force refresh cached towers in PlayerDataHandler
        if PlayerDataHandler and typeof(PlayerDataHandler.GetTowers) == "function" then
            pcall(function() PlayerDataHandler:GetTowers() end)
        end
        local isOwnedNow = false
        if PlayerDataHandler and typeof(PlayerDataHandler.IsTowerOwned) == "function" then
            isOwnedNow = PlayerDataHandler:IsTowerOwned(targetCanonical)
        end

        if isOwnedNow then
            logActivity(string.format("[Shop] Successfully purchased tower '%s'!", targetCanonical), "success")
            if UI and UI.Window and typeof(UI.Window.Notify) == "function" then
                RunAsExecutor(function()
                    UI.Window:Notify({
                        Title = "PURCHASE SUCCESS",
                        Desc = string.format("Bought %s for %s!", targetCanonical, costStr),
                        Duration = 6,
                        Type = "success",
                    })
                end)()
            end
            return true
        else
            logActivity(string.format("[Shop] Could not purchase '%s' (server rejected purchase).", targetCanonical), "warn")
        end
    end

    return false
    end
end

attemptBuyMissingTowersList = function(tList: { string }?): boolean
    if not isPremiumUser or not Globals.AutoTrials then return false end
    if not tList or #tList == 0 then return false end
    if game.PlaceId ~= LOBBY_PLACE_ID then return false end

    local anyBought = false
    for _, towerName in ipairs(tList) do
        local bought = attemptBuyMissingTower(towerName)
        if bought then
            anyBought = true
        end
    end
    return anyBought
end

-- Detailed Trial & Fallback Evaluation Sequence
--==============================================================================
export type AnalysisResult = {
    trialName: string,
    nextTrialName: string,
    currentMap: string,
    nextTrialMap: string,
    timeRemaining: string,
    nextTimeRemaining: string,
    configFound: boolean,
    requiredLevel: number,
    playerLevel: number,
    levelPassed: boolean,
    missingTowers: { string },
    missingGold: { string },
    missingSkills: { string },
    isEligible: boolean,
    isSelectedInFilter: boolean,
    isOwned: boolean,
    useFallback: boolean,
    fallbackMode: string,
}


local function analyzeCurrentTrial(): AnalysisResult
    local currentTrialTitle = "None"
    local upcomingTrialTitle = "None"
    local currentMap = "Unknown"
    local nextTrialMap = "Unknown"
    local timeLeft = "00:00:00"
    local nextTimeLeft = "00:00:00"

    -- Fetch from PlayerDataHandler (Direct MatchmakingTrialData extraction)
    if PlayerDataHandler then
        if typeof(PlayerDataHandler.GetCurrentTrial) == "function" then
            local ok, cur = pcall(function() return PlayerDataHandler:GetCurrentTrial() end)
            if ok and type(cur) == "table" then
                if cur.Title and cur.Title ~= "" then
                    currentTrialTitle = tostring(cur.Title)
                elseif cur.Name and cur.Name ~= "" then
                    currentTrialTitle = tostring(cur.Name)
                end
                if cur.Map and cur.Map ~= "" then
                    currentMap = tostring(cur.Map)
                end
                if cur.TimeRemaining and cur.TimeRemaining ~= "" then
                    timeLeft = tostring(cur.TimeRemaining)
                end
            end
        end

        if typeof(PlayerDataHandler.GetNextTrial) == "function" then
            local ok, nxt = pcall(function() return PlayerDataHandler:GetNextTrial() end)
            if ok and type(nxt) == "table" then
                if nxt.Title and nxt.Title ~= "" then
                    upcomingTrialTitle = tostring(nxt.Title)
                elseif nxt.Name and nxt.Name ~= "" then
                    upcomingTrialTitle = tostring(nxt.Name)
                end
                if nxt.Map and nxt.Map ~= "" then
                    nextTrialMap = tostring(nxt.Map)
                end
                if nxt.TimeRemaining and nxt.TimeRemaining ~= "" then
                    nextTimeLeft = tostring(nxt.TimeRemaining)
                else
                    nextTimeLeft = timeLeft
                end
            end
        end
    end

    -- Fallback to StateReplicators if current title wasn't found
    if currentTrialTitle == "None" then
        pcall(function()
            local stateReps = ReplicatedStorage:FindFirstChild("StateReplicators")
            local trialsRep = stateReps and stateReps:FindFirstChild("TrialsStateReplicator")
            if trialsRep then
                local gt = trialsRep:GetAttribute("GlobalTrial")
                if gt and tostring(gt) ~= "" and tostring(gt) ~= "None" then
                    currentTrialTitle = tostring(gt)
                end
            end
        end)
    end

    local normalizedCurrent = normalizeString(currentTrialTitle)
    local matchedKey: string? = nil

    for configName in pairs(RevampAutoTrials) do
        if normalizeString(configName) == normalizedCurrent then
            matchedKey = configName
            break
        end
    end

    local finalTrialName = matchedKey or currentTrialTitle

    local normalizedUpcoming = normalizeString(upcomingTrialTitle)
    local matchedNextKey: string? = nil
    for configName in pairs(RevampAutoTrials) do
        if normalizeString(configName) == normalizedUpcoming then
            matchedNextKey = configName
            break
        end
    end
    local finalNextTrialName = matchedNextKey or upcomingTrialTitle

    local pLevel = PlayerDataHandler and PlayerDataHandler:GetLevel() or 0
    local selectedFallback = isPremiumUser and (Globals.SelectedFallback or "None") or "None"

    local isWonTrial = checkIsTrialWon(finalTrialName)
        or (matchedKey and checkIsTrialWon(matchedKey))
        or checkIsTrialWon(currentTrialTitle)
        or (currentMap ~= "Unknown" and checkIsTrialWon(currentMap))
        or false

    local effectiveFallback = selectedFallback
    if selectedFallback == "Smart Auto" then
        effectiveFallback = resolveSmartFallback()
    end

    local result: AnalysisResult = {
        trialName = finalTrialName,
        nextTrialName = finalNextTrialName,
        currentMap = currentMap,
        nextTrialMap = nextTrialMap,
        timeRemaining = timeLeft,
        nextTimeRemaining = nextTimeLeft,
        configFound = (matchedKey ~= nil),
        requiredLevel = 175,
        playerLevel = pLevel,
        levelPassed = false,
        missingTowers = {},
        missingGold = {},
        missingSkills = {},
        isEligible = false,
        isSelectedInFilter = false,
        isOwned = isWonTrial,
        useFallback = false,
        fallbackMode = effectiveFallback,
    }

    local selectedTrials = Globals.SelectedTrials or {}
    if isPremiumUser then
        if type(selectedTrials) == "table" then
            for _, selectedItem in ipairs(selectedTrials) do
                if normalizeString(selectedItem) == normalizedCurrent then
                    result.isSelectedInFilter = true
                    break
                end
            end
        end
    else
        result.isSelectedInFilter = true
    end

    if not matchedKey or not RevampAutoTrials[matchedKey] then
        if isPremiumUser and selectedFallback ~= "None" then
            result.useFallback = true
        end
        return result
    end

    local config = RevampAutoTrials[matchedKey]
    local reqLevel = config.Level or config.level or 175
    result.requiredLevel = reqLevel
    result.levelPassed = (result.playerLevel >= reqLevel)

    -- Golden requirement check
    local missingGold = {}
    local goldReqs = config.Golden or config.golden
    if goldReqs and type(goldReqs) == "table" and #goldReqs > 0 and PlayerDataHandler then
        for _, goldTower in ipairs(goldReqs) do
            if goldTower and goldTower ~= "" and not PlayerDataHandler:IsGoldenOwned(goldTower) then
                table.insert(missingGold, goldTower)
            end
        end
    end

    -- Skill Tree requirement check
    local missingSkills = {}
    local skillReqs = config.SkillTree or config["Skill Tree"] or config.skillTree
    if skillReqs and type(skillReqs) == "table" and next(skillReqs) and PlayerDataHandler then
        local currentSkills = {}
        if type(PlayerDataHandler.GetSkillTree) == "function" then
            pcall(function()
                for _, skill in ipairs(PlayerDataHandler:GetSkillTree()) do
                    currentSkills[skill.Name] = skill.Level
                end
            end)
        end
        for skillName, reqNodeLevel in pairs(skillReqs) do
            local haveLevel = currentSkills[skillName] or 0
            if haveLevel < reqNodeLevel then
                table.insert(missingSkills, string.format("%s (Need %d, Have %d)", skillName, reqNodeLevel, haveLevel))
            end
        end
    end

    -- Towers requirement check across slots
    local towersConfig = config.Towers or config.towers or {}
    local slotKeys = {}
    if type(towersConfig) == "table" then
        if isPremiumUser then
            if towersConfig["Tower Config 2"] then table.insert(slotKeys, "Tower Config 2") end
            if towersConfig["Tower 2"] then table.insert(slotKeys, "Tower 2") end
        end
        if towersConfig["Tower Config 1"] then table.insert(slotKeys, "Tower Config 1") end
        if towersConfig["Tower 1"] then table.insert(slotKeys, "Tower 1") end
        if #slotKeys == 0 and #towersConfig > 0 then
            table.insert(slotKeys, "__array__")
        end
    end

    local function getSlotTowers(sKey)
        if sKey == "__array__" then return towersConfig end
        return towersConfig[sKey]
    end

    local matchedSlot = nil
    local bestMissingTowers = nil
    local bestSlotKey = nil

    for _, sKey in ipairs(slotKeys) do
        local tList = getSlotTowers(sKey)
        if type(tList) == "table" then
            local missing = {}
            if PlayerDataHandler then
                for _, tower in ipairs(tList) do
                    if tower and tower ~= "" and not PlayerDataHandler:IsTowerOwned(tower) then
                        table.insert(missing, tower)
                    end
                end
            end

            if #missing == 0 then
                matchedSlot = (sKey == "__array__") and "Tower 1" or sKey
                bestMissingTowers = {}
                bestSlotKey = matchedSlot
                break
            else
                if bestMissingTowers == nil or #missing < #bestMissingTowers then
                    bestMissingTowers = missing
                    bestSlotKey = (sKey == "__array__") and "Tower 1" or sKey
                end
            end
        end
    end

    if matchedSlot == nil and bestMissingTowers and #bestMissingTowers > 0 and game.PlaceId == LOBBY_PLACE_ID then
        local boughtAny = attemptBuyMissingTowersList(bestMissingTowers)
        if boughtAny then
            for _, sKey in ipairs(slotKeys) do
                local tList = getSlotTowers(sKey)
                if type(tList) == "table" then
                    local missing = {}
                    if PlayerDataHandler then
                        for _, tower in ipairs(tList) do
                            if tower and tower ~= "" and not PlayerDataHandler:IsTowerOwned(tower) then
                                table.insert(missing, tower)
                            end
                        end
                    end
                    if #missing == 0 then
                        matchedSlot = (sKey == "__array__") and "Tower 1" or sKey
                        bestMissingTowers = {}
                        bestSlotKey = matchedSlot
                        break
                    else
                        if #missing < #bestMissingTowers then
                            bestMissingTowers = missing
                            bestSlotKey = (sKey == "__array__") and "Tower 1" or sKey
                        end
                    end
                end
            end
        end
    end

    Globals.ActiveTrialSlot = bestSlotKey or "Tower 1"
    result.missingTowers = bestMissingTowers or {}
    result.missingGold = missingGold
    result.missingSkills = missingSkills

    local towersPassed = (matchedSlot ~= nil)
    local goldPassed = (#missingGold == 0)
    local skillsPassed = (#missingSkills == 0)

    result.isEligible = result.levelPassed and towersPassed and goldPassed and skillsPassed

    local isFarmOnlyActive = isPremiumUser and (Globals.FarmOnly == "Farm Only")
    local isOwnedModeActive = isPremiumUser and (Globals.TrialFarmMode == "Progression Mode")

    if not result.isEligible or not result.isSelectedInFilter or (isOwnedModeActive and result.isOwned) then
        if not isFarmOnlyActive and isPremiumUser and selectedFallback ~= "None" then
            result.useFallback = true
        end
    end

    if isFarmOnlyActive then
        result.useFallback = false
    end

    return result
end


--==============================================================================
-- Matchmaking Queue Helpers
--==============================================================================
local lastQueueAttemptTime = 0

local function triggerTrialsQueue(trialName: string)
    if (not Globals.AutoTrials and not Globals.MultiplayerEnabled) or game.PlaceId ~= LOBBY_PLACE_ID then return end

    -- Keyless Ownership Guard (Solo)
    if not isKeyUser and not isPremiumUser and not Globals.MultiplayerEnabled then
        if checkIsTrialWon(trialName) then
            warn(string.format("[ServiceHub AutoTrials] Keyless Mode blocked queue for owned trial: %s (waiting in lobby)", tostring(trialName)))
            return
        end
    end

    if os.time() - lastQueueAttemptTime < 3 then return end
    lastQueueAttemptTime = os.time()

    saveTrialState(trialName)
    saveActiveMode("AutoTrials")

    local isMultiHost = Globals.MultiplayerEnabled and Globals.MultiplayerIsHost
    local partyCount = isMultiHost and 2 or 1

    if Globals.MultiplayerEnabled and TDS and typeof(TDS.Loadout) == "function" then
        local role = isMultiHost and "Host" or "P2"
        local mpConfig = Requirements and Requirements.MultiplayerConfig or (getgenv and getgenv().MultiplayerConfig) or {}
        local trialEntry = mpConfig and mpConfig.TrialMode and (mpConfig.TrialMode[trialName] or mpConfig.TrialMode[trialName:gsub(" Enemies", "")] or mpConfig.TrialMode["Speedy Enemies"])
        local reqT = trialEntry and trialEntry.Towers and (trialEntry.Towers[role] or trialEntry.Towers[role:lower()])
        if reqT and #reqT > 0 then
            pcall(function() TDS:Loadout(unpack(reqT)) end)
        end
    end

    local remoteFunction = ReplicatedStorage:FindFirstChild("RemoteFunction")
    if remoteFunction and remoteFunction:IsA("RemoteFunction") then
        pcall(function()
            remoteFunction:InvokeServer("Multiplayer", "v2:stop")
        end)
        task.wait(0.1)
        pcall(function()
            remoteFunction:InvokeServer("Multiplayer", "v2:start", {
                count = partyCount,
                mode = "Trials"
            })
        end)
    end
end

local function triggerFallbackQueue(modeName: string)
    if not isPremiumUser or not Globals.AutoTrials or game.PlaceId ~= LOBBY_PLACE_ID then return end
    if os.time() - lastQueueAttemptTime < 3 then return end
    lastQueueAttemptTime = os.time()

    ensureDynamicHardcoreFallback()

    if modeName == "Smart Auto" then
        modeName = resolveSmartFallback()
    end

    saveTrialState(modeName)
    saveActiveMode("AutoTrials")

    local fallbackModeConfig = FallbackConfigs[modeName]
    local isHardcore = (normalizeString(modeName) == "hardcore")
        or (fallbackModeConfig and fallbackModeConfig.Mode and normalizeString(fallbackModeConfig.Mode) == "hardcore")

    local targetDifficulty = fallbackModeConfig and fallbackModeConfig.Mode or modeName
    if fallbackModeConfig and fallbackModeConfig.Towers and type(fallbackModeConfig.Towers) == "table" then
        local missingFb = {}
        if PlayerDataHandler then
            for _, tower in ipairs(fallbackModeConfig.Towers) do
                if tower and tower ~= "" and not PlayerDataHandler:IsTowerOwned(tower) then
                    table.insert(missingFb, tower)
                end
            end
        end
        if #missingFb > 0 then
            attemptBuyMissingTowersList(missingFb)
        end
    end

    local remoteFunction = ReplicatedStorage:FindFirstChild("RemoteFunction")
    if remoteFunction and remoteFunction:IsA("RemoteFunction") then
        pcall(function()
            remoteFunction:InvokeServer("Multiplayer", "v2:stop")
        end)
        task.wait(0.1)
        pcall(function()
            if isHardcore then
                return remoteFunction:InvokeServer("Multiplayer", "v2:start", {
                    difficulty = "Easy",
                    mode = "hardcore",
                    count = 1
                })
            else
                return remoteFunction:InvokeServer("Multiplayer", "v2:start", {
                    difficulty = targetDifficulty,
                    mode = "survival",
                    count = 1
                })
            end
        end)
    end
end

--==============================================================================
-- Forward Declarations
--==============================================================================
local isRequirementLocked = false
local buyingEvoDebounce = false
local refreshDisplay: () -> ()
local handleAutoGoldExecution: () -> ()
local handleAutoEvoExecution: () -> ()
local handleMultiplayerExecution: () -> ()
local handleAutoTrialsExecution: () -> ()
local fastQueueLobby: () -> ()
local AutoSkipRunning = false
local StartAutoSkip: () -> ()
local StartAutoGatling: () -> ()
local StartAutoReloadGatling: () -> ()

local staticTrialDefs = {
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
    { Name = "MysteryEnemies", Title = "Mystery Enemies", Map = "Winter Bridges" },
    { Name = "Quarantine", Title = "Quarantine", Map = "Dusty Bridges" },
    { Name = "SpeedyEnemies", Title = "Speedy Enemies", Map = "Autumn Falling" },
    { Name = "StunAbuse", Title = "Stun Abuse", Map = "Gilded Path" },
}

local function ensurePlayerData(): ()
    if not PlayerDataHandler and typeof(loadPlayerDataHandler) == "function" then
        pcall(function() PlayerDataHandler = loadPlayerDataHandler() end)
    end
end

local function areAllStaticTrialsWon(): boolean
    if setthreadidentity then pcall(setthreadidentity, 8) end
    for _, tDef in ipairs(staticTrialDefs) do
        if not checkIsTrialWon(tDef.Name) and not checkIsTrialWon(tDef.Title) then
            return false
        end
    end
    return true
end

isCoinTowersMaxed = function(): boolean
    ensurePlayerData()
    if not TowerList or not TowerList.Coins then return true end
    if not PlayerDataHandler or typeof(PlayerDataHandler.IsTowerOwned) ~= "function" then return false end
    local pLevel = 0
    pcall(function()
        if typeof(PlayerDataHandler.GetLevel) == "function" then
            pLevel = PlayerDataHandler:GetLevel() or 0
        end
    end)

    for _, t in ipairs(TowerList.Coins) do
        local clean = normalizeString(t.Name)
        if clean ~= "warden" and clean ~= "cowboy" and clean ~= "saboteur" and clean ~= "sabboteur" then
            local reqLvl = t.LevelReq or (LevelCoinTowers and LevelCoinTowers[t.Name] and LevelCoinTowers[t.Name].LevelReq) or 0
            if pLevel >= reqLvl then
                local owned = false
                pcall(function() owned = PlayerDataHandler:IsTowerOwned(t.Name) end)
                if not owned then
                    return false
                end
            end
        end
    end
    return true
end

isGemTowersMaxed = function(): boolean
    ensurePlayerData()
    if not TowerList or not TowerList.Gems then return true end
    if not PlayerDataHandler or typeof(PlayerDataHandler.IsTowerOwned) ~= "function" then return false end
    local pLevel = 0
    pcall(function()
        if typeof(PlayerDataHandler.GetLevel) == "function" then
            pLevel = PlayerDataHandler:GetLevel() or 0
        end
    end)

    for _, t in ipairs(TowerList.Gems) do
        local reqLvl = t.LevelReq or 0
        if pLevel >= reqLvl then
            local owned = false
            pcall(function() owned = PlayerDataHandler:IsTowerOwned(t.Name) end)
            if not owned then
                return false
            end
        end
    end
    return true
end

isEvoTowersMaxed = function(): boolean
    ensurePlayerData()
    if not TowerList or not TowerList.Evo then return true end
    if not PlayerDataHandler or typeof(PlayerDataHandler.IsTowerOwned) ~= "function" then return false end
    for _, e in ipairs(TowerList.Evo) do
        local owned = false
        pcall(function()
            if PlayerDataHandler:IsTowerOwned(e.Name) then
                owned = true
            elseif typeof(isTowerEvoComplete) == "function" then
                local baseName = EvoToTower[e.Name] or e.Name:gsub("^Evolved", "")
                if isTowerEvoComplete(e.Name) or isTowerEvoComplete(baseName) then
                    owned = true
                end
            end
        end)
        if not owned then
            return false
        end
    end
    return true
end

isGoldenSkinsMaxed = function(): boolean
    ensurePlayerData()
    if not TowerList or not TowerList.Golden then return true end
    if not PlayerDataHandler or typeof(PlayerDataHandler.IsGoldenOwned) ~= "function" then return false end
    for _, g in ipairs(TowerList.Golden) do
        local base = g.Name:gsub("^Golden%s+", "")
        local owned = false
        pcall(function()
            owned = PlayerDataHandler:IsGoldenOwned(g.Name) or PlayerDataHandler:IsGoldenOwned(base)
        end)
        if not owned then
            return false
        end
    end
    return true
end

local SkillNameToId = {
    ["Enhanced Optics"] = "1",
    ["Resourcefulness"] = "2",
    ["Fortify"] = "3",
    ["Over-Heal"] = "4",
    ["Fight Dirty"] = "5",
    ["Extreme Conditioning"] = "6",
    ["Stonks"] = "7",
    ["Expanded Barracks"] = "8",
    ["Improved Gunpowder"] = "9",
    ["Beefed Up Minions"] = "10",
    ["Precision"] = "11",
    ["Scavenger"] = "12",
    ["Accelerator"] = "13",
    ["Re-enforcements"] = "14",
    ["Bigger Budget"] = "15",
    ["Bandages"] = "16",
    ["Scholar"] = "17",
}

local function parseSkillInfo(sk: any, fallbackId: number?): { Id: string, Name: string, Level: number, MaxLevel: number, IsMaxed: boolean, LevelFormatted: string }
    local SkillDefinitions = {
        [1]  = { Name = "Enhanced Optics",      MaxLevel = 20 },
        [2]  = { Name = "Resourcefulness",       MaxLevel = 25 },
        [3]  = { Name = "Fortify",               MaxLevel = 40 },
        [4]  = { Name = "Over-Heal",             MaxLevel = 25 },
        [5]  = { Name = "Fight Dirty",           MaxLevel = 25 },
        [6]  = { Name = "Extreme Conditioning",  MaxLevel = 25 },
        [7]  = { Name = "Stonks",                MaxLevel = 20 },
        [8]  = { Name = "Expanded Barracks",     MaxLevel = 20 },
        [9]  = { Name = "Improved Gunpowder",    MaxLevel = 25 },
        [10] = { Name = "Beefed Up Minions",     MaxLevel = 25 },
        [11] = { Name = "Precision",             MaxLevel = 15 },
        [12] = { Name = "Scavenger",             MaxLevel = 20 },
        [13] = { Name = "Accelerator",           MaxLevel = 25 },
        [14] = { Name = "Re-enforcements",       MaxLevel = 10 },
        [15] = { Name = "Bigger Budget",         MaxLevel = 25 },
        [16] = { Name = "Bandages",              MaxLevel = 25 },
        [17] = { Name = "Scholar",               MaxLevel = 20 },
    }
    local idNum = (sk and tonumber(sk.Id)) or fallbackId or 1
    local def = SkillDefinitions[idNum] or { Name = "Skill #" .. tostring(idNum), MaxLevel = 25 }
    local name = (sk and sk.Name) or def.Name
    local curLvl = (sk and tonumber(sk.Level)) or 0
    local maxLvl = (sk and tonumber(sk.MaxLevel)) or def.MaxLevel
    local fmt = sk and tostring(sk.LevelFormatted or "") or ""
    local upperFmt = string.upper(fmt)

    local curMatch, maxMatch = fmt:match("(%d+)%s*/%s*(%d+)")
    if curMatch and maxMatch then
        curLvl = tonumber(curMatch) or curLvl
        maxLvl = tonumber(maxMatch) or maxLvl
    elseif upperFmt:find("MAX") then
        local numInFmt = upperFmt:match("(%d+)")
        if numInFmt then
            maxLvl = tonumber(numInFmt) or maxLvl
            curLvl = maxLvl
        else
            curLvl = maxLvl
        end
    end

    local isMaxed = false
    if sk and sk.IsMaxed == true then
        isMaxed = true
    elseif upperFmt:find("MAX") then
        isMaxed = true
    elseif curLvl >= maxLvl then
        isMaxed = true
    end

    if isMaxed and curLvl < maxLvl then
        curLvl = maxLvl
    end

    return {
        Id = tostring(idNum),
        Name = name,
        Level = curLvl,
        MaxLevel = maxLvl,
        IsMaxed = isMaxed,
        LevelFormatted = isMaxed and ("MAX" .. tostring(maxLvl)) or string.format("%d/%d", curLvl, maxLvl),
    }
end

isSkillTreeMaxed = function(): boolean
    ensurePlayerData()
    if not PlayerDataHandler or typeof(PlayerDataHandler.GetSkillTree) ~= "function" then return false end
    local skills = nil
    pcall(function() skills = PlayerDataHandler:GetSkillTree() end)
    if not skills or #skills == 0 then return false end

    local skillMap = {}
    for _, sk in ipairs(skills) do
        local idNum = tonumber(sk.Id)
        if not idNum and sk.Name and SkillNameToId[sk.Name] then
            idNum = tonumber(SkillNameToId[sk.Name])
        end
        if idNum then
            skillMap[idNum] = parseSkillInfo(sk, idNum)
        end
    end

    for id = 1, 17 do
        local info = skillMap[id] or parseSkillInfo(nil, id)
        if not info.IsMaxed then
            return false
        end
    end
    return true
end

areSelectedPrioritiesMaxed = function(): boolean
    local hasCoins = Globals.BuyMissingCoinsTower == true
    local hasGems = Globals.BuyMissingGemTower == true
    local hasEvo = Globals.BuyMissingEvoTower == true
    local hasGold = Globals.BuyMissingGoldSkins == true
    local hasSkill = Globals.BuySkillTree == true

    local anyToggleActive = hasCoins or hasGems or hasEvo or hasGold or hasSkill

    if anyToggleActive then
        if hasCoins and not isCoinTowersMaxed() then return false end
        if hasGems and not isGemTowersMaxed() then return false end
        if hasEvo and not isEvoTowersMaxed() then return false end
        if hasGold and not isGoldenSkinsMaxed() then return false end
        if hasSkill and not isSkillTreeMaxed() then return false end
        return true
    else
        return isCoinTowersMaxed() and isGemTowersMaxed() and isEvoTowersMaxed() and isGoldenSkinsMaxed() and isSkillTreeMaxed()
    end
end

checkIsEverythingMaxed = function(): boolean
    if setthreadidentity then pcall(setthreadidentity, 8) end
    ensurePlayerData()

    local analysis = analyzeCurrentTrial()
    local isCurTrialOwned = areAllStaticTrialsWon() or analysis.isOwned or checkIsTrialWon(analysis.trialName)
    if not isCurTrialOwned then
        return false
    end

    return areSelectedPrioritiesMaxed()
end

local function evaluateOwnedModeAction(analysis: AnalysisResult): (string, string?, string?, string?)
    ensurePlayerData()
    ensureDynamicHardcoreFallback()

    -- 0. Check unowned trial in rotation: if eligible and in filter, beat it first
    if analysis.isSelectedInFilter and not analysis.isOwned and analysis.isEligible and not isRequirementLocked then
        return "BeatUnownedTrial", analysis.trialName, nil, nil
    end

    -- Priority progression sequence:
    -- Coin tower > Hardcore tower > Evo Tower > Gold Crates / skin > Skill tree
    -- Rule: "it will not move to next if Coin towers are not yet owned all"

    local coinTowersDone = (typeof(isCoinTowersMaxed) == "function") and isCoinTowersMaxed() or false

    -- If Coin towers are NOT all owned:
    -- It will NOT move to next (Hardcore tower, Evo Tower, Gold Crates, or Skill tree)!
    if not coinTowersDone then
        if Globals.BuyMissingCoinsTower or Globals.BuyMissingGemTower or Globals.BuyMissingEvoTower or Globals.BuyMissingGoldSkins or Globals.BuySkillTree then
            local stratChoice = resolveCoinFarmFallback and resolveCoinFarmFallback() or "Molten"
            return "FarmCoins", stratChoice, "Coins", nil
        end
        if isPremiumUser and (analysis.useFallback or analysis.isOwned) and analysis.fallbackMode ~= "None" then
            local fbMode = analysis.fallbackMode
            if fbMode == "Smart Auto" then
                fbMode = resolveCoinFarmFallback and resolveCoinFarmFallback() or "Molten"
            end
            return "Fallback", fbMode, nil, nil
        end
        return "IdleWaiting", nil, nil, nil
    end

    -- From here, Coin towers are confirmed ALL OWNED!
    -- 1. Coin tower priority is completed.

    -- 2. Priority: Buy missing gem tower (Hardcore Towers)
    if Globals.BuyMissingGemTower and not isGemTowersMaxed() then
        return "FarmGems", "Lose", "Gems", nil
    end

    -- 3. Priority: Buy missing Evo tower
    if Globals.BuyMissingEvoTower and not isEvoTowersMaxed() then
        local evoAnalysis = (typeof(analyzeAutoEvoRequirements) == "function") and analyzeAutoEvoRequirements() or nil
        if evoAnalysis then
            if evoAnalysis.readyToBuy then
                return "EvoReadyInLobby", evoAnalysis.activeTower, nil, nil
            else
                local needType = evoAnalysis.farmType or "Coins"
                local stratChoice = (needType == "Gems") and "Lose" or "Win"
                return "FarmEvo", stratChoice, needType, evoAnalysis.activeTower
            end
        end
    end

    -- 4. Priority: Buy missing Gold skins (50,000 Coins)
    if Globals.BuyMissingGoldSkins and not isGoldenSkinsMaxed() then
        local stratChoice = resolveCoinFarmFallback and resolveCoinFarmFallback() or "Molten"
        return "FarmGoldSkins", stratChoice, "Coins", nil
    end

    -- 5. Priority: Buy Skill tree (Sequential ID 1 to 17)
    if Globals.BuySkillTree and not isSkillTreeMaxed() then
        local stratChoice = resolveCoinFarmFallback and resolveCoinFarmFallback() or "Molten"
        return "FarmSkillTree", stratChoice, "Coins", nil
    end

    -- If all selected priorities are maxed, use chosen fallback (defaults to Hardcore if Smart Auto):
    if areSelectedPrioritiesMaxed() or checkIsEverythingMaxed() then
        if isPremiumUser then
            local fbMode = analysis.fallbackMode
            if fbMode == "Smart Auto" then
                fbMode = "Hardcore"
            end
            if fbMode and fbMode ~= "None" then
                return "Fallback", fbMode, nil, nil
            end
            return "Fallback", "Hardcore", nil, nil
        end
    end

    -- If no priority action triggered, check fallback:
    if isPremiumUser and (analysis.useFallback or analysis.isOwned) and analysis.fallbackMode ~= "None" then
        local fbMode = analysis.fallbackMode
        if fbMode == "Smart Auto" then
            fbMode = resolveSmartFallback()
        end
        return "Fallback", fbMode, nil, nil
    end

    return "IdleWaiting", nil, nil, nil
end

--==============================================================================
-- Shop & Skill Tree Auto-Purchasing Engine (Progression Mode Priority System)
--==============================================================================
local function getNextUnmaxedSkill(): (string?, string?, number?, number?)
    ensurePlayerData()
    local skillList = (PlayerDataHandler and typeof(PlayerDataHandler.GetSkillTree) == "function") and PlayerDataHandler:GetSkillTree() or {}
    local skillMap = {}
    if skillList and #skillList > 0 then
        for _, sk in ipairs(skillList) do
            local idNum = tonumber(sk.Id)
            if not idNum and sk.Name and SkillNameToId[sk.Name] then
                idNum = tonumber(SkillNameToId[sk.Name])
            end
            if idNum then
                skillMap[idNum] = parseSkillInfo(sk, idNum)
            end
        end
    end

    -- Strictly start at ID 1. If maxed, move to ID 2, then ID 3, ..., up to ID 17
    for id = 1, 17 do
        local skInfo = skillMap[id] or parseSkillInfo(nil, id)
        if not skInfo.IsMaxed then
            return tostring(id), skInfo.Name, skInfo.Level, skInfo.MaxLevel
        end
    end

    return nil, nil, nil, nil
end

local processAutoPurchases: () -> ()
do
    local lastTowerPurchaseTime = 0
    local lastHardcorePurchaseTime = 0
    local lastEvoPurchaseTime = 0
    local lastGoldSkinPurchaseTime = 0
    local lastSkillPurchaseTime = 0
    local lastProcessAutoPurchasesTime = 0
    local lastClaimAttemptTime = 0

    processAutoPurchases = function()
    if not isPremiumUser or not Globals.AutoTrials or game.PlaceId ~= LOBBY_PLACE_ID then return end
    local anyPurchaseToggle = Globals.BuyMissingCoinsTower or Globals.BuyMissingGemTower or Globals.BuyMissingEvoTower or Globals.BuyMissingGoldSkins or Globals.BuySkillTree
    if Globals.TrialFarmMode ~= "Progression Mode" and not anyPurchaseToggle then return end

    local now = os.time()
    if now - lastProcessAutoPurchasesTime < 5 then return end
    lastProcessAutoPurchasesTime = now

    ensurePlayerData()
    if not PlayerDataHandler then return end
    local playerCoins = 0
    local playerGems = 0
    local playerLevel = 0
    pcall(function()
        if typeof(PlayerDataHandler.GetCoins) == "function" then
            playerCoins = PlayerDataHandler:GetCoins() or 0
        end
        if typeof(PlayerDataHandler.GetGems) == "function" then
            playerGems = PlayerDataHandler:GetGems() or 0
        end
        if typeof(PlayerDataHandler.GetLevel) == "function" then
            playerLevel = PlayerDataHandler:GetLevel() or 0
        end
    end)

    local isOwnedActive = (Globals.TrialFarmMode == "Progression Mode")

    -- 0. Priority: Auto-Claim Level Rewards and Claim-Type Towers (Crook Boss, Turret, Mortar, Mercenary Base)
    if now - lastClaimAttemptTime >= 15 then
        lastClaimAttemptTime = now
        pcall(tryClaimRewardsAndTowers)
    end

    -- Priority completion checks:
    local coinTowersDone = (typeof(isCoinTowersMaxed) == "function") and isCoinTowersMaxed() or false
    local gemTowersDone = (typeof(isGemTowersMaxed) == "function") and isGemTowersMaxed() or false
    local evoTowersDone = (typeof(isEvoTowersMaxed) == "function") and isEvoTowersMaxed() or false
    local goldSkinsDone = (typeof(isGoldenSkinsMaxed) == "function") and isGoldenSkinsMaxed() or false
    local skillTreeDone = (typeof(isSkillTreeMaxed) == "function") and isSkillTreeMaxed() or false

    local anyPurchased = false

    -- 1. Priority: Buy missing coins tower
    if (Globals.BuyMissingCoinsTower or isOwnedActive) and not coinTowersDone then
        if Globals.BuyMissingCoinsTower and (now - lastTowerPurchaseTime >= 5) and TowerList and TowerList.Coins then
            local targetTowerToBuy = nil
            local targetTowerCost = 0
            for _, t in ipairs(TowerList.Coins) do
                local clean = normalizeString(t.Name)
                if clean ~= "warden" and clean ~= "cowboy" and clean ~= "saboteur" and clean ~= "sabboteur" then
                    local isOwned = false
                    pcall(function() isOwned = PlayerDataHandler:IsTowerOwned(t.Name) end)
                    if not isOwned then
                        local reqLvl = t.LevelReq or (LevelCoinTowers and LevelCoinTowers[t.Name] and LevelCoinTowers[t.Name].LevelReq) or 0
                        local cost = tonumber(t.Cost) or 0
                        -- Only consider if player has reached the required level
                        if playerLevel >= reqLvl then
                            if playerCoins >= cost then
                                targetTowerToBuy = t.Name
                                targetTowerCost = cost
                                break
                            else
                                -- Insufficient CASH to afford this tower! Do not spam shop remotes!
                                break
                            end
                        end
                    end
                end
            end

            if targetTowerToBuy then
                lastTowerPurchaseTime = now
                pcall(function()
                    local rf = ReplicatedStorage:FindFirstChild("RemoteFunction")
                    if rf and rf:IsA("RemoteFunction") then
                        rf:InvokeServer("Shop", "Purchase", "Tower", targetTowerToBuy)
                        task.wait(0.5)
                        if PlayerDataHandler and typeof(PlayerDataHandler.GetTowers) == "function" then
                            pcall(function() PlayerDataHandler:GetTowers() end)
                        end
                        local isOwnedNow = false
                        if PlayerDataHandler and typeof(PlayerDataHandler.IsTowerOwned) == "function" then
                            isOwnedNow = PlayerDataHandler:IsTowerOwned(targetTowerToBuy)
                        end

                        if isOwnedNow then
                            anyPurchased = true
                            logActivity(string.format("[Auto Buy] Purchased coin tower '%s' (%s Coins)", targetTowerToBuy, formatNumberWithCommas(targetTowerCost)), "success")
                            if UI and UI.Window and typeof(UI.Window.Notify) == "function" then
                                UI.Window:Notify({
                                    Title = "Tower Purchased",
                                    Desc = string.format("Purchased %s for %s Coins!", targetTowerToBuy, formatNumberWithCommas(targetTowerCost)),
                                    Duration = 4,
                                    Type = "success"
                                })
                            end
                        else
                            logActivity(string.format("[Auto Buy] Purchase of '%s' failed or rejected by server.", targetTowerToBuy), "warn")
                        end
                    end
                end)
            end
        end
        -- STRICT PRIORITY: Coin towers are not yet all owned -> do not proceed to later priorities (Gems, Evo, Gold, Skill Tree)
        return
    end

    -- 2. Priority: Buy missing gem tower (Hardcore Towers)
    -- Coin towers are confirmed completed.
    if (Globals.BuyMissingGemTower or isOwnedActive) and not gemTowersDone then
        if Globals.BuyMissingGemTower and (now - lastHardcorePurchaseTime >= 5) and TowerList and TowerList.Gems then
            local targetHcToBuy = nil
            local targetHcCost = 0
            for _, t in ipairs(TowerList.Gems) do
                local isOwned = false
                pcall(function() isOwned = PlayerDataHandler:IsTowerOwned(t.Name) end)
                if not isOwned then
                    local reqLvl = t.LevelReq or 0
                    local cost = tonumber(t.Cost) or 0
                    if playerLevel >= reqLvl then
                        if playerGems >= cost then
                            targetHcToBuy = t.Name
                            targetHcCost = cost
                            break
                        else
                            -- Insufficient GEMS to afford this hardcore tower! Do not spam!
                            break
                        end
                    end
                end
            end

            if targetHcToBuy then
                lastHardcorePurchaseTime = now
                pcall(function()
                    local rf = ReplicatedStorage:FindFirstChild("RemoteFunction")
                    if rf and rf:IsA("RemoteFunction") then
                        rf:InvokeServer("Shop", "Purchase", "Tower", targetHcToBuy)
                        task.wait(0.5)
                        if PlayerDataHandler and typeof(PlayerDataHandler.GetTowers) == "function" then
                            pcall(function() PlayerDataHandler:GetTowers() end)
                        end
                        local isOwnedNow = false
                        if PlayerDataHandler and typeof(PlayerDataHandler.IsTowerOwned) == "function" then
                            isOwnedNow = PlayerDataHandler:IsTowerOwned(targetHcToBuy)
                        end

                        if isOwnedNow then
                            anyPurchased = true
                            logActivity(string.format("[Auto Buy] Purchased hardcore tower '%s' (%s Gems)", targetHcToBuy, formatNumberWithCommas(targetHcCost)), "success")
                            if UI and UI.Window and typeof(UI.Window.Notify) == "function" then
                                UI.Window:Notify({
                                    Title = "Hardcore Tower Purchased",
                                    Desc = string.format("Purchased %s for %s Gems!", targetHcToBuy, formatNumberWithCommas(targetHcCost)),
                                    Duration = 4,
                                    Type = "success"
                                })
                            end
                        else
                            logActivity(string.format("[Auto Buy] Purchase of '%s' failed or rejected by server.", targetHcToBuy), "warn")
                        end
                    end
                end)
            end
        end
        -- STRICT PRIORITY: Gem towers are not yet all owned -> do not proceed to later priorities (Evo, Gold, Skill Tree)
        return
    end

    -- 3. Priority: Buy missing Evo tower
    -- Coin towers AND Gem towers are confirmed completed.
    if (Globals.BuyMissingEvoTower or isOwnedActive) and not evoTowersDone then
        if Globals.BuyMissingEvoTower and (now - lastEvoPurchaseTime >= 5) and TowerList and TowerList.Evo then
            local targetEvoToBuy = nil
            local targetBaseTower = nil
            for _, e in ipairs(TowerList.Evo) do
                local isOwned = false
                pcall(function()
                    if PlayerDataHandler:IsTowerOwned(e.Name) then
                        isOwned = true
                    elseif typeof(isTowerEvoComplete) == "function" then
                        local base = EvoToTower[e.Name] or e.Name:gsub("^Evolved", "")
                        if isTowerEvoComplete(e.Name) or isTowerEvoComplete(base) then
                            isOwned = true
                        end
                    end
                end)
                if not isOwned then
                    local base = EvoToTower[e.Name] or e.Name:gsub("^Evolved", "")
                    local expData = nil
                    if typeof(PlayerDataHandler.GetTowerExp) == "function" then
                        pcall(function() expData = PlayerDataHandler:GetTowerExp(base) end)
                    end
                    local lvl = (expData and type(expData.Level) == "number") and expData.Level or 0
                    local reqCoins = tonumber(e.Coins) or 15000
                    local reqGems = tonumber(e.Gems) or 4500
                    if lvl >= 20 and playerCoins >= reqCoins and playerGems >= reqGems then
                        targetEvoToBuy = e.Name
                        targetBaseTower = base
                        break
                    else
                        -- Strict sequential progression: First unowned tower must reach Level 20 and have enough currency before moving to next!
                        break
                    end
                end
            end

            if targetBaseTower then
                lastEvoPurchaseTime = now
                pcall(function()
                    local rf = ReplicatedStorage:FindFirstChild("RemoteFunction")
                    if rf and rf:IsA("RemoteFunction") then
                        if typeof(sendEvoPurchaseWebhook) == "function" then
                            pcall(sendEvoPurchaseWebhook, targetBaseTower, targetEvoToBuy)
                        end
                        rf:InvokeServer("Shop", "EvolveTower", targetBaseTower)
                        task.wait(0.5)
                        local isEvolvedNow = false
                        pcall(function()
                            if PlayerDataHandler:IsTowerOwned(targetEvoToBuy) or (typeof(isTowerEvoComplete) == "function" and isTowerEvoComplete(targetEvoToBuy)) then
                                isEvolvedNow = true
                            end
                        end)
                        if isEvolvedNow then
                            anyPurchased = true
                            logActivity(string.format("[Auto Buy] Evolved tower '%s' into '%s'!", targetBaseTower, targetEvoToBuy), "success")
                            if UI and UI.Window and typeof(UI.Window.Notify) == "function" then
                                UI.Window:Notify({
                                    Title = "Tower Evolved",
                                    Desc = string.format("Successfully evolved %s!", targetBaseTower),
                                    Duration = 5,
                                    Type = "success"
                                })
                            end
                        else
                            logActivity(string.format("[Auto Buy] Evolution of '%s' failed or rejected by server.", targetBaseTower), "warn")
                        end
                    end
                end)
            end
        end
        -- STRICT PRIORITY: Evo towers are not yet all completed -> do not proceed to Gold Crates or Skill Tree
        return
    end

    -- 4. Priority: Buy missing Gold skins (50,000 Coins)
    -- Coin towers, Gem towers, AND Evo towers are confirmed completed.
    if (Globals.BuyMissingGoldSkins or isOwnedActive) and not goldSkinsDone then
        if Globals.BuyMissingGoldSkins and (now - lastGoldSkinPurchaseTime >= 5) and TowerList and TowerList.Golden then
            local hasUnownedGold = false
            for _, g in ipairs(TowerList.Golden) do
                local base = g.Name:gsub("^Golden%s+", "")
                local isOwned = false
                pcall(function()
                    isOwned = PlayerDataHandler:IsGoldenOwned(g.Name) or PlayerDataHandler:IsGoldenOwned(base)
                end)
                if not isOwned then
                    hasUnownedGold = true
                    break
                end
            end

            if hasUnownedGold and playerCoins >= 50000 then
                lastGoldSkinPurchaseTime = now
                pcall(function()
                    local rf = ReplicatedStorage:FindFirstChild("RemoteFunction")
                    if rf and rf:IsA("RemoteFunction") then
                        rf:InvokeServer("Shop", "Purchase", "Crate", "Golden Crate")
                        task.wait(0.5)
                        rf:InvokeServer("Shop", "Open", "Crate", "Golden Crate")
                        anyPurchased = true
                        logActivity("[Auto Buy] Purchased & opened Golden Crate (50,000 Coins)", "success")
                        if UI and UI.Window and typeof(UI.Window.Notify) == "function" then
                            UI.Window:Notify({
                                Title = "Golden Crate Purchased",
                                Desc = "Purchased and opened Golden Crate for 50,000 Coins!",
                                Duration = 5,
                                Type = "success"
                            })
                        end
                    end
                end)
            end
        end
        -- STRICT PRIORITY: Gold skins are not yet maxed (need 50,000 coins) -> do not spend coins on Skill Tree!
        return
    end

    -- 5. Priority: Buy Skill tree (Strictly Sequential ID 1 to 17) - AT THE VERY LAST!
    -- Coin towers, Gem towers, Evo towers, AND Gold skins MUST ALL BE COMPLETED before Skill Tree can spend coins!
    if Globals.BuySkillTree and not skillTreeDone and (now - lastSkillPurchaseTime >= 5) and playerCoins >= 500 then
        local nextId, nextName, nextLvl, maxLvl = getNextUnmaxedSkill()
        if nextId then
            lastSkillPurchaseTime = now
            pcall(function()
                local net = ReplicatedStorage:FindFirstChild("Network")
                local skills = net and net:FindFirstChild("Skills")
                local rf = skills and skills:FindFirstChild("RF:Purchase")
                if rf and rf:IsA("RemoteFunction") then
                    rf:InvokeServer(tostring(nextId))
                    anyPurchased = true
                    local targetLvl = (nextLvl or 0) + 1
                    local totalMax = maxLvl or 20
                    logActivity(string.format("[Auto Buy] Upgraded Skill '%s' (ID %s, Lvl %d/%d)", nextName, nextId, targetLvl, totalMax), "success")
                    if UI and UI.Window and typeof(UI.Window.Notify) == "function" then
                        UI.Window:Notify({
                            Title = "Skill Upgraded",
                            Desc = string.format("Upgraded %s (ID %s: %d/%d)!", nextName, nextId, targetLvl, totalMax),
                            Duration = 4,
                            Type = "success"
                        })
                    end
                end
            end)
        end
    end

    if anyPurchased then
        task.wait(0.5)
        pcall(function()
            if PlayerDataHandler and typeof(PlayerDataHandler.GetTowers) == "function" then
                PlayerDataHandler:GetTowers()
            end
        end)
    end
    end
end

--==============================================================================
-- Build User Interface (Auto Trials V9)
--==============================================================================
local coinsTrackerLabel: any = nil
local gemsTrackerLabel: any = nil

local function buildInterface()
    if setthreadidentity then pcall(setthreadidentity, 8) end
    pcall(function()
        local getParent = function()
            if gethui then
                local ok, h = pcall(gethui)
                if ok and h then return h end
            end
            local ok, parent = pcall(function() return game:GetService("CoreGui") end)
            if ok and parent then return parent end
            return LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui")
        end
        local parentGui = getParent()
        if parentGui then
            for _, name in ipairs({ "ServiceHub_Window", "CyberNeon_Window", "SkyBlueUI_Window" }) do
                local old = parentGui:FindFirstChild(name)
                if old then pcall(function() old:Destroy() end) end
            end
        end
        local pg = LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui")
        if pg then
            for _, name in ipairs({ "ServiceHub_Window", "CyberNeon_Window", "SkyBlueUI_Window" }) do
                local old = pg:FindFirstChild(name)
                if old then pcall(function() old:Destroy() end) end
            end
        end
    end)

    local executorName = "Unknown Executor"
    if identifyexecutor then
        executorName = identifyexecutor()
    elseif syn then
        executorName = "Synapse X"
    elseif KRNL_LOADED then
        executorName = "KRNL"
    elseif fluxus then
        executorName = "Fluxus"
    end

    local Window = UILibrary:Window({
        Name = "ServiceHub_Window",
        Title = "Service Hub v9.8 [Optimized]",
        Subtitle = (game.PlaceId == LOBBY_PLACE_ID) and "LOBBY : Idle / Queuing" or "IN GAME : Active Strategy",
        Icon = "Logo",
        BorderAnimation = false,       -- Mobile Optimization: Stops 60 FPS RenderStepped border rotation
        BackgroundAnimation = false,   -- Mobile Optimization: Stops 60 FPS RenderStepped gradient wave
        Keybind = Enum.KeyCode.RightShift,
        Theme = "SkyBlue",
    })
    UI.Window = Window
    UI.ScreenGui = Window.ScreenGui
    Globals.ServiceHub_ScreenGui = UI.ScreenGui

    local keyTierText = isPremiumUser and "PREMIUM" or (isKeyUser and "KEY" or "KEYLESS")
    local timeRemainingText = formatTimeRemaining()

    Window:UserProfile({
        Username = LocalPlayer.Name,
        Badge = keyTierText,
        TimeLeft = timeRemainingText,
        AvatarId = LocalPlayer.UserId,
    })

    -- =================== Overview Tab ===================
    local OverviewTab = Window:Tab({
        Title = "Overview",
        Subtitle = "System & Player Dashboard",
        Icon = "Home",
    })

    OverviewTab:Banner({
        Type = isPremiumUser and "Success" or "Info",
        Title = isPremiumUser and "Auto Trials V9.5 • Premium Active" or (isKeyUser and "Auto Trials V9.5 • Key Mode" or "Auto Trials V9.5 • Keyless Mode"),
        Desc = isPremiumUser and "Full VIP automation active. Multi-trial queues, smart rematching, and auto evolutions ready."
            or (isKeyUser and "Key Mode runs eligible trials repeatedly using the classic trial-only loop."
                or "Keyless Mode clears eligible unowned trials once, then waits for the next rotation.")
    })

    UI.OverviewGrid = OverviewTab:MetricGrid({
        Cols = 3,
        Items = {
            { Title = "ACCESS TIER", Value = keyTierText, Trend = isPremiumUser and "VIP" or (isKeyUser and "KEY" or "KEYLESS") },
            { Title = "LOCATION", Value = (game.PlaceId == LOBBY_PLACE_ID) and "LOBBY" or "MATCH", Sub = (game.PlaceId == LOBBY_PLACE_ID) and "Idle / Queue" or "In Game" },
            { Title = "EXECUTOR", Value = executorName:sub(1, 10), Sub = "Verified" },
        }
    })

    OverviewTab:Divider({ Height = 8 })

    UI.CurrencyGrid = OverviewTab:MetricGrid({
        Cols = 2,
        Items = {
            { Title = "USER CURRENT COINS", Value = "0 / 0", Sub = "Current / Target Coins" },
            { Title = "USER CURRENT GEMS", Value = "0 / 0", Sub = "Current / Target Gems" },
        }
    })

    OverviewTab:Divider({ Height = 10 })

    local SessionSection = OverviewTab:Section({ Title = "Session Information", Order = 1 })

    coinsTrackerLabel = SessionSection:Label({ Title = "User Current Coins", Desc = "0 / 0", Image = "Coins" })
    gemsTrackerLabel = SessionSection:Label({ Title = "User Current Gems", Desc = "0 / 0", Image = "Gem" })

    SessionSection:Label({ Title = "Username", Desc = LocalPlayer.Name, Image = "User" })
    SessionSection:Label({ Title = "Description", Desc = "Active Service Hub v9.8 session (Cloud Loadstring Edition)", Image = "Terminal" })
    SessionSection:Label({ Title = "Access", Desc = isPremiumUser and "Premium Active" or (isKeyUser and "Key Mode Active" or "Keyless Mode Active"), Image = "Key" })
    SessionSection:Label({ Title = "Session Expiry", Desc = tostring(Globals.JD_EXPIRES_AT or "Never / Permanent"), Image = "Clock" })

    SessionSection:Button({
        Title = "Buy Key / Upgrade",
        Desc = "Purchase or renew your premium access",
        Image = "Globe",
        Callback = function()
            if setclipboard then
                setclipboard("https://yourshoplink.com")
                Window:Notify({ Title = "Link Copied", Desc = "Store link copied to clipboard!", Duration = 2 })
            end
        end
    })

    SessionSection:Button({
        Title = "Discord Community",
        Desc = "Join our community for updates and support",
        Image = "Chat",
        Callback = function()
            if setclipboard then
                setclipboard("https://discord.gg/yourinvite")
                Window:Notify({ Title = "Link Copied", Desc = "Discord invite copied to clipboard!", Duration = 2 })
            end
        end
    })

    local LicenseSection = OverviewTab:Section({ Title = "Access Tiers", Order = 2 })

    LicenseSection:SelectionBox({
        Selections = { "Keyless", "Key", "Premium" },
        Value = isPremiumUser and "Premium" or (isKeyUser and "Key" or "Keyless"),
        Descriptions = {
            ["Keyless"] = "unowned trials only",
            ["Key"] = "classic repeat-trial mode",
            ["Premium"] = "full automation access"
        },
        Checklist = {
            ["Keyless"] = { "Queues eligible unowned trials", "Waits in lobby after a trial is owned", "No key required" },
            ["Key"] = { "Valid standard or Premium key required", "Classic trial-only automation", "Repeats eligible owned trials" },
            ["Premium"] = { "Multi-trial filters and fallbacks", "Progression Mode and auto-purchases", "Multiplayer Mode and instant rematching" }
        },
        ButtonTexts = { ["Keyless"] = "Use Keyless", ["Key"] = "Enter Key", ["Premium"] = "Get Premium" },
        Callbacks = {
            ["Keyless"] = function()
                isKeyUser = false
                isPremiumUser = false
                Globals.SCRIPT_KEY = nil
                SetSetting("PreferredAccessTier", "Keyless")
                Window:Notify({ Title = "Keyless Mode", Desc = "Switched to Keyless Mode. Runs unowned trials only.", Duration = 3 })
                task.defer(function()
                    pcall(function()
                        if UI.ScreenGui then UI.ScreenGui:Destroy() end
                    end)
                    task.wait(0.1)
                    pcall(function()
                        if setthreadidentity then pcall(setthreadidentity, 8) end
                        buildInterface()
                    end)
                end)
            end,
            ["Key"] = function()
                local savedKey = loadVerifiedKey()
                if savedKey and #savedKey > 0 and not isKeyUser then
                    Window:Notify({ Title = "Auto Loading Key", Desc = "Attempting to auto-load saved key...", Duration = 2 })
                    task.spawn(function()
                        local Junkie = getJunkieSDK()
                        if Junkie then
                            local ok, result = pcall(function() return Junkie.check_key(savedKey) end)
                            if ok and result and result.valid then
                                saveVerifiedKey(savedKey)
                                Globals.SCRIPT_KEY = savedKey
                                Globals.IS_JD_PREMIUM = (result.is_premium == true or result.premium == true)
                                Globals.JD_EXPIRES_AT = result.expires_at or result.expiresAt
                                isKeyUser = true
                                isPremiumUser = (Globals.IS_JD_PREMIUM == true)
                                SetSetting("PreferredAccessTier", isPremiumUser and "Premium" or "Key")
                                Window:Notify({ Title = "Key Validated", Desc = isPremiumUser and "Premium status unlocked!" or "Standard Key Mode unlocked! (Farms current trial repeatedly)", Duration = 3 })
                                task.defer(function()
                                    pcall(function() if UI.ScreenGui then UI.ScreenGui:Destroy() end end)
                                    task.wait(0.1)
                                    pcall(function()
                                        if setthreadidentity then pcall(setthreadidentity, 8) end
                                        buildInterface()
                                    end)
                                end)
                                return
                            end
                        end
                        Window:Notify({ Title = "Key Required", Desc = "Open the Key tab to enter your standard or Premium key.", Duration = 3 })
                    end)
                else
                    Window:Notify({ Title = "Key Required", Desc = "Open the Key tab and enter a valid standard or Premium key.", Duration = 3 })
                end
            end,
            ["Premium"] = function()
                if setclipboard then setclipboard("https://yourshoplink.com"); Window:Notify({ Title = "Link Copied", Desc = "Premium shop link copied to clipboard! Enter your key in the Key tab.", Duration = 3 }) end
            end
        }
    })

    local SystemSection = OverviewTab:Section({ Title = "System Information", Order = 3 })
    SystemSection:Label({ Title = "Detected Executor", Desc = executorName, Image = "Terminal" })

    -- =================== Auto Farm Trials Tab ===================
    local TrialsTab = Window:Tab({
        Title = "Auto Farm Trials",
        Subtitle = "Continuous Trial Farming",
        Icon = "Clock",
    })

    local AutoSec = TrialsTab:Section({ Title = "Automation Controls" })
    local isModeSwitching = false

    local autoToggle = AutoSec:Toggle({
        Title = "Auto Farm Trials",
        Desc = "Continuously farm selected trials with auto queue & rematch",
        Value = (Globals.AutoTrials and Globals.TrialFarmMode == "Farm Mode"),
        Callback = RunAsExecutor(function(val)
            if isModeSwitching then return end

            if isRequirementLocked and val then
                if UI.AutoToggle then UI.AutoToggle:SetValue(false) end
                Window:Notify({ Title = "REQUIREMENT LOCKED", Desc = "Level/Towers required!", Duration = 4 })
                return
            end

            if val then
                isModeSwitching = true
                SetSetting("TrialFarmMode", "Farm Mode")
                if UI.ProgAutoToggle then UI.ProgAutoToggle:SetValue(false) end
                if UI.MultiplayerToggle and Globals.MultiplayerEnabled then
                    UI.MultiplayerToggle:SetValue(false)
                end
                if isPremiumUser then
                    if UI.AutoGoldToggle and Globals.AutoGold then UI.AutoGoldToggle:SetValue(false) end
                    if UI.AutoEvoToggle and Globals.AutoEvo then UI.AutoEvoToggle:SetValue(false) end
                end
                isModeSwitching = false
            end

            SetSetting("AutoTrials", val)
            logActivity("Auto Farm Trials: " .. (val and "ENABLED" or "DISABLED"), val and "success" or "warn")
            lastQueueAttemptTime = 0

            if not Globals.AutoTrials then
                if game.PlaceId == LOBBY_PLACE_ID then
                    pcall(function()
                        local rf = ReplicatedStorage:FindFirstChild("RemoteFunction")
                        if rf then rf:InvokeServer("Multiplayer", "v2:stop") end
                    end)
                else
                    Globals.IsConfigDirty = true
                end
            else
                currentMatchMode = "AutoTrials"
                if game.PlaceId == LOBBY_PLACE_ID then
                    task.spawn(fastQueueLobby)
                else
                    Globals.IsConfigDirty = true
                end
            end

            task.spawn(function() pcall(refreshDisplay) end)
        end)
    })
    UI.AutoToggle = autoToggle
    UI.StatusLabel = AutoSec:Label({ Title = "Status", Desc = "Checking..." })

    local trialOptionsList = {}
    if RevampAutoTrials then
        for trialName, _ in pairs(RevampAutoTrials) do
            table.insert(trialOptionsList, trialName)
        end
        table.sort(trialOptionsList)
    end
    if #trialOptionsList == 0 then
        trialOptionsList = { "Fog", "Quarantine", "Exploding Enemies" }
    end

    AutoSec:Dropdown({
        Title = "Selected Trials (Multi)",
        Desc = "Choose targeted trial configurations",
        IsPrem = isPremiumUser,
        Searchable = true,
        Options = trialOptionsList,
        Multi = true,
        Value = Globals.SelectedTrials or { "Fog" },
        Callback = function(selectedItems)
            SetSetting("SelectedTrials", selectedItems)
        end,
    })

    local fbDropdownOptions = {}
    ensureDynamicHardcoreFallback()
    for _, opt in ipairs(fallbackModesList) do
        table.insert(fbDropdownOptions, opt)
    end
    local hasNone = false
    for _, opt in ipairs(fbDropdownOptions) do
        if opt == "None" then hasNone = true; break end
    end
    if not hasNone then
        table.insert(fbDropdownOptions, "None")
    end

    AutoSec:Dropdown({
        Title = "Selected Fallback",
        Desc = "Choose fallback mode if main trial fails requirements/filter",
        IsPrem = isPremiumUser,
        Searchable = false,
        Options = fbDropdownOptions,
        Value = tostring(Globals.SelectedFallback or "Smart Auto"),
        Callback = function(val)
            SetSetting("SelectedFallback", tostring(val))
        end,
    })

    local RotSec = TrialsTab:Section({ Title = "Trial Rotation" })
    UI.CurrentTrial = RotSec:Label({ Title = "Current Trial", Desc = "Loading rotation data..." })
    UI.NextTrial = RotSec:Label({ Title = "Next Trial", Desc = "Loading rotation data..." })

    if game.PlaceId ~= LOBBY_PLACE_ID then
        local GuardSec = TrialsTab:Section({ Title = "In-Game Ready Guard" })
        UI.ReadyGuard = GuardSec:Label({ Title = "Ready Button Guard (30s)", Desc = "Monitoring match status..." })
        UI.ReadyGuardBar = GuardSec:ProgressBar({
            Title = "Ready Countdown",
            Progress = 1.0,
            Status = "30s remaining"
        })
    end

    local OwnedTrialsSec = TrialsTab:Section({ Title = "Owned Trials" })
    UI.OwnedTrialLabels = {}

    if setthreadidentity then pcall(setthreadidentity, 8) end

    for _, tDef in ipairs(staticTrialDefs) do
        UI.OwnedTrialLabels[tDef.Name] = OwnedTrialsSec:Label({
            Title = tDef.Title,
            Desc = string.format("Map: %s | Owned: Checking...", tDef.Map)
        })
    end

    -- =================== Progress Mode Tab ===================
    local ProgressTab = Window:Tab({
        Title = "Progress Mode",
        Subtitle = "Auto Progression & Unowned Trials",
        Icon = "Coins",
    })

    local ProgAutoSec = ProgressTab:Section({ Title = "Automation Controls" })

    local progAutoToggle = ProgAutoSec:Toggle({
        Title = "Auto Progress Mode",
        Desc = "Prioritize unowned rotation trials and auto-purchase missing items",
        Value = (Globals.AutoTrials and Globals.TrialFarmMode == "Progression Mode"),
        Callback = RunAsExecutor(function(val)
            if isModeSwitching then return end

            if val and checkIsEverythingMaxed() then
                if UI.ProgAutoToggle then UI.ProgAutoToggle:SetValue(false) end
                if Window and Window.Notify then
                    Window:Notify({
                        Title = "Progression Mode",
                        Desc = "Everything is Maxed! Please select Auto Farm Trials.",
                        Duration = 4
                    })
                end
                return
            end

            if isRequirementLocked and val then
                if UI.ProgAutoToggle then UI.ProgAutoToggle:SetValue(false) end
                Window:Notify({ Title = "REQUIREMENT LOCKED", Desc = "Level/Towers required!", Duration = 4 })
                return
            end

            if val then
                isModeSwitching = true
                SetSetting("TrialFarmMode", "Progression Mode")
                if UI.AutoToggle then UI.AutoToggle:SetValue(false) end
                if UI.MultiplayerToggle and Globals.MultiplayerEnabled then
                    UI.MultiplayerToggle:SetValue(false)
                end
                if isPremiumUser then
                    if UI.AutoGoldToggle and Globals.AutoGold then UI.AutoGoldToggle:SetValue(false) end
                    if UI.AutoEvoToggle and Globals.AutoEvo then UI.AutoEvoToggle:SetValue(false) end
                end
                isModeSwitching = false
            end

            SetSetting("AutoTrials", val)
            logActivity("Progress Mode: " .. (val and "ENABLED" or "DISABLED"), val and "success" or "warn")
            lastQueueAttemptTime = 0

            if not Globals.AutoTrials then
                if game.PlaceId == LOBBY_PLACE_ID then
                    pcall(function()
                        local rf = ReplicatedStorage:FindFirstChild("RemoteFunction")
                        if rf then rf:InvokeServer("Multiplayer", "v2:stop") end
                    end)
                else
                    Globals.IsConfigDirty = true
                end
            else
                currentMatchMode = "AutoTrials"
                if game.PlaceId == LOBBY_PLACE_ID then
                    task.spawn(fastQueueLobby)
                else
                    Globals.IsConfigDirty = true
                end
            end

            task.spawn(function() pcall(refreshDisplay) end)
        end)
    })
    UI.ProgAutoToggle = progAutoToggle
    UI.ProgStatusLabel = ProgAutoSec:Label({ Title = "Status", Desc = "Checking..." })

    -- Synchronize Status Labels across Auto Farm Trials and Progress Mode
    local rawSetTitle = UI.StatusLabel.SetTitle
    local rawSetDesc = UI.StatusLabel.SetDesc
    UI.StatusLabel.SetTitle = function(self, t)
        pcall(rawSetTitle, self, t)
        if UI.ProgStatusLabel and UI.ProgStatusLabel.SetTitle then pcall(UI.ProgStatusLabel.SetTitle, UI.ProgStatusLabel, t) end
    end
    UI.StatusLabel.SetDesc = function(self, d)
        pcall(rawSetDesc, self, d)
        if UI.ProgStatusLabel and UI.ProgStatusLabel.SetDesc then pcall(UI.ProgStatusLabel.SetDesc, UI.ProgStatusLabel, d) end
    end

    ProgAutoSec:Dropdown({
        Title = "Selected Fallback",
        Desc = "Choose fallback mode when rotation trial is already owned",
        IsPrem = isPremiumUser,
        Searchable = false,
        Options = fbDropdownOptions,
        Value = tostring(Globals.SelectedFallback or "Smart Auto"),
        Callback = function(val)
            SetSetting("SelectedFallback", tostring(val))
        end,
    })

    local PrioritySec = ProgressTab:Section({ Title = "Priority" })

    PrioritySec:Toggle({
        Title = "Buy missing coins tower",
        Desc = "Auto-purchase missing coin towers (Progression Mode only)",
        IsPrem = isPremiumUser,
        Value = Globals.BuyMissingCoinsTower == true,
        Callback = function(val)
            SetSetting("BuyMissingCoinsTower", val)
            task.spawn(function() pcall(refreshDisplay) end)
        end,
    })

    PrioritySec:Toggle({
        Title = "Buy missing gem tower",
        Desc = "Auto-purchase missing gem/hardcore towers (Progression Mode only)",
        IsPrem = isPremiumUser,
        Value = Globals.BuyMissingGemTower == true,
        Callback = function(val)
            SetSetting("BuyMissingGemTower", val)
            task.spawn(function() pcall(refreshDisplay) end)
        end,
    })

    PrioritySec:Toggle({
        Title = "Auto Farm & Buy Missing Evolutions",
        Desc = "Farm required coins, gems, and EXP, then purchase missing evolutions (Progression Mode only)",
        IsPrem = isPremiumUser,
        Value = Globals.BuyMissingEvoTower == true,
        Callback = function(val)
            SetSetting("BuyMissingEvoTower", val)
            task.spawn(function() pcall(refreshDisplay) end)
        end,
    })

    PrioritySec:Toggle({
        Title = "Buy missing Gold skins",
        Desc = "Auto-purchase missing golden skins (Progression Mode only)",
        IsPrem = isPremiumUser,
        Value = Globals.BuyMissingGoldSkins == true,
        Callback = function(val)
            SetSetting("BuyMissingGoldSkins", val)
            task.spawn(function() pcall(refreshDisplay) end)
        end,
    })

    PrioritySec:Toggle({
        Title = "Buy Skill tree",
        Desc = "Auto-purchase/upgrade skill tree nodes (Progression Mode only)",
        IsPrem = isPremiumUser,
        Value = Globals.BuySkillTree == true,
        Callback = function(val)
            SetSetting("BuySkillTree", val)
            task.spawn(function() pcall(refreshDisplay) end)
        end,
    })

    local ProgSec = ProgressTab:Section({ Title = "Progression & Missing Indicators" })
    UI.ProgCurrency = ProgSec:Label({
        Title = "User Current Currency",
        Desc = "Coins: 0 / 0\nGems: 0 / 0"
    })
    UI.ProgCoinTowers = ProgSec:Label({
        Title = "Coin Towers (Checking...)",
        Desc = "Scanning inventory..."
    })
    UI.ProgClaimTowers = ProgSec:Label({
        Title = "Claim Towers (Checking...)",
        Desc = "Scanning inventory..."
    })
    UI.ProgGemTowers = ProgSec:Label({
        Title = "Hardcore Towers (Checking...)",
        Desc = "Scanning inventory..."
    })
    UI.ProgEvoTowers = ProgSec:Label({
        Title = "Evolved Towers (Checking...)",
        Desc = "Scanning evolution progress..."
    })
    UI.ProgGoldenSkins = ProgSec:Label({
        Title = "Golden Skins (Checking...)",
        Desc = "Scanning inventory..."
    })
    UI.ProgSkillTree = ProgSec:Label({
        Title = "Skill Tree (Checking...)",
        Desc = "Scanning skill tree..."
    })

    -- =================== Auto Evo Tab ===================
    local AutoEvoTab = Window:Tab({
        Title = "Auto Evo",
        Subtitle = "Automated Tower Evolution",
        Icon = "Zap",
    })

    local EvoControlSec = AutoEvoTab:Section({ Title = "Evolution Controls" })

    UI.AutoEvoToggle = EvoControlSec:Toggle({
        Title = "Enable Auto Evo",
        Desc = "Automatically evolve selected towers when currency allows",
        IsPrem = isPremiumUser,
        Value = Globals.AutoEvo,
        Callback = RunAsExecutor(function(val)
            local evoAnalysis = analyzeAutoEvoRequirements()
            if val and not evoAnalysis.isEligible then
                if UI.AutoEvoToggle then UI.AutoEvoToggle:SetValue(false) end
                local desc = #evoAnalysis.missingParts > 0 and table.concat(evoAnalysis.missingParts, ", ") or "Requirements not met!"
                if evoAnalysis.allFinished then desc = "All target evolutions are already complete!" end
                Window:Notify({ Title = "REQUIREMENT LOCKED", Desc = desc, Duration = 4 })
                return
            end

            SetSetting("AutoEvo", val)
            logActivity("Auto Evolution: " .. (val and "ENABLED" or "DISABLED"), val and "success" or "warn")
            if val then
                if UI.MultiplayerToggle and Globals.MultiplayerEnabled then
                    UI.MultiplayerToggle:SetValue(false)
                end
                if isPremiumUser and Globals.TrialFarmMode ~= "Progression Mode" then
                    if UI.AutoToggle and Globals.AutoTrials then UI.AutoToggle:SetValue(false) end
                    if UI.ProgAutoToggle and Globals.AutoTrials then UI.ProgAutoToggle:SetValue(false) end
                    if UI.AutoGoldToggle and Globals.AutoGold then UI.AutoGoldToggle:SetValue(false) end
                end
                currentMatchMode = "AutoEvo"
                if game.PlaceId == LOBBY_PLACE_ID then
                    task.spawn(fastQueueLobby)
                else
                    Globals.IsConfigDirty = true
                end
            else
                if game.PlaceId == LOBBY_PLACE_ID then
                    pcall(function()
                        local rf = ReplicatedStorage:FindFirstChild("RemoteFunction")
                        if rf then rf:InvokeServer("Multiplayer", "v2:stop") end
                    end)
                else
                    Globals.IsConfigDirty = true
                end
            end
            task.spawn(function() pcall(refreshDisplay) end)
        end),
    })

    EvoControlSec:Dropdown({
        Title = "Target Evo",
        Desc = "Select the target evolution",
        IsPrem = isPremiumUser,
        Searchable = true,
        Options = { "All", "Scout", "Shotgunner", "Crook Boss", "Minigunner" },
        Value = tostring(Globals.TargetEvo or "All"),
        Callback = function(val)
            SetSetting("TargetEvo", tostring(val))
            task.spawn(function() pcall(refreshDisplay) end)
            if game.PlaceId ~= LOBBY_PLACE_ID then
                Globals.IsConfigDirty = true
            end
        end,
    })

    EvoControlSec:Dropdown({
        Title = "Win / Lose Strategy",
        Desc = "Select outcome preference for Auto Evo",
        IsPrem = isPremiumUser,
        Searchable = false,
        Options = { "Win", "Lose" },
        Value = tostring(Globals.EvoStrat or "Lose"),
        Callback = function(val)
            SetSetting("EvoStrat", tostring(val))
            task.spawn(function() pcall(refreshDisplay) end)
            if game.PlaceId ~= LOBBY_PLACE_ID then
                Globals.IsConfigDirty = true
            end
        end,
    })

    UI.AutoEvoStatusLabel = EvoControlSec:Label({
        Title = "Status",
        Desc = "Checking..."
    })
    UI.EvoStatusLabel = UI.AutoEvoStatusLabel

    UI.AutoEvoMissingLabel = EvoControlSec:Label({
        Title = "Missing:",
        Desc = "Checking..."
    })

    local EvoTrackerSec = AutoEvoTab:Section({ Title = "Evolution Trackers" })

    UI.EvoCoinsGemsLabel = EvoTrackerSec:Label({
        Title = "Coins & Gems Tracker",
        Desc = "Waiting for data..."
    })

    UI.EvoTowersLabel = EvoTrackerSec:Label({
        Title = "Towers Level",
        Desc = "Waiting for data..."
    })

    -- =================== Multiplayer Mode Tab ===================
    local MultiplayerTab = Window:Tab({
        Title = "Multiplayer Mode",
        Subtitle = "Local Coordinated Runs (Host & Joiner)",
        Icon = "User",
    })

    -- 1. Automation & Mode Controls Section
    local MultiControlsSec = MultiplayerTab:Section({ Title = "Multiplayer Modes & Controls" })

    local function checkTowerEligibilityForPlayer(playerOrTarget, requiredTowersList, requiredLevelOrRole, maybeRole)
        local requiredLevel = nil
        local roleName = "Player"
        if type(requiredLevelOrRole) == "number" or (type(requiredLevelOrRole) == "string" and tonumber(requiredLevelOrRole)) then
            requiredLevel = tonumber(requiredLevelOrRole)
            roleName = maybeRole or "Player"
        elseif type(requiredLevelOrRole) == "string" then
            roleName = requiredLevelOrRole
            if type(maybeRole) == "number" or (type(maybeRole) == "string" and tonumber(maybeRole)) then
                requiredLevel = tonumber(maybeRole)
            end
        end

        local isLocal = (playerOrTarget == nil or playerOrTarget == LocalPlayer)
        local targetPlayer = isLocal and LocalPlayer or playerOrTarget

        if not isLocal then
            if not playerOrTarget or tostring(playerOrTarget):gsub("%s+", "") == "" then
                return false, roleName .. ": Target empty", requiredTowersList or {}
            end
            if not PlayerDataHandler or typeof(PlayerDataHandler.checkPlayer) ~= "function" then
                return false, roleName .. ": DataHandler checkPlayer not available", requiredTowersList or {}
            end
            local p, exists = PlayerDataHandler:checkPlayer(playerOrTarget)
            if not exists or p == "player does not exist" then
                return false, roleName .. ": player does not exist", requiredTowersList or {}
            end
            targetPlayer = p
        end

        if (not requiredTowersList or #requiredTowersList == 0) and not requiredLevel then
            return true, roleName .. ": Any / Not Configured", {}
        end

        local missing = {}

        -- Level requirement check
        if requiredLevel and tonumber(requiredLevel) then
            local currentLevel = 0
            if PlayerDataHandler and typeof(PlayerDataHandler.GetLevel) == "function" then
                currentLevel = PlayerDataHandler:GetLevel(isLocal and LocalPlayer or targetPlayer) or 0
            end
            if currentLevel < tonumber(requiredLevel) then
                table.insert(missing, string.format("Level %d+ (Current: %d)", tonumber(requiredLevel), currentLevel))
            end
        end

        -- Towers requirement check
        if requiredTowersList and #requiredTowersList > 0 then
            for _, towerName in ipairs(requiredTowersList) do
                local owned = false
                if PlayerDataHandler and typeof(PlayerDataHandler.IsTowerOwned) == "function" then
                    if isLocal then
                        owned = PlayerDataHandler:IsTowerOwned(towerName)
                    else
                        owned = PlayerDataHandler:IsTowerOwned(towerName, targetPlayer)
                    end
                end
                if not owned then
                    table.insert(missing, towerName)
                end
            end
        end

        if #missing == 0 then
            return true, roleName .. ": Eligible (None missing)", {}
        else
            return false, roleName .. " Missing: " .. table.concat(missing, ", "), missing
        end
    end

    local function updateMultiplayerTowersLabel()
        if not UI.MultiplayerRequiredTowers then return end
        local modeStr = Globals.MultiplayerMode or "Trial Mode"
        local selectedTrial = Globals.MultiplayerSelectedTrial or "Current Rotation"
        local trialName = selectedTrial
        if trialName == "Current Rotation" then
            local cur = (typeof(analyzeCurrentTrial) == "function") and analyzeCurrentTrial()
            trialName = cur and cur.trialName or "Speedy Enemies"
        end

        -- Retrieve configurations from MultiplayerConfig or RevampAutoTrials
        local mpConfig = Requirements and Requirements.MultiplayerConfig or (getgenv and getgenv().MultiplayerConfig) or {}
        local trialModeCfg = mpConfig.TrialMode or {}

        local hostReqTowers = {}
        local p2ReqTowers = {}
        local hostReqLevel = nil
        local p2ReqLevel = nil

        if modeStr == "Trial Mode" then
            -- 1. Try MultiplayerConfig.TrialMode[trialName]
            local trialEntry = trialModeCfg[trialName]
                or trialModeCfg[trialName:gsub(" Enemies", "")]
                or trialModeCfg["Speedy Enemies"]
                or trialModeCfg["Speedy"]

            if trialEntry then
                if trialEntry.Towers then
                    hostReqTowers = trialEntry.Towers["Host"] or trialEntry.Towers.Host or {}
                    p2ReqTowers = trialEntry.Towers["P2"] or trialEntry.Towers.P2 or {}
                end
                if trialEntry.Level then
                    hostReqLevel = trialEntry.Level.Host or trialEntry.Level["Host"]
                    p2ReqLevel = trialEntry.Level.P2 or trialEntry.Level["P2"]
                end
            end

            -- Fallback support for older/alternative schemas
            if (not hostReqTowers or #hostReqTowers == 0) and trialModeCfg.Host and trialModeCfg.Host.Towers then
                hostReqTowers = trialModeCfg.Host.Towers["Tower 1"] or trialModeCfg.Host.Towers or {}
                if not hostReqLevel and trialModeCfg.Host.Level then hostReqLevel = trialModeCfg.Host.Level end
            end
            if not p2ReqTowers or #p2ReqTowers == 0 then
                local p2Section = trialModeCfg.IsP2 or trialModeCfg.P2
                if p2Section then
                    if p2Section.Towers and p2Section.Towers["Tower 1"] then
                        p2ReqTowers = p2Section.Towers["Tower 1"]
                    elseif p2Section.Speedy and p2Section.Speedy.Towers and p2Section.Speedy.Towers["Tower 1"] then
                        p2ReqTowers = p2Section.Speedy.Towers["Tower 1"]
                    elseif p2Section.Towers then
                        p2ReqTowers = p2Section.Towers
                    end
                    if not p2ReqLevel and p2Section.Level then p2ReqLevel = p2Section.Level end
                end
            end

            -- Fallback to RevampAutoTrials if not found in MultiplayerConfig
            local tConfig = trialName and RevampAutoTrials and (RevampAutoTrials[trialName] or RevampAutoTrials[trialName:gsub(" Enemies", "")])
            if (not hostReqTowers or #hostReqTowers == 0) and tConfig and tConfig.Towers then
                hostReqTowers = tConfig.Towers["Tower Config 1"] or tConfig.Towers["Tower 1"] or {}
                if not hostReqLevel and tConfig.Level then hostReqLevel = tConfig.Level end
            end
            if (not p2ReqTowers or #p2ReqTowers == 0) and tConfig and tConfig.Towers then
                p2ReqTowers = tConfig.Towers["Tower Config 2"] or tConfig.Towers["Tower 2"] or hostReqTowers
                if not p2ReqLevel and tConfig.Level then p2ReqLevel = tConfig.Level end
            end
        else
            -- Farm Mode
            local fbMode = Globals.MultiplayerFarmStrategy or "Molten"
            if fbMode == "Smart Auto" and typeof(resolveSmartFallback) == "function" then
                fbMode = resolveSmartFallback()
            end
            local fbCfg = FallbackConfigs and FallbackConfigs[fbMode]
            if fbCfg and fbCfg.Towers then
                hostReqTowers = fbCfg.Towers
                p2ReqTowers = fbCfg.Towers
            end
        end

        local isHost = Globals.MultiplayerIsHost == true
        local hostTarget = isHost and LocalPlayer or (Globals.MultiplayerTargetHost ~= "" and Globals.MultiplayerTargetHost or nil)
        local p2Target = not isHost and LocalPlayer or (Globals.MultiplayerTargetP2 ~= "" and Globals.MultiplayerTargetP2 or (Globals.MultiplayerHostIdentifier ~= "" and Globals.MultiplayerHostIdentifier or nil))

        local hostEligible, hostDesc, hostMissing = checkTowerEligibilityForPlayer(hostTarget, hostReqTowers, hostReqLevel, "Host")
        local p2Eligible, p2Desc, p2Missing = checkTowerEligibilityForPlayer(p2Target, p2ReqTowers, p2ReqLevel, "P2")

        if Globals.MultiplayerEnabled and (not hostEligible or not p2Eligible or #hostMissing > 0 or #p2Missing > 0) then
            warn(string.format("[Multiplayer] ERROR missing towers! %s | %s", hostDesc, p2Desc))
            print(string.format("[Multiplayer] ERROR missing towers! %s | %s", hostDesc, p2Desc))
        end

        UI.MultiplayerRequiredTowers:SetTitle(string.format("Multiplayer Towers (%s)", tostring(trialName)))
        UI.MultiplayerRequiredTowers:SetDesc(string.format("%s\n%s", hostDesc, p2Desc))
    end

    UI.MultiplayerToggle = MultiControlsSec:Toggle({
        Title = "Enable Multiplayer Mode",
        Desc = "Coordinates local party formation and matchmaking between Host and P2",
        Value = Globals.MultiplayerEnabled == true,
        Callback = function(val)
            SetSetting("MultiplayerEnabled", val)
            updateMultiplayerTowersLabel()
            if val then
                if UI.AutoToggle and Globals.AutoTrials then UI.AutoToggle:SetValue(false) end
                if UI.ProgAutoToggle and Globals.AutoTrials then UI.ProgAutoToggle:SetValue(false) end
                if UI.AutoEvoToggle and Globals.AutoEvo then UI.AutoEvoToggle:SetValue(false) end
                if UI.AutoGoldToggle and Globals.AutoGold then UI.AutoGoldToggle:SetValue(false) end
                currentMatchMode = "Multiplayer"
                if game.PlaceId == LOBBY_PLACE_ID then
                    task.spawn(fastQueueLobby)
                end
            else
                if game.PlaceId == LOBBY_PLACE_ID then
                    pcall(function()
                        local rf = ReplicatedStorage:FindFirstChild("RemoteFunction")
                        if rf then rf:InvokeServer("Multiplayer", "v2:stop") end
                    end)
                end
            end
            task.spawn(function() pcall(refreshDisplay) end)
        end,
    })

    MultiControlsSec:Dropdown({
        Title = "Multiplayer Mode",
        Desc = "Trial Mode runs trials; Farm Mode runs farming strategies",
        Searchable = false,
        Options = { "Trial Mode", "Farm Mode" },
        Value = tostring(Globals.MultiplayerMode or "Trial Mode"),
        Callback = function(val)
            SetSetting("MultiplayerMode", tostring(val))
            updateMultiplayerTowersLabel()
            task.spawn(function() pcall(refreshDisplay) end)
        end,
    })

    MultiControlsSec:Dropdown({
        Title = "Multiplayer Role",
        Desc = "Host creates the party and queues; P2 follows and joins",
        Searchable = false,
        Options = { "Host (Party Leader)", "P2 / Joiner (Party Follower)" },
        Value = Globals.MultiplayerIsHost and "Host (Party Leader)" or "P2 / Joiner (Party Follower)",
        Callback = function(val)
            if val == "Host (Party Leader)" then
                SetSetting("MultiplayerIsHost", true)
                SetSetting("MultiplayerIsP2", false)
            else
                SetSetting("MultiplayerIsHost", false)
                SetSetting("MultiplayerIsP2", true)
            end
            updateMultiplayerTowersLabel()
            task.spawn(function() pcall(refreshDisplay) end)
        end,
    })

    local mpTrialOptions = { "Current Rotation" }
    local addedTrials = { ["Current Rotation"] = true }
    for _, tName in ipairs(trialOptionsList) do
        if not addedTrials[tName] then
            table.insert(mpTrialOptions, tName)
            addedTrials[tName] = true
        end
    end
    local mpConfig = Requirements and Requirements.MultiplayerConfig or (getgenv and getgenv().MultiplayerConfig) or {}
    if mpConfig.TrialMode then
        for tName, _ in pairs(mpConfig.TrialMode) do
            if not addedTrials[tName] and not addedTrials[tName .. " Enemies"] then
                table.insert(mpTrialOptions, tName)
                addedTrials[tName] = true
            end
        end
    end

    MultiControlsSec:Dropdown({
        Title = "Target Trial (Trial Mode)",
        Desc = "Select specific trial or follow rotation for Trial Mode",
        Searchable = true,
        Options = mpTrialOptions,
        Value = tostring(Globals.MultiplayerSelectedTrial or "Current Rotation"),
        Callback = function(val)
            SetSetting("MultiplayerSelectedTrial", tostring(val))
            updateMultiplayerTowersLabel()
            task.spawn(function() pcall(refreshDisplay) end)
        end,
    })

    MultiControlsSec:Dropdown({
        Title = "Farm Strategy (Farm Mode)",
        Desc = "Select strategy when running Farm Mode",
        Searchable = false,
        Options = { "Molten", "Fallen", "Hardcore", "Smart Auto" },
        Value = tostring(Globals.MultiplayerFarmStrategy or "Molten"),
        Callback = function(val)
            SetSetting("MultiplayerFarmStrategy", tostring(val))
            updateMultiplayerTowersLabel()
            task.spawn(function() pcall(refreshDisplay) end)
        end,
    })

    UI.MultiplayerRequiredTowers = MultiControlsSec:Label({
        Title = "Required Towers",
        Desc = "Host Towers: Checking...\nP2 Towers: Checking..."
    })

    updateMultiplayerTowersLabel()

    -- 2. Host Configuration Section
    local HostSec = MultiplayerTab:Section({ Title = "Host Configuration (Party Leader)" })

    HostSec:Textbox({
        Title = "Target P2 Username / User ID",
        Desc = "Roblox Username or numeric User ID of P2 / Joiner",
        Placeholder = "Enter P2 username...",
        Value = tostring(Globals.MultiplayerTargetP2 or Globals.MultiplayerHostIdentifier or ""),
        Callback = function(text)
            local clean = tostring(text):gsub("^%s*(.-)%s*$", "%1")
            SetSetting("MultiplayerTargetP2", clean)
            SetSetting("MultiplayerHostIdentifier", clean)
            updateMultiplayerTowersLabel()
            task.spawn(function() pcall(refreshDisplay) end)
        end,
    })

    HostSec:Button({
        Title = "Invite P2 Now",
        Desc = "Creates in-game party and invites player in Target P2 textbox",
        Callback = function()
            local target = tostring(Globals.MultiplayerTargetP2 or Globals.MultiplayerHostIdentifier or ""):gsub("^%s*(.-)%s*$", "%1")
            if target == "" then
                warn("[Local Multiplayer] Target P2 textbox is empty!")
                return
            end
            LocalPartyManager:CreateAndInvite(target)
        end,
    })

    -- 3. P2 / Joiner Configuration Section
    local P2Sec = MultiplayerTab:Section({ Title = "P2 / Joiner Configuration (Party Follower)" })

    P2Sec:Textbox({
        Title = "Target Host Username / User ID",
        Desc = "Roblox Username or numeric User ID of Host to join",
        Placeholder = "Enter Host username...",
        Value = tostring(Globals.MultiplayerTargetHost or ""),
        Callback = function(text)
            local clean = tostring(text):gsub("^%s*(.-)%s*$", "%1")
            SetSetting("MultiplayerTargetHost", clean)
            updateMultiplayerTowersLabel()
            task.spawn(function() pcall(refreshDisplay) end)
        end,
    })

    P2Sec:Button({
        Title = "Accept Host Invite Now",
        Desc = "Accepts in-game party invite from Host specified above",
        Callback = function()
            local target = tostring(Globals.MultiplayerTargetHost or ""):gsub("^%s*(.-)%s*$", "%1")
            if target == "" then
                warn("[Local Multiplayer] Target Host textbox is empty!")
                return
            end
            LocalPartyManager:AcceptInviteFrom(target)
        end,
    })

    -- 4. Setup & Meeting Point Section
    local MeetingSec = MultiplayerTab:Section({ Title = "Private Server Meeting Point" })

    MeetingSec:Textbox({
        Title = "Private Server Code / Link",
        Desc = "Enter VIP link or linkCode. If separated, both players automatically TP here every 30s to meet",
        Placeholder = "https://roblox.com/share?code=... or linkCode",
        Value = tostring(Globals.PrivateServerCode or Globals.PrivateCode or ""),
        Callback = function(text)
            local clean = tostring(text):gsub("^%s*(.-)%s*$", "%1")
            SetSetting("PrivateServerCode", clean)
            SetSetting("PrivateCode", clean)
        end,
    })

    MeetingSec:Toggle({
        Title = "Enable 30s Server Watcher",
        Desc = "Automatically teleports to Private Server if peer is missing for 30 seconds",
        Value = Globals.LobbyWatcherEnabled ~= false,
        Callback = function(val)
            SetSetting("LobbyWatcherEnabled", val)
        end,
    })

    MeetingSec:Button({
        Title = "Teleport to Private Server Now",
        Desc = "Immediately teleports this account to the configured Private Server",
        Callback = function()
            local code = tostring(Globals.PrivateServerCode or Globals.PrivateCode or ""):gsub("^%s*(.-)%s*$", "%1")
            if code == "" then
                warn("[Local Multiplayer] Private Server Code is empty!")
                return
            end
            teleportToPrivateServer(code)
        end,
    })

    -- 5. Live Status & Party Controls Section
    local StatusSec = MultiplayerTab:Section({ Title = "Live Status & Controls" })

    UI.MultiplayerPartyStatusLabel = StatusSec:Label({
        Title = "In-Game Party Status",
        Desc = LocalPartyManager and LocalPartyManager.PartyStatusText or "No Party"
    })

    UI.MultiplayerPeerPresenceLabel = StatusSec:Label({
        Title = "Target Peer Presence",
        Desc = LocalPartyManager and LocalPartyManager.PeerStatusText or "Checking server..."
    })

    UI.MultiplayerWatcherStatusLabel = StatusSec:Label({
        Title = "30s Server Watcher",
        Desc = LocalPartyManager and LocalPartyManager.WatcherStatusText or "Watcher Idle"
    })

    StatusSec:Button({
        Title = "Leave Current Party",
        Desc = "Disbands or leaves in-game party",
        Callback = function()
            LocalPartyManager:LeaveParty()
        end,
    })

    local KeyTab = Window:Tab({
        Title = "Key",
        Subtitle = "Keyless, Standard Key, & Premium Access",
        Icon = "Key",
    })

    local KeySec = KeyTab:Section({ Title = "Access Tier Status" })
    KeySec:Label({ Title = "Engine Status", Desc = "Active & Running" })
    KeySec:Label({
        Title = "Current Mode",
        Desc = isPremiumUser and "Premium Active" or (isKeyUser and "Standard Key Mode Active" or "Keyless Mode Active")
    })

    local modeExplanation = "Keyless Mode: Farms unowned trials only. If the current trial is already owned (e.g. Fog), it strictly stays in the lobby and waits for the next rotation."
    if isPremiumUser then
        modeExplanation = "Premium Mode: Full automation unlocked (Progression Mode, multi-trial queue filters, fallbacks, auto tower purchases, auto evolutions)."
    elseif isKeyUser then
        modeExplanation = "Standard Key Mode: Classic repeat-trial mode. Farms the current rotation trial continuously over and over if eligible, even if already owned."
    end
    KeySec:Label({ Title = "Mode Description", Desc = modeExplanation })

    local currentKeyDisplay = getSavedKey()
    local hasSavedDiskKey = (currentKeyDisplay ~= "No Key Found" and currentKeyDisplay ~= nil and #currentKeyDisplay > 0)
    local maskedKey = currentKeyDisplay
    if hasSavedDiskKey and #currentKeyDisplay > 8 then
        maskedKey = currentKeyDisplay:sub(1, 4) .. "..." .. currentKeyDisplay:sub(-4)
    elseif not hasSavedDiskKey then
        maskedKey = "None (Running Keyless)"
    end

    KeySec:Label({ Title = "Current Active Key", Desc = maskedKey })

    local UnlockSec = KeyTab:Section({ Title = "Key Management & Actions" })

    -- Helper to apply validated key
    local function applyValidatedKey(cleanKey, result)
        saveVerifiedKey(cleanKey)
        Globals.SCRIPT_KEY = cleanKey
        Globals.IS_JD_PREMIUM = (result.is_premium == true or result.premium == true)
        Globals.JD_EXPIRES_AT = result.expires_at or result.expiresAt
        isKeyUser = true
        isPremiumUser = (Globals.IS_JD_PREMIUM == true)
        SetSetting("PreferredAccessTier", isPremiumUser and "Premium" or "Key")

        local reqModule = loadConfigRequirements()
        if reqModule then
            Requirements = reqModule
            RevampAutoTrials = Requirements.RevampAutoTrials
            if type(RevampAutoTrials) ~= "table" or next(RevampAutoTrials) == nil then
                RevampAutoTrials = Requirements.trialConfigs or {}
            end
            allTrialOptions = Requirements.allTrialOptions or {}
            fallbackModesList = Requirements.fallbackModesList or {}
            FallbackConfigs = Requirements.RevampedFallbackConfigs or Requirements.FallbackConfigs or Requirements.fallbackConfigs or {}
            CrateConfigs = Requirements.CrateConfigs or {}
            AutoEvoConfigs = Requirements.AutoEvoConfigs or (getgenv and getgenv().AutoEvoConfigs) or (shared and shared.AutoEvoConfigs) or {}
            ensureDynamicHardcoreFallback()
            AutoGoldModule.Configs = FallbackConfigs
            AutoGoldModule.CrateConfigs = CrateConfigs
        end

        Window:Notify({
            Title = isPremiumUser and "Premium Validated!" or "Standard Key Validated!",
            Desc = isPremiumUser and "Premium status unlocked successfully!" or "Standard Key Mode unlocked! (Farms current trial over and over)",
            Duration = 3,
        })

        task.defer(function()
            pcall(function()
                if UI.ScreenGui then UI.ScreenGui:Destroy() end
            end)
            task.wait(0.1)
            pcall(function()
                if setthreadidentity then pcall(setthreadidentity, 8) end
                buildInterface()
            end)
        end)
    end

    -- Auto-Load Saved Key Button:
    -- If currently in Keyless Mode, and a saved key exists on disk, offer the one-click auto-load button!
    if not isKeyUser and hasSavedDiskKey then
        UnlockSec:Button({
            Title = "Auto-Load Saved Key",
            Desc = "Validate and load saved key to unlock Standard Key Mode or Premium Mode",
            Image = "Key",
            Callback = function()
                local diskKey = loadVerifiedKey() or currentKeyDisplay
                if not diskKey or diskKey == "" or diskKey == "No Key Found" then
                    Window:Notify({ Title = "No Key Found", Desc = "No saved key was found on disk.", Duration = 3 })
                    return
                end

                Window:Notify({
                    Title = "Validating Saved Key",
                    Desc = "Checking key with Junkie SDK...",
                    Duration = 2,
                })

                task.spawn(function()
                    local Junkie = getJunkieSDK()
                    if not Junkie then
                        Window:Notify({ Title = "Validation Error", Desc = "Unable to reach Junkie SDK service.", Duration = 3 })
                        return
                    end

                    local success, result = pcall(function()
                        return Junkie.check_key(diskKey)
                    end)

                    if success and result and result.valid then
                        applyValidatedKey(diskKey, result)
                    else
                        Window:Notify({
                            Title = "Invalid Saved Key",
                            Desc = "Saved key is expired or invalid. Please enter a valid key below.",
                            Duration = 3,
                        })
                    end
                end)
            end,
        })
    end

    -- Switch to Keyless Mode Button (Available when in Standard Key or Premium Mode)
    if isKeyUser or isPremiumUser then
        UnlockSec:Button({
            Title = "Switch to Keyless Mode",
            Desc = "Return to Keyless Mode (farms unowned trials only, stays in lobby for owned trials)",
            Image = "LogOut",
            Callback = function()
                isKeyUser = false
                isPremiumUser = false
                Globals.IS_JD_PREMIUM = false
                Globals.SCRIPT_KEY = nil
                SetSetting("PreferredAccessTier", "Keyless")
                Window:Notify({
                    Title = "Keyless Mode Active",
                    Desc = "Switched to Keyless Mode. Will only farm unowned trials and stay in lobby when owned.",
                    Duration = 3,
                })
                task.defer(function()
                    pcall(function()
                        if UI.ScreenGui then UI.ScreenGui:Destroy() end
                    end)
                    task.wait(0.1)
                    pcall(function()
                        if setthreadidentity then pcall(setthreadidentity, 8) end
                        buildInterface()
                    end)
                end)
            end,
        })
    end

    UnlockSec:Textbox({
        Title = (isKeyUser or isPremiumUser) and "Upgrade / Change Key" or "Enter Standard / Premium Key",
        Desc = "Enter a Standard key (farms current trial over and over) or Premium key (full automation)",
        Placeholder = "Enter license key here...",
        Value = "",
        Callback = RunAsExecutor(function(newKey)
            local cleanKey = newKey:gsub("^%s*(.-)%s*$", "%1")
            if cleanKey == "" then return end

            Window:Notify({
                Title = "Validating Key",
                Desc = "Checking key with Junkie SDK...",
                Duration = 2,
            })

            task.spawn(function()
                local Junkie = getJunkieSDK()
                if not Junkie then
                    Window:Notify({ Title = "Validation Error", Desc = "Unable to reach Junkie SDK service.", Duration = 3 })
                    return
                end

                local success, result = pcall(function()
                    return Junkie.check_key(cleanKey)
                end)

                if success and result and result.valid then
                    applyValidatedKey(cleanKey, result)
                else
                    Window:Notify({
                        Title = "Invalid Key",
                        Desc = "The key provided is invalid or expired.",
                        Duration = 3,
                    })
                end
            end)
        end),
    })

    local InfoSec = KeyTab:Section({ Title = "Mode Breakdown & Differences" })
    InfoSec:Label({
        Title = "Keyless Mode",
        Desc = "• Free access\n• ONLY farms trials you do NOT own (e.g. if Fog is owned, stays in lobby)\n• Automatically advances your trial collection safely"
    })
    InfoSec:Label({
        Title = "Standard Key Mode",
        Desc = "• Unlocked with Standard Key\n• Classic repeat-trial mode: farms the current rotation trial continuously over and over if eligible\n• Repeats trials even if already owned"
    })
    InfoSec:Label({
        Title = "Premium Key Mode",
        Desc = "• Unlocked with Premium Key\n• Full automation: Progression Mode (Evo leveling, Coin/Gem farming, Skill Tree, Golden Skins)\n• Multi-trial filters, smart fallbacks, and auto tower purchases"
    })

    -- =================== Misc Tab ===================
    local MiscTab = Window:Tab({ Title = "Misc", Subtitle = "Webhooks & Options", Icon = "Gear" })

    local PrivateServerSec = MiscTab:Section({ Title = "Private Server Settings" })
    PrivateServerSec:Textbox({
        Title = "Private Server Code",
        Desc = "Enter private server link code for smart lobby teleporting",
        Placeholder = "Enter code here...",
        Value = tostring(Globals.PrivateCode or ""),
        Callback = function(text)
            SetSetting("PrivateCode", text:gsub("^%s*(.-)%s*$", "%1"))
        end,
    })

    local UtilitiesSec = MiscTab:Section({ Title = "Utilities" })

    UtilitiesSec:Toggle({
        Title = "Mobile Low Graphics Boost",
        Desc = "Disables shadows, particles, and post-processing for smooth FPS on budget mobile devices",
        Value = Globals.MobileBoost or false,
        Callback = function(val)
            SetSetting("MobileBoost", val)
            applyMobileOptimizations(val)
        end,
    })

    UtilitiesSec:Toggle({
        Title = "Auto Skip",
        Desc = "Automatically vote to skip waves when vote prompt appears",
        Value = Globals.AutoSkip or false,
        Callback = function(val)
            SetSetting("AutoSkip", val)
            if val and not AutoSkipRunning then
                StartAutoSkip()
            end
        end,
    })

    UtilitiesSec:Toggle({
        Title = "Enable Auto Gatling",
        Desc = "Automatically load Gatling assistant script in match",
        Value = Globals.AutoGatling or false,
        Callback = function(val)
            SetSetting("AutoGatling", val)
            if val and not AutoGatlingRunning then
                StartAutoGatling()
            end
        end,
    })

    UtilitiesSec:Dropdown({
        Title = "Gatling Loader",
        Desc = "Choose default script to load for Gatling Gun",
        Searchable = false,
        Options = { "Gatlify", "Gatling Gun" },
        Value = Globals.SelectedGatling or "Gatlify",
        Callback = function(val)
            SetSetting("SelectedGatling", tostring(val))
        end,
    })

    UtilitiesSec:Toggle({
        Title = "Auto Reload Gatling",
        Desc = "Automatically handle gatling reloading based on percentage",
        IsPrem = isPremiumUser,
        Value = Globals.AutoReloadGatling or false,
        Callback = function(val)
            SetSetting("AutoReloadGatling", val)
            if val and not AutoReloadRunning and typeof(StartAutoReloadGatling) == "function" then
                StartAutoReloadGatling()
            end
        end,
    })

    UtilitiesSec:Slider({
        Title = "Reload Percentage",
        Desc = "Percentage threshold till reload (100% = full reload)",
        IsPrem = isPremiumUser,
        Min = 0,
        Max = 100,
        Step = 5,
        Suffix = "%",
        Value = Globals.GatlingReloadPercent or 100,
        Callback = function(val)
            SetSetting("GatlingReloadPercent", val)
        end,
    })

    UI.AutoReloadStatusLabel = UtilitiesSec:Label({
        Title = "Gatling Reload Status",
        Desc = "Status: Idle"
    })

    UtilitiesSec:Toggle({
        Title = "Enable Auto Timescale",
        Desc = "Automatically unlock and apply timescale multipliers",
        Value = Globals.TimeScaleEnabled or false,
        Callback = function(v)
            SetSetting("TimeScaleEnabled", v)
            if v and not TimeScaleRunning then
                StartTimeScale()
            end
        end,
    })

    UtilitiesSec:Slider({
        Title = "Timescale Target Speed",
        Desc = "Select the game speed multiplier to maintain (0.5x to 2.0x)",
        Min = 0.5,
        Max = 2.0,
        Step = 0.5,
        Suffix = "x",
        Value = Globals.TimeScaleValue or 2,
        Callback = function(choice)
            local value = tonumber(choice) or 2
            SetSetting("TimeScaleValue", value)
            if Globals.TimeScaleEnabled then
                ApplyTimeScaleOnce()
            end
        end,
    })

    local InterfaceSec = MiscTab:Section({ Title = "Interface & Keybind" })
    InterfaceSec:Keybind({
        Title = "Toggle UI Keybind",
        Desc = "Press any key to rebind the GUI toggle shortcut",
        Default = Window.Keybind or Enum.KeyCode.RightShift,
        Callback = function(newKey, keyName)
            Window.Keybind = newKey
            Window:Notify({ Title = "Keybind Updated", Desc = "GUI toggle set to [ " .. keyName .. " ]", Duration = 2 })
            logActivity("UI toggle keybind changed to " .. keyName, "info")
        end
    })

    local QuickActionsSec = MiscTab:Section({ Title = "Quick Actions" })
    QuickActionsSec:Button({
        Title = "Smart Lobby Teleport",
        Desc = "Safely return to a clean lobby instance with fail-safes",
        Image = "Globe",
        Callback = function()
            Window:Dialog({
                Title = "Return to Lobby?",
                Content = "Are you sure you want to teleport back to the lobby? In-game match will be abandoned.",
                ConfirmText = "Teleport",
                CancelText = "Stay In Game",
                Danger = true,
                OnConfirm = function()
                    logActivity("Manual smart lobby teleport initiated.", "warn")
                    Window:Notify({ Title = "Teleporting", Desc = "Searching for optimal lobby...", Duration = 3 })
                    SmartTeleportToLobby()
                end
            })
        end
    })

    local WebhookSec = MiscTab:Section({ Title = "Discord Webhook Integration" })
    WebhookSec:Textbox({
        Title = "Webhook URL",
        Desc = "Discord webhook link for status notifications",
        Placeholder = "Paste Discord Webhook URL here...",
        Value = Globals.WebhookURL or "",
        Callback = function(text)
            SetSetting("WebhookURL", text:gsub("^%s*(.-)%s*$", "%1"))
        end,
    })

    -- =================== Console Tab ===================
    local ConsoleTab = Window:Tab({
        Title = "Console",
        Subtitle = "Live Activity & Logs",
        Icon = "Terminal",
    })

    local ConsoleSec = ConsoleTab:Section({ Title = "Engine Feed" })
    UI.LogConsole = ConsoleSec:LogConsole({
        Title = "Service Hub v9.8 Live Feed",
        Height = 220,
        AutoScroll = true
    })
    UI.LogConsole:Success("Service Hub v9.8 initialized (Cloud Loadstring Edition).")
    UI.LogConsole:Info("CoreRevampNewAPI connected.")
    if isPremiumUser then
        UI.LogConsole:Success("License: Premium Verified (VIP Access).")
    else
        UI.LogConsole:Log("License: Standard Edition.")
    end

    task.spawn(function()
        task.wait(0.2)
        pcall(function()
            if not PlayerDataHandler then
                PlayerDataHandler = loadPlayerDataHandler()
            end
            if typeof(refreshDisplay) == "function" then
                refreshDisplay()
            end
        end)
    end)
end

sendEvoPurchaseWebhook = function(towerName, evoName)
    local url = Globals.WebhookURL
    if type(url) ~= "string" or url == "" then return end
    local httprequest = (syn and syn.request) or (http and http.request) or http_request or (fluxus and fluxus.request) or request
    if not httprequest then return end

    local currentState = "Lobby"
    if game.PlaceId ~= LOBBY_PLACE_ID then currentState = "Ingame" end

    pcall(function()
        local embed = {
            ["title"] = "🛒 Evolution Purchase",
            ["description"] = "Attempting to evolve a tower.",
            ["color"] = 16776960,
            ["timestamp"] = DateTime.now():ToIsoDate(),
            ["footer"] = { ["text"] = "ServiceHub V2 • Play Smart, Not Hard", ["icon_url"] = "https://i.imgur.com/W35kZkU.png" },
            ["fields"] = {
                { ["name"] = "Purchase", ["value"] = "waiting....", ["inline"] = false },
                { ["name"] = "Purchased", ["value"] = "check [ " .. (evoName or towerName) .. " ]", ["inline"] = false },
                { ["name"] = "State", ["value"] = currentState, ["inline"] = false }
            }
        }
        httprequest({
            Url = url, Method = "POST", Headers = { ["Content-Type"] = "application/json" },
            Body = game:GetService("HttpService"):JSONEncode({ ["username"] = "ServiceHub", ["avatar_url"] = "https://i.imgur.com/W35kZkU.png", ["embeds"] = { embed } })
        })
    end)
end

--==============================================================================
-- Main Display & Auto-Queue Update Engine
--==============================================================================
local lastRefreshDisplayTick = 0
refreshDisplay = function()
    local nowClock = os.clock()
    if nowClock - lastRefreshDisplayTick < 2.5 then return end
    lastRefreshDisplayTick = nowClock
    if setthreadidentity then pcall(setthreadidentity, 8) end
    pcall(checkRuntimeKeyExpiration)
    if not PlayerDataHandler then return end

    local coins, targetCoins, gems, targetGems, coinsDisplay, gemsDisplay = getCurrencyAndTargets()

    if coinsTrackerLabel then
        pcall(function() coinsTrackerLabel:SetDesc(coinsDisplay) end)
    end

    if gemsTrackerLabel then
        pcall(function() gemsTrackerLabel:SetDesc(gemsDisplay) end)
    end

    if UI and UI.CurrencyGrid then
        pcall(function()
            UI.CurrencyGrid:UpdateItem(1, coinsDisplay, "Current / Target Coins")
            UI.CurrencyGrid:UpdateItem(2, gemsDisplay, "Current / Target Gems")
        end)
    end

    if UI and UI.ProgCurrency then
        pcall(function()
            UI.ProgCurrency:SetDesc(string.format("Coins: %s\nGems: %s", coinsDisplay, gemsDisplay))
        end)
    end

    if game.PlaceId == LOBBY_PLACE_ID then
        pcall(processAutoPurchases)
    end

    if Globals.AutoGold and isPremiumUser then
        local targetCoins = tonumber(Globals.TargetCoins) or 0
        local targetGems = tonumber(Globals.TargetGems) or 0
        if (targetCoins > 0 and coins >= targetCoins) or (targetGems > 0 and gems >= targetGems) then
            Globals.AutoGold = false
            SetSetting("AutoGold", false)
            if UI.AutoGoldToggle then UI.AutoGoldToggle:SetValue(false) end
            
            if targetCoins > 0 and coins >= targetCoins then
                SetSetting("TargetCoins", 0)
                if UI.TargetCoinsBox then UI.TargetCoinsBox:SetValue("0") end
            end
            if targetGems > 0 and gems >= targetGems then
                SetSetting("TargetGems", 0)
                if UI.TargetGemsBox then UI.TargetGemsBox:SetValue("0") end
            end
            if UI and UI.Window and typeof(UI.Window.Notify) == "function" then
                RunAsExecutor(function()
                    UI.Window:Notify({
                        Title = "Target Reached",
                        Desc = (game.PlaceId == LOBBY_PLACE_ID) and "AutoGold stopped and targets reset to 0." or "Target reached! Match will conclude before returning to lobby.",
                        Duration = 5
                    })
                end)()
            end
            
            if game.PlaceId == LOBBY_PLACE_ID then
                SmartTeleportToLobby()
            else
                Globals.IsConfigDirty = true
            end
        end
    end
    
    local selected = tostring(Globals.TargetEvo or "All")
    local toCheck = {}
    local activeTowerFound = nil

    if selected == "All" then
        for _, tName in ipairs({ "Scout", "Shotgunner", "Crook Boss", "Minigunner" }) do
            if not isTowerEvoComplete(tName) and isTowerOrEvoOwned(tName) then
                if not activeTowerFound then
                    activeTowerFound = tName
                end
            end
        end
        if activeTowerFound then
            toCheck = { activeTowerFound }
        else
            toCheck = {}
        end
    elseif EvoData[selected] then
        toCheck = { selected }
        activeTowerFound = selected
    end
    
    if UI.EvoCoinsGemsLabel then
        local coinsStr, gemsStr
        if #toCheck == 0 then
            coinsStr = "Coins: " .. coinsDisplay .. " (Complete)"
            gemsStr = "Gems: " .. gemsDisplay .. " (Complete)"
        elseif activeTowerFound and EvoData[activeTowerFound] then
            local evoInfo = EvoData[activeTowerFound]
            local ownsActiveEvo = typeof(PlayerDataHandler.IsTowerOwned) == "function" and PlayerDataHandler:IsTowerOwned(evoInfo.Evo)
            if ownsActiveEvo then
                coinsStr = "Coins: " .. coinsDisplay .. " (" .. activeTowerFound .. " Owned)"
                gemsStr = "Gems: " .. gemsDisplay .. " (Grinding Level)"
            else
                coinsStr = string.format("Coins: %s / %s", formatNumberWithCommas(coins), formatNumberWithCommas(evoInfo.Coins))
                gemsStr = string.format("Gems: %s / %s", formatNumberWithCommas(gems), formatNumberWithCommas(evoInfo.Gems))
            end
        else
            coinsStr = "Coins: " .. coinsDisplay
            gemsStr = "Gems: " .. gemsDisplay
        end
        
        UI.EvoCoinsGemsLabel:SetDesc(coinsStr .. "\n" .. gemsStr)
    end
    
    if UI.EvoTowersLabel then
        local towersText = ""
        local grindState = "Idle / Finished"
        local stateFound = false
        
        if #toCheck > 0 then
            local lines = {}
            for _, towerName in ipairs(toCheck) do
                local eData = EvoData[towerName]
                local evoName = eData and eData.Evo or towerName
               
                
                local ownsEvo = typeof(PlayerDataHandler.IsTowerOwned) == "function" and PlayerDataHandler:IsTowerOwned(evoName)
                if ownsEvo then
                    table.insert(lines, towerName .. ": Complete!")
                    if typeof(PlayerDataHandler.GetTowerExp) == "function" then
                        local evoExp = PlayerDataHandler:GetTowerExp(evoName)
                        if evoExp then
                            if evoExp.Level < 20 then
                                table.insert(lines, string.format("%s: Level %d/20 (%s)", evoName, evoExp.Level, evoExp.ProgressDisplay))
                                if not stateFound then grindState = "Grinding level..."; stateFound = true; Globals.CurrentEvoActiveTower = towerName end
                            else
                                table.insert(lines, evoName .. ": Complete!")
                            end
                        else
                            table.insert(lines, evoName .. ": (Waiting for data)")
                        end
                    end
                else
                    if typeof(PlayerDataHandler.IsTowerOwned) == "function" and not PlayerDataHandler:IsTowerOwned(towerName) then
                        table.insert(lines, towerName .. ": Tower not owned")
                        table.insert(lines, evoName .. ": Locked")
                        if not stateFound then grindState = "Grinding coins..."; stateFound = true; Globals.CurrentEvoActiveTower = towerName end
                    else
                        if typeof(PlayerDataHandler.GetTowerExp) == "function" then
                            local expData = PlayerDataHandler:GetTowerExp(towerName)
                            if expData then
                                local coinsNeed = math.max(0, eData.Coins - coins)
                                local gemsNeed = math.max(0, eData.Gems - gems)
                                
                                if expData.Level < 20 then
                                    table.insert(lines, string.format("%s: Level %d/20 (%s)", towerName, expData.Level, expData.ProgressDisplay))
                                end
                                
                                if coinsNeed == 0 and gemsNeed == 0 then
                                    if expData.Level < 20 then
                                        if not stateFound then grindState = "Grinding level..."; stateFound = true; Globals.CurrentEvoActiveTower = towerName end
                                    else
                                        table.insert(lines, towerName .. ": Complete!")
                                        if not stateFound then grindState = "Buying Selected Evo...."; stateFound = true; Globals.CurrentEvoActiveTower = towerName end
                                        
                                        if Globals.AutoEvo and not buyingEvoDebounce then
                                            buyingEvoDebounce = true
                                            task.spawn(function()
                                                pcall(function()
                                                    local rf = game:GetService("ReplicatedStorage"):FindFirstChild("RemoteFunction")
                                                    if rf then
                                                        sendEvoPurchaseWebhook(towerName, evoName)
                                                        rf:InvokeServer("Shop", "EvolveTower", towerName)
                                                    end
                                                end)
                                                task.wait(4)
                                                buyingEvoDebounce = false
                                            end)
                                        end
                                    end
                                else
                                    local reqStr = {}
                                    if coinsNeed > 0 then table.insert(reqStr, formatNumberWithCommas(coinsNeed) .. " Coins") end
                                    if gemsNeed > 0 then table.insert(reqStr, formatNumberWithCommas(gemsNeed) .. " Gems") end
                                    table.insert(lines, string.format("%s: Needs %s", towerName, table.concat(reqStr, ", ")))
                                    
                                    if not stateFound then
                                        if coinsNeed > 0 then grindState = "Grinding coins..."
                                        else grindState = "Grinding gems..." end
                                        stateFound = true
                                        Globals.CurrentEvoActiveTower = towerName
                                    end
                                end
                            else
                                table.insert(lines, towerName .. ": (Waiting for data)")
                            end
                            table.insert(lines, evoName .. ": Locked (Requires Base)")
                        else
                            table.insert(lines, towerName .. ": (Update DataHandler)")
                        end
                    end
                end
                table.insert(lines, "") -- blank line separator
            end
            towersText = table.concat(lines, "\n"):gsub("\n$", "")
        else
            towersText = (selected == "All") and "All Evolutions Complete!" or "(No target selected)"
            grindState = (selected == "All") and "Idle / Finished" or "No target selected"
        end
        
        UI.EvoTowersLabel:SetDesc(towersText)
        
        Globals.CurrentEvoGrindState = grindState
        SetSetting("CurrentEvoGrindState", grindState)

        if grindState == "Grinding coins..." then
            Globals.CurrentEvoFarmType = "Coins"
            SetSetting("CurrentEvoFarmType", "Coins")
        elseif grindState == "Grinding gems..." or grindState == "Grinding level..." then
            Globals.CurrentEvoFarmType = "Gems"
            SetSetting("CurrentEvoFarmType", "Gems")
        else
            Globals.CurrentEvoFarmType = nil
            SetSetting("CurrentEvoFarmType", nil)
            Globals.CurrentEvoActiveTower = nil
            if Globals.AutoEvo and isPremiumUser and grindState == "Idle / Finished" then
                Globals.AutoEvo = false
                SetSetting("AutoEvo", false)
                if UI.AutoEvoToggle then UI.AutoEvoToggle:SetValue(false) end
                
                if UI and UI.Window and typeof(UI.Window.Notify) == "function" then
                    RunAsExecutor(function()
                        UI.Window:Notify({ Title = "Auto Evo Complete", Desc = "All target evolutions are fully leveled!", Duration = 5 })
                    end)()
                end
                if game.PlaceId ~= LOBBY_PLACE_ID then
                    Globals.IsConfigDirty = true
                    Globals.AutoEvoMilestoneReached = true
                end
            end
        end
        
        SetSetting("CurrentEvoActiveTower", Globals.CurrentEvoActiveTower)

        if game.PlaceId ~= LOBBY_PLACE_ID and Globals.AutoEvo then
            -- Live check if Coins, Gems, Level 20, or Evo Exp 20 milestone was reached
            local milestoneReached, milestoneReason = checkAutoEvoMilestonesReached()
            if milestoneReached then
                Globals.IsConfigDirty = true
                if not Globals.AutoEvoMilestoneReached then
                    Globals.AutoEvoMilestoneReached = true
                    if UI and UI.Window and typeof(UI.Window.Notify) == "function" then
                        RunAsExecutor(function()
                            UI.Window:Notify({
                                Title = "AUTO EVO MILESTONE",
                                Desc = tostring(milestoneReason) .. "! Match will finish before returning to Smart Lobby.",
                                Duration = 6,
                                Type = "info"
                            })
                        end)()
                    end
                end
            end
        end
        Globals.PreviousEvoGrindState = Globals.CurrentEvoGrindState
        Globals.PreviousEvoFarmType = Globals.CurrentEvoFarmType
    end

    if not PlayerDataHandler then
        PlayerDataHandler = loadPlayerDataHandler()
    end

    if game.PlaceId ~= LOBBY_PLACE_ID then
        if UI.Window and UI.Window.SetSubtitle then
            pcall(function()
                if setthreadidentity then pcall(setthreadidentity, 8) end
                UI.Window:SetSubtitle("IN-GAME : Active Match")
            end)
        end
    end

    local analysis = analyzeCurrentTrial()
    local playerLevel = PlayerDataHandler and PlayerDataHandler:GetLevel() or 0

    local missingParts = {}
    if not analysis.levelPassed then
        table.insert(missingParts, string.format("Level %d (You: %d)", analysis.requiredLevel, playerLevel))
    end
    if #analysis.missingTowers > 0 then
        table.insert(missingParts, "Towers: " .. table.concat(analysis.missingTowers, ", "))
    end
    if #analysis.missingGold > 0 then
        table.insert(missingParts, "Golden: " .. table.concat(analysis.missingGold, ", "))
    end
    if #analysis.missingSkills > 0 then
        table.insert(missingParts, "Skill Tree: " .. table.concat(analysis.missingSkills, ", "))
    end

    local wasLocked = isRequirementLocked
    isRequirementLocked = (#missingParts > 0 or not analysis.configFound)

    if wasLocked and not isRequirementLocked then
        if Globals.TrialFarmMode == "Progression Mode" then
            if UI.ProgAutoToggle then UI.ProgAutoToggle:SetValue(Globals.AutoTrials) end
        else
            if UI.AutoToggle then UI.AutoToggle:SetValue(Globals.AutoTrials) end
        end
    end

    if setthreadidentity then pcall(setthreadidentity, 8) end

    if UI.CurrentTrial then
        pcall(function()
            if setthreadidentity then pcall(setthreadidentity, 8) end
            if analysis.currentMap and analysis.currentMap ~= "Unknown" then
                UI.CurrentTrial:SetDesc(string.format("%s | Map: %s | Time Left: %s", analysis.trialName, analysis.currentMap, analysis.timeRemaining))
            else
                UI.CurrentTrial:SetDesc(string.format("%s | Time Left: %s", analysis.trialName, analysis.timeRemaining))
            end
        end)
    end

    if UI.NextTrial then
        pcall(function()
            if setthreadidentity then pcall(setthreadidentity, 8) end
            if analysis.nextTrialMap and analysis.nextTrialMap ~= "Unknown" then
                UI.NextTrial:SetDesc(string.format("%s | Map: %s | Time Left: %s", analysis.nextTrialName, analysis.nextTrialMap, analysis.nextTimeRemaining))
            else
                UI.NextTrial:SetDesc(string.format("%s | Time Left: %s", analysis.nextTrialName, analysis.nextTimeRemaining))
            end
        end)
    end

    if UI.OwnedTrialLabels then
        pcall(function()
            if setthreadidentity then pcall(setthreadidentity, 8) end
            local trialsList = nil
            if PlayerDataHandler and typeof(PlayerDataHandler.GetAllTrialsList) == "function" then
                trialsList = PlayerDataHandler:GetAllTrialsList()
            end
            if trialsList and #trialsList > 0 then
                for _, tInfo in ipairs(trialsList) do
                    local lbl = UI.OwnedTrialLabels[tInfo.Name] or UI.OwnedTrialLabels[tInfo.Title]
                    if not lbl then
                        for k, v in pairs(UI.OwnedTrialLabels) do
                            if normalizeString(k) == normalizeString(tInfo.Name) or normalizeString(k) == normalizeString(tInfo.Title) then
                                lbl = v
                                break
                            end
                        end
                    end
                    if lbl then
                        local stat = tInfo.Status
                        if stat == "✓" or stat == true or tostring(stat):find("✓") then
                            stat = "YES"
                        elseif stat == "✗" or stat == false or tostring(stat):find("✗") then
                            stat = "NO"
                        end
                        lbl:SetDesc(string.format("Map: %s | Owned: %s", tInfo.Map, stat))
                    end
                end
            else
                local status = PlayerDataHandler and typeof(PlayerDataHandler.GetTrialsStatus) == "function" and PlayerDataHandler:GetTrialsStatus()
                local wonLookup = {}
                if status and status.Won then
                    for _, n in ipairs(status.Won) do
                        wonLookup[n] = true
                        wonLookup[normalizeString(n)] = true
                    end
                end
                for _, tDef in ipairs(staticTrialDefs) do
                    local lbl = UI.OwnedTrialLabels[tDef.Name] or UI.OwnedTrialLabels[tDef.Title]
                    if not lbl then
                        for k, v in pairs(UI.OwnedTrialLabels) do
                            if normalizeString(k) == normalizeString(tDef.Name) or normalizeString(k) == normalizeString(tDef.Title) then
                                lbl = v
                                break
                            end
                        end
                    end
                    if lbl then
                        local isWon = false
                        if PlayerDataHandler and typeof(PlayerDataHandler.IsTrialWon) == "function" then
                            isWon = PlayerDataHandler:IsTrialWon(tDef.Name) or PlayerDataHandler:IsTrialWon(tDef.Title)
                        elseif wonLookup[tDef.Name] or wonLookup[tDef.Title] or wonLookup[normalizeString(tDef.Name)] then
                            isWon = true
                        end
                        lbl:SetDesc(string.format("Map: %s | Owned: %s", tDef.Map, isWon and "YES" or "NO"))
                    end
                end
            end
        end)
    end

    if UI.ProgCoinTowers or UI.ProgGemTowers or UI.ProgEvoTowers or UI.ProgGoldenSkins or UI.ProgSkillTree then
        pcall(function()
            if setthreadidentity then pcall(setthreadidentity, 8) end

            -- 1. Claim Towers (Crook Boss, Turret, Mortar, Mercenary Base)
            if UI.ProgClaimTowers then
                local claimDefs = {
                    { Name = "Crook Boss", LevelReq = 30 },
                    { Name = "Turret", LevelReq = 50 },
                    { Name = "Mortar", LevelReq = 75 },
                    { Name = "Mercenary Base", LevelReq = 150 },
                }
                local totalClaim = #claimDefs
                local ownedClaim = 0
                local statusParts = {}
                local pLvl = (PlayerDataHandler and typeof(PlayerDataHandler.GetLevel) == "function") and PlayerDataHandler:GetLevel() or 0

                for _, ct in ipairs(claimDefs) do
                    local isOwned = false
                    if PlayerDataHandler and typeof(PlayerDataHandler.IsTowerOwned) == "function" then
                        isOwned = PlayerDataHandler:IsTowerOwned(ct.Name)
                    end
                    if isOwned then
                        ownedClaim = ownedClaim + 1
                    else
                        if pLvl >= ct.LevelReq then
                            table.insert(statusParts, string.format("%s (Ready to Claim!)", ct.Name))
                        else
                            table.insert(statusParts, string.format("%s (Lvl %d)", ct.Name, ct.LevelReq))
                        end
                    end
                end

                if ownedClaim >= totalClaim then
                    UI.ProgClaimTowers:SetTitle(string.format("Claim Towers (%d/%d)", totalClaim, totalClaim))
                    UI.ProgClaimTowers:SetDesc("✓ All Level Reward Claim Towers Owned")
                else
                    UI.ProgClaimTowers:SetTitle(string.format("Claim Towers (%d/%d)", ownedClaim, totalClaim))
                    UI.ProgClaimTowers:SetDesc(string.format("Unclaimed: %s", table.concat(statusParts, ", ")))
                end
            end

            -- 2. Coin Towers
            if UI.ProgCoinTowers and TowerList and TowerList.Coins then
                local totalCoins = #TowerList.Coins
                local ownedCoins = 0
                local missingCoins = {}
                local totalMissingCoinsCost = 0
                local pLvl = (PlayerDataHandler and typeof(PlayerDataHandler.GetLevel) == "function") and PlayerDataHandler:GetLevel() or 0

                for _, t in ipairs(TowerList.Coins) do
                    local isOwned = false
                    if PlayerDataHandler and typeof(PlayerDataHandler.IsTowerOwned) == "function" then
                        isOwned = PlayerDataHandler:IsTowerOwned(t.Name)
                    end
                    if isOwned then
                        ownedCoins = ownedCoins + 1
                    else
                        local reqLvl = t.LevelReq or (LevelCoinTowers and LevelCoinTowers[t.Name] and LevelCoinTowers[t.Name].LevelReq) or 0
                        if reqLvl > 0 and pLvl < reqLvl then
                            table.insert(missingCoins, string.format("%s (Lvl %d Req)", t.Name, reqLvl))
                        else
                            table.insert(missingCoins, t.Name)
                        end
                        totalMissingCoinsCost = totalMissingCoinsCost + (t.Cost or 0)
                    end
                end

                if ownedCoins >= totalCoins then
                    UI.ProgCoinTowers:SetTitle(string.format("Coin Towers (%d/%d)", totalCoins, totalCoins))
                    UI.ProgCoinTowers:SetDesc("✓ All Coin Towers Owned")
                else
                    UI.ProgCoinTowers:SetTitle(string.format("Coin Towers (%d/%d)", ownedCoins, totalCoins))
                    if #missingCoins <= 3 then
                        UI.ProgCoinTowers:SetDesc(string.format("Missing: %s | Cost: %s Coins", table.concat(missingCoins, ", "), formatNumberWithCommas(totalMissingCoinsCost)))
                    else
                        UI.ProgCoinTowers:SetDesc(string.format("Missing: %d Towers | Cost: %s Coins", #missingCoins, formatNumberWithCommas(totalMissingCoinsCost)))
                    end
                end
            end

            -- 2. Hardcore Towers
            if UI.ProgGemTowers and TowerList and TowerList.Gems then
                local totalGems = #TowerList.Gems
                local ownedGems = 0
                local missingGems = {}
                local totalMissingGemsCost = 0

                for _, t in ipairs(TowerList.Gems) do
                    local isOwned = false
                    if PlayerDataHandler and typeof(PlayerDataHandler.IsTowerOwned) == "function" then
                        isOwned = PlayerDataHandler:IsTowerOwned(t.Name)
                    end
                    if isOwned then
                        ownedGems = ownedGems + 1
                    else
                        table.insert(missingGems, t.Name)
                        totalMissingGemsCost = totalMissingGemsCost + (t.Cost or 0)
                    end
                end

                if ownedGems >= totalGems then
                    UI.ProgGemTowers:SetTitle(string.format("Hardcore Towers (%d/%d)", totalGems, totalGems))
                    UI.ProgGemTowers:SetDesc("✓ All Hardcore Towers Owned")
                else
                    UI.ProgGemTowers:SetTitle(string.format("Hardcore Towers (%d/%d)", ownedGems, totalGems))
                    UI.ProgGemTowers:SetDesc(string.format("Missing: %s | Cost: %s Gems", table.concat(missingGems, ", "), formatNumberWithCommas(totalMissingGemsCost)))
                end
            end

            -- 3. Evolved Towers
            if UI.ProgEvoTowers then
                local evoDefs = {
                    { Base = "Scout", Evo = "EvolvedOperator", Coins = 15000, Gems = 4500 },
                    { Base = "Shotgunner", Evo = "EvolvedEnforcer", Coins = 15000, Gems = 5000 },
                    { Base = "Crook Boss", Evo = "EvolvedKingpin", Coins = 15000, Gems = 5500 },
                    { Base = "Minigunner", Evo = "EvolvedJuggernaut", Coins = 15000, Gems = 6000 },
                }
                local totalEvo = #evoDefs
                local ownedEvo = 0
                local activeTarget = nil
                local activeExpData = nil
                local missingEvoBases = {}

                for _, def in ipairs(evoDefs) do
                    local isOwned = false
                    if PlayerDataHandler and typeof(PlayerDataHandler.IsTowerOwned) == "function" then
                        isOwned = PlayerDataHandler:IsTowerOwned(def.Evo)
                    end
                    if not isOwned and typeof(isTowerEvoComplete) == "function" then
                        isOwned = isTowerEvoComplete(def.Evo) or isTowerEvoComplete(def.Base)
                    end

                    if isOwned then
                        ownedEvo = ownedEvo + 1
                    else
                        table.insert(missingEvoBases, def.Base)
                        if not activeTarget then
                            activeTarget = def
                            if PlayerDataHandler and typeof(PlayerDataHandler.GetTowerExp) == "function" then
                                pcall(function()
                                    activeExpData = PlayerDataHandler:GetTowerExp(def.Base)
                                end)
                            end
                        end
                    end
                end

                if ownedEvo >= totalEvo then
                    UI.ProgEvoTowers:SetTitle(string.format("Evolved Towers (%d/%d)", totalEvo, totalEvo))
                    UI.ProgEvoTowers:SetDesc("✓ All Evolved Towers Owned & Complete")
                elseif activeTarget then
                    UI.ProgEvoTowers:SetTitle(string.format("Evolved Towers (%d/%d)", ownedEvo, totalEvo))

                    local baseLvl = (activeExpData and type(activeExpData.Level) == "number") and activeExpData.Level or 0
                    local curExp = (activeExpData and type(activeExpData.Exp) == "number") and activeExpData.Exp or 0
                    local maxExp = (activeExpData and type(activeExpData.MaxExp) == "number") and activeExpData.MaxExp or 0
                    local missingExp = math.max(0, maxExp - curExp)

                    if baseLvl < 20 then
                        if maxExp > 0 then
                            UI.ProgEvoTowers:SetDesc(string.format("[%s] Lvl %d/20 (%s/%s EXP | -%s EXP) | Needs %sk C, %sk G",
                                activeTarget.Base, baseLvl, formatNumberWithCommas(curExp), formatNumberWithCommas(maxExp), formatNumberWithCommas(missingExp),
                                tostring(activeTarget.Coins / 1000), tostring(activeTarget.Gems / 1000)))
                        else
                            UI.ProgEvoTowers:SetDesc(string.format("[%s] Lvl %d/20 (EXP: %s) | Needs %sk C, %sk G",
                                activeTarget.Base, baseLvl, formatNumberWithCommas(curExp),
                                tostring(activeTarget.Coins / 1000), tostring(activeTarget.Gems / 1000)))
                        end
                    else
                        local playerCoins = 0
                        local playerGems = 0
                        pcall(function()
                            if typeof(PlayerDataHandler.GetCoins) == "function" then playerCoins = PlayerDataHandler:GetCoins() or 0 end
                            if typeof(PlayerDataHandler.GetGems) == "function" then playerGems = PlayerDataHandler:GetGems() or 0 end
                        end)
                        local coinsNeed = math.max(0, activeTarget.Coins - playerCoins)
                        local gemsNeed = math.max(0, activeTarget.Gems - playerGems)
                        if coinsNeed == 0 and gemsNeed == 0 then
                            UI.ProgEvoTowers:SetDesc(string.format("[%s] Lvl 20 Reached! Ready to Evolve in Lobby!", activeTarget.Base))
                        else
                            local needParts = {}
                            if coinsNeed > 0 then table.insert(needParts, formatNumberWithCommas(coinsNeed) .. " Coins") end
                            if gemsNeed > 0 then table.insert(needParts, formatNumberWithCommas(gemsNeed) .. " Gems") end
                            UI.ProgEvoTowers:SetDesc(string.format("[%s] Lvl 20 Reached! Needs: %s to Evolve", activeTarget.Base, table.concat(needParts, ", ")))
                        end
                    end
                else
                    UI.ProgEvoTowers:SetTitle(string.format("Evolved Towers (%d/%d)", ownedEvo, totalEvo))
                    UI.ProgEvoTowers:SetDesc(string.format("Missing: %s", table.concat(missingEvoBases, ", ")))
                end
            end

            -- 3. Golden Skins
            if UI.ProgGoldenSkins and TowerList and TowerList.Golden then
                local totalGold = #TowerList.Golden
                local ownedGold = 0
                local missingGold = {}
                local totalMissingGoldCost = 0

                for _, g in ipairs(TowerList.Golden) do
                    local baseTower = g.Name:gsub("^Golden%s+", "")
                    local isOwned = false
                    if PlayerDataHandler and typeof(PlayerDataHandler.IsGoldenOwned) == "function" then
                        isOwned = PlayerDataHandler:IsGoldenOwned(g.Name) or PlayerDataHandler:IsGoldenOwned(baseTower)
                    end
                    if isOwned then
                        ownedGold = ownedGold + 1
                    else
                        table.insert(missingGold, g.Name)
                        totalMissingGoldCost = totalMissingGoldCost + (g.Cost or 50000)
                    end
                end

                if ownedGold >= totalGold then
                    UI.ProgGoldenSkins:SetTitle(string.format("Golden Skins (%d/%d)", totalGold, totalGold))
                    UI.ProgGoldenSkins:SetDesc("✓ All Golden Skins Owned")
                else
                    UI.ProgGoldenSkins:SetTitle(string.format("Golden Skins (%d/%d)", ownedGold, totalGold))
                    if #missingGold <= 2 then
                        UI.ProgGoldenSkins:SetDesc(string.format("Missing: %s | Cost: %s Coins", table.concat(missingGold, ", "), formatNumberWithCommas(totalMissingGoldCost)))
                    else
                        UI.ProgGoldenSkins:SetDesc(string.format("Missing: %d Skins | Cost: %s Coins", #missingGold, formatNumberWithCommas(totalMissingGoldCost)))
                    end
                end
            end

            -- 4. Skill Tree
            if UI.ProgSkillTree then
                local totalSkills = 17
                local maxedSkills = 0
                local skills = (PlayerDataHandler and typeof(PlayerDataHandler.GetSkillTree) == "function") and PlayerDataHandler:GetSkillTree() or {}
                local skillMap = {}
                for _, sk in ipairs(skills) do
                    local idNum = tonumber(sk.Id)
                    if not idNum and sk.Name and SkillNameToId[sk.Name] then
                        idNum = tonumber(SkillNameToId[sk.Name])
                    end
                    if idNum then
                        skillMap[idNum] = parseSkillInfo(sk, idNum)
                    end
                end

                local activeUnmaxed = nil
                for id = 1, totalSkills do
                    local info = skillMap[id] or parseSkillInfo(nil, id)
                    if info.IsMaxed then
                        maxedSkills = maxedSkills + 1
                    elseif not activeUnmaxed then
                        activeUnmaxed = info
                    end
                end

                if maxedSkills >= totalSkills then
                    UI.ProgSkillTree:SetTitle(string.format("Skill Tree (%d/%d)", totalSkills, totalSkills))
                    UI.ProgSkillTree:SetDesc("✓ All Skills Maxed")
                else
                    UI.ProgSkillTree:SetTitle(string.format("Skill Tree (%d/%d Maxed)", maxedSkills, totalSkills))
                    if activeUnmaxed then
                        UI.ProgSkillTree:SetDesc(string.format("ID %s: %d / %d (%s)", activeUnmaxed.Id, activeUnmaxed.Level, activeUnmaxed.MaxLevel, activeUnmaxed.Name))
                    else
                        UI.ProgSkillTree:SetDesc(string.format("Missing: %d Skills", totalSkills - maxedSkills))
                    end
                end
            end
        end)
    end

    if UI.StatusLabel then
        pcall(function()
            if setthreadidentity then pcall(setthreadidentity, 8) end
            if not analysis.configFound then
                UI.StatusLabel:SetTitle("Status: Config Missing")
                UI.StatusLabel:SetDesc("No configuration for: " .. tostring(analysis.trialName))
            elseif #missingParts > 0 then
                UI.StatusLabel:SetTitle("Status: Missing Requirements")
                UI.StatusLabel:SetDesc(table.concat(missingParts, " | "))
            elseif not analysis.isSelectedInFilter then
                if isPremiumUser and analysis.useFallback and analysis.fallbackMode ~= "None" then
                    UI.StatusLabel:SetTitle("Status: Fallback Activated")
                    UI.StatusLabel:SetDesc(Globals.AutoTrials and ("Switching to fallback mode: " .. analysis.fallbackMode) or "Fallback ready.")
                else
                    UI.StatusLabel:SetTitle("Status: Trial Skipped")
                    UI.StatusLabel:SetDesc(tostring(analysis.trialName) .. " not in selected filter.")
                end
            else
                -- All requirements met and trial selected in filter!
                if game.PlaceId == LOBBY_PLACE_ID then
                    if Globals.AutoTrials and not Globals.AutoGold then
                        UI.StatusLabel:SetTitle("Status: Queuing Trial")
                        UI.StatusLabel:SetDesc("Queuing for matched trial: " .. tostring(analysis.trialName))
                    else
                        UI.StatusLabel:SetTitle("Status: Trial Eligible")
                        UI.StatusLabel:SetDesc("All requirements met for " .. tostring(analysis.trialName))
                    end
                else
                    -- In Game!
                    UI.StatusLabel:SetTitle("Status: Ready (In Match)")
                    if analysis.currentMap and analysis.currentMap ~= "Unknown" then
                        UI.StatusLabel:SetDesc(string.format("Match Active: %s | Map: %s", tostring(analysis.trialName), tostring(analysis.currentMap)))
                    else
                        UI.StatusLabel:SetDesc("Match Active: " .. tostring(analysis.trialName))
                    end
                end
            end
        end)
    end

    if UI.AutoGoldStatusLabel or UI.AutoGoldMissingLabel then
        pcall(function()
            if setthreadidentity then pcall(setthreadidentity, 8) end
            local goldAnalysis = analyzeAutoGoldRequirements()
            local selectedModeStr = string.format("%s (%s)", goldAnalysis.farmType, goldAnalysis.stratChoice)

            if UI.AutoGoldStatusLabel then
                UI.AutoGoldStatusLabel:SetTitle("Status: " .. selectedModeStr)
                if not goldAnalysis.configFound then
                    UI.AutoGoldStatusLabel:SetDesc("Config Missing")
                elseif not goldAnalysis.isEligible then
                    UI.AutoGoldStatusLabel:SetDesc("🔒 Locked (Missing Requirements)")
                elseif game.PlaceId == LOBBY_PLACE_ID then
                    if Globals.AutoGold then
                        UI.AutoGoldStatusLabel:SetDesc("Queuing for " .. tostring(goldAnalysis.targetMode) .. " (" .. goldAnalysis.farmType .. ")...")
                    else
                        UI.AutoGoldStatusLabel:SetDesc("Ready (Automation Off)")
                    end
                else
                    -- In Game!
                    UI.AutoGoldStatusLabel:SetDesc("In Match: " .. tostring(goldAnalysis.targetMode) .. " (" .. selectedModeStr .. ")")
                end
            end

            if UI.AutoGoldMissingLabel then
                UI.AutoGoldMissingLabel:SetTitle("Missing:")
                if #goldAnalysis.missingParts > 0 then
                    UI.AutoGoldMissingLabel:SetDesc(table.concat(goldAnalysis.missingParts, " | "))
                else
                    UI.AutoGoldMissingLabel:SetDesc("None (All requirements met)")
                end
            end
        end)
    end

    if UI.AutoEvoStatusLabel or UI.AutoEvoMissingLabel then
        pcall(function()
            if setthreadidentity then pcall(setthreadidentity, 8) end
            local evoAnalysis = analyzeAutoEvoRequirements()
            local displayTarget = evoAnalysis.targetEvo
            if evoAnalysis.targetEvo == "All" and evoAnalysis.activeTower then
                displayTarget = "All [" .. evoAnalysis.activeTower .. "]"
            end
            local selectedModeStr = string.format("%s (%s)", displayTarget, evoAnalysis.stratChoice)

            if UI.AutoEvoStatusLabel then
                UI.AutoEvoStatusLabel:SetTitle("Status: " .. selectedModeStr)
                if evoAnalysis.allFinished then
                    UI.AutoEvoStatusLabel:SetDesc("Finished (All Evolutions Complete)")
                elseif not evoAnalysis.configFound and not evoAnalysis.readyToBuy then
                    UI.AutoEvoStatusLabel:SetDesc("Config Missing")
                elseif not evoAnalysis.isEligible then
                    UI.AutoEvoStatusLabel:SetDesc("🔒 Locked (Missing Requirements)")
                elseif evoAnalysis.readyToBuy then
                    if Globals.AutoEvo then
                        UI.AutoEvoStatusLabel:SetDesc("Buying Evolution: " .. tostring(evoAnalysis.activeTower) .. "...")
                    else
                        UI.AutoEvoStatusLabel:SetDesc("Ready (Can Evolve " .. tostring(evoAnalysis.activeTower) .. ")")
                    end
                elseif game.PlaceId == LOBBY_PLACE_ID then
                    if Globals.AutoEvo then
                        UI.AutoEvoStatusLabel:SetDesc(string.format("Queuing: %s - %s (%s)...", tostring(evoAnalysis.activeTower), tostring(evoAnalysis.targetMode), tostring(evoAnalysis.farmType)))
                    else
                        UI.AutoEvoStatusLabel:SetDesc("Ready (Automation Off)")
                    end
                else
                    -- In Game!
                    UI.AutoEvoStatusLabel:SetDesc(string.format("In Match: %s - %s (%s)", tostring(evoAnalysis.activeTower), tostring(evoAnalysis.targetMode), tostring(evoAnalysis.farmType)))
                end
            end

            if UI.AutoEvoMissingLabel then
                UI.AutoEvoMissingLabel:SetTitle("Missing:")
                if evoAnalysis.allFinished then
                    UI.AutoEvoMissingLabel:SetDesc("None (All targets complete)")
                elseif #evoAnalysis.missingParts > 0 then
                    UI.AutoEvoMissingLabel:SetDesc(table.concat(evoAnalysis.missingParts, " | "))
                else
                    UI.AutoEvoMissingLabel:SetDesc("None (All requirements met)")
                end
            end
        end)
    end

    if game.PlaceId ~= LOBBY_PLACE_ID then
        if UI.Window and UI.Window.SetSubtitle then
            pcall(function()
                if setthreadidentity then pcall(setthreadidentity, 8) end
                UI.Window:SetSubtitle("IN-GAME : " .. tostring(analysis.trialName))
            end)
        end
        return
    end

    if Globals.MultiplayerEnabled then
        local roleStr = Globals.MultiplayerIsHost and "Host" or "P2"
        local mpMode = Globals.MultiplayerMode or "Trial Mode"
        local p2Name = tostring(Globals.MultiplayerTargetP2 or Globals.MultiplayerHostIdentifier or ""):gsub("^%s*(.-)%s*$", "%1")
        local hostName = tostring(Globals.MultiplayerTargetHost or ""):gsub("^%s*(.-)%s*$", "%1")

        if UI.Window and UI.Window.SetSubtitle then
            pcall(function()
                if setthreadidentity then pcall(setthreadidentity, 8) end
                if Globals.MultiplayerIsHost then
                    local p2Obj = (p2Name ~= "") and GetPlayerFromIdentifier(p2Name)
                    local inParty = p2Obj and LocalPartyManager and LocalPartyManager.InPartyWith[p2Obj.Name]
                    if inParty then
                        UI.Window:SetSubtitle(string.format("LOBBY : Multiplayer Host [%s] (Party Formed with %s)", mpMode, p2Obj.Name))
                    elseif p2Obj then
                        UI.Window:SetSubtitle(string.format("LOBBY : Multiplayer Host [%s] (Inviting %s...)", mpMode, p2Obj.Name))
                    else
                        UI.Window:SetSubtitle(string.format("LOBBY : Multiplayer Host [%s] (Waiting for %s)", mpMode, p2Name ~= "" and p2Name or "P2"))
                    end
                else
                    local hostObj = (hostName ~= "") and GetPlayerFromIdentifier(hostName)
                    local inParty = hostObj and LocalPartyManager and LocalPartyManager.InPartyWith[hostObj.Name]
                    if inParty then
                        UI.Window:SetSubtitle(string.format("LOBBY : Multiplayer P2 [%s] (In Party with %s)", mpMode, hostObj.Name))
                    elseif hostObj then
                        UI.Window:SetSubtitle(string.format("LOBBY : Multiplayer P2 [%s] (Accepting Invite from %s...)", mpMode, hostObj.Name))
                    else
                        UI.Window:SetSubtitle(string.format("LOBBY : Multiplayer P2 [%s] (Waiting for Host %s)", mpMode, hostName ~= "" and hostName or "Leader"))
                    end
                end
            end)
        end

        if UI.StatusLabel then
            pcall(function()
                if setthreadidentity then pcall(setthreadidentity, 8) end
                UI.StatusLabel:SetTitle(string.format("Status: Multiplayer (%s - %s)", roleStr, mpMode))
                if Globals.MultiplayerIsHost then
                    local p2Obj = (p2Name ~= "") and GetPlayerFromIdentifier(p2Name)
                    if p2Obj and LocalPartyManager and LocalPartyManager.InPartyWith[p2Obj.Name] then
                        UI.StatusLabel:SetDesc(string.format("Party formed with %s! Ready to queue %s.", p2Obj.Name, mpMode))
                    elseif p2Obj then
                        UI.StatusLabel:SetDesc(string.format("P2 '%s' in lobby. Forming party...", p2Obj.Name))
                    else
                        UI.StatusLabel:SetDesc(string.format("Waiting for P2 '%s' to join lobby / private server...", p2Name ~= "" and p2Name or "peer"))
                    end
                else
                    UI.StatusLabel:SetDesc(string.format("P2 following Host '%s'. Matchmaking is controlled by Host.", hostName ~= "" and hostName or "leader"))
                end
            end)
        end

        pcall(function()
            if typeof(updateMultiplayerTowersLabel) == "function" then
                updateMultiplayerTowersLabel()
            end
        end)
        return
    end

    if not Globals.AutoTrials then
        if Globals.AutoEvo then
            local evoAnalysis = (typeof(analyzeAutoEvoRequirements) == "function") and analyzeAutoEvoRequirements()
            if evoAnalysis then
                if evoAnalysis.readyToBuy then
                    if UI.Window and UI.Window.SetSubtitle then
                        UI.Window:SetSubtitle(string.format("LOBBY : Ready to Evolve (%s)", tostring(evoAnalysis.activeTower or "Tower")))
                    end
                elseif evoAnalysis.allFinished then
                    if UI.Window and UI.Window.SetSubtitle then
                        UI.Window:SetSubtitle("LOBBY : Auto Evo Complete (All Evolved)")
                    end
                elseif evoAnalysis.isEligible then
                    local stratChoice = evoAnalysis.stratChoice or "Win"
                    local needType = evoAnalysis.farmType or "Coins"
                    local activeTower = evoAnalysis.activeTower or "Tower"
                    local targetMode = evoAnalysis.targetMode or "Fallen"
                    if UI.Window and UI.Window.SetSubtitle then
                        UI.Window:SetSubtitle(string.format("LOBBY : Queuing %s (%s - %s)", tostring(activeTower), tostring(targetMode), tostring(needType)))
                    end
                    saveActiveMode("AutoEvo")
                    AutoGoldModule.QueueGold(stratChoice, needType)
                else
                    if UI.Window and UI.Window.SetSubtitle then
                        UI.Window:SetSubtitle("LOBBY : Auto Evo Locked (Missing Requirements)")
                    end
                end
            end
            return
        else
            pcall(function()
                if setthreadidentity then pcall(setthreadidentity, 8) end
                if UI.Window and UI.Window.SetSubtitle then
                    UI.Window:SetSubtitle("LOBBY : Automation Paused (Idle)")
                end
                if UI.StatusLabel then
                    UI.StatusLabel:SetTitle("Status: Automation Paused")
                    UI.StatusLabel:SetDesc("Enable Auto Trials, Auto Evo, or Multiplayer Mode to start automation.")
                end
            end)
            return
        end
    end

    local isFarmOnlyActive = isPremiumUser and (Globals.FarmOnly == "Farm Only")
    local isOwnedModeActive = isPremiumUser and (Globals.TrialFarmMode == "Progression Mode")

    pcall(processAutoPurchases)

    -- Lobby Subtitle and Matchmaking Trigger
    if isRequirementLocked and (not isOwnedModeActive or (not Globals.AutoGold and not Globals.AutoEvo)) then
        if UI.Window and UI.Window.SetSubtitle then UI.Window:SetSubtitle("LOBBY : 🔒 Missing Requirements") end
    elseif not isKeyUser then
        local isTrialOwned = analysis.isOwned or checkIsTrialWon(analysis.trialName)
        if isTrialOwned then
            if UI.Window and UI.Window.SetSubtitle then UI.Window:SetSubtitle("LOBBY : Keyless - Trial Owned (Waiting Next)") end
            if UI.StatusLabel then UI.StatusLabel:SetTitle("Status: Keyless Waiting"); UI.StatusLabel:SetDesc("Current trial is already owned. Waiting for the next rotation.") end
        elseif analysis.isEligible and analysis.isSelectedInFilter and not isRequirementLocked then
            if UI.Window and UI.Window.SetSubtitle then UI.Window:SetSubtitle("LOBBY : Keyless - Queuing " .. analysis.trialName) end
            if Globals.AutoTrials then saveActiveMode("AutoTrials"); triggerTrialsQueue(analysis.trialName) end
        else
            if UI.Window and UI.Window.SetSubtitle then UI.Window:SetSubtitle("LOBBY : Keyless - Criteria Unmet / Waiting") end
        end
    elseif isFarmOnlyActive then
        if analysis.isOwned then
            if UI.Window and UI.Window.SetSubtitle then UI.Window:SetSubtitle("LOBBY : Trial Owned (Waiting Next)") end
            if UI.StatusLabel then
                UI.StatusLabel:SetTitle("Status: Trial Owned (Waiting)")
                UI.StatusLabel:SetDesc("Farm Only: " .. tostring(analysis.trialName) .. " already owned. Waiting for rotation.")
            end
        elseif analysis.isEligible and analysis.isSelectedInFilter then
            if UI.Window and UI.Window.SetSubtitle then
                UI.Window:SetSubtitle(Globals.AutoTrials and ("LOBBY : Queuing Trial " .. analysis.trialName) or ("LOBBY : Ready (" .. analysis.trialName .. ")"))
            end
            if Globals.AutoTrials then
                saveActiveMode("AutoTrials")
                triggerTrialsQueue(analysis.trialName)
            end
        else
            if UI.Window and UI.Window.SetSubtitle then UI.Window:SetSubtitle("LOBBY : Farm Only (Waiting Rotation)") end
            if UI.StatusLabel then
                UI.StatusLabel:SetTitle("Status: Farm Only Waiting")
                UI.StatusLabel:SetDesc("Current trial not selected/eligible. Waiting for next rotation.")
            end
        end
    elseif isOwnedModeActive then
        pcall(processAutoPurchases)
        local action, arg1, arg2, arg3 = evaluateOwnedModeAction(analysis)

        if action == "EverythingMaxed" then
            action = "Fallback"
            arg1 = (analysis.fallbackMode and analysis.fallbackMode ~= "Smart Auto" and analysis.fallbackMode ~= "None") and analysis.fallbackMode or "Hardcore"
        end

        if action == "BeatUnownedTrial" then
            local trialName = arg1 or analysis.trialName
            if UI.Window and UI.Window.SetSubtitle then
                UI.Window:SetSubtitle(Globals.AutoTrials and ("LOBBY : Beating Unowned " .. trialName) or ("LOBBY : Ready (" .. trialName .. ")"))
            end
            if UI.StatusLabel then
                UI.StatusLabel:SetTitle("Status: Queuing Unowned Trial")
                UI.StatusLabel:SetDesc("Beating unowned trial: " .. tostring(trialName))
            end
            if Globals.AutoTrials then
                saveActiveMode("AutoTrials")
                triggerTrialsQueue(trialName)
            end
        elseif action == "FarmCoins" then
            local stratChoice = arg1 or "Molten"
            if UI.Window and UI.Window.SetSubtitle then
                UI.Window:SetSubtitle(Globals.AutoTrials and ("LOBBY : Farming Coins (" .. stratChoice .. ")") or "LOBBY : Priority (Coin Towers)")
            end
            if UI.StatusLabel then
                UI.StatusLabel:SetTitle("Status: Farming Coins")
                UI.StatusLabel:SetDesc("Progression Mode: Grinding coins for missing coin towers.")
            end
            if Globals.AutoTrials then
                saveActiveMode("AutoGold")
                AutoGoldModule.QueueGold(stratChoice, "Coins")
            end
        elseif action == "FarmGems" then
            if UI.Window and UI.Window.SetSubtitle then
                UI.Window:SetSubtitle(Globals.AutoTrials and "LOBBY : Farming Gems (Hardcore Lose)" or "LOBBY : Priority (Hardcore Towers)")
            end
            if UI.StatusLabel then
                UI.StatusLabel:SetTitle("Status: Farming Gems")
                UI.StatusLabel:SetDesc("Progression Mode: Grinding gems (Hardcore Lose) for hardcore towers.")
            end
            if Globals.AutoTrials then
                saveActiveMode("AutoGold")
                AutoGoldModule.QueueGold("Lose", "Gems")
            end
        elseif action == "EvoReadyInLobby" then
            local activeTower = arg1 or "Tower"
            if UI.Window and UI.Window.SetSubtitle then
                UI.Window:SetSubtitle("LOBBY : Ready to Evolve (" .. activeTower .. ")")
            end
            if UI.StatusLabel then
                UI.StatusLabel:SetTitle("Status: Evolving Tower")
                UI.StatusLabel:SetDesc("Progression Mode: Level 20 reached! Evolving " .. activeTower .. " in lobby.")
            end
        elseif action == "FarmEvo" then
            local stratChoice = arg1 or "Lose"
            local needType = arg2 or "Coins"
            local activeTower = arg3 or "Scout"
            if UI.Window and UI.Window.SetSubtitle then
                UI.Window:SetSubtitle(Globals.AutoTrials and string.format("LOBBY : Leveling Evo (%s - %s)", activeTower, needType) or string.format("LOBBY : Evo Ready (%s)", activeTower))
            end
            if UI.StatusLabel then
                UI.StatusLabel:SetTitle("Status: Leveling Evo Tower")
                UI.StatusLabel:SetDesc(string.format("Progression Mode: Grinding %s / EXP for %s.", needType, activeTower))
            end
            if Globals.AutoTrials then
                saveActiveMode("AutoEvo")
                AutoGoldModule.QueueGold(stratChoice, needType)
            end
        elseif action == "FarmGoldSkins" then
            local stratChoice = arg1 or "Molten"
            if UI.Window and UI.Window.SetSubtitle then
                UI.Window:SetSubtitle(Globals.AutoTrials and ("LOBBY : Farming Gold Skins (" .. stratChoice .. ")") or "LOBBY : Priority (Golden Skins)")
            end
            if UI.StatusLabel then
                UI.StatusLabel:SetTitle("Status: Farming Coins")
                UI.StatusLabel:SetDesc("Progression Mode: Grinding 50,000 coins for Golden Crates.")
            end
            if Globals.AutoTrials then
                saveActiveMode("AutoGold")
                AutoGoldModule.QueueGold(stratChoice, "Coins")
            end
        elseif action == "FarmSkillTree" then
            local stratChoice = arg1 or "Molten"
            if UI.Window and UI.Window.SetSubtitle then
                UI.Window:SetSubtitle(Globals.AutoTrials and ("LOBBY : Farming Skill Tree (" .. stratChoice .. ")") or "LOBBY : Priority (Skill Tree)")
            end
            if UI.StatusLabel then
                UI.StatusLabel:SetTitle("Status: Farming Currency")
                UI.StatusLabel:SetDesc("Progression Mode: Grinding currency for Skill Tree upgrades.")
            end
            if Globals.AutoTrials then
                saveActiveMode("AutoGold")
                AutoGoldModule.QueueGold(stratChoice, "Coins")
            end
        elseif action == "Fallback" then
            local fbMode = arg1 or "Molten"
            if UI.Window and UI.Window.SetSubtitle then
                UI.Window:SetSubtitle(Globals.AutoTrials and ("LOBBY : Fallback -> " .. fbMode) or "LOBBY : Fallback Ready")
            end
            if UI.StatusLabel then
                UI.StatusLabel:SetTitle("Status: Running Fallback")
                UI.StatusLabel:SetDesc("Progression Mode: Trial already owned -> Running fallback: " .. fbMode)
            end
            if Globals.AutoTrials then
                saveActiveMode("AutoTrials")
                triggerFallbackQueue(fbMode)
            end
        else
            local reason = analysis.isOwned and "Trial Owned (Waiting)" or "Criteria Unmet"
            if UI.Window and UI.Window.SetSubtitle then UI.Window:SetSubtitle("LOBBY : " .. reason) end
            if UI.StatusLabel then
                UI.StatusLabel:SetTitle("Status: " .. reason)
                UI.StatusLabel:SetDesc(analysis.isOwned and "Current trial already owned. Waiting for rotation." or "Missing requirements or filter unmet.")
            end
        end
    elseif analysis.isEligible and analysis.isSelectedInFilter then
        if UI.Window and UI.Window.SetSubtitle then
            UI.Window:SetSubtitle(Globals.AutoTrials and ("LOBBY : Queuing Trial " .. analysis.trialName) or ("LOBBY : Ready (" .. analysis.trialName .. ")"))
        end
        if Globals.AutoTrials and (not Globals.AutoGold or not isPremiumUser) then
            saveActiveMode("AutoTrials")
            triggerTrialsQueue(analysis.trialName)
        end
    elseif isPremiumUser and analysis.useFallback and analysis.fallbackMode ~= "None" then
        if UI.Window and UI.Window.SetSubtitle then
            UI.Window:SetSubtitle(Globals.AutoTrials and ("LOBBY : Fallback -> " .. analysis.fallbackMode) or ("LOBBY : Fallback Ready"))
        end
        if Globals.AutoTrials and not Globals.AutoGold then
            saveActiveMode("AutoTrials")
            triggerFallbackQueue(analysis.fallbackMode)
        end
    else
        if UI.Window and UI.Window.SetSubtitle then UI.Window:SetSubtitle("LOBBY : Criteria Unmet / Waiting") end
    end
end

--==============================================================================
-- Lobby Fast Check Data & Fast Queue Routine
--==============================================================================
fastQueueLobby = function()
    if setthreadidentity then pcall(setthreadidentity, 8) end
    if game.PlaceId ~= LOBBY_PLACE_ID then return end
    if not Globals.AutoTrials and not Globals.AutoEvo and not Globals.MultiplayerEnabled then return end

    ensurePlayerDataReady(20)
    if not PlayerDataHandler then
        PlayerDataHandler = loadPlayerDataHandler()
    end

    if PlayerDataHandler then
        refreshDisplay()
    end

    if Globals.MultiplayerEnabled then
        -- 1. Equip towers early in lobby for both Host and P2
        if typeof(ensureMultiplayerLobbyLoadout) == "function" then
            ensureMultiplayerLobbyLoadout()
        end

        if Globals.MultiplayerIsP2 then
            -- P2 equips their required towers in lobby so Host can verify them properly
            local mpMode = Globals.MultiplayerMode or "Trial Mode"
                local mpConfig = Requirements and Requirements.MultiplayerConfig or (getgenv and getgenv().MultiplayerConfig) or {}
                local mpTrialMode = mpConfig.TrialMode or {}
                local trialName = nil
                if Globals.MultiplayerSelectedTrial and Globals.MultiplayerSelectedTrial ~= "" and Globals.MultiplayerSelectedTrial ~= "Current Rotation" and ((RevampAutoTrials and RevampAutoTrials[Globals.MultiplayerSelectedTrial]) or mpTrialMode[Globals.MultiplayerSelectedTrial] or mpTrialMode[Globals.MultiplayerSelectedTrial:gsub(" Enemies", "")]) then
                    trialName = Globals.MultiplayerSelectedTrial
                else
                    local analysis = (typeof(analyzeCurrentTrial) == "function") and analyzeCurrentTrial()
                    trialName = analysis and analysis.trialName or "Speedy Enemies"
                end
                local trialEntry = mpTrialMode[trialName] or mpTrialMode[trialName:gsub(" Enemies", "")] or mpTrialMode[trialName .. " Enemies"] or mpTrialMode["Speedy Enemies"]
                local p2ReqT = trialEntry and trialEntry.Towers and (trialEntry.Towers["P2"] or trialEntry.Towers.P2)
                if p2ReqT and #p2ReqT > 0 and TDS and typeof(TDS.Loadout) == "function" then
                    pcall(function()
                        TDS:Loadout(unpack(p2ReqT))
                    end)
                end
            -- P2 strictly follows Host matchmaking; never queues alone
            return
        end

        if Globals.MultiplayerIsHost then
            local p2Target = tostring(Globals.MultiplayerTargetP2 or Globals.MultiplayerHostIdentifier or ""):gsub("^%s*(.-)%s*$", "%1")
            local p2Obj = (p2Target ~= "") and GetPlayerFromIdentifier(p2Target) or nil
            local p2InParty = false

            if p2Obj then
                p2InParty = (LocalPartyManager and LocalPartyManager.InPartyWith[p2Obj.Name] == true)
                if not p2InParty and (os.time() - (LocalPartyManager.LastInviteAttempt or 0) >= 2) then
                    LocalPartyManager.LastInviteAttempt = os.time()
                    LocalPartyManager:CreateAndInvite(p2Target)
                end
            end

            -- If P2 is specified, wait until P2 is in the server AND in the party before checking eligibility or queueing
            if p2Target ~= "" then
                if not p2Obj then
                    if UI and UI.StatusLabel then
                        UI.StatusLabel:SetDesc(string.format("Waiting for P2 '%s' to join lobby...", p2Target))
                    end
                    return
                end
                if not p2InParty then
                    if UI and UI.StatusLabel then
                        UI.StatusLabel:SetDesc(string.format("Inviting P2 '%s'... Waiting for invite acceptance before queueing.", p2Obj.Name))
                    end
                    return
                end
            end

            local mpMode = Globals.MultiplayerMode or "Trial Mode"
            if mpMode == "Trial Mode" then
                local mpConfig = Requirements and Requirements.MultiplayerConfig or (getgenv and getgenv().MultiplayerConfig) or {}
                local mpTrialMode = mpConfig.TrialMode or {}
                local trialName = nil
                if Globals.MultiplayerSelectedTrial and Globals.MultiplayerSelectedTrial ~= "" and Globals.MultiplayerSelectedTrial ~= "Current Rotation" and ((RevampAutoTrials and RevampAutoTrials[Globals.MultiplayerSelectedTrial]) or mpTrialMode[Globals.MultiplayerSelectedTrial] or mpTrialMode[Globals.MultiplayerSelectedTrial:gsub(" Enemies", "")]) then
                    trialName = Globals.MultiplayerSelectedTrial
                else
                    local analysis = (typeof(analyzeCurrentTrial) == "function") and analyzeCurrentTrial()
                    trialName = analysis and analysis.trialName or "Speedy Enemies"
                end

                if trialName and trialName ~= "" then
                    local trialEntry = mpTrialMode[trialName] or mpTrialMode[trialName:gsub(" Enemies", "")] or mpTrialMode[trialName .. " Enemies"] or mpTrialMode["Speedy Enemies"]
                    local canQueue = false

                    if trialEntry then
                        local hReqT = trialEntry.Towers and (trialEntry.Towers["Host"] or trialEntry.Towers.Host)
                        local hReqL = trialEntry.Level and (trialEntry.Level.Host or trialEntry.Level["Host"])
                        local p2ReqT = trialEntry.Towers and (trialEntry.Towers["P2"] or trialEntry.Towers.P2)
                        local p2ReqL = trialEntry.Level and (trialEntry.Level.P2 or trialEntry.Level["P2"])

                        -- Explicitly equip Host loadout before checking eligibility
                        if hReqT and #hReqT > 0 and TDS and typeof(TDS.Loadout) == "function" then
                            pcall(function()
                                TDS:Loadout(unpack(hReqT))
                            end)
                        end

                        local hOk, hDesc, hMissing = checkTowerEligibilityForPlayer(LocalPlayer, hReqT, hReqL, "Host")
                        local p2Ok, p2Desc, p2Missing = checkTowerEligibilityForPlayer(p2Target, p2ReqT, p2ReqL, "P2")

                        if not hOk or not p2Ok then
                            canQueue = false
                            local missingMsg = string.format("❌ Requirements not met: Host (%s) | P2 (%s)", hDesc, p2Desc)
                            if UI and UI.StatusLabel then
                                UI.StatusLabel:SetDesc(missingMsg)
                            end
                            warn("[Multiplayer Lobby] " .. missingMsg)
                        else
                            canQueue = true
                        end
                    else
                        local trialAnalysis = (typeof(analyzeCurrentTrial) == "function") and analyzeCurrentTrial()
                        canQueue = trialAnalysis and trialAnalysis.isEligible and not isRequirementLocked
                    end

                    if canQueue then
                        local hReqT = trialEntry and trialEntry.Towers and (trialEntry.Towers["Host"] or trialEntry.Towers.Host)
                        -- Call TDS:Loadout immediately before queueing so loadout is guaranteed
                        if hReqT and #hReqT > 0 and TDS and typeof(TDS.Loadout) == "function" then
                            pcall(function()
                                TDS:Loadout(unpack(hReqT))
                            end)
                        end

                        if UI and UI.StatusLabel then
                            UI.StatusLabel:SetDesc(string.format("✅ Both players eligible & in party! Starting queue for %s...", trialName))
                        end
                        lastQueueAttemptTime = 0
                        saveActiveMode("Multiplayer")
                        triggerTrialsQueue(trialName)
                    end
                end
            elseif mpMode == "Farm Mode" then
                local farmStrat = Globals.MultiplayerFarmStrategy or "Molten"
                if farmStrat == "Smart Auto" and typeof(resolveSmartFallback) == "function" then
                    farmStrat = resolveSmartFallback()
                end
                local fallbackModeConfig = FallbackConfigs and FallbackConfigs[farmStrat]
                if fallbackModeConfig and fallbackModeConfig.Towers and #fallbackModeConfig.Towers > 0 and TDS and typeof(TDS.Loadout) == "function" then
                    pcall(function()
                        TDS:Loadout(unpack(fallbackModeConfig.Towers))
                    end)
                end
                local farmType = (farmStrat == "Hardcore") and "Gems" or "Coins"
                lastQueueAttemptTime = 0
                saveActiveMode("Multiplayer")
                AutoGoldModule.QueueGold(farmStrat, farmType)
            end
        end
        return
    end

    if not Globals.AutoTrials then
        if Globals.AutoEvo then
            local evoAnalysis = (typeof(analyzeAutoEvoRequirements) == "function") and analyzeAutoEvoRequirements()
            if evoAnalysis and evoAnalysis.isEligible and not evoAnalysis.readyToBuy and not evoAnalysis.allFinished then
                local stratChoice = evoAnalysis.stratChoice or "Win"
                local needType = evoAnalysis.farmType or "Coins"
                lastQueueAttemptTime = 0
                saveActiveMode("AutoEvo")
                AutoGoldModule.QueueGold(stratChoice, needType)
            end
        end
        return
    end

    local isFarmOnlyActive = isPremiumUser and (Globals.FarmOnly == "Farm Only")
    local isOwnedModeActive = isPremiumUser and (Globals.TrialFarmMode == "Progression Mode")

    local analysis = analyzeCurrentTrial()
    local isTrialWon = analysis.isOwned or checkIsTrialWon(analysis.trialName) or false

    local isKeylessMode = not isKeyUser
    if isKeylessMode then
        -- Single-Player Keyless Guard:
        if analysis.isSelectedInFilter and not isTrialWon and analysis.isEligible and not isRequirementLocked then
            lastQueueAttemptTime = 0
            saveActiveMode("AutoTrials")
            triggerTrialsQueue(analysis.trialName)
        end
    elseif isFarmOnlyActive then
        -- Farm Only: Fallbacks are ignored. Only farm trials in filter and ONLY ONCE.
        -- When already owned, just do nothing and wait for next trial.
        if analysis.isSelectedInFilter and not isTrialWon and analysis.isEligible and not isRequirementLocked then
            lastQueueAttemptTime = 0
            saveActiveMode("AutoTrials")
            triggerTrialsQueue(analysis.trialName)
        end
    elseif isOwnedModeActive then
        pcall(processAutoPurchases)
        local action, arg1, arg2, arg3 = evaluateOwnedModeAction(analysis)

        if action == "EverythingMaxed" then
            action = "Fallback"
            arg1 = (analysis.fallbackMode and analysis.fallbackMode ~= "Smart Auto" and analysis.fallbackMode ~= "None") and analysis.fallbackMode or "Hardcore"
        end

        if action == "BeatUnownedTrial" then
            local trialName = arg1 or analysis.trialName
            lastQueueAttemptTime = 0
            saveActiveMode("AutoTrials")
            triggerTrialsQueue(trialName)
        elseif action == "FarmCoins" or action == "FarmGoldSkins" or action == "FarmSkillTree" then
            local stratChoice = arg1 or "Molten"
            lastQueueAttemptTime = 0
            saveActiveMode("AutoGold")
            AutoGoldModule.QueueGold(stratChoice, "Coins")
        elseif action == "FarmGems" then
            lastQueueAttemptTime = 0
            saveActiveMode("AutoGold")
            AutoGoldModule.QueueGold("Lose", "Gems")
        elseif action == "FarmEvo" then
            local stratChoice = arg1 or "Lose"
            local needType = arg2 or "Coins"
            lastQueueAttemptTime = 0
            saveActiveMode("AutoEvo")
            AutoGoldModule.QueueGold(stratChoice, needType)
        elseif action == "Fallback" then
            local fbMode = arg1 or "Molten"
            lastQueueAttemptTime = 0
            saveActiveMode("AutoTrials")
            triggerFallbackQueue(fbMode)
        end
    else
        -- Standard Farm Mode:
        if not isRequirementLocked then
            if analysis.isEligible and analysis.isSelectedInFilter then
                lastQueueAttemptTime = 0
                saveActiveMode("AutoTrials")
                triggerTrialsQueue(analysis.trialName)
            elseif isPremiumUser and analysis.useFallback and analysis.fallbackMode ~= "None" then
                lastQueueAttemptTime = 0
                saveActiveMode("AutoTrials")
                triggerFallbackQueue(analysis.fallbackMode)
            end
        end
    end
end

--==============================================================================
-- In-Game Ready Guard
--==============================================================================
local function runInGameGuard()
    if game.PlaceId == LOBBY_PLACE_ID then return end

    task.spawn(function()
        pcall(function()
            if Globals.AutoTrials and not Globals.AutoGold and isPremiumUser then
                ensureDynamicHardcoreFallback()
                local stateReplicators = ReplicatedStorage:WaitForChild("StateReplicators", 15)
                local gsr = stateReplicators and stateReplicators:WaitForChild("GameStateReplicator", 15)
                if gsr then
                    local liveDifficulty = ""
                    local liveGameMode = ""
                    local savedTrial = ""
                    if typeof(loadTrialState) == "function" then
                        pcall(function() savedTrial = tostring(loadTrialState() or "") end)
                    end

                    local t0 = tick()
                    while tick() - t0 < 10 do
                        liveDifficulty = tostring(gsr:GetAttribute("Difficulty") or "")
                        liveGameMode = tostring(gsr:GetAttribute("GameMode") or gsr:GetAttribute("Mode") or "")
                        if liveDifficulty ~= "" or liveGameMode ~= "" or savedTrial ~= "" then
                            break
                        end
                        task.wait(0.5)
                    end

                    for modeName, modeConfig in pairs(FallbackConfigs) do
                        local match = (liveDifficulty ~= "" and normalizeString(modeName) == normalizeString(liveDifficulty))
                            or (savedTrial ~= "" and normalizeString(modeName) == normalizeString(savedTrial))
                            or (normalizeString(modeName) == "hardcore" and (normalizeString(liveGameMode) == "hardcore" or normalizeString(savedTrial) == "hardcore"))
                        if match then
                            local mods = modeConfig.Modifiers or modeConfig.Modifers
                            if type(mods) == "table" and #mods == 1 and type(mods[1]) == "table" then
                                mods = mods[1]
                            end
                            local votedMap = AutoGoldModule.GameInfo(modeName, mods or {})
                            if not votedMap then return end
                            AutoGoldModule.LobbyReadyUp()
                            break
                        end
                    end
                end
            end
        end)
    end)

    task.spawn(function()
        local startTime = os.time()
        local readyPromptSeen = false
        while task.wait(1) do
            if not isRunning then break end
            if not (UI.ReadyGuard and UI.ReadyGuard.SetTitle) then break end

            if not Globals.AutoGold and not Globals.AutoTrials and not Globals.AutoEvo and not Globals.MultiplayerEnabled then
                UI.ReadyGuard:SetTitle("Ready Guard: Paused")
                UI.ReadyGuard:SetDesc("Automation toggled off.")
                startTime = os.time()
                continue
            end

            local isMultiTrial = (Globals.MultiplayerEnabled and Globals.MultiplayerMode == "Trial Mode") or (currentMatchMode == "Multiplayer" and Globals.MultiplayerMode ~= "Farm Mode")
            local shouldRunTrialGuard = (currentMatchMode == "AutoTrials" or isMultiTrial or (Globals.AutoTrials and not Globals.AutoGold and not Globals.AutoEvo))
            if not Globals.MultiplayerEnabled and currentMatchMode ~= "Multiplayer" and Globals.TrialFarmMode == "Progression Mode" and (currentMatchMode == "AutoGold" or currentMatchMode == "AutoEvo" or Globals.AutoEvo or Globals.AutoGold) then
                shouldRunTrialGuard = false
            end

            if shouldRunTrialGuard and not matchStratExecuted and not isStrategyExecuting then
                task.spawn(runMatchStrategyIfSaved)
            end

            local readyDone = isReadyPressedOrGameStarted()
            if readyDone then
                UI.ReadyGuard:SetTitle("Ready Guard: Confirmed YES")
                UI.ReadyGuard:SetDesc("Match in progress")
                if UI.ReadyGuardBar then
                    UI.ReadyGuardBar:SetProgress(1.0, "Match in progress (Active)")
                end
                if UI.Window and UI.Window.SetSubtitle then
                    UI.Window:SetSubtitle("IN GAME : Running Match")
                end
                startTime = os.time()
                readyPromptSeen = false
                continue
            end

            if isReadyPromptVisible() then
                if not readyPromptSeen then
                    readyPromptSeen = true
                    startTime = os.time()
                end
                
                -- Wait for map voting / intermission handling to conclude before readying up
                if not isMapIntermissionHandling and (intermissionMapHandled or (not Globals.AutoGold and not Globals.AutoTrials and not Globals.AutoEvo and not Globals.MultiplayerEnabled)) then
                    if not (Globals.AutoEvo and not Globals.AutoGold and not Globals.AutoTrials) then
                        AutoGoldModule.LobbyReadyUp()
                    end
                end
            end

            local elapsed = os.time() - startTime
            -- Give 45 seconds timeout so the game can natively force-start the match without us teleporting
            local timeLeft = math.max(0, 45 - elapsed)

            if timeLeft > 0 then
                UI.ReadyGuard:SetTitle(string.format("Ready Guard: Waiting (%ds)", timeLeft))
                UI.ReadyGuard:SetDesc("Ready button not pressed. Counting down...")
                if UI.ReadyGuardBar then
                    UI.ReadyGuardBar:SetProgress(timeLeft / 45, string.format("%ds remaining", timeLeft))
                end
            else
                UI.ReadyGuard:SetTitle("Ready Guard: Teleporting")
                UI.ReadyGuard:SetDesc("Timeout! Returning to lobby...")
                if UI.ReadyGuardBar then
                    UI.ReadyGuardBar:SetProgress(0, "Timeout - Teleporting")
                end
                logActivity("Ready Guard timeout! Returning to lobby.", "warn")
                SmartTeleportToLobby()
                break
            end
        end
    end)
end

--==============================================================================
-- Auto Gold In-Game Execution Handler
--==============================================================================
handleAutoGoldExecution = function()
    if game.PlaceId == LOBBY_PLACE_ID then return end
    if not isPremiumUser or not Globals.AutoGold or currentMatchMode ~= "AutoGold" then return end

    if activeStratThread and coroutine.status(activeStratThread) ~= "dead" then
        task.cancel(activeStratThread)
        activeStratThread = nil
    end

    local isOwnedActive = (Globals.TrialFarmMode == "Progression Mode" and Globals.AutoTrials)
    if not Globals.AutoGold and not isOwnedActive and currentMatchMode ~= "AutoGold" then return end

    local goldAnalysis = analyzeAutoGoldRequirements()
    if not goldAnalysis.isEligible then
        Globals.AutoGold = false
        SetSetting("AutoGold", false)
        if UI.AutoGoldToggle then UI.AutoGoldToggle:SetValue(false) end
        if game.PlaceId == LOBBY_PLACE_ID then
            SmartTeleportToLobby()
        else
            Globals.IsConfigDirty = true
            if UI and UI.Window and typeof(UI.Window.Notify) == "function" then
                RunAsExecutor(function()
                    UI.Window:Notify({
                        Title = "REQUIREMENTS LOCKED",
                        Desc = "Missing requirements for current farm type. Match will conclude before returning to lobby.",
                        Duration = 6,
                        Type = "warning"
                    })
                end)()
            end
        end
        return
    end

    local config = getCurrentCrateConfig()
    local activeMap = config and config.Maps and config.Maps[1] or "Lay By"

    if config and config.Maps and #config.Maps > 0 then
        local mods = config.Modifiers or {}
        local votedMap = AutoGoldModule.GameInfo(config.Maps[1], mods)
        if type(votedMap) == "string" then
            activeMap = votedMap
        else
            return
        end
    end

    local stateReplicators = ReplicatedStorage:WaitForChild("StateReplicators", 10)
    local gameStateReplicator = stateReplicators and stateReplicators:FindFirstChild("GameStateReplicator")

    if gameStateReplicator then
        repeat
            task.wait(1)
            if not Globals.AutoGold and not isOwnedActive and currentMatchMode ~= "AutoGold" then return end
        until (gameStateReplicator:GetAttribute("GameStarted") == true)
            or ((gameStateReplicator:GetAttribute("Wave") or 0) > 0)
            or PlayerGui:FindFirstChild("ReactUniversalHotbar")
    else
        task.wait(5)
    end

    if not Globals.AutoGold and not isOwnedActive and currentMatchMode ~= "AutoGold" then return end

    AutoGoldModule.LobbyReadyUp()

    activeStratThread = task.spawn(function()
        executeActiveStrategy(activeMap)
    end)

    if not autoGoldWatcherRunning then
        autoGoldWatcherRunning = true
        task.spawn(function()
            while true do
                task.wait(1)
                if not isRunning then break end
                if game.PlaceId == LOBBY_PLACE_ID then break end

                if not Globals.AutoGold and not isOwnedActive and currentMatchMode ~= "AutoGold" then
                    if activeStratThread and coroutine.status(activeStratThread) ~= "dead" then
                        task.cancel(activeStratThread)
                        activeStratThread = nil
                    end
                end

                local currentStatus = GetMatchStatus()
                if (currentStatus == "LOSS" or currentStatus == "WIN") and not isHandlingEndMatch then
                    isHandlingEndMatch = true

                    if activeStratThread and coroutine.status(activeStratThread) ~= "dead" then
                        pcall(task.cancel, activeStratThread)
                        activeStratThread = nil
                    end

                    local shouldLeave = handleAutoGoldMatchEnd(currentStatus)
                    if shouldLeave then
                        autoGoldWatcherRunning = false
                        return
                    end

                    -- Auto Restart handling for Lose strat thread:
                    task.spawn(function()
                        local startVoteTime = tick()
                        while isRunning and (tick() - startVoteTime < 30) do
                            if GetMatchStatus() == nil then break end
                            triggerRematchVote()
                            task.wait(0.5)
                        end
                    end)

                    local waitStart = tick()
                    local restartSuccess = false
                    while isRunning and (tick() - waitStart < 35) do
                        if not Globals.AutoGold and not isOwnedActive and currentMatchMode ~= "AutoGold" then break end
                        if GetMatchStatus() == nil then
                            restartSuccess = true
                            break
                        end
                        triggerRematchVote()
                        task.wait(0.5)
                    end

                    if not restartSuccess then
                        warn("[ServiceHub] Auto-Restart timed out waiting for rewards screen to close. Returning to lobby.")
                        SmartTeleportToLobby()
                        autoGoldWatcherRunning = false
                        return
                    end

                    local stateReps = ReplicatedStorage:WaitForChild("StateReplicators", 5)
                    local newGameStateReplicator = stateReps and stateReps:FindFirstChild("GameStateReplicator")

                    if newGameStateReplicator then
                        local readyStart = tick()
                        while (Globals.AutoGold or isOwnedActive or currentMatchMode == "AutoGold") do
                            if not isRunning then break end
                            local wave = newGameStateReplicator:GetAttribute("Wave") or 0
                            local uibar = PlayerGui:FindFirstChild("ReactUniversalHotbar") ~= nil
                            if uibar or wave > 0 then 
                                task.wait(2)
                                break 
                            end
                            if tick() - readyStart > 25 then break end
                            task.wait(0.5)
                        end
                    else
                        task.wait(2)
                    end

                    snapshotMatchConfig()
                    isLateExecution = false
                    initialExecutionWave = 0
                    Globals.IsConfigDirty = false
                    isHandlingEndMatch = false
                    matchStratExecuted = false
                    isStrategyExecuting = false

                    if (Globals.AutoGold or isOwnedActive or currentMatchMode == "AutoGold") then
                        loadoutApplied = false
                        warn(string.format("[ServiceHub AutoGold] Match restarted -> re-executing strategy thread for '%s'...", tostring(activeMap)))
                        logActivity(string.format("[AutoGold] Rematch successful! Re-executing strategy: %s", tostring(activeMap)), "success")
                        activeStratThread = task.spawn(function()
                            executeActiveStrategy(activeMap)
                        end)
                    else
                        SmartTeleportToLobby()
                        break
                    end
                end
            end
            autoGoldWatcherRunning = false
        end)
    end
end

--==============================================================================
-- Auto Evo Standalone Execution & Watcher Lifecycle
--==============================================================================
local activeAutoEvoMap = "Lay By"

local function executeAutoEvoStrategy(mapName: string)
    if isStrategyExecuting or matchStratExecuted then
        warn(string.format("[AutoEvo Strategy] Strategy already active/executed for '%s', skipping duplicate.", tostring(mapName)))
        return
    end
    isStrategyExecuting = true
    matchStratExecuted = true

    if not TDS or not getgenv().TDS then
        TDS = loadEmbeddedTDSAPI()
        if TDS then
            Globals.TDS = TDS
            pcall(function() getgenv().TDS = TDS end)
            pcall(function() _G.TDS = TDS end)
        end
    end

    local activeTower = Globals.CurrentEvoActiveTower
    if not activeTower and typeof(analyzeAutoEvoRequirements) == "function" then
        local ok, evoAnalysis = pcall(analyzeAutoEvoRequirements)
        if ok and evoAnalysis and evoAnalysis.activeTower then
            activeTower = evoAnalysis.activeTower
            Globals.CurrentEvoActiveTower = activeTower
            if evoAnalysis.farmType then
                Globals.CurrentEvoFarmType = evoAnalysis.farmType
            end
        end
    end

    local farmType = Globals.CurrentEvoFarmType or "Coins"
    local stratChoice = Globals.EvoStrat or "Lose"
    if farmType == "Gems" and stratChoice == "Win" then stratChoice = "Lose" end

    local category = AutoEvoConfigs and AutoEvoConfigs[farmType]
    local config = category and (category[stratChoice] or category["Lose"] or category["Win"])
    if not config and farmType == "Gems" then
        config = FallbackConfigs and FallbackConfigs["Hardcore"] or (CrateConfigs and CrateConfigs.Gems and CrateConfigs.Gems.Lose)
    end

    local scriptUrl = nil
    local resolvedTowers = nil

    if config and config.Scripts then
        if activeTower and config.Scripts[activeTower] then
            local towerScripts = config.Scripts[activeTower]
            if type(towerScripts) == "string" then
                scriptUrl = towerScripts
            elseif type(towerScripts) == "table" then
                scriptUrl = towerScripts[mapName] or next(towerScripts)
            end
        else
            scriptUrl = config.Scripts[mapName] or next(config.Scripts)
        end
    end

    if config and config.Towers then
        if activeTower and config.Towers[activeTower] then
            resolvedTowers = config.Towers[activeTower]
        elseif #config.Towers > 0 then
            resolvedTowers = config.Towers
        end
    end

    if not scriptUrl then
        if farmType == "Gems" or stratChoice == "Lose" then
            scriptUrl = "https://raw.githubusercontent.com/Atxvy/Main/refs/heads/main/Currency/Gems/Lose/WretchedFront.lua"
            resolvedTowers = resolvedTowers or {"Farm", "Boomerang", "Crook Boss"}
        else
            scriptUrl = "https://raw.githubusercontent.com/Atxvy/Main/refs/heads/main/Trials/Fallbacks/FallenLayby.lua"
            resolvedTowers = resolvedTowers or {"Gatling Gun", "Trapper", "Medic", "Mercenary Base", "Hacker"}
        end
    end

    if type(scriptUrl) == "table" then
        scriptUrl = scriptUrl[mapName] or next(scriptUrl)
    end

    warn(string.format("[AutoEvo Execution] ActiveTower: %s | Farm: %s (%s) | Map: %s | Script: %s", tostring(activeTower), tostring(farmType), tostring(stratChoice), tostring(mapName), tostring(scriptUrl)))
    logActivity(string.format("[AutoEvo] Strategy: %s (%s - %s)", tostring(activeTower), tostring(farmType), tostring(stratChoice)), "info")

    if not loadoutApplied and resolvedTowers and #resolvedTowers > 0 and TDS and typeof(TDS.Loadout) == "function" then
        pcall(function()
            TDS:Loadout(unpack(resolvedTowers))
            loadoutApplied = true
        end)
    end

    if scriptUrl and scriptUrl ~= "" then
        pcall(function()
            local fn = compiledMacroCache[scriptUrl]
            if not fn then
                local chunk = fetchStrategyScript(scriptUrl)
                if chunk then
                    local loadedFn, compileErr = loadstring(chunk)
                    if loadedFn then
                        fn = loadedFn
                        compiledMacroCache[scriptUrl] = fn
                    else
                        warn(string.format("[AutoEvo] Script compile error: %s", tostring(compileErr)))
                    end
                end
            end
            if fn then
                if TDS and typeof(TDS.RemoveIndex) == "function" then
                    pcall(function() TDS:RemoveIndex() end)
                end
                fn()
            end
        end)
    end
end

local function startAutoEvoWatcher(activeMap: string)
    if autoEvoWatcherRunning then return end
    autoEvoWatcherRunning = true

    task.spawn(function()
        while isRunning and (Globals.AutoEvo or currentMatchMode == "AutoEvo") do
            task.wait(1)
            if game.PlaceId == LOBBY_PLACE_ID then break end

            local currentStatus = GetMatchStatus()
            if (currentStatus == "LOSS" or currentStatus == "WIN") and not isHandlingEndMatch then
                isHandlingEndMatch = true

                if activeStratThread and coroutine.status(activeStratThread) ~= "dead" then
                    pcall(task.cancel, activeStratThread)
                    activeStratThread = nil
                end

                local shouldLeave = handleAutoEvoMatchEnd(currentStatus)
                if shouldLeave then
                    autoEvoWatcherRunning = false
                    return
                end

                -- Continuous rematch vote for Lose strat runs:
                task.spawn(function()
                    local startVoteTime = tick()
                    while isRunning and (tick() - startVoteTime < 30) do
                        if GetMatchStatus() == nil then break end
                        triggerRematchVote()
                        task.wait(0.5)
                    end
                end)

                local waitStart = tick()
                local restartSuccess = false
                while isRunning and (tick() - waitStart < 35) do
                    if not Globals.AutoEvo and currentMatchMode ~= "AutoEvo" then break end
                    if GetMatchStatus() == nil then
                        restartSuccess = true
                        break
                    end
                    triggerRematchVote()
                    task.wait(0.5)
                end

                if not restartSuccess then
                    warn("[ServiceHub AutoEvo] Rematch transition timed out; retrying rematch vote in-place without SmartLobby.")
                    triggerRematchVote()
                    isHandlingEndMatch = false
                    task.wait(2)
                    continue
                end

                local stateReps = ReplicatedStorage:WaitForChild("StateReplicators", 5)
                local newGameStateReplicator = stateReps and stateReps:FindFirstChild("GameStateReplicator")
                if newGameStateReplicator then
                    local readyStart = tick()
                    while (Globals.AutoEvo or currentMatchMode == "AutoEvo") do
                        if not isRunning then break end
                        local wave = newGameStateReplicator:GetAttribute("Wave") or 0
                        local uibar = PlayerGui:FindFirstChild("ReactUniversalHotbar") ~= nil
                        if uibar or wave > 0 then
                            task.wait(2)
                            break
                        end
                        if tick() - readyStart > 25 then break end
                        task.wait(0.5)
                    end
                else
                    task.wait(2)
                end

                snapshotMatchConfig()
                isLateExecution = false
                initialExecutionWave = 0
                Globals.IsConfigDirty = false
                isHandlingEndMatch = false
                matchStratExecuted = false
                isStrategyExecuting = false

                if Globals.AutoEvo or currentMatchMode == "AutoEvo" then
                    loadoutApplied = false
                    if TDS then TDS.MultiplayerLoadoutLocked = false end
                    warn(string.format("[ServiceHub AutoEvo] Match restarted -> re-executing strategy thread for '%s'...", tostring(activeMap)))
                    logActivity(string.format("[AutoEvo] Rematch successful! Re-executing strategy: %s", tostring(activeMap)), "success")
                    activeStratThread = task.spawn(function()
                        executeAutoEvoStrategy(activeMap)
                    end)
                else
                    SmartTeleportToLobby()
                    break
                end
            end
        end
        autoEvoWatcherRunning = false
    end)
end

handleAutoEvoExecution = function()
    if game.PlaceId == LOBBY_PLACE_ID then return end
    if not Globals.AutoEvo and currentMatchMode ~= "AutoEvo" then return end

    if activeStratThread and coroutine.status(activeStratThread) ~= "dead" then
        task.cancel(activeStratThread)
        activeStratThread = nil
    end

    local evoAnalysis = analyzeAutoEvoRequirements()
    if not evoAnalysis.isEligible then
        Globals.AutoEvo = false
        SetSetting("AutoEvo", false)
        if UI.AutoEvoToggle then UI.AutoEvoToggle:SetValue(false) end
        if game.PlaceId == LOBBY_PLACE_ID then
            SmartTeleportToLobby()
        else
            Globals.IsConfigDirty = true
            if UI and UI.Window and typeof(UI.Window.Notify) == "function" then
                RunAsExecutor(function()
                    UI.Window:Notify({
                        Title = "REQUIREMENTS LOCKED",
                        Desc = "Missing requirements for selected evolution. Match will conclude before returning to lobby.",
                        Duration = 6,
                        Type = "warning"
                    })
                end)()
            end
        end
        return
    end

    if evoAnalysis.activeTower then
        Globals.CurrentEvoActiveTower = evoAnalysis.activeTower
        SetSetting("CurrentEvoActiveTower", evoAnalysis.activeTower)
    end
    if evoAnalysis.farmType then
        Globals.CurrentEvoFarmType = evoAnalysis.farmType
        SetSetting("CurrentEvoFarmType", evoAnalysis.farmType)
    end
    logActivity(string.format("[AutoEvo] Farming: %s (%s)", tostring(Globals.CurrentEvoActiveTower), tostring(Globals.CurrentEvoFarmType)), "info")

    local farmType = Globals.CurrentEvoFarmType or "Coins"
    local stratChoice = Globals.EvoStrat or "Lose"
    if farmType == "Gems" and stratChoice == "Win" then stratChoice = "Lose" end
    local category = AutoEvoConfigs and AutoEvoConfigs[farmType]
    local config = category and (category[stratChoice] or category["Lose"] or category["Win"])
    local activeMap = config and config.Maps and config.Maps[1] or "Lay By"
    activeAutoEvoMap = activeMap

    if config and config.Maps and #config.Maps > 0 then
        local mods = config.Modifiers or {}
        local votedMap = AutoGoldModule.GameInfo(config.Maps[1], mods)
        if type(votedMap) == "string" then
            activeMap = votedMap
            activeAutoEvoMap = votedMap
        else
            return
        end
    end

    local stateReplicators = ReplicatedStorage:WaitForChild("StateReplicators", 10)
    local gameStateReplicator = stateReplicators and stateReplicators:FindFirstChild("GameStateReplicator")
    if gameStateReplicator then
        repeat
            task.wait(1)
            if not Globals.AutoEvo and currentMatchMode ~= "AutoEvo" then return end
        until (gameStateReplicator:GetAttribute("GameStarted") == true)
            or ((gameStateReplicator:GetAttribute("Wave") or 0) > 0)
            or PlayerGui:FindFirstChild("ReactUniversalHotbar")
    else
        task.wait(5)
    end

    if not Globals.AutoEvo and currentMatchMode ~= "AutoEvo" then return end

    AutoGoldModule.LobbyReadyUp()

    activeStratThread = task.spawn(function()
        executeAutoEvoStrategy(activeMap)
    end)

    startAutoEvoWatcher(activeMap)
end

--==============================================================================
-- Multiplayer Standalone Execution & Watcher Lifecycle
--==============================================================================
local function startMultiplayerWatcher()
    if multiplayerWatcherRunning then return end
    multiplayerWatcherRunning = true

    task.spawn(function()
        local missingSince = 0
        local pvCode = extractPrivateCode(Globals.MultiplayerPrivateServerCode or "")

        while isRunning and (Globals.MultiplayerEnabled or currentMatchMode == "Multiplayer") do
            task.wait(1)
            if game.PlaceId == LOBBY_PLACE_ID then break end

            -- 1. Partner Disconnect Watcher (30s grace period)
            local partnerName = Globals.MultiplayerIsHost
                and tostring(Globals.MultiplayerTargetP2 or Globals.MultiplayerHostIdentifier or ""):gsub("^%s*(.-)%s*$", "%1")
                or tostring(Globals.MultiplayerTargetHost or ""):gsub("^%s*(.-)%s*$", "%1")

            if partnerName ~= "" then
                local partnerObj = GetPlayerFromIdentifier(partnerName)
                if partnerObj then
                    missingSince = 0
                else
                    if missingSince == 0 then
                        missingSince = os.time()
                    end
                    local elapsed = os.time() - missingSince
                    local remaining = math.max(0, 30 - elapsed)
                    if elapsed >= 30 then
                        warn(string.format("[Multiplayer Watcher] Partner '%s' disconnected for 30s! Abandoning match...", partnerName))
                        logActivity(string.format("[Multiplayer] Partner %s disconnected (30s). Returning to lobby.", partnerName), "warn")
                        if pvCode ~= "" then
                            local tpOk = teleportToPrivateServer(pvCode)
                            if not tpOk then SmartTeleportToLobby() end
                        else
                            SmartTeleportToLobby()
                        end
                        break
                    end
                end
            end

            -- 2. Match Status Check
            local currentStatus = GetMatchStatus()
            if (currentStatus == "LOSS" or currentStatus == "WIN") and not isHandlingEndMatch then
                isHandlingEndMatch = true

                if activeStratThread and coroutine.status(activeStratThread) ~= "dead" then
                    pcall(task.cancel, activeStratThread)
                    activeStratThread = nil
                end

                handleMultiplayerMatchEnd(currentStatus)
                break
            end
        end
        multiplayerWatcherRunning = false
    end)
end

handleMultiplayerExecution = function()
    if game.PlaceId == LOBBY_PLACE_ID then return end
    if not Globals.MultiplayerEnabled and currentMatchMode ~= "Multiplayer" then return end

    if activeStratThread and coroutine.status(activeStratThread) ~= "dead" then
        task.cancel(activeStratThread)
        activeStratThread = nil
    end

    local isHost = Globals.MultiplayerIsHost == true
    local roleKey = isHost and "Host" or "P2"
    local mpMode = Globals.MultiplayerMode or "Trial Mode"

    warn(string.format("[ServiceHub Multiplayer] Initializing in-game execution: Mode = %s | Role = %s", mpMode, roleKey))
    logActivity(string.format("[Multiplayer] Starting %s as %s", mpMode, roleKey), "info")

    local scriptUrl = nil
    local activeTowers = nil

    if mpMode == "Trial Mode" then
        local liveTrial = ""
        pcall(function()
            local gsr = ReplicatedStorage:FindFirstChild("StateReplicators")
                and ReplicatedStorage.StateReplicators:FindFirstChild("GameStateReplicator")
            if gsr then liveTrial = tostring(gsr:GetAttribute("GlobalTrial") or "") end
            if (liveTrial == "" or liveTrial == "None") and typeof(loadTrialState) == "function" then
                liveTrial = tostring(loadTrialState() or "")
            end
        end)
        if (liveTrial == "" or liveTrial == "None") and Globals.MultiplayerSelectedTrial and Globals.MultiplayerSelectedTrial ~= "Current Rotation" then
            liveTrial = Globals.MultiplayerSelectedTrial
        end

        local mpConfig = Requirements and Requirements.MultiplayerConfig or (getgenv and getgenv().MultiplayerConfig) or {}
        local mpTrialMode = mpConfig.TrialMode or {}
        local trialEntry = nil
        if liveTrial ~= "" and liveTrial ~= "None" then
            trialEntry = mpTrialMode[liveTrial] or mpTrialMode[liveTrial:gsub(" Enemies", "")] or mpTrialMode[liveTrial .. " Enemies"]
        end
        if not trialEntry and Globals.MultiplayerSelectedTrial and Globals.MultiplayerSelectedTrial ~= "Current Rotation" then
            trialEntry = mpTrialMode[Globals.MultiplayerSelectedTrial] or mpTrialMode[Globals.MultiplayerSelectedTrial:gsub(" Enemies", "")]
        end
        if not trialEntry then
            trialEntry = mpTrialMode["Speedy Enemies"] or mpTrialMode["Speedy"]
        end

        if trialEntry then
            if trialEntry.scripts then
                scriptUrl = trialEntry.scripts[roleKey] or trialEntry.scripts["Host"]
            end
            if trialEntry.Towers then
                activeTowers = trialEntry.Towers[roleKey] or trialEntry.Towers["Host"]
            end
        end
    elseif mpMode == "Farm Mode" then
        local farmStrat = Globals.MultiplayerFarmStrategy or "Molten"
        if farmStrat == "Smart Auto" and typeof(resolveSmartFallback) == "function" then
            farmStrat = resolveSmartFallback()
        end
        local fbConfig = FallbackConfigs and FallbackConfigs[farmStrat]
        if fbConfig then
            activeTowers = fbConfig.Towers
            local mapName = fbConfig.Maps and fbConfig.Maps[1] or "Lay By"
            if fbConfig.Scripts then
                scriptUrl = fbConfig.Scripts[mapName] or next(fbConfig.Scripts)
            end
        end
    end

    local stateReplicators = ReplicatedStorage:WaitForChild("StateReplicators", 10)
    local gameStateReplicator = stateReplicators and stateReplicators:FindFirstChild("GameStateReplicator")
    if gameStateReplicator then
        repeat
            task.wait(1)
            if not Globals.MultiplayerEnabled and currentMatchMode ~= "Multiplayer" then return end
        until (gameStateReplicator:GetAttribute("GameStarted") == true)
            or ((gameStateReplicator:GetAttribute("Wave") or 0) > 0)
            or PlayerGui:FindFirstChild("ReactUniversalHotbar")
    else
        task.wait(5)
    end

    if not Globals.MultiplayerEnabled and currentMatchMode ~= "Multiplayer" then return end

    if isHost and AutoGoldModule and typeof(AutoGoldModule.LobbyReadyUp) == "function" then
        AutoGoldModule.LobbyReadyUp()
    end

    if scriptUrl and scriptUrl ~= "" then
        isStrategyExecuting = true
        matchStratExecuted = true

        activeStratThread = task.spawn(function()
            pcall(function()
                local fn = compiledMacroCache[scriptUrl]
                if not fn then
                    local chunk = fetchStrategyScript(scriptUrl)
                    if chunk then
                        local loadedFn, compileErr = loadstring(chunk)
                        if loadedFn then
                            fn = loadedFn
                            compiledMacroCache[scriptUrl] = fn
                        else
                            warn(string.format("[Multiplayer] Failed to parse script: %s", tostring(compileErr)))
                        end
                    end
                end

                if fn then
                    if TDS and typeof(TDS.Loadout) == "function" and type(activeTowers) == "table" and #activeTowers > 0 then
                        warn(string.format("[Multiplayer Loadout] TDS:Loadout equipping %s: %s", tostring(roleKey), table.concat(activeTowers, ", ")))
                        logActivity(string.format("[Multiplayer Loadout] %s: %s", tostring(roleKey), table.concat(activeTowers, ", ")), "info")
                        pcall(function() TDS:Loadout(unpack(activeTowers)) end)
                        loadoutApplied = true
                    end

                    if TDS and typeof(TDS.RemoveIndex) == "function" then
                        pcall(function() TDS:RemoveIndex() end)
                    end

                    if TDS then
                        TDS.MultiplayerLoadoutLocked = true
                    end

                    fn()
                end
            end)
        end)
    else
        warn(string.format("[Multiplayer] No script resolved for %s", tostring(mpMode)))
    end

    startMultiplayerWatcher()
end


--==============================================================================
-- Auto Gatling Integration
--==============================================================================
AutoGatlingRunning = false
do
    local GatlingExecuted = (Globals.GatlingLoaderLoaded == true)

    local function isGatlingEligible(): boolean
    if Globals.GatlingLoaderLoaded then return false end
    if Globals.AutoTrials then
        return true
    elseif Globals.AutoGold and tostring(Globals.Strat or "") == "Win" then
        return true
    elseif Globals.AutoEvo and tostring(Globals.EvoStrat or "") == "Win" then
        return true
    elseif Globals.MultiplayerEnabled then
        return true
    end
    local equippedTowers = Globals.EquippedTowers or {}
    for _, t in ipairs(equippedTowers) do
        if tostring(t):find("Gatling") then
            return true
        end
    end
    if PlayerGui:FindFirstChild("ReactUniversalHotbar") then
        local hotbar = PlayerGui.ReactUniversalHotbar:FindFirstChild("Frame")
        if hotbar then
            for _, child in ipairs(hotbar:GetChildren()) do
                if child:IsA("GuiObject") and child.Name:find("Gatling") then
                    return true
                end
            end
        end
    end
    return Globals.AutoGatling == true
end

    StartAutoGatling = function()
        if Globals.GatlingLoaderLoaded or GatlingExecuted then return end
        if AutoGatlingRunning or not Globals.AutoGatling then return end

        AutoGatlingRunning = true
        task.spawn(function()
            while Globals.AutoGatling and isRunning do
                if Globals.GatlingLoaderLoaded or GatlingExecuted then
                    break
                end

                local GameState = "LOBBY"
                if game.PlaceId ~= LOBBY_PLACE_ID then
                    local sr = ReplicatedStorage:FindFirstChild("StateReplicators")
                    local gsr = sr and sr:FindFirstChild("GameStateReplicator")
                    if gsr and gsr:GetAttribute("GameStarted") == true then
                        GameState = "GAME"
                    end
                end

                if GameState == "GAME" and isGatlingEligible() then
                    if not Globals.GatlingLoaderLoaded and not GatlingExecuted then
                        GatlingExecuted = true 
                        Globals.GatlingLoaderLoaded = true
                        task.spawn(function()
                            local selected = Globals.SelectedGatling or "Gatlify"
                            local scriptFileName = (selected == "Gatling Gun") and "autogutlin.lua" or "Gatlify.lua"
                            local scriptUrl = (selected == "Gatling Gun")
                                and "https://raw.githubusercontent.com/avtryxz/autogutlin/refs/heads/main/autogutlin.lua"
                                or "https://raw.githubusercontent.com/avtryxz/Gatlify/refs/heads/main/Gatlify.lua"

                            local gatlingChunk = readLocalFile(scriptFileName, {
                                "[STAY]/[AutoTrailsFInal]/FinalVersion/" .. scriptFileName,
                                "[STAY]/[AutoTrailsFInal]/" .. scriptFileName,
                                "[STAY]/" .. scriptFileName,
                                scriptFileName,
                            })
                            if not gatlingChunk or #gatlingChunk == 0 then
                                gatlingChunk = safeHttpGet(scriptUrl, 3)
                            end
                            if gatlingChunk then
                                local success, func = pcall(loadstring, gatlingChunk)
                                if success and func then
                                    pcall(func)
                                    logActivity(string.format("[Gatling] Loaded %s macro successfully (One-time load).", selected), "success")
                                else
                                    warn(string.format("[ServiceHub Gatling] Failed to execute %s", selected))
                                    Globals.GatlingLoaderLoaded = false
                                    GatlingExecuted = false
                                end
                            else
                                Globals.GatlingLoaderLoaded = false
                                GatlingExecuted = false
                            end
                        end)
                        break -- The Gatling Loader should only load once!
                    end
                end
                task.wait(1)
            end
            AutoGatlingRunning = false
        end)
    end
end

-- Auto Reload Gatling Logic
AutoReloadRunning = false
do
    local function hasLeadStatus(npc)
    local StatusEffects = npc:FindFirstChild("StatusEffects")
    if StatusEffects then
        local attributes = StatusEffects:GetAttributes()
        for _, val in pairs(attributes) do
            if type(val) == "string" and (string.find(val, '"definitionName":"Lead"') or string.find(val, '"id":"se_15"')) then
                return true
            end
        end
    end
    return false
end

local function isAliveNPC(npc): boolean
    local hpAttr = npc:GetAttribute("Health")
    if hpAttr ~= nil then
        local hpNum = tonumber(hpAttr)
        if hpNum ~= nil then
            return hpNum > 0
        end
    end

    local hum = npc:FindFirstChildOfClass("Humanoid")
    if hum then
        return hum.Health > 0
    end

    local valObj = npc:FindFirstChild("Health")
    if valObj and valObj:IsA("ValueBase") then
        local v = tonumber(valObj.Value)
        if v ~= nil then
            return v > 0
        end
    end

    return true
end

local function checkGatlingAmmo()
    local TowersFolder = workspace:FindFirstChild("Towers")
    local DefaultFolder = TowersFolder and TowersFolder:FindFirstChild("Default")

    if not DefaultFolder then return false, "No Towers Folder" end

    local myGatlingFound = false
    local ammoIsLow = false
    local details = ""
    local MyUserId = LocalPlayer.UserId

    for _, replicator in ipairs(DefaultFolder:GetChildren()) do
        if replicator.Name == "TowerReplicator" then
            local owner = replicator:GetAttribute("OwnerId")
            local towerName = replicator:GetAttribute("Name")

            if tonumber(owner) == MyUserId and towerName == "Gatling Gun" then
                myGatlingFound = true

                local currentAmmo = tonumber(replicator:GetAttribute("Ammo"))
                local maxAmmoAttr = tonumber(replicator:GetAttribute("MaxAmmo"))

                if currentAmmo and maxAmmoAttr and maxAmmoAttr > 0 then
                    local currentPercent = math.round((currentAmmo / maxAmmoAttr) * 100)
                    local threshold = Globals.GatlingReloadPercent or 100

                    if currentAmmo == maxAmmoAttr then
                        details = "Ammo full (100%)"
                    elseif currentPercent <= threshold then
                        ammoIsLow = true
                        details = string.format("Ammo low (%d%% <= %d%%)", currentPercent, threshold)
                    else
                        details = string.format("Ammo high (%d%% > %d%%)", currentPercent, threshold)
                    end
                else
                    details = "Missing Ammo Attributes"
                end
                break
            end
        end
    end

    if not myGatlingFound then
        return false, "Waiting for gatling..."
    elseif not ammoIsLow then
        return false, details
    end

    return true, "All Clear"
end

StartAutoReloadGatling = function()
    if AutoReloadRunning then return end
    AutoReloadRunning = true

    task.spawn(function()
        local clearTimer = 0
        local isCurrentlyReloading = false
        local reloadCooldown = 0
        local lastStatusDesc = ""
        local function updateReloadStatus(newDesc: string)
            if lastStatusDesc ~= newDesc then
                lastStatusDesc = newDesc
                if UI.AutoReloadStatusLabel then
                    UI.AutoReloadStatusLabel:SetDesc(newDesc)
                end
            end
        end

        while isRunning do
            task.wait(0.35) -- Mobile Optimization: Throttled from 0.1s to 0.35s

            if Globals.AutoReloadGatling and isPremiumUser then
                local GameState = "LOBBY"
                if game.PlaceId ~= LOBBY_PLACE_ID then
                    local sr = ReplicatedStorage:FindFirstChild("StateReplicators")
                    local gsr = sr and sr:FindFirstChild("GameStateReplicator")
                    if gsr and gsr:GetAttribute("GameStarted") == true then
                        GameState = "GAME"
                    end
                end

                if GameState == "GAME" then
                    -- If we recently fired reload, wait for reload animation & ammo replenish
                    if isCurrentlyReloading then
                        reloadCooldown = reloadCooldown - 0.35
                        if UI.AutoReloadStatusLabel then
                            UI.AutoReloadStatusLabel:SetDesc(string.format("Status: Reloading in progress... (%.1fs)", math.max(0, reloadCooldown)))
                        end

                        local passesCheck = checkGatlingAmmo()
                        -- Once ammo is refilled or cooldown expires, reset reload lock
                        if not passesCheck or reloadCooldown <= 0 then
                            isCurrentlyReloading = false
                            clearTimer = 0
                        end
                        continue
                    end

                    -- Check 1: Tower ammo percentage
                    local passesTowerCheck, towerError = checkGatlingAmmo()
                    if not passesTowerCheck then
                        clearTimer = 0
                        if UI.AutoReloadStatusLabel then
                            UI.AutoReloadStatusLabel:SetDesc("Status: " .. towerError)
                        end
                        continue
                    end

                    -- Check 2: Check for standard (non-lead) NPCs on the map
                    local hasStandardNPC = false
                    local sr = ReplicatedStorage:FindFirstChild("StateReplicators")
                    if sr then
                        for _, npc in ipairs(sr:GetChildren()) do
                            if npc.Name == "NPCReplicator" and isAliveNPC(npc) and not hasLeadStatus(npc) then
                                hasStandardNPC = true
                                break
                            end
                        end
                    end

                    if hasStandardNPC then
                        clearTimer = 0
                        if UI.AutoReloadStatusLabel then
                            UI.AutoReloadStatusLabel:SetDesc("Status: Locked (Standard NPCs Present)")
                        end
                    else
                        -- Map is clear of standard enemies! Count down 1.0 second
                        clearTimer = clearTimer + 0.35
                        local remaining = math.max(0, 1.0 - clearTimer)

                        if remaining > 0 then
                            if UI.AutoReloadStatusLabel then
                                UI.AutoReloadStatusLabel:SetDesc(string.format("Status: Safe window (%.1fs remaining)...", remaining))
                            end
                        else
                            -- 1 second is OUT! Fire the reload!
                            clearTimer = 0
                            isCurrentlyReloading = true
                            reloadCooldown = 3.0 -- Give 3 seconds for reload animation and server ammo update

                            if UI.AutoReloadStatusLabel then
                                UI.AutoReloadStatusLabel:SetDesc("Status: Reloading Active...")
                            end

                            pcall(function()
                                local event = ReplicatedStorage:FindFirstChild("Network")
                                if event then event = event:FindFirstChild("GatlingGun") end
                                if event then event = event:FindFirstChild("RE:Reload") end
                                if event then event:FireServer() end
                            end)
                        end
                    end
                else
                    clearTimer = 0
                    isCurrentlyReloading = false
                    if UI.AutoReloadStatusLabel then
                        UI.AutoReloadStatusLabel:SetDesc("Status: Waiting for game...")
                    end
                    task.wait(1)
                end
            else
                clearTimer = 0
                isCurrentlyReloading = false
                if UI.AutoReloadStatusLabel then
                    if not isPremiumUser then
                        UI.AutoReloadStatusLabel:SetDesc("Status: 🔒 Locked (Premium Only)")
                    else
                        UI.AutoReloadStatusLabel:SetDesc("Status: Idle")
                    end
                end
                task.wait(1)
            end
        end
        AutoReloadRunning = false
    end)
    end
end

do
    local function RunVoteSkip()
        local RemoteFunc = ReplicatedStorage:FindFirstChild("RemoteFunction")
        while true do
            if not isRunning or not Globals.AutoSkip then break end
            if not RemoteFunc then
                RemoteFunc = ReplicatedStorage:FindFirstChild("RemoteFunction")
            end
            local success = pcall(function()
                if RemoteFunc then
                    RemoteFunc:InvokeServer("Voting", "Skip")
                end
            end)
            if success then break end
            task.wait(0.1)
        end
    end

    StartAutoSkip = function()
    if AutoSkipRunning or not Globals.AutoSkip then return end
    AutoSkipRunning = true

    task.spawn(function()
        while Globals.AutoSkip do
            local SkipVisible =
                PlayerGui:FindFirstChild("ReactOverridesVote")
                and PlayerGui.ReactOverridesVote:FindFirstChild("Frame")
                and PlayerGui.ReactOverridesVote.Frame:FindFirstChild("votes")
                and PlayerGui.ReactOverridesVote.Frame.votes:FindFirstChild("vote")

            if SkipVisible and SkipVisible.Position == UDim2.new(0.5, 0, 0.5, 0) then
                RunVoteSkip()
            end

            task.wait(0.4) -- Mobile Optimization: Throttled from 0.1s to 0.4s
        end

        AutoSkipRunning = false
    end)
    end
end

--==============================================================================
-- Execution Bootstrap & Unified Background Loops
--==============================================================================
do
    local buildOk, buildErr = pcall(function()
        if setthreadidentity then pcall(setthreadidentity, 8) end
        buildInterface()
    end)
    if not buildOk then
        warn(string.format("[ServiceHub] Error initializing GUI: %s", tostring(buildErr)))
    end
end

if Globals.MobileBoost then
    task.spawn(function()
        task.wait(1.5)
        applyMobileOptimizations(true)
    end)
end

if Globals.TimeScaleEnabled and not TimeScaleRunning then
    StartTimeScale()
end

if Globals.AutoGatling and not AutoGatlingRunning then
    StartAutoGatling()
end

if Globals.AutoReloadGatling and not AutoReloadRunning and typeof(StartAutoReloadGatling) == "function" then
    StartAutoReloadGatling()
end

if Globals.AutoSkip and not AutoSkipRunning then
    StartAutoSkip()
end

if game.PlaceId ~= LOBBY_PLACE_ID then
    -- In-Game Execution Flow
    snapshotMatchConfig()

    -- Check if script was executed or re-executed mid-game (not wave 0 or wave 1)
    pcall(function()
        local stateReps = ReplicatedStorage:FindFirstChild("StateReplicators")
        local gsr = stateReps and stateReps:FindFirstChild("GameStateReplicator")
        if gsr then
            initialExecutionWave = gsr:GetAttribute("Wave") or 0
        else
            local pgui = LocalPlayer:FindFirstChild("PlayerGui")
            local topDisplay = pgui and pgui:FindFirstChild("TopGameDisplay")
            if topDisplay and topDisplay:FindFirstChild("Frame") and topDisplay.Frame:FindFirstChild("wave") then
                local label = topDisplay.Frame.wave:FindFirstChild("container") and topDisplay.Frame.wave.container:FindFirstChild("value")
                if label and label:IsA("TextLabel") then
                    local waveNum = label.Text:match("^(%d+)")
                    if waveNum then initialExecutionWave = tonumber(waveNum) or 0 end
                end
            end
        end
    end)

    if initialExecutionWave > 1 then
        isLateExecution = true
        Globals.IsConfigDirty = true
        task.spawn(function()
            task.wait(1.5)
            if UI and UI.Window and typeof(UI.Window.Notify) == "function" then
                RunAsExecutor(function()
                    UI.Window:Notify({
                        Title = "MID-GAME RE-EXECUTION",
                        Desc = string.format("Detected start at Wave %d. Match will finish, then teleport to Smart Lobby!", initialExecutionWave),
                        Duration = 8,
                        Type = "warning"
                    })
                end)()
            end
        end)
    end

    pcall(function()
        if not PlayerDataHandler then
            PlayerDataHandler = loadPlayerDataHandler()
        end
        if typeof(refreshDisplay) == "function" then
            refreshDisplay()
        end
    end)

    if Globals.AutoSkip and not AutoSkipRunning then
        StartAutoSkip()
    end

    -- Dedicated In-Game Dispatcher (Each mode has its own standalone lifecycle):
    if Globals.MultiplayerEnabled or currentMatchMode == "Multiplayer" then
        warn("[ServiceHub Dispatcher] Active Mode = Multiplayer. Spawning handleMultiplayerExecution...")
        task.spawn(handleMultiplayerExecution)
    elseif Globals.AutoEvo or currentMatchMode == "AutoEvo" then
        warn("[ServiceHub Dispatcher] Active Mode = Auto Evo Standalone. Spawning handleAutoEvoExecution...")
        task.spawn(handleAutoEvoExecution)
    elseif Globals.AutoTrials or currentMatchMode == "AutoTrials" then
        warn("[ServiceHub Dispatcher] Active Mode = Auto Trials (Progression Mode intact). Spawning handleAutoTrialsExecution...")
        task.spawn(handleAutoTrialsExecution)
    elseif Globals.AutoGold or currentMatchMode == "AutoGold" then
        warn("[ServiceHub Dispatcher] Active Mode = Auto Gold. Spawning handleAutoGoldExecution...")
        task.spawn(handleAutoGoldExecution)
    end

    runInGameGuard()

    -- In-Game Match Completion Supervisor (ensures GetMatchStatus is tracked even if mode watchers are idle)
    task.spawn(function()
        while isRunning do
            task.wait(1)
            if game.PlaceId == LOBBY_PLACE_ID then break end

            local currentStatus = GetMatchStatus()
            if (currentStatus == "LOSS" or currentStatus == "WIN") and not isHandlingEndMatch then
                -- Only supervise if none of the 4 watchers are actively running
                if not multiplayerWatcherRunning and not autoEvoWatcherRunning and not trialWatcherRunning and not autoGoldWatcherRunning then
                    if (Globals.AutoEvo or currentMatchMode == "AutoEvo") and currentStatus == "LOSS" and shouldRetryAutoEvoLoss(currentStatus) then
                        warn("[ServiceHub Supervisor] Watchers idle on LOSS, but Auto Evo Lose retry is active. Launching handleAutoEvoExecution.")
                        task.spawn(handleAutoEvoExecution)
                    else
                        local evoMilestone, evoReason = false, nil
                        if Globals.AutoEvo then
                            pcall(function()
                                evoMilestone, evoReason = checkAutoEvoMilestonesReached()
                            end)
                        end
                        if Globals.MultiplayerEnabled or Globals.IsConfigDirty or Globals.AutoEvoMilestoneReached or evoMilestone or (isMatchConfigDirty and isMatchConfigDirty()) then
                            isHandlingEndMatch = true
                            if activeStratThread and coroutine.status(activeStratThread) ~= "dead" then
                                pcall(task.cancel, activeStratThread)
                                activeStratThread = nil
                            end
                            shouldTeleportOnMatchEnd(currentStatus)
                            break
                        end
                    end
                end
            end
        end
    end)

    task.spawn(function()
        while isRunning do
            if setthreadidentity then pcall(setthreadidentity, 8) end
            local hasGui = false
            pcall(function()
                hasGui = UI.ScreenGui and UI.ScreenGui.Parent ~= nil
            end)
            if not hasGui then break end

            task.wait(5)
            pcall(function()
                if setthreadidentity then pcall(setthreadidentity, 8) end
                if not PlayerDataHandler then
                    PlayerDataHandler = loadPlayerDataHandler()
                end
                if PlayerDataHandler and typeof(refreshDisplay) == "function" then
                    refreshDisplay()
                end
            end)
        end
    end)
else
    -- Lobby Unified Management Flow
    task.spawn(fastQueueLobby)

    -- Single consolidated background monitor loop for the Lobby
    task.spawn(function()
        local lastQueueTick = 0
        while isRunning do
            if setthreadidentity then pcall(setthreadidentity, 8) end
            local hasGui = false
            pcall(function()
                hasGui = UI.ScreenGui and UI.ScreenGui.Parent ~= nil
            end)
            if not hasGui then break end

            task.wait(5)
            if game.PlaceId ~= LOBBY_PLACE_ID then break end

            pcall(function()
                if setthreadidentity then pcall(setthreadidentity, 8) end
                if not PlayerDataHandler then
                    PlayerDataHandler = loadPlayerDataHandler()
                end

                if PlayerDataHandler then
                    refreshDisplay()
                end

                local now = os.time()
                if now - lastQueueTick >= 5 then
                    lastQueueTick = now
                    fastQueueLobby()
                end
            end)
        end
    end)
end

return UI.ScreenGui
