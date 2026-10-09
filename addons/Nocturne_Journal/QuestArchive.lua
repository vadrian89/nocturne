local _, ns = ...

-- The API exposes only IDs for already turned-in quests — no title, no
-- text. We snapshot each live quest's text/objectives/chain into the
-- per-character DB and move it to `completed` on QUEST_TURNED_IN.

local MAX_COMPLETED = 500

local requestedMaps = {}

local function QuestMapID(qid)
    local mapID = C_QuestLog.GetQuestUiMapID and C_QuestLog.GetQuestUiMapID(qid)
    if (not mapID or mapID == 0) and C_Map and C_Map.GetBestMapForUnit then
        mapID = C_Map.GetBestMapForUnit("player")
    end
    if mapID and mapID > 0 then return mapID end
end

-- questLineID, questLineName for a quest, or nil. C_QuestLine answers only
-- for maps that were requested first.
function ns.QuestChainInfo(qid, mapID)
    if not (C_QuestLine and C_QuestLine.GetQuestLineInfo) then return end
    mapID = mapID or QuestMapID(qid)
    if not mapID then return end
    if not requestedMaps[mapID] and C_QuestLine.RequestQuestLinesForMap then
        requestedMaps[mapID] = true
        C_QuestLine.RequestQuestLinesForMap(mapID)
    end
    local info = C_QuestLine.GetQuestLineInfo(qid, mapID)
    if info then return info.questLineID, info.questLineName, mapID end
end

local function Snapshot(qid)
    if not ns.chardb then return end
    local idx = C_QuestLog.GetLogIndexForQuestID(qid)
    if not idx then return end
    local info = C_QuestLog.GetInfo(idx)
    -- SetSelectedQuest takes the questID; the text getter takes the index.
    local GetText = _G.GetQuestLogQuestText
        or C_QuestLog.GetQuestLogQuestText
    local prev, desc, objText
    if GetText then
        if C_QuestLog.SetSelectedQuest then
            prev = C_QuestLog.GetSelectedQuest and C_QuestLog.GetSelectedQuest()
            C_QuestLog.SetSelectedQuest(qid)
        end
        desc, objText = GetText(idx)
        if prev then C_QuestLog.SetSelectedQuest(prev) end
    end

    local snap = ns.chardb.pending[qid] or {}
    ns.chardb.pending[qid] = snap
    snap.qid = qid
    if info then
        if info.title then snap.title = info.title end
        snap.level = info.level
    end
    if not snap.title then snap.title = C_QuestLog.GetTitleForQuestID(qid) end
    if snap.title then ns.chardb.titles[qid] = snap.title end
    if desc and not ns.IsSecret(desc) then snap.desc = desc end
    if objText and not ns.IsSecret(objText) then snap.objText = objText end

    local objs = {}
    for _, o in ipairs(C_QuestLog.GetQuestObjectives(qid) or {}) do
        if o.text and not ns.IsSecret(o.text) then
            objs[#objs + 1] = o.text
        end
    end
    if #objs > 0 then snap.objs = objs end

    local lineID, lineName = ns.QuestChainInfo(qid)
    if lineID then
        snap.lineID = lineID
        snap.lineName = lineName
        snap.lineIDs = C_QuestLine.GetQuestLineQuests(lineID)
    end
end

local function SnapshotAll()
    if not ns.chardb then return end
    local seen = {}
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(i)
        if info and not info.isHeader and info.questID then
            seen[info.questID] = true
            Snapshot(info.questID)
        end
    end
    for qid in pairs(ns.chardb.pending) do
        if not seen[qid] then ns.chardb.pending[qid] = nil end
    end
end

-- Turn-in order is QUEST_TURNED_IN then QUEST_REMOVED; an abandon fires only
-- QUEST_REMOVED, so pending entries surviving TURNED_IN are dropped here.
_G.Nocturne.RegisterEvent("QUEST_TURNED_IN", function(_, qid)
    if not ns.chardb then return end
    local snap = ns.chardb.pending[qid]
    if not snap then
        -- We never saw it live (accepted before install); archive the ID at
        -- least, so it shows up with its title instead of only in Earlier.
        snap = { qid = qid }
    end
    snap.ts = time()
    ns.chardb.pending[qid] = nil
    tinsert(ns.chardb.completed, 1, snap)
    while #ns.chardb.completed > MAX_COMPLETED do
        table.remove(ns.chardb.completed)
    end
    ns.histIDs = nil
    ns.questListDirty = true
    if ns.QuestsRefresh then ns:QuestsRefresh() end
end)

_G.Nocturne.RegisterEvent("QUEST_REMOVED", function(_, qid)
    if ns.chardb then ns.chardb.pending[qid] = nil end
    ns.histIDs = nil
    ns.questListDirty = true
    if ns.QuestsRefresh then ns:QuestsRefresh() end
end)

local snapTimer
local function SnapshotAllSoon()
    if snapTimer then return end
    snapTimer = C_Timer.After(0.5, function()
        snapTimer = nil
        SnapshotAll()
    end)
end

for _, event in ipairs({ "QUEST_ACCEPTED", "QUEST_LOG_UPDATE", "PLAYER_ENTERING_WORLD" }) do
    _G.Nocturne.RegisterEvent(event, SnapshotAllSoon)
end

_G.Nocturne.RegisterEvent("QUEST_DATA_LOAD_RESULT", function()
    ns.questListDirty = true
    if ns.QuestsRefresh then ns:QuestsRefresh() end
end)

-- Completed-quest IDs minus everything we already track (archive, pending,
-- live log). Sorted by ID descending — newer expansions have bigger IDs.
function ns.HistoricalIDs()
    if ns.histIDs then return ns.histIDs end
    ns.histIDs = {}
    if not (ns.chardb and C_QuestLog.GetAllCompletedQuestIDs) then return ns.histIDs end
    local known = {}
    for _, e in ipairs(ns.chardb.completed) do known[e.qid] = true end
    for qid in pairs(ns.chardb.pending) do known[qid] = true end
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(i)
        if info and not info.isHeader and info.questID then known[info.questID] = true end
    end
    local ids = C_QuestLog.GetAllCompletedQuestIDs()
    if ids then
        table.sort(ids, function(a, b) return a > b end)
        for _, qid in ipairs(ids) do
            if not known[qid] then ns.histIDs[#ns.histIDs + 1] = qid end
        end
    end
    return ns.histIDs
end

-- Title for any quest ID: live log, archive, cached, else async request.
function ns.QuestTitle(qid)
    local t = ns.chardb and ns.chardb.titles[qid]
    if not t then
        t = C_QuestLog.GetTitleForQuestID(qid)
        if t and t ~= "" and ns.chardb then ns.chardb.titles[qid] = t end
    end
    if t and t ~= "" then return t end
    if C_QuestLog.RequestLoadQuestByID then C_QuestLog.RequestLoadQuestByID(qid) end
end
