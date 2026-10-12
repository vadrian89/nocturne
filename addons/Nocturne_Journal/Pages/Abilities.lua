local _, ns = ...

local Nocturne = _G.Nocturne
local T = Nocturne.Theme

local PANEL = ns.JournalPanel
local MARGIN, GAP = ns.JournalMargin, ns.JournalGap

-- Readable on both the spellbook atlas and the dark fallback.
local TEXT = { 0.95, 0.95, 0.97, 1 }
local HEADER_COLOR = { 0.80, 0.68, 0.42, 1 }
local DIM_COLOR = { 0.60, 0.60, 0.65, 1 }
local FUTURE_COLOR = { 0.45, 0.45, 0.52, 1 }

local BANK_PLAYER = Enum and Enum.SpellBookSpellBank
    and Enum.SpellBookSpellBank.Player or 0
local BANK_PET = Enum and Enum.SpellBookSpellBank
    and Enum.SpellBookSpellBank.Pet or 1
local IT = Enum and Enum.SpellBookItemType or {
    None = 0,
    Spell = 1,
    FutureSpell = 2,
    PetAction = 3,
    Flyout = 4
}

-- Book geometry: inner padding of a page, its header (category title and
-- the LT/RT leaf hints) and footer (page number), and one grid cell.
local PAD = 40
local HEADER_H, FOOTER_H = 40, 24
local CELL_W, CELL_H = 250, 66
local ROW_GAP = 10
local ICON = 40

-- One section per visible skill line, plus "Pet" when the pet has spells.
-- The first line is the general one; it shows the race icon.
local function Sections()
    local secs = {}
    if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines then
        for i = 1, C_SpellBook.GetNumSpellBookSkillLines() do
            local info = C_SpellBook.GetSpellBookSkillLineInfo(i)
            if info and not info.shouldHide then
                secs[#secs + 1] = {
                    name = info.name or ("Tab " .. i),
                    skillLine = i,
                    icon = info.iconID,
                    general = i == 1,
                }
            end
        end
        if C_SpellBook.HasPetSpells and C_SpellBook.HasPetSpells() then
            secs[#secs + 1] = { name = PET or "Pet", pet = true }
        end
    end
    return secs
end

local function BuildItems(sec)
    local items = {}
    if not (sec and C_SpellBook and C_SpellBook.GetSpellBookItemInfo) then
        return items
    end
    if sec.pet then
        local n = C_SpellBook.HasPetSpells and C_SpellBook.HasPetSpells()
        for slot = 1, n or 0 do
            local info = C_SpellBook.GetSpellBookItemInfo(slot, BANK_PET)
            if info and info.itemType ~= IT.None and info.name ~= "" then
                items[#items + 1] = { slot = slot, bank = BANK_PET, info = info }
            end
        end
        return items
    end
    local line = C_SpellBook.GetSpellBookSkillLineInfo(sec.skillLine)
    if not line then return items end
    local last = line.itemIndexOffset + line.numSpellBookItems
    for slot = line.itemIndexOffset + 1, last do
        local info = C_SpellBook.GetSpellBookItemInfo(slot, BANK_PLAYER)
        if info and info.itemType ~= IT.None and info.name ~= "" then
            items[#items + 1] = { slot = slot, bank = BANK_PLAYER, info = info }
        end
    end
    return items
end

-- Race icon for the general section. *(Unverified)* atlas names: the
-- character-create race icons, keyed by the lowercased UnitRace token.
local RACE_ATLAS_TOKEN = {
    Scourge = "undead",
    HighmountainTauren = "highmountain",
    LightforgedDraenei = "lightforged",
    ZandalariTroll = "zandalari",
    MagharOrc = "maghar",
}
local function RaceAtlas()
    local _, token = UnitRace("player")
    if not token then return nil end
    local race = RACE_ATLAS_TOKEN[token] or token:lower()
    local sex = UnitSex("player") == 3 and "female" or "male"
    return Nocturne.FirstAtlas(
        ("raceicon128-%s-%s"):format(race, sex),
        ("raceicon-%s-%s"):format(race, sex))
end

local function SetSectionIcon(tex, sec)
    tex:SetTexCoord(0, 1, 0, 1)
    local atlas = sec.general and RaceAtlas()
    if atlas then
        tex:SetAtlas(atlas)
    elseif sec.pet then
        SetPortraitTexture(tex, "pet")
    elseif sec.icon then
        tex:SetTexture(sec.icon)
        tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    else
        tex:SetTexture(nil)
    end
end

-- Key sequences that cast a spell, by spell ID and by name (Forever's bars
-- may hold another rank of the spellbook spell). Forever's native gamepad
-- bars map modifier state + button to a storage slot (ns.GamepadBarSlot);
-- elsewhere the standard action buttons and their key bindings are used.
local GAMEPAD_MODS = { "", "PADLTRIGGER-", "PADRTRIGGER-",
    "PADLTRIGGER-PADRTRIGGER-" }
-- Action slot ranges of the standard bars and their binding commands.
local SLOT_COMMANDS = {
    { 1,   12,  "ACTIONBUTTON" },
    { 25,  36,  "MULTIACTIONBAR3BUTTON" },
    { 37,  48,  "MULTIACTIONBAR4BUTTON" },
    { 49,  60,  "MULTIACTIONBAR2BUTTON" },
    { 61,  72,  "MULTIACTIONBAR1BUTTON" },
    { 145, 156, "MULTIACTIONBAR5BUTTON" },
    { 157, 168, "MULTIACTIONBAR6BUTTON" },
    { 169, 180, "MULTIACTIONBAR7BUTTON" },
}

local function SpellName(id)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
    return GetSpellInfo and (GetSpellInfo(id))
end

local function BuildBindMap(ui)
    local byID, byName = {}, {}
    ui.binds = { byID = byID, byName = byName }
    if not ns.GamepadBarSlot then return end
    for _, mod in ipairs(GAMEPAD_MODS) do
        for key in pairs(ns.GamepadBarButtons) do
            local seq = mod .. key
            local slot = ns.GamepadBarSlot(seq)
            local kind, id = nil, nil
            if slot then kind, id = GetActionInfo(slot) end
            if kind == "spell" and id and not byID[id] then
                byID[id] = seq
                local name = SpellName(id)
                if name and not byName[name] then byName[name] = seq end
            end
        end
    end
end

local function StandardBinding(id)
    if not (C_ActionBar and C_ActionBar.FindSpellActionButtons) then
        return nil
    end
    for _, slot in ipairs(C_ActionBar.FindSpellActionButtons(id) or {}) do
        for _, r in ipairs(SLOT_COMMANDS) do
            if slot >= r[1] and slot <= r[2] then
                local key = GetBindingKey(r[3] .. (slot - r[1] + 1))
                if key then return key end
            end
        end
    end
    return nil
end

local function BindingFor(ui, item)
    local id = item.info.spellID
    if not id or item.bank ~= BANK_PLAYER then return nil end
    local b = ui.binds
    local seq = b and (b.byID[id] or b.byName[item.info.name])
        or StandardBinding(id)
    return seq and ns.SeqGlyphs(seq) or nil
end

-- Pagination: every section starts on a new page and flows onto as many
-- pages as it needs; pages pair up into spreads (left, right).
local function Capacity(ui)
    local w = ui.side[1].grid:GetWidth()
    local h = ui.side[1].grid:GetHeight()
    if not w or w <= 0 or not h or h <= 0 then return nil end
    local cols = math.max(1, math.floor(w / CELL_W))
    local rows = math.max(1, math.floor(h / (CELL_H + ROW_GAP)))
    return cols, rows
end

local function Paginate(ui)
    local cols, rows = Capacity(ui)
    if not cols then return false end
    ui.cols, ui.rows = cols, rows
    local cap = cols * rows
    local pages = {}
    for _, sec in ipairs(ui.sections) do
        local items = sec.items
        for first = 1, #items, cap do
            local page = { sec = sec, items = {} }
            for i = first, math.min(#items, first + cap - 1) do
                page.items[#page.items + 1] = items[i]
            end
            pages[#pages + 1] = page
        end
    end
    ui.pages = pages
    ui.spreads = math.max(1, math.ceil(#pages / 2))
    return true
end

-- Spread, side (1 left, 2 right) and index on that page of an item.
local function Locate(ui, item)
    if not item then return nil end
    for p, page in ipairs(ui.pages) do
        for i, it in ipairs(page.items) do
            if it == item then
                return math.ceil(p / 2), p % 2 == 1 and 1 or 2, i
            end
        end
    end
    return nil
end

local function PageAt(ui, side)
    return ui.pages[(ui.spread - 1) * 2 + side]
end

local function HideTip(ui)
    if ui.tipOwner then
        GameTooltip:Hide()
        ns.SetTipScale(1)
        ui.tipOwner = nil
    end
end

local function ShowTip(ui, cell)
    local item = cell and cell.item
    if not (item and ui.frame:IsShown()) then
        HideTip(ui)
        return
    end
    GameTooltip:SetOwner(cell, cell.side == 1 and "ANCHOR_RIGHT" or "ANCHOR_LEFT")
    local ok = GameTooltip.SetSpellBookItem
        and pcall(GameTooltip.SetSpellBookItem, GameTooltip, item.slot, item.bank)
    if not ok and item.info.spellID then
        GameTooltip:SetSpellByID(item.info.spellID)
    end
    ui.tipOwner = cell
    ns.SetTipScale(ns.TIP_SCALE)
    GameTooltip:Show()
end

local function SetCell(ui, cell, item)
    cell.item = item
    if not item then
        cell:Hide()
        return
    end
    local info = item.info
    cell.icon:SetTexture(info.iconID)
    cell.label:SetText(info.name)
    cell.sub:SetText(info.subName or "")
    cell.bind:SetText(BindingFor(ui, item) or "")
    local c = TEXT
    if info.itemType == IT.FutureSpell then
        c = FUTURE_COLOR
    elseif info.isPassive then
        c = DIM_COLOR
    end
    cell.label:SetTextColor(c[1], c[2], c[3])
    cell.icon:SetDesaturated(info.itemType == IT.FutureSpell)
    cell.icon:SetVertexColor(1, 1, 1,
        info.itemType == IT.FutureSpell and 0.55 or 1)
    cell.sel:SetShown(ui.selected == item)
    cell:Show()
end

local function Render(ui)
    if not ui.pages then return end
    local total = #ui.pages
    local cw = ui.side[1].grid:GetWidth() / ui.cols
    for s = 1, 2 do
        local side = ui.side[s]
        local page = PageAt(ui, s)
        local n = page and #page.items or 0
        for i = 1, math.max(n, #side.cells) do
            local cell = side.cells[i]
            if not cell then
                cell = side.NewCell()
                side.cells[i] = cell
            end
            cell:ClearAllPoints()
            cell:SetPoint("TOPLEFT", side.grid, "TOPLEFT",
                ((i - 1) % ui.cols) * cw,
                -math.floor((i - 1) / ui.cols) * (CELL_H + ROW_GAP))
            cell:SetWidth(cw - 8)
            SetCell(ui, cell, page and page.items[i])
        end
        if page then
            side.title:SetText(page.sec.name)
            SetSectionIcon(side.titleIcon, page.sec)
            side.titleIcon:Show()
            side.num:SetText(((ui.spread - 1) * 2 + s) .. " / " .. total)
        else
            side.title:SetText("")
            side.titleIcon:Hide()
            side.num:SetText("")
        end
    end
    ui.prev:SetAlpha(ui.spread > 1 and 1 or 0.4)
    ui.next:SetAlpha(ui.spread < ui.spreads and 1 or 0.4)
end

local function CellOf(ui, item)
    if not item then return nil end
    for s = 1, 2 do
        for _, cell in ipairs(ui.side[s].cells) do
            if cell.item == item and cell:IsShown() then return cell end
        end
    end
    return nil
end

local function Select(ui, item)
    ui.selected = item
    for s = 1, 2 do
        for _, cell in ipairs(ui.side[s].cells) do
            cell.sel:SetShown(item ~= nil and cell.item == item)
        end
    end
    ShowTip(ui, CellOf(ui, item))
end

local function FirstOnSpread(ui)
    local page = PageAt(ui, 1) or PageAt(ui, 2)
    return page and page.items[1]
end

local function SetSpread(ui, spread)
    if not ui.pages then return end
    ui.spread = math.min(math.max(1, spread), ui.spreads)
    Render(ui)
    if ui.selected then Select(ui, FirstOnSpread(ui)) end
end

-- Re-lays the book (size change, new spells) keeping the selected spell.
local function Relayout(ui)
    if not Paginate(ui) then return end
    local spread = Locate(ui, ui.selected)
    if not spread then
        ui.selected = nil
        spread = math.min(ui.spread or 1, ui.spreads)
    end
    ui.spread = spread
    Render(ui)
    Select(ui, ui.selected)
end

local function Rebuild(ui)
    ui.sections = Sections()
    for _, sec in ipairs(ui.sections) do sec.items = BuildItems(sec) end
    -- Item tables are new; keep the selection by spellbook slot.
    local old = ui.selected
    ui.selected = nil
    if old then
        for _, sec in ipairs(ui.sections) do
            for _, it in ipairs(sec.items) do
                if it.slot == old.slot and it.bank == old.bank then
                    ui.selected = it
                end
            end
        end
    end
    BuildBindMap(ui)
    Relayout(ui)
end

-- D-pad over the spread: left/right walk a page row and cross the gutter
-- between the two pages, up/down move one row and stop at the page edges.
local function MoveSelection(ui, button)
    if not ui.pages then return end
    local spread, side, idx = Locate(ui, ui.selected)
    if spread ~= ui.spread then
        Select(ui, FirstOnSpread(ui))
        return
    end
    local cols = ui.cols
    local n = #PageAt(ui, side).items
    local col, row = (idx - 1) % cols, math.floor((idx - 1) / cols)
    if button == "PADDUP" then
        if row == 0 then return end
        idx = idx - cols
    elseif button == "PADDDOWN" then
        if row >= math.floor((n - 1) / cols) then return end
        idx = math.min(n, idx + cols)
    elseif button == "PADDLEFT" then
        if col > 0 then
            idx = idx - 1
        elseif side == 2 and PageAt(ui, 1) then
            side = 1
            idx = math.min(#PageAt(ui, 1).items, row * cols + cols)
        else
            return
        end
    elseif button == "PADDRIGHT" then
        if col < cols - 1 and idx < n then
            idx = idx + 1
        elseif side == 1 and PageAt(ui, 2) then
            side = 2
            idx = math.min(#PageAt(ui, 2).items, row * cols + 1)
        else
            return
        end
    end
    Select(ui, PageAt(ui, side).items[idx])
end

-- Dark paper multiply over the parchment atlases, same as the quests page.
ns.pageBgTint["abilities-left"] = { 0.35, 0.35, 0.38 }
ns.pageBgTint["abilities-right"] = { 0.35, 0.35, 0.38 }

local function NavButton(parent, text)
    local b = CreateFrame("Button", nil, parent)
    b.label = T.CreateFontString(b, 17, TEXT)
    b.label:SetPoint("CENTER")
    b.label:SetText(text)
    -- Inline pad glyphs aren't measured by GetStringWidth (AGENTS.md).
    b:SetSize(b.label:GetStringWidth() + 40, HEADER_H)
    return b
end

ns.RegisterPage(4, {
    key = "abilities",
    title = "Abilities",
    Build = function(f)
        local ui = { dpadHold = {}, side = {}, spread = 1, frame = f }
        ns.abUI = ui

        -- Each panel gets both horizontal edges anchored: a frame with only
        -- left-edge anchors has no width, and its children never lay out.
        local left = PANEL(f, "abilities-left",
            "spellbook-background-evergreen-left")
        ui.left = left
        left:SetPoint("TOPLEFT", MARGIN, -MARGIN)
        left:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -GAP / 2, MARGIN)
        local right = PANEL(f, "abilities-right",
            "spellbook-background-evergreen-right")
        ui.right = right
        right:SetPoint("TOPLEFT", f, "TOP", GAP / 2, -MARGIN)
        right:SetPoint("BOTTOMRIGHT", -MARGIN, MARGIN)

        for s, panel in ipairs({ left, right }) do
            local side = { cells = {}, panel = panel }
            ui.side[s] = side

            -- Header: section icon + name, centered on the page.
            side.title = T.CreateFontString(panel, 22, HEADER_COLOR)
            side.title:SetPoint("TOP", panel, "TOP", 21, -PAD - 8)
            side.titleIcon = panel:CreateTexture(nil, "ARTWORK")
            side.titleIcon:SetSize(32, 32)
            side.titleIcon:SetPoint("RIGHT", side.title, "LEFT", -10, 0)

            side.grid = CreateFrame("Frame", nil, panel)
            side.grid:SetPoint("TOPLEFT", PAD, -(PAD + HEADER_H + 16))
            side.grid:SetPoint("BOTTOMRIGHT", -PAD, PAD + FOOTER_H + 8)

            side.num = T.CreateFontString(panel, 15, DIM_COLOR)
            side.num:SetPoint("BOTTOM", panel, "BOTTOM", 0, PAD)

            function side.NewCell()
                local b = CreateFrame("Button", nil, side.grid)
                b.side = s
                b:SetHeight(CELL_H)
                b.sel = b:CreateTexture(nil, "BACKGROUND")
                b.sel:SetAllPoints()
                local a = T.colors.accent
                b.sel:SetColorTexture(a[1], a[2], a[3], 0.35)
                b.sel:Hide()
                b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
                b.icon = b:CreateTexture(nil, "ARTWORK")
                b.icon:SetSize(ICON, ICON)
                b.icon:SetPoint("TOPLEFT", 4, -4)
                b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
                -- Single TOPLEFT anchors + fixed widths: TOPLEFT + RIGHT
                -- at different y over-constrains a FontString (AGENTS.md).
                b.label = T.CreateFontString(b, 16, TEXT)
                b.label:SetPoint("TOPLEFT", b.icon, "TOPRIGHT", 8, -2)
                b.label:SetWidth(CELL_W - ICON - 24)
                b.label:SetJustifyH("LEFT")
                b.label:SetWordWrap(false)
                b.sub = T.CreateFontString(b, 12, DIM_COLOR)
                b.sub:SetPoint("TOPLEFT", b.label, "BOTTOMLEFT", 0, -3)
                b.sub:SetWidth(CELL_W - ICON - 24)
                b.sub:SetJustifyH("LEFT")
                b.sub:SetWordWrap(false)
                -- Activation sequence, under the icon.
                b.bind = T.CreateFontString(b, 13, DIM_COLOR)
                b.bind:SetPoint("TOPLEFT", b.icon, "BOTTOMLEFT", 0, -3)
                b.bind:SetJustifyH("LEFT")
                b:SetScript("OnEnter", function(self)
                    if self.item then Select(ui, self.item) end
                end)
                b:SetScript("OnClick", function(self)
                    if self.item then Select(ui, self.item) end
                end)
                return b
            end
        end

        -- Leaf hints: LT Previous top-left of the left page, Next RT
        -- top-right of the right page. Clickable too.
        ui.prev = NavButton(left,
            ns.PadGlyph("PADLTRIGGER", "LT") .. "  Previous")
        ui.prev:SetPoint("TOPLEFT", PAD - 20, -PAD)
        ui.prev:SetScript("OnClick", function() SetSpread(ui, ui.spread - 1) end)
        ui.next = NavButton(right,
            "Next  " .. ns.PadGlyph("PADRTRIGGER", "RT"))
        ui.next:SetPoint("TOPRIGHT", -(PAD - 20), -PAD)
        ui.next:SetScript("OnClick", function() SetSpread(ui, ui.spread + 1) end)

        -- Pad legend in the right page's footer.
        local nav = T.CreateFontString(right, 15, TEXT)
        nav:SetPoint("BOTTOMRIGHT", -PAD, PAD)
        local dpad = ""
        for _, b in ipairs({ "PADDUP", "PADDDOWN", "PADDLEFT", "PADDRIGHT" }) do
            local g = ns.PadGlyph(b)
            if not (g and g:find("|")) then
                dpad = "D-Pad"
                break
            end
            dpad = dpad .. g
        end
        nav:SetText(dpad .. "  Navigate")

        left:SetScript("OnSizeChanged", function()
            if f:IsShown() and ui.sections then Relayout(ui) end
        end)

        -- Held D-pad repeats, same ramp as the quests page.
        f:SetScript("OnUpdate", function(_, dt)
            for button, st in pairs(ui.dpadHold) do
                st.t = st.t + dt
                st.acc = st.acc + dt
                local iv = math.max(0.11, 0.22 - st.t * 0.08)
                if st.acc >= iv then
                    st.acc = 0
                    MoveSelection(ui, button)
                end
            end
        end)
    end,
    OnShow = function(f)
        local ui = ns.abUI
        if not ui then return end
        ui.selected = nil
        if ui.dirty or not ui.sections then
            ui.dirty = nil
            Rebuild(ui)
        else
            if ui.bindsDirty then
                ui.bindsDirty = nil
                BuildBindMap(ui)
            end
            Relayout(ui)
        end
    end,
    OnTrigger = function(f, dir)
        local ui = ns.abUI
        if not (ui and ui.pages) then return false end
        local spread = ui.spread + dir
        if spread < 1 or spread > ui.spreads then return false end
        SetSpread(ui, spread)
        return true
    end,
    OnPad = function(f, button)
        local ui = ns.abUI
        if not ui then return end
        if button == "PADDUP" or button == "PADDDOWN"
            or button == "PADDLEFT" or button == "PADDRIGHT" then
            ui.dpadHold[button] = { t = 0, acc = 0 }
            MoveSelection(ui, button)
        end
    end,
    OnPadReset = function()
        local ui = ns.abUI
        if ui and ui.dpadHold then wipe(ui.dpadHold) end
    end,
    OnPadUp = function(f, button)
        local ui = ns.abUI
        if ui and ui.dpadHold then ui.dpadHold[button] = nil end
    end,
    OnHide = function()
        local ui = ns.abUI
        if not ui then return end
        if ui.dpadHold then wipe(ui.dpadHold) end
        HideTip(ui)
    end,
})

local function IsShown()
    return ns.pageFrames[4] and ns.pageFrames[4]:IsShown()
end

-- New spells / spec change: re-read the book (now if open, else on show).
local function SpellsChanged()
    local ui = ns.abUI
    if not ui then return end
    if IsShown() then Rebuild(ui) else ui.dirty = true end
end
Nocturne.RegisterEvent("SPELLS_CHANGED", SpellsChanged)
Nocturne.RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED", SpellsChanged)

-- Bars or bindings changed: refresh the activation sequences.
local function BindsChanged()
    local ui = ns.abUI
    if not (ui and ui.sections) then return end
    if IsShown() then
        BuildBindMap(ui)
        Render(ui)
        Select(ui, ui.selected)
    else
        ui.bindsDirty = true
    end
end
Nocturne.RegisterEvent("ACTIONBAR_SLOT_CHANGED", BindsChanged)
Nocturne.RegisterEvent("UPDATE_BINDINGS", BindsChanged)
