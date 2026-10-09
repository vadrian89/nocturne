local _, ns = ...

local Nocturne = _G.Nocturne
local T = Nocturne.Theme

local MARGIN = 24
local GAP = 16
local PARCHMENT_TEXT = { 0.16, 0.10, 0.05, 1 }

-- First existing atlas wins; missing atlases fall back to the theme color.
-- Results land in ns.diagAtlas so /njrn diag shows what resolved.
local function SetBackground(pageKey, tex, ...)
    local atlas = Nocturne.FirstAtlas(...)
    ns.diagAtlas[pageKey] = atlas or "fallback"
    if atlas and tex.SetAtlas then
        tex:SetAtlas(atlas, false) -- stretched, not atlas-sized
        local tint = ns.pageBgTint and ns.pageBgTint[pageKey]
        if tint then tex:SetVertexColor(tint[1], tint[2], tint[3]) end
    else
        local c = T.colors.backdrop
        tex:SetColorTexture(c[1], c[2], c[3], 1)
    end
end

-- Vertex-color multiply applied only when the atlas resolved (a color
-- fallback would go near-black). Dark gray paper instead of light parchment.
ns.pageBgTint = {
    quests = { 0.35, 0.35, 0.38 },
    inventory = { 0.35, 0.35, 0.38 },
}

local function Panel(parent, pageKey, ...)
    local p = CreateFrame("Frame", nil, parent)
    p.bg = p:CreateTexture(nil, "BACKGROUND")
    p.bg:SetAllPoints()
    SetBackground(pageKey, p.bg, ...)
    return p
end

local function CenteredText(parent, text, color, size)
    local fs = T.CreateFontString(parent, size or 14, color or T.colors.textDim)
    fs:SetPoint("CENTER")
    fs:SetText(text)
    return fs
end

local function ComingSoon(parent, text, color)
    local fs = CenteredText(parent, text, color, 16)
    local sub = T.CreateFontString(parent, 11, color or T.colors.textDim)
    sub:SetPoint("TOP", fs, "BOTTOM", 0, -6)
    sub:SetText("Coming soon")
    return fs
end

-- Page 1: Map
ns.RegisterPage(1, {
    key = "map",
    title = "Map",
    Build = function(f)
        ComingSoon(f, "Map")
    end,
})

-- Page 2 lives in Pages/Quests.lua.

-- Export the panel helpers the real pages share.
ns.JournalPanel = Panel
ns.JournalCenteredText = CenteredText
ns.JournalParchmentText = PARCHMENT_TEXT
ns.JournalMargin = MARGIN
ns.JournalGap = GAP


-- Page 3: Inventory — bags left, equipment right.
ns.RegisterPage(3, {
    key = "inventory",
    title = "Inventory",
    Build = function(f)
        local bags = Panel(f, "inventory", "QuestBG-Parchment")
        bags:SetPoint("TOPLEFT", MARGIN, -MARGIN)
        bags:SetPoint("BOTTOMLEFT", MARGIN, MARGIN)
        local equip = Panel(f, "inventory", "QuestBG-Parchment")
        equip:SetPoint("TOPRIGHT", -MARGIN, -MARGIN)
        equip:SetPoint("BOTTOMRIGHT", -MARGIN, MARGIN)
        equip:SetPoint("LEFT", bags, "RIGHT", GAP, 0)

        ComingSoon(bags, "Bags", PARCHMENT_TEXT)
        ComingSoon(equip, "Equipment", PARCHMENT_TEXT)

        local function Layout()
            bags:SetWidth(math.floor(f:GetWidth() * 0.55) - GAP)
        end
        Layout()
        f:SetScript("OnSizeChanged", Layout)
    end,
})

-- Page 4: Abilities — one sub-page per spellbook skill line, cycled by
-- LT/RT. Background halves from Blizzard_SpellBookFrame.xml.
local function SpellBookTabs()
    local names = {}
    if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines then
        for i = 1, C_SpellBook.GetNumSpellBookSkillLines() do
            local info = C_SpellBook.GetSpellBookSkillLineInfo(i)
            if info and not info.shouldHide then
                names[#names + 1] = info.name or ("Tab " .. i)
            end
        end
        if C_SpellBook.HasPetSpells and C_SpellBook.HasPetSpells() then
            names[#names + 1] = PET or "Pet"
        end
    end
    if #names == 0 then
        names = { "General", "Class", "Spec" }
    end
    return names
end

ns.RegisterPage(4, {
    key = "abilities",
    title = "Abilities",
    subPages = SpellBookTabs,
    Build = function(f)
        local header = f:CreateTexture(nil, "BACKGROUND")
        header:SetPoint("TOPLEFT")
        header:SetPoint("TOPRIGHT")
        header:SetHeight(40)
        SetBackground("abilities-top", header, "spellbook-background-evergreen-header")
        local left = f:CreateTexture(nil, "BACKGROUND", nil, 1)
        left:SetPoint("TOPLEFT", 0, -40)
        left:SetPoint("BOTTOMLEFT")
        left:SetPoint("RIGHT", f, "CENTER")
        SetBackground("abilities-left", left, "spellbook-background-evergreen-left")
        local right = f:CreateTexture(nil, "BACKGROUND", nil, 1)
        right:SetPoint("TOPRIGHT", 0, -40)
        right:SetPoint("BOTTOMRIGHT")
        right:SetPoint("LEFT", f, "CENTER")
        SetBackground("abilities-right", right, "spellbook-background-evergreen-right")

        f.subTitle = T.CreateFontString(f, 18, T.colors.accent)
        f.subTitle:SetPoint("TOP", 0, -54)
        f.hint = T.CreateFontString(f, 15, T.colors.textDim)
        f.hint:SetPoint("CENTER")
    end,
    OnSubPage = function(f, i)
        local names = SpellBookTabs()
        f.subTitle:SetText(names[i] or "")
        f.hint:SetText("Spell grid for this tab — coming soon")
    end,
})

-- Page 5: Talents
ns.RegisterPage(5, {
    key = "talents",
    title = "Talents",
    Build = function(f)
        local bg = f:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        SetBackground("talents", bg, "talents-background")
        ComingSoon(f, "Talents")
    end,
})
