-- Magic Loot [Dino Event] - Full Auto Farm Hub (MOBILE / Delta diagnostic build)
-- Same features as MagicLootFullAutoFarm.lua, PLUS an on-screen debug log
-- (since Delta's console isn't easy to read on a phone) and a manual
-- "Sell Now" button so you can trigger a sell outside the auto-loop and see
-- exactly what happens, step by step, without needing PC access.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

local SessionId = tostring(os.clock()) .. "_" .. tostring(math.random(1, 1e9))
if getgenv then
    getgenv().MagicLootFarmSession = SessionId
end
local function isCurrentSession()
    return not getgenv or getgenv().MagicLootFarmSession == SessionId
end

--============================================================
-- On-screen debug log (read this instead of the console)
--============================================================

local DebugGui, DebugList
local debugLines = {}

local function ensureDebugGui()
    if DebugGui and DebugGui.Parent then return end
    pcall(function()
        local old = LocalPlayer.PlayerGui:FindFirstChild("MagicLootDebug")
        if old then old:Destroy() end
    end)

    DebugGui = Instance.new("ScreenGui")
    DebugGui.Name = "MagicLootDebug"
    DebugGui.ResetOnSpawn = false
    DebugGui.IgnoreGuiInset = true
    DebugGui.Parent = LocalPlayer.PlayerGui

    local Frame = Instance.new("Frame")
    Frame.Size = UDim2.new(0, 380, 0, 220)
    Frame.Position = UDim2.new(0, 10, 1, -230)
    Frame.BackgroundColor3 = Color3.new(0, 0, 0)
    Frame.BackgroundTransparency = 0.35
    Frame.BorderSizePixel = 0
    Frame.Parent = DebugGui

    local Title = Instance.new("TextLabel")
    Title.Size = UDim2.new(1, 0, 0, 24)
    Title.BackgroundTransparency = 1
    Title.Text = "Magic Loot Debug Log"
    Title.TextColor3 = Color3.new(1, 1, 1)
    Title.Font = Enum.Font.SourceSansBold
    Title.TextSize = 16
    Title.Parent = Frame

    DebugList = Instance.new("TextLabel")
    DebugList.Size = UDim2.new(1, -8, 1, -28)
    DebugList.Position = UDim2.new(0, 4, 0, 26)
    DebugList.BackgroundTransparency = 1
    DebugList.Text = ""
    DebugList.TextColor3 = Color3.new(1, 1, 0)
    DebugList.Font = Enum.Font.Code
    DebugList.TextSize = 13
    DebugList.TextXAlignment = Enum.TextXAlignment.Left
    DebugList.TextYAlignment = Enum.TextYAlignment.Top
    DebugList.TextWrapped = true
    DebugList.Parent = Frame
end

local function debugLog(msg)
    print("[MagicLoot] " .. tostring(msg))
    pcall(function()
        ensureDebugGui()
        table.insert(debugLines, os.date("%H:%M:%S") .. "  " .. tostring(msg))
        while #debugLines > 10 do
            table.remove(debugLines, 1)
        end
        DebugList.Text = table.concat(debugLines, "\n")
    end)
end

debugLog("Script loaded, session=" .. SessionId)

--============================================================
-- Game modules
--============================================================

local okUtils, UtilsSystem = pcall(require, game.ReplicatedFirst.AllSideCode.UtilsSystem)
if not okUtils then
    debugLog("FATAL: could not require UtilsSystem: " .. tostring(UtilsSystem))
    return
end

local NetWork = UtilsSystem.NetWork
local NetMsg = UtilsSystem.NetMsg
local CfgFind = UtilsSystem.CfgFind
local GetData = UtilsSystem.GetData
local PlayerData = UtilsSystem.PlayerData
local EnumMgr = UtilsSystem.EnumMgr
local CollectionService = UtilsSystem.CollectionService
local TipsModule = UtilsSystem.TipsModule
local ItemType = EnumMgr.ItemType
local Alchemy = GetData.Alchemy

debugLog("UtilsSystem OK. NetWork=" .. tostring(NetWork ~= nil) .. " NetMsg=" .. tostring(NetMsg ~= nil)
    .. " PlayerData=" .. tostring(PlayerData ~= nil) .. " Backpack=" .. tostring(GetData.Backpack ~= nil))

local bagFullTipSeen = false
if TipsModule and TipsModule.ErrorTips then
    local originalErrorTips = TipsModule.ErrorTips
    TipsModule.ErrorTips = function(player, key, ...)
        if type(key) == "string" and (key:find("背包") or key:find("[Bb]ackpack")) then
            bagFullTipSeen = true
        end
        return originalErrorTips(player, key, ...)
    end
end

local tipsHookConnection = nil
local function ensureTipsHook()
    if tipsHookConnection then return end
    local PlayerGui = LocalPlayer:FindFirstChild("PlayerGui")
    local TipsGui = PlayerGui and PlayerGui:FindFirstChild("TipsGui")
    local NewTipsFrame = TipsGui and TipsGui:FindFirstChild("NewTipsFrame")
    if not NewTipsFrame then return end
    local function checkLabel(inst)
        if not inst:IsA("TextLabel") then return end
        local function check()
            local text = inst.Text or ""
            if text:find("[Bb]ackpack") or text:find("背包") then
                bagFullTipSeen = true
            end
        end
        check()
        inst:GetPropertyChangedSignal("Text"):Connect(check)
    end
    for _, inst in ipairs(NewTipsFrame:GetChildren()) do
        checkLabel(inst)
    end
    tipsHookConnection = NewTipsFrame.ChildAdded:Connect(checkLabel)
end

pcall(function()
    local RobloxGui = game.CoreGui:FindFirstChild("RobloxGui")
    local old = RobloxGui and RobloxGui:FindFirstChild("Rayfield")
    if old then old:Destroy() end
end)

local okRay, Rayfield = pcall(function()
    return loadstring(game:HttpGet('https://sirius.menu/rayfield'))()
end)
if not okRay then
    debugLog("FATAL: Rayfield failed to load: " .. tostring(Rayfield))
    return
end
debugLog("Rayfield loaded OK")

local Window = Rayfield:CreateWindow({
    Name = "Magic Loot Auto Farm (Mobile)",
    LoadingTitle = "Magic Loot [Dino Event]",
    LoadingSubtitle = "Mobile Diagnostic Build",
    ConfigurationSaving = {
        Enabled = true,
        FolderName = "MagicLootAutoFarmHub",
        FileName = "MobileConfig",
    },
})

local LootTab = Window:CreateTab("Loot")
local DungeonTab = Window:CreateTab("Dungeon")

local State = {
    AutoPickup = false,
    MinPickupPrice = 0,
    AutoSell = false,
    MaxSellPrice = 1000,
    AutoClaimOnline = false,

    AutoDungeon = false,
    StageCap = 10,
    HoverHeight = 10,
    HpReturnPercent = 50,

    TeleportFarmEnabled = false,
    TeleportFarmStage = nil,
}

if getgenv then
    getgenv().MagicLootFarmState = State
end

--============================================================
-- Shared helpers
--============================================================

local function getUnitPrice(itemId)
    if not itemId then return 0 end
    local okCfg, cfg = pcall(CfgFind.FindCfgByID, itemId, ItemType.Material)
    if not okCfg or not cfg then return 0 end
    local okPrice, price = pcall(GetData.GetSellPrice, LocalPlayer, cfg)
    if okPrice and type(price) == "number" then return price end
    return tonumber(cfg.GoldValue) or 0
end

-- Sells every unlocked, non-recipe-protected material below maxPrice.
-- Verbose version: reports every step to the on-screen log so a sell
-- failure is visible without console access.
local function sellJunk(maxPrice, verbose)
    local function log(msg)
        if verbose then debugLog(msg) end
    end

    local okBag, Bag = pcall(PlayerData.GetPlrDataByKey, LocalPlayer, "Bag")
    if not okBag then
        log("sellJunk: GetPlrDataByKey errored: " .. tostring(Bag))
        return 0
    end
    if type(Bag) ~= "table" then
        log("sellJunk: Bag is not a table (got " .. type(Bag) .. ")")
        return 0
    end

    local scanned, skippedLocked, skippedProtected, skippedPrice = 0, 0, 0, 0
    local sellList = {}
    for _, item in pairs(Bag) do
        if type(item) == "table" and tonumber(item.tp) == ItemType.Material then
            scanned = scanned + 1
            local locked = item.lock == 1 or item.lock == true
            if locked then
                skippedLocked = skippedLocked + 1
            else
                local itemId = tonumber(item.id)
                local protected = false
                if itemId and Alchemy then
                    local okProt, isProt = pcall(Alchemy.IsMarkedRecipeMaterial, LocalPlayer, itemId)
                    protected = okProt and isProt
                end
                if protected then
                    skippedProtected = skippedProtected + 1
                else
                    local price = getUnitPrice(itemId)
                    if price < maxPrice then
                        local onlyID = tonumber(item.onlyID)
                        if onlyID then table.insert(sellList, onlyID) end
                    else
                        skippedPrice = skippedPrice + 1
                    end
                end
            end
        end
    end

    log(string.format(
        "sellJunk: %d material items in bag, threshold<%s -> %d queued, %d locked, %d recipe-protected, %d over price",
        scanned, tostring(maxPrice), #sellList, skippedLocked, skippedProtected, skippedPrice
    ))

    if #sellList == 0 then
        return 0
    end

    local ok, result = pcall(function()
        return NetWork.InvokeServer(NetMsg.SELL_MATERIAL, { onlyIDList = sellList })
    end)
    log(string.format("sellJunk: SELL_MATERIAL call ok=%s result=%s", tostring(ok), tostring(result)))

    return #sellList
end

local Character = {
    model = nil,
    hrp = nil,
    humanoid = nil,
}

local function refreshCharacter()
    local model = LocalPlayer.Character
    if not model then return end
    Character.model = model
    Character.hrp = model:FindFirstChild("HumanoidRootPart")
    Character.humanoid = model:FindFirstChildOfClass("Humanoid")
end

LocalPlayer.CharacterAdded:Connect(function()
    task.wait(0.5)
    refreshCharacter()
    if Character.hrp then Character.hrp.Anchored = false end
end)
refreshCharacter()

local function getHpPercent()
    local hum = Character.humanoid
    if not hum or hum.MaxHealth <= 0 then return 100 end
    return (hum.Health / hum.MaxHealth) * 100
end

local function isInDungeonChallenge()
    local v = LocalPlayer:FindFirstChild("InDungeonChallenge")
    return v ~= nil and tonumber(v.Value) and v.Value > 0
end

local function isInSafeArea()
    local v = LocalPlayer:FindFirstChild("InStageSafeArea")
    return not v or tonumber(v.Value) == nil or v.Value > 0
end

local function getBagUsage()
    local okSize, size = pcall(GetData.Backpack.GetBackpackWarehouseCurrentSize, LocalPlayer)
    if okSize and type(size) == "number" then return size end
    return 0
end

local function getBagMax()
    local okSize, size = pcall(GetData.Backpack.GetBackpackWarehouseMaxSize)
    if okSize and type(size) == "number" and size > 0 then return size end
    return 999
end

local function getEligibleTeleStages()
    local careerMax = LocalPlayer:FindFirstChild("CareerMaxStage")
    careerMax = careerMax and tonumber(careerMax.Value) or 0

    local broomMax = 0
    local NowBroom = LocalPlayer:FindFirstChild("NowBroom")
    local broomId = NowBroom and tonumber(NowBroom.Value) or 0
    if broomId > 0 then
        local okCfg, cfg = pcall(CfgFind.FindCfgByID, broomId, EnumMgr.ItemType.Broom)
        if okCfg and cfg then broomMax = tonumber(cfg.Dungeon) or 0 end
    end

    local stages = {}
    local maxStage = math.min(careerMax, broomMax)
    for i = 1, maxStage do
        local okCfg, cfg = pcall(CfgFind.GetCfgByNameAndID, "dungeonConf", i)
        if okCfg and cfg and type(cfg.TeleIcon) == "string" and cfg.TeleIcon ~= "" then
            table.insert(stages, i)
        end
    end
    return stages
end

local function getDoors()
    local doors = {}
    for _, d in ipairs(CollectionService:GetTagged("DungeonFrontDoor")) do
        local stage = tonumber(d:GetAttribute("Stage"))
        if stage then doors[stage] = d end
    end
    return doors
end

local function getCurrentTargetPosition()
    local ok, obj = pcall(function()
        local v = ReplicatedStorage:FindFirstChild("NowTargetCurrent")
        return v and v.Value
    end)
    if not ok or not obj or not obj.Parent then return nil end
    if obj:IsA("Model") then
        local okPivot, cf = pcall(obj.GetPivot, obj)
        if okPivot then return cf.Position end
        return nil
    elseif obj:IsA("BasePart") then
        return obj.Position
    end
    return nil
end

local function enableAutoAttack()
    local hub = LocalPlayer:FindFirstChild("PlayerScripts")
        and LocalPlayer.PlayerScripts:FindFirstChild("Manager")
        and LocalPlayer.PlayerScripts.Manager:FindFirstChild("PlayerSkillClientManager")
        and LocalPlayer.PlayerScripts.Manager.PlayerSkillClientManager:FindFirstChild("PlayerSkillControlHub")
    if not hub then
        debugLog("enableAutoAttack: PlayerSkillControlHub not found")
        return
    end
    local okReq, ControlHub = pcall(require, hub)
    if okReq and ControlHub and ControlHub.setDebugAutoAttackEnabled then
        pcall(ControlHub.setDebugAutoAttackEnabled, true)
        debugLog("Auto-attack enabled")
    else
        debugLog("enableAutoAttack: require/setDebugAutoAttackEnabled failed: " .. tostring(ControlHub))
    end
end

local DungeonState = "PUSH" -- "PUSH" | "RETURNING"
local TeleportFarmState = "FARM" -- "FARM" | "RETURNING"

--============================================================
-- Auto Pickup
--============================================================

task.spawn(function()
    while true do
        task.wait(0.3)
        if not isCurrentSession() then break end
        if State.AutoPickup then
            local DropsClient = workspace:FindFirstChild("DropsClient")
            if DropsClient then
                for _, prompt in ipairs(DropsClient:GetDescendants()) do
                    if prompt:IsA("ProximityPrompt") and prompt.Name == "PickupPrompt" then
                        local model = prompt.Parent and prompt.Parent.Parent
                        local itemId = model and tonumber(model:GetAttribute("ItemId"))
                        if itemId and getUnitPrice(itemId) >= State.MinPickupPrice then
                            local ok, err = pcall(fireproximityprompt, prompt, 0)
                            if not ok then
                                debugLog("fireproximityprompt failed: " .. tostring(err))
                            end
                        end
                    end
                end
            end
        end
    end
end)

--============================================================
-- Auto Sell (standalone loop)
--============================================================

task.spawn(function()
    while true do
        task.wait(2)
        if not isCurrentSession() then break end
        if State.AutoSell then
            sellJunk(State.MaxSellPrice, false)
        end
    end
end)

--============================================================
-- Auto Claim Online Reward
--============================================================

local function claimOnlineRewards(verbose)
    local function log(msg)
        if verbose then debugLog(msg) end
    end

    local okList, list = pcall(CfgFind.GetOnlineAwardList)
    if not okList then
        log("claimOnlineRewards: GetOnlineAwardList errored: " .. tostring(list))
        return 0
    end
    if type(list) ~= "table" then
        log("claimOnlineRewards: award list is not a table (got " .. type(list) .. ")")
        return 0
    end

    local okBox, onlineBox = pcall(PlayerData.GetPlrDataByKey, LocalPlayer, "OnlineBox")
    if not okBox then
        log("claimOnlineRewards: GetPlrDataByKey(OnlineBox) errored: " .. tostring(onlineBox))
        onlineBox = nil
    end
    log(string.format("claimOnlineRewards: %d tiers total, OnlineSeconds=%s",
        #list, tostring(onlineBox and onlineBox.OnlineSeconds)))

    local attempted, claimed = 0, 0
    for _, award in ipairs(list) do
        local claimable = true
        if onlineBox then
            local okCheck, res = pcall(CfgFind.IsOnlineTierClaimable, onlineBox, award)
            if okCheck then claimable = res end
        end
        if claimable then
            attempted = attempted + 1
            local ok, result = pcall(function()
                return NetWork.InvokeServer(NetMsg.CLAIM_ONLINE_AWARD, award.id)
            end)
            log(string.format("claimOnlineRewards: tier id=%s ok=%s result=%s",
                tostring(award.id), tostring(ok), tostring(result)))
            if ok and result then claimed = claimed + 1 end
        end
    end
    log(string.format("claimOnlineRewards: %d/%d tiers looked claimable, %d actually claimed",
        attempted, #list, claimed))
    return claimed
end

task.spawn(function()
    while true do
        task.wait(5)
        if not isCurrentSession() then break end
        if State.AutoClaimOnline then
            claimOnlineRewards(false)
        end
    end
end)

--============================================================
-- Hover combat positioning
--============================================================

task.spawn(function()
    while true do
        task.wait(0.2)
        if not isCurrentSession() then break end
        local returning = DungeonState == "RETURNING" or TeleportFarmState == "RETURNING"
        if not returning and (State.AutoDungeon or State.TeleportFarmEnabled) and isInDungeonChallenge() and not isInSafeArea() and Character.hrp then
            local targetPos = getCurrentTargetPosition()
            if targetPos then
                local hoverPos = targetPos + Vector3.new(0, State.HoverHeight, 0)
                Character.hrp.Anchored = true
                local tween = TweenService:Create(
                    Character.hrp,
                    TweenInfo.new(0.18, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
                    { CFrame = CFrame.lookAt(hoverPos, targetPos) }
                )
                tween:Play()
            else
                if Character.hrp.Anchored then
                    Character.hrp.Anchored = false
                end
            end
        elseif Character.hrp and Character.hrp.Anchored then
            Character.hrp.Anchored = false
        end
    end
end)

--============================================================
-- Dungeon push state machine
--============================================================

local pushStage = 1
local lastEnterAttempt = 0
local stageEnterTime = os.clock()
local returningEnteredAt = os.clock()
local STAGE_TIMEOUT_SECONDS = 90
local RETURNING_TIMEOUT_SECONDS = 30

local sawDropThisStage = false
local dropsClientConnection = nil

local function ensureDropsClientHook()
    if dropsClientConnection then return end
    local DropsClient = workspace:FindFirstChild("DropsClient")
    if DropsClient then
        dropsClientConnection = DropsClient.DescendantAdded:Connect(function(inst)
            if inst.Name == "DropItem" then
                sawDropThisStage = true
            end
        end)
    end
end

local function stageDoorPosition(doors, stage)
    local door = doors[stage]
    if not door then return nil end
    local okPivot, cf = pcall(door.GetPivot, door)
    if not okPivot then return nil end
    return cf.Position
end

local function enterStage(stage)
    refreshCharacter()
    local doors = getDoors()
    local pos = stageDoorPosition(doors, stage)
    if pos and Character.hrp then
        pcall(function()
            Character.hrp.Anchored = false
            Character.hrp.CFrame = CFrame.new(pos + Vector3.new(0, 3, 6))
        end)
    end
    sawDropThisStage = false
    stageEnterTime = os.clock()
    ensureDropsClientHook()
end

local SAFE_RETURN_POSITION = Vector3.new(-454.74, 10.15, 88.90)
local DEEP_TOWN_POSITION = Vector3.new(-452.62, 10.09, 51.91)

local function retreatAndSell()
    refreshCharacter()
    if Character.hrp then
        pcall(function()
            Character.hrp.Anchored = false
            Character.hrp.CFrame = CFrame.new(SAFE_RETURN_POSITION)
            task.wait(0.1)

            local steps1 = 16
            for i = 1, steps1 do
                Character.hrp.CFrame = Character.hrp.CFrame + Vector3.new(0, 0, -0.35)
                task.wait(0.8 / steps1)
            end

            local startPos = Character.hrp.Position
            local steps2 = 16
            for i = 1, steps2 do
                local alpha = i / steps2
                Character.hrp.CFrame = CFrame.new(startPos:Lerp(DEEP_TOWN_POSITION, alpha))
                task.wait(0.6 / steps2)
            end
        end)
    end
    task.wait(1)
    sellJunk(math.huge, true)
    task.wait(0.5)
end

if getgenv then
    getgenv().MagicLootFarmDebug = {
        getPushStage = function() return pushStage end,
        getDungeonState = function() return DungeonState end,
        getSawDrop = function() return sawDropThisStage end,
        getBagFullTipSeen = function() return bagFullTipSeen end,
    }
end

task.spawn(function()
    enableAutoAttack()
    while true do
        task.wait(1)
        if not isCurrentSession() then break end
        if not State.AutoDungeon then
            DungeonState = "PUSH"
        else
            if DungeonState == "PUSH" then
                ensureTipsHook()
                local bagFull = getBagUsage() >= getBagMax() or bagFullTipSeen
                local hpLow = getHpPercent() < State.HpReturnPercent
                if bagFull or hpLow then
                    returningEnteredAt = os.clock()
                    DungeonState = "RETURNING"
                else
                    ensureDropsClientHook()
                    local timedOut = (os.clock() - stageEnterTime) > STAGE_TIMEOUT_SECONDS
                    if sawDropThisStage or timedOut then
                        if pushStage < State.StageCap then
                            pushStage = pushStage + 1
                        end
                        lastEnterAttempt = 0
                    end
                    if (os.clock() - lastEnterAttempt) > 5 then
                        lastEnterAttempt = os.clock()
                        enterStage(math.min(pushStage, State.StageCap))
                    end
                end
            elseif DungeonState == "RETURNING" then
                retreatAndSell()
                local stuck = (os.clock() - returningEnteredAt) > RETURNING_TIMEOUT_SECONDS
                if getHpPercent() >= State.HpReturnPercent or stuck then
                    bagFullTipSeen = false
                    pushStage = 1
                    lastEnterAttempt = 0
                    DungeonState = "PUSH"
                end
            end
        end
    end
end)

--============================================================
-- Teleport Farm
--============================================================

local lastTeleportAttempt = 0
local teleReturningEnteredAt = os.clock()

if getgenv then
    getgenv().MagicLootFarmDebug.getTeleportFarmState = function() return TeleportFarmState end
end

task.spawn(function()
    while true do
        task.wait(1)
        if not isCurrentSession() then break end
        if not State.TeleportFarmEnabled or State.AutoDungeon or not State.TeleportFarmStage then
            TeleportFarmState = "FARM"
        else
            if TeleportFarmState == "FARM" then
                ensureTipsHook()
                local bagFull = getBagUsage() >= getBagMax() or bagFullTipSeen
                local hpLow = getHpPercent() < State.HpReturnPercent
                if bagFull or hpLow then
                    teleReturningEnteredAt = os.clock()
                    TeleportFarmState = "RETURNING"
                elseif not isInDungeonChallenge() and (os.clock() - lastTeleportAttempt) > 8 then
                    lastTeleportAttempt = os.clock()
                    pcall(function()
                        NetWork.FireServer(NetMsg.STAGE_JUMP_REQUEST, State.TeleportFarmStage)
                    end)
                end
            elseif TeleportFarmState == "RETURNING" then
                retreatAndSell()
                local stuck = (os.clock() - teleReturningEnteredAt) > RETURNING_TIMEOUT_SECONDS
                if getHpPercent() >= State.HpReturnPercent or stuck then
                    bagFullTipSeen = false
                    lastTeleportAttempt = 0
                    TeleportFarmState = "FARM"
                end
            end
        end
    end
end)

--============================================================
-- GUI - Loot tab
--============================================================

LootTab:CreateToggle({
    Name = "Auto Pickup Item",
    CurrentValue = false,
    Flag = "AutoPickup",
    Callback = function(v) State.AutoPickup = v end,
})

LootTab:CreateInput({
    Name = "Min Pickup Price (ต่ำกว่านี้ไม่เก็บ)",
    PlaceholderText = "0",
    RemoveTextAfterFocusLost = false,
    Flag = "MinPickupPrice",
    Callback = function(txt) State.MinPickupPrice = tonumber(txt) or 0 end,
})

LootTab:CreateToggle({
    Name = "Auto Sell",
    CurrentValue = false,
    Flag = "AutoSell",
    Callback = function(v) State.AutoSell = v end,
})

LootTab:CreateInput({
    Name = "Sell ของราคาต่ำกว่านี้ทิ้ง",
    PlaceholderText = "1000",
    RemoveTextAfterFocusLost = false,
    Flag = "MaxSellPrice",
    Callback = function(txt) State.MaxSellPrice = tonumber(txt) or 0 end,
})

LootTab:CreateButton({
    Name = "Sell Now (ทดสอบขายทันที)",
    Callback = function()
        debugLog("Sell Now pressed, threshold=" .. tostring(State.MaxSellPrice))
        local n = sellJunk(State.MaxSellPrice, true)
        debugLog("Sell Now done, queued " .. tostring(n) .. " items")
    end,
})

LootTab:CreateToggle({
    Name = "Auto Claim Online Reward",
    CurrentValue = false,
    Flag = "AutoClaimOnline",
    Callback = function(v) State.AutoClaimOnline = v end,
})

LootTab:CreateButton({
    Name = "Claim Now (ทดลองเคลมทันที)",
    Callback = function()
        debugLog("Claim Now pressed")
        local n = claimOnlineRewards(true)
        debugLog("Claim Now done, claimed " .. tostring(n) .. " tiers")
    end,
})

--============================================================
-- GUI - Dungeon tab
--============================================================

local autoDungeonToggle, teleportFarmToggle

autoDungeonToggle = DungeonTab:CreateToggle({
    Name = "Auto Dungeon Push (เดินฟาร์ม+ลอยหลบมอนอัตโนมัติ)",
    CurrentValue = false,
    Flag = "AutoDungeon",
    Callback = function(v)
        State.AutoDungeon = v
        if v then
            enableAutoAttack()
            pushStage = 1
            State.TeleportFarmEnabled = false
            pcall(function() teleportFarmToggle:Set(false) end)
        end
    end,
})

DungeonTab:CreateInput({
    Name = "Stage สูงสุดที่จะดันถึง (cap)",
    PlaceholderText = "10",
    RemoveTextAfterFocusLost = false,
    Flag = "StageCap",
    Callback = function(txt) State.StageCap = tonumber(txt) or State.StageCap end,
})

DungeonTab:CreateParagraph({
    Title = "Farm ที่ Stage เดียว (ใช้ Teleport ของเกม)",
    Content = "เลือก stage ที่จะวาปไป (ต้องเคยผ่านมาแล้ว + อยู่ในระยะไม้กวาดที่ถืออยู่) ยืนฟาร์มจนของเต็ม แล้วกลับเมือง ขายของ วาปกลับที่เดิมอัตโนมัติ",
})

local teleStageOptions = {}
for _, stage in ipairs(getEligibleTeleStages()) do
    table.insert(teleStageOptions, tostring(stage))
end
if #teleStageOptions == 0 then
    teleStageOptions = { "ไม่มี stage ที่วาปได้ตอนนี้" }
end

local teleStageDropdown = DungeonTab:CreateDropdown({
    Name = "เลือก Stage",
    Options = teleStageOptions,
    CurrentOption = { teleStageOptions[1] },
    MultipleOptions = false,
    Flag = "TeleportFarmStage",
    Callback = function(option)
        local stage = tonumber(option[1] or option)
        State.TeleportFarmStage = stage
    end,
})
State.TeleportFarmStage = tonumber(teleStageOptions[1])

local lastTeleStageOptionsKey = table.concat(teleStageOptions, ",")
task.spawn(function()
    while true do
        task.wait(15)
        if not isCurrentSession() then break end
        local fresh = {}
        for _, stage in ipairs(getEligibleTeleStages()) do
            table.insert(fresh, tostring(stage))
        end
        if #fresh == 0 then
            fresh = { "ไม่มี stage ที่วาปได้ตอนนี้" }
        end
        local key = table.concat(fresh, ",")
        if key ~= lastTeleStageOptionsKey then
            lastTeleStageOptionsKey = key
            pcall(function() teleStageDropdown:Refresh(fresh, true) end)
        end
    end
end)

teleportFarmToggle = DungeonTab:CreateToggle({
    Name = "Farm ที่ Stage นี้ (Teleport)",
    CurrentValue = false,
    Flag = "TeleportFarmEnabled",
    Callback = function(v)
        State.TeleportFarmEnabled = v
        if v then
            enableAutoAttack()
            State.AutoDungeon = false
            pcall(function() autoDungeonToggle:Set(false) end)
        end
    end,
})

DungeonTab:CreateSlider({
    Name = "ความสูงที่ลอยเหนือมอน",
    Range = { 4, 150 },
    Increment = 1,
    CurrentValue = 10,
    Flag = "HoverHeight",
    Callback = function(v) State.HoverHeight = v end,
})

DungeonTab:CreateSlider({
    Name = "HP% ต่ำกว่านี้ให้ Return",
    Range = { 10, 90 },
    Increment = 5,
    CurrentValue = 50,
    Flag = "HpReturnPercent",
    Callback = function(v) State.HpReturnPercent = v end,
})

DungeonTab:CreateParagraph({
    Title = "หมายเหตุ",
    Content = "ลอยเหนือมอนช่วยหลบมอนระยะประชิดได้ แต่มอนระยะไกลอาจยังโดนอยู่ - ถ้า HP ต่ำกว่าเกณฑ์ระบบจะ Return+ขายของ+รอฟื้นให้เอง ดู log ที่มุมซ้ายล่างจอ (กล่องดำ) เพื่อดูว่าระบบกำลังทำอะไรอยู่",
})

pcall(function()
    Rayfield:LoadConfiguration()
end)

debugLog("GUI ready. AutoSell=" .. tostring(State.AutoSell) .. " MaxSellPrice=" .. tostring(State.MaxSellPrice))
