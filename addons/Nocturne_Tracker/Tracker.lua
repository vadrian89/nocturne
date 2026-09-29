local _, ns = ...

local Nocturne = _G.Nocturne
local T = Nocturne.Theme

local UnitAffectingCombat = UnitAffectingCombat
local InCombatLockdown = InCombatLockdown
local IsShiftKeyDown = IsShiftKeyDown
local GetQuestLogCompletionText = GetQuestLogCompletionText
local GetQuestObjectiveInfo = GetQuestObjectiveInfo

local PAD = 10                        -- inner padding around the list
local BLOCK_GAP = 10                  -- vertical gap between quests
local CAT_GAP = 6                     -- extra gap before a new category header
local HEADER_GAP = 4                  -- gap under a category header
local ICON_GAP = 4                    -- gap between the quest icon and its title
local LINE_GAP = 1
local WHEEL_STEP = 48                 -- pixels per mouse wheel notch

local DONE = { 0.52, 0.78, 0.55, 1 }  -- soft green for finished quests
local WHITE = { 1, 1, 1, 1 }          -- quest titles
local WHITE_DIM = { 1, 1, 1, 0.80 }   -- objective lines
local WHITE_FAINT = { 1, 1, 1, 0.45 } -- completed objective lines
local EMPTY = {}

ns.fontChoices = {
    { label = "Friz Quadrata", path = "Fonts\\FRIZQT__.TTF" },
    { label = "Arial Narrow",  path = "Fonts\\ARIALN.TTF" },
    { label = "Morpheus",      path = "Fonts\\MORPHEUS.TTF" },
    { label = "Skurri",        path = "Fonts\\SKURRI.TTF" },
}

local order, kindOf, catOf, dailyOf = {}, {}, {}, {} -- scratch, wiped each rebuild
local cats = {}                         -- category names in first-seen watch order
local catQuests = {}                    -- category name -> ordered questID list (reused)
local WQ_LABEL = _G.TRACKER_HEADER_WORLD_QUESTS or "World Quests"
local blocks = {}                       -- Button pool: one per quest (clickable title row)
local lines = {}                        -- FontString pool: headers/objective/completion lines
local scrollOffset = 0
local curFont, curWidth                 -- set by Rebuild for PlaceLine

local function FontPath()
    local c = ns.fontChoices[ns.db.fontFace]
    return c and c.path or ns.fontChoices[1].path
end

local function CollectWatched()
    wipe(order)
    wipe(kindOf)
    wipe(catOf)
    wipe(dailyOf)
    for i = 1, C_QuestLog.GetNumQuestWatches() or 0 do
        local qid = C_QuestLog.GetQuestIDForQuestWatchIndex(i)
        if qid and not kindOf[qid] then
            kindOf[qid] = "quest"
            order[#order + 1] = qid
        end
    end
    for i = 1, C_QuestLog.GetNumWorldQuestWatches() or 0 do
        local qid = C_QuestLog.GetQuestIDForWorldQuestWatchIndex(i)
        if qid and not kindOf[qid] then
            kindOf[qid] = "worldquest"
            order[#order + 1] = qid
        end
    end

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
        if kindOf[qid] == "worldquest" then catOf[qid] = WQ_LABEL end
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

local function GetObjectiveText(qid, o)
    local text = o.text
    if ns.IsSecret(text) then return nil end
    if (not text or text == "") and o.type == "progressbar"
        and C_QuestLog.GetQuestProgressBarPercent then
        local pct = C_QuestLog.GetQuestProgressBarPercent(qid)
        if pct and not ns.IsSecret(pct) then text = ("%d%%"):format(pct) end
    end
    if text ~= "" then return text end
end

local function ClearSuperTrack()
    if C_SuperTrack.ClearAllSuperTracked then
        C_SuperTrack.ClearAllSuperTracked()
    else
        C_SuperTrack.SetSuperTrackedQuestID(0)
    end
end

local function OnBlockClick(self, button)
    local qid = self.questID
    if not qid then return end
    if button == "RightButton" then
        if self.kind == "worldquest" then
            C_QuestLog.RemoveWorldQuestWatch(qid)
        else
            C_QuestLog.RemoveQuestWatch(qid)
        end
    elseif IsShiftKeyDown() and _G.QuestMapFrame_OpenToQuestDetails then
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

local function OnBlockEnter(self)
    if not self.questID then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine(self.title:GetText() or "", 1, 1, 1)
    GameTooltip:AddLine("Click: super-track | Shift-click: details | Right-click: untrack", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

local function ApplyPoint()
    local p = ns.db.point
    ns.frame:ClearAllPoints()
    ns.frame:SetPoint(p[1], UIParent, p[1], p[2], p[3])
end

local function SavePosition()
    local f, p = ns.frame, ns.db.point
    p[1] = "TOPRIGHT"
    p[2] = f:GetRight() - UIParent:GetRight()
    p[3] = f:GetTop() - UIParent:GetTop()
end

local function StartDrag()
    if not ns.db.locked then ns.frame:StartMoving() end
end

local function StopDrag()
    local f = ns.frame
    f:StopMovingOrSizing()
    -- StartMoving marks a named frame user-placed; the client would then
    -- restore it from layout-cache on top of db.point.
    f:SetUserPlaced(false)
    SavePosition()
    -- StopMovingOrSizing re-anchors to whatever point the client picks;
    -- restore TOPRIGHT so later height changes grow downward.
    ApplyPoint()
end

local function NewText(parent)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetJustifyH("LEFT")
    fs:SetShadowColor(0, 0, 0, 0.8)
    fs:SetShadowOffset(1, -1)
    return fs
end

local function AcquireBlock(i)
    local b = blocks[i]
    if not b then
        b = CreateFrame("Button", nil, ns.content)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.title = NewText(b)
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b:RegisterForDrag("LeftButton")
        b:SetScript("OnClick", OnBlockClick)
        b:SetScript("OnEnter", OnBlockEnter)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        b:SetScript("OnDragStart", StartDrag)
        b:SetScript("OnDragStop", StopDrag)
        blocks[i] = b
    end
    return b
end

-- Places pooled line `li` at (x, -y) inside the content; returns its height.
local function PlaceLine(li, x, y, text, size, flags, color)
    local fs = lines[li]
    if not fs then
        fs = NewText(ns.content)
        lines[li] = fs
    end
    fs:SetFont(curFont, size, flags)
    fs:SetWidth(curWidth - x)
    fs:SetText(text)
    fs:SetTextColor(color[1], color[2], color[3], color[4])
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", ns.content, "TOPLEFT", x, -y)
    fs:Show()
    return fs:GetStringHeight()
end

local function ApplyScroll()
    -- The visible height is min(contentH, db.height), so compute the range
    -- directly instead of reading clip geometry mid-layout.
    ns.maxScroll = math.max(0, (ns.contentH or 0) - ns.db.height)
    scrollOffset = math.min(math.max(scrollOffset, 0), ns.maxScroll)
    ns.scrollOffset = scrollOffset
    ns.content:ClearAllPoints()
    ns.content:SetPoint("TOPLEFT", ns.clip, "TOPLEFT", 0, scrollOffset)
    ns.frame:EnableMouseWheel(ns.maxScroll > 0)
end

local function UpdateVisibility()
    local db, f = ns.db, ns.frame
    if not f then return end
    -- While unlocked, keep an empty frame visible so the user can find and
    -- drag it; locked + nothing tracked = fully hidden.
    local show = db.enabled and ((ns.questCount or 0) > 0 or not db.locked)
    if show and db.hideInCombat and UnitAffectingCombat("player") then show = false end
    f:SetShown(show)
end

function ns:Rebuild()
    local f, db = ns.frame, ns.db
    if not f or not db then return end
    if not db.enabled then
        f:Hide()
        return
    end

    CollectWatched()
    ns.questCount = #order

    curFont = FontPath()
    curWidth = db.width - PAD * 2
    local size = db.fontSize
    local iconSize = size + 2
    local indent = iconSize + ICON_GAP -- objectives align with the title text
    local superID = C_SuperTrack.GetSuperTrackedQuestID()
    if not superID or ns.IsSecret(superID) then superID = nil end

    -- Group by quest-log category, preserving first-seen watch order.
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

    local y, bi, li = 0, 0, 0
    for ci, cat in ipairs(cats) do
        if ci > 1 then y = y + CAT_GAP end
        li = li + 1
        y = y + PlaceLine(li, 0, y, cat ~= "" and cat or "Quests",
            math.max(8, size - 1), "OUTLINE", T.colors.textDim) + HEADER_GAP

        for _, qid in ipairs(catQuests[cat]) do
            bi = bi + 1
            local b = AcquireBlock(bi)
            b.questID, b.kind = qid, kindOf[qid]
            local isComplete = b.kind == "quest" and C_QuestLog.IsComplete(qid)
            if ns.IsSecret(isComplete) then isComplete = false end
            local objs = GetObjectives(qid)
            -- Quests without objectives ("talk to X") are complete the moment
            -- they're accepted; only quests whose objectives got done go green.
            local objectivesDone = isComplete and #objs > 0

            local atlas = GetAtlas(qid, isComplete)
            if b.atlas ~= atlas then
                b.atlas = atlas
                if atlas then b.icon:SetAtlas(atlas) end
            end
            b.icon:SetSize(iconSize, iconSize)
            b.icon:ClearAllPoints()
            b.icon:SetPoint("TOPLEFT", 0, (iconSize - size) / 2)
            b.icon:SetShown(atlas ~= nil)

            b.title:SetFont(curFont, size, "")
            b.title:SetWidth(curWidth - indent)
            b.title:ClearAllPoints()
            b.title:SetPoint("TOPLEFT", indent, 0)
            b.title:SetText(GetTitle(qid))
            local tc = (qid == superID and T.colors.accent)
                or (objectivesDone and DONE)
                or WHITE
            b.title:SetTextColor(tc[1], tc[2], tc[3], tc[4])

            local th = math.max(b.title:GetStringHeight(), size)
            b:SetSize(curWidth, th)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", ns.content, "TOPLEFT", 0, -y)
            b:Show()
            y = y + th

            if isComplete then
                li = li + 1
                y = y + LINE_GAP + PlaceLine(li, indent, y + LINE_GAP,
                    GetCompletionText(qid), size - 1, "", objectivesDone and DONE or WHITE_DIM)
            else
                for _, o in ipairs(objs) do
                    local text = GetObjectiveText(qid, o)
                    if text then
                        li = li + 1
                        y = y + LINE_GAP + PlaceLine(li, indent, y + LINE_GAP,
                            text, size - 1, "", o.finished and WHITE_FAINT or WHITE_DIM)
                    end
                end
            end
            y = y + BLOCK_GAP
        end
    end

    for i = bi + 1, #blocks do blocks[i]:Hide() end
    for i = li + 1, #lines do lines[i]:Hide() end

    ns.contentH = math.max(0, y - BLOCK_GAP)
    ns.content:SetSize(curWidth, math.max(ns.contentH, 1))

    -- The visible zone hugs the content: height tracks the list, capped at
    -- the configured max (longer lists scroll). Empty + unlocked keeps a
    -- small box so the frame can still be found and dragged.
    local visibleH = ns.contentH > 0 and math.min(ns.contentH, db.height) or 40
    f:SetSize(db.width, visibleH + PAD * 2)
    ApplyScroll()

    local empty = #order == 0
    if empty then
        local c = T.colors.textDim
        ns.empty:SetFont(curFont, math.max(8, size - 1), "")
        ns.empty:SetText("No tracked quests")
        ns.empty:SetTextColor(c[1], c[2], c[3], c[4])
    end
    ns.empty:SetShown(empty)
    UpdateVisibility()
end

local function OnWheel(_, delta)
    if (ns.maxScroll or 0) <= 0 then return end
    scrollOffset = math.min(math.max(scrollOffset - delta * WHEEL_STEP, 0), ns.maxScroll)
    ApplyScroll()
end

function ns:ApplyLayout()
    local f, db = ns.frame, ns.db
    if not f then return end

    -- Locked = the empty area is click-through; quest rows stay clickable.
    f:EnableMouse(not db.locked)

    ApplyPoint()

    if f.SetBackdropColor then
        local c, b = T.colors.backdrop, T.colors.border
        f:SetBackdropColor(c[1], c[2], c[3], db.bgOpacity)
        f:SetBackdropBorderColor(b[1], b[2], b[3], db.bgOpacity)
    end

    ns:Rebuild()
end

function ns:CreateTrackerFrame()
    local f = CreateFrame("Frame", "NocturneTrackerFrame", UIParent)
    ns.frame = f

    T.ApplyBackdrop(f)
    f:SetFrameStrata("LOW")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", StartDrag)
    f:SetScript("OnDragStop", StopDrag)
    f:SetScript("OnMouseWheel", OnWheel)

    -- clip bounds the scrollable content (SetClipsChildren clips child
    -- frames incl. their regions — same pattern as the compass drum).
    local clip = CreateFrame("Frame", nil, f)
    clip:SetPoint("TOPLEFT", PAD, -PAD)
    clip:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    clip:SetClipsChildren(true)
    ns.clip = clip

    ns.content = CreateFrame("Frame", nil, clip)

    ns.empty = NewText(clip)
    ns.empty:SetPoint("CENTER")
    ns.empty:Hide()

    ns:ApplyLayout()
end

local function WantBlizzardHidden()
    return ns.db.enabled and ns.db.replaceBlizzard
end

-- The objective tracker holds secure children (quest item buttons), so
-- Hide()/Show() on it is blocked in combat: fade it out instead and let
-- PLAYER_REGEN_ENABLED finish the job.
local function BlizzardLocked(f)
    return InCombatLockdown() and f:IsProtected()
end

local function SuppressBlizzard(f)
    ns._otHidden = true
    if BlizzardLocked(f) then
        f:SetAlpha(0)
    else
        f:Hide()
    end
end

-- Blizzard's objective tracker re-shows itself on events and edit mode.
-- OnShow -> Hide is the standard suppression; HookScript can't be removed,
-- so the handler reads the live setting instead of an install-time flag.
-- Only frames we hid are ever re-shown, so Blizzard's own visibility logic
-- (and other addons) are left alone when replacement is off.
function ns:SyncBlizzard()
    local f = _G.ObjectiveTrackerFrame
    if not f or not ns.db then return end
    if not ns._otHooked then
        ns._otHooked = true
        f:HookScript("OnShow", function(s)
            if WantBlizzardHidden() then SuppressBlizzard(s) end
        end)
    end
    if WantBlizzardHidden() then
        SuppressBlizzard(f)
    elseif ns._otHidden and not BlizzardLocked(f) then
        ns._otHidden = false
        f:SetAlpha(1)
        f:Show()
    end
end

function ns:DiagText()
    local ot = _G.ObjectiveTrackerFrame
    local out = {
        ("enabled=%s locked=%s replaceBlizzard=%s font=%d size=%d w=%d h=%d bg=%.2f"):format(
            tostring(ns.db.enabled), tostring(ns.db.locked), tostring(ns.db.replaceBlizzard),
            ns.db.fontFace, ns.db.fontSize, ns.db.width, ns.db.height, ns.db.bgOpacity),
        ("quests=%d contentH=%d scroll=%d/%d shown=%s point=%s,%d,%d"):format(
            ns.questCount or 0, ns.contentH or 0, ns.scrollOffset or 0, ns.maxScroll or 0,
            tostring(ns.frame and ns.frame:IsShown()),
            tostring(ns.db.point[1]), ns.db.point[2] or 0, ns.db.point[3] or 0),
        ("blizzard frame=%s shown=%s alpha=%.2f hiddenByUs=%s protected=%s"):format(
            tostring(ot ~= nil), tostring(ot and ot:IsShown()), ot and ot:GetAlpha() or -1,
            tostring(ns._otHidden), tostring(ot and ot:IsProtected())),
    }
    CollectWatched()
    for i, qid in ipairs(order) do
        local isComplete = kindOf[qid] == "quest" and C_QuestLog.IsComplete(qid)
        if ns.IsSecret(isComplete) then isComplete = false end
        out[#out + 1] = ("%d. %d %s [%s] '%s' complete=%s objectives=%d icon=%s"):format(
            i, qid, kindOf[qid] or "?", catOf[qid] or "?", GetTitle(qid),
            tostring(isComplete), #GetObjectives(qid), tostring(GetAtlas(qid, isComplete)))
    end
    return table.concat(out, "\n")
end

-- Quest events can burst (turn-in fires several in a row); coalesce them
-- into one rebuild per 100ms instead of rebuilding per event.
local rebuildPending = false
local function RequestRebuild()
    if rebuildPending then return end
    rebuildPending = true
    C_Timer.After(0.1, function()
        rebuildPending = false
        ns:Rebuild()
    end)
end

for _, event in ipairs({
    "QUEST_WATCH_LIST_CHANGED",
    "QUEST_WATCH_UPDATE",
    "QUEST_LOG_UPDATE",
    "QUEST_ACCEPTED",
    "QUEST_REMOVED",
    "QUEST_TURNED_IN",
    "QUEST_POI_UPDATE",
    "SUPER_TRACKING_CHANGED",
    "WORLD_QUEST_COMPLETED",
}) do
    Nocturne.RegisterEvent(event, RequestRebuild)
end

Nocturne.RegisterEvent("PLAYER_ENTERING_WORLD", function()
    ns:SyncBlizzard()
    RequestRebuild()
end)
Nocturne.RegisterEvent("PLAYER_REGEN_DISABLED", UpdateVisibility)
Nocturne.RegisterEvent("PLAYER_REGEN_ENABLED", function()
    ns:SyncBlizzard()
    UpdateVisibility()
end)
