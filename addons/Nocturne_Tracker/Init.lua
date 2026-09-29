local ADDON_NAME, ns = ...

ns = _G.Nocturne.RegisterModule("tracker", ns)

ns.ADDON_NAME = ADDON_NAME
ns.VERSION = "0.1.0"

ns.IsSecret = _G.Nocturne.IsSecret

-- Truthiness of a possibly-secret flag: secret counts as false.
function ns.Flag(v)
    return not ns.IsSecret(v) and v and true or false
end

-- Content providers (Sources/*.lua), rendered top to bottom in load order,
-- and per-entry-kind click/tooltip handlers they register.
ns.sources = {}
ns.kinds = {}

-- Deferred to ADDON_LOADED: SavedVariables (ns.db) aren't populated until
-- then. Blizzard's objective tracker may load after us, so its own
-- ADDON_LOADED (and PLAYER_ENTERING_WORLD, registered in Tracker.lua)
-- re-runs the suppression.
_G.Nocturne.RegisterEvent("ADDON_LOADED", function(_, loadedAddon)
    if loadedAddon == "Blizzard_ObjectiveTracker" then
        ns:SyncBlizzard()
        return
    end
    if loadedAddon ~= ADDON_NAME then return end
    ns:InitDB()
    ns:CreateTrackerFrame()
    ns:InitOptions()
    ns:SyncBlizzard()
end)
