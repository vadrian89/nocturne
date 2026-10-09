local _, ns = ...

local Nocturne = _G.Nocturne
local T = Nocturne.Theme

local HEADER_H = 42
local SUBBAR_H = 28
local TAB_PAD = 16

ns.pages = {}
ns.pageFrames = {}
ns.padCounts = {}
ns.diagAtlas = {}
ns.current = 0
ns.subCurrent = 1

function ns.RegisterPage(index, def)
    def.index = index
    ns.pages[index] = def
end

-- Binding text for a pad button; on gamepad it can come back as icon markup.
local function PadGlyph(name, fallback)
    local s = GetBindingText and GetBindingText(name)
    if s and s ~= "" and s ~= name then return s end
    return fallback
end
ns.PadGlyph = PadGlyph

local function SetLabelColor(label, c)
    label:SetTextColor(c[1], c[2], c[3], c[4] or 1)
end

local function CreateTab(parent, index, title, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(parent:GetHeight())
    b.label = T.CreateFontString(b, 13)
    b.label:SetPoint("CENTER")
    b.label:SetText(title)
    b:SetWidth(math.floor(b.label:GetStringWidth() + TAB_PAD * 2))
    b.line = b:CreateTexture(nil, "OVERLAY")
    b.line:SetPoint("BOTTOMLEFT", 6, 5)
    b.line:SetPoint("BOTTOMRIGHT", -6, 5)
    b.line:SetHeight(2)
    local a = T.colors.accent
    b.line:SetColorTexture(a[1], a[2], a[3], 1)
    b.line:Hide()
    b:SetScript("OnClick", function() onClick(index) end)
    b:SetScript("OnEnter", function(self)
        if not self.active then SetLabelColor(self.label, T.colors.text) end
    end)
    b:SetScript("OnLeave", function(self)
        SetLabelColor(self.label, self.active and T.colors.accent or T.colors.textDim)
    end)
    return b
end

-- Centers a row of same-height tab buttons inside `bar`.
local function LayoutTabs(tabs, bar, maxIndex)
    local w = 0
    for i = 1, maxIndex do w = w + tabs[i]:GetWidth() end
    local x = -w / 2
    for i = 1, maxIndex do
        local t = tabs[i]
        t:ClearAllPoints()
        t:SetPoint("LEFT", bar, "CENTER", x, 0)
        x = x + t:GetWidth()
    end
end

function ns:CreateShell()
    if ns.frame then return end

    -- Plain insecure frame so it can open and close even in combat. It is
    -- not a UIPanel: we never run it through ShowUIPanel/HideUIPanel, which
    -- is where Forever's gamepad focus gets refused (ADDON_ACTION_FORBIDDEN).
    local f = CreateFrame("Frame", "NocturneJournalFrame", UIParent)
    ns.frame = f
    f:SetAllPoints()
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:EnableMouse(true)
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    local c = T.colors.backdrop
    f.bg:SetColorTexture(c[1], c[2], c[3], 0.96)

    tinsert(UISpecialFrames, "NocturneJournalFrame")

    local h = CreateFrame("Frame", "NocturneJournalHeader", f)
    ns.header = h
    h:SetPoint("TOPLEFT")
    h:SetPoint("TOPRIGHT")
    h:SetHeight(HEADER_H)
    h:SetFrameLevel(f:GetFrameLevel() + 10)
    h.bg = h:CreateTexture(nil, "BACKGROUND")
    h.bg:SetAllPoints()
    h.bg:SetColorTexture(0.02, 0.03, 0.05, 0.95)
    h.rule = h:CreateTexture(nil, "ARTWORK")
    h.rule:SetPoint("BOTTOMLEFT")
    h.rule:SetPoint("BOTTOMRIGHT")
    h.rule:SetHeight(1)
    local rl = T.colors.border
    h.rule:SetColorTexture(rl[1], rl[2], rl[3], rl[4])

    h.lb = T.CreateFontString(h, 12, T.colors.textDim)
    h.lb:SetPoint("LEFT", 16, 0)
    h.lb:SetText(PadGlyph("PADLSHOULDER", "LB"))
    h.rb = T.CreateFontString(h, 12, T.colors.textDim)
    h.rb:SetPoint("RIGHT", -16, 0)
    h.rb:SetText(PadGlyph("PADRSHOULDER", "RB"))

    ns.tabs = {}
    for i = 1, #ns.pages do
        ns.tabs[i] = CreateTab(h, i, ns.pages[i].title, function(idx) ns:SetPage(idx) end)
    end
    LayoutTabs(ns.tabs, h, #ns.pages)

    -- Sub-page bar (LT/RT), shown only while the current page has sub-pages.
    local sub = CreateFrame("Frame", "NocturneJournalSubBar", f)
    ns.subBar = sub
    sub:SetPoint("TOPLEFT", h, "BOTTOMLEFT")
    sub:SetPoint("TOPRIGHT", h, "BOTTOMRIGHT")
    sub:SetHeight(SUBBAR_H)
    sub:SetFrameLevel(h:GetFrameLevel())
    sub.bg = sub:CreateTexture(nil, "BACKGROUND")
    sub.bg:SetAllPoints()
    sub.bg:SetColorTexture(0.03, 0.04, 0.07, 0.90)
    sub.rule = sub:CreateTexture(nil, "ARTWORK")
    sub.rule:SetPoint("BOTTOMLEFT")
    sub.rule:SetPoint("BOTTOMRIGHT")
    sub.rule:SetHeight(1)
    sub.rule:SetColorTexture(rl[1], rl[2], rl[3], rl[4])
    sub.lt = T.CreateFontString(sub, 12, T.colors.textDim)
    sub.lt:SetPoint("LEFT", 16, 0)
    sub.lt:SetText(PadGlyph("PADLTRIGGER", "LT"))
    sub.rt = T.CreateFontString(sub, 12, T.colors.textDim)
    sub.rt:SetPoint("RIGHT", -16, 0)
    sub.rt:SetText(PadGlyph("PADRTRIGGER", "RT"))
    sub:Hide()

    -- Own confirm modal: Blizzard's StaticPopup is off-limits here — on
    -- Forever's native gamepad UI, showing it makes FrameControlsManager
    -- call SetPreferredGamepadInteractTarget in our name (FORBIDDEN).
    local c = CreateFrame("Frame", "NocturneJournalConfirm", f)
    ns.confirm = c
    c:SetFrameLevel(h:GetFrameLevel() + 20)
    c:SetSize(480, 150)
    c:SetPoint("CENTER")
    T.ApplyBackdrop(c)
    c:EnableMouse(true)
    c.title = T.CreateFontString(c, 17, T.colors.text)
    c.title:SetPoint("TOP", 0, -24)
    c.title:SetWidth(420)
    c.title:SetJustifyH("CENTER")
    c.hint = T.CreateFontString(c, 14, T.colors.textDim)
    c.hint:SetPoint("BOTTOM", 0, 24)
    c:SetScript("OnHide", function()
        c.onConfirm = nil
        if ns.modal == c then ns.modal = nil end
    end)
    c:Hide()

    f:SetScript("OnHide", function() ns:OnShellHide() end)

    -- Modal pad input: propagation stays at its default so our presses don't
    -- leak to the world, and it is set once — changing propagation in combat
    -- is restricted. Counters prove in diag that buttons reach us.
    f:EnableGamePadButton(true)
    f:SetScript("OnGamePadButtonDown", function(_, button) ns:OnPadButton(button) end)
    f:Hide()
end

local function EnsurePage(i)
    local pf = ns.pageFrames[i]
    if pf then return pf end
    local def = ns.pages[i]
    pf = CreateFrame("Frame", "NocturneJournalPage" .. i, ns.frame)
    pf:SetPoint("TOPLEFT", ns.header, "BOTTOMLEFT")
    pf:SetPoint("BOTTOMRIGHT", ns.frame, "BOTTOMRIGHT")
    pf:Hide()
    ns.pageFrames[i] = pf
    if def.Build then def.Build(pf) end
    return pf
end

function ns:UpdateTabs()
    for i, t in ipairs(ns.tabs) do
        t.active = i == ns.current
        t.line:SetShown(t.active)
        SetLabelColor(t.label, t.active and T.colors.accent or T.colors.textDim)
    end
end

function ns:UpdateSubBar()
    local def = ns.pages[ns.current]
    local titles = def and def.subPages and def.subPages()
    local sub = ns.subBar
    if not titles or #titles == 0 then
        sub:Hide()
        ns.subTitles = nil
        return
    end
    ns.subTitles = titles
    -- A page can render its own sub-tab row; the global bar stays hidden but
    -- LT/RT still route through SetSubPage.
    if def.ownSubBar then
        sub:Hide()
        return
    end
    ns.subTabs = ns.subTabs or {}
    for i = 1, #titles do
        local t = ns.subTabs[i]
        if not t then
            t = CreateTab(sub, i, "", function(idx) ns:SetSubPage(idx) end)
            ns.subTabs[i] = t
        end
        t.label:SetText(titles[i])
        t:SetWidth(math.floor(t.label:GetStringWidth() + TAB_PAD * 2))
        t.active = i == ns.subCurrent
        t.line:SetShown(t.active)
        SetLabelColor(t.label, t.active and T.colors.accent or T.colors.textDim)
        t:Show()
    end
    for i = #titles + 1, #ns.subTabs do
        ns.subTabs[i]:Hide()
    end
    LayoutTabs(ns.subTabs, sub, #titles)
    sub:Show()
end

function ns:SetPage(i)
    local n = #ns.pages
    if n == 0 then return end
    i = ((i - 1) % n) + 1
    if i == ns.current then return end
    if ns.current ~= 0 then
        local pf = ns.pageFrames[ns.current]
        local def = ns.pages[ns.current]
        if pf then
            if def.OnHide then def.OnHide(pf) end
            pf:Hide()
        end
    end
    ns.current = i
    ns.subCurrent = 1
    local pf = EnsurePage(i)
    pf:Show()
    ns:UpdateTabs()
    ns:UpdateSubBar()
    local def = ns.pages[i]
    if def.OnShow then def.OnShow(pf) end
    if def.OnSubPage then def.OnSubPage(pf, ns.subCurrent) end
    if ns.db and ns.db.rememberPage then ns.db.lastPage = i end
end

function ns:SetSubPage(i)
    local titles = ns.subTitles
    if not titles or #titles == 0 then return end
    i = ((i - 1) % #titles) + 1
    ns.subCurrent = i
    local def = ns.pages[ns.current]
    if def and def.OnSubPage then def.OnSubPage(ns.pageFrames[ns.current], i) end
    ns:UpdateSubBar()
end

function ns:Open(page)
    if not ns.frame then return end
    ns.frame:Show()
    ns:SetPage(page or (ns.db and ns.db.rememberPage and ns.db.lastPage) or 1)
    ns:UpdateTabs()
    ns:UpdateSubBar()
end

function ns:Close()
    if ns.frame and ns.frame:IsShown() then ns.frame:Hide() end
end

function ns:Toggle()
    if ns.frame and ns.frame:IsShown() then ns:Close() else ns:Open() end
end

function ns:OnShellHide()
    if ns.modal then
        ns.modal:Hide()
        ns.modal = nil
    end
    if ns.current ~= 0 then
        local pf = ns.pageFrames[ns.current]
        local def = ns.pages[ns.current]
        if pf then
            if def.OnHide then def.OnHide(pf) end
            pf:Hide()
        end
        ns.current = 0
    end
end

-- Centered yes/no dialog. A confirms, B/Back cancels; click works too.
function ns:ShowConfirm(text, confirmLabel, onConfirm)
    local c = ns.confirm
    if not c then return end
    c.title:SetText(text)
    c.hint:SetText(("%s %s      %s %s"):format(
        PadGlyph("PAD1", "A"), confirmLabel or OKAY or "OK",
        PadGlyph("PAD2", "B"), CANCEL or "Cancel"))
    c.onConfirm = onConfirm
    ns.modal = c
    c:Show()
end

function ns:OnPadButton(button)
    ns.padCounts[button] = (ns.padCounts[button] or 0) + 1
    local m = ns.modal
    if m and m:IsShown() then
        if button == "PAD1" then
            local fn = m.onConfirm
            m:Hide()
            if fn then fn() end
        elseif button == "PAD2" or button == "PADBACK" then
            m:Hide()
        end
        return
    end
    if button == "PADLSHOULDER" then
        ns:SetPage((ns.current == 0 and 1 or ns.current) - 1)
    elseif button == "PADRSHOULDER" then
        ns:SetPage((ns.current == 0 and 1 or ns.current) + 1)
    elseif button == "PADLTRIGGER" then
        ns:SetSubPage(ns.subCurrent - 1)
    elseif button == "PADRTRIGGER" then
        ns:SetSubPage(ns.subCurrent + 1)
    elseif button == "PAD2" or button == "PADBACK" then
        ns:Close()
    else
        local def = ns.pages[ns.current]
        if def and def.OnPad then def.OnPad(ns.pageFrames[ns.current], button) end
    end
end
