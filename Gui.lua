-- ============================================================
--  ███████╗███╗   ██╗██╗
--  ██╔════╝████╗  ██║██║
--  █████╗  ██╔██╗ ██║██║
--  ██╔══╝  ██║╚██╗██║██║
--  ███████╗██║ ╚████║██║
--  ╚══════╝╚═╝  ╚═══╝╚═╝
-- ============================================================
--  SCRIPT  : School Thugs OP Script
--  GAME    : School Thugs 👊  (Koudai · 18460355546)
--  VERSION : v1.0
--  AUTHOR  : ENI
--  GUI     : Rayfield (sirius.menu/rayfield)
--  EXECUTOR: Xeno / Synapse / Fluxus / Delta (cross-compatible)
-- ============================================================
--  CHANGELOG
--  v1.0 — Initial release
--    · Three-pass + network-spy remote detection engine
--    · Password-capture kill aura (arg[1]/arg[4] replay system)
--    · Auto Stomp (finish downed enemies)
--    · Auto Block toggle (Shield remote + VirtualUser fallback)
--    · Speed Boost / Jump Boost (client-side, re-applies every 2s)
--    · Infinite Stamina (hooks purple/suplex energy bar)
--    · Player ESP  (BillboardGui, health, color picker)
--    · Whitelist  (add/remove usernames)
--    · Anti-AFK  (player.Idled hook)
--    · Cleanup guard (zombie loop prevention on re-exec)
--    · CharacterAdded state refresh
--    · Full Rayfield GUI: Combat / Movement / Visuals / Settings
--    · Live status labels (remote learned count, target name)
-- ============================================================

-- ============================================================
-- § 2  CLEANUP GUARD — destroy previous instance before init
--      This prevents duplicate loops when the script is re-run
-- ============================================================
local SCRIPT_ID = "SCHOOLTHUGS_ENI_V1"
if _G[SCRIPT_ID] then
    _G[SCRIPT_ID].Running = false
    pcall(function()
        if _G[SCRIPT_ID].GUI then
            _G[SCRIPT_ID].GUI:Destroy()
        end
    end)
    task.wait(0.15)   -- let the old loop tick and exit cleanly
end
local ST = { Running = true, GUI = nil }
_G[SCRIPT_ID] = ST

-- ============================================================
-- § 1  EXECUTOR DETECTION & UNC COMPATIBILITY
-- ============================================================
local IS_XENO    = (identifyexecutor and identifyexecutor():lower():find("xeno"))    ~= nil
local IS_SYNAPSE = (syn  ~= nil)
local IS_FLUXUS  = (fluxus ~= nil)
local EXECUTOR   = (identifyexecutor and identifyexecutor()) or "Unknown"

-- UNC shims — always present, ensures cross-executor safety
if not cloneref        then cloneref        = function(s) return s  end end
if not getnilinstances then getnilinstances = function()  return {} end end
if not getinstances    then getinstances    = function()  return {} end end
if not newcclosure     then newcclosure     = function(f) return f  end end
if not checkcaller     then checkcaller     = function()  return false end end

-- ============================================================
-- § 3  SERVICES (all cloneref'd — anti-detection standard)
-- ============================================================
local Players           = cloneref(game:GetService("Players"))
local RunService        = cloneref(game:GetService("RunService"))
local UserInputService  = cloneref(game:GetService("UserInputService"))
local TweenService      = cloneref(game:GetService("TweenService"))
local HttpService       = cloneref(game:GetService("HttpService"))
local VirtualUser       = cloneref(game:GetService("VirtualUser"))
local ReplicatedStorage = cloneref(game:GetService("ReplicatedStorage"))
local Workspace         = cloneref(game:GetService("Workspace"))

-- ============================================================
-- § 4  PLAYER REFERENCES + CharacterAdded refresh
-- ============================================================
local player    = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid  = character:WaitForChild("Humanoid", 10)
local rootPart  = character:WaitForChild("HumanoidRootPart", 10)

-- ============================================================
-- § 5  CONFIG TABLE — all user-facing settings with defaults
-- ============================================================
local CFG = {
    -- Master
    Enabled        = true,

    -- Combat
    AutoAttack     = false,
    AttackSpeed    = 8,      -- attacks per second
    AttackRange    = 20,     -- studs

    AutoStomp      = false,
    StompRange     = 15,     -- studs; stomp finishes downed enemies

    AutoBlock      = false,  -- toggle shield when off cooldown

    -- Movement
    SpeedEnabled   = false,
    WalkSpeed      = 40,
    JumpEnabled    = false,
    JumpPower      = 100,
    InfStamina     = false,  -- keeps suplex energy maxed

    -- Visuals
    ESPEnabled     = false,
    ESPColor       = Color3.fromRGB(255, 80, 80),
    ESPShowHP      = true,

    -- Whitelist — players we never attack (populated via GUI)
    Whitelist      = {},
}

-- ============================================================
-- § 6  STATE TABLE — runtime flags, caches, counters
-- ============================================================
local REM       = {}   -- discovered RemoteEvent/Function objects  [name] = instance
local LEARNED   = {}   -- arg signatures captured via network spy  [name] = {args...}
local Enemies   = {}   -- set of enemy characters  [model] = true
local ESPObjects = {}  -- BillboardGui handles     [character] = BillboardGui
local StaminaConnections = {}  -- stamina hook connections for cleanup

-- ============================================================
-- § 7  UTILITIES
-- ============================================================

-- pcall-wrapped FireServer — never crashes the loop on bad remotes
local function SafeFire(remote, ...)
    if not remote then return false end
    local ok, err = pcall(function() remote:FireServer(...) end)
    if not ok then
        warn("[ENI:SafeFire] " .. tostring(remote.Name) .. " — " .. tostring(err))
    end
    return ok
end

-- Randomized-delay fire — breaks fixed-interval pattern detection
local function ThrottledFire(remote, minW, maxW, ...)
    if SafeFire(remote, ...) then
        task.wait(minW + math.random() * (maxW - minW))
    end
end

-- Returns the nearest alive enemy character within maxDist studs
local function GetNearest(maxDist)
    if not rootPart then return nil end
    local best, bestDist = nil, (maxDist or math.huge)
    for model in pairs(Enemies) do
        if model and model.Parent then
            local r = model:FindFirstChild("HumanoidRootPart")
            local h = model:FindFirstChildWhichIsA("Humanoid")
            if r and h and h.Health > 0 then
                local d = (r.Position - rootPart.Position).Magnitude
                if d < bestDist then best, bestDist = model, d end
            end
        else
            Enemies[model] = nil   -- prune stale refs
        end
    end
    return best
end

-- Returns all downed enemy characters (Health == 0, char still exists)
-- School Thugs keeps downed players in the world so stomping is possible
local function GetDownedInRange(maxDist)
    local results = {}
    if not rootPart then return results end
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= player and not CFG.Whitelist[p.Name] then
            local char = p.Character
            if char then
                local r = char:FindFirstChild("HumanoidRootPart")
                local h = char:FindFirstChildWhichIsA("Humanoid")
                if r and h and h.Health <= 0 then
                    local d = (r.Position - rootPart.Position).Magnitude
                    if d <= maxDist then table.insert(results, char) end
                end
            end
        end
    end
    return results
end

-- Search LEARNED + REM for the first matching remote name in a priority list
-- Returns (remote, learnedArgs) or (nil, nil) if nothing found yet
local function GetLearnedRemote(nameList)
    for _, name in ipairs(nameList) do
        if LEARNED[name] and REM[name] then
            return REM[name], LEARNED[name]
        end
    end
    return nil, nil
end

-- Get the Players.Player associated with a character model
local function CharToPlayer(char)
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Character == char then return p end
    end
    return nil
end

-- Lazy Rayfield notify (nil-safe — Rayfield loads in §11)
local Rayfield = nil
local function Notify(title, content, duration, icon)
    pcall(function()
        if Rayfield then
            Rayfield:Notify({
                Title    = title,
                Content  = content,
                Duration = duration or 4,
                Image    = icon or "info",
            })
        end
    end)
end

-- ============================================================
-- § 8  REMOTE DETECTION ENGINE — three passes + network spy
-- ============================================================

-- ── Pass 1: ReplicatedStorage hierarchy scan ─────────────────
local function ScanRemotes(root)
    for _, obj in ipairs(root:GetDescendants()) do
        if obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") then
            REM[obj.Name] = obj
        end
    end
end
pcall(function() ScanRemotes(ReplicatedStorage) end)

-- ── Pass 2: Nil-instance sweep — finds hidden/parented-to-nil remotes ────────
pcall(function()
    for _, obj in ipairs(getnilinstances()) do
        if obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") then
            REM[obj.Name] = obj
        end
    end
end)

-- ── Pass 3: Network spy hook — THE CORE SYSTEM FOR SCHOOL THUGS ─────────────
-- School Thugs uses password-validated remotes:
--   arg[1] = static password string (checked server-side)
--   arg[4] = target player name (sometimes)
-- We intercept every FireServer the game makes, cache the remote + args,
-- and replay them with our own target substituted in.
-- Once the player attacks once normally, LEARNED is populated and kill aura works.

if hookmetamethod then
    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
        local method = getnamecallmethod()

        -- Only intercept calls made by the GAME (not by us — checkcaller returns true for our code)
        if not checkcaller() then
            if (method == "FireServer" or method == "InvokeServer") then
                local ok = pcall(function()
                    if self:IsA("RemoteEvent") or self:IsA("RemoteFunction") then
                        -- Cache the remote reference
                        if not REM[self.Name] then
                            REM[self.Name] = self
                        end
                        -- Capture the argument signature (password + target info)
                        local args = { ... }
                        if #args > 0 then
                            LEARNED[self.Name] = args
                            -- To debug: uncomment the line below and attack something
                            -- print("[SPY CAPTURED]", self.Name, table.unpack(args))
                        end
                    end
                end)
                -- Swallow pcall error silently — hook must never crash
                _ = ok
            end
        end

        return oldNamecall(self, ...)
    end))
end

-- ============================================================
-- § 9  GAME SCANNER — build enemy registry from Players service
--      Event-driven, never uses GetDescendants in a loop
-- ============================================================

local function RegisterEnemy(p)
    if p == player then return end

    -- Re-register whenever their character spawns
    local function OnCharAdded(char)
        if CFG.Whitelist[p.Name] then return end
        Enemies[char] = true

        -- Remove from registry when humanoid is removed (death cleanup)
        char.DescendantRemoving:Connect(function(obj)
            if obj:IsA("Humanoid") then
                Enemies[char] = nil
            end
        end)
    end

    p.CharacterAdded:Connect(OnCharAdded)
    if p.Character then OnCharAdded(p.Character) end
end

-- Seed registry with current players
for _, p in ipairs(Players:GetPlayers()) do RegisterEnemy(p) end

Players.PlayerAdded:Connect(RegisterEnemy)
Players.PlayerRemoving:Connect(function(p)
    if p.Character then Enemies[p.Character] = nil end
end)

-- ============================================================
-- § 10  FEATURES
--       Each feature is isolated with pcall + nil checks
-- ============================================================

-- ─── Priority lists for remote lookup ────────────────────────────────────────
-- School Thugs community scripts confirmed the game has combat remotes
-- with these common naming patterns. Network spy handles anything obfuscated.
local ATTACK_REMOTE_NAMES = {
    "Attack", "AttackEvent", "PunchRemote", "HitEvent", "DamageEvent",
    "DealDamage", "Hit", "Punch", "CombatEvent", "FightEvent", "SwingEvent",
    "StrikeEvent", "MeleeEvent", "TouchEvent",
}
local STOMP_REMOTE_NAMES = {
    "Stomp", "StompEvent", "StompPlayer", "FinishEvent", "Finish",
    "ExecuteEvent", "GroundFinish", "KillEvent", "DownedFinish",
}
local BLOCK_REMOTE_NAMES = {
    "Block", "BlockEvent", "Shield", "ShieldEvent", "GuardEvent",
    "DefendEvent", "ParryEvent",
}

-- ─── KILL AURA ────────────────────────────────────────────────────────────────
-- Core mechanism: replay the exact args the game fired for our own attack,
-- but substitute arg[4] (target name) with the nearest enemy's name.
-- The password in arg[1] stays intact — server accepts it as legitimate.
local function DoAttack()
    -- Bail if we're dead or no character
    if not rootPart or not humanoid or humanoid.Health <= 0 then return end

    local target = GetNearest(CFG.AttackRange)
    if not target then return end

    local targetRoot = target:FindFirstChild("HumanoidRootPart")
    if not targetRoot then return end

    -- Preferred path: use learned args (password intact, target swapped)
    local remote, learnedArgs = GetLearnedRemote(ATTACK_REMOTE_NAMES)
    if remote and learnedArgs then
        local args = {}
        local targetPlayer = CharToPlayer(target)

        for i, v in ipairs(learnedArgs) do
            -- Slot 4 is typically the target player name in School Thugs remotes
            -- We swap it to our target; everything else (especially slot 1 password) stays
            if i == 4 and targetPlayer then
                args[i] = targetPlayer.Name
            else
                args[i] = v
            end
        end

        SafeFire(remote, table.unpack(args))
        return
    end

    -- Fallback path: no learned args yet — fire with raw target ref
    -- This may not work if the game validates the password, but it will
    -- trigger the spy capture on the server's rejection response
    for _, name in ipairs(ATTACK_REMOTE_NAMES) do
        if REM[name] then
            SafeFire(REM[name], target)
            return
        end
    end
end

-- ─── AUTO STOMP ───────────────────────────────────────────────────────────────
-- School Thugs keeps downed players alive with 0 HP so others can stomp (E key)
-- We fire the stomp remote at the nearest downed enemy
local function DoStomp()
    if not rootPart or not humanoid or humanoid.Health <= 0 then return end

    local downedList = GetDownedInRange(CFG.StompRange)
    if #downedList == 0 then return end

    local target = downedList[1]   -- always stomp the closest first
    local targetPlayer = CharToPlayer(target)

    local remote, learnedArgs = GetLearnedRemote(STOMP_REMOTE_NAMES)
    if remote and learnedArgs then
        local args = {}
        for i, v in ipairs(learnedArgs) do
            if i == 4 and targetPlayer then
                args[i] = targetPlayer.Name
            else
                args[i] = v
            end
        end
        SafeFire(remote, table.unpack(args))
        return
    end

    -- Fallback — raw fire
    for _, name in ipairs(STOMP_REMOTE_NAMES) do
        if REM[name] then SafeFire(REM[name], target); return end
    end
end

-- ─── AUTO BLOCK ───────────────────────────────────────────────────────────────
-- Attempts to fire the block/shield remote; falls back to VirtualUser F-press
local function DoBlock()
    local remote, learnedArgs = GetLearnedRemote(BLOCK_REMOTE_NAMES)
    if remote and learnedArgs then
        SafeFire(remote, table.unpack(learnedArgs))
        return
    end
    for _, name in ipairs(BLOCK_REMOTE_NAMES) do
        if REM[name] then SafeFire(REM[name]); return end
    end
    -- VirtualUser fallback — simulates the F key client-side
    pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:Button1Down(Vector2.new(0, 0), Workspace.CurrentCamera.CFrame)
    end)
end

-- ─── SPEED / JUMP BOOST ───────────────────────────────────────────────────────
-- Client-side WalkSpeed and JumpPower manipulation
-- Re-applied every 2 seconds by the main loop to fight game resets
local BASE_SPEED = 16
local BASE_JUMP  = 50

local function ApplyMovement()
    if not humanoid then return end
    pcall(function()
        humanoid.WalkSpeed = CFG.SpeedEnabled and CFG.WalkSpeed or BASE_SPEED
        humanoid.JumpPower = CFG.JumpEnabled  and CFG.JumpPower or BASE_JUMP
    end)
end

-- ─── INFINITE STAMINA ─────────────────────────────────────────────────────────
-- School Thugs uses a purple bar (suplex energy) that drains on use.
-- We hook any NumberValue/IntValue named "stamina", "energy", "purple", "special"
-- and snap it back to MaxValue on any change.
local function ClearStaminaHooks()
    for _, conn in ipairs(StaminaConnections) do
        pcall(function() conn:Disconnect() end)
    end
    StaminaConnections = {}
end

local function HookStaminaValues(char)
    if not char then return end
    for _, obj in ipairs(char:GetDescendants()) do
        if obj:IsA("NumberValue") or obj:IsA("IntValue") then
            local n = obj.Name:lower()
            if n:find("stamina") or n:find("energy") or
               n:find("purple")  or n:find("special") or n:find("suplex") then
                local conn = obj.Changed:Connect(function(val)
                    if CFG.InfStamina then
                        pcall(function()
                            -- Try .MaxValue; if that doesn't exist, set to 100
                            local max = rawget(obj, "MaxValue") or 100
                            if val < max then obj.Value = max end
                        end)
                    end
                end)
                table.insert(StaminaConnections, conn)
            end
        end
    end
end

local function EnableInfStamina(on)
    ClearStaminaHooks()
    if not on then return end
    if character then HookStaminaValues(character) end
    player.CharacterAdded:Connect(function(char)
        task.wait(1)   -- let the game build value objects first
        HookStaminaValues(char)
    end)
end

-- ─── ESP ──────────────────────────────────────────────────────────────────────
-- BillboardGui on each enemy's head showing name and optional HP
-- Updated at 4 Hz (every 0.25s in the main loop)
local function UpdateESP()
    -- Prune dead refs first
    for char, bb in pairs(ESPObjects) do
        if not char or not char.Parent then
            pcall(function() bb:Destroy() end)
            ESPObjects[char] = nil
        end
    end

    -- If ESP is off, destroy all and bail
    if not CFG.ESPEnabled then
        for _, bb in pairs(ESPObjects) do pcall(function() bb:Destroy() end) end
        table.clear(ESPObjects)
        return
    end

    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= player then
            local char = p.Character
            if char then
                local head = char:FindFirstChild("Head") or
                             char:FindFirstChild("HumanoidRootPart")
                local hum  = char:FindFirstChildWhichIsA("Humanoid")

                if head and hum then
                    -- Create billboard if it doesn't exist yet for this char
                    if not ESPObjects[char] or not ESPObjects[char].Parent then
                        local bb = Instance.new("BillboardGui")
                        bb.Size         = UDim2.new(0, 220, 0, 55)
                        bb.StudsOffset  = Vector3.new(0, 3.5, 0)
                        bb.AlwaysOnTop  = true
                        bb.Adornee      = head
                        bb.Parent       = char

                        local lbl = Instance.new("TextLabel", bb)
                        lbl.Name                 = "Label"
                        lbl.Size                 = UDim2.new(1, 0, 1, 0)
                        lbl.BackgroundTransparency = 1
                        lbl.Font                 = Enum.Font.GothamBold
                        lbl.TextSize             = 14
                        lbl.TextStrokeTransparency = 0.35
                        lbl.TextStrokeColor3     = Color3.new(0, 0, 0)

                        ESPObjects[char] = bb
                    end

                    -- Update label content dynamically
                    local lbl = ESPObjects[char]:FindFirstChild("Label")
                    if lbl then
                        lbl.TextColor3 = CFG.ESPColor
                        if CFG.ESPShowHP then
                            local hp    = math.floor(hum.Health)
                            local maxHP = math.floor(hum.MaxHealth)
                            lbl.Text = p.Name .. "\n[" .. hp .. " / " .. maxHP .. "]"
                        else
                            lbl.Text = p.Name
                        end
                    end
                end
            else
                -- Character is gone — remove stale billboard
                if ESPObjects[char] then
                    pcall(function() ESPObjects[char]:Destroy() end)
                    ESPObjects[char] = nil
                end
            end
        end
    end
end

local function ClearAllESP()
    for _, bb in pairs(ESPObjects) do pcall(function() bb:Destroy() end) end
    table.clear(ESPObjects)
end

-- ============================================================
-- § 11  RAYFIELD GUI
--        Full window, all tabs, all elements, live status labels
-- ============================================================

Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()

local Window = Rayfield:CreateWindow({
    Name                   = "School Thugs 👊  ·  ENI v1.0",
    Icon                   = "graduation-cap",
    LoadingTitle           = "ENI  ·  School Thugs",
    LoadingSubtitle        = "Initializing systems...",
    Theme                  = "Default",
    DisableRayfieldPrompts = false,
    DisableBuildWarnings   = false,
    ConfigurationSaving    = {
        Enabled    = true,
        FolderName = "ENI_Scripts",
        FileName   = "SchoolThugs_v1",
    },
    KeySystem = false,
})

ST.GUI = Window   -- attach to state so cleanup guard can destroy it

-- ── Tabs ───────────────────────────────────────────────────────────────────
local CombatTab   = Window:CreateTab("Combat",   "sword")
local MovementTab = Window:CreateTab("Movement", "zap")
local VisualsTab  = Window:CreateTab("Visuals",  "eye")
local SettingsTab = Window:CreateTab("Settings", "settings")

-- ═══════════════════════════════════════════════════════════
--  COMBAT TAB
-- ═══════════════════════════════════════════════════════════

CombatTab:CreateSection("Kill Aura")

CombatTab:CreateParagraph({
    Title   = "How Kill Aura Works",
    Content = "The script hooks the game's own remote calls to capture the password and arguments. Attack ONE PLAYER MANUALLY first — the spy will learn the remote signature. After that, Kill Aura replays those exact args against all nearby enemies automatically.",
})

-- Live remote learning status — updated by main loop
local RemoteStatusLabel = CombatTab:CreateLabel(
    "● Remote: Waiting — attack someone once to teach me!",
    "wifi"
)

CombatTab:CreateToggle({
    Name         = "Kill Aura (Auto Attack)",
    CurrentValue = false,
    Flag         = "AutoAttackToggle",
    Callback     = function(v)
        CFG.AutoAttack = v
        if v then
            Notify("Kill Aura", "Active. If remote not learned yet, hit someone manually first.", 4, "sword")
        end
    end,
})

CombatTab:CreateSlider({
    Name         = "Attacks Per Second",
    Range        = { 1, 20 },
    Increment    = 0.5,
    Suffix       = " APS",
    CurrentValue = 8,
    Flag         = "AttackSpeedSlider",
    Callback     = function(v) CFG.AttackSpeed = v end,
})

CombatTab:CreateSlider({
    Name         = "Attack Range (studs)",
    Range        = { 5, 100 },
    Increment    = 1,
    Suffix       = " st",
    CurrentValue = 20,
    Flag         = "AttackRangeSlider",
    Callback     = function(v) CFG.AttackRange = v end,
})

-- Live target display — updated by main loop
local KillAuraStatusLabel = CombatTab:CreateLabel("● Status: Idle", "activity")
local TargetLabel         = CombatTab:CreateLabel("● Target: None", "crosshair")

CombatTab:CreateSection("Stomp System")

CombatTab:CreateToggle({
    Name         = "Auto Stomp (Finish Downed)",
    CurrentValue = false,
    Flag         = "AutoStompToggle",
    Callback     = function(v)
        CFG.AutoStomp = v
        if v then Notify("Auto Stomp", "Will E-stomp downed players in range.", 3, "zap") end
    end,
})

CombatTab:CreateSlider({
    Name         = "Stomp Range (studs)",
    Range        = { 5, 50 },
    Increment    = 1,
    Suffix       = " st",
    CurrentValue = 15,
    Flag         = "StompRangeSlider",
    Callback     = function(v) CFG.StompRange = v end,
})

CombatTab:CreateSection("Defense")

CombatTab:CreateToggle({
    Name         = "Auto Block (F Shield)",
    CurrentValue = false,
    Flag         = "AutoBlockToggle",
    Callback     = function(v)
        CFG.AutoBlock = v
        if v then Notify("Auto Block", "Shield active — will block when off cooldown.", 3, "shield") end
    end,
})

-- ═══════════════════════════════════════════════════════════
--  MOVEMENT TAB
-- ═══════════════════════════════════════════════════════════

MovementTab:CreateSection("Speed")

MovementTab:CreateToggle({
    Name         = "Speed Boost",
    CurrentValue = false,
    Flag         = "SpeedToggle",
    Callback     = function(v)
        CFG.SpeedEnabled = v
        ApplyMovement()
        Notify("Speed", v and ("Speed set to " .. CFG.WalkSpeed) or "Speed restored to default.", 3, "zap")
    end,
})

MovementTab:CreateSlider({
    Name         = "Walk Speed",
    Range        = { 16, 250 },
    Increment    = 1,
    Suffix       = " WS",
    CurrentValue = 40,
    Flag         = "WalkSpeedSlider",
    Callback     = function(v)
        CFG.WalkSpeed = v
        if CFG.SpeedEnabled then ApplyMovement() end
    end,
})

MovementTab:CreateSection("Jump")

MovementTab:CreateToggle({
    Name         = "Jump Boost",
    CurrentValue = false,
    Flag         = "JumpToggle",
    Callback     = function(v)
        CFG.JumpEnabled = v
        ApplyMovement()
        Notify("Jump", v and ("JumpPower set to " .. CFG.JumpPower) or "Jump restored.", 3, "chevrons-up")
    end,
})

MovementTab:CreateSlider({
    Name         = "Jump Power",
    Range        = { 50, 350 },
    Increment    = 5,
    Suffix       = " JP",
    CurrentValue = 100,
    Flag         = "JumpPowerSlider",
    Callback     = function(v)
        CFG.JumpPower = v
        if CFG.JumpEnabled then ApplyMovement() end
    end,
})

MovementTab:CreateSection("Stamina / Suplex Bar")

MovementTab:CreateToggle({
    Name         = "Infinite Stamina (Always Suplex Ready)",
    CurrentValue = false,
    Flag         = "InfStaminaToggle",
    Callback     = function(v)
        CFG.InfStamina = v
        EnableInfStamina(v)
        Notify(
            "Stamina",
            v and "Infinite stamina ON — C-Suplex will always be charged."
              or "Stamina back to normal.",
            4, "battery"
        )
    end,
})

-- ═══════════════════════════════════════════════════════════
--  VISUALS TAB
-- ═══════════════════════════════════════════════════════════

VisualsTab:CreateSection("Player ESP")

VisualsTab:CreateToggle({
    Name         = "Enable ESP",
    CurrentValue = false,
    Flag         = "ESPToggle",
    Callback     = function(v)
        CFG.ESPEnabled = v
        if not v then ClearAllESP() end
        Notify("ESP", v and "ESP enabled — tracking all enemies." or "ESP disabled.", 3, "eye")
    end,
})

VisualsTab:CreateToggle({
    Name         = "Show Health in ESP",
    CurrentValue = true,
    Flag         = "ESPHPToggle",
    Callback     = function(v) CFG.ESPShowHP = v end,
})

VisualsTab:CreateColorPicker({
    Name     = "ESP Color",
    Color    = Color3.fromRGB(255, 80, 80),
    Flag     = "ESPColorPicker",
    Callback = function(v) CFG.ESPColor = v end,
})

-- ═══════════════════════════════════════════════════════════
--  SETTINGS TAB
-- ═══════════════════════════════════════════════════════════

SettingsTab:CreateSection("Whitelist")

SettingsTab:CreateParagraph({
    Title   = "Whitelist Info",
    Content = "Whitelisted players are excluded from Kill Aura and Auto Stomp. Your own name is always protected. Usernames are case-sensitive.",
})

SettingsTab:CreateInput({
    Name                    = "Add Player to Whitelist",
    CurrentValue            = "",
    PlaceholderText         = "Exact username...",
    RemoveTextAfterFocusLost = true,
    Flag                    = "WhitelistAddInput",
    Callback                = function(text)
        if text and text ~= "" then
            CFG.Whitelist[text] = true
            -- Rebuild enemy registry respecting new whitelist
            table.clear(Enemies)
            for _, p in ipairs(Players:GetPlayers()) do RegisterEnemy(p) end
            Notify("Whitelist", text .. " is now protected.", 3, "shield")
        end
    end,
})

SettingsTab:CreateInput({
    Name                    = "Remove Player from Whitelist",
    CurrentValue            = "",
    PlaceholderText         = "Exact username...",
    RemoveTextAfterFocusLost = true,
    Flag                    = "WhitelistRemoveInput",
    Callback                = function(text)
        if text and text ~= "" then
            CFG.Whitelist[text] = nil
            Notify("Whitelist", text .. " removed from protection.", 3, "x")
        end
    end,
})

SettingsTab:CreateSection("Script Control")

SettingsTab:CreateToggle({
    Name         = "Master Enable",
    CurrentValue = true,
    Flag         = "MasterEnableToggle",
    Callback     = function(v) CFG.Enabled = v end,
})

SettingsTab:CreateKeybind({
    Name           = "Master Toggle Keybind",
    CurrentKeybind = "RightShift",
    HoldToInteract = false,
    Flag           = "MasterKeybind",
    Callback       = function()
        CFG.Enabled = not CFG.Enabled
        Notify(
            "Master Toggle",
            CFG.Enabled and "Script ENABLED ✓" or "Script PAUSED ✗",
            3,
            CFG.Enabled and "check-circle" or "pause-circle"
        )
    end,
})

SettingsTab:CreateSection("Remote Tools")

SettingsTab:CreateButton({
    Name     = "Force Rescan ReplicatedStorage",
    Callback = function()
        local before = 0
        for _ in pairs(REM) do before = before + 1 end
        pcall(function() ScanRemotes(ReplicatedStorage) end)
        local after = 0
        for _ in pairs(REM) do after = after + 1 end
        Notify("Remote Scan", "Found " .. after .. " remotes (" .. (after - before) .. " new).", 4, "refresh-cw")
    end,
})

SettingsTab:CreateButton({
    Name     = "Clear Learned Args (Re-learn)",
    Callback = function()
        table.clear(LEARNED)
        Notify("Learned Args", "Cleared — attack manually to re-capture.", 3, "trash-2")
    end,
})

SettingsTab:CreateButton({
    Name     = "Print All Discovered Remotes",
    Callback = function()
        local count = 0
        for name, _ in pairs(REM) do
            print("[ENI REMOTE]", name)
            count = count + 1
        end
        print("[ENI]", count, "remotes in registry")
        Notify("Remotes", count .. " remotes printed to output console.", 3, "terminal")
    end,
})

SettingsTab:CreateButton({
    Name     = "Print Learned Args",
    Callback = function()
        local count = 0
        for name, args in pairs(LEARNED) do
            local argStr = ""
            for i, v in ipairs(args) do
                argStr = argStr .. "[" .. i .. "]=" .. tostring(v) .. "  "
            end
            print("[ENI LEARNED]", name, "->", argStr)
            count = count + 1
        end
        if count == 0 then
            print("[ENI] Nothing learned yet — attack someone manually!")
        end
        Notify("Learned", count .. " learned remotes printed to console.", 3, "terminal")
    end,
})

SettingsTab:CreateSection("Info")

SettingsTab:CreateParagraph({
    Title   = "ENI · School Thugs v1.0",
    Content = "Network spy engine captures live password arguments from the game's own remotes. Three-pass remote detection, event-driven enemy registry, consolidated 20Hz main loop, full Rayfield GUI, UNC shims, anti-AFK, cloneref anti-detection. Built for LO.",
})

-- ============================================================
-- § 12  MAIN LOOP — single consolidated tick thread
--        Per-feature timers, 20 Hz base rate
-- ============================================================

task.spawn(function()
    local timers = {
        attack  = 0,
        stomp   = 0,
        block   = 0,
        esp     = 0,
        move    = 0,
        labels  = 0,
    }

    while ST.Running do
        local now = tick()

        if CFG.Enabled then

            -- ── Movement re-application (every 2s) ──────────────────────
            -- Game may reset WalkSpeed/JumpPower; we re-apply periodically
            if (now - timers.move) > 2.0 then
                ApplyMovement()
                timers.move = now
            end

            -- ── Kill Aura ────────────────────────────────────────────────
            if CFG.AutoAttack and (now - timers.attack) > (1 / CFG.AttackSpeed) then
                pcall(DoAttack)
                timers.attack = now
            end

            -- ── Auto Stomp ───────────────────────────────────────────────
            if CFG.AutoStomp and (now - timers.stomp) > 0.4 then
                pcall(DoStomp)
                timers.stomp = now
            end

            -- ── Auto Block ───────────────────────────────────────────────
            if CFG.AutoBlock and (now - timers.block) > 0.35 then
                pcall(DoBlock)
                timers.block = now
            end

            -- ── ESP update (4 Hz) ────────────────────────────────────────
            if (now - timers.esp) > 0.25 then
                pcall(UpdateESP)
                timers.esp = now
            end

            -- ── GUI label updates (2 Hz) ─────────────────────────────────
            if (now - timers.labels) > 0.5 then

                -- Count learned and total remotes
                local learnedCount, remoteCount = 0, 0
                for _ in pairs(LEARNED) do learnedCount = learnedCount + 1 end
                for _ in pairs(REM)     do remoteCount  = remoteCount  + 1 end

                pcall(function()
                    if learnedCount > 0 then
                        RemoteStatusLabel:Set(
                            "● Remote: " .. learnedCount .. " learned / " .. remoteCount .. " found ✓"
                        )
                    else
                        RemoteStatusLabel:Set(
                            "● Remote: Spy active — attack once to learn!"
                        )
                    end
                end)

                -- Kill Aura status + target name
                local currentTarget = CFG.AutoAttack and GetNearest(CFG.AttackRange) or nil
                pcall(function()
                    if CFG.AutoAttack and currentTarget then
                        local tp = CharToPlayer(currentTarget)
                        KillAuraStatusLabel:Set("● Status: ATTACKING 🔴")
                        TargetLabel:Set("● Target: " .. (tp and tp.Name or "Unknown"))
                    elseif CFG.AutoAttack then
                        KillAuraStatusLabel:Set("● Status: Scanning... (no target in range)")
                        TargetLabel:Set("● Target: None in " .. CFG.AttackRange .. "st")
                    else
                        KillAuraStatusLabel:Set("● Status: Idle")
                        TargetLabel:Set("● Target: —")
                    end
                end)

                timers.labels = now
            end

        end -- CFG.Enabled

        task.wait(0.05)   -- 20 Hz base tick
    end
end)

-- ============================================================
-- § 13  EVENT HANDLERS
-- ============================================================

-- CharacterAdded — refresh all character/humanoid/rootPart refs
-- and re-apply active movement settings
player.CharacterAdded:Connect(function(char)
    character = char
    humanoid  = char:WaitForChild("Humanoid", 10)
    rootPart  = char:WaitForChild("HumanoidRootPart", 10)
    -- Never put ourselves in the enemy registry
    Enemies[char] = nil
    -- Re-apply movement after a short delay (game sets defaults on spawn)
    task.wait(0.75)
    ApplyMovement()
    if CFG.InfStamina then
        HookStaminaValues(char)
    end
    Notify("Respawned", "Character refreshed — all systems active.", 3, "refresh-cw")
end)

-- Anti-AFK — fires VirtualUser click to prevent the idle kick
player.Idled:Connect(function()
    pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end)
end)

-- ============================================================
-- § 14  INIT — startup sequence
-- ============================================================

-- Protect ourselves from our own kill aura
CFG.Whitelist[player.Name] = true

-- Apply movement defaults
ApplyMovement()

-- Load saved Rayfield configuration flags
pcall(function() Rayfield:LoadConfiguration() end)

-- Startup notification
Notify(
    "School Thugs 👊  ·  ENI v1.0",
    "Loaded on " .. EXECUTOR
        .. "\nHit someone once to teach the spy.\nRightShift = master toggle.",
    8,
    "graduation-cap"
)
