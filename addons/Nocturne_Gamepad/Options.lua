local _, ns = ...

local function ApplyNow()
    if ns:ApplyLayout() then
        _G.Nocturne.Print("applied layout 'Nocturne Compact'.")
    else
        _G.Nocturne.Print("ConsolePort bar is not ready yet — try again after login.")
    end
end

function ns:InitOptions()
    local s = _G.Nocturne.NewSettings("Nocturne: Gamepad", "NocturneGamepad_", ns.db, ns.defaults,
        function() ns:ApplySettings() end)
    ns.category = s.category

    s:Checkbox("compactLayout", "Compact cluster layout",
        "Apply the 'Nocturne Compact' cluster layout: the dpad and X/Y/A/B rings moved together (2px between the innermost buttons), with LB/RB at the top corners and LT/RT at the bottom corners. Stock ConsolePort art is kept.")
    s:Text(
        "The layout is applied through ConsolePort's own preset system and appears as 'Nocturne Compact' in the loadout presets. Your previous layout is saved as 'Backup (pre-Nocturne)'. Revert with /ngp reset.")
    s:Button("Apply compact layout now", "Apply", ApplyNow)
    s:Finish()
end

function ns:OpenOptions()
    Settings.OpenToCategory(ns.category:GetID())
end

SLASH_NOCTURNEGAMEPAD1 = "/ngamepad"
SLASH_NOCTURNEGAMEPAD2 = "/ngp"
SlashCmdList.NOCTURNEGAMEPAD = function(msg)
    msg = strlower(strtrim(msg or ""))
    if msg == "apply" then
        ApplyNow()
    elseif msg == "reset" then
        if ns:ResetLayout() then
            _G.Nocturne.Print("reverted ConsolePort layout.")
        else
            _G.Nocturne.Print("ConsolePort bar is not ready yet.")
        end
    elseif msg == "diag" then
        _G.Nocturne.ShowCopyText("Nocturne: Gamepad — diag", ns:DiagText())
    else
        ns:OpenOptions()
    end
end

function NocturneGamepad_OnCompartmentClick()
    ns:OpenOptions()
end

function NocturneGamepad_OnCompartmentEnter(_, menuButton)
    GameTooltip:SetOwner(menuButton, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Nocturne: Gamepad", 1, 1, 1)
    GameTooltip:AddLine("Click to open settings", 0.8, 0.8, 0.8)
    GameTooltip:Show()
end

function NocturneGamepad_OnCompartmentLeave()
    GameTooltip:Hide()
end

local function SafeV(v) return ns.IsSecret(v) and "<secret>" or tostring(v) end

function ns:DiagText()
    local presets = _G.ConsolePort_BarPresets
    local live = _G.ConsolePort_BarLayout
    local pad4 = _G.CPB_PAD4
    local px, py
    if pad4 then
        px, py = select(4, pad4:GetPoint(1))
    end
    local n = 0
    for name, obj in pairs(_G) do
        if type(name) == "string" and name:find("^CPB_")
            and type(obj) == "table" and obj.mod then
            n = n + 1
        end
    end
    return table.concat({
        ("compactLayout=%s applied=%s version=%s/%s"):format(
            tostring(ns.db and ns.db.compactLayout),
            tostring(ns.db and ns.db.layoutApplied),
            tostring(ns.db and ns.db.layoutVersion), tostring(ns.LAYOUT_VERSION)),
        ("envReady=%s liveLayout=%s"):format(
            tostring(ns:CPEnvReady()), SafeV(live and live.name)),
        ("preset=%s backup=%s stockRestored=%s"):format(
            tostring(presets and rawget(presets, "NocturneCompact") ~= nil),
            tostring(presets and rawget(presets, "NocturneBackup") ~= nil),
            tostring(ns.db and ns.db.stockRestored)),
        ("layoutLive=%s pad4=%s,%s clusterButtons=%d"):format(
            tostring(ns:IsLayoutLive()), tostring(px), tostring(py), n),
    }, "\n")
end
