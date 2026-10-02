local _, ns = ...

function ns:InitOptions()
    local s = _G.Nocturne.NewSettings("Nocturne: Extra", "NocturneExtra_", ns.db, ns.defaults,
        function() ns:ApplySettings() end)
    ns.category = s.category

    s:Checkbox("hideTarget", "Hide target frame", "Hide the Blizzard target unit frame.")
    s:Checkbox("hideBags", "Hide bag bar",
        "Hide the backpack and bag slot buttons near the micro menu. Bag windows still open with the keybind.")
    s:Checkbox("hideChatInCombat", "Hide chat in combat (solo)",
        "Hide chat frames during combat while not in a party or raid.")
    s:Checkbox("hideCPCluster", "Hide ConsolePort cluster while sheathed",
        "Fade out the ConsolePort cluster while weapons are sheathed. Always shown in combat.")
    s:Checkbox("hidePlayerIdle", "Hide player frame when idle",
        "Show the player frame only in combat, with weapons unsheathed, or while health/primary resource isn't at its rest value.")

    s:Text(
        "Import the bundled Blizzard Edit Mode layout as 'Nocturne' (a character layout) and make it the active one. An existing 'Nocturne' layout is replaced, so repeated applies stay clean.")
    s:Button("Apply Blizzard edit mode layout", "Apply", function() ns:ApplyEditModeLayout() end)

    s:Finish()
end

function ns:OpenOptions()
    Settings.OpenToCategory(ns.category:GetID())
end

SLASH_NOCTURNEEXTRA1 = "/nextra"
SLASH_NOCTURNEEXTRA2 = "/next"
SlashCmdList.NOCTURNEEXTRA = function(msg)
    msg = strlower(strtrim(msg or ""))
    if msg == "layout" then
        ns:ApplyEditModeLayout()
    elseif msg == "diag" then
        _G.Nocturne.ShowCopyText("Nocturne: Extra — diag", ns:DiagText())
    else
        ns:OpenOptions()
    end
end

function NocturneExtra_OnCompartmentClick()
    ns:OpenOptions()
end

function NocturneExtra_OnCompartmentEnter(_, menuButton)
    GameTooltip:SetOwner(menuButton, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Nocturne: Extra", 1, 1, 1)
    GameTooltip:AddLine("Click to open settings", 0.8, 0.8, 0.8)
    GameTooltip:Show()
end

function NocturneExtra_OnCompartmentLeave()
    GameTooltip:Hide()
end
