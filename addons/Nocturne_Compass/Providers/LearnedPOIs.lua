local _, ns = ...

-- Learned POIs: townsfolk positions (vendors, innkeepers, mailboxes...)
-- are engine-drawn and have no Lua API, so the addon records where the
-- player stood when that service's frame opened
-- (PLAYER_INTERACTION_MANAGER_FRAME_SHOW carries the interaction type).
-- Flight masters get the same treatment via TAXIMAP_OPENED, where
-- GetAllTaxiNodes identifies the exact node — the stored position then
-- overrides the map icon's, which can sit tens of yards off the real one.
-- Positions are stored unconditionally, but the compass marker only
-- renders while one of the POI's minimap tracking filters is enabled.
-- Records are keyed per NPC (creature ID), so every interaction with it —
-- gossip included — refreshes the same record's position.

local IT = Enum.PlayerInteractionType or {}
local F = Enum.MinimapTrackingFilter or {}

local KIND = {}
local function K(itype, label, ...)
    if itype then KIND[itype] = { label = label, bits = { ... } } end
end
-- A generic merchant can't be told apart from food/reagent/poison vendors,
-- so it follows whichever vendor filter the player has on.
local VENDOR_BITS = { F.VenderFood, F.VendorReagent, F.VendorPoison, F.Repair }
local function V(itype)
    K(itype, "Vendor", unpack(VENDOR_BITS))
    if itype then KIND[itype].vendor = true end
end
V(IT.Merchant)
V(IT.Vendor)
V(IT.PetitionVendor)
V(IT.GuildTabardVendor)
V(IT.PerksProgramVendor)
V(IT.PersonalTabardVendor)
K(IT.Trainer, "Trainer", F.TrainerProfession)
K(IT.Professions, "Trainer", F.TrainerProfession)
K(IT.ProfessionRespec, "Trainer", F.TrainerProfession)
K(IT.TalentMaster, "Trainer", F.TrainerProfession)
K(IT.Banker, "Banker", F.Banker)
K(IT.GuildBanker, "Guild Banker", F.Banker)
K(IT.VoidStorageBanker, "Void Storage", F.Banker)
K(IT.CharacterBanker, "Banker", F.Banker)
K(IT.AccountBanker, "Account Bank", F.AccountBanker)
K(IT.MailInfo, "Mailbox", F.Mailbox)
K(IT.Binder, "Innkeeper", F.Innkeeper)
K(IT.Auctioneer, "Auction House", F.Auctioneer)
K(IT.BlackMarketAuctioneer, "Black Market", F.Auctioneer)
K(IT.StableMaster, "Stable Master", F.Stablemaster)
K(IT.BattleMaster, "Battlemaster", F.Battlemaster)
K(IT.Transmogrifier, "Transmogrifier", F.Transmogrifier)
K(IT.ItemUpgrade, "Item Upgrade", F.ItemUpgrade)
K(IT.ForgeMaster, "Item Upgrade", F.ItemUpgrade)
K(IT.BarbersChoice, "Barber", F.Barber)

-- A learned POI renders only while one of its tracking filters is on.
local function ActiveBit(kind)
    if not kind then return nil end
    for _, bit in ipairs(kind.bits) do
        if bit and ns.TrackingFilterActive(bit) then return bit end
    end
    return nil
end

-- The tracking menu's own name/icon per filter bit
-- (MinimapScriptTrackingInfo .texture is a fileID), plus name -> bit: the
-- menu uses the same localized service names NPCs carry as their
-- "<Subtitle>" ("Innkeeper", "Food & Drink", "Reagents", "Stable Master").
local trackInfo, trackByName
local function LoadTracking()
    if trackInfo then return true end
    if not (C_Minimap and C_Minimap.GetNumTrackingTypes and C_Minimap.GetTrackingFilter) then return end
    local n = C_Minimap.GetNumTrackingTypes()
    if not n or n == 0 then return end
    trackInfo, trackByName = {}, {}
    for i = 1, n do
        local f = C_Minimap.GetTrackingFilter(i)
        local info = C_Minimap.GetTrackingInfo(i)
        local name, tex
        if type(info) == "table" then
            name, tex = info.name, info.texture
        else
            name, tex = C_Minimap.GetTrackingInfo(i)
        end
        local bit = f and f.filterID
        if bit and bit ~= 0 and not trackInfo[bit] and type(name) == "string"
            and not ns.IsSecret(name) and not ns.IsSecret(tex) then
            trackInfo[bit] = { name = name, texture = tex }
            trackByName[name:lower()] = trackByName[name:lower()] or bit
        end
    end
    return true
end

local function FilterInfo(bit)
    if bit ~= nil and LoadTracking() then return trackInfo[bit] end
end

local function FilterIcon(bit)
    local info = FilterInfo(bit)
    return info and info.texture
end

-- Vendor subtype: repair is exact, then the tooltip subtitle
-- ("<Food & Drink>", "<Poison Vendor>"), then what the merchant sells.
local function ClassifyVendor()
    if CanMerchantRepair and CanMerchantRepair() then return F.Repair end
    local tip = C_TooltipInfo and C_TooltipInfo.GetUnit and C_TooltipInfo.GetUnit("npc")
    if tip and tip.lines then
        for _, line in ipairs(tip.lines) do
            local text = line.leftText
            if type(text) == "string" and not ns.IsSecret(text) then
                if text:find("Food") or text:find("Drink") then return F.VenderFood end
                if text:find("Reagent") then return F.VendorReagent end
                if text:find("Poison") then return F.VendorPoison end
            end
        end
    end
    if not (GetNumMerchantItems and GetMerchantItemLink
            and C_Item and C_Item.GetItemInfoInstant) then
        return
    end
    local IC, CS = Enum.ItemClass or {}, Enum.ItemConsumableSubclass or {}
    local counts, total
    for i = 1, GetNumMerchantItems() do
        local link = GetMerchantItemLink(i)
        if link and not ns.IsSecret(link) then
            local classID, subclassID = select(6, C_Item.GetItemInfoInstant(link))
            local bit
            if classID == IC.Consumable and subclassID == CS.Fooddrink then
                bit = F.VenderFood
            elseif classID == IC.Reagent or classID == IC.Tradegoods then
                bit = F.VendorReagent
            end
            if bit then
                counts = counts or {}; counts[bit] = (counts[bit] or 0) + 1
                total = (total or 0) + 1
            end
        end
    end
    local best, bn
    for bit, n in pairs(counts or {}) do
        if not bn or n > bn then best, bn = bit, n end
    end
    if best and bn * 2 >= total then return best end
end

local mapProvider
local lastRefresh = {}

local function PlayerPos()
    local mapID = C_Map.GetBestMapForUnit("player")
    local pos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos or ns.IsSecret(pos.x) or ns.IsSecret(pos.y) then return end
    return mapID, pos.x, pos.y
end

local function RefreshMapPins()
    if mapProvider and WorldMapFrame and WorldMapFrame:IsShown() then
        mapProvider:RefreshAllData()
    end
    ns.MarkScanDirty(true)
end

-- Classification strength, so a weaker interaction never overwrites a
-- stronger one: an innkeeper's shop window (Merchant) must not turn a known
-- innkeeper back into a "Vendor". The bind option's confirmation popup
-- fires Binder even when cancelled (proven in-game), so "bind -> Cancel"
-- is enough to learn an innkeeper.
local RANK_NONE, RANK_VENDOR, RANK_SERVICE, RANK_SUBTITLE = 0, 1, 2, 3

local function Rank(rec)
    if rec.r then return rec.r end
    if not rec.t then return RANK_NONE end
    local kind = KIND[rec.t]
    return kind and kind.vendor and RANK_VENDOR or RANK_SERVICE
end

-- Flight masters are learned per taxi node (TAXIMAP_OPENED), not as NPCs.
local SUBTITLE_SKIP = { [F.TaxiNode or -1] = true }

-- The NPC's subtitle tooltip line matched against the tracking names.
-- C_TooltipInfo carries it WITHOUT the "<>" drawn on screen (proven:
-- "Innkeeper Grosk | Innkeeper | Level 9 | ..."), so a whole line equal to
-- a tracking name is the match; line 1 is the NPC's own name.
-- Localized class names (both genders) -> classFile, longest first so
-- "Demon Hunter" wins over "Hunter". Class trainers carry no tracking
-- name; their subtitle ("Warrior Trainer") names the class instead.
local classNames
local function ClassNames()
    if classNames then return classNames end
    classNames = {}
    local function add(name, file)
        if type(name) == "string" and name ~= "" then
            classNames[#classNames + 1] = { name = name:lower(), file = file }
        end
    end
    for i = 1, (GetNumClasses and GetNumClasses() or 0) do
        local info = C_CreatureInfo and C_CreatureInfo.GetClassInfo(i)
        local file = info and info.classFile
        if file then
            add(info.className, file)
            add(LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[file], file)
            add(LOCALIZED_CLASS_NAMES_FEMALE and LOCALIZED_CLASS_NAMES_FEMALE[file], file)
        end
    end
    table.sort(classNames, function(a, b) return #a.name > #b.name end)
    return classNames
end

local function ClassInSubtitle(text)
    local lower = text:lower()
    for _, c in ipairs(ClassNames()) do
        if lower:find(c.name, 1, true) then return c.file end
    end
    return nil
end

-- Results: tracking bit, subtitle text, raw tooltip lines (diag), and the
-- classFile when the subtitle (line 2) names a class instead.
local function SubtitleBit()
    if not (LoadTracking() and C_TooltipInfo and C_TooltipInfo.GetUnit) then return end
    local tip = C_TooltipInfo.GetUnit("npc")
    if not (tip and tip.lines) then return nil, nil, "no tooltip" end
    local raw, bit, sub, class = {}, nil, nil, nil
    for i, line in ipairs(tip.lines) do
        local text = line.leftText
        if ns.IsSecret(text) then
            raw[#raw + 1] = "<secret>"
        elseif type(text) == "string" then
            raw[#raw + 1] = text
            if i > 1 and not bit then
                local s = text:match("^<(.+)>$") or text
                local b = trackByName[s:lower()]
                if b and not SUBTITLE_SKIP[b] then
                    bit, sub, class = b, s, nil
                elseif i == 2 then
                    class = ClassInSubtitle(s)
                    if class then sub = s end
                end
            end
        end
    end
    return bit, sub, table.concat(raw, " | "), class
end

-- Creatures are identified by their NPC ID; mailboxes and other objects
-- share entry IDs across locations, so they're matched by proximity.
local function NpcIdentity()
    if not UnitExists("npc") then return end
    local name = UnitName("npc")
    if ns.IsSecret(name) then name = nil end
    local guid = UnitGUID("npc")
    if not guid or ns.IsSecret(guid) then return name end
    local unitType, _, _, _, _, id = strsplit("-", guid)
    if unitType == "Creature" or unitType == "Vehicle" then
        return name, id, true
    end
    return name
end

local function UniqueKey(t, prefix)
    local i = 1
    while t[prefix .. i] do i = i + 1 end
    return prefix .. i
end

local MERGE_YARDS = 15
local function NearbyKey(t, mapID, prefix, x, y)
    local inst = ns.player.instance
    local wx, wy = ns.MapToWorld(mapID, x, y, inst)
    if not wx then return end
    for key, rec in pairs(t) do
        if key:sub(1, #prefix) == prefix then
            local rx, ry = ns.MapToWorld(mapID, rec.x, rec.y, inst)
            if rx and (rx - wx) ^ 2 + (ry - wy) ^ 2 <= MERGE_YARDS ^ 2 then return key end
        end
    end
end

-- Records used to be keyed "<interactionType>|<npcID or name or ?>", which
-- split one NPC into several records; fold them into the per-NPC keys.
local migrated
local function Migrate()
    if migrated or not (ns.db and ns.db.pois) then return end
    migrated = true
    for _, t in pairs(ns.db.pois) do
        local old = {}
        for key in pairs(t) do
            if type(key) == "string" and key:find("^%d+|") then old[#old + 1] = key end
        end
        for _, key in ipairs(old) do
            local rec = t[key]
            t[key] = nil
            local rest = key:match("^%d+|(.+)$")
            local newKey
            if rest:find("^%d+$") then
                newKey = "npc:" .. rest
            elseif rest ~= "?" then
                newKey = "name:" .. rest
            else
                newKey = UniqueKey(t, "obj:" .. tostring(rec.t) .. ":")
            end
            local cur = t[newKey]
            if not cur or Rank(rec) > Rank(cur) then t[newKey] = rec end
        end
    end
end

ns.seenIT = {}

_G.Nocturne.RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(_, itype)
    if not ns.db or ns.IsSecret(itype) then return end
    Migrate()
    local seen = ns.seenIT
    if #seen >= 15 then table.remove(seen, 1) end
    seen[#seen + 1] = tostring(itype)
    local mapID, x, y = PlayerPos()
    if not mapID then return end
    local kind = KIND[itype]
    local name, id, isCreature = NpcIdentity()
    local subBit, subText, tipLines, class
    if isCreature then subBit, subText, tipLines, class = SubtitleBit() end

    -- Class trainers are saved for every class; only the player's own
    -- class is displayed (PoiShown).
    local rank, v = RANK_NONE, nil
    if subBit or class then
        rank, v = RANK_SUBTITLE, subBit
    elseif kind and not kind.vendor then
        rank = RANK_SERVICE
    elseif kind then
        rank, v = RANK_VENDOR, ClassifyVendor()
    end
    ns.lastInteraction = {
        itype = itype, sub = subText, subBit = subBit, class = class, rank = rank, tip = tipLines,
    }

    local pois = ns.db.pois
    local t = pois[mapID] or {}
    local key
    if id then
        key = "npc:" .. id
    elseif name and isCreature then
        key = "name:" .. name
    elseif kind then
        local prefix = "obj:" .. itype .. ":"
        key = NearbyKey(t, mapID, prefix, x, y) or UniqueKey(t, prefix)
    end
    if not key then return end
    local rec = t[key]
    if not rec then
        -- Plain gossip only refreshes NPCs already learned.
        if rank == RANK_NONE then return end
        rec = {}
        t[key] = rec
        pois[mapID] = t
    end
    rec.x, rec.y = x, y
    rec.n = name or rec.n
    local cur = Rank(rec)
    if rank > cur or (rank == cur and rank > RANK_NONE and (v ~= nil or class ~= nil)) then
        rec.t, rec.v, rec.r = itype, v, rank
        rec.c, rec.s = class, class and subText or nil
    end
    ns.lastInteraction.key = key
    RefreshMapPins()
end)

-- Taxi: PLAYER_INTERACTION_MANAGER gives no node id, so the node is
-- identified on TAXIMAP_OPENED via the Current state — the stored spot
-- then overrides the map icon position everywhere the pin is drawn.
_G.Nocturne.RegisterEvent("TAXIMAP_OPENED", function()
    if not (ns.db and C_TaxiMap and C_TaxiMap.GetAllTaxiNodes) then return end
    local mapID, x, y = PlayerPos()
    local taxiMap = GetTaxiMapID and GetTaxiMapID()
    if not (mapID and taxiMap) then return end
    local current = Enum.FlightPathState and Enum.FlightPathState.Current or 0
    for _, node in ipairs(C_TaxiMap.GetAllTaxiNodes(taxiMap) or {}) do
        if node.state == current and node.nodeID then
            local name = node.name
            if ns.IsSecret(name) then name = nil end
            ns.db.taxi[node.nodeID] = { m = mapID, x = x, y = y, n = name }
            RefreshMapPins()
        end
    end
end)

-- ------------------------------------------------------------------------
-- Compass provider
-- ------------------------------------------------------------------------

local provider = { name = "learnedPOIs" }
ns.providers[#ns.providers + 1] = provider
provider.results = {}

local function PoiLabel(poi)
    if poi.c then return poi.s or "Class Trainer" end
    local kind = KIND[poi.t]
    if poi.v then
        local info = FilterInfo(poi.v)
        if info and info.name then return info.name end
    end
    return kind and kind.label or "POI"
end

local function PoiTitle(poi)
    local label = PoiLabel(poi)
    return poi.n and (poi.n .. " — " .. label) or label
end

-- A classified vendor follows its own filter only; unclassified POIs any of
-- their kind's filters.
local function PoiBit(poi)
    if poi.v then
        return ns.TrackingFilterActive(poi.v) and poi.v or nil
    end
    return ActiveBit(KIND[poi.t])
end

-- Whether a POI is drawn (compass and world map), plus its icon: a fileID
-- (tracking filter icon) or an atlas. Class trainers have no tracking
-- filter; they show only for the player's own class.
-- Icon (fileID) or atlas for a POI. `bit` is the active filter when known;
-- otherwise the POI's own/first filter, so a destination keeps its icon
-- even with tracking off.
local function PoiIcon(poi, bit)
    if poi.c then
        local lower = poi.c:lower()
        return nil, ns.FirstAtlas("classicon-" .. lower, "groupfinder-icon-class-" .. lower)
    end
    local kind = KIND[poi.t]
    return FilterIcon(bit or poi.v or (kind and kind.bits[1])), nil
end

local function PoiShown(poi)
    if poi.c then
        if poi.c ~= select(2, UnitClass("player")) then return false end
        return true, PoiIcon(poi)
    end
    local bit = PoiBit(poi)
    if not bit then return false end
    return true, PoiIcon(poi, bit)
end

-- A waypoint read back from the client can drift in the last float digits.
local WP_EPS = 1e-3

local function WaypointAt(wp, mapID, x, y)
    return wp and wp.uiMapID == mapID and wp.position
        and math.abs(wp.position.x - x) < WP_EPS
        and math.abs(wp.position.y - y) < WP_EPS or false
end

-- The learned POI a user waypoint was placed on (by clicking its map pin).
local function PoiAtWaypoint(wp)
    if not (wp and ns.db and ns.db.pois) then return end
    for _, poi in pairs(ns.db.pois[wp.uiMapID] or {}) do
        if WaypointAt(wp, wp.uiMapID, poi.x, poi.y) then return poi end
    end
end

-- MapPins draws the user waypoint marker with the POI's name and icon
-- (title, icon fileID, atlas); nil when the waypoint isn't on a POI.
function ns.LearnedWaypointInfo(wp)
    Migrate()
    local poi = PoiAtWaypoint(wp)
    if not poi then return nil end
    return PoiTitle(poi), PoiIcon(poi)
end

function provider:Scan(playerMapID, playerInstance)
    local results = wipe(self.results)
    if not (ns.db and ns.db.pois) then return results end
    Migrate()
    -- The waypoint marker (MapPins) already stands on a tracked POI.
    local wp = C_SuperTrack.IsSuperTrackingUserWaypoint() and C_Map.GetUserWaypoint()
    for _, mapID in ipairs(ns.CandidateMaps(playerMapID)) do
        for key, poi in pairs(ns.db.pois[mapID] or {}) do
            local shown, icon, atlas = PoiShown(poi)
            if shown and not WaypointAt(wp, mapID, poi.x, poi.y) then
                local wx, wy = ns.MapToWorld(mapID, poi.x, poi.y, playerInstance)
                if wx then
                    results[#results + 1] = {
                        key = "learn:" .. mapID .. ":" .. key,
                        provider = self,
                        title = PoiTitle(poi),
                        x = wx,
                        y = wy,
                        icon = icon,
                        atlas = atlas,
                    }
                end
            end
        end
    end
    return results
end

function provider:IsInRegion(entry, dist)
    return dist <= 10
end

function ns.LearnedPOIDiag(lines)
    Migrate()
    local li = ns.lastInteraction
    if li then
        lines[#lines + 1] = ("  lastInteraction it=%s sub=%s subBit=%s class=%s rank=%s key=%s"):format(
            tostring(li.itype), tostring(li.sub), tostring(li.subBit), tostring(li.class),
            tostring(li.rank), tostring(li.key))
        lines[#lines + 1] = "  tooltip: " .. tostring(li.tip)
    end
    local mapID = ns.player.mapID
    for key, poi in pairs(ns.db and ns.db.pois and (ns.db.pois[mapID] or {}) or {}) do
        local shown, icon, atlas = PoiShown(poi)
        lines[#lines + 1] = ("  learn %s t=%s v=%s c=%s r=%s label=%s shown=%s icon=%s"):format(
            key, tostring(poi.t), tostring(poi.v), tostring(poi.c), tostring(Rank(poi)),
            tostring(PoiLabel(poi)), tostring(shown), tostring(atlas or icon))
    end
end

-- ------------------------------------------------------------------------
-- World map pins
-- ------------------------------------------------------------------------

local PIN_TEMPLATE = "NocturneLearnedPOI"

local function CopyMixin(target, mixin)
    if Mixin then
        Mixin(target, mixin)
    else
        for k, v in pairs(mixin) do target[k] = v end
    end
end

local PinMixin = {}
if CreateFromMixins and MapCanvasPinMixin then
    PinMixin = CreateFromMixins(MapCanvasPinMixin)
elseif MapCanvasPinMixin then
    CopyMixin(PinMixin, MapCanvasPinMixin)
end

-- The frame's own SetPassThroughButtons, before PinMixin shadows it.
local NativePassThrough

-- AcquirePin reads IsMouseMotionEnabled()/IsMouseClickEnabled() BEFORE
-- calling OnLoad to decide whether to wire OnMouseEnter/OnMouseLeave and
-- the click scripts, so mouse state has to be set at frame creation.
local function InitPin(pin)
    NativePassThrough = NativePassThrough or pin.SetPassThroughButtons
    CopyMixin(pin, PinMixin)
    pin:SetSize(14, 14)
    pin.Texture = pin:CreateTexture(nil, "OVERLAY")
    pin.Texture:SetAllPoints()
    pin:SetMouseMotionEnabled(true)
    pin:SetMouseClickEnabled(true)
end

-- Same limits as Blizzard's POI pins (SharedMapPoiTemplates): constant
-- on-screen size, slightly larger zoomed in. The AM_PIN_SCALE_STYLE_*
-- presets shrink a pin to 1% at one end of the zoom range.
function PinMixin:OnLoad()
    self:SetScalingLimits(1, 1.0, 1.2)
    self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI")
end

-- AcquirePin calls CheckMouseButtonPassthrough -> SetPassThroughButtons
-- (right-click through to the map, to zoom out). Reportedly protected in
-- combat (HereBeDragons stubs it out) — only forwarded outside it.
function PinMixin:SetPassThroughButtons(...)
    if NativePassThrough and not InCombatLockdown() then
        NativePassThrough(self, ...)
    end
end

function PinMixin:IsDestination()
    local x, y = self:GetPosition()
    return C_SuperTrack.IsSuperTrackingUserWaypoint()
        and WaypointAt(C_Map.GetUserWaypoint(), self:GetMap():GetMapID(), x, y)
end

-- Left click: make this POI the destination (user waypoint, super-tracked);
-- clicking the current destination again clears it.
function PinMixin:OnMouseClickAction(button)
    if button ~= "LeftButton" then return end
    local mapID = self:GetMap():GetMapID()
    local x, y = self:GetPosition()
    if not (mapID and x and y) then return end
    if self:IsDestination() then
        C_Map.ClearUserWaypoint()
    elseif C_Map.CanSetUserWaypointOnMap(mapID) then
        C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, x, y))
        C_SuperTrack.SetSuperTrackedUserWaypoint(true)
    end
    if self:IsMouseOver() then self:OnMouseEnter() end
end

-- Yards from the player, when the pin sits in the player's instance.
function PinMixin:Distance()
    local p = ns.player
    local x, y = self:GetPosition()
    local wx, wy = ns.MapToWorld(self:GetMap():GetMapID(), x, y, p.instance)
    if not (wx and p.x) then return end
    return math.sqrt((wx - p.x) ^ 2 + (wy - p.y) ^ 2)
end

-- The canvas asserts OnEnter/OnLeave scripts are nil on new pins and wires
-- OnMouseEnter/OnMouseLeave itself.
function PinMixin:OnMouseEnter()
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if self._name then
        GameTooltip:AddLine(self._name, 1, 1, 1)
        GameTooltip:AddLine(self._label, 1, 0.82, 0)
    else
        GameTooltip:AddLine(self._label or "?", 1, 1, 1)
    end
    local dist = self:Distance()
    if dist then
        GameTooltip:AddLine(("%d yd"):format(dist), 0.8, 0.8, 0.8)
    end
    if self:IsDestination() then
        GameTooltip:AddLine("Current destination", 0.4, 0.8, 1)
        GameTooltip:AddLine("Click: clear destination", 0.6, 0.6, 0.6)
    else
        GameTooltip:AddLine("Click: set as destination", 0.6, 0.6, 0.6)
    end
    GameTooltip:Show()
end

function PinMixin:OnMouseLeave()
    GameTooltip:Hide()
end

function PinMixin:OnAcquired(data)
    self._name, self._label = data.name, data.label
    if data.icon then
        self.Texture:SetTexture(data.icon)
        self.Texture:SetTexCoord(0, 1, 0, 1)
    else
        self.Texture:SetAtlas(data.atlas or "Waypoint-MapPin-Tracked")
    end
    self:SetPosition(data.x, data.y)
end

function PinMixin:OnReleased()
    self._name, self._label = nil, nil
end

local function ResetPin(pool, pin)
    pin:Hide()
    pin:ClearAllPoints()
    if pin.OnReleased then pin:OnReleased() end
end

local function EnsureMapProvider()
    if mapProvider or not (WorldMapFrame and WorldMapFrame.AddDataProvider
            and MapCanvasDataProviderMixin and CreateFromMixins and CreateFramePool) then
        return
    end
    mapProvider = CreateFromMixins(MapCanvasDataProviderMixin)

    function mapProvider:RemoveAllData()
        self:GetMap():RemoveAllPinsByTemplate(PIN_TEMPLATE)
    end

    local function Refresh(self)
        Migrate()
        self:RemoveAllData()
        local mapID = self:GetMap():GetMapID()
        lastRefresh.mapID, lastRefresh.n, lastRefresh.err = mapID, 0, nil
        if not (ns.db and ns.db.pois) then return end
        -- Same rule as the compass: only POIs whose tracking filter is on.
        for _, poi in pairs(ns.db.pois[mapID] or {}) do
            local shown, icon, atlas = PoiShown(poi)
            if shown then
                self:GetMap():AcquirePin(PIN_TEMPLATE, {
                    x = poi.x,
                    y = poi.y,
                    name = poi.n,
                    label = PoiLabel(poi),
                    icon = icon,
                    atlas = atlas,
                })
                lastRefresh.n = lastRefresh.n + 1
            end
        end
    end

    -- The canvas runs providers through secureexecuterange, so an error
    -- here is swallowed unless scriptErrors is on; keep it for the diag.
    function mapProvider:RefreshAllData()
        local ok, err = pcall(Refresh, self)
        if not ok then lastRefresh.err = tostring(err) end
    end

    WorldMapFrame.pinPools[PIN_TEMPLATE] = CreateFramePool("FRAME",
        WorldMapFrame:GetCanvas(), nil, ResetPin, false, InitPin)
    WorldMapFrame:AddDataProvider(mapProvider)
end

-- The world map loads on demand; the provider attaches once it exists.
if WorldMapFrame then
    EnsureMapProvider()
end
_G.Nocturne.RegisterEvent("ADDON_LOADED", function(_, name)
    if name == "Blizzard_WorldMap" then EnsureMapProvider() end
end)
-- Pins follow the tracking menu; toggling a filter with the map open
-- redraws them.
_G.Nocturne.RegisterEvent("MINIMAP_UPDATE_TRACKING", RefreshMapPins)

local function Num(v)
    return v and ("%.2f"):format(v) or "nil"
end

function ns.WorldMapPinDiag(lines)
    local map = WorldMapFrame
    lines[#lines + 1] = ("worldmap frame=%s provider=%s attached=%s shown=%s mapID=%s"):format(
        tostring(map ~= nil), tostring(mapProvider ~= nil),
        tostring(map and mapProvider and map.dataProviders
            and map.dataProviders[mapProvider] or false),
        tostring(map and map:IsShown()), tostring(map and map.GetMapID and map:GetMapID()))
    lines[#lines + 1] = ("  lastRefresh map=%s n=%s err=%s"):format(
        tostring(lastRefresh.mapID), tostring(lastRefresh.n), tostring(lastRefresh.err))
    if not (map and map.EnumeratePinsByTemplate) then return end
    local i = 0
    for pin in map:EnumeratePinsByTemplate(PIN_TEMPLATE) do
        i = i + 1
        if i <= 5 then
            local cx, cy = pin:GetCenter()
            lines[#lines + 1] = ("  pin %s/%s onEnter=%s shown=%s visible=%s alpha=%s scale=%s eff=%s level=%s size=%sx%s center=%s,%s tex=%s parentOK=%s"):format(
                tostring(pin._name), tostring(pin._label), tostring(pin:GetScript("OnEnter") ~= nil),
                tostring(pin:IsShown()), tostring(pin:IsVisible()),
                Num(pin:GetEffectiveAlpha()), Num(pin:GetScale()), Num(pin:GetEffectiveScale()),
                tostring(pin:GetFrameLevel()), Num(pin:GetWidth()), Num(pin:GetHeight()),
                Num(cx), Num(cy), tostring(pin.Texture and pin.Texture:GetTexture()),
                tostring(pin:GetParent() == map:GetCanvas()))
        end
    end
    lines[#lines + 1] = "  activePins=" .. i
end
