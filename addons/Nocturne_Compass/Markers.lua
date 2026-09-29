local _, ns = ...

local Nocturne = _G.Nocturne
local T = Nocturne.Theme

local pool = {}
local banner
local glowOn = false

local DIST_Y = -17 -- distance label offset from the bar's center
local DIST_SIZE = 9

local QC = Enum.QuestClassification

local ATLAS_FALLBACK = "QuestNormal"
local function AtlasFor(entry)
    local candidates
    if entry.isTransit then
        candidates = { "Navigation-Tracked-Arrow", "MinimapArrow" }
    elseif entry.isComplete then
        candidates = { "QuestTurnin", ATLAS_FALLBACK }
    elseif entry.isWorldQuest then
        candidates = { "worldquest-questicon-questionmark", ATLAS_FALLBACK }
    elseif entry.classification == QC.Campaign then
        candidates = { "QuestCampaign", ATLAS_FALLBACK }
    elseif entry.classification == QC.Important then
        candidates = { "QuestImportant", ATLAS_FALLBACK }
    elseif entry.classification == QC.Legendary then
        candidates = { "QuestLegendary", ATLAS_FALLBACK }
    elseif entry.classification == QC.Recurring then
        candidates = { "QuestRecurring", ATLAS_FALLBACK }
    else
        candidates = { ATLAS_FALLBACK }
    end
    for _, name in ipairs(candidates) do
        if C_Texture.GetAtlasInfo(name) then return name end
    end
end

local function CreateMarker()
    local m = CreateFrame("Frame", nil, ns.clip)
    m:SetSize(14, 14)
    m.icon = m:CreateTexture(nil, "ARTWORK")
    m.icon:SetAllPoints()
    -- Distance text lives on the main frame (not the clip) so it can hang
    -- below the strip line without being clipped.
    m.dist = ns.frame:CreateFontString(nil, "OVERLAY")
    m.dist:SetFont(T.fonts.main, DIST_SIZE, "")
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

local function ApplyIcon(m, entry)
    local atlas = AtlasFor(entry)
    local layer = entry.isSuperTracked and 2 or entry.isComplete and 1 or 0
    local sig = tostring(atlas) .. ":" .. layer
    if m._iconSig == sig then return end
    m._iconSig = sig

    if atlas then
        m.icon:SetTexture("Interface\\Buttons\\WHITE8x8") -- clear any flat color
        m.icon:SetAtlas(atlas)
    else
        -- Last resort: a flat accent square.
        m.icon:SetTexture("Interface\\Buttons\\WHITE8x8")
    end

    if entry.isSuperTracked or not atlas then
        local c = T.colors.accent
        m.icon:SetVertexColor(c[1], c[2], c[3], 1)
    else
        m.icon:SetVertexColor(1, 1, 1, 1)
    end

    -- Edge stacking order (above the drum): open < completed < super-tracked.
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

function ns:UpdateMarkers()
    local db = ns.db
    local p = ns.player
    local pxPerRad = ns.pxPerRad
    local bannerTitle, bannerDist
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

        if e.provider:IsInRegion(e) then
            m:Hide()
            m.dist:Hide()
            if not bannerDist or dist < bannerDist then
                bannerDist = dist
                bannerTitle = e.title
            end
        else
            local t = ns.math.Clamp(dist / db.scaleRange, 0, 1)
            local scale = ns.math.Lerp(db.maxScale, db.minScale, t)
            if e.isSuperTracked then scale = scale * 1.25 end

            -- Outside the compass FOV: pin the marker to the near edge of
            -- the bar (like Skyrim/ESO's compass) instead of hiding it, so
            -- the player still knows which side to turn towards. The margin
            -- accounts for this marker's own scaled size so it never gets
            -- clipped. Anchoring is deferred to the edge pass below, where
            -- same-type markers are grouped into one overlapping slot.
            local size = MARKER_SIZE * scale
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
                    m.dist:SetPoint("CENTER", ns.frame, "CENTER", x, DIST_Y)
                    m.dist:Show()
                end
            else
                m.dist:Hide()
            end
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
            m.dist:SetPoint("CENTER", ns.frame, "CENTER", x, DIST_Y)
            m.dist:Show()
        end
    end

    for _, m in pairs(pool) do
        if not m._seen then
            m:Hide()
            m.dist:Hide()
        end
    end

    -- In-region banner: steady quest/zone name below the bar + a glow on
    -- the compass frame while inside.
    local inRegion = bannerTitle ~= nil and bannerTitle ~= ""
    if inRegion ~= glowOn then
        glowOn = inRegion
        T.SetGlow(ns.frame, inRegion)
    end
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
    if db.showDistance then y = math.min(y, DIST_Y - DIST_SIZE) end
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

-- Rescan triggers: quest/zone/super-track changes. Marker positions and
-- bearings are still recomputed every frame from cached world coords.
for _, event in ipairs({
    "QUEST_WATCH_LIST_CHANGED",
    "QUEST_LOG_UPDATE",
    "QUEST_POI_UPDATE",
    "SUPER_TRACKING_CHANGED",
    "ZONE_CHANGED",
    "ZONE_CHANGED_NEW_AREA",
    "PLAYER_ENTERING_WORLD",
}) do
    Nocturne.RegisterEvent(event, function() ns.scanDirty = true end)
end
