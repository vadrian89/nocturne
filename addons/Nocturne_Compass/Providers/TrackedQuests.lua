local _, ns = ...

-- Collects the player's tracked quests (quest watches + world quest watches)
-- and resolves them to world positions in the player's zone/instance.

local IsInsideQuestBlob = C_Minimap and C_Minimap.IsInsideQuestBlob
local GetTime = GetTime

local function QuestAtlas(e, isDaily)
    if e.isTransit then return ns.TransitAtlas() end
    return _G.Nocturne.QuestAtlas(e.classification, e.isComplete, e.isWorldQuest, isDaily)
end

local provider = { name = "trackedQuests" }
ns.providers[#ns.providers + 1] = provider

provider.results = {}

local function GetWatchedQuests(watched, order)
    for i = 1, C_QuestLog.GetNumQuestWatches() or 0 do
        local qid = C_QuestLog.GetQuestIDForQuestWatchIndex(i)
        if qid and not watched[qid] then
            watched[qid] = { kind = "quest" }
            order[#order + 1] = qid
        end
    end
    for i = 1, C_QuestLog.GetNumWorldQuestWatches() or 0 do
        local qid = C_QuestLog.GetQuestIDForWorldQuestWatchIndex(i)
        if qid and not watched[qid] then
            watched[qid] = { kind = "worldquest" }
            order[#order + 1] = qid
        end
    end
end

-- Record every still-unfound quest of `watched` listed on `mapID`.
local function MatchPOIs(mapID, pois, watched)
    local n = 0
    for _, info in ipairs(pois or {}) do
        local w = watched[info.questID]
        if w and not w.found and info.x then
            w.found = { mapID = mapID, x = info.x, y = info.y, name = info.questName, isDaily = info.isDaily }
            n = n + 1
        end
    end
    return n
end

-- Quest offers (not yet accepted quests shown on the map) load on demand:
-- request an empty map at most once a minute (the client may drop the data
-- again); QUESTLINE_UPDATE then triggers a rescan.
local OFFER_REQUEST_INTERVAL = 60
local requestedOffers = {}
local function QuestOffersOnMap(mapID)
    if not C_QuestLine then return nil end
    local offers = C_QuestLine.GetAvailableQuestLines(mapID)
    if (not offers or #offers == 0) and C_QuestLine.RequestQuestLinesForMap then
        local now = GetTime()
        if now - (requestedOffers[mapID] or -OFFER_REQUEST_INTERVAL) >= OFFER_REQUEST_INTERVAL then
            requestedOffers[mapID] = now
            C_QuestLine.RequestQuestLinesForMap(mapID)
        end
    end
    return offers
end

local function MatchMap(mapID, watched)
    if not mapID or mapID == 0 then return 0 end
    return MatchPOIs(mapID, C_QuestLog.GetQuestsOnMap(mapID), watched)
        + MatchPOIs(mapID, C_TaskQuest.GetQuestsOnMap(mapID), watched)
        + MatchPOIs(mapID, QuestOffersOnMap(mapID), watched)
end

-- Map the selected quest was last found on, so rescans skip the search;
-- and the search epoch in which a continent-wide search last missed.
local superMapCache = {}
local missedAt = {}

-- The selected quest anywhere on the player's continent: the map it was
-- last found on, its own quest map, then every zone of the continent (the
-- latter at most once per search epoch).
local function FindOnContinent(qid, w, playerMapID)
    local only = { [qid] = w }
    local own
    if w.kind == "worldquest" then
        own = C_TaskQuest.GetQuestZoneID and C_TaskQuest.GetQuestZoneID(qid)
    elseif GetQuestUiMapID then
        own = GetQuestUiMapID(qid)
    end
    if MatchMap(superMapCache[qid], only) == 0 and MatchMap(own, only) == 0
        and missedAt[qid] ~= ns.searchEpoch then
        for _, child in ipairs(ns.ContinentZones(playerMapID)) do
            if MatchMap(child.mapID, only) > 0 then break end
        end
    end
    if w.found then
        superMapCache[qid], missedAt[qid] = w.found.mapID, nil
    else
        missedAt[qid] = ns.searchEpoch
    end
end

-- Tracked quests are limited to the player's zone; the selected
-- (super-tracked) quest, watched or not, is shown anywhere on the continent.
function provider:Scan(playerMapID, playerInstance)
    local results = wipe(self.results)
    if not playerMapID or not playerInstance then return results end

    local watched, order = {}, {}
    GetWatchedQuests(watched, order)

    local superID = ns.GetSelectedQuestID()
    if superID and not watched[superID] then
        watched[superID] = { kind = C_QuestLog.IsWorldQuest(superID) and "worldquest" or "quest" }
        order[#order + 1] = superID
    end
    if #order == 0 then return results end

    local remaining = #order
    for _, mapID in ipairs(ns.CandidateMaps(playerMapID)) do
        if remaining == 0 then break end
        remaining = remaining - MatchMap(mapID, watched)
    end

    -- A route that leaves the map (portal, boat, zone exit): the bar points
    -- at the transit waypoint with the transit arrow instead of the quest.
    local transitX, transitY
    if superID then
        transitX, transitY = ns.TransitWaypoint(playerMapID, playerInstance)
        if not transitX and not watched[superID].found then
            FindOnContinent(superID, watched[superID], playerMapID)
        end
    end

    for _, qid in ipairs(order) do
        local w = watched[qid]
        local isTransit = qid == superID and transitX ~= nil
        local wx, wy
        if isTransit then
            wx, wy = transitX, transitY
        elseif w.found then
            wx, wy = ns.MapToWorld(w.found.mapID, w.found.x, w.found.y, playerInstance)
        end
        if wx then
            local e = {
                key = "quest:" .. qid,
                provider = self,
                questID = qid,
                title = C_QuestLog.GetTitleForQuestID(qid) or (w.found and w.found.name) or "Quest",
                x = wx,
                y = wy,
                isTransit = isTransit,
                isComplete = C_QuestLog.IsComplete(qid) or false,
                classification = C_QuestInfoSystem.GetQuestClassification(qid),
                isSuperTracked = (qid == superID),
                isWorldQuest = (w.kind == "worldquest"),
            }
            e.atlas = QuestAtlas(e, w.found and w.found.isDaily)
            results[#results + 1] = e
        end
    end

    -- Quest offers (available, unaccepted "!" givers) are never watched, so
    -- they bypass the watched-set path entirely: trivial ones ride the
    -- "Trivial Quests" filter, the rest the always-on "Quest POIs" filter.
    local F = Enum.MinimapTrackingFilter or {}
    local trivialOn = F.TrivialQuests and C_QuestLog.IsQuestTrivial
        and ns.TrackingFilterActive(F.TrivialQuests)
    local offersOn = not F.QuestPOIs or ns.TrackingFilterActive(F.QuestPOIs)
    if trivialOn or offersOn then
        for _, mapID in ipairs(ns.CandidateMaps(playerMapID)) do
            for _, info in ipairs(QuestOffersOnMap(mapID) or {}) do
                local qid = info.questID
                if qid and not watched[qid] and not ns.IsSecret(qid) and ns.OnMap(mapID, info.x, info.y) then
                    local trivial = C_QuestLog.IsQuestTrivial and C_QuestLog.IsQuestTrivial(qid)
                    if (trivial and trivialOn) or (not trivial and offersOn) then
                        local wx, wy = ns.MapToWorld(mapID, info.x, info.y, playerInstance)
                        if wx then
                            local e = {
                                key = "quest:" .. qid,
                                provider = self,
                                questID = qid,
                                title = C_QuestLog.GetTitleForQuestID(qid) or info.questName or "Quest",
                                x = wx,
                                y = wy,
                                isComplete = false,
                                classification = C_QuestInfoSystem.GetQuestClassification(qid),
                                isWorldQuest = false,
                            }
                            e.atlas = QuestAtlas(e, info.isDaily)
                            results[#results + 1] = e
                        end
                    end
                end
            end
        end
    end

    return results
end

-- Enum.NavigationState: the super-tracked diamond is transparent in
-- Invalid/Disabled and solid in Occluded/InRange.
local NAV_STATE_INVALID, NAV_STATE_DISABLED = 0, 3

-- The client's own "arrived" verdict: while a quest is super-tracked the
-- navigation frame exists, and its target state flips to Invalid once the
-- client decides the player reached the quest area (the gold diamond
-- fades out). nil = no verdict (no navigation, or navigation disabled) —
-- the caller falls back to pin distance.
local function NavArrived()
    local N = C_Navigation
    if not (N and N.GetFrame and N.GetFrame()) then return nil end
    local state = N.GetTargetState and N.GetTargetState()
    if state == nil or ns.IsSecret(state) or state == NAV_STATE_DISABLED then return nil end
    return state == NAV_STATE_INVALID
end
ns.NavArrived = NavArrived

-- True while the player stands inside the quest's region. The quest blob
-- (the yellow area on the map) is the real region boundary; quests without
-- a blob fall back to a radius around the pin (GetDistanceSqToQuest
-- measures to the pin, never to the area — verified in-game).
-- IsInsideQuestBlob answers regardless of the minimap being suppressed
-- (unverified whether it keeps updating long-term while hidden); if it
-- can't answer for the selected quest, the navigation diamond's arrival
-- state is the next-best verdict before falling back to pin distance.
function provider:IsInRegion(entry)
    if entry.isTransit then return false end
    if IsInsideQuestBlob then
        local inside = IsInsideQuestBlob(entry.questID)
        if not ns.IsSecret(inside) and inside then return true end
    end
    if entry.isSuperTracked then
        local arrived = NavArrived()
        if arrived ~= nil then return arrived end
    end
    local distSq = C_QuestLog.GetDistanceSqToQuest(entry.questID)
    if not distSq or ns.IsSecret(distSq) then return false end
    local r = ns.db.inRegionYards
    return distSq <= r * r
end
