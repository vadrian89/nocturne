local _, ns = ...

-- Clock left of the zone name, like the minimap's: Blizzard's own time
-- settings (local/realm time, 24h, alarm) apply. Click opens them,
-- right-click toggles the stopwatch.

local T = _G.Nocturne.Theme

local button

local function TimeText()
    if GameTime_GetTime then return GameTime_GetTime(true) end
    return date("%H:%M")
end

-- Both live in the load-on-demand Blizzard_TimeManager.
local function CallTimeManager(name)
    if not _G[name] and C_AddOns and C_AddOns.LoadAddOn then C_AddOns.LoadAddOn("Blizzard_TimeManager") end
    local fn = _G[name]
    if fn then fn() end
end

local function Update()
    local clock = ns.clock
    if not clock or not ns.db.showClock then return end
    local text = TimeText()
    if text ~= clock._text then
        clock._text = text
        clock:SetText(text)
    end
end

local function ShowTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine(_G.TIMEMANAGER_TOOLTIP_TITLE or "Time")
    if GameTime_GetLocalTime and GameTime_GetGameTime then
        GameTooltip:AddDoubleLine(_G.TIMEMANAGER_TOOLTIP_LOCALTIME or "Local time:",
            GameTime_GetLocalTime(true), 1, 1, 1, 1, 1, 1)
        GameTooltip:AddDoubleLine(_G.TIMEMANAGER_TOOLTIP_REALMTIME or "Realm time:",
            GameTime_GetGameTime(true), 1, 1, 1, 1, 1, 1)
    end
    GameTooltip:AddLine("Click: time options. Right-click: stopwatch.", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end

function ns:InitClock()
    ns.clock = T.CreateFontString(ns.frame, 12, nil, "OVERLAY", "OUTLINE")
    button = CreateFrame("Button", nil, ns.frame)
    button:SetAllPoints(ns.clock)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:SetScript("OnClick", function(_, mouse)
        CallTimeManager(mouse == "RightButton" and "Stopwatch_Toggle" or "TimeManager_Toggle")
    end)
    button:SetScript("OnEnter", ShowTooltip)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    C_Timer.NewTicker(1, Update)
end

-- Called from ApplyLayout and when the bar shows/hides (a faded-out bar
-- must not take clicks).
function ns:ApplyClock()
    if not button then return end
    local shown = ns.db.showClock
    ns.clock:SetShown(shown)
    button:SetShown(shown and ns.barVisible ~= false)
    Update()
end
