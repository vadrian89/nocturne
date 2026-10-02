local _, ns       = ...

-- ConsolePort applies named layouts through its own preset system:
-- ConsolePort_BarPresets is the user-preset saved var (proxied into
-- env.Presets), and ConsolePort('layout <name>') runs the same code path as
-- /cp layout — ReleaseAll + env('Layout', preset) + OnLayoutChanged, deferred
-- out of combat by CP's RunSafe.
local PRESET_KEY  = 'NocturneCompact'
local PRESET_NAME = 'Nocturne Compact'
local BACKUP_KEY  = 'NocturneBackup'
local BACKUP_NAME = 'Backup (pre-Nocturne)'

-- Geometry (cluster-bar units). The cluster bar is widened to the screen
-- width so its LEFT/RIGHT edges sit at the screen edges; each ring keeps
-- the stock cross shape (64px buttons) pinned to its side: dpad ring
-- anchored LEFT, face ring anchored RIGHT. In a cross, neighboring
-- buttons sit diagonal to each other; the visible round art is smaller
-- than the 64px frame, so to get the rims ~2px apart the centers go to
-- ~66px on the diagonal -> offset s = 66/sqrt(2) ~ 47. Frame corners
-- overlap (~19px); harmless for gamepad input.
local EDGE        = 16                  -- screen edge to a ring's outermost button edge
local HALF        = 32                  -- button half-size
local D_OFF       = 47                  -- both rings: round art ~2px apart
local RING_INSET  = EDGE + HALF + D_OFF -- ring centers from the screen edges
local RING_Y      = 42
local SH_X        = 75                  -- shoulders/triggers: diagonal corners of the
local SH_UP       = 82                  -- face ring (LB/RB up, LT/RT down)
local SH_DOWN     = 70
local SH_SIZE     = 48                  -- shoulders/triggers: smaller than ring buttons
ns.PRESET_NAME    = PRESET_NAME
-- Bump when the geometry changes: Init re-applies the preset once.
ns.LAYOUT_VERSION = 11

local function Handle(x, y, dir, side, size)
    return {
        type = 'ClusterHandle',
        pos = { point = side, relPoint = side, x = x, y = y },
        -- The /cp layout path applies our raw table without BuildLayout's
        -- default filling, so every interface field must be set here.
        size = size or 64,
        dir = dir,
        showFlyouts = true,
    }
end

local function CompactChildren()
    local lx, rx, y = RING_INSET, -RING_INSET, RING_Y
    return {
        PADDUP       = Handle(lx, y + D_OFF, 'UP', 'LEFT'),
        PADDDOWN     = Handle(lx, y - D_OFF, 'DOWN', 'LEFT'),
        PADDLEFT     = Handle(lx - D_OFF, y, 'LEFT', 'LEFT'),
        PADDRIGHT    = Handle(lx + D_OFF, y, 'RIGHT', 'LEFT'),
        PAD4         = Handle(rx, y + D_OFF, 'UP', 'RIGHT'),
        PAD1         = Handle(rx, y - D_OFF, 'DOWN', 'RIGHT'),
        PAD3         = Handle(rx - D_OFF, y, 'LEFT', 'RIGHT'),
        PAD2         = Handle(rx + D_OFF, y, 'RIGHT', 'RIGHT'),
        PADLSHOULDER = Handle(rx - SH_X, y + SH_UP, 'UP', 'RIGHT', SH_SIZE),
        PADRSHOULDER = Handle(rx + SH_X, y + SH_UP, 'UP', 'RIGHT', SH_SIZE),
        PADLTRIGGER  = Handle(rx - SH_X, y - SH_DOWN, 'DOWN', 'RIGHT', SH_SIZE),
        PADRTRIGGER  = Handle(rx + SH_X, y - SH_DOWN, 'DOWN', 'RIGHT', SH_SIZE),
    }
end

-- env.Layout is built (and env.Presets proxied) in ConsolePort_Bar's deferred
-- init, not at file load: ConsolePort_BarLayout existing is the ready signal.
function ns:CPEnvReady()
    return _G.ConsolePort ~= nil and type(_G.ConsolePort_BarLayout) == 'table'
end

-- Cluster:SetPoint anchors the main button (CPB_<ID>) to the cluster bar at
-- the handle's pos, so the live position of PAD4 tells whether our preset
-- is the active layout (release clears anchors -> GetPoint returns nil).
function ns:IsLayoutLive()
    local b = _G.CPB_PAD4
    if not b then return false end
    local _, _, rpt, x, y = b:GetPoint(1)
    return rpt == 'RIGHT' and x ~= nil
        and math.abs(x + RING_INSET) < 0.5 and math.abs(y - (RING_Y + D_OFF)) < 0.5
end

local function BaseLayout()
    local live = _G.ConsolePort_BarLayout
    if type(live.children) == 'table' then
        return CopyTable(live)
    end
    -- First-run fallback: env.Presets proxy reads builtins through the saved
    -- var's metatable, so .Default is reachable once env is up.
    local presets = _G.ConsolePort_BarPresets
    if presets and presets.Default then
        return CopyTable(presets.Default)
    end
    return {}
end

local DEFAULT_CLUSTER = {
    type = 'Cluster',
    pos = { point = 'BOTTOM', relPoint = 'BOTTOM', x = 0, y = 16 },
    width = 1200,
    height = 140,
    rescale = '90',
    visibility = '[vehicleui][overridebar] hide; show',
    opacity = '100',
    override = 'shown',
}

function ns:BuildPreset()
    local preset = BaseLayout()
    preset.name = PRESET_NAME
    preset.desc = 'Rings pinned to the screen edges (Nocturne: Gamepad).'
    preset.visibility = preset.visibility or '[petbattle] hide; show'
    preset.children = preset.children or {}
    local cluster = preset.children.Cluster
    if type(cluster) ~= 'table' then
        cluster = CopyTable(DEFAULT_CLUSTER)
        preset.children.Cluster = cluster
    end
    -- Bar units are scaled by rescale ('90' -> 0.9): widen the bar so its
    -- LEFT/RIGHT edges coincide with the screen edges.
    local scale = (tonumber(cluster.rescale) or 100) / 100
    cluster.width = math.floor(UIParent:GetWidth() / scale + 0.5)
    cluster.children = CompactChildren()
    return preset
end

function ns:RegisterPreset()
    if not ns:CPEnvReady() then return false end
    _G.ConsolePort_BarPresets = _G.ConsolePort_BarPresets or {}
    _G.ConsolePort_BarPresets[PRESET_KEY] = ns:BuildPreset()
    return true
end

function ns:ApplyLayout()
    if not ns:CPEnvReady() then return false end
    -- First apply only: keep the previous layout as a named preset so
    -- /ngp reset (or the CP loadout list) can restore it.
    local live = _G.ConsolePort_BarLayout
    local presets = _G.ConsolePort_BarPresets
    if ns.db and not ns.db.layoutApplied and type(live.children) == 'table'
        and live.name ~= PRESET_NAME
        and not (presets and rawget(presets, BACKUP_KEY)) then
        local backup = CopyTable(live)
        backup.name = BACKUP_NAME
        _G.ConsolePort_BarPresets[BACKUP_KEY] = backup
    end
    ns:RegisterPreset()
    ConsolePort('layout ' .. PRESET_KEY)
    if ns.db then
        ns.db.layoutApplied = true
        ns.db.layoutVersion = ns.LAYOUT_VERSION
    end
    return true
end

-- cluster.width is baked from UIParent's width at build time, so a
-- resolution or UI-scale change leaves the bar (and the edge-pinned rings)
-- sized for the old screen. Rebuild the preset, and re-apply it through
-- CP's own path when it's the live layout.
function ns:RefreshLayout()
    if not ns:CPEnvReady() then return false end
    local live = _G.ConsolePort_BarLayout
    local isLive = ns:IsLayoutLive()
        or (type(live) == 'table' and live.name == PRESET_NAME)
    if not (isLive or (ns.db and ns.db.compactLayout)) then return false end
    ns:RegisterPreset()
    if isLive then
        ConsolePort('layout ' .. PRESET_KEY)
    end
    return true
end

function ns:ResetLayout()
    if not ns:CPEnvReady() then return false end
    local presets = _G.ConsolePort_BarPresets
    local target = presets and rawget(presets, BACKUP_KEY) and BACKUP_KEY or 'Default'
    ConsolePort('layout ' .. target)
    return true
end
