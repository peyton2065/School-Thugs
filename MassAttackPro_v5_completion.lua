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

                -- Remote Aura: fire at everyone without teleporting
                if CFG.RemoteAura and HAS_ATTACK then
                    for _, p in ipairs(Players:GetPlayers()) do
                        if p ~= plr and p.Character then
                            if not IsWhitelisted(p.Name) then
                                if not (CFG.AutoWhitelistFriends and IsFriend(p)) then
                                    local h = p.Character:FindFirstChildOfClass("Humanoid")
                                    if h and h.Health > 0 then
                                        Attack(p.Character)
                                    end
                                end
                            end
                        end
                    end

                elseif #ST.TargetCache > 0 then
                    -- Sort by priority score
                    local sorted = {}
                    for _, model in ipairs(ST.TargetCache) do
                        if model and model.Parent then
                            table.insert(sorted, { model = model, score = ScoreTarget(model, myPos) })
                        end
                    end
                    if #sorted == 0 then ClearAllESP() end
                    table.sort(sorted, function(a, b) return a.score > b.score end)

                    local limit   = CFG.TargetAll and math.min(#sorted, CFG.MaxTargetsPerCycle) or 1
                    local attacked = 0

                    for _, entry in ipairs(sorted) do
                        if attacked >= limit then break end
                        local model = entry.model
                        local hrp   = model:FindFirstChild("HumanoidRootPart")
                        if hrp then
                            local dist = (myPos - hrp.Position).Magnitude
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
