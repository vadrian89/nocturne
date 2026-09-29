local _, ns = ...

ns.defaults = {
    enabled         = true,
    locked          = false,
    point           = { "CENTER", 0, 300 },
    width           = 520,
    height          = 28,
    fovDegrees      = 120,
    showHeading     = true,
    showDistance    = true,
    minScale        = 0.5,
    maxScale        = 1.6,
    scaleRange      = 1200,
    inRegionYards   = 60,
    bannerSize      = 16,
    hideInInstances = true,
    hideInCombat    = false,
    opacity         = 1.0,
}

-- Called from ADDON_LOADED (see Init.lua) — SavedVariables are nil until
-- then, so merging at file-load time would always see empty defaults and
-- get overwritten once the real saved data loads.
function ns:InitDB()
    NocturneCompassDB = _G.Nocturne.MergeDefaults(_G.NocturneCompassDB or {}, ns.defaults)
    NocturneCompassDB.bannerPulse = nil
    ns.db = NocturneCompassDB
end
