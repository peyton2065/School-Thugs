--[[
╔══════════════════════════════════════════════════════════════════╗
║                   MASS ATTACK PRO v4.0                         ║
║            Production Combat Enhancement Suite                 ║
║               Xeno Executor Compatible                         ║
║                                                                ║
║  Insert      = Toggle GUI                                      ║
║  RightShift  = Toggle Script                                   ║
║  K           = Toggle Kill All                                 ║
║  T           = Toggle Single/AoE                               ║
║  X           = Emergency Stop                                  ║
║  B           = Toggle Auto Block                               ║
╠══════════════════════════════════════════════════════════════════╣
║  CHANGELOG v3.2 → v4.0:                                       ║
║                                                                ║
║  [CRITICAL FIXES]                                              ║
║  • TryPickupTools: Replaced 20+ blind remote fires with       ║
║    intelligent tiered pickup system (direct parent, minimal    ║
║    remote sigs, ClickDetector, ProximityPrompt fallbacks)      ║
║    + deduplication + fail tracking + visual feedback           ║
║  • TryBuyFood: Replaced 40+ carpet-bomb fires with signature  ║
║    discovery via hookmetamethod sniffing or tiered probing     ║
║    with health-delta detection to cache working signature      ║
║                                                                ║
║  [PERFORMANCE]                                                 ║
║  • NPC Registry: Event-driven via DescendantAdded/Removing,   ║
║    eliminates per-cycle GetDescendants() calls                 ║
║  • Tool Registry: Persistent, event-driven, monitors named    ║
║    folders (Drops, Items, Weapons, etc.)                       ║
║  • Food item cache: 30s TTL instead of per-cycle scanning     ║
║  • Loop consolidation: 11+ loops → 6 focused loops            ║
║  • Attack loop: single pcall wrap instead of per-fire         ║
║  • Early-exit on all proximity checks verified                 ║
║                                                                ║
║  [UI OVERHAUL]                                                 ║
║  • Tab system: Combat, Defense, Survival, Utility, System     ║
║  • Status card always visible with grouped stats               ║
║  • Collapsible sections with persistent state                  ║
║  • Category-colored toggles (purple/blue/green/amber/gray)    ║
║  • Toggle click bounce animation using Back easing             ║
║  • Slider knob glow on drag                                    ║
║  • Tooltip system on hover                                     ║
║  • Search/filter bar                                           ║
║  • Notification queue capped at 5 visible                      ║
║  • Auto-height window based on visible content                 ║
║  • Mobile touch support verified                               ║
║  • Combat log panel with colored timestamped entries           ║
║                                                                ║
║  [NEW FEATURES]                                                ║
║  • Target prioritization: Nearest / Lowest HP / Highest Threat║
║  • Whitelist/Blacklist system with auto-friend whitelist       ║
║  • Kill aura visualization (toggleable range ring)             ║
║  • DPS tracker with rolling window                             ║
║  • Anti-AFK system                                             ║
║  • Customizable keybinds via UI                                ║
║  • Config export/import via clipboard                          ║
║  • ESP overlay for active targets (name + health bar)          ║
║  • Auto-respawn with mode re-engagement                        ║
║  • Combat log (kills, deaths, heals, pickups, errors)          ║
║                                                                ║
║  [CODE QUALITY]                                                ║
║  • 4-space indent, consistent formatting                       ║
║  • Function header comments on every function                  ║
║  • All remotes pcall-wrapped                                   ║
║  • All connections tracked in ST.Connections                   ║
║  • All loops guard ST.Running for clean exit                   ║
║  • Cleanup handles partial initialization                      ║
║  • Dead code removed, unused variables eliminated              ║
║  • Xeno config persistence extended to all new fields          ║
╚══════════════════════════════════════════════════════════════════╝
]]

local SCRIPT_VERSION = "4.0"

----------------------------------------------------------------
-- S0. EXECUTOR DETECTION & UNC SHIMS
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

--- UNC shims for environments that lack them
if not cloneref then cloneref = function(o) return o end end
if not getnilinstances then getnilinstances = function() return {} end end
if not getinstances then getinstances = function() return {} end end

--- Capability detection for advanced hooking
local CAN_HOOK_META = type(hookmetamethod) == "function"
local CAN_HOOK_FUNC = type(hookfunction) == "function"
local CAN_FIRE_CLICK = type(fireclickdetector) == "function"
local CAN_FIRE_PROMPT = type(fireproximityprompt) == "function"
local CAN_SET_CLIPBOARD = type(setclipboard) == "function"

----------------------------------------------------------------
-- S0b. ONE-SHOT DAMAGE FLAG
-- PUNCH_REMOTE is discovered here so Attack() can send -9e9 damage
-- directly in FireServer args — no namecall hook needed, no checkcaller
-- conflict. Works universally across all combat modes on Xeno.
----------------------------------------------------------------
local ONESHOT_HOOKED = false
local PUNCH_REMOTE = nil

pcall(function()
    local folder = game:GetService("ReplicatedStorage"):FindFirstChild("MainEvents")
    if folder then
        PUNCH_REMOTE = folder:FindFirstChild("PUNCHEVENT")
    end
    if not PUNCH_REMOTE then
        PUNCH_REMOTE = game:GetService("ReplicatedStorage"):FindFirstChild("PUNCHEVENT", true)
    end
    if PUNCH_REMOTE then
        ONESHOT_HOOKED = true
        print("[MAP] One-shot punch active — damage arg will be -9e9")
    end
end)

----------------------------------------------------------------
-- S1. CLEANUP PREVIOUS INSTANCE
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
                if pg then oldGui = pg:FindFirstChild("MassAttackPro") end
            end)
        end
        if oldGui then oldGui:Destroy() end
    end)
    _G._MassAttackPro = nil
    task.wait(0.2)
end

----------------------------------------------------------------
-- S1. SERVICES & CORE REFERENCES
----------------------------------------------------------------
local Players       = cloneref(game:GetService("Players"))
local RepStorage    = cloneref(game:GetService("ReplicatedStorage"))
local UIS           = cloneref(game:GetService("UserInputService"))
local TweenService  = cloneref(game:GetService("TweenService"))
local RunService    = cloneref(game:GetService("RunService"))
local HttpService   = cloneref(game:GetService("HttpService"))
local StarterPack   = cloneref(game:GetService("StarterPack"))

local plr       = Players.LocalPlayer
local char      = plr.Character or plr.CharacterAdded:Wait()
local rootPart  = char:WaitForChild("HumanoidRootPart", 10)
local humanoid  = char:WaitForChild("Humanoid", 10)

--- Parent a ScreenGui safely across executor environments
-- @param screenGui ScreenGui to parent
local function ParentGui(screenGui)
    local ok = pcall(function()
        screenGui.Parent = game:GetService("CoreGui")
    end)
    if ok and screenGui.Parent then return end

    ok = pcall(function()
        if type(gethui) == "function" then
            screenGui.Parent = gethui()
        else error() end
    end)
    if ok and screenGui.Parent then return end

    ok = pcall(function()
        if syn and syn.protect_gui then
            syn.protect_gui(screenGui)
            screenGui.Parent = game:GetService("CoreGui")
        else error() end
    end)
    if ok and screenGui.Parent then return end

    screenGui.Parent = plr:WaitForChild("PlayerGui")
end

----------------------------------------------------------------
-- S2. STATE TABLE + FULL CONFIG
----------------------------------------------------------------
local CFG = {
    Enabled              = false,

    -- Combat
    AttacksPerSecond     = 20,
    TargetAll            = true,
    TargetPlayers        = true,
    TargetNPCs           = true,
    IgnoreForceField     = true,
    MinHealth            = 1,
    TargetPart           = "Head",
    MaxTargetsPerCycle   = 10,
    TargetUpdateInterval = 0.5,
    AttackRange          = 9999,
    TargetPriority       = "Nearest", -- "Nearest" | "LowestHP" | "HighestThreat"

    -- Attacks
    UsePunch             = true,
    UseSuplex            = true,
    UseHeavyHit          = true,

    -- Tool / Weapon
    UseToolAttack        = true,
    PreferWeaponOverFist = false,

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
    StunRange            = 50,

    -- Guard
    UseAutoGuard         = true,
    GuardCooldown        = 0.10,
    GuardDropForAttack   = true,
    GuardReactivateDelay = 0.04,
    HealthPollInterval   = 0.05,
    GuardActivationRange = 15,

    -- Heal
    UseAutoHeal          = true,
    HealThreshold        = 95,
    HealCooldown         = 0.5,

    -- Auto Buy Food
    UseAutoBuyFood       = false,
    BuyFoodCooldown      = 1.5,

    -- Pickup
    UseAutoPickupTools   = false,
    ToolPickupRange      = 100,
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
    UseSmartPVP          = true,
    PVPOffThreshold      = 25,
    PVPOnThreshold       = 80,

    -- Remote Aura (hit every player simultaneously, no proximity required)
    RemoteAura           = false,

    -- Kill All
    KillAllActive        = false,
    KillAllTimeout       = 8,
    KillAllTeleportDelay = 0.25,
    KillAllReteleportDist = 12,
    KillAllRetries       = 3,

    -- Size Changer
    SizeChangerEnabled   = false,
    SizeChangerValue     = 1.0,

    -- New Features
    AntiAFK              = true,
    AutoRespawn          = false,
    AutoReengageMode     = true,
    KillAuraVisualization = false,
    ESPEnabled           = false,
    DPSTrackingWindow    = 3,
    CombatLogEnabled     = true,
    CombatLogMaxEntries  = 50,

    -- Whitelist / Blacklist
    Whitelist            = {},
    Blacklist            = {},
    AutoWhitelistFriends = true,

    -- Keybinds
    Keybinds = {
        ToggleGUI        = Enum.KeyCode.Insert,
        ToggleScript     = Enum.KeyCode.RightShift,
        KillAll          = Enum.KeyCode.K,
        ToggleAoE        = Enum.KeyCode.T,
        EmergencyStop    = Enum.KeyCode.X,
        ToggleAutoBlock  = Enum.KeyCode.B,
    },

    -- UI State
    DefaultTab           = "Combat",
    CollapsedSections    = {},

    -- Cached signatures (auto-populated)
    CachedFoodSignature  = nil,
    CachedPickupSignature = nil,

    Debug                = false,
}

local ST = {
    Running           = true,
    StartTime         = tick(),
    GuardActive       = false,
    LastGuardTime     = 0,
    LastTargetUpdate  = 0,
    TargetCache       = {},
    TargetIndex       = 1,
    TotalAttacks      = 0,
    TargetsFound      = 0,
    LastHealth        = humanoid and humanoid.Health or 100,
    Connections       = {},

    TotalStomps       = 0,
    LastStompTime     = 0,
    EnemyNearby       = false,

    TotalStuns        = 0,
    LastStunTime      = 0,

    LastHealTime      = 0,
    TotalHeals        = 0,
    AutoHealActive    = false,

    LastFoodBuy       = 0,
    TotalFoodBuys     = 0,
    FoodProbeIndex    = 0,
    FoodSigFails      = 0,

    LastToolPickup    = 0,
    TotalPickups      = 0,
    TotalToolHits     = 0,

    LastCarryTime     = 0,
    TotalThrows       = 0,
    IsCarrying        = false,

    PVPEnabled        = true,
    LastPVPToggle     = 0,

    KillAllRunning    = false,
    KillAllTarget     = "",
    KillAllProgress   = "",
    KillAllKills      = 0,

    PreviousMode      = nil,
    CurrentMode       = nil,

    -- Registries
    NPCRegistry       = {},
    ToolRegistry      = {},
    ToolBlacklist     = {},
    FoodItemCache     = {},
    FoodItemCacheTime = 0,

    -- DPS
    DPSHistory        = {},
    CurrentDPS        = 0,

    -- Threat
    ThreatTable       = {},

    -- Combat Log
    CombatLog         = {},

    -- Friend cache
    FriendCache       = {},

    -- ESP pool
    ESPPool           = {},

    -- Kill aura part
    AuraRing          = nil,
    AuraConn          = nil,

    -- Notification tracking
    ActiveNotifs      = {},
}

local _nearbyCache = { result = false, lastCheck = 0, interval = 0.5 }

_G._MassAttackPro = ST

----------------------------------------------------------------
-- S3. CONFIG PERSISTENCE
----------------------------------------------------------------

--- Save config to Xeno globals
-- @param cfg table The config table
local function XenoSaveConfig(cfg)
    pcall(function()
        if IS_XENO and Xeno.SetGlobal then
            local saveData = {}
            for k, v in pairs(cfg) do
                local t = type(v)
                if t == "number" or t == "boolean" or t == "string" then
                    saveData[k] = tostring(v)
                elseif t == "table" then
                    pcall(function()
                        saveData[k] = HttpService:JSONEncode(v)
                    end)
                end
            end
            Xeno.SetGlobal("MAP_Config_v4", saveData)
        end
    end)
end

--- Load config from Xeno globals
-- @param cfg table The config table to populate
local function XenoLoadConfig(cfg)
    pcall(function()
        if IS_XENO and Xeno.GetGlobal then
            local saved = Xeno.GetGlobal("MAP_Config_v4")
            if saved and type(saved) == "table" then
                for k, v in pairs(saved) do
                    if cfg[k] ~= nil then
                        local ct = type(cfg[k])
                        if ct == "boolean" then
                            cfg[k] = v == "true"
                        elseif ct == "number" then
                            cfg[k] = tonumber(v) or cfg[k]
                        elseif ct == "string" then
                            cfg[k] = v
                        elseif ct == "table" then
                            pcall(function()
                                cfg[k] = HttpService:JSONDecode(v)
                            end)
                        end
                    end
                end
            end
        end
    end)
end

local _lastSave = 0

--- Auto-save config with 2s debounce
local function AutoSave()
    if not IS_XENO then return end
    local now = tick()
    if now - _lastSave < 2 then return end
    _lastSave = now
    task.defer(function() XenoSaveConfig(CFG) end)
end

----------------------------------------------------------------
-- S4. UTILITY FUNCTIONS
----------------------------------------------------------------

--- Track an RBXScriptConnection for cleanup
-- @param signal RBXScriptSignal
-- @param fn function callback
-- @return RBXScriptConnection
local function Conn(signal, fn)
    local c = signal:Connect(fn)
    table.insert(ST.Connections, c)
    return c
end

--- Debug logger
local function Log(...)
    if CFG.Debug then print("[MAP]", ...) end
end

--- Protected call wrapper
-- @return boolean success, any error
local function SafeCall(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok and CFG.Debug then warn("[MAP ERROR]", err) end
    return ok, err
end

--- Format seconds as MM:SS
-- @param seconds number
-- @return string
local function FormatTime(seconds)
    local m = math.floor(seconds / 60)
    local s = math.floor(seconds % 60)
    return string.format("%02d:%02d", m, s)
end

--- Refresh character references
-- @return Character, HumanoidRootPart, Humanoid
local function GetChar()
    char = plr.Character
    if char then
        rootPart = char:FindFirstChild("HumanoidRootPart")
        humanoid = char:FindFirstChildOfClass("Humanoid")
    end
    return char, rootPart, humanoid
end

--- Apply a uniform size scale to the local character via Model:ScaleTo()
-- After scaling, repositions the character so feet stay planted at ground
-- level — prevents the floating/levitating appearance on other clients.
-- @param value number  Scale factor (1.0 = default, 2.0 = double, etc.)
local function ApplySize(value)
    GetChar()
    if not char or not char.Parent then return end
    if not rootPart or not humanoid then return end

    pcall(function()
        -- Capture foot Y position before scaling (HRP minus hip height + half HRP height)
        -- This is the ground level we want to preserve after scaling
        local hipH     = humanoid.HipHeight
        local hrpHalfY = rootPart.Size.Y / 2
        local footY    = rootPart.Position.Y - hipH - hrpHalfY

        -- Apply the scale
        char:ScaleTo(value)

        -- Recalculate where the new HRP should sit above that foot position
        -- Hip height and HRP size have both scaled, so re-read them
        local newHipH     = humanoid.HipHeight
        local newHrpHalfY = rootPart.Size.Y / 2
        local targetY     = footY + newHipH + newHrpHalfY

        -- Reposition — X and Z unchanged, Y snapped back to ground
        rootPart.CFrame = CFrame.new(
            rootPart.Position.X,
            targetY,
            rootPart.Position.Z
        ) * (rootPart.CFrame - rootPart.CFrame.Position)
    end)
end

--- Check if a player is a friend (cached per session)
-- @param targetPlayer Player
-- @return boolean
local function IsFriend(targetPlayer)
    if ST.FriendCache[targetPlayer.UserId] ~= nil then
        return ST.FriendCache[targetPlayer.UserId]
    end
    local ok, result = pcall(function()
        return plr:IsFriendsWith(targetPlayer.UserId)
    end)
    local val = ok and result or false
    ST.FriendCache[targetPlayer.UserId] = val
    return val
end

--- Check if a player is whitelisted
-- @param playerName string
-- @return boolean
local function IsWhitelisted(playerName)
    return CFG.Whitelist[playerName] == true
end

--- Check if a player is blacklisted
-- @param playerName string
-- @return boolean
local function IsBlacklisted(playerName)
    return CFG.Blacklist[playerName] == true
end

-- Forward declare Notify
local Notify = function() end

-- Forward declare AddLogEntry
local AddLogEntry = function() end

----------------------------------------------------------------
-- S4b. COMBAT LOG
----------------------------------------------------------------
local LOG_COLORS = {
    kill   = Color3.fromRGB(255, 80, 80),
    death  = Color3.fromRGB(255, 50, 50),
    heal   = Color3.fromRGB(80, 255, 120),
    pickup = Color3.fromRGB(255, 220, 80),
    system = Color3.fromRGB(180, 180, 180),
    error  = Color3.fromRGB(255, 100, 50),
}

--- Add entry to combat log
-- @param category string one of: kill, death, heal, pickup, system, error
-- @param message string
AddLogEntry = function(category, message)
    if not CFG.CombatLogEnabled then return end
    local entry = {
        time     = os.date("%H:%M:%S"),
        category = category,
        message  = message,
        color    = LOG_COLORS[category] or LOG_COLORS.system,
    }
    table.insert(ST.CombatLog, entry)
    if #ST.CombatLog > CFG.CombatLogMaxEntries then
        table.remove(ST.CombatLog, 1)
    end
end

----------------------------------------------------------------
-- S5. THEME
----------------------------------------------------------------
local CLR = {
    bg          = Color3.fromRGB(15, 15, 24),
    header      = Color3.fromRGB(22, 22, 36),
    headerGrad  = Color3.fromRGB(30, 25, 50),
    card        = Color3.fromRGB(24, 24, 38),
    cardHover   = Color3.fromRGB(30, 30, 48),
    accent      = Color3.fromRGB(110, 68, 255),
    accentDim   = Color3.fromRGB(80, 50, 180),
    text        = Color3.fromRGB(235, 235, 245),
    textDim     = Color3.fromRGB(130, 130, 155),
    green       = Color3.fromRGB(45, 200, 95),
    red         = Color3.fromRGB(240, 60, 60),
    orange      = Color3.fromRGB(245, 170, 45),
    yellow      = Color3.fromRGB(245, 215, 50),
    cyan        = Color3.fromRGB(50, 195, 240),
    toggleOff   = Color3.fromRGB(60, 60, 80),
    border      = Color3.fromRGB(42, 42, 62),
    sliderBg    = Color3.fromRGB(32, 32, 50),
    shadow      = Color3.fromRGB(0, 0, 0),
    notifBg     = Color3.fromRGB(28, 28, 44),
    tabActive   = Color3.fromRGB(35, 35, 55),
    tabInactive = Color3.fromRGB(20, 20, 32),
    tooltipBg   = Color3.fromRGB(18, 18, 30),
}

--- Category-specific toggle colors
local CAT_COLORS = {
    Combat   = Color3.fromRGB(177, 100, 255),
    Defense  = Color3.fromRGB(100, 150, 255),
    Survival = Color3.fromRGB(100, 255, 150),
    Utility  = Color3.fromRGB(255, 200, 100),
    System   = Color3.fromRGB(180, 180, 180),
}

local TWEEN_FAST   = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TWEEN_SMOOTH = TweenInfo.new(0.20, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local TWEEN_BOUNCE = TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

----------------------------------------------------------------
-- S6. REMOTE DETECTION
----------------------------------------------------------------

--- Find a RemoteEvent by name across known locations
-- @param name string
-- @return RemoteEvent|nil
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
            if v:IsA("RemoteEvent") and v.Name == name then r = v end
        end
    end)
    if r then return r end
    pcall(function()
        if type(getinstances) == "function" then
            for _, v in ipairs(getinstances()) do
                if v:IsA("RemoteEvent") and v.Name == name then r = v end
            end
        end
    end)
    return r
end

local REM = {
    Punch      = FindRemote("PUNCHEVENT"),
    Suplex     = FindRemote("SUPLEXEVENT"),
    HeavyHit   = FindRemote("HEAVYHIT"),
    Block      = FindRemote("BLOCKEVENT"),
    Stomp      = FindRemote("STOMPEVENT"),
    ToolHit    = FindRemote("TOOLHITEVENT"),
    Stun       = FindRemote("STUNEVENT"),
    Heal       = FindRemote("HEALCHARACTERCARRIED"),
    Carniceria = FindRemote("Carniceria"),
    Carry      = FindRemote("CARRYEVENT"),
    Throw      = FindRemote("THROWCHARACTEREVENT"),
    Crouch     = FindRemote("CROUCHEVENT"),
    StopAnim   = FindRemote("STOPLOCALANIMATIONS"),
    PVPToggle  = FindRemote("PVPONOFFEVENT"),
    PickupTool = FindRemote("PICKUPTOOLSEVENT"),
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
-- S7. REGISTRY SYSTEMS
----------------------------------------------------------------

--- Keyword lists for classification
local FOOD_KEYWORDS = {
    "food","pizza","burger","meat","steak","chicken","sandwich","hotdog",
    "taco","burrito","soda","drink","water","juice","milk","apple",
    "bread","donut","candy","chips","snack","fries","rice","soup",
    "heal","health","potion","bandage","medkit","med","carne","torta",
    "empanada","elote","churro","pollo","bistec","carnitas","barbacoa","asada",
}

local WEAPON_KEYWORDS = {
    "bat","metal","weapon","knife","sword","pipe","gun","pistol","rifle",
    "shotgun","tool","crowbar","machete","hammer","axe","stick","club",
    "chain","wrench","bottle","brick","rock","pan","shovel",
}

--- Check if a name matches food keywords
local function IsLikelyFood(name)
    local lower = name:lower()
    for _, kw in ipairs(FOOD_KEYWORDS) do
        if lower:find(kw) then return true end
    end
    return false
end

--- Check if a name matches weapon keywords
local function IsLikelyWeapon(name)
    local lower = name:lower()
    for _, kw in ipairs(WEAPON_KEYWORDS) do
        if lower:find(kw) then return true end
    end
    return false
end

-- ===== NPC REGISTRY (event-driven) =====

--- Attempt to register a model as an NPC
-- @param model Model
local function TryRegisterNPC(model)
    if not model or not model:IsA("Model") then return end
    if Players:GetPlayerFromCharacter(model) then return end
    local hum = model:FindFirstChildOfClass("Humanoid")
    local hrp = model:FindFirstChild("HumanoidRootPart")
    if hum and hrp and hum.Health > 0 then
        ST.NPCRegistry[model] = { humanoid = hum, hrp = hrp, addedAt = tick() }
        -- Auto-deregister on death
        local deathConn
        deathConn = hum.Died:Connect(function()
            ST.NPCRegistry[model] = nil
            if deathConn then deathConn:Disconnect() end
        end)
        table.insert(ST.Connections, deathConn)
    end
end

--- Deregister an NPC model
local function DeregisterNPC(model)
    ST.NPCRegistry[model] = nil
end

--- Initialize NPC registry with one-time scan + listeners
local function InitNPCRegistry()
    -- Initial population
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("Humanoid") and obj.Parent then
            TryRegisterNPC(obj.Parent)
        end
    end
    -- Live listeners
    Conn(workspace.DescendantAdded, function(obj)
        if obj:IsA("Humanoid") and obj.Parent then
            task.defer(function() TryRegisterNPC(obj.Parent) end)
        end
    end)
    Conn(workspace.DescendantRemoving, function(obj)
        if obj:IsA("Humanoid") and obj.Parent then
            DeregisterNPC(obj.Parent)
        elseif obj:IsA("Model") then
            DeregisterNPC(obj)
        end
    end)
    Log("NPC Registry initialized with", 0, "entries (async)")
end

-- ===== TOOL REGISTRY (event-driven) =====

local TOOL_FOLDERS = {
    "Drops", "Items", "Weapons", "Loot", "DroppedItems",
    "DropItems", "Tools", "Pickups", "SpawnedItems",
}

--- Get a position reference from a tool/model/part
-- @param obj Instance
-- @return BasePart|nil
local function GetToolPart(obj)
    if obj:IsA("Tool") then
        return obj:FindFirstChild("Handle")
    elseif obj:IsA("Model") then
        return obj.PrimaryPart
            or obj:FindFirstChild("Handle")
            or obj:FindFirstChildWhichIsA("BasePart")
    elseif obj:IsA("BasePart") then
        return obj
    end
    return nil
end

--- Register a potential pickup item
-- @param obj Instance
local function TryRegisterTool(obj)
    if ST.ToolRegistry[obj] then return end
    -- Must be a Tool, weapon-like Model, or weapon-like Part
    local validType = obj:IsA("Tool")
        or (obj:IsA("Model") and IsLikelyWeapon(obj.Name))
        or (obj:IsA("BasePart") and IsLikelyWeapon(obj.Name))
    if not validType then return end
    -- Don't register tools already in a player's backpack or character
    if obj:FindFirstAncestorOfClass("Backpack") then return end
    if Players:GetPlayerFromCharacter(obj:FindFirstAncestorOfClass("Model") or obj) then return end
    local part = GetToolPart(obj)
    if not part then return end
    ST.ToolRegistry[obj] = {
        instance          = obj,
        name              = obj.Name,
        part              = part,
        hasClickDetector  = obj:FindFirstChildWhichIsA("ClickDetector", true) ~= nil,
        hasProximityPrompt = obj:FindFirstChildWhichIsA("ProximityPrompt", true) ~= nil,
        failCount         = 0,
        blacklistedUntil  = 0,
    }
end

--- Deregister a tool
local function DeregisterTool(obj)
    ST.ToolRegistry[obj] = nil
end

--- Initialize tool registry
local function InitToolRegistry()
    -- Scan workspace top-level
    for _, obj in ipairs(workspace:GetChildren()) do
        TryRegisterTool(obj)
    end
    -- Scan known folders
    for _, folderName in ipairs(TOOL_FOLDERS) do
        local folder = workspace:FindFirstChild(folderName)
        if folder then
            for _, obj in ipairs(folder:GetChildren()) do
                TryRegisterTool(obj)
            end
            Conn(folder.ChildAdded, function(obj)
                task.defer(function() TryRegisterTool(obj) end)
            end)
            Conn(folder.ChildRemoved, function(obj)
                DeregisterTool(obj)
            end)
        end
    end
    -- Scan nested tools
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("Tool") then TryRegisterTool(obj) end
    end
    -- Live listeners
    Conn(workspace.DescendantAdded, function(obj)
        if obj:IsA("Tool") or (obj:IsA("Model") and IsLikelyWeapon(obj.Name)) then
            task.defer(function() TryRegisterTool(obj) end)
        end
    end)
    Conn(workspace.DescendantRemoving, function(obj)
        DeregisterTool(obj)
    end)
    Log("Tool Registry initialized")
end

-- ===== FOOD ITEM CACHE (30s TTL) =====

--- Scan game for food-related item names
-- @return table list of food item name strings
local function ScanForFoodItems()
    local now = tick()
    if now - ST.FoodItemCacheTime < 30 then return ST.FoodItemCache end
    local items = {}
    local checked = {}

    -- Scan ReplicatedStorage
    pcall(function()
        for _, obj in ipairs(RepStorage:GetDescendants()) do
            if not checked[obj.Name] and IsLikelyFood(obj.Name) then
                checked[obj.Name] = true
                table.insert(items, obj.Name)
            end
            if obj:IsA("StringValue") and obj.Value ~= "" and IsLikelyFood(obj.Value) then
                if not checked[obj.Value] then
                    checked[obj.Value] = true
                    table.insert(items, obj.Value)
                end
            end
        end
    end)

    -- Scan backpack
    pcall(function()
        local bp = plr:FindFirstChild("Backpack")
        if bp then
            for _, t in ipairs(bp:GetChildren()) do
                if t:IsA("Tool") and not checked[t.Name] and IsLikelyFood(t.Name) then
                    checked[t.Name] = true
                    table.insert(items, t.Name)
                end
            end
        end
    end)

    -- Scan StarterPack
    pcall(function()
        for _, t in ipairs(StarterPack:GetChildren()) do
            if t:IsA("Tool") and not checked[t.Name] and IsLikelyFood(t.Name) then
                checked[t.Name] = true
                table.insert(items, t.Name)
            end
        end
    end)

    ST.FoodItemCache = items
    ST.FoodItemCacheTime = now
    Log("Food scan found", #items, "items")
    return items
end

-- Initialize registries
InitNPCRegistry()
InitToolRegistry()
task.defer(ScanForFoodItems)

----------------------------------------------------------------
-- S7b. NETWORK SNIFFING (Food Signature Discovery)
----------------------------------------------------------------

--- Attempt to hook __namecall on Carniceria to discover args
local function TrySniffFoodSignature()
    if not CAN_HOOK_META or not REM.Carniceria then return end
    pcall(function()
        local oldNamecall
        oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
            local method = getnamecallmethod()
            if self == REM.Carniceria and (method == "FireServer" or method == "fireServer") then
                local args = {...}
                if #args > 0 and not CFG.CachedFoodSignature then
                    CFG.CachedFoodSignature = args
                    Log("Food signature sniffed:", unpack(args))
                    AddLogEntry("system", "Food remote signature discovered")
                end
            end
            return oldNamecall(self, ...)
        end)
    end)
end

TrySniffFoodSignature()

----------------------------------------------------------------
-- S8. CORE COMBAT FUNCTIONS
----------------------------------------------------------------

--- Set guard state via remote
-- @param state boolean
local function SetGuard(state)
    if not CFG.UseAutoGuard or not REM.Block then return end
    local now = tick()
    if now - ST.LastGuardTime < CFG.GuardCooldown then return end
    if state == ST.GuardActive then return end
    local ok = SafeCall(function() REM.Block:FireServer(state) end)
    if ok then
        ST.GuardActive = state
        ST.LastGuardTime = now
    end
end

--- Validate a target model
-- @param model Model
-- @return boolean
local function IsValid(model)
    if not model or not model.Parent then return false end
    local h = model:FindFirstChildOfClass("Humanoid")
    local r = model:FindFirstChild("HumanoidRootPart")
    if not h or not r then return false end
    if h.Health <= CFG.MinHealth then return false end
    if not CFG.IgnoreForceField and model:FindFirstChildWhichIsA("ForceField") then
        return false
    end
    -- Check whitelist
    local p = Players:GetPlayerFromCharacter(model)
    if p then
        if IsWhitelisted(p.Name) then return false end
        if CFG.AutoWhitelistFriends and IsFriend(p) then return false end
    end
    return true
end

--- Refresh target list using NPC registry + player iteration
local function RefreshTargets()
    local list = {}
    local playerChars = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Character then playerChars[p.Character] = p end
    end

    -- Player targets
    if CFG.TargetPlayers then
        for c, p in pairs(playerChars) do
            if p ~= plr and IsValid(c) then
                list[#list + 1] = c
            end
        end
    end

    -- NPC targets via registry (no GetDescendants!)
    if CFG.TargetNPCs then
        for model, data in pairs(ST.NPCRegistry) do
            if model and model.Parent
               and not playerChars[model]
               and data.humanoid and data.humanoid.Health > CFG.MinHealth
               and data.hrp and data.hrp.Parent then
                if CFG.IgnoreForceField or not model:FindFirstChildWhichIsA("ForceField") then
                    list[#list + 1] = model
                end
            else
                -- Stale entry
                ST.NPCRegistry[model] = nil
            end
        end
    end

    ST.TargetCache = list
    ST.TargetsFound = #list
    ST.LastTargetUpdate = tick()
end

--- Score a target for prioritization
-- @param model Model the target
-- @param playerPos Vector3 local player position
-- @return number score (higher = higher priority)
local function ScoreTarget(model, playerPos)
    local hrp = model:FindFirstChild("HumanoidRootPart")
    if not hrp then return -math.huge end
    local dist = (hrp.Position - playerPos).Magnitude
    local hum = model:FindFirstChildOfClass("Humanoid")
    local priority = CFG.TargetPriority

    -- Blacklist bonus
    local p = Players:GetPlayerFromCharacter(model)
    local bonus = 0
    if p and IsBlacklisted(p.Name) then bonus = 10000 end

    if priority == "Nearest" then
        return -dist + bonus
    elseif priority == "LowestHP" then
        local hp = hum and hum.Health or 999999
        return -hp + bonus - dist * 0.001
    elseif priority == "HighestThreat" then
        local threat = ST.ThreatTable[model.Name] or 0
        return threat + bonus - dist * 0.01
    end
    return -dist + bonus
end

--- Fire attack remotes at a target
-- When ONESHOT_HOOKED, passes -9e9 as the damage arg directly in FireServer
-- so the server registers an instant kill. Falls back to 50 if not active.
-- @param target Model
local function Attack(target)
    if not target or not target.Parent then return end
    local part = target:FindFirstChild(CFG.TargetPart)
        or target:FindFirstChild("UpperTorso")
        or target:FindFirstChild("HumanoidRootPart")
    if not part then return end

    -- Damage value: -9e9 for one-shot, 50 for normal
    local dmg = ONESHOT_HOOKED and -9e9 or 50

    pcall(function()
        local usedTool = false
        if CFG.PreferWeaponOverFist and CFG.UseToolAttack and REM.ToolHit then
            REM.ToolHit:FireServer(target, part)
            REM.ToolHit:FireServer(1, target, dmg, part)
            ST.TotalToolHits += 1
            usedTool = true
        end

        if not usedTool or not CFG.PreferWeaponOverFist then
            if CFG.UsePunch and REM.Punch then
                REM.Punch:FireServer(1, target, dmg, part)
            end
            if CFG.UseSuplex and REM.Suplex then
                REM.Suplex:FireServer(1, target, dmg, part)
            end
            if CFG.UseHeavyHit and REM.HeavyHit then
                REM.HeavyHit:FireServer(1, target, dmg, part)
            end
        end

        if not CFG.PreferWeaponOverFist and CFG.UseToolAttack and REM.ToolHit then
            REM.ToolHit:FireServer(target, part)
            ST.TotalToolHits += 1
        end

        if CFG.UseAnimCancel and REM.StopAnim then
            task.delay(CFG.AnimCancelDelay, function()
                pcall(function() REM.StopAnim:FireServer() end)
            end)
        end
    end)

    ST.TotalAttacks += 1
end

--- Invalidate enemy-nearby cache
local function InvalidateNearbyCache()
    _nearbyCache.lastCheck = 0
end

--- Check for enemy within range (cached)
-- @param range number
-- @return boolean
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

    -- Check players
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

    -- Check NPC registry
    if CFG.TargetNPCs then
        for model, data in pairs(ST.NPCRegistry) do
            if model and model.Parent and data.hrp and data.hrp.Parent then
                if (pos - data.hrp.Position).Magnitude <= range then
                    _nearbyCache.result = true
                    return true
                end
            end
        end
    end

    _nearbyCache.result = false
    return false
end

--- Downed-state detection attributes
local DOWNED_ATTRIBUTES = {
    "Ragdolled","KnockedDown","Downed","Stunned",
    "IsDown","Ragdoll","IsRagdoll","KO",
}

--- Check if a character is in a downed/ragdoll state
-- @param character Model
-- @return boolean
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
                or n:find("down") or n:find("stun")) and child.Value then
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

--- Try auto-stomp on nearby downed players
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
                    ST.TotalStomps += 1
                    ST.LastStompTime = now
                    AddLogEntry("kill", "Stomped " .. p.Name)
                end
                return
            end
        end
    end
end

--- Try auto-stun on nearby standing players
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
                pcall(function()
                    REM.Stun:FireServer(p.Character)
                    REM.Stun:FireServer(p)
                end)
                ST.TotalStuns += 1
                ST.LastStunTime = now
                return
            end
        end
    end
end

----------------------------------------------------------------
-- S9. SURVIVAL SYSTEMS
----------------------------------------------------------------

--- Try to heal via remote
local function TryHeal()
    if not CFG.UseAutoHeal then return end
    if not humanoid or humanoid.Health <= 0 then return end
    local now = tick()
    if now - ST.LastHealTime < CFG.HealCooldown then return end
    local hpPct = (humanoid.Health / humanoid.MaxHealth) * 100
    if hpPct > CFG.HealThreshold then
        ST.AutoHealActive = false
        return
    end
    ST.AutoHealActive = true
    if REM.Heal then
        pcall(function()
            REM.Heal:FireServer()
            REM.Heal:FireServer(char)
        end)
        ST.TotalHeals += 1
        ST.LastHealTime = now
        AddLogEntry("heal", string.format("Auto-heal at %d%% HP", math.floor(hpPct)))
    end
end

--- Intelligent food purchase with signature caching
local function TryBuyFood()
    if not CFG.UseAutoBuyFood or not REM.Carniceria then return end
    if not humanoid or humanoid.Health <= 0 then return end
    local now = tick()
    if now - ST.LastFoodBuy < CFG.BuyFoodCooldown then return end
    local hpPct = (humanoid.Health / humanoid.MaxHealth) * 100
    if hpPct > CFG.HealThreshold then return end

    local healthBefore = humanoid.Health

    -- Phase 1: Use cached signature if available
    if CFG.CachedFoodSignature then
        pcall(function()
            REM.Carniceria:FireServer(unpack(CFG.CachedFoodSignature))
        end)
        ST.LastFoodBuy = now
        ST.TotalFoodBuys += 1

        -- Verify it still works
        task.delay(0.5, function()
            if humanoid and humanoid.Health > healthBefore then
                ST.FoodSigFails = 0
                AddLogEntry("heal", "Food purchased (cached sig)")
            else
                ST.FoodSigFails += 1
                if ST.FoodSigFails >= 3 then
                    CFG.CachedFoodSignature = nil
                    ST.FoodProbeIndex = 0
                    ST.FoodSigFails = 0
                    AddLogEntry("error", "Food sig invalidated, re-probing")
                end
            end
        end)
        return
    end

    -- Phase 2: Tiered probing (ONE attempt per cycle, stop on success)
    local foods = ScanForFoodItems()
    local probes = {
        function() REM.Carniceria:FireServer() end,
        function() REM.Carniceria:FireServer(true) end,
        function() REM.Carniceria:FireServer(1) end,
        function() REM.Carniceria:FireServer("Buy") end,
        function() REM.Carniceria:FireServer("Comprar") end,
    }
    -- Add scanned food items as probes
    for _, fname in ipairs(foods) do
        table.insert(probes, function() REM.Carniceria:FireServer(fname) end)
        table.insert(probes, function() REM.Carniceria:FireServer("Buy", fname) end)
    end

    ST.FoodProbeIndex += 1
    if ST.FoodProbeIndex > #probes then ST.FoodProbeIndex = 1 end

    local probeIdx = ST.FoodProbeIndex
    local probeOk = pcall(probes[probeIdx])
    ST.LastFoodBuy = now
    ST.TotalFoodBuys += 1

    if probeOk then
        -- Check health delta after 0.5s
        task.delay(0.5, function()
            if humanoid and humanoid.Health > healthBefore then
                -- This signature worked! Cache it.
                -- Reconstruct the args from the probe
                local sigTable = nil
                if probeIdx == 1 then sigTable = {}
                elseif probeIdx == 2 then sigTable = {true}
                elseif probeIdx == 3 then sigTable = {1}
                elseif probeIdx == 4 then sigTable = {"Buy"}
                elseif probeIdx == 5 then sigTable = {"Comprar"}
                else
                    -- Food item probe
                    local adjustedIdx = probeIdx - 5
                    local foodIdx = math.ceil(adjustedIdx / 2)
                    if foodIdx <= #foods then
                        if adjustedIdx % 2 == 1 then
                            sigTable = {foods[foodIdx]}
                        else
                            sigTable = {"Buy", foods[foodIdx]}
                        end
                    end
                end
                if sigTable then
                    CFG.CachedFoodSignature = sigTable
                    ST.FoodSigFails = 0
                    Notify("Food signature discovered!", "success", 3)
                    AddLogEntry("system", "Food remote signature cached")
                    AutoSave()
                end
            end
        end)
    end
end

----------------------------------------------------------------
-- S10. UTILITY SYSTEMS
----------------------------------------------------------------

--- Intelligent tool pickup with tiered fallback + dedup
local function TryPickupTools()
    if not CFG.UseAutoPickupTools then return end
    local now = tick()
    if now - ST.LastToolPickup < CFG.ToolPickupCooldown then return end
    if not rootPart or not rootPart.Parent then return end
    local pos = rootPart.Position
    local backpack = plr:FindFirstChild("Backpack")
    if not backpack then return end

    -- Build sorted list from registry
    local candidates = {}
    for obj, data in pairs(ST.ToolRegistry) do
        if obj and obj.Parent and data.part and data.part.Parent then
            -- Skip blacklisted
            if data.blacklistedUntil > 0 and now < data.blacklistedUntil then
                continue
            end
            -- Skip if in a player's backpack/character now
            if obj:FindFirstAncestorOfClass("Backpack") then
                DeregisterTool(obj)
                continue
            end
            local dist = (pos - data.part.Position).Magnitude
            if dist <= CFG.ToolPickupRange then
                table.insert(candidates, { obj = obj, data = data, dist = dist })
            end
        else
            -- Stale
            ST.ToolRegistry[obj] = nil
        end
    end

    if #candidates == 0 then return end

    table.sort(candidates, function(a, b) return a.dist < b.dist end)

    -- Process top 3 nearest
    local processed = 0
    for _, cand in ipairs(candidates) do
        if processed >= 3 then break end
        processed += 1

        local obj = cand.obj
        local data = cand.data
        local pickedUp = false

        -- Tier 1: Direct parent to backpack
        pcall(function()
            if obj:IsA("Tool") then
                obj.Parent = backpack
                pickedUp = true
            end
        end)

        -- Check if it worked
        if not pickedUp then
            task.wait(0.1)
            if obj.Parent == backpack then pickedUp = true end
        end

        -- Tier 2: Minimal remote fires (if remote exists)
        if not pickedUp and REM.PickupTool then
            pcall(function() REM.PickupTool:FireServer(obj) end)
            task.wait(0.1)
            if obj.Parent == backpack then
                pickedUp = true
            else
                pcall(function() REM.PickupTool:FireServer(obj.Name) end)
                task.wait(0.1)
                if obj.Parent == backpack then
                    pickedUp = true
                else
                    pcall(function() REM.PickupTool:FireServer(obj, data.part) end)
                    task.wait(0.1)
                    if obj.Parent == backpack then pickedUp = true end
                end
            end
        end

        -- Tier 3: ClickDetector
        if not pickedUp and data.hasClickDetector and CAN_FIRE_CLICK then
            local cd = obj:FindFirstChildWhichIsA("ClickDetector", true)
            if cd then
                pcall(function() fireclickdetector(cd) end)
                task.wait(0.15)
                if obj.Parent == backpack or not obj.Parent then pickedUp = true end
            end
        end

        -- Tier 4: ProximityPrompt
        if not pickedUp and data.hasProximityPrompt and CAN_FIRE_PROMPT then
            local pp = obj:FindFirstChildWhichIsA("ProximityPrompt", true)
            if pp then
                pcall(function() fireproximityprompt(pp) end)
                task.wait(0.15)
                if obj.Parent == backpack or not obj.Parent then pickedUp = true end
            end
        end

        -- Result
        if pickedUp then
            DeregisterTool(obj)
            ST.TotalPickups += 1
            Notify("Picked up: " .. data.name, "success", 2)
            AddLogEntry("pickup", "Picked up " .. data.name)
        else
            data.failCount += 1
            if data.failCount >= 3 then
                data.blacklistedUntil = now + 30
                data.failCount = 0
                Log("Tool blacklisted for 30s:", data.name)
            end
        end
    end

    ST.LastToolPickup = now
end

--- Carry and throw downed players
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
                pcall(function()
                    REM.Carry:FireServer(p.Character)
                end)
                task.wait(CFG.CarryDuration)
                pcall(function()
                    REM.Throw:FireServer()
                    REM.Throw:FireServer(rootPart.CFrame.LookVector)
                end)
                ST.TotalThrows += 1
                ST.LastCarryTime = tick()
                ST.IsCarrying = false
                AddLogEntry("system", "Threw " .. p.Name)
                return
            end
        end
    end
end

--- Smart PVP management
local function ManagePVP()
    if not CFG.UseSmartPVP or not REM.PVPToggle then return end
    if not humanoid or humanoid.Health <= 0 then return end
    local now = tick()
    if now - ST.LastPVPToggle < 1.0 then return end
    local hpPct = (humanoid.Health / humanoid.MaxHealth) * 100
    if hpPct <= CFG.PVPOffThreshold and ST.PVPEnabled then
        pcall(function()
            REM.PVPToggle:FireServer(false)
            REM.PVPToggle:FireServer("Off")
        end)
        ST.PVPEnabled = false
        ST.LastPVPToggle = now
        AddLogEntry("system", "PVP OFF (low HP)")
    elseif hpPct >= CFG.PVPOnThreshold and not ST.PVPEnabled then
        pcall(function()
            REM.PVPToggle:FireServer(true)
            REM.PVPToggle:FireServer("On")
        end)
        ST.PVPEnabled = true
        ST.LastPVPToggle = now
        AddLogEntry("system", "PVP ON")
    end
end

----------------------------------------------------------------
-- S11. DPS TRACKER
----------------------------------------------------------------

--- Record a damage event for DPS calculation
-- @param delta number positive health change (damage dealt)
local function RecordDamage(delta)
    if delta <= 0 then return end
    table.insert(ST.DPSHistory, { time = tick(), delta = delta })
end

--- Calculate current DPS over the tracking window
-- @return number
local function CalculateDPS()
    local now = tick()
    local window = CFG.DPSTrackingWindow
    local total = 0
    local newHistory = {}
    for _, entry in ipairs(ST.DPSHistory) do
        if now - entry.time <= window then
            total += entry.delta
            table.insert(newHistory, entry)
        end
    end
    ST.DPSHistory = newHistory
    ST.CurrentDPS = total / math.max(window, 0.1)
    return ST.CurrentDPS
end

----------------------------------------------------------------
-- S12. KILL ALL
----------------------------------------------------------------

--- Run the Kill All targeting loop
-- Attack() now carries the one-shot damage value (-9e9) directly when
-- ONESHOT_HOOKED is true, so this loop needs no special casing.
local function RunKillAll()
    if not HAS_ATTACK then
        Notify("No attack remotes found", "error")
        return
    end
    ST.KillAllRunning = true
    ST.CurrentMode = "KillAll"
    Notify("Kill All engaged" .. (ONESHOT_HOOKED and " [ONE-SHOT]" or ""), "warning", 2)
    AddLogEntry("system", "Kill All STARTED" .. (ONESHOT_HOOKED and " (one-shot)" or ""))

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
                if IsWhitelisted(p.Name) then continue end
                if CFG.AutoWhitelistFriends and IsFriend(p) then continue end
                local h = p.Character:FindFirstChildOfClass("Humanoid")
                local r = p.Character:FindFirstChild("HumanoidRootPart")
                if h and r and h.Health > 0 then
                    targets[#targets + 1] = {
                        player = p,
                        dist = (myPos - r.Position).Magnitude,
                    }
                end
            end
        end

        if #targets == 0 then
            ST.KillAllTarget = "No targets"
            ST.KillAllProgress = "0/0"
            task.wait(1.5)
            continue
        end

        table.sort(targets, function(a, b) return a.dist < b.dist end)

        for i, entry in ipairs(targets) do
            if not CFG.KillAllActive or not CFG.Enabled or not ST.Running then break end
            local target = entry.player
            local tChar = target.Character
            if not tChar then continue end
            local tRoot = tChar:FindFirstChild("HumanoidRootPart")
            local tHum = tChar:FindFirstChildOfClass("Humanoid")
            if not tRoot or not tHum or tHum.Health <= 0 then continue end

            ST.KillAllTarget = target.Name
            ST.KillAllProgress = i .. "/" .. #targets

            -- Teleport to target
            GetChar()
            if rootPart and rootPart.Parent then
                rootPart.CFrame = tRoot.CFrame * CFrame.new(0, 0, 3)
                InvalidateNearbyCache()
            end
            task.wait(CFG.KillAllTeleportDelay)

            -- Reteleport if needed
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

            -- Attack loop — Attack() handles one-shot damage internally
            local startTime = tick()
            while CFG.KillAllActive and CFG.Enabled and ST.Running do
                tChar = target.Character
                if not tChar then break end
                tHum = tChar:FindFirstChildOfClass("Humanoid")
                tRoot = tChar:FindFirstChild("HumanoidRootPart")
                if not tHum or tHum.Health <= 0 or not tRoot then break end

                GetChar()
                if not rootPart or not rootPart.Parent then break end
                if tick() - startTime > CFG.KillAllTimeout then break end

                local dist = (rootPart.Position - tRoot.Position).Magnitude
                if dist > CFG.KillAllReteleportDist then
                    rootPart.CFrame = tRoot.CFrame * CFrame.new(0, 0, 3)
                    InvalidateNearbyCache()
                    task.wait(0.05)
                end

                Attack(tChar)

                if CFG.UseAutoStomp and REM.Stomp and IsPlayerDown(tChar) then
                    pcall(function() REM.Stomp:FireServer() end)
                    ST.TotalStomps += 1
                end

                task.wait(1 / math.max(CFG.AttacksPerSecond, 1))
            end

            -- Check kill
            local killed = false
            pcall(function()
                local tc = target.Character
                if tc then
                    local th = tc:FindFirstChildOfClass("Humanoid")
                    if th and th.Health <= 0 then killed = true end
                end
            end)
            if killed then
                ST.KillAllKills += 1
                Notify("Killed " .. target.Name .. " (" .. ST.KillAllKills .. ")", "success", 2)
                AddLogEntry("kill", "Killed " .. target.Name)
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

    ST.KillAllRunning = false
    ST.KillAllTarget = ""
    ST.KillAllProgress = ""
    ST.CurrentMode = nil
    Notify("Kill All disengaged", "info", 2)
    AddLogEntry("system", "Kill All STOPPED")
end

----------------------------------------------------------------
-- S13. KILL AURA VISUALIZATION
----------------------------------------------------------------

--- Create or destroy the kill aura ring
local function UpdateAuraRing()
    if CFG.KillAuraVisualization and CFG.Enabled then
        if not ST.AuraRing then
            local ring = Instance.new("Part")
            ring.Name = "MAPAuraRing"
            ring.Anchored = true
            ring.CanCollide = false
            ring.Shape = Enum.PartType.Cylinder
            ring.Material = Enum.Material.Neon
            ring.Color = CLR.accent
            ring.Transparency = 0.85
            ring.Size = Vector3.new(0.1, CFG.AttackRange * 2, CFG.AttackRange * 2)
            ring.CFrame = CFrame.new(0, -1000, 0)
            ring.Parent = workspace
            ST.AuraRing = ring
        end
        if not ST.AuraConn then
            ST.AuraConn = Conn(RunService.RenderStepped, function(dt)
                if ST.AuraRing and rootPart and rootPart.Parent then
                    local cf = rootPart.CFrame
                    ST.AuraRing.CFrame = CFrame.new(cf.Position)
                        * CFrame.Angles(0, 0, math.rad(90))
                    ST.AuraRing.Size = Vector3.new(0.1, CFG.AttackRange * 2, CFG.AttackRange * 2)
                end
            end)
        end
    else
        if ST.AuraRing then
            ST.AuraRing:Destroy()
            ST.AuraRing = nil
        end
        if ST.AuraConn then
            ST.AuraConn:Disconnect()
            ST.AuraConn = nil
        end
    end
end

----------------------------------------------------------------
-- S14. ESP OVERLAY
----------------------------------------------------------------

--- Create or update ESP billboard for a target
-- @param model Model
local function CreateESP(model)
    if not CFG.ESPEnabled then return end
    if ST.ESPPool[model] then return end
    local hrp = model:FindFirstChild("HumanoidRootPart")
    local hum = model:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum then return end

    if #ST.ESPPool >= 5 then return end -- Max 5 ESP displays

    local bb = Instance.new("BillboardGui")
    bb.Name = "MAPESP"
    bb.Adornee = hrp
    bb.Size = UDim2.new(0, 120, 0, 40)
    bb.StudsOffset = Vector3.new(0, 3, 0)
    bb.AlwaysOnTop = true

    local nameL = Instance.new("TextLabel")
    nameL.Size = UDim2.new(1, 0, 0, 16)
    nameL.BackgroundTransparency = 1
    nameL.Text = model.Name
    nameL.TextColor3 = CLR.text
    nameL.TextSize = 11
    nameL.Font = Enum.Font.GothamBold
    nameL.Parent = bb

    local barBg = Instance.new("Frame")
    barBg.Size = UDim2.new(1, -10, 0, 6)
    barBg.Position = UDim2.new(0, 5, 0, 18)
    barBg.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    barBg.BorderSizePixel = 0
    barBg.Parent = bb
    Instance.new("UICorner", barBg).CornerRadius = UDim.new(0, 3)

    local barFill = Instance.new("Frame")
    barFill.Size = UDim2.new(math.clamp(hum.Health / hum.MaxHealth, 0, 1), 0, 1, 0)
    barFill.BackgroundColor3 = CLR.green
    barFill.BorderSizePixel = 0
    barFill.Parent = barBg
    Instance.new("UICorner", barFill).CornerRadius = UDim.new(0, 3)

    local distL = Instance.new("TextLabel")
    distL.Size = UDim2.new(1, 0, 0, 14)
    distL.Position = UDim2.new(0, 0, 0, 26)
    distL.BackgroundTransparency = 1
    distL.Text = "0m"
    distL.TextColor3 = CLR.textDim
    distL.TextSize = 9
    distL.Font = Enum.Font.Gotham
    distL.Parent = bb

    bb.Parent = game:GetService("CoreGui")

    ST.ESPPool[model] = {
        billboard = bb,
        barFill = barFill,
        distLabel = distL,
        humanoid = hum,
        hrp = hrp,
    }
end

--- Remove ESP for a model
local function RemoveESP(model)
    local data = ST.ESPPool[model]
    if data then
        if data.billboard then data.billboard:Destroy() end
        ST.ESPPool[model] = nil
    end
end

--- Clear all ESP
local function ClearAllESP()
    for model, _ in pairs(ST.ESPPool) do
        RemoveESP(model)
    end
end

--- Update all active ESP displays
local function UpdateESP()
    if not CFG.ESPEnabled then
        ClearAllESP()
        return
    end
    for model, data in pairs(ST.ESPPool) do
        if not model or not model.Parent or not data.hrp or not data.hrp.Parent then
            RemoveESP(model)
        else
            local hum = data.humanoid
            if hum and hum.Parent then
                local ratio = math.clamp(hum.Health / hum.MaxHealth, 0, 1)
                data.barFill.Size = UDim2.new(ratio, 0, 1, 0)
                -- Color gradient: red→yellow→green
                if ratio > 0.5 then
                    data.barFill.BackgroundColor3 = CLR.green:Lerp(CLR.yellow, (1 - ratio) * 2)
                else
                    data.barFill.BackgroundColor3 = CLR.yellow:Lerp(CLR.red, (0.5 - ratio) * 2)
                end
            end
            if rootPart and rootPart.Parent and data.hrp and data.hrp.Parent then
                local dist = math.floor((rootPart.Position - data.hrp.Position).Magnitude)
                data.distLabel.Text = dist .. "m"
            end
        end
    end
end

----------------------------------------------------------------
-- S15. GUI CONSTRUCTION
----------------------------------------------------------------
local GUI_REFS

local function BuildGUI()
    -- Cleanup existing
    local existing
    pcall(function() existing = game:GetService("CoreGui"):FindFirstChild("MassAttackPro") end)
    if not existing then
        local pg = plr:FindFirstChild("PlayerGui")
        if pg then existing = pg:FindFirstChild("MassAttackPro") end
    end
    if existing then existing:Destroy() end

    local sg = Instance.new("ScreenGui")
    sg.Name = "MassAttackPro"
    sg.ResetOnSpawn = false
    sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    sg.DisplayOrder = 999
    ParentGui(sg)

    -- Helper: UICorner
    local function Corner(p, r)
        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, r or 8)
        c.Parent = p
    end

    -- Helper: UIStroke
    local function Stroke(p, col, t)
        local s = Instance.new("UIStroke")
        s.Color = col or CLR.border
        s.Thickness = t or 1
        s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        s.Parent = p
    end

    -- Helper: Hover effect
    local function Hover(el, normal, hovered)
        el.MouseEnter:Connect(function()
            TweenService:Create(el, TWEEN_FAST, {BackgroundColor3 = hovered}):Play()
        end)
        el.MouseLeave:Connect(function()
            TweenService:Create(el, TWEEN_FAST, {BackgroundColor3 = normal}):Play()
        end)
    end

    -- ==========================================
    -- NOTIFICATION SYSTEM (max 5 visible)
    -- ==========================================
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
            _notifOrder += 1
            local col = NOTIF_COLORS[nType] or CLR.accent

            -- Enforce max 5 visible
            while #ST.ActiveNotifs >= 5 do
                local oldest = table.remove(ST.ActiveNotifs, 1)
                if oldest and oldest.Parent then oldest:Destroy() end
            end

            local frame = Instance.new("Frame")
            frame.Size = UDim2.new(1, 0, 0, 36)
            frame.BackgroundColor3 = CLR.notifBg
            frame.BackgroundTransparency = 1
            frame.BorderSizePixel = 0
            frame.LayoutOrder = _notifOrder
            frame.ClipsDescendants = true
            frame.Parent = notifContainer
            Corner(frame, 8)

            table.insert(ST.ActiveNotifs, frame)

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
                    TweenService:Create(frame, TweenInfo.new(0.4, Enum.EasingStyle.Quint),
                        {BackgroundTransparency = 1}):Play()
                    task.wait(0.4)
                    if frame and frame.Parent then
                        frame:Destroy()
                        -- Remove from active list
                        for i, n in ipairs(ST.ActiveNotifs) do
                            if n == frame then table.remove(ST.ActiveNotifs, i) break end
                        end
                    end
                end
            end)
        end)
    end

    -- ==========================================
    -- TOOLTIP SYSTEM
    -- ==========================================
    local TOOLTIPS = {
        ["Script Enabled"]          = "Master toggle for all combat systems.",
        ["Attack All Targets (AoE)"]= "Hit all valid targets each cycle instead of just one.",
        ["Target Players"]          = "Include other players as valid targets.",
        ["Target NPCs"]             = "Include non-player humanoids as valid targets.",
        ["Animation Cancel"]        = "Interrupts attack recovery frames to increase effective DPS.",
        ["Auto Stomp"]              = "Automatically stomp downed players within range.",
        ["Auto Stun"]               = "Automatically attempt to stun standing enemies.",
        ["Auto Guard"]              = "Automatically block when enemies are nearby.",
        ["Drop Guard to Attack"]    = "Briefly disable guard to allow attacks, then re-enable.",
        ["Ignore ForceField"]       = "Attack targets even if they have a ForceField.",
        ["Smart PVP Toggle"]        = "Auto-enables PVP at high HP, disables at low HP.",
        ["Auto Heal"]               = "Fire heal remote when HP drops below threshold.",
        ["Auto Buy Food"]           = "Attempt to buy food from shop remotes for healing.",
        ["Auto Pickup Weapons"]     = "Automatically pick up nearby dropped weapons/tools.",
        ["Auto Carry+Throw"]        = "Carry and throw downed players.",
        ["Crouch Spam"]             = "Rapidly toggle crouch for movement disruption.",
        ["Kill All (TP & Kill)"]    = "Teleport to and attack every player on the server.",
        ["Kill Aura Visualization"] = "Show a ring around you indicating attack range.",
        ["ESP Overlay"]             = "Show name, health, and distance over active targets.",
        ["Anti-AFK"]                = "Prevent being kicked for idling.",
        ["Auto Respawn"]            = "Automatically respawn and resume combat on death.",
        ["Debug Logging"]           = "Print debug information to console.",
        ["Prefer Weapon Over Fist"] = "Use equipped tool attacks before fist attacks.",
        ["DPS Tracker"]             = "Track and display your damage per second.",
    }

    local tooltipFrame = Instance.new("Frame")
    tooltipFrame.Name = "Tooltip"
    tooltipFrame.Size = UDim2.new(0, 200, 0, 30)
    tooltipFrame.BackgroundColor3 = CLR.tooltipBg
    tooltipFrame.BackgroundTransparency = 0.05
    tooltipFrame.BorderSizePixel = 0
    tooltipFrame.Visible = false
    tooltipFrame.ZIndex = 100
    tooltipFrame.Parent = sg
    Corner(tooltipFrame, 6)
    Stroke(tooltipFrame, CLR.accent, 1)

    local tooltipLabel = Instance.new("TextLabel")
    tooltipLabel.Size = UDim2.new(1, -12, 1, -6)
    tooltipLabel.Position = UDim2.new(0, 6, 0, 3)
    tooltipLabel.BackgroundTransparency = 1
    tooltipLabel.Text = ""
    tooltipLabel.TextColor3 = CLR.text
    tooltipLabel.TextSize = 10
    tooltipLabel.Font = Enum.Font.Gotham
    tooltipLabel.TextWrapped = true
    tooltipLabel.TextXAlignment = Enum.TextXAlignment.Left
    tooltipLabel.TextYAlignment = Enum.TextYAlignment.Top
    tooltipLabel.ZIndex = 101
    tooltipLabel.Parent = tooltipFrame

    local function ShowTooltip(label, guiObj)
        local tip = TOOLTIPS[label]
        if not tip then return end
        tooltipLabel.Text = tip
        -- Estimate height
        local lines = math.ceil(#tip / 30)
        tooltipFrame.Size = UDim2.new(0, 200, 0, math.max(30, lines * 14 + 10))
        -- Position below the element
        local absPos = guiObj.AbsolutePosition
        local absSize = guiObj.AbsoluteSize
        tooltipFrame.Position = UDim2.new(0, absPos.X, 0, absPos.Y + absSize.Y + 4)
        tooltipFrame.Visible = true
    end

    local function HideTooltip()
        tooltipFrame.Visible = false
    end

    -- ==========================================
    -- MAIN FRAME
    -- ==========================================
    local main = Instance.new("Frame")
    main.Name = "Main"
    main.Size = UDim2.new(0, 380, 0, 660)
    main.Position = UDim2.new(0.5, -190, 0.5, -330)
    main.BackgroundColor3 = CLR.bg
    main.BorderSizePixel = 0
    main.ClipsDescendants = true
    main.Active = true
    main.Parent = sg
    Corner(main, 12)
    Stroke(main, CLR.border, 1)

    -- Shadow
    local sh = Instance.new("ImageLabel")
    sh.Size = UDim2.new(1, 50, 1, 50)
    sh.Position = UDim2.new(0, -25, 0, -25)
    sh.BackgroundTransparency = 1
    sh.Image = "rbxassetid://6015897843"
    sh.ImageColor3 = CLR.shadow
    sh.ImageTransparency = 0.4
    sh.ScaleType = Enum.ScaleType.Slice
    sh.SliceCenter = Rect.new(49, 49, 450, 450)
    sh.ZIndex = -1
    sh.Parent = main

    -- ==========================================
    -- HEADER
    -- ==========================================
    local hdr = Instance.new("Frame")
    hdr.Name = "Header"
    hdr.Size = UDim2.new(1, 0, 0, 46)
    hdr.BackgroundColor3 = CLR.header
    hdr.BorderSizePixel = 0
    hdr.Parent = main
    Corner(hdr, 12)

    local grad = Instance.new("UIGradient")
    grad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, CLR.headerGrad),
        ColorSequenceKeypoint.new(1, CLR.header),
    })
    grad.Rotation = 90
    grad.Parent = hdr

    local hdrFix = Instance.new("Frame")
    hdrFix.Size = UDim2.new(1, 0, 0, 14)
    hdrFix.Position = UDim2.new(0, 0, 1, -14)
    hdrFix.BackgroundColor3 = CLR.header
    hdrFix.BorderSizePixel = 0
    hdrFix.Parent = hdr

    local sep = Instance.new("Frame")
    sep.Size = UDim2.new(1, -16, 0, 1)
    sep.Position = UDim2.new(0, 8, 1, 0)
    sep.BackgroundColor3 = CLR.border
    sep.BorderSizePixel = 0
    sep.Parent = hdr

    local ttl = Instance.new("TextLabel")
    ttl.Size = UDim2.new(1, -120, 1, 0)
    ttl.Position = UDim2.new(0, 14, 0, 0)
    ttl.BackgroundTransparency = 1
    ttl.Text = "⚔  MASS ATTACK PRO"
    ttl.TextColor3 = CLR.text
    ttl.TextSize = 15
    ttl.Font = Enum.Font.GothamBold
    ttl.TextXAlignment = Enum.TextXAlignment.Left
    ttl.Parent = hdr

    local verBadge = Instance.new("TextLabel")
    verBadge.Size = UDim2.new(0, 36, 0, 16)
    verBadge.Position = UDim2.new(0, 180, 0.5, -8)
    verBadge.BackgroundColor3 = CLR.accent
    verBadge.Text = "v" .. SCRIPT_VERSION
    verBadge.TextColor3 = CLR.text
    verBadge.TextSize = 9
    verBadge.Font = Enum.Font.GothamBold
    verBadge.Parent = hdr
    Corner(verBadge, 5)

    local minB = Instance.new("TextButton")
    minB.Size = UDim2.new(0, 28, 0, 28)
    minB.Position = UDim2.new(1, -68, 0.5, -14)
    minB.BackgroundColor3 = CLR.orange
    minB.Text = "—"
    minB.TextColor3 = CLR.text
    minB.TextSize = 14
    minB.Font = Enum.Font.GothamBold
    minB.AutoButtonColor = false
    minB.Parent = hdr
    Corner(minB, 7)
    Hover(minB, CLR.orange, Color3.fromRGB(255, 195, 60))

    local clsB = Instance.new("TextButton")
    clsB.Size = UDim2.new(0, 28, 0, 28)
    clsB.Position = UDim2.new(1, -36, 0.5, -14)
    clsB.BackgroundColor3 = CLR.red
    clsB.Text = "✕"
    clsB.TextColor3 = CLR.text
    clsB.TextSize = 11
    clsB.Font = Enum.Font.GothamBold
    clsB.AutoButtonColor = false
    clsB.Parent = hdr
    Corner(clsB, 7)
    Hover(clsB, CLR.red, Color3.fromRGB(255, 85, 85))

    -- DRAGGING
    do
        local dragging, dInput, dStart, sPos
        Conn(hdr.InputBegan, function(inp)
            if inp.UserInputType == Enum.UserInputType.MouseButton1
            or inp.UserInputType == Enum.UserInputType.Touch then
                dragging = true
                dStart = inp.Position
                sPos = main.Position
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
                    sPos.Y.Scale, sPos.Y.Offset + d.Y)
            end
        end)
    end

    -- ==========================================
    -- SEARCH BAR
    -- ==========================================
    local searchBar = Instance.new("Frame")
    searchBar.Size = UDim2.new(1, -14, 0, 28)
    searchBar.Position = UDim2.new(0, 7, 0, 50)
    searchBar.BackgroundColor3 = CLR.card
    searchBar.BorderSizePixel = 0
    searchBar.Parent = main
    Corner(searchBar, 6)

    local searchIcon = Instance.new("TextLabel")
    searchIcon.Size = UDim2.new(0, 24, 1, 0)
    searchIcon.Position = UDim2.new(0, 4, 0, 0)
    searchIcon.BackgroundTransparency = 1
    searchIcon.Text = "🔍"
    searchIcon.TextSize = 12
    searchIcon.Font = Enum.Font.Gotham
    searchIcon.Parent = searchBar

    local searchBox = Instance.new("TextBox")
    searchBox.Size = UDim2.new(1, -32, 1, 0)
    searchBox.Position = UDim2.new(0, 28, 0, 0)
    searchBox.BackgroundTransparency = 1
    searchBox.PlaceholderText = "Search controls..."
    searchBox.PlaceholderColor3 = CLR.textDim
    searchBox.Text = ""
    searchBox.TextColor3 = CLR.text
    searchBox.TextSize = 11
    searchBox.Font = Enum.Font.Gotham
    searchBox.TextXAlignment = Enum.TextXAlignment.Left
    searchBox.ClearTextOnFocus = false
    searchBox.Parent = searchBar

    -- ==========================================
    -- TAB BAR
    -- ==========================================
    local tabBar = Instance.new("Frame")
    tabBar.Size = UDim2.new(1, -14, 0, 30)
    tabBar.Position = UDim2.new(0, 7, 0, 82)
    tabBar.BackgroundTransparency = 1
    tabBar.Parent = main

    local tabLayout = Instance.new("UIListLayout")
    tabLayout.FillDirection = Enum.FillDirection.Horizontal
    tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
    tabLayout.Padding = UDim.new(0, 3)
    tabLayout.Parent = tabBar

    local TAB_NAMES = {"Combat", "Defense", "Survival", "Utility", "System"}
    local TAB_ICONS = {
        Combat   = "⚔",
        Defense  = "🛡",
        Survival = "❤",
        Utility  = "🔧",
        System   = "⚙",
    }

    local tabButtons = {}
    local tabFrames = {}
    local activeTab = CFG.DefaultTab

    -- ==========================================
    -- STATUS CARD (always visible above tabs)
    -- ==========================================
    local statusCard = Instance.new("Frame")
    statusCard.Size = UDim2.new(1, -14, 0, 110)
    statusCard.Position = UDim2.new(0, 7, 0, 116)
    statusCard.BackgroundColor3 = CLR.card
    statusCard.BorderSizePixel = 0
    statusCard.Parent = main
    Corner(statusCard, 8)
    Stroke(statusCard)

    -- Status dot
    local sDot = Instance.new("Frame")
    sDot.Size = UDim2.new(0, 10, 0, 10)
    sDot.Position = UDim2.new(0, 10, 0, 8)
    sDot.BackgroundColor3 = CLR.red
    sDot.BorderSizePixel = 0
    sDot.Parent = statusCard
    Corner(sDot, 5)

    local sLbl = Instance.new("TextLabel")
    sLbl.Size = UDim2.new(0, 80, 0, 14)
    sLbl.Position = UDim2.new(0, 26, 0, 6)
    sLbl.BackgroundTransparency = 1
    sLbl.Text = "DISABLED"
    sLbl.TextColor3 = CLR.red
    sLbl.TextSize = 10
    sLbl.Font = Enum.Font.GothamBold
    sLbl.TextXAlignment = Enum.TextXAlignment.Left
    sLbl.Parent = statusCard

    local sTimer = Instance.new("TextLabel")
    sTimer.Size = UDim2.new(0, 50, 0, 14)
    sTimer.Position = UDim2.new(1, -58, 0, 6)
    sTimer.BackgroundTransparency = 1
    sTimer.Text = "00:00"
    sTimer.TextColor3 = CLR.textDim
    sTimer.TextSize = 9
    sTimer.Font = Enum.Font.GothamSemibold
    sTimer.TextXAlignment = Enum.TextXAlignment.Right
    sTimer.Parent = statusCard

    -- Combat Stats group header
    local function GroupHeader(text, y, color)
        local h = Instance.new("TextLabel")
        h.Size = UDim2.new(0.5, -8, 0, 12)
        h.Position = UDim2.new(0, 10, 0, y)
        h.BackgroundTransparency = 1
        h.Text = text
        h.TextColor3 = color or CLR.accent
        h.TextSize = 8
        h.Font = Enum.Font.GothamBold
        h.TextXAlignment = Enum.TextXAlignment.Left
        h.Parent = statusCard
    end

    GroupHeader("⚔ COMBAT", 22, CAT_COLORS.Combat)
    GroupHeader("🛡 DEFENSE", 22, CAT_COLORS.Defense)

    -- Stat labels helper
    local function StatL(name, x, y)
        local n = Instance.new("TextLabel")
        n.Size = UDim2.new(0, 52, 0, 12)
        n.Position = UDim2.new(0, x, 0, y)
        n.BackgroundTransparency = 1
        n.Text = name .. ":"
        n.TextColor3 = CLR.textDim
        n.TextSize = 9
        n.Font = Enum.Font.Gotham
        n.TextXAlignment = Enum.TextXAlignment.Left
        n.Parent = statusCard
        local v = Instance.new("TextLabel")
        v.Size = UDim2.new(0, 40, 0, 12)
        v.Position = UDim2.new(0, x + 52, 0, y)
        v.BackgroundTransparency = 1
        v.Text = "0"
        v.TextColor3 = CLR.text
        v.TextSize = 9
        v.Font = Enum.Font.GothamBold
        v.TextXAlignment = Enum.TextXAlignment.Left
        v.Parent = statusCard
        return v
    end

    -- Left column: Combat stats
    local svTargets  = StatL("Targets", 10, 34)
    local svAttacks  = StatL("Attacks", 10, 48)
    local svDPS      = StatL("DPS",     10, 62)
    local svMode     = StatL("Mode",    10, 76)

    -- Divider line
    local statDiv = Instance.new("Frame")
    statDiv.Size = UDim2.new(0, 1, 0, 60)
    statDiv.Position = UDim2.new(0.5, -1, 0, 30)
    statDiv.BackgroundColor3 = CLR.border
    statDiv.BorderSizePixel = 0
    statDiv.Parent = statusCard

    -- Right column: Defense + System stats
    local svGuard   = StatL("Guard",  200, 34)
    local svHP      = StatL("Health", 200, 48)
    local svNearby  = StatL("Nearby", 200, 62)
    local svKAKills = StatL("Kills",  200, 76)

    -- System row at bottom
    local sysDivider = Instance.new("Frame")
    sysDivider.Size = UDim2.new(1, -20, 0, 1)
    sysDivider.Position = UDim2.new(0, 10, 0, 90)
    sysDivider.BackgroundColor3 = CLR.border
    sysDivider.BorderSizePixel = 0
    sysDivider.Parent = statusCard

    local svUptime = Instance.new("TextLabel")
    svUptime.Size = UDim2.new(0.33, 0, 0, 12)
    svUptime.Position = UDim2.new(0, 10, 0, 94)
    svUptime.BackgroundTransparency = 1
    svUptime.Text = "⏱ 00:00"
    svUptime.TextColor3 = CLR.textDim
    svUptime.TextSize = 8
    svUptime.Font = Enum.Font.Gotham
    svUptime.TextXAlignment = Enum.TextXAlignment.Left
    svUptime.Parent = statusCard

    local svExec = Instance.new("TextLabel")
    svExec.Size = UDim2.new(0.33, 0, 0, 12)
    svExec.Position = UDim2.new(0.33, 0, 0, 94)
    svExec.BackgroundTransparency = 1
    svExec.Text = "🖥 " .. EXECUTOR_NAME
    svExec.TextColor3 = CLR.textDim
    svExec.TextSize = 8
    svExec.Font = Enum.Font.Gotham
    svExec.Parent = statusCard

    -- ==========================================
    -- TAB CONTENT AREA
    -- ==========================================
    local contentArea = Instance.new("Frame")
    contentArea.Size = UDim2.new(1, -14, 1, -230)
    contentArea.Position = UDim2.new(0, 7, 0, 230)
    contentArea.BackgroundTransparency = 1
    contentArea.ClipsDescendants = true
    contentArea.Parent = main

    -- Create a scroll frame for each tab
    for _, tabName in ipairs(TAB_NAMES) do
        local scroll = Instance.new("ScrollingFrame")
        scroll.Name = tabName
        scroll.Size = UDim2.new(1, 0, 1, 0)
        scroll.BackgroundTransparency = 1
        scroll.BorderSizePixel = 0
        scroll.ScrollBarThickness = 3
        scroll.ScrollBarImageColor3 = CLR.accent
        scroll.ScrollBarImageTransparency = 0.35
        scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
        scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
        scroll.Visible = (tabName == activeTab)
        scroll.Parent = contentArea

        local lay = Instance.new("UIListLayout")
        lay.SortOrder = Enum.SortOrder.LayoutOrder
        lay.Padding = UDim.new(0, 4)
        lay.Parent = scroll

        Instance.new("UIPadding", scroll).PaddingBottom = UDim.new(0, 12)

        tabFrames[tabName] = scroll
    end

    -- Track per-tab layout order
    local _tabOrders = {}
    for _, n in ipairs(TAB_NAMES) do _tabOrders[n] = 0 end
    local function nxt(tab) _tabOrders[tab] += 1; return _tabOrders[tab] end

    -- All controls for search
    local allControls = {}

    -- ==========================================
    -- UI BUILDERS
    -- ==========================================

    --- Section header (collapsible)
    local function Section(tab, name)
        local parent = tabFrames[tab]
        if not parent then return end
        local f = Instance.new("Frame")
        f.Name = "Section_" .. name
        f.Size = UDim2.new(1, 0, 0, 24)
        f.BackgroundTransparency = 1
        f.LayoutOrder = nxt(tab)
        f.Parent = parent

        local isCollapsed = CFG.CollapsedSections[name] or false

        local arrow = Instance.new("TextButton")
        arrow.Size = UDim2.new(1, 0, 1, 0)
        arrow.BackgroundTransparency = 1
        arrow.Text = ""
        arrow.Parent = f

        local arrowLabel = Instance.new("TextLabel")
        arrowLabel.Size = UDim2.new(1, -10, 1, 0)
        arrowLabel.Position = UDim2.new(0, 5, 0, 0)
        arrowLabel.BackgroundTransparency = 1
        arrowLabel.Text = (isCollapsed and "▶  " or "▼  ") .. string.upper(name)
        arrowLabel.TextColor3 = CAT_COLORS[tab] or CLR.accent
        arrowLabel.TextSize = 10
        arrowLabel.Font = Enum.Font.GothamBold
        arrowLabel.TextXAlignment = Enum.TextXAlignment.Left
        arrowLabel.Parent = f

        local ln = Instance.new("Frame")
        ln.Size = UDim2.new(1, -10, 0, 1)
        ln.Position = UDim2.new(0, 5, 1, -1)
        ln.BackgroundColor3 = CLR.border
        ln.BorderSizePixel = 0
        ln.Parent = f

        local sectionChildren = {}

        arrow.MouseButton1Click:Connect(function()
            isCollapsed = not isCollapsed
            CFG.CollapsedSections[name] = isCollapsed
            arrowLabel.Text = (isCollapsed and "▶  " or "▼  ") .. string.upper(name)
            for _, child in ipairs(sectionChildren) do
                child.Visible = not isCollapsed
            end
            AutoSave()
        end)

        return {
            register = function(element)
                table.insert(sectionChildren, element)
                if isCollapsed then element.Visible = false end
            end,
        }
    end

    --- Toggle control with category coloring, bounce, and tooltip
    local function Toggle(tab, label, def, cb, section)
        local parent = tabFrames[tab]
        if not parent then return end
        local catColor = CAT_COLORS[tab] or CLR.green

        local f = Instance.new("Frame")
        f.Name = "Toggle_" .. label
        f.Size = UDim2.new(1, 0, 0, 34)
        f.BackgroundColor3 = CLR.card
        f.BorderSizePixel = 0
        f.LayoutOrder = nxt(tab)
        f.Parent = parent
        Corner(f, 8)
        Hover(f, CLR.card, CLR.cardHover)

        if section then section.register(f) end
        table.insert(allControls, { frame = f, label = label })

        local tl = Instance.new("TextLabel")
        tl.Size = UDim2.new(1, -64, 1, 0)
        tl.Position = UDim2.new(0, 12, 0, 0)
        tl.BackgroundTransparency = 1
        tl.Text = label
        tl.TextColor3 = CLR.text
        tl.TextSize = 12
        tl.Font = Enum.Font.Gotham
        tl.TextXAlignment = Enum.TextXAlignment.Left
        tl.TextTruncate = Enum.TextTruncate.AtEnd
        tl.Parent = f

        -- Tooltip
        tl.MouseEnter:Connect(function() ShowTooltip(label, tl) end)
        tl.MouseLeave:Connect(function() HideTooltip() end)

        local bg = Instance.new("Frame")
        bg.Size = UDim2.new(0, 42, 0, 20)
        bg.Position = UDim2.new(1, -52, 0.5, -10)
        bg.BackgroundColor3 = def and catColor or CLR.toggleOff
        bg.BorderSizePixel = 0
        bg.Parent = f
        Corner(bg, 10)

        local dot = Instance.new("Frame")
        dot.Size = UDim2.new(0, 16, 0, 16)
        dot.Position = def and UDim2.new(1, -18, 0.5, -8)
                            or UDim2.new(0, 2, 0.5, -8)
        dot.BackgroundColor3 = Color3.new(1, 1, 1)
        dot.BorderSizePixel = 0
        dot.Parent = bg
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
        dotShadow.ZIndex = -1
        dotShadow.Parent = dot

        local st = def
        local api = {}

        function api.Set(v)
            st = v
            TweenService:Create(bg, TWEEN_SMOOTH,
                {BackgroundColor3 = st and catColor or CLR.toggleOff}):Play()
            TweenService:Create(dot, TWEEN_BOUNCE,
                {Position = st and UDim2.new(1, -18, 0.5, -8)
                                or UDim2.new(0, 2, 0.5, -8)}):Play()
        end
        function api.Get() return st end

        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, 0, 1, 0)
        btn.BackgroundTransparency = 1
        btn.Text = ""
        btn.Parent = f
        btn.MouseButton1Click:Connect(function()
            -- Bounce micro-interaction
            TweenService:Create(f, TweenInfo.new(0.08), {Size = UDim2.new(1, 0, 0, 32)}):Play()
            task.delay(0.08, function()
                TweenService:Create(f, TWEEN_BOUNCE, {Size = UDim2.new(1, 0, 0, 34)}):Play()
            end)
            st = not st
            api.Set(st)
            if cb then cb(st) end
        end)

        return api
    end

    --- Slider control with drag glow
    local function Slider(tab, label, lo, hi, def, cb, section)
        local parent = tabFrames[tab]
        if not parent then return end

        local f = Instance.new("Frame")
        f.Name = "Slider_" .. label
        f.Size = UDim2.new(1, 0, 0, 48)
        f.BackgroundColor3 = CLR.card
        f.BorderSizePixel = 0
        f.LayoutOrder = nxt(tab)
        f.Parent = parent
        Corner(f, 8)
        Hover(f, CLR.card, CLR.cardHover)

        if section then section.register(f) end
        table.insert(allControls, { frame = f, label = label })

        local tl = Instance.new("TextLabel")
        tl.Size = UDim2.new(1, -54, 0, 18)
        tl.Position = UDim2.new(0, 12, 0, 4)
        tl.BackgroundTransparency = 1
        tl.Text = label
        tl.TextColor3 = CLR.text
        tl.TextSize = 11
        tl.Font = Enum.Font.Gotham
        tl.TextXAlignment = Enum.TextXAlignment.Left
        tl.Parent = f

        -- Tooltip on slider label too
        tl.MouseEnter:Connect(function() ShowTooltip(label, tl) end)
        tl.MouseLeave:Connect(function() HideTooltip() end)

        local vl = Instance.new("TextLabel")
        vl.Size = UDim2.new(0, 44, 0, 18)
        vl.Position = UDim2.new(1, -54, 0, 4)
        vl.BackgroundTransparency = 1
        vl.Text = tostring(def)
        vl.TextColor3 = CLR.accent
        vl.TextSize = 12
        vl.Font = Enum.Font.GothamBold
        vl.TextXAlignment = Enum.TextXAlignment.Right
        vl.Parent = f

        local track = Instance.new("Frame")
        track.Size = UDim2.new(1, -24, 0, 6)
        track.Position = UDim2.new(0, 12, 0, 32)
        track.BackgroundColor3 = CLR.sliderBg
        track.BorderSizePixel = 0
        track.Parent = f
        Corner(track, 3)

        local initR = math.clamp((def - lo) / (hi - lo), 0, 1)

        local fill = Instance.new("Frame")
        fill.Size = UDim2.new(initR, 0, 1, 0)
        fill.BackgroundColor3 = CLR.accent
        fill.BorderSizePixel = 0
        fill.Parent = track
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
        knob.BorderSizePixel = 0
        knob.ZIndex = 2
        knob.Parent = track
        Corner(knob, 7)

        -- Glow stroke (hidden by default)
        local knobGlow = Instance.new("UIStroke")
        knobGlow.Color = CLR.accent
        knobGlow.Thickness = 1.5
        knobGlow.Transparency = 1
        knobGlow.Parent = knob

        local hit = Instance.new("TextButton")
        hit.Size = UDim2.new(1, 0, 0, 24)
        hit.Position = UDim2.new(0, 0, 0, 22)
        hit.BackgroundTransparency = 1
        hit.Text = ""
        hit.Parent = f

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
                sliding = true
                upd(i.Position)
                -- Show glow
                TweenService:Create(knobGlow, TWEEN_FAST, {Transparency = 0.4}):Play()
            end
        end)
        Conn(UIS.InputEnded, function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1
            or i.UserInputType == Enum.UserInputType.Touch then
                if sliding then
                    sliding = false
                    TweenService:Create(knobGlow, TWEEN_FAST, {Transparency = 1}):Play()
                end
            end
        end)
        Conn(UIS.InputChanged, function(i)
            if sliding and track and track.Parent
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

    --- Info row (non-interactive label pair)
    local function InfoRow(tab, label, defaultVal, section)
        local parent = tabFrames[tab]
        if not parent then return end
        local f = Instance.new("Frame")
        f.Name = "Info_" .. label
        f.Size = UDim2.new(1, 0, 0, 24)
        f.BackgroundColor3 = CLR.card
        f.BorderSizePixel = 0
        f.LayoutOrder = nxt(tab)
        f.Parent = parent
        Corner(f, 6)

        if section then section.register(f) end

        local nl = Instance.new("TextLabel")
        nl.Size = UDim2.new(0.5, -5, 1, 0)
        nl.Position = UDim2.new(0, 12, 0, 0)
        nl.BackgroundTransparency = 1
        nl.Text = label
        nl.TextColor3 = CLR.textDim
        nl.TextSize = 10
        nl.Font = Enum.Font.Gotham
        nl.TextXAlignment = Enum.TextXAlignment.Left
        nl.Parent = f

        local vl = Instance.new("TextLabel")
        vl.Size = UDim2.new(0.5, -12, 1, 0)
        vl.Position = UDim2.new(0.5, 0, 0, 0)
        vl.BackgroundTransparency = 1
        vl.Text = defaultVal or "-"
        vl.TextColor3 = CLR.text
        vl.TextSize = 10
        vl.Font = Enum.Font.GothamBold
        vl.TextXAlignment = Enum.TextXAlignment.Right
        vl.Parent = f

        return vl
    end

    -- ==========================================
    -- CREATE TABS
    -- ==========================================
    for idx, tabName in ipairs(TAB_NAMES) do
        local btn = Instance.new("TextButton")
        btn.Name = tabName
        btn.Size = UDim2.new(0, 70, 1, 0)
        btn.BackgroundColor3 = tabName == activeTab and CLR.tabActive or CLR.tabInactive
        btn.BorderSizePixel = 0
        btn.Text = TAB_ICONS[tabName] .. " " .. tabName
        btn.TextColor3 = tabName == activeTab and CLR.text or CLR.textDim
        btn.TextSize = 10
        btn.Font = Enum.Font.GothamBold
        btn.AutoButtonColor = false
        btn.LayoutOrder = idx
        btn.Parent = tabBar
        Corner(btn, 6)

        -- Underline for active tab
        local underline = Instance.new("Frame")
        underline.Size = UDim2.new(0.8, 0, 0, 2)
        underline.Position = UDim2.new(0.1, 0, 1, -2)
        underline.BackgroundColor3 = CAT_COLORS[tabName] or CLR.accent
        underline.BorderSizePixel = 0
        underline.Visible = tabName == activeTab
        underline.Parent = btn

        tabButtons[tabName] = { button = btn, underline = underline }
    end

    --- Switch to a tab
    local function SwitchTab(tabName)
        activeTab = tabName
        for name, data in pairs(tabButtons) do
            local isActive = name == tabName
            TweenService:Create(data.button, TWEEN_FAST, {
                BackgroundColor3 = isActive and CLR.tabActive or CLR.tabInactive,
                TextColor3 = isActive and CLR.text or CLR.textDim,
            }):Play()
            data.underline.Visible = isActive
        end
        for name, frame in pairs(tabFrames) do
            frame.Visible = name == tabName
        end
    end

    for name, data in pairs(tabButtons) do
        data.button.MouseButton1Click:Connect(function()
            SwitchTab(name)
        end)
    end

    -- ==========================================
    -- SEARCH FUNCTIONALITY
    -- ==========================================
    searchBox:GetPropertyChangedSignal("Text"):Connect(function()
        local query = searchBox.Text:lower()
        if query == "" then
            -- Restore tab view
            tabBar.Visible = true
            for name, frame in pairs(tabFrames) do
                frame.Visible = name == activeTab
                -- Restore all children visibility
                for _, child in ipairs(frame:GetChildren()) do
                    if child:IsA("Frame") then child.Visible = true end
                end
            end
        else
            -- Search mode: show all tabs, filter
            tabBar.Visible = false
            for _, frame in pairs(tabFrames) do
                frame.Visible = true
                for _, child in ipairs(frame:GetChildren()) do
                    if child:IsA("Frame") and child.Name ~= "" then
                        local matchLabel = child.Name:lower():find(query)
                        child.Visible = matchLabel ~= nil
                    end
                end
            end
        end
    end)

    -- ==========================================
    -- POPULATE TABS
    -- ==========================================

    -- === COMBAT TAB ===
    local secMain = Section("Combat", "Main Controls")

    local tEnabled = Toggle("Combat", "Script Enabled", CFG.Enabled, function(v)
        CFG.Enabled = v
        sDot.BackgroundColor3 = v and CLR.green or CLR.red
        sLbl.Text = v and "ACTIVE" or "DISABLED"
        sLbl.TextColor3 = v and CLR.green or CLR.red
        UpdateAuraRing()
        Notify(v and "Script enabled" or "Script disabled",
               v and "success" or "info", 1.5)
        AutoSave()
    end, secMain)

    Toggle("Combat", "Attack All (AoE)", CFG.TargetAll, function(v)
        CFG.TargetAll = v; AutoSave()
    end, secMain)

    Toggle("Combat", "Target Players", CFG.TargetPlayers, function(v)
        CFG.TargetPlayers = v; ST.LastTargetUpdate = 0; AutoSave()
    end, secMain)

    Toggle("Combat", "Target NPCs", CFG.TargetNPCs, function(v)
        CFG.TargetNPCs = v; ST.LastTargetUpdate = 0; AutoSave()
    end, secMain)

    local secAttack = Section("Combat", "Attack Settings")

    Slider("Combat", "Attacks Per Second", 1, 20, CFG.AttacksPerSecond, function(v)
        CFG.AttacksPerSecond = v; AutoSave()
    end, secAttack)

    Slider("Combat", "Max Targets / Cycle", 1, 10, CFG.MaxTargetsPerCycle, function(v)
        CFG.MaxTargetsPerCycle = v; AutoSave()
    end, secAttack)

    local secTypes = Section("Combat", "Attack Types")

    Toggle("Combat", "Punch " .. (REM.Punch and "✓" or "✗"),
        REM.Punch ~= nil and CFG.UsePunch,
        function(v) if REM.Punch then CFG.UsePunch = v end; AutoSave() end, secTypes)

    Toggle("Combat", "Suplex " .. (REM.Suplex and "✓" or "✗"),
        REM.Suplex ~= nil and CFG.UseSuplex,
        function(v) if REM.Suplex then CFG.UseSuplex = v end; AutoSave() end, secTypes)

    Toggle("Combat", "Heavy Hit " .. (REM.HeavyHit and "✓" or "✗"),
        REM.HeavyHit ~= nil and CFG.UseHeavyHit,
        function(v) if REM.HeavyHit then CFG.UseHeavyHit = v end; AutoSave() end, secTypes)

    Toggle("Combat", "Tool/Weapon Attack " .. (REM.ToolHit and "✓" or "✗"),
        REM.ToolHit ~= nil and CFG.UseToolAttack,
        function(v) if REM.ToolHit then CFG.UseToolAttack = v end; AutoSave() end, secTypes)

    Toggle("Combat", "Prefer Weapon Over Fist", CFG.PreferWeaponOverFist,
        function(v) CFG.PreferWeaponOverFist = v; AutoSave() end, secTypes)

    Toggle("Combat", "Animation Cancel " .. (REM.StopAnim and "✓" or "✗"),
        REM.StopAnim ~= nil and CFG.UseAnimCancel,
        function(v) if REM.StopAnim then CFG.UseAnimCancel = v end; AutoSave() end, secTypes)

    local secStomp = Section("Combat", "Stomp & Stun")

    Toggle("Combat", "Auto Stomp " .. (REM.Stomp and "✓" or "✗"),
        REM.Stomp ~= nil and CFG.UseAutoStomp,
        function(v) if REM.Stomp then CFG.UseAutoStomp = v end; AutoSave() end, secStomp)

    Slider("Combat", "Stomp Range (studs)", 5, 50, CFG.StompRange, function(v)
        CFG.StompRange = v; AutoSave()
    end, secStomp)

    Toggle("Combat", "Auto Stun " .. (REM.Stun and "✓" or "✗"),
        REM.Stun ~= nil and CFG.UseAutoStun,
        function(v) if REM.Stun then CFG.UseAutoStun = v end; AutoSave() end, secStomp)

    Slider("Combat", "Stun Range (studs)", 5, 50, CFG.StunRange, function(v)
        CFG.StunRange = v; AutoSave()
    end, secStomp)

    local secKA = Section("Combat", "Kill All")

    local tRemoteAura = Toggle("Combat", "Remote Aura (All Players, No TP)", CFG.RemoteAura, function(v)
        CFG.RemoteAura = v
        if v then
            -- Disable Kill All — they're mutually exclusive
            CFG.KillAllActive = false
            tKillAll.Set(false)
            if not CFG.Enabled then
                CFG.Enabled = true
                tEnabled.Set(true)
                sDot.BackgroundColor3 = CLR.green
                sLbl.Text = "ACTIVE"
                sLbl.TextColor3 = CLR.green
            end
        end
        Notify(v and "Remote Aura ACTIVE — hitting entire server" or "Remote Aura disabled", v and "warning" or "info", 2)
        AutoSave()
    end, secKA)

    local tKillAll = Toggle("Combat", "Kill All (TP & Kill)", CFG.KillAllActive, function(v)
        CFG.KillAllActive = v
        if v then
            -- Disable Remote Aura — mutually exclusive
            CFG.RemoteAura = false
            tRemoteAura.Set(false)
            if not CFG.Enabled then
                CFG.Enabled = true
                tEnabled.Set(true)
                sDot.BackgroundColor3 = CLR.green
                sLbl.Text = "ACTIVE"
                sLbl.TextColor3 = CLR.green
            end
            if not ST.KillAllRunning then task.spawn(RunKillAll) end
        end
        AutoSave()
    end, secKA)

    Slider("Combat", "Kill Timeout (sec)", 3, 20, CFG.KillAllTimeout, function(v)
        CFG.KillAllTimeout = v; AutoSave()
    end, secKA)

    local secVis = Section("Combat", "Visualization")

    Toggle("Combat", "Kill Aura Visualization", CFG.KillAuraVisualization, function(v)
        CFG.KillAuraVisualization = v; UpdateAuraRing(); AutoSave()
    end, secVis)

    Toggle("Combat", "ESP Overlay", CFG.ESPEnabled, function(v)
        CFG.ESPEnabled = v
        if not v then ClearAllESP() end
        AutoSave()
    end, secVis)

    -- === DEFENSE TAB ===
    local secGuard = Section("Defense", "Guard")

    Toggle("Defense", "Auto Guard " .. (REM.Block and "✓" or "✗"),
        REM.Block ~= nil and CFG.UseAutoGuard, function(v)
        if REM.Block then CFG.UseAutoGuard = v; if not v then SetGuard(false) end end
        AutoSave()
    end, secGuard)

    Toggle("Defense", "Drop Guard to Attack", CFG.GuardDropForAttack, function(v)
        CFG.GuardDropForAttack = v; AutoSave()
    end, secGuard)

    Toggle("Defense", "Ignore ForceField", CFG.IgnoreForceField, function(v)
        CFG.IgnoreForceField = v; AutoSave()
    end, secGuard)

    Slider("Defense", "Guard Range (studs)", 5, 150, CFG.GuardActivationRange, function(v)
        CFG.GuardActivationRange = v; InvalidateNearbyCache(); AutoSave()
    end, secGuard)

    local secPVP = Section("Defense", "PVP")

    Toggle("Defense", "Smart PVP Toggle " .. (REM.PVPToggle and "✓" or "✗"),
        REM.PVPToggle ~= nil and CFG.UseSmartPVP, function(v)
        if REM.PVPToggle then CFG.UseSmartPVP = v end; AutoSave()
    end, secPVP)

    -- === SURVIVAL TAB ===
    local secHeal = Section("Survival", "Healing")

    Toggle("Survival", "Auto Heal " .. (REM.Heal and "✓" or "✗"),
        REM.Heal ~= nil and CFG.UseAutoHeal, function(v)
        CFG.UseAutoHeal = v; AutoSave()
    end, secHeal)

    Slider("Survival", "Heal Threshold (%)", 10, 100, CFG.HealThreshold, function(v)
        CFG.HealThreshold = v; AutoSave()
    end, secHeal)

    Toggle("Survival", "Auto Buy Food " .. (REM.Carniceria and "✓" or "✗"),
        CFG.UseAutoBuyFood, function(v)
        CFG.UseAutoBuyFood = v; AutoSave()
    end, secHeal)

    Toggle("Survival", "Anti-AFK", CFG.AntiAFK, function(v)
        CFG.AntiAFK = v; AutoSave()
    end, secHeal)

    Toggle("Survival", "Auto Respawn", CFG.AutoRespawn, function(v)
        CFG.AutoRespawn = v; AutoSave()
    end, secHeal)

    -- === UTILITY TAB ===
    local secSize = Section("Utility", "Size Changer")

    Toggle("Utility", "Size Changer", CFG.SizeChangerEnabled, function(v)
        CFG.SizeChangerEnabled = v
        if v then
            ApplySize(CFG.SizeChangerValue)
            Notify("Size set to " .. string.format("%.1f", CFG.SizeChangerValue), "success", 2)
        else
            ApplySize(1.0)
            Notify("Size reset to normal", "info", 2)
        end
        AutoSave()
    end, secSize)

    Slider("Utility", "Size", 0.1, 10, CFG.SizeChangerValue, function(v)
        CFG.SizeChangerValue = v
        if CFG.SizeChangerEnabled then
            ApplySize(v)
        end
        AutoSave()
    end, secSize)

    local secWeapon = Section("Utility", "Weapons")

    Toggle("Utility", "Auto Pickup Weapons " .. (REM.PickupTool and "✓" or "✗"),
        CFG.UseAutoPickupTools, function(v)
        CFG.UseAutoPickupTools = v; AutoSave()
    end, secWeapon)

    Slider("Utility", "Pickup Range (studs)", 10, 200, CFG.ToolPickupRange, function(v)
        CFG.ToolPickupRange = v; AutoSave()
    end, secWeapon)

    local secAdv = Section("Utility", "Advanced Combat")

    Toggle("Utility", "Auto Carry+Throw " .. ((REM.Carry and REM.Throw) and "✓" or "✗"),
        CFG.UseAutoCarryThrow, function(v)
        if REM.Carry and REM.Throw then CFG.UseAutoCarryThrow = v end; AutoSave()
    end, secAdv)

    Toggle("Utility", "Crouch Spam " .. (REM.Crouch and "✓" or "✗"),
        CFG.UseCrouchSpam, function(v)
        if REM.Crouch then CFG.UseCrouchSpam = v end; AutoSave()
    end, secAdv)

    -- Whitelist/Blacklist section
    local secLists = Section("Utility", "Player Lists")

    Toggle("Utility", "Auto-Whitelist Friends", CFG.AutoWhitelistFriends, function(v)
        CFG.AutoWhitelistFriends = v; AutoSave()
    end, secLists)

    -- Whitelist add box
    do
        local wlFrame = Instance.new("Frame")
        wlFrame.Size = UDim2.new(1, 0, 0, 30)
        wlFrame.BackgroundColor3 = CLR.card
        wlFrame.BorderSizePixel = 0
        wlFrame.LayoutOrder = nxt("Utility")
        wlFrame.Parent = tabFrames["Utility"]
        Corner(wlFrame, 6)
        if secLists then secLists.register(wlFrame) end

        local wlBox = Instance.new("TextBox")
        wlBox.Size = UDim2.new(1, -80, 1, -6)
        wlBox.Position = UDim2.new(0, 8, 0, 3)
        wlBox.BackgroundTransparency = 1
        wlBox.PlaceholderText = "Player name..."
        wlBox.PlaceholderColor3 = CLR.textDim
        wlBox.Text = ""
        wlBox.TextColor3 = CLR.text
        wlBox.TextSize = 10
        wlBox.Font = Enum.Font.Gotham
        wlBox.TextXAlignment = Enum.TextXAlignment.Left
        wlBox.Parent = wlFrame

        local wlBtn = Instance.new("TextButton")
        wlBtn.Size = UDim2.new(0, 32, 0, 22)
        wlBtn.Position = UDim2.new(1, -72, 0, 4)
        wlBtn.BackgroundColor3 = CLR.green
        wlBtn.Text = "+WL"
        wlBtn.TextColor3 = CLR.text
        wlBtn.TextSize = 8
        wlBtn.Font = Enum.Font.GothamBold
        wlBtn.AutoButtonColor = false
        wlBtn.Parent = wlFrame
        Corner(wlBtn, 4)

        local blBtn = Instance.new("TextButton")
        blBtn.Size = UDim2.new(0, 32, 0, 22)
        blBtn.Position = UDim2.new(1, -36, 0, 4)
        blBtn.BackgroundColor3 = CLR.red
        blBtn.Text = "+BL"
        blBtn.TextColor3 = CLR.text
        blBtn.TextSize = 8
        blBtn.Font = Enum.Font.GothamBold
        blBtn.AutoButtonColor = false
        blBtn.Parent = wlFrame
        Corner(blBtn, 4)

        wlBtn.MouseButton1Click:Connect(function()
            local name = wlBox.Text:gsub("%s+", "")
            if name ~= "" then
                CFG.Whitelist[name] = true
                CFG.Blacklist[name] = nil
                Notify("Whitelisted: " .. name, "success", 2)
                wlBox.Text = ""
                AutoSave()
            end
        end)

        blBtn.MouseButton1Click:Connect(function()
            local name = wlBox.Text:gsub("%s+", "")
            if name ~= "" then
                CFG.Blacklist[name] = true
                CFG.Whitelist[name] = nil
                Notify("Blacklisted: " .. name, "warning", 2)
                wlBox.Text = ""
                AutoSave()
            end
        end)
    end

    -- === SYSTEM TAB ===
    local secSys = Section("System", "System")

    Toggle("System", "Debug Logging", CFG.Debug, function(v) CFG.Debug = v; AutoSave() end, secSys)

    Toggle("System", "DPS Tracker", true, function(v) AutoSave() end, secSys)

    -- Config export/import
    local secConfig = Section("System", "Configuration")

    do
        local cfgFrame = Instance.new("Frame")
        cfgFrame.Size = UDim2.new(1, 0, 0, 30)
        cfgFrame.BackgroundColor3 = CLR.card
        cfgFrame.BorderSizePixel = 0
        cfgFrame.LayoutOrder = nxt("System")
        cfgFrame.Parent = tabFrames["System"]
        Corner(cfgFrame, 6)
        if secConfig then secConfig.register(cfgFrame) end

        local expBtn = Instance.new("TextButton")
        expBtn.Size = UDim2.new(0.48, 0, 0, 24)
        expBtn.Position = UDim2.new(0.01, 0, 0, 3)
        expBtn.BackgroundColor3 = CLR.accent
        expBtn.Text = "📋 Export Config"
        expBtn.TextColor3 = CLR.text
        expBtn.TextSize = 10
        expBtn.Font = Enum.Font.GothamBold
        expBtn.AutoButtonColor = false
        expBtn.Parent = cfgFrame
        Corner(expBtn, 5)

        expBtn.MouseButton1Click:Connect(function()
            local ok, json = pcall(function()
                return HttpService:JSONEncode(CFG)
            end)
            if ok and CAN_SET_CLIPBOARD then
                setclipboard(json)
                Notify("Config copied to clipboard!", "success", 3)
            elseif ok then
                Notify("Clipboard API unavailable", "error", 3)
            end
        end)

        local impBtn = Instance.new("TextButton")
        impBtn.Size = UDim2.new(0.48, 0, 0, 24)
        impBtn.Position = UDim2.new(0.51, 0, 0, 3)
        impBtn.BackgroundColor3 = CAT_COLORS.Utility
        impBtn.Text = "📥 Import Config"
        impBtn.TextColor3 = CLR.bg
        impBtn.TextSize = 10
        impBtn.Font = Enum.Font.GothamBold
        impBtn.AutoButtonColor = false
        impBtn.Parent = cfgFrame
        Corner(impBtn, 5)

        -- Import dialog (simple text box)
        local importFrame = Instance.new("Frame")
        importFrame.Size = UDim2.new(1, 0, 0, 60)
        importFrame.BackgroundColor3 = CLR.card
        importFrame.BorderSizePixel = 0
        importFrame.LayoutOrder = nxt("System")
        importFrame.Visible = false
        importFrame.Parent = tabFrames["System"]
        Corner(importFrame, 6)
        if secConfig then secConfig.register(importFrame) end

        local importBox = Instance.new("TextBox")
        importBox.Size = UDim2.new(1, -12, 0, 36)
        importBox.Position = UDim2.new(0, 6, 0, 3)
        importBox.BackgroundColor3 = CLR.sliderBg
        importBox.PlaceholderText = "Paste JSON config here..."
        importBox.PlaceholderColor3 = CLR.textDim
        importBox.Text = ""
        importBox.TextColor3 = CLR.text
        importBox.TextSize = 9
        importBox.Font = Enum.Font.Gotham
        importBox.TextXAlignment = Enum.TextXAlignment.Left
        importBox.ClearTextOnFocus = true
        importBox.Parent = importFrame
        Corner(importBox, 4)

        local applyBtn = Instance.new("TextButton")
        applyBtn.Size = UDim2.new(1, -12, 0, 18)
        applyBtn.Position = UDim2.new(0, 6, 0, 40)
        applyBtn.BackgroundColor3 = CLR.green
        applyBtn.Text = "Apply"
        applyBtn.TextColor3 = CLR.text
        applyBtn.TextSize = 10
        applyBtn.Font = Enum.Font.GothamBold
        applyBtn.Parent = importFrame
        Corner(applyBtn, 4)

        impBtn.MouseButton1Click:Connect(function()
            importFrame.Visible = not importFrame.Visible
        end)

        applyBtn.MouseButton1Click:Connect(function()
            local ok, decoded = pcall(function()
                return HttpService:JSONDecode(importBox.Text)
            end)
            if ok and type(decoded) == "table" then
                for k, v in pairs(decoded) do
                    if CFG[k] ~= nil and type(CFG[k]) == type(v) then
                        CFG[k] = v
                    end
                end
                Notify("Config imported successfully!", "success", 3)
                importFrame.Visible = false
                AutoSave()
            else
                Notify("Invalid JSON config", "error", 3)
            end
        end)
    end

    -- Remote status section
    local secRemotes = Section("System", "Remote Status")

    local remoteList = {
        {"PUNCHEVENT", REM.Punch}, {"SUPLEXEVENT", REM.Suplex},
        {"HEAVYHIT", REM.HeavyHit}, {"BLOCKEVENT", REM.Block},
        {"STOMPEVENT", REM.Stomp}, {"TOOLHITEVENT", REM.ToolHit},
        {"STUNEVENT", REM.Stun}, {"HEALCHARACTERCARRIED", REM.Heal},
        {"Carniceria", REM.Carniceria}, {"CARRYEVENT", REM.Carry},
        {"THROWCHARACTEREVENT", REM.Throw}, {"CROUCHEVENT", REM.Crouch},
        {"STOPLOCALANIMATIONS", REM.StopAnim}, {"PVPONOFFEVENT", REM.PVPToggle},
        {"PICKUPTOOLSEVENT", REM.PickupTool}, {"ADMINCOMMANDS", REM.AdminCmd},
        {"ADMINPANNEL", REM.AdminPanel},
    }

    local ri = Instance.new("Frame")
    ri.Size = UDim2.new(1, 0, 0, #remoteList * 15 + 8)
    ri.BackgroundColor3 = CLR.card
    ri.BorderSizePixel = 0
    ri.LayoutOrder = nxt("System")
    ri.Parent = tabFrames["System"]
    Corner(ri, 8)
    if secRemotes then secRemotes.register(ri) end

    for idx, data in ipairs(remoteList) do
        local ok = data[2] ~= nil
        local rl = Instance.new("TextLabel")
        rl.Size = UDim2.new(1, -14, 0, 13)
        rl.Position = UDim2.new(0, 12, 0, 4 + (idx - 1) * 15)
        rl.BackgroundTransparency = 1
        rl.Text = (ok and "●  " or "○  ") .. data[1]
        rl.TextColor3 = ok and CLR.green or CLR.red
        rl.TextSize = 9
        rl.Font = Enum.Font.GothamSemibold
        rl.TextXAlignment = Enum.TextXAlignment.Left
        rl.Parent = ri
    end

    -- ==========================================
    -- COMBAT LOG (pinned at bottom of main frame)
    -- ==========================================
    local logFrame = Instance.new("Frame")
    logFrame.Name = "CombatLog"
    logFrame.Size = UDim2.new(1, -14, 0, 80)
    logFrame.Position = UDim2.new(0, 7, 1, -87)
    logFrame.BackgroundColor3 = CLR.card
    logFrame.BorderSizePixel = 0
    logFrame.ClipsDescendants = true
    logFrame.Parent = main
    Corner(logFrame, 6)
    Stroke(logFrame)

    local logTitle = Instance.new("TextLabel")
    logTitle.Size = UDim2.new(1, 0, 0, 16)
    logTitle.BackgroundTransparency = 1
    logTitle.Text = "  📜 Combat Log"
    logTitle.TextColor3 = CLR.textDim
    logTitle.TextSize = 9
    logTitle.Font = Enum.Font.GothamBold
    logTitle.TextXAlignment = Enum.TextXAlignment.Left
    logTitle.Parent = logFrame

    local logScroll = Instance.new("ScrollingFrame")
    logScroll.Size = UDim2.new(1, -4, 1, -18)
    logScroll.Position = UDim2.new(0, 2, 0, 16)
    logScroll.BackgroundTransparency = 1
    logScroll.BorderSizePixel = 0
    logScroll.ScrollBarThickness = 2
    logScroll.ScrollBarImageColor3 = CLR.accent
    logScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    logScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    logScroll.Parent = logFrame

    local logLayout = Instance.new("UIListLayout")
    logLayout.SortOrder = Enum.SortOrder.LayoutOrder
    logLayout.Padding = UDim.new(0, 1)
    logLayout.Parent = logScroll

    -- Adjust content area to account for log
    contentArea.Size = UDim2.new(1, -14, 1, -320)

    -- ==========================================
    -- FOOTER
    -- ==========================================
    local footerText = Instance.new("TextLabel")
    footerText.Size = UDim2.new(1, -14, 0, 12)
    footerText.Position = UDim2.new(0, 7, 1, -7)  -- at very bottom but above log
    footerText.BackgroundTransparency = 1
    footerText.Text = "MAP v" .. SCRIPT_VERSION .. " | " .. EXECUTOR_NAME
    footerText.TextColor3 = Color3.fromRGB(50, 50, 70)
    footerText.TextSize = 8
    footerText.Font = Enum.Font.GothamSemibold
    -- (omitted - taking up space, version shown in badge)

    -- ==========================================
    -- MINIMIZE / CLOSE
    -- ==========================================
    local minimized = false
    local fullSz = main.Size

    minB.MouseButton1Click:Connect(function()
        minimized = not minimized
        if minimized then
            TweenService:Create(main, TweenInfo.new(0.2, Enum.EasingStyle.Quint),
                {Size = UDim2.new(0, 380, 0, 46)}):Play()
            task.wait(0.2)
            contentArea.Visible = false
            statusCard.Visible = false
            searchBar.Visible = false
            tabBar.Visible = false
            logFrame.Visible = false
            minB.Text = "+"
        else
            contentArea.Visible = true
            statusCard.Visible = true
            searchBar.Visible = true
            tabBar.Visible = true
            logFrame.Visible = true
            TweenService:Create(main, TweenInfo.new(0.25, Enum.EasingStyle.Quint),
                {Size = fullSz}):Play()
            minB.Text = "—"
        end
    end)

    clsB.MouseButton1Click:Connect(function()
        ST.Running = false
        CFG.Enabled = false
        CFG.KillAllActive = false
        SetGuard(false)
        ClearAllESP()
        UpdateAuraRing()
        TweenService:Create(main, TweenInfo.new(0.25, Enum.EasingStyle.Quint),
            {Size = UDim2.new(0, 380, 0, 0), BackgroundTransparency = 1}):Play()
        task.wait(0.3)
        sg:Destroy()
    end)

    -- ==========================================
    -- KEYBINDS
    -- ==========================================
    Conn(UIS.InputBegan, function(inp, gp)
        if gp then return end
        local kc = inp.KeyCode
        local kb = CFG.Keybinds

        if kc == kb.ToggleGUI then
            main.Visible = not main.Visible
        elseif kc == kb.ToggleScript then
            CFG.Enabled = not CFG.Enabled
            tEnabled.Set(CFG.Enabled)
            sDot.BackgroundColor3 = CFG.Enabled and CLR.green or CLR.red
            sLbl.Text = CFG.Enabled and "ACTIVE" or "DISABLED"
            sLbl.TextColor3 = CFG.Enabled and CLR.green or CLR.red
            UpdateAuraRing()
            Notify(CFG.Enabled and "Script enabled" or "Script disabled",
                   CFG.Enabled and "success" or "info", 1.5)
        elseif kc == kb.KillAll then
            CFG.KillAllActive = not CFG.KillAllActive
            tKillAll.Set(CFG.KillAllActive)
            if CFG.KillAllActive then
                if not CFG.Enabled then
                    CFG.Enabled = true
                    tEnabled.Set(true)
                end
                if not ST.KillAllRunning then task.spawn(RunKillAll) end
            end
        elseif kc == kb.ToggleAoE then
            CFG.TargetAll = not CFG.TargetAll
            Notify("Mode: " .. (CFG.TargetAll and "AoE" or "Single Target"), "info", 1.5)
        elseif kc == kb.EmergencyStop then
            CFG.Enabled = false
            CFG.KillAllActive = false
            tEnabled.Set(false)
            tKillAll.Set(false)
            SetGuard(false)
            sDot.BackgroundColor3 = CLR.red
            sLbl.Text = "DISABLED"
            sLbl.TextColor3 = CLR.red
            UpdateAuraRing()
            ClearAllESP()
            Notify("EMERGENCY STOP", "error", 3)
            AddLogEntry("system", "Emergency stop activated")
        elseif kc == kb.ToggleAutoBlock then
            if REM.Block then
                CFG.UseAutoGuard = not CFG.UseAutoGuard
                if not CFG.UseAutoGuard then SetGuard(false) end
                Notify("Auto Guard: " .. (CFG.UseAutoGuard and "ON" or "OFF"), "info", 1.5)
            end
        end
    end)

    -- ==========================================
    -- OPEN ANIMATION
    -- ==========================================
    main.Size = UDim2.new(0, 380, 0, 0)
    main.BackgroundTransparency = 1
    task.defer(function()
        TweenService:Create(main,
            TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
            {Size = fullSz, BackgroundTransparency = 0}):Play()
    end)

    -- Status dot pulse
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
        gui = sg,
        main = main,
        statusDot = sDot,
        statusLbl = sLbl,
        timer = sTimer,
        logScroll = logScroll,
        sv = {
            targets = svTargets, attacks = svAttacks,
            guard = svGuard, dps = svDPS,
            health = svHP, mode = svMode,
            nearby = svNearby, kaKills = svKAKills,
            uptime = svUptime,
        },
        toggleEnabled = tEnabled,
        toggleKillAll = tKillAll,
    }
end

GUI_REFS = BuildGUI()

----------------------------------------------------------------
-- S16. MAIN LOOPS (6 consolidated)
----------------------------------------------------------------

--- Update combat log UI
local _lastLogLen = 0
local function FlushCombatLog()
    if not GUI_REFS or not GUI_REFS.logScroll then return end
    local scroll = GUI_REFS.logScroll
    if #ST.CombatLog == _lastLogLen then return end

    -- Add new entries
    for i = _lastLogLen + 1, #ST.CombatLog do
        local entry = ST.CombatLog[i]
        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, -4, 0, 12)
        lbl.BackgroundTransparency = 1
        lbl.Text = "[" .. entry.time .. "] " .. entry.message
        lbl.TextColor3 = entry.color
        lbl.TextSize = 8
        lbl.Font = Enum.Font.Gotham
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.TextTruncate = Enum.TextTruncate.AtEnd
        lbl.LayoutOrder = i
        lbl.Parent = scroll
    end
    _lastLogLen = #ST.CombatLog

    -- Auto-scroll to bottom
    task.defer(function()
        if scroll and scroll.Parent then
            scroll.CanvasPosition = Vector2.new(0, scroll.AbsoluteCanvasSize.Y)
        end
    end)
end

-- LOOP 1: COMBAT (attack, target selection, stomp, stun)
task.spawn(function()
    while ST.Running do
        if CFG.Enabled and HAS_ATTACK and not CFG.KillAllActive then
            local interval = 1 / math.max(CFG.AttacksPerSecond, 1)
            local t0 = tick()

            -- ═══ REMOTE AURA: blast every player simultaneously, no proximity ═══
            -- Attack() fires raw remotes server-side; position doesn't matter.
            -- One-shot active = everyone dies in one cycle hit.
            if CFG.RemoteAura then
                pcall(function()
                    for _, p in ipairs(Players:GetPlayers()) do
                        if p ~= plr and p.Character then
                            if IsWhitelisted(p.Name) then continue end
                            if CFG.AutoWhitelistFriends and IsFriend(p) then continue end
                            local h = p.Character:FindFirstChildOfClass("Humanoid")
                            if h and h.Health > 0 then
                                Attack(p.Character)
                            end
                        end
                    end
                end)
            else
                -- Standard target cache path
                if tick() - ST.LastTargetUpdate > CFG.TargetUpdateInterval then
                    RefreshTargets()
                end

                local tgts = ST.TargetCache
                if #tgts > 0 then
                    if CFG.GuardDropForAttack and CFG.UseAutoGuard then
                        SetGuard(false)
                    end

                    pcall(function()
                        if CFG.TargetAll then
                            -- Sort by priority
                            if rootPart and rootPart.Parent then
                                local mp = rootPart.Position
                                table.sort(tgts, function(a, b)
                                    return ScoreTarget(a, mp) > ScoreTarget(b, mp)
                                end)
                            end
                            local cnt = math.min(#tgts, CFG.MaxTargetsPerCycle)
                            for i = 1, cnt do
                                local t = tgts[i]
                                if t and t.Parent and IsValid(t) then
                                    Attack(t)
                                    -- ESP
                                    if CFG.ESPEnabled then CreateESP(t) end
                                end
                            end
                        else
                            -- Single target with priority
                            local best, bestScore = nil, -math.huge
                            if rootPart and rootPart.Parent then
                                local mp = rootPart.Position
                                for _, c in ipairs(tgts) do
                                    if IsValid(c) then
                                        local score = ScoreTarget(c, mp)
                                        if score > bestScore then
                                            bestScore = score
                                            best = c
                                        end
                                    end
                                end
                            end
                            if best then
                                Attack(best)
                                if CFG.ESPEnabled then CreateESP(best) end
                            end
                        end
                    end)

                    -- Stomp & Stun inline
                    if CFG.UseAutoStomp and REM.Stomp then TryStomp() end
                    if CFG.UseAutoStun and REM.Stun then TryStun() end

                    if CFG.GuardDropForAttack and CFG.UseAutoGuard then
                        task.delay(CFG.GuardReactivateDelay, function()
                            if CFG.UseAutoGuard and CFG.Enabled and ST.Running
                               and IsEnemyNearby(CFG.GuardActivationRange) then
                                SetGuard(true)
                            end
                        end)
                    end
                end
            end

            local w = interval - (tick() - t0)
            task.wait(w > 0 and w or 0.001)
        else
            task.wait(0.2)
        end
    end
end)

-- LOOP 2: DEFENSE (guard, PVP, health monitor)
task.spawn(function()
    while ST.Running do
        SafeCall(function()
            GetChar()
            if CFG.Enabled then
                -- Health monitor for guard
                if CFG.UseAutoGuard and humanoid then
                    local hp = humanoid.Health
                    if hp < ST.LastHealth and ST.EnemyNearby then
                        SetGuard(true)
                    end
                    ST.LastHealth = hp

                    -- Threat tracking
                    if hp < ST.LastHealth then
                        -- Someone damaged us, increase threat for nearby
                        for _, p in ipairs(Players:GetPlayers()) do
                            if p ~= plr and p.Character then
                                local r = p.Character:FindFirstChild("HumanoidRootPart")
                                if r and rootPart and rootPart.Parent then
                                    if (rootPart.Position - r.Position).Magnitude <= 20 then
                                        ST.ThreatTable[p.Name] = (ST.ThreatTable[p.Name] or 0) + (ST.LastHealth - hp)
                                    end
                                end
                            end
                        end
                    end
                end

                -- Guard keep-alive
                if CFG.UseAutoGuard then
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

                -- Smart PVP
                if CFG.UseSmartPVP and REM.PVPToggle then ManagePVP() end

                -- Crouch spam
                if CFG.UseCrouchSpam and REM.Crouch then
                    pcall(function()
                        REM.Crouch:FireServer(true)
                        task.wait(CFG.CrouchSpamSpeed)
                        REM.Crouch:FireServer(false)
                    end)
                end
            end
        end)

        -- Threat decay
        for name, threat in pairs(ST.ThreatTable) do
            ST.ThreatTable[name] = math.max(0, threat - 0.1)
            if ST.ThreatTable[name] <= 0 then ST.ThreatTable[name] = nil end
        end

        task.wait(0.1)
    end
end)

-- LOOP 3: SURVIVAL (heal, food, anti-AFK)
local _lastAFK = 0
task.spawn(function()
    while ST.Running do
        if CFG.Enabled then
            SafeCall(function()
                GetChar()
                if CFG.UseAutoHeal then TryHeal() end
                if CFG.UseAutoBuyFood then TryBuyFood() end
            end)
        end

        -- Anti-AFK (runs regardless of Enabled state)
        if CFG.AntiAFK then
            local now = tick()
            if now - _lastAFK >= 60 then
                _lastAFK = now
                pcall(function()
                    local vu = game:GetService("VirtualUser")
                    vu:CaptureController()
                    vu:ClickButton2(Vector2.new())
                end)
            end
        end

        task.wait(0.5)
    end
end)

-- LOOP 4: UTILITY (tool pickup, carry/throw)
task.spawn(function()
    while ST.Running do
        if CFG.Enabled then
            SafeCall(function()
                GetChar()
                if CFG.UseAutoPickupTools then TryPickupTools() end
                if CFG.UseAutoCarryThrow and REM.Carry and REM.Throw then TryCarryThrow() end
            end)
        end
        task.wait(0.5)
    end
end)

-- LOOP 5: UI (status card, DPS, ESP, combat log)
task.spawn(function()
    while ST.Running do
        SafeCall(function()
            if GUI_REFS and GUI_REFS.sv then
                local s = GUI_REFS.sv

                s.targets.Text = tostring(ST.TargetsFound)
                s.attacks.Text = tostring(ST.TotalAttacks)

                s.guard.Text = ST.GuardActive and "ON" or "OFF"
                s.guard.TextColor3 = ST.GuardActive and CLR.green or CLR.red

                -- DPS
                local dps = CalculateDPS()
                s.dps.Text = string.format("%.1f", dps)
                s.dps.TextColor3 = dps > 0 and CLR.cyan or CLR.textDim

                s.health.Text = humanoid
                    and tostring(math.floor(humanoid.Health)) or "?"

                s.mode.Text = CFG.KillAllActive and "KILL ALL"
                    or CFG.RemoteAura and "REMOTE AURA"
                    or (CFG.TargetAll and "AoE" or "Single")
                s.mode.TextColor3 = (CFG.KillAllActive or CFG.RemoteAura) and CLR.cyan or CLR.text

                s.nearby.Text = ST.EnemyNearby and "YES" or "NO"
                s.nearby.TextColor3 = ST.EnemyNearby and CLR.yellow or CLR.textDim

                s.kaKills.Text = tostring(ST.KillAllKills)
                s.kaKills.TextColor3 = ST.KillAllKills > 0 and CLR.cyan or CLR.text

                if s.uptime then
                    s.uptime.Text = "⏱ " .. FormatTime(tick() - ST.StartTime)
                end

                if GUI_REFS.timer then
                    GUI_REFS.timer.Text = FormatTime(tick() - ST.StartTime)
                end
            end

            -- Update ESP
            UpdateESP()

            -- Flush combat log
            FlushCombatLog()
        end)
        task.wait(0.25)
    end
end)

-- LOOP 6: REGISTRY MAINTENANCE (prune stale entries, re-scan caches)
task.spawn(function()
    while ST.Running do
        SafeCall(function()
            -- Prune stale NPC entries
            for model, data in pairs(ST.NPCRegistry) do
                if not model or not model.Parent
                   or not data.humanoid or not data.humanoid.Parent
                   or data.humanoid.Health <= 0 then
                    ST.NPCRegistry[model] = nil
                end
            end

            -- Prune stale tool entries
            for obj, data in pairs(ST.ToolRegistry) do
                if not obj or not obj.Parent then
                    ST.ToolRegistry[obj] = nil
                elseif obj:FindFirstAncestorOfClass("Backpack") then
                    ST.ToolRegistry[obj] = nil
                end
            end

            -- Re-scan food items cache
            ScanForFoodItems()
        end)
        task.wait(5)
    end
end)

----------------------------------------------------------------
-- S17. RESPAWN HANDLER + AUTO-RESPAWN
----------------------------------------------------------------
Conn(plr.CharacterAdded, function(newChar)
    char = newChar
    rootPart = char:WaitForChild("HumanoidRootPart", 10)
    humanoid = char:WaitForChild("Humanoid", 10)

    ST.GuardActive = false
    ST.LastHealth = humanoid and humanoid.Health or 100
    ST.LastTargetUpdate = 0
    ST.EnemyNearby = false
    ST.IsCarrying = false
    InvalidateNearbyCache()

    Notify("Respawned — systems reinitializing", "info", 2)
    AddLogEntry("system", "Respawned")

    -- Reapply size after spawn — wait for character to fully load first
    if CFG.SizeChangerEnabled then
        task.delay(0.5, function()
            ApplySize(CFG.SizeChangerValue)
        end)
    end

    task.delay(1, ScanForFoodItems)

    if CFG.UseAutoGuard and CFG.Enabled then
        task.wait(0.5)
        if IsEnemyNearby(CFG.GuardActivationRange) then
            SetGuard(true)
        end
    end

    -- Auto re-engage previous mode
    if CFG.AutoRespawn and CFG.AutoReengageMode and ST.PreviousMode then
        task.wait(1)
        if ST.PreviousMode == "KillAll" then
            CFG.KillAllActive = true
            CFG.Enabled = true
            if not ST.KillAllRunning then task.spawn(RunKillAll) end
            Notify("Auto-resumed: Kill All", "info", 2)
            AddLogEntry("system", "Auto-resumed Kill All after respawn")
        end
        ST.PreviousMode = nil
    end

    -- Track DPS on humanoid health changes
    if humanoid then
        -- We track target health changes in the attack loop itself
        -- Here we track damage taken for threat table
        Conn(humanoid.HealthChanged:Connect(function(newHP)
            if newHP < ST.LastHealth then
                -- We took damage
            end
            ST.LastHealth = newHP
        end))
    end
end)

-- Track mode before death for auto-respawn
Conn(plr.CharacterRemoving, function()
    if CFG.KillAllActive then
        ST.PreviousMode = "KillAll"
    end
    ST.CurrentMode = nil
    AddLogEntry("death", "Player died")
end)

-- Anti-AFK idle connection
pcall(function()
    Conn(plr.Idled, function()
        if CFG.AntiAFK then
            pcall(function()
                local vu = game:GetService("VirtualUser")
                vu:CaptureController()
                vu:ClickButton2(Vector2.new())
            end)
        end
    end)
end)

-- Auto-respawn: attempt to click respawn button
if CFG.AutoRespawn then
    task.spawn(function()
        while ST.Running do
            if not plr.Character or not plr.Character.Parent then
                -- Try to find and click respawn button
                pcall(function()
                    local pg = plr:FindFirstChild("PlayerGui")
                    if pg then
                        for _, gui in ipairs(pg:GetDescendants()) do
                            if gui:IsA("TextButton") or gui:IsA("ImageButton") then
                                local txt = ""
                                pcall(function() txt = gui.Text:lower() end)
                                if txt:find("respawn") or txt:find("retry")
                                   or txt:find("play again") or txt:find("restart") then
                                    pcall(function()
                                        -- Simulate click via event firing
                                        gui.MouseButton1Click:Fire()
                                    end)
                                end
                            end
                        end
                    end
                end)
            end
            task.wait(2)
        end
    end)
end

----------------------------------------------------------------
-- S18. INITIALIZATION
----------------------------------------------------------------
RefreshTargets()
ST.EnemyNearby = IsEnemyNearby(CFG.GuardActivationRange)
if CFG.UseAutoGuard and CFG.Enabled and ST.EnemyNearby then
    SetGuard(true)
end

if IS_XENO then
    XenoLoadConfig(CFG)
end

task.delay(0.5, function()
    local remoteCount = 0
    for _, v in pairs(REM) do if v then remoteCount += 1 end end
    Notify("MAP v" .. SCRIPT_VERSION .. " loaded | "
           .. EXECUTOR_NAME .. " | " .. remoteCount .. "/17 remotes"
           .. (ONESHOT_HOOKED and " | ONE-SHOT ACTIVE" or ""), "success", 4)
    AddLogEntry("system", "Script loaded — " .. remoteCount .. " remotes found"
        .. (ONESHOT_HOOKED and " | one-shot hook active" or ""))
    if IS_XENO then
        Notify("Xeno detected — config persistence active", "info", 3)
    end
end)

print("╔══════════════════════════════════════════════════╗")
print("║    MASS ATTACK PRO v" .. SCRIPT_VERSION .. " — XENO COMPATIBLE    ║")
print("╠══════════════════════════════════════════════════╣")
print("║  Executor:  " .. EXECUTOR_NAME)
print("║  One-Shot:  " .. (ONESHOT_HOOKED and "ACTIVE" or "unavailable (fallback mode)"))
print("║  Insert      =  Toggle GUI")
print("║  RightShift  =  Toggle Script")
print("║  K           =  Kill All Toggle")
print("║  T           =  AoE / Single Toggle")
print("║  X           =  Emergency Stop")
print("║  B           =  Toggle Auto Block")
print("╚══════════════════════════════════════════════════╝")
