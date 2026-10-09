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
    add("pad input:")
    local any
    for button, count in pairs(ns.padCounts) do
        add(("  %s x%d"):format(button, count))
        any = true
    end
    if not any then add("  (nothing received yet)") end
    add("atlases:")
    for i, def in ipairs(ns.pages) do
        add(("  %s: %s"):format(def.title, tostring(ns.diagAtlas[def.key] or "-")))
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
