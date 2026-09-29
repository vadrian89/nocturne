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

-- First candidate atlas the client actually has (names change between
-- expansions); candidates may be nil.
function ns.FirstAtlas(...)
    for i = 1, select("#", ...) do
        local name = select(i, ...)
        if name and C_Texture.GetAtlasInfo(name) then return name end
    end
end

-- Continent-wide searches that came up empty aren't repeated on every
-- rescan (QUEST_LOG_UPDATE fires constantly), only once a "retry" event
-- (new target, new area, fresh map data) has bumped this epoch.
ns.searchEpoch = 0

function ns.MarkScanDirty(retry)
    ns.scanDirty = true
    if retry then ns.searchEpoch = ns.searchEpoch + 1 end
end

local function Rescan() ns.MarkScanDirty() end
local function RescanRetry() ns.MarkScanDirty(true) end

-- Events that invalidate the POI scan. Marker positions and bearings are
-- still recomputed every frame from the cached world coords.
function ns.RescanOn(events, retry)
    local fn = retry and RescanRetry or Rescan
    for _, event in ipairs(events) do
        _G.Nocturne.RegisterEvent(event, fn)
    end
end

-- Deferred to ADDON_LOADED: SavedVariables (ns.db) aren't populated until
-- then, and layout/options code reads them during setup.
_G.Nocturne.RegisterEvent("ADDON_LOADED", function(_, loadedAddon)
    if loadedAddon ~= ADDON_NAME then return end
    ns:InitDB()
    ns:CreateCompassFrame()
    ns:InitMarkers()
    ns:InitOptions()
end)
