local _, ns = ...

-- While the player is dead, the corpse is the destination: a single
-- super-tracked-style marker at C_DeathInfo's corpse pin.

local GetCorpseMapPosition = C_DeathInfo and C_DeathInfo.GetCorpseMapPosition
local UnitIsDeadOrGhost = UnitIsDeadOrGhost

local provider = { name = "corpse", glowInRegion = true }
ns.providers[#ns.providers + 1] = provider

provider.results = {}

-- CorpsePinTemplate (DeathMapDataProvider.xml): the tombstone crop of the
-- shared POI icon sheet, same art the world map uses for the corpse.
local CORPSE_TEXCOORDS = { 0.56640625, 0.6328125, 0.001953125, 0.03515625 }
local REZ_RANGE_YARDS = 40

function provider:Scan(playerMapID, playerInstance)
    local results = wipe(self.results)
    if not (playerMapID and playerInstance and GetCorpseMapPosition
            and UnitIsDeadOrGhost and UnitIsDeadOrGhost("player")) then
        return results
    end
    for _, mapID in ipairs(ns.CandidateMaps(playerMapID)) do
        local pos = GetCorpseMapPosition(mapID)
        if pos and not ns.IsSecret(pos.x) and not ns.IsSecret(pos.y) then
            local wx, wy = ns.MapToWorld(mapID, pos.x, pos.y, playerInstance)
            if wx then
                results[#results + 1] = {
                    key = "corpse",
                    provider = self,
                    title = CORPSE or "Corpse",
                    x = wx,
                    y = wy,
                    icon = "Interface\\Minimap\\POIIcons",
                    texCoords = CORPSE_TEXCOORDS,
                    isSuperTracked = true,
                }
            end
            return results
        end
    end
    return results
end

-- Close enough to click Resurrect: the banner lights up, same as quests.
function provider:IsInRegion(entry, dist)
    return dist <= REZ_RANGE_YARDS
end

ns.RescanOn({ "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST" }, true)
