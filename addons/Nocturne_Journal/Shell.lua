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
    T.ApplyBackdrop(c)
    c:EnableMouse(true)
    -- Dialog layout rule (AGENTS.md): 16px padding all around; title, body,
    -- then a right-aligned button bar, each section 16px apart; frame size
    -- shrink-wraps the content.
    c.title = T.CreateFontString(c, 17, T.colors.text)
    c.title:SetPoint("TOP", 0, -16)
    c.title:SetJustifyH("CENTER")
    c.body = T.CreateFontString(c, 15, T.colors.accent)
    c.body:SetPoint("TOP", c.title, "BOTTOM", 0, -16)
    c.body:SetJustifyH("CENTER")
    c.hint = T.CreateFontString(c, 14, T.colors.textDim)
    c.hint:SetPoint("BOTTOMRIGHT", -16, 16)
    c.hint:SetJustifyH("RIGHT")
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
    local h = 16 + DlgTextH(d.title) + 16 + bodyH
    if d.err and DlgTextH(d.err) > 0 then
        h = h + 8 + DlgTextH(d.err)
    end
    h = h + 16 + math.max(DlgTextH(d.hint), 8) + 16
    d:SetHeight(math.max(80, h))
    local w = math.max(DlgTextW(d.title), bodyW,
        d.err and DlgTextW(d.err) or 0, DlgTextW(d.hint)) + 32
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
        if not ns.trigUsed[button] and not ns.padCapture
            and not (ns.modal and ns.modal:IsShown()) then
            ns:SetSubPage(ns.subCurrent + (button == "PADRTRIGGER" and 1 or -1))
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
    "PAD1", "PAD2", "PAD4", "PADDUP", "PADDDOWN", "PADDLEFT", "PADDRIGHT",
    "PADLSHOULDER", "PADRSHOULDER", "PADLTRIGGER", "PADRTRIGGER", "PADBACK",
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
        SetOverrideBindingClick(padOwner, true, "PAD3",
            "NocturneJournalPadUse", "LeftButton")
        for _, key in ipairs(PAD_KEYS) do
            SetOverrideBindingClick(padOwner, true, key,
                "NocturneJournalPad_" .. key, "LeftButton")
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
