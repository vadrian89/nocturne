local _, ns = ...

-- WoW Forever's native gamepad bars (Blizzard_GamepadActionBars, loads only
-- on camelot). Blizzard anchors each action button to its bar's CENTER and
-- re-anchors it on every press and expand/collapse; the buttons are secure,
-- so a bar can't be split across screen edges. GamepadMainActionBarFrame
-- itself is never re-anchored by Blizzard (only Hide/Show around its edit
-- frame), so the whole frame is moved and scaled — out of combat only,
-- since it holds protected children.
local EDGE   = 16  -- screen edge to the bars' rightmost content (UIParent units)
local BOT_Y  = 110 -- Blizzard's own BOTTOM offset
-- Frame is 656 wide. Compact layout (CVar GamepadUseCompactActionBar) stacks
-- every bar on the bottom anchor at the center, so its content ends ~180
-- from the center; the cross layout spans the whole frame.
local HALF_W         = 328
local COMPACT_HALF_W = 180

local pending = false

local function Frame() return _G.GamepadMainActionBarFrame end

local function IsCompact()
    return GetCVarBool and GetCVarBool("GamepadUseCompactActionBar")
end

function ns:ApplyNativeBars()
    local f = Frame()
    if not (f and ns.db) then return false end
    if InCombatLockdown() then
        pending = true
        return false
    end
    pending = false
    f:ClearAllPoints()
    if ns.db.nativeRight then
        local scale = ns.db.nativeScale / 100
        local inset = HALF_W - (IsCompact() and COMPACT_HALF_W or HALF_W)
        f:SetScale(scale)
        -- SetPoint offsets are in the frame's own scaled space.
        f:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT",
            -EDGE / scale + inset, BOT_Y / scale)
        ns.nativeMoved = true
    else
        f:SetScale(1)
        f:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, BOT_Y)
        ns.nativeMoved = false
    end
    return true
end

local function Refresh()
    if ns.db and (ns.db.nativeRight or ns.nativeMoved) then ns:ApplyNativeBars() end
end

_G.Nocturne.RegisterEvent("PLAYER_ENTERING_WORLD", Refresh)
_G.Nocturne.RegisterEvent("PLAYER_REGEN_ENABLED", function()
    if pending then ns:ApplyNativeBars() end
end)
_G.Nocturne.RegisterEvent("CVAR_UPDATE", function(_, name)
    if name == "GamepadUseCompactActionBar" then Refresh() end
end)

local function RightGap(region)
    if not (region and region:IsShown()) then return "hidden" end
    local r = region:GetRight()
    if not r then return "nil" end
    return ("%.1f"):format(UIParent:GetRight() * UIParent:GetEffectiveScale()
        - r * region:GetEffectiveScale())
end

function ns:NativeDiagText()
    local f = Frame()
    if not f then return "native bars: GamepadMainActionBarFrame missing" end
    local pu = f.PageUnit
    local point, rel, relPoint, x, y = f:GetPoint(1)
    return table.concat({
        ("native: right=%s scale=%s moved=%s pending=%s shown=%s compact=%s"):format(
            tostring(ns.db and ns.db.nativeRight), tostring(ns.db and ns.db.nativeScale),
            tostring(ns.nativeMoved), tostring(pending), tostring(f:IsShown()),
            tostring(IsCompact())),
        ("point=%s %s %s %s %s frameScale=%.2f"):format(tostring(point),
            tostring(rel and rel:GetName()), tostring(relPoint), tostring(x), tostring(y),
            f:GetScale()),
        ("rightGap(screen px): frame=%s bottomBar=%s rightBar=%s rightClass=%s"):format(
            RightGap(f), RightGap(pu and pu.BottomCenteredAnchor.Bar),
            RightGap(pu and pu.RightCenteredAnchor.Bar), RightGap(pu and pu.RightClassAction)),
    }, "\n")
end
