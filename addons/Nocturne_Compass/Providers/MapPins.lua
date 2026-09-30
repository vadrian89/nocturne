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

local function FindTaxiNode(mapID, nodeID)
    for _, node in ipairs(C_TaxiMap.GetTaxiNodesForMap(mapID) or {}) do
        if node.nodeID == nodeID and node.position then
            return { pos = node.position, name = node.name, atlas = node.atlasName }
        end
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
        hit.mapID = mapID
        foundOn[key] = mapID
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
    if wp and wp.position and not (tracked and transitX) then
        self:Add(results, playerInstance, wp.uiMapID, wp.position, {
            key = "pin:user",
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
    self.hasVignette = kind == "vignette"
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
                if node.position and TaxiForPlayer(node) and not (kind == "taxi" and node.nodeID == id)
                    and ns.OnMap(mapID, node.position.x, node.position.y) then
                    self:Add(results, playerInstance, mapID, node.position, {
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

    return results
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
}, true)

-- Vignettes (rares, treasures) come and go constantly; only rescan for
-- them while one is (or just was) super-tracked.
_G.Nocturne.RegisterEvent("VIGNETTES_UPDATED", function()
    if provider.hasVignette or
        (C_SuperTrack.GetSuperTrackedVignette and C_SuperTrack.GetSuperTrackedVignette()) then
        ns.MarkScanDirty(true)
    end
end)
