local _, ns = ...

-- Optional minimap replacement: Blizzard's minimap is hidden while the bar
-- is shown, and what lived on it moves next to the bar — a menu button
-- (expansion summary, calendar, tracking, addon compartment, other addons'
-- minimap buttons) plus mail / calendar invite / crafting order indicators.

local Nocturne = _G.Nocturne

local BUTTON_SIZE = 18
local BUTTON_GAP = 4

local launcher
local indicators = {}

-- The minimap stays hidden in compass mode even while the bar itself is
-- away (combat), so it doesn't pop in and out.
local function WantHidden()
    return ns.db and ns.db.display == ns.DISPLAY_COMPASS or false
end

local minimap = Nocturne.NewSuppressor(function() return _G.MinimapCluster end, WantHidden)

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
        local tracking = root:CreateButton("Tracking")
        for i = 1, C_Minimap.GetNumTrackingTypes() do
            local name = TrackingInfo(i)
            if name then
                tracking:CreateCheckbox(name,
                    function() return select(2, TrackingInfo(i)) and true or false end,
                    function() C_Minimap.SetTracking(i, not select(2, TrackingInfo(i))) end)
            end
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
    local shown = WantHidden() and ns.barVisible or false
    launcher:SetShown(shown)
    local prev = launcher
    for _, b in ipairs(indicators) do
        local on = shown and b.count() > 0
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
    launcher = CreateButton(ns.frame, function(tip)
        tip:AddLine("Minimap menu")
        tip:AddLine("Expansion summary, calendar, tracking and addon buttons.", 1, 1, 1, true)
    end)
    launcher:SetPoint("LEFT", ns.frame, "RIGHT", BUTTON_GAP, 0)
    SetIcon(launcher.icon, "Interface\\Icons\\INV_Misc_Map02")
    launcher:SetScript("OnClick", function(self)
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
        function() if _G.ToggleCalendar then _G.ToggleCalendar() end end)

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
