local _, ns = ...

local Nocturne = _G.Nocturne
local T = Nocturne.Theme

local UnitExists = UnitExists
local UnitCanAttack = UnitCanAttack
local UnitIsBossMob = UnitIsBossMob
local UnitClassification = UnitClassification
local UnitName = UnitName
local function RawPercent(cur, max)
    if not max or max <= 0 then return 0 end
    return cur / max
end
local UnitHealthPercent = UnitHealthPercent or function(unit)
    return RawPercent(UnitHealth(unit), UnitHealthMax(unit))
end
local UnitPowerPercent = UnitPowerPercent or function(unit, ptype)
    return RawPercent(UnitPower(unit, ptype), UnitPowerMax(unit, ptype))
end
local UnitPowerType = UnitPowerType
local UnitPowerMax = UnitPowerMax
local UnitGUID = UnitGUID
local strsplit = strsplit
local CurveConstants = CurveConstants

-- UnitHealthPercent's optional curve scales the (secret) 0-1 result to a
-- displayable 0-100 so SetFormattedText can render it without Lua ever
-- reading the value.
local PCT_SCALE = CurveConstants and CurveConstants.ScaleTo100

-- "Above medium difficulty": elite+ classifications, plus skull-level bosses
-- (UnitIsBossMob covers "worldboss" and ??-level mobs). Atlases match the
-- small nameplate badges from NamePlateClassificationFrame — the
-- TargetFrame "PortraitOn-Boss" atlases are portrait rings, not icons.
-- SetAtlas is called WITHOUT useAtlasSize so the 26px SetSize holds.
local BOSS_ATLAS = {
    rare      = "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Rare-Star",
    rareelite = "nameplates-icon-elite-silver",
    elite     = "nameplates-icon-elite-gold",
    boss      = "nameplates-icon-elite-gold",
}
local BOSS_TEXTURE = {
    rare      = "Interface\\TargetingFrame\\UI-TargetingFrame-Rare",
    rareelite = "Interface\\TargetingFrame\\UI-TargetingFrame-Rare-Elite",
    elite     = "Interface\\TargetingFrame\\UI-TargetingFrame-Elite",
    boss      = "Interface\\TargetingFrame\\UI-TargetingFrame-Elite",
}

local function BossKind()
    if not UnitExists("target") then return nil end
    local attackable = UnitCanAttack("player", "target")
    if ns.IsSecret(attackable) then return nil end
    if not attackable then return nil end
    local boss = UnitIsBossMob("target")
    if ns.IsSecret(boss) then return nil end
    if boss then return "boss" end
    local c = UnitClassification("target")
    if ns.IsSecret(c) or not BOSS_ATLAS[c] then return nil end
    return c
end

-- Each bar lives in its own dark bordered wrap; the outer frame is an
-- invisible anchor only — no single black box around everything.
local function NewBar(f, relativeTo, yOfs, height)
    local wrap = CreateFrame("Frame", nil, f)
    if relativeTo then
        wrap:SetPoint("TOPLEFT", relativeTo, "BOTTOMLEFT", 0, yOfs)
        wrap:SetPoint("TOPRIGHT", relativeTo, "BOTTOMRIGHT", 0, yOfs)
    else
        wrap:SetPoint("TOPLEFT", f, "TOPLEFT", 32, yOfs)
        wrap:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, yOfs)
    end
    wrap:SetHeight(height)
    T.ApplyBackdrop(wrap)
    local bg = wrap:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.85)

    local bar = CreateFrame("StatusBar", nil, wrap)
    bar:SetPoint("TOPLEFT", 2, -2)
    bar:SetPoint("BOTTOMRIGHT", -2, 2)
    bar:SetMinMaxValues(0, 1)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    return wrap, bar
end

-- Vertical layout: a name zone on top, then the hp wrap, a gap, the power
-- wrap. The hp wrap matches the compass bar height when it's installed.
local NAME_H = 14
local BAR_GAP = 2
local POWER_H = 9
local BOT_PAD = 4

local function CreateBossFrame()
    local f = CreateFrame("Frame", "NocturneExtraBossFrame", UIParent)
    f:SetFrameStrata("MEDIUM")
    f:Hide()

    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetSize(28, 28)
    f.icon = icon

    local hpWrap, hp = NewBar(f, nil, -NAME_H, 28)
    local ppWrap, pp = NewBar(f, hpWrap, -BAR_GAP, POWER_H)
    f.hpWrap = hpWrap
    f.hp = hp
    f.pp = pp
    -- Badge centered on the hp bar, tight to its left.
    icon:SetPoint("RIGHT", hpWrap, "LEFT", -4, 0)
    hp:GetStatusBarTexture():SetVertexColor(0.0, 1.0, 0.0)
    pp:GetStatusBarTexture():SetVertexColor(0.30, 0.40, 0.90)

    -- Name floats above the hp bar, centered on it — no backdrop.
    local name = T.CreateFontString(f, 11, nil, "OVERLAY", "OUTLINE")
    name:SetPoint("BOTTOMLEFT", hpWrap, "TOPLEFT", 0, 1)
    name:SetPoint("BOTTOMRIGHT", hpWrap, "TOPRIGHT", 0, 1)
    name:SetJustifyH("CENTER")
    f.name = name

    local hpText = T.CreateFontString(hp, 18, nil, "OVERLAY", "OUTLINE")
    hpText:SetPoint("RIGHT", -3, 0)
    f.hpText = hpText

    -- Phase breakpoints: no API exposes them (C_EncounterTimeline is
    -- time-based only), so ticks are either learned per-NPC (see Sync) or
    -- fall back to static quarter marks. Pool grows on demand.
    f.phaseTicks = {}

    return f
end

local function AnchorToCompass(f)
    local cmod = Nocturne.modules.compass
    local w = (cmod and cmod.db and cmod.db.width) or 460
    local hpH = (cmod and cmod.db and cmod.db.height) or 28
    local nameSize = (ns.db and ns.db.bossNameSize) or 12
    if f.lastW ~= w or f.lastH ~= hpH or f.lastName ~= nameSize then
        f.lastW, f.lastH, f.lastName = w, hpH, nameSize
        f:SetSize(w, NAME_H + hpH + BAR_GAP + POWER_H + BOT_PAD)
        f.hpWrap:SetHeight(hpH)
        f.name:SetFont(T.fonts.main, nameSize, "OUTLINE")
    end
    f:ClearAllPoints()
    if cmod and cmod.frame then
        f:SetPoint("CENTER", cmod.frame, "CENTER")
    else
        f:SetPoint("TOP", UIParent, "TOP", 0, -60)
    end
end

-- Learned phase breakpoints per npcID, persisted in SavedVariables. Two
-- phase-change signals don't require reading values: the boss's power bar
-- filling then dumping (the "resource -> mechanic" pattern) and the boss
-- going unattackable mid-fight (intermission). The hp percent AT that moment
-- is recorded. Only works where the client leaves unit values readable —
-- where UnitHealthPercent is secret there is nothing to record.
local DEFAULT_TICKS = { 0.25, 0.5, 0.75 }
local lastGuid, npcID, wasAttackable, lastPower
local preview = false

local function LearnPhase(hpPct)
    if not (ns.db and npcID and hpPct) or ns.IsSecret(hpPct) then return end
    if hpPct <= 0.02 or hpPct >= 0.98 then return end
    local list = ns.db.bossPhases[npcID]
    if not list then
        list = {}
        ns.db.bossPhases[npcID] = list
    end
    for _, p in ipairs(list) do
        if math.abs(p - hpPct) < 0.02 then return end
    end
    if #list >= 8 then return end
    list[#list + 1] = hpPct
    table.sort(list, function(a, b) return a > b end)
    Nocturne.Print(("Extra: learned phase boundary at %d%% for %s."):format(
        hpPct * 100, tostring(npcID)))
end

local function TickAt(f, i)
    local t = f.phaseTicks[i]
    if not t then
        t = f.hp:CreateTexture(nil, "OVERLAY")
        t:SetWidth(1)
        t:SetColorTexture(0, 0, 0, 1)
        f.phaseTicks[i] = t
    end
    t:Show()
    return t
end

local function RenderBars(f, name, iconKind, hpPct, hpPctText, breaks, ppct, color)
    f.name:SetText(name)
    if not f.icon:SetAtlas(BOSS_ATLAS[iconKind]) then
        f.icon:SetTexture(BOSS_TEXTURE[iconKind])
    end
    f.hp:SetValue(hpPct or 0)
    -- hpPctText is a 0-100 number or a secret; SetFormattedText renders
    -- either without Lua touching it.
    if hpPctText ~= nil then
        f.hpText:SetFormattedText("%d%%", hpPctText)
    else
        f.hpText:SetText("")
    end
    -- Bar width = frame width minus icon+gap (32) minus wrap insets (4).
    local barW = (f.lastW or 460) - 36
    for i, p in ipairs(breaks) do
        local t = TickAt(f, i)
        t:ClearAllPoints()
        -- Full bar height: TOP and BOTTOM anchors stretch the tick.
        t:SetPoint("TOP", f.hp, "TOPLEFT", p * barW, 0)
        t:SetPoint("BOTTOM", f.hp, "BOTTOMLEFT", p * barW, 0)
    end
    for i = #breaks + 1, #f.phaseTicks do f.phaseTicks[i]:Hide() end
    f.pp:SetShown(ppct ~= nil)
    if ppct then
        f.pp:SetValue(ppct)
        local c = color or { r = 0.30, g = 0.40, b = 0.90 }
        f.pp:SetStatusBarColor(c.r, c.g, c.b)
    end
end

local function Sync()
    local f = ns.bossFrame
    if not f then
        f = CreateBossFrame()
        ns.bossFrame = f
    end
    if preview then
        AnchorToCompass(f)
        f:Show()
        RenderBars(f, "Boss Preview", "boss", 0.73, 73, DEFAULT_TICKS, 0.62,
            PowerBarColor and PowerBarColor["MANA"])
        return
    end
    local kind = (ns.db and ns.db.bossFrame) and BossKind() or nil
    if not kind then
        -- Intermission detector: same unit still targeted but just turned
        -- unattackable — snapshot its hp as a phase boundary.
        if wasAttackable and ns.db and ns.db.bossFrame then
            local guid = UnitGUID("target")
            if guid and not ns.IsSecret(guid) and guid == lastGuid then
                LearnPhase(UnitHealthPercent("target"))
            end
        end
        wasAttackable = false
        lastPower = nil
        lastGuid, npcID = nil, nil
        f:Hide()
        return
    end
    local guid = UnitGUID("target")
    if guid and not ns.IsSecret(guid) then
        if guid ~= lastGuid then
            lastGuid = guid
            npcID = tonumber((select(6, strsplit("-", guid))))
        end
    else
        lastGuid, npcID = nil, nil
    end
    wasAttackable = true
    AnchorToCompass(f)
    f:Show()

    local name = UnitName("target")
    name = (name and not ns.IsSecret(name)) and name or ""

    -- StatusBar:SetValue accepts secret values; the percent APIs are the
    -- sanctioned feed on this client. The scaled variant feeds the text so
    -- the percent shows even when the value itself is secret.
    local pct = UnitHealthPercent("target")
    local pctText = PCT_SCALE and UnitHealthPercent("target", true, PCT_SCALE) or nil

    -- Ticks: learned breakpoints for this NPC, else quarter marks.
    local breaks = (ns.db and npcID and ns.db.bossPhases[npcID]) or DEFAULT_TICKS

    local ptype, token = UnitPowerType("target")
    local pmax = UnitPowerMax("target")
    -- Secret values short-circuit `and` but still throw on `>`; test secrecy
    -- first, compare only plain numbers.
    local hasPower = false
    if ns.IsSecret(pmax) then
        hasPower = true
    elseif pmax then
        hasPower = pmax > 0
    end
    local ppct = hasPower and UnitPowerPercent("target", ptype) or nil
    local c = token and PowerBarColor and PowerBarColor[token]

    RenderBars(f, name, kind, pct, pctText, breaks, hasPower and (ppct or 0) or nil, c)

    -- Fill-then-dump detector: power pegged near max then released back to
    -- baseline means the resource mechanic fired — a phase boundary.
    if ppct and not ns.IsSecret(ppct) then
        if lastPower and lastPower >= 0.9 and ppct <= 0.3 then
            LearnPhase(pct)
        end
        lastPower = ppct
    else
        lastPower = nil
    end
end

-- Queried by Nocturne_Compass's ShouldHide so the boss frame takes the
-- compass's spot instead of overlapping it.
function ns:IsBossFrameUp()
    return self.bossFrame and self.bossFrame:IsShown() or false
end

-- Re-applies on settings changes too (ApplySettings calls it via Frames.lua).
function ns:SyncBossFrame()
    Sync()
end

-- Preview with fake data so the frame can be checked without a boss target.
function ns:ToggleBossFramePreview()
    preview = not preview
    Sync()
    Nocturne.Print("Extra: boss frame preview " .. (preview and "ON" or "OFF") .. ".")
end

Nocturne.RegisterEvent("PLAYER_TARGET_CHANGED", Sync)
for _, event in ipairs({
    "UNIT_HEALTH", "UNIT_MAXHEALTH",
    "UNIT_POWER_UPDATE", "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER",
    "UNIT_CLASSIFICATION_CHANGED", "UNIT_NAME_UPDATE", "UNIT_FACTION",
}) do
    Nocturne.RegisterEvent(event, function(_, unit)
        if unit == "target" then Sync() end
    end)
end
