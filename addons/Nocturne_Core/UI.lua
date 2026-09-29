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

-- Keeps a Blizzard frame hidden while `want()` is true. Such frames re-show
-- themselves (events, Edit Mode), so OnShow -> Hide is the standard
-- suppression; HookScript can't be removed, so the hook asks `want()` live.
-- Only a frame we hid is ever re-shown, leaving Blizzard's own visibility
-- logic (and other addons) alone otherwise. Frames holding secure children
-- can't Hide()/Show() in combat: they're faded out instead, and a later
-- Sync() (e.g. on PLAYER_REGEN_ENABLED) finishes the job.
function Nocturne.NewSuppressor(getFrame, want)
    local s = { hidden = false }
    local hooked
    local function Locked(f) return InCombatLockdown() and f:IsProtected() end
    local function Suppress(f)
        s.hidden = true
        if Locked(f) then f:SetAlpha(0) else f:Hide() end
    end
    function s.Sync()
        local f = getFrame()
        if not f then return end
        if not hooked then
            hooked = true
            f:HookScript("OnShow", function(frame)
                if want() then Suppress(frame) end
            end)
        end
        if want() then
            Suppress(f)
        elseif s.hidden and not Locked(f) then
            s.hidden = false
            f:SetAlpha(1)
            f:Show()
        end
    end
    return s
end
