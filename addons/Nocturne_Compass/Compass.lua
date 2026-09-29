local _, ns = ...

local Nocturne = _G.Nocturne
local T = Nocturne.Theme

-- Locals for hot-path globals (OnUpdate runs frequently): avoids the
-- global-table lookup on every call.
local GetPlayerFacing = GetPlayerFacing
local UnitAffectingCombat = UnitAffectingCombat
local IsInInstance = IsInInstance
local GetBestMapForUnit = C_Map.GetBestMapForUnit
local GetPlayerMapPosition = C_Map.GetPlayerMapPosition
local GetWorldPosFromMapPos = C_Map.GetWorldPosFromMapPos

local CARDINALS = {
    [0] = "N",
    [45] = "NE",
    [90] = "E",
    [135] = "SE",
    [180] = "S",
    [225] = "SW",
    [270] = "W",
    [315] = "NW",
}

-- Bearing/facing math lives in Math.lua (ns.FacingCW / ns.RelAngle) so it
-- has a single implementation shared by the drum, markers and diagnostics.

local letters = {}
local ticks = {}

local function SavePosition()
    local db = ns.db
    local cx, cy = ns.frame:GetCenter()
    db.point[1] = "CENTER"
    db.point[2] = cx - UIParent:GetWidth() / 2
    db.point[3] = cy - UIParent:GetHeight() / 2
end

-- Rebuilds the letters/ticks inside the drum for the current width/FOV.
function ns:RebuildDrum()
    local db = ns.db
    ns.pxPerRad = db.width / math.rad(db.fovDegrees)
    ns.drum:SetSize(ns.pxPerRad * math.pi * 4, ns.clip:GetHeight() > 0 and ns.clip:GetHeight() or db.height)

    local i = 0
    for deg = -360, 360, 45 do
        i = i + 1
        local fs = letters[i]
        if not fs then
            fs = T.CreateFontString(ns.drum, 11, nil, "OVERLAY")
            letters[i] = fs
        end
        local major = (deg % 90) == 0
        fs:SetText(CARDINALS[deg % 360])
        fs:SetFont(T.fonts.main, major and 12 or 10, "")
        local c = major and T.colors.text or T.colors.textDim
        fs:SetTextColor(c[1], c[2], c[3], c[4])
        fs:ClearAllPoints()
        fs:SetPoint("CENTER", ns.drum, "CENTER", math.rad(deg) * ns.pxPerRad, -2)
        fs:Show()
    end
    for j = i + 1, #letters do letters[j]:Hide() end

    local n = 0
    for deg = -360, 360, 15 do
        if deg % 45 ~= 0 then
            n = n + 1
            local t = ticks[n]
            if not t then
                t = ns.drum:CreateTexture(nil, "BORDER")
                t:SetWidth(1)
                local c = T.colors.stripLine
                t:SetColorTexture(c[1], c[2], c[3], c[4])
                ticks[n] = t
            end
            t:ClearAllPoints()
            t:SetPoint("TOP", ns.drum, "TOP", math.rad(deg) * ns.pxPerRad, -2)
            t:SetHeight(5)
            t:Show()
        end
    end
    for j = n + 1, #ticks do ticks[j]:Hide() end
end

function ns:ApplyLayout()
    local db = ns.db
    if not ns.frame then return end

    ns.frame:SetSize(db.width, db.height)
    ns.frame:SetAlpha(db.opacity)
    ns.frame:EnableMouse(not db.locked)

    local p = db.point
    ns.frame:ClearAllPoints()
    ns.frame:SetPoint(p[1] or "CENTER", UIParent, p[1] or "CENTER", p[2] or 0, p[3] or 0)

    ns.coords:SetShown(db.showHeading)
    ns:RebuildDrum()
    ns:ApplyBanner()
end

local function UpdatePlayer()
    local p = ns.player
    -- Derive the player's world position through the same API used for POIs
    -- so both ends always share the same coordinate frame.
    local mapID = GetBestMapForUnit("player")
    p.mapID = mapID
    p.mapX, p.mapY = nil, nil
    if mapID then
        local pos = GetPlayerMapPosition(mapID, "player")
        if pos then
            if not ns.IsSecret(pos.x) and not ns.IsSecret(pos.y) then
                p.mapX, p.mapY = pos:GetXY()
            end
            local inst, wpos = GetWorldPosFromMapPos(mapID, pos)
            if inst and wpos and not ns.IsSecret(wpos.x) and not ns.IsSecret(wpos.y) then
                p.x, p.y = wpos:GetXY()
                p.instance = inst
            end
        end
    end
    local facing = GetPlayerFacing()
    if not ns.IsSecret(facing) then
        p.facing = facing -- nil while inside instances
    end
end

local function ShouldHide()
    local p = ns.player
    if not p.facing then return true end
    if ns.db.hideInCombat and UnitAffectingCombat("player") then return true end
    if ns.db.hideInInstances then
        local _, instanceType = IsInInstance()
        if instanceType and instanceType ~= "none" then return true end
    end
    return false
end

-- Throttled to 60Hz: smooth enough to not be perceptible while still capping
-- cost on uncapped framerates well above that.
local UPDATE_INTERVAL = 1 / 60
local sinceUpdate = 0

local function OnUpdate(_, elapsed)
    sinceUpdate = sinceUpdate + elapsed
    if sinceUpdate < UPDATE_INTERVAL then return end
    sinceUpdate = 0

    if not ns.db.enabled then
        ns.frame:SetAlpha(0)
        ns.frame:EnableMouse(false)
        return
    end

    UpdatePlayer()

    if ShouldHide() then
        ns.frame:SetAlpha(0)
        ns.frame:EnableMouse(false)
        return
    end
    ns.frame:SetAlpha(ns.db.opacity)
    ns.frame:EnableMouse(not ns.db.locked)

    local facingCW = ns.FacingCW() or 0

    ns.drum:ClearAllPoints()
    ns.drum:SetPoint("CENTER", ns.clip, "CENTER", -facingCW * ns.pxPerRad, 0)

    if ns.db.showHeading then
        local p = ns.player
        if p.mapX then
            ns.coords:SetFormattedText("%.1f, %.1f", p.mapX * 100, p.mapY * 100)
        else
            ns.coords:SetText("")
        end
    end

    if ns.scanDirty then
        ns.scanDirty = false
        ns:RescanPOI()
    end
    ns:UpdateMarkers()
end

function ns:CreateCompassFrame()
    local f = CreateFrame("Frame", "NocturneCompassFrame", UIParent)
    ns.frame = f

    T.ApplyBackdrop(f)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        if not ns.db.locked then self:StartMoving() end
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition()
    end)

    local clip = CreateFrame("Frame", nil, f)
    clip:SetPoint("TOPLEFT", 3, -3)
    clip:SetPoint("BOTTOMRIGHT", -3, 3)
    clip:SetClipsChildren(true)
    ns.clip = clip

    -- Center indicator under the current heading.
    local center = clip:CreateTexture(nil, "ARTWORK")
    center:SetSize(1, 8)
    center:SetPoint("CENTER", clip, "CENTER", 0, 0)
    local ac = T.colors.accent
    center:SetColorTexture(ac[1], ac[2], ac[3], 1)
    ns.centerTick = center

    local drum = CreateFrame("Frame", nil, clip)
    ns.drum = drum

    local coords = T.CreateFontString(f, 12, T.colors.accent, "OVERLAY", "OUTLINE")
    coords:SetPoint("BOTTOM", f, "TOP", 0, 1)
    ns.coords = coords

    f:SetScript("OnUpdate", OnUpdate)

    ns:ApplyLayout()
end
