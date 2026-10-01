local _, ns          = ...

-- ConsolePort applies named layouts through its own preset system:
-- ConsolePort_BarPresets is the user-preset saved var (proxied into
-- env.Presets), and ConsolePort('layout <name>') runs the same code path as
-- /cp layout — ReleaseAll + env('Layout', preset) + OnLayoutChanged, deferred
-- out of combat by CP's RunSafe.
local PRESET_KEY     = 'NocturneCompact'
local PRESET_NAME    = 'Nocturne Compact'
local BACKUP_KEY     = 'NocturneBackup'
local BACKUP_NAME    = 'Backup (pre-Nocturne)'

-- Geometry (cluster-bar units, offsets from the bar's CENTER). Stock look:
-- 64px buttons in a cross per ring, in-ring offsets +-65 horizontally and
-- +-42 vertically. RING_X puts the innermost buttons (PADDRIGHT and PAD3)
-- 2px apart: (RING_X - OFFX) - (-RING_X + OFFX) - 64 = 2.
local RING_X, RING_Y = 98, 42
local OFFX, OFFY     = 65, 42
local SH_X           = 80 -- shoulders/triggers: diagonal corners of the
local SH_UP          = 82 -- face ring (LB/RB up, LT/RT down)
local SH_DOWN        = 70
ns.PRESET_NAME       = PRESET_NAME
-- Bump when the geometry changes: Init re-applies the preset once.
ns.LAYOUT_VERSION    = 5

local function Handle(x, y, dir)
    return {
        type = 'ClusterHandle',
        pos = { point = 'CENTER', relPoint = 'CENTER', x = x, y = y },
        -- The /cp layout path applies our raw table without BuildLayout's
        -- default filling, so every interface field must be set here.
        size = 64,
        dir = dir,
        showFlyouts = true,
    }
end

local function Ring(cx, cy, up, down, left, right)
    return {
        [up]    = Handle(cx, cy + OFFY, 'UP'),
        [down]  = Handle(cx, cy - OFFY, 'DOWN'),
        [left]  = Handle(cx - OFFX, cy, 'LEFT'),
        [right] = Handle(cx + OFFX, cy, 'RIGHT'),
    }
end

local function CompactChildren()
    local children = Ring(-RING_X, RING_Y, 'PADDUP', 'PADDDOWN', 'PADDLEFT', 'PADDRIGHT')
    local face = Ring(RING_X, RING_Y, 'PAD4', 'PAD1', 'PAD3', 'PAD2')
    for id, handle in pairs(face) do
        children[id] = handle
    end
    children.PADLSHOULDER = Handle(RING_X - SH_X, RING_Y + SH_UP, 'UP')
    children.PADRSHOULDER = Handle(RING_X + SH_X, RING_Y + SH_UP, 'UP')
    children.PADLTRIGGER  = Handle(RING_X - SH_X, RING_Y - SH_DOWN, 'DOWN')
    children.PADRTRIGGER  = Handle(RING_X + SH_X, RING_Y - SH_DOWN, 'DOWN')
    return children
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
    local _, _, _, x, y = b:GetPoint(1)
    return x ~= nil and math.abs(x - RING_X) < 0.5 and math.abs(y - (RING_Y + OFFY)) < 0.5
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
    preset.desc = 'Compact rings: 2px between dpad and face buttons (Nocturne: Gamepad).'
    preset.visibility = preset.visibility or '[petbattle] hide; show'
    preset.children = preset.children or {}
    local cluster = preset.children.Cluster
    if type(cluster) ~= 'table' then
        cluster = CopyTable(DEFAULT_CLUSTER)
        preset.children.Cluster = cluster
    end
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

function ns:ResetLayout()
    if not ns:CPEnvReady() then return false end
    local presets = _G.ConsolePort_BarPresets
    local target = presets and rawget(presets, BACKUP_KEY) and BACKUP_KEY or 'Default'
    ConsolePort('layout ' .. target)
    return true
end
