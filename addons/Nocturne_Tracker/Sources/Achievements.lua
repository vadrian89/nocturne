local _, ns = ...

-- Tracked achievements (C_ContentTracking, 10.1+) with their open criteria.

local C = ns.colors
local CT = C_ContentTracking
local TRACK = Enum.ContentTrackingType
local STOP = Enum.ContentTrackingStopType
local ACHIEVEMENT = TRACK and TRACK.Achievement
local GetAchievementInfo = GetAchievementInfo
local GetAchievementNumCriteria = GetAchievementNumCriteria
local GetAchievementCriteriaInfo = GetAchievementCriteriaInfo
local PROGRESS_BAR = _G.EVALUATION_TREE_FLAG_PROGRESS_BAR or 1
local band = bit.band

local LABEL = _G.TRACKER_HEADER_ACHIEVEMENTS or "Achievements"
local MAX_CRITERIA = 6                  -- open criteria listed per achievement

local function Usable(v) return v ~= nil and not ns.IsSecret(v) end

-- Progress-bar criteria ("Loot 1,000 items") show their quantity string.
local function CriteriaText(id, i, fallback)
    local text, _, done, _, _, _, flags, _, quantityString = GetAchievementCriteriaInfo(id, i)
    if ns.Flag(done) or not Usable(text) then return nil end
    if Usable(flags) and band(flags, PROGRESS_BAR) ~= 0 and Usable(quantityString) then
        local label = (text ~= "" and text) or (Usable(fallback) and fallback) or nil
        return label and ("%s %s"):format(label, quantityString) or quantityString
    end
    if text ~= "" then return text end
end

local src = { name = "achievements" }
ns.sources[#ns.sources + 1] = src

function src:Collect(db)
    if not (db.showAchievements and CT and CT.GetTrackedIDs and ACHIEVEMENT) then return end
    local ids = CT.GetTrackedIDs(ACHIEVEMENT)
    if not ids or #ids == 0 then return end

    local s = ns.NewSection(LABEL)
    for _, id in ipairs(ids) do
        local _, name, _, completed, _, _, _, description, _, icon = GetAchievementInfo(id)
        if Usable(name) then
            local e = ns.AddEntry(s)
            e.kind, e.id, e.title, e.texture = "achievement", id, name, icon
            e.titleColor = ns.Flag(completed) and C.done or C.title

            local num = GetAchievementNumCriteria(id) or 0
            if ns.IsSecret(num) then num = 0 end
            if num == 0 then
                if Usable(description) and description ~= "" then ns.AddLine(e, description, C.line) end
            else
                local shown = 0
                for i = 1, num do
                    local text = CriteriaText(id, i, description)
                    if text then
                        shown = shown + 1
                        if shown > MAX_CRITERIA then
                            ns.AddLine(e, "…", C.lineDone)
                            break
                        end
                        ns.AddLine(e, text, C.line)
                    end
                end
            end
        end
    end
end

ns.kinds.achievement = {
    OnClick = function(e, button)
        if button == "RightButton" then
            if CT and CT.StopTracking and STOP then
                CT.StopTracking(ACHIEVEMENT, e.id, STOP.Manual)
            end
        elseif _G.OpenAchievementFrameToAchievement then
            _G.OpenAchievementFrameToAchievement(e.id)
        end
    end,
    hint = "Click: open | Right-click: untrack",
}

ns.RebuildOn({
    "CONTENT_TRACKING_UPDATE",
    "CONTENT_TRACKING_LIST_UPDATE",
    "TRACKED_ACHIEVEMENT_UPDATE",
    "TRACKED_ACHIEVEMENT_LIST_CHANGED",
    "ACHIEVEMENT_EARNED",
})
