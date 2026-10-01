local _, ns = ...

-- Own minimap container: Blizzard's Minimap is taken out of MinimapCluster
-- (a 256px Edit Mode box with header, ring art and edge buttons that eats
-- clicks over its whole area) into a compact square frame in the top-right
-- corner. MinimapCluster stays hidden for good; what lived on it is on the
-- compass menu and indicators (Minimap.lua). Blizzard only re-anchors
-- MinimapContainer (header-underneath / Edit Mode scale), never Minimap.

local Nocturne = _G.Nocturne
local T = Nocturne.Theme

local BORDER = 4
local EDGE_INSET = 9   -- cardinal letters' distance from the map edge
local SQUARE_MASK = "Interface\\Buttons\\WHITE8X8"

-- Cardinal letters at the middle of each edge (the map never rotates).
local CARDINALS = { { "N", "TOP", 0, -1 }, { "E", "RIGHT", -1, 0 }, { "S", "BOTTOM", 0, 1 }, { "W", "LEFT", 1, 0 } }

local frame, overlay
local ldbiHooked

-- Blizzard re-shows these (zoom buttons on hover, ring/landing button on
-- updates); hidden from insecure code, none of them are protected.
local function KeepHidden(f)
    if not f or f._noctHidden then return end
    f._noctHidden = true
    f:Hide()
    f:HookScript("OnShow", f.Hide)
end

-- North stays up: the letters are fixed, so rotation (Blizzard's "Rotate
-- minimap" option / Edit Mode setting) is kept off.
local function NoRotation()
    if GetCVar("rotateMinimap") ~= "0" then SetCVar("rotateMinimap", "0") end
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

local function SquareHybridMinimap()
    local hybrid = _G.HybridMinimap
    if hybrid and hybrid.CircleMask then hybrid.CircleMask:SetTexture(SQUARE_MASK) end
end

-- Instance difficulty stays (small, top-left), only meaningful in instances.
local function AnchorDifficulty()
    local diff = MinimapCluster and MinimapCluster.InstanceDifficulty
    if not (diff and frame) then return end
    diff:SetParent(overlay)
    diff:ClearAllPoints()
    diff:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, -2)
    diff:SetScale(0.8)
end

function ns:InitMinimapFrame()
    if frame or not Minimap then return end
    frame = CreateFrame("Frame", "NocturneCompassMinimap", UIParent)
    frame:SetFrameStrata("LOW")
    T.ApplyBackdrop(frame)

    Minimap:SetParent(frame)
    Minimap:ClearAllPoints()
    Minimap:SetPoint("CENTER", frame, "CENTER")
    Minimap:SetMaskTexture(SQUARE_MASK)
    -- Blob rings are drawn as circles around quest/dig areas.
    for _, fn in ipairs({ "SetArchBlobRingAlpha", "SetQuestBlobRingAlpha", "SetTaskBlobRingAlpha" }) do
        if Minimap[fn] then Minimap[fn](Minimap, 0) end
    end

    KeepHidden(_G.MinimapBackdrop) -- ring art + expansion button (menu keeps it)
    KeepHidden(Minimap.ZoomIn)
    KeepHidden(Minimap.ZoomOut)
    if Minimap.ZoomHitArea then Minimap.ZoomHitArea:EnableMouse(false) end
    SquareHybridMinimap()

    overlay = CreateFrame("Frame", nil, frame)
    overlay:SetAllPoints(frame)
    overlay:SetFrameLevel(Minimap:GetFrameLevel() + 10)
    for i, c in ipairs(CARDINALS) do
        local color = i == 1 and T.colors.accent or T.colors.text
        local fs = T.CreateFontString(overlay, i == 1 and 13 or 11, color, "OVERLAY", "OUTLINE")
        fs:SetText(c[1])
        fs:SetPoint("CENTER", Minimap, c[2], c[3] * EDGE_INSET, c[4] * EDGE_INSET)
    end
    NoRotation()

    AnchorDifficulty()
    if MinimapCluster and MinimapCluster.SetHeaderUnderneath then
        hooksecurefunc(MinimapCluster, "SetHeaderUnderneath", AnchorDifficulty)
    end

    -- Addons that clamp minimap pins/buttons to the edge (LibDBIcon,
    -- HereBeDragons) resolve this global by name.
    if not _G.GetMinimapShape then
        _G.GetMinimapShape = function() return "SQUARE" end
    end

    ns.minimapFrame = frame
    HideAddonButtons()
end

-- Size/position from settings; called from ApplyMinimap.
function ns:ApplyMinimapFrame()
    if not frame then return end
    local size = ns.db.minimapSize
    frame:ClearAllPoints()
    frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", 0, 0)
    frame:SetSize(size + 2 * BORDER, size + 2 * BORDER)
    if Minimap:GetWidth() ~= size then
        Minimap:SetSize(size, size)
        -- The render target only picks up a new size on a zoom change.
        local z = Minimap:GetZoom()
        Minimap:SetZoom(z > 0 and z - 1 or z + 1)
        Minimap:SetZoom(z)
    end
end

Nocturne.RegisterEvent("CVAR_UPDATE", function() if frame then NoRotation() end end)
Nocturne.RegisterEvent("PLAYER_ENTERING_WORLD", function()
    HideAddonButtons()
    -- Addons creating their LibDBIcon buttons late (after login).
    C_Timer.After(3, HideAddonButtons)
end)
Nocturne.RegisterEvent("ADDON_LOADED", function(_, name)
    if name == "Blizzard_HybridMinimap" then SquareHybridMinimap() end
    if frame then HideAddonButtons() end
end)
