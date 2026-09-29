local _, core = ...
local Nocturne = _G.Nocturne
local T = Nocturne.Theme

-- Generic popup that presents text in a selectable edit box so the user can
-- Ctrl+C it (addons cannot write to the OS clipboard directly).
local frame

function Nocturne.ShowCopyText(title, text)
    if not frame then
        frame = CreateFrame("Frame", "NocturneCopyFrame", UIParent)
        frame:SetSize(440, 320)
        frame:SetPoint("CENTER")
        frame:SetFrameStrata("DIALOG")
        frame:EnableMouse(true)
        frame:SetMovable(true)
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
        frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
        frame:Hide()
        T.ApplyBackdrop(frame)
        tinsert(UISpecialFrames, "NocturneCopyFrame")

        frame.title = T.CreateFontString(frame, 12, T.colors.accent)
        frame.title:SetPoint("TOP", 0, -10)

        local scroll = CreateFrame("ScrollFrame", nil, frame, "InputScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 10, -32)
        scroll:SetPoint("BOTTOMRIGHT", -10, 34)
        frame.editBox = scroll.EditBox
        frame.editBox:SetFont(T.fonts.main, 11, "")
        frame.editBox:SetAutoFocus(false)

        local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -2, -2)

        frame.hint = T.CreateFontString(frame, 10, T.colors.textDim)
        frame.hint:SetPoint("BOTTOM", 0, 12)
        frame.hint:SetText("Ctrl+C to copy")
    end

    frame.title:SetText(title or "Copy")
    frame.editBox:SetText(text or "")
    frame:Show()
    frame.editBox:SetFocus()
    frame.editBox:HighlightText()
end
