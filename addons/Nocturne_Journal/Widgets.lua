local _, ns = ...

local Nocturne = _G.Nocturne
local T = Nocturne.Theme

-- Virtualized scroll list: a fixed pool of rows recycled over a data array,
-- mouse wheel + draggable thumb. `initRow(row)` runs once per pooled row,
-- `setRow(row, item)` on every relayout; `row.item` holds the bound item.
function ns.NewList(parent, o)
    local rowH = o.rowHeight or 22
    local list = { items = {}, offset = 0, rows = {} }

    local frame = CreateFrame("Frame", nil, parent)
    frame:EnableMouseWheel(true)
    frame:SetClipsChildren(true)
    list.frame = frame

    local bar = CreateFrame("Slider", nil, frame)
    bar:SetOrientation("VERTICAL")
    bar:SetWidth(8)
    bar:SetPoint("TOPRIGHT")
    bar:SetPoint("BOTTOMRIGHT")
    bar:SetValueStep(1)
    bar:SetObeyStepOnDrag(false)
    bar.track = bar:CreateTexture(nil, "BACKGROUND")
    bar.track:SetAllPoints()
    bar.track:SetColorTexture(0.5, 0.5, 0.6, 0.15)
    bar.thumb = bar:CreateTexture(nil, "OVERLAY")
    bar.thumb:SetWidth(8)
    bar.thumb:SetColorTexture(0.6, 0.62, 0.72, 0.6)
    bar:SetThumbTexture(bar.thumb)
    list.bar = bar

    local function maxOffset()
        return math.max(0, #list.items * rowH - frame:GetHeight())
    end

    local function EnsureRows()
        local need = math.floor(frame:GetHeight() / rowH) + 2
        while #list.rows < need do
            local row = CreateFrame("Button", nil, frame)
            row:SetHeight(rowH)
            if o.onClick then
                row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
                row:SetScript("OnClick", function(self, button)
                    if self.item then o.onClick(self.item, button) end
                end)
            end
            o.initRow(row)
            list.rows[#list.rows + 1] = row
        end
    end

    function list:Refresh()
        if frame:GetHeight() <= 0 then return end
        EnsureRows()
        local first = math.floor(self.offset / rowH) + 1
        local y0 = self.offset % rowH
        for i, row in ipairs(self.rows) do
            local idx = first + i - 1
            local item = self.items[idx]
            row.item = item
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -((i - 1) * rowH - y0))
            row:SetPoint("RIGHT", bar, "LEFT", -4, 0)
            if item then
                row:Show()
                o.setRow(row, item)
            else
                row:Hide()
            end
        end
        local max = maxOffset()
        bar:SetMinMaxValues(0, math.max(1, max))
        bar:SetValue(self.offset)
        local vh = frame:GetHeight()
        bar.thumb:SetHeight(math.max(18, vh * math.min(1, vh / math.max(1, #self.items * rowH))))
        bar:SetShown(max > 0)
    end

    function list:SetOffset(off)
        self.offset = math.min(math.max(0, off), maxOffset())
        self:Refresh()
    end

    function list:SetItems(items)
        self.items = items or {}
        self:SetOffset(self.offset)
    end

    -- Scrolls just enough to make item `idx` visible (no-op if it is).
    function list:RevealIndex(idx)
        if not idx then return end
        local top = (idx - 1) * rowH
        local bottom = top + rowH
        local vh = frame:GetHeight()
        if top < self.offset then
            self:SetOffset(top)
        elseif bottom > self.offset + vh then
            self:SetOffset(bottom - vh)
        end
    end

    function list:IndexOf(item)
        for i, it in ipairs(self.items) do
            if it == item or (item.qid and it.qid == item.qid) then return i end
        end
    end

    frame:SetScript("OnMouseWheel", function(_, delta)
        list:SetOffset(list.offset - delta * rowH * 3)
    end)
    frame:SetScript("OnSizeChanged", function() list:Refresh() end)
    bar:SetScript("OnValueChanged", function(_, value)
        if math.abs(value - list.offset) > 0.5 then
            list.offset = value
            list:Refresh()
        end
    end)

    return list
end

-- Row for a quest/chain entry: 14px atlas icon + text. Color is picked by
-- the setter via row.label:SetTextColor.
function ns.NewListRow(listRow, darkText, fontSize)
    listRow.icon = listRow:CreateTexture(nil, "ARTWORK")
    listRow.icon:SetSize(18, 18)
    listRow.icon:SetPoint("LEFT", 4, 0)
    listRow.label = listRow:CreateFontString(nil, "ARTWORK")
    local c = darkText and ns.JournalParchmentText or T.colors.text
    listRow.label:SetFont(T.fonts.main, fontSize or 14, "")
    listRow.label:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    listRow.label:SetPoint("LEFT", listRow.icon, "RIGHT", 8, 0)
    listRow.label:SetPoint("RIGHT", -4, 0)
    listRow.label:SetJustifyH("LEFT")
    listRow.label:SetWordWrap(false)
    listRow:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
end
