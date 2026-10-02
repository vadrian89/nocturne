local _, ns = ...

ns.defaults = {
    hideTarget       = true, -- TargetFrame
    hideBags         = true, -- bag bar buttons (bag windows still open)
    hideChatInCombat = true, -- chat while solo and in combat
    hideCPCluster    = true, -- ConsolePort bar/cluster while weapons sheathed
    hidePlayerIdle   = true, -- PlayerFrame while out of combat and at rest
}

-- Called from ADDON_LOADED (see Init.lua) — SavedVariables are nil until then.
function ns:InitDB()
    NocturneExtraDB = _G.Nocturne.MergeDefaults(_G.NocturneExtraDB or {}, ns.defaults)
    ns.db = NocturneExtraDB
end
