local _, core = ...
local Nocturne = _G.Nocturne

local T = {}
Nocturne.Theme = T

-- Console-like, low-contrast palette shared by every Nocturne addon.
T.colors = {
    backdrop  = { 0.04, 0.05, 0.08, 0.80 },
    border    = { 0.20, 0.22, 0.30, 0.90 },
    accent    = { 0.80, 0.68, 0.42, 1.00 }, -- pale gold
    text      = { 0.85, 0.86, 0.90, 1.00 },
    textDim   = { 0.55, 0.57, 0.66, 1.00 },
    stripLine = { 0.60, 0.62, 0.72, 0.55 },
}

T.fonts = {
    main = "Fonts\\FRIZQT__.TTF",
}

function T.ApplyBackdrop(frame)
    -- 12.0: SetBackdrop is native on widgets; BackdropTemplateMixin is a
    -- legacy fallback and may not exist anymore.
    if not frame.SetBackdrop and Mixin and BackdropTemplateMixin then
        Mixin(frame, BackdropTemplateMixin)
        if frame.HookBackdrop then
            frame:HookBackdrop()
        end
    end
    if not frame.SetBackdrop then return end
    -- Classic Blizzard tooltip look: dark blue-grey background, thin border.
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropColor(0.09, 0.09, 0.19, 0.92)
    frame:SetBackdropBorderColor(0.75, 0.75, 0.75, 1)
end

-- `text` wrapped in a |c color escape for a theme color (e.g. T.colors.accent).
function T.ColorText(text, c)
    return ("|cff%02x%02x%02x%s|r"):format(c[1] * 255, c[2] * 255, c[3] * 255, text)
end

function T.CreateFontString(parent, size, color, drawLayer, flags)
    local fs = parent:CreateFontString(nil, drawLayer or "OVERLAY")
    fs:SetFont(T.fonts.main, size or 12, flags or "")
    local c = color or T.colors.text
    fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    return fs
end

-- Rounded rectangle from non-overlapping pieces (so the additive alpha stays
-- even): a full-height center strip, two side strips and four corner
-- quarter-discs cut from Blizzard's circular portrait mask.
local GLOW_RADIUS = 10
local CIRCLE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"

local function GlowPiece(g, c, file)
    local t = g:CreateTexture(nil, "OVERLAY")
    if file then
        t:SetTexture(file)
        t:SetVertexColor(c[1], c[2], c[3], 0.35)
    else
        t:SetColorTexture(c[1], c[2], c[3], 0.35)
    end
    t:SetBlendMode("ADD")
    return t
end

local function BuildRoundedGlow(g, c, r)
    local center = GlowPiece(g, c)
    center:SetPoint("TOPLEFT", r, 0)
    center:SetPoint("BOTTOMRIGHT", -r, 0)
    for _, side in ipairs({ "LEFT", "RIGHT" }) do
        local s = GlowPiece(g, c)
        s:SetWidth(r)
        s:SetPoint("TOP" .. side, 0, -r)
        s:SetPoint("BOTTOM" .. side, 0, r)
    end
    -- point, x/y offsets, texcoords of that quarter of the disc
    for _, q in ipairs({
        { "TOPLEFT", 0, 0.5, 0, 0.5 }, { "TOPRIGHT", 0.5, 1, 0, 0.5 },
        { "BOTTOMLEFT", 0, 0.5, 0.5, 1 }, { "BOTTOMRIGHT", 0.5, 1, 0.5, 1 },
    }) do
        local corner = GlowPiece(g, c, CIRCLE)
        corner:SetSize(r, r)
        corner:SetPoint(q[1])
        corner:SetTexCoord(q[2], q[3], q[4], q[5])
    end
end

-- Frame glow for "something active" states (e.g. inside a quest region):
-- a pulsing additive accent rounded rect over the frame.
function T.SetGlow(frame, shown)
    local g = frame._noctGlow
    if shown then
        if not g then
            g = CreateFrame("Frame", nil, frame)
            g:SetPoint("TOPLEFT", -6, 6)
            g:SetPoint("BOTTOMRIGHT", 6, -6)
            BuildRoundedGlow(g, T.colors.accent, GLOW_RADIUS)
            local ag = g:CreateAnimationGroup()
            ag:SetLooping("BOUNCE")
            -- Slow, eased breathing (2.5s each way) rather than a blink.
            local a = ag:CreateAnimation("Alpha")
            a:SetFromAlpha(0.35)
            a:SetToAlpha(1)
            a:SetDuration(2.5)
            a:SetSmoothing("IN_OUT")
            g.pulse = ag
            frame._noctGlow = g
        end
        g:Show()
        g.pulse:Play()
    elseif g then
        g.pulse:Stop()
        g:Hide()
    end
end
