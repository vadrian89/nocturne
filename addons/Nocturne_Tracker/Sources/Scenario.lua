local _, ns = ...

-- Active scenario (scenarios, delves, dungeons with a scenario step,
-- Mythic+): current step and its criteria; Mythic+ adds a live timer and
-- the death count.

local C = ns.colors
local SI = C_ScenarioInfo
local CM = C_ChallengeMode
local GetWorldElapsedTime = GetWorldElapsedTime
local GetWorldElapsedTimers = GetWorldElapsedTimers
local CM_TIMER = _G.LE_WORLD_ELAPSED_TIMER_TYPE_CHALLENGE_MODE or 1

local function Secret(v) return ns.IsSecret(v) end

local function FormatTime(s)
    s = math.max(0, math.floor(s))
    return ("%d:%02d"):format(math.floor(s / 60), s % 60)
end

local function ChallengeElapsed(...)
    for i = 1, select("#", ...) do
        local _, elapsed, kind = GetWorldElapsedTime((select(i, ...)))
        if kind == CM_TIMER and not Secret(elapsed) then return elapsed end
    end
end

local function IsChallengeActive()
    return CM and CM.IsChallengeModeActive and CM.IsChallengeModeActive()
end

local function ChallengeTimerText()
    if not (GetWorldElapsedTimers and GetWorldElapsedTime) then return end
    local elapsed = ChallengeElapsed(GetWorldElapsedTimers())
    if not elapsed then return end
    local mapID = CM.GetActiveChallengeMapID and CM.GetActiveChallengeMapID()
    local limit
    if mapID and CM.GetMapUIInfo then
        local _, _, timeLimit = CM.GetMapUIInfo(mapID)
        if timeLimit and not Secret(timeLimit) then limit = timeLimit end
    end
    if limit then
        return ("%s / %s"):format(FormatTime(elapsed), FormatTime(limit))
    end
    return FormatTime(elapsed)
end

-- The timer line is refreshed in place once a second; the rest of the
-- list only changes on events.
local ticker
local function Tick()
    local fs = ns.timerFS
    if not (fs and fs:IsVisible()) then return end
    local text = ChallengeTimerText()
    if text then fs:SetText(text) end
end

local function SetTicking(on)
    if on and not ticker then
        ticker = C_Timer.NewTicker(1, Tick)
    elseif not on and ticker then
        ticker:Cancel()
        ticker = nil
    end
end

-- Blizzard's format: "3/8 Description" unless the criteria is weighted
-- (enemy forces: percentage) or its description is preformatted.
local function CriteriaText(c)
    local desc = c.description
    if not desc or Secret(desc) or desc == "" then return nil end
    if ns.Flag(c.isWeightedProgress) then
        local q = c.quantityString
        if q and not Secret(q) and q ~= "" then return ("%s %s"):format(desc, q) end
        return desc
    end
    if ns.Flag(c.isFormatted) then return desc end
    local have, need = c.quantity, c.totalQuantity
    if have and need and not Secret(have) and not Secret(need) and need > 0 then
        return ("%d/%d %s"):format(have, need, desc)
    end
    return desc
end

local src = { name = "scenario" }
ns.sources[#ns.sources + 1] = src

function src:Collect(db)
    local inScenario = db.showScenario and SI and SI.GetScenarioInfo
        and C_Scenario and C_Scenario.IsInScenario and C_Scenario.IsInScenario()
    if not inScenario then
        SetTicking(false)
        return
    end
    local info = SI.GetScenarioInfo()
    if not info or not info.name or Secret(info.name) then
        SetTicking(false)
        return
    end
    local step = SI.GetScenarioStepInfo and SI.GetScenarioStepInfo()
    local challenge = IsChallengeActive()

    local header = info.name
    if challenge and CM.GetActiveKeystoneInfo then
        local level = CM.GetActiveKeystoneInfo()
        if level and not Secret(level) and level > 0 then
            header = ("%s +%d"):format(info.name, level)
        end
    end
    local s = ns.NewSection(header)
    local e = ns.AddEntry(s)
    e.kind = "scenario"
    local title = step and step.title
    e.title = (title and not Secret(title) and title ~= "") and title or info.name
    e.titleColor = ns.Flag(info.isComplete) and C.done or C.title

    local stage, stages = info.currentStage, info.numStages
    if stage and stages and not Secret(stage) and not Secret(stages) and stages > 1 then
        ns.AddLine(e, ("Stage %d/%d"):format(stage, stages), C.lineDone)
    end

    if challenge then
        local text = ChallengeTimerText()
        if text then e.timerLine = ns.AddLine(e, text, C.line) end
        if CM.GetDeathCount then
            local deaths, lost = CM.GetDeathCount()
            if deaths and not Secret(deaths) and deaths > 0 then
                if lost and not Secret(lost) then
                    ns.AddLine(e, ("Deaths: %d (-%s)"):format(deaths, FormatTime(lost)), C.line)
                else
                    ns.AddLine(e, ("Deaths: %d"):format(deaths), C.line)
                end
            end
        end
    end
    SetTicking(e.timerLine ~= nil)

    local num = step and step.numCriteria
    if num and not Secret(num) and SI.GetCriteriaInfo then
        for i = 1, num do
            local c = SI.GetCriteriaInfo(i)
            local text = c and CriteriaText(c)
            if text then
                ns.AddLine(e, text, ns.Flag(c.completed) and C.lineDone or C.line)
            end
        end
    end
end

ns.RebuildOn({
    "SCENARIO_UPDATE",
    "SCENARIO_CRITERIA_UPDATE",
    "SCENARIO_COMPLETED",
    "CHALLENGE_MODE_START",
    "CHALLENGE_MODE_COMPLETED",
    "CHALLENGE_MODE_RESET",
    "CHALLENGE_MODE_DEATH_COUNT_UPDATED",
    "WORLD_STATE_TIMER_START",
    "WORLD_STATE_TIMER_STOP",
})
