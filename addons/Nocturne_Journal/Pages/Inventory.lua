local _, ns = ...

local Nocturne = _G.Nocturne
local T = Nocturne.Theme

local PANEL = ns.JournalPanel
local MARGIN, GAP = ns.JournalMargin, ns.JournalGap

local CELL, CELL_GAP = 44, 6
local HEADER_H = 30
local PAD = 40

local UpdateLegend, SyncUseButton

local TEXT = { 0.95, 0.95, 0.97, 1 }
local HEADER_COLOR = { 0.80, 0.68, 0.42, 1 }
local DIM_COLOR = { 0.60, 0.60, 0.65, 1 }

-- Backpack..4 equipable bags; the reagent bag rides along when present.
local function BagIDs()
    local n = _G.NUM_BAG_SLOTS or 4
    local ids = {}
    for i = 0, n do ids[#ids + 1] = i end
    local rb = Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag
    if rb and C_Container.GetContainerNumSlots
        and C_Container.GetContainerNumSlots(rb) > 0 then
        ids[#ids + 1] = rb
    end
    return ids
end

local function CombinedBags()
    return GetCVarBool and GetCVarBool("combinedBags")
end

local function ItemInfo(bag, slot)
    if not (C_Container and C_Container.GetContainerItemInfo) then return end
    local info = C_Container.GetContainerItemInfo(bag, slot)
    -- Empty slots return a table with no icon on modern clients.
    if info and info.iconFileID then return info end
end

local function NewCell(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(CELL, CELL)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.bg:SetColorTexture(0, 0, 0, 0.4)
    b.q = b:CreateTexture(nil, "BACKGROUND", nil, 1)
    b.q:SetPoint("TOPLEFT", -2, 2)
    b.q:SetPoint("BOTTOMRIGHT", 2, -2)
    b.q:Hide()
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.count:SetPoint("BOTTOMRIGHT", -2, 1)
    b.sel = b:CreateTexture(nil, "OVERLAY")
    b.sel:SetPoint("TOPLEFT", -3, 3)
    b.sel:SetPoint("BOTTOMRIGHT", 3, -3)
    local a = T.colors.accent
    b.sel:SetColorTexture(a[1], a[2], a[3], 0.35)
    b.sel:Hide()
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    return b
end

local function QualityBorder(b, quality)
    if quality and quality > 1 then
        local r, g, bl
        if C_Item and C_Item.GetItemQualityColor then
            r, g, bl = C_Item.GetItemQualityColor(quality)
        end
        if r then
            b.q:SetColorTexture(r, g, bl, 1)
            b.q:Show()
            return
        end
    end
    b.q:Hide()
end

-- One pooled fontstring row per bag header inside the scroll child.
local function HeaderText(child, i)
    local fs = ns.invUI.headers[i]
    if not fs then
        fs = T.CreateFontString(child, 22, HEADER_COLOR)
        fs:SetJustifyH("LEFT")
        ns.invUI.headers[i] = fs
    end
    return fs
end

local EQUIP_LEFT = {
    { 1,  "HeadSlot" }, { 2, "NeckSlot" }, { 3, "ShoulderSlot" },
    { 15, "BackSlot" }, { 5, "ChestSlot" }, { 4, "ShirtSlot" },
    { 19, "TabardSlot" }, { 9, "WristSlot" },
}
local EQUIP_RIGHT = {
    { 10, "HandsSlot" }, { 6, "WaistSlot" }, { 7, "LegsSlot" },
    { 8,  "FeetSlot" }, { 11, "Finger0Slot" }, { 12, "Finger1Slot" },
    { 13, "Trinket0Slot" }, { 14, "Trinket1Slot" },
}
local EQUIP_BOTTOM = {
    { 16, "MainHandSlot" }, { 17, "SecondaryHandSlot" }, { 18, "RangedSlot" },
}

local SLOT_NAMES = {
    HeadSlot = "Head",
    NeckSlot = "Neck",
    ShoulderSlot = "Shoulder",
    BackSlot = "Back",
    ChestSlot = "Chest",
    ShirtSlot = "Shirt",
    TabardSlot = "Tabard",
    WristSlot = "Wrist",
    HandsSlot = "Hands",
    WaistSlot = "Waist",
    LegsSlot = "Legs",
    FeetSlot = "Feet",
    Finger0Slot = "Finger",
    Finger1Slot = "Finger",
    Trinket0Slot = "Trinket",
    Trinket1Slot = "Trinket",
    MainHandSlot = "Main Hand",
    SecondaryHandSlot = "Off Hand",
    RangedSlot = "Ranged",
}

local function RenderEquipCell(b, slotID, slotName)
    local link = GetInventoryItemLink and GetInventoryItemLink("player", slotID)
    local icon = GetInventoryItemTexture and GetInventoryItemTexture("player", slotID)
    if icon and not ns.IsSecret(icon) then
        b.icon:SetTexture(icon)
        b.icon:SetDesaturated(false)
        b.icon:SetVertexColor(1, 1, 1)
    else
        local _, empty = GetInventorySlotInfo(slotName)
        b.icon:SetTexture(empty)
        b.icon:SetVertexColor(0.45, 0.45, 0.5)
    end
    local q = GetInventoryItemQuality and GetInventoryItemQuality("player", slotID)
    QualityBorder(b, q)
    b.count:SetText("")
    b.slotID, b.slotName, b.link = slotID, slotName, link
end

local function RenderBags(ui)
    local child, cells = ui.child, ui.cells
    local combined = CombinedBags()

    -- Flatten into display lines: a header line or a row of cells.
    local w = math.max(CELL, child:GetWidth() - PAD * 2)
    local perRow = math.max(1, math.floor((w + CELL_GAP) / (CELL + CELL_GAP)))
    local lines, line = {}
    local function PushCell(el)
        if not line or #line == perRow then
            line = {}
            lines[#lines + 1] = line
        end
        line[#line + 1] = el
    end
    for _, bag in ipairs(BagIDs()) do
        local n = C_Container.GetContainerNumSlots
            and C_Container.GetContainerNumSlots(bag) or 0
        if n > 0 then
            if not combined then
                lines[#lines + 1] = {
                    header = bag == 0 and "Backpack"
                        or (C_Container.GetBagName and C_Container.GetBagName(bag))
                        or ("Bag " .. bag)
                }
                line = nil
            end
            for s = 1, n do PushCell({ bag = bag, slot = s }) end
        end
    end

    ui.navBags = {}
    local y, hi, ci = PAD, 0, 0
    for _, ln in ipairs(lines) do
        if ln.header then
            hi = hi + 1
            local fs = HeaderText(child, hi)
            fs:ClearAllPoints()
            fs:SetPoint("TOPLEFT", child, "TOPLEFT", PAD, -y)
            fs:SetText(ln.header)
            fs:Show()
            y = y + HEADER_H + 8
        else
            local row = {}
            ui.navBags[#ui.navBags + 1] = row
            local navRow = #ui.navBags
            for j, el in ipairs(ln) do
                ci = ci + 1
                local b = cells[ci]
                if not b then
                    b = NewCell(child)
                    b:SetScript("OnEnter", function(self)
                        if not self.bag then return end
                        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                        GameTooltip:SetBagItem(self.bag, self.slot)
                        GameTooltip:Show()
                    end)
                    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
                    b:SetScript("OnClick", function(self)
                        ns.invUI.selected = self
                        ns:InventorySelect()
                    end)
                    cells[ci] = b
                end
                local info = ItemInfo(el.bag, el.slot)
                if info then
                    b.icon:SetTexture(info.iconFileID)
                    b.icon:SetVertexColor(1, 1, 1)
                    b.icon:SetDesaturated(false)
                    b.count:SetText((info.stackCount and info.stackCount > 1)
                        and info.stackCount or "")
                    QualityBorder(b, info.quality)
                else
                    b.icon:SetTexture(nil)
                    b.count:SetText("")
                    b.q:Hide()
                end
                b.bag, b.slot = el.bag, el.slot
                b.navRow, b.navCol = navRow, j
                row[j] = b
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", child, "TOPLEFT",
                    PAD + (j - 1) * (CELL + CELL_GAP), -y)
                b:Show()
            end
            y = y + CELL + CELL_GAP
        end
    end
    for i = hi + 1, #ui.headers do ui.headers[i]:Hide() end
    for i = ci + 1, #cells do
        cells[i]:Hide()
        cells[i].bag = nil
    end
    child:SetHeight(math.max(1, y + PAD))

    -- Keep the pad selection on a live cell after reflow.
    if ui.focus ~= 2 then ui.nav = ui.navBags end
    if ui.selected and ui.selected.bag
        and not ui.selected:IsShown() then
        ui.selected = nil
    end
    if ui.focus == 1 and not ui.selected and ui.navBags[1] then
        ui.selected = ui.navBags[1][1]
    end
    ns:InventorySelect()
end

local function MoveInvSelection(ui, dx, dy)
    local cur = ui.selected
    if not cur then return end
    if dy ~= 0 then
        local row = ui.nav[cur.navRow + dy]
        if not row then return end
        local col = math.min(cur.navCol, #row)
        if row[col] then ui.selected = row[col] end
    else
        local row = ui.nav[cur.navRow]
        local col = cur.navCol + dx
        if row and row[col] then
            ui.selected = row[col]
        elseif col < 1 and ui.nav[cur.navRow - 1] then
            local prev = ui.nav[cur.navRow - 1]
            ui.selected = prev[#prev]
        elseif col > #row and ui.nav[cur.navRow + 1] then
            ui.selected = ui.nav[cur.navRow + 1][1]
        end
    end
    ns:InventorySelect()
end

function ns:InventorySelect()
    local ui = ns.invUI
    if not ui then return end
    for _, grid in ipairs({ ui.navBags, ui.navEquip }) do
        for _, row in pairs(grid or {}) do
            for _, b in pairs(row) do
                b.sel:SetShown(b == ui.selected)
            end
        end
    end
    local b = ui.selected
    if b and b.bag then
        -- Reveal the cell inside the bag scroll area.
        local top = -b:GetTop() + ui.child:GetTop() -- child-local y of the cell
        local pos = ui.scroll:GetVerticalScroll()
        local vh = ui.scroll:GetHeight()
        if top < pos then
            ui.sbar:SetValue(top)
        elseif top + CELL > pos + vh then
            ui.sbar:SetValue(top + CELL - vh)
        end
    end
    SyncUseButton(ui)
    if UpdateLegend then UpdateLegend(ui) end
end

function ns:InventoryRefresh()
    local ui = ns.invUI
    if not ui then return end
    if not (ns.pageFrames[3] and ns.pageFrames[3]:IsShown()) then
        ns.invDirty = true
        return
    end
    ns.invDirty = false
    RenderBags(ui)
    for _, b in ipairs(ui.equipCells) do
        RenderEquipCell(b, b.slotID, b.slotName)
    end
end

local function Dirty()
    ns.invDirty = true
    ns:InventoryRefresh()
end

for _, event in ipairs({
    "BAG_UPDATE", "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED",
    "GET_ITEM_INFO_RECEIVED", "ITEM_LOCK_CHANGED",
}) do
    Nocturne.RegisterEvent(event, Dirty)
end

-- An item with a cast time (Hearthstone...) starts a player cast right after
-- the use click; instant items never fire these, so the journal stays open.
local USE_CAST_WINDOW = 1.5
local function CloseOnUseCast(_, unit)
    local ui = ns.invUI
    if unit ~= "player" or not (ui and ui.useAt) then return end
    if GetTime() - ui.useAt > USE_CAST_WINDOW then return end
    ui.useAt = nil
    ns:Close()
end
Nocturne.RegisterEvent("UNIT_SPELLCAST_START", CloseOnUseCast)
Nocturne.RegisterEvent("UNIT_SPELLCAST_CHANNEL_START", CloseOnUseCast)

-- Item use is a protected call, so A cannot touch the bag directly. A
-- hidden secure button carries the action instead, driven by a real
-- override-binding click on PAD1 (secure execution context).
local function EnsureUseButton(ui)
    if ui.useBtn then return true end
    if InCombatLockdown and InCombatLockdown() then return false end
    -- Parented to UIParent: a secure template makes every parent protected,
    -- which would stop the journal from showing/hiding in combat.
    local ok, b = pcall(CreateFrame, "Button", "NocturneJournalPadUse",
        UIParent, "SecureActionButtonTemplate")
    if not ok or not b then return false end
    -- Shown-but-transparent: a hidden button may not receive binding clicks.
    b:SetSize(1, 1)
    b:SetAlpha(0)
    b:EnableMouse(false)
    b:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
    b:RegisterForClicks("AnyUp")
    b:SetAttribute("type", "item")
    b:SetAttribute("useOnKeyDown", false)
    b:HookScript("OnClick", function()
        ui.useClicks = (ui.useClicks or 0) + 1
        ui.useAt = GetTime()
    end)
    ui.useBtn = b
    return true
end

SyncUseButton = function(ui)
    if not EnsureUseButton(ui) then return end
    if InCombatLockdown and InCombatLockdown() then return end
    local b = ui.selected
    local info = ui.focus == 1 and b and b.bag
        and ItemInfo(b.bag, b.slot)
    ui.useBtn:SetAttribute("item", info and
        (info.hyperlink or ("item:" .. info.itemID)) or nil)
end

-- Pad actions, mirroring the native gamepad bag controls: A uses/equips
-- (unequips on the doll), X picks the item up for moving, Y destroys.
local function PadUse(ui)
    local b = ui.selected
    if not b then return end
    if ui.focus == 1 then
        return
    elseif b.slotID and b.link
        and _G.PickupInventoryItem and _G.PutItemInBackpack then
        PickupInventoryItem(b.slotID)
        PutItemInBackpack()
    end
end

local function PadPickup(ui)
    local b = ui.selected
    if ui.focus ~= 1 or not b or not b.bag then return end
    if C_Container.PickupContainerItem then
        C_Container.PickupContainerItem(b.bag, b.slot)
    end
end

local function PadDestroy(ui)
    local b = ui.selected
    if not b then return end
    local name, destroy
    if ui.focus == 1 then
        if not b.bag then return end
        local info = C_Container.GetContainerItemInfo(b.bag, b.slot)
        if not info or not info.itemID then return end
        name = (GetItemInfo and GetItemInfo(info.itemID)) or "item"
        destroy = function()
            C_Container.PickupContainerItem(b.bag, b.slot)
            if DeleteCursorItem then DeleteCursorItem() end
        end
    else
        if not b.link then return end
        name = (GetItemInfo and GetItemInfo(b.link)) or "item"
        destroy = function()
            PickupInventoryItem(b.slotID)
            if DeleteCursorItem then DeleteCursorItem() end
        end
    end
    ns:ShowConfirm(("Destroy \"%s\"?"):format(name), "Destroy", destroy)
end

UpdateLegend = function(ui)
    local function Set(e, text)
        e.label:SetText(text or "")
        e.glyph:SetShown(text ~= nil)
    end
    local b = ui.selected
    local hasItem = false
    if b then
        if ui.focus == 1 then
            hasItem = b.bag and ItemInfo(b.bag, b.slot) ~= nil
        else
            hasItem = b.link ~= nil
        end
    end
    if not hasItem then
        Set(ui.legendX, nil)
        Set(ui.legendY, nil)
        Set(ui.legendA, nil)
    elseif ui.focus == 1 then
        Set(ui.legendX, "Pick up")
        Set(ui.legendY, "Destroy")
        Set(ui.legendA, "Use")
    else
        Set(ui.legendX, nil)
        Set(ui.legendY, "Destroy")
        Set(ui.legendA, "Unequip")
    end
    -- Navigate hugs the leftmost visible action, or the right edge itself.
    local nav = ui.legendNav
    nav:ClearAllPoints()
    for _, e in ipairs({ ui.legendX, ui.legendY, ui.legendA }) do
        if e.glyph:IsShown() then
            nav:SetPoint("RIGHT", e.glyph, "LEFT", -26, 0)
            return
        end
    end
    nav:SetPoint("BOTTOMRIGHT", ui.legend, "BOTTOMRIGHT")
end

ns.RegisterPage(3, {
    key = "inventory",
    title = "Inventory",
    subPages = function() return { "Bags", "Equipped" } end,
    ownSubBar = true,
    PadBind = function()
        local ui = ns.invUI
        return ui and ui.focus == 1 and ui.useBtn ~= nil
    end,
    OnPadReset = function()
        local ui = ns.invUI
        if ui and ui.dpadHold then wipe(ui.dpadHold) end
    end,
    OnSubPage = function(f, i)
        local ui = ns.invUI
        if not ui then return end
        ui.focus = i
        for j, b in ipairs(ui.subTabs) do
            local on = j == i
            local c = on and HEADER_COLOR or TEXT
            b.label:SetTextColor(c[1], c[2], c[3])
            b.line:SetShown(on)
        end
        ui.nav = i == 1 and ui.navBags or ui.navEquip
        ui.selected = ui.nav and ui.nav[1] and ui.nav[1][1]
        UpdateLegend(ui)
        SyncUseButton(ui)
        ns:InventorySelect()
    end,
    Build = function(f)
        local ui = { cells = {}, headers = {}, equipCells = {}, nav = {}, focus = 1 }
        ns.invUI = ui
        ui.pageFrame = f

        -- Focus switcher, shrink-wrapped and centered over both panels:
        -- [LT] Bags  Equipped [RT]
        local subBar = CreateFrame("Frame", nil, f)
        subBar:SetPoint("TOP", f, "TOP", 0, -16)
        subBar:SetHeight(36)
        local lt = T.CreateFontString(subBar, 20, T.colors.textDim)
        lt:SetText(ns.PadGlyph("PADLTRIGGER", "LT"))
        local rt = T.CreateFontString(subBar, 20, T.colors.textDim)
        rt:SetText(ns.PadGlyph("PADRTRIGGER", "RT"))
        ui.subTabs = {}
        local parts = { lt }
        for i, name in ipairs({ "Bags", "Equipped" }) do
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
        subBar:SetSize(math.ceil(total), 36)
        local x = -total / 2
        for _, p in ipairs(parts) do
            p:ClearAllPoints()
            p:SetPoint("LEFT", subBar, "CENTER", x, 0)
            x = x + Width(p) + GAPX
        end

        local bags = PANEL(f, "inventory", "QuestBG-Parchment")
        bags:SetPoint("TOPLEFT", MARGIN, -MARGIN - 44)
        bags:SetPoint("BOTTOMLEFT", MARGIN, MARGIN)
        local equip = PANEL(f, "inventory", "QuestBG-Parchment")
        equip:SetPoint("TOPRIGHT", -MARGIN, -MARGIN - 44)
        equip:SetPoint("BOTTOMRIGHT", -MARGIN, MARGIN)
        equip:SetPoint("LEFT", bags, "RIGHT", GAP, 0)

        -- Left: bag grid in a native scroll.
        local scroll = CreateFrame("ScrollFrame", nil, bags)
        ui.scroll = scroll
        scroll:SetPoint("TOPLEFT")
        scroll:SetPoint("BOTTOMRIGHT", -28, 0)
        scroll:EnableMouseWheel(true)
        local sbar = CreateFrame("Slider", nil, scroll, "UIPanelScrollBarTemplate")
        ui.sbar = sbar
        sbar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 8, -16)
        sbar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 8, 16)
        sbar:SetValueStep(30)
        sbar:SetObeyStepOnDrag(false)
        sbar:SetScript("OnValueChanged", function(_, v) scroll:SetVerticalScroll(v) end)
        scroll:SetScript("OnMouseWheel", function(_, delta)
            sbar:SetValue(sbar:GetValue() - delta * 60)
        end)
        scroll:SetScript("OnScrollRangeChanged", function(_, _, yrange)
            sbar:SetMinMaxValues(0, math.max(1, yrange or 0))
            sbar:SetShown((yrange or 0) > 1)
        end)
        scroll:SetScript("OnVerticalScroll", function(_, off) sbar:SetValue(off) end)
        local child = CreateFrame("Frame", nil, scroll)
        scroll:SetScrollChild(child)
        ui.child = child

        -- Right: paper-doll columns + player model + weapon row.
        local ok, model = pcall(CreateFrame, "PlayerModel", nil, equip)
        if ok and model then
            ui.model = model
            model:SetPoint("TOP", 0, -40)
            model:SetPoint("BOTTOM", 0, 90)
            model:SetPoint("LEFT", equip, "LEFT", 100, 0)
            model:SetPoint("RIGHT", equip, "RIGHT", -100, 0)
            model:SetAlpha(0.9)
            pcall(function() model:SetUnit("player") end)
        end

        local function EquipCell(slotID, slotName)
            local b = NewCell(equip)
            b:SetSize(CELL + 6, CELL + 6)
            b.label = T.CreateFontString(b, 12, DIM_COLOR)
            b.label:SetPoint("TOP", b, "BOTTOM", 0, -2)
            b.label:SetText(SLOT_NAMES[slotName] or slotName)
            b:SetScript("OnEnter", function(self)
                if not self.link then return end
                GameTooltip:SetOwner(self, "ANCHOR_LEFT")
                GameTooltip:SetInventoryItem("player", self.slotID)
                GameTooltip:Show()
            end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
            b:SetScript("OnClick", function(self)
                ns.invUI.selected = self
                ns:InventorySelect()
            end)
            b.slotID, b.slotName = slotID, slotName
            ui.equipCells[#ui.equipCells + 1] = b
            return b
        end

        ui.navEquip = {}
        local function NavEquip(b, r, c)
            b.navRow, b.navCol = r, c
            ui.navEquip[r] = ui.navEquip[r] or {}
            ui.navEquip[r][c] = b
        end
        for i, s in ipairs(EQUIP_LEFT) do
            local b = EquipCell(s[1], s[2])
            b:SetPoint("TOPLEFT", equip, "TOPLEFT", PAD, -PAD - (i - 1) * 78)
            NavEquip(b, i, 1)
        end
        for i, s in ipairs(EQUIP_RIGHT) do
            local b = EquipCell(s[1], s[2])
            b:SetPoint("TOPRIGHT", equip, "TOPRIGHT", -PAD, -PAD - (i - 1) * 78)
            NavEquip(b, i, 2)
        end
        for i, s in ipairs(EQUIP_BOTTOM) do
            local b = EquipCell(s[1], s[2])
            b:SetPoint("BOTTOM", equip, "BOTTOM", (i - 2) * 66, PAD)
            NavEquip(b, 9, i)
        end

        -- Pad legend, bottom-right, same style as the quest page.
        local legend = CreateFrame("Frame", nil, f)
        legend:SetPoint("BOTTOMRIGHT", -MARGIN, MARGIN)
        legend:SetSize(600, 30)
        local function LegendEntry(pad, prev)
            local label = T.CreateFontString(legend, 15, TEXT)
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
        ui.legend = legend
        local nav = T.CreateFontString(legend, 15, TEXT)
        ui.legendNav = nav
        local up = ns.PadGlyph("PADDUP")
        local down = ns.PadGlyph("PADDDOWN")
        local dpad = (up and up:find("|") and down and down:find("|"))
            and (up .. down) or "D-Pad"
        nav:SetText(dpad .. "  Navigate")
        nav:SetPoint("RIGHT", ui.legendX.glyph, "LEFT", -26, 0)

        -- Held D-pad repeats with the same gentle ramp as the quest list.
        ui.dpadHold = {}
        local function Move(dx, dy)
            MoveInvSelection(ui, dx, dy)
        end
        f:SetScript("OnUpdate", function(_, dt)
            for button, st in pairs(ui.dpadHold) do
                st.t = st.t + dt
                st.acc = st.acc + dt
                local iv = math.max(0.11, 0.22 - st.t * 0.08)
                if st.acc >= iv then
                    st.acc = 0
                    if button == "PADDUP" then
                        Move(0, -1)
                    elseif button == "PADDDOWN" then
                        Move(0, 1)
                    elseif button == "PADDLEFT" then
                        Move(-1, 0)
                    elseif button == "PADDRIGHT" then
                        Move(1, 0)
                    end
                end
            end
        end)

        local function Layout()
            bags:SetWidth(math.floor(f:GetWidth() * 0.55) - GAP)
            child:SetWidth(math.max(10, scroll:GetWidth()))
            RenderBags(ui)
        end
        Layout()
        f:SetScript("OnSizeChanged", Layout)

        ns.invDirty = true
    end,
    OnShow = function()
        if ns.invDirty then ns:InventoryRefresh() end
    end,
    OnPad = function(f, button)
        local ui = ns.invUI
        if not ui then return end
        local dir = { PADDUP = true, PADDDOWN = true, PADDLEFT = true, PADDRIGHT = true }
        if dir[button] then
            ui.dpadHold[button] = { t = 0, acc = 0 }
            if not ui.selected then
                ui.selected = ui.nav[1] and ui.nav[1][1]
                ns:InventorySelect()
                return
            end
            if button == "PADDUP" then
                MoveInvSelection(ui, 0, -1)
            elseif button == "PADDDOWN" then
                MoveInvSelection(ui, 0, 1)
            elseif button == "PADDLEFT" then
                MoveInvSelection(ui, -1, 0)
            else
                MoveInvSelection(ui, 1, 0)
            end
            return
        end
        if button == "PAD3" then
            PadPickup(ui)
        elseif button == "PAD4" then
            PadDestroy(ui)
        elseif button == "PAD1" then
            PadUse(ui)
        end
    end,
    OnPadUp = function(f, button)
        local ui = ns.invUI
        if ui and ui.dpadHold then ui.dpadHold[button] = nil end
    end,
    OnHide = function()
        local ui = ns.invUI
        if ui and ui.dpadHold then wipe(ui.dpadHold) end
    end,
})
