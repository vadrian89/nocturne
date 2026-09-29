local _, ns = ...

function ns:InitOptions()
    local s = _G.Nocturne.NewSettings("Nocturne: Compass", "NocturneCompass_", ns.db, ns.defaults,
        function() ns:ApplyLayout() end)
    ns.category = s.category

    s:Checkbox("enabled", "Enable compass", "Show or hide the navigation bar.")
    s:Checkbox("locked", "Lock position", "Prevent dragging the bar and make it click-through.")
    s:Checkbox("showHeading", "Show coordinates", "Player map coordinates above the bar, e.g. 45.2, 67.8.")
    s:Checkbox("showDistance", "Show marker distance", "Yards to each tracked quest under its marker.")
    s:Checkbox("hideInInstances", "Hide in instances", "Dungeons, raids, battlegrounds and arenas.")
    s:Checkbox("hideInCombat", "Hide in combat", "Fade the bar out while in combat.")

    s:Slider("width", "Bar width", "Length of the compass strip in pixels.", 200, 900, 10)
    s:Slider("height", "Bar height", nil, 16, 64, 2)
    s:Slider("fovDegrees", "Field of view", "Degrees of heading visible across the bar.", 60, 180, 5)
    s:Slider("opacity", "Opacity", nil, 0.2, 1, 0.05)
    s:Slider("scaleRange", "Scale range (yards)", "Distance at which markers reach their minimum size.", 300, 3000,
        50)
    s:Slider("minScale", "Marker min scale", "Size of far away markers.", 0.2, 1, 0.05)
    s:Slider("maxScale", "Marker max scale", "Size of nearby markers.", 1, 3, 0.05)
    s:Slider("inRegionYards", "Area radius (yards)",
        "Distance to a quest objective that counts as 'inside' its region.", 10, 200, 5)
    s:Slider("bannerSize", "Area title size",
        "Font size of the quest/area name shown below the bar while inside its region.", 10, 32, 1)

    s:Finish()
end

function ns:OpenOptions()
    Settings.OpenToCategory(ns.category:GetID())
end

function ns:ToggleLock()
    ns.db.locked = not ns.db.locked
    ns:ApplyLayout()
    _G.Nocturne.Print("compass", ns.db.locked and "locked" or "unlocked")
end

SLASH_NOCTURNECOMPASS1 = "/ncompass"
SLASH_NOCTURNECOMPASS2 = "/ncmp"
SlashCmdList.NOCTURNECOMPASS = function(msg)
    msg = strlower(strtrim(msg or ""))
    if msg == "lock" then
        if not ns.db.locked then ns:ToggleLock() end
    elseif msg == "unlock" then
        if ns.db.locked then ns:ToggleLock() end
    elseif msg == "reset" then
        ns.db.point = { "CENTER", 0, 300 }
        ns:ApplyLayout()
    elseif msg == "diag" then
        local p = ns.player
        local db = ns.db
        local fovHalf = math.rad(db.fovDegrees) / 2
        local pxPerRad = ns.pxPerRad or 0
        local clipW = ns.clip and ns.clip:GetWidth() or -1
        -- GetCenter()/GetLeft() etc. return coordinates in the CALLING
        -- frame's own local scale, not a shared screen-pixel space — a
        -- marker scaled to 1.5x and its parent (scale 1) are NOT directly
        -- comparable. Normalize both to true screen pixels first.
        local function TrueCenter(f)
            if not f then return nil end
            local cx, cy = f:GetCenter()
            if not cx then return nil end
            local s = f:GetEffectiveScale()
            return cx * s, cy * s
        end
        local clipCX, clipCY = TrueCenter(ns.clip)
        local lines = {
            ("facing=%.3f (%.0fdeg) facingCW=%.0f pos=%.1f,%.1f inst=%s map=%s results=%d"):format(
                p.facing or -1, math.deg(p.facing or 0), math.deg(ns.FacingCW() or 0),
                p.x or 0, p.y or 0, tostring(p.instance), tostring(p.mapID), #ns.scanResults),
            ("pxPerRad=%.1f clipWidth=%.1f"):format(pxPerRad, clipW),
        }
        -- What the client is navigating to (the gold diamond), whether or
        -- not a provider resolved it into a marker.
        local ST = C_SuperTrack
        local pinType, pinID
        if ST.GetSuperTrackedMapPin then pinType, pinID = ST.GetSuperTrackedMapPin() end
        local wx, wy = ST.GetNextWaypointForMap(p.mapID or 0)
        local tx, ty = ns.TransitWaypoint(p.mapID, p.instance)
        lines[#lines + 1] = ("superTrack type=%s quest=%s mapPin=%s:%s vignette=%s userWP=%s transit=%s,%s world=%s,%s"):format(
            tostring(ST.GetHighestPrioritySuperTrackingType and ST.GetHighestPrioritySuperTrackingType()),
            tostring(ST.GetSuperTrackedQuestID()), tostring(pinType), tostring(pinID),
            tostring(ST.GetSuperTrackedVignette and ST.GetSuperTrackedVignette()),
            tostring(ST.IsSuperTrackingUserWaypoint()), tostring(wx), tostring(wy), tostring(tx), tostring(ty))
        for _, e in ipairs(ns.scanResults) do
            local dx, dy = e.x - (p.x or 0), e.y - (p.y or 0)
            local dist = ns.math.Distance(dx, dy)
            local rel = p.facing and ns.RelAngle(dx, dy) or nil
            local m = ns:GetMarkerFrame(e.key)
            -- Read the marker's actual rendered offset (post fan-out/clamp)
            -- instead of recomputing the formula, so diag can't drift out of
            -- sync with what UpdateMarkers really does.
            local mx, my = 0, 0
            if m and clipCX then
                local mcx, mcy = TrueCenter(m)
                if mcx then mx, my = mcx - clipCX, mcy - clipCY end
            end
            lines[#lines + 1] = ("%s '%s' rel=%.0fdeg(%s) %s renderXY=%.0f,%.0f shown=%s alpha=%.2f scale=%.2f dist=%d atlas=%s class=%s")
                :format(
                    e.key, e.title or "?",
                    rel and math.deg(rel) or 0,
                    rel and (rel > 0 and "right" or "left") or "?",
                    rel and (math.abs(rel) <= fovHalf and "IN-FOV" or "OUT") or "?",
                    mx, my,
                    tostring(m and m:IsShown()), m and m:GetAlpha() or -1, m and m:GetScale() or -1,
                    dist, tostring(e.atlas or e.textureIndex), tostring(e.classification))
        end
        _G.Nocturne.ShowCopyText("Nocturne: Compass — diag", table.concat(lines, "\n"))
    elseif msg == "toggle" then
        ns.db.enabled = not ns.db.enabled
    else
        ns:OpenOptions()
    end
end

function NocturneCompass_OnCompartmentClick()
    ns:OpenOptions()
end

function NocturneCompass_OnCompartmentEnter(_, menuButton)
    GameTooltip:SetOwner(menuButton, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Nocturne: Compass", 1, 1, 1)
    GameTooltip:AddLine("Click to open settings", 0.8, 0.8, 0.8)
    GameTooltip:Show()
end

function NocturneCompass_OnCompartmentLeave()
    GameTooltip:Hide()
end
