local ADDON_NAME, ns = ...

ns = _G.Nocturne.RegisterModule("utils", ns)

ns.ADDON_NAME = ADDON_NAME
ns.VERSION = "0.1.0"
ns.IsSecret = _G.Nocturne.IsSecret

-- Deferred to ADDON_LOADED: SavedVariables (ns.db) aren't populated until
-- then. ConsolePort's bar loads as its own addon and may come after us.
_G.Nocturne.RegisterEvent("ADDON_LOADED", function(_, loadedAddon)
    if loadedAddon == "ConsolePort_Bar" or loadedAddon == "ConsolePort" then
        ns:ApplyConsolePort()
        return
    end
    if loadedAddon ~= ADDON_NAME then return end
    ns:InitDB()
    ns:ApplySettings()
    ns:InitOptions()
end)
