local _, ns = ...

local T = _G.Nocturne.Theme

function ns:InitOptions()
    local s = _G.Nocturne.NewSettings("Nocturne: Compass", "NocturneCompass_", ns.db, ns.defaults,
        function() ns:ApplyLayout() end)
    ns.category = s.category

    s:Dropdown("display", "Display", "Which navigation UI to show. While the minimap is away, what lived " ..
        "on it (addon buttons, tracking, calendar, expansion summary) moves to a menu button next to " ..
        "the bar, with mail, calendar invite and crafting order indicators.",
        { "Compass only", "Compass and minimap", "Smart" })
    local accent = T.colors.accent
    s:Text(
        T.ColorText("Compass only", accent) .. " — the minimap stays hidden for good. The in-region " ..
        "quest glow still follows the quest's real area, plus the selected quest's navigation " ..
        "diamond arrival, else the Area radius (below) around the pin.\n" ..
        T.ColorText("Compass and minimap", accent) .. " — both are always shown.\n" ..
        T.ColorText("Smart", accent) .. " — the minimap shows itself within 150 yards of a tracked quest, " ..
        "world quest or event, within the Area radius of the selected quest's target and in " ..
        "instances, so the in-region glow covers the whole quest area; it hides otherwise and " ..
        "during combat.")
    s:Checkbox("locked", "Lock position", "Prevent dragging the bar and make it click-through.")
    s:Checkbox("anchorTop", "Anchor to top of screen",
        "Pin the bar to the top edge, leaving room for the clock, zone name and coordinates above it. " ..
        "It can still be dragged sideways.")
    s:Button("Horizontal position", "Center", function() ns:CenterHorizontally() end,
        "Center the bar horizontally on the screen, keeping its height.")
    s:Checkbox("showZone", "Show zone name", "Current zone above the bar, colored like the minimap's zone text.")
    s:Checkbox("showClock", "Show clock",
        "Time left of the zone name. Click it for Blizzard's time options (local/realm time, 24h, " ..
        "alarm); right-click for the stopwatch.")
    s:Checkbox("showHeading", "Show coordinates", "Player map coordinates above the bar, e.g. 45.2, 67.8.")
    s:Checkbox("showDistance", "Show marker distance", "Yards to each tracked quest under its marker.")
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
    s:Slider("zoneSize", "Zone text size", "Font size of the clock, zone name and coordinates above the bar.", 8, 24, 1)
    s:Slider("bannerSize", "Area title size",
        "Font size of the quest/area name shown below the bar while inside its region.", 10, 32, 1)
    s:Slider("minimapSize", "Minimap size",
        "Side of the square minimap in the top-right corner, in pixels.", 120, 320, 10)

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
    elseif msg == "forget" then
        wipe(ns.db.pois)
        wipe(ns.db.taxi)
        ns.MarkScanDirty(true)
        Nocturne.Print("Learned POIs cleared.")
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
        lines[#lines + 1] = ("superTrack type=%s quest=%s mapPin=%s:%s vignette=%s userWP=%s transit=%s,%s world=%s,%s")
            :format(
                tostring(ST.GetHighestPrioritySuperTrackingType and ST.GetHighestPrioritySuperTrackingType()),
                tostring(ST.GetSuperTrackedQuestID()), tostring(pinType), tostring(pinID),
                tostring(ST.GetSuperTrackedVignette and ST.GetSuperTrackedVignette()),
                tostring(ST.IsSuperTrackingUserWaypoint()), tostring(wx), tostring(wy), tostring(tx), tostring(ty))

        -- Raw inputs the client may restrict inside instances (nil or secret).
        local function S(v) return ns.IsSecret(v) and "<secret>" or tostring(v) end
        local instName, instType, difficultyID = GetInstanceInfo()
        local rawPos = p.mapID and C_Map.GetPlayerMapPosition(p.mapID, "player")
        local ux, uy = UnitPosition("player")
        lines[#lines + 1] = ("instance='%s' type=%s difficulty=%s rawFacing=%s rawMapPos=%s,%s unitPos=%s,%s"):format(
            S(instName), S(instType), S(difficultyID), S(GetPlayerFacing()),
            S(rawPos and rawPos.x), S(rawPos and rawPos.y), S(ux), S(uy))
        local N = C_Navigation
        if N then
            local nav = N.GetFrame and N.GetFrame()
            local nx, ny
            if nav then nx, ny = nav:GetCenter() end
            lines[#lines + 1] = ("navigation state=%s dist=%s validScreen=%s clamped=%s frame=%s,%s screen=%.0fx%.0f")
                :format(
                    S(N.GetTargetState and N.GetTargetState()), S(N.GetDistance and N.GetDistance()),
                    S(N.HasValidScreenPosition and N.HasValidScreenPosition()),
                    S(N.WasClampedToScreen and N.WasClampedToScreen()), S(nx), S(ny),
                    UIParent:GetWidth(), UIParent:GetHeight())
        end
        -- Tracked content (C_ContentTracking): what is followed, and what
        -- the client places on the player's map for it.
        local CT = C_ContentTracking
        if CT and CT.GetTrackedIDs then
            local sType, sID
            if ST.GetSuperTrackedContent then sType, sID = ST.GetSuperTrackedContent() end
            lines[#lines + 1] = ("content super=%s:%s"):format(S(sType), S(sID))
            for tname, ttype in pairs(Enum.ContentTrackingType or {}) do
                local ids = CT.GetTrackedIDs(ttype)
                local res, infos
                if CT.GetTrackablesOnMap and p.mapID then
                    res, infos = CT.GetTrackablesOnMap(ttype, p.mapID)
                end
                lines[#lines + 1] = ("  type=%s(%s) tracked=%d onMap res=%s n=%d"):format(
                    tname, S(ttype), ids and #ids or -1, S(res), infos and #infos or -1)
                for _, info in ipairs(infos or {}) do
                    lines[#lines + 1] = ("    id=%s x=%s y=%s wp='%s'"):format(
                        S(info.trackableID), S(info.x), S(info.y), S(info.waypointText))
                end
            end
        end
        -- Active minimap tracking filters, by menu name.
        if C_Minimap and C_Minimap.GetNumTrackingTypes then
            local names = {}
            for i = 1, C_Minimap.GetNumTrackingTypes() do
                local info = C_Minimap.GetTrackingInfo(i)
                local n, a
                if type(info) == "table" then
                    n, a = info.name, info.active
                else
                    n, _, a = C_Minimap.GetTrackingInfo(i)
                end
                if a then names[#names + 1] = S(n) end
            end
            lines[#lines + 1] = "tracking=" .. table.concat(names, ",")
        end
        if p.mapID and ns.OfferDiag then ns.OfferDiag(p.mapID, lines) end
        if p.mapID and ns.PinDiag then ns.PinDiag(p.mapID, p.instance, lines) end
        lines[#lines + 1] = "interactions=" .. table.concat(ns.seenIT or {}, ",")
        if ns.LearnedPOIDiag then ns.LearnedPOIDiag(lines) end
        if ns.WorldMapPinDiag then ns.WorldMapPinDiag(lines) end
        local selected = ns.GetSelectedQuestID()
        local onMap = p.mapID and C_QuestLog.GetQuestsOnMap(p.mapID)
        local objectives = selected and C_QuestLog.GetQuestObjectives(selected)
        lines[#lines + 1] = ("questsOnMap=%d selected=%s objectives=%d"):format(
            onMap and #onMap or -1, tostring(selected), objectives and #objectives or -1)
        for _, o in ipairs(objectives or {}) do
            lines[#lines + 1] = ("  objective '%s' done=%s"):format(S(o.text), S(o.finished))
        end
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
        -- Pop the minimap up next to the compass, then back to the mode
        -- that was active (smart or compass only).
        local db = ns.db
        if db.display == ns.DISPLAY_BOTH then
            db.display = ns.lastCompassDisplay or ns.DISPLAY_SMART
        else
            ns.lastCompassDisplay, db.display = db.display, ns.DISPLAY_BOTH
        end
        ns:ApplyLayout()
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
