local ADDON_NAME, ns = ...

ns = _G.Nocturne.RegisterModule("journal", ns)

ns.ADDON_NAME = ADDON_NAME
ns.VERSION = "0.1.0"
ns.IsSecret = _G.Nocturne.IsSecret

-- Binding display names are resolved by the client from globals at load time.
_G.BINDING_HEADER_NOCTURNE = "Nocturne"
_G["BINDING_NAME_CLICK NocturneJournalToggleButton:LeftButton"] = "Toggle Nocturne Journal"

_G.Nocturne.RegisterEvent("ADDON_LOADED", function(_, loadedAddon)
    if loadedAddon ~= ADDON_NAME then return end
    ns:InitDB()
    ns:CreateShell()
    ns:InitOptions()
    ns:SyncMapBinding()
end)
