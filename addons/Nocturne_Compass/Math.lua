local _, ns = ...

local M = ns.math
local PI2 = math.pi * 2

-- Normalize an angle to [-pi, pi].
function M.WrapAnglePi(a)
    if a > math.pi then return a - PI2 end
    if a < -math.pi then return a + PI2 end
    return a
end

-- Straight-line distance for a world-space delta (yards).
function M.Distance(dx, dy)
    return math.sqrt(dx * dx + dy * dy)
end

-- Conventions verified live against the Blizzard nav arrow (see AGENTS.md):
--   world deltas: +x = north, +y = west (90°-rotated vs map orientation)
--   GetPlayerFacing(): radians CCW from north (0 = N, turning left increases)

-- Direction the player faces, expressed as a CW compass bearing.
function ns.FacingCW()
    local f = ns.player.facing
    return f and (PI2 - f) % PI2 or nil
end

-- Signed angle of a world direction relative to heading: >0 = to the right.
function ns.RelAngle(dx, dy)
    -- east = -dy, north = dx -> bearing = atan2(east, north)
    local bearing = math.atan2(-dy, dx) % PI2
    return M.WrapAnglePi(bearing - ns.FacingCW())
end

function M.Clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

function M.Lerp(a, b, t)
    return a + (b - a) * t
end
