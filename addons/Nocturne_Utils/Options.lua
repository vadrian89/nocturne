local _, ns = ...

function ns:InitOptions()
    local s = _G.Nocturne.NewSettings("Nocturne: Utils", "NocturneUtils_", ns.db, ns.defaults,
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

    s:Finish()
end

function ns:OpenOptions()
    Settings.OpenToCategory(ns.category:GetID())
end

SLASH_NOCTURNEUTILS1 = "/nutils"
SLASH_NOCTURNEUTILS2 = "/nutl"
SlashCmdList.NOCTURNEUTILS = function(msg)
    msg = strlower(strtrim(msg or ""))
    if msg == "diag" then
        _G.Nocturne.ShowCopyText("Nocturne: Utils — diag", ns:DiagText())
    else
        ns:OpenOptions()
    end
end

function NocturneUtils_OnCompartmentClick()
    ns:OpenOptions()
end

function NocturneUtils_OnCompartmentEnter(_, menuButton)
    GameTooltip:SetOwner(menuButton, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Nocturne: Utils", 1, 1, 1)
    GameTooltip:AddLine("Click to open settings", 0.8, 0.8, 0.8)
    GameTooltip:Show()
end

function NocturneUtils_OnCompartmentLeave()
    GameTooltip:Hide()
end
