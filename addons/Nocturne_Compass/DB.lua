local _, ns = ...

-- What navigation UI is shown (`display`): the compass replaces the minimap,
-- the minimap alone, or both.
ns.DISPLAY_COMPASS = 1
ns.DISPLAY_MINIMAP = 2
ns.DISPLAY_BOTH = 3

ns.defaults = {
    display         = ns.DISPLAY_BOTH,
    locked          = false,
    point           = { "CENTER", 0, 300 },
    width           = 520,
    height          = 28,
    fovDegrees      = 120,
    showHeading     = true,
    showZone        = true,
    zoneSize        = 12,
    showDistance    = true,
    minScale        = 0.5,
    maxScale        = 1.6,
    scaleRange      = 1200,
    inRegionYards   = 60,
    bannerSize      = 16,
    hideInCombat    = false,
    opacity         = 1.0,
}

-- Called from ADDON_LOADED (see Init.lua) — SavedVariables are nil until
-- then, so merging at file-load time would always see empty defaults and
-- get overwritten once the real saved data loads.
function ns:InitDB()
    local db = _G.NocturneCompassDB or {}
    -- `display` replaced the `enabled` / `hideMinimap` switches.
    if db.display == nil then
        if db.enabled == false then
            db.display = ns.DISPLAY_MINIMAP
        elseif db.hideMinimap then
            db.display = ns.DISPLAY_COMPASS
        end
    end
    db.enabled, db.hideMinimap, db.hideInInstances, db.bannerPulse = nil, nil, nil, nil
    NocturneCompassDB = _G.Nocturne.MergeDefaults(db, ns.defaults)
    ns.db = NocturneCompassDB
end
