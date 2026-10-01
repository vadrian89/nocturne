local ADDON_NAME, ns = ...

ns = _G.Nocturne.RegisterModule("gamepad", ns)

ns.ADDON_NAME = ADDON_NAME
ns.VERSION = "0.3.0"
ns.IsSecret = _G.Nocturne.IsSecret

function ns:ApplySettings()
    if not ns.db then return end
    -- Layout applies on the toggle only — re-running it on every unrelated
    -- option change would clobber in-session CP layout edits.
    if ns.db.compactLayout ~= ns.lastCompactLayout then
        ns.lastCompactLayout = ns.db.compactLayout
        if ns.db.compactLayout then
            ns:ApplyLayout()
        end
    end
end

-- ConsolePort_Bar builds its env (env.Layout, env.Presets) on a deferred
-- ADDON_LOADED/OnDataLoaded chain that may run after our init; poll briefly
-- until ConsolePort_BarLayout exists, then:
--  - revert once: if the live layout is still the old 'Nocturne Diamond'
--    experiment, hand control back to the pre-Nocturne backup (or Default);
--  - register + auto-apply the compact preset once per LAYOUT_VERSION.
local function Init()
    ns:InitDB()
    ns:InitOptions()
    ns.lastCompactLayout = ns.db.compactLayout
    ns:ApplySettings()

    local ticks = 0
    local ticker
    ticker = C_Timer.NewTicker(0.5, function()
        ticks = ticks + 1
        if ticks > 40 then
            ticker:Cancel()
            return
        end
        if not ns:CPEnvReady() then return end
        ticker:Cancel()
        if not ns.db.stockRestored then
            ns.db.stockRestored = true
            if _G.ConsolePort_BarLayout.name == 'Nocturne Diamond' then
                local presets = _G.ConsolePort_BarPresets
                local target = presets and rawget(presets, 'NocturneBackup')
                    and 'NocturneBackup' or 'Default'
                ConsolePort('layout ' .. target)
                _G.Nocturne.Print("ConsolePort layout reverted to '" .. target .. "'.")
            end
        end
        ns:RegisterPreset()
        if ns.db.compactLayout and ns.db.layoutVersion ~= ns.LAYOUT_VERSION then
            ns:ApplyLayout()
        end
    end)
end

_G.Nocturne.RegisterEvent("ADDON_LOADED", function(_, loadedAddon)
    if loadedAddon == ADDON_NAME then
        Init()
    end
end)
