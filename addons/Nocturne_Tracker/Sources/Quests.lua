local _, ns = ...

-- Watched quests grouped by quest-log category, then bonus objectives and
-- world quests (watched + the ones in the current area, like Blizzard's
-- tracker shows them).

local Nocturne = _G.Nocturne
local T = Nocturne.Theme
local C = ns.colors

local IsShiftKeyDown = IsShiftKeyDown
local GetQuestLogCompletionText = GetQuestLogCompletionText
local GetQuestObjectiveInfo = GetQuestObjectiveInfo
local GetQuestProgressBarPercent = _G.GetQuestProgressBarPercent or C_QuestLog.GetQuestProgressBarPercent
local GetQuestLogSpecialItemInfo = GetQuestLogSpecialItemInfo
local GetTasksTable, GetTaskInfo = GetTasksTable, GetTaskInfo

local EMPTY = {}
local QUESTS_LABEL = "Quests"
local WQ_LABEL = _G.TRACKER_HEADER_WORLD_QUESTS or "World Quests"
local BONUS_LABEL = _G.TRACKER_HEADER_BONUS_OBJECTIVES or "Bonus Objectives"

local order, kindOf, catOf, dailyOf, watchedOf = {}, {}, {}, {}, {} -- scratch, wiped each rebuild
local areaWQ = {}                       -- area world quests, appended after the watched ones
local cats = {}                         -- category names in first-seen order
local catQuests = {}                    -- category name -> ordered questID list (reused)

local function Add(qid, kind, watched)
    if qid and not kindOf[qid] then
        kindOf[qid], watchedOf[qid] = kind, watched
        order[#order + 1] = qid
    end
end

-- Tasks (bonus objectives, world quests) the player is standing in.
local function CollectAreaTasks()
    if not (GetTasksTable and GetTaskInfo) then return end
    for _, qid in ipairs(GetTasksTable() or EMPTY) do
        local isInArea, _, numObjectives = GetTaskInfo(qid)
        if ns.Flag(isInArea) and not ns.IsSecret(numObjectives) and (numObjectives or 0) > 0 then
            if C_QuestLog.IsWorldQuest(qid) then
                areaWQ[#areaWQ + 1] = qid
            else
                Add(qid, "task", false)
            end
        end
    end
end

local function CollectIDs(db)
    wipe(order)
    wipe(kindOf)
    wipe(catOf)
    wipe(dailyOf)
    wipe(watchedOf)
    wipe(areaWQ)
    for i = 1, C_QuestLog.GetNumQuestWatches() or 0 do
        Add(C_QuestLog.GetQuestIDForQuestWatchIndex(i), "quest", true)
    end
    if db.showAreaTasks then CollectAreaTasks() end
    for i = 1, C_QuestLog.GetNumWorldQuestWatches() or 0 do
        Add(C_QuestLog.GetQuestIDForWorldQuestWatchIndex(i), "worldquest", true)
    end
    for _, qid in ipairs(areaWQ) do Add(qid, "worldquest", false) end

    -- Quest log section each quest belongs to (zone, campaign…): walk the
    -- log, remember the current header for every quest entry.
    local current
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(i)
        if info then
            if info.isHeader then
                current = info.title
            elseif info.questID then
                catOf[info.questID] = current or ""
                dailyOf[info.questID] = (info.frequency or 0) > 0
            end
        end
    end
    for _, qid in ipairs(order) do
        local kind = kindOf[qid]
        if kind == "worldquest" then
            catOf[qid] = WQ_LABEL
        elseif kind == "task" then
            catOf[qid] = BONUS_LABEL
        end
    end
end

local function GetAtlas(qid, isComplete)
    local class = C_QuestInfoSystem and C_QuestInfoSystem.GetQuestClassification(qid)
    if ns.IsSecret(class) then class = nil end
    return Nocturne.QuestAtlas(class, isComplete, kindOf[qid] == "worldquest", dailyOf[qid])
end

local function GetTitle(qid)
    local title = C_QuestLog.GetTitleForQuestID(qid)
    if (not title or title == "") and C_TaskQuest.GetQuestInfoByQuestID then
        title = C_TaskQuest.GetQuestInfoByQuestID(qid)
    end
    return title or ("Quest " .. qid)
end

local function GetObjectives(qid)
    local objs = C_QuestLog.GetQuestObjectives(qid)
    if objs and #objs > 0 then return objs end
    -- World/task quests may not be covered by GetQuestObjectives.
    if not GetQuestObjectiveInfo then return objs or EMPTY end
    objs = {}
    for i = 1, 10 do
        local text, objType, finished = GetQuestObjectiveInfo(qid, i, false)
        if not text then break end
        objs[i] = { text = text, type = objType, finished = finished }
    end
    return objs
end

-- GetQuestLogCompletionText takes a quest LOG INDEX, not a questID.
local function GetCompletionText(qid)
    local idx = GetQuestLogCompletionText and C_QuestLog.GetLogIndexForQuestID(qid)
    local txt = idx and GetQuestLogCompletionText(idx)
    if not txt or ns.IsSecret(txt) or txt == "" then return "Ready for turn-in" end
    return txt
end

-- Progress-bar objectives (bonus objectives, many world quests) carry their
-- progress separately from the text.
local function GetObjectiveText(qid, o)
    local text = o.text
    if ns.IsSecret(text) then return nil end
    if o.type == "progressbar" and GetQuestProgressBarPercent then
        local pct = GetQuestProgressBarPercent(qid)
        if pct and not ns.IsSecret(pct) then
            if text and text ~= "" then
                text = ("%s (%d%%)"):format(text, pct)
            else
                text = ("%d%%"):format(pct)
            end
        end
    end
    if text and text ~= "" then return text end
end

-- Usable quest item, rendered as a secure button by ItemButtons.lua.
local function SetItem(e, qid, isComplete)
    if not GetQuestLogSpecialItemInfo then return end
    local idx = C_QuestLog.GetLogIndexForQuestID(qid)
    if not idx then return end
    local link, texture, charges, showWhenComplete = GetQuestLogSpecialItemInfo(idx)
    if not link or ns.IsSecret(link) or (isComplete and not ns.Flag(showWhenComplete)) then return end
    local itemID = tonumber(link:match("item:(%d+)"))
    if not itemID then return end
    if ns.IsSecret(charges) then charges = nil end
    e.itemID, e.itemLink, e.itemTexture, e.itemCharges = itemID, link, texture, charges
end

local function FillEntry(e, qid, superID, db)
    local kind = kindOf[qid]
    local isComplete = kind == "quest" and ns.Flag(C_QuestLog.IsComplete(qid))
    local objs = GetObjectives(qid)
    -- Quests without objectives ("talk to X") are complete the moment
    -- they're accepted; only quests whose objectives got done go green.
    local objectivesDone = isComplete and #objs > 0

    e.kind, e.id, e.watched = kind, qid, watchedOf[qid]
    e.title = GetTitle(qid)
    e.titleColor = (qid == superID and T.colors.accent) or (objectivesDone and C.done) or C.title
    e.atlas = GetAtlas(qid, isComplete)

    if isComplete then
        ns.AddLine(e, GetCompletionText(qid), objectivesDone and C.done or C.line)
    else
        for _, o in ipairs(objs) do
            local text = GetObjectiveText(qid, o)
            if text then ns.AddLine(e, text, ns.Flag(o.finished) and C.lineDone or C.line) end
        end
    end
    if db.showItems then SetItem(e, qid, isComplete) end
end

local src = { name = "quests" }
ns.sources[#ns.sources + 1] = src

function src:Collect(db)
    CollectIDs(db)
    local superID = C_SuperTrack.GetSuperTrackedQuestID()
    if not superID or ns.IsSecret(superID) then superID = nil end

    -- Group by category, preserving first-seen order: log categories of the
    -- watched quests, then bonus objectives, then world quests.
    wipe(cats)
    for _, list in pairs(catQuests) do wipe(list) end
    for _, qid in ipairs(order) do
        local cat = catOf[qid] or ""
        local list = catQuests[cat]
        if not list then
            list = {}
            catQuests[cat] = list
        end
        if #list == 0 then cats[#cats + 1] = cat end
        list[#list + 1] = qid
    end

    for _, cat in ipairs(cats) do
        local s = ns.NewSection(cat ~= "" and cat or QUESTS_LABEL)
        for _, qid in ipairs(catQuests[cat]) do
            FillEntry(ns.AddEntry(s), qid, superID, db)
        end
    end
end

local function ClearSuperTrack()
    if C_SuperTrack.ClearAllSuperTracked then
        C_SuperTrack.ClearAllSuperTracked()
    else
        C_SuperTrack.SetSuperTrackedQuestID(0)
    end
end

local function OnQuestClick(e, button)
    local qid = e.id
    if button == "RightButton" then
        if not e.watched then return end
        if e.kind == "worldquest" then
            C_QuestLog.RemoveWorldQuestWatch(qid)
        else
            C_QuestLog.RemoveQuestWatch(qid)
        end
    elseif IsShiftKeyDown() and e.kind == "quest" and _G.QuestMapFrame_OpenToQuestDetails then
        _G.QuestMapFrame_OpenToQuestDetails(qid)
    else
        local cur = C_SuperTrack.GetSuperTrackedQuestID()
        if cur and not ns.IsSecret(cur) and cur == qid then
            ClearSuperTrack()
        else
            C_SuperTrack.SetSuperTrackedQuestID(qid)
        end
    end
end

ns.kinds.quest = {
    OnClick = OnQuestClick,
    hint = "Click: super-track | Shift-click: details | Right-click: untrack",
}
ns.kinds.worldquest = {
    OnClick = OnQuestClick,
    hint = function(e)
        return e.watched and "Click: super-track | Right-click: untrack" or "Click: super-track"
    end,
}
ns.kinds.task = { OnClick = OnQuestClick, hint = "Click: super-track" }

ns.RebuildOn({
    "QUEST_WATCH_LIST_CHANGED",
    "QUEST_WATCH_UPDATE",
    "QUEST_LOG_UPDATE",
    "QUEST_ACCEPTED",
    "QUEST_REMOVED",
    "QUEST_TURNED_IN",
    "QUEST_POI_UPDATE",
    "SUPER_TRACKING_CHANGED",
    "WORLD_QUEST_COMPLETED",
    -- Area tasks come and go with the player's position.
    "ZONE_CHANGED",
    "ZONE_CHANGED_NEW_AREA",
})
