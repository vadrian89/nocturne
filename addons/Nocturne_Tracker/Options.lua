local _, ns = ...

function ns:InitOptions()
    local s = _G.Nocturne.NewSettings("Nocturne: Tracker", "NocturneTracker_", ns.db, ns.defaults,
        function()
            ns:ApplyLayout()
            ns:SyncBlizzard()
        end)
    ns.category = s.category

    s:Checkbox("enabled", "Enable tracker", "Show the Nocturne quest list.")
    s:Checkbox("replaceBlizzard", "Replace Blizzard tracker",
        "Hide the default objective tracker. Nocturne shows quests, bonus objectives, area world quests, "
            .. "scenarios/delves/Mythic+, tracked achievements and recipes, plus quest item buttons.")
    s:Checkbox("locked", "Lock position",
        "Prevent dragging, make the empty area click-through and hide the frame while nothing is tracked.")
    s:Checkbox("hideInCombat", "Hide in combat", "Hide the list while in combat.")

    s:Checkbox("showScenario", "Scenarios", "Scenario, delve and Mythic+ objectives (with the keystone timer).")
    s:Checkbox("showAreaTasks", "Bonus objectives & area world quests",
        "Tasks in the area you're in, shown automatically like the default tracker does.")
    s:Checkbox("showAchievements", "Achievements", "Tracked achievements and their open criteria.")
    s:Checkbox("showRecipes", "Recipes", "Tracked profession recipes with reagents in your bags.")
    s:Checkbox("showItems", "Quest item buttons",
        "Clickable quest items left of the list. In combat their position updates only after combat ends.")

    s:Slider("width", "Width", nil, 160, 500, 10)
    s:Slider("height", "Max height",
        "The tracker shrinks to fit the tracked quests; longer lists scroll with the mouse wheel.",
        60, 900, 20)
    s:Slider("fontSize", "Font size", nil, 9, 24, 1)
    s:Slider("bgOpacity", "Background opacity",
        "0 hides the backdrop completely — clean floating text.", 0, 0.95, 0.05)

    local labels = {}
    for i, f in ipairs(ns.fontChoices) do labels[i] = f.label end
    s:Dropdown("fontFace", "Font", "Typeface for quest titles and objectives.", labels)

    s:Finish()
end

function ns:OpenOptions()
    Settings.OpenToCategory(ns.category:GetID())
end

function ns:ToggleLock()
    ns.db.locked = not ns.db.locked
    ns:ApplyLayout()
    _G.Nocturne.Print("tracker", ns.db.locked and "locked" or "unlocked")
end

SLASH_NOCTURNETRACKER1 = "/ntracker"
SLASH_NOCTURNETRACKER2 = "/ntrk"
SlashCmdList.NOCTURNETRACKER = function(msg)
    msg = strlower(strtrim(msg or ""))
    if msg == "lock" then
        if not ns.db.locked then ns:ToggleLock() end
    elseif msg == "unlock" then
        if ns.db.locked then ns:ToggleLock() end
    elseif msg == "reset" then
        ns:ResetPosition()
        ns:ApplyLayout()
    elseif msg == "toggle" then
        ns.db.enabled = not ns.db.enabled
        ns:Rebuild()
        ns:SyncBlizzard()
    elseif msg == "diag" then
        _G.Nocturne.ShowCopyText("Nocturne: Tracker — diag", ns:DiagText())
    else
        ns:OpenOptions()
    end
end

function NocturneTracker_OnCompartmentClick()
    ns:OpenOptions()
end

function NocturneTracker_OnCompartmentEnter(_, menuButton)
    GameTooltip:SetOwner(menuButton, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Nocturne: Tracker", 1, 1, 1)
    GameTooltip:AddLine("Click to open settings", 0.8, 0.8, 0.8)
    GameTooltip:Show()
end

function NocturneTracker_OnCompartmentLeave()
    GameTooltip:Hide()
end
