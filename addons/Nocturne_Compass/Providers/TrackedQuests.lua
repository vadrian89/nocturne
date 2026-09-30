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

-- The offer classifications Blizzard can pin (questOfferPinData in
-- QuestOfferDataProvider); world quests, bonus objectives and friends-
-- recruiting entries get no pin and are dropped.
local OFFER_CLASS = {}
for _, name in ipairs({ "Normal", "Questline", "Recurring", "Meta", "Calling",
    "Campaign", "Legendary", "Important" }) do
    local c = Enum.QuestClassification and Enum.QuestClassification[name]
    if c then OFFER_CLASS[c] = true end
end

-- Every offer source for a map, merged in Blizzard's priority order
-- (quest lines, force-visible quests, task info). Task info lacks
-- isHidden/isAccountCompleted; CreateQuestOfferFromTaskInfo fills them
-- from IsQuestTrivial/IsQuestFlaggedCompletedOnAccount the same way.
local function EachOffer(mapID, cb)
    for _, info in ipairs(QuestOffersOnMap(mapID) or {}) do
        cb(info, "line")
    end
    if C_QuestLine.GetForceVisibleQuests and C_QuestLine.GetQuestLineInfo then
        for _, qid in ipairs(C_QuestLine.GetForceVisibleQuests(mapID) or {}) do
            cb(C_QuestLine.GetQuestLineInfo(qid, mapID), "force")
        end
    end
    -- GetQuestsOnMap covers standalone quests that belong to no quest
    -- line; isQuestStart marks the unaccepted "!" offers among them.
    if C_QuestLog.GetQuestsOnMap then
        for _, info in ipairs(C_QuestLog.GetQuestsOnMap(mapID) or {}) do
            if info.isQuestStart then
                if C_QuestLog.IsQuestTrivial then
                    info.isHidden = C_QuestLog.IsQuestTrivial(info.questID)
                end
                if C_QuestLog.IsQuestFlaggedCompletedOnAccount then
                    info.isAccountCompleted = C_QuestLog.IsQuestFlaggedCompletedOnAccount(info.questID)
                end
                cb(info, "poi")
            end
        end
    end
    if C_TaskQuest and C_TaskQuest.GetQuestsOnMap then
        for _, info in ipairs(C_TaskQuest.GetQuestsOnMap(mapID) or {}) do
            if C_QuestLog.IsQuestTrivial then
                info.isHidden = C_QuestLog.IsQuestTrivial(info.questID)
            end
            if C_QuestLog.IsQuestFlaggedCompletedOnAccount then
                info.isAccountCompleted = C_QuestLog.IsQuestFlaggedCompletedOnAccount(info.questID)
            end
            cb(info, "task")
        end
    end
end

-- Blizzard's ShouldAddQuestOffer: drops in-progress quests, offers that
-- start on another (non-child) map, hidden offers without the hidden-
-- quests toggle and account-completed offers without that tracking flag.
local function ShowableOffer(info, mapID, hiddenOn, accountOn)
    if info.inProgress then return false end
    local class = C_QuestInfoSystem.GetQuestClassification(info.questID)
    if ns.IsSecret(class) or not OFFER_CLASS[class] then return false end
    if info.startMapID and info.startMapID ~= 0 and info.startMapID ~= mapID
        and not ns.IsDescendantOf(info.startMapID, mapID) then
        return false
    end
    if info.isHidden and not hiddenOn then return false end
    if info.isAccountCompleted and not accountOn then
        local keep = info.questLineID and C_QuestLine.QuestLineIgnoresAccountCompletedFiltering
            and C_QuestLine.QuestLineIgnoresAccountCompletedFiltering(mapID, info.questLineID)
        if not keep and C_QuestLog.QuestIgnoresAccountCompletedFiltering then
            keep = C_QuestLog.QuestIgnoresAccountCompletedFiltering(info.questID)
        end
        if not keep then return false end
    end
    return true
end

-- Offers carry coordinates in their start map's own space and
-- ShowableOffer already gates the zone by startMapID, so point-in-zone
-- probing (GetMapInfoAtPosition, which can name a neighbouring map for a
-- valid offer) only applies to offers without a start map (task info).
local function OfferOnMap(mapID, info)
    if not info.x or not info.y then return false end
    if info.startMapID and info.startMapID ~= 0 then
        return info.x >= 0 and info.x <= 1 and info.y >= 0 and info.y <= 1
    end
    return ns.OnMap(mapID, info.x, info.y)
end

-- /ncmp diag: every offer the client lists for the player's maps, with the
-- verdict of each filter so a missing "!" can be traced to its cause.
function ns.OfferDiag(playerMapID, lines)
    local F = Enum.MinimapTrackingFilter or {}
    local hiddenOn = C_Minimap.IsTrackingHiddenQuests and C_Minimap.IsTrackingHiddenQuests()
    local accountOn = C_Minimap.IsTrackingAccountCompletedQuests and C_Minimap.IsTrackingAccountCompletedQuests()
    lines[#lines + 1] = ("offers hiddenOn=%s accountOn=%s questPOIsOn=%s trivialOn=%s"):format(
        tostring(hiddenOn), tostring(accountOn),
        tostring(F.QuestPOIs and ns.TrackingFilterActive(F.QuestPOIs, true)),
        tostring(F.TrivialQuests and ns.TrackingFilterActive(F.TrivialQuests)))
    local function S(v) return ns.IsSecret(v) and "<secret>" or tostring(v) end
    for _, mapID in ipairs(ns.CandidateMaps(playerMapID)) do
        local counts = {}
        EachOffer(mapID, function(info, src)
            counts[src] = (counts[src] or 0) + 1
            local qid = info and info.questID
            if not qid or ns.IsSecret(qid) then return end
            local class = C_QuestInfoSystem.GetQuestClassification(qid)
            lines[#lines + 1] = ("  offer map=%d src=%s q=%d class=%s start=%s prog=%s hid=%s acct=%s sm=%s onMap=%s showable=%s xy=%.2f,%.2f")
            :format(
                mapID, src, qid, S(class), S(info.isQuestStart), S(info.inProgress), S(info.isHidden),
                S(info.isAccountCompleted), S(info.startMapID),
                tostring(OfferOnMap(mapID, info)),
                tostring(ShowableOffer(info, mapID, hiddenOn, accountOn)), info.x or -1, info.y or -1)
        end)
        lines[#lines + 1] = ("  map=%d totals line=%d force=%d poi=%d task=%d"):format(
            mapID, counts.line or 0, counts.force or 0, counts.poi or 0, counts.task or 0)
    end
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

    -- Quest offers (available, unaccepted "!" givers) are never watched,
    -- so they bypass the watched-set path entirely. Hidden (trivial) ones
    -- ride the hidden-quests toggle, the rest the "Quest POIs" filter —
    -- which defaults to on when the client doesn't list it in the menu.
    local F = Enum.MinimapTrackingFilter or {}
    local hiddenOn = C_Minimap.IsTrackingHiddenQuests and C_Minimap.IsTrackingHiddenQuests()
        or (F.TrivialQuests and ns.TrackingFilterActive(F.TrivialQuests))
    local accountOn = C_Minimap.IsTrackingAccountCompletedQuests
        and C_Minimap.IsTrackingAccountCompletedQuests()
    local offersOn = not F.QuestPOIs or ns.TrackingFilterActive(F.QuestPOIs, true)
    if hiddenOn or offersOn then
        local seen = {}
        for _, mapID in ipairs(ns.CandidateMaps(playerMapID)) do
            EachOffer(mapID, function(info)
                local qid = info.questID
                if not (qid and not ns.IsSecret(qid) and not watched[qid] and not seen[qid]
                        and (info.isHidden and hiddenOn or (not info.isHidden and offersOn))
                        and ShowableOffer(info, mapID, hiddenOn, accountOn)
                        and OfferOnMap(mapID, info)) then
                    return
                end
                local wx, wy = ns.MapToWorld(mapID, info.x, info.y, playerInstance)
                if not wx then return end
                seen[qid] = true
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
            end)
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
