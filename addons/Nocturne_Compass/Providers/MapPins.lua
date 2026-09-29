local _, ns = ...

-- The player's own map selection: the user waypoint (pin placed on the world
-- map) and a super-tracked map POI (area POI, flight master, vignette), each
-- drawn with its own map icon. Unlike quests (zone only), these are shown
-- anywhere on the player's continent.

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
    if C_SuperTrack.GetSuperTrackedMapPin then
        pinType, pinID = C_SuperTrack.GetSuperTrackedMapPin()
    end
    if pinID and pinType == MapPinType.AreaPOI and C_AreaPoiInfo then
        find, id, kind = FindAreaPOI, pinID, "poi"
    elseif pinID and pinType == MapPinType.TaxiNode and C_TaxiMap then
        find, id, kind = FindTaxiNode, pinID, "taxi"
    elseif C_SuperTrack.GetSuperTrackedVignette and C_VignetteInfo then
        local guid = C_SuperTrack.GetSuperTrackedVignette()
        if guid then find, id, kind = FindVignette, guid, "vignette" end
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

    return results
end

-- Arrival: close enough that the bearing would swing wildly. A transit
-- arrow stays visible until the client moves on to the next waypoint.
function provider:IsInRegion(entry, dist)
    return not entry.isTransit and dist <= ARRIVE_YARDS
end

ns.RescanOn({ "USER_WAYPOINT_UPDATED", "AREA_POIS_UPDATED" }, true)

-- Vignettes (rares, treasures) come and go constantly; only rescan for
-- them while one is (or just was) super-tracked.
_G.Nocturne.RegisterEvent("VIGNETTES_UPDATED", function()
    if provider.hasVignette or
        (C_SuperTrack.GetSuperTrackedVignette and C_SuperTrack.GetSuperTrackedVignette()) then
        ns.MarkScanDirty(true)
    end
end)
