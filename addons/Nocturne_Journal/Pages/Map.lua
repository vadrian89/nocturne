local _, ns = ...

local Nocturne = _G.Nocturne
local T = Nocturne.Theme

local MARGIN, GAP = ns.JournalMargin, ns.JournalGap
local EMPTY = {}

local PAN_TICK = 0.045   -- host fraction per D-pad repeat tick
local STICK_SPEED = 0.55 -- host fraction per second at full deflection
local ZOOM_STEP = 1.3
local ZOOM_MIN, ZOOM_MAX = 1, 10
local ZOOM_RATE = 12     -- ease speed toward the target zoom (1/s)
local PLAYER_TICK = 0.15 -- seconds between player-marker refreshes

local DIR = {
    PADDUP = { 0, -1 },
    PADDDOWN = { 0, 1 },
    PADDLEFT = { -1, 0 },
    PADDRIGHT = { 1, 0 },
}

local PIN_GOLD = { 0.85, 0.65, 0.15, 1 }
local PIN_DONE = { 0.30, 0.75, 0.35, 1 }
local LIST_W = 280
local PIN_SIZE = 38        -- every marker (quest, POI, taxi, transit)
local PIN_SIZE_SUPER = 48  -- the super-tracked quest marker
local QUEST_OVERDRAW = 1.3 -- quest disc art vs pin box (atlas padding)
local GetPOITextureCoords = (C_Minimap and C_Minimap.GetPOITextureCoords)
    or _G.GetPOITextureCoords
local POI_TEXTURE = "Interface\\Minimap\\POIIcons"

local function MapInfo(mapID)
    if not (C_Map and C_Map.GetMapInfo) then return end
    local ok, info = pcall(C_Map.GetMapInfo, mapID)
    if ok and type(info) == "table" then return info end
end

local function PlayerPos(mapID)
    if not (C_Map and C_Map.GetPlayerMapPosition) then return end
    local ok, pos = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
    if ok and pos and pos.GetXY then
        local x, y = pos:GetXY()
        if type(x) == "number" and type(y) == "number"
            and not ns.IsSecret(x) and not ns.IsSecret(y) then
            return x, y
        end
    end
end

local function SuperID()
    if not (C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID) then
        return
    end
    local id = C_SuperTrack.GetSuperTrackedQuestID()
    if id and not ns.IsSecret(id) then return id end
end

-- Artwork layers: retail field names (tileRows/tileCols/textureWidth) are
-- probed into ns.mapDiagArtKeys once, since Forever's schema is unverified.
local function CollectArt(mapID, data)
    if not (C_Map.GetMapArtLayers and C_Map.GetMapArtLayerTextures) then
        return
    end
    local ok, layers = pcall(C_Map.GetMapArtLayers, mapID)
    if not (ok and type(layers) == "table") then return end
    local layer
    for _, l in ipairs(layers) do
        if type(l) == "table" then
            layer = l
            break
        end
    end
    if not layer then return end
    if not ns.mapDiagArtKeys then
        local ks = {}
        for k in pairs(layer) do ks[#ks + 1] = tostring(k) end
        table.sort(ks)
        ns.mapDiagArtKeys = table.concat(ks, ",")
    end
    -- Forever's layerInfo carries no layerIndex and no tile counts; the
    -- textures call is 1-based there (idx 0 answers empty). The coordinate
    -- space is layerWidth×layerHeight file px while tiles tile a larger
    -- 256-px grid — both sizes are kept.
    local ids, usedIdx
    -- No holes in the candidate list: a leading nil (Forever has no
    -- layerIndex) would stop ipairs at once.
    local cand = { 1, 0, 2 }
    if layer.layerIndex then table.insert(cand, 1, layer.layerIndex) end
    for _, idx in ipairs(cand) do
        if idx then
            local okt, t = pcall(C_Map.GetMapArtLayerTextures, mapID, idx)
            if okt and type(t) == "table" and #t > 0 then
                ids, usedIdx = t, idx
                break
            end
        end
    end
    ns.mapDiagArtIdx = usedIdx or "none"
    if not ids then return end
    data.texIDs = ids
    data.tileW = layer.tileWidth or 256
    data.tileH = layer.tileHeight or 256
    data.texW = layer.textureWidth or layer.layerWidth
        or data.tileW * math.ceil(math.sqrt(#ids))
    data.texH = layer.textureHeight or layer.layerHeight
        or data.tileH * math.ceil(math.sqrt(#ids))
    data.cols = layer.tileCols or layer.cols
        or math.ceil(data.texW / data.tileW)
    data.rows = layer.tileRows or layer.rows
        or math.ceil(data.texH / data.tileH)
    if #ids > data.cols * data.rows then
        data.rows = math.ceil(#ids / data.cols)
    end
    data.gridW = data.cols * data.tileW
    data.gridH = data.rows * data.tileH
end

local function CollectQuests(mapID, data)
    data.quests = {}
    if not (C_QuestLog and C_QuestLog.GetQuestsOnMap) then return end
    local ok, qs = pcall(C_QuestLog.GetQuestsOnMap, mapID)
    if not (ok and type(qs) == "table") then return end
    for _, q in ipairs(qs) do
        if type(q) == "table" and q.questID
            and type(q.x) == "number" and type(q.y) == "number"
            and not ns.IsSecret(q.x) then
            data.quests[#data.quests + 1] = q
        end
    end
end

-- Explored-area overlays: the base layer is the "undiscovered" parchment;
-- each explored area carries its own texture(s) + offset in map file-px.
local function CollectExplored(mapID, data)
    data.explored = {}
    local f = C_MapExplorationInfo
        and C_MapExplorationInfo.GetExploredMapTextures
    if not f then return end
    local ok, areas = pcall(f, mapID)
    if not (ok and type(areas) == "table") then return end
    if not ns.mapDiagExpKeys and type(areas[1]) == "table" then
        local ks = {}
        for k in pairs(areas[1]) do ks[#ks + 1] = tostring(k) end
        table.sort(ks)
        ns.mapDiagExpKeys = table.concat(ks, ",")
    end
    for _, a in ipairs(areas) do
        -- Forever's schema: fileDataIDs, textureWidth/Height, offsetX/Y,
        -- isDrawOnTopLayer, isShownByMouseOver, hitRect.
        local w = type(a) == "table"
            and (a.fileWidth or a.textureWidth)
        local h = type(a) == "table"
            and (a.fileHeight or a.textureHeight)
        if w and h and type(a.fileDataIDs) == "table"
            and a.offsetX and a.offsetY then
            data.explored[#data.explored + 1] = {
                ids = a.fileDataIDs,
                x = a.offsetX,
                y = a.offsetY,
                w = w,
                h = h,
            }
        end
    end
end

-- Other points of interest: area POIs (towns, vendors) and taxi nodes.
-- Coordinates come back as Vector2D; schemas are dumped to diag once.
local function CollectPOIs(mapID, data)
    data.pois = {}
    if C_AreaPoiInfo and C_AreaPoiInfo.GetAreaPOIForMap
        and C_AreaPoiInfo.GetAreaPOIInfo then
        local ok, ids = pcall(C_AreaPoiInfo.GetAreaPOIForMap, mapID)
        if ok and type(ids) == "table" then
            for _, poiID in ipairs(ids) do
                local okI, info = pcall(C_AreaPoiInfo.GetAreaPOIInfo,
                    mapID, poiID)
                if okI and type(info) == "table" then
                    if not ns.mapDiagPoiKeys then
                        local ks = {}
                        for k in pairs(info) do
                            ks[#ks + 1] = tostring(k)
                        end
                        table.sort(ks)
                        ns.mapDiagPoiKeys = table.concat(ks, ",")
                    end
                    -- POIs that link out to another map (city listings on
                    -- the parent map etc.) don't belong to this zone.
                    local link = info.linkedUiMapID or info.uiMapID
                        or info.mapID
                    local x, y
                    local p = info.position
                    if p and p.GetXY then
                        x, y = p:GetXY()
                    elseif p then
                        x, y = p.x, p.y
                    end
                    if (not link or ns.IsSecret(link) or link == mapID)
                        and type(x) == "number" and type(y) == "number"
                        and not ns.IsSecret(x) then
                        data.pois[#data.pois + 1] = {
                            x = x,
                            y = y,
                            name = info.name or "Point of interest",
                            atlas = info.atlasName or info.atlas,
                            textureIndex = info.textureIndex,
                            loc = true,
                        }
                    end
                end
            end
        end
    end
    data.taxis = {}
    -- Forever's GetTaxiNodesForMap answers the whole continent's flight
    -- map (36 nodes for Tirisfal) in flight-map coordinates, not this
    -- zone's — drawing them litters the map with wrong-zone pins. Only
    -- nodes learned via TAXIMAP_OPENED (CollectLearned, real player-side
    -- positions) are drawn. The API call is still probed for diag.
    if C_TaxiMap and C_TaxiMap.GetTaxiNodesForMap then
        local ok, nodes = pcall(C_TaxiMap.GetTaxiNodesForMap, mapID)
        local n = ok and type(nodes) == "table" and nodes[1]
        if not ns.mapDiagTaxiKeys and type(n) == "table" then
            local ks = {}
            for k in pairs(n) do ks[#ks + 1] = tostring(k) end
            table.sort(ks)
            ns.mapDiagTaxiKeys = table.concat(ks, ",")
        end
    end
end

-- POIs learned by Nocturne_Compass: engine-drawn townsfolk (innkeepers,
-- vendors, trainers...) have no Lua API, so Compass records where the
-- player stood when each service opened into NocturneCompassDB.pois,
-- keyed per map; taxi nodes get a real position via TAXIMAP_OPENED.
-- Record schema: { x, y, n = npc name, t = interaction type,
-- v = vendor-subtype tracking bit, c = classFile + s = subtitle for
-- class trainers }.

local KIND = {}
do
    local IT = Enum.PlayerInteractionType or {}
    local F = Enum.MinimapTrackingFilter or {}
    local function K(itype, label, ...)
        if itype then KIND[itype] = { label = label, bit = (...) } end
    end
    local function V(itype)
        K(itype, "Vendor", F.VenderFood or F.VendorReagent
            or F.VendorPoison or F.Repair)
    end
    V(IT.Merchant)
    V(IT.Vendor)
    V(IT.PetitionVendor)
    V(IT.GuildTabardVendor)
    V(IT.PerksProgramVendor)
    V(IT.PersonalTabardVendor)
    K(IT.Trainer, "Trainer", F.TrainerProfession)
    K(IT.Professions, "Trainer", F.TrainerProfession)
    K(IT.ProfessionRespec, "Trainer", F.TrainerProfession)
    K(IT.TalentMaster, "Trainer", F.TrainerProfession)
    K(IT.Banker, "Banker", F.Banker)
    K(IT.GuildBanker, "Guild Banker", F.Banker)
    K(IT.VoidStorageBanker, "Void Storage", F.Banker)
    K(IT.CharacterBanker, "Banker", F.Banker)
    K(IT.AccountBanker, "Account Bank", F.AccountBanker)
    K(IT.MailInfo, "Mailbox", F.Mailbox)
    K(IT.Binder, "Innkeeper", F.Innkeeper)
    K(IT.Auctioneer, "Auction House", F.Auctioneer)
    K(IT.BlackMarketAuctioneer, "Black Market", F.Auctioneer)
    K(IT.StableMaster, "Stable Master", F.Stablemaster)
    K(IT.BattleMaster, "Battlemaster", F.Battlemaster)
    K(IT.Transmogrifier, "Transmogrifier", F.Transmogrifier)
    K(IT.ItemUpgrade, "Item Upgrade", F.ItemUpgrade)
    K(IT.ForgeMaster, "Item Upgrade", F.ItemUpgrade)
    K(IT.BarbersChoice, "Barber", F.Barber)
end

-- Tracking filter bit -> { name, texture }: the minimap tracking menu's
-- own name/icon per service, reused as POI label and pin icon.
local trackBits
local function FilterByBit(bit)
    if bit == nil then return nil end
    if not trackBits then
        trackBits = {}
        if C_Minimap and C_Minimap.GetNumTrackingTypes
            and C_Minimap.GetTrackingFilter
            and C_Minimap.GetTrackingInfo then
            for i = 1, C_Minimap.GetNumTrackingTypes() or 0 do
                local f = C_Minimap.GetTrackingFilter(i)
                local info = C_Minimap.GetTrackingInfo(i)
                if type(info) == "table" and f
                    and f.filterID and f.filterID ~= 0 then
                    trackBits[f.filterID] = info
                end
            end
        end
    end
    return trackBits[bit]
end

local function CollectLearned(mapID, data)
    local db = _G.NocturneCompassDB
    if type(db) ~= "table" then return end
    local myClass = select(2, UnitClass("player"))
    data.learned = 0
    for _, poi in pairs(db.pois and db.pois[mapID] or {}) do
        if type(poi) == "table"
            and type(poi.x) == "number" and type(poi.y) == "number"
            and not ns.IsSecret(poi.x)
            -- class trainers of other classes aren't shown
            and (not poi.c or poi.c == myClass) then
            local kind = KIND[poi.t]
            local label, icon, atlas
            if poi.c then
                label = poi.s or "Class Trainer"
                local lower = poi.c:lower()
                if C_Texture and C_Texture.GetAtlasInfo then
                    for _, cand in ipairs({
                        "classicon-" .. lower,
                        "groupfinder-icon-class-" .. lower,
                    }) do
                        if C_Texture.GetAtlasInfo(cand) then
                            atlas = cand
                            break
                        end
                    end
                end
            elseif poi.v then
                local info = FilterByBit(poi.v)
                label = (info and info.name)
                    or (kind and kind.label) or "Vendor"
                icon = info and info.texture
            else
                label = kind and kind.label or "Point of interest"
                local info = kind and FilterByBit(kind.bit)
                icon = info and info.texture
            end
            data.pois[#data.pois + 1] = {
                x = poi.x,
                y = poi.y,
                name = poi.n and not ns.IsSecret(poi.n)
                    and (poi.n .. " — " .. label) or label,
                icon = icon,
                atlas = atlas,
                round = poi.c and true or nil,
                group = label,
            }
            data.learned = data.learned + 1
        end
    end
    -- Recorded flight-master spots override the API node (map icons sit
    -- tens of yards off) or extend the list when the API has no nodes.
    for nodeID, rec in pairs(db.taxi or {}) do
        if rec.m == mapID and type(rec.x) == "number"
            and type(rec.y) == "number" then
            local found
            for _, t in ipairs(data.taxis) do
                if t.id == nodeID then
                    found = t
                    break
                end
            end
            if found then
                found.x, found.y = rec.x, rec.y
                if rec.n and not ns.IsSecret(rec.n) then
                    found.name = rec.n
                end
            else
                data.taxis[#data.taxis + 1] = {
                    x = rec.x,
                    y = rec.y,
                    name = rec.n and not ns.IsSecret(rec.n)
                        and rec.n or "Flight path",
                }
                data.learned = data.learned + 1
            end
        end
    end
end

local function CollectMap(mapID)
    local data = { mapID = mapID }
    local info = MapInfo(mapID)
    if info then
        data.name = info.name
        data.parent = info.parentMapID
        data.mapType = info.mapType
    end
    CollectArt(mapID, data)
    CollectExplored(mapID, data)
    CollectQuests(mapID, data)
    CollectPOIs(mapID, data)
    CollectLearned(mapID, data)
    return data
end

-- host-px per texture-file-px at zoom 1 (aspect-preserved fit).
local function FitScale(ui)
    local d = ui.data
    local w, h = ui.host:GetSize()
    if not (d and d.texW and w and w > 0 and h and h > 0) then
        return ui.fit or 1
    end
    -- cover, not contain: the art fills the whole host (no letterbox
    -- bands); the axis that overflows pans, the other stays centered.
    return math.max(w / d.texW, h / d.texH)
end

local function MapToScreen(ui, x, y)
    local d, v = ui.data, ui.view
    local w, h = ui.host:GetSize()
    local s = ui.fit * v.zoom
    return (x - v.cx) * d.texW * s + w / 2,
        (y - v.cy) * d.texH * s + h / 2
end

local function ClampView(ui)
    local v, d = ui.view, ui.data
    if v.zoom < ZOOM_MIN then
        v.zoom = ZOOM_MIN
    elseif v.zoom > ZOOM_MAX then
        v.zoom = ZOOM_MAX
    end
    -- Pan only when part of the map is off-screen: per axis, the viewport
    -- half-extent in map units either pins the center at 0.5 (whole map
    -- visible — nothing to pan) or keeps it inside the bounds.
    local w, h = ui.host:GetSize()
    local s = ui.fit * v.zoom
    local vw = w > 0 and w / (2 * d.texW * s) or 0.5
    local vh = h > 0 and h / (2 * d.texH * s) or 0.5
    if vw >= 0.5 then
        v.cx = 0.5
    elseif v.cx < vw then
        v.cx = vw
    elseif v.cx > 1 - vw then
        v.cx = 1 - vw
    end
    if vh >= 0.5 then
        v.cy = 0.5
    elseif v.cy < vh then
        v.cy = vh
    elseif v.cy > 1 - vh then
        v.cy = 1 - vh
    end
end

local function ApplyView(ui)
    local d = ui.data
    if not (d and d.texW) then return end
    ClampView(ui)
    ui.fit = FitScale(ui)
    local w, h = ui.host:GetSize()
    local s = ui.fit * ui.view.zoom
    -- world is laid out once in fit-space; pan/zoom only moves and scales
    -- its origin — no per-tile relayout. SetPoint offsets are multiplied
    -- by the frame's OWN scale (AGENTS.md), so divide by zoom.
    local z = ui.view.zoom
    ui.world:SetScale(z)
    ui.world:ClearAllPoints()
    ui.world:SetPoint("TOPLEFT", ui.host, "TOPLEFT",
        (w / 2 - ui.view.cx * d.texW * s) / z,
        -(h / 2 - ui.view.cy * d.texH * s) / z)
    for _, pin in ipairs(ui.pins) do
        local x, y = MapToScreen(ui, pin.x, pin.y)
        pin:ClearAllPoints()
        pin:SetPoint("CENTER", ui.host, "TOPLEFT", x, -y)
    end
    if ui.px then
        local x, y = MapToScreen(ui, ui.px, ui.py)
        ui.player:ClearAllPoints()
        ui.player:SetPoint("CENTER", ui.host, "TOPLEFT", x, -y)
    end
    local zoomPct = math.floor(ui.view.zoom * 100 + 0.5)
    local coords = ui.px and ("  %.1f, %.1f"):format(
        ui.px * 100, ui.py * 100) or ""
    ui.coords:SetText(("%d%%%s"):format(zoomPct, coords))
end

local function LayoutTiles(ui)
    local d = ui.data
    for _, tex in ipairs(ui.tiles) do tex:Hide() end
    for _, tex in ipairs(ui.exp) do tex:Hide() end
    if not (d and d.texIDs and ui.fit) then return end
    -- Tiles step by their file-pixel size (256), not by texW/cols — the
    -- grid can be larger than the layerWidth×layerHeight coordinate rect.
    local tw = (d.tileW or 256) * ui.fit
    local th = (d.tileH or 256) * ui.fit
    ui.world:SetSize(d.cols * tw, d.rows * th)
    for r = 1, d.rows do
        for c = 1, d.cols do
            local i = (r - 1) * d.cols + c
            local id = d.texIDs[i]
            local tex = ui.tiles[i]
            if not tex then
                tex = ui.world:CreateTexture(nil, "BACKGROUND")
                ui.tiles[i] = tex
            end
            if id then
                tex:ClearAllPoints()
                tex:SetPoint("TOPLEFT", (c - 1) * tw, -(r - 1) * th)
                tex:SetSize(tw, th)
                tex:SetTexture(id)
                tex:Show()
            else
                tex:Hide()
            end
        end
    end
    -- Explored-area detail overlays sit above the base tiles.
    local n = 0
    for _, a in ipairs(d.explored or EMPTY) do
        for _, id in ipairs(a.ids) do
            n = n + 1
            local tex = ui.exp[n]
            if not tex then
                tex = ui.world:CreateTexture(nil, "BORDER")
                ui.exp[n] = tex
            end
            tex:ClearAllPoints()
            tex:SetPoint("TOPLEFT", a.x * ui.fit, -a.y * ui.fit)
            tex:SetSize(a.w * ui.fit, a.h * ui.fit)
            tex:SetTexture(id)
            tex:Show()
        end
    end
end

-- The list holds exactly: the zone's POIs (learned + API + taxi), the
-- zone's untracked quest pins from the API, the player's tracked quests,
-- and the super-tracked target — plus its transit waypoint when the
-- route leaves this map. Tracked quests off-map get a row but no pin.
local function EntriesFor(data)
    local quests, byId = {}, {}
    local superID = SuperID()
    local function Title(qid)
        local t = C_QuestLog.GetTitleForQuestID
            and C_QuestLog.GetTitleForQuestID(qid)
        return (t and not ns.IsSecret(t) and t ~= "" and t)
            or ("Quest " .. tostring(qid))
    end
    local function AddQ(qid, x, y, q)
        if not qid then return end
        local e = byId[qid]
        if not e then
            e = { kind = "quest", qid = qid, label = Title(qid) }
            byId[qid] = e
            quests[#quests + 1] = e
        end
        if x then e.x, e.y = x, y end
        if q then e.q = q end
    end
    for _, q in ipairs(data.quests or EMPTY) do
        AddQ(q.questID, q.x, q.y, q)
    end
    local watched = {}
    if C_QuestLog.GetNumQuestWatches
        and C_QuestLog.GetQuestIDForQuestWatchIndex then
        for i = 1, C_QuestLog.GetNumQuestWatches() or 0 do
            local qid = C_QuestLog.GetQuestIDForQuestWatchIndex(i)
            if qid then
                watched[qid] = true; AddQ(qid)
            end
        end
    end
    if C_QuestLog.GetNumWorldQuestWatches
        and C_QuestLog.GetQuestIDForWorldQuestWatchIndex then
        for i = 1, C_QuestLog.GetNumWorldQuestWatches() or 0 do
            local qid = C_QuestLog.GetQuestIDForWorldQuestWatchIndex(i)
            if qid then
                watched[qid] = true; AddQ(qid)
            end
        end
    end
    for _, e in ipairs(quests) do
        e.super = e.qid == superID or nil
        e.tracked = watched[e.qid] or nil
    end
    -- super-tracked first, then tracked, then the zone's other pins.
    table.sort(quests, function(a, b)
        local ra = (a.super and 0) or (a.tracked and 1) or 2
        local rb = (b.super and 0) or (b.tracked and 1) or 2
        if ra ~= rb then return ra < rb end
        return a.label < b.label
    end)

    -- Grouped sections with a non-selectable header row each: quests
    -- (with the transit hand-off), flight paths, NPCs, then the zone's
    -- static locations (towns etc.) last.
    local out = {}
    local function Header(label)
        out[#out + 1] = { kind = "header", label = label }
    end
    if quests[1] then Header("Quests") end
    for _, e in ipairs(quests) do out[#out + 1] = e end

    if superID and C_SuperTrack and C_SuperTrack.GetNextWaypointForMap then
        local ok, tx, ty = pcall(C_SuperTrack.GetNextWaypointForMap,
            data.mapID)
        if ok and tx and ty
            and not ns.IsSecret(tx) and not ns.IsSecret(ty) then
            out[#out + 1] = {
                kind = "transit",
                x = tx,
                y = ty,
                label = "Transit",
                atlas = Nocturne.FirstAtlas(
                    "Navigation-Tracked-Arrow", "MinimapArrow"),
            }
        end
    end

    if #(data.taxis or EMPTY) > 0 then Header("Flight paths") end
    for _, t in ipairs(data.taxis or EMPTY) do
        out[#out + 1] = {
            kind = "taxi",
            x = t.x,
            y = t.y,
            label = t.name
        }
    end
    local function PoiEntry(p)
        out[#out + 1] = {
            kind = "poi",
            x = p.x,
            y = p.y,
            label = p.name,
            atlas = p.atlas,
            icon = p.icon,
            textureIndex = p.textureIndex,
            round = p.round,
        }
    end
    local npcs, locs = 0, 0
    for _, p in ipairs(data.pois or EMPTY) do
        if p.loc then locs = locs + 1 else npcs = npcs + 1 end
    end
    -- NPCs grouped by the minimap tracking category (its own name:
    -- Innkeeper, Banker, Vendor...), one header per category.
    if npcs > 0 then
        local groups, names = {}, {}
        for _, p in ipairs(data.pois or EMPTY) do
            if not p.loc then
                local g = p.group or "Other"
                if not groups[g] then
                    groups[g] = {}
                    names[#names + 1] = g
                end
                groups[g][#groups[g] + 1] = p
            end
        end
        table.sort(names)
        for _, g in ipairs(names) do
            Header(g)
            for _, p in ipairs(groups[g]) do PoiEntry(p) end
        end
    end
    if locs > 0 then Header("Locations") end
    for _, p in ipairs(data.pois or EMPTY) do
        if p.loc then PoiEntry(p) end
    end
    return out
end

local GLOW_GOLD = { 1, 0.85, 0.3, 1 }

-- Round glow behind a pin, `scale` times the pin box: the atlas when the
-- client has it, else the classic round action-button border.
local function Glow(f, atlas, scale, color, blend)
    local t = f:CreateTexture(nil, "BACKGROUND", nil, -2)
    t:SetPoint("CENTER")
    t:SetSize(PIN_SIZE * scale, PIN_SIZE * scale)
    if C_Texture.GetAtlasInfo(atlas) then
        t:SetAtlas(atlas, false)
    else
        t:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
        t:SetTexCoord(0, 1, 0, 1)
        t:SetBlendMode("ADD")
    end
    t:SetBlendMode(blend)
    if color then t:SetVertexColor(color[1], color[2], color[3], color[4]) end
    return t
end

local function NewPin(ui, e)
    local f = CreateFrame("Frame", nil, ui.pinHost)
    f.x, f.y = e.x, e.y
    f.entry = e
    local tex = f:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    local size
    if e.kind == "quest" then
        local super = e.super or e.qid == SuperID()
        local done = ns.Flag(C_QuestLog.IsComplete(e.qid))
        local onQuest = ns.Flag(C_QuestLog.IsOnQuest
            and C_QuestLog.IsOnQuest(e.qid))
        -- Composed "coin" marker: gold disc + glyph, crisp at any scale
        -- (no texture asset needed). "!" = available offer,
        -- "..." = in progress, "?" = complete — the classic map look.
        size = super and PIN_SIZE_SUPER or PIN_SIZE
        -- Blizzard's own POIButton art (Blizzard_POIButton): the round
        -- QuestNumber disc as background plus a glyph atlas on top —
        -- "Quest-In-Progress-Icon-yellow" (three dots) in progress,
        -- "UI-QuestIcon-TurnIn-Normal" ("?") complete, QuestNormal ("!")
        -- for an available offer. Falls back to a plain gold disc.
        local FA = Nocturne.FirstAtlas
        local bg = FA("UI-QuestPoi-QuestNumber" .. (super and "-SuperTracked" or ""),
            "UI-QuestPoi-QuestNumber")
        local gl
        if done then
            gl = FA("UI-QuestIcon-TurnIn-Normal", "QuestTurnin")
        elseif onQuest then
            gl = FA(super and "Quest-In-Progress-Icon-Brown"
                or "Quest-In-Progress-Icon-yellow",
                "Quest-In-Progress-Icon-yellow")
        else
            gl = FA("QuestNormal", "UI-QuestIcon-Available-Normal")
        end
        -- The disc atlas carries transparent padding, so the art is drawn
        -- larger than the pin box (QUEST_OVERDRAW) to match the visible
        -- size of the full-bleed POI icons; the glyph keeps Blizzard's
        -- native glyph/disc proportion (read from the atlas sizes).
        local ratio
        if bg and (onQuest or done) then
            local bi = C_Texture.GetAtlasInfo(bg)
            local gi = gl and C_Texture.GetAtlasInfo(gl)
            if bi and bi.width and bi.width > 0 then
                ratio = size * QUEST_OVERDRAW / bi.width
            end
            ns.mapDiagAtlas = ("%s=%sx%s %s=%sx%s"):format(bg,
                tostring(bi and bi.width), tostring(bi and bi.height),
                tostring(gl), tostring(gi and gi.width),
                tostring(gi and gi.height))
        end
        if bg and not (not onQuest and not done) then
            tex:SetAtlas(bg, false)
            tex:ClearAllPoints()
            tex:SetPoint("CENTER")
            tex:SetSize(size * QUEST_OVERDRAW, size * QUEST_OVERDRAW)
        elseif not onQuest and not done then
            tex:SetColorTexture(0, 0, 0, 0)
        else
            local disc = done and PIN_DONE or PIN_GOLD
            tex:SetColorTexture(disc[1], disc[2], disc[3], 1)
            local mask = f:CreateMaskTexture()
            mask:SetAllPoints()
            mask:SetTexture(
                "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
            tex:AddMaskTexture(mask)
        end
        if gl then
            local g = f:CreateTexture(nil, "OVERLAY")
            g:SetAtlas(gl, false)
            if bg and (onQuest or done) then
                local gi = C_Texture.GetAtlasInfo(gl)
                g:SetPoint("CENTER")
                if ratio and gi and gi.width then
                    g:SetSize(gi.width * ratio, gi.height * ratio)
                else
                    g:SetSize(size * 0.8, size * 0.8)
                end
            else
                g:SetAllPoints()
            end
        else
            local glyph = T.CreateFontString(f, size - 12,
                { 0.16, 0.10, 0.02, 1 }, "OVERLAY", "OUTLINE")
            glyph:SetPoint("CENTER", 0, 0)
            glyph:SetText(done and "?" or onQuest and "..." or "!")
        end
        local icn = ns.mapDiagIcons
        if icn then
            local ic = (done and "done" or onQuest and "prog" or "offer")
                .. (bg and "+bg" or "") .. (gl and "+gl" or "")
            icn[ic] = (icn[ic] or 0) + 1
        end
        -- Super-tracked: Blizzard's round outer glow behind the disc.
        if super then
            f.ring = Glow(f, "UI-QuestPoi-OuterGlow", 2.2, nil, "ADD")
        end
    else
        -- POIs/taxis/transit use their own atlas when the client provides
        -- one, else a tracking-filter icon, the legacy POIIcons cell
        -- (area POIs with only a textureIndex, e.g. cities on the
        -- continent map), the taxi icon, or a theme-colored diamond.
        local ok, how = false, "diamond"
        if e.atlas then
            ok = C_Texture and C_Texture.GetAtlasInfo
                and C_Texture.GetAtlasInfo(e.atlas) ~= nil
            if ok then
                tex:SetAtlas(e.atlas, false)
                how = "atlas"
            end
        end
        if not ok and e.icon then
            tex:SetTexture(e.icon)
            ok = tex:GetTextureFileID() ~= nil
            if ok then how = "icon" end
        end
        if not ok and e.textureIndex and GetPOITextureCoords then
            tex:SetTexture(POI_TEXTURE)
            tex:SetTexCoord(GetPOITextureCoords(e.textureIndex))
            ok, how = true, "texIdx"
        end
        if not ok and e.kind == "taxi" then
            tex:SetTexture("Interface\\TaxiFrame\\UI-Taxi-Icon-Green")
            ok = tex:GetTextureFileID() ~= nil
            if ok then how = "taxi" end
        end
        local icn = ns.mapDiagIcons
        if icn then
            local ic = e.kind .. ":" .. how
            icn[ic] = (icn[ic] or 0) + 1
        end
        if not ok then
            tex:SetTexture(nil)
            local c = e.kind == "taxi"
                and { 0.35, 0.65, 0.95, 1 } or T.colors.accent
            tex:SetColorTexture(c[1], c[2], c[3], c[4])
            tex:SetRotation(math.pi / 4)
        end
        -- Class trainers draw round (circular mask over whatever art won).
        if e.round and tex:GetTexture() then
            local mask = f:CreateMaskTexture()
            mask:SetAllPoints()
            mask:SetTexture(
                "Interface\\CharacterFrame\\TempPortraitAlphaMask")
            tex:AddMaskTexture(mask)
        end
    end
    size = size or PIN_SIZE
    f:SetSize(size, size)
    -- list-cursor highlight: a golden glow around the marker
    f.sel = Glow(f, "UI-QuestPoi-OuterGlow", 2.6, GLOW_GOLD, "ADD")
    f.sel:Hide()
    ui.pins[#ui.pins + 1] = f
    return f
end

local function RebuildPins(ui)
    for _, p in ipairs(ui.pins) do p:Hide() end
    wipe(ui.pins)
    ns.mapDiagIcons = wipe(ns.mapDiagIcons or {})
    for _, e in ipairs(ui.entries or EMPTY) do
        -- Entries without a position (tracked quests on another map)
        -- are list-only.
        e.pin = e.x and NewPin(ui, e) or nil
    end
end

local function UpdatePlayer(ui)
    local d = ui.data
    ui.px, ui.py = nil, nil
    ui.player:Hide()
    if not d then return end
    local x, y = PlayerPos(d.mapID)
    if not x then return end
    ui.px, ui.py = x, y
    local facing = GetPlayerFacing and GetPlayerFacing()
    if type(facing) == "number" and not ns.IsSecret(facing) then
        -- facing is radians CCW from north; SetRotation CCW matches the
        -- on-screen arrow convention directly.
        ui.player.tex:SetRotation(facing)
    end
    ui.player:Show()
end

local function SetMap(ui, mapID, recenter)
    ui.data = CollectMap(mapID)
    UpdatePlayer(ui)
    if recenter or not ui.view then
        ui.view = {
            cx = ui.px or 0.5,
            cy = ui.py or 0.5,
            zoom = 1,
        }
    end
    local info = MapInfo(mapID)
    ui.zone:SetText(ui.data.name
        or (info and info.name) or "Unknown map")
    ui.noArt:SetShown(not ui.data.texIDs)
    ui.entries = EntriesFor(ui.data)
    ui.sel = nil
    for i, e in ipairs(ui.entries) do
        if e.kind ~= "header" then
            ui.sel = i
            break
        end
    end
    ui.fit = FitScale(ui)
    LayoutTiles(ui)
    RebuildPins(ui)
    local e = ui.sel and ui.entries[ui.sel]
    if e then
        for _, p in ipairs(ui.pins) do
            if p.sel then p.sel:SetShown(p.entry == e) end
        end
    end
    local ics = {}
    for k, v in pairs(ns.mapDiagIcons or EMPTY) do
        ics[#ics + 1] = k .. "=" .. v
    end
    table.sort(ics)
    ns.mapDiag = ("map=%s id=%s type=%s tiles=%dx%d/%d exp=%d pins=%d pois=%d taxis=%d learned=%d onQ=%s ic=[%s] art=[%s]")
        :format(tostring(ui.data.name), tostring(mapID),
            tostring(ui.data.mapType),
            ui.data.cols or 0, ui.data.rows or 0,
            ui.data.texIDs and #ui.data.texIDs or 0,
            #(ui.data.explored or EMPTY),
            #ui.data.quests,
            #(ui.data.pois or EMPTY),
            #(ui.data.taxis or EMPTY),
            ui.data.learned or 0,
            type(C_QuestLog.IsOnQuest),
            table.concat(ics, ","),
            (ns.mapDiagArtKeys or "-") .. " idx="
            .. tostring(ns.mapDiagArtIdx) .. " expKeys=["
            .. tostring(ns.mapDiagExpKeys) .. "] poiKeys=["
            .. tostring(ns.mapDiagPoiKeys) .. "] taxiKeys=["
            .. tostring(ns.mapDiagTaxiKeys) .. "] atlas=["
            .. tostring(ns.mapDiagAtlas) .. "]")
    if ui.PaintList then ui.PaintList() end
    ApplyView(ui)
    if ui.UpdateLegend then ui.UpdateLegend() end
end

local function Refresh(ui)
    if ui.data then
        CollectQuests(ui.data.mapID, ui.data)
        CollectPOIs(ui.data.mapID, ui.data)
        CollectLearned(ui.data.mapID, ui.data)
        ui.entries = EntriesFor(ui.data)
        RebuildPins(ui)
        if ui.PaintList then ui.PaintList() end
    end
    UpdatePlayer(ui)
    ApplyView(ui)
end

-- D-pad list cursor: moves between entries, centers the view on the
-- selected pin (the clamp keeps it a no-op while the map is fully
-- visible) and marks the pin's ring.
local function SelectEntry(ui, i, dir)
    local n = #(ui.entries or EMPTY)
    if n == 0 then return end
    dir = dir or 1
    local e
    -- header rows are skipped by the cursor, with wrap-around
    for _ = 1, n do
        if i < 1 then
            i = n
        elseif i > n then
            i = 1
        end
        e = ui.entries[i]
        if e and e.kind ~= "header" then break end
        i = i + dir
    end
    if not e or e.kind == "header" then return end
    ui.sel = i
    if ui.view and e.x then
        ui.view.cx, ui.view.cy = e.x, e.y
    end
    for _, p in ipairs(ui.pins) do
        if p.sel then p.sel:SetShown(p.entry == e) end
    end
    if ui.PaintList then ui.PaintList() end
    if ui.view then ApplyView(ui) end
    if ui.UpdateLegend then ui.UpdateLegend() end
end

ns.RegisterPage(1, {
    key = "map",
    title = "Map",
    Build = function(f)
        local ui = {}
        ns.mapUI = ui
        ui.pins = {}
        ui.tiles = {}
        ui.exp = {}
        ui.fit = 1

        -- host clips every child frame (world tiles + pins) to the page.
        -- The right strip is the points-of-interest list panel.
        ui.host = CreateFrame("Frame", nil, f)
        -- Map spans from the left edge to just before the list; the
        -- button legend sits in the strip below it.
        ui.host:SetPoint("TOPLEFT", 0, 0)
        ui.host:SetPoint("BOTTOMRIGHT", -(MARGIN + LIST_W + GAP), 0)
        ui.host:SetClipsChildren(true)
        ui.hostBg = ui.host:CreateTexture(nil, "BACKGROUND")
        ui.hostBg:SetAllPoints()
        local c = T.colors.backdrop
        ui.hostBg:SetColorTexture(c[1], c[2], c[3], 1)

        ui.world = CreateFrame("Frame", nil, ui.host)
        ui.pinHost = CreateFrame("Frame", nil, ui.host)
        ui.pinHost:SetAllPoints()
        ui.pinHost:SetClipsChildren(true)
        ui.pinHost:SetFrameLevel(ui.world:GetFrameLevel() + 2)

        ui.player = CreateFrame("Frame", nil, ui.host)
        ui.player:SetSize(55, 55)
        ui.player:SetFrameLevel(ui.pinHost:GetFrameLevel() + 2)
        ui.player.tex = ui.player:CreateTexture(nil, "OVERLAY")
        ui.player.tex:SetAllPoints()
        ui.player.tex:SetTexture("Interface\\MINIMAP\\MinimapArrow")
        if not ui.player.tex:GetTextureFileID() then
            -- no arrow art: rotated accent diamond
            local a = T.colors.accent
            ui.player.tex:SetColorTexture(a[1], a[2], a[3], 1)
            ui.player.tex:SetRotation(math.pi / 4)
        else
            ui.player.tex:SetRotation(0)
        end

        -- Points-of-interest list on the right strip.
        ui.side = CreateFrame("Frame", nil, f)
        ui.side:SetPoint("TOPRIGHT", -MARGIN, 0)
        ui.side:SetPoint("BOTTOMRIGHT", -MARGIN, MARGIN + 26)
        ui.side:SetWidth(LIST_W)
        ui.rows = {}
        local function PaintList()
            local items = ui.entries or EMPTY
            local h = ui.side:GetHeight()
            local rowH = 30
            local maxRows = math.max(1,
                math.floor(h / rowH))
            -- keep the selected row inside the rendered window
            ui.listTop = ui.listTop or 1
            if ui.sel then
                if ui.sel < ui.listTop then
                    ui.listTop = ui.sel
                elseif ui.sel > ui.listTop + maxRows - 1 then
                    ui.listTop = ui.sel - maxRows + 1
                end
            end
            if ui.listTop > #items - maxRows + 1 then
                ui.listTop = math.max(1, #items - maxRows + 1)
            end
            for i = 1, maxRows do
                local e = items[ui.listTop + i - 1]
                local row = ui.rows[i]
                if e then
                    if not row then
                        row = T.CreateFontString(ui.side, 19,
                            T.colors.text)
                        row:SetHeight(rowH)
                        row:SetJustifyH("LEFT")
                        row:SetWordWrap(false)
                        row:SetPoint("TOPLEFT", 0,
                            -(i - 1) * rowH)
                        row:SetPoint("RIGHT", 0, 0)
                        ui.rows[i] = row
                    end
                    local label = e.label
                    if e.kind == "quest"
                        and (e.super or e.qid == SuperID()) then
                        label = label .. " *"
                    end
                    row:SetText(label)
                    local c
                    if e.kind == "header" then
                        c = T.colors.accent
                    elseif i + ui.listTop - 1 == ui.sel then
                        c = T.colors.accent
                    elseif e.kind == "quest" then
                        c = T.colors.text
                    else
                        c = T.colors.textDim
                    end
                    row:SetTextColor(c[1], c[2], c[3], c[4] or 1)
                    row:Show()
                elseif row then
                    row:Hide()
                end
            end
        end
        ui.PaintList = PaintList

        ui.overlay = CreateFrame("Frame", nil, ui.host)
        ui.overlay:SetAllPoints()
        ui.overlay:SetFrameLevel(ui.player:GetFrameLevel() + 2)
        -- zone name at the top edge of the map (outlined, no bar)
        ui.zone = T.CreateFontString(ui.overlay, 18, T.colors.text,
            "OVERLAY", "OUTLINE")
        ui.zone:SetPoint("TOPLEFT", 14, -8)
        ui.coords = T.CreateFontString(ui.overlay, 20, T.colors.text,
            "OVERLAY", "OUTLINE")
        ui.coords:SetPoint("BOTTOMLEFT", 14, 8)
        ui.coords:SetJustifyH("LEFT")
        ui.noArt = T.CreateFontString(ui.host, 15, T.colors.textDim)
        ui.noArt:SetPoint("CENTER")
        ui.noArt:SetText("No map artwork on this client")
        ui.noArt:Hide()

        local up = ns.PadGlyph("PADDUP")
        local down = ns.PadGlyph("PADDDOWN")
        local dpadUD = (up and up:find("|") and down
            and down:find("|")) and (up .. down) or "D-Pad"
        local left = ns.PadGlyph("PADDLEFT")
        local right = ns.PadGlyph("PADDRIGHT")
        local dpadLR = (left and left:find("|") and right
            and right:find("|")) and (left .. right) or "D-Pad"
        -- the legend lives on its own frame above the map and the list,
        -- anchored to the page's bottom-right corner
        ui.legendHost = CreateFrame("Frame", nil, f)
        ui.legendHost:SetAllPoints()
        ui.legendHost:SetFrameLevel(ui.overlay:GetFrameLevel() + 5)
        ui.legend = T.CreateFontString(ui.legendHost, 15, T.colors.text,
            "OVERLAY", "OUTLINE")
        ui.legend:SetPoint("BOTTOMRIGHT", -MARGIN, MARGIN)
        ui.legend:SetJustifyH("RIGHT")
        local function UpdateLegend()
            local t = dpadUD .. "  Select      "
                .. dpadLR .. "  Pan      "
                .. ns.PadGlyph("PADLTRIGGER", "LT") .. "/"
                .. ns.PadGlyph("PADRTRIGGER", "RT") .. "  Zoom      "
                .. ns.PadGlyph("PAD3", "X") .. "  Center"
            local e = ui.sel and ui.entries and ui.entries[ui.sel]
            if e and e.kind == "quest" then
                t = t .. "      " .. ns.PadGlyph("PAD1", "A")
                    .. "  Track"
            end
            if ui.data and ui.data.parent and ui.data.parent ~= 0 then
                t = t .. "      " .. ns.PadGlyph("PAD4", "Y")
                    .. "  Parent"
            end
            ui.legend:SetText(t)
        end
        ui.UpdateLegend = UpdateLegend

        -- player position/facing refresh; the D-pad hold owns f's OnUpdate,
        -- so this ticker hangs off the map host instead.
        ui.tickT = 0
        ui.host:SetScript("OnUpdate", function(_, dt)
            local v = ui.view
            local zt = v and v.zt
            if zt then
                local r = zt / v.zoom
                if math.abs(r - 1) < 0.002 then
                    v.zoom, v.zt = zt, nil
                else
                    v.zoom = v.zoom * r ^ (1 - math.exp(-ZOOM_RATE * dt))
                end
                ApplyView(ui)
            end
            ui.tickT = ui.tickT + dt
            if ui.tickT >= PLAYER_TICK then
                ui.tickT = 0
                local had = ui.px
                UpdatePlayer(ui)
                if had or ui.px then ApplyView(ui) end
            end
        end)

        local function DpadTick(btn)
            if btn == "PADDUP" or btn == "PADDDOWN" then
                local d = btn == "PADDUP" and -1 or 1
                SelectEntry(ui, (ui.sel or 0) + d, d)
                return
            end
            local d = DIR[btn]
            if not d or not ui.view then return end
            local z = ui.view.zoom
            ui.view.cx = ui.view.cx + d[1] * PAN_TICK / z
            ui.view.cy = ui.view.cy + d[2] * PAN_TICK / z
            ApplyView(ui)
        end
        ui.DpadTick = DpadTick
        ui.dpadHold = ns.DpadHoldFrame(f, DpadTick)

        f:SetScript("OnSizeChanged", function()
            if ui.data then
                ui.fit = FitScale(ui)
                LayoutTiles(ui)
                ApplyView(ui)
            end
        end)
        return ui
    end,
    OnShow = function(f)
        local ui = ns.mapUI
        local mapID = C_Map.GetBestMapForUnit
            and C_Map.GetBestMapForUnit("player")
        ui.stickX, ui.stickY = 0, 0
        if mapID then
            SetMap(ui, mapID, true)
        else
            ui.zone:SetText("No map")
            ns.mapDiag = "no mapID"
        end
        ui.UpdateLegend()
    end,
    OnStick = function(f, stick, x, y, dt)
        local ui = ns.mapUI
        if not (ui and ui.view) then return end
        dt = dt or 0.016
        local step = STICK_SPEED * dt / ui.view.zoom
        ui.view.cx = ui.view.cx + x * step
        ui.view.cy = ui.view.cy - y * step
        ApplyView(ui)
    end,
    OnTrigger = function(f, dir)
        local ui = ns.mapUI
        local v = ui.view
        if not v then return true end
        local z = (v.zt or v.zoom) * (dir > 0 and ZOOM_STEP or 1 / ZOOM_STEP)
        v.zt = math.min(ZOOM_MAX, math.max(ZOOM_MIN, z))
        return true
    end,
    OnPad = function(f, button)
        local ui = ns.mapUI
        if button == "PAD1" then
            -- super-track the selected quest pin
            local e = ui.sel and ui.entries and ui.entries[ui.sel]
            if e and e.kind == "quest" and e.qid
                and C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID
            then
                C_SuperTrack.SetSuperTrackedQuestID(e.qid)
            end
        elseif button == "PAD3" then
            if ui.px then
                ui.view.cx, ui.view.cy = ui.px, ui.py
            else
                ui.view.cx, ui.view.cy = 0.5, 0.5
            end
            ui.view.zt = 1
            ApplyView(ui)
        elseif button == "PAD4" then
            local p = ui.data and ui.data.parent
            if p and p ~= 0 then
                SetMap(ui, p, true)
            end
            ui.UpdateLegend()
        else
            -- D-pad: start the hold repeat and fire once immediately.
            local d = DIR[button]
            if not (d and ui.dpadHold) then return end
            ui.dpadHold[button] = { t = 0, acc = 0 }
            if ui.DpadTick then ui.DpadTick(button) end
        end
    end,
    OnPadUp = function(f, button)
        local ui = ns.mapUI
        if ui and ui.dpadHold then ui.dpadHold[button] = nil end
    end,
    OnHide = function()
        local ui = ns.mapUI
        if ui and ui.dpadHold then wipe(ui.dpadHold) end
    end,
})

_G.Nocturne.RegisterEvent("QUEST_LOG_UPDATE", function()
    local f = ns.pageFrames and ns.pageFrames[1]
    local ui = ns.mapUI
    if ui and f and f:IsShown() then Refresh(ui) end
end)
_G.Nocturne.RegisterEvent("QUEST_WATCH_LIST_CHANGED", function()
    local f = ns.pageFrames and ns.pageFrames[1]
    local ui = ns.mapUI
    if ui and f and f:IsShown() then Refresh(ui) end
end)
_G.Nocturne.RegisterEvent("SUPER_TRACKING_CHANGED", function()
    local f = ns.pageFrames and ns.pageFrames[1]
    local ui = ns.mapUI
    if ui and f and f:IsShown() then Refresh(ui) end
end)
