local Nocturne = _G.Nocturne

-- First candidate atlas the client actually has (names change between
-- expansions); candidates may be nil.
function Nocturne.FirstAtlas(...)
    for i = 1, select("#", ...) do
        local name = select(i, ...)
        if name and C_Texture.GetAtlasInfo(name) then return name end
    end
end

-- Quest icons per classification: available/in progress ("!") and ready to
-- turn in ("?"). Candidates are tried in order since atlas names changed
-- across expansions. Blizzard's QuestUtil icon pickers are avoided on
-- purpose: they fill Blizzard's QuestCache, which would spread taint.
local QC = Enum.QuestClassification or {}
local QUEST_ICONS = {}
local function QuestIcons(class, offer, turnIn)
    if class then QUEST_ICONS[class] = { offer = offer, turnIn = turnIn } end
end
QuestIcons(QC.Campaign, { "Quest-Campaign-Available", "CampaignAvailableQuestIcon" },
    { "Quest-Campaign-TurnIn", "CampaignActiveQuestIcon" })
QuestIcons(QC.Important, { "Quest-Important-Available", "importantavailablequesticon" },
    { "Quest-Important-TurnIn", "importantactivequesticon" })
QuestIcons(QC.Legendary, { "Quest-Legendary-Available", "legendaryavailablequesticon" },
    { "Quest-Legendary-TurnIn", "legendaryactivequesticon" })
QuestIcons(QC.Calling, { "Quest-DailyCampaign-Available", "CampaignAvailableDailyQuestIcon" },
    { "Quest-DailyCampaign-TurnIn", "CampaignActiveDailyQuestIcon" })
QuestIcons(QC.Meta, { "Quest-Meta-Available" }, { "Quest-Meta-TurnIn" })
QuestIcons(QC.Recurring, { "Quest-Recurring-Available", "QuestDaily" },
    { "Quest-Recurring-TurnIn", "QuestRepeatableTurnin" })
local DAILY_ICONS = { offer = { "QuestDaily" }, turnIn = { "QuestRepeatableTurnin" } }
local NORMAL_ICONS = { offer = {}, turnIn = {} }
local WORLD_ICONS = { offer = { "worldquest-questicon-questionmark" }, turnIn = {} }

-- Atlas availability can't change within a session: resolve each
-- (icon set, state) once instead of probing GetAtlasInfo on every call.
local resolved = {}
local function Resolve(icons, turnIn)
    local r = resolved[icons]
    if not r then
        r = {}
        resolved[icons] = r
    end
    local key = turnIn and "turnIn" or "offer"
    local atlas = r[key]
    if atlas == nil then
        if turnIn then
            atlas = Nocturne.FirstAtlas(unpack(icons.turnIn)) or Nocturne.FirstAtlas("QuestTurnin", "QuestNormal")
        else
            atlas = Nocturne.FirstAtlas(unpack(icons.offer)) or Nocturne.FirstAtlas("QuestNormal")
        end
        r[key] = atlas or false
    end
    return atlas or nil
end

function Nocturne.QuestAtlas(classification, isComplete, isWorldQuest, isDaily)
    if isWorldQuest and not isComplete then return Resolve(WORLD_ICONS, false) end
    local icons = QUEST_ICONS[classification] or (isDaily and DAILY_ICONS) or NORMAL_ICONS
    return Resolve(icons, isComplete)
end
