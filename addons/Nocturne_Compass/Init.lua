local ADDON_NAME, ns = ...

ns = _G.Nocturne.RegisterModule("compass", ns)

ns.ADDON_NAME = ADDON_NAME
ns.VERSION = "0.1.0"

ns.math = {}
ns.providers = {}
ns.scanResults = {}
ns.scanDirty = true

-- Current player state, refreshed every frame.
ns.player = { x = 0, y = 0, instance = nil, mapID = nil, facing = nil }

-- Midnight (12.0): some values may be "secret" on tainted paths.
ns.IsSecret = _G.issecretvalue or function() return false end

-- Deferred to ADDON_LOADED: SavedVariables (ns.db) aren't populated until
-- then, and layout/options code reads them during setup.
_G.Nocturne.RegisterEvent("ADDON_LOADED", function(_, loadedAddon)
    if loadedAddon ~= ADDON_NAME then return end
    ns:InitDB()
    ns:CreateCompassFrame()
    ns:InitMarkers()
    ns:InitOptions()
end)
