local _, ns = ...

local Nocturne = _G.Nocturne
local T = Nocturne.Theme

local MARGIN = ns.JournalMargin

local NODE = 69
-- Spec tab row placed like Inventory's: 16px from the top, columns from
-- MARGIN + 44 (16px under the 36px row).
local TABROW_Y = 16
local TOPPAD = MARGIN + 44
local BOTTOMPAD = 34
local HEADPAD = 8
local HEADICON = 48
local COLHEAD = HEADICON + HEADPAD * 3
-- Spec art is opaque (the shell's race scene must not show through) and
-- dimmed by vertex color instead.
local ART_SHADE = 0.75
-- Horizontal crop anchor for whole retail pictures: 0 left, 1 right.
local ART_ALIGN_X = 1
local COLPAD = 8
local GAP = ns.JournalGap
local EMPTY = {}

local SUBTREE_SEL = Enum and Enum.TraitNodeType
    and Enum.TraitNodeType.SubTreeSelection or 3

local STATE_COLOR = {
    full      = { 0.80, 0.68, 0.42, 1 },
    partial   = { 0.92, 0.82, 0.52, 1 },
    available = { 0.60, 0.62, 0.70, 1 },
    locked    = { 0.20, 0.20, 0.25, 1 },
}
local EDGE_ACTIVE = { 0.80, 0.68, 0.42, 0.95 }
local EDGE_DIM = { 0.50, 0.50, 0.58, 0.85 }

local RANK_GREEN = { 0.35, 0.90, 0.35, 1 }
local RANK_WHITE = { 1, 1, 1, 1 }
local RANK_GRAY = { 0.62, 0.62, 0.68, 1 }

local Flag = ns.Flag

-- Forward declarations: the spec-switch timer and page callbacks call
-- these before their definitions appear below.
local RenderAll, Reload, Dirty

local SI = C_SpecializationInfo

-- Forever's dual spec (Camelot ClassTalentsFrame): talent groups 1/2 are
-- tabs, each with its own combat config (GetCombatConfigIDForSpecGroup,
-- nil until the group is first activated); group 2 unlocks when
-- GetNumSpecGroups() > 1 (level 40).
local function HasSpecTabs()
    return Nocturne.IS_FOREVER and SI
        and SI.GetCombatConfigIDForSpecGroup ~= nil or false
end

local function ActiveSpecGroup()
    if SI and SI.GetActiveSpecGroup then
        local ok, g = pcall(SI.GetActiveSpecGroup)
        if ok and type(g) == "number" and g >= 1 then return g end
    end
    return 1
end

-- No API reports the unlock level (Forever's TALENT_SPEC_LOCKED is just
-- "Locked"); group 2 unlocks at 40 per the user's Forever client.
local DUAL_SPEC_LEVEL = 40

local GROUP_NAMES = { "Primary", "Secondary" }
local function GroupName(g)
    return GROUP_NAMES[g] or ("Spec " .. g)
end

local function SpecGroupUnlocked(g)
    if g == 1 then return true end
    if not GetNumSpecGroups then return false end
    local ok, n = pcall(GetNumSpecGroups)
    return ok and type(n) == "number" and n >= g
end

local function LockedText()
    local lvl = UnitLevel("player") or 0
    if lvl >= DUAL_SPEC_LEVEL then
        return type(TALENT_SPEC_LOCKED) == "string" and TALENT_SPEC_LOCKED
            or "Locked"
    end
    local fmt = FEATURE_BECOMES_AVAILABLE_AT_LEVEL
    local ok, txt = false, nil
    if type(fmt) == "string" and fmt:find("%d", 1, true) then
        ok, txt = pcall(string.format, fmt, DUAL_SPEC_LEVEL)
    end
    if not ok then
        txt = ("Unlocks at level %d"):format(DUAL_SPEC_LEVEL)
    end
    return ("%s\n(level %d now)"):format(txt, lvl)
end

local function CanActivate(g)
    return g ~= nil and g ~= ActiveSpecGroup() and SpecGroupUnlocked(g)
end

-- Purchases/refunds/resets only apply to the active spec's config; the
-- inactive tab (Forever dual spec) is view-only.
local function IsActiveView()
    return not HasSpecTabs() or ns.talView == ActiveSpecGroup()
end

-- group: the dual-spec tab to read (Forever); nil = the active config.
local function LoadConfig(group)
    if not (C_Traits and C_Traits.GetConfigInfo) then return end
    local ok, cfg
    if group then
        ok, cfg = pcall(SI.GetCombatConfigIDForSpecGroup, group)
    elseif C_ClassTalents and C_ClassTalents.GetActiveConfigID then
        ok, cfg = pcall(C_ClassTalents.GetActiveConfigID)
    end
    if not (ok and cfg) or ns.IsSecret(cfg) then return end
    local ok2, info = pcall(C_Traits.GetConfigInfo, cfg)
    if not (ok2 and info and info.treeIDs) then return end
    for _, tid in ipairs(info.treeIDs) do
        if not ns.IsSecret(tid) then return cfg, tid end
    end
end

local function NodeState(n)
    if n.rank >= n.maxRank then return "full" end
    if n.rank > 0 then return "partial" end
    return n.avail and "available" or "locked"
end

local function BuildNodes(cfg, tid)
    local nodes = {}
    if not (C_Traits.GetTreeNodes and C_Traits.GetNodeInfo) then
        return nodes
    end
    local ok, ids = pcall(C_Traits.GetTreeNodes, tid)
    if not (ok and ids) then return nodes end
    for _, nid in ipairs(ids) do
        local ok2, ni = pcall(C_Traits.GetNodeInfo, cfg, nid)
        if ok2 and ni and Flag(ni.isVisible)
            and ni.type ~= SUBTREE_SEL
            and not (ni.subTreeID and not ns.IsSecret(ni.subTreeActive)
                and ni.subTreeActive == false)
            and type(ni.posX) == "number" and type(ni.posY) == "number"
            and not ns.IsSecret(ni.posX) and not ns.IsSecret(ni.posY) then
            local n = {
                id = nid,
                px = ni.posX,
                py = ni.posY,
                groups = ni.groupIDs,
                subTreeID = ni.subTreeID,
                rank = ni.ranksPurchased or 0,
                eff = ni.currentRank or 0,
                maxRank = ni.maxRanks or 1,
                avail = Flag(ni.isAvailable)
                    and (ns.IsSecret(ni.meetsEdgeRequirements)
                        or ni.meetsEdgeRequirements ~= false),
                edges = ni.visibleEdges or ni.edges,
                conds = ni.conditionIDs,
            }
            n.state = NodeState(n)
            n.entryID = ni.activeEntry and ni.activeEntry.entryID
                or (ni.entryIDs and ni.entryIDs[1])
            local inc = ni.ranksIncreased or 0
            if ni.activeEntry then
                n.curRank = (ni.activeEntry.rank or 0) + inc
            end
            if ni.nextEntry then
                n.nextEntryID = ni.nextEntry.entryID
                n.nextRank = (ni.nextEntry.rank or 1) + inc
            end
            if n.entryID and C_Traits.GetEntryInfo
                and C_Traits.GetDefinitionInfo then
                local ok3, ei = pcall(C_Traits.GetEntryInfo, cfg, n.entryID)
                local did = ok3 and ei and ei.definitionID
                if did and not ns.IsSecret(did) then
                    local ok4, di = pcall(C_Traits.GetDefinitionInfo, did)
                    if ok4 and di then
                        n.spellID = di.spellID
                        n.icon = di.overrideIcon
                        n.name = di.overrideName
                        n.desc = di.overrideDescription
                        n.subtext = di.overrideSubtext
                    end
                end
            end
            if not n.name and n.spellID
                and C_Spell and C_Spell.GetSpellInfo then
                local si = C_Spell.GetSpellInfo(n.spellID)
                if si then
                    n.name = n.name or si.name
                    n.icon = n.icon or si.iconID
                end
            end
            -- Tooltip line 1 is the trait name even when the definition
            -- carries no name override (Forever's entries mostly don't).
            if not n.name and C_TooltipInfo and C_TooltipInfo.GetTraitEntry
                and n.entryID then
                local ok5, td = pcall(C_TooltipInfo.GetTraitEntry,
                    n.entryID, 1)
                local lt = ok5 and td and td.lines and td.lines[1]
                    and td.lines[1].leftText
                if lt and not ns.IsSecret(lt) then n.name = lt end
            end
            nodes[#nodes + 1] = n
        end
    end
    -- Edges hang off their source node; the tooltip needs them per target.
    local byID = {}
    for _, n in ipairs(nodes) do byID[n.id] = n end
    for _, n in ipairs(nodes) do
        for _, e in ipairs(n.edges or EMPTY) do
            local t = byID[e.targetNode or e.targetID or e.target]
            if t then
                t.incoming = t.incoming or {}
                t.incoming[#t.incoming + 1] = {
                    src = n, active = Flag(e.isActive), type = e.type,
                }
            end
        end
    end
    return nodes
end

local function BucketInto(secs, nodes)
    local placed = {}
    for _, n in ipairs(nodes) do
        for _, s in ipairs(secs) do
            if s.gid then
                for _, g in ipairs(n.groups or EMPTY) do
                    if g == s.gid then
                        s.nodes[#s.nodes + 1] = n
                        n.sec = s
                        placed[n] = true
                        break
                    end
                end
            end
            if placed[n] then break end
        end
    end
    return placed
end

-- Sections: Forever exposes the classic tabs through
-- GetGroupDisplayInfoByTreeID; elsewhere split by the node's currency
-- (class vs spec points) or fall back to one flat section.
local function SectionsFor(cfg, tid, nodes)
    local secs = {}
    if C_Traits.GetGroupDisplayInfoByTreeID then
        local ok, gd = pcall(C_Traits.GetGroupDisplayInfoByTreeID, tid)
        if ok and type(gd) == "table" then
            for _, g in pairs(gd) do
                if type(g) == "table" and g.groupID then
                    secs[#secs + 1] = {
                        key = "g" .. tostring(g.groupID),
                        title = g.displayName or "Talents",
                        icon = g.icon,
                        gid = g.groupID,
                        skill = g.skillLineID,
                        order = g.orderIndex or 0,
                        nodes = {},
                    }
                end
            end
            table.sort(secs, function(a, b) return a.order < b.order end)
        end
    end
    if #secs > 0 then
        local placed = BucketInto(secs, nodes)
        local rest = {}
        for _, n in ipairs(nodes) do
            if not placed[n] then rest[#rest + 1] = n end
        end
        if #rest > 0 then
            secs[#secs + 1] = {
                key = "rest", title = "Other", nodes = rest,
            }
        end
        return secs
    end
    if C_Traits.GetTreeCurrencyInfo and C_Traits.GetNodeCost then
        local ok, curs = pcall(C_Traits.GetTreeCurrencyInfo, cfg, tid, true)
        if ok and curs and #curs > 1 then
            local NAMES = { "Class", "Spec", "Hero" }
            local byCur = {}
            for i, c in ipairs(curs) do
                local icon
                if C_Traits.GetTraitCurrencyInfo then
                    local _, _, _, ic = pcall(
                        C_Traits.GetTraitCurrencyInfo, c.traitCurrencyID)
                    if type(ic) == "number" or type(ic) == "string" then
                        icon = ic
                    end
                end
                local s = {
                    key = "c" .. tostring(c.traitCurrencyID),
                    cid = c.traitCurrencyID,
                    title = NAMES[i] or ("Tree " .. i),
                    icon = icon,
                    order = i,
                    nodes = {},
                }
                secs[#secs + 1] = s
                byCur[c.traitCurrencyID] = s
            end
            local rest = {}
            for _, n in ipairs(nodes) do
                local ok2, cost = pcall(C_Traits.GetNodeCost, cfg, n.id)
                local s = ok2 and cost and cost[1]
                    and byCur[cost[1].ID]
                if s then
                    s.nodes[#s.nodes + 1] = n
                    n.sec = s
                else
                    rest[#rest + 1] = n
                end
            end
            for _, n in ipairs(rest) do
                local s = secs[1]
                s.nodes[#s.nodes + 1] = n
                n.sec = s
            end
            return secs
        end
    end
    secs[1] = { key = "all", title = "Talents", nodes = nodes }
    return secs
end

function ns:TalentsEnsureData()
    if ns.talData then return ns.talData end
    local data = { secs = {} }
    ns.talData = data
    local view = ns.talView
    local cfg, tid = LoadConfig(view)
    data.cfg = cfg
    if not cfg then
        if view and not SpecGroupUnlocked(view) then
            data.err = LockedText()
        elseif view then
            data.err = GroupName(view) .. " hasn't been activated yet"
        else
            data.err = "no trait config"
        end
        return data
    end
    data.configID, data.treeID = cfg, tid
    -- Staged-commit model: retail C_Traits buffers rank changes until
    -- CommitConfig. GetStagedChangesCost lists the pending changes —
    -- a non-empty cost table is the real "Apply needed" signal.
    -- (IsReadyForCommit answers true even with nothing staged on
    -- Forever, so it is only a fallback.)
    if C_Traits.GetStagedChangesCost then
        local okr, cost = pcall(C_Traits.GetStagedChangesCost, cfg)
        data.staged = okr and type(cost) == "table" and #cost > 0
    elseif C_Traits.IsReadyForCommit then
        local okr, rdy = pcall(C_Traits.IsReadyForCommit, cfg)
        data.staged = okr and rdy == true
    end
    if C_Traits.GetTreeCurrencyInfo then
        local okc, curs = pcall(C_Traits.GetTreeCurrencyInfo, cfg, tid, true)
        if okc and curs then
            local pts = 0
            for _, c in ipairs(curs) do
                if type(c) == "table" and not ns.IsSecret(c.quantity) then
                    pts = pts + (c.quantity or 0)
                end
            end
            data.points = pts
        end
    end
    local nodes = BuildNodes(cfg, tid)
    data.secs = SectionsFor(cfg, tid, nodes)
    data.nodeCount = #nodes
    return data
end

local function NewNode(ui)
    local b = CreateFrame("Button", nil, ui.canvas)
    b:SetSize(NODE, NODE)
    b:RegisterForClicks("LeftButtonUp")
    b.edge = b:CreateTexture(nil, "BACKGROUND")
    b.edge:SetAllPoints()
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("CENTER")
    b.icon:SetSize(NODE - 6, NODE - 6)
    b.icon:SetTexCoord(0.0625, 0.9375, 0.0625, 0.9375)
    b.rankBg = b:CreateTexture(nil, "OVERLAY")
    b.rankBg:SetColorTexture(0.04, 0.04, 0.07, 0.85)
    b.rank = T.CreateFontString(b, 13, { 1, 1, 1, 1 })
    b.rank:SetDrawLayer("OVERLAY")
    b.rank:SetPoint("BOTTOMRIGHT", -2, 2)
    b.rankBg:SetPoint("TOPLEFT", b.rank, "TOPLEFT", -4, 2)
    b.rankBg:SetPoint("BOTTOMRIGHT", b.rank, "BOTTOMRIGHT", 2, -2)
    b.sel = b:CreateTexture(nil, "OVERLAY")
    local a = T.colors.accent
    b.sel:SetColorTexture(a[1], a[2], a[3], 0.45)
    b.sel:SetPoint("TOPLEFT", -2, 2)
    b.sel:SetPoint("BOTTOMRIGHT", 2, -2)
    b.sel:Hide()
    b:SetScript("OnEnter", function(self)
        if self.node then
            ui.sel = self.node
            ns:TalentsPaint()
        end
    end)
    b:SetScript("OnClick", function()
        if b.node then
            ui.sel = b.node
            ns:TalentsPaint()
        end
    end)
    return b
end

-- Dependency arrows, built from straight segments: a Line object where the
-- client has CreateLine, else a rotated texture. Art is Blizzard's talent
-- arrow (TalentEdgeArrowTemplate: 6px line, head atlas at atlas size,
-- head drawn pointing down at rotation 0), scaled up with our larger
-- nodes; flat color strokes if missing.
local EDGE_THICK = 4
local ART_SCALE = 1.7
local ART_THICK = 6 * ART_SCALE
local HEAD_LEN = 12
local HEAD_ANG = math.rad(32)
local ARROW_ART = {}

local function ArrowArt(active)
    local kind = active and "yellow" or "gray"
    local art = ARROW_ART[kind]
    if art == nil then
        local line = Nocturne.FirstAtlas("talents-arrow-line-" .. kind)
        local head = Nocturne.FirstAtlas("talents-arrow-head-" .. kind)
        art = line and head and { line = line, head = head } or false
        ARROW_ART[kind] = art
    end
    return art or nil
end

local function Segment(ui, li, x1, y1, x2, y2, c, atlas)
    local l = ui.lines[li]
    if not l then
        if ui.canvas.CreateLine then
            l = ui.canvas:CreateLine(nil, "ARTWORK")
            l.isLine = true
        else
            l = ui.canvas:CreateTexture(nil, "ARTWORK")
        end
        ui.lines[li] = l
    end
    local thick = atlas and ART_THICK or EDGE_THICK
    if atlas then
        l:SetAtlas(atlas, false)
        l:SetVertexColor(1, 1, 1, 1)
    else
        l:SetColorTexture(c[1], c[2], c[3], c[4])
    end
    if l.isLine then
        l:SetThickness(thick)
        l:SetStartPoint("TOPLEFT", ui.canvas, x1, -y1)
        l:SetEndPoint("TOPLEFT", ui.canvas, x2, -y2)
    else
        local dx, dy = x2 - x1, y2 - y1
        l:ClearAllPoints()
        l:SetPoint("CENTER", ui.canvas, "TOPLEFT",
            x1 + dx / 2, -(y1 + dy / 2))
        l:SetSize(math.max(1, math.sqrt(dx * dx + dy * dy)), thick)
        l:SetRotation(math.atan2(-dy, dx))
    end
    l:Show()
end

-- Shaft plus head whose tip touches the target's border.
-- Canvas coordinates: x right, y down.
local function Arrow(ui, li, x1, y1, x2, y2, c, art)
    local dx, dy = x2 - x1, y2 - y1
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 1 then return li end
    local ux, uy = dx / len, dy / len
    if art then
        ui.hi = ui.hi + 1
        local h = ui.heads[ui.hi]
        if not h then
            h = ui.canvas:CreateTexture(nil, "OVERLAY")
            ui.heads[ui.hi] = h
        end
        h:SetAtlas(art.head, true)
        h:SetSize(h:GetWidth() * ART_SCALE, h:GetHeight() * ART_SCALE)
        local half = h:GetHeight() / 2
        local cx, cy = x2 - ux * half, y2 - uy * half
        h:ClearAllPoints()
        h:SetPoint("CENTER", ui.canvas, "TOPLEFT", cx, -cy)
        h:SetRotation(math.atan2(uy, -ux) - math.pi / 2)
        h:Show()
        Segment(ui, li + 1, x1, y1, cx, cy, c, art.line)
        return li + 1
    end
    Segment(ui, li + 1, x1, y1, x2 - ux * 2, y2 - uy * 2, c)
    local cs, sn = math.cos(HEAD_ANG), math.sin(HEAD_ANG)
    for i, s in ipairs({ sn, -sn }) do
        local bx, by = ux * cs - uy * s, ux * s + uy * cs
        Segment(ui, li + 1 + i, x2, y2,
            x2 - bx * HEAD_LEN, y2 - by * HEAD_LEN, c)
    end
    return li + 3
end

-- Like the classic talent frame: a straight arrow when source and target
-- share a row or column, otherwise across the source's row to the
-- target's column, then into the target. Returns the last segment index.
local function ShowEdge(ui, li, n, t, c, active)
    local art = ArrowArt(active)
    local h = NODE / 2 + 3
    local dx, dy = t.x - n.x, t.y - n.y
    local tol = NODE * 0.25
    if math.abs(dx) < tol or math.abs(dy) < tol then
        local len = math.sqrt(dx * dx + dy * dy)
        if len <= h * 2 then return li end
        local ux, uy = dx / len, dy / len
        local r = h / math.max(math.abs(ux), math.abs(uy))
        return Arrow(ui, li, n.x + ux * r, n.y + uy * r,
            t.x - ux * r, t.y - uy * r, c, art)
    end
    local sx = dx > 0 and 1 or -1
    local sy = dy > 0 and 1 or -1
    local thick = art and ART_THICK or EDGE_THICK
    li = li + 1
    Segment(ui, li, n.x + sx * h, n.y, t.x + sx * thick / 2, n.y, c,
        art and art.line)
    return Arrow(ui, li, t.x, n.y, t.x, t.y - sy * h, c, art)
end

local RANK_FMT = TALENT_BUTTON_TOOLTIP_RANK_FORMAT or "Rank %s/%s"
local NEXT_RANK = TALENT_BUTTON_TOOLTIP_NEXT_RANK or "Next Rank:"

local function RGB(c, r, g, b)
    if c and c.GetRGB then return c:GetRGB() end
    return r, g, b
end

-- One GetTraitEntry rank, both columns (cost/range/cast sit on the right).
-- Returns the left texts joined, for the description check and diag.
local function AddEntryLines(entryID, rank, skip)
    if not (entryID and C_TooltipInfo and C_TooltipInfo.GetTraitEntry) then
        return ""
    end
    local ok, td = pcall(C_TooltipInfo.GetTraitEntry, entryID, rank)
    if not (ok and td and td.lines) then return "" end
    local seen = {}
    for _, ln in ipairs(td.lines) do
        if not ln.leftText and ln.args and TooltipUtil
            and TooltipUtil.SurfaceArgs then
            pcall(TooltipUtil.SurfaceArgs, ln)
        end
        local l, r = ln.leftText, ln.rightText
        if l and ns.IsSecret(l) then l = nil end
        if r and (ns.IsSecret(r) or r == "") then r = nil end
        if l and l ~= skip then
            local lr, lg, lb = RGB(ln.leftColor, 1, 0.82, 0)
            if r then
                local rr, rg, rb = RGB(ln.rightColor, 1, 1, 1)
                GameTooltip:AddDoubleLine(l, r, lr, lg, lb, rr, rg, rb)
            else
                GameTooltip:AddLine(l, lr, lg, lb, true)
            end
            seen[#seen + 1] = r and (l .. " || " .. r) or l
        end
    end
    return table.concat(seen, " / ")
end

local function TalentDesc(n)
    local d = n.desc
    if not d and n.spellID and C_Spell and C_Spell.GetSpellDescription then
        local ok, t = pcall(C_Spell.GetSpellDescription, n.spellID)
        if ok then d = t end
    end
    if d and not ns.IsSecret(d) and d ~= "" then return d end
    return nil
end

local RANKS_ALLOWED = Enum and Enum.TraitConditionType
    and Enum.TraitConditionType.RanksAllowed

-- Port of TalentFrameBaseMixin:AddConditionsToTooltip: only the highest
-- tier gate, the lowest unmet level cap, and no unmet condition of a type
-- another sufficient condition already meets. Forever names the gate's
-- tree after the node's group ("... in Holy Talents").
local function ConditionLines(n, out)
    local cfg = ns.talData and ns.talData.cfg
    if not (cfg and n.conds and C_Traits.GetConditionInfo) then return end
    local treeName = n.sec and n.sec.gid and n.sec.title or ""
    local infos, metTypes = {}, {}
    local bestGate, bestLevel
    for i, cid in ipairs(n.conds) do
        local ok, ci = pcall(C_Traits.GetConditionInfo, cfg, cid, false,
            treeName)
        if not ok then ok, ci = pcall(C_Traits.GetConditionInfo, cfg, cid) end
        if ok and type(ci) == "table" then
            infos[i] = ci
            if ci.isSufficient and ci.isMet then metTypes[ci.type] = true end
            if ci.isGate and (not bestGate or (ci.spentAmountRequired or 0)
                    > (infos[bestGate].spentAmountRequired or 0)) then
                bestGate = i
            end
            if ci.type == RANKS_ALLOWED and ci.playerLevel and not ci.isMet
                and (not bestLevel
                    or ci.playerLevel < infos[bestLevel].playerLevel) then
                bestLevel = i
            end
        end
    end
    for i = 1, #n.conds do
        local ci = infos[i]
        local txt = ci and ci.tooltipText
        if txt and not ns.IsSecret(txt) and txt ~= ""
            and (ci.isMet or not metTypes[ci.type])
            and (not ci.isGate or i == bestGate)
            and not (ci.type == RANKS_ALLOWED and ci.playerLevel
                and i ~= bestLevel) then
            out[#out + 1] = { txt, 1, 1, 1 }
        end
    end
end

-- Classic prerequisite arrows: the source talent must be fully ranked.
local function PrereqLines(n, out)
    for _, inc in ipairs(n.incoming or EMPTY) do
        local src = inc.src
        local need = src.maxRank or 1
        local met = inc.active or (src.rank or 0) >= need
        local txt = ("Requires %d %s in %s"):format(need,
            need == 1 and "point" or "points", src.name or ("Talent " .. src.id))
        if met then
            out[#out + 1] = { txt, 1, 1, 1 }
        else
            out[#out + 1] = { txt, 1, 0.125, 0.125 }
        end
    end
end

local ShowTip

-- Trait tooltips read the talent's spell; Blizzard's TalentDisplay waits
-- for its data before building one, otherwise the description is missing.
local function RetipOnSpellLoad(n, b)
    if not (n.spellID and C_Spell and C_Spell.IsSpellDataCached
            and Spell and Spell.CreateFromSpellID) then
        return
    end
    if C_Spell.IsSpellDataCached(n.spellID) then return end
    local sp = Spell:CreateFromSpellID(n.spellID)
    pcall(sp.ContinueOnSpellLoad, sp, function()
        local ui = ns.talUI
        if ui and ui.sel == n and b.node == n and b:IsVisible() then
            ShowTip(b)
        end
    end)
end

-- Mirrors TalentDisplayMixin:SetTooltipInternal on Forever: title, rank,
-- subtext, the active entry's rank, then the next rank once one is bought.
-- The title is ours: Forever's GetTraitEntry lines don't always carry it.
function ShowTip(b)
    local n = b.node
    if not n then return end
    RetipOnSpellLoad(n, b)
    ns.SetTipScale(1)
    local half = b:GetParent():GetWidth() / 2
    GameTooltip:SetOwner(b, n.x < half and "ANCHOR_RIGHT" or "ANCHOR_LEFT")
    local name = n.name or ("Talent " .. n.id)
    GameTooltip:AddLine(name, 1, 0.82, 0)
    GameTooltip:AddLine(RANK_FMT:format(n.eff or 0, n.maxRank or 1), 1, 1, 1)
    local sub = n.subtext
    if TalentUtil and TalentUtil.GetTalentSubtext then
        local ok, s = pcall(TalentUtil.GetTalentSubtext, n.subtext, n.spellID)
        if ok then sub = s end
    end
    if sub and not ns.IsSecret(sub) and sub ~= "" then
        GameTooltip:AddLine(sub, 0.5, 0.5, 0.5)
    end
    GameTooltip:AddLine(" ")
    local curID, curRank = n.entryID, n.curRank
    if not curRank then
        curID = n.nextEntryID or n.entryID
        curRank = n.nextRank or 1
    end
    local body = AddEntryLines(curID, curRank, name)
    local d = TalentDesc(n)
    if d and not body:find(d:sub(1, 24), 1, true) then
        GameTooltip:AddLine(d, 1, 0.82, 0, true)
    end
    local nextBody = ""
    if n.curRank and n.nextEntryID and (n.rank or 0) > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(NEXT_RANK, 1, 1, 1)
        nextBody = AddEntryLines(n.nextEntryID, n.nextRank, name)
    end
    local req = {}
    ConditionLines(n, req)
    PrereqLines(n, req)
    if #req > 0 then GameTooltip:AddLine(" ") end
    local reqDiag = {}
    for _, r in ipairs(req) do
        GameTooltip:AddLine(r[1], r[2], r[3], r[4], true)
        reqDiag[#reqDiag + 1] = r[1]
    end
    for _, inc in ipairs(n.incoming or EMPTY) do
        reqDiag[#reqDiag + 1] = ("edge from %s type=%s active=%s")
            :format(tostring(inc.src.id), tostring(inc.type),
                tostring(inc.active))
    end
    GameTooltip:Show()
    ns.SetTipScale(ns.TIP_SCALE)
    if ns.talUI then
        ns.talUI.tipDiag = ("node=%s spell=%s cached=%s entry=%s@%s next=%s@%s desc=%s conds=%d\n    cur: %s\n    next: %s\n    req: %s")
            :format(tostring(n.id), tostring(n.spellID),
                tostring(n.spellID and C_Spell and C_Spell.IsSpellDataCached
                    and C_Spell.IsSpellDataCached(n.spellID)),
                tostring(curID), tostring(curRank),
                tostring(n.nextEntryID), tostring(n.nextRank),
                tostring(d and d:sub(1, 40)), #(n.conds or EMPTY), body,
                nextBody, table.concat(reqDiag, " / "))
    end
end

-- One thin line per side, like the pane frames around Blizzard's spec
-- columns: no template dependency (BackdropTemplateMixin is gone on
-- Midnight), so the frame is drawn from raw textures.
local function AddBorder(col)
    local r, g, b = 0.55, 0.47, 0.32
    local function Edge()
        local t = col:CreateTexture(nil, "BORDER")
        t:SetColorTexture(r, g, b, 0.9)
        return t
    end
    local top, bottom, left, right = Edge(), Edge(), Edge(), Edge()
    top:SetPoint("TOPLEFT")
    top:SetPoint("TOPRIGHT")
    top:SetHeight(1)
    bottom:SetPoint("BOTTOMLEFT")
    bottom:SetPoint("BOTTOMRIGHT")
    bottom:SetHeight(1)
    left:SetPoint("TOPLEFT")
    left:SetPoint("BOTTOMLEFT")
    left:SetWidth(1)
    right:SetPoint("TOPRIGHT")
    right:SetPoint("BOTTOMRIGHT")
    right:SetWidth(1)
end

local function NewCol(ui)
    local col = CreateFrame("Frame", nil, ui.colHost)
    col.art = col:CreateTexture(nil, "BACKGROUND", nil, 1)
    col.art:Hide()
    col.mark = col:CreateTexture(nil, "BACKGROUND", nil, 1)
    col.mark:SetPoint("CENTER")
    col.mark:SetDesaturated(true)
    col.mark:SetVertexColor(1, 1, 1, 0.07)
    col.mark:Hide()
    col.icon = col:CreateTexture(nil, "ARTWORK")
    col.icon:SetSize(HEADICON, HEADICON)
    col.icon:SetPoint("TOPLEFT", HEADPAD, -HEADPAD)
    col.name = T.CreateFontString(col, 31, T.colors.accent)
    col.name:SetPoint("LEFT", col.icon, "RIGHT", 10, 0)
    col.name:SetJustifyH("LEFT")
    col.name:SetWordWrap(false)
    col.spent = T.CreateFontString(col, 26, T.colors.text)
    col.spent:SetPoint("TOPRIGHT", -HEADPAD - 2, -HEADPAD)
    AddBorder(col)
    return col
end

-- Retail art (Mainline ClassTalentUtil): talents-background-<class>-<spec>.
-- Forever's columns are its three specs, each gets its own picture; the
-- fallback is Forever's own class image (Camelot ClassTalentUtil),
-- talent-background-<class>. Midnight's columns are class/spec/hero trees
-- under the active spec's picture, like retail.
-- Returns atlas, the u-range of it to use, and whether that range fills
-- the column alone (true) or spans the whole column area (false).
-- Classic tree names that differ from retail spec names.
local SPEC_ALIAS = { combat = "outlaw", feralcombat = "feral" }
-- Locale-free fallback: classic talent-tree skill line -> retail spec.
-- Paladin's three are proven (/njrn diag); the rest are classic
-- SkillLine IDs, unverified in-game.
local SKILL_SPEC = {
    [26] = "arms",
    [256] = "fury",
    [257] = "protection",
    [594] = "holy",
    [267] = "protection",
    [184] = "retribution",
    [50] = "beastmastery",
    [163] = "marksmanship",
    [51] = "survival",
    [253] = "assassination",
    [38] = "outlaw",
    [39] = "subtlety",
    [613] = "discipline",
    [56] = "holy",
    [78] = "shadow",
    [375] = "elemental",
    [373] = "enhancement",
    [374] = "restoration",
    [237] = "arcane",
    [8] = "fire",
    [6] = "frost",
    [355] = "affliction",
    [354] = "demonology",
    [593] = "destruction",
    [574] = "balance",
    [134] = "feral",
    [573] = "restoration",
}

local function ColArtAtlas(sec, i, n)
    local cl = (select(2, UnitClass("player")) or ""):lower()
    if Nocturne.IS_FOREVER then
        local sp = (sec.title or ""):lower():gsub("[^%a]", "")
        local base = "talents-background-" .. cl .. "-"
        local spec = Nocturne.FirstAtlas(base .. (SPEC_ALIAS[sp] or sp),
            SKILL_SPEC[sec.skill] and (base .. SKILL_SPEC[sec.skill]))
        if spec then return spec, 0, 1, true end
        local cls = Nocturne.FirstAtlas("talent-background-" .. cl)
        if cls and n > 1 then return cls, (i - 1) / n, i / n, true end
        return cls, 0, 1, false
    end
    local sp = ""
    if GetSpecialization and GetSpecializationInfo then
        local idx = GetSpecialization()
        local name = idx and select(2, GetSpecializationInfo(idx))
        if type(name) == "string" and not ns.IsSecret(name) then
            sp = name:lower():gsub("[^%a]", "")
        end
    end
    return Nocturne.FirstAtlas("talents-background-" .. cl .. "-" .. sp),
        0, 1, false
end

-- The picture (or its su0..su1 slice) is cover-fitted to the column alone
-- or to the whole column area, then each column shows the part under it.
-- Forever's class image is the three spec panels side by side (2046x1177
-- for Paladin, Holy | Protection | Retribution): slice i is column i's. SetTexCoord on an atlas texture
-- overwrites the atlas UVs, so slices are cut from the atlas' file with
-- the UVs remapped. Falls back to a desaturated spec icon watermark.
-- Reports the source for diag.
local function ApplyColBg(col, sec, x0, x1, W, H, atlas, su0, su1, own)
    col.art:Hide()
    col.mark:Hide()
    col.art:ClearAllPoints()
    local info = atlas and C_Texture.GetAtlasInfo(atlas)
    local file = info and (info.file or info.filename)
    if file then
        local bx0, bw = 0, W
        if own then bx0, bw = x0, x1 - x0 end
        local aw = (info.width or 1) * (su1 - su0)
        local ah = info.height or 1
        local sc = math.max(bw / aw, H / ah)
        local iw, ih = aw * sc, ah * sc
        local ax = (su1 - su0 < 1) and 0.5 or ART_ALIGN_X
        local ix, iy = bx0 + (bw - iw) * ax, (H - ih) / 2
        local vx0, vx1 = math.max(x0, ix), math.min(x1, ix + iw)
        local vy0, vy1 = math.max(0, iy), math.min(H, iy + ih)
        local l, r = info.leftTexCoord or 0, info.rightTexCoord or 1
        local t, b = info.topTexCoord or 0, info.bottomTexCoord or 1
        local function U(x)
            return l + (r - l) * (su0 + (su1 - su0) * (x - ix) / iw)
        end
        local function V(y) return t + (b - t) * (y - iy) / ih end
        col.art:SetTexture(file)
        col.art:SetTexCoord(U(vx0), U(vx1), V(vy0), V(vy1))
        col.art:SetPoint("TOPLEFT", vx0 - x0, -vy0)
        col.art:SetSize(vx1 - vx0, vy1 - vy0)
        col.art:SetVertexColor(ART_SHADE, ART_SHADE, ART_SHADE, 1)
        col.art:Show()
        return ("atlas:%s %dx%d"):format(atlas, info.width or 0,
            info.height or 0)
    end
    if sec.icon then
        col.mark:SetTexture(sec.icon)
        col.mark:Show()
        return "icon"
    end
    return "none"
end

local function CanLearn(n)
    return n and n.avail and (n.rank or 0) < (n.maxRank or 1)
        and ((ns.talData and ns.talData.points) or 0) > 0
end

local function SpentRanks(data)
    local n = 0
    for _, s in ipairs(data and data.secs or EMPTY) do
        for _, nd in ipairs(s.nodes) do
            n = n + (nd.rank or 0)
        end
    end
    return n
end

local function UpdateLegend(ui)
    local extra = ""
    if IsActiveView() then
        if CanLearn(ui.sel) then
            extra = extra .. "      " .. ns.PadGlyph("PAD1", "A")
                .. "  Learn"
        end
        if ui.sel and (ui.sel.rank or 0) > 0 then
            extra = extra .. "      " .. ns.PadGlyph("PAD2", "B")
                .. "  Refund"
        end
        if SpentRanks(ns.talData) > 0 then
            extra = extra .. "      " .. ns.PadGlyph("PAD4", "Y")
                .. "  Reset"
        end
        if ns.talData and ns.talData.staged then
            extra = extra .. "      " .. ns.PadGlyph("PAD3", "X")
                .. "  Apply"
        end
    end
    if CanActivate(ns.talView) then
        extra = extra .. "      " .. ns.PadGlyph("PAD3", "X")
            .. "  Activate"
    end
    ui.legend:SetText(ui.legendNav .. extra)
end

local function UpdateSpecBar(ui)
    local view = ns.talView
    if ui.tabRow then
        local active = ActiveSpecGroup()
        local off = {}
        for g, b in ipairs(ui.tabRow.tabs) do
            local open = SpecGroupUnlocked(g)
            b.label:SetText(GroupName(g) .. (g == active and " (active)"
                or not open and (" (level %d)"):format(DUAL_SPEC_LEVEL)
                or ""))
            off[g] = open and T.colors.text or T.colors.textDim
        end
        ns.LayoutSubTabRow(ui.tabRow)
        ns.PaintSubTabRow(ui.tabRow, view or active, off)
    end
    UpdateLegend(ui)
end

-- Try each known group-switch API in turn and report what happened, both
-- in chat (immediate) and in /njrn diag (ns.talActDiag). The server owns
-- the active group, so the page re-reads ActiveSpecGroup a beat later
-- instead of trusting the call's return.
local function SwitchSpecGroup(g)
    local tries = {
        { "SI.SetActiveSpecGroup",
            SI and SI.SetActiveSpecGroup },
        { "SetActiveTalentGroup", SetActiveTalentGroup },
        { "C_ClassTalents.SwitchToSpecializationByIndex",
            C_ClassTalents and C_ClassTalents.SwitchToSpecializationByIndex },
    }
    for _, t in ipairs(tries) do
        local name, f = t[1], t[2]
        if f then
            local ok, ret = pcall(f, g)
            ns.talActDiag = ("%s(%d) ok=%s ret=%s"):format(
                name, g, tostring(ok), tostring(ret))
            C_Timer.After(0.4, function()
                local active = ActiveSpecGroup()
                ns.talActDiag = ns.talActDiag
                    .. (" active=%s"):format(tostring(active))
                if active ~= g then
                    print(("Nocturne: %s (%s)"):format(
                        GROUP_NAMES and GroupName(g) or "spec",
                        ns.talActDiag))
                end
                Dirty()
            end)
            return
        end
    end
    ns.talActDiag = "no group-switch API"
    print("Nocturne: no spec-switch API on this client")
end

local function ActivateViewedSpec()
    local g = ns.talView
    if InCombatLockdown() or not CanActivate(g) then return end
    local name = GroupName(g)
    ns:ShowConfirm("Change specialization?",
        "Activate the " .. name .. " spec.", "Activate",
        function() SwitchSpecGroup(g) end)
end

-- A / click: buy the next rank of the selected talent; the PurchaseRank
-- answer comes back via trait events.
local function SpendPoint()
    local ui = ns.talUI
    local n = ui and ui.sel
    local data = ns.talData
    if InCombatLockdown() or not IsActiveView()
        or not (n and data and data.configID and CanLearn(n)) then
        return
    end
    if not (C_Traits and C_Traits.PurchaseRank) then
        ns.talActDiag = "no PurchaseRank API"
        print("Nocturne: PurchaseRank not available on this client")
        return
    end
    local ok, ret = pcall(C_Traits.PurchaseRank, data.configID, n.id)
    ns.talActDiag = ("PurchaseRank(node %d) ok=%s ret=%s"):format(n.id,
        tostring(ok), tostring(ret))
    C_Timer.After(0.4, function()
        Dirty()
        local m = ui.sel
        ns.talActDiag = (ns.talActDiag or "")
            .. (" rank=%s pts=%s"):format(
                tostring(m and m.rank), tostring(
                    ns.talData and ns.talData.points))
    end)
end

-- B: refund one rank of the selected talent. Routed through OnCancel (B
-- otherwise closes the journal): returns true only once a refund ran, so
-- B still closes the page when there is nothing to refund. RefundRank is
-- the confirmed API on both clients; RollbackConfig is deliberately not
-- a fallback — it discards every staged change, not one rank.
local function RefundPoint()
    local ui = ns.talUI
    local n = ui and ui.sel
    local data = ns.talData
    if InCombatLockdown() or not IsActiveView()
        or not (n and data and data.configID)
        or (n.rank or 0) <= 0 then
        return
    end
    if not (C_Traits and C_Traits.RefundRank) then
        ns.talActDiag = "no RefundRank API"
        print("Nocturne: no talent-refund API on this client")
        return true
    end
    local ok, ret = pcall(C_Traits.RefundRank, data.configID, n.id)
    ns.talActDiag = ("RefundRank(node %d) ok=%s ret=%s"):format(n.id,
        tostring(ok), tostring(ret))
    C_Timer.After(0.4, function()
        Dirty()
        local m = ui.sel
        ns.talActDiag = (ns.talActDiag or "")
            .. (" rank=%s pts=%s"):format(
                tostring(m and m.rank), tostring(
                    ns.talData and ns.talData.points))
    end)
    return true
end

-- X (active tab): commit staged rank changes on clients that buffer them
-- (retail model). No-op on Forever-style clients where IsReadyForCommit
-- stays false and purchases apply instantly.
local function CommitChanges()
    local data = ns.talData
    if InCombatLockdown() or not IsActiveView()
        or not (data and data.configID and data.staged) then
        return
    end
    if not (C_Traits and C_Traits.CommitConfig) then
        ns.talActDiag = "no CommitConfig API"
        print("Nocturne: no talent-commit API on this client")
        return
    end
    local ok, ret = pcall(C_Traits.CommitConfig, data.configID)
    ns.talActDiag = ("C_Traits.CommitConfig ok=%s ret=%s"):format(
        tostring(ok), tostring(ret))
    C_Timer.After(0.4, Dirty)
end

-- Y: refund every purchased rank in the viewed config at once.
local function ResetSpecTalents()
    local data = ns.talData
    if InCombatLockdown() or not IsActiveView()
        or not (data and data.configID) then
        return
    end
    local spent = SpentRanks(data)
    if spent == 0 then return end
    ns:ShowConfirm("Reset talents?",
        ("Refunds all %d spent points."):format(spent),
        "Reset", function()
            if not (C_Traits and C_Traits.ResetTree) then
                ns.talActDiag = "no ResetTree API"
                print("Nocturne: no tree-reset API on this client")
                return
            end
            local ok, ret = pcall(C_Traits.ResetTree, data.configID,
                data.treeID)
            ns.talActDiag = ("C_Traits.ResetTree ok=%s ret=%s")
                :format(tostring(ok), tostring(ret))
            C_Timer.After(0.4, Dirty)
        end)
end

function ns:TalentsPaint()
    local ui = ns.talUI
    if not ui then return end
    UpdateLegend(ui)
    for _, b in pairs(ui.pool) do
        if b:IsShown() then
            b.sel:SetShown(b.node == ui.sel)
        end
    end
    if ui.sel and ui.sel.btn then
        ShowTip(ui.sel.btn)
    elseif GameTooltip:GetOwner()
        and GameTooltip:GetOwner():GetParent() == ui.canvas then
        GameTooltip:Hide()
    end
end

RenderAll = function(f, ui)
    local secs = ns.talData and ns.talData.secs or EMPTY
    local N = #secs
    for _, b in pairs(ui.pool) do
        b:Hide()
        b.node = nil
    end
    for _, l in ipairs(ui.lines) do l:Hide() end
    for _, h in ipairs(ui.heads) do h:Hide() end
    ui.hi = 0
    for _, col in ipairs(ui.cols) do col:Hide() end
    ui.navNodes = {}
    UpdateSpecBar(ui)
    if N == 0 then
        ui.sel = nil
        GameTooltip:Hide()
        ui.empty:SetText(ns.talData and ns.talData.err or "No talents")
        ui.empty:Show()
        return
    end
    ui.empty:Hide()
    local W = f:GetWidth()
    local H = f:GetHeight() - TOPPAD - BOTTOMPAD
    local colW = math.max(60, (W - GAP * (N - 1)) / N)
    local li, ne = 0, 0
    local areaW = N * colW + (N - 1) * GAP
    local diag = {}
    for i, sec in ipairs(secs) do
        local col = ui.cols[i]
        if not col then
            col = NewCol(ui)
            ui.cols[i] = col
        end
        col:ClearAllPoints()
        col:SetPoint("TOPLEFT", (i - 1) * (colW + GAP), -TOPPAD)
        col:SetSize(colW, H)
        col:Show()
        if sec.icon then
            col.icon:SetTexture(sec.icon)
            col.icon:Show()
        else
            col.icon:Hide()
        end
        col.name:SetText(sec.title or "Talents")
        local spent, tot = 0, 0
        for _, n in ipairs(sec.nodes) do
            spent = spent + (n.rank or 0)
            tot = tot + (n.maxRank or 0)
        end
        col.spent:SetText(spent .. " / " .. tot)
        col.name:SetWidth(math.max(20, colW - HEADPAD * 2 - HEADICON - 10
            - col.spent:GetStringWidth() - 12))
        col.mark:SetSize(math.min(colW, H) * 0.55, math.min(colW, H) * 0.55)
        local cx = (i - 1) * (colW + GAP)
        diag[i] = (sec.key or i) .. ":"
            .. ApplyColBg(col, sec, cx, cx + colW, areaW, H,
                ColArtAtlas(sec, i, N))
        -- Nodes are laid out in this column's inner box but positioned on
        -- the shared canvas in page coordinates, so D-pad navigation can
        -- flow freely between spec columns.
        local ix = (i - 1) * (colW + GAP) + COLPAD
        local iy = TOPPAD + COLHEAD
        local iw = colW - COLPAD * 2
        local ih = H - COLHEAD - COLPAD
        local minX, minY, maxX, maxY
        for _, n in ipairs(sec.nodes) do
            minX = minX and math.min(minX, n.px) or n.px
            maxX = maxX and math.max(maxX, n.px) or n.px
            minY = minY and math.min(minY, n.py) or n.py
            maxY = maxY and math.max(maxY, n.py) or n.py
        end
        if minX then
            local s = math.min(
                iw / math.max(maxX - minX, 1),
                ih / math.max(maxY - minY, 1))
            -- Fit-to-box spreads small trees thin; cap the scale so the
            -- MEDIAN nearest-neighbor distance maps to ~1.4 node widths
            -- (robust to irregular grids: min-unique-diff under-measures
            -- when a spec skips grid columns).
            local nns = {}
            for a = 1, #sec.nodes do
                local na = sec.nodes[a]
                local best
                for b2 = 1, #sec.nodes do
                    if a ~= b2 then
                        local nb = sec.nodes[b2]
                        local d = math.sqrt(
                            (na.px - nb.px) ^ 2 + (na.py - nb.py) ^ 2)
                        if not best or d < best then best = d end
                    end
                end
                if best then nns[#nns + 1] = best end
            end
            if #nns > 0 then
                table.sort(nns)
                local med = nns[math.ceil(#nns / 2)]
                if med and med > 0 then
                    s = math.min(s, NODE * 1.4 / med)
                end
            end
            local ox = ix + (iw - (maxX - minX) * s) / 2
            local oy = iy + (ih - (maxY - minY) * s) / 2
            local byID = {}
            for _, n in ipairs(sec.nodes) do byID[n.id] = n end
            for _, n in ipairs(sec.nodes) do
                n.x = ox + (n.px - minX) * s
                n.y = oy + (n.py - minY) * s
                ui.navNodes[#ui.navNodes + 1] = n
                local b = ui.pool[n.id]
                if not b then
                    b = NewNode(ui)
                    ui.pool[n.id] = b
                end
                b.node = n
                n.btn = b
                b:ClearAllPoints()
                b:SetPoint("CENTER", ui.canvas, "TOPLEFT", n.x, -n.y)
                local c = STATE_COLOR[n.state] or STATE_COLOR.locked
                b.edge:SetColorTexture(c[1], c[2], c[3], c[4])
                if n.icon then
                    b.icon:SetTexture(n.icon)
                    b.icon:SetDesaturated(n.state == "locked")
                else
                    b.icon:SetTexture(nil)
                end
                b.rank:SetText(n.eff .. "/" .. n.maxRank)
                local pts = ns.talData and ns.talData.points or 0
                local rc
                if n.avail and n.rank < n.maxRank and pts > 0 then
                    rc = RANK_GREEN
                elseif n.state == "full" then
                    rc = T.colors.accent
                elseif n.eff > 0 then
                    rc = RANK_WHITE
                else
                    rc = RANK_GRAY
                end
                b.rank:SetTextColor(rc[1], rc[2], rc[3], rc[4] or 1)
                b:Show()
            end
            for _, n in ipairs(sec.nodes) do
                for _, e in ipairs(n.edges or EMPTY) do
                    local t = byID[e.targetNode or e.targetID or e.target]
                    if t and t.sec == n.sec and t.btn and n.btn then
                        ne = ne + 1
                        local c2 = Flag(e.isActive)
                            and EDGE_ACTIVE or EDGE_DIM
                        li = ShowEdge(ui, li, n, t, c2, Flag(e.isActive))
                    end
                end
            end
        end
    end
    ui.points:SetText(ns.talData and ns.talData.points
        and ("Talent points: " .. ns.talData.points) or "")
    local selID = ui.sel and ui.sel.id
    ui.sel = nil
    for _, n in ipairs(ui.navNodes) do
        if n.id == selID then
            ui.sel = n
            break
        end
    end
    ns:TalentsPaint()
    local nn = 0
    for _, n in ipairs(ui.navNodes) do
        if not n.name then nn = nn + 1 end
    end
    ui.diag = ("%d nodes, %d edges, %d noname, arrows=%s line=%s | %s")
        :format(#ui.navNodes, ne, nn, ArrowArt(false) and "atlas" or "flat",
            ui.canvas.CreateLine and "Line" or "tex",
            table.concat(diag, ", "))
end

local DIR = {
    PADDUP = { 0, -1 },
    PADDDOWN = { 0, 1 },
    PADDLEFT = { -1, 0 },
    PADDRIGHT = { 1, 0 }
}

local function Move(ui, dx, dy)
    local nodes = ui.navNodes
    if not (nodes and #nodes > 0) then return end
    if not ui.sel then
        ui.sel = nodes[1]
    else
        local nxt = ns.NavNearest(nodes, ui.sel, dx, dy)
        if nxt then ui.sel = nxt end
    end
    ns:TalentsPaint()
end

Reload = function()
    ns.talentsDirty = nil
    ns.talData = nil
    ns:TalentsEnsureData()
end

Dirty = function()
    ns.talentsDirty = true
    local f = ns.pageFrames and ns.pageFrames[5]
    if not (f and f:IsShown()) then return end
    Reload()
    local ui = ns.talUI
    if ui then RenderAll(f, ui) end
end

-- Single registration site: counts each event for /njrn diag (RegisterEvent
-- silently skips unknown names, so only valid ones tick) and schedules a
-- debounced refresh of the page.
local debounced
ns.diagTraitEvents = {}
ns.talentEvents = {
    "TRAIT_CONFIG_UPDATED", "TRAIT_CONFIG_LIST_UPDATED", "TRAIT_CONFIG_CREATED",
    "TRAIT_CONFIG_DELETED", "TRAIT_TREE_CHANGED", "TRAIT_TREE_CURRENCY_INFO_UPDATED",
    "TRAIT_NODE_CHANGED", "TRAIT_NODE_CHANGED_PARTIAL", "TRAIT_NODE_ENTRY_UPDATED",
    "TRAIT_SUB_TREE_CHANGED", "TRAIT_SYSTEM_INTERACTION_STARTED",
    "ACTIVE_TALENT_GROUP_CHANGED", "PLAYER_TALENT_UPDATE",
    "TALENTS_INVOLUNTARILY_RESET",
}
for _, ev in ipairs(ns.talentEvents) do
    Nocturne.RegisterEvent(ev, function()
        ns.diagTraitEvents[ev] = (ns.diagTraitEvents[ev] or 0) + 1
        if debounced then return end
        debounced = true
        C_Timer.After(0.1, function()
            debounced = nil
            Dirty()
        end)
    end)
end

ns.RegisterPage(5, {
    key = "talents",
    title = "Talents",
    subPages = function()
        return HasSpecTabs() and { "Primary", "Secondary" } or nil
    end,
    ownSubBar = true,
    Build = function(f)
        local ui = {}
        ns.talUI = ui
        ui.pool = {}
        ui.lines = {}
        ui.heads = {}
        ui.cols = {}
        ui.colHost = CreateFrame("Frame", nil, f)
        ui.colHost:SetAllPoints()

        -- Spec columns are colHost's children (one level up); the canvas
        -- must sit above them or the column backgrounds cover the arrows.
        ui.canvas = CreateFrame("Frame", nil, f)
        ui.canvas:SetAllPoints()
        ui.canvas:SetFrameLevel(ui.colHost:GetFrameLevel() + 5)

        ui.empty = T.CreateFontString(f, 22, T.colors.textDim)
        ui.empty:SetPoint("CENTER")
        ui.empty:SetJustifyH("CENTER")
        ui.empty:Hide()

        -- Dual-spec tabs (Forever) across the top; column contents start
        -- below them (TOPPAD).
        if HasSpecTabs() then
            ui.tabRow = ns.NewSubTabRow(f, { "Primary", "Secondary" })
            ui.tabRow:SetPoint("TOP", f, "TOP", 0, -TABROW_Y)
        end

        -- Parented to the canvas so it draws above the spec frames.
        ui.legend = T.CreateFontString(ui.canvas, 15, T.colors.text)
        -- The point counter ends just left of the tab row's LT glyph;
        -- without spec tabs it falls back to the bottom left.
        ui.points = T.CreateFontString(ui.tabRow or ui.canvas, 22,
            T.colors.accent)
        if ui.tabRow then
            ui.points:SetPoint("RIGHT", ui.tabRow.lt, "LEFT", -32, 0)
        else
            ui.points:SetPoint("BOTTOMLEFT", MARGIN, MARGIN)
        end
        local up = ns.PadGlyph("PADDUP")
        local down = ns.PadGlyph("PADDDOWN")
        local dpad = (up and up:find("|") and down and down:find("|"))
            and (up .. down) or "D-Pad"
        ui.legendNav = dpad .. "  Navigate"
        ui.legend:SetText(ui.legendNav)
        ui.legend:SetPoint("BOTTOMRIGHT", -MARGIN, MARGIN)

        ui.dpadHold = ns.DpadHoldFrame(f, function(btn)
            local d = DIR[btn]
            if d then Move(ui, d[1], d[2]) end
        end)

        f:SetScript("OnSizeChanged", function()
            if f:IsShown() and ns.talUI == ui then
                RenderAll(f, ui)
            end
        end)
    end,
    -- Opens on the active spec's tab; SetPage calls OnSubPage right
    -- after, which loads and renders.
    OnShow = function()
        if HasSpecTabs() then ns.subCurrent = ActiveSpecGroup() end
    end,
    OnSubPage = function(f, i)
        local ui = ns.talUI
        if not ui then return end
        local view = HasSpecTabs() and i or nil
        if view ~= ns.talView or ns.talentsDirty or not ns.talData then
            if view ~= ns.talView then ui.sel = nil end
            ns.talView = view
            Reload()
        end
        RenderAll(f, ui)
    end,
    OnPad = function(f, button)
        if button == "PAD3" then
            -- X shares the button: Activate only exists on the inactive
            -- spec tab; on the active tab it commits staged changes.
            if IsActiveView() then
                CommitChanges()
            else
                ActivateViewedSpec()
            end
            return
        end
        if button == "PAD1" then
            SpendPoint()
            return
        end
        if button == "PAD4" then
            ResetSpecTalents()
            return
        end
        local d = DIR[button]
        local ui = ns.talUI
        if not (d and ui) then return end
        ui.dpadHold[button] = { t = 0, acc = 0 }
        Move(ui, d[1], d[2])
    end,
    -- B refunds the selected talent's rank when there is one; otherwise
    -- the press falls through and closes the journal.
    OnCancel = function()
        return RefundPoint()
    end,
    OnPadUp = function(f, button)
        local ui = ns.talUI
        if ui and ui.dpadHold then ui.dpadHold[button] = nil end
    end,
    OnHide = function()
        local ui = ns.talUI
        if ui then
            ui.sel = nil
            if ui.dpadHold then wipe(ui.dpadHold) end
            ns.SetTipScale(1)
            GameTooltip:Hide()
        end
    end,
})
