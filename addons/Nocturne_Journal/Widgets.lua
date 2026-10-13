local _, ns = ...

local Nocturne = _G.Nocturne
local T = Nocturne.Theme

-- Enlarged tooltips (Inventory items, Abilities spells); the comparison
-- tooltips for an equipped counterpart follow the same scale.
ns.TIP_SCALE = 1.6
function ns.SetTipScale(scale)
    GameTooltip:SetScale(scale)
    for i = 1, 2 do
        local st = _G["ShoppingTooltip" .. i]
        if st then st:SetScale(scale) end
    end
end

-- Thumb sized like the native ones: proportional to the visible fraction
-- of the content, floored so it never shrinks to nothing.
function ns.FitScrollThumb(bar, viewport, range)
    local track = bar:GetHeight()
    if track <= 0 then return end
    local total = (viewport or 0) + math.max(0, range or 0)
    local frac = total > 0 and (viewport / total) or 1
    bar.knobH = math.max(24, track * frac)
end

-- Plain vertical slider with a flat track and thumb. The stock scrollbar
-- template's art (capped track, knob margins, buttons outside the slider
-- bounds) can't be fitted flush to the scroll area.
function ns.NewScrollBar(parent)
    local bar = CreateFrame("Slider", nil, parent)
    bar:SetOrientation("VERTICAL")
    bar:SetWidth(8)
    bar:SetFrameLevel(parent:GetFrameLevel() + 20)
    bar:EnableMouse(true)
    local track = bar:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    track:SetColorTexture(0, 0, 0, 0.3)
    local a = T.colors.accent
    -- The slider's own thumb is never laid out on this client (its rect
    -- stays nil), so it is kept invisible and a knob is anchored by hand.
    local thumb = bar:CreateTexture(nil, "ARTWORK")
    thumb:SetColorTexture(0, 0, 0, 0)
    thumb:SetSize(8, 24)
    bar:SetThumbTexture(thumb)
    local knob = bar:CreateTexture(nil, "OVERLAY")
    knob:SetColorTexture(a[1], a[2], a[3], 0.9)
    knob:SetWidth(8)
    knob:SetHeight(24)
    bar.knobH = 24
    local dragging, key
    bar:SetScript("OnMouseDown", function() dragging = true end)
    bar:SetScript("OnMouseUp", function() dragging = false end)
    bar:SetScript("OnUpdate", function(self)
        local lo, hi = self:GetMinMaxValues()
        local h = self:GetHeight()
        local kh = math.min(self.knobH, h)
        local travel = math.max(1, h - kh)
        if dragging then
            local _, cy = GetCursorPosition()
            local top = self:GetTop()
            if top then
                local f = math.min(1, math.max(0,
                    (top - cy / self:GetEffectiveScale() - kh / 2) / travel))
                self:SetValue(lo + f * (hi - lo))
            end
        end
        local v = self:GetValue()
        local k = v .. ":" .. lo .. ":" .. hi .. ":" .. h .. ":" .. kh
        if k == key then return end
        key = k
        local f = hi > lo and (v - lo) / (hi - lo) or 0
        knob:ClearAllPoints()
        knob:SetPoint("TOP", self, "TOP", 0, -f * travel)
        knob:SetHeight(kh)
    end)
    return bar
end

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

    local bar = ns.NewScrollBar(frame)
    bar:SetPoint("TOPRIGHT")
    bar:SetPoint("BOTTOMRIGHT")
    bar:SetValueStep(rowH)
    bar:SetObeyStepOnDrag(false)
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
        bar:SetShown(max > 0)
        ns.FitScrollThumb(bar, frame:GetHeight(), max)
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

-- Held D-pad key repeat with a gentle speed ramp: the interval eases from
-- 0.22s down to a 0.11s floor over ~1.4s. Shared by every page — call
-- `hold[button] = { t = 0, acc = 0 }` on press, `hold[button] = nil` on up.
function ns.DpadHoldFrame(frame, onTick)
    local hold = {}
    frame:SetScript("OnUpdate", function(_, dt)
        for button, st in pairs(hold) do
            st.t = st.t + dt
            st.acc = st.acc + dt
            local iv = math.max(0.11, 0.22 - st.t * 0.08)
            if st.acc >= iv then
                st.acc = 0
                onTick(button)
            end
        end
    end)
    return hold
end

-- Directional nearest pick for free-form graphs (talent trees): of the
-- nodes in the direction's half-plane, the winner minimizes perpendicular
-- offset with a light distance term — same family as the inventory nav.
function ns.NavNearest(nodes, cur, dx, dy)
    local c = cur
    if not c then return end
    local best, bs
    for _, n in ipairs(nodes) do
        if n ~= c then
            local fwd = (n.x - c.x) * dx + (n.y - c.y) * dy
            if fwd > 0.0001 then
                local perp = math.abs((n.x - c.x) * dy - (n.y - c.y) * dx)
                local score = perp * 4 + fwd * 0.02
                if not bs or score < bs then best, bs = n, score end
            end
        end
    end
    return best
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

-- Page-owned sub-tab row, shrink-wrapped and centered on its own frame:
-- [LT] name  name [RT]. Pages that set ownSubBar build one, anchor it
-- and repaint it from OnSubPage.
local SUBTAB_H, SUBTAB_GAPX = 36, 18

function ns.LayoutSubTabRow(bar)
    local parts = { bar.lt }
    for _, b in ipairs(bar.tabs) do
        b:SetWidth(b.label:GetStringWidth() + 8)
        parts[#parts + 1] = b
    end
    parts[#parts + 1] = bar.rt
    local function Width(p)
        return p.GetStringWidth and p:GetStringWidth() or p:GetWidth()
    end
    local total = 0
    for _, p in ipairs(parts) do total = total + Width(p) end
    total = total + SUBTAB_GAPX * (#parts - 1)
    -- A zero-size frame can leave its children unrendered; give the
    -- switcher its real rect.
    bar:SetSize(math.ceil(total), SUBTAB_H)
    local x = -total / 2
    for _, p in ipairs(parts) do
        p:ClearAllPoints()
        p:SetPoint("LEFT", bar, "CENTER", x, 0)
        x = x + Width(p) + SUBTAB_GAPX
    end
end

function ns.NewSubTabRow(parent, names)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetHeight(SUBTAB_H)
    bar.lt = T.CreateFontString(bar, 20, T.colors.textDim)
    bar.lt:SetText(ns.PadGlyph("PADLTRIGGER", "LT"))
    bar.rt = T.CreateFontString(bar, 20, T.colors.textDim)
    bar.rt:SetText(ns.PadGlyph("PADRTRIGGER", "RT"))
    bar.tabs = {}
    for i, name in ipairs(names) do
        local b = CreateFrame("Button", nil, bar)
        b:SetHeight(SUBTAB_H)
        b.label = T.CreateFontString(b, 26)
        b.label:SetPoint("CENTER")
        b.label:SetText(name)
        b.line = b:CreateTexture(nil, "OVERLAY")
        b.line:SetPoint("BOTTOMLEFT", 4, 3)
        b.line:SetPoint("BOTTOMRIGHT", -4, 3)
        b.line:SetHeight(2)
        local a = T.colors.accent
        b.line:SetColorTexture(a[1], a[2], a[3], 1)
        b:SetScript("OnClick", function() ns:SetSubPage(i) end)
        bar.tabs[i] = b
    end
    ns.LayoutSubTabRow(bar)
    return bar
end

-- offColor per tab (optional) lets a page dim unavailable tabs.
function ns.PaintSubTabRow(bar, current, offColors)
    for j, b in ipairs(bar.tabs) do
        local on = j == current
        local c = on and T.colors.accent
            or (offColors and offColors[j]) or T.colors.text
        b.label:SetTextColor(c[1], c[2], c[3])
        b.line:SetShown(on)
    end
end
