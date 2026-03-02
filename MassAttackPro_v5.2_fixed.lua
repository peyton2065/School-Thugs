--[[
╔══════════════════════════════════════════════════════════════════╗
║                   MASS ATTACK PRO v5.0                         ║
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
║  CHANGELOG v4.0 → v5.0:                                       ║
║                                                                ║
║  [CRITICAL FIXES]                                              ║
║  • Carniceria: BindableEvent — .Fire() replaces :FireServer()  ║
║  • IsPlayerDown: States.isRagdoleao replaces all heuristics    ║
║  • RANDOMS blocking/stunned gates wired into Loop 1+2          ║
║  • GroupHeader X param fix — columns no longer overlap         ║
║  • Conn(humanoid.HealthChanged,...) double-connect fixed        ║
║  • task.wait floor raised to 0.01 — no 1000hz hammering        ║
║  • Keybind Enum.KeyCode serialization fixed for Xeno persist   ║
║  • continue → if-guards everywhere (older Luau compat)         ║
║  • ClearAllESP() called when TargetCache is empty              ║
║  • ApplySize nil-char guard on SizeChanger disable             ║
║                                                                ║
║  [NEW FEATURES]                                                ║
║  • DisableControls + NoTools fired pre-attack on target        ║
║  • ATM Farmer — destroys workspace.Damageables ATMs            ║
║  • In-world Shop Auto-Buy via ProximityPrompt scan             ║
║  • PickUpItems folder explicit registration + ProxPrompt       ║
║  • Throwables Auto-Grab (Throw RemoteFunction)                 ║
║  • Stamina-based targeting — LowestStamina priority mode       ║
║  • SmallestFirst targeting priority mode                       ║
║  • suplexCharge-gated suplex (SmartSuplexGating)               ║
║  • Team-based targeting filter (None/StudentsOnly/VIPOnly)     ║
║  • TELEPORTPLAYERSBACK zone avoidance in Kill All              ║
║  • Auto Spin Wheel (IsResetTime + Spin RemoteFunctions)        ║
║  • ESP stat upgrade: Money, Kills, Level, Size labels          ║
║  • Quest Farmer auto-links Quests + ChristmasQuests folders    ║
║  • Effects on hit: Shake, Red Screen, Impact Frames            ║
║  • hasPvpOn state check — skip PVP-off targets (unless BL)     ║
║  • RagdollTrigger IntValue used in stomp detection             ║
║                                                                ║
║  [GUI OVERHAUL v5.0]                                           ║
║  • CornerRadius tightened to 6 everywhere                      ║
║  • Header shrunk to 40px, gradient refined                     ║
║  • Pill-style tabs — active tab gets category color fill       ║
║  • Dropdown widget for TargetPriority + TeamFilter             ║
║  • New sections: Effects, ATM Farmer, Shop, Quests, Spin Wheel ║
║  • Search scans TextLabel .Text content, not just frame Name   ║
║  • Window open: Quint + 0.95→1.0 scale animation              ║
║  • Refined palette: bg #0A0A12, accent #6339FF, green #34D399  ║
╚══════════════════════════════════════════════════════════════════╝
]]

local SCRIPT_VERSION = "5.1"
--[[
  CHANGELOG v5.0 -> v5.1 (BUG FIX PASS):
  [FIX 1] REVERTED - standard loop does NOT teleport. AttackRange gate restored (attacks nearby only).
           Kill All remains the sole system that teleports. Remote Aura fires globally without moving.
  [FIX 2] _espStatUpdate nil-reference declared before UpdateESP() - ESP no longer errors every 0.15s
  [FIX 3] ToolHit:FireServer() signatures normalized - no more double-fire / arg mismatch
  [FIX 4] RANDOMS_BLOCKING gated into Attack() pre-fire check - blocked targets skipped
  [FIX 5] Conn() nil-guards signal before Connect() - no more silent crash on missing RANDOMS children
  [FIX 6] RemoteAura branch now runs full IsValid() - ForceField/TeamFilter/PVP respected
  [FIX 7] Sorted target list cached between RefreshTargets() calls - ~95% fewer GetPlayerFromCharacter calls
  [FIX 8] TryPickupTools() tier-waits moved into task.spawn - Loop 3 no longer stalls 0.6s per cycle
  [FIX 9] DPSHistory capped proactively in RecordDamage() - no unbounded growth
  [FIX 10] GuardActivationRange slider invalidates nearby cache on change
]]

----------------------------------------------------------------
-- S0. EXECUTOR DETECTION & UNC SHIMS
----------------------------------------------------------------
local EXECUTOR_NAME = "Unknown"
local IS_XENO      = false

pcall(function()
    if type(identifyexecutor) == "function" then
        EXECUTOR_NAME = identifyexecutor()
    elseif type(getexecutorname) == "function" then
        EXECUTOR_NAME = getexecutorname()
    end
end)

pcall(function()
    if Xeno and type(Xeno) == "table" then
        IS_XENO       = true
        EXECUTOR_NAME = "Xeno"
        if Xeno.PID then print("[MAP] Xeno PID:", Xeno.PID) end
    end
end)

print("[MAP] Executor:", EXECUTOR_NAME, "| Xeno:", IS_XENO)

if not cloneref       then cloneref       = function(o) return o end end
if not getnilinstances then getnilinstances = function() return {} end end
if not getinstances   then getinstances   = function() return {} end end

local CAN_HOOK_META  = type(hookmetamethod)    == "function"
local CAN_HOOK_FUNC  = type(hookfunction)      == "function"
local CAN_FIRE_CLICK = type(fireclickdetector) == "function"
local CAN_FIRE_PROMPT= type(fireproximityprompt) == "function"
local CAN_SET_CLIPBOARD = type(setclipboard)   == "function"

----------------------------------------------------------------
-- S0b. ONE-SHOT DAMAGE FLAG
----------------------------------------------------------------
local ONESHOT_HOOKED = false
local PUNCH_REMOTE   = nil

pcall(function()
    local folder = game:GetService("ReplicatedStorage"):FindFirstChild("MainEvents")
    if folder then PUNCH_REMOTE = folder:FindFirstChild("PUNCHEVENT") end
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
                local pg = game:GetService("Players").LocalPlayer:FindFirstChild("PlayerGui")
                if pg then oldGui = pg:FindFirstChild("MassAttackPro") end
            end)
        end
        if oldGui then oldGui:Destroy() end
    end)
    _G._MassAttackPro = nil
    task.wait(0.2)
end

----------------------------------------------------------------
-- S1b. SERVICES & CORE REFERENCES
----------------------------------------------------------------
local Players      = cloneref(game:GetService("Players"))
local RepStorage   = cloneref(game:GetService("ReplicatedStorage"))
local UIS          = cloneref(game:GetService("UserInputService"))
local TweenService = cloneref(game:GetService("TweenService"))
local RunService   = cloneref(game:GetService("RunService"))
local HttpService  = cloneref(game:GetService("HttpService"))
local StarterPack  = cloneref(game:GetService("StarterPack"))

local plr      = Players.LocalPlayer
local char     = plr.Character or plr.CharacterAdded:Wait()
local rootPart = char:WaitForChild("HumanoidRootPart", 10)
local humanoid = char:WaitForChild("Humanoid", 10)

local function ParentGui(screenGui)
    local ok = pcall(function() screenGui.Parent = game:GetService("CoreGui") end)
    if ok and screenGui.Parent then return end
    ok = pcall(function()
        if type(gethui) == "function" then screenGui.Parent = gethui()
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
    TargetPriority       = "Nearest", -- "Nearest"|"LowestHP"|"HighestThreat"|"LowestStamina"|"SmallestFirst"

    -- Attack types
    UsePunch             = true,
    UseSuplex            = true,
    UseHeavyHit          = true,

    -- Suplex gating
    SmartSuplexGating       = true,
    SuplexChargeThreshold   = 50,

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
    UseAutoGuard            = true,
    GuardCooldown           = 0.10,
    GuardDropForAttack      = true,
    GuardReactivateDelay    = 0.04,
    HealthPollInterval      = 0.05,
    GuardActivationRange    = 15,

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

    -- Throwables (world objects)
    UseAutoThrowable     = false,
    ThrowableRange       = 30,
    ThrowableCooldown    = 3.0,

    -- Crouch Spam
    UseCrouchSpam        = false,
    CrouchSpamSpeed      = 0.15,

    -- PVP Toggle
    UseSmartPVP          = true,
    PVPOffThreshold      = 25,
    PVPOnThreshold       = 80,

    -- Remote Aura
    RemoteAura           = false,

    -- Kill All
    KillAllActive        = false,
    KillAllTimeout       = 8,
    KillAllTeleportDelay = 0.25,
    KillAllReteleportDist= 12,
    KillAllRetries       = 3,

    -- Size Changer
    SizeChangerEnabled   = false,
    SizeChangerValue     = 1.0,

    -- New Features
    AntiAFK              = true,
    AutoRespawn          = false,
    AutoReengageMode     = true,
    KillAuraVisualization= false,
    ESPEnabled           = false,
    ESPShowStats         = false,
    DPSTrackingWindow    = 3,
    CombatLogEnabled     = true,
    CombatLogMaxEntries  = 50,

    -- Combat effects on hit
    UseDisableControlsOnAttack = false,
    UseNoToolsOnAttack         = false,
    UseShakeOnHit              = false,
    UseRedScreenOnHit          = false,
    UseImpactFramesOnHit       = false,

    -- ATM Farmer
    UseATMFarmer         = false,
    ATMFarmerCooldown    = 0.5,

    -- Shop Auto-Buy
    UseAutoShopBuy       = false,
    ShopBuyList          = {
        Crowbar       = false,
        Baseballbat   = false,
        Sledgehammer  = false,
        BoxingGloves  = false,
        Hotdog        = false,
        Cookies       = false,
        Cabbage       = false,
        Drink         = false,
    },

    -- Spin Wheel
    UseAutoSpin          = false,
    AutoSpinCooldown     = 35,

    -- Quest Farmer
    UseQuestFarmer       = false,

    -- Targeting upgrades
    TeamFilter           = "None",   -- "None" | "StudentsOnly" | "VIPOnly"
    UseTPBackAvoidance   = true,

    -- Whitelist / Blacklist
    Whitelist            = {},
    Blacklist            = {},
    AutoWhitelistFriends = true,

    -- Keybinds (stored as strings for Xeno serialization)
    Keybinds = {
        ToggleGUI       = "Insert",
        ToggleScript    = "RightShift",
        KillAll         = "K",
        ToggleAoE       = "T",
        EmergencyStop   = "X",
        ToggleAutoBlock = "B",
    },

    -- UI State
    DefaultTab         = "Combat",
    CollapsedSections  = {},

    -- Cached signatures
    CachedFoodSignature  = nil,
    CachedPickupSignature= nil,

    Debug              = false,
}

-- Keybind name→Enum lookup
local KEYCODE_LOOKUP = {}
for name, val in pairs(Enum.KeyCode:GetEnumItems()) do
    KEYCODE_LOOKUP[val.Name] = val
end

-- Resolve a stored keybind string to Enum.KeyCode
local function ResolveKey(name)
    return KEYCODE_LOOKUP[name] or Enum.KeyCode.Unknown
end

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
    ATMRegistry       = {},
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

    -- Kill aura
    AuraRing          = nil,
    AuraConn          = nil,

    -- Fix 7: cached sorted target list - rebuilt only when RefreshTargets fires
    SortedTargetCache      = {},
    SortedTargetCacheDirty = true,

    -- Notification tracking
    ActiveNotifs      = {},

    -- Spin wheel
    LastSpinTime      = 0,
    LastSpinReward    = "None",

    -- Shop cache
    ShopButtonCache   = {},
    ShopCacheTime     = 0,

    -- Quest display refs (filled by GUI)
    QuestLabels       = {},
}

local _nearbyCache = { result = false, lastCheck = 0, interval = 0.5 }

_G._MassAttackPro = ST

----------------------------------------------------------------
-- S3. CONFIG PERSISTENCE
----------------------------------------------------------------

-- Keybind serialization: save as string name ("Insert"), restore via lookup
local function XenoSaveConfig(cfg)
    pcall(function()
        if IS_XENO and Xeno.SetGlobal then
            local saveData = {}
            for k, v in pairs(cfg) do
                local t = type(v)
                if t == "number" or t == "boolean" or t == "string" then
                    saveData[k] = tostring(v)
                elseif t == "table" then
                    -- Special: Keybinds already stored as strings, encode directly
                    pcall(function()
                        saveData[k] = HttpService:JSONEncode(v)
                    end)
                end
            end
            Xeno.SetGlobal("MAP_Config_v5", saveData)
        end
    end)
end

local function XenoLoadConfig(cfg)
    pcall(function()
        if IS_XENO and Xeno.GetGlobal then
            local saved = Xeno.GetGlobal("MAP_Config_v5")
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

local function Conn(signal, fn)
    -- Fix 5: guard against nil signals (missing RANDOMS children, absent folders, etc.)
    if not signal then return { Disconnect = function() end } end
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

--- Read a player's States folder — authoritative ragdoll/pvp/dead detection
-- @param playerInstance Player
-- @return table|nil
local function GetPlayerStates(playerInstance)
    if not playerInstance then return nil end
    local states = playerInstance:FindFirstChild("States")
    if not states then return nil end
    local pvpVal      = states:FindFirstChild("hasPvpOn")
    local ragdollVal  = states:FindFirstChild("isRagdoleao") -- exact game spelling
    local deadVal     = states:FindFirstChild("Dead")
    return {
        pvpOn     = pvpVal    and pvpVal.Value    ~= 0 or false,
        ragdolled = ragdollVal and ragdollVal.Value ~= 0 or false,
        dead      = deadVal   and deadVal.Value    ~= 0 or false,
    }
end

--- Apply a uniform size scale to the local character
local function ApplySize(value)
    GetChar()
    if not char or not char.Parent then return end
    if not rootPart or not humanoid then return end
    pcall(function()
        local rayParams = RaycastParams.new()
        rayParams.FilterDescendantsInstances = { char }
        rayParams.FilterType = Enum.RaycastFilterType.Exclude
        local hit = workspace:Raycast(rootPart.Position, Vector3.new(0, -100, 0), rayParams)
        local groundY = hit and hit.Position.Y
            or (rootPart.Position.Y - humanoid.HipHeight - rootPart.Size.Y / 2)
        char:ScaleTo(value)
        task.defer(function()
            GetChar()
            if not rootPart or not rootPart.Parent then return end
            local newHipH     = humanoid.HipHeight
            local newHrpHalfY = rootPart.Size.Y / 2
            local targetY     = groundY + newHipH + newHrpHalfY
            rootPart.CFrame = CFrame.new(
                rootPart.Position.X, targetY, rootPart.Position.Z
            ) * CFrame.fromMatrix(
                Vector3.zero, rootPart.CFrame.XVector, rootPart.CFrame.YVector
            )
        end)
    end)
end

--- TPBACK zone AABB check
local TPBACK_ZONES = {}
do
    local tpFolder = workspace:FindFirstChild("TELEPORTPLAYERSBACK")
    if tpFolder then
        for _, part in ipairs(tpFolder:GetChildren()) do
            if part:IsA("BasePart") then
                table.insert(TPBACK_ZONES, { pos = part.Position, size = part.Size })
            end
        end
    end
end

local function IsInTPBackZone(position)
    for _, zone in ipairs(TPBACK_ZONES) do
        local half = zone.size / 2
        local diff = position - zone.pos
        if math.abs(diff.X) <= half.X + 2
        and math.abs(diff.Y) <= half.Y + 10
        and math.abs(diff.Z) <= half.Z + 2 then
            return true
        end
    end
    return false
end

--- Safe teleport that avoids TPBACK zones
local function SafeTeleport(targetCFrame)
    if not CFG.UseTPBackAvoidance then
        rootPart.CFrame = targetCFrame
        return
    end
    local pos = targetCFrame.Position
    if not IsInTPBackZone(pos) then
        rootPart.CFrame = targetCFrame
        return
    end
    -- Nudge in ±X/Z until clear (max 8 attempts)
    local offsets = {
        Vector3.new(5,0,0), Vector3.new(-5,0,0),
        Vector3.new(0,0,5), Vector3.new(0,0,-5),
        Vector3.new(5,0,5), Vector3.new(-5,0,5),
        Vector3.new(5,0,-5), Vector3.new(-5,0,-5),
    }
    for _, off in ipairs(offsets) do
        local newPos = pos + off
        if not IsInTPBackZone(newPos) then
            rootPart.CFrame = CFrame.new(newPos) * CFrame.fromMatrix(
                Vector3.zero, targetCFrame.XVector, targetCFrame.YVector
            )
            return
        end
    end
    -- All nudges in zone — teleport anyway (better than not moving)
    rootPart.CFrame = targetCFrame
end

local function IsFriend(targetPlayer)
    if ST.FriendCache[targetPlayer.UserId] ~= nil then
        return ST.FriendCache[targetPlayer.UserId]
    end
    local ok, result = pcall(function() return plr:IsFriendsWith(targetPlayer.UserId) end)
    local val = ok and result or false
    ST.FriendCache[targetPlayer.UserId] = val
    return val
end

local function IsWhitelisted(playerName)
    return CFG.Whitelist[playerName] == true
end

local function IsBlacklisted(playerName)
    return CFG.Blacklist[playerName] == true
end

local Notify    = function() end
local AddLogEntry = function() end

----------------------------------------------------------------
-- S4b. COMBAT LOG
----------------------------------------------------------------
local LOG_COLORS = {
    kill   = Color3.fromRGB(255, 80,  80),
    death  = Color3.fromRGB(255, 50,  50),
    heal   = Color3.fromRGB(52,  211, 153),
    pickup = Color3.fromRGB(255, 220, 80),
    system = Color3.fromRGB(180, 180, 180),
    error  = Color3.fromRGB(255, 100, 50),
}

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
    bg          = Color3.fromRGB(10,  10,  18),
    header      = Color3.fromRGB(18,  18,  30),
    headerGrad  = Color3.fromRGB(26,  20,  44),
    card        = Color3.fromRGB(22,  22,  36),
    cardHover   = Color3.fromRGB(28,  28,  46),
    accent      = Color3.fromRGB(99,  57,  255),
    accentDim   = Color3.fromRGB(70,  40,  180),
    text        = Color3.fromRGB(235, 235, 245),
    textDim     = Color3.fromRGB(120, 120, 148),
    green       = Color3.fromRGB(52,  211, 153),
    red         = Color3.fromRGB(240, 60,  60),
    orange      = Color3.fromRGB(245, 170, 45),
    yellow      = Color3.fromRGB(245, 215, 50),
    cyan        = Color3.fromRGB(50,  195, 240),
    toggleOff   = Color3.fromRGB(55,  55,  75),
    border      = Color3.fromRGB(38,  38,  58),
    sliderBg    = Color3.fromRGB(28,  28,  45),
    shadow      = Color3.fromRGB(0,   0,   0),
    notifBg     = Color3.fromRGB(24,  24,  40),
    tabActive   = Color3.fromRGB(32,  32,  52),
    tabInactive = Color3.fromRGB(16,  16,  28),
    tooltipBg   = Color3.fromRGB(14,  14,  26),
}

local CAT_COLORS = {
    Combat   = Color3.fromRGB(177, 100, 255),
    Defense  = Color3.fromRGB(100, 150, 255),
    Survival = Color3.fromRGB(52,  211, 153),
    Utility  = Color3.fromRGB(255, 200, 100),
    System   = Color3.fromRGB(180, 180, 180),
}

local TWEEN_FAST   = TweenInfo.new(0.12, Enum.EasingStyle.Quad,  Enum.EasingDirection.Out)
local TWEEN_SMOOTH = TweenInfo.new(0.20, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local TWEEN_BOUNCE = TweenInfo.new(0.18, Enum.EasingStyle.Back,  Enum.EasingDirection.Out)

----------------------------------------------------------------
-- S6. REMOTE DETECTION
----------------------------------------------------------------
local MainEventsFolder   = RepStorage:FindFirstChild("MainEvents")
local EffectsFoldr       = RepStorage:FindFirstChild("EffectsRemoteEvents")
local SpinWheelFolder    = RepStorage:FindFirstChild("SpinWheel")

--- Find a RemoteEvent or RemoteFunction by name
local function FindRemote(name)
    local r
    -- Check MainEvents first
    if MainEventsFolder then
        r = MainEventsFolder:FindFirstChild(name)
        if r then return r end
    end
    -- Deep search ReplicatedStorage
    r = RepStorage:FindFirstChild(name, true)
    if r then return r end
    -- Nil instances
    pcall(function()
        for _, v in ipairs(getnilinstances()) do
            if (v:IsA("RemoteEvent") or v:IsA("RemoteFunction")) and v.Name == name then
                r = v
            end
        end
    end)
    if r then return r end
    pcall(function()
        if type(getinstances) == "function" then
            for _, v in ipairs(getinstances()) do
                if (v:IsA("RemoteEvent") or v:IsA("RemoteFunction")) and v.Name == name then
                    r = v
                end
            end
        end
    end)
    return r
end

--- Find a BindableEvent by name
local function FindBindable(name)
    if MainEventsFolder then
        local b = MainEventsFolder:FindFirstChild(name)
        if b and b:IsA("BindableEvent") then return b end
    end
    local b = RepStorage:FindFirstChild(name, true)
    if b and b:IsA("BindableEvent") then return b end
    return nil
end

--- Find inside Effects folder specifically
local function FindEffect(name)
    if EffectsFoldr then
        local r = EffectsFoldr:FindFirstChild(name)
        if r then return r end
    end
    return FindRemote(name)
end

--- Find inside SpinWheel folder specifically
local function FindSpin(name)
    if SpinWheelFolder then
        local r = SpinWheelFolder:FindFirstChild(name)
        if r then return r end
    end
    return FindRemote(name)
end

local REM = {
    -- Core combat
    Punch      = FindRemote("PUNCHEVENT"),
    Suplex     = FindRemote("SUPLEXEVENT"),
    HeavyHit   = FindRemote("HEAVYHIT"),
    Block      = FindRemote("BLOCKEVENT"),
    Stomp      = FindRemote("STOMPEVENT"),
    ToolHit    = FindRemote("TOOLHITEVENT"),
    Stun       = FindRemote("STUNEVENT"),
    Heal       = FindRemote("HEALCHARACTERCARRIED"),
    Carry      = FindRemote("CARRYEVENT"),
    Throw      = FindRemote("Throw"),           -- RemoteFunction in MainEvents
    Crouch     = FindRemote("CROUCHEVENT"),
    StopAnim   = FindRemote("STOPLOCALANIMATIONS"),
    PVPToggle  = FindRemote("PVPONOFFEVENT"),
    PickupTool = FindRemote("PICKUPTOOLSEVENT"),
    AdminCmd   = FindRemote("ADMINCOMMANDS"),
    AdminPanel = FindRemote("ADMINPANNEL"),

    -- Carniceria is a BindableEvent — use .Fire() not :FireServer()
    Carniceria = FindBindable("Carniceria"),

    -- Effects folder
    DisableControlsEffect = FindEffect("DisableControls"),
    NoTools               = FindEffect("NoTools"),
    ShakeScreen           = FindEffect("ShakeScreenEvent"),
    RedScreen             = FindEffect("RedScreenEvent"),
    ImpactFrames          = FindEffect("ImpactFramesEvent"),

    -- SpinWheel folder (RemoteFunctions)
    IsResetTime = FindSpin("IsResetTime"),
    Spin        = FindSpin("Spin"),
    Sell1Spin   = FindSpin("Sell1Spin"),
}

-- Disable features whose remotes weren't found
if not REM.Punch    then CFG.UsePunch               = false end
if not REM.Suplex   then CFG.UseSuplex              = false end
if not REM.HeavyHit then CFG.UseHeavyHit            = false end
if not REM.Block    then CFG.UseAutoGuard            = false end
if not REM.Stomp    then CFG.UseAutoStomp            = false end
if not REM.ToolHit  then CFG.UseToolAttack           = false end
if not REM.Stun     then CFG.UseAutoStun             = false end
if not REM.StopAnim then CFG.UseAnimCancel           = false end
if not REM.Throw    then CFG.UseAutoThrowable        = false; CFG.UseAutoCarryThrow = false end

local HAS_ATTACK = REM.Punch or REM.Suplex or REM.HeavyHit or REM.ToolHit

----------------------------------------------------------------
-- S7. REGISTRY SYSTEMS
----------------------------------------------------------------
local FOOD_KEYWORDS = {
    "food","pizza","burger","meat","steak","chicken","sandwich","hotdog",
    "taco","burrito","soda","drink","water","juice","milk","apple",
    "bread","donut","candy","chips","snack","fries","rice","soup",
    "heal","health","potion","bandage","medkit","med","carne","torta",
    "empanada","elote","churro","pollo","bistec","carnitas","barbacoa","asada",
    "cookies","cabbage","hotdog",
}

local WEAPON_KEYWORDS = {
    "bat","metal","weapon","knife","sword","pipe","gun","pistol","rifle",
    "shotgun","tool","crowbar","machete","hammer","axe","stick","club",
    "chain","wrench","bottle","brick","rock","pan","shovel",
    "chair","stopsign","stop sign","ladder","frying","chicharron",
    "boxing","gloves","sledge","baseball",
}

local function IsLikelyFood(name)
    local lower = name:lower()
    for _, kw in ipairs(FOOD_KEYWORDS) do
        if lower:find(kw, 1, true) then return true end
    end
    return false
end

local function IsLikelyWeapon(name)
    local lower = name:lower()
    for _, kw in ipairs(WEAPON_KEYWORDS) do
        if lower:find(kw, 1, true) then return true end
    end
    return false
end

-- ===== NPC REGISTRY =====
local function TryRegisterNPC(model)
    if not model or not model:IsA("Model") then return end
    if Players:GetPlayerFromCharacter(model) then return end
    local hum = model:FindFirstChildOfClass("Humanoid")
    local hrp = model:FindFirstChild("HumanoidRootPart")
    if hum and hrp and hum.Health > 0 then
        ST.NPCRegistry[model] = { humanoid = hum, hrp = hrp, addedAt = tick() }
        local deathConn
        deathConn = hum.Died:Connect(function()
            ST.NPCRegistry[model] = nil
            if deathConn then deathConn:Disconnect() end
        end)
        table.insert(ST.Connections, deathConn)
    end
end

local function DeregisterNPC(model)
    ST.NPCRegistry[model] = nil
end

local function InitNPCRegistry()
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("Humanoid") and obj.Parent then
            TryRegisterNPC(obj.Parent)
        end
    end
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
end

-- ===== TOOL REGISTRY =====
local TOOL_FOLDERS = {
    "Drops","Items","Weapons","Loot","DroppedItems",
    "DropItems","Tools","Pickups","SpawnedItems","PickUpItems",
}

local function GetToolPart(obj)
    if obj:IsA("Tool") then
        return obj:FindFirstChild("Handle")
    elseif obj:IsA("Model") then
        return obj.PrimaryPart or obj:FindFirstChild("Handle")
            or obj:FindFirstChildWhichIsA("BasePart")
    elseif obj:IsA("BasePart") or obj:IsA("UnionOperation")
        or obj:IsA("MeshPart") or obj:IsA("SpecialMesh") then
        return obj
    end
    return nil
end

local function TryRegisterTool(obj)
    if ST.ToolRegistry[obj] then return end
    if not obj or not obj.Parent then return end

    local validType = obj:IsA("Tool")
        or (obj:IsA("Model")         and IsLikelyWeapon(obj.Name))
        or (obj:IsA("BasePart")      and IsLikelyWeapon(obj.Name))
        or (obj:IsA("UnionOperation")and IsLikelyWeapon(obj.Name))
        or (obj:IsA("MeshPart")      and IsLikelyWeapon(obj.Name))

    if not validType then return end
    if obj:FindFirstAncestorOfClass("Backpack") then return end

    local part = GetToolPart(obj)
    if not part then return end

    ST.ToolRegistry[obj] = {
        instance           = obj,
        name               = obj.Name,
        part               = part,
        hasClickDetector   = obj:FindFirstChildWhichIsA("ClickDetector",   true) ~= nil,
        hasProximityPrompt = obj:FindFirstChildWhichIsA("ProximityPrompt", true) ~= nil,
        failCount          = 0,
        blacklistedUntil   = 0,
    }
end

local function DeregisterTool(obj)
    ST.ToolRegistry[obj] = nil
end

local function InitToolRegistry()
    -- Standard folders
    for _, obj in ipairs(workspace:GetChildren()) do
        TryRegisterTool(obj)
    end
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
    -- PickUpItems explicit scan — these are world interaction items (all have ProximityPrompts)
    local pickupFolder = workspace:FindFirstChild("PickUpItems")
    if pickupFolder then
        for _, obj in ipairs(pickupFolder:GetChildren()) do
            if obj:IsA("BasePart") or obj:IsA("UnionOperation") or obj:IsA("MeshPart") then
                -- Force-register regardless of name keywords
                local pp = obj:FindFirstChildWhichIsA("ProximityPrompt")
                if pp and not ST.ToolRegistry[obj] then
                    ST.ToolRegistry[obj] = {
                        instance           = obj,
                        name               = obj.Name,
                        part               = obj,
                        hasClickDetector   = false,
                        hasProximityPrompt = true,
                        failCount          = 0,
                        blacklistedUntil   = 0,
                    }
                end
            end
        end
        Conn(pickupFolder.ChildAdded, function(obj)
            task.defer(function() TryRegisterTool(obj) end)
        end)
        Conn(pickupFolder.ChildRemoved, DeregisterTool)
    end
    -- Deep scan for Tool instances
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("Tool") then TryRegisterTool(obj) end
    end
    -- Live listeners
    Conn(workspace.DescendantAdded, function(obj)
        if obj:IsA("Tool")
        or (obj:IsA("Model")          and IsLikelyWeapon(obj.Name))
        or (obj:IsA("UnionOperation") and IsLikelyWeapon(obj.Name)) then
            task.defer(function() TryRegisterTool(obj) end)
        end
    end)
    Conn(workspace.DescendantRemoving, function(obj)
        DeregisterTool(obj)
    end)
    Log("Tool Registry initialized")
end

-- ===== ATM REGISTRY (event-driven) =====
local function InitATMRegistry()
    local damageables = workspace:FindFirstChild("Damageables")
    if not damageables then return end
    for _, atm in ipairs(damageables:GetChildren()) do
        if atm.Name == "ATM" then
            local mesh = atm:FindFirstChild("ATM")
            if mesh then
                ST.ATMRegistry[atm] = mesh
            end
        end
    end
    Conn(damageables.ChildRemoved, function(obj)
        ST.ATMRegistry[obj] = nil
        AddLogEntry("system", "ATM destroyed: " .. obj.Name)
    end)
    Conn(damageables.ChildAdded, function(obj)
        if obj.Name == "ATM" then
            task.defer(function()
                local mesh = obj:FindFirstChild("ATM")
                if mesh then ST.ATMRegistry[obj] = mesh end
            end)
        end
    end)
end

-- ===== RANDOMS HANDLES =====
local RANDOMS_FOLDER = workspace:FindFirstChild("RANDOMS")
local RANDOMS_BLOCKING = RANDOMS_FOLDER and RANDOMS_FOLDER:FindFirstChild("blocking")
local RANDOMS_STUNNED  = RANDOMS_FOLDER and RANDOMS_FOLDER:FindFirstChild("stunned")
local RANDOMS_RAGDOLL  = RANDOMS_FOLDER and RANDOMS_FOLDER:FindFirstChild("RagdollTrigger")

-- ===== FOOD ITEM CACHE =====
local function ScanForFoodItems()
    local now = tick()
    if now - ST.FoodItemCacheTime < 30 then return ST.FoodItemCache end
    local items   = {}
    local checked = {}
    pcall(function()
        for _, obj in ipairs(RepStorage:GetDescendants()) do
            if not checked[obj.Name] and IsLikelyFood(obj.Name) then
                checked[obj.Name] = true
                table.insert(items, obj.Name)
            end
        end
    end)
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
    pcall(function()
        for _, t in ipairs(StarterPack:GetChildren()) do
            if t:IsA("Tool") and not checked[t.Name] and IsLikelyFood(t.Name) then
                checked[t.Name] = true
                table.insert(items, t.Name)
            end
        end
    end)
    ST.FoodItemCache     = items
    ST.FoodItemCacheTime = now
    return items
end

-- ===== SHOP BUTTON SCAN =====
local SHOP_BUTTON_NAMES = {
    Crowbar      = "botonComprarCrowbar",
    Baseballbat  = "botonComprarBaseballbat",
    Sledgehammer = "botonComprarSledgehammer",
    BoxingGloves = "botonComprarBoxingGloves",
    Hotdog       = "botonComprarHotdog",
    Cookies      = "botonComprarCookies",
    Cabbage      = "botonComprarCabbage",
    Drink        = "botonComprarDrink",
}

local function ScanShopButtons()
    local now = tick()
    if now - ST.ShopCacheTime < 30 then return ST.ShopButtonCache end
    ST.ShopButtonCache = {}
    pcall(function()
        for _, obj in ipairs(workspace:GetDescendants()) do
            for itemName, btnName in pairs(SHOP_BUTTON_NAMES) do
                if obj.Name == btnName and not ST.ShopButtonCache[itemName] then
                    local pp = obj:FindFirstChildWhichIsA("ProximityPrompt")
                        or obj:FindFirstChildWhichIsA("ClickDetector")
                    if pp then
                        ST.ShopButtonCache[itemName] = { obj = obj, prompt = pp }
                    end
                end
            end
        end
    end)
    ST.ShopCacheTime = now
    return ST.ShopButtonCache
end

-- Initialize all registries
InitNPCRegistry()
InitToolRegistry()
InitATMRegistry()
task.defer(ScanForFoodItems)

----------------------------------------------------------------
-- S7b. NETWORK SNIFFING (Food Signature Discovery)
----------------------------------------------------------------
local function TrySniffFoodSignature()
    -- Carniceria is a BindableEvent — hook its Event signal for one-shot arg capture
    if not REM.Carniceria then return end
    local conn
    conn = REM.Carniceria.Event:Connect(function(...)
        if not CFG.CachedFoodSignature then
            local args = {...}
            CFG.CachedFoodSignature = args
            Log("Food BindableEvent args captured:", unpack(args))
            AddLogEntry("system", "Food remote signature discovered via Event")
        end
        if conn then conn:Disconnect() end
    end)
    table.insert(ST.Connections, conn)
end

TrySniffFoodSignature()

----------------------------------------------------------------
-- S8. CORE COMBAT FUNCTIONS
----------------------------------------------------------------

local function SetGuard(state)
    if not CFG.UseAutoGuard or not REM.Block then return end
    local now = tick()
    if now - ST.LastGuardTime < CFG.GuardCooldown then return end
    if state == ST.GuardActive then return end
    local ok = SafeCall(function() REM.Block:FireServer(state) end)
    if ok then
        ST.GuardActive   = state
        ST.LastGuardTime = now
    end
end

--- IsPlayerDown: States folder first, then heuristics
local function IsPlayerDown(character)
    if not character or not character.Parent then return false end
    local hum = character:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return false end

    -- Phase 1: States folder (authoritative)
    local p = Players:GetPlayerFromCharacter(character)
    if p then
        local states = p:FindFirstChild("States")
        if states then
            local ragdollVal = states:FindFirstChild("isRagdoleao")
            if ragdollVal then return ragdollVal.Value ~= 0 end
        end
    end

    -- Phase 2: RagdollTrigger global (if you stomped via RANDOMS)
    if RANDOMS_RAGDOLL and RANDOMS_RAGDOLL.Value ~= 0 then return true end

    -- Phase 3: Humanoid state heuristics
    local state = hum:GetState()
    if state == Enum.HumanoidStateType.Physics
    or state == Enum.HumanoidStateType.FallingDown
    or state == Enum.HumanoidStateType.PlatformStanding then
        return true
    end
    if hum.PlatformStand then return true end

    -- Phase 4: BoolValue/StringValue children
    for _, child in ipairs(character:GetChildren()) do
        if child:IsA("BoolValue") then
            local n = child.Name:lower()
            if (n:find("ragdoll") or n:find("knocked") or n:find("down") or n:find("stun"))
                and child.Value then
                return true
            end
        elseif child:IsA("StringValue") then
            local v = child.Value:lower()
            if v == "down" or v == "knocked" or v == "ragdoll" then return true end
        end
    end

    -- Phase 5: Attributes
    local DOWNED_ATTRS = {"Ragdolled","KnockedDown","Downed","Stunned","IsDown","Ragdoll","IsRagdoll","KO"}
    for _, attr in ipairs(DOWNED_ATTRS) do
        if character:GetAttribute(attr) == true then return true end
    end

    return false
end

--- IsValid: checks humanoid, FF, whitelist, TeamFilter, PVP state
local function IsValid(model)
    if not model or not model.Parent then return false end
    local h = model:FindFirstChildOfClass("Humanoid")
    local r = model:FindFirstChild("HumanoidRootPart")
    if not h or not r then return false end
    if h.Health <= CFG.MinHealth then return false end
    if not CFG.IgnoreForceField and model:FindFirstChildWhichIsA("ForceField") then
        return false
    end
    local p = Players:GetPlayerFromCharacter(model)
    if p then
        if IsWhitelisted(p.Name) then return false end
        if CFG.AutoWhitelistFriends and IsFriend(p) then return false end

        -- Team filter
        if CFG.TeamFilter ~= "None" then
            local teamName = p.Team and p.Team.Name or "None"
            if CFG.TeamFilter == "StudentsOnly" and teamName ~= "Student" then return false end
            if CFG.TeamFilter == "VIPOnly"      and teamName ~= "VIP"     then return false end
        end

        -- Skip PVP-off targets unless blacklisted
        if not IsBlacklisted(p.Name) then
            local states = p:FindFirstChild("States")
            if states then
                local pvpVal = states:FindFirstChild("hasPvpOn")
                if pvpVal and pvpVal.Value == 0 then return false end
            end
        end
    end
    return true
end

local function RefreshTargets()
    local list      = {}
    local playerChars = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Character then playerChars[p.Character] = p end
    end
    if CFG.TargetPlayers then
        for c, p in pairs(playerChars) do
            if p ~= plr and IsValid(c) then
                list[#list + 1] = c
            end
        end
    end
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
                ST.NPCRegistry[model] = nil
            end
        end
    end
    ST.TargetCache       = list
    ST.TargetsFound      = #list
    ST.LastTargetUpdate  = tick()

    -- Fix 7: rebuild the sorted cache whenever the target list changes.
    -- Loop 1 reads ST.SortedTargetCache instead of re-sorting every tick,
    -- eliminating hundreds of GetPlayerFromCharacter calls per second.
    ST.SortedTargetCacheDirty = true
end

--- ScoreTarget: higher score = higher attack priority
local function ScoreTarget(model, playerPos)
    local hrp = model:FindFirstChild("HumanoidRootPart")
    if not hrp then return -math.huge end
    local dist     = (hrp.Position - playerPos).Magnitude
    local hum      = model:FindFirstChildOfClass("Humanoid")
    local priority = CFG.TargetPriority
    local p        = Players:GetPlayerFromCharacter(model)

    -- Blacklisted targets get a massive bonus
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

    elseif priority == "LowestStamina" then
        -- Stamina lives directly on the Player instance
        local staminaVal = p and p:FindFirstChild("Stamina")
        local stamina    = staminaVal and staminaVal.Value or 100
        return (100 - math.clamp(stamina, 0, 100)) * 0.5 + bonus - dist * 0.001

    elseif priority == "SmallestFirst" then
        local ls      = p and p:FindFirstChild("leaderstats")
        local sizeVal = ls and ls:FindFirstChild("Size")
        local sz      = sizeVal and sizeVal.Value or 999
        return -sz + bonus - dist * 0.001
    end

    return -dist + bonus
end

--- Fire attack remotes at a target, with pre-attack effects and post-attack effects
local function Attack(target)
    if not target or not target.Parent then return end
    local part = target:FindFirstChild(CFG.TargetPart)
        or target:FindFirstChild("UpperTorso")
        or target:FindFirstChild("HumanoidRootPart")
    if not part then return end

    -- Fix 4: skip targets that are currently blocking (server rejects these silently)
    if RANDOMS_BLOCKING and RANDOMS_BLOCKING.Value ~= 0 then return end

    local dmg = ONESHOT_HOOKED and -9e9 or 50

    pcall(function()
        -- Pre-attack: disable controls / no tools on target
        if CFG.UseDisableControlsOnAttack and REM.DisableControlsEffect then
            pcall(function() REM.DisableControlsEffect:FireServer(target) end)
        end
        if CFG.UseNoToolsOnAttack and REM.NoTools then
            pcall(function() REM.NoTools:FireServer(target) end)
        end

        -- Suplex gating
        local suplexReady = not CFG.SmartSuplexGating
        if not suplexReady then
            local chargeObj = plr:FindFirstChild("suplexCharge")
            suplexReady = chargeObj and chargeObj.Value >= CFG.SuplexChargeThreshold
        end

        -- Main attack sequence
        -- Fix 3: ToolHit was being fired twice with mismatched arg shapes.
        -- Correct signature for all attack remotes is (1, target, dmg, part).
        -- PreferWeaponOverFist just controls ordering, not duplication.
        local usedTool = false
        if CFG.PreferWeaponOverFist and CFG.UseToolAttack and REM.ToolHit then
            REM.ToolHit:FireServer(1, target, dmg, part) -- normalized single call
            ST.TotalToolHits += 1
            usedTool = true
        end

        if not usedTool or not CFG.PreferWeaponOverFist then
            if CFG.UsePunch and REM.Punch then
                REM.Punch:FireServer(1, target, dmg, part)
            end
            if CFG.UseSuplex and REM.Suplex and suplexReady then
                REM.Suplex:FireServer(1, target, dmg, part)
            end
            if CFG.UseHeavyHit and REM.HeavyHit then
                REM.HeavyHit:FireServer(1, target, dmg, part)
            end
        end

        -- Fix 3: non-prefer ToolHit also normalized to full signature
        if not CFG.PreferWeaponOverFist and CFG.UseToolAttack and REM.ToolHit then
            REM.ToolHit:FireServer(1, target, dmg, part)
            ST.TotalToolHits += 1
        end

        -- Animation cancel
        if CFG.UseAnimCancel and REM.StopAnim then
            task.delay(CFG.AnimCancelDelay, function()
                pcall(function() REM.StopAnim:FireServer() end)
            end)
        end

        -- Post-attack effects
        if CFG.UseShakeOnHit and REM.ShakeScreen then
            pcall(function() REM.ShakeScreen:FireServer(target) end)
        end
        if CFG.UseRedScreenOnHit and REM.RedScreen then
            pcall(function() REM.RedScreen:FireServer(target) end)
        end
        if CFG.UseImpactFramesOnHit and REM.ImpactFrames then
            pcall(function() REM.ImpactFrames:FireServer(target) end)
        end
    end)

    ST.TotalAttacks += 1
end

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
                    ST.TotalStomps  += 1
                    ST.LastStompTime = now
                    AddLogEntry("kill", "Stomped " .. p.Name)
                end
                return
            end
        end
    end
end

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
                ST.TotalStuns  += 1
                ST.LastStunTime = now
                return
            end
        end
    end
end

----------------------------------------------------------------
-- S9. SURVIVAL SYSTEMS
----------------------------------------------------------------

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
        ST.TotalHeals  += 1
        ST.LastHealTime = now
        AddLogEntry("heal", string.format("Auto-heal at %d%% HP", math.floor(hpPct)))
    end
end

--- TryBuyFood: Carniceria is a BindableEvent — use .Fire()
local function TryBuyFood()
    if not CFG.UseAutoBuyFood or not REM.Carniceria then return end
    if not humanoid or humanoid.Health <= 0 then return end
    local now = tick()
    if now - ST.LastFoodBuy < CFG.BuyFoodCooldown then return end
    local hpPct = (humanoid.Health / humanoid.MaxHealth) * 100
    if hpPct > CFG.HealThreshold then return end

    local healthBefore = humanoid.Health

    -- Phase 1: Cached signature
    if CFG.CachedFoodSignature then
        pcall(function()
            REM.Carniceria:Fire(table.unpack(CFG.CachedFoodSignature))
        end)
        ST.LastFoodBuy  = now
        ST.TotalFoodBuys += 1
        task.delay(0.5, function()
            if humanoid and humanoid.Health > healthBefore then
                ST.FoodSigFails = 0
                AddLogEntry("heal", "Food purchased (cached sig)")
            else
                ST.FoodSigFails += 1
                if ST.FoodSigFails >= 3 then
                    CFG.CachedFoodSignature = nil
                    ST.FoodProbeIndex       = 0
                    ST.FoodSigFails         = 0
                    AddLogEntry("error", "Food sig invalidated, re-probing")
                end
            end
        end)
        return
    end

    -- Phase 2: Tiered probing (one attempt per cycle)
    local foods  = ScanForFoodItems()
    local probes = {
        function() REM.Carniceria:Fire()        end,
        function() REM.Carniceria:Fire(true)    end,
        function() REM.Carniceria:Fire(1)       end,
        function() REM.Carniceria:Fire("Buy")   end,
        function() REM.Carniceria:Fire("Comprar") end,
    }
    for _, fname in ipairs(foods) do
        local f1 = fname
        table.insert(probes, function() REM.Carniceria:Fire(f1) end)
        table.insert(probes, function() REM.Carniceria:Fire("Buy", f1) end)
    end

    ST.FoodProbeIndex += 1
    if ST.FoodProbeIndex > #probes then ST.FoodProbeIndex = 1 end

    local idx    = ST.FoodProbeIndex
    local probeOk = pcall(probes[idx])
    ST.LastFoodBuy   = now
    ST.TotalFoodBuys += 1

    if probeOk then
        task.delay(0.5, function()
            if humanoid and humanoid.Health > healthBefore then
                local sig = nil
                if idx == 1 then sig = {}
                elseif idx == 2 then sig = {true}
                elseif idx == 3 then sig = {1}
                elseif idx == 4 then sig = {"Buy"}
                elseif idx == 5 then sig = {"Comprar"}
                else
                    local adj = idx - 5
                    local fi  = math.ceil(adj / 2)
                    if fi <= #foods then
                        if adj % 2 == 1 then sig = {foods[fi]}
                        else sig = {"Buy", foods[fi]} end
                    end
                end
                if sig then
                    CFG.CachedFoodSignature = sig
                    ST.FoodSigFails         = 0
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

local function TryPickupTools()
    if not CFG.UseAutoPickupTools then return end
    local now = tick()
    if now - ST.LastToolPickup < CFG.ToolPickupCooldown then return end
    if not rootPart or not rootPart.Parent then return end
    local pos     = rootPart.Position
    local backpack = plr:FindFirstChild("Backpack")
    if not backpack then return end

    local candidates = {}
    for obj, data in pairs(ST.ToolRegistry) do
        if obj and obj.Parent and data.part and data.part.Parent then
            if data.blacklistedUntil > 0 and now < data.blacklistedUntil then
                -- skip blacklisted
            elseif obj:FindFirstAncestorOfClass("Backpack") then
                DeregisterTool(obj)
            else
                local dist = (pos - data.part.Position).Magnitude
                if dist <= CFG.ToolPickupRange then
                    table.insert(candidates, { obj = obj, data = data, dist = dist })
                end
            end
        else
            ST.ToolRegistry[obj] = nil
        end
    end

    if #candidates == 0 then return end
    table.sort(candidates, function(a, b) return a.dist < b.dist end)

    -- Fix 8: each pickup attempt runs in its own task.spawn so the blocking
    -- task.wait() calls inside the tier checks no longer stall Loop 3.
    local processed = 0
    for _, cand in ipairs(candidates) do
        if processed >= 3 then break end
        processed += 1

        local obj  = cand.obj
        local data = cand.data

        task.spawn(function()
            local pickedUp = false

            -- Tier 1: Direct parent
            pcall(function()
                if obj:IsA("Tool") then
                    obj.Parent = backpack
                    pickedUp   = true
                end
            end)
            if not pickedUp then
                task.wait(0.1)
                if obj.Parent == backpack then pickedUp = true end
            end

            -- Tier 2: Pickup remote
            if not pickedUp and REM.PickupTool then
                pcall(function() REM.PickupTool:FireServer(obj) end)
                task.wait(0.1)
                if obj.Parent == backpack then pickedUp = true end
                if not pickedUp then
                    pcall(function() REM.PickupTool:FireServer(obj.Name) end)
                    task.wait(0.1)
                    if obj.Parent == backpack then pickedUp = true end
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

            if pickedUp then
                DeregisterTool(obj)
                ST.TotalPickups += 1
                Notify("Picked up: " .. data.name, "success", 2)
                AddLogEntry("pickup", "Picked up " .. data.name)
            else
                data.failCount += 1
                if data.failCount >= 3 then
                    data.blacklistedUntil = tick() + 30
                    data.failCount        = 0
                end
            end
        end)
    end

    ST.LastToolPickup = now
end

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
                pcall(function() REM.Carry:FireServer(p.Character) end)
                task.wait(CFG.CarryDuration)
                pcall(function()
                    -- Throw is a RemoteFunction
                    pcall(function()
                        REM.Throw:InvokeServer(p.Character, rootPart.CFrame.LookVector)
                    end)
                end)
                ST.TotalThrows  += 1
                ST.LastCarryTime = tick()
                ST.IsCarrying    = false
                AddLogEntry("system", "Threw " .. p.Name)
                return
            end
        end
    end
end

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
        ST.PVPEnabled   = false
        ST.LastPVPToggle = now
        AddLogEntry("system", "PVP OFF (low HP)")
    elseif hpPct >= CFG.PVPOnThreshold and not ST.PVPEnabled then
        pcall(function()
            REM.PVPToggle:FireServer(true)
            REM.PVPToggle:FireServer("On")
        end)
        ST.PVPEnabled   = true
        ST.LastPVPToggle = now
        AddLogEntry("system", "PVP ON")
    end
end

----------------------------------------------------------------
-- S11. DPS TRACKER
----------------------------------------------------------------
local function RecordDamage(delta)
    if delta <= 0 then return end
    table.insert(ST.DPSHistory, { time = tick(), delta = delta })
    -- Fix 9: cap history so it never grows unbounded between CalculateDPS() calls
    if #ST.DPSHistory > 500 then
        table.remove(ST.DPSHistory, 1)
    end
end

local function CalculateDPS()
    local now     = tick()
    local window  = CFG.DPSTrackingWindow
    local total   = 0
    local newHist = {}
    for _, entry in ipairs(ST.DPSHistory) do
        if now - entry.time <= window then
            total += entry.delta
            table.insert(newHist, entry)
        end
    end
    ST.DPSHistory = newHist
    ST.CurrentDPS = total / math.max(window, 0.1)
    return ST.CurrentDPS
end

----------------------------------------------------------------
-- S12. KILL ALL
----------------------------------------------------------------
local function RunKillAll()
    if not HAS_ATTACK then
        Notify("No attack remotes found", "error")
        return
    end
    ST.KillAllRunning = true
    ST.CurrentMode    = "KillAll"
    Notify("Kill All engaged" .. (ONESHOT_HOOKED and " [ONE-SHOT]" or ""), "warning", 2)
    AddLogEntry("system", "Kill All STARTED")

    while CFG.KillAllActive and CFG.Enabled and ST.Running do
        GetChar()
        if not rootPart or not rootPart.Parent then
            ST.KillAllTarget = "Respawning..."
            task.wait(1)
        else
            local targets = {}
            local myPos   = rootPart.Position
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= plr and p.Character then
                    if not IsWhitelisted(p.Name) then
                        if not (CFG.AutoWhitelistFriends and IsFriend(p)) then
                            local h = p.Character:FindFirstChildOfClass("Humanoid")
                            local r = p.Character:FindFirstChild("HumanoidRootPart")
                            if h and r and h.Health > 0 then
                                table.insert(targets, {
                                    player = p,
                                    dist   = (myPos - r.Position).Magnitude,
                                })
                            end
                        end
                    end
                end
            end

            if #targets == 0 then
                ST.KillAllTarget   = "No targets"
                ST.KillAllProgress = "0/0"
                task.wait(1.5)
            else
                table.sort(targets, function(a, b) return a.dist < b.dist end)

                for i, entry in ipairs(targets) do
                    if not CFG.KillAllActive or not CFG.Enabled or not ST.Running then break end
                    local target = entry.player
                    local tChar  = target.Character
                    if not tChar then
                        -- skip
                    else
                        local tRoot = tChar:FindFirstChild("HumanoidRootPart")
                        local tHum  = tChar:FindFirstChildOfClass("Humanoid")
                        if tRoot and tHum and tHum.Health > 0 then
                            ST.KillAllTarget   = target.Name
                            ST.KillAllProgress = i .. "/" .. #targets

                            -- Teleport with TPBACK avoidance
                            GetChar()
                            if rootPart and rootPart.Parent then
                                SafeTeleport(tRoot.CFrame * CFrame.new(0, 0, 3))
                                InvalidateNearbyCache()
                            end
                            task.wait(CFG.KillAllTeleportDelay)

                            -- Reteleport if drifted
                            GetChar()
                            if rootPart and rootPart.Parent and tRoot and tRoot.Parent then
                                local postDist = (rootPart.Position - tRoot.Position).Magnitude
                                if postDist > CFG.KillAllReteleportDist then
                                    for _ = 1, CFG.KillAllRetries do
                                        SafeTeleport(tRoot.CFrame * CFrame.new(0, 0, 3))
                                        task.wait(0.1)
                                        if (rootPart.Position - tRoot.Position).Magnitude
                                           <= CFG.KillAllReteleportDist then
                                            break
                                        end
                                    end
                                end
                            end

                            -- Attack loop
                            local startTime = tick()
                            local attacking = true
                            while attacking and CFG.KillAllActive and CFG.Enabled and ST.Running do
                                tChar = target.Character
                                if not tChar then attacking = false
                                else
                                    tHum  = tChar:FindFirstChildOfClass("Humanoid")
                                    tRoot = tChar:FindFirstChild("HumanoidRootPart")
                                    if not tHum or tHum.Health <= 0 or not tRoot then
                                        attacking = false
                                    elseif tick() - startTime > CFG.KillAllTimeout then
                                        attacking = false
                                    else
                                        GetChar()
                                        if not rootPart or not rootPart.Parent then
                                            attacking = false
                                        else
                                            local dist = (rootPart.Position - tRoot.Position).Magnitude
                                            if dist > CFG.KillAllReteleportDist then
                                                SafeTeleport(tRoot.CFrame * CFrame.new(0, 0, 3))
                                                InvalidateNearbyCache()
                                                task.wait(0.05)
                                            end
                                            Attack(tChar)
                                            if CFG.UseAutoStomp and REM.Stomp and IsPlayerDown(tChar) then
                                                pcall(function() REM.Stomp:FireServer() end)
                                                ST.TotalStomps += 1
                                            end
                                            task.wait(math.max(1 / math.max(CFG.AttacksPerSecond, 1), 0.01))
                                        end
                                    end
                                end
                            end

                            -- Kill check
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
                    end
                end

                if CFG.KillAllActive and CFG.Enabled and ST.Running then
                    ST.KillAllTarget   = "Scanning..."
                    ST.KillAllProgress = ""
                    task.wait(1.5)
                end
            end
        end
    end

    ST.KillAllRunning  = false
    ST.KillAllTarget   = ""
    ST.KillAllProgress = ""
    ST.CurrentMode     = nil
    Notify("Kill All disengaged", "info", 2)
    AddLogEntry("system", "Kill All STOPPED")
end

----------------------------------------------------------------
-- S13. KILL AURA VISUALIZATION
----------------------------------------------------------------
local function UpdateAuraRing()
    if CFG.KillAuraVisualization and CFG.Enabled then
        if not ST.AuraRing then
            local ring = Instance.new("Part")
            ring.Name        = "MAPAuraRing"
            ring.Anchored    = true
            ring.CanCollide  = false
            ring.Shape       = Enum.PartType.Cylinder
            ring.Material    = Enum.Material.Neon
            ring.Color       = CLR.accent
            ring.Transparency= 0.85
            ring.Size        = Vector3.new(0.1, CFG.AttackRange * 2, CFG.AttackRange * 2)
            ring.CFrame      = CFrame.new(0, -1000, 0)
            ring.Parent      = workspace
            ST.AuraRing      = ring
        end
        if not ST.AuraConn then
            ST.AuraConn = Conn(RunService.RenderStepped, function()
                if ST.AuraRing and rootPart and rootPart.Parent then
                    local cf = rootPart.CFrame
                    ST.AuraRing.CFrame = CFrame.new(cf.Position)
                        * CFrame.Angles(0, 0, math.rad(90))
                    ST.AuraRing.Size = Vector3.new(0.1, CFG.AttackRange * 2, CFG.AttackRange * 2)
                end
            end)
        end
    else
        if ST.AuraRing then ST.AuraRing:Destroy(); ST.AuraRing = nil end
        if ST.AuraConn  then ST.AuraConn:Disconnect(); ST.AuraConn = nil end
    end
end

----------------------------------------------------------------
-- S14. ESP OVERLAY
----------------------------------------------------------------
local _espStatUpdate = 0

local function CreateESP(model)
    if not CFG.ESPEnabled then return end
    if ST.ESPPool[model] then return end
    local hrp = model:FindFirstChild("HumanoidRootPart")
    local hum = model:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum then return end
    if #ST.ESPPool >= 5 then return end

    local bb = Instance.new("BillboardGui")
    bb.Name         = "MAPESP"
    bb.Adornee      = hrp
    bb.Size         = UDim2.new(0, 130, 0, CFG.ESPShowStats and 60 or 44)
    bb.StudsOffset  = Vector3.new(0, 3, 0)
    bb.AlwaysOnTop  = true

    local nameL = Instance.new("TextLabel")
    nameL.Size                  = UDim2.new(1, 0, 0, 16)
    nameL.BackgroundTransparency= 1
    nameL.Text                  = model.Name
    nameL.TextColor3            = CLR.text
    nameL.TextSize              = 11
    nameL.Font                  = Enum.Font.GothamBold
    nameL.Parent                = bb

    local barBg = Instance.new("Frame")
    barBg.Size                  = UDim2.new(1, -10, 0, 5)
    barBg.Position              = UDim2.new(0, 5, 0, 18)
    barBg.BackgroundColor3      = Color3.fromRGB(40, 40, 40)
    barBg.BorderSizePixel       = 0
    barBg.Parent                = bb
    local barCorner = Instance.new("UICorner")
    barCorner.CornerRadius      = UDim.new(0, 2)
    barCorner.Parent            = barBg

    local barFill = Instance.new("Frame")
    barFill.Size                = UDim2.new(math.clamp(hum.Health / hum.MaxHealth, 0, 1), 0, 1, 0)
    barFill.BackgroundColor3    = CLR.green
    barFill.BorderSizePixel     = 0
    barFill.Parent              = barBg
    local fillCorner = Instance.new("UICorner")
    fillCorner.CornerRadius     = UDim.new(0, 2)
    fillCorner.Parent           = barFill

    local distL = Instance.new("TextLabel")
    distL.Size                  = UDim2.new(1, 0, 0, 12)
    distL.Position              = UDim2.new(0, 0, 0, 26)
    distL.BackgroundTransparency= 1
    distL.Text                  = "0m"
    distL.TextColor3            = CLR.textDim
    distL.TextSize              = 9
    distL.Font                  = Enum.Font.Gotham
    distL.Parent                = bb

    -- Stats row (Money / Level / Size)
    local statsL = Instance.new("TextLabel")
    statsL.Size                  = UDim2.new(1, 0, 0, 12)
    statsL.Position              = UDim2.new(0, 0, 0, 40)
    statsL.BackgroundTransparency= 1
    statsL.Text                  = ""
    statsL.TextColor3            = CLR.yellow
    statsL.TextSize              = 8
    statsL.Font                  = Enum.Font.Gotham
    statsL.Visible               = CFG.ESPShowStats
    statsL.Parent                = bb

    bb.Parent = game:GetService("CoreGui")

    ST.ESPPool[model] = {
        billboard = bb,
        barFill   = barFill,
        distLabel = distL,
        statsLabel= statsL,
        humanoid  = hum,
        hrp       = hrp,
    }
end

local function RemoveESP(model)
    local data = ST.ESPPool[model]
    if data then
        if data.billboard then data.billboard:Destroy() end
        ST.ESPPool[model] = nil
    end
end

local function ClearAllESP()
    for model, _ in pairs(ST.ESPPool) do RemoveESP(model) end
end

-- Fix 2: _espStatUpdate was referenced but never declared - caused nil arithmetic error every 0.15s
local _espStatUpdate = 0

local function UpdateESP()
    if not CFG.ESPEnabled then ClearAllESP(); return end
    local now = tick()
    local doStats = CFG.ESPShowStats and (now - _espStatUpdate > 0.5)
    if doStats then _espStatUpdate = now end

    for model, data in pairs(ST.ESPPool) do
        if not model or not model.Parent or not data.hrp or not data.hrp.Parent then
            RemoveESP(model)
        else
            local hum = data.humanoid
            if hum and hum.Parent then
                local ratio = math.clamp(hum.Health / hum.MaxHealth, 0, 1)
                data.barFill.Size = UDim2.new(ratio, 0, 1, 0)
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
            -- Stats update (capped to 0.5s)
            if doStats and data.statsLabel then
                data.statsLabel.Visible = CFG.ESPShowStats
                if CFG.ESPShowStats then
                    local p  = Players:GetPlayerFromCharacter(model)
                    local ls = p and p:FindFirstChild("leaderstats")
                    if ls then
                        local money = ls:FindFirstChild("Money")
                        local level = ls:FindFirstChild("Level")
                        local size  = ls:FindFirstChild("Size")
                        local parts = {}
                        if money then table.insert(parts, "$" .. tostring(money.Value)) end
                        if level then table.insert(parts, "Lv" .. tostring(level.Value)) end
                        if size  then table.insert(parts, "Sz" .. tostring(math.floor(size.Value * 10) / 10)) end
                        data.statsLabel.Text = table.concat(parts, "  ")
                    end
                end
            end
        end
    end
end

----------------------------------------------------------------
-- S19. ENVIRONMENTAL SYSTEMS
----------------------------------------------------------------

--- ATM Farmer — attacks workspace.Damageables ATMs
local _lastATM = 0
local function TryATMFarmer()
    if not CFG.UseATMFarmer then return end
    if not HAS_ATTACK then return end
    local now = tick()
    if now - _lastATM < CFG.ATMFarmerCooldown then return end
    if not rootPart or not rootPart.Parent then return end

    -- Find nearest live ATM
    local nearest, nearestMesh, nearestDist = nil, nil, math.huge
    for model, mesh in pairs(ST.ATMRegistry) do
        if model and model.Parent and mesh and mesh.Parent then
            local dist = (rootPart.Position - mesh.Position).Magnitude
            if dist < nearestDist then
                nearestDist  = dist
                nearest      = model
                nearestMesh  = mesh
            end
        else
            ST.ATMRegistry[model] = nil
        end
    end

    if not nearest or not nearestMesh then return end

    -- Teleport to ATM
    rootPart.CFrame = CFrame.new(nearestMesh.Position + Vector3.new(3, 0, 0))
    task.wait(0.05)

    local dmg = ONESHOT_HOOKED and -9e9 or 50
    pcall(function()
        if REM.Punch   then REM.Punch:FireServer(1, nearestMesh, dmg, nearestMesh)   end
        if REM.HeavyHit then REM.HeavyHit:FireServer(1, nearestMesh, dmg, nearestMesh) end
        if REM.ToolHit then REM.ToolHit:FireServer(nearestMesh, nearestMesh)          end
    end)

    _lastATM = now
end

--- Shop Auto-Buy — fires ProximityPrompts on shop buttons
local function TryBuyShopItems()
    if not CFG.UseAutoShopBuy then return end
    local cache = ScanShopButtons()
    for itemName, data in pairs(cache) do
        if CFG.ShopBuyList[itemName] and data.obj and data.obj.Parent then
            pcall(function()
                if data.prompt:IsA("ProximityPrompt") and CAN_FIRE_PROMPT then
                    fireproximityprompt(data.prompt)
                elseif data.prompt:IsA("ClickDetector") and CAN_FIRE_CLICK then
                    fireclickdetector(data.prompt)
                end
            end)
        end
    end
end

--- Throwables Auto-Grab — uses Throw RemoteFunction
local _lastThrowable = 0
local function TryAutoThrowable()
    if not CFG.UseAutoThrowable then return end
    if not REM.Throw then return end
    local now = tick()
    if now - _lastThrowable < CFG.ThrowableCooldown then return end
    if not rootPart or not rootPart.Parent then return end

    local throwFolder = workspace:FindFirstChild("Throwables")
    if not throwFolder then return end

    local nearest, nearestDist = nil, CFG.ThrowableRange
    for _, obj in ipairs(throwFolder:GetChildren()) do
        local part = nil
        if obj:IsA("BasePart") or obj:IsA("UnionOperation") or obj:IsA("MeshPart") then
            part = obj
        elseif obj:IsA("Model") then
            part = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")
        end
        if part then
            local dist = (rootPart.Position - part.Position).Magnitude
            if dist < nearestDist then
                nearestDist = dist
                nearest     = obj
            end
        end
    end

    if not nearest then return end

    -- Find best target
    local bestTarget = nil
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= plr and p.Character then
            local h = p.Character:FindFirstChildOfClass("Humanoid")
            if h and h.Health > 0 then
                bestTarget = p.Character
                break
            end
        end
    end

    if not bestTarget then return end

    -- Teleport near throwable
    local throwPart = nearest:IsA("Model")
        and (nearest.PrimaryPart or nearest:FindFirstChildWhichIsA("BasePart"))
        or nearest
    if throwPart then
        rootPart.CFrame = CFrame.new(throwPart.Position + Vector3.new(3, 0, 0))
        task.wait(0.1)
    end

    -- Invoke with timeout guard
    local done = false
    task.spawn(function()
        pcall(function() REM.Throw:InvokeServer(nearest, bestTarget) end)
        done = true
    end)
    local t0 = tick()
    while not done and tick() - t0 < 3 do task.wait(0.1) end

    _lastThrowable = now
    ST.TotalThrows += 1
    AddLogEntry("system", "Throwable: " .. nearest.Name)
end

--- Auto Spin Wheel
local function TryAutoSpin()
    if not CFG.UseAutoSpin then return end
    if not REM.IsResetTime or not REM.Spin then return end
    local now = tick()
    if now - ST.LastSpinTime < CFG.AutoSpinCooldown then return end
    ST.LastSpinTime = now

    -- Check if it's time
    local isReset = false
    pcall(function()
        local ok, result = pcall(function() return REM.IsResetTime:InvokeServer() end)
        if ok then isReset = result end
    end)

    if not isReset then return end

    -- Spin with timeout
    local done = false
    task.spawn(function()
        local ok, reward = pcall(function() return REM.Spin:InvokeServer() end)
        if ok and reward then
            local str = tostring(reward)
            ST.LastSpinReward = str
            Notify("Spin reward: " .. str, "success", 3)
            AddLogEntry("system", "Spin: " .. str)
        end
        done = true
    end)
    local t0 = tick()
    while not done and tick() - t0 < 5 do task.wait(0.1) end
end

----------------------------------------------------------------
-- S20. QUEST FARMER
----------------------------------------------------------------
local QUEST_MAPPINGS = {
    ["Throw things"]                      = function(done) if CFG.UseQuestFarmer then CFG.UseAutoThrowable   = not done end end,
    ["Buy weapons"]                       = function(done) if CFG.UseQuestFarmer then CFG.UseAutoShopBuy     = not done end end,
    ["Eat tortas"]                        = function(done) if CFG.UseQuestFarmer then CFG.UseAutoBuyFood     = not done end end,
    ["Destroy ATMs"]                      = function(done) if CFG.UseQuestFarmer then CFG.UseATMFarmer       = not done end end,
    ["Pick random weapons from the floor"]= function(done) if CFG.UseQuestFarmer then CFG.UseAutoPickupTools = not done end end,
}
local XMAS_QUEST_MAPPINGS = {
    ["Destroy ATMs"]                      = function(done) if CFG.UseQuestFarmer then CFG.UseATMFarmer       = not done end end,
    ["Pick random weapons from the floor"]= function(done) if CFG.UseQuestFarmer then CFG.UseAutoPickupTools = not done end end,
}

local function IsQuestDone(strValue)
    local v = strValue:lower()
    if v:find("done") or v:find("completo") or v:find("complete") then return true end
    local cur, max = v:match("(%d+)/(%d+)")
    if cur and max then return tonumber(cur) >= tonumber(max) end
    return false
end

local function RunQuestFarmer()
    if not CFG.UseQuestFarmer then return end
    local questFolder = plr:FindFirstChild("Quests")
    if questFolder then
        for _, sv in ipairs(questFolder:GetChildren()) do
            if sv:IsA("StringValue") then
                local mapper = QUEST_MAPPINGS[sv.Name]
                if mapper then mapper(IsQuestDone(sv.Value)) end
            end
        end
    end
    local xmasFolder = plr:FindFirstChild("ChristmasQuests")
    if xmasFolder then
        for _, sv in ipairs(xmasFolder:GetChildren()) do
            if sv:IsA("StringValue") then
                local mapper = XMAS_QUEST_MAPPINGS[sv.Name]
                if mapper then mapper(IsQuestDone(sv.Value)) end
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
    sg.Name            = "MassAttackPro"
    sg.ResetOnSpawn    = false
    sg.ZIndexBehavior  = Enum.ZIndexBehavior.Sibling
    sg.DisplayOrder    = 999
    ParentGui(sg)

    -- Helpers
    local function Corner(p, r)
        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, r or 6)
        c.Parent = p
    end

    local function Stroke(p, col, t)
        local s = Instance.new("UIStroke")
        s.Color            = col or CLR.border
        s.Thickness        = t   or 1
        s.ApplyStrokeMode  = Enum.ApplyStrokeMode.Border
        s.Parent           = p
    end

    local function Hover(el, normal, hovered)
        el.MouseEnter:Connect(function()
            TweenService:Create(el, TWEEN_FAST, {BackgroundColor3 = hovered}):Play()
        end)
        el.MouseLeave:Connect(function()
            TweenService:Create(el, TWEEN_FAST, {BackgroundColor3 = normal}):Play()
        end)
    end

    -- ==========================================
    -- NOTIFICATION SYSTEM
    -- ==========================================
    local notifContainer = Instance.new("Frame")
    notifContainer.Name                  = "Notifications"
    notifContainer.Size                  = UDim2.new(0, 260, 1, -20)
    notifContainer.Position              = UDim2.new(1, -270, 0, 10)
    notifContainer.BackgroundTransparency= 1
    notifContainer.Parent                = sg

    local notifLayout = Instance.new("UIListLayout")
    notifLayout.SortOrder             = Enum.SortOrder.LayoutOrder
    notifLayout.Padding               = UDim.new(0, 5)
    notifLayout.VerticalAlignment     = Enum.VerticalAlignment.Top
    notifLayout.HorizontalAlignment   = Enum.HorizontalAlignment.Right
    notifLayout.Parent                = notifContainer

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

            while #ST.ActiveNotifs >= 5 do
                local oldest = table.remove(ST.ActiveNotifs, 1)
                if oldest and oldest.Parent then oldest:Destroy() end
            end

            local frame = Instance.new("Frame")
            frame.Size                  = UDim2.new(1, 0, 0, 36)
            frame.BackgroundColor3      = col:Lerp(Color3.fromRGB(10, 10, 18), 0.82)
            frame.BackgroundTransparency= 1
            frame.BorderSizePixel       = 0
            frame.LayoutOrder           = _notifOrder
            frame.ClipsDescendants      = true
            frame.Parent                = notifContainer
            Corner(frame, 6)
            Stroke(frame, col, 1)

            table.insert(ST.ActiveNotifs, frame)

            local icon = Instance.new("TextLabel")
            icon.Size                  = UDim2.new(0, 24, 1, 0)
            icon.Position              = UDim2.new(0, 6, 0, 0)
            icon.BackgroundTransparency= 1
            icon.Text                  = nType == "success" and "✓"
                                      or nType == "error"   and "✗"
                                      or nType == "warning" and "⚠"
                                      or "ℹ"
            icon.TextColor3            = col
            icon.TextSize              = 13
            icon.Font                  = Enum.Font.GothamBold
            icon.Parent                = frame

            local label = Instance.new("TextLabel")
            label.Size                  = UDim2.new(1, -36, 1, 0)
            label.Position              = UDim2.new(0, 30, 0, 0)
            label.BackgroundTransparency= 1
            label.Text                  = msgText
            label.TextColor3            = CLR.text
            label.TextSize              = 11
            label.Font                  = Enum.Font.Gotham
            label.TextXAlignment        = Enum.TextXAlignment.Left
            label.TextTruncate          = Enum.TextTruncate.AtEnd
            label.Parent                = frame

            TweenService:Create(frame, TweenInfo.new(0.25, Enum.EasingStyle.Quint),
                {BackgroundTransparency = 0.1}):Play()

            task.delay(duration, function()
                if frame and frame.Parent then
                    TweenService:Create(frame, TweenInfo.new(0.35, Enum.EasingStyle.Quint),
                        {BackgroundTransparency = 1}):Play()
                    task.wait(0.35)
                    if frame and frame.Parent then
                        frame:Destroy()
                        for i, n in ipairs(ST.ActiveNotifs) do
                            if n == frame then table.remove(ST.ActiveNotifs, i); break end
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
        ["Script Enabled"]           = "Master toggle for all combat systems.",
        ["Attack All (AoE)"]         = "Hit all valid targets each cycle instead of just one.",
        ["Target Players"]           = "Include other players as valid targets.",
        ["Target NPCs"]              = "Include non-player humanoids as valid targets.",
        ["Animation Cancel"]         = "Interrupts attack recovery frames to boost effective DPS.",
        ["Auto Stomp"]               = "Automatically stomp ragdolled players within range.",
        ["Auto Stun"]                = "Automatically attempt to stun standing enemies.",
        ["Auto Guard"]               = "Automatically block when enemies are nearby.",
        ["Drop Guard to Attack"]     = "Briefly disable guard to land attacks, then re-enable.",
        ["Ignore ForceField"]        = "Attack targets even if they have a ForceField.",
        ["Smart PVP Toggle"]         = "Auto-enables PVP at high HP, disables at low HP.",
        ["Auto Heal"]                = "Fire heal remote when HP drops below threshold.",
        ["Auto Buy Food"]            = "Attempt to buy food from the Carniceria BindableEvent.",
        ["Auto Pickup Weapons"]      = "Automatically pick up nearby dropped weapons and world items.",
        ["Auto Carry+Throw"]         = "Carry and throw ragdolled players.",
        ["Auto Throwables"]          = "Auto-grab and throw world Throwables at enemies.",
        ["Crouch Spam"]              = "Rapidly toggle crouch for movement disruption.",
        ["Kill All (TP & Kill)"]     = "Teleport to and attack every player on the server.",
        ["Kill Aura Visualization"]  = "Show a ring around you indicating attack range.",
        ["ESP Overlay"]              = "Show name, health, and distance over active targets.",
        ["ESP Show Stats"]           = "Show Money / Level / Size under ESP health bar.",
        ["Anti-AFK"]                 = "Prevent being kicked for idling.",
        ["Auto Respawn"]             = "Automatically respawn and resume combat on death.",
        ["Debug Logging"]            = "Print debug information to the executor console.",
        ["Prefer Weapon Over Fist"]  = "Use equipped tool attacks before fist attacks.",
        ["Smart Suplex Gating"]      = "Only suplex when suplexCharge meets the threshold.",
        ["Disable Controls on Hit"]  = "Fires DisableControls remote at target before attack.",
        ["No Tools on Hit"]          = "Fires NoTools remote at target before attack.",
        ["Shake on Hit"]             = "Fires ShakeScreenEvent at target after each hit.",
        ["Red Screen on Hit"]        = "Fires RedScreenEvent at target after each hit.",
        ["Impact Frames on Hit"]     = "Fires ImpactFramesEvent at target after each hit.",
        ["ATM Farmer"]               = "Teleports to and destroys ATMs in workspace.Damageables.",
        ["Shop Auto-Buy"]            = "Fires ProximityPrompts on shop buy buttons.",
        ["Auto Spin Wheel"]          = "Auto-spins the SpinWheel when IsResetTime returns true.",
        ["Quest Farmer"]             = "Reads Quests/ChristmasQuests and auto-enables matching systems.",
        ["TP-Back Zone Avoidance"]   = "Avoids TELEPORTPLAYERSBACK zones when Kill All teleports.",
        ["Remote Aura"]              = "Fires attacks at ALL players simultaneously, no proximity needed.",
        ["Auto-Whitelist Friends"]   = "Automatically skip players you are friends with.",
    }

    local tooltipFrame = Instance.new("Frame")
    tooltipFrame.Name                  = "Tooltip"
    tooltipFrame.Size                  = UDim2.new(0, 210, 0, 30)
    tooltipFrame.BackgroundColor3      = CLR.tooltipBg
    tooltipFrame.BackgroundTransparency= 0.05
    tooltipFrame.BorderSizePixel       = 0
    tooltipFrame.Visible               = false
    tooltipFrame.ZIndex                = 100
    tooltipFrame.Parent                = sg
    Corner(tooltipFrame, 6)
    Stroke(tooltipFrame, CLR.accent, 1)

    local tooltipLabel = Instance.new("TextLabel")
    tooltipLabel.Size                  = UDim2.new(1, -12, 1, -6)
    tooltipLabel.Position              = UDim2.new(0, 6, 0, 3)
    tooltipLabel.BackgroundTransparency= 1
    tooltipLabel.Text                  = ""
    tooltipLabel.TextColor3            = CLR.text
    tooltipLabel.TextSize              = 10
    tooltipLabel.Font                  = Enum.Font.Gotham
    tooltipLabel.TextWrapped           = true
    tooltipLabel.TextXAlignment        = Enum.TextXAlignment.Left
    tooltipLabel.TextYAlignment        = Enum.TextYAlignment.Top
    tooltipLabel.ZIndex                = 101
    tooltipLabel.Parent                = tooltipFrame

    local function ShowTooltip(label, guiObj)
        local tip = TOOLTIPS[label]
        if not tip then return end
        tooltipLabel.Text     = tip
        local lines = math.ceil(#tip / 32)
        tooltipFrame.Size     = UDim2.new(0, 210, 0, math.max(28, lines * 14 + 8))
        local absPos  = guiObj.AbsolutePosition
        local absSize = guiObj.AbsoluteSize
        tooltipFrame.Position = UDim2.new(0, absPos.X, 0, absPos.Y + absSize.Y + 3)
        tooltipFrame.Visible  = true
    end

    local function HideTooltip()
        tooltipFrame.Visible = false
    end

    -- ==========================================
    -- MAIN FRAME
    -- ==========================================
    local FULL_W = 385
    local FULL_H = 670

    local main = Instance.new("Frame")
    main.Name              = "Main"
    main.Size              = UDim2.new(0, FULL_W * 0.95, 0, FULL_H * 0.95)
    main.Position          = UDim2.new(0.5, -FULL_W / 2, 0.5, -FULL_H / 2)
    main.BackgroundColor3  = CLR.bg
    main.BackgroundTransparency = 1
    main.BorderSizePixel   = 0
    main.ClipsDescendants  = true
    main.Active            = true
    main.Parent            = sg
    Corner(main, 10)
    Stroke(main, CLR.border, 1)

    -- Shadow
    local sh = Instance.new("ImageLabel")
    sh.Size                  = UDim2.new(1, 50, 1, 50)
    sh.Position              = UDim2.new(0, -25, 0, -25)
    sh.BackgroundTransparency= 1
    sh.Image                 = "rbxassetid://6015897843"
    sh.ImageColor3           = CLR.shadow
    sh.ImageTransparency     = 0.45
    sh.ScaleType             = Enum.ScaleType.Slice
    sh.SliceCenter           = Rect.new(49, 49, 450, 450)
    sh.ZIndex                = -1
    sh.Parent                = main

    -- ==========================================
    -- HEADER (40px)
    -- ==========================================
    local hdr = Instance.new("Frame")
    hdr.Name               = "Header"
    hdr.Size               = UDim2.new(1, 0, 0, 40)
    hdr.BackgroundColor3   = CLR.header
    hdr.BorderSizePixel    = 0
    hdr.Parent             = main
    Corner(hdr, 10)

    local grad = Instance.new("UIGradient")
    grad.Color    = ColorSequence.new({
        ColorSequenceKeypoint.new(0, CLR.headerGrad),
        ColorSequenceKeypoint.new(1, CLR.header),
    })
    grad.Rotation = 270
    grad.Parent   = hdr

    -- Round bottom corners flush
    local hdrFix = Instance.new("Frame")
    hdrFix.Size              = UDim2.new(1, 0, 0, 12)
    hdrFix.Position          = UDim2.new(0, 0, 1, -12)
    hdrFix.BackgroundColor3  = CLR.header
    hdrFix.BorderSizePixel   = 0
    hdrFix.Parent            = hdr

    local sep = Instance.new("Frame")
    sep.Size             = UDim2.new(1, -16, 0, 1)
    sep.Position         = UDim2.new(0, 8, 1, 0)
    sep.BackgroundColor3 = CLR.border
    sep.BorderSizePixel  = 0
    sep.Parent           = hdr

    local ttl = Instance.new("TextLabel")
    ttl.Size              = UDim2.new(1, -130, 1, 0)
    ttl.Position          = UDim2.new(0, 12, 0, 0)
    ttl.BackgroundTransparency= 1
    ttl.Text              = "⚔  MASS ATTACK PRO"
    ttl.TextColor3        = CLR.text
    ttl.TextSize          = 14
    ttl.Font              = Enum.Font.GothamBold
    ttl.TextXAlignment    = Enum.TextXAlignment.Left
    ttl.Parent            = hdr

    local verBadge = Instance.new("TextLabel")
    verBadge.Size            = UDim2.new(0, 36, 0, 16)
    verBadge.Position        = UDim2.new(0, 178, 0.5, -8)
    verBadge.BackgroundColor3= CLR.accent
    verBadge.Text            = "v" .. SCRIPT_VERSION
    verBadge.TextColor3      = CLR.text
    verBadge.TextSize        = 9
    verBadge.Font            = Enum.Font.GothamBold
    verBadge.Parent          = hdr
    Corner(verBadge, 4)

    local minB = Instance.new("TextButton")
    minB.Size               = UDim2.new(0, 26, 0, 26)
    minB.Position           = UDim2.new(1, -62, 0.5, -13)
    minB.BackgroundColor3   = CLR.orange
    minB.Text               = "—"
    minB.TextColor3         = CLR.text
    minB.TextSize           = 13
    minB.Font               = Enum.Font.GothamBold
    minB.AutoButtonColor    = false
    minB.Parent             = hdr
    Corner(minB, 6)
    Hover(minB, CLR.orange, Color3.fromRGB(255, 195, 65))

    local clsB = Instance.new("TextButton")
    clsB.Size               = UDim2.new(0, 26, 0, 26)
    clsB.Position           = UDim2.new(1, -32, 0.5, -13)
    clsB.BackgroundColor3   = CLR.red
    clsB.Text               = "✕"
    clsB.TextColor3         = CLR.text
    clsB.TextSize           = 11
    clsB.Font               = Enum.Font.GothamBold
    clsB.AutoButtonColor    = false
    clsB.Parent             = hdr
    Corner(clsB, 6)
    Hover(clsB, CLR.red, Color3.fromRGB(255, 88, 88))

    -- DRAGGING
    do
        local dragging, dInput, dStart, sPos
        Conn(hdr.InputBegan, function(inp)
            if inp.UserInputType == Enum.UserInputType.MouseButton1
            or inp.UserInputType == Enum.UserInputType.Touch then
                dragging = true
                dStart   = inp.Position
                sPos     = main.Position
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
    searchBar.Size              = UDim2.new(1, -14, 0, 26)
    searchBar.Position          = UDim2.new(0, 7, 0, 44)
    searchBar.BackgroundColor3  = CLR.card
    searchBar.BorderSizePixel   = 0
    searchBar.Parent            = main
    Corner(searchBar, 6)

    local searchIcon = Instance.new("TextLabel")
    searchIcon.Size                  = UDim2.new(0, 22, 1, 0)
    searchIcon.Position              = UDim2.new(0, 4, 0, 0)
    searchIcon.BackgroundTransparency= 1
    searchIcon.Text                  = "🔍"
    searchIcon.TextSize              = 11
    searchIcon.Font                  = Enum.Font.Gotham
    searchIcon.Parent                = searchBar

    local searchBox = Instance.new("TextBox")
    searchBox.Size                  = UDim2.new(1, -30, 1, 0)
    searchBox.Position              = UDim2.new(0, 26, 0, 0)
    searchBox.BackgroundTransparency= 1
    searchBox.PlaceholderText       = "Search controls..."
    searchBox.PlaceholderColor3     = CLR.textDim
    searchBox.Text                  = ""
    searchBox.TextColor3            = CLR.text
    searchBox.TextSize              = 11
    searchBox.Font                  = Enum.Font.Gotham
    searchBox.TextXAlignment        = Enum.TextXAlignment.Left
    searchBox.ClearTextOnFocus      = false
    searchBox.Parent                = searchBar

    -- ==========================================
    -- TAB BAR (pill style)
    -- ==========================================
    local tabBar = Instance.new("Frame")
    tabBar.Size                 = UDim2.new(1, -14, 0, 28)
    tabBar.Position             = UDim2.new(0, 7, 0, 74)
    tabBar.BackgroundTransparency= 1
    tabBar.Parent               = main

    local tabLayout = Instance.new("UIListLayout")
    tabLayout.FillDirection     = Enum.FillDirection.Horizontal
    tabLayout.SortOrder         = Enum.SortOrder.LayoutOrder
    tabLayout.Padding           = UDim.new(0, 3)
    tabLayout.Parent            = tabBar

    local TAB_NAMES = {"Combat","Defense","Survival","Utility","System"}
    local TAB_ICONS = {
        Combat   = "⚔",
        Defense  = "🛡",
        Survival = "❤",
        Utility  = "🔧",
        System   = "⚙",
    }

    local tabButtons = {}
    local tabFrames  = {}
    local activeTab  = CFG.DefaultTab

    -- ==========================================
    -- STATUS CARD (always visible)
    -- ==========================================
    local statusCard = Instance.new("Frame")
    statusCard.Size             = UDim2.new(1, -14, 0, 108)
    statusCard.Position         = UDim2.new(0, 7, 0, 106)
    statusCard.BackgroundColor3 = CLR.card
    statusCard.BorderSizePixel  = 0
    statusCard.Parent           = main
    Corner(statusCard, 6)
    Stroke(statusCard)

    local sDot = Instance.new("Frame")
    sDot.Size              = UDim2.new(0, 8, 0, 8)
    sDot.Position          = UDim2.new(0, 10, 0, 8)
    sDot.BackgroundColor3  = CLR.red
    sDot.BorderSizePixel   = 0
    sDot.Parent            = statusCard
    Corner(sDot, 4)

    local sLbl = Instance.new("TextLabel")
    sLbl.Size                  = UDim2.new(0, 80, 0, 14)
    sLbl.Position              = UDim2.new(0, 24, 0, 5)
    sLbl.BackgroundTransparency= 1
    sLbl.Text                  = "DISABLED"
    sLbl.TextColor3            = CLR.red
    sLbl.TextSize              = 10
    sLbl.Font                  = Enum.Font.GothamBold
    sLbl.TextXAlignment        = Enum.TextXAlignment.Left
    sLbl.Parent                = statusCard

    local sTimer = Instance.new("TextLabel")
    sTimer.Size                 = UDim2.new(0, 50, 0, 14)
    sTimer.Position             = UDim2.new(1, -58, 0, 5)
    sTimer.BackgroundTransparency=1
    sTimer.Text                 = "00:00"
    sTimer.TextColor3           = CLR.textDim
    sTimer.TextSize             = 9
    sTimer.Font                 = Enum.Font.GothamSemibold
    sTimer.TextXAlignment       = Enum.TextXAlignment.Right
    sTimer.Parent               = statusCard

    -- GroupHeader helper — now takes X offset param
    local function GroupHeader(text, xOff, y, color)
        local h = Instance.new("TextLabel")
        h.Size                  = UDim2.new(0, 100, 0, 12)
        h.Position              = UDim2.new(0, xOff, 0, y)
        h.BackgroundTransparency= 1
        h.Text                  = text
        h.TextColor3            = color or CLR.accent
        h.TextSize              = 8
        h.Font                  = Enum.Font.GothamBold
        h.TextXAlignment        = Enum.TextXAlignment.Left
        h.Parent                = statusCard
    end

    GroupHeader("⚔ COMBAT",  10,  20, CAT_COLORS.Combat)
    GroupHeader("🛡 DEFENSE", 200, 20, CAT_COLORS.Defense)

    local function StatL(name, x, y)
        local nl = Instance.new("TextLabel")
        nl.Size                  = UDim2.new(0, 52, 0, 12)
        nl.Position              = UDim2.new(0, x, 0, y)
        nl.BackgroundTransparency= 1
        nl.Text                  = name .. ":"
        nl.TextColor3            = CLR.textDim
        nl.TextSize              = 9
        nl.Font                  = Enum.Font.Gotham
        nl.TextXAlignment        = Enum.TextXAlignment.Left
        nl.Parent                = statusCard
        local vl = Instance.new("TextLabel")
        vl.Size                  = UDim2.new(0, 50, 0, 12)
        vl.Position              = UDim2.new(0, x + 52, 0, y)
        vl.BackgroundTransparency= 1
        vl.Text                  = "0"
        vl.TextColor3            = CLR.text
        vl.TextSize              = 9
        vl.Font                  = Enum.Font.GothamBold
        vl.TextXAlignment        = Enum.TextXAlignment.Left
        vl.Parent                = statusCard
        return vl
    end

    local svTargets = StatL("Targets",  10,  32)
    local svAttacks = StatL("Attacks",  10,  46)
    local svDPS     = StatL("DPS",      10,  60)
    local svMode    = StatL("Mode",     10,  74)

    local statDiv = Instance.new("Frame")
    statDiv.Size             = UDim2.new(0, 1, 0, 62)
    statDiv.Position         = UDim2.new(0.5, -1, 0, 28)
    statDiv.BackgroundColor3 = CLR.border
    statDiv.BorderSizePixel  = 0
    statDiv.Parent           = statusCard

    local svGuard   = StatL("Guard",  200, 32)
    local svHP      = StatL("HP",     200, 46)
    local svNearby  = StatL("Nearby", 200, 60)
    local svKAKills = StatL("Kills",  200, 74)

    local sysDivider = Instance.new("Frame")
    sysDivider.Size             = UDim2.new(1, -20, 0, 1)
    sysDivider.Position         = UDim2.new(0, 10, 0, 88)
    sysDivider.BackgroundColor3 = CLR.border
    sysDivider.BorderSizePixel  = 0
    sysDivider.Parent           = statusCard

    local svUptime = Instance.new("TextLabel")
    svUptime.Size               = UDim2.new(0.45, 0, 0, 12)
    svUptime.Position           = UDim2.new(0, 10, 0, 92)
    svUptime.BackgroundTransparency=1
    svUptime.Text               = "⏱ 00:00"
    svUptime.TextColor3         = CLR.textDim
    svUptime.TextSize           = 8
    svUptime.Font               = Enum.Font.Gotham
    svUptime.TextXAlignment     = Enum.TextXAlignment.Left
    svUptime.Parent             = statusCard

    local svExec = Instance.new("TextLabel")
    svExec.Size                 = UDim2.new(0.55, -10, 0, 12)
    svExec.Position             = UDim2.new(0.45, 0, 0, 92)
    svExec.BackgroundTransparency=1
    svExec.Text                 = "🖥 " .. EXECUTOR_NAME
    svExec.TextColor3           = CLR.textDim
    svExec.TextSize             = 8
    svExec.Font                 = Enum.Font.Gotham
    svExec.TextXAlignment       = Enum.TextXAlignment.Right
    svExec.Parent               = statusCard

    -- ==========================================
    -- TAB CONTENT AREA
    -- ==========================================
    local contentArea = Instance.new("Frame")
    contentArea.Size                 = UDim2.new(1, -14, 1, -310)
    contentArea.Position             = UDim2.new(0, 7, 0, 218)
    contentArea.BackgroundTransparency= 1
    contentArea.ClipsDescendants     = true
    contentArea.Parent               = main

    for _, tabName in ipairs(TAB_NAMES) do
        local scroll = Instance.new("ScrollingFrame")
        scroll.Name                  = tabName
        scroll.Size                  = UDim2.new(1, 0, 1, 0)
        scroll.BackgroundTransparency= 1
        scroll.BorderSizePixel       = 0
        scroll.ScrollBarThickness    = 3
        scroll.ScrollBarImageColor3  = CLR.accent
        scroll.ScrollBarImageTransparency = 0.35
        scroll.CanvasSize            = UDim2.new(0, 0, 0, 0)
        scroll.AutomaticCanvasSize   = Enum.AutomaticSize.Y
        scroll.Visible               = (tabName == activeTab)
        scroll.Parent                = contentArea

        local lay = Instance.new("UIListLayout")
        lay.SortOrder     = Enum.SortOrder.LayoutOrder
        lay.Padding       = UDim.new(0, 4)
        lay.Parent        = scroll

        local pad = Instance.new("UIPadding")
        pad.PaddingBottom = UDim.new(0, 12)
        pad.Parent        = scroll

        tabFrames[tabName] = scroll
    end

    local _tabOrders = {}
    for _, n in ipairs(TAB_NAMES) do _tabOrders[n] = 0 end
    local function nxt(tab) _tabOrders[tab] += 1; return _tabOrders[tab] end

    local allControls = {}

    -- ==========================================
    -- UI BUILDERS
    -- ==========================================
    local function Section(tab, name)
        local parent = tabFrames[tab]
        if not parent then return end
        local f = Instance.new("Frame")
        f.Name                  = "Section_" .. name
        f.Size                  = UDim2.new(1, 0, 0, 22)
        f.BackgroundTransparency= 1
        f.LayoutOrder           = nxt(tab)
        f.Parent                = parent

        local isCollapsed = CFG.CollapsedSections[name] or false

        local arrow = Instance.new("TextButton")
        arrow.Size                  = UDim2.new(1, 0, 1, 0)
        arrow.BackgroundTransparency= 1
        arrow.Text                  = ""
        arrow.Parent                = f

        local arrowLabel = Instance.new("TextLabel")
        arrowLabel.Size                  = UDim2.new(1, -10, 1, 0)
        arrowLabel.Position              = UDim2.new(0, 5, 0, 0)
        arrowLabel.BackgroundTransparency= 1
        arrowLabel.Text                  = (isCollapsed and "▶  " or "▼  ") .. string.upper(name)
        arrowLabel.TextColor3            = CAT_COLORS[tab] or CLR.accent
        arrowLabel.TextSize              = 9
        arrowLabel.Font                  = Enum.Font.GothamBold
        arrowLabel.TextXAlignment        = Enum.TextXAlignment.Left
        arrowLabel.Parent                = f

        local ln = Instance.new("Frame")
        ln.Size             = UDim2.new(1, -10, 0, 1)
        ln.Position         = UDim2.new(0, 5, 1, -1)
        ln.BackgroundColor3 = CLR.border
        ln.BorderSizePixel  = 0
        ln.Parent           = f

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

    local function Toggle(tab, label, def, cb, section)
        local parent   = tabFrames[tab]
        if not parent then return end
        local catColor = CAT_COLORS[tab] or CLR.green

        local f = Instance.new("Frame")
        f.Name              = "Toggle_" .. label
        f.Size              = UDim2.new(1, 0, 0, 32)
        f.BackgroundColor3  = CLR.card
        f.BorderSizePixel   = 0
        f.LayoutOrder       = nxt(tab)
        f.Parent            = parent
        Corner(f, 6)

        -- Left category stripe
        local stripe = Instance.new("Frame")
        stripe.Size             = UDim2.new(0, 3, 0.7, 0)
        stripe.Position         = UDim2.new(0, 0, 0.15, 0)
        stripe.BackgroundColor3 = catColor
        stripe.BorderSizePixel  = 0
        stripe.Parent           = f
        Corner(stripe, 1)

        Hover(f, CLR.card, CLR.cardHover)
        if section then section.register(f) end
        table.insert(allControls, { frame = f, label = label })

        local tl = Instance.new("TextLabel")
        tl.Size                  = UDim2.new(1, -62, 1, 0)
        tl.Position              = UDim2.new(0, 10, 0, 0)
        tl.BackgroundTransparency= 1
        tl.Text                  = label
        tl.TextColor3            = CLR.text
        tl.TextSize              = 11
        tl.Font                  = Enum.Font.Gotham
        tl.TextXAlignment        = Enum.TextXAlignment.Left
        tl.TextTruncate          = Enum.TextTruncate.AtEnd
        tl.Parent                = f

        tl.MouseEnter:Connect(function() ShowTooltip(label, tl) end)
        tl.MouseLeave:Connect(function() HideTooltip() end)

        local bg = Instance.new("Frame")
        bg.Size             = UDim2.new(0, 40, 0, 18)
        bg.Position         = UDim2.new(1, -50, 0.5, -9)
        bg.BackgroundColor3 = def and catColor or CLR.toggleOff
        bg.BorderSizePixel  = 0
        bg.Parent           = f
        Corner(bg, 9)

        local dot = Instance.new("Frame")
        dot.Size            = UDim2.new(0, 14, 0, 14)
        dot.Position        = def and UDim2.new(1, -16, 0.5, -7)
                                   or UDim2.new(0, 2, 0.5, -7)
        dot.BackgroundColor3= Color3.new(1, 1, 1)
        dot.BorderSizePixel = 0
        dot.Parent          = bg
        Corner(dot, 7)

        local st  = def
        local api = {}

        function api.Set(v)
            st = v
            TweenService:Create(bg, TWEEN_SMOOTH,
                {BackgroundColor3 = st and catColor or CLR.toggleOff}):Play()
            TweenService:Create(dot, TWEEN_BOUNCE,
                {Position = st and UDim2.new(1, -16, 0.5, -7)
                                or UDim2.new(0, 2, 0.5, -7)}):Play()
        end
        function api.Get() return st end

        local btn = Instance.new("TextButton")
        btn.Size                  = UDim2.new(1, 0, 1, 0)
        btn.BackgroundTransparency= 1
        btn.Text                  = ""
        btn.Parent                = f
        btn.MouseButton1Click:Connect(function()
            TweenService:Create(f, TweenInfo.new(0.07), {Size = UDim2.new(1, 0, 0, 30)}):Play()
            task.delay(0.07, function()
                TweenService:Create(f, TWEEN_BOUNCE, {Size = UDim2.new(1, 0, 0, 32)}):Play()
            end)
            st = not st
            api.Set(st)
            if cb then cb(st) end
        end)

        return api
    end

    local function Slider(tab, label, lo, hi, def, cb, section)
        local parent = tabFrames[tab]
        if not parent then return end

        local f = Instance.new("Frame")
        f.Name              = "Slider_" .. label
        f.Size              = UDim2.new(1, 0, 0, 46)
        f.BackgroundColor3  = CLR.card
        f.BorderSizePixel   = 0
        f.LayoutOrder       = nxt(tab)
        f.Parent            = parent
        Corner(f, 6)
        Hover(f, CLR.card, CLR.cardHover)
        if section then section.register(f) end
        table.insert(allControls, { frame = f, label = label })

        local tl = Instance.new("TextLabel")
        tl.Size                  = UDim2.new(1, -52, 0, 16)
        tl.Position              = UDim2.new(0, 10, 0, 4)
        tl.BackgroundTransparency= 1
        tl.Text                  = label
        tl.TextColor3            = CLR.text
        tl.TextSize              = 11
        tl.Font                  = Enum.Font.Gotham
        tl.TextXAlignment        = Enum.TextXAlignment.Left
        tl.Parent                = f

        tl.MouseEnter:Connect(function() ShowTooltip(label, tl) end)
        tl.MouseLeave:Connect(function() HideTooltip() end)

        local vl = Instance.new("TextLabel")
        vl.Size                  = UDim2.new(0, 42, 0, 16)
        vl.Position              = UDim2.new(1, -52, 0, 4)
        vl.BackgroundTransparency= 1
        vl.Text                  = tostring(def)
        vl.TextColor3            = CLR.accent
        vl.TextSize              = 12
        vl.Font                  = Enum.Font.GothamBold
        vl.TextXAlignment        = Enum.TextXAlignment.Right
        vl.Parent                = f

        local track = Instance.new("Frame")
        track.Size             = UDim2.new(1, -20, 0, 4)
        track.Position         = UDim2.new(0, 10, 0, 32)
        track.BackgroundColor3 = CLR.sliderBg
        track.BorderSizePixel  = 0
        track.Parent           = f
        Corner(track, 2)

        local initR = math.clamp((def - lo) / (hi - lo), 0, 1)

        local fill = Instance.new("Frame")
        fill.Size             = UDim2.new(initR, 0, 1, 0)
        fill.BackgroundColor3 = CLR.accent
        fill.BorderSizePixel  = 0
        fill.Parent           = track
        Corner(fill, 2)

        local knob = Instance.new("Frame")
        knob.Size             = UDim2.new(0, 12, 0, 12)
        knob.Position         = UDim2.new(initR, -6, 0.5, -6)
        knob.BackgroundColor3 = Color3.new(1, 1, 1)
        knob.BorderSizePixel  = 0
        knob.ZIndex           = 2
        knob.Parent           = track
        Corner(knob, 6)

        local knobGlow = Instance.new("UIStroke")
        knobGlow.Color       = CLR.accent
        knobGlow.Thickness   = 1.5
        knobGlow.Transparency= 1
        knobGlow.Parent      = knob

        local hit = Instance.new("TextButton")
        hit.Size                  = UDim2.new(1, 0, 0, 24)
        hit.Position              = UDim2.new(0, 0, 0, 20)
        hit.BackgroundTransparency= 1
        hit.Text                  = ""
        hit.Parent                = f

        local sliding = false
        local cur     = def

        local function upd(pos)
            if not track or not track.Parent then return end
            local ax, aw = track.AbsolutePosition.X, track.AbsoluteSize.X
            if aw == 0 then return end
            local r = math.clamp((pos.X - ax) / aw, 0, 1)
            local v = math.clamp(math.floor(lo + (hi - lo) * r + 0.5), lo, hi)
            r = (v - lo) / (hi - lo)
            fill.Size     = UDim2.new(r, 0, 1, 0)
            knob.Position = UDim2.new(r, -6, 0.5, -6)
            vl.Text       = tostring(v)
            if v ~= cur then cur = v; if cb then cb(v) end end
        end

        hit.InputBegan:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1
            or i.UserInputType == Enum.UserInputType.Touch then
                sliding = true
                upd(i.Position)
                TweenService:Create(knobGlow, TWEEN_FAST, {Transparency = 0.3}):Play()
            end
        end)
        Conn(UIS.InputEnded, function(i)
            if (i.UserInputType == Enum.UserInputType.MouseButton1
             or i.UserInputType == Enum.UserInputType.Touch) and sliding then
                sliding = false
                TweenService:Create(knobGlow, TWEEN_FAST, {Transparency = 1}):Play()
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
                fill.Size     = UDim2.new(r, 0, 1, 0)
                knob.Position = UDim2.new(r, -6, 0.5, -6)
                vl.Text       = tostring(v)
            end,
            Get = function() return cur end,
        }
    end

    local function InfoRow(tab, label, defaultVal, section)
        local parent = tabFrames[tab]
        if not parent then return end
        local f = Instance.new("Frame")
        f.Name              = "Info_" .. label
        f.Size              = UDim2.new(1, 0, 0, 22)
        f.BackgroundColor3  = CLR.card
        f.BorderSizePixel   = 0
        f.LayoutOrder       = nxt(tab)
        f.Parent            = parent
        Corner(f, 5)
        if section then section.register(f) end

        local nl = Instance.new("TextLabel")
        nl.Size                  = UDim2.new(0.55, -5, 1, 0)
        nl.Position              = UDim2.new(0, 10, 0, 0)
        nl.BackgroundTransparency= 1
        nl.Text                  = label
        nl.TextColor3            = CLR.textDim
        nl.TextSize              = 9
        nl.Font                  = Enum.Font.Gotham
        nl.TextXAlignment        = Enum.TextXAlignment.Left
        nl.Parent                = f

        local vl = Instance.new("TextLabel")
        vl.Size                  = UDim2.new(0.45, -10, 1, 0)
        vl.Position              = UDim2.new(0.55, 0, 0, 0)
        vl.BackgroundTransparency= 1
        vl.Text                  = defaultVal or "-"
        vl.TextColor3            = CLR.text
        vl.TextSize              = 9
        vl.Font                  = Enum.Font.GothamBold
        vl.TextXAlignment        = Enum.TextXAlignment.Right
        vl.Parent                = f
        return vl
    end

    --- Dropdown widget (new in v5.0)
    local function Dropdown(tab, label, options, defaultVal, cb, section)
        local parent = tabFrames[tab]
        if not parent then return end

        local f = Instance.new("Frame")
        f.Name              = "Dropdown_" .. label
        f.Size              = UDim2.new(1, 0, 0, 32)
        f.BackgroundColor3  = CLR.card
        f.BorderSizePixel   = 0
        f.LayoutOrder       = nxt(tab)
        f.Parent            = parent
        Corner(f, 6)
        Hover(f, CLR.card, CLR.cardHover)
        if section then section.register(f) end
        table.insert(allControls, { frame = f, label = label })

        local tl = Instance.new("TextLabel")
        tl.Size                  = UDim2.new(0.48, 0, 1, 0)
        tl.Position              = UDim2.new(0, 10, 0, 0)
        tl.BackgroundTransparency= 1
        tl.Text                  = label
        tl.TextColor3            = CLR.text
        tl.TextSize              = 11
        tl.Font                  = Enum.Font.Gotham
        tl.TextXAlignment        = Enum.TextXAlignment.Left
        tl.Parent                = f

        local dropBtn = Instance.new("TextButton")
        dropBtn.Size              = UDim2.new(0, 130, 0, 22)
        dropBtn.Position          = UDim2.new(1, -138, 0.5, -11)
        dropBtn.BackgroundColor3  = CLR.sliderBg
        dropBtn.Text              = defaultVal .. " ▼"
        dropBtn.TextColor3        = CLR.accent
        dropBtn.TextSize          = 10
        dropBtn.Font              = Enum.Font.GothamBold
        dropBtn.AutoButtonColor   = false
        dropBtn.Parent            = f
        Corner(dropBtn, 5)

        -- Overlay parented to sg (screen level) so it draws above everything
        local overlay = Instance.new("Frame")
        overlay.Size              = UDim2.new(0, 140, 0, #options * 26 + 6)
        overlay.BackgroundColor3  = CLR.tooltipBg
        overlay.BorderSizePixel   = 0
        overlay.Visible           = false
        overlay.ZIndex            = 150
        overlay.Parent            = sg
        Corner(overlay, 6)
        Stroke(overlay, CLR.accent, 1)

        local ovLayout = Instance.new("UIListLayout")
        ovLayout.SortOrder = Enum.SortOrder.LayoutOrder
        ovLayout.Padding   = UDim.new(0, 2)
        ovLayout.Parent    = overlay

        local ovPad = Instance.new("UIPadding")
        ovPad.PaddingTop    = UDim.new(0, 3)
        ovPad.PaddingBottom = UDim.new(0, 3)
        ovPad.PaddingLeft   = UDim.new(0, 3)
        ovPad.PaddingRight  = UDim.new(0, 3)
        ovPad.Parent        = overlay

        local currentVal = defaultVal

        local optButtons = {}
        for oi, opt in ipairs(options) do
            local optBtn = Instance.new("TextButton")
            optBtn.Size              = UDim2.new(1, -6, 0, 22)
            optBtn.BackgroundColor3  = opt == currentVal and CLR.accent or CLR.card
            optBtn.Text              = opt
            optBtn.TextColor3        = CLR.text
            optBtn.TextSize          = 10
            optBtn.Font              = Enum.Font.GothamSemibold
            optBtn.AutoButtonColor   = false
            optBtn.LayoutOrder       = oi
            optBtn.ZIndex            = 151
            optBtn.Parent            = overlay
            Corner(optBtn, 4)
            optButtons[opt] = optBtn

            optBtn.MouseButton1Click:Connect(function()
                currentVal       = opt
                dropBtn.Text     = opt .. " ▼"
                overlay.Visible  = false
                for o, btn in pairs(optButtons) do
                    btn.BackgroundColor3 = o == opt and CLR.accent or CLR.card
                end
                if cb then cb(opt) end
            end)

            Hover(optBtn,
                opt == currentVal and CLR.accent or CLR.card,
                CLR.cardHover)
        end

        dropBtn.MouseButton1Click:Connect(function()
            if not overlay.Visible then
                local absPos  = dropBtn.AbsolutePosition
                local absSize = dropBtn.AbsoluteSize
                overlay.Position = UDim2.new(0, absPos.X, 0, absPos.Y + absSize.Y + 3)
                overlay.Visible  = true
            else
                overlay.Visible = false
            end
        end)

        -- Close on outside click
        Conn(UIS.InputBegan, function(inp, gp)
            if overlay.Visible and not gp
               and inp.UserInputType == Enum.UserInputType.MouseButton1 then
                local mp    = UIS:GetMouseLocation()
                local ovPos = overlay.AbsolutePosition
                local ovSz  = overlay.AbsoluteSize
                if mp.X < ovPos.X or mp.X > ovPos.X + ovSz.X
                or mp.Y < ovPos.Y or mp.Y > ovPos.Y + ovSz.Y then
                    overlay.Visible = false
                end
            end
        end)

        return {
            Get = function() return currentVal end,
            Set = function(v)
                currentVal   = v
                dropBtn.Text = v .. " ▼"
                for o, btn in pairs(optButtons) do
                    btn.BackgroundColor3 = o == v and CLR.accent or CLR.card
                end
            end,
        }
    end

    -- ==========================================
    -- TAB BUTTONS (pill style)
    -- ==========================================
    for idx, tabName in ipairs(TAB_NAMES) do
        local isActive = tabName == activeTab
        local btn = Instance.new("TextButton")
        btn.Name              = tabName
        btn.Size              = UDim2.new(0, 68, 1, 0)
        btn.BackgroundColor3  = isActive and (CAT_COLORS[tabName] or CLR.accent) or CLR.tabInactive
        btn.BorderSizePixel   = 0
        btn.Text              = TAB_ICONS[tabName] .. " " .. tabName
        btn.TextColor3        = isActive and Color3.new(1, 1, 1) or CLR.textDim
        btn.TextSize          = 9
        btn.Font              = Enum.Font.GothamBold
        btn.AutoButtonColor   = false
        btn.LayoutOrder       = idx
        btn.Parent            = tabBar
        Corner(btn, 6)
        tabButtons[tabName] = { button = btn }
    end

    local function SwitchTab(tabName)
        activeTab = tabName
        for name, data in pairs(tabButtons) do
            local isActive = name == tabName
            TweenService:Create(data.button, TWEEN_FAST, {
                BackgroundColor3 = isActive and (CAT_COLORS[name] or CLR.accent) or CLR.tabInactive,
                TextColor3       = isActive and Color3.new(1, 1, 1) or CLR.textDim,
            }):Play()
        end
        for name, frame in pairs(tabFrames) do
            frame.Visible = name == tabName
        end
    end

    for name, data in pairs(tabButtons) do
        data.button.MouseButton1Click:Connect(function() SwitchTab(name) end)
    end

    -- ==========================================
    -- SEARCH (scans both frame Name AND TextLabel text)
    -- ==========================================
    searchBox:GetPropertyChangedSignal("Text"):Connect(function()
        local query = searchBox.Text:lower()
        if query == "" then
            tabBar.Visible = true
            for name, frame in pairs(tabFrames) do
                frame.Visible = name == activeTab
                for _, child in ipairs(frame:GetChildren()) do
                    if child:IsA("Frame") then child.Visible = true end
                end
            end
        else
            tabBar.Visible = false
            for _, frame in pairs(tabFrames) do
                frame.Visible = true
                for _, child in ipairs(frame:GetChildren()) do
                    if child:IsA("Frame") and child.Name ~= "" then
                        -- Check frame name
                        local matchName = child.Name:lower():find(query)
                        -- Check any TextLabel text inside
                        local matchText = false
                        for _, el in ipairs(child:GetChildren()) do
                            if el:IsA("TextLabel") then
                                if el.Text:lower():find(query) then
                                    matchText = true
                                    break
                                end
                            end
                        end
                        child.Visible = (matchName ~= nil) or matchText
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
        sLbl.Text             = v and "ACTIVE" or "DISABLED"
        sLbl.TextColor3       = v and CLR.green or CLR.red
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

    Toggle("Combat", "Ignore ForceField", CFG.IgnoreForceField, function(v)
        CFG.IgnoreForceField = v; AutoSave()
    end, secMain)

    Dropdown("Combat", "Team Filter",
        {"None", "StudentsOnly", "VIPOnly"}, CFG.TeamFilter,
        function(v) CFG.TeamFilter = v; AutoSave() end, secMain)

    local secAttack = Section("Combat", "Attack Settings")

    Slider("Combat", "Attacks Per Second", 1, 20, CFG.AttacksPerSecond, function(v)
        CFG.AttacksPerSecond = v; AutoSave()
    end, secAttack)

    Slider("Combat", "Max Targets / Cycle", 1, 10, CFG.MaxTargetsPerCycle, function(v)
        CFG.MaxTargetsPerCycle = v; AutoSave()
    end, secAttack)

    Dropdown("Combat", "Target Priority",
        {"Nearest","LowestHP","HighestThreat","LowestStamina","SmallestFirst"},
        CFG.TargetPriority,
        function(v) CFG.TargetPriority = v; AutoSave() end, secAttack)

    Toggle("Combat", "Prefer Weapon Over Fist", CFG.PreferWeaponOverFist, function(v)
        CFG.PreferWeaponOverFist = v; AutoSave()
    end, secAttack)

    Toggle("Combat", "Animation Cancel " .. (REM.StopAnim and "✓" or "✗"),
        REM.StopAnim ~= nil and CFG.UseAnimCancel,
        function(v) if REM.StopAnim then CFG.UseAnimCancel = v end; AutoSave()
    end, secAttack)

    Toggle("Combat", "Disable Controls on Hit " .. (REM.DisableControlsEffect and "✓" or "✗"),
        CFG.UseDisableControlsOnAttack,
        function(v) CFG.UseDisableControlsOnAttack = v; AutoSave() end, secAttack)

    Toggle("Combat", "No Tools on Hit " .. (REM.NoTools and "✓" or "✗"),
        CFG.UseNoToolsOnAttack,
        function(v) CFG.UseNoToolsOnAttack = v; AutoSave() end, secAttack)

    local secTypes = Section("Combat", "Attack Types")

    Toggle("Combat", "Punch " .. (REM.Punch and "✓" or "✗"),
        REM.Punch ~= nil and CFG.UsePunch,
        function(v) if REM.Punch then CFG.UsePunch = v end; AutoSave() end, secTypes)

    Toggle("Combat", "Suplex " .. (REM.Suplex and "✓" or "✗"),
        REM.Suplex ~= nil and CFG.UseSuplex,
        function(v) if REM.Suplex then CFG.UseSuplex = v end; AutoSave() end, secTypes)

    Toggle("Combat", "Smart Suplex Gating", CFG.SmartSuplexGating, function(v)
        CFG.SmartSuplexGating = v; AutoSave()
    end, secTypes)

    Slider("Combat", "Suplex Charge Threshold", 0, 100, CFG.SuplexChargeThreshold, function(v)
        CFG.SuplexChargeThreshold = v; AutoSave()
    end, secTypes)

    Toggle("Combat", "Heavy Hit " .. (REM.HeavyHit and "✓" or "✗"),
        REM.HeavyHit ~= nil and CFG.UseHeavyHit,
        function(v) if REM.HeavyHit then CFG.UseHeavyHit = v end; AutoSave() end, secTypes)

    Toggle("Combat", "Tool/Weapon Attack " .. (REM.ToolHit and "✓" or "✗"),
        REM.ToolHit ~= nil and CFG.UseToolAttack,
        function(v) if REM.ToolHit then CFG.UseToolAttack = v end; AutoSave() end, secTypes)

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

    Slider("Combat", "Stun Range (studs)", 5, 100, CFG.StunRange, function(v)
        CFG.StunRange = v; AutoSave()
    end, secStomp)

    local secKA = Section("Combat", "Kill All")

    local tRemoteAura
    local tKillAll

    tRemoteAura = Toggle("Combat", "Remote Aura (All Players, No TP)", CFG.RemoteAura, function(v)
        CFG.RemoteAura = v
        if v then
            CFG.KillAllActive = false
            tKillAll.Set(false)
            if not CFG.Enabled then
                CFG.Enabled = true
                tEnabled.Set(true)
                sDot.BackgroundColor3 = CLR.green
                sLbl.Text             = "ACTIVE"
                sLbl.TextColor3       = CLR.green
            end
        end
        Notify(v and "Remote Aura ACTIVE" or "Remote Aura disabled",
               v and "warning" or "info", 2)
        AutoSave()
    end, secKA)

    tKillAll = Toggle("Combat", "Kill All (TP & Kill)", CFG.KillAllActive, function(v)
        CFG.KillAllActive = v
        if v then
            CFG.RemoteAura = false
            tRemoteAura.Set(false)
            if not CFG.Enabled then
                CFG.Enabled = true
                tEnabled.Set(true)
                sDot.BackgroundColor3 = CLR.green
                sLbl.Text             = "ACTIVE"
                sLbl.TextColor3       = CLR.green
            end
            if not ST.KillAllRunning then task.spawn(RunKillAll) end
        end
        AutoSave()
    end, secKA)

    Slider("Combat", "Kill Timeout (sec)", 3, 20, CFG.KillAllTimeout, function(v)
        CFG.KillAllTimeout = v; AutoSave()
    end, secKA)

    Toggle("Combat", "TP-Back Zone Avoidance", CFG.UseTPBackAvoidance, function(v)
        CFG.UseTPBackAvoidance = v; AutoSave()
    end, secKA)

    local secEffects = Section("Combat", "Effects on Hit")

    Toggle("Combat", "Shake on Hit " .. (REM.ShakeScreen and "✓" or "✗"),
        CFG.UseShakeOnHit, function(v) CFG.UseShakeOnHit = v; AutoSave() end, secEffects)

    Toggle("Combat", "Red Screen on Hit " .. (REM.RedScreen and "✓" or "✗"),
        CFG.UseRedScreenOnHit, function(v) CFG.UseRedScreenOnHit = v; AutoSave() end, secEffects)

    Toggle("Combat", "Impact Frames on Hit " .. (REM.ImpactFrames and "✓" or "✗"),
        CFG.UseImpactFramesOnHit, function(v) CFG.UseImpactFramesOnHit = v; AutoSave() end, secEffects)

    local secVis = Section("Combat", "Visualization")

    Toggle("Combat", "Kill Aura Visualization", CFG.KillAuraVisualization, function(v)
        CFG.KillAuraVisualization = v; UpdateAuraRing(); AutoSave()
    end, secVis)

    Toggle("Combat", "ESP Overlay", CFG.ESPEnabled, function(v)
        CFG.ESPEnabled = v
        if not v then ClearAllESP() end
        AutoSave()
    end, secVis)

    Toggle("Combat", "ESP Show Stats", CFG.ESPShowStats, function(v)
        CFG.ESPShowStats = v; AutoSave()
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

    local secAFK = Section("Survival", "Respawn / AFK")

    Toggle("Survival", "Anti-AFK", CFG.AntiAFK, function(v)
        CFG.AntiAFK = v; AutoSave()
    end, secAFK)

    Toggle("Survival", "Auto Respawn", CFG.AutoRespawn, function(v)
        CFG.AutoRespawn = v; AutoSave()
    end, secAFK)

    local secSpin = Section("Survival", "Spin Wheel")

    Toggle("Survival", "Auto Spin Wheel " .. (REM.Spin and "✓" or "✗"),
        CFG.UseAutoSpin, function(v)
        CFG.UseAutoSpin = v; AutoSave()
    end, secSpin)

    Slider("Survival", "Spin Cooldown (sec)", 10, 120, CFG.AutoSpinCooldown, function(v)
        CFG.AutoSpinCooldown = v; AutoSave()
    end, secSpin)

    local svSpinReward = InfoRow("Survival", "Last Spin Reward", ST.LastSpinReward, secSpin)

    -- === UTILITY TAB ===
    local secSize = Section("Utility", "Size Changer")

    Toggle("Utility", "Size Changer", CFG.SizeChangerEnabled, function(v)
        CFG.SizeChangerEnabled = v
        if v then
            ApplySize(CFG.SizeChangerValue)
            Notify("Size set to " .. string.format("%.1f", CFG.SizeChangerValue), "success", 2)
        else
            -- Nil-char guard (Bug #7 fix)
            GetChar()
            if char and char.Parent then ApplySize(1.0) end
            Notify("Size reset to normal", "info", 2)
        end
        AutoSave()
    end, secSize)

    Slider("Utility", "Size", 1, 10, CFG.SizeChangerValue, function(v)
        CFG.SizeChangerValue = v
        if CFG.SizeChangerEnabled then ApplySize(v) end
        AutoSave()
    end, secSize)

    local secWeapon = Section("Utility", "Weapons & Pickups")

    Toggle("Utility", "Auto Pickup Weapons " .. (REM.PickupTool and "✓" or "✗"),
        CFG.UseAutoPickupTools, function(v)
        CFG.UseAutoPickupTools = v; AutoSave()
    end, secWeapon)

    Slider("Utility", "Pickup Range (studs)", 10, 200, CFG.ToolPickupRange, function(v)
        CFG.ToolPickupRange = v; AutoSave()
    end, secWeapon)

    Toggle("Utility", "Auto Throwables " .. (REM.Throw and "✓" or "✗"),
        CFG.UseAutoThrowable, function(v)
        if REM.Throw then CFG.UseAutoThrowable = v end; AutoSave()
    end, secWeapon)

    Slider("Utility", "Throwable Range (studs)", 5, 100, CFG.ThrowableRange, function(v)
        CFG.ThrowableRange = v; AutoSave()
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

    local secATM = Section("Utility", "ATM Farmer")

    Toggle("Utility", "ATM Farmer", CFG.UseATMFarmer, function(v)
        CFG.UseATMFarmer = v
        local count = 0
        for _ in pairs(ST.ATMRegistry) do count += 1 end
        Notify(v and ("ATM Farmer ON — " .. count .. " ATMs found") or "ATM Farmer OFF",
               v and "warning" or "info", 2)
        AutoSave()
    end, secATM)

    Slider("Utility", "ATM Attack Cooldown (s)", 1, 10, CFG.ATMFarmerCooldown * 10, function(v)
        CFG.ATMFarmerCooldown = v / 10; AutoSave()
    end, secATM)

    local secShop = Section("Utility", "Shop Auto-Buy")

    Toggle("Utility", "Shop Auto-Buy", CFG.UseAutoShopBuy, function(v)
        CFG.UseAutoShopBuy = v; AutoSave()
    end, secShop)

    -- Per-item checkboxes
    local SHOP_DISPLAY = {
        {"Crowbar", "Crowbar"}, {"Baseballbat", "Baseball Bat"},
        {"Sledgehammer", "Sledgehammer"}, {"BoxingGloves", "Boxing Gloves"},
        {"Hotdog", "Hotdog"}, {"Cookies", "Cookies"},
        {"Cabbage", "Cabbage"}, {"Drink", "Drink"},
    }
    for _, entry in ipairs(SHOP_DISPLAY) do
        local key    = entry[1]
        local dispNm = entry[2]
        Toggle("Utility", "  Buy " .. dispNm, CFG.ShopBuyList[key] or false, function(v)
            CFG.ShopBuyList[key] = v; AutoSave()
        end, secShop)
    end

    local secQuests = Section("Utility", "Quest Farmer")

    Toggle("Utility", "Quest Farmer", CFG.UseQuestFarmer, function(v)
        CFG.UseQuestFarmer = v
        if v then RunQuestFarmer() end
        AutoSave()
    end, secQuests)

    -- Quest progress display
    local ALL_QUESTS = {
        {"Quests", "Throw things"},
        {"Quests", "Buy weapons"},
        {"Quests", "Eat tortas"},
        {"ChristmasQuests", "Destroy ATMs"},
        {"ChristmasQuests", "Pick random weapons from the floor"},
    }
    for _, qEntry in ipairs(ALL_QUESTS) do
        local folder = qEntry[1]
        local qName  = qEntry[2]
        local vl     = InfoRow("Utility", qName, "?", secQuests)
        if vl then
            ST.QuestLabels[folder .. ":" .. qName] = vl
        end
    end

    local secLists = Section("Utility", "Player Lists")

    Toggle("Utility", "Auto-Whitelist Friends", CFG.AutoWhitelistFriends, function(v)
        CFG.AutoWhitelistFriends = v; AutoSave()
    end, secLists)

    -- Whitelist / Blacklist input
    do
        local wlFrame = Instance.new("Frame")
        wlFrame.Size              = UDim2.new(1, 0, 0, 30)
        wlFrame.BackgroundColor3  = CLR.card
        wlFrame.BorderSizePixel   = 0
        wlFrame.LayoutOrder       = nxt("Utility")
        wlFrame.Parent            = tabFrames["Utility"]
        Corner(wlFrame, 5)
        if secLists then secLists.register(wlFrame) end

        local wlBox = Instance.new("TextBox")
        wlBox.Size                  = UDim2.new(1, -82, 1, -6)
        wlBox.Position              = UDim2.new(0, 8, 0, 3)
        wlBox.BackgroundTransparency= 1
        wlBox.PlaceholderText       = "Player name..."
        wlBox.PlaceholderColor3     = CLR.textDim
        wlBox.Text                  = ""
        wlBox.TextColor3            = CLR.text
        wlBox.TextSize              = 10
        wlBox.Font                  = Enum.Font.Gotham
        wlBox.TextXAlignment        = Enum.TextXAlignment.Left
        wlBox.Parent                = wlFrame

        local wlBtn = Instance.new("TextButton")
        wlBtn.Size              = UDim2.new(0, 34, 0, 22)
        wlBtn.Position          = UDim2.new(1, -74, 0, 4)
        wlBtn.BackgroundColor3  = CLR.green
        wlBtn.Text              = "+WL"
        wlBtn.TextColor3        = Color3.fromRGB(10,10,18)
        wlBtn.TextSize          = 8
        wlBtn.Font              = Enum.Font.GothamBold
        wlBtn.AutoButtonColor   = false
        wlBtn.Parent            = wlFrame
        Corner(wlBtn, 4)

        local blBtn = Instance.new("TextButton")
        blBtn.Size              = UDim2.new(0, 34, 0, 22)
        blBtn.Position          = UDim2.new(1, -36, 0, 4)
        blBtn.BackgroundColor3  = CLR.red
        blBtn.Text              = "+BL"
        blBtn.TextColor3        = CLR.text
        blBtn.TextSize          = 8
        blBtn.Font              = Enum.Font.GothamBold
        blBtn.AutoButtonColor   = false
        blBtn.Parent            = wlFrame
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

    local secConfig = Section("System", "Configuration")

    do
        local cfgFrame = Instance.new("Frame")
        cfgFrame.Size             = UDim2.new(1, 0, 0, 30)
        cfgFrame.BackgroundColor3 = CLR.card
        cfgFrame.BorderSizePixel  = 0
        cfgFrame.LayoutOrder      = nxt("System")
        cfgFrame.Parent           = tabFrames["System"]
        Corner(cfgFrame, 5)
        if secConfig then secConfig.register(cfgFrame) end

        local expBtn = Instance.new("TextButton")
        expBtn.Size              = UDim2.new(0.48, 0, 0, 24)
        expBtn.Position          = UDim2.new(0.01, 0, 0, 3)
        expBtn.BackgroundColor3  = CLR.accent
        expBtn.Text              = "📋 Export Config"
        expBtn.TextColor3        = CLR.text
        expBtn.TextSize          = 10
        expBtn.Font              = Enum.Font.GothamBold
        expBtn.AutoButtonColor   = false
        expBtn.Parent            = cfgFrame
        Corner(expBtn, 5)

        expBtn.MouseButton1Click:Connect(function()
            local ok, json = pcall(function() return HttpService:JSONEncode(CFG) end)
            if ok and CAN_SET_CLIPBOARD then
                setclipboard(json)
                Notify("Config copied to clipboard!", "success", 3)
            elseif ok then
                Notify("Clipboard API unavailable", "error", 3)
            end
        end)

        local impBtn = Instance.new("TextButton")
        impBtn.Size             = UDim2.new(0.48, 0, 0, 24)
        impBtn.Position         = UDim2.new(0.51, 0, 0, 3)
        impBtn.BackgroundColor3 = CAT_COLORS.Utility
        impBtn.Text             = "📥 Import Config"
        impBtn.TextColor3       = Color3.fromRGB(10, 10, 18)
        impBtn.TextSize         = 10
        impBtn.Font             = Enum.Font.GothamBold
        impBtn.AutoButtonColor  = false
        impBtn.Parent           = cfgFrame
        Corner(impBtn, 5)

        local importFrame = Instance.new("Frame")
        importFrame.Size              = UDim2.new(1, 0, 0, 60)
        importFrame.BackgroundColor3  = CLR.card
        importFrame.BorderSizePixel   = 0
        importFrame.LayoutOrder       = nxt("System")
        importFrame.Visible           = false
        importFrame.Parent            = tabFrames["System"]
        Corner(importFrame, 5)
        if secConfig then secConfig.register(importFrame) end

        local importBox = Instance.new("TextBox")
        importBox.Size                  = UDim2.new(1, -12, 0, 36)
        importBox.Position              = UDim2.new(0, 6, 0, 3)
        importBox.BackgroundColor3      = CLR.sliderBg
        importBox.PlaceholderText       = "Paste JSON config here..."
        importBox.PlaceholderColor3     = CLR.textDim
        importBox.Text                  = ""
        importBox.TextColor3            = CLR.text
        importBox.TextSize              = 9
        importBox.Font                  = Enum.Font.Gotham
        importBox.TextXAlignment        = Enum.TextXAlignment.Left
        importBox.ClearTextOnFocus      = true
        importBox.Parent                = importFrame
        Corner(importBox, 4)

        local applyBtn = Instance.new("TextButton")
        applyBtn.Size              = UDim2.new(1, -12, 0, 16)
        applyBtn.Position          = UDim2.new(0, 6, 0, 42)
        applyBtn.BackgroundColor3  = CLR.green
        applyBtn.Text              = "Apply"
        applyBtn.TextColor3        = Color3.fromRGB(10, 10, 18)
        applyBtn.TextSize          = 10
        applyBtn.Font              = Enum.Font.GothamBold
        applyBtn.Parent            = importFrame
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
                Notify("Config imported!", "success", 3)
                importFrame.Visible = false
                AutoSave()
            else
                Notify("Invalid JSON config", "error", 3)
            end
        end)
    end

    local secRemotes = Section("System", "Remote Status")

    local remoteList = {
        {"PUNCHEVENT",             REM.Punch},
        {"SUPLEXEVENT",            REM.Suplex},
        {"HEAVYHIT",               REM.HeavyHit},
        {"BLOCKEVENT",             REM.Block},
        {"STOMPEVENT",             REM.Stomp},
        {"TOOLHITEVENT",           REM.ToolHit},
        {"STUNEVENT",              REM.Stun},
        {"HEALCHARACTERCARRIED",   REM.Heal},
        {"Carniceria (Bindable)",   REM.Carniceria},
        {"CARRYEVENT",             REM.Carry},
        {"Throw (RemoteFunction)", REM.Throw},
        {"CROUCHEVENT",            REM.Crouch},
        {"STOPLOCALANIMATIONS",    REM.StopAnim},
        {"PVPONOFFEVENT",          REM.PVPToggle},
        {"PICKUPTOOLSEVENT",       REM.PickupTool},
        {"DisableControls (FX)",   REM.DisableControlsEffect},
        {"NoTools (FX)",           REM.NoTools},
        {"ShakeScreenEvent (FX)",  REM.ShakeScreen},
        {"RedScreenEvent (FX)",    REM.RedScreen},
        {"ImpactFramesEvent (FX)", REM.ImpactFrames},
        {"IsResetTime (Spin)",     REM.IsResetTime},
        {"Spin (RemoteFunction)",  REM.Spin},
    }

    local ri = Instance.new("Frame")
    ri.Size             = UDim2.new(1, 0, 0, #remoteList * 14 + 8)
    ri.BackgroundColor3 = CLR.card
    ri.BorderSizePixel  = 0
    ri.LayoutOrder      = nxt("System")
    ri.Parent           = tabFrames["System"]
    Corner(ri, 6)
    if secRemotes then secRemotes.register(ri) end

    for idx, data in ipairs(remoteList) do
        local ok  = data[2] ~= nil
        local rl  = Instance.new("TextLabel")
        rl.Size               = UDim2.new(1, -14, 0, 12)
        rl.Position           = UDim2.new(0, 10, 0, 4 + (idx - 1) * 14)
        rl.BackgroundTransparency= 1
        rl.Text               = (ok and "● " or "○ ") .. data[1]
        rl.TextColor3         = ok and CLR.green or CLR.red
        rl.TextSize           = 8
        rl.Font               = Enum.Font.GothamSemibold
        rl.TextXAlignment     = Enum.TextXAlignment.Left
        rl.Parent             = ri
    end

    -- ==========================================
    -- COMBAT LOG
    -- ==========================================
    local logFrame = Instance.new("Frame")
    logFrame.Name              = "CombatLog"
    logFrame.Size              = UDim2.new(1, -14, 0, 78)
    logFrame.Position          = UDim2.new(0, 7, 1, -83)
    logFrame.BackgroundColor3  = CLR.card
    logFrame.BackgroundTransparency = 0.15
    logFrame.BorderSizePixel   = 0
    logFrame.ClipsDescendants  = true
    logFrame.Parent            = main
    Corner(logFrame, 6)
    Stroke(logFrame)

    local logTitle = Instance.new("TextLabel")
    logTitle.Size                  = UDim2.new(1, 0, 0, 14)
    logTitle.BackgroundTransparency= 1
    logTitle.Text                  = "  📜 Combat Log"
    logTitle.TextColor3            = CLR.textDim
    logTitle.TextSize              = 8
    logTitle.Font                  = Enum.Font.GothamBold
    logTitle.TextXAlignment        = Enum.TextXAlignment.Left
    logTitle.Parent                = logFrame

    local logScroll = Instance.new("ScrollingFrame")
    logScroll.Size                  = UDim2.new(1, -4, 1, -16)
    logScroll.Position              = UDim2.new(0, 2, 0, 14)
    logScroll.BackgroundTransparency= 1
    logScroll.BorderSizePixel       = 0
    logScroll.ScrollBarThickness    = 2
    logScroll.ScrollBarImageColor3  = CLR.accent
    logScroll.CanvasSize            = UDim2.new(0, 0, 0, 0)
    logScroll.AutomaticCanvasSize   = Enum.AutomaticSize.Y
    logScroll.Parent                = logFrame

    local logLayout = Instance.new("UIListLayout")
    logLayout.SortOrder = Enum.SortOrder.LayoutOrder
    logLayout.Padding   = UDim.new(0, 1)
    logLayout.Parent    = logScroll

    -- ==========================================
    -- MINIMIZE / CLOSE
    -- ==========================================
    local minimized = false
    local fullSz    = UDim2.new(0, FULL_W, 0, FULL_H)

    minB.MouseButton1Click:Connect(function()
        minimized = not minimized
        if minimized then
            TweenService:Create(main, TweenInfo.new(0.2, Enum.EasingStyle.Quint),
                {Size = UDim2.new(0, FULL_W, 0, 40)}):Play()
            task.wait(0.2)
            contentArea.Visible = false
            statusCard.Visible  = false
            searchBar.Visible   = false
            tabBar.Visible      = false
            logFrame.Visible    = false
            minB.Text           = "+"
        else
            contentArea.Visible = true
            statusCard.Visible  = true
            searchBar.Visible   = true
            tabBar.Visible      = true
            logFrame.Visible    = true
            TweenService:Create(main, TweenInfo.new(0.25, Enum.EasingStyle.Quint),
                {Size = fullSz}):Play()
            minB.Text = "—"
        end
    end)

    clsB.MouseButton1Click:Connect(function()
        ST.Running        = false
        CFG.Enabled       = false
        CFG.KillAllActive = false
        SetGuard(false)
        ClearAllESP()
        UpdateAuraRing()
        TweenService:Create(main, TweenInfo.new(0.22, Enum.EasingStyle.Quint),
            {Size = UDim2.new(0, FULL_W, 0, 0), BackgroundTransparency = 1}):Play()
        task.wait(0.25)
        sg:Destroy()
    end)

    -- ==========================================
    -- KEYBINDS
    -- ==========================================
    Conn(UIS.InputBegan, function(inp, gp)
        if gp then return end
        local kc = inp.KeyCode
        local kb = CFG.Keybinds

        if kc == ResolveKey(kb.ToggleGUI) then
            main.Visible = not main.Visible

        elseif kc == ResolveKey(kb.ToggleScript) then
            CFG.Enabled = not CFG.Enabled
            tEnabled.Set(CFG.Enabled)
            sDot.BackgroundColor3 = CFG.Enabled and CLR.green or CLR.red
            sLbl.Text             = CFG.Enabled and "ACTIVE" or "DISABLED"
            sLbl.TextColor3       = CFG.Enabled and CLR.green or CLR.red
            UpdateAuraRing()
            Notify(CFG.Enabled and "Script enabled" or "Script disabled",
                   CFG.Enabled and "success" or "info", 1.5)

        elseif kc == ResolveKey(kb.KillAll) then
            CFG.KillAllActive = not CFG.KillAllActive
            tKillAll.Set(CFG.KillAllActive)
            if CFG.KillAllActive then
                if not CFG.Enabled then
                    CFG.Enabled = true
                    tEnabled.Set(true)
                end
                if not ST.KillAllRunning then task.spawn(RunKillAll) end
            end

        elseif kc == ResolveKey(kb.ToggleAoE) then
            CFG.TargetAll = not CFG.TargetAll
            Notify("Mode: " .. (CFG.TargetAll and "AoE" or "Single Target"), "info", 1.5)

        elseif kc == ResolveKey(kb.EmergencyStop) then
            CFG.Enabled       = false
            CFG.KillAllActive = false
            tEnabled.Set(false)
            tKillAll.Set(false)
            SetGuard(false)
            sDot.BackgroundColor3 = CLR.red
            sLbl.Text             = "DISABLED"
            sLbl.TextColor3       = CLR.red
            UpdateAuraRing()
            ClearAllESP()
            Notify("EMERGENCY STOP", "error", 3)
            AddLogEntry("system", "Emergency stop activated")

        elseif kc == ResolveKey(kb.ToggleAutoBlock) then
            if REM.Block then
                CFG.UseAutoGuard = not CFG.UseAutoGuard
                if not CFG.UseAutoGuard then SetGuard(false) end
                Notify("Auto Guard: " .. (CFG.UseAutoGuard and "ON" or "OFF"), "info", 1.5)
            end
        end
    end)

    -- ==========================================
    -- OPEN ANIMATION (0.95 → 1.0 + fade in)
    -- ==========================================
    task.defer(function()
        TweenService:Create(main, TweenInfo.new(0.35, Enum.EasingStyle.Quint),
            {Size = fullSz, BackgroundTransparency = 0}):Play()
    end)

    -- Status dot pulse
    task.spawn(function()
        while ST.Running do
            if sg and sg.Parent and sDot and sDot.Parent then
                if CFG.Enabled then
                    TweenService:Create(sDot, TweenInfo.new(0.65),
                        {BackgroundTransparency = 0.45}):Play()
                    task.wait(0.65)
                    if sDot and sDot.Parent then
                        TweenService:Create(sDot, TweenInfo.new(0.65),
                            {BackgroundTransparency = 0}):Play()
                    end
                    task.wait(0.65)
                else
                    if sDot.BackgroundTransparency ~= 0 then
                        TweenService:Create(sDot, TweenInfo.new(0.25),
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
        gui            = sg,
        main           = main,
        statusDot      = sDot,
        statusLbl      = sLbl,
        timer          = sTimer,
        logScroll      = logScroll,
        spinRewardLabel= svSpinReward,
        sv = {
            targets = svTargets, attacks = svAttacks,
            guard   = svGuard,   dps     = svDPS,
            health  = svHP,      mode    = svMode,
            nearby  = svNearby,  kaKills = svKAKills,
            uptime  = svUptime,
        },
        toggleEnabled  = tEnabled,
        toggleKillAll  = tKillAll,
    }
end

GUI_REFS = BuildGUI()

----------------------------------------------------------------
-- S16. MAIN LOOPS (6 consolidated)
----------------------------------------------------------------

-- Combat log flush
local _lastLogLen = 0
local function FlushCombatLog()
    if not GUI_REFS or not GUI_REFS.logScroll then return end
    local scroll = GUI_REFS.logScroll
    if #ST.CombatLog == _lastLogLen then return end
    for i = _lastLogLen + 1, #ST.CombatLog do
        local entry = ST.CombatLog[i]
        local lbl   = Instance.new("TextLabel")
        lbl.Size                  = UDim2.new(1, -4, 0, 11)
        lbl.BackgroundTransparency= 1
        lbl.Text                  = "[" .. entry.time .. "] " .. entry.message
        lbl.TextColor3            = entry.color
        lbl.TextSize              = 7
        lbl.Font                  = Enum.Font.Gotham
        lbl.TextXAlignment        = Enum.TextXAlignment.Left
        lbl.TextTruncate          = Enum.TextTruncate.AtEnd
        lbl.LayoutOrder           = i
        lbl.Parent                = scroll
    end
    _lastLogLen = #ST.CombatLog
    task.defer(function()
        if scroll and scroll.Parent then
            scroll.CanvasPosition = Vector2.new(0, scroll.AbsoluteCanvasSize.Y)
        end
    end)
end

-- ============================================================
-- COMPLETION BLOCK — paste this directly after the last line:
-- "local function FlushQuestLabels()"
-- "    for key, lbl in pairs(ST.QuestLab"
-- ============================================================

local function FlushQuestLabels()
    for key, lbl in pairs(ST.QuestLabels) do
        if lbl and lbl.Parent then
            local parts   = key:split(":")
            local folder  = parts[1]
            local qName   = parts[2]
            local f       = plr:FindFirstChild(folder)
            if f then
                local sv = f:FindFirstChild(qName)
                if sv and sv:IsA("StringValue") then
                    lbl.Text       = sv.Value ~= "" and sv.Value or "—"
                    lbl.TextColor3 = IsQuestDone(sv.Value) and CLR.green or CLR.text
                end
            end
        end
    end
end

-- ==========================================
-- LOOP 1 — MAIN ATTACK LOOP (high-frequency)
-- ==========================================
task.spawn(function()
    while ST.Running do
        if CFG.Enabled and not CFG.KillAllActive and not ST.KillAllRunning then
            GetChar()
            if rootPart and rootPart.Parent and humanoid and humanoid.Health > 0 then

                -- Refresh target list on interval
                local now = tick()
                if now - ST.LastTargetUpdate >= CFG.TargetUpdateInterval then
                    RefreshTargets()
                end

                local myPos = rootPart.Position

                -- Fix 6: RemoteAura now runs full IsValid() - ForceField, TeamFilter, PVP all respected
                if CFG.RemoteAura and HAS_ATTACK then
                    for _, p in ipairs(Players:GetPlayers()) do
                        if p ~= plr and p.Character then
                            if IsValid(p.Character) then
                                Attack(p.Character)
                            end
                        end
                    end

                elseif #ST.TargetCache > 0 then
                    -- Fix 7: only re-sort when the target list actually changed
                    if ST.SortedTargetCacheDirty then
                        local sorted = {}
                        for _, model in ipairs(ST.TargetCache) do
                            if model and model.Parent then
                                table.insert(sorted, {
                                    model = model,
                                    score = ScoreTarget(model, myPos)
                                })
                            end
                        end
                        table.sort(sorted, function(a, b) return a.score > b.score end)
                        ST.SortedTargetCache      = sorted
                        ST.SortedTargetCacheDirty = false
                    end

                    if #ST.SortedTargetCache == 0 then ClearAllESP() end

                    local limit   = CFG.TargetAll and math.min(#ST.SortedTargetCache, CFG.MaxTargetsPerCycle) or 1
                    local attacked = 0

                    for _, entry in ipairs(ST.SortedTargetCache) do
                        if attacked >= limit then break end
                        local model = entry.model
                        if not model or not model.Parent then
                            -- model gone, mark cache dirty for next cycle
                            ST.SortedTargetCacheDirty = true
                        else
                            local hrp = model:FindFirstChild("HumanoidRootPart")
                            if hrp then
                                local dist = (myPos - hrp.Position).Magnitude

                                -- Standard combat: NO teleport. Only attack targets already
                                -- within AttackRange. Kill All handles all teleporting.
                                if dist <= CFG.AttackRange then
                                    -- Guard drop
                                    if CFG.UseAutoGuard and CFG.GuardDropForAttack and ST.GuardActive then
                                        SetGuard(false)
                                        task.wait(0.02)
                                    end

                                    Attack(model)
                                    attacked += 1

                                    -- Re-raise guard
                                    if CFG.UseAutoGuard and CFG.GuardDropForAttack then
                                        task.delay(CFG.GuardReactivateDelay, function()
                                            if CFG.Enabled and CFG.UseAutoGuard then
                                                SetGuard(true)
                                            end
                                        end)
                                    end

                                    -- ESP creation
                                    if CFG.ESPEnabled then CreateESP(model) end

                                    -- Threat table update
                                    local p = Players:GetPlayerFromCharacter(model)
                                    if p then
                                        ST.ThreatTable[model.Name] = (ST.ThreatTable[model.Name] or 0) + 1
                                    end
                                end
                            end
                        end
                    end
                else
                    -- No targets — clear stale ESP
                    ClearAllESP()
                end

                TryStomp()
                TryStun()
            end
        end

        local rate = math.max(1 / math.max(CFG.AttacksPerSecond, 1), 0.01)
        task.wait(rate)
    end
end)

-- ==========================================
-- LOOP 2 — GUARD & SURVIVAL (medium-frequency ~0.05s)
-- ==========================================
task.spawn(function()
    while ST.Running do
        if CFG.Enabled then
            GetChar()
            if humanoid and humanoid.Health > 0 then
                -- Guard management
                if CFG.UseAutoGuard and REM.Block and not CFG.KillAllActive then
                    local nearby = IsEnemyNearby(CFG.GuardActivationRange)
                    ST.EnemyNearby = nearby
                    if nearby and not ST.GuardActive then
                        SetGuard(true)
                    elseif not nearby and ST.GuardActive then
                        SetGuard(false)
                    end
                end

                -- Health tracking for DPS measurement
                local currentHP = humanoid.Health
                local delta     = ST.LastHealth - currentHP
                if delta > 0 then RecordDamage(delta) end
                ST.LastHealth = currentHP

                TryHeal()
                TryBuyFood()
                ManagePVP()
            end
        end
        task.wait(math.max(CFG.HealthPollInterval, 0.01))
    end
end)

-- ==========================================
-- LOOP 3 — UTILITY SYSTEMS (low-frequency ~0.5s)
-- ==========================================
task.spawn(function()
    while ST.Running do
        if CFG.Enabled then
            TryPickupTools()
            TryCarryThrow()
            TryATMFarmer()
            TryAutoThrowable()
            TryAutoSpin()
            TryBuyShopItems()
            if CFG.UseQuestFarmer then RunQuestFarmer() end

            -- Crouch spam
            if CFG.UseCrouchSpam and REM.Crouch then
                pcall(function() REM.Crouch:FireServer(true) end)
                task.wait(CFG.CrouchSpamSpeed)
                pcall(function() REM.Crouch:FireServer(false) end)
            end
        end
        task.wait(0.5)
    end
end)

-- ==========================================
-- LOOP 4 — GUI STATUS UPDATE (~0.15s)
-- ==========================================
task.spawn(function()
    while ST.Running do
        pcall(function()
            if not GUI_REFS then return end
            local sv = GUI_REFS.sv
            if not sv then return end

            GetChar()
            local hpPct = 0
            if humanoid and humanoid.MaxHealth > 0 then
                hpPct = math.floor((humanoid.Health / humanoid.MaxHealth) * 100)
            end

            local dps    = math.floor(CalculateDPS() * 10) / 10
            local uptime = FormatTime(tick() - ST.StartTime)
            local mode   = CFG.KillAllActive and "KillAll"
                        or CFG.RemoteAura     and "RemoteAura"
                        or CFG.TargetAll      and "AoE"
                        or "Single"

            -- Safe label updates
            if sv.targets and sv.targets.Parent then
                sv.targets.Text = tostring(ST.TargetsFound)
            end
            if sv.attacks and sv.attacks.Parent then
                sv.attacks.Text = tostring(ST.TotalAttacks)
            end
            if sv.dps and sv.dps.Parent then
                sv.dps.Text = string.format("%.1f", dps)
            end
            if sv.mode and sv.mode.Parent then
                sv.mode.Text = mode
                sv.mode.TextColor3 = CFG.KillAllActive and CLR.red
                    or CFG.RemoteAura and CLR.orange
                    or CLR.text
            end
            if sv.guard and sv.guard.Parent then
                sv.guard.Text       = ST.GuardActive and "ON" or "OFF"
                sv.guard.TextColor3 = ST.GuardActive and CLR.green or CLR.textDim
            end
            if sv.health and sv.health.Parent then
                sv.health.Text       = hpPct .. "%"
                sv.health.TextColor3 = hpPct > 60 and CLR.green
                    or hpPct > 30 and CLR.yellow
                    or CLR.red
            end
            if sv.nearby and sv.nearby.Parent then
                local nb = IsEnemyNearby(CFG.GuardActivationRange)
                sv.nearby.Text       = nb and "YES" or "No"
                sv.nearby.TextColor3 = nb and CLR.orange or CLR.textDim
            end
            if sv.kaKills and sv.kaKills.Parent then
                sv.kaKills.Text = tostring(ST.KillAllKills)
            end
            if sv.uptime and sv.uptime.Parent then
                sv.uptime.Text = "⏱ " .. uptime
            end
            if GUI_REFS.timer and GUI_REFS.timer.Parent then
                GUI_REFS.timer.Text = uptime
            end
            if GUI_REFS.spinRewardLabel and GUI_REFS.spinRewardLabel.Parent
               and ST.LastSpinReward ~= "None" then
                GUI_REFS.spinRewardLabel.Text = ST.LastSpinReward
            end

            -- Kill All status in mode label
            if CFG.KillAllActive and ST.KillAllTarget ~= "" then
                if sv.mode and sv.mode.Parent then
                    local progress = ST.KillAllProgress ~= "" and (" [" .. ST.KillAllProgress .. "]") or ""
                    sv.mode.Text = "→ " .. ST.KillAllTarget .. progress
                end
            end

            -- ESP update
            UpdateESP()

            -- Combat log flush
            FlushCombatLog()

            -- Quest labels
            FlushQuestLabels()
        end)
        task.wait(0.15)
    end
end)

-- ==========================================
-- LOOP 5 — ANTI-AFK (~55s)
-- ==========================================
task.spawn(function()
    while ST.Running do
        task.wait(55)
        if CFG.AntiAFK then
            pcall(function()
                local vjs = game:GetService("VirtualInputManager")
                if vjs then
                    vjs:SendKeyEvent(true,  Enum.KeyCode.W, false, game)
                    task.wait(0.1)
                    vjs:SendKeyEvent(false, Enum.KeyCode.W, false, game)
                end
            end)
            pcall(function()
                local v = game:GetService("VirtualUser")
                if v then v:Button2Down(Vector2.new(0,0), CFrame.new()) end
                task.wait(0.05)
                if v then v:Button2Up(Vector2.new(0,0), CFrame.new()) end
            end)
        end
    end
end)

-- ==========================================
-- LOOP 6 — CHARACTER RESPAWN WATCHER
-- ==========================================
Conn(plr.CharacterAdded, function(newChar)
    char     = newChar
    rootPart = newChar:WaitForChild("HumanoidRootPart", 10)
    humanoid = newChar:WaitForChild("Humanoid", 10)

    ST.LastHealth = humanoid and humanoid.Health or 100
    InvalidateNearbyCache()

    if CFG.AutoRespawn and CFG.Enabled then
        task.wait(1.5)
        Notify("Respawned — resuming combat", "info", 2)
        AddLogEntry("system", "Auto-respawned, combat resumed")
    end

    -- Reapply size changer on respawn
    if CFG.SizeChangerEnabled then
        task.wait(0.5)
        ApplySize(CFG.SizeChangerValue)
    end

    -- Re-hook health for DPS tracking
    if humanoid then
        Conn(humanoid.HealthChanged, function(hp)
            local delta = ST.LastHealth - hp
            if delta > 0 then RecordDamage(delta) end
            ST.LastHealth = hp
        end)
    end
end)

-- Initial health hook
if humanoid then
    Conn(humanoid.HealthChanged, function(hp)
        local delta = ST.LastHealth - hp
        if delta > 0 then RecordDamage(delta) end
        ST.LastHealth = hp
    end)
end

-- ==========================================
-- FINAL INIT — Load config, show welcome
-- ==========================================
XenoLoadConfig(CFG)

-- Sync status dot to loaded config state
if GUI_REFS then
    local dot = GUI_REFS.statusDot
    local lbl = GUI_REFS.statusLbl
    if dot and dot.Parent then
        dot.BackgroundColor3 = CFG.Enabled and CLR.green or CLR.red
    end
    if lbl and lbl.Parent then
        lbl.Text       = CFG.Enabled and "ACTIVE" or "DISABLED"
        lbl.TextColor3 = CFG.Enabled and CLR.green or CLR.red
    end
    if GUI_REFS.toggleEnabled then
        GUI_REFS.toggleEnabled.Set(CFG.Enabled)
    end
end

-- Kill All auto-resume if it was active when config was saved
if CFG.KillAllActive and not ST.KillAllRunning then
    task.spawn(RunKillAll)
end

-- Aura ring initial state
UpdateAuraRing()

-- Welcome notification
task.delay(0.6, function()
    Notify("MAP v" .. SCRIPT_VERSION .. " loaded — " .. EXECUTOR_NAME, "success", 4)
    AddLogEntry("system", "Mass Attack Pro v" .. SCRIPT_VERSION .. " initialized on " .. EXECUTOR_NAME)
    local remCount = 0
    for _, v in pairs(REM) do if v then remCount += 1 end end
    AddLogEntry("system", remCount .. " remotes found")
    local atmCount = 0
    for _ in pairs(ST.ATMRegistry) do atmCount += 1 end
    if atmCount > 0 then
        AddLogEntry("system", atmCount .. " ATMs registered in Damageables")
    end
    local toolCount = 0
    for _ in pairs(ST.ToolRegistry) do toolCount += 1 end
    AddLogEntry("system", toolCount .. " world tools registered")
end)

print(string.format(
    "[MAP] v%s ready | Executor: %s | Remotes found: %d | OneShot: %s",
    SCRIPT_VERSION,
    EXECUTOR_NAME,
    (function() local c=0; for _,v in pairs(REM) do if v then c+=1 end end; return c end)(),
    tostring(ONESHOT_HOOKED)
))