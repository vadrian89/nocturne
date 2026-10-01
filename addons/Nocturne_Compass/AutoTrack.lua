local _, ns = ...

-- Automatic super-tracking (setting `autoSuperTrack`). Candidates are the
-- quests on the objective tracker (quest + world quest watches).
-- 1. Nothing super-tracked at all, and a candidate in range → track it.
-- 2. The super-tracked quest's objectives just got completed and another
--    unfinished candidate is in range → move to it. Otherwise it stays:
--    Blizzard's pin then points at the turn-in (and auto-complete quests
--    simply keep it).
-- Nothing else ever replaces what is super-tracked — not a manual pick,
-- not a waypoint/map pin/vignette — and nothing runs on a taxi or in an
-- instance.
--
-- "In range": within `autoTrackYards` of the quest pin
-- (GetDistanceSqToQuest measures to the pin), or inside the quest's area —
-- the area test only while the minimap is shown.

local Nocturne = _G.Nocturne
local IsInsideQuestBlob = C_Minimap and C_Minimap.IsInsideQuestBlob
local QC = Enum.QuestClassification or {}

-- Picked first when several candidates are in range; then the nearest.
local PRIORITY = {}
for _, name in ipairs({ "Campaign", "Important", "Legendary" }) do
    if QC[name] then PRIORITY[QC[name]] = true end
end

local function Enabled()
    local db = ns.db
    if not (db and db.autoSuperTrack) then return false end
    if IsInInstance() or (UnitOnTaxi and UnitOnTaxi("player")) then return false end
    return GetPlayerFacing() ~= nil
end

-- Nothing of any kind is super-tracked (quest, offer, waypoint, map pin,
-- vignette, content): the highest-priority type is nil (seen in /ncmp diag).
local function NothingSuperTracked()
    return C_SuperTrack.GetHighestPrioritySuperTrackingType() == nil
end

local function MinimapShown()
    local f = ns.minimapFrame or _G.MinimapCluster
    return f and f:IsVisible() and f:GetAlpha() > 0 or false
end

-- In range + the pin distance² for sorting (huge when unknown).
local function InRange(qid)
    local d = C_QuestLog.GetDistanceSqToQuest(qid)
    if d and ns.IsSecret(d) then d = nil end
    if IsInsideQuestBlob and MinimapShown() then
        local inside = IsInsideQuestBlob(qid)
        if not ns.IsSecret(inside) and inside then return true, d or math.huge end
    end
    local r = ns.db.autoTrackYards
    if d and d <= r * r then return true, d end
    return false
end

local function BestNearby(exclude, unfinishedOnly)
    local best, bestPri, bestD
    local function consider(qid)
        if not qid or qid == exclude then return end
        if unfinishedOnly and C_QuestLog.IsComplete(qid) then return end
        local ok, d = InRange(qid)
        if not ok then return end
        local pri = PRIORITY[C_QuestInfoSystem.GetQuestClassification(qid)] and 0 or 1
        if not best or pri < bestPri or (pri == bestPri and d < bestD) then
            best, bestPri, bestD = qid, pri, d
        end
    end
    for i = 1, C_QuestLog.GetNumQuestWatches() or 0 do
        consider(C_QuestLog.GetQuestIDForQuestWatchIndex(i))
    end
    for i = 1, C_QuestLog.GetNumWorldQuestWatches() or 0 do
        consider(C_QuestLog.GetQuestIDForWorldQuestWatchIndex(i))
    end
    return best
end

-- The super-tracked quest and whether it was complete last time we looked:
-- only an incomplete -> complete flip of the same quest triggers rule 2.
local watchID, watchComplete

local function Remember(id)
    watchID = id
    watchComplete = id and C_QuestLog.IsComplete(id) or false
end

local function Track(qid)
    C_SuperTrack.SetSuperTrackedQuestID(qid)
    Remember(qid)
end

-- Rule 2, on quest log changes.
local function CheckCompletion()
    local id = C_SuperTrack.GetSuperTrackedQuestID()
    if not id or id == 0 then
        Remember(nil)
        return
    end
    if id == watchID and not watchComplete and C_QuestLog.IsComplete(id) and Enabled() then
        local next = BestNearby(id, true)
        if next then
            Track(next)
            return
        end
    end
    Remember(id)
end

-- Rule 1, polled: there's no event for walking into range.
local function CheckProximity()
    if not (Enabled() and NothingSuperTracked()) then return end
    local qid = BestNearby(nil, false)
    if qid then Track(qid) end
end

Nocturne.RegisterEvent("QUEST_LOG_UPDATE", CheckCompletion)
Nocturne.RegisterEvent("SUPER_TRACKING_CHANGED", function()
    local id = C_SuperTrack.GetSuperTrackedQuestID()
    Remember(id and id ~= 0 and id or nil)
end)
C_Timer.NewTicker(1, CheckProximity)
