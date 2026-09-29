local _, ns = ...

local Nocturne = _G.Nocturne

local IsInGroup = IsInGroup
local UnitAffectingCombat = UnitAffectingCombat
local GetSheathState = GetSheathState
local EnumerateFrames = EnumerateFrames

-- One Nocturne.NewSuppressor per Blizzard frame (resolved by name, since
-- some are created late); combat-locked frames are faded instead of hidden.
local suppressors = {}

local function Suppress(name, want)
    local s = Nocturne.NewSuppressor(function() return _G[name] end, want)
    s.name, s.want = name, want
    suppressors[#suppressors + 1] = s
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

Suppress("PlayerFrame", Const("hidePlayer"))
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

-- Personal Resource Display: since 12.0 it's PersonalResourceDisplayFrame
-- (Blizzard_PersonalResourceDisplay, an Edit Mode system holding health,
-- power, alternate power and class bars), no longer the player's nameplate.
-- Its own visibility follows the user's Edit Mode setting (UpdateShownState
-- Show()/Hide()s it on combat changes), so it's faded on top of that instead
-- of hidden, leaving Blizzard's logic alone.
local prdHidden = false

-- Powers that rest at 0 out of combat (rage-like): "not idle" = any charge.
-- Powers that rest full (mana-like): "not idle" = below max.
local ZERO_BASELINE_POWER = {}
for _, k in ipairs({
    "Rage", "RunicPower", "Fury", "Pain", "Insanity",
    "LunarPower", "Maelstrom",
}) do
    local v = Enum.PowerType and Enum.PowerType[k]
    if v then ZERO_BASELINE_POWER[v] = true end
end
-- Segmented class resources with a fixed out-of-combat resting value:
-- active while away from it. Soul shards regenerate/decay to 3.
local CHARGE_POWER, CHARGE_REST = {}, {}
for k, rest in pairs({
    HolyPower = 0, Chi = 0, SoulShards = 3, ArcaneCharges = 0, ComboPoints = 0,
}) do
    local v = Enum.PowerType and Enum.PowerType[k]
    if v then
        CHARGE_POWER[#CHARGE_POWER + 1] = v
        CHARGE_REST[v] = rest
    end
end
-- Segmented resources that recharge over time: active until refilled.
local POOL_POWER = {}
for _, k in ipairs({ "Essence", "Runes" }) do
    local v = Enum.PowerType and Enum.PowerType[k]
    if v then POOL_POWER[#POOL_POWER + 1] = v end
end

local function NumOK(v) return type(v) == "number" and not ns.IsSecret(v) end

local function HealthNeeds()
    local cur, max = UnitHealth("player"), UnitHealthMax("player")
    return NumOK(cur) and NumOK(max) and max > 0 and cur < max
end

local function PowerNeeds()
    local pt, cur, max = UnitPowerType("player"), UnitPower("player"), UnitPowerMax("player")
    if not NumOK(cur) or not NumOK(max) then return false end
    if not ns.IsSecret(pt) and ZERO_BASELINE_POWER[pt] then return cur > 0 end
    return cur < max
end

local function SegmentsNeed()
    for i = 1, #CHARGE_POWER do
        local pt = CHARGE_POWER[i]
        local cur, max = UnitPower("player", pt), UnitPowerMax("player", pt)
        if NumOK(cur) and NumOK(max) and max > 0 and cur ~= CHARGE_REST[pt] then return true end
    end
    for i = 1, #POOL_POWER do
        local cur = UnitPower("player", POOL_POWER[i])
        local max = UnitPowerMax("player", POOL_POWER[i])
        if NumOK(cur) and NumOK(max) and max > 0 and cur < max then return true end
    end
    return false
end

local function PRDWantHidden()
    return ns.db.hidePRDWhenIdle
        and not UnitAffectingCombat("player")
        and (GetSheathState() or 1) == 1
        and not (HealthNeeds() or PowerNeeds() or SegmentsNeed())
end

function ns:ApplyPRD()
    if not ns.db then return end
    local f = _G.PersonalResourceDisplayFrame
    if not f then return end
    if PRDWantHidden() and not f.isInEditMode then
        prdHidden = true
        f:SetAlpha(0)
    elseif prdHidden then
        prdHidden = false
        f:SetAlpha(1)
    end
end

function ns:ApplySettings()
    if not ns.db then return end
    SyncSuppression()
    ns:ApplyConsolePort()
    ns:ApplyPRD()
end

-- Sheath toggles fire UNIT_MODEL_CHANGED for the player; the ticker also
-- re-applies alpha when ConsolePort's own fades fight the suppression.
Nocturne.RegisterEvent("UNIT_MODEL_CHANGED", function(_, unit)
    if unit == "player" then
        ns:ApplyConsolePort()
        ns:ApplyPRD()
    end
end)
Nocturne.RegisterEvent("PLAYER_ENTERING_WORLD", function()
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
-- Health/power drift is covered by the ticker (0.5s is fast enough here);
-- combat/sheath changes above apply immediately. Idle unless a feature is
-- on or still has something faded to restore.
C_Timer.NewTicker(0.5, function()
    if not ns.db then return end
    if ns.db.hideCPCluster or cpHidden then ns:ApplyConsolePort() end
    if ns.db.hidePRDWhenIdle or prdHidden then ns:ApplyPRD() end
end)

local function SafeV(v) return ns.IsSecret(v) and "<secret>" or tostring(v) end

function ns:DiagText()
    local prd = _G.PersonalResourceDisplayFrame
    local out = {
        ("player=%s target=%s bags=%s chatCombat=%s cpCluster=%s"):format(
            tostring(ns.db.hidePlayer), tostring(ns.db.hideTarget), tostring(ns.db.hideBags),
            tostring(ns.db.hideChatInCombat), tostring(ns.db.hideCPCluster)),
        ("combat=%s group=%s sheath=%s cpInstalled=%s cpFrame=%s alpha=%s"):format(
            tostring(UnitAffectingCombat("player")), tostring(IsInGroup()),
            tostring(GetSheathState()), tostring(CPInstalled()),
            tostring(cpFrame and cpFrame:GetName()),
            tostring(cpFrame and cpFrame:GetAlpha())),
        ("prd=%s frame=%s shown=%s alpha=%s editMode=%s hidden=%s hp=%s power=%s segs=%s"):format(
            tostring(ns.db.hidePRDWhenIdle), tostring(prd ~= nil),
            tostring(prd and prd:IsShown()), prd and SafeV(prd:GetAlpha()) or "nil",
            tostring(prd and prd.isInEditMode), tostring(prdHidden),
            tostring(HealthNeeds()), tostring(PowerNeeds()), tostring(SegmentsNeed())),
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
