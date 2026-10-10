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

-- One sub-page per visible skill line, plus "Pet" when the pet has spells.
-- The index matches the shell's sub-page index on every call.
local function AbilityTabs()
    local tabs = {}
    if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines then
        for i = 1, C_SpellBook.GetNumSpellBookSkillLines() do
            local info = C_SpellBook.GetSpellBookSkillLineInfo(i)
            if info and not info.shouldHide then
                tabs[#tabs + 1] = {
                    name = info.name or ("Tab " .. i),
                    skillLine = i
                }
            end
        end
        if C_SpellBook.HasPetSpells and C_SpellBook.HasPetSpells() then
            tabs[#tabs + 1] = { name = PET or "Pet", pet = true }
        end
    end
    if #tabs == 0 then
        tabs[1] = { name = "Abilities" }
    end
    return tabs
end

local function TabNames()
    local names = {}
    for _, t in ipairs(AbilityTabs()) do names[#names + 1] = t.name end
    return names
end

local function BuildItems(tab)
    local items = {}
    if not (tab and C_SpellBook and C_SpellBook.GetSpellBookItemInfo) then
        return items
    end
    if tab.pet then
        local n = C_SpellBook.HasPetSpells and C_SpellBook.HasPetSpells()
        for slot = 1, n or 0 do
            local info = C_SpellBook.GetSpellBookItemInfo(slot, BANK_PET)
            if info and info.itemType ~= IT.None and info.name ~= "" then
                items[#items + 1] = {
                    slot = slot,
                    bank = BANK_PET,
                    info = info
                }
            end
        end
        return items
    end
    if not tab.skillLine then return items end
    local line = C_SpellBook.GetSpellBookSkillLineInfo(tab.skillLine)
    if not line then return items end
    local last = line.itemIndexOffset + line.numSpellBookItems
    for slot = line.itemIndexOffset + 1, last do
        local info = C_SpellBook.GetSpellBookItemInfo(slot, BANK_PLAYER)
        if info and info.itemType ~= IT.None and info.name ~= "" then
            items[#items + 1] = {
                slot = slot,
                bank = BANK_PLAYER,
                info = info
            }
        end
    end
    return items
end

local function DetailFlags(ui, item)
    local info = item.info
    local bits = {}
    if info.isPassive then bits[#bits + 1] = "Passive" end
    if info.itemType == IT.Flyout then bits[#bits + 1] = "Flyout" end
    if info.itemType == IT.PetAction then bits[#bits + 1] = "Pet" end
    if info.itemType == IT.FutureSpell then
        local lv = C_SpellBook.GetSpellBookItemLevelLearned
            and C_SpellBook.GetSpellBookItemLevelLearned(item.slot,
                item.bank)
        bits[#bits + 1] = lv and lv > 0
            and ("Learned at level " .. lv) or "Not learned yet"
    end
    if info.isOffSpec then bits[#bits + 1] = "Off-spec" end
    return table.concat(bits, "  |  ")
end

local function ShowDetail(ui)
    local item = ui.selected
    if not item then
        ui.dIcon:Hide()
        ui.dName:SetText("")
        ui.dSub:SetText("")
        ui.dFlags:SetText("")
        ui.dDesc:SetText("")
        return
    end
    local info = item.info
    ui.dIcon:SetTexture(info.iconID)
    ui.dIcon:Show()
    ui.dName:SetText(info.name or "")
    ui.dSub:SetText(info.subName or "")
    ui.dFlags:SetText(DetailFlags(ui, item))
    local desc = C_SpellBook.GetSpellBookItemDescription
        and C_SpellBook.GetSpellBookItemDescription(item.slot, item.bank)
    ui.dDesc:SetText((desc and desc ~= "") and desc or "")
end

local function Refresh(ui)
    ui.list:SetItems(ui.items)
    ui.list:Refresh()
    ShowDetail(ui)
end

local function SelectItem(ui, item)
    ui.selected = item
    ui.list:Refresh()
    ShowDetail(ui)
end

local function MoveSelection(ui, dir)
    local items = ui.items
    if not items or #items == 0 then return end
    local idx = 0
    for i, it in ipairs(items) do
        if it == ui.selected then
            idx = i
            break
        end
    end
    idx = ((idx + dir - 1) % #items) + 1
    SelectItem(ui, items[idx])
    ui.list:RevealIndex(idx)
end

-- Dark paper multiply over the parchment atlases, same as the quests page.
ns.pageBgTint["abilities-left"] = { 0.35, 0.35, 0.38 }
ns.pageBgTint["abilities-right"] = { 0.35, 0.35, 0.38 }

ns.RegisterPage(4, {
    key = "abilities",
    title = "Abilities",
    subPages = TabNames,
    OnSubPage = function(f, i)
        local ui = ns.abUI
        if not ui then return end
        ui.tab = AbilityTabs()[i] or {}
        ui.items = BuildItems(ui.tab)
        ui.selected = ui.items[1]
        Refresh(ui)
    end,
    Build = function(f)
        local ui = { dpadHold = {} }
        ns.abUI = ui

        -- Top edge clears the shell's sub-bar (44px). Each panel gets both
        -- horizontal edges anchored: a frame with only left-edge anchors
        -- has no width, and its children (the list) never lay out.
        local top = -(44 + MARGIN)
        local left = PANEL(f, "abilities-left",
            "spellbook-background-evergreen-left")
        ui.left = left
        left:SetPoint("TOPLEFT", MARGIN, top)
        left:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -GAP / 2, MARGIN)
        local right = PANEL(f, "abilities-right",
            "spellbook-background-evergreen-right")
        ui.right = right
        right:SetPoint("TOPLEFT", f, "TOP", GAP / 2, top)
        right:SetPoint("BOTTOMRIGHT", -MARGIN, MARGIN)

        ui.list = ns.NewList(left, {
            rowHeight = 40,
            initRow = function(row)
                ns.NewListRow(row, false, 18)
                row.icon:SetSize(30, 30)
                row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
                -- Two-line cell: name over rank, both right of the icon.
                -- LEFT+RIGHT at the same y: a mismatch on the mid-y pins a
                -- degenerate rect and the text never shows.
                row.label:ClearAllPoints()
                row.label:SetPoint("LEFT", row.icon, "RIGHT", 8, 7)
                row.label:SetPoint("RIGHT", -4, 7)
                row.sub = row:CreateFontString(nil, "ARTWORK")
                row.sub:SetFont(T.fonts.main, 12, "")
                row.sub:SetTextColor(DIM_COLOR[1], DIM_COLOR[2], DIM_COLOR[3])
                row.sub:SetPoint("LEFT", row.icon, "RIGHT", 8, -12)
                row.sub:SetPoint("RIGHT", -4, -12)
                row.sub:SetJustifyH("LEFT")
                row.sub:SetWordWrap(false)
                row.sel = row:CreateTexture(nil, "BACKGROUND")
                row.sel:SetAllPoints()
                local a = T.colors.accent
                row.sel:SetColorTexture(a[1], a[2], a[3], 0.35)
                row.sel:Hide()
            end,
            setRow = function(row, item)
                local info = item.info
                row.sel:SetShown(ui.selected == item)
                row.icon:SetTexture(info.iconID)
                row.label:SetText(info.name)
                row.sub:SetText(info.subName or "")
                local c = TEXT
                if info.itemType == IT.FutureSpell then
                    c = FUTURE_COLOR
                elseif info.isPassive then
                    c = DIM_COLOR
                end
                row.label:SetTextColor(c[1], c[2], c[3])
                row.icon:SetDesaturated(info.itemType == IT.FutureSpell)
                row.icon:SetVertexColor(1, 1, 1,
                    info.itemType == IT.FutureSpell and 0.55 or 1)
            end,
            onClick = function(item) SelectItem(ui, item) end,
        })
        ui.list.frame:SetPoint("TOPLEFT", 8, -8)
        ui.list.frame:SetPoint("BOTTOMRIGHT", -4, 8)

        -- Detail panel: big icon, name, rank line, flags, description.
        ui.dIcon = right:CreateTexture(nil, "ARTWORK")
        ui.dIcon:SetSize(56, 56)
        ui.dIcon:SetPoint("TOPLEFT", 40, -40)
        ui.dIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        ui.dIcon:Hide()

        ui.dName = T.CreateFontString(right, 30, HEADER_COLOR)
        ui.dName:SetPoint("LEFT", ui.dIcon, "RIGHT", 16, 10)
        ui.dName:SetJustifyH("LEFT")
        ui.dSub = T.CreateFontString(right, 15, DIM_COLOR)
        ui.dSub:SetPoint("LEFT", ui.dIcon, "RIGHT", 16, -16)
        ui.dSub:SetJustifyH("LEFT")

        ui.dFlags = T.CreateFontString(right, 15, T.colors.accent)
        ui.dFlags:SetPoint("TOPLEFT", ui.dIcon, "BOTTOMLEFT", 0, -18)
        ui.dFlags:SetJustifyH("LEFT")

        -- TOPLEFT+BOTTOMRIGHT fixes the whole box, so a mid-y clash can't
        -- collapse it the way a lone LEFT+RIGHT pair did.
        ui.dDesc = T.CreateFontString(right, 17, TEXT)
        ui.dDesc:SetPoint("TOPLEFT", ui.dFlags, "BOTTOMLEFT", 0, -16)
        ui.dDesc:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT", -40, 40)
        ui.dDesc:SetJustifyH("LEFT")
        ui.dDesc:SetJustifyV("TOP")
        ui.dDesc:SetWordWrap(true)

        -- Held D-pad repeats, same ramp as the quests page.
        f:SetScript("OnUpdate", function(_, dt)
            for button, st in pairs(ui.dpadHold) do
                st.t = st.t + dt
                st.acc = st.acc + dt
                local iv = math.max(0.11, 0.22 - st.t * 0.08)
                if st.acc >= iv then
                    st.acc = 0
                    MoveSelection(ui, st.dir)
                end
            end
        end)

        -- Pad legend, bottom-right.
        local legend = CreateFrame("Frame", nil, f)
        legend:SetPoint("BOTTOMRIGHT", -MARGIN, MARGIN)
        legend:SetSize(400, 30)
        local nav = T.CreateFontString(legend, 15, TEXT)
        nav:SetPoint("BOTTOMRIGHT")
        local up, down = ns.PadGlyph("PADDUP"), ns.PadGlyph("PADDDOWN")
        local dpad = (up and up:find("|") and down and down:find("|"))
            and (up .. down) or "D-Pad"
        nav:SetText(dpad .. "  Navigate")

        ui.tab, ui.items = {}, {}
    end,
    OnShow = function(f)
        local ui = ns.abUI
        if not ui then return end
        if ui.dirty or not ui.items or #ui.items == 0 then
            ui.dirty = nil
            local i = ns.subCurrent or 1
            ui.tab = AbilityTabs()[i] or {}
            ui.items = BuildItems(ui.tab)
            ui.selected = ui.items[1]
        end
        Refresh(ui)
        -- Snapshot the layout while the page is actually shown: hidden
        -- frames report no rect, so the post-close diag can't tell
        -- "never laid out" from "was fine while open".
        C_Timer.After(0.3, function()
            local function Box(fr)
                if not fr then return "-" end
                return ("L%.0f R%.0f T%.0f B%.0f"):format(
                    fr:GetLeft() or -1, fr:GetRight() or -1,
                    fr:GetTop() or -1, fr:GetBottom() or -1)
            end
            ui.boxSnap = ("shown=%s left[%s] vis=%s right[%s] list[%s] rows=%d row1[%s]"):format(
                tostring(f:IsShown()), Box(ui.left),
                tostring(ui.left and ui.left:IsVisible()),
                Box(ui.right), Box(ui.list and ui.list.frame),
                ui.list and #ui.list.rows or -1,
                Box(ui.list and ui.list.rows[1]))
        end)
    end,
    OnPad = function(f, button)
        local ui = ns.abUI
        if not ui then return end
        if button == "PADDUP" then
            ui.dpadHold[button] = { t = 0, acc = 0, dir = -1 }
            MoveSelection(ui, -1)
        elseif button == "PADDDOWN" then
            ui.dpadHold[button] = { t = 0, acc = 0, dir = 1 }
            MoveSelection(ui, 1)
        elseif button == "PADDLEFT" then
            ui.dpadHold[button] = { t = 0, acc = 0, dir = -10 }
            MoveSelection(ui, -10)
        elseif button == "PADDRIGHT" then
            ui.dpadHold[button] = { t = 0, acc = 0, dir = 10 }
            MoveSelection(ui, 10)
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
        if ui and ui.dpadHold then wipe(ui.dpadHold) end
    end,
})

-- New spells / spec change: re-read the book on next show.
Nocturne.RegisterEvent("SPELLS_CHANGED", function()
    local ui = ns.abUI
    if ui then ui.dirty = true end
end)
Nocturne.RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED", function()
    local ui = ns.abUI
    if ui then ui.dirty = true end
end)
