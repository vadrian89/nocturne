local _, ns = ...

-- What navigation UI is shown (`display`): the compass alone, both, or
-- "smart" — the minimap shows itself near a tracked quest, world quest or
-- event, near the selected quest's navigation target and in instances.
-- The in-region glow follows the quest blob regardless of the minimap
-- (IsInsideQuestBlob answers with it suppressed); fallbacks are the
-- navigation diamond's arrival state for the selected quest and pin
-- proximity (the `inRegionYards` radius) for the rest.
ns.DISPLAY_COMPASS = 1
ns.DISPLAY_BOTH = 2
ns.DISPLAY_SMART = 3

ns.defaults = {
    display       = ns.DISPLAY_BOTH,
    locked        = false,
    point         = { "CENTER", 0, 300 },
    anchorTop     = false,
    width         = 520,
    height        = 28,
    fovDegrees    = 120,
    showHeading   = true,
    showZone      = true,
    showClock     = true,
    zoneSize      = 12,
    showDistance  = true,
    minScale      = 0.5,
    maxScale      = 1.6,
    scaleRange    = 1200,
    inRegionYards = 60,
    bannerSize    = 16,
    hideInCombat  = false,
    opacity       = 1.0,
    minimapSize   = 180,
    -- Learned POIs (NPCs the player interacted with) and real flight-master
    -- spots recorded on TAXIMAP_OPENED, both keyed per map/node.
    pois          = {},
    taxi          = {},
}

-- Called from ADDON_LOADED (see Init.lua) — SavedVariables are nil until
-- then, so merging at file-load time would always see empty defaults and
-- get overwritten once the real saved data loads.
function ns:InitDB()
    local db = _G.NocturneCompassDB or {}
    -- `display` replaced the `enabled` / `hideMinimap` switches.
    if db.display == nil then
        if db.enabled == false then
            db.display = ns.DISPLAY_BOTH
        elseif db.hideMinimap then
            db.display = ns.DISPLAY_COMPASS
        end
    end
    db.enabled, db.hideMinimap, db.hideInInstances, db.bannerPulse = nil, nil, nil, nil
    NocturneCompassDB = _G.Nocturne.MergeDefaults(db, ns.defaults)
    ns.db = NocturneCompassDB
end
