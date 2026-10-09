local _, ns = ...

local Nocturne = _G.Nocturne
local T = Nocturne.Theme

local PANEL = ns.JournalPanel
local MARGIN, GAP = ns.JournalMargin, ns.JournalGap

-- Readable on both the parchment atlas and the dark fallback.
local TEXT = { 0.95, 0.95, 0.97, 1 }
local HEADER_COLOR = { 0.80, 0.68, 0.42, 1 }
local DONE_COLOR = { 0.30, 0.75, 0.35, 1 }
local DIM_COLOR = { 0.60, 0.60, 0.65, 1 }

local function IsWatched(qid)
    for i = 1, C_QuestLog.GetNumQuestWatches() or 0 do
        if C_QuestLog.GetQuestIDForQuestWatchIndex(i) == qid then return true end
    end
end

local function SuperID()
    local id = C_SuperTrack.GetSuperTrackedQuestID()
    if id and not ns.IsSecret(id) then return id end
end

local checkAtlas
local function CheckAtlas()
    if checkAtlas == nil then
        checkAtlas = Nocturne.FirstAtlas("common-icon-checkmark", "common-icon-checkmark-yellow") or false
    end
    return checkAtlas or nil
end

local watchAtlas
local function WatchAtlas()
    if watchAtlas == nil then
        watchAtlas = Nocturne.FirstAtlas("common-icon-checkmark-yellow", "common-icon-checkmark") or false
    end
    return watchAtlas or nil
end

local function BuildActiveItems()
    local items = {}
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(i)
        if info then
            if info.isHeader then
                items[#items + 1] = { header = true, title = info.title }
            elseif info.questID then
                items[#items + 1] = {
                    qid = info.questID,
                    logIndex = i,
                    title = info.title,
                    level = info.level,
                    isComplete = ns.Flag(C_QuestLog.IsComplete(info.questID)),
                }
            end
        end
    end
    return items
end

local function BuildCompletedItems()
    local items = {}
    if ns.chardb and #ns.chardb.completed > 0 then
        items[#items + 1] = { header = true, title = "Completed" }
        for _, e in ipairs(ns.chardb.completed) do
            items[#items + 1] = { qid = e.qid, snap = e }
        end
    end
    local hist = ns.HistoricalIDs()
    if #hist > 0 then
        items[#items + 1] = { header = true, title = "Earlier" }
        for _, qid in ipairs(hist) do
            items[#items + 1] = { qid = qid, historical = true }
        end
    end
    return items
end

local function BuildItems(ui)
    return (ui.subIdx or 1) == 1 and BuildActiveItems() or BuildCompletedItems()
end

local function ChainItems(ui, qid, snap)
    local items = {}
    local ids, name
    if snap and snap.lineIDs then
        ids, name = snap.lineIDs, snap.lineName
    else
        local lineID, lineName = ns.QuestChainInfo(qid)
        if lineID then
            name = lineName
            ids = C_QuestLine.GetQuestLineQuests(lineID)
        end
    end
    if name then
        items[#items + 1] = { header = true, title = name }
    elseif ids and #ids == 0 then
        return items
    end
    if ids then
        for _, id in ipairs(ids) do
            local state = "future"
            if ns.Flag(C_QuestLog.IsQuestFlaggedCompleted(id)) then
                state = "done"
            elseif C_QuestLog.GetLogIndexForQuestID(id) then
                state = "active"
            end
            items[#items + 1] = { qid = id, chainState = state }
        end
    elseif not name then
        items[#items + 1] = { header = true, title = "No quest line" }
    end
    return items
end

-- Modern API: GetQuestLogQuestText(logIndex) takes the index directly and
-- SetSelectedQuest/GetSelectedQuest use the questID (not the index).
local function LiveText(qid)
    local GetText = _G.GetQuestLogQuestText
        or (C_QuestLog and C_QuestLog.GetQuestLogQuestText)
    local idx = C_QuestLog.GetLogIndexForQuestID(qid)
    if not (GetText and idx) then return end
    local prev
    if C_QuestLog.SetSelectedQuest then
        prev = C_QuestLog.GetSelectedQuest and C_QuestLog.GetSelectedQuest()
        C_QuestLog.SetSelectedQuest(qid)
    end
    local desc, objText = GetText(idx)
    if prev then C_QuestLog.SetSelectedQuest(prev) end
    if ns.IsSecret(desc) then desc = nil end
    if ns.IsSecret(objText) then objText = nil end
    return desc, objText
end

ns.RegisterPage(2, {
    key = "quests",
    title = "Quests",
    subPages = function() return { "Active", "Completed" } end,
    ownSubBar = true,
    OnSubPage = function(f, i)
        local ui = ns.questUI
        if not ui then return end
        ui.subIdx = i
        ui.selected = nil
        for j, b in ipairs(ui.subTabs) do
            local on = j == i
            local c = on and HEADER_COLOR or T.colors.text
            b.label:SetTextColor(c[1], c[2], c[3])
            b.line:SetShown(on)
        end
        ns:QuestsRefresh()
    end,
    Build = function(f)
        local ui = {}
        ns.questUI = ui

        local left = PANEL(f, "quests", "QuestBG-Parchment")
        ui.left = left
        left:SetPoint("TOPLEFT", MARGIN, -MARGIN)
        left:SetPoint("BOTTOMLEFT", MARGIN, MARGIN)
        local right = PANEL(f, "quests", "QuestBG-Parchment")
        right:SetPoint("TOPRIGHT", -MARGIN, -MARGIN)
        right:SetPoint("BOTTOMRIGHT", -MARGIN, MARGIN)
        right:SetPoint("LEFT", left, "RIGHT", GAP, 0)

        -- Sub-tabs over the list, shrink-wrapped and centered:
        -- [LT] Active  Completed [RT]
        local subBar = CreateFrame("Frame", nil, left)
        subBar:SetPoint("TOP", left, "TOP", 0, -20)
        subBar:SetHeight(36)

        local lt = T.CreateFontString(subBar, 20, T.colors.textDim)
        lt:SetText(ns.PadGlyph("PADLTRIGGER", "LT"))
        local rt = T.CreateFontString(subBar, 20, T.colors.textDim)
        rt:SetText(ns.PadGlyph("PADRTRIGGER", "RT"))

        ui.subTabs = {}
        local parts = { lt }
        for i, name in ipairs({ "Active", "Completed" }) do
            local b = CreateFrame("Button", nil, subBar)
            b:SetHeight(36)
            b.label = T.CreateFontString(b, 26)
            b.label:SetPoint("CENTER")
            b.label:SetText(name)
            b:SetWidth(b.label:GetStringWidth() + 8)
            b.line = b:CreateTexture(nil, "OVERLAY")
            b.line:SetPoint("BOTTOMLEFT", 4, 3)
            b.line:SetPoint("BOTTOMRIGHT", -4, 3)
            b.line:SetHeight(2)
            local a = T.colors.accent
            b.line:SetColorTexture(a[1], a[2], a[3], 1)
            b:SetScript("OnClick", function() ns:SetSubPage(i) end)
            ui.subTabs[i] = b
            parts[#parts + 1] = b
        end
        parts[#parts + 1] = rt

        local function Width(p)
            return p.GetStringWidth and p:GetStringWidth() or p:GetWidth()
        end
        local GAPX = 18
        local total = 0
        for _, p in ipairs(parts) do total = total + Width(p) end
        total = total + GAPX * (#parts - 1)
        -- A zero-size frame can leave its children unrendered; give the
        -- switcher its real rect.
        subBar:SetSize(math.ceil(total), 36)
        subBar:SetFrameLevel(left:GetFrameLevel() + 5)
        local x = -total / 2
        for _, p in ipairs(parts) do
            p:ClearAllPoints()
            p:SetPoint("LEFT", subBar, "CENTER", x, 0)
            x = x + Width(p) + GAPX
        end

        -- Right side: scrollable centered text on top, chain list at bottom.
        local chainPanel = PANEL(f, "quests", "QuestBG-Parchment")
        chainPanel:SetPoint("BOTTOMLEFT", right, "BOTTOMLEFT")
        chainPanel:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT")
        local textPanel = CreateFrame("Frame", nil, right)
        ui.textPanel = textPanel
        textPanel:SetPoint("TOPLEFT")
        textPanel:SetPoint("TOPRIGHT")
        textPanel:SetPoint("BOTTOM", chainPanel, "TOP")

        -- Actions shared by the on-screen buttons and the pad buttons.
        -- Quests that are complete (ready to turn in) can't be tracked.
        local function Trackable(item)
            return item and item.logIndex and not item.isComplete
        end
        local function ToggleTrack()
            local item = ui.selected
            if not Trackable(item) then return end
            if IsWatched(item.qid) then
                C_QuestLog.RemoveQuestWatch(item.qid)
            else
                C_QuestLog.AddQuestWatch(item.qid)
            end
            ns:QuestsRefresh()
        end
        local function Abandon()
            local item = ui.selected
            if not item or not item.logIndex then return end
            local qid, title = item.qid, item.title
            ns:ShowConfirm(("Abandon quest \"%s\"?"):format(title or "?"),
                "Abandon", function()
                    -- SetAbandonQuest takes no argument: it targets the
                    -- selected quest. Blizzard's own flow selects first.
                    local prev = C_QuestLog.GetSelectedQuest
                        and C_QuestLog.GetSelectedQuest()
                    C_QuestLog.SetSelectedQuest(qid)
                    C_QuestLog.SetAbandonQuest()
                    C_QuestLog.AbandonQuest()
                    if prev then C_QuestLog.SetSelectedQuest(prev) end
                end)
        end
        local function ToggleSuper()
            local item = ui.selected
            if not Trackable(item) then return end
            if SuperID() == item.qid then
                if C_SuperTrack.ClearAllSuperTracked then
                    C_SuperTrack.ClearAllSuperTracked()
                else
                    C_SuperTrack.SetSuperTrackedQuestID(0)
                end
            else
                C_SuperTrack.SetSuperTrackedQuestID(item.qid)
            end
            ns:QuestsRefresh()
        end
        ns.questActions = { track = ToggleTrack, abandon = Abandon, super = ToggleSuper }

        -- D-pad moves the selection through non-header rows.
        local function MoveSelection(dir)
            local items = ui.list.items
            if #items == 0 then return end
            local idx = ui.selected and ui.list:IndexOf(ui.selected)
            if not idx then idx = dir > 0 and 0 or (#items + 1) end
            for _ = 1, #items do
                idx = idx + dir
                if idx < 1 then idx = #items elseif idx > #items then idx = 1 end
                if not items[idx].header then break end
            end
            if items[idx].header then return end
            ui.selected = items[idx]
            ui.list:RevealIndex(idx)
            ns:QuestShowDetail()
            ui.list:Refresh()
        end
        ns.moveSelection = MoveSelection

        -- Pad legend, bottom-right: [X] action  [Y] action  [A] action.
        local legend = CreateFrame("Frame", nil, f)
        legend:SetPoint("BOTTOMRIGHT", -MARGIN, MARGIN)
        legend:SetSize(600, 30)
        local function LegendEntry(pad, prev)
            local label = T.CreateFontString(legend, 15, T.colors.text)
            local glyph = T.CreateFontString(legend, 15, T.colors.accent)
            glyph:SetText(ns.PadGlyph(pad, pad))
            if prev then
                label:SetPoint("RIGHT", prev.glyph, "LEFT", -26, 0)
            else
                label:SetPoint("BOTTOMRIGHT", legend, "BOTTOMRIGHT")
            end
            glyph:SetPoint("RIGHT", label, "LEFT", -6, 0)
            return { label = label, glyph = glyph }
        end
        ui.legendA = LegendEntry("PAD1")
        ui.legendY = LegendEntry("PAD4", ui.legendA)
        ui.legendX = LegendEntry("PAD3", ui.legendY)
        -- D-Pad: real pad glyphs when the client renders them as icons,
        -- else a text fallback.
        local nav = T.CreateFontString(legend, 15, T.colors.text)
        local up = ns.PadGlyph("PADDUP")
        local down = ns.PadGlyph("PADDDOWN")
        local dpad = (up and up:find("|") and down and down:find("|"))
            and (up .. down) or "D-Pad"
        nav:SetText(dpad .. "  Navigate")
        nav:SetPoint("RIGHT", ui.legendX.glyph, "LEFT", -26, 0)

        ui.list = ns.NewList(left, {
            rowHeight = 34,
            initRow = function(row)
                ns.NewListRow(row, true)
                row.sel = row:CreateTexture(nil, "BACKGROUND")
                row.sel:SetAllPoints()
                local a = T.colors.accent
                row.sel:SetColorTexture(a[1], a[2], a[3], 0.35)
                row.sel:Hide()
                row.mark = row:CreateTexture(nil, "OVERLAY")
                row.mark:SetPoint("RIGHT", -6, 0)
            end,
            setRow = function(row, item)
                row.sel:SetShown(ui.selected == item)
                if item.header then
                    row.icon:SetTexture(nil)
                    row.mark:SetTexture(nil)
                    row.label:SetFont(T.fonts.main, 26, "")
                    row.label:SetText(item.title)
                    row.label:SetTextColor(HEADER_COLOR[1], HEADER_COLOR[2], HEADER_COLOR[3])
                    return
                end
                row.label:SetFont(T.fonts.main, 20, "")
                local qid = item.qid
                local done = item.snap or item.historical
                local title = item.title or (item.snap and item.snap.title)
                    or ns.QuestTitle(qid) or ("Quest " .. qid)
                row.label:SetText((item.level and item.level > 0) and ("[%d] %s"):format(item.level, title) or title)
                if done then
                    local atlas = CheckAtlas()
                    if atlas then row.icon:SetAtlas(atlas) else row.icon:SetTexture(nil) end
                    row.label:SetTextColor(DONE_COLOR[1], DONE_COLOR[2], DONE_COLOR[3])
                else
                    local atlas = Nocturne.QuestAtlas(nil, ns.Flag(item.isComplete), false, false)
                    if atlas then row.icon:SetAtlas(atlas) else row.icon:SetTexture(nil) end
                    row.label:SetTextColor(TEXT[1], TEXT[2], TEXT[3])
                end
                -- Right edge: gold diamond for super-tracked, gold check for
                -- watched, nothing for the rest.
                local a = T.colors.accent
                if item.logIndex and not done and SuperID() == qid then
                    row.mark:SetSize(11, 11)
                    row.mark:SetTexture("Interface\\Buttons\\WHITE8x8",
                        "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
                    row.mark:SetVertexColor(a[1], a[2], a[3], 1)
                    row.mark:SetRotation(math.rad(45))
                elseif item.logIndex and not done and IsWatched(qid) then
                    local atlas = WatchAtlas()
                    if atlas then
                        row.mark:SetSize(20, 20)
                        row.mark:SetRotation(0)
                        row.mark:SetAtlas(atlas)
                        row.mark:SetVertexColor(1, 1, 1, 1)
                    else
                        row.mark:SetTexture(nil)
                    end
                else
                    row.mark:SetTexture(nil)
                end
            end,
            onClick = function(item)
                if item.header then return end
                ui.selected = item
                ns:QuestShowDetail()
                ui.list:Refresh()
            end,
        })
        ui.list.frame:SetPoint("TOPLEFT", 8, -76)
        ui.list.frame:SetPoint("BOTTOMRIGHT", -4, 8)

        -- Centered quest text, vertically scrollable.
        local scroll = CreateFrame("ScrollFrame", nil, textPanel)
        ui.scroll = scroll
        scroll:SetPoint("TOPLEFT", 48, -48)
        scroll:SetPoint("BOTTOMRIGHT", -48, 48)
        scroll:EnableMouseWheel(true)
        scroll:SetScript("OnMouseWheel", function(self, delta)
            local max = math.max(0, self:GetVerticalScrollRange())
            self:SetVerticalScroll(math.min(max, math.max(0, self:GetVerticalScroll() - delta * 30)))
        end)
        local child = CreateFrame("Frame", nil, scroll)
        scroll:SetScrollChild(child)
        ui.child = child

        local function Text(fs)
            fs:SetFont(T.fonts.main, 20, "")
            fs:SetTextColor(TEXT[1], TEXT[2], TEXT[3], 1)
            fs:SetJustifyH("CENTER")
            fs:SetJustifyV("TOP")
            fs:SetWordWrap(true)
            return fs
        end
        ui.title = child:CreateFontString(nil, "OVERLAY")
        ui.title:SetFont(T.fonts.main, 34, "")
        ui.title:SetTextColor(HEADER_COLOR[1], HEADER_COLOR[2], HEADER_COLOR[3], 1)
        ui.title:SetJustifyH("CENTER")
        ui.title:SetWordWrap(true)
        ui.desc = Text(child:CreateFontString(nil, "OVERLAY"))
        ui.objs = Text(child:CreateFontString(nil, "OVERLAY"))
        ui.done = Text(child:CreateFontString(nil, "OVERLAY"))
        ui.done:SetTextColor(DONE_COLOR[1], DONE_COLOR[2], DONE_COLOR[3], 1)

        ui.title:SetPoint("TOPLEFT")
        ui.title:SetPoint("TOPRIGHT")
        ui.desc:SetPoint("TOPLEFT", ui.title, "BOTTOMLEFT", 0, -26)
        ui.desc:SetPoint("TOPRIGHT", ui.title, "BOTTOMRIGHT", 0, -26)
        ui.objs:SetPoint("TOPLEFT", ui.desc, "BOTTOMLEFT", 0, -12)
        ui.objs:SetPoint("TOPRIGHT", ui.desc, "BOTTOMRIGHT", 0, -12)
        ui.done:SetPoint("TOPLEFT", ui.objs, "BOTTOMLEFT", 0, -12)
        ui.done:SetPoint("TOPRIGHT", ui.objs, "BOTTOMRIGHT", 0, -12)

        ui.chain = ns.NewList(chainPanel, {
            rowHeight = 30,
            initRow = function(row) ns.NewListRow(row, true, 14) end,
            setRow = function(row, item)
                if item.header then
                    row.icon:SetTexture(nil)
                    row.label:SetFont(T.fonts.main, 14, "OUTLINE")
                    row.label:SetText(item.title)
                    row.label:SetTextColor(HEADER_COLOR[1], HEADER_COLOR[2], HEADER_COLOR[3])
                    return
                end
                row.label:SetFont(T.fonts.main, 14, "")
                row.label:SetText(ns.QuestTitle(item.qid) or ("Quest " .. item.qid))
                local c = item.chainState == "done" and DONE_COLOR
                    or item.chainState == "active" and T.colors.accent or DIM_COLOR
                row.label:SetTextColor(c[1], c[2], c[3])
                if item.chainState == "done" then
                    local atlas = Nocturne.FirstAtlas("common-icon-checkmark", "common-icon-checkmark-yellow")
                    if atlas then row.icon:SetAtlas(atlas) else row.icon:SetTexture(nil) end
                elseif item.chainState == "active" then
                    local atlas = Nocturne.FirstAtlas("common-icon-indicator", "QuestNormal")
                    if atlas then row.icon:SetAtlas(atlas) else row.icon:SetTexture(nil) end
                else
                    row.icon:SetTexture(nil)
                end
            end,
            onClick = function(item)
                if item.header then return end
                local items = ui.list.items
                for _, it in ipairs(items) do
                    if it.qid == item.qid then
                        ui.selected = it
                        ns:QuestShowDetail()
                        ui.list:Refresh()
                        return
                    end
                end
                -- Not in the lists (e.g. future chain step): show title only.
                ui.selected = { qid = item.qid, chainOnly = true }
                ns:QuestShowDetail()
                ui.list:Refresh()
            end,
        })
        ui.chain.frame:SetPoint("TOPLEFT", 8, -8)
        ui.chain.frame:SetPoint("BOTTOMRIGHT", -4, 8)

        local function Layout()
            left:SetWidth(math.floor(f:GetWidth() * 0.32) - GAP)
            chainPanel:SetHeight(math.floor(f:GetHeight() * 0.30))
            local w = math.max(10, scroll:GetWidth())
            child:SetWidth(w)
            ns:QuestShowDetail()
        end
        Layout()
        f:SetScript("OnSizeChanged", Layout)

        ns.questListDirty = true
    end,
    OnPad = function(f, button)
        if button == "PADDUP" then
            if ns.moveSelection then ns.moveSelection(-1) end
            return
        elseif button == "PADDDOWN" then
            if ns.moveSelection then ns.moveSelection(1) end
            return
        end
        local a = ns.questActions
        if not a then return end
        if button == "PAD3" then
            a.track()
        elseif button == "PAD4" then
            a.abandon()
        elseif button == "PAD1" then
            a.super()
        end
    end,
    OnShow = function()
        ns:QuestsRefresh()
    end,
    OnHide = function()
        if ns.questUI then ns.questUI.selected = nil end
    end,
})

local function UpdateButtons(ui)
    local item = ui.selected
    local live = item and item.logIndex and not item.snap and not item.historical and not item.chainOnly
    local trackable = live and not item.isComplete
    local watched = live and IsWatched(item.qid)
    ui.legendX.label:SetText(watched and "Untrack" or "Track")
    ui.legendY.label:SetText("Abandon")
    ui.legendA.label:SetText(trackable and SuperID() == item.qid and "Remove active" or "Set as active")
end

function ns:QuestShowDetail()
    local ui = ns.questUI
    if not ui then return end
    local item = ui.selected
    UpdateButtons(ui)
    if not item then
        ui.title:SetText("")
        ui.desc:SetText("")
        ui.objs:SetText("")
        ui.done:SetText("")
        ui.chain:SetItems({})
        ui.child:SetHeight(1)
        return
    end

    local qid = item.qid
    local snap = item.snap or (ns.chardb and ns.chardb.pending[qid])
    ui.title:SetText(item.title or (snap and snap.title) or ns.QuestTitle(qid) or ("Quest " .. qid))

    local desc, objText
    if snap then
        desc, objText = snap.desc, snap.objText
    else
        desc, objText = LiveText(qid)
    end
    ui.desc:SetText(desc or "")
    if ui.desc:GetText() == "" and not snap then
        ui.desc:SetText(objText or "")
        objText = nil
    end

    local lines = {}
    if objText and objText ~= "" then
        lines[#lines + 1] = objText
    end
    local objs = snap and snap.objs
    if not objs then
        objs = {}
        for _, o in ipairs(C_QuestLog.GetQuestObjectives(qid) or {}) do
            if o.text and not ns.IsSecret(o.text) then
                objs[#objs + 1] = (ns.Flag(o.finished) and "- " or "o ") .. o.text
            end
        end
    else
        local prefixed = {}
        for _, t in ipairs(objs) do prefixed[#prefixed + 1] = "- " .. t end
        objs = prefixed
    end
    for _, t in ipairs(objs) do lines[#lines + 1] = t end
    ui.objs:SetText(table.concat(lines, "\n\n"))

    local isComplete = item.snap or item.historical
        or (not item.chainOnly and ns.Flag(C_QuestLog.IsComplete(qid)))
    ui.done:SetText(isComplete and (_G.QUEST_COMPLETE or "Quest completed") or "")

    ui.child:SetHeight(math.max(1,
        ui.title:GetStringHeight() + ui.desc:GetStringHeight()
        + ui.objs:GetStringHeight() + ui.done:GetStringHeight() + 60))

    ui.chain:SetItems(ChainItems(ui, qid, snap))
end

function ns:QuestsRefresh()
    local ui = ns.questUI
    if not ui then return end
    if not (ns.pageFrames[2] and ns.pageFrames[2]:IsShown()) then
        ns.questListDirty = true
        return
    end
    ns.questListDirty = false
    ui.list:SetItems(BuildItems(ui))
    -- Re-resolve the selection's entry (items are rebuilt tables); if the
    -- quest left the log (e.g. just abandoned), clear the selection.
    if ui.selected then
        local found
        for _, it in ipairs(ui.list.items) do
            if it.qid == ui.selected.qid then
                ui.selected = it
                found = true
                break
            end
        end
        if not found then ui.selected = nil end
    end
    ns:QuestShowDetail()
end

local function Dirty()
    ns.questListDirty = true
    ns:QuestsRefresh()
end

for _, event in ipairs({
    "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED",
    "QUEST_WATCH_LIST_CHANGED", "QUEST_WATCH_UPDATE", "QUEST_POI_UPDATE",
    "QUESTLINE_UPDATE", "ZONE_CHANGED_NEW_AREA", "SUPER_TRACKING_CHANGED",
}) do
    _G.Nocturne.RegisterEvent(event, Dirty)
end
