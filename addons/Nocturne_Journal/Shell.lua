local _, ns = ...

local Nocturne = _G.Nocturne
local T = Nocturne.Theme

local HEADER_H = 64
local SUBBAR_H = 44
local TAB_PAD = 16
local TAB_FONT = 26
local GLYPH_FONT = 20

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

-- Binding text for a pad button. The client's markup uses the "Generic"
-- atlases (Gamepad_Gen_1_64...) whose face buttons are drawn as 1/2/3/4, so
-- the letter-style set (Gamepad_Ltr_A_64...) is swapped in when it exists.
local FACE = { PAD1 = "A", PAD2 = "B", PAD3 = "X", PAD4 = "Y" }
local function AtlasExists(markup)
    local atlas = markup:match("|A:([^:|]+)")
    return atlas and C_Texture and C_Texture.GetAtlasInfo
        and C_Texture.GetAtlasInfo(atlas) ~= nil
end
local function PadGlyph(name, fallback)
    local s = GetBindingText and GetBindingText(name)
    if s and (s:find("|T") or s:find("|A")) then
        if s:find("Gamepad_Gen_") then
            local face = FACE[name]
            local ltr = face and s:gsub("Gamepad_Gen_%d_", "Gamepad_Ltr_" .. face .. "_")
                or s:gsub("Gamepad_Gen_", "Gamepad_Ltr_")
            if AtlasExists(ltr) then return ltr end
            if face then return face end
        end
        return s
    end
    return FACE[name] or fallback
end
ns.PadGlyph = PadGlyph

-- Render a stored/pressed sequence ("PADLTRIGGER-PAD1") with the active
-- controller's glyphs.
function ns.SeqGlyphs(seq)
    local out = {}
    for k in seq:gmatch("[^-]+") do
        out[#out + 1] = PadGlyph(k, k:gsub("^PAD", ""))
    end
    return table.concat(out, " + ")
end

-- Forever's native gamepad bars already turn modifier state + button into a
-- bar slot: LT selects the left bar, RT the right bar, LT+RT the bottom bar,
-- none the top bar; the last key picks one of the 8 diamond buttons
-- (dpad 1-4, face buttons 5-8). Placing the item on that storage slot makes
-- the captured chord work outside the journal too.
local BAR_BTN = {
    PADDLEFT = 1,
    PADDUP = 2,
    PADDRIGHT = 3,
    PADDDOWN = 4,
    PAD3 = 5,
    PAD4 = 6,
    PAD2 = 7,
    PAD1 = 8,
}

ns.GamepadBarButtons = BAR_BTN

function ns.GamepadBarSlot(seq)
    local util = _G.GamepadActionBarBindingUtil
    local pu = _G.GamepadMainActionBarFrame
        and _G.GamepadMainActionBarFrame.PageUnit
    if not (util and pu and pu.GetCurrentPage) then return nil end
    local parts = {}
    for k in seq:gmatch("[^-]+") do parts[#parts + 1] = k end
    local btnIdx = BAR_BTN[parts[#parts]]
    if not btnIdx then return nil end
    local lt, rt = false, false
    for i = 1, #parts - 1 do
        if parts[i] == "PADLTRIGGER" then
            lt = true
        elseif parts[i] == "PADRTRIGGER" then
            rt = true
        end
    end
    -- Bar index order: top, left(LT), right(RT), bottom(LT+RT).
    local slotID = ((lt and rt) and 3 or lt and 1 or rt and 2 or 0) * 8
        + btnIdx
    if util.IsReservedPageUnitSlotID(slotID) then return nil end
    local page = pu:GetCurrentPage()
    if not util.IsStandardGamepadPageNum(page) then page = 1 end
    return util.GetGamepadStorageSlotIndexFromPageAndPageUnitSlotID(
        page, slotID)
end

local function SetLabelColor(label, c)
    label:SetTextColor(c[1], c[2], c[3], c[4] or 1)
end

local function CreateTab(parent, index, title, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(parent:GetHeight())
    b.label = T.CreateFontString(b, TAB_FONT)
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
        SetLabelColor(self.label, self.active and T.colors.accent or T.colors.text)
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

-- Character-select style shell backdrop: the glue scene per race lives at
-- Interface\Glues\Models\UI_<race>\. UnitRace file names differ from the
-- folder names for a few races.
local function RaceScene(f)
    local _, race = UnitRace("player")
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    -- Appended one by one: a nil inside a table constructor would stop ipairs.
    local candidates = {}
    if race then
        candidates[#candidates + 1] = "UI_" .. race
    end
    if faction == "Horde" then
        candidates[#candidates + 1] = "UI_Orc"
    elseif faction == "Alliance" then
        candidates[#candidates + 1] = "UI_Human"
    end
    local ok, m = pcall(CreateFrame, "Model", nil, f)
    if not (ok and m) then
        ns.diagScene = "no Model frame (" .. tostring(m) .. ")"
        return
    end
    m:SetAllPoints(f)
    m:SetFrameLevel(f:GetFrameLevel())
    local tried = {}
    for _, dir in ipairs(candidates) do
        if dir and m.SetModel then
            local path = ("Interface\\GLUES\\Models\\%s\\%s.m2"):format(dir, dir)
            local okSet, err = pcall(m.SetModel, m, path)
            local fid = okSet and m.GetModelFileID and m:GetModelFileID()
            tried[#tried + 1] = dir .. "=" .. (okSet and ("ok/id=" .. tostring(fid))
                or tostring(err):sub(1, 60))
            if okSet and (fid == nil or fid ~= 0) then
                pcall(m.SetCamera, m, 0)
                pcall(m.SetSequence, m, 0)
                local veil = m:CreateTexture(nil, "OVERLAY")
                veil:SetAllPoints()
                veil:SetColorTexture(0.02, 0.02, 0.03, 0.72)
                ns.diagScene = ("race=%s -> %s; %s"):format(
                    tostring(race), dir, table.concat(tried, "; "))
                return m
            end
        end
    end
    m:Hide()
    ns.diagScene = ("none (race=%s; %s)"):format(
        tostring(race), table.concat(tried, "; "))
end

-- Dark translucent nine-slice border (the Edit Mode dialogs' look); the
-- tooltip backdrop is the fallback when a template is absent.
local function DlgSkin(f, tpl)
    if f.SetBackdrop then
        f:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background" })
        f:SetBackdropColor(0.07, 0.07, 0.10, 0.94)
    end
    local ok, border = pcall(CreateFrame, "Frame", nil, f, tpl)
    if ok and border then
        border:SetAllPoints(f)
        return
    end
    T.ApplyBackdrop(f)
end

-- Shared dialog chrome: translucent border, a title plaque straddling the
-- top edge (its midline is the border's top bar, ~7px inside the frame
-- edge like the native TitleBox anchor), centered subject/icon slots and
-- white input hints floating under the right edge. Callers add their own
-- content (d.content may replace the body text) and size via ns:FitDialog.
function ns.DressDialog(d)
    DlgSkin(d, "DialogBorderTranslucentTemplate")
    local tb = CreateFrame("Frame", nil, d)
    d.titleBox = tb
    tb:SetFrameLevel(d:GetFrameLevel() + 2)
    tb:SetPoint("CENTER", d, "TOP", 0, -7)
    tb:SetSize(160, 40)
    DlgSkin(tb, "DialogBorderDarkTemplate")
    d.title = T.CreateFontString(tb, 20, T.colors.accent)
    d.title:SetPoint("CENTER", tb)
    d.body = T.CreateFontString(d, 17, T.colors.text)
    d.body:SetPoint("TOP", d, "TOP", 0, -48)
    d.subject = T.CreateFontString(d, 20, T.colors.accent)
    d.subject:SetPoint("TOP", d.body, "BOTTOM", 0, -14)
    d.subject:Hide()
    d.icon = d:CreateTexture(nil, "ARTWORK")
    d.icon:SetSize(35, 35)
    d.icon:SetTexCoord(0.0625, 0.9375, 0.0625, 0.9375)
    d.icon:SetPoint("TOP", d.subject, "BOTTOM", 0, -4)
    d.icon:Hide()
    d.hintFloating = true
    d.hint = T.CreateFontString(d, 15, { 1, 1, 1, 1 })
    d.hint:SetPoint("TOPRIGHT", d, "BOTTOMRIGHT", -6, -10)
    d.hint:SetJustifyH("RIGHT")
    d.err = T.CreateFontString(d, 16, { 0.92, 0.30, 0.25, 1 })
    d.err:SetPoint("TOP", d.body, "BOTTOM", 0, -8)
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
    local rl = T.colors.border

    h.lb = T.CreateFontString(h, GLYPH_FONT, T.colors.textDim)
    h.lb:SetPoint("LEFT", 16, 0)
    h.lb:SetText(PadGlyph("PADLSHOULDER", "LB"))
    h.rb = T.CreateFontString(h, GLYPH_FONT, T.colors.textDim)
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
    sub.lt = T.CreateFontString(sub, GLYPH_FONT, T.colors.textDim)
    sub.lt:SetPoint("LEFT", 16, 0)
    sub.lt:SetText(PadGlyph("PADLTRIGGER", "LT"))
    sub.rt = T.CreateFontString(sub, GLYPH_FONT, T.colors.textDim)
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
    c:EnableMouse(true)
    ns.DressDialog(c)
    c.body:SetJustifyH("CENTER")
    c:SetScript("OnHide", function()
        c.onConfirm = nil
        if ns.modal == c then ns.modal = nil end
        -- Not at once: the confirming press is still down and its release
        -- would hit the freshly rebound pad keys.
        C_Timer.After(0.4, function() ns:UpdatePadMode() end)
    end)
    c:Hide()

    f:SetScript("OnHide", function() ns:OnShellHide() end)

    -- Modal pad input: propagation stays at its default so our presses don't
    -- leak to the world, and it is set once — changing propagation in combat
    -- is restricted. Counters prove in diag that buttons reach us.
    f:EnableGamePadButton(true)
    f:SetScript("OnGamePadButtonDown", function(_, button) ns:OnPadButton(button) end)
    f:SetScript("OnGamePadButtonUp", function(_, button) ns:OnPadButtonUp(button) end)
    if f.EnableGamePadStick then f:EnableGamePadStick(true) end
    ns.stickCounts = {}
    f:SetScript("OnGamePadStick", function(_, stick, x, y)
        ns.stickEvents = true
        ns.stickCounts[stick or "?"] = (ns.stickCounts[stick or "?"] or 0) + 1
        local def = ns.pages[ns.current]
        if def and def.OnStick then
            def.OnStick(ns.pageFrames[ns.current], stick, x, y)
        end
    end)
    -- Forever's native gamepad UI may swallow OnGamePadStick entirely
    -- (sticks drive camera/cursor), so poll the mapped stick state while
    -- the journal is open. Disabled once real stick events arrive.
    local gp = C_GamePad
    ns.padStickBtn = {}
    f:SetScript("OnUpdate", function(_, dt)
        if not (gp and gp.GetActiveDeviceID and gp.GetDeviceMappedState) then return end
        local id = gp.GetActiveDeviceID()
        local state = id and gp.GetDeviceMappedState(id)
        if not state then return end
        -- Stick clicks never reach OnGamePadButtonDown (client bindings eat
        -- them) and override bindings for them don't take. The mapped state
        -- still reports them, so detect edges ourselves.
        if state.buttons and gp.ButtonIndexToConfigName then
            ns.diagPadBtns = ns.diagPadBtns or {}
            ns.heldSeen = ns.heldSeen or {}
            ns.padHeld = ns.padHeld or {}
            wipe(ns.padHeld)
            for i = 1, #state.buttons do
                local name = gp.ButtonIndexToConfigName(i)
                if name then
                    ns.diagPadBtns[i] = name
                    if state.buttons[i] then
                        ns.padHeld[name] = true
                        ns.heldSeen[name] = true
                    end
                    -- PADLSTICK/PADRSTICK are the L3/R3 clicks; the
                    -- PADxSTICK<dir> entries are axis directions.
                    local k = (name == "PADLSTICK" or name == "PADRSTICK")
                        and name or nil
                    if k then
                        local down = state.buttons[i] and true or false
                        local was = ns.padStickBtn[i]
                        if down ~= was then
                            ns.padStickBtn[i] = down
                            if down then
                                ns:OnPadButton(k)
                            else
                                ns:OnPadButtonUp(k)
                            end
                        end
                    end
                end
            end
            ns:UpdateChordBinds()
        end
        if ns.stickEvents then return end
        if not (state and state.sticks) then return end
        if not ns.stickIdxR then
            for i = 1, #state.sticks do
                local name = gp.StickIndexToConfigName
                    and gp.StickIndexToConfigName(i) or ""
                if name:find("Right") or name:find("Camera") then
                    ns.stickIdxR = i
                elseif name:find("Left") or name:find("Movement") then
                    ns.stickIdxL = i
                end
            end
            ns.stickIdxR = ns.stickIdxR or math.min(2, #state.sticks)
            ns.stickIdxL = ns.stickIdxL or 1
        end
        local def = ns.pages[ns.current]
        if not (def and def.OnStick) then return end
        for i = 1, 2 do
            local s = state.sticks[i == 1 and ns.stickIdxL or ns.stickIdxR]
            local x, y = s and s.x or 0, s and s.y or 0
            if not ns.IsSecret(x) and not ns.IsSecret(y)
                and (x > 0.15 or x < -0.15 or y > 0.15 or y < -0.15) then
                def.OnStick(ns.pageFrames[ns.current],
                    i == 1 and "LeftStick" or "RightStick", x, y, dt)
            end
        end
    end)
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
        SetLabelColor(t.label, t.active and T.colors.accent or T.colors.text)
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
        SetLabelColor(t.label, t.active and T.colors.accent or T.colors.text)
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
    ns:UpdatePadMode()
    if ns.db and ns.db.rememberPage then ns.db.lastPage = i end
end

function ns:SetSubPage(i)
    local titles = ns.subTitles
    if not titles or #titles == 0 then return end
    i = ((i - 1) % #titles) + 1
    ns.subCurrent = i
    local def = ns.pages[ns.current]
    if def and def.OnSubPage then def.OnSubPage(ns.pageFrames[ns.current], i) end
    ns:UpdatePadMode()
    ns:UpdateSubBar()
end

function ns:Open(page)
    if not ns.frame then return end
    -- Built on first open, once the player's race is surely known.
    if not ns.sceneBuilt then
        ns.sceneBuilt = true
        ns.scene = RaceScene(ns.frame)
    end
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
    if ns.seqBind then ns:CloseSeqBind() end
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
    ns:UpdatePadMode()
end

-- Centered yes/no dialog. A confirms, B/Back cancels; click works too.
-- Inline pad glyphs are ~24px while the font line is ~15, so rows with
-- atlas escapes need extra measured height/width.
local function DlgTextH(fs)
    local t = fs:GetText() or ""
    if t == "" then return 0 end
    local h = fs:GetStringHeight()
    local lineH = (fs.GetLineHeight and fs:GetLineHeight()) or 15
    for line in t:gmatch("[^\n]+") do
        if line:find("|A:", 1, true) then
            h = h + math.max(0, 24 - lineH)
        end
    end
    return h
end

local function DlgTextW(fs)
    local t = fs:GetText() or ""
    if t == "" then return 0 end
    local w = fs:GetStringWidth()
    for _ in t:gmatch("|A:") do w = w + 24 end
    return w
end

-- Shrink-wrap a title/body/err/hint dialog to its content (AGENTS.md dialog
-- rule: 16px padding, sections 16px apart, err 8px under the body). A shown
-- d.content frame (sized by the caller) stands in for the body text.
function ns:FitDialog(d)
    local content = d.content and d.content:IsShown() and d.content
    local bodyH = content and content:GetHeight() or DlgTextH(d.body)
    local bodyW = content and content:GetWidth() or DlgTextW(d.body)
    if d.titleBox then
        d.titleBox:SetSize(math.max(80, DlgTextW(d.title) + 32),
            math.max(30, DlgTextH(d.title) + 32))
    end
    -- Plaque dialogs: content padded 48px on every side
    -- from the frame edges, hints float outside. Others: 16px padding,
    -- in-frame title and hints.
    local pad = d.titleBox and 48 or 16
    local padY = d.titleBox and 48 or 16
    if d.titleBox then
        for _, w in ipairs({ d.body, d.content }) do
            if w then
                w:ClearAllPoints()
                w:SetPoint("TOP", d, "TOP", 0, -padY)
            end
        end
    end
    local h = (d.titleBox and padY or 16 + DlgTextH(d.title) + 16) + bodyH
    local below = content or d.body
    if d.subject and d.subject:IsShown() then
        d.subject:ClearAllPoints()
        d.subject:SetPoint("TOP", below, "BOTTOM", 0, -14)
        h = h + 14 + DlgTextH(d.subject)
        below = d.subject
        if d.icon and d.icon:IsShown() then
            d.icon:ClearAllPoints()
            d.icon:SetPoint("TOP", d.subject, "BOTTOM", 0, -4)
            h = h + 4 + d.icon:GetHeight()
            below = d.icon
        end
    end
    if d.err then
        d.err:ClearAllPoints()
        d.err:SetPoint("TOP", below, "BOTTOM", 0, -8)
        if DlgTextH(d.err) > 0 then
            h = h + 8 + DlgTextH(d.err)
        end
    end
    h = h + padY
    if not d.hintFloating then
        h = h + math.max(DlgTextH(d.hint), 8) + padY
    end
    d:SetHeight(math.max(80, h))
    local w = math.max(DlgTextW(d.title), bodyW,
        d.subject and d.subject:IsShown() and DlgTextW(d.subject) or 0,
        d.err and DlgTextW(d.err) or 0,
        d.hintFloating and 0 or DlgTextW(d.hint)) + pad * 2
    d:SetWidth(math.max(200, math.min(w, 640)))
end

function ns:ShowConfirm(text, detail, confirmLabel, onConfirm)
    local c = ns.confirm
    if not c then return end
    c.title:SetText(text)
    c.body:SetText(detail or "")
    ns:FitDialog(c)
    c.hint:SetText(("%s %s      %s %s"):format(
        PadGlyph("PAD1", "A"), confirmLabel or OKAY or "OK",
        PadGlyph("PAD2", "B"), CANCEL or "Cancel"))
    c.onConfirm = onConfirm
    ns.modal = c
    c:Show()
    ns:UpdatePadMode()
end

-- LT/RT switch the sub-page on release, and only when nothing else was done
-- while they were held (a page may use RT + stick as a modifier).
ns.trigDown, ns.trigUsed = {}, {}

function ns:OnPadButtonUp(button)
    if ns.padHeldKeys then ns.padHeldKeys[button] = nil end
    if ns.trigDown[button] then
        ns.trigDown[button] = nil
        -- A trigger pressed before the dialog opened still owes the
        -- capture its release — otherwise st.held keeps it forever.
        if ns.padCapture then
            ns.padCapture(button, false)
            return
        end
        if not ns.trigUsed[button]
            and not (ns.modal and ns.modal:IsShown()) then
            -- A page may turn its own leaves instead (Abilities: book
            -- spreads); OnTrigger returns true when it took the press.
            local dir = button == "PADRTRIGGER" and 1 or -1
            local def = ns.pages[ns.current]
            if not (def and def.OnTrigger
                    and def.OnTrigger(ns.pageFrames[ns.current], dir)) then
                ns:SetSubPage(ns.subCurrent + dir)
            end
        end
        return
    end
    if button == "PADLSTICK" or button == "PADRSTICK" then
        local now = GetTime()
        ns.stickDedupUp = ns.stickDedupUp or {}
        if ns.stickDedupUp[button] and now - ns.stickDedupUp[button] < 0.08 then
            return
        end
        ns.stickDedupUp[button] = now
    end
    if ns.padCapture then
        ns.padCapture(button, false)
        return
    end
    local def = ns.pages[ns.current]
    if def and def.OnPadUp then
        def.OnPadUp(ns.pageFrames[ns.current], button)
    end
end

-- Pad "bind mode". While the shell frame has EnableGamePadButton on, every
-- press is consumed by OnGamePadButtonDown and never reaches the keybinding
-- dispatcher (SetPropagateKeyboardInput is keyboard-only), so a secure
-- button can't be clicked from the pad. A page that needs that
-- (def.PadBind) switches the shell to override bindings instead: PAD3 clicks
-- the page's secure button, every other key clicks a forwarding button that
-- feeds the same OnPadButton/OnPadButtonUp handlers. Frames keep the pad
-- sticks either way.
local PAD_KEYS = {
    "PAD1", "PAD2", "PAD3", "PAD4", "PADDUP", "PADDDOWN", "PADDLEFT",
    "PADDRIGHT", "PADLSHOULDER", "PADRSHOULDER", "PADLTRIGGER",
    "PADRTRIGGER", "PADBACK",
}
-- Stick clicks (L3/R3) carry client bindings (ping etc.), so they never
-- reach OnGamePadButtonDown. They are override-bound for the whole time the
-- journal is open, not just in PadBind mode. Button polling in OnUpdate is
-- the actual delivery path; these bindings mainly keep the client function
-- (e.g. ping) from firing while the journal is open.
local STICK_KEYS = { "PADLSTICK", "PADRSTICK" }
local padOwner = CreateFrame("Frame")
local stickOwner = CreateFrame("Frame")
local bindOwner = CreateFrame("Frame")
local chordOwner = CreateFrame("Frame")
local function PadForward(key)
    local b = CreateFrame("Button", "NocturneJournalPad_" .. key, UIParent)
    b:SetSize(1, 1)
    b:SetAlpha(0)
    b:EnableMouse(false)
    b:RegisterForClicks("AnyDown", "AnyUp")
    b:SetScript("OnClick", function(_, _, down)
        if not (ns.frame and ns.frame:IsShown()) then return end
        local k = "bind:" .. key
        ns.padCounts[k] = (ns.padCounts[k] or 0) + 1
        if down then ns:OnPadButton(key) else ns:OnPadButtonUp(key) end
    end)
end
for _, key in ipairs(PAD_KEYS) do PadForward(key) end
for _, key in ipairs(STICK_KEYS) do PadForward(key) end

function ns:UpdatePadMode()
    if not ns.frame or InCombatLockdown() then return end
    -- Stick-click overrides follow the journal's own visibility; unlike
    -- PadBind they are needed in every mode.
    local shown = ns.frame:IsShown() and true or false
    if shown ~= (ns.stickBound or false) then
        ns.stickBound = shown
        ClearOverrideBindings(stickOwner)
        if shown then
            for _, key in ipairs(STICK_KEYS) do
                SetOverrideBindingClick(stickOwner, true, key,
                    "NocturneJournalPad_" .. key, "LeftButton")
            end
        end
    end
    -- Item binds live on their own owner so PadBind flips don't drop them.
    if shown ~= (ns.bindsBound or false) then
        ns.bindsBound = shown
        ClearOverrideBindings(bindOwner)
        if shown and ns.invApplyBinds then ns.invApplyBinds(bindOwner) end
    end
    if not shown then
        ClearOverrideBindings(chordOwner)
        ns.chordSig, ns.padHeld, ns.padHeldKeys = nil, nil, nil
    end
    local def = ns.pages[ns.current]
    local want = ns.frame:IsShown() and def and def.PadBind
        and not (ns.modal and ns.modal:IsShown())
        and def.PadBind(ns.pageFrames[ns.current]) and true or false
    if want == (ns.padBind or false) then return end
    ns.padBind = want
    ns.frame:EnableGamePadButton(not want)
    ClearOverrideBindings(padOwner)
    if def and def.OnPadReset then def.OnPadReset(ns.pageFrames[ns.current]) end
    if want then
        for _, key in ipairs(PAD_KEYS) do
            SetOverrideBindingClick(padOwner, true, key,
                "NocturneJournalPad_" .. key, "LeftButton")
        end
        -- A page may claim keys for its own secure buttons (Abilities:
        -- PAD1 casts the selected spell); the default claims PAD3 for the
        -- inventory item-use button.
        if def.PadBindKeys then
            def.PadBindKeys(ns.pageFrames[ns.current], padOwner)
        else
            SetOverrideBindingClick(padOwner, true, "PAD3",
                "NocturneJournalPadUse", "LeftButton")
        end
    end
end

_G.Nocturne.RegisterEvent("PLAYER_REGEN_ENABLED", function() ns:UpdatePadMode() end)

function ns:ReapplyItemBinds()
    if not ns.bindsBound or InCombatLockdown() then return end
    ClearOverrideBindings(bindOwner)
    if ns.invApplyBinds then ns.invApplyBinds(bindOwner) end
    ns.chordSig = nil -- force the chord re-map to pick up the change
end

-- The client rejects modifier chords in override bindings, so chord item
-- binds are handled dynamically: while the bind's modifiers are held the
-- poll above re-points the chord's last key at the bind's secure button.
-- Plain keys go back to normal as soon as the modifiers are released.
local function IsHeld(name)
    return (ns.padHeld and ns.padHeld[name])
        or (ns.padHeldKeys and ns.padHeldKeys[name]) or nil
end

ns.IsPadHeld = function(name) return IsHeld(name) and true or false end

function ns:UpdateChordBinds()
    local want = {}
    local ui = ns.invUI
    if not ns.padCapture and (ns.padHeld or ns.padHeldKeys)
        and ui and ui.bindBtnFor
        and ns.chardb and ns.chardb.binds then
        local best = {}
        for seq in pairs(ns.chardb.binds) do
            local mods, last = seq:match("^(.+)-([^-]+)$")
            if mods and ui.bindBtnFor[seq] then
                local n, ok = 0, true
                for m in mods:gmatch("[^-]+") do
                    if IsHeld(m) then
                        n = n + 1
                    else
                        ok = false
                        break
                    end
                end
                -- Prefer the longest matching modifier set per key.
                if ok and (not best[last] or n > best[last].n) then
                    best[last] = { n = n, seq = seq }
                end
            end
        end
        for last, t in pairs(best) do want[last] = t.seq end
    end
    local parts = {}
    for last, seq in pairs(want) do
        parts[#parts + 1] = last .. "=" .. seq
    end
    table.sort(parts)
    local sig = table.concat(parts, ";")
    if sig == (ns.chordSig or "") then return end
    if InCombatLockdown() then return end -- retried on a later frame
    ns.chordSig = sig
    ns.chordApplies = (ns.chordApplies or 0) + 1
    ClearOverrideBindings(chordOwner)
    for last, seq in pairs(want) do
        SetOverrideBindingClick(chordOwner, true, last,
            ui.bindBtnFor[seq]:GetName(), "LeftButton")
    end
end

function ns:OnPadButton(button)
    ns.padHeldKeys = ns.padHeldKeys or {}
    ns.padHeldKeys[button] = true
    -- Stick clicks arrive twice on Forever: once from the override binding
    -- and once from the mapped-state poll. Drop the second delivery.
    if button == "PADLSTICK" or button == "PADRSTICK" then
        local now = GetTime()
        ns.stickDedup = ns.stickDedup or {}
        if ns.stickDedup[button] and now - ns.stickDedup[button] < 0.08 then
            return
        end
        ns.stickDedup[button] = now
    end
    ns.padCounts[button] = (ns.padCounts[button] or 0) + 1
    for t in pairs(ns.trigDown) do ns.trigUsed[t] = true end
    -- A page dialog (split/bind) swallows every press while it is open.
    if ns.padCapture then
        ns.padCapture(button, true)
        return
    end
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
    elseif button == "PADLTRIGGER" or button == "PADRTRIGGER" then
        ns.trigDown[button], ns.trigUsed[button] = true, nil
    elseif button == "PAD2" or button == "PADBACK" then
        -- A page may claim B for itself (Inventory: destroy); Select always closes.
        local def = ns.pages[ns.current]
        if button == "PAD2" and def and def.OnCancel
            and def.OnCancel(ns.pageFrames[ns.current]) then
            return
        end
        ns:Close()
    else
        local def = ns.pages[ns.current]
        if def and def.OnPad then def.OnPad(ns.pageFrames[ns.current], button) end
    end
end

-- A pressed sequence maps to a native gamepad-bar storage slot when the
-- last key is a bar button and the modifiers are LT/RT only. Modifier
-- order doesn't matter: GamepadBarSlot reads them as flags.
function ns.BarSeqSlot(seq)
    if not BAR_BTN[seq[#seq]] then return nil end
    for i = 1, #seq - 1 do
        if seq[i] ~= "PADLTRIGGER" and seq[i] ~= "PADRTRIGGER" then
            return nil
        end
    end
    return ns.GamepadBarSlot(table.concat(seq, "-"))
end

function ns.PickupSpellID(id)
    if C_Spell and C_Spell.PickupSpell then
        C_Spell.PickupSpell(id)
    elseif PickupSpellByID then
        PickupSpellByID(id)
    elseif PickupSpell then
        PickupSpell(id)
    end
end

-- Put whatever `pickup` leaves on the cursor into the bar storage slot.
function ns.BarPlace(slot, pickup)
    if InCombatLockdown() then return false end
    local util = _G.GamepadActionBarBindingUtil
    if util and util.AssignActionToGamepadStandardSlot then
        local ok = pcall(util.AssignActionToGamepadStandardSlot, slot, pickup)
        if ClearCursor then ClearCursor() end
        return ok
    end
    if not PlaceAction then return false end
    local ok = pcall(function()
        pickup()
        if GetCursorInfo and GetCursorInfo() then PlaceAction(slot) end
        if ClearCursor then ClearCursor() end
    end)
    return ok
end

-- Swap the contents of two bar storage slots (or move into an empty one):
-- PlaceAction leaves the displaced action on the cursor, so a second
-- PlaceAction drops it back on the source slot.
function ns.BarMove(src, dst)
    if InCombatLockdown() or not (PickupAction and PlaceAction) then
        return false
    end
    return pcall(function()
        PickupAction(src)
        if not (GetCursorInfo and GetCursorInfo()) then return end
        PlaceAction(dst)
        if GetCursorInfo() then PlaceAction(src) end
        if ClearCursor then ClearCursor() end
    end)
end

function ns.BarClear(slot)
    if InCombatLockdown() then return false end
    local util = _G.GamepadActionBarBindingUtil
    if util and util.ClearActionFromGamepadSlot then
        return pcall(util.ClearActionFromGamepadSlot, slot)
    end
    if not PickupAction then return false end
    return pcall(function()
        PickupAction(slot)
        if ClearCursor then ClearCursor() end
    end)
end

-- Shared combination-capture dialog (Abilities: bind a spell / edit the
-- action bars; Inventory: bind a usable item). The caller drives the state
-- machine: onSeq gets the ordered key list and returns an error string to
-- show or nil to accept; onButton runs on each down first and may eat the
-- press (returns true). Centered like the native bind UI: title plaque on
-- the top edge, action name+icon centered in the body, input hints in a
-- bar below, action tooltip anchored flush right (ns.TipRight).
local seqDlg

local function EnsureSeqDlg()
    if seqDlg then return seqDlg end
    local d = CreateFrame("Frame", "NocturneJournalSeqBind", ns.frame)
    seqDlg = d
    ns.seqDlg = d
    d:SetPoint("CENTER", 0, 0)
    d:SetSize(430, 170)
    d:SetFrameLevel(ns.header:GetFrameLevel() + 50)
    d:EnableMouse(true)
    ns.DressDialog(d)
    d:Hide()
    return d
end

-- The native gamepad bars sit under the journal's fullscreen layer; while
-- a bind/edit dialog is open they are raised above it so the slots being
-- edited are visible. Prior visibility and layering are restored on close.
-- Only GamepadMainActionBarFrame is touched: it parents every bar cluster
-- (PageUnit + possess/stance/targeting bars). GamepadActionBarEditFrame is
-- deliberately left alone -- its OnShow activates input binding groups and
-- its OnHide writes PageUnit fields; both reach forbidden APIs or taint
-- the secure click path when driven from addon code.
local function GamepadBarFrames()
    local f = _G.GamepadMainActionBarFrame
    if f then return { f } end
    return {}
end

-- Tooltip flush right of the dialog, top edges aligned (native bind UI
-- look). ANCHOR_NONE, not ANCHOR_RIGHT: that preset vertically CENTERS the
-- tooltip on the owner and is re-applied by the engine on Show/resize —
-- a scaled-up tooltip taller than the dialog ends up floating above it.
function ns.TipRight(d)
    GameTooltip:SetOwner(d, "ANCHOR_NONE")
    GameTooltip:ClearAllPoints()
    GameTooltip:SetPoint("TOPLEFT", d, "TOPRIGHT", 8, 0)
end

local function BarsVisible(show)
    ns.seqBars = ns.seqBars or {}
    for _, f in ipairs(GamepadBarFrames()) do
        if show and not ns.seqBars[f] then
            local ok, s = pcall(function()
                return { f:IsShown(), f:GetFrameStrata(),
                    f:GetFrameLevel() }
            end)
            if ok then
                ns.seqBars[f] = s
                pcall(function()
                    f:Show()
                    f:SetFrameStrata("FULLSCREEN_DIALOG")
                    f:SetFrameLevel(ns.frame:GetFrameLevel() + 30)
                end)
            end
        elseif not show and ns.seqBars[f] then
            local s = ns.seqBars[f]
            ns.seqBars[f] = nil
            pcall(function()
                f:SetFrameStrata(s[2])
                f:SetFrameLevel(s[3])
                if not s[1] then f:Hide() end
            end)
        end
    end
end

-- Modifier highlight driven from our own held state (LT -> left bar, RT ->
-- right, both -> bottom, none -> top; same mapping as GamepadBarSlot).
-- The native mixins are off-limits: SetActiveActionBar writes
-- PageUnit.activeBar and Show/HideHighlight write actionBarScaledUp -- Lua
-- fields on secure-path objects. Addon-tainted values read by
-- PressActionButton -> actionButton:Click -> UseAction turn the next real
-- bar press into ADDON_ACTION_FORBIDDEN. So the visuals are replicated
-- with engine calls only (child show/hide, frame level): native values are
-- read, never written. HIGHLIGHT_*_FRAME_LEVEL are file-local in
-- ActionBar.lua: 5 active, 4 inactive.
local BAR_KEYS = { "topBar", "leftBar", "rightBar", "bottomBar" }

local function BarVisual(bar, on)
    pcall(function()
        local ab = bar.pagingUnitOwner and bar.pagingUnitOwner:GetParent()
        local icons = on and ab and ab.showButtonIcons and ab.shouldExpand
        local n = _G.Constants
            and _G.Constants.GamepadActionBarConstants
            and _G.Constants.GamepadActionBarConstants
            .NUM_SLOTS_PER_GAMEPAD_ACTION_BAR_GROUP or 4
        for i = 1, n do
            local nm = "ActionButton" .. i
            for _, g in ipairs({ bar.Left, bar.Right }) do
                local ic = g and g[nm] and g[nm].ButtonIcon
                if ic then
                    if icons then ic:Show() else ic:Hide() end
                end
            end
        end
        bar:SetFrameLevel(on and 5 or 4)
        local bg = bar.BackgroundFocus
        if bg then
            if on and (not ab or ab.showHighlight) then
                bg:Show()
            else
                bg:Hide()
            end
        end
        local lbf, rbf = bar.LeftButtonFrame, bar.RightButtonFrame
        if lbf then lbf:Hide() end
        if rbf then rbf:Hide() end
    end)
end

-- Held state comes from IsKeyDown (physical state, the same source the
-- native GamepadMode modifier checks use) — event-held tables can desync
-- when an up-event is eaten, and the polled padHeld misreports triggers
-- on Forever (LT alone reads as LT+RT).
local function ModHeld(name)
    if IsKeyDown and IsKeyDown(name) then return true end
    if ns.seqBind and ns.seqBind.held[name] then return true end
    return ns.padHeldKeys and ns.padHeldKeys[name] or false
end

local function SyncBarMods()
    local pu = _G.GamepadMainActionBarFrame
        and _G.GamepadMainActionBarFrame.PageUnit
    local bars = pu and pu.actionBars
    if not bars then return end
    local lt = ModHeld("PADLTRIGGER")
    local rt = ModHeld("PADRTRIGGER")
    local active = (lt and rt and bars.bottomBar) or (lt and bars.leftBar)
        or (rt and bars.rightBar) or bars.topBar
    local compact = pu.ShouldUseCompactLayout
        and pu:ShouldUseCompactLayout()
    for _, key in ipairs(BAR_KEYS) do
        local bar = bars[key]
        if bar then
            if compact then pcall(bar.SetShown, bar, bar == active) end
            BarVisual(bar, bar == active)
        end
    end
end

-- opts: title/body/hint text; tip(owner) anchors a tooltip to the dialog;
-- live keeps capturing after each resolved sequence; onLive(seq) previews
-- the pressed keys; onSeq/onButton/onClose drive the caller's state.
function ns:OpenSeqBind(opts)
    local d = EnsureSeqDlg()
    local st = { seq = {}, held = {}, opts = opts }
    ns.seqBind = st
    d.title:SetText(opts.title or "")
    d.body:SetText(opts.body or "")
    d.err:SetText("")
    d.subject:SetText(opts.subject or "")
    d.subject:SetShown(opts.subject ~= nil)
    if opts.icon then d.icon:SetTexture(opts.icon) end
    d.icon:SetShown(opts.icon ~= nil)
    d.hint:SetText(opts.hint or
        (PadGlyph("PAD2", "B") .. "  " .. (CANCEL or "Cancel")))
    ns:FitDialog(d)
    d:Show()
    BarsVisible(true)
    SyncBarMods()
    if opts.tip then opts.tip(d) end
    ns.padCapture = function(btn, down)
        local o = ns.seqBind and ns.seqBind.opts
        if not o then
            ns.padCapture = nil
            return
        end
        C_Timer.After(0, SyncBarMods)
        if down then
            -- Modifiers already held when the chord starts (e.g. held while
            -- the dialog opened) produce no down event — fold them into the
            -- sequence so "held LT + press X" resolves to the LT bar.
            if BAR_BTN[btn] and #st.seq == 0 then
                for _, m in ipairs({ "PADLTRIGGER", "PADRTRIGGER" }) do
                    if ModHeld(m) then
                        st.held[m] = true
                        st.seq[#st.seq + 1] = m
                    end
                end
            end
            if o.onButton and o.onButton(btn, st) then return end
            -- B cancels like the native bind UI — but only as the first
            -- key, so LT/RT + B stays a valid bar combination.
            if btn == "PADBACK" or (btn == "PAD2" and #st.seq == 0) then
                st.cancel = true
                return
            end
            if btn == "PADLTRIGGER" or btn == "PADRTRIGGER" or BAR_BTN[btn] then
                st.held[btn] = true
                if #st.seq < 3 then st.seq[#st.seq + 1] = btn end
                if o.onLive then o.onLive(st.seq) end
            end
            return
        end
        st.held[btn] = nil
        local seq = st.seq
        if st.cancel then
            if next(st.held) then return end
            st.cancel = nil
            ns:CloseSeqBind()
            return
        end
        -- A chord completes when its last-pressed key is released, or when
        -- nothing is held anymore; a leftover modifier tail is dropped.
        local last = seq[#seq]
        local complete = (btn == last and BAR_BTN[btn])
            or not next(st.held)
        if not complete then return end
        st.seq = {}
        if not last or last == "PADLTRIGGER" or last == "PADRTRIGGER" then
            return
        end
        local err = o.onSeq and o.onSeq(seq)
        d.err:SetText(err or "")
        ns:FitDialog(d)
        if err then return end
        if not o.live then ns:CloseSeqBind() end
    end
    ns:UpdatePadMode()
end

function ns:CloseSeqBind()
    local st = ns.seqBind
    ns.seqBind = nil
    ns.padCapture = nil
    GameTooltip:Hide()
    if ns.SetTipScale then ns.SetTipScale(1) end
    BarsVisible(false)
    SyncBarMods()
    if seqDlg then seqDlg:Hide() end
    if st and st.opts.onClose then st.opts.onClose() end
    ns:UpdatePadMode()
end
