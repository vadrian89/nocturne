local _, ns = ...

local Nocturne = _G.Nocturne
local T = Nocturne.Theme

local pool = {}
local banner
local glowOn = false

local DIST_SIZE = 16
-- The selected (super-tracked) marker is at least this many bar heights
-- tall and isn't clipped, so it pokes out above and below the bar.
local SELECTED_POP = 1.4
local SELECTED_SCALE = 1.25

-- Height of the selected marker at its usual (smallest) pop-out size; the
-- labels above the bar keep clear of it.
function ns:SelectedPopHeight()
    return ns.db.height * SELECTED_POP
end

-- Distance label offset for a marker of `size`: its top sits 4px under the
-- icon's bottom edge (labels anchor TOP at this offset).
local function DistY(size)
    return -size / 2 - 4
end

local GetPOITextureCoords = (C_Minimap and C_Minimap.GetPOITextureCoords) or _G.GetPOITextureCoords
local POI_TEXTURE = "Interface\\Minimap\\POIIcons"

local function CreateMarker()
    local m = CreateFrame("Frame", nil, ns.clip)
    m:SetSize(14, 14)
    m.icon = m:CreateTexture(nil, "ARTWORK")
    m.icon:SetAllPoints()
    -- Distance text lives on the main frame (not the clip) so it can hang
    -- below the strip line without being clipped.
    m.dist = ns.frame:CreateFontString(nil, "OVERLAY")
    m.dist:SetFont(T.fonts.main, DIST_SIZE, "OUTLINE")
    m.dist:SetTextColor(unpack(T.colors.textDim))
    return m
end

local function GetMarker(key)
    local m = pool[key]
    if not m then
        m = CreateMarker()
        pool[key] = m
    end
    return m
end

-- Exposed read-only accessor for diagnostics (/ncmp diag).
function ns:GetMarkerFrame(key)
    return pool[key]
end

-- Providers resolve and validate the icon at scan time: `entry.atlas`, or a
-- POI texture index for map icons without an atlas.
local function ApplyIcon(m, entry)
    local atlas = entry.atlas
    local layer = entry.isSuperTracked and 2 or entry.isComplete and 1 or 0
    local sig = tostring(atlas or entry.icon or entry.textureIndex) .. ":" .. layer
    if m._iconSig == sig then return end
    m._iconSig = sig

    local drawn = true
    if atlas then
        m.icon:SetTexture("Interface\\Buttons\\WHITE8x8") -- clear any flat color
        m.icon:SetAtlas(atlas)
    elseif entry.icon then
        m.icon:SetTexture(entry.icon)
        m.icon:SetTexCoord(0, 1, 0, 1)
    elseif entry.textureIndex and GetPOITextureCoords then
        m.icon:SetTexture(POI_TEXTURE)
        m.icon:SetTexCoord(GetPOITextureCoords(entry.textureIndex))
    else
        -- Last resort: a flat accent square.
        m.icon:SetTexture("Interface\\Buttons\\WHITE8x8")
        m.icon:SetTexCoord(0, 1, 0, 1)
        drawn = false
    end

    if not drawn then
        local c = T.colors.accent
        m.icon:SetVertexColor(c[1], c[2], c[3], 1)
    else
        m.icon:SetVertexColor(1, 1, 1, 1)
    end

    -- Edge stacking order (above the drum): open < completed < super-tracked.
    m:SetParent(entry.isSuperTracked and ns.frame or ns.clip)
    m:SetFrameLevel(ns.clip:GetFrameLevel() + 1 + layer)
    m.dist:SetDrawLayer("OVERLAY", layer)
end

function ns:RescanPOI()
    local p = ns.player
    local results = {}
    if p.mapID and p.instance then
        for _, prov in ipairs(ns.providers) do
            for _, e in ipairs(prov:Scan(p.mapID, p.instance)) do
                results[#results + 1] = e
            end
        end
    end
    ns.scanResults = results
end

local MARKER_SIZE = 14
local EDGE_PAD = 3     -- extra breathing room beyond the icon's own half-size
local EDGE_GAP = 2     -- spacing between marker groups fanned out at the same edge
local EDGE_SHIFT = 0.5 -- completed stack's inward shift, as a fraction of the open stack's width
local EDGE_ALPHA = 0.5 -- out-of-FOV (behind) markers pinned to the edge
-- Directly behind the player |rel| sits near pi and flips sign on the
-- slightest turn; keep the previous edge until it clearly moves past.
local BEHIND_HYST = math.rad(10)

-- Per-frame scratch for the edge pass (reused, no per-frame churn). At-edge
-- markers of one provider share a slot; inside it, open and completed
-- entries form two stacks (edgeMax[1] / edgeMax[2], keyed [side][provider])
-- that partially overlap.
local edgeList = {}
local edgeMax = { { [-1] = {}, [1] = {} }, { [-1] = {}, [1] = {} } }
local edgeOff = { [-1] = {}, [1] = {} }
local edgeUsed = { [-1] = 0, [1] = 0 }

-- Anchor points define the clip's size lazily; GetWidth() can briefly read 0
-- before the layout engine resolves it (e.g. right after login/reload), so
-- fall back to the configured bar width instead of clamping everything to
-- a sliver around the center. `margin` should be the current marker's own
-- half-size (scaled) so a large, close marker never gets cut by the clip.
function ns:EdgeHalfWidth(margin)
    local w = ns.clip and ns.clip:GetWidth()
    if not w or w <= 0 then w = ns.db.width end
    return w / 2 - (margin or EDGE_PAD)
end

local function SetInRegion(on)
    if on ~= glowOn then
        glowOn = on
        T.SetGlow(ns.frame, on)
    end
end

-- Navigation unavailable (instances): clear every marker, label and banner.
function ns:HideMarkers()
    for _, m in pairs(pool) do
        m:Hide()
        m.dist:Hide()
    end
    banner._title = nil
    banner:Hide()
    SetInRegion(false)
end

function ns:UpdateMarkers()
    local db = ns.db
    local p = ns.player
    local pxPerRad = ns.pxPerRad
    local bannerTitle, bannerDist, bannerGlow
    -- Flying over a POI on a flight path isn't "arriving": no glow/banner.
    local onTaxi = UnitOnTaxi and UnitOnTaxi("player") or false
    local edgeN = 0
    wipe(edgeMax[1][-1])
    wipe(edgeMax[1][1])
    wipe(edgeMax[2][-1])
    wipe(edgeMax[2][1])
    wipe(edgeOff[-1])
    wipe(edgeOff[1])
    edgeUsed[-1], edgeUsed[1] = 0, 0

    for _, m in pairs(pool) do m._seen = false end

    for _, e in ipairs(ns.scanResults) do
        local m = GetMarker(e.key)
        m._seen = true
        ApplyIcon(m, e)

        local dx, dy = e.x - p.x, e.y - p.y
        local dist = ns.math.Distance(dx, dy)
        local rel = ns.RelAngle(dx, dy)
        if m._side and math.abs(rel) > math.pi - BEHIND_HYST then
            rel = m._side * math.abs(rel)
        end
        m._side = rel < 0 and -1 or 1
        -- Transit arrow (drawn pointing up = straight ahead) turns towards
        -- the waypoint; SetRotation is CCW while rel > 0 means right. Other
        -- icons are only reset once, so POI sheet crops are never touched.
        if e.isTransit then
            m.icon:SetRotation(-rel)
            m._rotated = true
        elseif m._rotated then
            m.icon:SetRotation(0)
            m._rotated = false
        end

        if not onTaxi and e.provider:IsInRegion(e, dist)
            and (not bannerDist or dist < bannerDist) then
            bannerDist = dist
            bannerTitle = e.title
            bannerGlow = e.provider.glowInRegion
        end

        local t = ns.math.Clamp(dist / db.scaleRange, 0, 1)
        local scale = ns.math.Lerp(db.maxScale, db.minScale, t)
        if e.isSuperTracked then
            scale = math.max(scale * SELECTED_SCALE, db.height * SELECTED_POP / MARKER_SIZE)
        end

        -- Outside the compass FOV: pin the marker to the near edge of
        -- the bar (like Skyrim/ESO's compass) instead of hiding it, so
        -- the player still knows which side to turn towards. The margin
        -- accounts for this marker's own scaled size so it never gets
        -- clipped. Anchoring is deferred to the edge pass below, where
        -- same-type markers are grouped into one overlapping slot.
        local size = MARKER_SIZE * scale
        m._distY = DistY(size)
        local halfW = ns:EdgeHalfWidth(size / 2 + EDGE_PAD)
        local rawX = rel * pxPerRad
        local x = ns.math.Clamp(rawX, -halfW, halfW)
        local atEdge = x ~= rawX

        m:Show()
        m:ClearAllPoints()
        m:SetScale(scale)
        local alpha = 1
        if not e.isSuperTracked then
            alpha = atEdge and EDGE_ALPHA or ns.math.Lerp(1, 0.45, t)
        end
        m:SetAlpha(alpha)

        if atEdge then
            local side = x < 0 and -1 or 1
            local group = e.provider.name
            local stack = e.isComplete and 2 or 1
            local gm = edgeMax[stack][side]
            if (gm[group] or 0) < size then gm[group] = size end
            m._eside, m._egroup, m._estack = side, group, stack
            edgeN = edgeN + 1
            edgeList[edgeN] = m
        else
            -- SetPoint offsets are in the anchored frame's OWN scaled
            -- space (proven via /ncmp diag): divide by the marker's
            -- scale so x stays in clip units.
            m:SetPoint("CENTER", ns.clip, "CENTER", x / scale, 0)
        end

        if db.showDistance then
            m.dist:SetText(BreakUpLargeNumbers(math.floor(dist + 0.5)))
            m.dist:SetAlpha((atEdge and not e.isSuperTracked) and EDGE_ALPHA or 1)
            m.dist:ClearAllPoints()
            if not atEdge then
                m.dist:SetPoint("TOP", ns.frame, "CENTER", x, m._distY)
                m.dist:Show()
            end
        else
            m.dist:Hide()
        end
    end

    -- Edge pass: each provider gets a slot fanned inward from the edge. In
    -- the slot, open entries stack at the edge and completed ones stack
    -- shifted inward, partially covering them. Stacked distance labels
    -- overlap too — unreadable, but kept per-marker.
    for i = 1, edgeN do
        local m = edgeList[i]
        edgeList[i] = nil
        local side, group, stack = m._eside, m._egroup, m._estack
        local openW = edgeMax[1][side][group]
        local doneW = edgeMax[2][side][group]
        local shift = (openW and doneW) and openW * EDGE_SHIFT or 0
        local offs = edgeOff[side]
        local off = offs[group]
        if not off then
            off = edgeUsed[side]
            offs[group] = off
            edgeUsed[side] = off + math.max(openW or 0, shift + (doneW or 0)) + EDGE_GAP
        end
        local w = stack == 2 and doneW or openW
        if stack == 2 then off = off + shift end
        local x = side * ns:EdgeHalfWidth(w / 2 + EDGE_PAD + off)
        m:SetPoint("CENTER", ns.clip, "CENTER", x / m:GetScale(), 0)
        if db.showDistance then
            m.dist:SetPoint("TOP", ns.frame, "CENTER", x, m._distY)
            m.dist:Show()
        end
    end

    for _, m in pairs(pool) do
        if not m._seen then
            m:Hide()
            m.dist:Hide()
        end
    end

    -- In-region banner: steady quest/zone name below the bar; the glow on
    -- the compass frame only for quest regions.
    local inRegion = bannerTitle ~= nil and bannerTitle ~= ""
    SetInRegion(inRegion and bannerGlow or false)
    if inRegion then
        if banner._title ~= bannerTitle then
            banner._title = bannerTitle
            banner:SetText(bannerTitle)
        end
        banner:Show()
    else
        banner._title = nil
        banner:Hide()
    end
end

-- Sits below the bar, and below the distance labels when they're shown so
-- the two never overlap.
function ns:ApplyBanner()
    if not banner then return end
    local db = ns.db
    local y = -db.height / 2 - 4
    if db.showDistance then
        -- Clear the largest the selected marker can get (close + max scale).
        local selectedMax = math.max(db.height * SELECTED_POP, MARKER_SIZE * db.maxScale * SELECTED_SCALE)
        y = math.min(y, DistY(selectedMax) - DIST_SIZE)
    end
    banner:SetFont(T.fonts.main, db.bannerSize, "OUTLINE")
    banner:ClearAllPoints()
    banner:SetPoint("TOP", ns.frame, "CENTER", 0, y)
end

function ns:InitMarkers()
    banner = ns.frame:CreateFontString(nil, "OVERLAY")
    banner:SetTextColor(1, 1, 1, 1)
    banner:Hide()
    ns:ApplyBanner()
end

ns.RescanOn({
    "QUEST_WATCH_LIST_CHANGED",
    "QUEST_LOG_UPDATE",
    "QUEST_POI_UPDATE",
    "ZONE_CHANGED",
})
ns.RescanOn({
    "SUPER_TRACKING_CHANGED",
    "SUPER_TRACKING_PATH_UPDATED",
    "QUESTLINE_UPDATE",
    "ZONE_CHANGED_NEW_AREA",
    "PLAYER_ENTERING_WORLD",
}, true)
