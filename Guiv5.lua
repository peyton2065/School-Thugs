--[[
    MASS ATTACK PRO v3.1
    Production Combat Enhancement Suite
    Xeno Executor Compatible
    Insert      = Toggle GUI
    RightShift  = Toggle Script
]]

local SCRIPT_VERSION = "3.1"

----------------------------------------------------------------
-- 0. EXECUTOR DETECTION
----------------------------------------------------------------
local EXECUTOR_NAME = "Unknown"
local IS_XENO = false

pcall(function()
    if type(identifyexecutor) == "function" then
        EXECUTOR_NAME = identifyexecutor()
    elseif type(getexecutorname) == "function" then
        EXECUTOR_NAME = getexecutorname()
    end
end)

pcall(function()
    if Xeno and type(Xeno) == "table" then
        IS_XENO = true
        EXECUTOR_NAME = "Xeno"
        if Xeno.PID then
            print("[MAP] Xeno PID:", Xeno.PID)
        end
    end
end)

print("[MAP] Executor:", EXECUTOR_NAME, "| Xeno:", IS_XENO)

----------------------------------------------------------------
-- 0b. UNC SHIMS
----------------------------------------------------------------
if not cloneref then
    cloneref = function(obj) return obj end
end

if not getnilinstances then
    getnilinstances = function() return {} end
end

if not getinstances then
    getinstances = function() return {} end
end

----------------------------------------------------------------
-- 1. CLEANUP PREVIOUS INSTANCE
----------------------------------------------------------------
if _G._MassAttackPro then
    pcall(function()
        _G._MassAttackPro.Running = false
        for _, c in ipairs(_G._MassAttackPro.Connections or {}) do
            pcall(function() c:Disconnect() end)
        end
        local oldGui
        pcall(function()
            oldGui = game:GetService("CoreGui"):FindFirstChild("MassAttackPro")
        end)
        if not oldGui then
            pcall(function()
                local pg = game:GetService("Players").LocalPlayer
                    :FindFirstChild("PlayerGui")
                if pg then
                    oldGui = pg:FindFirstChild("MassAttackPro")
                end
            end)
        end
        if oldGui then oldGui:Destroy() end
    end)
    _G._MassAttackPro = nil
    task.wait(0.2)
end

----------------------------------------------------------------
-- 2. SERVICES
----------------------------------------------------------------
local Players      = cloneref(game:GetService("Players"))
local RepStorage   = cloneref(game:GetService("ReplicatedStorage"))
local UIS          = cloneref(game:GetService("UserInputService"))
local TweenService = cloneref(game:GetService("TweenService"))
local RunService   = cloneref(game:GetService("RunService"))

----------------------------------------------------------------
-- 3. PLAYER REFERENCES
----------------------------------------------------------------
local plr      = Players.LocalPlayer
local char     = plr.Character or plr.CharacterAdded:Wait()
local rootPart = char:WaitForChild("HumanoidRootPart", 10)
local humanoid = char:WaitForChild("Humanoid", 10)

----------------------------------------------------------------
-- 3b. GUI PARENTING (Xeno-compatible)
----------------------------------------------------------------
local function ParentGui(screenGui)
    local ok = pcall(function()
        screenGui.Parent = game:GetService("CoreGui")
    end)
    if ok and screenGui.Parent then return end

    ok = pcall(function()
        if type(gethui) == "function" then
            screenGui.Parent = gethui()
        else
            error()
        end
    end)
    if ok and screenGui.Parent then return end

    ok = pcall(function()
        if syn and syn.protect_gui then
            syn.protect_gui(screenGui)
            screenGui.Parent = game:GetService("CoreGui")
        else
            error()
        end
    end)
    if ok and screenGui.Parent then return end

    screenGui.Parent = plr:WaitForChild("PlayerGui")
end

----------------------------------------------------------------
-- 3c. XENO GLOBALS (config persistence)
----------------------------------------------------------------
local function XenoSaveConfig(cfg)
    pcall(function()
        if IS_XENO and Xeno.SetGlobal then
            local saveData = {}
            for k, v in pairs(cfg) do
                if type(v) == "number" or type(v) == "boolean" then
                    saveData[k] = tostring(v)
                end
            end
            Xeno.SetGlobal("MAP_Config", saveData)
        end
    end)
end

local function XenoLoadConfig(cfg)
    pcall(function()
        if IS_XENO and Xeno.GetGlobal then
            local saved = Xeno.GetGlobal("MAP_Config")
            if saved and type(saved) == "table" then
                for k, v in pairs(saved) do
                    if cfg[k] ~= nil then
                        if type(cfg[k]) == "boolean" then
                            cfg[k] = v == "true"
                        elseif type(cfg[k]) == "number" then
                            cfg[k] = tonumber(v) or cfg[k]
                        end
                    end
                end
            end
        end
    end)
end

local _lastSave = 0
local function AutoSave()
    if not IS_XENO then return end
    local now = tick()
    if now - _lastSave < 2 then return end
    _lastSave = now
    task.defer(function()
        XenoSaveConfig(CFG)
    end)
end

----------------------------------------------------------------
-- 4. CONFIGURATION
----------------------------------------------------------------
local CFG = {
    Enabled              = false,

    -- Combat
    AttacksPerSecond     = 8,
    TargetAll            = true,
    TargetPlayers        = true,
    TargetNPCs           = true,
    IgnoreForceField     = false,
    MinHealth            = 1,
    TargetPart           = "Head",
    MaxTargetsPerCycle   = 3,
    TargetUpdateInterval = 0.5,
    AttackRange          = 9999,

    -- Attacks
    UsePunch             = true,
    UseSuplex            = true,
    UseHeavyHit          = true,

    -- Tool / Weapon
    UseToolAttack        = true,
    PreferWeaponOverFist = true,

    -- Animation Cancel
    UseAnimCancel        = true,
    AnimCancelDelay      = 0.08,

    -- Stomp
    UseAutoStomp         = true,
    StompRange           = 15,
    StompCooldown        = 0.5,

    -- Stun
    UseAutoStun          = true,
    StunCooldown         = 1.0,
    StunRange            = 15,

    -- Guard
    UseAutoGuard         = true,
    GuardCooldown        = 0.10,
    GuardDropForAttack   = true,
    GuardReactivateDelay = 0.04,
    HealthPollInterval   = 0.05,
    GuardActivationRange = 50,

    -- Heal
    UseAutoHeal          = true,
    HealThreshold        = 60,
    HealCooldown         = 1.5,

    -- Auto Buy Food
    UseAutoBuyFood       = true,
    BuyFoodThreshold     = 40,
    BuyFoodCooldown      = 5.0,

    -- Pickup
    UseAutoPickupTools   = true,
    ToolPickupRange      = 40,
    ToolPickupCooldown   = 1.0,

    -- Carry + Throw
    UseAutoCarryThrow    = false,
    CarryThrowRange      = 15,
    CarryDuration        = 1.0,
    CarryThrowCooldown   = 2.0,

    -- Crouch Spam
    UseCrouchSpam        = false,
    CrouchSpamSpeed      = 0.15,

    -- PVP Toggle
    UseSmartPVP          = false,
    PVPOffThreshold      = 25,
    PVPOnThreshold       = 80,

    -- Admin
    UseAdminAbuse        = false,
    UseAdminAutoGod      = false,
    AdminSpamCooldown    = 2.0,
    AdminAutoGodInterval = 5.0,

    -- Kill All
    KillAllActive        = false,
    KillAllTimeout       = 8,
    KillAllTeleportDelay = 0.25,
    KillAllReteleportDist = 12,
    KillAllRetries       = 3,

    -- Keybinds
    GuiToggleKey         = Enum.KeyCode.Insert,
    ScriptToggleKey      = Enum.KeyCode.RightShift,

    Debug                = false,
}

----------------------------------------------------------------
-- 5. STATE
----------------------------------------------------------------
local ST = {
    Running          = true,
    StartTime        = tick(),
    GuardActive      = false,
    LastGuardTime    = 0,
    LastTargetUpdate = 0,
    TargetCache      = {},
    TargetIndex      = 1,
    TotalAttacks     = 0,
    TargetsFound     = 0,
    LastHealth       = humanoid and humanoid.Health or 100,
    Connections      = {},

    TotalStomps      = 0,
    LastStompTime    = 0,
    EnemyNearby      = false,

    TotalStuns       = 0,
    LastStunTime     = 0,

    LastHealTime     = 0,
    TotalHeals       = 0,
    AutoHealActive   = false,

    LastFoodBuy      = 0,
    TotalFoodBuys    = 0,

    LastToolPickup   = 0,
    TotalPickups     = 0,
    TotalToolHits    = 0,

    LastCarryTime    = 0,
    TotalThrows      = 0,
    IsCarrying       = false,

    PVPEnabled       = true,
    LastPVPToggle    = 0,

    AdminAttempts    = 0,
    AdminSuccesses   = 0,
    LastAdminFire    = 0,

    KillAllRunning   = false,
    KillAllTarget    = "",
    KillAllProgress  = "",
    KillAllKills     = 0,
}

local _nearbyCache = { result = false, lastCheck = 0, interval = 0.5 }

_G._MassAttackPro = ST

----------------------------------------------------------------
-- 6. UTILITIES
----------------------------------------------------------------
local function Conn(signal, fn)
    local c = signal:Connect(fn)
    table.insert(ST.Connections, c)
    return c
end

local function Log(...)
    if CFG.Debug then print("[MAP]", ...) end
end

local function SafeCall(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok and CFG.Debug then warn("[MAP ERROR]", err) end
    return ok, err
end

local function FormatTime(seconds)
    local m = math.floor(seconds / 60)
    local s = math.floor(seconds % 60)
    return string.format("%02d:%02d", m, s)
end

local function GetChar()
    char = plr.Character
    if char then
        rootPart = char:FindFirstChild("HumanoidRootPart")
        humanoid = char:FindFirstChildOfClass("Humanoid")
    end
    return char, rootPart, humanoid
end

----------------------------------------------------------------
-- 7. THEME
----------------------------------------------------------------
local CLR = {
    bg         = Color3.fromRGB(15, 15, 24),
    header     = Color3.fromRGB(22, 22, 36),
    headerGrad = Color3.fromRGB(30, 25, 50),
    card       = Color3.fromRGB(24, 24, 38),
    cardHover  = Color3.fromRGB(30, 30, 48),
    accent     = Color3.fromRGB(110, 68, 255),
    accentDim  = Color3.fromRGB(80, 50, 180),
    text       = Color3.fromRGB(235, 235, 245),
    textDim    = Color3.fromRGB(130, 130, 155),
    green      = Color3.fromRGB(45, 200, 95),
    red        = Color3.fromRGB(240, 60, 60),
    orange     = Color3.fromRGB(245, 170, 45),
    yellow     = Color3.fromRGB(245, 215, 50),
    cyan       = Color3.fromRGB(50, 195, 240),
    toggleOn   = Color3.fromRGB(45, 200, 95),
    toggleOff  = Color3.fromRGB(60, 60, 80),
    border     = Color3.fromRGB(42, 42, 62),
    sliderBg   = Color3.fromRGB(32, 32, 50),
    shadow     = Color3.fromRGB(0, 0, 0),
    notifBg    = Color3.fromRGB(28, 28, 44),
}

local TWEEN_FAST   = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TWEEN_SMOOTH = TweenInfo.new(0.20, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local TWEEN_BOUNCE = TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

----------------------------------------------------------------
-- 8. REMOTE DETECTION (Xeno-compatible)
----------------------------------------------------------------
local function FindRemote(name)
    local r

    local folder = RepStorage:FindFirstChild("MainEvents")
    if folder then
        r = folder:FindFirstChild(name)
        if r then return r end
    end

    r = RepStorage:FindFirstChild(name, true)
    if r then return r end

    pcall(function()
        for _, v in ipairs(getnilinstances()) do
            if v:IsA("RemoteEvent") and v.Name == name then
                r = v
            end
        end
    end)
    if r then return r end

    pcall(function()
        if type(getinstances) == "function" then
            for _, v in ipairs(getinstances()) do
                if v:IsA("RemoteEvent") and v.Name == name then
                    r = v
                end
            end
        end
    end)

    return r
end

local REM = {
    -- Combat (original)
    Punch    = FindRemote("PUNCHEVENT"),
    Suplex   = FindRemote("SUPLEXEVENT"),
    HeavyHit = FindRemote("HEAVYHIT"),
    Block    = FindRemote("BLOCKEVENT"),
    Stomp    = FindRemote("STOMPEVENT"),

    -- Combat (new)
    ToolHit  = FindRemote("TOOLHITEVENT"),
    Stun     = FindRemote("STUNEVENT"),

    -- Survival
    Heal       = FindRemote("HEALCHARACTERCARRIED"),
    Carniceria = FindRemote("Carniceria"),

    -- Movement / State
    Carry    = FindRemote("CARRYEVENT"),
    Throw    = FindRemote("THROWCHARACTEREVENT"),
    Crouch   = FindRemote("CROUCHEVENT"),
    StopAnim = FindRemote("STOPLOCALANIMATIONS"),

    -- Systems
    PVPToggle  = FindRemote("PVPONOFFEVENT"),
    PickupTool = FindRemote("PICKUPTOOLSEVENT"),

    -- Admin
    AdminCmd   = FindRemote("ADMINCOMMANDS"),
    AdminPanel = FindRemote("ADMINPANNEL"),
}

if not REM.Punch    then CFG.UsePunch     = false end
if not REM.Suplex   then CFG.UseSuplex    = false end
if not REM.HeavyHit then CFG.UseHeavyHit  = false end
if not REM.Block    then CFG.UseAutoGuard  = false end
if not REM.Stomp    then CFG.UseAutoStomp  = false end
if not REM.ToolHit  then CFG.UseToolAttack = false end
if not REM.Stun     then CFG.UseAutoStun   = false end
if not REM.StopAnim then CFG.UseAnimCancel = false end

local HAS_ATTACK = REM.Punch or REM.Suplex or REM.HeavyHit or REM.ToolHit

----------------------------------------------------------------
-- 9. CORE FUNCTIONS
----------------------------------------------------------------

-- 9a  Guard
local function SetGuard(state)
    if not CFG.UseAutoGuard or not REM.Block then return end
    local now = tick()
    if now - ST.LastGuardTime < CFG.GuardCooldown then return end
    if state == ST.GuardActive then return end
    local ok = SafeCall(function() REM.Block:FireServer(state) end)
    if ok then
        ST.GuardActive   = state
        ST.LastGuardTime = now
        Log(state and "Guard ON" or "Guard OFF")
    end
end

-- 9b  Validation
local function IsValid(model)
    if not model or not model.Parent then return false end
    local h = model:FindFirstChildOfClass("Humanoid")
    local r = model:FindFirstChild("HumanoidRootPart")
    if not h or not r then return false end
    if h.Health <= CFG.MinHealth then return false end
    if not CFG.IgnoreForceField
       and model:FindFirstChildWhichIsA("ForceField") then
        return false
    end
    return true
end

-- 9c  Targets
local function RefreshTargets()
    local list = {}
    local playerChars = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Character then playerChars[p.Character] = p end
    end
    if CFG.TargetPlayers then
        for c, p in pairs(playerChars) do
            if p ~= plr and IsValid(c) then list[#list + 1] = c end
        end
    end
    if CFG.TargetNPCs then
        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA("Model")
               and not playerChars[obj]
               and obj:FindFirstChildOfClass("Humanoid")
               and IsValid(obj) then
                list[#list + 1] = obj
            end
        end
    end
    ST.TargetCache      = list
    ST.TargetsFound     = #list
    ST.LastTargetUpdate = tick()
end

-- 9d  Attack (fully remote)
local function Attack(target)
    if not target or not target.Parent then return end
    local part = target:FindFirstChild(CFG.TargetPart)
              or target:FindFirstChild("UpperTorso")
              or target:FindFirstChild("HumanoidRootPart")
    if not part then return end

    -- Weapon attack via remote
    local usedTool = false
    if CFG.PreferWeaponOverFist and CFG.UseToolAttack and REM.ToolHit then
        SafeCall(function() REM.ToolHit:FireServer(target, part) end)
        SafeCall(function() REM.ToolHit:FireServer(1, target, 50, part) end)
        SafeCall(function() REM.ToolHit:FireServer(target, 50, part) end)
        ST.TotalToolHits = ST.TotalToolHits + 1
        usedTool = true
    end

    -- Fist attacks via remote
    if not usedTool or not CFG.PreferWeaponOverFist then
        if CFG.UsePunch and REM.Punch then
            SafeCall(function() REM.Punch:FireServer(1, target, 50, part) end)
        end
        if CFG.UseSuplex and REM.Suplex then
            SafeCall(function() REM.Suplex:FireServer(1, target, 50, part) end)
        end
        if CFG.UseHeavyHit and REM.HeavyHit then
            SafeCall(function() REM.HeavyHit:FireServer(1, target, 50, part) end)
        end
    end

    -- Animation cancel via remote
    if CFG.UseAnimCancel and REM.StopAnim then
        task.delay(CFG.AnimCancelDelay, function()
            SafeCall(function() REM.StopAnim:FireServer() end)
        end)
    end

    ST.TotalAttacks = ST.TotalAttacks + 1
end

-- 9e  Proximity (cached)
local function InvalidateNearbyCache()
    _nearbyCache.lastCheck = 0
end

local function IsEnemyNearby(range)
    local now = tick()
    if now - _nearbyCache.lastCheck < _nearbyCache.interval then
        return _nearbyCache.result
    end
    _nearbyCache.lastCheck = now
    if not rootPart or not rootPart.Parent then
        _nearbyCache.result = false
        return false
    end
    local pos = rootPart.Position
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= plr and p.Character then
            local r = p.Character:FindFirstChild("HumanoidRootPart")
            if r then
                local h = p.Character:FindFirstChildOfClass("Humanoid")
                if h and h.Health > 0 and (pos - r.Position).Magnitude <= range then
                    _nearbyCache.result = true
                    return true
                end
            end
        end
    end
    if CFG.TargetNPCs then
        for _, model in ipairs(ST.TargetCache) do
            if model and model.Parent
               and not Players:GetPlayerFromCharacter(model) then
                local r = model:FindFirstChild("HumanoidRootPart")
                if r and (pos - r.Position).Magnitude <= range then
                    _nearbyCache.result = true
                    return true
                end
            end
        end
    end
    _nearbyCache.result = false
    return false
end

-- 9f  Downed detection
local DOWNED_ATTRIBUTES = {
    "Ragdolled","KnockedDown","Downed","Stunned",
    "IsDown","Ragdoll","IsRagdoll","KO",
}

local function IsPlayerDown(character)
    if not character or not character.Parent then return false end
    local hum = character:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return false end
    local state = hum:GetState()
    if state == Enum.HumanoidStateType.Physics
    or state == Enum.HumanoidStateType.FallingDown
    or state == Enum.HumanoidStateType.PlatformStanding then
        return true
    end
    if hum.PlatformStand then return true end
    for _, child in ipairs(character:GetChildren()) do
        if child:IsA("BoolValue") then
            local n = child.Name:lower()
            if (n:find("ragdoll") or n:find("knocked")
                or n:find("down") or n:find("stun"))
               and child.Value then
                return true
            end
        elseif child:IsA("StringValue") then
            local v = child.Value:lower()
            if v == "down" or v == "knocked" or v == "ragdoll" then
                return true
            end
        end
    end
    for _, attr in ipairs(DOWNED_ATTRIBUTES) do
        if character:GetAttribute(attr) == true then return true end
    end
    return false
end

-- 9g  Stomp (remote only)
local function TryStomp()
    if not CFG.UseAutoStomp or not REM.Stomp then return end
    local now = tick()
    if now - ST.LastStompTime < CFG.StompCooldown then return end
    if not rootPart or not rootPart.Parent then return end
    local pos = rootPart.Position
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= plr and p.Character then
            local r = p.Character:FindFirstChild("HumanoidRootPart")
            if r and (pos - r.Position).Magnitude <= CFG.StompRange
               and IsPlayerDown(p.Character) then
                local ok = SafeCall(function() REM.Stomp:FireServer() end)
                if ok then
                    ST.TotalStomps  = ST.TotalStomps + 1
                    ST.LastStompTime = now
                    Log("Stomp! Total:", ST.TotalStomps)
                end
                return
            end
        end
    end
end

-- 9h  Stun (remote only)
local function TryStun()
    if not CFG.UseAutoStun or not REM.Stun then return end
    local now = tick()
    if now - ST.LastStunTime < CFG.StunCooldown then return end
    if not rootPart or not rootPart.Parent then return end
    local pos = rootPart.Position
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= plr and p.Character then
            local h = p.Character:FindFirstChildOfClass("Humanoid")
            local r = p.Character:FindFirstChild("HumanoidRootPart")
            if h and r and h.Health > 0
               and (pos - r.Position).Magnitude <= CFG.StunRange
               and not IsPlayerDown(p.Character) then
                SafeCall(function() REM.Stun:FireServer(p.Character) end)
                SafeCall(function() REM.Stun:FireServer(p) end)
                SafeCall(function() REM.Stun:FireServer(r) end)
                ST.TotalStuns = ST.TotalStuns + 1
                ST.LastStunTime = now
                Log("Stunned:", p.Name)
                return
            end
        end
    end
end

-- 9i  Heal (remote only)
local function TryHeal()
    if not CFG.UseAutoHeal then return end
    if not humanoid or humanoid.Health <= 0 then return end
    local now = tick()
    if now - ST.LastHealTime < CFG.HealCooldown then return end
    local hpPercent = (humanoid.Health / humanoid.MaxHealth) * 100
    if hpPercent > CFG.HealThreshold then
        ST.AutoHealActive = false
        return
    end
    ST.AutoHealActive = true
    Log("Auto Heal: HP at " .. math.floor(hpPercent) .. "%")
    local healed = false
    if REM.Heal then
        SafeCall(function() REM.Heal:FireServer() end)
        SafeCall(function() REM.Heal:FireServer(char) end)
        SafeCall(function() REM.Heal:FireServer(plr) end)
        SafeCall(function() REM.Heal:FireServer(plr, char) end)
        healed = true
    end
    if healed then
        ST.TotalHeals = ST.TotalHeals + 1
        ST.LastHealTime = now
    end
end

-- 9j  Buy Food (remote only)
local function TryBuyFood()
    if not CFG.UseAutoBuyFood or not REM.Carniceria then return end
    if not humanoid or humanoid.Health <= 0 then return end
    local now = tick()
    if now - ST.LastFoodBuy < CFG.BuyFoodCooldown then return end
    local hpPercent = (humanoid.Health / humanoid.MaxHealth) * 100
    if hpPercent > CFG.BuyFoodThreshold then return end
    SafeCall(function() REM.Carniceria:FireServer() end)
    SafeCall(function() REM.Carniceria:FireServer("Buy") end)
    SafeCall(function() REM.Carniceria:FireServer(1) end)
    SafeCall(function() REM.Carniceria:FireServer("Food") end)
    SafeCall(function() REM.Carniceria:FireServer("Heal") end)
    ST.TotalFoodBuys = ST.TotalFoodBuys + 1
    ST.LastFoodBuy = now
    Log("Carniceria: attempted food purchase")
end

-- 9k  Pickup Tools (remote only)
local function TryPickupTools()
    if not CFG.UseAutoPickupTools or not REM.PickupTool then return end
    local now = tick()
    if now - ST.LastToolPickup < CFG.ToolPickupCooldown then return end
    if not rootPart or not rootPart.Parent then return end
    local pos = rootPart.Position
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("Tool") then
            local handle = obj:FindFirstChild("Handle")
            if handle and (pos - handle.Position).Magnitude <= CFG.ToolPickupRange then
                SafeCall(function() REM.PickupTool:FireServer(obj) end)
                SafeCall(function() REM.PickupTool:FireServer(obj.Name) end)
                SafeCall(function() REM.PickupTool:FireServer(obj, handle) end)
                SafeCall(function() REM.PickupTool:FireServer(handle) end)
                ST.TotalPickups = ST.TotalPickups + 1
                ST.LastToolPickup = now
                Log("Picked up:", obj.Name)
                return
            end
        end
        if obj:IsA("Model") and obj.Parent == workspace then
            local primary = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")
            if primary and (pos - primary.Position).Magnitude <= CFG.ToolPickupRange then
                local n = obj.Name:lower()
                if n:find("bat") or n:find("weapon") or n:find("knife")
                or n:find("gun") or n:find("tool") or n:find("item")
                or n:find("sword") or n:find("pipe") or n:find("metal") then
                    SafeCall(function() REM.PickupTool:FireServer(obj) end)
                    SafeCall(function() REM.PickupTool:FireServer(obj.Name) end)
                    SafeCall(function() REM.PickupTool:FireServer(primary) end)
                    ST.TotalPickups = ST.TotalPickups + 1
                    ST.LastToolPickup = now
                    Log("Picked up model:", obj.Name)
                    return
                end
            end
        end
    end
end

-- 9l  Carry + Throw (remote only)
local function TryCarryThrow()
    if not CFG.UseAutoCarryThrow then return end
    if not REM.Carry or not REM.Throw then return end
    if ST.IsCarrying then return end
    local now = tick()
    if now - ST.LastCarryTime < CFG.CarryThrowCooldown then return end
    if not rootPart or not rootPart.Parent then return end
    local pos = rootPart.Position
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= plr and p.Character then
            local r = p.Character:FindFirstChild("HumanoidRootPart")
            if r and (pos - r.Position).Magnitude <= CFG.CarryThrowRange
               and IsPlayerDown(p.Character) then
                ST.IsCarrying = true
                Log("Carry+Throw:", p.Name)
                SafeCall(function() REM.Carry:FireServer(p.Character) end)
                SafeCall(function() REM.Carry:FireServer(p) end)
                SafeCall(function() REM.Carry:FireServer(r) end)
                task.wait(CFG.CarryDuration)
                SafeCall(function() REM.Throw:FireServer() end)
                SafeCall(function() REM.Throw:FireServer(rootPart.CFrame.LookVector) end)
                SafeCall(function() REM.Throw:FireServer(p.Character) end)
                ST.TotalThrows = ST.TotalThrows + 1
                ST.LastCarryTime = tick()
                ST.IsCarrying = false
                Log("Threw:", p.Name)
                return
            end
        end
    end
end

-- 9m  Smart PVP (remote only)
local function ManagePVP()
    if not CFG.UseSmartPVP or not REM.PVPToggle then return end
    if not humanoid or humanoid.Health <= 0 then return end
    local now = tick()
    if now - ST.LastPVPToggle < 1.0 then return end
    local hpPercent = (humanoid.Health / humanoid.MaxHealth) * 100
    if hpPercent <= CFG.PVPOffThreshold and ST.PVPEnabled then
        SafeCall(function() REM.PVPToggle:FireServer(false) end)
        SafeCall(function() REM.PVPToggle:FireServer("Off") end)
        SafeCall(function() REM.PVPToggle:FireServer(0) end)
        ST.PVPEnabled = false
        ST.LastPVPToggle = now
        Log("Smart PVP: OFF")
    elseif hpPercent >= CFG.PVPOnThreshold and not ST.PVPEnabled then
        SafeCall(function() REM.PVPToggle:FireServer(true) end)
        SafeCall(function() REM.PVPToggle:FireServer("On") end)
        SafeCall(function() REM.PVPToggle:FireServer(1) end)
        ST.PVPEnabled = true
        ST.LastPVPToggle = now
        Log("Smart PVP: ON")
    end
end

-- 9n  Admin Commands (remote only)
local function FireAdminCommand(command, target, value)
    if not REM.AdminCmd and not REM.AdminPanel then return end
    ST.AdminAttempts = ST.AdminAttempts + 1

    if REM.AdminCmd then
        SafeCall(function() REM.AdminCmd:FireServer(command) end)
        SafeCall(function() REM.AdminCmd:FireServer(command, target) end)
        SafeCall(function() REM.AdminCmd:FireServer(command, target, value) end)
        SafeCall(function()
            REM.AdminCmd:FireServer({
                Command = command,
                Target  = target,
                Value   = value,
            })
        end)
        SafeCall(function()
            REM.AdminCmd:FireServer("/" .. command .. " " .. tostring(target or ""))
        end)
        SafeCall(function()
            REM.AdminCmd:FireServer(":" .. command .. " " .. tostring(target or ""))
        end)
        if target and type(target) == "string" then
            local targetPlayer = nil
            for _, p in ipairs(Players:GetPlayers()) do
                if p.Name:lower():find(target:lower()) then
                    targetPlayer = p
                    break
                end
            end
            if targetPlayer then
                SafeCall(function() REM.AdminCmd:FireServer(command, targetPlayer) end)
                SafeCall(function() REM.AdminCmd:FireServer(command, targetPlayer.Name) end)
                SafeCall(function() REM.AdminCmd:FireServer(command, targetPlayer.UserId) end)
                SafeCall(function() REM.AdminCmd:FireServer(command, targetPlayer, value) end)
            end
        end
    end

    if REM.AdminPanel then
        SafeCall(function() REM.AdminPanel:FireServer(command) end)
        SafeCall(function() REM.AdminPanel:FireServer(command, target) end)
        SafeCall(function() REM.AdminPanel:FireServer(command, target, value) end)
        SafeCall(function()
            REM.AdminPanel:FireServer({
                Command = command,
                Target  = target,
                Value   = value,
            })
        end)
        SafeCall(function() REM.AdminPanel:FireServer(command, plr) end)
        SafeCall(function() REM.AdminPanel:FireServer(command, target, value, plr) end)
    end

    Log("Admin:", command, tostring(target), tostring(value))
end

local function AdminSelfBuff()
    if not CFG.UseAdminAbuse then return end
    local now = tick()
    if now - ST.LastAdminFire < CFG.AdminSpamCooldown then return end
    ST.LastAdminFire = now
    local me = plr.Name

    FireAdminCommand("god", me)
    FireAdminCommand("godmode", me)
    FireAdminCommand("heal", me)
    FireAdminCommand("heal", me, 999999)
    FireAdminCommand("health", me, 999999)
    FireAdminCommand("maxhealth", me, 999999)
    FireAdminCommand("sethealth", me, 999999)
    FireAdminCommand("sethp", me, 999999)
    FireAdminCommand("invincible", me)
    FireAdminCommand("speed", me, 100)
    FireAdminCommand("walkspeed", me, 100)
    FireAdminCommand("ws", me, 100)
    FireAdminCommand("jumppower", me, 200)
    FireAdminCommand("jp", me, 200)
    FireAdminCommand("give", me, "MetalBat")
    FireAdminCommand("give", me, "Metal Bat")
    FireAdminCommand("give", me, "Bat")
    FireAdminCommand("giveall", me)
    FireAdminCommand("givetools", me)
    FireAdminCommand("givemoney", me, 999999)
    FireAdminCommand("money", me, 999999)
    FireAdminCommand("setmoney", me, 999999)
    FireAdminCommand("cash", me, 999999)
    FireAdminCommand("addmoney", me, 999999)
    FireAdminCommand("size", me, 5)
    FireAdminCommand("setsize", me, 5)
    FireAdminCommand("scale", me, 5)
    FireAdminCommand("damage", me, 999)
    FireAdminCommand("strength", me, 999)
    FireAdminCommand("power", me, 999)
    FireAdminCommand("givemutation", me)
    FireAdminCommand("giveaura", me)
    FireAdminCommand("mutation", me, "All")
    FireAdminCommand("aura", me, "All")

    Log("Admin: self-buff volley fired")
end

local function AdminTargetPlayer(targetName, action)
    if not CFG.UseAdminAbuse then return end
    if action == "kill" then
        FireAdminCommand("kill", targetName)
        FireAdminCommand("slay", targetName)
        FireAdminCommand("smite", targetName)
        FireAdminCommand("explode", targetName)
        FireAdminCommand("sethealth", targetName, 0)
        FireAdminCommand("damage", targetName, 999999)
    elseif action == "kick" then
        FireAdminCommand("kick", targetName)
        FireAdminCommand("kick", targetName, "Kicked")
        FireAdminCommand("remove", targetName)
        FireAdminCommand("disconnect", targetName)
    elseif action == "ban" then
        FireAdminCommand("ban", targetName)
        FireAdminCommand("ban", targetName, "Banned")
        FireAdminCommand("permban", targetName)
    elseif action == "freeze" then
        FireAdminCommand("freeze", targetName)
        FireAdminCommand("stun", targetName)
        FireAdminCommand("lock", targetName)
        FireAdminCommand("anchor", targetName)
    elseif action == "teleport" then
        FireAdminCommand("tp", targetName, plr.Name)
        FireAdminCommand("bring", targetName)
        FireAdminCommand("teleport", targetName, plr.Name)
        FireAdminCommand("summon", targetName)
    end
    Log("Admin: targeted", targetName, "with", action)
end

local function AdminServerCommand(action)
    if not CFG.UseAdminAbuse then return end
    if action == "killall" then
        FireAdminCommand("killall")
        FireAdminCommand("kill", "all")
        FireAdminCommand("kill", "others")
        FireAdminCommand("slay", "all")
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= plr then
                FireAdminCommand("kill", p.Name)
            end
        end
    elseif action == "kickall" then
        FireAdminCommand("kickall")
        FireAdminCommand("kick", "all")
        FireAdminCommand("kick", "others")
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= plr then
                FireAdminCommand("kick", p.Name)
            end
        end
    elseif action == "healall" then
        FireAdminCommand("healall")
        FireAdminCommand("heal", "all")
    elseif action == "shutdown" then
        FireAdminCommand("shutdown")
        FireAdminCommand("stop")
        FireAdminCommand("shutdownserver")
    elseif action == "lockserver" then
        FireAdminCommand("lock")
        FireAdminCommand("lockserver")
        FireAdminCommand("slock")
        FireAdminCommand("serverlock")
    end
    Log("Admin: server command:", action)
end

-- Forward declaration for notifications
local Notify = function() end

-- 9o  Kill All
local function RunKillAll()
    if not HAS_ATTACK then
        Notify("No attack remotes found", "error")
        return
    end
    ST.KillAllRunning = true
    Notify("Kill All engaged", "warning", 2)
    Log("Kill All: STARTED")

    while CFG.KillAllActive and CFG.Enabled and ST.Running do
        GetChar()
        if not rootPart or not rootPart.Parent then
            ST.KillAllTarget = "Respawning..."
            task.wait(1)
            continue
        end

        local targets = {}
        local myPos = rootPart.Position
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= plr and p.Character then
                local h = p.Character:FindFirstChildOfClass("Humanoid")
                local r = p.Character:FindFirstChild("HumanoidRootPart")
                if h and r and h.Health > 0 then
                    targets[#targets + 1] = {
                        player = p,
                        dist   = (myPos - r.Position).Magnitude,
                    }
                end
            end
        end

        if #targets == 0 then
            ST.KillAllTarget   = "No targets"
            ST.KillAllProgress = "0/0"
            task.wait(1.5)
            continue
        end

        table.sort(targets, function(a, b) return a.dist < b.dist end)

        for i, entry in ipairs(targets) do
            if not CFG.KillAllActive or not CFG.Enabled or not ST.Running then
                break
            end

            local target = entry.player
            local tChar  = target.Character
            if not tChar then continue end
            local tRoot = tChar:FindFirstChild("HumanoidRootPart")
            local tHum  = tChar:FindFirstChildOfClass("Humanoid")
            if not tRoot or not tHum or tHum.Health <= 0 then continue end

            ST.KillAllTarget   = target.Name
            ST.KillAllProgress = i .. "/" .. #targets

            GetChar()
            if rootPart and rootPart.Parent then
                rootPart.CFrame = tRoot.CFrame * CFrame.new(0, 0, 3)
                InvalidateNearbyCache()
            end
            task.wait(CFG.KillAllTeleportDelay)

            GetChar()
            if rootPart and rootPart.Parent and tRoot and tRoot.Parent then
                local postDist = (rootPart.Position - tRoot.Position).Magnitude
                if postDist > CFG.KillAllReteleportDist then
                    for _ = 1, CFG.KillAllRetries do
                        rootPart.CFrame = tRoot.CFrame * CFrame.new(0, 0, 3)
                        task.wait(0.1)
                        if (rootPart.Position - tRoot.Position).Magnitude
                           <= CFG.KillAllReteleportDist then
                            break
                        end
                    end
                end
            end

            local startTime = tick()
            while CFG.KillAllActive and CFG.Enabled and ST.Running do
                tChar = target.Character
                if not tChar then break end
                tHum  = tChar:FindFirstChildOfClass("Humanoid")
                tRoot = tChar:FindFirstChild("HumanoidRootPart")
                if not tHum or tHum.Health <= 0 or not tRoot then break end

                GetChar()
                if not rootPart or not rootPart.Parent then break end

                if tick() - startTime > CFG.KillAllTimeout then
                    Log("Kill All: timeout on", target.Name)
                    break
                end

                local dist = (rootPart.Position - tRoot.Position).Magnitude
                if dist > CFG.KillAllReteleportDist then
                    rootPart.CFrame = tRoot.CFrame * CFrame.new(0, 0, 3)
                    InvalidateNearbyCache()
                    task.wait(0.05)
                end

                Attack(tChar)

                if CFG.UseAutoStomp and REM.Stomp and IsPlayerDown(tChar) then
                    SafeCall(function() REM.Stomp:FireServer() end)
                    ST.TotalStomps = ST.TotalStomps + 1
                end

                task.wait(1 / math.max(CFG.AttacksPerSecond, 1))
            end

            local killed = false
            SafeCall(function()
                local tc = target.Character
                if tc then
                    local th = tc:FindFirstChildOfClass("Humanoid")
                    if th and th.Health <= 0 then killed = true end
                end
            end)
            if killed then
                ST.KillAllKills = ST.KillAllKills + 1
                Notify("Killed " .. target.Name .. " (" .. ST.KillAllKills .. " total)", "success", 2.5)
            end

            if CFG.KillAllActive and CFG.Enabled and ST.Running then
                task.wait(CFG.KillAllTeleportDelay)
            end
        end

        if CFG.KillAllActive and CFG.Enabled and ST.Running then
            ST.KillAllTarget = "Scanning..."
            ST.KillAllProgress = ""
            task.wait(1.5)
        end
    end

    ST.KillAllRunning  = false
    ST.KillAllTarget   = ""
    ST.KillAllProgress = ""
    Notify("Kill All disengaged", "info", 2)
    Log("Kill All: STOPPED")
end

----------------------------------------------------------------
-- 10. GUI
----------------------------------------------------------------
local GUI_REFS

local function BuildGUI()
    local existing
    pcall(function()
        existing = game:GetService("CoreGui"):FindFirstChild("MassAttackPro")
    end)
    if not existing then
        existing = plr:FindFirstChild("PlayerGui")
                   and plr.PlayerGui:FindFirstChild("MassAttackPro")
    end
    if existing then existing:Destroy() end

    local sg = Instance.new("ScreenGui")
    sg.Name            = "MassAttackPro"
    sg.ResetOnSpawn    = false
    sg.ZIndexBehavior  = Enum.ZIndexBehavior.Sibling
    sg.DisplayOrder    = 999

    ParentGui(sg)

    -- HELPERS
    local function Corner(p, r)
        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, r or 8); c.Parent = p
    end

    local function Stroke(p, col, t)
        local s = Instance.new("UIStroke")
        s.Color = col or CLR.border; s.Thickness = t or 1
        s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        s.Parent = p
    end

    local function Hover(element, normal, hovered)
        element.MouseEnter:Connect(function()
            TweenService:Create(element, TWEEN_FAST,
                {BackgroundColor3 = hovered}):Play()
        end)
        element.MouseLeave:Connect(function()
            TweenService:Create(element, TWEEN_FAST,
                {BackgroundColor3 = normal}):Play()
        end)
    end

    -- NOTIFICATION SYSTEM
    local notifContainer = Instance.new("Frame")
    notifContainer.Name = "Notifications"
    notifContainer.Size = UDim2.new(0, 260, 1, -20)
    notifContainer.Position = UDim2.new(1, -270, 0, 10)
    notifContainer.BackgroundTransparency = 1
    notifContainer.Parent = sg

    local notifLayout = Instance.new("UIListLayout")
    notifLayout.SortOrder = Enum.SortOrder.LayoutOrder
    notifLayout.Padding = UDim.new(0, 6)
    notifLayout.VerticalAlignment = Enum.VerticalAlignment.Top
    notifLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
    notifLayout.Parent = notifContainer

    local _notifOrder = 0
    local NOTIF_COLORS = {
        success = CLR.green,
        error   = CLR.red,
        warning = CLR.orange,
        info    = CLR.accent,
    }

    Notify = function(msgText, nType, duration)
        SafeCall(function()
            duration = duration or 3
            _notifOrder = _notifOrder + 1
            local col = NOTIF_COLORS[nType] or CLR.accent

            local frame = Instance.new("Frame")
            frame.Size = UDim2.new(1, 0, 0, 36)
            frame.BackgroundColor3 = CLR.notifBg
            frame.BackgroundTransparency = 1
            frame.BorderSizePixel = 0
            frame.LayoutOrder = _notifOrder
            frame.ClipsDescendants = true
            frame.Parent = notifContainer
            Corner(frame, 8)

            local accentBar = Instance.new("Frame")
            accentBar.Size = UDim2.new(0, 3, 1, -10)
            accentBar.Position = UDim2.new(0, 5, 0, 5)
            accentBar.BackgroundColor3 = col
            accentBar.BorderSizePixel = 0
            accentBar.Parent = frame
            Corner(accentBar, 2)

            local icon = Instance.new("TextLabel")
            icon.Size = UDim2.new(0, 16, 1, 0)
            icon.Position = UDim2.new(0, 14, 0, 0)
            icon.BackgroundTransparency = 1
            icon.Text = nType == "success" and "✓"
                     or nType == "error" and "✗"
                     or nType == "warning" and "⚠"
                     or "ℹ"
            icon.TextColor3 = col
            icon.TextSize = 12
            icon.Font = Enum.Font.GothamBold
            icon.Parent = frame

            local label = Instance.new("TextLabel")
            label.Size = UDim2.new(1, -38, 1, 0)
            label.Position = UDim2.new(0, 32, 0, 0)
            label.BackgroundTransparency = 1
            label.Text = msgText
            label.TextColor3 = CLR.text
            label.TextSize = 11
            label.Font = Enum.Font.Gotham
            label.TextXAlignment = Enum.TextXAlignment.Left
            label.TextTruncate = Enum.TextTruncate.AtEnd
            label.Parent = frame

            Stroke(frame, col, 1)

            TweenService:Create(frame, TweenInfo.new(0.3, Enum.EasingStyle.Quint),
                {BackgroundTransparency = 0.05}):Play()

            task.delay(duration, function()
                if frame and frame.Parent then
                    TweenService:Create(frame,
                        TweenInfo.new(0.4, Enum.EasingStyle.Quint),
                        {BackgroundTransparency = 1}):Play()
                    task.wait(0.4)
                    if frame and frame.Parent then frame:Destroy() end
                end
            end)
        end)
    end

    -- MAIN FRAME
    local main = Instance.new("Frame")
    main.Name = "Main"
    main.Size     = UDim2.new(0, 380, 0, 680)
    main.Position = UDim2.new(0.5, -190, 0.5, -340)
    main.BackgroundColor3 = CLR.bg
    main.BorderSizePixel  = 0
    main.ClipsDescendants = true
    main.Active = true
    main.Parent = sg
    Corner(main, 12)
    Stroke(main, CLR.border, 1)

    local sh = Instance.new("ImageLabel")
    sh.Size = UDim2.new(1, 50, 1, 50)
    sh.Position = UDim2.new(0, -25, 0, -25)
    sh.BackgroundTransparency = 1
    sh.Image = "rbxassetid://6015897843"
    sh.ImageColor3 = CLR.shadow
    sh.ImageTransparency = 0.4
    sh.ScaleType = Enum.ScaleType.Slice
    sh.SliceCenter = Rect.new(49, 49, 450, 450)
    sh.ZIndex = -1; sh.Parent = main

    -- HEADER
    local hdr = Instance.new("Frame")
    hdr.Name = "Header"
    hdr.Size = UDim2.new(1, 0, 0, 46)
    hdr.BackgroundColor3 = CLR.header
    hdr.BorderSizePixel = 0; hdr.Parent = main
    Corner(hdr, 12)

    local grad = Instance.new("UIGradient")
    grad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, CLR.headerGrad),
        ColorSequenceKeypoint.new(1, CLR.header),
    })
    grad.Rotation = 90; grad.Parent = hdr

    local hdrFix = Instance.new("Frame")
    hdrFix.Size = UDim2.new(1, 0, 0, 14)
    hdrFix.Position = UDim2.new(0, 0, 1, -14)
    hdrFix.BackgroundColor3 = CLR.header
    hdrFix.BorderSizePixel = 0; hdrFix.Parent = hdr

    local sep = Instance.new("Frame")
    sep.Size = UDim2.new(1, -16, 0, 1)
    sep.Position = UDim2.new(0, 8, 1, 0)
    sep.BackgroundColor3 = CLR.border
    sep.BorderSizePixel = 0; sep.Parent = hdr

    local ttl = Instance.new("TextLabel")
    ttl.Size = UDim2.new(1, -120, 1, 0)
    ttl.Position = UDim2.new(0, 14, 0, 0)
    ttl.BackgroundTransparency = 1
    ttl.Text = "⚔  MASS ATTACK PRO"
    ttl.TextColor3 = CLR.text; ttl.TextSize = 15
    ttl.Font = Enum.Font.GothamBold
    ttl.TextXAlignment = Enum.TextXAlignment.Left; ttl.Parent = hdr

    local verBadge = Instance.new("TextLabel")
    verBadge.Size = UDim2.new(0, 36, 0, 16)
    verBadge.Position = UDim2.new(0, 180, 0.5, -8)
    verBadge.BackgroundColor3 = CLR.accent
    verBadge.Text = "v" .. SCRIPT_VERSION
    verBadge.TextColor3 = CLR.text
    verBadge.TextSize = 9
    verBadge.Font = Enum.Font.GothamBold; verBadge.Parent = hdr
    Corner(verBadge, 5)

    local minB = Instance.new("TextButton")
    minB.Size = UDim2.new(0, 28, 0, 28)
    minB.Position = UDim2.new(1, -68, 0.5, -14)
    minB.BackgroundColor3 = CLR.orange; minB.Text = "—"
    minB.TextColor3 = CLR.text; minB.TextSize = 14
    minB.Font = Enum.Font.GothamBold
    minB.AutoButtonColor = false; minB.Parent = hdr
    Corner(minB, 7)
    Hover(minB, CLR.orange, Color3.fromRGB(255, 195, 60))

    local clsB = Instance.new("TextButton")
    clsB.Size = UDim2.new(0, 28, 0, 28)
    clsB.Position = UDim2.new(1, -36, 0.5, -14)
    clsB.BackgroundColor3 = CLR.red; clsB.Text = "✕"
    clsB.TextColor3 = CLR.text; clsB.TextSize = 11
    clsB.Font = Enum.Font.GothamBold
    clsB.AutoButtonColor = false; clsB.Parent = hdr
    Corner(clsB, 7)
    Hover(clsB, CLR.red, Color3.fromRGB(255, 85, 85))

    -- DRAGGING
    do
        local dragging, dInput, dStart, sPos
        Conn(hdr.InputBegan, function(inp)
            if inp.UserInputType == Enum.UserInputType.MouseButton1
            or inp.UserInputType == Enum.UserInputType.Touch then
                dragging = true; dStart = inp.Position; sPos = main.Position
                inp.Changed:Connect(function()
                    if inp.UserInputState == Enum.UserInputState.End then
                        dragging = false
                    end
                end)
            end
        end)
        Conn(hdr.InputChanged, function(inp)
            if inp.UserInputType == Enum.UserInputType.MouseMovement
            or inp.UserInputType == Enum.UserInputType.Touch then
                dInput = inp
            end
        end)
        Conn(UIS.InputChanged, function(inp)
            if inp == dInput and dragging then
                local d = inp.Position - dStart
                main.Position = UDim2.new(
                    sPos.X.Scale, sPos.X.Offset + d.X,
                    sPos.Y.Scale, sPos.Y.Offset + d.Y
                )
            end
        end)
    end

    -- SCROLL CONTENT
    local scroll = Instance.new("ScrollingFrame")
    scroll.Name = "Content"
    scroll.Size     = UDim2.new(1, -14, 1, -54)
    scroll.Position = UDim2.new(0, 7, 0, 50)
    scroll.BackgroundTransparency = 1
    scroll.BorderSizePixel = 0
    scroll.ScrollBarThickness = 3
    scroll.ScrollBarImageColor3 = CLR.accent
    scroll.ScrollBarImageTransparency = 0.35
    scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scroll.Parent = main

    local lay = Instance.new("UIListLayout")
    lay.SortOrder = Enum.SortOrder.LayoutOrder
    lay.Padding = UDim.new(0, 5)
    lay.Parent = scroll

    local scrollPad = Instance.new("UIPadding")
    scrollPad.PaddingBottom = UDim.new(0, 12)
    scrollPad.Parent = scroll

    local _ord = 0
    local function nxt() _ord = _ord + 1; return _ord end

    -- SECTION BUILDER
    local function Section(name)
        local f = Instance.new("Frame")
        f.Size = UDim2.new(1, 0, 0, 26)
        f.BackgroundTransparency = 1
        f.LayoutOrder = nxt(); f.Parent = scroll

        local l = Instance.new("TextLabel")
        l.Size = UDim2.new(1, -10, 1, 0)
        l.Position = UDim2.new(0, 5, 0, 0)
        l.BackgroundTransparency = 1
        l.Text = "  " .. string.upper(name)
        l.TextColor3 = CLR.accent; l.TextSize = 10
        l.Font = Enum.Font.GothamBold
        l.TextXAlignment = Enum.TextXAlignment.Left; l.Parent = f

        local ln = Instance.new("Frame")
        ln.Size = UDim2.new(1, -10, 0, 1)
        ln.Position = UDim2.new(0, 5, 1, -1)
        ln.BackgroundColor3 = CLR.border
        ln.BorderSizePixel = 0; ln.Parent = f
    end

    -- TOGGLE BUILDER
    local function Toggle(label, def, cb)
        local f = Instance.new("Frame")
        f.Size = UDim2.new(1, 0, 0, 34)
        f.BackgroundColor3 = CLR.card
        f.BorderSizePixel = 0
        f.LayoutOrder = nxt(); f.Parent = scroll
        Corner(f, 8)
        Hover(f, CLR.card, CLR.cardHover)

        local tl = Instance.new("TextLabel")
        tl.Size = UDim2.new(1, -64, 1, 0)
        tl.Position = UDim2.new(0, 12, 0, 0)
        tl.BackgroundTransparency = 1; tl.Text = label
        tl.TextColor3 = CLR.text; tl.TextSize = 12
        tl.Font = Enum.Font.Gotham
        tl.TextXAlignment = Enum.TextXAlignment.Left
        tl.TextTruncate = Enum.TextTruncate.AtEnd; tl.Parent = f

        local bg = Instance.new("Frame")
        bg.Size = UDim2.new(0, 42, 0, 20)
        bg.Position = UDim2.new(1, -52, 0.5, -10)
        bg.BackgroundColor3 = def and CLR.toggleOn or CLR.toggleOff
        bg.BorderSizePixel = 0; bg.Parent = f
        Corner(bg, 10)

        local dot = Instance.new("Frame")
        dot.Size = UDim2.new(0, 16, 0, 16)
        dot.Position = def and UDim2.new(1, -18, 0.5, -8)
                            or UDim2.new(0, 2, 0.5, -8)
        dot.BackgroundColor3 = Color3.new(1, 1, 1)
        dot.BorderSizePixel = 0; dot.Parent = bg
        Corner(dot, 8)

        local dotShadow = Instance.new("ImageLabel")
        dotShadow.Size = UDim2.new(1, 6, 1, 6)
        dotShadow.Position = UDim2.new(0, -3, 0, -1)
        dotShadow.BackgroundTransparency = 1
        dotShadow.Image = "rbxassetid://6015897843"
        dotShadow.ImageColor3 = CLR.shadow
        dotShadow.ImageTransparency = 0.7
        dotShadow.ScaleType = Enum.ScaleType.Slice
        dotShadow.SliceCenter = Rect.new(49, 49, 450, 450)
        dotShadow.ZIndex = -1; dotShadow.Parent = dot

        local st = def
        local api = {}

        function api.Set(v)
            st = v
            TweenService:Create(bg, TWEEN_SMOOTH,
                {BackgroundColor3 = st and CLR.toggleOn or CLR.toggleOff}):Play()
            TweenService:Create(dot, TWEEN_BOUNCE,
                {Position = st and UDim2.new(1, -18, 0.5, -8)
                                or UDim2.new(0, 2, 0.5, -8)}):Play()
        end
        function api.Get() return st end

        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, 0, 1, 0)
        btn.BackgroundTransparency = 1
        btn.Text = ""; btn.Parent = f
        btn.MouseButton1Click:Connect(function()
            st = not st; api.Set(st)
            if cb then cb(st) end
        end)

        return api
    end

    -- SLIDER BUILDER
    local function Slider(label, lo, hi, def, cb)
        local f = Instance.new("Frame")
        f.Size = UDim2.new(1, 0, 0, 48)
        f.BackgroundColor3 = CLR.card
        f.BorderSizePixel = 0
        f.LayoutOrder = nxt(); f.Parent = scroll
        Corner(f, 8)
        Hover(f, CLR.card, CLR.cardHover)

        local tl = Instance.new("TextLabel")
        tl.Size = UDim2.new(1, -54, 0, 18)
        tl.Position = UDim2.new(0, 12, 0, 4)
        tl.BackgroundTransparency = 1; tl.Text = label
        tl.TextColor3 = CLR.text; tl.TextSize = 11
        tl.Font = Enum.Font.Gotham
        tl.TextXAlignment = Enum.TextXAlignment.Left; tl.Parent = f

        local vl = Instance.new("TextLabel")
        vl.Size = UDim2.new(0, 44, 0, 18)
        vl.Position = UDim2.new(1, -54, 0, 4)
        vl.BackgroundTransparency = 1; vl.Text = tostring(def)
        vl.TextColor3 = CLR.accent; vl.TextSize = 12
        vl.Font = Enum.Font.GothamBold
        vl.TextXAlignment = Enum.TextXAlignment.Right; vl.Parent = f

        local track = Instance.new("Frame")
        track.Size = UDim2.new(1, -24, 0, 6)
        track.Position = UDim2.new(0, 12, 0, 32)
        track.BackgroundColor3 = CLR.sliderBg
        track.BorderSizePixel = 0; track.Parent = f
        Corner(track, 3)

        local initR = math.clamp((def - lo) / (hi - lo), 0, 1)

        local fill = Instance.new("Frame")
        fill.Size = UDim2.new(initR, 0, 1, 0)
        fill.BackgroundColor3 = CLR.accent
        fill.BorderSizePixel = 0; fill.Parent = track
        Corner(fill, 3)

        local fillGrad = Instance.new("UIGradient")
        fillGrad.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, CLR.accentDim),
            ColorSequenceKeypoint.new(1, CLR.accent),
        })
        fillGrad.Parent = fill

        local knob = Instance.new("Frame")
        knob.Size = UDim2.new(0, 14, 0, 14)
        knob.Position = UDim2.new(initR, -7, 0.5, -7)
        knob.BackgroundColor3 = Color3.new(1, 1, 1)
        knob.BorderSizePixel = 0; knob.ZIndex = 2
        knob.Parent = track
        Corner(knob, 7)

        local hit = Instance.new("TextButton")
        hit.Size = UDim2.new(1, 0, 0, 24)
        hit.Position = UDim2.new(0, 0, 0, 22)
        hit.BackgroundTransparency = 1; hit.Text = ""; hit.Parent = f

        local sliding = false
        local cur = def

        local function upd(pos)
            if not track or not track.Parent then return end
            local ax, aw = track.AbsolutePosition.X, track.AbsoluteSize.X
            if aw == 0 then return end
            local r = math.clamp((pos.X - ax) / aw, 0, 1)
            local v = math.clamp(math.floor(lo + (hi - lo) * r + 0.5), lo, hi)
            r = (v - lo) / (hi - lo)
            fill.Size = UDim2.new(r, 0, 1, 0)
            knob.Position = UDim2.new(r, -7, 0.5, -7)
            vl.Text = tostring(v)
            if v ~= cur then cur = v; if cb then cb(v) end end
        end

        hit.InputBegan:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1
            or i.UserInputType == Enum.UserInputType.Touch then
                sliding = true; upd(i.Position)
            end
        end)
        Conn(UIS.InputEnded, function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1
            or i.UserInputType == Enum.UserInputType.Touch then
                sliding = false
            end
        end)
        Conn(UIS.InputChanged, function(i)
            if sliding
               and track and track.Parent
               and (i.UserInputType == Enum.UserInputType.MouseMovement
               or  i.UserInputType == Enum.UserInputType.Touch) then
                upd(i.Position)
            end
        end)

        return {
            Set = function(v)
                cur = v
                local r = math.clamp((v - lo) / (hi - lo), 0, 1)
                fill.Size = UDim2.new(r, 0, 1, 0)
                knob.Position = UDim2.new(r, -7, 0.5, -7)
                vl.Text = tostring(v)
            end,
            Get = function() return cur end,
        }
    end

    -- ACTION BUTTON BUILDER
    local function ActionButton(label, color, callback)
        local f = Instance.new("Frame")
        f.Size = UDim2.new(1, 0, 0, 32)
        f.BackgroundColor3 = color
        f.BorderSizePixel = 0
        f.LayoutOrder = nxt(); f.Parent = scroll
        Corner(f, 8)
        Hover(f, color, Color3.fromRGB(
            math.min(color.R * 255 + 25, 255),
            math.min(color.G * 255 + 25, 255),
            math.min(color.B * 255 + 25, 255)
        ))

        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, 0, 1, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text = label
        lbl.TextColor3 = CLR.text
        lbl.TextSize = 11
        lbl.Font = Enum.Font.GothamBold
        lbl.Parent = f

        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, 0, 1, 0)
        btn.BackgroundTransparency = 1
        btn.Text = ""
        btn.Parent = f
        btn.MouseButton1Click:Connect(callback)

        return f
    end

    -- STATUS CARD
    local sCard = Instance.new("Frame")
    sCard.Size = UDim2.new(1, 0, 0, 142)
    sCard.BackgroundColor3 = CLR.card
    sCard.BorderSizePixel = 0
    sCard.LayoutOrder = nxt(); sCard.Parent = scroll
    Corner(sCard, 8); Stroke(sCard)

    local sDot = Instance.new("Frame")
    sDot.Size = UDim2.new(0, 10, 0, 10)
    sDot.Position = UDim2.new(0, 12, 0, 12)
    sDot.BackgroundColor3 = CLR.red
    sDot.BorderSizePixel = 0; sDot.Parent = sCard
    Corner(sDot, 5)

    local sLbl = Instance.new("TextLabel")
    sLbl.Size = UDim2.new(0.35, 0, 0, 16)
    sLbl.Position = UDim2.new(0, 28, 0, 8)
    sLbl.BackgroundTransparency = 1; sLbl.Text = "DISABLED"
    sLbl.TextColor3 = CLR.red; sLbl.TextSize = 11
    sLbl.Font = Enum.Font.GothamBold
    sLbl.TextXAlignment = Enum.TextXAlignment.Left; sLbl.Parent = sCard

    local sTimer = Instance.new("TextLabel")
    sTimer.Size = UDim2.new(0, 60, 0, 14)
    sTimer.Position = UDim2.new(1, -70, 0, 9)
    sTimer.BackgroundTransparency = 1; sTimer.Text = "00:00"
    sTimer.TextColor3 = CLR.textDim; sTimer.TextSize = 10
    sTimer.Font = Enum.Font.GothamSemibold
    sTimer.TextXAlignment = Enum.TextXAlignment.Right; sTimer.Parent = sCard

    local function StatL(name, y)
        local n = Instance.new("TextLabel")
        n.Size = UDim2.new(0, 62, 0, 14)
        n.Position = UDim2.new(0, 12, 0, y)
        n.BackgroundTransparency = 1; n.Text = name .. ":"
        n.TextColor3 = CLR.textDim; n.TextSize = 10
        n.Font = Enum.Font.Gotham
        n.TextXAlignment = Enum.TextXAlignment.Left; n.Parent = sCard
        local v = Instance.new("TextLabel")
        v.Size = UDim2.new(0, 48, 0, 14)
        v.Position = UDim2.new(0, 74, 0, y)
        v.BackgroundTransparency = 1; v.Text = "0"
        v.TextColor3 = CLR.text; v.TextSize = 10
        v.Font = Enum.Font.GothamBold
        v.TextXAlignment = Enum.TextXAlignment.Left; v.Parent = sCard
        return v
    end
    local function StatR(name, y)
        local n = Instance.new("TextLabel")
        n.Size = UDim2.new(0, 55, 0, 14)
        n.Position = UDim2.new(0.5, 8, 0, y)
        n.BackgroundTransparency = 1; n.Text = name .. ":"
        n.TextColor3 = CLR.textDim; n.TextSize = 10
        n.Font = Enum.Font.Gotham
        n.TextXAlignment = Enum.TextXAlignment.Left; n.Parent = sCard
        local v = Instance.new("TextLabel")
        v.Size = UDim2.new(0.5, -70, 0, 14)
        v.Position = UDim2.new(0.5, 63, 0, y)
        v.BackgroundTransparency = 1; v.Text = "-"
        v.TextColor3 = CLR.text; v.TextSize = 10
        v.Font = Enum.Font.GothamBold
        v.TextXAlignment = Enum.TextXAlignment.Left
        v.TextTruncate = Enum.TextTruncate.AtEnd; v.Parent = sCard
        return v
    end

    local svTargets  = StatL("Targets",  32)
    local svAttacks  = StatL("Attacks",  48)
    local svGuard    = StatL("Guard",    64)
    local svStomps   = StatL("Stomps",   80)
    local svStuns    = StatL("Stuns",    96)
    local svKAKills  = StatL("KA Kills", 112)
    local svAPS      = StatR("APS",      32)
    local svHP       = StatR("Health",   48)
    local svMode     = StatR("Mode",     64)
    local svNearby   = StatR("Nearby",   80)
    local svHeals    = StatR("Heals",    96)
    local svKATarget = StatR("KA Tgt",   112)

    -- CONTROLS
    Section("Main Controls")

    local tEnabled = Toggle("Script Enabled", CFG.Enabled, function(v)
        CFG.Enabled = v
        sDot.BackgroundColor3 = v and CLR.green or CLR.red
        sLbl.Text = v and "ACTIVE" or "DISABLED"
        sLbl.TextColor3 = v and CLR.green or CLR.red
        Notify(v and "Script enabled" or "Script disabled",
               v and "success" or "info", 1.5)
        AutoSave()
    end)

    Toggle("Attack All Targets (AoE)", CFG.TargetAll, function(v)
        CFG.TargetAll = v; AutoSave()
    end)

    Toggle("Target Players", CFG.TargetPlayers, function(v)
        CFG.TargetPlayers = v; ST.LastTargetUpdate = 0; AutoSave()
    end)

    Toggle("Target NPCs", CFG.TargetNPCs, function(v)
        CFG.TargetNPCs = v; ST.LastTargetUpdate = 0; AutoSave()
    end)

    Section("Attack Settings")

    Slider("Attacks Per Second", 1, 20, CFG.AttacksPerSecond, function(v)
        CFG.AttacksPerSecond = v; AutoSave()
    end)

    Slider("Max Targets / Cycle", 1, 10, CFG.MaxTargetsPerCycle, function(v)
        CFG.MaxTargetsPerCycle = v; AutoSave()
    end)

    Section("Attack Types")

    Toggle("Punch " .. (REM.Punch and "✓" or "✗"),
        REM.Punch ~= nil and CFG.UsePunch,
        function(v) if REM.Punch then CFG.UsePunch = v end; AutoSave() end)

    Toggle("Suplex " .. (REM.Suplex and "✓" or "✗"),
        REM.Suplex ~= nil and CFG.UseSuplex,
        function(v) if REM.Suplex then CFG.UseSuplex = v end; AutoSave() end)

    Toggle("Heavy Hit " .. (REM.HeavyHit and "✓" or "✗"),
        REM.HeavyHit ~= nil and CFG.UseHeavyHit,
        function(v) if REM.HeavyHit then CFG.UseHeavyHit = v end; AutoSave() end)

    Toggle("Tool/Weapon Attack " .. (REM.ToolHit and "✓" or "✗"),
        REM.ToolHit ~= nil and CFG.UseToolAttack,
        function(v) if REM.ToolHit then CFG.UseToolAttack = v end; AutoSave() end)

    Toggle("Prefer Weapon Over Fist", CFG.PreferWeaponOverFist,
        function(v) CFG.PreferWeaponOverFist = v; AutoSave() end)

    Toggle("Animation Cancel " .. (REM.StopAnim and "✓" or "✗"),
        REM.StopAnim ~= nil and CFG.UseAnimCancel,
        function(v) if REM.StopAnim then CFG.UseAnimCancel = v end; AutoSave() end)

    Toggle("Auto Stomp " .. (REM.Stomp and "✓" or "✗"),
        REM.Stomp ~= nil and CFG.UseAutoStomp,
        function(v) if REM.Stomp then CFG.UseAutoStomp = v end; AutoSave() end)

    Slider("Stomp Range (studs)", 5, 50, CFG.StompRange, function(v)
        CFG.StompRange = v; AutoSave()
    end)

    Toggle("Auto Stun " .. (REM.Stun and "✓" or "✗"),
        REM.Stun ~= nil and CFG.UseAutoStun,
        function(v) if REM.Stun then CFG.UseAutoStun = v end; AutoSave() end)

    Slider("Stun Range (studs)", 5, 50, CFG.StunRange, function(v)
        CFG.StunRange = v; AutoSave()
    end)

    -- SURVIVAL
    Section("Survival")

    Toggle("Auto Heal " .. (REM.Heal and "✓" or "✗"),
        REM.Heal ~= nil and CFG.UseAutoHeal,
        function(v) CFG.UseAutoHeal = v; AutoSave() end)

    Slider("Heal Threshold (%)", 10, 90, CFG.HealThreshold, function(v)
        CFG.HealThreshold = v; AutoSave()
    end)

    Toggle("Auto Buy Food " .. (REM.Carniceria and "✓" or "✗"),
        REM.Carniceria ~= nil and CFG.UseAutoBuyFood,
        function(v) CFG.UseAutoBuyFood = v; AutoSave() end)

    Toggle("Smart PVP Toggle " .. (REM.PVPToggle and "✓" or "✗"),
        false,
        function(v) if REM.PVPToggle then CFG.UseSmartPVP = v end; AutoSave() end)

    -- WEAPONS
    Section("Weapons")

    Toggle("Auto Pickup Weapons " .. (REM.PickupTool and "✓" or "✗"),
        REM.PickupTool ~= nil and CFG.UseAutoPickupTools,
        function(v) if REM.PickupTool then CFG.UseAutoPickupTools = v end; AutoSave() end)

    Slider("Pickup Range (studs)", 10, 100, CFG.ToolPickupRange, function(v)
        CFG.ToolPickupRange = v; AutoSave()
    end)

    -- ADVANCED COMBAT
    Section("Advanced Combat")

    Toggle("Auto Carry+Throw " .. ((REM.Carry and REM.Throw) and "✓" or "✗"),
        false,
        function(v)
            if REM.Carry and REM.Throw then CFG.UseAutoCarryThrow = v end
            AutoSave()
        end)

    Toggle("Crouch Spam " .. (REM.Crouch and "✓" or "✗"),
        false,
        function(v) if REM.Crouch then CFG.UseCrouchSpam = v end; AutoSave() end)

    -- KILL ALL
    Section("Kill All")

    local tKillAll = Toggle("Kill All (Teleport & Kill)", CFG.KillAllActive,
    function(v)
        CFG.KillAllActive = v
        if v then
            if not CFG.Enabled then
                CFG.Enabled = true
                tEnabled.Set(true)
                sDot.BackgroundColor3 = CLR.green
                sLbl.Text = "ACTIVE"; sLbl.TextColor3 = CLR.green
            end
            if not ST.KillAllRunning then
                task.spawn(RunKillAll)
            end
        end
        AutoSave()
    end)

    Slider("Kill Timeout (sec)", 3, 20, CFG.KillAllTimeout, function(v)
        CFG.KillAllTimeout = v; AutoSave()
    end)

    -- DEFENSE
    Section("Defense")

    local tGuard = Toggle("Auto Guard " .. (REM.Block and "✓" or "✗"),
        REM.Block ~= nil and CFG.UseAutoGuard,
        function(v)
            if REM.Block then
                CFG.UseAutoGuard = v
                if not v then SetGuard(false) end
            end
            AutoSave()
        end)

    Toggle("Drop Guard to Attack", CFG.GuardDropForAttack,
        function(v) CFG.GuardDropForAttack = v; AutoSave() end)

    Toggle("Ignore ForceField", CFG.IgnoreForceField,
        function(v) CFG.IgnoreForceField = v; AutoSave() end)

    Slider("Guard Range (studs)", 10, 150, CFG.GuardActivationRange, function(v)
        CFG.GuardActivationRange = v; InvalidateNearbyCache(); AutoSave()
    end)

    -- ADMIN ABUSE
    Section("Admin Abuse")

    Toggle("Enable Admin Abuse " .. ((REM.AdminCmd or REM.AdminPanel) and "✓" or "✗"),
        CFG.UseAdminAbuse,
        function(v)
            CFG.UseAdminAbuse = v
            if v then
                Notify("Admin abuse enabled — server may reject", "warning", 3)
            end
            AutoSave()
        end)

    Toggle("Auto God Mode (Admin)", CFG.UseAdminAutoGod,
        function(v) CFG.UseAdminAutoGod = v; AutoSave() end)

    ActionButton("Self Buff (God/Speed/Items)", CLR.accent, function()
        task.spawn(AdminSelfBuff)
    end)

    ActionButton("Admin Kill All", CLR.red, function()
        task.spawn(function() AdminServerCommand("killall") end)
    end)

    ActionButton("Admin Kick All", CLR.orange, function()
        task.spawn(function() AdminServerCommand("kickall") end)
    end)

    ActionButton("Admin Heal All", CLR.green, function()
        task.spawn(function() AdminServerCommand("healall") end)
    end)

    ActionButton("Admin Lock Server", CLR.yellow, function()
        task.spawn(function() AdminServerCommand("lockserver") end)
    end)

    ActionButton("Admin Shutdown", Color3.fromRGB(180, 30, 30), function()
        task.spawn(function() AdminServerCommand("shutdown") end)
    end)

    -- ADMIN TARGET PLAYER
    Section("Admin Target Player")

    local targetAdminPlayer = ""

    local targetInput = Instance.new("TextBox")
    targetInput.Size = UDim2.new(1, 0, 0, 30)
    targetInput.BackgroundColor3 = CLR.card
    targetInput.BorderSizePixel = 0
    targetInput.Text = ""
    targetInput.PlaceholderText = "Type player name..."
    targetInput.TextColor3 = CLR.text
    targetInput.PlaceholderColor3 = CLR.textDim
    targetInput.TextSize = 11
    targetInput.Font = Enum.Font.Gotham
    targetInput.ClearTextOnFocus = false
    targetInput.LayoutOrder = nxt()
    targetInput.Parent = scroll
    Corner(targetInput, 8)

    local inputPad = Instance.new("UIPadding")
    inputPad.PaddingLeft = UDim.new(0, 10)
    inputPad.Parent = targetInput

    targetInput.FocusLost:Connect(function()
        targetAdminPlayer = targetInput.Text
        if targetAdminPlayer ~= "" then
            Notify("Admin target: " .. targetAdminPlayer, "info", 2)
        end
    end)

    ActionButton("Kill Target", CLR.red, function()
        if targetAdminPlayer ~= "" then
            task.spawn(function() AdminTargetPlayer(targetAdminPlayer, "kill") end)
        else
            Notify("No target set", "error", 2)
        end
    end)

    ActionButton("Kick Target", CLR.orange, function()
        if targetAdminPlayer ~= "" then
            task.spawn(function() AdminTargetPlayer(targetAdminPlayer, "kick") end)
        else
            Notify("No target set", "error", 2)
        end
    end)

    ActionButton("Ban Target", Color3.fromRGB(180, 30, 30), function()
        if targetAdminPlayer ~= "" then
            task.spawn(function() AdminTargetPlayer(targetAdminPlayer, "ban") end)
        else
            Notify("No target set", "error", 2)
        end
    end)

    ActionButton("Freeze Target", CLR.cyan, function()
        if targetAdminPlayer ~= "" then
            task.spawn(function() AdminTargetPlayer(targetAdminPlayer, "freeze") end)
        else
            Notify("No target set", "error", 2)
        end
    end)

    ActionButton("Bring Target", CLR.green, function()
        if targetAdminPlayer ~= "" then
            task.spawn(function() AdminTargetPlayer(targetAdminPlayer, "teleport") end)
        else
            Notify("No target set", "error", 2)
        end
    end)

    -- SYSTEM
    Section("System")

    Toggle("Debug Logging", CFG.Debug, function(v) CFG.Debug = v; AutoSave() end)

    -- REMOTE STATUS
    Section("Remote Status")

    local remoteList = {
        {"PUNCHEVENT",            REM.Punch},
        {"SUPLEXEVENT",           REM.Suplex},
        {"HEAVYHIT",              REM.HeavyHit},
        {"BLOCKEVENT",            REM.Block},
        {"STOMPEVENT",            REM.Stomp},
        {"TOOLHITEVENT",          REM.ToolHit},
        {"STUNEVENT",             REM.Stun},
        {"HEALCHARACTERCARRIED",  REM.Heal},
        {"Carniceria",            REM.Carniceria},
        {"CARRYEVENT",            REM.Carry},
        {"THROWCHARACTEREVENT",   REM.Throw},
        {"CROUCHEVENT",           REM.Crouch},
        {"STOPLOCALANIMATIONS",   REM.StopAnim},
        {"PVPONOFFEVENT",         REM.PVPToggle},
        {"PICKUPTOOLSEVENT",      REM.PickupTool},
        {"ADMINCOMMANDS",         REM.AdminCmd},
        {"ADMINPANNEL",           REM.AdminPanel},
    }

    local ri = Instance.new("Frame")
    ri.Size = UDim2.new(1, 0, 0, #remoteList * 17 + 8)
    ri.BackgroundColor3 = CLR.card
    ri.BorderSizePixel = 0
    ri.LayoutOrder = nxt(); ri.Parent = scroll
    Corner(ri, 8)

    for idx, data in ipairs(remoteList) do
        local ok = data[2] ~= nil
        local rl = Instance.new("TextLabel")
        rl.Size = UDim2.new(1, -14, 0, 15)
        rl.Position = UDim2.new(0, 12, 0, 4 + (idx - 1) * 17)
        rl.BackgroundTransparency = 1
        rl.Text = (ok and "●  " or "○  ") .. data[1]
        rl.TextColor3 = ok and CLR.green or CLR.red
        rl.TextSize = 10; rl.Font = Enum.Font.GothamSemibold
        rl.TextXAlignment = Enum.TextXAlignment.Left; rl.Parent = ri
    end

    -- FOOTER
    local footer = Instance.new("Frame")
    footer.Size = UDim2.new(1, 0, 0, 32)
    footer.BackgroundTransparency = 1
    footer.LayoutOrder = nxt(); footer.Parent = scroll

    local footerText = Instance.new("TextLabel")
    footerText.Size = UDim2.new(1, 0, 0, 12)
    footerText.Position = UDim2.new(0, 0, 0, 2)
    footerText.BackgroundTransparency = 1
    footerText.Text = "Insert = Toggle GUI   |   RShift = Toggle Script"
    footerText.TextColor3 = CLR.textDim; footerText.TextSize = 9
    footerText.Font = Enum.Font.Gotham; footerText.Parent = footer

    local brand = Instance.new("TextLabel")
    brand.Size = UDim2.new(1, 0, 0, 12)
    brand.Position = UDim2.new(0, 0, 0, 16)
    brand.BackgroundTransparency = 1
    brand.Text = "Mass Attack Pro v" .. SCRIPT_VERSION .. "  |  " .. EXECUTOR_NAME
    brand.TextColor3 = Color3.fromRGB(60, 60, 80)
    brand.TextSize = 8; brand.Font = Enum.Font.GothamSemibold
    brand.Parent = footer

    -- MINIMIZE / CLOSE
    local minimized = false
    local fullSz = main.Size

    minB.MouseButton1Click:Connect(function()
        minimized = not minimized
        if minimized then
            TweenService:Create(scroll, TweenInfo.new(0.12),
                {Size = UDim2.new(1, -14, 0, 0)}):Play()
            task.wait(0.12)
            scroll.Visible = false
            TweenService:Create(main, TweenInfo.new(0.2, Enum.EasingStyle.Quint),
                {Size = UDim2.new(0, 380, 0, 46)}):Play()
            minB.Text = "+"
        else
            scroll.Visible = true
            TweenService:Create(main, TweenInfo.new(0.25, Enum.EasingStyle.Quint),
                {Size = fullSz}):Play()
            task.wait(0.15)
            TweenService:Create(scroll, TweenInfo.new(0.15),
                {Size = UDim2.new(1, -14, 1, -54)}):Play()
            minB.Text = "—"
        end
    end)

    clsB.MouseButton1Click:Connect(function()
        ST.Running = false; CFG.Enabled = false; CFG.KillAllActive = false
        SetGuard(false)
        TweenService:Create(main, TweenInfo.new(0.25, Enum.EasingStyle.Quint),
            {Size = UDim2.new(0, 380, 0, 0), BackgroundTransparency = 1}):Play()
        task.wait(0.3)
        sg:Destroy()
    end)

    -- KEYBINDS
    Conn(UIS.InputBegan, function(inp, gp)
        if gp then return end
        if inp.KeyCode == CFG.GuiToggleKey then
            main.Visible = not main.Visible
        elseif inp.KeyCode == CFG.ScriptToggleKey then
            CFG.Enabled = not CFG.Enabled
            tEnabled.Set(CFG.Enabled)
            sDot.BackgroundColor3 = CFG.Enabled and CLR.green or CLR.red
            sLbl.Text = CFG.Enabled and "ACTIVE" or "DISABLED"
            sLbl.TextColor3 = CFG.Enabled and CLR.green or CLR.red
            Notify(CFG.Enabled and "Script enabled" or "Script disabled",
                   CFG.Enabled and "success" or "info", 1.5)
        end
    end)

    -- OPEN ANIMATION
    main.Size = UDim2.new(0, 380, 0, 0)
    main.BackgroundTransparency = 1
    task.defer(function()
        TweenService:Create(main,
            TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
            {Size = fullSz, BackgroundTransparency = 0}):Play()
    end)

    -- STATUS DOT PULSE
    task.spawn(function()
        while ST.Running do
            if sg and sg.Parent and sDot and sDot.Parent then
                if CFG.Enabled then
                    TweenService:Create(sDot, TweenInfo.new(0.7),
                        {BackgroundTransparency = 0.45}):Play()
                    task.wait(0.7)
                    if sDot and sDot.Parent then
                        TweenService:Create(sDot, TweenInfo.new(0.7),
                            {BackgroundTransparency = 0}):Play()
                    end
                    task.wait(0.7)
                else
                    if sDot.BackgroundTransparency ~= 0 then
                        TweenService:Create(sDot, TweenInfo.new(0.3),
                            {BackgroundTransparency = 0}):Play()
                    end
                    task.wait(0.5)
                end
            else
                break
            end
        end
    end)

    return {
        gui  = sg,
        main = main,
        statusDot = sDot,
        statusLbl = sLbl,
        timer     = sTimer,
        sv = {
            targets  = svTargets,  attacks  = svAttacks,
            guard    = svGuard,    aps      = svAPS,
            health   = svHP,       mode     = svMode,
            stomps   = svStomps,   nearby   = svNearby,
            stuns    = svStuns,    heals    = svHeals,
            kaKills  = svKAKills,  kaTarget = svKATarget,
        },
        toggleEnabled = tEnabled,
        toggleKillAll = tKillAll,
    }
end

GUI_REFS = BuildGUI()

----------------------------------------------------------------
-- 11. MAIN LOOPS
----------------------------------------------------------------

-- 11a  Health monitor
task.spawn(function()
    while ST.Running do
        SafeCall(function()
            if CFG.UseAutoGuard and CFG.Enabled and humanoid then
                local hp = humanoid.Health
                if hp < ST.LastHealth and ST.EnemyNearby then
                    SetGuard(true)
                end
                ST.LastHealth = hp
            end
        end)
        task.wait(CFG.HealthPollInterval)
    end
end)

-- 11b  Guard keep-alive
task.spawn(function()
    while ST.Running do
        SafeCall(function()
            if CFG.UseAutoGuard and CFG.Enabled then
                local nearby = IsEnemyNearby(CFG.GuardActivationRange)
                ST.EnemyNearby = nearby
                if nearby and not ST.GuardActive then
                    SetGuard(true)
                elseif not nearby and ST.GuardActive then
                    SetGuard(false)
                end
            else
                ST.EnemyNearby = IsEnemyNearby(CFG.GuardActivationRange)
            end
        end)
        task.wait(0.4)
    end
end)

-- 11c  Attack loop
task.spawn(function()
    while ST.Running do
        if CFG.Enabled and HAS_ATTACK and not CFG.KillAllActive then
            local interval = 1 / math.max(CFG.AttacksPerSecond, 1)
            local t0 = tick()

            if tick() - ST.LastTargetUpdate > CFG.TargetUpdateInterval then
                RefreshTargets()
            end

            local tgts = ST.TargetCache
            if #tgts > 0 then
                if CFG.GuardDropForAttack and CFG.UseAutoGuard then
                    SetGuard(false)
                end

                SafeCall(function()
                    if CFG.TargetAll then
                        local cnt = math.min(#tgts, CFG.MaxTargetsPerCycle)
                        for i = 1, cnt do
                            local idx = ((ST.TargetIndex + i - 2) % #tgts) + 1
                            local t = tgts[idx]
                            if t and t.Parent and IsValid(t) then Attack(t) end
                        end
                        ST.TargetIndex = (ST.TargetIndex % #tgts) + 1
                    else
                        local best, bestD = nil, CFG.AttackRange
                        if rootPart and rootPart.Parent then
                            local mp = rootPart.Position
                            for _, c in ipairs(tgts) do
                                local r = c:FindFirstChild("HumanoidRootPart")
                                if r then
                                    local d = (mp - r.Position).Magnitude
                                    if d < bestD then bestD = d; best = c end
                                end
                            end
                        end
                        if best and IsValid(best) then Attack(best) end
                    end
                end)

                if CFG.GuardDropForAttack and CFG.UseAutoGuard then
                    task.delay(CFG.GuardReactivateDelay, function()
                        if CFG.UseAutoGuard and CFG.Enabled and ST.Running
                           and IsEnemyNearby(CFG.GuardActivationRange) then
                            SetGuard(true)
                        end
                    end)
                end
            end

            local w = interval - (tick() - t0)
            task.wait(w > 0 and w or 0.001)
        else
            task.wait(0.2)
        end
    end
end)

-- 11d  Status updater
task.spawn(function()
    while ST.Running do
        SafeCall(function()
            if GUI_REFS and GUI_REFS.sv then
                local s = GUI_REFS.sv

                s.targets.Text = tostring(ST.TargetsFound)
                s.attacks.Text = tostring(ST.TotalAttacks)

                s.guard.Text = ST.GuardActive and "ON" or "OFF"
                s.guard.TextColor3 = ST.GuardActive and CLR.green or CLR.red

                s.aps.Text    = tostring(CFG.AttacksPerSecond)
                s.health.Text = humanoid
                    and tostring(math.floor(humanoid.Health)) or "?"

                s.mode.Text = CFG.KillAllActive and "KILL ALL"
                    or (CFG.TargetAll and "AoE" or "Single")
                s.mode.TextColor3 = CFG.KillAllActive and CLR.cyan or CLR.text

                s.stomps.Text  = tostring(ST.TotalStomps)
                s.stuns.Text   = tostring(ST.TotalStuns)
                s.heals.Text   = tostring(ST.TotalHeals)

                s.nearby.Text = ST.EnemyNearby and "YES" or "NO"
                s.nearby.TextColor3 = ST.EnemyNearby
                    and CLR.yellow or CLR.textDim

                s.kaKills.Text = tostring(ST.KillAllKills)
                s.kaKills.TextColor3 = ST.KillAllKills > 0
                    and CLR.cyan or CLR.text

                s.kaTarget.Text = ST.KillAllTarget ~= ""
                    and ST.KillAllTarget or "-"
                s.kaTarget.TextColor3 = CFG.KillAllActive
                    and CLR.cyan or CLR.textDim

                if GUI_REFS.timer then
                    GUI_REFS.timer.Text = FormatTime(tick() - ST.StartTime)
                end
            end
        end)
        task.wait(0.35)
    end
end)

-- 11e  Auto Stomp loop
task.spawn(function()
    while ST.Running do
        if CFG.Enabled and CFG.UseAutoStomp and REM.Stomp then
            SafeCall(TryStomp)
            task.wait(0.15)
        else
            task.wait(0.3)
        end
    end
end)

-- 11f  Auto Heal loop
task.spawn(function()
    while ST.Running do
        if CFG.Enabled and CFG.UseAutoHeal then
            SafeCall(TryBuyFood)
            SafeCall(TryHeal)
            task.wait(CFG.HealCooldown * 0.5)
        else
            task.wait(0.5)
        end
    end
end)

-- 11g  Auto Stun loop
task.spawn(function()
    while ST.Running do
        if CFG.Enabled and CFG.UseAutoStun and REM.Stun then
            SafeCall(TryStun)
            task.wait(CFG.StunCooldown * 0.5)
        else
            task.wait(0.5)
        end
    end
end)

-- 11h  Auto Pickup loop
task.spawn(function()
    while ST.Running do
        if CFG.Enabled and CFG.UseAutoPickupTools and REM.PickupTool then
            SafeCall(TryPickupTools)
            task.wait(CFG.ToolPickupCooldown)
        else
            task.wait(1.0)
        end
    end
end)

-- 11i  Carry+Throw loop
task.spawn(function()
    while ST.Running do
        if CFG.Enabled and CFG.UseAutoCarryThrow
           and REM.Carry and REM.Throw then
            SafeCall(TryCarryThrow)
            task.wait(0.5)
        else
            task.wait(0.5)
        end
    end
end)

-- 11j  Crouch Spam loop
task.spawn(function()
    while ST.Running do
        if CFG.Enabled and CFG.UseCrouchSpam and REM.Crouch then
            SafeCall(function() REM.Crouch:FireServer(true) end)
            task.wait(CFG.CrouchSpamSpeed)
            SafeCall(function() REM.Crouch:FireServer(false) end)
            task.wait(CFG.CrouchSpamSpeed)
        else
            task.wait(0.5)
        end
    end
end)

-- 11k  Smart PVP loop
task.spawn(function()
    while ST.Running do
        if CFG.Enabled and CFG.UseSmartPVP and REM.PVPToggle then
            SafeCall(ManagePVP)
            task.wait(0.5)
        else
            task.wait(1.0)
        end
    end
end)

-- 11l  Admin Auto-God loop
task.spawn(function()
    while ST.Running do
        if CFG.Enabled and CFG.UseAdminAutoGod
           and (REM.AdminCmd or REM.AdminPanel) then
            local me = plr.Name
            SafeCall(function() FireAdminCommand("god", me) end)
            SafeCall(function() FireAdminCommand("heal", me) end)
            SafeCall(function() FireAdminCommand("health", me, 999999) end)
            SafeCall(function() FireAdminCommand("invincible", me) end)
            task.wait(CFG.AdminAutoGodInterval)
        else
            task.wait(1.0)
        end
    end
end)

----------------------------------------------------------------
-- 12. RESPAWN HANDLER
----------------------------------------------------------------
Conn(plr.CharacterAdded, function(newChar)
    char     = newChar
    rootPart = char:WaitForChild("HumanoidRootPart", 10)
    humanoid = char:WaitForChild("Humanoid", 10)

    ST.GuardActive      = false
    ST.LastHealth        = humanoid and humanoid.Health or 100
    ST.LastTargetUpdate  = 0
    ST.EnemyNearby       = false
    ST.IsCarrying        = false
    InvalidateNearbyCache()

    Notify("Respawned — systems reinitializing", "info", 2)

    if CFG.UseAutoGuard and CFG.Enabled then
        task.wait(0.5)
        if IsEnemyNearby(CFG.GuardActivationRange) then
            SetGuard(true)
        end
    end
    Log("Respawned - reset complete")
end)

----------------------------------------------------------------
-- 13. INITIALIZATION
----------------------------------------------------------------
RefreshTargets()
ST.EnemyNearby = IsEnemyNearby(CFG.GuardActivationRange)
if CFG.UseAutoGuard and CFG.Enabled and ST.EnemyNearby then
    SetGuard(true)
end

-- Load saved config on Xeno
if IS_XENO then
    XenoLoadConfig(CFG)
end

task.delay(0.5, function()
    local remoteCount = 0
    for _, v in pairs(REM) do if v then remoteCount = remoteCount + 1 end end
    Notify("MAP v" .. SCRIPT_VERSION .. " loaded on " .. EXECUTOR_NAME
           .. " | " .. remoteCount .. "/17 remotes", "success", 4)
    if IS_XENO then
        Notify("Xeno detected — config persistence active", "info", 3)
    end
end)

print("╔══════════════════════════════════════════════════╗")
print("║    MASS ATTACK PRO v" .. SCRIPT_VERSION .. " — XENO COMPATIBLE    ║")
print("╠══════════════════════════════════════════════════╣")
print("║  Executor:  " .. EXECUTOR_NAME)
print("║  Insert      =  Toggle GUI")
print("║  RightShift  =  Toggle Script")
print("╚══════════════════════════════════════════════════╝")
