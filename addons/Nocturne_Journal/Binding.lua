local _, ns = ...

local InCombatLockdown = InCombatLockdown
local GetBindingKey = GetBindingKey

-- Invisible click target for the CLICK bindings (the separate Key Bindings
-- entry and the map-key override). Kept shown-but-transparent because a
-- hidden button may not receive binding clicks.
local btn = CreateFrame("Button", "NocturneJournalToggleButton", UIParent)
btn:SetSize(1, 1)
btn:SetAlpha(0)
btn:EnableMouse(false)
btn:SetScript("OnClick", function() ns:Toggle() end)

-- Override bindings live on this owner frame, never on Blizzard's, so
-- ClearOverrideBindings only drops ours.
local owner = CreateFrame("Frame")

ns.diagMapKeys = {}

local syncing = false
function ns:SyncMapBinding()
    if syncing then return end
    syncing = true
    -- SetOverrideBinding* is protected; defer while locked down.
    if InCombatLockdown() then
        ns.mapBindingPending = true
    else
        ns.mapBindingPending = false
        ClearOverrideBindings(owner)
        wipe(ns.diagMapKeys)
        if ns.db and ns.db.takeMapKey then
            for i = 1, select("#", GetBindingKey("TOGGLEWORLDMAP")) do
                local key = select(i, GetBindingKey("TOGGLEWORLDMAP"))
                SetOverrideBindingClick(owner, true, key, "NocturneJournalToggleButton")
                ns.diagMapKeys[#ns.diagMapKeys + 1] = key
            end
        end
    end
    syncing = false
end

-- Applying overrides re-fires UPDATE_BINDINGS; the flag above stops the loop.
_G.Nocturne.RegisterEvent("UPDATE_BINDINGS", function() ns:SyncMapBinding() end)
_G.Nocturne.RegisterEvent("PLAYER_ENTERING_WORLD", function() ns:SyncMapBinding() end)
_G.Nocturne.RegisterEvent("PLAYER_REGEN_ENABLED", function()
    if ns.mapBindingPending then ns:SyncMapBinding() end
end)
