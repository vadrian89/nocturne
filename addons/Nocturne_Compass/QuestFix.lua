local _, ns = ...

-- Position fix where the client hands out no player position (instances):
-- C_QuestLog.GetDistanceSqToQuest keeps answering there with the 2D yards²
-- to the quest's pin, so three or more quests with pins on the map locate
-- the player by trilateration. Proven on Ragefire Chasm (map 213): two
-- /ncmp diag samples both solve to a 739.5 x 493 yd map with no residual.
-- Facing stays unreadable, so the heading is the course over ground: it
-- follows the direction of travel and holds while standing still.

local M = ns.math
local PI2 = math.pi * 2
local sqrt, abs, atan2 = math.sqrt, math.abs, math.atan2
local GetTime = GetTime
local GetQuestsOnMap = C_QuestLog.GetQuestsOnMap
local GetDistanceSqToQuest = C_QuestLog.GetDistanceSqToQuest
local GetWorldPosFromMapPos = C_Map.GetWorldPosFromMapPos

local ANCHOR_TTL = 2      -- seconds between pin list refreshes
local MIN_SPREAD = 0.01   -- below this the pins are (nearly) in one line
local TOLERANCE = 3       -- yards a pin distance may disagree with the fix
local COURSE_MIN = 2      -- yards travelled before the course is re-read
local COURSE_MAX = 40     -- a longer step is a teleport, not a course
local EASE = 0.25         -- share of the remaining turn taken per update

-- Map extent in yards, read off its corners (world +x = north, +y = west).
local sizes = {}
local function MapSize(mapID)
    local s = sizes[mapID]
    if not s then
        local i1, tl = GetWorldPosFromMapPos(mapID, CreateVector2D(0, 0))
        local i2, br = GetWorldPosFromMapPos(mapID, CreateVector2D(1, 1))
        if not (i1 and i1 == i2 and tl and br) then return nil end
        if ns.IsSecret(tl.x) or ns.IsSecret(br.x) then return nil end
        local w, h = abs(tl.y - br.y), abs(tl.x - br.x)
        if w == 0 or h == 0 then return nil end
        s = { w, h }
        sizes[mapID] = s
    end
    return s[1], s[2]
end

-- Pins in map yards (x east, y south), parallel arrays reused across updates.
local qids, pinX, pinY, distSq = {}, {}, {}, {}
local count, mapW, mapH = 0, nil, nil
local anchorMap, anchorsAt = nil, 0
local why
local vec

local function RebuildAnchors(mapID)
    count = 0
    mapW, mapH = MapSize(mapID)
    if not mapW then return end
    for _, q in ipairs(GetQuestsOnMap(mapID) or {}) do
        local x, y = q.x, q.y
        if q.questID and not q.isQuestStart and x and y and not ns.IsSecret(x) and not ns.IsSecret(y) then
            count = count + 1
            qids[count], pinX[count], pinY[count] = q.questID, x * mapW, y * mapH
        end
    end
end

-- The player's position on `mapID` as a (reused) Vector2D, or nil.
function ns.QuestFix(mapID)
    local now = GetTime()
    if mapID ~= anchorMap or now - anchorsAt >= ANCHOR_TTL then
        anchorMap, anchorsAt = mapID, now
        RebuildAnchors(mapID)
    end

    local first, used = nil, 0
    for i = 1, count do
        local d, onContinent = GetDistanceSqToQuest(qids[i])
        if d and onContinent and not ns.IsSecret(d) then
            distSq[i] = d
            first = first or i
            used = used + 1
        else
            distSq[i] = false
        end
    end
    if used < 3 then
        why = "anchors<3"
        return nil
    end

    -- Each circle minus the first one is a line; least squares over those.
    local x1, y1, d1 = pinX[first], pinY[first], distSq[first]
    local k1 = x1 * x1 + y1 * y1
    local saa, sab, sbb, sac, sbc = 0, 0, 0, 0, 0
    for i = first + 1, count do
        local d = distSq[i]
        if d then
            local xi, yi = pinX[i], pinY[i]
            local a, b = 2 * (xi - x1), 2 * (yi - y1)
            local c = d1 - d + xi * xi + yi * yi - k1
            saa, sab, sbb = saa + a * a, sab + a * b, sbb + b * b
            sac, sbc = sac + a * c, sbc + b * c
        end
    end
    local det = saa * sbb - sab * sab
    if det <= MIN_SPREAD * saa * sbb then
        why = "collinear"
        return nil
    end
    local x = (sac * sbb - sab * sbc) / det
    local y = (saa * sbc - sab * sac) / det

    -- A pin that moved since the last refresh (or a distance measured to
    -- something else) shows up as a circle the fix doesn't sit on.
    for i = first, count do
        local d = distSq[i]
        if d then
            local dx, dy = x - pinX[i], y - pinY[i]
            if abs(sqrt(dx * dx + dy * dy) - sqrt(d)) > TOLERANCE then
                why = "residual"
                return nil
            end
        end
    end

    why = nil
    vec = vec or CreateVector2D(0, 0)
    vec:SetXY(x / mapW, y / mapH)
    return vec
end

local refX, refY, refInst, course, heading

-- Heading (radians CCW from north, like GetPlayerFacing) from successive
-- world positions; nil until the player has travelled COURSE_MIN yards.
function ns.FixHeading(x, y, instance)
    if instance ~= refInst then
        refX, refY, refInst, course, heading = x, y, instance, nil, nil
        return nil
    end
    local dx, dy = x - refX, y - refY
    local d2 = dx * dx + dy * dy
    if d2 > COURSE_MAX * COURSE_MAX then
        refX, refY, course, heading = x, y, nil, nil
    elseif d2 >= COURSE_MIN * COURSE_MIN then
        course = atan2(dy, dx) % PI2
        refX, refY = x, y
    end
    if course then
        heading = heading and (heading + M.WrapAnglePi(course - heading) * EASE) % PI2 or course
    end
    return heading
end

function ns.QuestFixDiag(mapID, lines)
    if not mapID then return end
    local function S(v) return ns.IsSecret(v) and "<secret>" or tostring(v) end
    local pos = ns.QuestFix(mapID)
    lines[#lines + 1] = ("questFix active=%s size=%s x %s anchors=%d fix=%s,%s why=%s course=%s heading=%s"):format(
        tostring(ns.player.fixed), tostring(mapW), tostring(mapH), count,
        tostring(pos and pos.x), tostring(pos and pos.y), tostring(why),
        tostring(course and math.deg(course)), tostring(heading and math.deg(heading)))
    for i = 1, count do
        local d, onContinent = GetDistanceSqToQuest(qids[i])
        lines[#lines + 1] = ("  anchor quest=%s pin=%.1f,%.1f distSq=%s onContinent=%s"):format(
            S(qids[i]), pinX[i], pinY[i], S(d), S(onContinent))
    end
end
