local _, ns = ...

ns.defaults = {
    enabled         = true,
    replaceBlizzard = true,
    locked          = false,
    point           = { "TOPRIGHT", -70, -240 }, -- grows downward from here
    width           = 280,
    height          = 420,
    fontSize        = 12,
    fontFace        = 1, -- index into ns.fontChoices
    bgOpacity       = 0.55, -- 0 = borderless floating text
    hideInCombat    = false,
    showScenario    = true,  -- scenarios, delves, Mythic+
    showAreaTasks   = true,  -- bonus objectives + world quests in the current area
    showAchievements = true,
    showRecipes     = true,
    showItems       = true,  -- secure quest item buttons left of the list
}

-- Called from ADDON_LOADED (see Init.lua) — SavedVariables are nil until then.
function ns:InitDB()
    NocturneTrackerDB = _G.Nocturne.MergeDefaults(_G.NocturneTrackerDB or {}, ns.defaults)
    ns.db = NocturneTrackerDB
    -- Older saves were CENTER/RIGHT-anchored and grew in both directions.
    if ns.db.point[1] ~= "TOPRIGHT" then ns:ResetPosition() end
end

function ns:ResetPosition()
    ns.db.point = _G.Nocturne.MergeDefaults({}, ns.defaults.point)
end
