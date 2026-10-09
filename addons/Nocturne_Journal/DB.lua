local _, ns = ...

ns.defaults = {
    takeMapKey   = true,
    rememberPage = true,
    lastPage     = 1,
}

-- Per-character archive of quest text: the API gives no way to read the
-- text of an already turned-in quest, so we snapshot it while it's live.
ns.charDefaults = {
    completed = {}, -- newest-first array of snapshots (see QuestArchive.lua)
    pending   = {}, -- qid -> snapshot for quests still in the log
    titles    = {}, -- qid -> resolved title (historical quests load async)
}

-- Called from ADDON_LOADED (see Init.lua) — SavedVariables are nil until then.
function ns:InitDB()
    NocturneJournalDB = _G.Nocturne.MergeDefaults(_G.NocturneJournalDB or {}, ns.defaults)
    ns.db = NocturneJournalDB
    NocturneJournalCharDB = _G.Nocturne.MergeDefaults(_G.NocturneJournalCharDB or {}, ns.charDefaults)
    ns.chardb = NocturneJournalCharDB
end
