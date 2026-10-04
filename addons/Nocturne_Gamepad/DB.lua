local _, ns = ...

ns.defaults = {
    compactLayout = true,  -- apply the 'Nocturne Compact' ring positions
    stockRestored = false, -- one-time revert of the diamond experiment (internal)
    layoutApplied = false, -- set after the first apply; guards the backup (internal)
    layoutVersion = 0,     -- ns.LAYOUT_VERSION last applied (internal)
    nativeRight = true,    -- Forever: native gamepad bars pinned to the right edge
    nativeScale = 120,     -- Forever: native gamepad bars scale, percent
}

-- Called from ADDON_LOADED (see Init.lua) — SavedVariables are nil until then.
function ns:InitDB()
    NocturneGamepadDB = _G.Nocturne.MergeDefaults(_G.NocturneGamepadDB or {}, ns.defaults)
    ns.db = NocturneGamepadDB
end
