local _, ns = ...

ns.defaults = {
    takeMapKey   = true,
    rememberPage = true,
    lastPage     = 1,
}

-- Called from ADDON_LOADED (see Init.lua) — SavedVariables are nil until then.
function ns:InitDB()
    NocturneJournalDB = _G.Nocturne.MergeDefaults(_G.NocturneJournalDB or {}, ns.defaults)
    ns.db = NocturneJournalDB
end
