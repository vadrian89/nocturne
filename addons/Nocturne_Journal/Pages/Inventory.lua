local _, ns = ...

local Nocturne = _G.Nocturne
local T = Nocturne.Theme

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
local WHITE = { 1, 1, 1, 1 }

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

local function BindsForItem(itemID)
    local seqs
    if ns.chardb and ns.chardb.binds then
        for seq, id in pairs(ns.chardb.binds) do
            if id == itemID then
                seqs = seqs or {}
                seqs[#seqs + 1] = seq
            end
        end
    end
    if seqs then table.sort(seqs) end
    return seqs
end

local function ItemBound(itemID)
    return BindsForItem(itemID) ~= nil
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
    b.bind = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    b.bind:SetPoint("TOPRIGHT", -1, -1)
    b.bind:SetText("B")
    b.bind:SetTextColor(1, 0.82, 0.25)
    b.bind:Hide()
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

local function HideItemTip(ui)
    if ui.tipOwner then
        GameTooltip:Hide()
        ns.SetTipScale(1)
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
    ns.SetTipScale(ns.TIP_SCALE)
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

local function SNum(v)
    if v == nil or ns.IsSecret(v) then return nil end
    return v
end

-- Damage numbers carry buff/percent modifiers; the range shown is the
-- modified one, same as Blizzard's paper doll.
local function DmgParts(lo, hi, pos, neg, pct)
    lo, hi = SNum(lo), SNum(hi)
    if not (lo and hi) then return nil end
    pos, neg, pct = SNum(pos) or 0, SNum(neg) or 0, SNum(pct) or 1
    return (lo + pos - neg) * pct, (hi + pos - neg) * pct
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

-- { header, column, rows }: `column` is an index into ui.statCols for the
-- static groups; the per-weapon groups built on each render store their
-- column frame directly. Row field 3 is the icon function.
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

-- Weapon stat columns: one per weapon type the character actually has,
-- rebuilt on every render so a gear swap or a class with no ranged weapon
-- leaves no stale stats behind. UnitDamage returns main+off hand damage;
-- UnitRangedDamage leads with the ranged attack speed.
local WCOL_W, WCOL_GAP = 190, 24

local function WeaponGroups()
    local groups = {}
    local mh = {
        { "Damage", function()
            if not UnitDamage then return nil end
            local lo, hi, _, _, pos, neg, pct = UnitDamage("player")
            local a, b = DmgParts(lo, hi, pos, neg, pct)
            return a and ("%.0f - %.0f"):format(a, b) or nil
        end, function() return SpellIcon(78) end },
        { "Speed", function()
            if not UnitAttackSpeed then return nil end
            local s = SNum((UnitAttackSpeed("player")))
            return s and ("%.2f"):format(s) or nil
        end, function() return SpellIcon(5171) end },
        { "DPS", function()
            if not (UnitDamage and UnitAttackSpeed) then return nil end
            local lo, hi, _, _, pos, neg, pct = UnitDamage("player")
            local a, b = DmgParts(lo, hi, pos, neg, pct)
            local s = SNum((UnitAttackSpeed("player")))
            if not (a and s and s > 0) then return nil end
            return ("%.1f"):format((a + b) / 2 / s)
        end, function() return SpellIcon(12328) end },
        { "Attack Power", function()
            if not UnitAttackPower then return nil end
            local base, pos, neg = UnitAttackPower("player")
            base = SNum(base)
            if not base then return nil end
            return tostring(base + (SNum(pos) or 0) + (SNum(neg) or 0))
        end, function() return SpellIcon(19506) end },
    }
    groups[#groups + 1] = { "Main Hand", nil, mh }

    -- Off Hand: only a real off-hand weapon produces a second attack
    -- speed or off-hand damage; a shield or a held item does not.
    local ospd = UnitAttackSpeed
        and SNum(select(2, UnitAttackSpeed("player")))
    local _, _, olo, ohi, opos, oneg, opct
    if UnitDamage then _, _, olo, ohi, opos, oneg, opct = UnitDamage("player") end
    local _, odmg = DmgParts(olo, ohi, opos, oneg, opct)
    if (ospd and ospd > 0) or (odmg and odmg > 0) then
        groups[#groups + 1] = { "Off Hand", nil, {
            { "Damage", function()
                if not UnitDamage then return nil end
                local _, _, lo, hi, pos, neg, pct = UnitDamage("player")
                local a, b = DmgParts(lo, hi, pos, neg, pct)
                return a and ("%.0f - %.0f"):format(a, b) or nil
            end, function() return SpellIcon(674) end },
            { "Speed", function()
                if not UnitAttackSpeed then return nil end
                local s = SNum(select(2, UnitAttackSpeed("player")))
                return s and ("%.2f"):format(s) or nil
            end, function() return SpellIcon(5171) end },
            { "DPS", function()
                if not (UnitDamage and UnitAttackSpeed) then return nil end
                local _, _, lo, hi, pos, neg, pct = UnitDamage("player")
                local a, b = DmgParts(lo, hi, pos, neg, pct)
                local s = SNum(select(2, UnitAttackSpeed("player")))
                if not (a and s and s > 0) then return nil end
                return ("%.1f"):format((a + b) / 2 / s)
            end, function() return SpellIcon(12328) end },
        } }
    end

    -- Ranged: a real ranged weapon in slot 18 (wand, bow, thrown — not a
    -- relic), or the API still reporting ranged damage.
    local ranged = false
    local link = GetInventoryItemLink and GetInventoryItemLink("player", 18)
    if link and C_Item and C_Item.GetItemInfoInstant then
        local loc = select(4, C_Item.GetItemInfoInstant(link))
        ranged = loc == "INVTYPE_RANGED" or loc == "INVTYPE_RANGEDRIGHT"
            or loc == "INVTYPE_THROWN"
    end
    if UnitRangedDamage then
        ranged = ranged
            or (SNum(select(3, UnitRangedDamage("player"))) or 0) > 0
    end
    if ranged and UnitRangedDamage then
        groups[#groups + 1] = { "Ranged", nil, {
            { "Damage", function()
                local _, lo, hi, pos, neg, pct = UnitRangedDamage("player")
                local a, b = DmgParts(lo, hi, pos, neg, pct)
                return a and ("%.0f - %.0f"):format(a, b) or nil
            end, function() return SpellIcon(75) end },
            { "Speed", function()
                local s = SNum((UnitRangedDamage("player")))
                return s and ("%.2f"):format(s) or nil
            end, function() return SpellIcon(5171) end },
            { "DPS", function()
                local s, lo, hi, pos, neg, pct = UnitRangedDamage("player")
                s = SNum(s)
                local a, b = DmgParts(lo, hi, pos, neg, pct)
                if not (a and s and s > 0) then return nil end
                return ("%.1f"):format((a + b) / 2 / s)
            end, function() return SpellIcon(12328) end },
            { "Attack Power", function()
                if not UnitRangedAttackPower then return nil end
                local base, pos, neg = UnitRangedAttackPower("player")
                base = SNum(base)
                if not base then return nil end
                return tostring(base + (SNum(pos) or 0) + (SNum(neg) or 0))
            end, function() return SpellIcon(19506) end },
        } }
    end
    return groups
end

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
            label = T.CreateFontString(col, 19, WHITE),
            value = T.CreateFontString(col, 19, WHITE),
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
    if not (cols and ui.weaponCols and ui.weaponStats) then return end

    -- One column per weapon group, packed under the doll and centered in
    -- the span between the gear columns and the right stats column.
    local wgroups = WeaponGroups()
    local n = #wgroups
    local avail = ui.weaponStats:GetWidth()
    if avail <= 0 then avail = n * WCOL_W + (n - 1) * WCOL_GAP end
    local cw = n > 0 and math.min(WCOL_W,
        math.max(80, math.floor((avail - (n - 1) * WCOL_GAP) / n))) or 0
    local total = n * cw + math.max(0, n - 1) * WCOL_GAP
    local x = math.max(0, math.floor((avail - total) / 2))
    local groups = {}
    for _, g in ipairs(STATS) do groups[#groups + 1] = g end
    for i, g in ipairs(wgroups) do
        local c = ui.weaponCols[i]
        if not c then
            c = CreateFrame("Frame", nil, ui.weaponStats)
            ui.weaponCols[i] = c
        end
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", ui.weaponStats, "TOPLEFT", x, 0)
        c:SetSize(cw, 10)
        c:Show()
        g[2] = c
        groups[#groups + 1] = g
        x = x + cw + WCOL_GAP
    end
    for i = n + 1, #ui.weaponCols do ui.weaponCols[i]:Hide() end

    local used, ys = {}, {}
    for _, group in ipairs(groups) do
        local col = group[2]
        if type(col) == "number" then col = cols[col] end
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
                    r.label:SetTextColor(1, 1, 1)
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
    local pools = {}
    for _, col in ipairs(cols) do pools[#pools + 1] = col end
    for _, col in ipairs(ui.weaponCols) do pools[#pools + 1] = col end
    for _, col in ipairs(pools) do
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

-- EquipLoc (from GetItemInfoInstant) -> candidate inventory slot ids.
local INVTYPE_SLOTS = {
    INVTYPE_HEAD = { 1 },
    INVTYPE_NECK = { 2 },
    INVTYPE_SHOULDER = { 3 },
    INVTYPE_BODY = { 4 },
    INVTYPE_CHEST = { 5 },
    INVTYPE_ROBE = { 5 },
    INVTYPE_WAIST = { 6 },
    INVTYPE_LEGS = { 7 },
    INVTYPE_FEET = { 8 },
    INVTYPE_WRIST = { 9 },
    INVTYPE_HAND = { 10 },
    INVTYPE_FINGER = { 11, 12 },
    INVTYPE_TRINKET = { 13, 14 },
    INVTYPE_CLOAK = { 15 },
    INVTYPE_WEAPON = { 16, 17 },
    INVTYPE_2HWEAPON = { 16 },
    INVTYPE_WEAPONMAINHAND = { 16 },
    INVTYPE_WEAPONOFFHAND = { 17 },
    INVTYPE_SHIELD = { 17 },
    INVTYPE_HOLDABLE = { 17 },
    INVTYPE_RANGED = { 18 },
    INVTYPE_RANGEDRIGHT = { 18 },
    INVTYPE_THROWN = { 18 },
    INVTYPE_RELIC = { 18 },
    INVTYPE_TABARD = { 19 },
}

-- An unmet equip requirement (armor type, level, class...) shows up as red
-- text in the item tooltip. C_TooltipInfo gives the same lines without
-- touching the visible GameTooltip.
local function ItemRestricted(bag, slot)
    if not (C_TooltipInfo and C_TooltipInfo.GetBagItem) then
        return false
    end
    local ok, data = pcall(C_TooltipInfo.GetBagItem, bag, slot)
    if not (ok and data and data.lines) then return false end
    for _, line in ipairs(data.lines) do
        for _, col in ipairs({ line.leftColor, line.rightColor }) do
            if col and col.r and col.r > 0.9 and col.g < 0.3 and col.b < 0.3 then
                return true
            end
        end
    end
    return false
end

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
                    if b.bind then
                        if ItemBound(info.itemID) then
                            b.bind:Show()
                        else
                            b.bind:Hide()
                        end
                    end
                else
                    b.icon:SetTexture(nil)
                    b.count:SetText("")
                    QualityBorder(b, nil)
                    if b.bind then b.bind:Hide() end
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
    -- Highlight the equip slot(s) a selected bag item would go into.
    local hits, blocked
    if b and b.bag then
        local info = ItemInfo(b.bag, b.slot)
        local id = info and info.itemID
        if id and C_Item and C_Item.GetItemInfoInstant then
            local equipLoc = select(4, C_Item.GetItemInfoInstant(id))
            hits = equipLoc and INVTYPE_SLOTS[equipLoc]
            if hits then blocked = ItemRestricted(b.bag, b.slot) end
        end
    end
    local hr, hg, hb = 1, 0.82, 0.2
    if blocked then hr, hg, hb = 1, 0.15, 0.1 end
    for _, eb in ipairs(ui.equipCells or {}) do
        if eb.eqHl then
            local show = hits ~= nil
            if show then
                show = false
                for _, sid in ipairs(hits) do
                    if sid == eb.slotID then
                        show = true
                        break
                    end
                end
            end
            if show then eb.eqHl:SetColorTexture(hr, hg, hb, 0.45) end
            eb.eqHl:SetShown(show)
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

local function CloseOnUseCast(_, unit)
    local ui = ns.invUI
    if unit ~= "player" or not (ui and ui.useAt) then return end
    if GetTime() - ui.useAt > USE_CAST_WINDOW then return end
    ui.useAt = nil
    ns:Close()
end
Nocturne.RegisterEvent("UNIT_SPELLCAST_START", CloseOnUseCast)
Nocturne.RegisterEvent("UNIT_SPELLCAST_CHANNEL_START", CloseOnUseCast)

-- Item use is a protected call, so X cannot touch the bag directly. A
-- hidden secure button carries the action instead, driven by a real
-- override-binding click on PAD3 (secure execution context).
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

-- Pad actions: A moves (picks up / drops on the cursor), X uses or equips
-- (unequips on the doll), Y opens the "More" menu, B destroys.
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

local function PadMove(ui)
    local b = ui.selected
    if not b then return end
    if ui.focus == 1 then
        if b.bag and C_Container.PickupContainerItem then
            C_Container.PickupContainerItem(b.bag, b.slot)
        end
    elseif b.slotID and _G.PickupInventoryItem then
        PickupInventoryItem(b.slotID)
    end
end

local function PadDestroy(ui)
    local b = ui.selected
    if not b then return false end
    local name, destroy
    if ui.focus == 1 then
        if not b.bag then return false end
        local info = C_Container.GetContainerItemInfo(b.bag, b.slot)
        if not info or not info.itemID then return false end
        name = info.itemName
            or (GetItemInfo and GetItemInfo(info.itemID)) or "item"
        destroy = function()
            C_Container.PickupContainerItem(b.bag, b.slot)
            if DeleteCursorItem then DeleteCursorItem() end
        end
    else
        if not b.link then return false end
        name = (C_Item and C_Item.GetItemNameByID
                and C_Item.GetItemNameByID(b.link))
            or (GetItemInfo and GetItemInfo(b.link)) or "item"
        destroy = function()
            PickupInventoryItem(b.slotID)
            if DeleteCursorItem then DeleteCursorItem() end
        end
    end
    ns:ShowConfirm(("Destroy \"%s\"?"):format(name), nil, "Destroy", destroy)
    return true
end

-- Small in-page dialogs (split stepper, bind capture) swallow all pad input
-- through ns.padCapture and drop PadBind so every key reaches the capture.
local function CloseDlg(ui)
    ns.padCapture = nil
    ui.dlgOpen = nil
    ui.split = nil
    ui.bindCap = nil
    if ui.dlg then ui.dlg:Hide() end
    ns:UpdatePadMode()
end

local function FitDlg(d)
    ns:FitDialog(d)
end

local function OpenDlg(ui, title, hint)
    local d = ui.dlg
    d.title:SetText(title)
    d.body:SetText("")
    d.err:SetText("")
    d.hint:SetText(hint or "")
    d.content:Hide()
    d.body:Show()
    ui.dlgOpen = true
    d:Show()
    FitDlg(d)
    ns:UpdatePadMode()
end

-- Character model state: yaw, camera distance scale (zoom) and a pan offset
-- in the frame. The right stick drives it, R3 resets it.
local PAN_MAX = 1.5

local function ApplyModel(ui)
    local m = ui.model
    if not m then return end
    if m.SetFacing then m:SetFacing(ui.modelYaw) end
    pcall(function()
        local depth = 0
        if m.SetCamDistanceScale then
            m:SetCamDistanceScale(ui.modelZoom)
        else
            depth = 1 - ui.modelZoom
        end
        if m.SetPosition then
            m:SetPosition(depth, ui.modelPanX, ui.modelPanY)
        end
    end)
end

local function ResetModel(ui)
    ui.modelYaw, ui.modelZoom, ui.modelPanX, ui.modelPanY = 0, 1, 0, 0
    ApplyModel(ui)
end

-- PlayerModel keeps showing the old gear until told to re-read the unit
-- (Blizzard's paper doll does this on UNIT_MODEL_CHANGED). The refresh is
-- deferred while the page is hidden and applied from OnShow.
local function RefreshModel(ui)
    local m = ui.model
    if not m then return end
    ui.modelDirty = nil
    if m.RefreshUnit then
        pcall(m.RefreshUnit, m)
    else
        pcall(m.SetUnit, m, "player")
    end
    ApplyModel(ui)
end

local function MarkModelDirty()
    local ui = ns.invUI
    if not (ui and ui.model) then return end
    ui.modelDirty = true
    if ns.pageFrames[3] and ns.pageFrames[3]:IsShown() then RefreshModel(ui) end
end
Nocturne.RegisterEvent("PLAYER_EQUIPMENT_CHANGED", MarkModelDirty)
Nocturne.RegisterEvent("UNIT_MODEL_CHANGED", function(_, unit)
    if unit == "player" then MarkModelDirty() end
end)

-- Dialog option rows: a highlighted row per option in the dialog's content
-- frame (it replaces the body text).
local MENU_FONT, MENU_ROW_H, MENU_GAP, MENU_PAD = 20, 32, 10, 16

-- Rows show `texts`; all share the width of the widest of `texts`/`probe`.
local function ShowRows(ui, texts, probe)
    local menu = ui.dlg.content
    ui.dlg.body:Hide()
    menu:Show()
    local width = 0
    for i, text in ipairs(texts) do
        local row = menu.rows[i]
        if not row then
            row = CreateFrame("Frame", nil, menu)
            row.hl = row:CreateTexture(nil, "BACKGROUND")
            row.hl:SetAllPoints()
            local a = T.colors.accent
            row.hl:SetColorTexture(a[1], a[2], a[3], 0.35)
            row.label = T.CreateFontString(row, MENU_FONT, TEXT)
            row.label:SetPoint("CENTER")
            menu.rows[i] = row
        end
        row.label:SetText(text)
        width = math.max(width, row.label:GetStringWidth())
    end
    for _, text in ipairs(probe or {}) do
        menu.rows[1].label:SetText(text)
        width = math.max(width, menu.rows[1].label:GetStringWidth())
    end
    menu.rows[1].label:SetText(texts[1])
    for i = #texts + 1, #menu.rows do menu.rows[i]:Hide() end
    width = width + 2 * MENU_PAD
    for i = 1, #texts do
        local row = menu.rows[i]
        row:SetSize(width, MENU_ROW_H)
        row:ClearAllPoints()
        row:SetPoint("TOP", menu, "TOP", 0, -(i - 1) * (MENU_ROW_H + MENU_GAP))
        row:Show()
    end
    menu:SetSize(width, #texts * MENU_ROW_H + (#texts - 1) * MENU_GAP)
    return menu
end

-- Button bar hints: D-pad glyphs + `dpad` label, A `a`, B `b`.
local function PadHint(dpad, a, b)
    local G = ns.PadGlyph
    return ("%s%s %s      %s %s      %s %s"):format(
        G("PADDUP", "Up"), G("PADDDOWN", "Down"), dpad,
        G("PAD1", "A"), a, G("PAD2", "B"), b)
end

local function OpenSplitDlg(ui)
    local b = ui.selected
    local info = b and b.bag and ItemInfo(b.bag, b.slot)
    if not (info and info.stackCount and info.stackCount > 1) then return end
    if not C_Container.SplitContainerItem then return end
    local name = info.itemName
        or (GetItemInfo and GetItemInfo(info.itemID)) or "item"
    ui.split = { bag = b.bag, slot = b.slot, max = info.stackCount, n = 1 }
    OpenDlg(ui, "Split " .. name, PadHint("Amount", "Split", "Cancel"))
    local max = ui.split.max
    local row = ShowRows(ui, { "1 / " .. max }, { max .. " / " .. max }).rows[1]
    row.hl:Show()
    local function Body()
        row.label:SetText(("%d / %d"):format(ui.split.n, max))
        FitDlg(ui.dlg)
    end
    Body()
    ns.padCapture = function(btn, down)
        local s = ui.split
        if not (down and s) then return end
        if s.placing then
            if btn == "PAD1" then
                local c = ui.selected
                if c and c.bag and not ItemInfo(c.bag, c.slot) then
                    C_Container.PickupContainerItem(c.bag, c.slot)
                    ns:InventoryRefresh()
                    CloseDlg(ui)
                else
                    ui.dlg.err:SetText("Pick an empty slot")
                    FitDlg(ui.dlg)
                end
                return
            elseif btn == "PAD2" or btn == "PADBACK" then
                -- Cancel: drop the cursor into the first empty slot.
                for _, bag in ipairs(BagIDs()) do
                    local n = C_Container.GetContainerNumSlots
                        and C_Container.GetContainerNumSlots(bag) or 0
                    for slot = 1, n do
                        if not ItemInfo(bag, slot) then
                            C_Container.PickupContainerItem(bag, slot)
                            s.placed = true
                            break
                        end
                    end
                    if s.placed then break end
                end
                ns:InventoryRefresh()
                CloseDlg(ui)
                return
            end
            if btn == "PADDUP" then
                MoveInvSelection(ui, 0, -1)
            elseif btn == "PADDDOWN" then
                MoveInvSelection(ui, 0, 1)
            elseif btn == "PADDLEFT" then
                MoveInvSelection(ui, -1, 0)
            elseif btn == "PADDRIGHT" then
                MoveInvSelection(ui, 1, 0)
            end
            return
        end
        if btn == "PADDLEFT" then
            s.n = math.max(1, s.n - 1)
        elseif btn == "PADDRIGHT" then
            s.n = math.min(s.max - 1, s.n + 1)
        elseif btn == "PADDDOWN" then
            s.n = math.max(1, s.n - 5)
        elseif btn == "PADDUP" then
            s.n = math.min(s.max - 1, s.n + 5)
        elseif btn == "PAD1" then
            C_Container.SplitContainerItem(s.bag, s.slot, s.n)
            s.placing = true
            ui.dlg.title:SetText("Place split stack")
            ui.dlg.content:Hide()
            ui.dlg.body:Show()
            ui.dlg.body:SetText("Move to an empty slot")
            ui.dlg.err:SetText("")
            ui.dlg.hint:SetText(PadHint("Choose slot", "Place", "Auto"))
            FitDlg(ui.dlg)
            return
        elseif btn == "PAD2" or btn == "PADBACK" then
            CloseDlg(ui)
            return
        else
            return
        end
        Body()
    end
end

-- Binds a usable item to a pad sequence while the journal is open: either a
-- single free key (paddles, PAD5/6...) or LT/RT modifier(s) + one button
-- ("PADLTRIGGER-PAD3", "PADLTRIGGER-PADRTRIGGER-PAD3").
local BIND_MODS = {
    PADLTRIGGER = true,
    PADRTRIGGER = true,
}
local BIND_RESERVED = {
    PAD1 = true,
    PAD2 = true,
    PAD3 = true,
    PAD4 = true,
    PADDUP = true,
    PADDDOWN = true,
    PADDLEFT = true,
    PADDRIGHT = true,
    PADBACK = true,
    PADLSTICK = true,
    PADRSTICK = true,
}

local function ItemUsable(info)
    local id = info and info.itemID
    if not id then return false end
    if IsEquippableItem and IsEquippableItem(id) then return true end
    -- Items with a "Use:" effect expose it through GetItemSpell.
    local getSpell = (C_Item and C_Item.GetItemSpell) or GetItemSpell
    if getSpell and getSpell(id) then return true end
    if IsUsableItem then
        local ok, usable = pcall(IsUsableItem, id)
        if ok and usable then return true end
    end
    return false
end

-- Canonical chord string: modifiers sorted (the binding system builds them
-- in a fixed order, so "RT-LT-X" never matches the pressed chord).
local function CanonBindKey(seq)
    if #seq == 1 then return seq[1] end
    local mods = {}
    for i = 1, #seq - 1 do mods[#mods + 1] = seq[i] end
    table.sort(mods)
    mods[#mods + 1] = seq[#seq]
    return table.concat(mods, "-")
end

local function SeqBindKey(seq)
    if #seq == 1 then
        local k = seq[1]
        if BIND_MODS[k] then return nil, "a modifier alone can't be bound" end
        if BIND_RESERVED[k] then
            return nil, k .. " is used by the journal"
        end
        return k
    end
    if #seq > 3 or BIND_MODS[seq[#seq]] then
        return nil, "sequence must end with a button"
    end
    for i = 1, #seq - 1 do
        if not BIND_MODS[seq[i]] then
            return nil, "only LT and RT can be modifiers"
        end
        if seq[i] == seq[#seq] then return nil, "duplicate key" end
    end
    if #seq == 3 and seq[1] == seq[2] then return nil, "duplicate key" end
    return CanonBindKey(seq)
end

local GamepadBarSlot, SeqGlyphs = ns.GamepadBarSlot, ns.SeqGlyphs

local function PlaceOnGamepadBar(seq, itemID)
    local util = _G.GamepadActionBarBindingUtil
    local slot = util and GamepadBarSlot(seq)
    if not slot then return nil end
    local ok = util.AssignActionToGamepadStandardSlot(slot, function(id)
        if C_Item and C_Item.PickupItem then
            C_Item.PickupItem(id)
        elseif PickupItem then
            PickupItem(id)
        end
    end, itemID)
    return ok and slot or nil
end

local function ClearOnGamepadBar(seq, itemID)
    local util = _G.GamepadActionBarBindingUtil
    local slot = util and util.ClearActionFromGamepadSlot
        and GamepadBarSlot(seq)
    if not slot then return end
    local t, id = GetActionInfo(slot)
    if t == "item" and id == itemID then
        util.ClearActionFromGamepadSlot(slot)
    end
end


local function UnbindItem(ui, itemID, name)
    local removed = 0
    for seq, id in pairs(ns.chardb.binds) do
        if id == itemID then
            ns.chardb.binds[seq] = nil
            ClearOnGamepadBar(seq, id)
            removed = removed + 1
        end
    end
    ns:ReapplyItemBinds()
    RenderBags(ui)
    if removed > 0 then
        Nocturne.Print(("Unbound %s (%d bind%s)."):format(
            name, removed, removed == 1 and "" or "s"))
    else
        Nocturne.Print(("%s has no binds."):format(name))
    end
end

local function OpenBindDlg(ui)
    local b = ui.selected
    local info = b and b.bag and ItemInfo(b.bag, b.slot)
    if not ItemUsable(info) then return end
    if not (ns.chardb and ns.chardb.binds) then return end
    local name = info.itemName
        or (GetItemInfo and GetItemInfo(info.itemID)) or "item"
    local itemID = info.itemID
    local function Body(extra)
        local d = ns.seqDlg
        local lines = {}
        local cur = BindsForItem(itemID)
        if cur then
            local g = {}
            for _, s in ipairs(cur) do g[#g + 1] = SeqGlyphs(s) end
            lines[#lines + 1] = "current: " .. table.concat(g, "   ")
        end
        lines[#lines + 1] = extra or "Hold LT/RT + key to bind"
        d.body:SetText(table.concat(lines, "\n"))
        ns:FitDialog(d)
    end
    ui.dlgOpen = true
    ns:OpenSeqBind {
        title = "Bind " .. name,
        tip = function(d)
            ns.TipRight(d)
            if info.hyperlink then
                GameTooltip:SetHyperlink(info.hyperlink)
            else
                pcall(GameTooltip.SetItemByID, GameTooltip, itemID)
            end
            ns.SetTipScale(ns.TIP_SCALE)
            GameTooltip:Show()
        end,
        onLive = function(seq)
            local g = {}
            for _, s in ipairs(seq) do
                g[#g + 1] = ns.PadGlyph(s, s:gsub("^PAD", ""))
            end
            Body(table.concat(g, " + "))
        end,
        onSeq = function(seq)
            local key, err = SeqBindKey(seq)
            if not key then return "Invalid: " .. err end
            -- One bind per item: drop the item's previous seqs (and their
            -- bar slots) before storing the new one.
            for s, id in pairs(ns.chardb.binds) do
                if id == itemID and s ~= key then
                    ns.chardb.binds[s] = nil
                    ClearOnGamepadBar(s, id)
                end
            end
            ns.chardb.binds[key] = itemID
            ns:ReapplyItemBinds()
            RenderBags(ui)
            if PlaceOnGamepadBar(key, itemID) then
                Nocturne.Print(("Bound %s to %s (also on action bar).")
                    :format(name, key))
            else
                Nocturne.Print(("Bound %s to %s."):format(name, key))
            end
            return nil
        end,
        onClose = function() ui.dlgOpen = nil end,
    }
    Body()
end

local function ConfirmUnbind(ui)
    local b = ui.selected
    local info = b and b.bag and ItemInfo(b.bag, b.slot)
    local itemID = info and info.itemID
    local seqs = itemID and BindsForItem(itemID)
    if not seqs then return end
    local name = info.itemName
        or (GetItemInfo and GetItemInfo(itemID)) or "item"
    local g = {}
    for _, s in ipairs(seqs) do
        g[#g + 1] = SeqGlyphs(s)
    end
    ns:ShowConfirm("Unbind " .. name, table.concat(g, "   "), "Unbind",
        function()
            UnbindItem(ui, itemID, name)
        end)
end

-- Y menu: actions that depend on the selected bag item.
local function MoreOptions(ui)
    local b = ui.selected
    local info = ui.focus == 1 and b and b.bag and ItemInfo(b.bag, b.slot)
    if not info then return nil end
    local opts
    if info.stackCount and info.stackCount > 1
        and C_Container.SplitContainerItem then
        opts = { { "Split", OpenSplitDlg } }
    end
    if ItemUsable(info) and ns.chardb and ns.chardb.binds then
        opts = opts or {}
        if ItemBound(info.itemID) then
            opts[#opts + 1] = { "Unbind", ConfirmUnbind }
        else
            opts[#opts + 1] = { "Bind", OpenBindDlg }
        end
    end
    return opts
end

local function OpenMoreMenu(ui)
    local opts = MoreOptions(ui)
    if not opts then return end
    local b = ui.selected
    local info = ItemInfo(b.bag, b.slot)
    local name = info.itemName
        or (GetItemInfo and GetItemInfo(info.itemID)) or "item"
    local sel = 1
    OpenDlg(ui, name, PadHint("Select", "OK", "Cancel"))
    local texts = {}
    for i, o in ipairs(opts) do texts[i] = o[1] end
    local menu = ShowRows(ui, texts)
    local function Body()
        for i = 1, #opts do menu.rows[i].hl:SetShown(i == sel) end
        FitDlg(ui.dlg)
    end
    Body()
    ns.padCapture = function(btn, down)
        if not down then return end
        if btn == "PADDUP" then
            sel = sel > 1 and sel - 1 or #opts
        elseif btn == "PADDDOWN" then
            sel = sel < #opts and sel + 1 or 1
        elseif btn == "PAD1" then
            local fn = opts[sel][2]
            CloseDlg(ui)
            fn(ui)
            return
        elseif btn == "PAD2" or btn == "PADBACK" then
            CloseDlg(ui)
            return
        else
            return
        end
        Body()
    end
end

local function EnsureBindButton(ui, i)
    ui.bindBtns = ui.bindBtns or {}
    if ui.bindBtns[i] then return ui.bindBtns[i] end
    if InCombatLockdown and InCombatLockdown() then return nil end
    local ok, b = pcall(CreateFrame, "Button",
        "NocturneJournalPadBind" .. i, UIParent, "SecureActionButtonTemplate")
    if not ok or not b then return nil end
    b:SetSize(1, 1)
    b:SetAlpha(0)
    b:EnableMouse(false)
    b:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", i * 2, 0)
    b:RegisterForClicks("AnyUp")
    b:SetAttribute("type", "item")
    b:SetAttribute("useOnKeyDown", false)
    b:HookScript("OnClick", function()
        ui.useAt = GetTime()
        ns.bindClicks = (ns.bindClicks or 0) + 1
    end)
    ui.bindBtns[i] = b
    return b
end

-- Called by the shell whenever the journal is (re)shown: creates one secure
-- use-button per stored seq and override-binds the seq to click it.
function ns.invApplyBinds(owner)
    local ui = ns.invUI
    if not (ui and ns.chardb and ns.chardb.binds) then return end
    if InCombatLockdown and InCombatLockdown() then return end
    -- Rewrite stored seqs canonically once so the key used for the binding
    -- and the key shown in diag always match.
    local binds, norm, dirty = ns.chardb.binds, {}, false
    for seq, itemID in pairs(binds) do
        local parts = {}
        for k in seq:gmatch("[^-]+") do parts[#parts + 1] = k end
        local canon = CanonBindKey(parts)
        norm[canon] = itemID
        if canon ~= seq then dirty = true end
    end
    if dirty then
        wipe(binds)
        for k, v in pairs(norm) do binds[k] = v end
    end
    ui.bindBtnFor = wipe(ui.bindBtnFor or {})
    local i = 0
    for seq, itemID in pairs(binds) do
        i = i + 1
        local b = EnsureBindButton(ui, i)
        if not b then return end
        b:SetAttribute("item", "item:" .. itemID)
        ui.bindBtnFor[seq] = b
        -- Only plain keys get a static binding; chord seqs are re-mapped
        -- dynamically while their modifiers are held (see UpdateChordBinds).
        if not seq:find("-", 1, true) then
            pcall(SetOverrideBindingClick, owner, true,
                seq, b:GetName(), "LeftButton")
        end
    end
    -- Once per session mirror stored binds onto the native action bars so
    -- chords keep working with the journal closed. Skipped while the cursor
    -- holds something (AssignAction clears it).
    if not ns.barsMigrated and not (GetCursorInfo and GetCursorInfo()) then
        ns.barsMigrated = true
        for seq, itemID in pairs(binds) do
            PlaceOnGamepadBar(seq, itemID)
        end
    end
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
        Set(ui.legendA, nil)
        Set(ui.legendX, nil)
        Set(ui.legendY, nil)
        Set(ui.legendB, nil)
    elseif ui.focus == 1 then
        Set(ui.legendA, "Move")
        Set(ui.legendX, "Use")
        Set(ui.legendY, MoreOptions(ui) and "More" or nil)
        Set(ui.legendB, "Destroy")
    else
        Set(ui.legendA, "Move")
        Set(ui.legendX, "Unequip")
        Set(ui.legendY, nil)
        Set(ui.legendB, "Destroy")
    end
    Set(ui.legendR3, "Reset model")
    -- Visible entries pack against the right edge (right to left); Navigate
    -- hugs the leftmost one.
    local last
    for _, e in ipairs({ ui.legendA, ui.legendX, ui.legendY, ui.legendB,
        ui.legendR3 }) do
        if e.glyph:IsShown() then
            e.label:ClearAllPoints()
            if last then
                e.label:SetPoint("RIGHT", last.glyph, "LEFT", -26, 0)
            else
                e.label:SetPoint("BOTTOMRIGHT", ui.legend, "BOTTOMRIGHT")
            end
            last = e
        end
    end
    local nav = ui.legendNav
    nav:ClearAllPoints()
    if last then
        nav:SetPoint("RIGHT", last.glyph, "LEFT", -26, 0)
    else
        nav:SetPoint("BOTTOMRIGHT", ui.legend, "BOTTOMRIGHT")
    end
end

ns.RegisterPage(3, {
    key = "inventory",
    title = "Inventory",
    subPages = function() return { "Bags", "Equipped" } end,
    ownSubBar = true,
    PadBind = function()
        local ui = ns.invUI
        return ui and ui.focus == 1 and ui.useBtn ~= nil and not ui.dlgOpen
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

        local bags = CreateFrame("Frame", nil, f)
        bags:SetPoint("TOPLEFT", MARGIN, -MARGIN - 44)
        bags:SetPoint("BOTTOMLEFT", MARGIN, MARGIN)
        local equip = CreateFrame("Frame", nil, f)
        equip:SetPoint("TOPRIGHT", -MARGIN, -MARGIN - 44)
        equip:SetPoint("BOTTOMRIGHT", -MARGIN, MARGIN)
        equip:SetPoint("LEFT", bags, "RIGHT", GAP, 0)

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

        -- Weapon stats: a row of per-weapon columns under the doll, in the
        -- same span as the model (gear columns .. right stats column).
        local wstats = CreateFrame("Frame", nil, equip)
        ui.weaponStats = wstats
        ui.weaponCols = {}
        wstats:SetHeight(130)
        wstats:SetPoint("BOTTOM", equip, "BOTTOM", 0, PAD)
        wstats:SetPoint("LEFT", equip, "LEFT", PAD + 2 * EQ_CELL + 56, 0)
        wstats:SetPoint("RIGHT", equip, "RIGHT", -PAD - STATS_W - 16, 0)

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
            ui.modelYaw, ui.modelZoom, ui.modelPanX, ui.modelPanY = 0, 1, 0, 0
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
            b.eqHl = b:CreateTexture(nil, "OVERLAY", nil, 3)
            b.eqHl:SetPoint("TOPLEFT", -4, 4)
            b.eqHl:SetPoint("BOTTOMRIGHT", 4, -4)
            b.eqHl:SetColorTexture(1, 0.82, 0.2, 0.45)
            b.eqHl:SetBlendMode("ADD")
            b.eqHl:Hide()
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
        local function LegendEntry(pad, prev, fb)
            local label = T.CreateFontString(legend, 15, TEXT)
            local glyph = T.CreateFontString(legend, 15, T.colors.accent)
            glyph:SetText(ns.PadGlyph(pad, fb or pad))
            if prev then
                label:SetPoint("RIGHT", prev.glyph, "LEFT", -26, 0)
            else
                label:SetPoint("BOTTOMRIGHT", legend, "BOTTOMRIGHT")
            end
            glyph:SetPoint("RIGHT", label, "LEFT", -6, 0)
            return { label = label, glyph = glyph }
        end
        ui.legendA = LegendEntry("PAD1")
        ui.legendX = LegendEntry("PAD3", ui.legendA)
        ui.legendY = LegendEntry("PAD4", ui.legendX)
        ui.legendB = LegendEntry("PAD2", ui.legendY)
        ui.legendR3 = LegendEntry("PADRSTICK", ui.legendB, "R3")
        ui.legend = legend

        -- Shared small dialog for the split stepper and the bind capture.
        local dlg = CreateFrame("Frame", nil, f)
        ui.dlg = dlg
        dlg:SetSize(430, 170)
        dlg:SetPoint("CENTER", f, "CENTER")
        dlg:SetFrameLevel(f:GetFrameLevel() + 60)
        T.ApplyBackdrop(dlg)
        -- Dialog layout: 16px padding all around; title, body, then the
        -- bottom button bar, each section 16px apart; errors sit in the
        -- body 8px under the active element. Size wraps the content.
        dlg.title = T.CreateFontString(dlg, 17, TEXT)
        dlg.title:SetPoint("TOP", 0, -16)
        -- Button bar: input hints (and later real buttons for
        -- mouse/keyboard) live here, right-aligned.
        dlg.hint = T.CreateFontString(dlg, 13, DIM_COLOR)
        dlg.hint:SetPoint("BOTTOMRIGHT", -16, 16)
        dlg.hint:SetJustifyH("RIGHT")
        dlg.body = T.CreateFontString(dlg, 15, TEXT)
        dlg.body:SetPoint("TOP", dlg.title, "BOTTOM", 0, -16)
        -- Optional body replacement (More menu rows), sized by its owner.
        dlg.content = CreateFrame("Frame", nil, dlg)
        dlg.content:SetPoint("TOP", dlg.title, "BOTTOM", 0, -16)
        dlg.content.rows = {}
        dlg.content:Hide()
        dlg.err = T.CreateFontString(dlg, 14, { 0.92, 0.30, 0.25, 1 })
        dlg.err:SetPoint("TOP", dlg.body, "BOTTOM", 0, -8)
        dlg:Hide()
        local nav = T.CreateFontString(legend, 15, TEXT)
        ui.legendNav = nav
        local up = ns.PadGlyph("PADDUP")
        local down = ns.PadGlyph("PADDDOWN")
        local dpad = (up and up:find("|") and down and down:find("|"))
            and (up .. down) or "D-Pad"
        nav:SetText(dpad .. "  Navigate")
        nav:SetPoint("RIGHT", ui.legendR3.glyph, "LEFT", -26, 0)
        local view = T.CreateFontString(legend, 15, TEXT)
        ui.legendView = view
        -- Direction glyphs come from the binding text of the stick axes;
        -- without icons for them, fall back to plain "R Stick".
        local function Axes(a, b)
            local ga = ns.PadGlyph(a, "")
            local gb = ns.PadGlyph(b, "")
            if ga:find("|") and gb:find("|") then return ga .. gb end
        end
        local lr = Axes("PADRSTICKLEFT", "PADRSTICKRIGHT")
        local ud = Axes("PADRSTICKUP", "PADRSTICKDOWN")
        local rt = ns.PadGlyph("PADRTRIGGER", "RT")
        if lr and ud then
            view:SetText(("%s  Rotate      %s  Zoom      %s + %s%s  Move")
                :format(lr, ud, rt, lr, ud))
        else
            view:SetText(("R Stick  Rotate / Zoom      %s + R Stick  Move")
                :format(rt))
        end
        view:SetPoint("RIGHT", nav, "LEFT", -26, 0)

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
        if ui and ui.modelDirty then RefreshModel(ui) end
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
        if button == "PADRSTICK" then
            ResetModel(ui)
        elseif button == "PAD1" then
            PadMove(ui)
        elseif button == "PAD3" then
            PadUse(ui)
        elseif button == "PAD4" then
            OpenMoreMenu(ui)
        end
    end,
    OnCancel = function()
        local ui = ns.invUI
        return ui and PadDestroy(ui) or false
    end,
    OnPadUp = function(f, button)
        local ui = ns.invUI
        if ui and ui.dpadHold then ui.dpadHold[button] = nil end
    end,
    OnStick = function(f, stick, x, y, dt)
        local ui = ns.invUI
        if not (ui and ui.model) then return end
        local name = stick or ""
        if not (name:find("Right") or name:find("Camera")
                or name == "PADRSTICK") then
            return
        end
        x, y = StickAxis(x), StickAxis(y)
        if x == 0 and y == 0 then return end
        local step = (dt or 0.05) * 0.6
        if ns.IsPadHeld("PADRTRIGGER") then
            -- RT is a modifier here, not the sub-page switch.
            ns.trigUsed.PADRTRIGGER = true
            ui.modelPanX = math.max(-PAN_MAX, math.min(PAN_MAX,
                ui.modelPanX + x * step))
            ui.modelPanY = math.max(-PAN_MAX, math.min(PAN_MAX,
                ui.modelPanY + y * step))
        else
            ui.modelYaw = ui.modelYaw + x * step * 2
            ui.modelZoom = math.max(0.4, math.min(3,
                ui.modelZoom - y * step))
        end
        ApplyModel(ui)
    end,
    OnHide = function()
        local ui = ns.invUI
        if ui and ui.dpadHold then wipe(ui.dpadHold) end
        if ui then HideItemTip(ui) end
        ns.padCapture = nil
        if ui then
            ui.dlgOpen, ui.split, ui.bindCap = nil, nil, nil
            if ui.dlg then ui.dlg:Hide() end
        end
    end,
})
