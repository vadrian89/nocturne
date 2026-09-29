local _, ns = ...

local M = ns.math
local PI2 = math.pi * 2

-- Normalize an angle to [-pi, pi].
function M.WrapAnglePi(a)
    if a > math.pi then return a - PI2 end
    if a < -math.pi then return a + PI2 end
    return a
end

-- Straight-line distance for a world-space delta (yards).
function M.Distance(dx, dy)
    return math.sqrt(dx * dx + dy * dy)
end

-- Conventions verified live against the Blizzard nav arrow (see AGENTS.md):
--   world deltas: +x = north, +y = west (90°-rotated vs map orientation)
--   GetPlayerFacing(): radians CCW from north (0 = N, turning left increases)

-- World position of a map-relative point; nil when it lies in another
-- instance than `instance` (so both ends share one coordinate frame) or
-- the client hands back secret values.
function ns.MapToWorld(mapID, x, y, instance)
    local inst, wpos = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(x, y))
    if not inst or inst ~= instance or not wpos then return nil end
    if ns.IsSecret(wpos.x) or ns.IsSecret(wpos.y) then return nil end
    return wpos:GetXY()
end

-- `mapID` and its ancestors up to (and including) the continent. Second
-- result: info of the last map in the chain.
function ns.MapChain(mapID)
    local chain = {}
    local info = mapID and C_Map.GetMapInfo(mapID)
    while info do
        chain[#chain + 1] = info.mapID
        if info.mapType <= Enum.UIMapType.Continent then break end
        local parent = info.parentMapID
        info = parent and parent ~= 0 and C_Map.GetMapInfo(parent) or nil
    end
    return chain, info
end

-- Zones of the continent `mapID` belongs to; empty when it has none (e.g.
-- orphan/instance maps).
function ns.ContinentZones(mapID)
    local _, top = ns.MapChain(mapID)
    if not top or top.mapType ~= Enum.UIMapType.Continent then return {} end
    return C_Map.GetMapChildrenInfo(top.mapID, Enum.UIMapType.Zone, true) or {}
end

-- Blizzard's next navigation waypoint towards whatever is super-tracked.
-- The client only returns one when the route leaves the map (portal, boat,
-- zone exit — see AGENTS.md); asked from the player's map upwards since a
-- cave/micro map may not carry it.
function ns.TransitWaypoint(playerMapID, instance)
    for _, mapID in ipairs(ns.MapChain(playerMapID)) do
        local tx, ty = C_SuperTrack.GetNextWaypointForMap(mapID)
        if tx and ty then
            local x, y = ns.MapToWorld(mapID, tx, ty, instance)
            if x then return x, y end
        end
    end
end

-- The selected quest: the super-tracked quest, or a quest offer picked on
-- the map (the client super-tracks that as a map pin, not as a quest).
local QUEST_OFFER = Enum.SuperTrackingMapPinType and Enum.SuperTrackingMapPinType.QuestOffer
function ns.GetSelectedQuestID()
    local id = C_SuperTrack.GetSuperTrackedQuestID()
    if id and id > 0 then return id end
    if QUEST_OFFER and C_SuperTrack.GetSuperTrackedMapPin then
        local pinType, pinID = C_SuperTrack.GetSuperTrackedMapPin()
        if pinType == QUEST_OFFER and pinID and pinID > 0 then return pinID end
    end
end

function ns.TransitAtlas()
    return ns.FirstAtlas("Navigation-Tracked-Arrow", "MinimapArrow")
end

-- Direction the player faces, expressed as a CW compass bearing.
function ns.FacingCW()
    local f = ns.player.facing
    return f and (PI2 - f) % PI2 or nil
end

-- Signed angle of a world direction relative to heading: >0 = to the right.
function ns.RelAngle(dx, dy)
    -- east = -dy, north = dx -> bearing = atan2(east, north)
    local bearing = math.atan2(-dy, dx) % PI2
    return M.WrapAnglePi(bearing - ns.FacingCW())
end

function M.Clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

function M.Lerp(a, b, t)
    return a + (b - a) * t
end
