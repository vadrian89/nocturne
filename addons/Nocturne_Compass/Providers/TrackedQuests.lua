local _, ns = ...

-- Collects the player's tracked quests (quest watches + world quest watches)
-- and resolves them to world positions in the player's zone/instance.

local provider = { name = "trackedQuests" }
ns.providers[#ns.providers + 1] = provider

provider.results = {}

-- Maps worth scanning for quest POIs: only the zone the player is in.
-- The walk up the map ancestry covers the player standing inside a
-- cave/dungeon sub-map of the zone; quests anywhere else on the
-- continent/world are intentionally ignored.
local function GetCandidateMaps(playerMapID)
    local maps, seen = {}, {}
    local function add(id)
        if id and not seen[id] then
            seen[id] = true
            maps[#maps + 1] = id
        end
    end

    add(playerMapID)
    add(C_QuestLog.GetMapForQuestPOIs())

    -- Climb the ancestry only while maps are sub-zone (caves/micro maps)
    -- and stop at the zone/dungeon level — never add continent/world maps.
    local info = C_Map.GetMapInfo(playerMapID)
    while info do
        local mt = info.mapType
        add(info.mapID)
        if mt ~= Enum.UIMapType.Micro and mt ~= Enum.UIMapType.Orphan then break end
        if not info.parentMapID or info.parentMapID == 0 then break end
        info = C_Map.GetMapInfo(info.parentMapID)
    end
    return maps
end

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

function provider:Scan(playerMapID, playerInstance)
    local results = wipe(self.results)
    if not playerMapID or not playerInstance then return results end

    local watched, order = {}, {}
    GetWatchedQuests(watched, order)
    if #order == 0 then return results end

    local remaining = #order
    for _, mapID in ipairs(GetCandidateMaps(playerMapID)) do
        if remaining == 0 then break end
        for _, info in ipairs(C_QuestLog.GetQuestsOnMap(mapID) or {}) do
            local w = watched[info.questID]
            if w and not w.found and info.x then
                w.found = { mapID = mapID, x = info.x, y = info.y }
                remaining = remaining - 1
            end
        end
        for _, info in ipairs(C_TaskQuest.GetQuestsOnMap(mapID) or {}) do
            local w = watched[info.questID]
            if w and not w.found and info.x then
                w.found = { mapID = mapID, x = info.x, y = info.y }
                remaining = remaining - 1
            end
        end
    end

    -- Blizzard's own navigation waypoint for the super-tracked quest: for a
    -- same-map quest this is the objective area the client navigates to
    -- (better centered than the map pin); cross-continent it is a transit
    -- waypoint on the player's map.
    local superID = C_SuperTrack.GetSuperTrackedQuestID()
    local superWP, superPlaced
    if superID and superID > 0 then
        local tx, ty = C_SuperTrack.GetNextWaypointForMap(playerMapID)
        if tx and ty then
            local inst, wpos = C_Map.GetWorldPosFromMapPos(playerMapID, CreateVector2D(tx, ty))
            if inst and wpos and inst == playerInstance and
                not ns.IsSecret(wpos.x) and not ns.IsSecret(wpos.y) then
                superWP = wpos
            end
        end
    end

    for _, qid in ipairs(order) do
        local f = watched[qid].found
        if f then
            local inst, wpos = C_Map.GetWorldPosFromMapPos(f.mapID, CreateVector2D(f.x, f.y))
            if inst and wpos and inst == playerInstance then
                local wx, wy = wpos:GetXY()
                if qid == superID then
                    superPlaced = true
                    if superWP then wx, wy = superWP:GetXY() end
                end
                results[#results + 1] = {
                    key = "quest:" .. qid,
                    provider = self,
                    questID = qid,
                    title = C_QuestLog.GetTitleForQuestID(qid) or "Quest",
                    x = wx,
                    y = wy,
                    isComplete = C_QuestLog.IsComplete(qid) or false,
                    classification = C_QuestInfoSystem.GetQuestClassification(qid),
                    isSuperTracked = (qid == superID),
                    isWorldQuest = (watched[qid].kind == "worldquest"),
                }
            end
        end
    end

    -- The super-tracked quest lives on another continent/instance: point the
    -- bar at the client's transit waypoint (if any) instead.
    if superWP and superID and not superPlaced then
        local wx, wy = superWP:GetXY()
        results[#results + 1] = {
            key = "quest:" .. superID,
            provider = self,
            questID = superID,
            title = (C_QuestLog.GetTitleForQuestID(superID) or "Quest"),
            x = wx,
            y = wy,
            isTransit = true,
            isSuperTracked = true,
        }
    end

    return results
end

-- True while the player stands inside the quest's region. GetDistanceSqToQuest
-- measures the distance to the quest's objective area; verify in-game whether
-- it reaches 0 inside the area blob, otherwise tune `inRegionYards`.
function provider:IsInRegion(entry)
    if entry.isTransit then return false end
    local distSq = C_QuestLog.GetDistanceSqToQuest(entry.questID)
    if not distSq or ns.IsSecret(distSq) then return false end
    local r = ns.db.inRegionYards
    return distSq <= r * r
end
