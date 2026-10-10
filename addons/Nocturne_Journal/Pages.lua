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


-- Page 3 lives in Pages/Inventory.lua.

-- Page 4 lives in Pages/Abilities.lua.

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
