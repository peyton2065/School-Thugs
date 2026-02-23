--[[
    ╔═══════════════════════════════════════════════════╗
    ║            MASS ATTACK PRO  v2.2                  ║
    ║       Production Combat Enhancement Suite         ║
    ╠═══════════════════════════════════════════════════╣
    ║   Insert      →  Toggle GUI visibility            ║
    ║   RightShift  →  Toggle script on / off           ║
    ╚═══════════════════════════════════════════════════╝
]]

----------------------------------------------------------------
-- 1. CLEANUP PREVIOUS INSTANCE
----------------------------------------------------------------
if _G._MassAttackPro then
    pcall(function()
        _G._MassAttackPro.Running = false
        for _, c in ipairs(_G._MassAttackPro.Connections or {}) do
            pcall(function() c:Disconnect() end)
        end
        local old = game:GetService("Players").LocalPlayer
            :FindFirstChild("PlayerGui")
        if old then
            local g = old:FindFirstChild("MassAttackPro")
            if g then g:Destroy() end
        end
    end)
    _G._MassAttackPro = nil
    task.wait(0.15)
end

----------------------------------------------------------------
-- 2. SERVICES
----------------------------------------------------------------
local Players      = game:GetService("Players")
local RepStorage   = game:GetService("ReplicatedStorage")
local UIS          = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

----------------------------------------------------------------
-- 3. PLAYER REFERENCES
----------------------------------------------------------------
local plr      = Players.LocalPlayer
local char     = plr.Character or plr.CharacterAdded:Wait()
local rootPart = char:WaitForChild("HumanoidRootPart", 10)
local humanoid = char:WaitForChild("Humanoid", 10)

----------------------------------------------------------------
-- 4. CONFIGURATION
----------------------------------------------------------------
local CFG = {
    Enabled              = false,

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

    UsePunch             = true,
    UseSuplex            = true,
    UseHeavyHit          = true,

    UseAutoStomp         = true,
    StompRange           = 15,
    StompCooldown        = 0.5,

    UseAutoGuard         = true,
    GuardCooldown        = 0.10,
    GuardDropForAttack   = true,
    GuardReactivateDelay = 0.04,
    HealthPollInterval   = 0.05,
    GuardActivationRange = 50,

    -- ▸ NEW: Kill All
    KillAllActive        = false,
    KillAllTimeout       = 8,
    KillAllTeleportDelay = 0.25,
    KillAllReteleportDist = 12,

    GuiToggleKey         = Enum.KeyCode.Insert,
    ScriptToggleKey      = Enum.KeyCode.RightShift,

    Debug                = false,
}

----------------------------------------------------------------
-- 5. SHARED STATE
----------------------------------------------------------------
local ST = {
    Running          = true,
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

    -- ▸ NEW: Kill All state
    KillAllRunning   = false,
    KillAllTarget    = "",
    KillAllProgress  = "",
    KillAllKills     = 0,
}

-- ▸ FIX: Proximity cache to prevent lag from repeated scans
local _nearbyCache = {
    result    = false,
    lastCheck = 0,
    interval  = 0.5,
}

_G._MassAttackPro = ST

local function Conn(signal, fn)
    local c = signal:Connect(fn)
    table.insert(ST.Connections, c)
    return c
end

local function Log(...)
    if CFG.Debug then print("[MAP]", ...) end
end

----------------------------------------------------------------
-- 6. COLOR PALETTE
----------------------------------------------------------------
local CLR = {
    bg        = Color3.fromRGB(18, 18, 28),
    header    = Color3.fromRGB(25, 25, 40),
    card      = Color3.fromRGB(26, 26, 40),
    accent    = Color3.fromRGB(105, 65, 255),
    text      = Color3.fromRGB(235, 235, 245),
    textDim   = Color3.fromRGB(140, 140, 165),
    green     = Color3.fromRGB(45, 200, 95),
    red       = Color3.fromRGB(245, 65, 65),
    orange    = Color3.fromRGB(245, 175, 50),
    yellow    = Color3.fromRGB(245, 220, 50),
    cyan      = Color3.fromRGB(50, 200, 245),
    toggleOn  = Color3.fromRGB(45, 200, 95),
    toggleOff = Color3.fromRGB(70, 70, 90),
    border    = Color3.fromRGB(45, 45, 65),
    sliderBg  = Color3.fromRGB(35, 35, 55),
}

----------------------------------------------------------------
-- 7. REMOTE DETECTION
----------------------------------------------------------------
local function FindRemote(name)
    local folder = RepStorage:FindFirstChild("MainEvents")
    if folder then
        local r = folder:FindFirstChild(name)
        if r then return r end
    end
    local r = RepStorage:FindFirstChild(name, true)
    if r then return r end
    pcall(function()
        if type(getnilinstances) == "function" then
            for _, v in ipairs(getnilinstances()) do
                if v:IsA("RemoteEvent") and v.Name == name then
                    r = v
                end
            end
        end
    end)
    return r
end

local REM = {
    Punch    = FindRemote("PUNCHEVENT"),
    Suplex   = FindRemote("SUPLEXEVENT"),
    HeavyHit = FindRemote("HEAVYHIT"),
    Block    = FindRemote("BLOCKEVENT"),
    Stomp    = FindRemote("STOMPEVENT"),
}

if not REM.Punch    then CFG.UsePunch     = false end
if not REM.Suplex   then CFG.UseSuplex    = false end
if not REM.HeavyHit then CFG.UseHeavyHit  = false end
if not REM.Block    then CFG.UseAutoGuard  = false end
if not REM.Stomp    then CFG.UseAutoStomp  = false end

local HAS_ATTACK = REM.Punch or REM.Suplex or REM.HeavyHit

----------------------------------------------------------------
-- 8. CORE FUNCTIONS
----------------------------------------------------------------

-- 8a  Guard ---------------------------------------------------
local function SetGuard(state)
    if not CFG.UseAutoGuard or not REM.Block then return end
    local now = tick()
    if now - ST.LastGuardTime < CFG.GuardCooldown then return end
    if state == ST.GuardActive then return end

    local ok = pcall(function()
        REM.Block:FireServer(state)
    end)
    if ok then
        ST.GuardActive = state
        ST.LastGuardTime = now
        Log(state and "Guard ON" or "Guard OFF")
    end
end

-- 8b  Validation ----------------------------------------------
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

-- 8c  Target refresh ------------------------------------------
local function RefreshTargets()
    local list = {}
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
    Log("Targets refreshed:", #list)
end

-- 8d  Attack --------------------------------------------------
local function Attack(target)
    if not target or not target.Parent then return end
    local part = target:FindFirstChild(CFG.TargetPart)
              or target:FindFirstChild("UpperTorso")
              or target:FindFirstChild("HumanoidRootPart")
    if not part then return end

    if CFG.UsePunch and REM.Punch then
        pcall(function() REM.Punch:FireServer(1, target, 50, part) end)
    end
    if CFG.UseSuplex and REM.Suplex then
        pcall(function() REM.Suplex:FireServer(1, target, 50, part) end)
    end
    if CFG.UseHeavyHit and REM.HeavyHit then
        pcall(function() REM.HeavyHit:FireServer(1, target, 50, part) end)
    end

    ST.TotalAttacks += 1
end

-- 8e  ▸ FIXED: Proximity check with caching ------------------
--     No longer scans workspace:GetDescendants() every call.
--     Uses ST.TargetCache for NPCs instead. Results cached 0.5s.
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

    -- Fast check: players only (small list)
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

    -- NPC check: use already-cached target list (no workspace scan)
    if CFG.TargetNPCs then
        for _, model in ipairs(ST.TargetCache) do
            if model and model.Parent then
                if not Players:GetPlayerFromCharacter(model) then
                    local r = model:FindFirstChild("HumanoidRootPart")
                    if r and (pos - r.Position).Magnitude <= range then
                        _nearbyCache.result = true
                        return true
                    end
                end
            end
        end
    end

    _nearbyCache.result = false
    return false
end

-- Force-refresh the nearby cache (used after teleporting)
local function InvalidateNearbyCache()
    _nearbyCache.lastCheck = 0
end

-- 8f  Downed player detection ---------------------------------
local function IsPlayerDown(character)
    if not character or not character.Parent then return false end
    local hum = character:FindFirstChildOfClass("Humanoid")
    if not hum then return false end
    if hum.Health <= 0 then return false end

    local state = hum:GetState()
    if state == Enum.HumanoidStateType.Physics
    or state == Enum.HumanoidStateType.FallingDown
    or state == Enum.HumanoidStateType.PlatformStanding then
        return true
    end

    if hum.PlatformStand == true then return true end

    for _, child in ipairs(character:GetChildren()) do
        if child:IsA("BoolValue") then
            local name = child.Name:lower()
            if (name:find("ragdoll") or name:find("knocked")
                or name:find("down") or name:find("stun")) then
                if child.Value == true then return true end
            end
        end
        if child:IsA("StringValue") then
            local val = child.Value:lower()
            if val == "down" or val == "knocked" or val == "ragdoll" then
                return true
            end
        end
    end

    for _, attr in ipairs({
        "Ragdolled", "KnockedDown", "Downed", "Stunned",
        "IsDown", "Ragdoll", "IsRagdoll", "KO",
    }) do
        local val = character:GetAttribute(attr)
        if val == true then return true end
    end

    return false
end

-- 8g  Fire stomp ----------------------------------------------
local function TryStomp()
    if not CFG.UseAutoStomp or not REM.Stomp then return end
    local now = tick()
    if now - ST.LastStompTime < CFG.StompCooldown then return end
    if not rootPart or not rootPart.Parent then return end

    local pos = rootPart.Position
    local foundDown = false

    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= plr and p.Character then
            local r = p.Character:FindFirstChild("HumanoidRootPart")
            if r and (pos - r.Position).Magnitude <= CFG.StompRange then
                if IsPlayerDown(p.Character) then
                    foundDown = true
                    break
                end
            end
        end
    end

    if foundDown then
        local ok = pcall(function()
            REM.Stomp:FireServer()
        end)
        if ok then
            ST.TotalStomps  += 1
            ST.LastStompTime = now
            Log("Stomp fired! Total:", ST.TotalStomps)
        end
    end
end

-- 8h  ▸ NEW: Kill All — core teleport + kill function ---------
local function RunKillAll()
    if not HAS_ATTACK then
        Log("Kill All: no attack remotes found")
        return
    end

    ST.KillAllRunning = true
    Log("Kill All: STARTED")

    while CFG.KillAllActive and CFG.Enabled and ST.Running do
        -- Refresh our own character references
        if not rootPart or not rootPart.Parent then
            char = plr.Character
            if char then
                rootPart = char:FindFirstChild("HumanoidRootPart")
                humanoid = char:FindFirstChildOfClass("Humanoid")
            end
            if not rootPart then
                ST.KillAllTarget = "Waiting..."
                task.wait(1)
                continue
            end
        end

        -- Build target list of alive enemy players
        local targets = {}
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= plr and p.Character then
                local h = p.Character:FindFirstChildOfClass("Humanoid")
                local r = p.Character:FindFirstChild("HumanoidRootPart")
                if h and r and h.Health > 0 then
                    targets[#targets + 1] = p
                end
            end
        end

        if #targets == 0 then
            ST.KillAllTarget   = "No targets"
            ST.KillAllProgress = "0/0"
            task.wait(1)
            continue
        end

        for i, target in ipairs(targets) do
            -- Check if we should still be running
            if not CFG.KillAllActive or not CFG.Enabled or not ST.Running then
                break
            end

            -- Verify target still valid
            local tChar = target.Character
            if not tChar then continue end
            local tRoot = tChar:FindFirstChild("HumanoidRootPart")
            local tHum  = tChar:FindFirstChildOfClass("Humanoid")
            if not tRoot or not tHum or tHum.Health <= 0 then continue end

            ST.KillAllTarget   = target.Name
            ST.KillAllProgress = i .. "/" .. #targets
            Log("Kill All: targeting", target.Name, ST.KillAllProgress)

            -- ── Teleport to target ──
            if rootPart and rootPart.Parent then
                rootPart.CFrame = tRoot.CFrame * CFrame.new(0, 0, 3)
                InvalidateNearbyCache()
            end
            task.wait(CFG.KillAllTeleportDelay)

            -- ── Attack loop until target dies or timeout ──
            local startTime = tick()
            while CFG.KillAllActive and CFG.Enabled and ST.Running do
                -- Re-fetch references (they can go nil on respawn)
                tChar = target.Character
                if not tChar then break end
                tHum  = tChar:FindFirstChildOfClass("Humanoid")
                tRoot = tChar:FindFirstChild("HumanoidRootPart")
                if not tHum or tHum.Health <= 0 then break end
                if not tRoot then break end

                -- Check our own character
                if not rootPart or not rootPart.Parent then
                    char = plr.Character
                    if char then
                        rootPart = char:FindFirstChild("HumanoidRootPart")
                        humanoid = char:FindFirstChildOfClass("Humanoid")
                    end
                    if not rootPart then break end
                end

                -- Timeout check
                if tick() - startTime > CFG.KillAllTimeout then
                    Log("Kill All: timeout on", target.Name)
                    break
                end

                -- Re-teleport if drifted too far
                local dist = (rootPart.Position - tRoot.Position).Magnitude
                if dist > CFG.KillAllReteleportDist then
                    rootPart.CFrame = tRoot.CFrame * CFrame.new(0, 0, 3)
                    InvalidateNearbyCache()
                    task.wait(0.05)
                end

                -- Attack
                Attack(tChar)

                -- Stomp if they're downed
                if CFG.UseAutoStomp and REM.Stomp and IsPlayerDown(tChar) then
                    pcall(function() REM.Stomp:FireServer() end)
                    ST.TotalStomps += 1
                end

                task.wait(1 / math.max(CFG.AttacksPerSecond, 1))
            end

            -- Check if we got the kill
            tChar = target.Character
            tHum  = tChar and tChar:FindFirstChildOfClass("Humanoid")
            if tHum and tHum.Health <= 0 then
                ST.KillAllKills += 1
                Log("Kill All: killed", target.Name, "Total:", ST.KillAllKills)
            end

            -- Brief pause before next target
            if CFG.KillAllActive and CFG.Enabled and ST.Running then
                task.wait(CFG.KillAllTeleportDelay)
            end
        end

        -- Finished one pass, short cooldown before next scan
        if CFG.KillAllActive and CFG.Enabled and ST.Running then
            ST.KillAllTarget   = "Scanning..."
            ST.KillAllProgress = ""
            task.wait(1.5)
        end
    end

    ST.KillAllRunning  = false
    ST.KillAllTarget   = ""
    ST.KillAllProgress = ""
    Log("Kill All: STOPPED")
end

----------------------------------------------------------------
-- 9. GUI
----------------------------------------------------------------
local GUI_REFS

local function BuildGUI()
    local existing = plr:FindFirstChild("PlayerGui")
                     and plr.PlayerGui:FindFirstChild("MassAttackPro")
    if existing then existing:Destroy() end

    local sg = Instance.new("ScreenGui")
    sg.Name = "MassAttackPro"
    sg.ResetOnSpawn   = false
    sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    sg.DisplayOrder   = 999

    pcall(function()
        if syn and syn.protect_gui then syn.protect_gui(sg)
        elseif gethui then sg.Parent = gethui(); return end
    end)
    if not sg.Parent then sg.Parent = plr:WaitForChild("PlayerGui") end

    local function Corner(p, r)
        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, r or 8); c.Parent = p
    end
    local function Stroke(p, col, t)
        local s = Instance.new("UIStroke")
        s.Color = col or CLR.border; s.Thickness = t or 1; s.Parent = p
    end

    -- ── main frame ──
    local main = Instance.new("Frame")
    main.Name = "Main"
    main.Size     = UDim2.new(0, 370, 0, 600)
    main.Position = UDim2.new(0.5, -185, 0.5, -300)
    main.BackgroundColor3 = CLR.bg
    main.BorderSizePixel  = 0
    main.ClipsDescendants = true
    main.Active = true
    main.Parent = sg
    Corner(main, 10); Stroke(main)

    local sh = Instance.new("ImageLabel")
    sh.Size = UDim2.new(1, 40, 1, 40)
    sh.Position = UDim2.new(0, -20, 0, -20)
    sh.BackgroundTransparency = 1
    sh.Image = "rbxassetid://6015897843"
    sh.ImageColor3 = Color3.new(0, 0, 0)
    sh.ImageTransparency = 0.45
    sh.ScaleType = Enum.ScaleType.Slice
    sh.SliceCenter = Rect.new(49, 49, 450, 450)
    sh.ZIndex = -1; sh.Parent = main

    -- ── header ──
    local hdr = Instance.new("Frame")
    hdr.Name = "Header"
    hdr.Size = UDim2.new(1, 0, 0, 44)
    hdr.BackgroundColor3 = CLR.header
    hdr.BorderSizePixel = 0; hdr.Parent = main
    Corner(hdr, 10)

    local hf = Instance.new("Frame")
    hf.Size = UDim2.new(1, 0, 0, 12)
    hf.Position = UDim2.new(0, 0, 1, -12)
    hf.BackgroundColor3 = CLR.header
    hf.BorderSizePixel = 0; hf.Parent = hdr

    local sep = Instance.new("Frame")
    sep.Size = UDim2.new(1, 0, 0, 1)
    sep.Position = UDim2.new(0, 0, 1, 0)
    sep.BackgroundColor3 = CLR.border
    sep.BorderSizePixel = 0; sep.Parent = hdr

    local ttl = Instance.new("TextLabel")
    ttl.Size = UDim2.new(1, -110, 1, 0)
    ttl.Position = UDim2.new(0, 12, 0, 0)
    ttl.BackgroundTransparency = 1
    ttl.Text = "⚔  MASS ATTACK PRO"
    ttl.TextColor3 = CLR.text; ttl.TextSize = 15
    ttl.Font = Enum.Font.GothamBold
    ttl.TextXAlignment = Enum.TextXAlignment.Left; ttl.Parent = hdr

    local vb = Instance.new("TextLabel")
    vb.Size = UDim2.new(0, 36, 0, 16)
    vb.Position = UDim2.new(0, 176, 0.5, -8)
    vb.BackgroundColor3 = CLR.accent; vb.Text = "v2.2"
    vb.TextColor3 = CLR.text; vb.TextSize = 9
    vb.Font = Enum.Font.GothamBold; vb.Parent = hdr
    Corner(vb, 5)

    local minB = Instance.new("TextButton")
    minB.Size = UDim2.new(0, 26, 0, 26)
    minB.Position = UDim2.new(1, -64, 0.5, -13)
    minB.BackgroundColor3 = CLR.orange; minB.Text = "—"
    minB.TextColor3 = CLR.text; minB.TextSize = 14
    minB.Font = Enum.Font.GothamBold
    minB.AutoButtonColor = true; minB.Parent = hdr; Corner(minB, 6)

    local clsB = Instance.new("TextButton")
    clsB.Size = UDim2.new(0, 26, 0, 26)
    clsB.Position = UDim2.new(1, -34, 0.5, -13)
    clsB.BackgroundColor3 = CLR.red; clsB.Text = "✕"
    clsB.TextColor3 = CLR.text; clsB.TextSize = 11
    clsB.Font = Enum.Font.GothamBold
    clsB.AutoButtonColor = true; clsB.Parent = hdr; Corner(clsB, 6)

    -- ── dragging ──
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

    -- ── scrolling content ──
    local scroll = Instance.new("ScrollingFrame")
    scroll.Name = "Content"
    scroll.Size     = UDim2.new(1, -14, 1, -52)
    scroll.Position = UDim2.new(0, 7, 0, 48)
    scroll.BackgroundTransparency = 1
    scroll.BorderSizePixel = 0
    scroll.ScrollBarThickness = 3
    scroll.ScrollBarImageColor3 = CLR.accent
    scroll.ScrollBarImageTransparency = 0.3
    scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scroll.Parent = main

    local lay = Instance.new("UIListLayout")
    lay.SortOrder = Enum.SortOrder.LayoutOrder
    lay.Padding = UDim.new(0, 5)
    lay.Parent = scroll

    local pad = Instance.new("UIPadding")
    pad.PaddingBottom = UDim.new(0, 10)
    pad.Parent = scroll

    local _ord = 0
    local function nxt() _ord += 1; return _ord end

    -- ── section header ──
    local function Section(name)
        local f = Instance.new("Frame")
        f.Size = UDim2.new(1, 0, 0, 24)
        f.BackgroundTransparency = 1
        f.LayoutOrder = nxt(); f.Parent = scroll

        local l = Instance.new("TextLabel")
        l.Size = UDim2.new(1, -8, 1, 0)
        l.Position = UDim2.new(0, 4, 0, 0)
        l.BackgroundTransparency = 1
        l.Text = string.upper(name)
        l.TextColor3 = CLR.accent; l.TextSize = 10
        l.Font = Enum.Font.GothamBold
        l.TextXAlignment = Enum.TextXAlignment.Left; l.Parent = f

        local ln = Instance.new("Frame")
        ln.Size = UDim2.new(1, -8, 0, 1)
        ln.Position = UDim2.new(0, 4, 1, -1)
        ln.BackgroundColor3 = CLR.border
        ln.BorderSizePixel = 0; ln.Parent = f
    end

    -- ── toggle builder ──
    local function Toggle(label, def, cb)
        local f = Instance.new("Frame")
        f.Size = UDim2.new(1, 0, 0, 32)
        f.BackgroundColor3 = CLR.card
        f.BorderSizePixel = 0
        f.LayoutOrder = nxt(); f.Parent = scroll
        Corner(f, 7)

        local tl = Instance.new("TextLabel")
        tl.Size = UDim2.new(1, -62, 1, 0)
        tl.Position = UDim2.new(0, 10, 0, 0)
        tl.BackgroundTransparency = 1; tl.Text = label
        tl.TextColor3 = CLR.text; tl.TextSize = 12
        tl.Font = Enum.Font.Gotham
        tl.TextXAlignment = Enum.TextXAlignment.Left
        tl.TextTruncate = Enum.TextTruncate.AtEnd; tl.Parent = f

        local bg = Instance.new("Frame")
        bg.Size = UDim2.new(0, 40, 0, 18)
        bg.Position = UDim2.new(1, -50, 0.5, -9)
        bg.BackgroundColor3 = def and CLR.toggleOn or CLR.toggleOff
        bg.BorderSizePixel = 0; bg.Parent = f; Corner(bg, 9)

        local dot = Instance.new("Frame")
        dot.Size = UDim2.new(0, 14, 0, 14)
        dot.Position = def and UDim2.new(1, -16, 0.5, -7)
                            or UDim2.new(0, 2, 0.5, -7)
        dot.BackgroundColor3 = Color3.new(1, 1, 1)
        dot.BorderSizePixel = 0; dot.Parent = bg; Corner(dot, 7)

        local st = def
        local api = {}

        function api.Set(v)
            st = v
            TweenService:Create(bg, TweenInfo.new(0.18),
                {BackgroundColor3 = st and CLR.toggleOn or CLR.toggleOff}):Play()
            TweenService:Create(dot, TweenInfo.new(0.14, Enum.EasingStyle.Back),
                {Position = st and UDim2.new(1, -16, 0.5, -7)
                                or UDim2.new(0, 2, 0.5, -7)}):Play()
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

    -- ── slider builder ──
    local function Slider(label, lo, hi, def, cb)
        local f = Instance.new("Frame")
        f.Size = UDim2.new(1, 0, 0, 46)
        f.BackgroundColor3 = CLR.card
        f.BorderSizePixel = 0
        f.LayoutOrder = nxt(); f.Parent = scroll
        Corner(f, 7)

        local tl = Instance.new("TextLabel")
        tl.Size = UDim2.new(1, -52, 0, 18)
        tl.Position = UDim2.new(0, 10, 0, 3)
        tl.BackgroundTransparency = 1; tl.Text = label
        tl.TextColor3 = CLR.text; tl.TextSize = 11
        tl.Font = Enum.Font.Gotham
        tl.TextXAlignment = Enum.TextXAlignment.Left; tl.Parent = f

        local vl = Instance.new("TextLabel")
        vl.Size = UDim2.new(0, 42, 0, 18)
        vl.Position = UDim2.new(1, -52, 0, 3)
        vl.BackgroundTransparency = 1; vl.Text = tostring(def)
        vl.TextColor3 = CLR.accent; vl.TextSize = 12
        vl.Font = Enum.Font.GothamBold
        vl.TextXAlignment = Enum.TextXAlignment.Right; vl.Parent = f

        local track = Instance.new("Frame")
        track.Size = UDim2.new(1, -20, 0, 5)
        track.Position = UDim2.new(0, 10, 0, 30)
        track.BackgroundColor3 = CLR.sliderBg
        track.BorderSizePixel = 0; track.Parent = f; Corner(track, 3)

        local fill = Instance.new("Frame")
        fill.Size = UDim2.new(math.clamp((def - lo) / (hi - lo), 0, 1), 0, 1, 0)
        fill.BackgroundColor3 = CLR.accent
        fill.BorderSizePixel = 0; fill.Parent = track; Corner(fill, 3)

        local knob = Instance.new("Frame")
        knob.Size = UDim2.new(0, 12, 0, 12)
        knob.Position = UDim2.new(
            math.clamp((def - lo) / (hi - lo), 0, 1), -6, 0.5, -6
        )
        knob.BackgroundColor3 = Color3.new(1, 1, 1)
        knob.BorderSizePixel = 0; knob.ZIndex = 2
        knob.Parent = track; Corner(knob, 6)

        local hit = Instance.new("TextButton")
        hit.Size = UDim2.new(1, 0, 0, 20)
        hit.Position = UDim2.new(0, 0, 0, 22)
        hit.BackgroundTransparency = 1; hit.Text = ""; hit.Parent = f

        local sliding = false
        local cur = def

        local function upd(pos)
            local ax, aw = track.AbsolutePosition.X, track.AbsoluteSize.X
            if aw == 0 then return end
            local r = math.clamp((pos.X - ax) / aw, 0, 1)
            local v = math.clamp(math.floor(lo + (hi - lo) * r + 0.5), lo, hi)
            r = (v - lo) / (hi - lo)
            fill.Size = UDim2.new(r, 0, 1, 0)
            knob.Position = UDim2.new(r, -6, 0.5, -6)
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
            if sliding and (i.UserInputType == Enum.UserInputType.MouseMovement
            or i.UserInputType == Enum.UserInputType.Touch) then
                upd(i.Position)
            end
        end)

        return {
            Set = function(v)
                cur = v
                local r = math.clamp((v - lo) / (hi - lo), 0, 1)
                fill.Size = UDim2.new(r, 0, 1, 0)
                knob.Position = UDim2.new(r, -6, 0.5, -6)
                vl.Text = tostring(v)
            end,
            Get = function() return cur end,
        }
    end

    -- ════════════════════════════════════
    --  BUILD ALL CONTROLS
    -- ════════════════════════════════════

    -- ── Status card (expanded) ──
    local sCard = Instance.new("Frame")
    sCard.Size = UDim2.new(1, 0, 0, 120)
    sCard.BackgroundColor3 = CLR.card
    sCard.BorderSizePixel = 0
    sCard.LayoutOrder = nxt(); sCard.Parent = scroll
    Corner(sCard, 7); Stroke(sCard)

    local sDot = Instance.new("Frame")
    sDot.Size = UDim2.new(0, 8, 0, 8)
    sDot.Position = UDim2.new(0, 10, 0, 11)
    sDot.BackgroundColor3 = CLR.red
    sDot.BorderSizePixel = 0; sDot.Parent = sCard
    Corner(sDot, 4)

    local sLbl = Instance.new("TextLabel")
    sLbl.Size = UDim2.new(0.4, 0, 0, 16)
    sLbl.Position = UDim2.new(0, 24, 0, 6)
    sLbl.BackgroundTransparency = 1; sLbl.Text = "DISABLED"
    sLbl.TextColor3 = CLR.red; sLbl.TextSize = 11
    sLbl.Font = Enum.Font.GothamBold
    sLbl.TextXAlignment = Enum.TextXAlignment.Left; sLbl.Parent = sCard

    local function StatL(name, y)
        local n = Instance.new("TextLabel")
        n.Size = UDim2.new(0, 62, 0, 14)
        n.Position = UDim2.new(0, 10, 0, y)
        n.BackgroundTransparency = 1; n.Text = name .. ":"
        n.TextColor3 = CLR.textDim; n.TextSize = 10
        n.Font = Enum.Font.Gotham
        n.TextXAlignment = Enum.TextXAlignment.Left; n.Parent = sCard
        local v = Instance.new("TextLabel")
        v.Size = UDim2.new(0, 50, 0, 14)
        v.Position = UDim2.new(0, 72, 0, y)
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

    local svTargets  = StatL("Targets",  28)
    local svAttacks  = StatL("Attacks",  44)
    local svGuard    = StatL("Guard",    60)
    local svStomps   = StatL("Stomps",   76)
    local svKAKills  = StatL("KA Kills", 92)      -- ▸ NEW
    local svAPS      = StatR("APS",      28)
    local svHP       = StatR("Health",   44)
    local svMode     = StatR("Mode",     60)
    local svNearby   = StatR("Nearby",   76)
    local svKATarget = StatR("KA Tgt",   92)       -- ▸ NEW

    -- ── Main Controls ──
    Section("Main Controls")

    local tEnabled = Toggle("Script Enabled", CFG.Enabled, function(v)
        CFG.Enabled = v
        sDot.BackgroundColor3 = v and CLR.green or CLR.red
        sLbl.Text = v and "ACTIVE" or "DISABLED"
        sLbl.TextColor3 = v and CLR.green or CLR.red
    end)

    Toggle("Attack All Targets (AoE)", CFG.TargetAll, function(v)
        CFG.TargetAll = v
    end)

    Toggle("Target Players", CFG.TargetPlayers, function(v)
        CFG.TargetPlayers = v; ST.LastTargetUpdate = 0
    end)

    Toggle("Target NPCs", CFG.TargetNPCs, function(v)
        CFG.TargetNPCs = v; ST.LastTargetUpdate = 0
    end)

    -- ── Attack Settings ──
    Section("Attack Settings")

    Slider("Attacks Per Second", 1, 20, CFG.AttacksPerSecond, function(v)
        CFG.AttacksPerSecond = v
    end)

    Slider("Max Targets / Cycle", 1, 10, CFG.MaxTargetsPerCycle, function(v)
        CFG.MaxTargetsPerCycle = v
    end)

    -- ── Attack Types ──
    Section("Attack Types")

    Toggle("Punch "    .. (REM.Punch    and "✓" or "✗"),
        REM.Punch ~= nil and CFG.UsePunch,
        function(v) if REM.Punch then CFG.UsePunch = v end end)

    Toggle("Suplex "   .. (REM.Suplex   and "✓" or "✗"),
        REM.Suplex ~= nil and CFG.UseSuplex,
        function(v) if REM.Suplex then CFG.UseSuplex = v end end)

    Toggle("Heavy Hit " .. (REM.HeavyHit and "✓" or "✗"),
        REM.HeavyHit ~= nil and CFG.UseHeavyHit,
        function(v) if REM.HeavyHit then CFG.UseHeavyHit = v end end)

    Toggle("Auto Stomp " .. (REM.Stomp and "✓" or "✗"),
        REM.Stomp ~= nil and CFG.UseAutoStomp,
        function(v) if REM.Stomp then CFG.UseAutoStomp = v end end)

    Slider("Stomp Range (studs)", 5, 50, CFG.StompRange, function(v)
        CFG.StompRange = v
    end)

    -- ▸ NEW ── Kill All ──
    Section("Kill All")

    local tKillAll = Toggle("Kill All (Teleport & Kill)", CFG.KillAllActive, function(v)
        CFG.KillAllActive = v
        if v and not ST.KillAllRunning then
            task.spawn(RunKillAll)
        end
    end)

    Slider("Kill Timeout (sec)", 3, 20, CFG.KillAllTimeout, function(v)
        CFG.KillAllTimeout = v
    end)

    -- ── Defense ──
    Section("Defense")

    local tGuard = Toggle("Auto Guard " .. (REM.Block and "✓" or "✗"),
        REM.Block ~= nil and CFG.UseAutoGuard,
        function(v)
            if REM.Block then
                CFG.UseAutoGuard = v
                if not v then SetGuard(false) end
            end
        end)

    Toggle("Drop Guard to Attack", CFG.GuardDropForAttack,
        function(v) CFG.GuardDropForAttack = v end)

    Toggle("Ignore ForceField", CFG.IgnoreForceField,
        function(v) CFG.IgnoreForceField = v end)

    Slider("Guard Range (studs)", 10, 150, CFG.GuardActivationRange, function(v)
        CFG.GuardActivationRange = v
        InvalidateNearbyCache()
    end)

    -- ── System ──
    Section("System")

    Toggle("Debug Logging", CFG.Debug, function(v) CFG.Debug = v end)

    -- ── Remote Status ──
    Section("Remote Status")
    local ri = Instance.new("Frame")
    ri.Size = UDim2.new(1, 0, 0, 91)
    ri.BackgroundColor3 = CLR.card
    ri.BorderSizePixel = 0
    ri.LayoutOrder = nxt(); ri.Parent = scroll
    Corner(ri, 7)

    for idx, data in ipairs({
        {"PUNCHEVENT",  REM.Punch},
        {"SUPLEXEVENT", REM.Suplex},
        {"HEAVYHIT",    REM.HeavyHit},
        {"BLOCKEVENT",  REM.Block},
        {"STOMPEVENT",  REM.Stomp},
    }) do
        local ok = data[2] ~= nil
        local rl = Instance.new("TextLabel")
        rl.Size = UDim2.new(1, -14, 0, 15)
        rl.Position = UDim2.new(0, 10, 0, 2 + (idx - 1) * 17)
        rl.BackgroundTransparency = 1
        rl.Text = (ok and "●  " or "○  ") .. data[1]
        rl.TextColor3 = ok and CLR.green or CLR.red
        rl.TextSize = 10; rl.Font = Enum.Font.GothamSemibold
        rl.TextXAlignment = Enum.TextXAlignment.Left; rl.Parent = ri
    end

    local kb = Instance.new("TextLabel")
    kb.Size = UDim2.new(1, 0, 0, 18)
    kb.BackgroundTransparency = 1
    kb.Text = "Insert → Toggle GUI   |   RShift → Toggle Script"
    kb.TextColor3 = CLR.textDim; kb.TextSize = 9
    kb.Font = Enum.Font.Gotham
    kb.LayoutOrder = nxt(); kb.Parent = scroll

    -- ── minimize / close ──
    local minimized = false
    local fullSz = main.Size

    minB.MouseButton1Click:Connect(function()
        minimized = not minimized
        if minimized then
            TweenService:Create(main, TweenInfo.new(0.22, Enum.EasingStyle.Quint),
                {Size = UDim2.new(0, 370, 0, 44)}):Play()
            scroll.Visible = false; minB.Text = "+"
        else
            scroll.Visible = true
            TweenService:Create(main, TweenInfo.new(0.22, Enum.EasingStyle.Quint),
                {Size = fullSz}):Play()
            minB.Text = "—"
        end
    end)

    clsB.MouseButton1Click:Connect(function()
        ST.Running = false; CFG.Enabled = false
        CFG.KillAllActive = false
        SetGuard(false); sg:Destroy()
    end)

    -- ── keybinds ──
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
        end
    end)

    -- ── open animation ──
    main.Size = UDim2.new(0, 370, 0, 0)
    main.BackgroundTransparency = 1
    task.defer(function()
        TweenService:Create(main,
            TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
            {Size = fullSz, BackgroundTransparency = 0}):Play()
    end)

    return {
        gui  = sg,
        main = main,
        statusDot = sDot,
        statusLbl = sLbl,
        sv = {
            targets  = svTargets,  attacks  = svAttacks,
            guard    = svGuard,    aps      = svAPS,
            health   = svHP,       mode     = svMode,
            stomps   = svStomps,   nearby   = svNearby,
            kaKills  = svKAKills,  kaTarget = svKATarget,
        },
        toggleEnabled = tEnabled,
        toggleKillAll = tKillAll,
    }
end

GUI_REFS = BuildGUI()

----------------------------------------------------------------
-- 10. MAIN LOOPS
----------------------------------------------------------------

-- 10a  Health monitor ─────────────────────────────────────────
task.spawn(function()
    while ST.Running do
        if CFG.UseAutoGuard and CFG.Enabled and humanoid then
            local hp = humanoid.Health
            if hp < ST.LastHealth then
                if ST.EnemyNearby then
                    SetGuard(true)
                    Log("Damage + enemy nearby → guard ON")
                end
            end
            ST.LastHealth = hp
        end
        task.wait(CFG.HealthPollInterval)
    end
end)

-- 10b  Passive guard keep-alive ───────────────────────────────
--      ▸ FIXED: uses cached IsEnemyNearby, no lag
task.spawn(function()
    while ST.Running do
        if CFG.UseAutoGuard and CFG.Enabled then
            local nearby = IsEnemyNearby(CFG.GuardActivationRange)
            ST.EnemyNearby = nearby
            if nearby then
                if not ST.GuardActive then
                    SetGuard(true)
                    Log("Enemy nearby → guard ON")
                end
            else
                if ST.GuardActive then
                    SetGuard(false)
                    Log("No enemies nearby → guard OFF")
                end
            end
        else
            -- ▸ FIX: still update nearby status for display even when
            --   guard is off, but use a longer interval to save perf
            ST.EnemyNearby = IsEnemyNearby(CFG.GuardActivationRange)
        end
        task.wait(0.4)
    end
end)

-- 10c  Attack loop ────────────────────────────────────────────
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

                if CFG.GuardDropForAttack and CFG.UseAutoGuard then
                    task.delay(CFG.GuardReactivateDelay, function()
                        if CFG.UseAutoGuard and CFG.Enabled and ST.Running then
                            if IsEnemyNearby(CFG.GuardActivationRange) then
                                SetGuard(true)
                            end
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

-- 10d  Status updater ─────────────────────────────────────────
task.spawn(function()
    while ST.Running do
        if GUI_REFS and GUI_REFS.sv then
            local s = GUI_REFS.sv
            s.targets.Text = tostring(ST.TargetsFound)
            s.attacks.Text = tostring(ST.TotalAttacks)
            s.guard.Text   = ST.GuardActive and "ON" or "OFF"
            s.guard.TextColor3 = ST.GuardActive and CLR.green or CLR.red
            s.aps.Text     = tostring(CFG.AttacksPerSecond)
            s.health.Text  = humanoid
                and tostring(math.floor(humanoid.Health)) or "?"
            s.mode.Text    = CFG.KillAllActive and "KILL ALL"
                             or (CFG.TargetAll and "AoE" or "Single")
            s.mode.TextColor3 = CFG.KillAllActive and CLR.cyan or CLR.text

            s.stomps.Text  = tostring(ST.TotalStomps)
            s.nearby.Text  = ST.EnemyNearby and "YES" or "NO"
            s.nearby.TextColor3 = ST.EnemyNearby and CLR.yellow or CLR.textDim

            -- Kill All stats
            s.kaKills.Text  = tostring(ST.KillAllKills)
            s.kaKills.TextColor3 = ST.KillAllKills > 0 and CLR.cyan or CLR.text
            s.kaTarget.Text = ST.KillAllTarget ~= "" and ST.KillAllTarget or "-"
            s.kaTarget.TextColor3 = CFG.KillAllActive and CLR.cyan or CLR.textDim
        end
        task.wait(0.35)
    end
end)

-- 10e  Auto Stomp loop ────────────────────────────────────────
task.spawn(function()
    while ST.Running do
        if CFG.Enabled and CFG.UseAutoStomp and REM.Stomp then
            TryStomp()
            task.wait(0.15)
        else
            task.wait(0.3)
        end
    end
end)

-- 10f  Kill All is launched on-demand via RunKillAll()
--      (spawned by the toggle callback in the GUI)

----------------------------------------------------------------
-- 11. RESPAWN HANDLER
----------------------------------------------------------------
Conn(plr.CharacterAdded, function(newChar)
    char     = newChar
    rootPart = char:WaitForChild("HumanoidRootPart", 10)
    humanoid = char:WaitForChild("Humanoid", 10)
    ST.GuardActive      = false
    ST.LastHealth        = humanoid and humanoid.Health or 100
    ST.LastTargetUpdate  = 0
    ST.EnemyNearby       = false
    InvalidateNearbyCache()

    if CFG.UseAutoGuard and CFG.Enabled then
        task.wait(0.5)
        if IsEnemyNearby(CFG.GuardActivationRange) then
            SetGuard(true)
        end
    end
    Log("Respawned – reset")
end)

----------------------------------------------------------------
-- 12. INIT
----------------------------------------------------------------
RefreshTargets()
ST.EnemyNearby = IsEnemyNearby(CFG.GuardActivationRange)
if CFG.UseAutoGuard and CFG.Enabled and ST.EnemyNearby then
    SetGuard(true)
end

print("╔═══════════════════════════════════════╗")
print("║     MASS ATTACK PRO v2.2 — LOADED     ║")
print("╠═══════════════════════════════════════╣")
print("║  Insert      →  Toggle GUI            ║")
print("║  RightShift  →  Toggle Script          ║")
print("║  + Kill All  + Proximity Guard         ║")
print("║  + Auto Stomp (lag fix applied)        ║")
print("╚═══════════════════════════════════════╝")
