local _, ns = ...

local Nocturne = _G.Nocturne
local T = Nocturne.Theme

local UnitAffectingCombat = UnitAffectingCombat

local PAD = 10                        -- inner padding around the list
local BLOCK_GAP = 10                  -- vertical gap between entries
local CAT_GAP = 6                     -- extra gap before a new section header
local HEADER_GAP = 4                  -- gap under a section header
local ICON_GAP = 4                    -- gap between an entry icon and its title
local LINE_GAP = 1
local WHEEL_STEP = 48                 -- pixels per mouse wheel notch
ns.PAD = PAD

-- Shared by Sources/*.lua.
ns.colors = {
    title    = { 1, 1, 1, 1 },          -- entry titles
    done     = { 0.52, 0.78, 0.55, 1 }, -- soft green: objectives finished
    line     = { 1, 1, 1, 0.80 },       -- objective lines
    lineDone = { 1, 1, 1, 0.45 },       -- completed objective lines
}

ns.fontChoices = {
    { label = "Friz Quadrata", path = "Fonts\\FRIZQT__.TTF" },
    { label = "Arial Narrow",  path = "Fonts\\ARIALN.TTF" },
    { label = "Morpheus",      path = "Fonts\\MORPHEUS.TTF" },
    { label = "Skurri",        path = "Fonts\\SKURRI.TTF" },
}

local blocks = {}                       -- Button pool: one per entry (clickable title row)
local lines = {}                        -- FontString pool: headers and entry lines
local scrollOffset = 0
local curFont, curWidth                 -- set by Rebuild for PlaceLine

-- Model: every rebuild the sources fill sections -> entries -> lines.
-- All tables are pooled and reused, never reallocated per rebuild.
local sections, numSections = {}, 0
local itemEntries = {}                  -- entries with a quest item, for ItemButtons.lua
ns.itemEntries = itemEntries
local ENTRY_FIELDS = {
    "kind", "id", "title", "titleColor", "atlas", "texture", "watched", "isRecraft",
    "itemID", "itemLink", "itemTexture", "itemCharges", "timerLine", "y",
}

function ns.NewSection(title)
    numSections = numSections + 1
    local s = sections[numSections]
    if not s then
        s = { entries = {} }
        sections[numSections] = s
    end
    s.title, s.n = title, 0
    return s
end

function ns.AddEntry(s)
    s.n = s.n + 1
    local e = s.entries[s.n]
    if not e then
        e = { texts = {}, colors = {} }
        s.entries[s.n] = e
    end
    for _, k in ipairs(ENTRY_FIELDS) do e[k] = nil end
    e.nLines = 0
    return e
end

-- Returns the line's index within the entry.
function ns.AddLine(e, text, color)
    local n = e.nLines + 1
    e.nLines = n
    e.texts[n], e.colors[n] = text, color or ns.colors.line
    return n
end

local function FontPath()
    local c = ns.fontChoices[ns.db.fontFace]
    return c and c.path or ns.fontChoices[1].path
end

local function OnBlockClick(self, button)
    local e = self.entry
    local k = e and ns.kinds[e.kind]
    if k and k.OnClick then k.OnClick(e, button) end
end

local function OnBlockEnter(self)
    local e = self.entry
    if not e then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine(e.title or "", 1, 1, 1)
    local k = ns.kinds[e.kind]
    local hint = k and k.hint
    if type(hint) == "function" then hint = hint(e) end
    if hint then GameTooltip:AddLine(hint, 0.6, 0.6, 0.6) end
    GameTooltip:Show()
end

local function ApplyPoint()
    local p = ns.db.point
    ns.frame:ClearAllPoints()
    ns.frame:SetPoint(p[1], UIParent, p[1], p[2], p[3])
end

local function SavePosition()
    local f, p = ns.frame, ns.db.point
    p[1] = "TOPRIGHT"
    p[2] = f:GetRight() - UIParent:GetRight()
    p[3] = f:GetTop() - UIParent:GetTop()
end

local function StartDrag()
    if not ns.db.locked then ns.frame:StartMoving() end
end

local function StopDrag()
    local f = ns.frame
    f:StopMovingOrSizing()
    -- StartMoving marks a named frame user-placed; the client would then
    -- restore it from layout-cache on top of db.point.
    f:SetUserPlaced(false)
    SavePosition()
    -- StopMovingOrSizing re-anchors to whatever point the client picks;
    -- restore TOPRIGHT so later height changes grow downward.
    ApplyPoint()
    ns:LayoutItems()
end

local function NewText(parent)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetJustifyH("LEFT")
    fs:SetShadowColor(0, 0, 0, 0.8)
    fs:SetShadowOffset(1, -1)
    return fs
end

local function AcquireBlock(i)
    local b = blocks[i]
    if not b then
        b = CreateFrame("Button", nil, ns.content)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.title = NewText(b)
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b:RegisterForDrag("LeftButton")
        b:SetScript("OnClick", OnBlockClick)
        b:SetScript("OnEnter", OnBlockEnter)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        b:SetScript("OnDragStart", StartDrag)
        b:SetScript("OnDragStop", StopDrag)
        blocks[i] = b
    end
    return b
end

-- Atlas (quest type) or texture (achievement/recipe icon); a missing icon
-- keeps its column so every title stays aligned.
local function SetBlockIcon(b, e, iconSize, size)
    local key = e.atlas or e.texture
    if b.iconKey ~= key then
        b.iconKey = key
        if e.atlas then
            b.icon:SetAtlas(e.atlas)
        elseif e.texture then
            b.icon:SetTexture(e.texture)
            b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        end
    end
    b.icon:SetSize(iconSize, iconSize)
    b.icon:ClearAllPoints()
    b.icon:SetPoint("TOPLEFT", 0, (iconSize - size) / 2)
    b.icon:SetShown(key ~= nil)
end

-- Places pooled line `li` at (x, -y) inside the content; returns its
-- height and the FontString.
local function PlaceLine(li, x, y, text, size, flags, color)
    local fs = lines[li]
    if not fs then
        fs = NewText(ns.content)
        lines[li] = fs
    end
    fs:SetFont(curFont, size, flags)
    fs:SetWidth(curWidth - x)
    fs:SetText(text)
    fs:SetTextColor(color[1], color[2], color[3], color[4])
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", ns.content, "TOPLEFT", x, -y)
    fs:Show()
    return fs:GetStringHeight(), fs
end

local function ApplyScroll()
    -- The visible height is min(contentH, db.height), so compute the range
    -- directly instead of reading clip geometry mid-layout.
    ns.maxScroll = math.max(0, (ns.contentH or 0) - ns.db.height)
    scrollOffset = math.min(math.max(scrollOffset, 0), ns.maxScroll)
    ns.scrollOffset = scrollOffset
    ns.content:ClearAllPoints()
    ns.content:SetPoint("TOPLEFT", ns.clip, "TOPLEFT", 0, scrollOffset)
    ns.frame:EnableMouseWheel(ns.maxScroll > 0)
end

local function UpdateVisibility()
    local db, f = ns.db, ns.frame
    if not f then return end
    -- While unlocked, keep an empty frame visible so the user can find and
    -- drag it; locked + nothing tracked = fully hidden.
    local show = db.enabled and ((ns.entryCount or 0) > 0 or not db.locked)
    if show and db.hideInCombat and UnitAffectingCombat("player") then show = false end
    f:SetShown(show)
end

function ns:Rebuild()
    local f, db = ns.frame, ns.db
    if not f or not db then return end
    if not db.enabled then
        f:Hide()
        ns:LayoutItems()
        return
    end

    numSections = 0
    for _, src in ipairs(ns.sources) do src:Collect(db) end

    curFont = FontPath()
    curWidth = db.width - PAD * 2
    local size = db.fontSize
    local iconSize = size + 2
    local indent = iconSize + ICON_GAP -- lines align with the title text

    wipe(itemEntries)
    ns.timerFS = nil
    local y, bi, li, count = 0, 0, 0, 0
    for si = 1, numSections do
        local s = sections[si]
        if s.n > 0 then
            if count > 0 then y = y + CAT_GAP end
            li = li + 1
            y = y + PlaceLine(li, 0, y, s.title, math.max(8, size - 1), "OUTLINE", T.colors.textDim)
                + HEADER_GAP

            for ei = 1, s.n do
                local e = s.entries[ei]
                count = count + 1
                bi = bi + 1
                local b = AcquireBlock(bi)
                b.entry = e
                e.y = y
                if e.itemID then itemEntries[#itemEntries + 1] = e end

                SetBlockIcon(b, e, iconSize, size)
                b.title:SetFont(curFont, size, "")
                b.title:SetWidth(curWidth - indent)
                b.title:ClearAllPoints()
                b.title:SetPoint("TOPLEFT", indent, 0)
                b.title:SetText(e.title or "")
                local tc = e.titleColor or ns.colors.title
                b.title:SetTextColor(tc[1], tc[2], tc[3], tc[4])

                local th = math.max(b.title:GetStringHeight(), size)
                b:SetSize(curWidth, th)
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", ns.content, "TOPLEFT", 0, -y)
                b:Show()
                y = y + th

                for l = 1, e.nLines do
                    li = li + 1
                    local h, fs = PlaceLine(li, indent, y + LINE_GAP, e.texts[l], size - 1, "", e.colors[l])
                    if l == e.timerLine then ns.timerFS = fs end
                    y = y + LINE_GAP + h
                end
                y = y + BLOCK_GAP
            end
        end
    end
    ns.entryCount = count

    for i = bi + 1, #blocks do
        blocks[i]:Hide()
        blocks[i].entry = nil
    end
    for i = li + 1, #lines do lines[i]:Hide() end

    ns.contentH = math.max(0, y - BLOCK_GAP)
    ns.content:SetSize(curWidth, math.max(ns.contentH, 1))

    -- The visible zone hugs the content: height tracks the list, capped at
    -- the configured max (longer lists scroll). Empty + unlocked keeps a
    -- small box so the frame can still be found and dragged.
    local visibleH = ns.contentH > 0 and math.min(ns.contentH, db.height) or 40
    ns.viewH = visibleH
    f:SetSize(db.width, visibleH + PAD * 2)
    ApplyScroll()

    local empty = count == 0
    if empty then
        local c = T.colors.textDim
        ns.empty:SetFont(curFont, math.max(8, size - 1), "")
        ns.empty:SetText("Nothing tracked")
        ns.empty:SetTextColor(c[1], c[2], c[3], c[4])
    end
    ns.empty:SetShown(empty)
    UpdateVisibility()
    ns:LayoutItems()
end

local function OnWheel(_, delta)
    if (ns.maxScroll or 0) <= 0 then return end
    scrollOffset = math.min(math.max(scrollOffset - delta * WHEEL_STEP, 0), ns.maxScroll)
    ApplyScroll()
    ns:LayoutItems()
end

function ns:ApplyLayout()
    local f, db = ns.frame, ns.db
    if not f then return end

    -- Locked = the empty area is click-through; entry rows stay clickable.
    f:EnableMouse(not db.locked)
    ApplyPoint()

    if f.SetBackdropColor then
        local c, b = T.colors.backdrop, T.colors.border
        f:SetBackdropColor(c[1], c[2], c[3], db.bgOpacity)
        f:SetBackdropBorderColor(b[1], b[2], b[3], db.bgOpacity)
    end

    ns:Rebuild()
end

function ns:CreateTrackerFrame()
    local f = CreateFrame("Frame", "NocturneTrackerFrame", UIParent)
    ns.frame = f

    T.ApplyBackdrop(f)
    f:SetFrameStrata("LOW")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", StartDrag)
    f:SetScript("OnDragStop", StopDrag)
    f:SetScript("OnMouseWheel", OnWheel)

    -- clip bounds the scrollable content (SetClipsChildren clips child
    -- frames incl. their regions — same pattern as the compass drum).
    local clip = CreateFrame("Frame", nil, f)
    clip:SetPoint("TOPLEFT", PAD, -PAD)
    clip:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    clip:SetClipsChildren(true)
    ns.clip = clip

    ns.content = CreateFrame("Frame", nil, clip)

    ns.empty = NewText(clip)
    ns.empty:SetPoint("CENTER")
    ns.empty:Hide()

    ns:ApplyLayout()
end

local function WantBlizzardHidden()
    return ns.db.enabled and ns.db.replaceBlizzard
end

-- The objective tracker holds secure children (quest item buttons) and
-- re-shows itself on events and edit mode; see Nocturne.NewSuppressor.
local blizzard = Nocturne.NewSuppressor(function() return _G.ObjectiveTrackerFrame end, WantBlizzardHidden)

function ns:SyncBlizzard()
    if ns.db then blizzard.Sync() end
end

function ns:DiagText()
    local db, ot = ns.db, _G.ObjectiveTrackerFrame
    local out = {
        ("enabled=%s locked=%s replaceBlizzard=%s font=%d size=%d w=%d h=%d bg=%.2f"):format(
            tostring(db.enabled), tostring(db.locked), tostring(db.replaceBlizzard),
            db.fontFace, db.fontSize, db.width, db.height, db.bgOpacity),
        ("sources: scenario=%s areaTasks=%s achievements=%s recipes=%s items=%s"):format(
            tostring(db.showScenario), tostring(db.showAreaTasks), tostring(db.showAchievements),
            tostring(db.showRecipes), tostring(db.showItems)),
        ("entries=%d contentH=%d scroll=%d/%d shown=%s point=%s,%d,%d itemButtons=%d"):format(
            ns.entryCount or 0, ns.contentH or 0, ns.scrollOffset or 0, ns.maxScroll or 0,
            tostring(ns.frame and ns.frame:IsShown()),
            tostring(db.point[1]), db.point[2] or 0, db.point[3] or 0, ns.numItemButtons or 0),
        ("blizzard frame=%s shown=%s alpha=%.2f hiddenByUs=%s protected=%s"):format(
            tostring(ot ~= nil), tostring(ot and ot:IsShown()), ot and ot:GetAlpha() or -1,
            tostring(blizzard.hidden), tostring(ot and ot:IsProtected())),
    }
    for si = 1, numSections do
        local s = sections[si]
        out[#out + 1] = ("# %s (%d)"):format(tostring(s.title), s.n)
        for ei = 1, s.n do
            local e = s.entries[ei]
            out[#out + 1] = ("  %s %s '%s' lines=%d icon=%s item=%s watched=%s"):format(
                tostring(e.kind), tostring(e.id), tostring(e.title), e.nLines,
                tostring(e.atlas or e.texture), tostring(e.itemID), tostring(e.watched))
            for l = 1, e.nLines do
                out[#out + 1] = "    - " .. tostring(e.texts[l])
            end
        end
    end
    return table.concat(out, "\n")
end

-- Events can burst (turn-in, criteria updates fire several in a row);
-- coalesce them into one rebuild per 100ms instead of rebuilding per event.
local rebuildPending = false
function ns.RequestRebuild()
    if rebuildPending then return end
    rebuildPending = true
    C_Timer.After(0.1, function()
        rebuildPending = false
        ns:Rebuild()
    end)
end

-- Events that only mean "something changed": rebuild, debounced.
function ns.RebuildOn(events)
    for _, event in ipairs(events) do
        Nocturne.RegisterEvent(event, ns.RequestRebuild)
    end
end

Nocturne.RegisterEvent("PLAYER_ENTERING_WORLD", function()
    ns:SyncBlizzard()
    ns.RequestRebuild()
end)
Nocturne.RegisterEvent("PLAYER_REGEN_DISABLED", UpdateVisibility)
Nocturne.RegisterEvent("PLAYER_REGEN_ENABLED", function()
    ns:SyncBlizzard()
    UpdateVisibility()
    ns:LayoutItems()
end)
