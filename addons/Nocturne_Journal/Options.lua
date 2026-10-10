local _, ns = ...

local Nocturne = _G.Nocturne

function ns:InitOptions()
    local s = Nocturne.NewSettings("Nocturne: Journal", "NocturneJournal_", ns.db, ns.defaults,
        function()
            ns:SyncMapBinding()
        end)
    ns.category = s.category

    s:Checkbox("takeMapKey", "Open with the map key",
        "The keys bound to 'Toggle World Map' open the journal instead. The world map itself is left alone.")
    s:Checkbox("rememberPage", "Remember last page",
        "The journal reopens on the page you used last instead of always starting on the map.")

    s:Finish()
end

function ns:OpenOptions()
    Nocturne.OpenSettings(ns.category)
end

function ns:DiagText()
    local L = {}
    local function add(s) L[#L + 1] = s end

    local interface = select(4, GetBuildInfo())
    add(("interface=%s forever=%s gamepadUI=%s"):format(
        tostring(interface), tostring(Nocturne.IS_FOREVER), tostring(Nocturne.GamepadUI())))
    add(("shown=%s page=%d (%s) sub=%d"):format(
        tostring(ns.frame and ns.frame:IsShown() or false),
        ns.current,
        (ns.current ~= 0 and ns.pages[ns.current]) and ns.pages[ns.current].title or "-",
        ns.subCurrent))
    add("takeMapKey=" .. tostring(ns.db and ns.db.takeMapKey))
    if ns.mapBindingPending then
        add("map keys: pending (combat)")
    else
        add("map keys: " .. (#ns.diagMapKeys > 0 and table.concat(ns.diagMapKeys, ", ") or "none bound"))
    end
    for _, k in ipairs({ "PAD1", "PAD2", "PAD3", "PAD4", "PADDUP", "PADLTRIGGER", "PADLSHOULDER" }) do
        local raw = GetBindingText and GetBindingText(k)
        add(("glyph %s: raw=[%s] used=[%s]"):format(k,
            tostring(raw):gsub("|", "||"), tostring(ns.PadGlyph(k)):gsub("|", "||")))
    end
    add("pad input:")
    local any
    for button, count in pairs(ns.padCounts) do
        add(("  %s x%d"):format(button, count))
        any = true
    end
    if not any then add("  (nothing received yet)") end
    add(("stick: api=%s events=%s pollIdx=%s"):format(
        tostring(not not (C_GamePad and C_GamePad.GetDeviceMappedState)),
        tostring(ns.stickEvents or false),
        tostring(ns.stickIdxL) .. "/" .. tostring(ns.stickIdxR)))
    for name, count in pairs(ns.stickCounts or {}) do
        add(("  %s x%d"):format(name, count))
    end
    if ns.diagPadBtns then
        local names = {}
        for i, name in pairs(ns.diagPadBtns) do
            names[#names + 1] = ("%s=%s"):format(tostring(i), tostring(name))
        end
        table.sort(names)
        add("pad buttons: " .. table.concat(names, ", "))
    end
    add("atlases:")
    for i, def in ipairs(ns.pages) do
        add(("  %s: %s"):format(def.title, tostring(ns.diagAtlas[def.key] or "-")))
    end
    if ns.chardb then
        local pend = 0
        for _ in pairs(ns.chardb.pending) do pend = pend + 1 end
        add(("archive: %d completed, %d pending, %d historical"):format(
            #ns.chardb.completed, pend, #ns.HistoricalIDs()))
    end
    if ns.questUI then
        add(("quest list: %d rows, selected=%s, dirty=%s"):format(
            #ns.questUI.list.items,
            tostring(ns.questUI.selected and ns.questUI.selected.qid),
            tostring(ns.questListDirty)))
    end
    add("scene: " .. tostring(ns.diagScene or "-"))
    if ns.invUI and ns.invUI.sbar then
        local ui = ns.invUI
        local lo, hi = ui.sbar:GetMinMaxValues()
        local th = ui.sbar:GetThumbTexture()
        add(("invBar: shown=%s h=%.0f range=%.0f..%.0f thumbH=%s scrollH=%.0f childH=%.0f"):format(
            tostring(ui.sbar:IsShown()), ui.sbar:GetHeight(), lo, hi,
            th and ("%.0f"):format(th:GetHeight()) or "nil",
            ui.scroll:GetHeight(), ui.child:GetHeight()))
        local function Box(f)
            return ("L%.0f R%.0f T%.0f B%.0f"):format(
                f:GetLeft() or -1, f:GetRight() or -1,
                f:GetTop() or -1, f:GetBottom() or -1)
        end
        add(("invBarBox: bar[%s] vis=%s alpha=%.2f lvl=%d thumbShown=%s thumb[%s]"):format(
            Box(ui.sbar), tostring(ui.sbar:IsVisible()),
            ui.sbar:GetEffectiveAlpha(), ui.sbar:GetFrameLevel(),
            tostring(th and th:IsShown()), th and Box(th) or "-"))
        add("invBarSnapshot(0.3s after show): " .. tostring(ui.barSnap))
        add(("invScrollBox: scroll[%s] screen=%.0fx%.0f"):format(
            Box(ui.scroll), UIParent:GetWidth(), UIParent:GetHeight()))
    end
    if ns.chardb and ns.chardb.binds then
        local t = {}
        for k, v in pairs(ns.chardb.binds) do
            local act = GetBindingAction
                and GetBindingAction(k, true) or "?"
            t[#t + 1] = ("%s->%s [%s]"):format(k, tostring(v), tostring(act))
        end
        table.sort(t)
        add("item binds: " .. (#t > 0 and table.concat(t, ", ") or "none"))
        local held = {}
        for k in pairs(ns.heldSeen or {}) do held[#held + 1] = k end
        table.sort(held)
        add("held seen: " .. (#held > 0 and table.concat(held, ",") or "none"))
        add(("chord: sig=%q applies=%d bindClicks=%d"):format(
            ns.chordSig or "", ns.chordApplies or 0, ns.bindClicks or 0))
    end
    if ns.abUI then
        local ui = ns.abUI
        add(("abilities: tab=%s items=%d selected=%s"):format(
            tostring(ui.tab and ui.tab.name),
            ui.items and #ui.items or -1,
            tostring(ui.selected and ui.selected.info
                and ui.selected.info.name)))
        local function Box(f)
            if not f then return "-" end
            return ("L%.0f R%.0f T%.0f B%.0f"):format(
                f:GetLeft() or -1, f:GetRight() or -1,
                f:GetTop() or -1, f:GetBottom() or -1)
        end
        add(("abBox: left[%s] vis=%s right[%s] list[%s] rows=%d row1[%s]"):format(
            Box(ui.left), tostring(ui.left and ui.left:IsVisible()),
            Box(ui.right), Box(ui.list and ui.list.frame),
            ui.list and #ui.list.rows or -1,
            Box(ui.list and ui.list.rows[1])))
        add("abBoxSnapshot(0.3s after show): " .. tostring(ui.boxSnap))
    end
    if ns.invUI then
        local ub = ns.invUI.useBtn
        add(("padUse: btn=%s item=%s clicks=%d padBind=%s"):format(
            tostring(not not ub),
            ub and tostring(ub:GetAttribute("item")) or "-",
            ns.invUI.useClicks or 0,
            tostring(ns.padBind)))
    end
    return table.concat(L, "\n")
end

SLASH_NOCTURNEJOURNAL1 = "/njournal"
SLASH_NOCTURNEJOURNAL2 = "/njrn"
SlashCmdList.NOCTURNEJOURNAL = function(msg)
    msg = strlower(strtrim(msg or ""))
    if msg == "toggle" then
        ns:Toggle()
    elseif msg == "diag" then
        Nocturne.ShowCopyText("Nocturne: Journal — diag", ns:DiagText())
    elseif tonumber(msg) then
        ns:Open(tonumber(msg))
    else
        ns:OpenOptions()
    end
end

function NocturneJournal_OnCompartmentClick()
    ns:Toggle()
end

function NocturneJournal_OnCompartmentEnter(_, menuButton)
    GameTooltip:SetOwner(menuButton, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Nocturne: Journal", 1, 1, 1)
    GameTooltip:AddLine("Click to toggle the journal", 0.8, 0.8, 0.8)
    GameTooltip:Show()
end

function NocturneJournal_OnCompartmentLeave()
    GameTooltip:Hide()
end
