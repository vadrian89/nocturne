local _, ns = ...

local Nocturne = _G.Nocturne
local T = Nocturne.Theme

local PANEL = ns.JournalPanel
local MARGIN, GAP = ns.JournalMargin, ns.JournalGap

local CELL, CELL_GAP = 44, 6
local BAG_CELL = 66
local SLOT_ATLAS = "bags-item-slot64"
local QUALITY_FRAME = "Interface\\Common\\WhiteIconFrame"
local HEADER_H = 30
local PAD = 40
local STATS_W = 265
local EQ_CELL = 60

local UpdateLegend, SyncUseButton

local TEXT = { 0.95, 0.95, 0.97, 1 }
local HEADER_COLOR = { 0.80, 0.68, 0.42, 1 }
local DIM_COLOR = { 0.60, 0.60, 0.65, 1 }

local function StickAxis(v)
    if v == nil or ns.IsSecret(v) then return 0 end
    if v > -0.25 and v < 0.25 then return 0 end
    return v
end

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
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(SLOT_ATLAS) then
        b.bg:SetAtlas(SLOT_ATLAS)
    else
        b.bg:SetColorTexture(0, 0, 0, 0.4)
    end
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.q = b:CreateTexture(nil, "ARTWORK", nil, 2)
    b.q:SetAllPoints()
    b.q:SetTexture(QUALITY_FRAME)
    b.q:Hide()
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
            b.q:SetVertexColor(r, g, bl)
            b.q:Show()
            return
        end
    end
    -- Neutral gray frame on common/empty slots so they read against the
    -- dark scene backdrop.
    b.q:SetVertexColor(0.55, 0.55, 0.58)
    b.q:Show()
end

local TIP_SCALE = 1.6

local function HideItemTip(ui)
    if ui.tipOwner then
        GameTooltip:Hide()
        GameTooltip:SetScale(1)
        for i = 1, 2 do
            local st = _G["ShoppingTooltip" .. i]
            if st then st:SetScale(1) end
        end
        ui.tipOwner = nil
    end
end

local function ShowItemTip(ui, b)
    if not (b and ui.pageFrame and ui.pageFrame:IsShown()) then return end
    if b.bag then
        if not ItemInfo(b.bag, b.slot) then
            HideItemTip(ui)
            return
        end
        GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
        GameTooltip:SetBagItem(b.bag, b.slot)
    elseif b.slotID and b.link then
        GameTooltip:SetOwner(b, b.tipAnchor or "ANCHOR_LEFT")
        GameTooltip:SetInventoryItem("player", b.slotID)
    else
        HideItemTip(ui)
        return
    end
    ui.tipOwner = b
    GameTooltip:SetScale(TIP_SCALE)
    -- Comparison tooltip for the equipped counterpart uses the same scale.
    for i = 1, 2 do
        local st = _G["ShoppingTooltip" .. i]
        if st then st:SetScale(TIP_SCALE) end
    end
    GameTooltip:Show()
end

-- Mouse hover reroutes through the same path so the enlarged scale applies.
local function CellEnter(self)
    ShowItemTip(ns.invUI, self)
end
local function CellLeave(self)
    local ui = ns.invUI
    if ui and ui.selected and ui.selected ~= self then
        ShowItemTip(ui, ui.selected)
    elseif ui then
        HideItemTip(ui)
    end
end

local function StatUnit(i)
    if not UnitStat then return nil end
    local _, eff = UnitStat("player", i)
    if eff == nil or ns.IsSecret(eff) then return nil end
    return tostring(eff)
end

local function StatPct(fn, ...)
    if not fn then return nil end
    local v = fn(...)
    if v == nil or ns.IsSecret(v) then return nil end
    return ("%.1f%%"):format(v)
end

local function StatNum(fn, ...)
    if not fn then return nil end
    local v = fn(...)
    if v == nil or ns.IsSecret(v) then return nil end
    return tostring(v)
end

-- Stat icons: spell/item art (fileID) or a texture path — both are valid
-- SetTexture inputs. SpellIDs are classic buffs with on-theme icons.
local function SpellIcon(id)
    local t = C_Spell and C_Spell.GetSpellTexture
        and C_Spell.GetSpellTexture(id)
    if t == nil and GetSpellTexture then t = GetSpellTexture(id) end
    if t == nil or ns.IsSecret(t) then return nil end
    return t
end
local function ItemIcon(id)
    local t = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)
    if t == nil and GetItemIcon then t = GetItemIcon(id) end
    if t == nil or ns.IsSecret(t) then return nil end
    return t
end

-- { header, statCols index, rows }: column 1 is right of the doll, columns
-- 2..4 are the three bottom slots. Row field 3 is the icon function.
local STATS = {
    { "General", 1, {
        { "Item Level", function()
            local v = GetAverageItemLevel and GetAverageItemLevel()
            if v == nil or ns.IsSecret(v) then return nil end
            return ("%.1f"):format(v)
        end, function() return ItemIcon(19) end },
        { "Health", function() return StatNum(UnitHealthMax, "player") end,
            function() return SpellIcon(2054) end },
        { "Mana", function()
            local pt = Enum and Enum.PowerType and Enum.PowerType.Mana or 0
            local v = UnitPowerMax and UnitPowerMax("player", pt)
            if v == nil or ns.IsSecret(v) or v == 0 then return nil end
            return tostring(v)
        end, function() return SpellIcon(12051) end },
        { "Movement Speed", function()
            if not GetUnitSpeed then return nil end
            local v = GetUnitSpeed("player")
            if v == nil or ns.IsSecret(v) then return nil end
            return ("%.0f%%"):format(v / 7 * 100)
        end, function() return SpellIcon(2983) end },
    } },
    { "Primary Attributes", 1, {
        { "Strength", function() return StatUnit(1) end,
            function() return SpellIcon(6673) end },
        { "Agility", function() return StatUnit(2) end,
            function() return SpellIcon(768) end },
        { "Stamina", function() return StatUnit(3) end,
            function() return SpellIcon(1243) end },
        { "Intellect", function() return StatUnit(4) end,
            function() return SpellIcon(1459) end },
        { "Spirit", function() return StatUnit(5) end,
            function() return SpellIcon(14752) end },
    } },
    { "Modifiers", 1, {
        { "Critical Strike", function() return StatPct(GetCritChance) end,
            function() return SpellIcon(11366) end },
        { "Haste", function() return StatPct(GetHaste) end,
            function()
                return "Interface\\Icons\\Spell_Nature_Swiftness"
            end },
        { "Mastery", function() return StatPct(GetMasteryEffect) end,
            function()
                return "Interface\\Icons\\Trade_BlackSmithing"
            end },
        { "Versatility", function()
            if not (GetCombatRatingBonus and _G.CR_VERSATILITY_DAMAGE_DONE) then
                return nil
            end
            return StatPct(GetCombatRatingBonus, CR_VERSATILITY_DAMAGE_DONE)
        end, function() return SpellIcon(740) end },
    } },
    { "Weapons", 2, { -- column 2 sits under the equipment cells
        { "Main Hand", function()
            if not UnitDamage then return nil end
            local lo, hi = UnitDamage("player")
            if lo == nil or hi == nil or ns.IsSecret(lo) or ns.IsSecret(hi) then
                return nil
            end
            return ("%.0f - %.0f"):format(lo, hi)
        end, function() return SpellIcon(78) end },
        { "Attack Power", function()
            if not UnitAttackPower then return nil end
            local base, pos, neg = UnitAttackPower("player")
            if base == nil or ns.IsSecret(base) then return nil end
            return tostring(base + (pos or 0) + (neg or 0))
        end, function() return SpellIcon(19506) end },
    } },
    { "Defense", 1, {
        { "Defense", function()
            if not UnitDefense then return nil end
            local base, mod = UnitDefense("player")
            if base == nil or ns.IsSecret(base) then return nil end
            mod = (mod ~= nil and not ns.IsSecret(mod)) and mod or 0
            return ("%d / %d"):format(base, base + mod)
        end, function() return SpellIcon(871) end },
        { "Dodge", function() return StatPct(GetDodgeChance) end,
            function() return SpellIcon(5277) end },
        { "Parry", function() return StatPct(GetParryChance) end,
            function() return SpellIcon(20230) end },
        { "Block", function() return StatPct(GetBlockChance) end,
            function() return SpellIcon(2565) end },
        { "Armor", function()
            if not UnitArmor then return nil end
            local _, v = UnitArmor("player")
            if v == nil or ns.IsSecret(v) then return nil end
            return tostring(v)
        end, function() return SpellIcon(588) end },
    } },
    { "Resistances", 1, {
        { "Arcane", function() return StatNum(UnitResistance, "player", 7) end,
            function() return "Interface\\PaperDollInfoFrame\\SpellSchoolIcon7" end },
        { "Fire", function() return StatNum(UnitResistance, "player", 3) end,
            function() return "Interface\\PaperDollInfoFrame\\SpellSchoolIcon3" end },
        { "Frost", function() return StatNum(UnitResistance, "player", 5) end,
            function() return "Interface\\PaperDollInfoFrame\\SpellSchoolIcon5" end },
        { "Nature", function() return StatNum(UnitResistance, "player", 4) end,
            function() return "Interface\\PaperDollInfoFrame\\SpellSchoolIcon4" end },
        { "Shadow", function() return StatNum(UnitResistance, "player", 6) end,
            function() return "Interface\\PaperDollInfoFrame\\SpellSchoolIcon6" end },
    } },
}

local function StatRow(col, j)
    local rows = col.rows
    if not rows then
        rows = {}
        col.rows = rows
    end
    local r = rows[j]
    if not r then
        r = {
            bar = col:CreateTexture(nil, "ARTWORK"),
            icon = col:CreateTexture(nil, "ARTWORK", nil, 1),
            label = T.CreateFontString(col, 19, DIM_COLOR),
            value = T.CreateFontString(col, 19, TEXT),
        }
        r.bar:SetTexture("Interface\\CharacterFrame\\Char-Stat-Top")
        r.bar:Hide()
        r.label:SetJustifyH("LEFT")
        r.value:SetJustifyH("RIGHT")
        r.icon:SetSize(18, 18)
        rows[j] = r
    end
    return r
end

local function RenderStats(ui)
    local cols = ui.statCols
    if not cols then return end
    local used, ys = {}, {}
    for _, group in ipairs(STATS) do
        local col = cols[group[2]]
        if col then
            local rows = {}
            for _, s in ipairs(group[3]) do
                local ok, v = pcall(s[2])
                if ok and v ~= nil then
                    local icon = s[3] and s[3]()
                    rows[#rows + 1] = { s[1], tostring(v), icon }
                end
            end
            if #rows > 0 then
                local n = (used[col] or 0) + 1
                local y = ys[col] or -8
                local font = 19
                local r = StatRow(col, n)
                -- Category header: the character-frame stat-category bar.
                r.bar:ClearAllPoints()
                r.bar:SetPoint("TOPLEFT", col, "TOPLEFT", -4, y)
                r.bar:SetPoint("TOPRIGHT", col, "TOPRIGHT", 4, y)
                r.bar:SetHeight(28)
                r.bar:Show()
                r.label:ClearAllPoints()
                r.label:SetFont(T.fonts.main, font, "")
                r.label:SetTextColor(HEADER_COLOR[1], HEADER_COLOR[2],
                    HEADER_COLOR[3])
                r.label:SetPoint("CENTER", r.bar, "CENTER", 0, -1)
                r.label:SetText(group[1])
                r.value:Hide()
                r.icon:Hide()
                y = y - 34
                for _, sv in ipairs(rows) do
                    n = n + 1
                    used[col] = n
                    r = StatRow(col, n)
                    r.bar:Hide()
                    r.label:ClearAllPoints()
                    r.value:ClearAllPoints()
                    r.icon:ClearAllPoints()
                    r.label:SetFont(T.fonts.main, font, "")
                    r.value:SetFont(T.fonts.main, font, "")
                    r.label:SetTextColor(DIM_COLOR[1], DIM_COLOR[2],
                        DIM_COLOR[3])
                    if sv[3] then
                        r.icon:SetPoint("TOPLEFT", col, "TOPLEFT", 0, y - 2)
                        r.icon:SetTexture(sv[3])
                        r.icon:Show()
                        r.label:SetPoint("TOPLEFT", col, "TOPLEFT", 24, y)
                    else
                        r.icon:Hide()
                        r.label:SetPoint("TOPLEFT", col, "TOPLEFT", 0, y)
                    end
                    r.value:SetPoint("TOPRIGHT", col, "TOPRIGHT", 0, y)
                    r.label:SetText(sv[1])
                    r.value:SetText(sv[2])
                    r.label:Show()
                    r.value:Show()
                    y = y - 25
                end
                ys[col] = y - 8
            end
        end
    end
    for _, col in ipairs(cols) do
        for j = (used[col] or 0) + 1, #(col.rows or {}) do
            local r = col.rows[j]
            r.bar:Hide()
            r.label:Hide()
            r.value:Hide()
            r.icon:Hide()
        end
    end
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
    local w = math.max(BAG_CELL, child:GetWidth() - PAD * 2)
    local perRow = math.max(1, math.floor((w + CELL_GAP) / (BAG_CELL + CELL_GAP)))
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
                    b:SetSize(BAG_CELL, BAG_CELL)
                    b:SetScript("OnEnter", CellEnter)
                    b:SetScript("OnLeave", CellLeave)
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
                    QualityBorder(b, nil)
                end
                b.bag, b.slot = el.bag, el.slot
                b.navRow, b.navCol = navRow, j
                row[j] = b
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", child, "TOPLEFT",
                    PAD + (j - 1) * (BAG_CELL + CELL_GAP), -y)
                b:Show()
            end
            y = y + BAG_CELL + CELL_GAP
        end
    end
    for i = hi + 1, #ui.headers do ui.headers[i]:Hide() end
    for i = ci + 1, #cells do
        cells[i]:Hide()
        cells[i].bag = nil
    end
    child:SetHeight(math.max(1, y + CELL_GAP))

    if ui.UpdateBar then ui.UpdateBar() end

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
    if b and ui.focus == 1 then
        -- Reveal the cell inside the bag scroll area.
        local top = -b:GetTop() + ui.child:GetTop() -- child-local y of the cell
        local pos = ui.scroll:GetVerticalScroll()
        local vh = ui.scroll:GetHeight()
        local h = b:GetHeight()
        if top < pos then
            ui.sbar:SetValue(top)
        elseif top + h > pos + vh then
            ui.sbar:SetValue(top + h - vh)
        end
    end
    SyncUseButton(ui)
    ShowItemTip(ui, b)
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
    RenderStats(ui)
end

local function Dirty()
    ns.invDirty = true
    ns:InventoryRefresh()
end

for _, event in ipairs({
    "BAG_UPDATE", "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED",
    "GET_ITEM_INFO_RECEIVED", "ITEM_LOCK_CHANGED",
    "UNIT_STATS", "UNIT_ATTACK_POWER", "COMBAT_RATING_UPDATE",
    "SPELL_POWER_CHANGED", "PLAYER_DAMAGE_DONE_MODS",
}) do
    Nocturne.RegisterEvent(event, Dirty)
end

-- An item with a cast time (Hearthstone...) starts a player cast right after
-- the use click; instant items never fire these, so the journal stays open.
local USE_CAST_WINDOW = 1.5

-- Character-select style backdrop: the glue scene per race lives at
-- Interface\Glues\Models\UI_<race>\. UnitRace file names differ from the
-- folder names for a few races.
local RACE_BG_DIR = { Scourge = "UI_Undead" }
local function RaceScene(f)
    local _, race = UnitRace("player")
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    local candidates = {
        race and RACE_BG_DIR[race],
        race and ("UI_" .. race),
        faction == "Horde" and "UI_Orc",
        faction == "Alliance" and "UI_Human",
    }
    local ok, m = pcall(CreateFrame, "Model", nil, f)
    if not (ok and m) then
        ns.diagInvScene = "no Model frame (" .. tostring(m) .. ")"
        return
    end
    m:SetAllPoints(f)
    local tried = {}
    for _, dir in ipairs(candidates) do
        if dir and m.SetModel then
            local path = ("Interface\\GLUES\\Models\\%s\\%s.m2"):format(dir, dir)
            local okSet, err = pcall(m.SetModel, m, path)
            local fid = okSet and m.GetModelFileID and m:GetModelFileID()
            tried[#tried + 1] = dir .. "=" .. (okSet and ("ok/id=" .. tostring(fid))
                or tostring(err):sub(1, 60))
            if okSet and (fid == nil or fid ~= 0) then
                pcall(m.SetCamera, m, 0)
                pcall(m.SetSequence, m, 0)
                local veil = m:CreateTexture(nil, "OVERLAY")
                veil:SetAllPoints()
                veil:SetColorTexture(0.02, 0.02, 0.03, 0.72)
                ns.diagInvScene = dir
                return m
            end
        end
    end
    m:Hide()
    ns.diagInvScene = "none (fileID=" .. tostring(GetFileIDFromPath) .. "; "
        .. table.concat(tried, "; ") .. ")"
end
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

        local scene = RaceScene(f)
        ui.scene = scene

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
        if scene then
            bags.bg:SetColorTexture(0.03, 0.03, 0.04, 0.62)
            equip.bg:SetColorTexture(0.03, 0.03, 0.04, 0.62)
        end

        -- Left: bag grid in a native scroll.
        local scroll = CreateFrame("ScrollFrame", nil, bags)
        ui.scroll = scroll
        scroll:SetPoint("TOPLEFT")
        scroll:SetPoint("BOTTOMRIGHT", -28, 0)
        scroll:EnableMouseWheel(true)
        local sbar = ns.NewScrollBar(scroll)
        ui.sbar = sbar
        sbar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 8, 0)
        sbar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 8, 0)
        sbar:SetValueStep(30)
        sbar:SetObeyStepOnDrag(false)
        sbar:SetScript("OnValueChanged", function(_, v) scroll:SetVerticalScroll(v) end)
        scroll:SetScript("OnMouseWheel", function(_, delta)
            sbar:SetValue(sbar:GetValue() - delta * 60)
        end)
        scroll:SetScript("OnScrollRangeChanged", function(_, _, yrange)
            sbar:SetMinMaxValues(0, math.max(1, yrange or 0))
            sbar:SetShown((yrange or 0) > 1)
            ns.FitScrollThumb(sbar, scroll:GetHeight(), yrange)
        end)
        scroll:SetScript("OnVerticalScroll", function(_, off) sbar:SetValue(off) end)
        local child = CreateFrame("Frame", nil, scroll)
        scroll:SetScrollChild(child)
        ui.child = child

        -- OnScrollRangeChanged does not fire reliably while the page is
        -- hidden at build time, so the range is derived from the real sizes
        -- whenever the content or the viewport changes.
        ui.UpdateBar = function()
            local vh = scroll:GetHeight()
            local range = math.max(0, child:GetHeight() - vh)
            sbar:SetMinMaxValues(0, math.max(1, range))
            sbar:SetShown(range > 1)
            ns.FitScrollThumb(sbar, vh, range)
        end
        scroll:SetScript("OnSizeChanged", function() ui.UpdateBar() end)

        ui.statCols = {}

        -- Weapons stats go under the model, centered on its column.
        local wstats = CreateFrame("Frame", nil, equip)
        ui.statCols[2] = wstats
        wstats:SetSize(280, 110)
        wstats:SetPoint("BOTTOM", equip, "BOTTOM", -35, PAD)

        -- Middle column: the character model, between the gear and stats.
        local ok, model = pcall(CreateFrame, "PlayerModel", nil, equip)
        if ok and model then
            ui.model = model
            model:SetPoint("TOPLEFT", equip, "TOPLEFT",
                PAD + 2 * EQ_CELL + 56, -40)
            model:SetPoint("RIGHT", equip, "RIGHT",
                -PAD - STATS_W - 16, 0)
            model:SetPoint("BOTTOM", wstats, "TOP", 0, 10)
            model:SetAlpha(0.9)
            pcall(function() model:SetUnit("player") end)
            ui.modelYaw = 0
            ui.modelPitch = 0
            ui.modelZoom = 1
        end

        -- Right column: all stats except Weapons, full height.
        local stats = CreateFrame("Frame", nil, equip)
        ui.stats = stats
        stats:SetPoint("TOPRIGHT", equip, "TOPRIGHT", -PAD, -PAD)
        stats:SetPoint("BOTTOMRIGHT", equip, "BOTTOMRIGHT", -PAD, PAD)
        stats:SetWidth(STATS_W)
        ui.statCols[1] = stats

        local function EquipCell(slotID, slotName)
            local b = NewCell(equip)
            b:SetSize(EQ_CELL, EQ_CELL)
            b.label = T.CreateFontString(b, 12, DIM_COLOR)
            b.label:SetPoint("TOP", b, "BOTTOM", 0, -2)
            b.label:SetText(SLOT_NAMES[slotName] or slotName)
            b:SetScript("OnEnter", CellEnter)
            b:SetScript("OnLeave", CellLeave)
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
        -- Column A is 208 wide (the 3-cell weapon row); the 2 gear columns
        -- (140) are centered inside it.
        local lastL
        for i, s in ipairs(EQUIP_LEFT) do
            local b = EquipCell(s[1], s[2])
            b.tipAnchor = "ANCHOR_RIGHT"
            b:SetPoint("TOPLEFT", equip, "TOPLEFT",
                PAD + 34, -PAD - (i - 1) * 74)
            NavEquip(b, i, 1)
            lastL = b
        end
        for i, s in ipairs(EQUIP_RIGHT) do
            local b = EquipCell(s[1], s[2])
            b.tipAnchor = "ANCHOR_LEFT"
            b:SetPoint("TOPLEFT", equip, "TOPLEFT",
                PAD + 34 + EQ_CELL + 20, -PAD - (i - 1) * 74)
            NavEquip(b, i, 2)
        end
        for i, s in ipairs(EQUIP_BOTTOM) do
            local b = EquipCell(s[1], s[2])
            b.tipAnchor = "ANCHOR_TOP"
            b:SetPoint("TOP", lastL, "BOTTOM", (i - 1) * 74 - 34, -18)
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
            bags:SetWidth(math.floor(f:GetWidth() * 0.3) - GAP)
            child:SetWidth(math.max(10, scroll:GetWidth()))
            RenderBags(ui)
        end
        Layout()
        f:SetScript("OnSizeChanged", Layout)

        ns.invDirty = true
    end,
    OnShow = function()
        if ns.invDirty then ns:InventoryRefresh() end
        local ui = ns.invUI
        if ui and ui.UpdateBar then
            ui.UpdateBar()
            C_Timer.After(0, ui.UpdateBar)
            C_Timer.After(0.3, function()
                local th = ui.sbar:GetThumbTexture()
                local function Box(f)
                    return ("L%.0f R%.0f T%.0f B%.0f"):format(
                        f:GetLeft() or -1, f:GetRight() or -1,
                        f:GetTop() or -1, f:GetBottom() or -1)
                end
                if th then
                    ui.barSnap = ("vis=%s effAlpha=%.2f val=%.0f bar[%s] thumb[%s] thumbShown=%s thumbVisible=%s")
                        :format(
                            tostring(ui.sbar:IsVisible()), ui.sbar:GetEffectiveAlpha(),
                            ui.sbar:GetValue(), Box(ui.sbar), Box(th),
                            tostring(th:IsShown()), tostring(th:IsVisible()))
                end
            end)
        end
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
    OnStick = function(f, stick, x, y, dt)
        local ui = ns.invUI
        local m = ui and ui.model
        if not m then return end
        local name = stick or ""
        local step = (dt or 0.05) * 0.6
        if name:find("Left") or name:find("Move") or name == "PADLSTICK" then
            x, y = StickAxis(x), StickAxis(y)
            if x ~= 0 then
                ui.modelYaw = (ui.modelYaw or 0) + x * step * 2
                if m.SetFacing then m:SetFacing(ui.modelYaw) end
            end
            if y ~= 0 then
                ui.modelPitch = math.max(-1.2, math.min(1.2,
                    (ui.modelPitch or 0) + y * step * 1.5))
                pcall(function()
                    if m.SetPitch then m:SetPitch(ui.modelPitch) end
                end)
            end
        elseif name:find("Right") or name:find("Camera") or name == "PADRSTICK" then
            y = StickAxis(y)
            if y ~= 0 then
                local z = math.max(0.4, math.min(3,
                    (ui.modelZoom or 1) + y * step))
                ui.modelZoom = z
                pcall(function()
                    if m.SetCamDistanceScale then
                        m:SetCamDistanceScale(z)
                    elseif m.SetPosition then
                        m:SetPosition(0, 0, 1 - z)
                    end
                end)
            end
        end
    end,
    OnHide = function()
        local ui = ns.invUI
        if ui and ui.dpadHold then wipe(ui.dpadHold) end
        if ui then HideItemTip(ui) end
    end,
})
