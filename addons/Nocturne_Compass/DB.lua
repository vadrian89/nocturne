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

local function MergeDefaults(dst, src)
    for k, v in pairs(src) do
        if dst[k] == nil then
            if type(v) == "table" then
                dst[k] = MergeDefaults({}, v)
            else
                dst[k] = v
            end
        end
    end
    return dst
end

-- Called from ADDON_LOADED (see Init.lua) — SavedVariables are nil until
-- then, so merging at file-load time would always see empty defaults and
-- get overwritten once the real saved data loads.
function ns:InitDB()
    NocturneCompassDB = MergeDefaults(_G.NocturneCompassDB or {}, ns.defaults)
    NocturneCompassDB.bannerPulse = nil
    ns.db = NocturneCompassDB
end
