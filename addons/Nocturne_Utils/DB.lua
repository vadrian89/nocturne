local _, ns = ...

ns.defaults = {
    hidePlayer       = true, -- PlayerFrame
    hideTarget       = true, -- TargetFrame
    hideBags         = true, -- bag bar buttons (bag windows still open)
    hideChatInCombat = true, -- chat while solo and in combat
    hideCPCluster    = true, -- ConsolePort bar/cluster while weapons sheathed
    hidePRDWhenIdle  = true, -- personal resource display only when relevant
}

-- Called from ADDON_LOADED (see Init.lua) — SavedVariables are nil until then.
function ns:InitDB()
    NocturneUtilsDB = _G.Nocturne.MergeDefaults(_G.NocturneUtilsDB or {}, ns.defaults)
    ns.db = NocturneUtilsDB
end
