local _, ns = ...

-- The player's own map selection: the user waypoint (pin placed on the world
-- map) and a super-tracked map POI (area POI, flight master, vignette,
-- tracked content), each drawn with its own map icon. Unlike quests (zone
-- only), these are shown anywhere on the player's continent. Tracked points
-- of interest (C_ContentTracking) follow the quest rule instead: only the
-- ones in the player's zone are drawn; the selected one gets the
-- continent-wide Locate and the transit arrow like every other pin.

local GetPOITextureCoords = (C_Minimap and C_Minimap.GetPOITextureCoords) or _G.GetPOITextureCoords
local MapPinType = Enum.SuperTrackingMapPinType or {}

local provider = { name = "mapPins" }
ns.providers[#ns.providers + 1] = provider

provider.results = {}

local ARRIVE_YARDS = 10
local PIN_TITLE = "Map Pin"
local PIN_TRACKED = "Waypoint-MapPin-Tracked"
local PIN_UNTRACKED = "Waypoint-MapPin-Untracked"

local function FindAreaPOI(mapID, poiID)
    local info = C_AreaPoiInfo.GetAreaPOIInfo(mapID, poiID)
    if info and info.position then
        return { pos = info.position, name = info.name, atlas = info.atlasName, textureIndex = info.textureIndex }
    end
end

-- LearnedPOIs records the real spot when the player opens a flight map;
-- it wins over the icon position, which can sit tens of yards off.
local function FindTaxiNode(mapID, nodeID)
    local learned = ns.db and ns.db.taxi and ns.db.taxi[nodeID]
    for _, node in ipairs(C_TaxiMap.GetTaxiNodesForMap(mapID) or {}) do
        if node.nodeID == nodeID then
            if learned then
                return {
                    pos = { x = learned.x, y = learned.y },
                    mapOverride = learned.m,
                    name = node.name or learned.n,
                    atlas = node.atlasName
                }
            end
            if node.position then
                return { pos = node.position, name = node.name, atlas = node.atlasName }
            end
        end
    end
    if learned then
        return { pos = { x = learned.x, y = learned.y }, mapOverride = learned.m, name = learned.n }
    end
end

local RESULT_SUCCESS = Enum.ContentTrackingResult and Enum.ContentTrackingResult.Success or 0

-- A trackable's label: its title, else the waypoint text on the map pin.
local function TrackableTitle(trackableType, trackableID, info)
    local t = C_ContentTracking.GetTitle and C_ContentTracking.GetTitle(trackableType, trackableID)
    if ns.IsSecret(t) or t == "" then t = nil end
    local w = info and info.waypointText
    if ns.IsSecret(w) or w == "" then w = nil end
    return t or w
end

-- A tracked-content pin on `mapID` (ContentTrackingMapInfo carries x/y
-- directly, so it doubles as `pos`).
local function FindTrackable(mapID, trackableType, trackableID)
    local res, infos = C_ContentTracking.GetTrackablesOnMap(trackableType, mapID)
    if res ~= RESULT_SUCCESS then return end
    for _, info in ipairs(infos or {}) do
        if info.trackableID == trackableID then
            return { pos = info, name = TrackableTitle(trackableType, trackableID, info) }
        end
    end
end

local function FindDigSite(mapID, siteID)
    for _, site in ipairs(C_ResearchInfo.GetDigSitesForMap(mapID) or {}) do
        if site.researchSiteID == siteID and site.position then
            return { pos = site.position, name = site.name, textureIndex = site.textureIndex }
        end
    end
end

-- Plot data only exists while the player stands in the neighborhood, and
-- only for the player's own map (same gate as Blizzard's
-- NeighborhoodMapDataProvider).
local function FindHousingPlot(mapID, plotDataID)
    if not (C_Housing and C_Housing.IsOnNeighborhoodMap and C_Housing.IsOnNeighborhoodMap()) then return end
    if mapID ~= C_Map.GetBestMapForUnit("player") then return end
    for _, plot in ipairs(C_HousingNeighborhood.GetNeighborhoodMapData() or {}) do
        if plot.plotDataID == plotDataID and plot.mapPosition then
            local owner = plot.ownerName
            if ns.IsSecret(owner) or owner == "" then owner = nil end
            return { pos = plot.mapPosition, name = owner or ("Plot " .. tostring(plot.plotID)) }
        end
    end
end

-- Same faction rule as Blizzard's FlightPointDataProvider.
local FlightFaction = Enum.FlightPathFaction or {}
local function TaxiForPlayer(node)
    local faction = UnitFactionGroup("player")
    if node.faction == FlightFaction.Horde then return faction == "Horde" end
    if node.faction == FlightFaction.Alliance then return faction == "Alliance" end
    return true
end

local function FindVignette(mapID, guid)
    local pos = C_VignetteInfo.GetVignettePosition(guid, mapID)
    if pos then
        local info = C_VignetteInfo.GetVignetteInfo(guid)
        return { pos = pos, name = info and info.name, atlas = info and info.atlasName }
    end
end

-- Map each pin was last found on, so rescans skip the continent search;
-- and the search epoch in which a continent-wide search last missed.
local foundOn = {}
local missedAt = {}

local function Try(find, id, key, mapID)
    local hit = mapID and find(mapID, id)
    if hit then
        hit.mapID = hit.mapOverride or mapID
        foundOn[key] = hit.mapID
        return hit
    end
end

-- Continent-wide: the pin may sit in any zone of the player's continent and
-- have been picked at any zoom level of the world map. Try the map it was
-- last found on, the player's map chain up to the continent, then every
-- zone of that continent (the latter at most once per search epoch).
local function Locate(find, id, key, playerMapID)
    local hit = Try(find, id, key, foundOn[key])
    if hit then return hit end
    for _, mapID in ipairs(ns.MapChain(playerMapID)) do
        hit = Try(find, id, key, mapID)
        if hit then return hit end
    end
    if missedAt[key] == ns.searchEpoch then return end
    for _, child in ipairs(ns.ContinentZones(playerMapID)) do
        hit = Try(find, id, key, child.mapID)
        if hit then
            missedAt[key] = nil
            return hit
        end
    end
    missedAt[key] = ns.searchEpoch
end

function provider:Add(results, instance, mapID, pos, entry)
    local x, y = ns.MapToWorld(mapID, pos.x, pos.y, instance)
    if not x then return end
    entry.atlas = ns.FirstAtlas(entry.atlas)
    if entry.atlas or not GetPOITextureCoords then entry.textureIndex = nil end
    if not entry.atlas and not entry.textureIndex then entry.atlas = ns.FirstAtlas(PIN_TRACKED) end
    entry.provider, entry.x, entry.y = self, x, y
    entry.title = entry.title or PIN_TITLE
    results[#results + 1] = entry
end

function provider:Scan(playerMapID, playerInstance)
    local results = wipe(self.results)

    -- Anything but a quest selected (quests handle their own) whose route
    -- leaves the map — portal, boat, another continent: a single transit
    -- arrow replaces the selected pin, which may not even be on this
    -- continent.
    local transitX, transitY
    if not ns.GetSelectedQuestID() then
        transitX, transitY = ns.TransitWaypoint(playerMapID, playerInstance)
    end
    if transitX then
        results[#results + 1] = {
            key = "pin:transit",
            provider = self,
            title = "Transit",
            x = transitX,
            y = transitY,
            atlas = ns.TransitAtlas(),
            isTransit = true,
            isSuperTracked = true,
        }
    end

    local wp = C_Map.GetUserWaypoint()
    local tracked = wp and C_SuperTrack.IsSuperTrackingUserWaypoint() or false
    -- A waypoint placed on a learned POI (LearnedPOIs) stands in for the
    -- POI's own marker only while super-tracked; untracked, the POI's
    -- marker is the one drawn.
    local learnedTitle = ns.LearnedWaypointTitle and ns.LearnedWaypointTitle(wp)
    if wp and wp.position and not (tracked and transitX) and (tracked or not learnedTitle) then
        self:Add(results, playerInstance, wp.uiMapID, wp.position, {
            key = "pin:user",
            title = learnedTitle,
            atlas = tracked and PIN_TRACKED or PIN_UNTRACKED,
            isSuperTracked = tracked,
        })
    end

    local find, id, kind
    local pinType, pinID
    local selType, selID
    if C_SuperTrack.GetSuperTrackedMapPin then
        pinType, pinID = C_SuperTrack.GetSuperTrackedMapPin()
    end
    if C_SuperTrack.GetSuperTrackedContent then
        selType, selID = C_SuperTrack.GetSuperTrackedContent()
        if ns.IsSecret(selID) then selType, selID = nil, nil end
    end
    if pinID and pinType == MapPinType.AreaPOI and C_AreaPoiInfo then
        find, id, kind = FindAreaPOI, pinID, "poi"
    elseif pinID and pinType == MapPinType.TaxiNode and C_TaxiMap then
        find, id, kind = FindTaxiNode, pinID, "taxi"
    elseif pinID and pinType == MapPinType.DigSite and C_ResearchInfo and C_ResearchInfo.GetDigSitesForMap then
        find, id, kind = FindDigSite, pinID, "dig"
    elseif pinID and pinType == MapPinType.HousingPlot and C_HousingNeighborhood
        and C_HousingNeighborhood.GetNeighborhoodMapData then
        find, id, kind = FindHousingPlot, pinID, "plot"
    elseif C_SuperTrack.GetSuperTrackedVignette and C_VignetteInfo and C_SuperTrack.GetSuperTrackedVignette() then
        find, id, kind = FindVignette, C_SuperTrack.GetSuperTrackedVignette(), "vignette"
    elseif selID and selID ~= 0 and C_ContentTracking then
        find = function(mapID, tid) return FindTrackable(mapID, selType, tid) end
        id, kind = selID, "ct" .. tostring(selType)
    end
    self.sel = find and { find = find, id = id, kind = kind, key = "pin:" .. kind .. ":" .. tostring(id) } or nil
    if find and not transitX then
        local key = "pin:" .. kind .. ":" .. tostring(id)
        local hit = Locate(find, id, key, playerMapID)
        if hit then
            self:Add(results, playerInstance, hit.mapID, hit.pos, {
                key = key,
                title = hit.name,
                atlas = hit.atlas,
                textureIndex = hit.textureIndex,
                isSuperTracked = true,
            })
        end
    end

    -- Tracked points of interest the user did not select: zone-only, like
    -- watched quests (the selected one is handled above with Locate and
    -- the transit arrow).
    if C_ContentTracking and C_ContentTracking.GetTrackedIDs and C_ContentTracking.GetTrackablesOnMap then
        for _, ttype in pairs(Enum.ContentTrackingType or {}) do
            local ids = C_ContentTracking.GetTrackedIDs(ttype)
            local wanted
            for _, tid in ipairs(ids or {}) do
                if not ns.IsSecret(tid) and not (ttype == selType and tid == selID) then
                    wanted = wanted or {}
                    wanted[tid] = true
                end
            end
            if wanted then
                for _, mapID in ipairs(ns.CandidateMaps(playerMapID)) do
                    local res, infos = C_ContentTracking.GetTrackablesOnMap(ttype, mapID)
                    if res == RESULT_SUCCESS then
                        for _, info in ipairs(infos or {}) do
                            if not ns.IsSecret(info.trackableID) and wanted[info.trackableID]
                                and ns.OnMap(mapID, info.x, info.y) then
                                wanted[info.trackableID] = nil
                                self:Add(results, playerInstance, mapID, info, {
                                    key = "pin:ct:" .. ttype .. ":" .. info.trackableID,
                                    title = TrackableTitle(ttype, info.trackableID, info),
                                    atlas = PIN_TRACKED,
                                })
                            end
                        end
                    end
                end
            end
        end
    end

    -- Categories from the minimap tracking menu whose positions are
    -- exposed to addons: flight masters and archaeology dig sites.
    -- Townsfolk and gather/creature tracking blips are engine-drawn and
    -- have no position API.
    local FILTER = Enum.MinimapTrackingFilter or {}
    if FILTER.TaxiNode and C_TaxiMap and ns.TrackingFilterActive(FILTER.TaxiNode) then
        for _, mapID in ipairs(ns.CandidateMaps(playerMapID)) do
            for _, node in ipairs(C_TaxiMap.GetTaxiNodesForMap(mapID) or {}) do
                -- The learned spot replaces the icon's position only; zone
                -- membership still comes from where the icon sits, or a
                -- visited node could leak in from another zone.
                local learned = ns.db and ns.db.taxi and ns.db.taxi[node.nodeID]
                if node.position and TaxiForPlayer(node)
                    and not (kind == "taxi" and node.nodeID == id)
                    and ns.OnMap(mapID, node.position.x, node.position.y) then
                    self:Add(results, playerInstance,
                        learned and learned.m or mapID,
                        learned and { x = learned.x, y = learned.y } or node.position, {
                            key = "pin:taxi:" .. node.nodeID,
                            title = node.name,
                            atlas = node.atlasName,
                        })
                end
            end
        end
    end
    if FILTER.Digsites and C_ResearchInfo and C_ResearchInfo.GetDigSitesForMap
        and ns.TrackingFilterActive(FILTER.Digsites) then
        for _, mapID in ipairs(ns.CandidateMaps(playerMapID)) do
            for _, site in ipairs(C_ResearchInfo.GetDigSitesForMap(mapID) or {}) do
                if site.position and not (kind == "dig" and site.researchSiteID == id)
                    and ns.OnMap(mapID, site.position.x, site.position.y) then
                    self:Add(results, playerInstance, mapID, site.position, {
                        key = "pin:dig:" .. site.researchSiteID,
                        title = site.name,
                        textureIndex = site.textureIndex,
                    })
                end
            end
        end
    end

    -- Battle-pet tracking is a separate flag from the MinimapTrackingFilter
    -- bits; a selected tamer super-tracks as an AreaPOI pin, so skip it here.
    if C_Minimap.IsTrackingBattlePets and C_Minimap.IsTrackingBattlePets()
        and C_PetInfo and C_PetInfo.GetPetTamersForMap then
        for _, mapID in ipairs(ns.CandidateMaps(playerMapID)) do
            for _, tamer in ipairs(C_PetInfo.GetPetTamersForMap(mapID) or {}) do
                if tamer.position and not (kind == "poi" and tamer.areaPoiID == id)
                    and ns.OnMap(mapID, tamer.position.x, tamer.position.y) then
                    self:Add(results, playerInstance, mapID, tamer.position, {
                        key = "pin:tamer:" .. tostring(tamer.areaPoiID),
                        title = tamer.name,
                        atlas = tamer.atlasName,
                        textureIndex = tamer.textureIndex,
                    })
                end
            end
        end
    end

    -- The zone's own points of interest: vignettes are exactly what the
    -- minimap draws as blips (rares, treasures, delve entrances, zone
    -- events). No tracking filter exists for them; they are always on.
    -- Townsfolk blips, by contrast, are engine-drawn with no Lua position
    -- API, so they can never reach the compass.
    if C_VignetteInfo and C_VignetteInfo.GetVignettes then
        for _, guid in ipairs(C_VignetteInfo.GetVignettes() or {}) do
            if not ns.IsSecret(guid) and not (kind == "vignette" and guid == id) then
                local info = C_VignetteInfo.GetVignetteInfo(guid)
                if info and info.onMinimap then
                    for _, mapID in ipairs(ns.CandidateMaps(playerMapID)) do
                        local pos = C_VignetteInfo.GetVignettePosition(guid, mapID)
                        if pos and ns.OnMap(mapID, pos.x, pos.y) then
                            local name = info.name
                            if ns.IsSecret(name) or name == "" then name = nil end
                            self:Add(results, playerInstance, mapID, pos, {
                                key = "pin:vignette:" .. guid,
                                title = name,
                                atlas = info.atlasName,
                            })
                            break
                        end
                    end
                end
            end
        end
    end

    return results
end

-- /ncmp diag: where the selected pin resolves on each map that lists it,
-- and how far that puts it from the player next to the client's own
-- navigation distance (the nav diamond is the ground truth).
function ns.PinDiag(playerMapID, instance, lines)
    local sel = provider.sel
    if not sel then return end
    local nav = C_Navigation and C_Navigation.GetDistance and C_Navigation.GetDistance()
    lines[#lines + 1] = ("selpin %s foundOn=%s navDist=%s"):format(sel.key, tostring(foundOn[sel.key]),
        ns.IsSecret(nav) and "<secret>" or ("%.0f"):format(nav or -1))
    local maps = ns.MapChain(playerMapID)
    for _, child in ipairs(ns.ContinentZones(playerMapID)) do maps[#maps + 1] = child.mapID end
    local p = ns.player
    for _, mapID in ipairs(maps) do
        local hit = sel.find(mapID, sel.id)
        if hit then
            local x, y = ns.MapToWorld(mapID, hit.pos.x, hit.pos.y, instance)
            local d = x and p.x and math.sqrt((x - p.x) ^ 2 + (y - p.y) ^ 2)
            local info = C_Map.GetMapInfo(mapID)
            lines[#lines + 1] = ("  on map=%d type=%s xy=%.5f,%.5f dist=%s"):format(mapID,
                tostring(info and info.mapType), hit.pos.x, hit.pos.y, d and ("%.0f"):format(d) or "nil")
        end
    end
end

-- Arrival: close enough that the bearing would swing wildly. A transit
-- arrow stays visible until the client moves on to the next waypoint.
function provider:IsInRegion(entry, dist)
    return not entry.isTransit and dist <= ARRIVE_YARDS
end

ns.RescanOn({
    "USER_WAYPOINT_UPDATED", "AREA_POIS_UPDATED", "MINIMAP_UPDATE_TRACKING",
    "CONTENT_TRACKING_UPDATE", "CONTENT_TRACKING_LIST_UPDATE",
    "TRACKABLE_INFO_UPDATE", "TRACKING_TARGET_INFO_UPDATE",
    "NEIGHBORHOOD_MAP_DATA_UPDATED",
    "VIGNETTES_UPDATED", "VIGNETTE_MINIMAP_UPDATED",
}, true)
