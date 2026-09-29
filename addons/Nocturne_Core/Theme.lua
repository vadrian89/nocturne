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

function T.CreateFontString(parent, size, color, drawLayer)
    local fs = parent:CreateFontString(nil, drawLayer or "OVERLAY")
    fs:SetFont(T.fonts.main, size or 12, "")
    local c = color or T.colors.text
    fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    return fs
end
