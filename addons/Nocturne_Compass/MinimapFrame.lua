local _, ns = ...

-- Own minimap container: Blizzard's Minimap is taken out of MinimapCluster
-- (a 256px Edit Mode box with header and edge buttons that eats clicks over
-- its whole area) into a frame just the size of the round map + Blizzard's
-- ring, in the top-right corner. MinimapCluster stays hidden for good; what
-- lived on it is on the compass menu and indicators (Minimap.lua). Blizzard
-- only re-anchors MinimapContainer (header-underneath / Edit Mode scale),
-- never Minimap. The ring (MinimapBackdrop / MinimapCompassTexture) is a
-- child of Minimap, so it comes along.

local Nocturne = _G.Nocturne
local T = Nocturne.Theme
local GetPlayerFacing = GetPlayerFacing
local sin, cos = math.sin, math.cos
local TWO_PI = 2 * math.pi

-- Blizzard's layout: a 198px map inside a 215x226 ring, both centered.
local MAP_DEFAULT, RING_W, RING_H = 198, 215, 226
local EDGE_INSET = 12  -- cardinal letters' distance from the map's edge
-- The outlined glyphs render ~1px left of their box center (observed: N/S
-- sat left of the ring's north arrow).
local LETTER_NUDGE_X = 1

-- Cardinal letters and their bearings (CW from north).
local CARDINALS = { { "N", 0 }, { "E", math.pi / 2 }, { "S", math.pi }, { "W", 3 * math.pi / 2 } }

local frame, overlay, holder
local letters = {}
local lastFacing
local ldbiHooked

-- Blizzard re-shows these (zoom buttons on hover); hidden from insecure
-- code, none of them are protected.
local function KeepHidden(f)
    if not f or f._noctHidden then return end
    f._noctHidden = true
    f:Hide()
    f:HookScript("OnShow", f.Hide)
end

-- Letters sit on a circle inside the map edge. `facingCW` is 0 unless the
-- minimap rotates with the player (Blizzard's "Rotate minimap" setting).
local function PlaceCardinals(facingCW)
    local r = Minimap:GetWidth() / 2 - EDGE_INSET
    for _, l in ipairs(letters) do
        local a = l.bearing - facingCW
        l.fs:SetPoint("CENTER", Minimap, "CENTER", r * sin(a) + LETTER_NUDGE_X, r * cos(a))
    end
end

local function OnUpdate()
    local f = GetPlayerFacing()
    if not f or ns.IsSecret(f) or f == lastFacing then return end
    lastFacing = f
    PlaceCardinals((TWO_PI - f) % TWO_PI)
end

-- Follows Blizzard's setting: with rotation on the heading points up and
-- the letters move around the edge (OnUpdate only then); off, they're fixed.
local function UpdateRotation()
    if not frame then return end
    local rotating = GetCVar("rotateMinimap") == "1"
    lastFacing = nil
    frame:SetScript("OnUpdate", rotating and OnUpdate or nil)
    if not rotating then PlaceCardinals(0) end
end

local function HideAddonButtons()
    local LDBI = _G.LibStub and _G.LibStub("LibDBIcon-1.0", true)
    if not LDBI then return end
    for _, name in ipairs(LDBI:GetButtonList()) do
        KeepHidden(LDBI:GetMinimapButton(name))
    end
    -- Hidden on our side only: LDBI:Hide() would write `hide = true` into
    -- each addon's own saved settings.
    if not ldbiHooked and LDBI.RegisterCallback then
        ldbiHooked = true
        LDBI.RegisterCallback(ns, "LibDBIcon_IconCreated", function(_, button) KeepHidden(button) end)
    end
end

-- Instance difficulty stays (small, top-left), only meaningful in instances.
local function AnchorDifficulty()
    local diff = MinimapCluster and MinimapCluster.InstanceDifficulty
    if not (diff and frame) then return end
    diff:SetParent(overlay)
    diff:ClearAllPoints()
    diff:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    diff:SetScale(0.8)
end

function ns:InitMinimapFrame()
    if frame or not Minimap then return end
    frame = CreateFrame("Frame", "NocturneCompassMinimap", UIParent)
    frame:SetFrameStrata("LOW")

    Minimap:SetParent(frame)
    Minimap:ClearAllPoints()
    Minimap:SetPoint("CENTER", frame, "CENTER")

    -- The expansion summary button sits on the ring; parked on a hidden
    -- holder it disappears but keeps IsShown(), which the compass menu
    -- uses to offer it.
    holder = CreateFrame("Frame", nil, frame)
    holder:Hide()
    local landing = _G.ExpansionLandingPageMinimapButton
    if landing then landing:SetParent(holder) end

    KeepHidden(Minimap.ZoomIn)
    KeepHidden(Minimap.ZoomOut)
    if Minimap.ZoomHitArea then Minimap.ZoomHitArea:EnableMouse(false) end

    overlay = CreateFrame("Frame", nil, frame)
    overlay:SetAllPoints(frame)
    overlay:SetFrameLevel(Minimap:GetFrameLevel() + 10)
    for i, c in ipairs(CARDINALS) do
        local color = i == 1 and T.colors.accent or T.colors.text
        local fs = T.CreateFontString(overlay, i == 1 and 15 or 13, color, "OVERLAY", "THICKOUTLINE")
        fs:SetText(c[1])
        letters[i] = { fs = fs, bearing = c[2] }
    end

    AnchorDifficulty()
    if MinimapCluster and MinimapCluster.SetHeaderUnderneath then
        hooksecurefunc(MinimapCluster, "SetHeaderUnderneath", AnchorDifficulty)
    end

    ns.minimapFrame = frame
    HideAddonButtons()
end

-- Size/position from settings; called from ApplyMinimap. The ring art is
-- sized for a 198px map, so it scales along with the map.
function ns:ApplyMinimapFrame()
    if not frame then return end
    local size = ns.db.minimapSize
    local ringW, ringH = size * RING_W / MAP_DEFAULT, size * RING_H / MAP_DEFAULT
    frame:ClearAllPoints()
    frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", 0, 0)
    frame:SetSize(ringW, ringH)
    for _, ring in ipairs({ _G.MinimapBackdrop, _G.MinimapCompassTexture }) do
        ring:SetSize(ringW, ringH)
    end
    if Minimap:GetWidth() ~= size then
        Minimap:SetSize(size, size)
        -- The render target only picks up a new size on a zoom change.
        local z = Minimap:GetZoom()
        Minimap:SetZoom(z > 0 and z - 1 or z + 1)
        Minimap:SetZoom(z)
    end
    UpdateRotation()
end

Nocturne.RegisterEvent("CVAR_UPDATE", UpdateRotation)
Nocturne.RegisterEvent("PLAYER_ENTERING_WORLD", function()
    HideAddonButtons()
    -- Addons creating their LibDBIcon buttons late (after login).
    C_Timer.After(3, HideAddonButtons)
end)
Nocturne.RegisterEvent("ADDON_LOADED", function()
    if frame then HideAddonButtons() end
end)
