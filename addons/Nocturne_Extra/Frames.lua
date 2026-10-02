local _, ns = ...

local Nocturne = _G.Nocturne

local IsInGroup = IsInGroup
local UnitAffectingCombat = UnitAffectingCombat
local GetSheathState = GetSheathState
local EnumerateFrames = EnumerateFrames
local UnitHealth = UnitHealth
local UnitHealthMax = UnitHealthMax
local UnitPower = UnitPower
local UnitPowerMax = UnitPowerMax
local UnitPowerType = UnitPowerType

-- One Nocturne.NewSuppressor per Blizzard frame (resolved by name, since
-- some are created late); combat-locked frames are faded instead of hidden.
local suppressors = {}

local function Suppress(name, want)
    local s = Nocturne.NewSuppressor(function() return _G[name] end, want)
    s.name, s.want = name, want
    suppressors[#suppressors + 1] = s
    return s
end

local function SyncSuppression()
    for i = 1, #suppressors do suppressors[i].Sync() end
end

local function Const(key)
    return function() return ns.db and ns.db[key] end
end

-- Chat hides only while solo AND in combat.
local function ChatCond()
    return ns.db and ns.db.hideChatInCombat
        and UnitAffectingCombat("player")
        and not IsInGroup()
end

-- UnitHealth/UnitPower (and the percent APIs) return secret values for
-- "player" unconditionally on this build — tainted addon code can never
-- read or compare them (verified: canaccessvalue=false with no active
-- restriction). So "at rest" is approximated by activity: hp/power events
-- fire on every change, regen ticks keep them firing until the value
-- settles at its baseline, then they go quiet. A change inside the window
-- counts as unrest.
local vitalsChangedAt = 0
local UNREST_WINDOW   = 3.5

-- Primary-power types whose rest value is 0 (decay out of combat); the
-- remaining primary powers rest at max. Secondary resources (combo points,
-- holy power, ...) are ignored entirely.
local ZERO_POWER      = {
    [Enum.PowerType.Rage]       = true,
    [Enum.PowerType.RunicPower] = true,
    [Enum.PowerType.Fury]       = true,
    [Enum.PowerType.Pain]       = true,
    [Enum.PowerType.Insanity]   = true,
    [Enum.PowerType.Maelstrom]  = true,
    [Enum.PowerType.LunarPower] = true,
}

-- If the values ever come back readable, prefer the real comparison.
local function ValuesSecret()
    local hp = UnitHealth("player")
    return hp == nil or ns.IsSecret(hp)
end

local function HealthNotAtRest()
    if ValuesSecret() then
        return (GetTime() - vitalsChangedAt) < UNREST_WINDOW
    end
    local hp, hm = UnitHealth("player"), UnitHealthMax("player")
    local p, pm = UnitPower("player"), UnitPowerMax("player")
    if ns.IsSecret(p) or ns.IsSecret(pm) or p == nil or pm == nil then
        return (GetTime() - vitalsChangedAt) < UNREST_WINDOW
    end
    if hp < hm then return true end
    -- Secondary resources (combo points, holy power, ...) stay ignored:
    -- UnitPower defaults to the primary type.
    local restAtZero = ZERO_POWER[UnitPowerType("player")]
    if restAtZero then return p > 0 end
    return p < pm
end

-- Player frame hides only while fully at rest: out of combat, weapons
-- sheathed, full health, primary power at its baseline.
local function PlayerCond()
    if not (ns.db and ns.db.hidePlayerIdle) then return false end
    if UnitAffectingCombat("player") then return false end
    if (GetSheathState() or 1) ~= 1 then return false end
    if HealthNotAtRest() then return false end
    return true
end

local playerSuppressor = Suppress("PlayerFrame", PlayerCond)

Suppress("TargetFrame", Const("hideTarget"))
for _, name in ipairs({
    "BagsBar",
    "MainMenuBarBackpackButton",
    "CharacterBag0Slot", "CharacterBag1Slot", "CharacterBag2Slot", "CharacterBag3Slot",
    "BagReagentBag",
}) do
    Suppress(name, Const("hideBags"))
end
for i = 1, 10 do Suppress("ChatFrame" .. i, ChatCond) end
for _, name in ipairs({
    "GeneralDockManager", "ChatFrameMenuButton", "ChatFrameChannelButton", "QuickJoinToastButton",
}) do
    Suppress(name, ChatCond)
end

-- ConsolePort: the cluster lives inside ConsolePortBarCluster, a secure
-- (protected) frame — Hide() on it would error in combat, so we suppress
-- with SetAlpha instead, which is legal on protected frames.
local IsAddOnLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or _G.IsAddOnLoaded
local cpFrame
local cpHidden = false

local function CPInstalled()
    return IsAddOnLoaded
        and (IsAddOnLoaded("ConsolePort_Bar") or IsAddOnLoaded("ConsolePort"))
end

-- ConsolePortBarCluster is the cluster widget's own secure frame (verified
-- via /nutl diag); the manager hosts toolbar/etc. too, so it's only a
-- fallback. Not cached: the cluster may be created after a fallback matched.
local function ResolveCP()
    if not CPInstalled() then return nil end
    return _G.ConsolePortBarCluster
        or _G.ConsolePortBarManager
        or _G.ConsolePortCluster
end

-- GetSheathState(): 1 = sheathed, 2 = melee, 3 = ranged. In combat the
-- cluster always shows (casters can stay sheathed while fighting).
function ns:ApplyConsolePort()
    if not ns.db then return end
    local f = ResolveCP()
    if cpFrame and cpFrame ~= f then
        cpFrame:SetAlpha(1)
        cpHidden = false
    end
    cpFrame = f
    if not f then return end
    local wantHidden = ns.db.hideCPCluster
        and (GetSheathState() or 1) == 1
        and not UnitAffectingCombat("player")
    if wantHidden then
        cpHidden = true
        f:SetAlpha(0)
    elseif cpHidden then
        cpHidden = false
        f:SetAlpha(1)
    end
end

function ns:ApplySettings()
    if not ns.db then return end
    SyncSuppression()
    ns:ApplyConsolePort()
end

-- Sheath toggles fire UNIT_MODEL_CHANGED for the player; the ticker also
-- re-applies alpha when ConsolePort's own fades fight the suppression.
Nocturne.RegisterEvent("UNIT_MODEL_CHANGED", function(_, unit)
    if unit == "player" then
        ns:ApplyConsolePort()
        if playerSuppressor then playerSuppressor.Sync() end
    end
end)
-- Health/power events stamp the unrest timestamp (it drives the "at rest"
-- approximation when the values are secret), then sync the frame.
-- UNIT_HEALTH_FREQUENT was folded into UNIT_HEALTH in 9.0.1; the bus
-- silently skips unknown events, so the old name never fired.
local vitalsEvents = {}
for _, event in ipairs({
    "UNIT_HEALTH", "UNIT_MAXHEALTH",
    "UNIT_POWER_FREQUENT", "UNIT_DISPLAYPOWER",
}) do
    vitalsEvents[event] = 0
    Nocturne.RegisterEvent(event, function(_, unit)
        if unit ~= "player" then return end
        vitalsEvents[event] = vitalsEvents[event] + 1
        vitalsChangedAt = GetTime()
        if playerSuppressor then playerSuppressor.Sync() end
    end)
end
Nocturne.RegisterEvent("PLAYER_ENTERING_WORLD", function()
    -- Values may still be regenerating; wait one window before hiding.
    vitalsChangedAt = GetTime()
    ns:ApplySettings()
end)
Nocturne.RegisterEvent("PLAYER_REGEN_DISABLED", function()
    ns:ApplySettings()
end)
Nocturne.RegisterEvent("PLAYER_REGEN_ENABLED", function()
    ns:ApplySettings()
end)
Nocturne.RegisterEvent("GROUP_ROSTER_UPDATE", function()
    if ns.db then SyncSuppression() end
end)
-- Combat/sheath changes above apply immediately; the ticker only re-applies
-- the cluster fade. Idle unless it's on or still has something to restore.
C_Timer.NewTicker(0.5, function()
    if not ns.db then return end
    if ns.db.hideCPCluster or cpHidden then ns:ApplyConsolePort() end
    -- Also covers the return-to-rest transition if the unit power/health
    -- events are renamed or throttled away on this client.
    if playerSuppressor and (ns.db.hidePlayerIdle or playerSuppressor.hidden) then
        playerSuppressor.Sync()
    end
end)

local function SafeV(v) return ns.IsSecret(v) and "<secret>" or tostring(v) end

function ns:DiagText()
    local out = {
        ("target=%s bags=%s chatCombat=%s cpCluster=%s playerIdle=%s"):format(
            tostring(ns.db.hideTarget), tostring(ns.db.hideBags),
            tostring(ns.db.hideChatInCombat), tostring(ns.db.hideCPCluster),
            tostring(ns.db.hidePlayerIdle)),
        ("playerFrame shown=%s alpha=%s hidden=%s cond=%s"):format(
            tostring(_G.PlayerFrame and _G.PlayerFrame:IsShown()),
            _G.PlayerFrame and SafeV(_G.PlayerFrame:GetAlpha()) or "nil",
            tostring(playerSuppressor and playerSuppressor.hidden),
            tostring(PlayerCond())),
        ("hp=%s/%s power=%s/%s type=%s unrest=%s vitalsAge=%.1f"):format(
            SafeV(UnitHealth("player")), SafeV(UnitHealthMax("player")),
            SafeV(UnitPower("player")), SafeV(UnitPowerMax("player")),
            SafeV(UnitPowerType("player")),
            tostring(HealthNotAtRest()), GetTime() - vitalsChangedAt),
        ("vitalsEvents hp=%d maxhp=%d power=%d displaypower=%d"):format(
            vitalsEvents.UNIT_HEALTH, vitalsEvents.UNIT_MAXHEALTH,
            vitalsEvents.UNIT_POWER_FREQUENT, vitalsEvents.UNIT_DISPLAYPOWER),
        -- Secret-probing: UnitHealthPercent is SecretWhenCurveSecret — a
        -- call WITHOUT a curve may return a plain 0..1. canaccessvalue
        -- reports whether this execution path may touch secrets at all.
        ("hpPctNaked=%s powerPctNaked=%s canAccess=%s"):format(
            SafeV(UnitHealthPercent and UnitHealthPercent("player")),
            SafeV(UnitPowerPercent and UnitPowerPercent("player", UnitPowerType("player"))),
            SafeV(canaccessvalue and canaccessvalue(UnitHealth("player")))),
        ("restr=%s secretsEnabled=%s"):format(
            (function()
                if not (C_RestrictedActions and Enum.AddOnRestrictionType) then
                    return "n/a"
                end
                local parts = {}
                for name, t in pairs(Enum.AddOnRestrictionType) do
                    if C_RestrictedActions.IsAddOnRestrictionActive(t) then
                        parts[#parts + 1] = name
                    end
                end
                return table.concat(parts, "+")
            end)(),
            SafeV(C_Secrets and C_Secrets.HasSecretRestrictions and C_Secrets.HasSecretRestrictions())),
        -- Oracle probe: StatusBars driven by untainted Blizzard code (PRD,
        -- PlayerFrame) — if the fill geometry is readable it reveals the
        -- secret ratio without touching the value.
        (function()
            local function barInfo(bar)
                if not (bar and bar.GetValue) then return "noBar" end
                local ok, v = pcall(bar.GetValue, bar)
                if not ok then return "err" end
                local lo, hi = bar:GetMinMaxValues()
                local fill = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
                return ("%s/%s..%s fill=%s w=%s"):format(
                    SafeV(v), SafeV(lo), SafeV(hi),
                    tostring(fill and fill:IsShown()),
                    fill and SafeV(select(2, pcall(fill.GetWidth, fill))) or "nil")
            end
            local prd = _G.PersonalResourceDisplayFrame
            local pf = _G.PlayerFrame
            return ("prd=%s hp=[%s] pw=[%s] | pf hp=[%s] mp=[%s]"):format(
                tostring(prd and prd:IsShown()),
                barInfo(prd and (prd.healthbar or prd.healthBar)),
                barInfo(prd and (prd.powerbar or prd.powerBar)),
                barInfo(pf and pf.healthbar), barInfo(pf and pf.manabar))
        end)(),
        ("combat=%s group=%s sheath=%s cpInstalled=%s cpFrame=%s alpha=%s"):format(
            tostring(UnitAffectingCombat("player")), tostring(IsInGroup()),
            tostring(GetSheathState()), tostring(CPInstalled()),
            tostring(cpFrame and cpFrame:GetName()),
            tostring(cpFrame and cpFrame:GetAlpha())),
    }
    for i = 1, #suppressors do
        local s = suppressors[i]
        local f = _G[s.name]
        out[#out + 1] = ("suppressed %s shown=%s alpha=%s ours=%s want=%s"):format(
            s.name, tostring(f and f:IsShown()), f and SafeV(f:GetAlpha()) or "nil",
            tostring(s.hidden), tostring(s.want()))
    end
    -- Named ConsolePort* frames on screen, to identify the real cluster
    -- container if ConsolePortBarCluster isn't it.
    local f = EnumerateFrames()
    while f do
        -- GetName can hand back a secret value on protected frames; string
        -- methods on it are nil.
        local n = f.GetName and f:GetName()
        if type(n) == "string" and not ns.IsSecret(n) and n:find("ConsolePort") then
            out[#out + 1] = ("cp-named %s shown=%s alpha=%s"):format(
                n, tostring(f:IsShown()), SafeV(f:GetAlpha()))
        end
        f = EnumerateFrames(f)
    end
    return table.concat(out, "\n")
end
