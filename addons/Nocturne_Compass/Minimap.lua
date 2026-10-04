local _, ns = ...

-- Optional minimap replacement: while the bar is shown, a menu button
-- (expansion summary, calendar, tracking, addon compartment, other addons'
-- minimap buttons) sits next to it permanently; mail / calendar invite /
-- crafting order indicators only join it while Blizzard's minimap itself
-- is suppressed.
--
-- "Smart" mode brings the minimap up near a tracked quest, world quest or
-- event, near the selected quest's navigation target and in instances, and
-- drops it otherwise and in combat. The in-region glow doesn't depend on
-- it either way (see DB.lua / TrackedQuests.lua).

local Nocturne = _G.Nocturne
local UnitAffectingCombat = UnitAffectingCombat
local IsInInstance = IsInInstance
local GetTime = GetTime

local BUTTON_SIZE = 18
local BUTTON_GAP = 4
-- Smart mode shows the minimap inside NEAR and hides it only past FAR, so
-- standing on the line doesn't flip it every tick.
local SMART_NEAR_YARDS = 150
local SMART_FAR_YARDS = 175
local EVENTS_TTL = 10

local launcher
local indicators = {}
local smartShown = false

local function Within(x, y, r)
    local p = ns.player
    local dx, dy = x - p.x, y - p.y
    return dx * dx + dy * dy <= r * r
end

local function NearTrackedQuest(r)
    for _, e in ipairs(ns.scanResults) do
        if e.questID and not e.isTransit and Within(e.x, e.y, r) then return true end
    end
    return false
end

-- World positions of the world quests and area POI events on the map the
-- quest POIs are drawn for, as a flat x1, y1, x2, y2, ... array. The
-- getters allocate fresh tables, so the list is rebuilt per map/instance
-- every few seconds instead of every tick.
local eventPoints = {}
local eventsMap, eventsInstance, eventsAt

local function AddEventPoint(mapID, x, y, instance)
    local wx, wy = ns.MapToWorld(mapID, x, y, instance)
    if wx then
        eventPoints[#eventPoints + 1] = wx
        eventPoints[#eventPoints + 1] = wy
    end
end

local function RebuildEventPoints(mapID, instance)
    wipe(eventPoints)
    if C_TaskQuest and C_TaskQuest.GetQuestsOnMap then
        for _, info in ipairs(C_TaskQuest.GetQuestsOnMap(mapID) or {}) do
            if info.x and info.y then AddEventPoint(mapID, info.x, info.y, instance) end
        end
    end
    if C_AreaPoiInfo and C_AreaPoiInfo.GetEventsForMap then
        for _, id in ipairs(C_AreaPoiInfo.GetEventsForMap(mapID) or {}) do
            local poi = C_AreaPoiInfo.GetAreaPOIInfo(mapID, id)
            if poi and poi.position then AddEventPoint(mapID, poi.position.x, poi.position.y, instance) end
        end
    end
end

-- The selected quest's navigation anchor sits on the edge of its area, not
-- on the pin, so C_Navigation.GetDistance is the distance to the area —
-- the "Area radius" setting doubles as this trigger's threshold. Once the
-- diamond has faded out (arrived) the anchor distance stops being a
-- reliable "inside" signal, so that state counts too, unless the anchor is
-- known to be far away.
local function NearSelectedQuest(r)
    if not ns.GetSelectedQuestID() then return false end
    local d = C_Navigation and C_Navigation.GetDistance and C_Navigation.GetDistance()
    if d ~= nil and ns.IsSecret(d) then d = nil end
    if d and d <= r then return true end
    return ns.NavArrived() == true and (d == nil or d <= SMART_FAR_YARDS)
end

local function NearEvent(r)
    local instance = ns.player.instance
    local mapID = C_QuestLog.GetMapForQuestPOIs and C_QuestLog.GetMapForQuestPOIs()
    if not mapID or mapID == 0 then mapID = ns.player.mapID end
    if not mapID or mapID == 0 or not instance then return false end
    local now = GetTime()
    if mapID ~= eventsMap or instance ~= eventsInstance or now - eventsAt >= EVENTS_TTL then
        eventsMap, eventsInstance, eventsAt = mapID, instance, now
        RebuildEventPoints(mapID, instance)
    end
    for i = 1, #eventPoints, 2 do
        if Within(eventPoints[i], eventPoints[i + 1], r) then return true end
    end
    return false
end

local function EvalSmart()
    if UnitAffectingCombat("player") then return false end
    if IsInInstance() then return true end
    local hyst = smartShown and (SMART_FAR_YARDS - SMART_NEAR_YARDS) or 0
    local r = SMART_NEAR_YARDS + hyst
    if NearTrackedQuest(r) or NearEvent(r) then return true end
    return NearSelectedQuest(ns.db.inRegionYards + hyst)
end

-- Re-evaluates the cached smart state; true when it flipped.
local function RefreshSmart()
    local shown = ns.db and ns.db.display == ns.DISPLAY_SMART and EvalSmart() or false
    local changed = shown ~= smartShown
    smartShown = shown
    return changed
end

-- The minimap stays hidden in compass mode even while the bar itself is
-- away (combat), so it doesn't pop in and out.
local function WantHidden()
    local db = ns.db
    if not db then return false end
    if db.display == ns.DISPLAY_COMPASS then return true end
    if db.display == ns.DISPLAY_SMART then return not smartShown end
    return false
end

-- The display modes act on the own container (MinimapFrame.lua); with it in
-- place Blizzard's cluster (header, buttons, ring) is hidden for good.
-- Without it (Minimap missing) they fall back to the cluster.
local minimap = Nocturne.NewSuppressor(function() return ns.minimapFrame or _G.MinimapCluster end, WantHidden)
local cluster = Nocturne.NewSuppressor(function() return ns.minimapFrame and _G.MinimapCluster end,
    function() return true end)

-- Texture from the first atlas the client has, else a plain icon file.
local function SetIcon(tex, file, ...)
    local atlas = ns.FirstAtlas(...)
    if atlas then
        tex:SetAtlas(atlas)
    else
        tex:SetTexture(file)
        tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
end

local function IconMarkup(icon)
    if not icon then return "" end
    if type(icon) == "string" and C_Texture.GetAtlasInfo(icon) then
        return "|A:" .. icon .. ":14:14|a "
    end
    return "|T" .. icon .. ":14:14|t "
end

local function PendingInvites()
    return C_Calendar and C_Calendar.GetNumPendingInvites and C_Calendar.GetNumPendingInvites() or 0
end

-- Tracking info is a table on current clients, loose values on older ones.
local function TrackingInfo(i)
    local info, _, active = C_Minimap.GetTrackingInfo(i)
    if type(info) == "table" then return info.name, info.active end
    return info, active
end

local function AddBlizzardEntries(root)
    local landing = _G.ExpansionLandingPageMinimapButton
    if landing and landing:IsShown() then
        root:CreateButton(landing.title or "Expansion summary", function() landing:Click("LeftButton") end)
    end

    if _G.ToggleCalendar then
        local n = PendingInvites()
        root:CreateButton(n > 0 and ("Calendar (%d)"):format(n) or "Calendar", function() _G.ToggleCalendar() end)
    end

    if C_Minimap and C_Minimap.GetNumTrackingTypes then
        -- The full tracking list: learned townsfolk POIs follow these same
        -- toggles, so every category the client exposes gets an entry.
        -- Some entries share a display name ("Banker" covers several bank
        -- filters) — they collapse into one checkbox toggling them all.
        local tracking, order, byName
        for i = 1, C_Minimap.GetNumTrackingTypes() do
            local name = TrackingInfo(i)
            if name then
                order = order or {}
                byName = byName or {}
                local group = byName[name]
                if not group then
                    group = {}
                    byName[name] = group
                    order[#order + 1] = name
                end
                group[#group + 1] = i
            end
        end
        for _, name in ipairs(order or {}) do
            local group = byName[name]
            tracking = tracking or root:CreateButton("Tracking")
            tracking:CreateCheckbox(name,
                function()
                    for _, i in ipairs(group) do
                        if select(2, TrackingInfo(i)) then return true end
                    end
                end,
                function()
                    local on = true
                    for _, i in ipairs(group) do
                        if select(2, TrackingInfo(i)) then
                            on = false
                            break
                        end
                    end
                    for _, i in ipairs(group) do C_Minimap.SetTracking(i, on) end
                end)
        end
    end
end

-- Addons registered in Blizzard's Addon Compartment. Their func takes
-- (button, menuInputData, menu), same as the compartment's own menu.
local function AddCompartmentEntries(root, seen)
    local compartment = _G.AddonCompartmentFrame
    for _, info in ipairs(compartment and compartment.registeredAddons or {}) do
        if info.text and info.func and not seen[info.text] then
            seen[info.text] = true
            root:CreateButton(IconMarkup(info.icon) .. info.text, function(_, inputData, menu)
                info.func(launcher, inputData, menu)
            end)
        end
    end
end

-- Other addons' minimap buttons, via LibDBIcon when some addon loaded it.
-- Read-only use of another addon's library — not a dependency.
local function AddMinimapButtonEntries(root, seen)
    local LDBI = _G.LibStub and _G.LibStub("LibDBIcon-1.0", true)
    if not LDBI then return end
    for _, name in ipairs(LDBI:GetButtonList()) do
        local button = LDBI:GetMinimapButton(name)
        local obj = button and button.dataObject
        local label = obj and (obj.label or name)
        if obj and obj.OnClick and not (button.db and button.db.hide) and not seen[label] then
            seen[label] = true
            root:CreateButton(IconMarkup(obj.icon) .. label, function(_, inputData)
                obj.OnClick(launcher, inputData and inputData.buttonName or "LeftButton")
            end)
        end
    end
end

local function BuildMenu(_, root)
    AddBlizzardEntries(root)
    local seen = {}
    root:CreateDivider()
    AddCompartmentEntries(root, seen)
    AddMinimapButtonEntries(root, seen)
end

local function ShowTooltip(owner, fill)
    GameTooltip:SetOwner(owner, "ANCHOR_BOTTOMRIGHT")
    fill(GameTooltip)
    GameTooltip:Show()
end

local function CreateButton(parent, onTooltip)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:SetScript("OnEnter", function(self) ShowTooltip(self, onTooltip) end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

-- Indicators: shown only while their `count()` is > 0.
local function AddIndicator(file, atlas, count, onTooltip, onClick)
    local b = CreateButton(ns.frame, onTooltip)
    SetIcon(b.icon, file, atlas)
    if onClick then b:SetScript("OnClick", onClick) end
    b.count = count
    b:Hide()
    indicators[#indicators + 1] = b
end

local function Layout()
    if not launcher then return end
    -- The menu button is always part of the bar. Blizzard's mail/crafting
    -- indicators live on the (always hidden) cluster once the own container
    -- is up, so ours show whenever the bar does; else only while the
    -- minimap is suppressed.
    launcher:SetShown(ns.barVisible or false)
    local suppressed = ns.barVisible and (ns.minimapFrame ~= nil or WantHidden())
    local prev = launcher
    for _, b in ipairs(indicators) do
        local on = suppressed and b.count() > 0
        b:SetShown(on)
        if on then
            b:ClearAllPoints()
            b:SetPoint("LEFT", prev, "RIGHT", BUTTON_GAP, 0)
            prev = b
        end
    end
end

local function PersonalOrders()
    if not (C_CraftingOrders and C_CraftingOrders.GetPersonalOrdersInfo) then return 0, {} end
    local list, n = C_CraftingOrders.GetPersonalOrdersInfo() or {}, 0
    for _, o in ipairs(list) do n = n + (o.numPersonalOrders or 0) end
    return n, list
end

function ns:InitMinimapButtons()
    ns:InitMinimapFrame()
    launcher = CreateButton(ns.frame, function(tip)
        tip:AddLine("Minimap menu")
        tip:AddLine("Expansion summary, calendar, tracking and addon buttons.", 1, 1, 1, true)
    end)
    launcher:SetPoint("LEFT", ns.frame, "RIGHT", BUTTON_GAP, 0)
    SetIcon(launcher.icon, "Interface\\Icons\\INV_Misc_Map02")
    launcher:SetScript("OnClick", function(self)
        if Nocturne.GamepadRefuses("The minimap menu") then return end
        if MenuUtil and MenuUtil.CreateContextMenu then MenuUtil.CreateContextMenu(self, BuildMenu) end
    end)

    AddIndicator("Interface\\Icons\\INV_Letter_15", "UI-HUD-Minimap-Mail-Up",
        function() return HasNewMail() and 1 or 0 end,
        function(tip)
            tip:AddLine("New mail")
            for _, sender in ipairs({ GetLatestThreeSenders() }) do tip:AddLine(sender, 1, 1, 1) end
        end)

    local day = C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime and C_DateAndTime.GetCurrentCalendarTime()
    AddIndicator("Interface\\Icons\\Spell_Holy_BorrowedTime",
        day and ("UI-HUD-Calendar-%d-Up"):format(day.monthDay),
        PendingInvites,
        function(tip)
            tip:AddLine(("Calendar: %d pending invite(s)"):format(PendingInvites()))
            tip:AddLine("Click to open the calendar.", 1, 1, 1)
        end,
        function()
            if _G.ToggleCalendar and not Nocturne.GamepadRefuses("The calendar") then _G.ToggleCalendar() end
        end)

    AddIndicator("Interface\\Icons\\Trade_BlackSmithing", "UI-HUD-Minimap-CraftingOrder-Up",
        PersonalOrders,
        function(tip)
            tip:AddLine("Personal crafting orders")
            local _, list = PersonalOrders()
            for _, o in ipairs(list) do
                if (o.numPersonalOrders or 0) > 0 then
                    tip:AddDoubleLine(o.professionName or "?", o.numPersonalOrders, 1, 1, 1, 1, 1, 1)
                end
            end
        end)
end

-- Called from ApplyLayout and whenever the bar shows/hides.
function ns:ApplyMinimap()
    RefreshSmart()
    ns:ApplyMinimapFrame()
    cluster.Sync()
    minimap.Sync()
    Layout()
end

for _, event in ipairs({
    "UPDATE_PENDING_MAIL", "MAIL_CLOSED", "CALENDAR_UPDATE_PENDING_INVITES",
    "CRAFTINGORDERS_UPDATE_PERSONAL_ORDER_COUNTS", "PLAYER_ENTERING_WORLD",
}) do
    Nocturne.RegisterEvent(event, Layout)
end
Nocturne.RegisterEvent("PLAYER_REGEN_ENABLED", function() ns:ApplyMinimap() end)

-- Smart mode reacts to place/combat transitions immediately and to
-- quest-distance drift on a slow ticker (positions only change in
-- OnUpdate, there is no event for crossing the 150y line). The frames are
-- only touched when the smart state actually flips.
local function SmartSync()
    if ns.db and ns.db.display == ns.DISPLAY_SMART and RefreshSmart() then
        minimap.Sync()
        Layout()
    end
end
for _, event in ipairs({ "PLAYER_REGEN_DISABLED", "ZONE_CHANGED_NEW_AREA" }) do
    Nocturne.RegisterEvent(event, SmartSync)
end
C_Timer.NewTicker(0.5, SmartSync)
