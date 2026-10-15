local _, ns = ...

local Nocturne = _G.Nocturne

function ns:InitOptions()
    local s = Nocturne.NewSettings("Nocturne: Journal", "NocturneJournal_", ns.db, ns.defaults,
        function()
            ns:SyncMapBinding()
        end)
    ns.category = s.category

    s:Checkbox("takeMapKey", "Open with the map key",
        "The keys bound to 'Toggle World Map' open the journal instead. The world map itself is left alone.")
    s:Checkbox("rememberPage", "Remember last page",
        "The journal reopens on the page you used last instead of always starting on the map.")

    s:Finish()
end

function ns:OpenOptions()
    Nocturne.OpenSettings(ns.category)
end

function ns:DiagText()
    local L = {}
    local function add(s) L[#L + 1] = s end

    local interface = select(4, GetBuildInfo())
    add(("interface=%s forever=%s gamepadUI=%s"):format(
        tostring(interface), tostring(Nocturne.IS_FOREVER), tostring(Nocturne.GamepadUI())))
    add(("shown=%s page=%d (%s) sub=%d"):format(
        tostring(ns.frame and ns.frame:IsShown() or false),
        ns.current,
        (ns.current ~= 0 and ns.pages[ns.current]) and ns.pages[ns.current].title or "-",
        ns.subCurrent))
    add("takeMapKey=" .. tostring(ns.db and ns.db.takeMapKey))
    if ns.mapBindingPending then
        add("map keys: pending (combat)")
    else
        add("map keys: " .. (#ns.diagMapKeys > 0 and table.concat(ns.diagMapKeys, ", ") or "none bound"))
    end
    for _, k in ipairs({ "PAD1", "PAD2", "PAD3", "PAD4", "PADDUP", "PADLTRIGGER", "PADLSHOULDER" }) do
        local raw = GetBindingText and GetBindingText(k)
        add(("glyph %s: raw=[%s] used=[%s]"):format(k,
            tostring(raw):gsub("|", "||"), tostring(ns.PadGlyph(k)):gsub("|", "||")))
    end
    add("pad input:")
    local any
    for button, count in pairs(ns.padCounts) do
        add(("  %s x%d"):format(button, count))
        any = true
    end
    if not any then add("  (nothing received yet)") end
    add(("stick: api=%s events=%s pollIdx=%s"):format(
        tostring(not not (C_GamePad and C_GamePad.GetDeviceMappedState)),
        tostring(ns.stickEvents or false),
        tostring(ns.stickIdxL) .. "/" .. tostring(ns.stickIdxR)))
    for name, count in pairs(ns.stickCounts or {}) do
        add(("  %s x%d"):format(name, count))
    end
    if ns.diagPadBtns then
        local names = {}
        for i, name in pairs(ns.diagPadBtns) do
            names[#names + 1] = ("%s=%s"):format(tostring(i), tostring(name))
        end
        table.sort(names)
        add("pad buttons: " .. table.concat(names, ", "))
    end
    add("atlases:")
    for i, def in ipairs(ns.pages) do
        add(("  %s: %s"):format(def.title, tostring(ns.diagAtlas[def.key] or "-")))
    end
    if ns.chardb then
        local pend = 0
        for _ in pairs(ns.chardb.pending) do pend = pend + 1 end
        add(("archive: %d completed, %d pending, %d historical"):format(
            #ns.chardb.completed, pend, #ns.HistoricalIDs()))
    end
    if ns.questUI then
        add(("quest list: %d rows, selected=%s, dirty=%s"):format(
            #ns.questUI.list.items,
            tostring(ns.questUI.selected and ns.questUI.selected.qid),
            tostring(ns.questListDirty)))
    end
    add("scene: " .. tostring(ns.diagScene or "-"))
    if ns.invUI and ns.invUI.sbar then
        local ui = ns.invUI
        local lo, hi = ui.sbar:GetMinMaxValues()
        local th = ui.sbar:GetThumbTexture()
        add(("invBar: shown=%s h=%.0f range=%.0f..%.0f thumbH=%s scrollH=%.0f childH=%.0f"):format(
            tostring(ui.sbar:IsShown()), ui.sbar:GetHeight(), lo, hi,
            th and ("%.0f"):format(th:GetHeight()) or "nil",
            ui.scroll:GetHeight(), ui.child:GetHeight()))
        local function Box(f)
            return ("L%.0f R%.0f T%.0f B%.0f"):format(
                f:GetLeft() or -1, f:GetRight() or -1,
                f:GetTop() or -1, f:GetBottom() or -1)
        end
        add(("invBarBox: bar[%s] vis=%s alpha=%.2f lvl=%d thumbShown=%s thumb[%s]"):format(
            Box(ui.sbar), tostring(ui.sbar:IsVisible()),
            ui.sbar:GetEffectiveAlpha(), ui.sbar:GetFrameLevel(),
            tostring(th and th:IsShown()), th and Box(th) or "-"))
        add("invBarSnapshot(0.3s after show): " .. tostring(ui.barSnap))
        add(("invScrollBox: scroll[%s] screen=%.0fx%.0f"):format(
            Box(ui.scroll), UIParent:GetWidth(), UIParent:GetHeight()))
    end
    if ns.chardb and ns.chardb.binds then
        local t = {}
        for k, v in pairs(ns.chardb.binds) do
            local act = GetBindingAction
                and GetBindingAction(k, true) or "?"
            t[#t + 1] = ("%s->%s [%s]"):format(k, tostring(v), tostring(act))
        end
        table.sort(t)
        add("item binds: " .. (#t > 0 and table.concat(t, ", ") or "none"))
        local held = {}
        for k in pairs(ns.heldSeen or {}) do held[#held + 1] = k end
        table.sort(held)
        add("held seen: " .. (#held > 0 and table.concat(held, ",") or "none"))
        add(("chord: sig=%q applies=%d bindClicks=%d"):format(
            ns.chordSig or "", ns.chordApplies or 0, ns.bindClicks or 0))
    end
    if ns.abUI then
        local ui = ns.abUI
        local sel = ui.selected
        local binds = 0
        for _ in pairs(ui.binds and ui.binds.byID or {}) do binds = binds + 1 end
        add(("abilities: sections=%d pages=%d spread=%s/%s grid=%sx%s selected=%s spellID=%s gamepadBinds=%d"):format(
            ui.sections and #ui.sections or -1,
            ui.pages and #ui.pages or -1,
            tostring(ui.spread), tostring(ui.spreads),
            tostring(ui.cols), tostring(ui.rows),
            tostring(sel and sel.info.name),
            tostring(sel and sel.info.spellID), binds))
        local g = ui.side and ui.side[1] and ui.side[1].grid
        add(("abGrid: L%.0f R%.0f T%.0f B%.0f"):format(
            g and g:GetLeft() or -1, g and g:GetRight() or -1,
            g and g:GetTop() or -1, g and g:GetBottom() or -1))
    end
    if ns.invUI then
        local ub = ns.invUI.useBtn
        add(("padUse: btn=%s item=%s clicks=%d padBind=%s"):format(
            tostring(not not ub),
            ub and tostring(ub:GetAttribute("item")) or "-",
            ns.invUI.useClicks or 0,
            tostring(ns.padBind)))
    end
    -- Talent API surface probe: decides the Talents page backend
    -- (see .devin/plans/journal-stageA-talents.md). Both Midnight and
    -- Forever use C_Traits; what differs is how sections are split —
    -- currencies/subTreeID on Midnight, groupIDs + combat configs on
    -- Forever. Every call is pcalled and every value passes ns.IsSecret.
    add("talents api:")
    local function val(v)
        return ns.IsSecret(v) and "<secret>" or tostring(v)
    end
    local function tryv(f, ...)
        local r = { pcall(f, ...) }
        if not r[1] then return "err:" .. tostring(r[2]):sub(1, 40) end
        local out = {}
        for i = 2, 4 do
            local v = r[i]
            if v == nil then break end
            if type(v) == "table" then v = "#" .. tostring(#v) end
            out[#out + 1] = val(v)
        end
        return table.concat(out, ",")
    end
    local function fns(t, pat)
        local out = {}
        if type(t) == "table" then
            for k in pairs(t) do
                if type(k) == "string" and k:lower():find(pat) then
                    out[#out + 1] = k
                end
            end
        end
        table.sort(out)
        return table.concat(out, ", ")
    end
    add(("  C_Traits=%s C_ClassTalents=%s C_Spec=%s"):format(
        type(C_Traits), type(C_ClassTalents), type(C_SpecializationInfo)))
    add("  level=" .. tryv(UnitLevel, "player"))
    -- Self-describing inventory: whatever group/combat/currency helpers a
    -- client ships surface here, even ones we don't know by name.
    if type(C_Traits) == "table" then
        add("  traits: " .. fns(C_Traits, "group"))
        add("  traits: " .. fns(C_Traits, "currency"))
        add("  traits: " .. fns(C_Traits, "subtree"))
        add("  traits: " .. fns(C_Traits, "combat"))
    end
    if type(C_ClassTalents) == "table" then
        add("  classT: " .. fns(C_ClassTalents, "combat"))
        add("  classT: " .. fns(C_ClassTalents, "config"))
        add("  classT: " .. fns(C_ClassTalents, "spec"))
        add("  classT: " .. fns(C_ClassTalents, "hero"))
    end
    if C_Traits and C_Traits.GetConfigsByType then
        for t = 1, 3 do
            add(("  cfgs type%d=%s"):format(t, tryv(C_Traits.GetConfigsByType, t)))
        end
    end
    if C_SpecializationInfo and C_SpecializationInfo.GetSpecialization then
        add("  spec=" .. tryv(C_SpecializationInfo.GetSpecialization))
        local okS, si = pcall(C_SpecializationInfo.GetSpecialization)
        if okS and si and not ns.IsSecret(si)
            and C_SpecializationInfo.GetSpecializationInfo then
            add("  specInfo=" .. tryv(
                C_SpecializationInfo.GetSpecializationInfo, si))
            local okI, sid = pcall(C_SpecializationInfo.GetSpecializationInfo, si)
            if okI and sid and not ns.IsSecret(sid)
                and C_ClassTalents and C_ClassTalents.GetTraitTreeForSpec then
                add("  treeForSpec=" .. tryv(C_ClassTalents.GetTraitTreeForSpec, sid))
            end
        end
        if C_SpecializationInfo.GetNumSpecializations then
            add("  numSpecs=" .. tryv(C_SpecializationInfo.GetNumSpecializations))
        end
    end
    -- Dual-spec (Forever): which talent group is active and whether the
    -- switch functions exist.
    local function tryf(f, ...)
        if type(f) ~= "function" then return "-" end
        return tryv(f, ...)
    end
    add(("  specgrp active=%s num=%s switchIdx=%s switchName=%s"):format(
        tryf(GetActiveTalentGroup), tryf(GetNumTalentGroups),
        val(C_ClassTalents and C_ClassTalents.SwitchToSpecializationByIndex ~= nil),
        val(C_ClassTalents and C_ClassTalents.SwitchToSpecializationByName ~= nil)))
    local si = C_SpecializationInfo
    if si then
        add(("  dualspec active=%s numGroups=%s cfg1=%s cfg2=%s set=%s"):format(
            tryf(si.GetActiveSpecGroup), tryf(GetNumSpecGroups),
            si.GetCombatConfigIDForSpecGroup
            and tryv(si.GetCombatConfigIDForSpecGroup, 1) or "-",
            si.GetCombatConfigIDForSpecGroup
            and tryv(si.GetCombatConfigIDForSpecGroup, 2) or "-",
            val(si.SetActiveSpecGroup ~= nil)))
    end
    if C_ClassTalents and C_ClassTalents.GetActiveConfigID then
        add("  configID=" .. tryv(C_ClassTalents.GetActiveConfigID))
        if C_ClassTalents.HasUnspentTalentPoints then
            add("  unspent flags=" .. tryv(C_ClassTalents.HasUnspentTalentPoints))
        end
        if C_ClassTalents.HasUnspentHeroTalentPoints then
            add("  unspentHero=" .. tryv(C_ClassTalents.HasUnspentHeroTalentPoints))
        end
        if C_ClassTalents.GetActiveHeroTalentSpec then
            add("  heroSpec=" .. tryv(C_ClassTalents.GetActiveHeroTalentSpec))
        end
        if C_ClassTalents.GetHeroTalentSpecsForClassSpec then
            add("  heroSpecs=" .. tryv(C_ClassTalents.GetHeroTalentSpecsForClassSpec))
        end
        local ok, cfg = pcall(C_ClassTalents.GetActiveConfigID)
        if ok and cfg and not ns.IsSecret(cfg)
            and C_Traits and C_Traits.GetConfigInfo then
            local ok2, info = pcall(C_Traits.GetConfigInfo, cfg)
            if ok2 and info and info.treeIDs then
                add(("  trees=%d ids=%s"):format(#info.treeIDs,
                    (function()
                        local ids = {}
                        for _, tid in ipairs(info.treeIDs) do
                            ids[#ids + 1] = val(tid)
                        end
                        return table.concat(ids, ",")
                    end)()))
                local tid = info.treeIDs[1]
                if tid and not ns.IsSecret(tid) then
                    if C_Traits.GetTreeInfo then
                        local ok3, ti = pcall(C_Traits.GetTreeInfo, cfg, tid)
                        if ok3 and ti then
                            add(("  tree title=%s root=%s gates=%d kit=%s"):format(
                                val(ti.titleText), val(ti.rootNodeID),
                                ti.gates and #ti.gates or -1,
                                val(ti.uiTextureKit)))
                        end
                    end
                    if C_Traits.GetTreeCurrencyInfo then
                        local ok4, cur = pcall(C_Traits.GetTreeCurrencyInfo,
                            cfg, tid, true)
                        if ok4 and cur then
                            for i, c in ipairs(cur) do
                                add(("  cur%d id=%s qty=%s max=%s spent=%s"):format(
                                    i, val(c.traitCurrencyID), val(c.quantity),
                                    val(c.maxQuantity), val(c.spent)))
                            end
                        end
                    end
                    -- Forever's own group API (found by the fns inventory):
                    -- display info per groupID on this tree.
                    if C_Traits.GetGroupDisplayInfoByTreeID then
                        local okG, gd = pcall(C_Traits.GetGroupDisplayInfoByTreeID, tid)
                        if okG and type(gd) == "table" then
                            local i = 0
                            for k, g in pairs(gd) do
                                i = i + 1
                                if i > 12 then
                                    add("  grpDisplay: ... (truncated)")
                                    break
                                end
                                if type(g) == "table" then
                                    local keys = {}
                                    for k2, v2 in pairs(g) do
                                        if type(v2) ~= "table" then
                                            keys[#keys + 1] = ("%s=%s"):format(
                                                tostring(k2), val(v2))
                                        end
                                    end
                                    table.sort(keys)
                                    add(("  grp[%s]: %s"):format(val(k),
                                        table.concat(keys, " ")))
                                else
                                    add(("  grp[%s]=%s"):format(val(k), val(g)))
                                end
                            end
                        else
                            add("  grpDisplay=" .. (okG and val(gd)
                                or "err:" .. tostring(gd):sub(1, 40)))
                        end
                    end
                    if C_Traits.GetTreeNodes and C_Traits.GetNodeInfo then
                        local ok5, nodes = pcall(C_Traits.GetTreeNodes, tid)
                        if ok5 and nodes then
                            add("  tree nodes=" .. tostring(#nodes))
                            -- Whole-tree pass: group distribution + real
                            -- posX/posY bounds (uniform scaling needs them).
                            local infos, groups, perGroup = {}, {}, {}
                            local minx, maxx, miny, maxy
                            for _, nid in ipairs(nodes) do
                                local ok6, ni = pcall(C_Traits.GetNodeInfo, cfg, nid)
                                if ok6 and ni then
                                    infos[nid] = ni
                                    if type(ni.posX) == "number"
                                        and not ns.IsSecret(ni.posX) then
                                        minx = minx and math.min(minx, ni.posX) or ni.posX
                                        maxx = maxx and math.max(maxx, ni.posX) or ni.posX
                                    end
                                    if type(ni.posY) == "number"
                                        and not ns.IsSecret(ni.posY) then
                                        miny = miny and math.min(miny, ni.posY) or ni.posY
                                        maxy = maxy and math.max(maxy, ni.posY) or ni.posY
                                    end
                                    for _, g in ipairs(ni.groupIDs or {}) do
                                        groups[g] = true
                                        perGroup[g] = (perGroup[g] or 0) + 1
                                    end
                                end
                            end
                            local gout = {}
                            for g in pairs(groups) do
                                gout[#gout + 1] = g .. "=" .. perGroup[g]
                            end
                            table.sort(gout)
                            add("  groups: " .. (#gout > 0
                                and table.concat(gout, " ") or "none"))
                            add(("  bbox x=%s..%s y=%s..%s"):format(
                                val(minx), val(maxx), val(miny), val(maxy)))
                            for i = 1, math.min(3, #nodes) do
                                local ni = infos[nodes[i]]
                                if ni then
                                    local g = ni.groupIDs
                                        and table.concat(ni.groupIDs, "/") or "-"
                                    add(("  node%d id=%s xy=%s,%s type=%s vis=%s grp=%s sub=%s/%s r=%s/%s spent=%s e=%s")
                                        :format(
                                            i, val(nodes[i]), val(ni.posX), val(ni.posY),
                                            val(ni.type), val(ni.isVisible), g,
                                            val(ni.subTreeID), val(ni.subTreeActive),
                                            val(ni.currentRank), val(ni.maxRanks),
                                            val(ni.ranksPurchased),
                                            val(#(ni.visibleEdges
                                                or ni.edges or {}))))
                                end
                            end
                            -- Field names of trait conditions vary by
                            -- client; dump a few so the emu gate rules can
                            -- be verified against the real schema.
                            if C_Traits.GetConditionInfo then
                                local shown = 0
                                for _, nid in ipairs(nodes) do
                                    local ni = infos[nid]
                                    if ni and ni.conditionIDs
                                        and shown < 3 then
                                        for _, cid in
                                        ipairs(ni.conditionIDs) do
                                            local ok9, ci = pcall(
                                                C_Traits.GetConditionInfo,
                                                cfg, cid)
                                            if ok9 and type(ci)
                                                == "table" then
                                                local keys = {}
                                                for k2, v2 in pairs(ci) do
                                                    if type(v2)
                                                        ~= "table" then
                                                        keys[#keys + 1] =
                                                            ("%s=%s")
                                                            :format(
                                                                tostring(k2),
                                                                val(v2))
                                                    end
                                                end
                                                table.sort(keys)
                                                add(("  cond n%s c%s: %s")
                                                    :format(val(nid),
                                                        val(cid),
                                                        table.concat(
                                                            keys, " ")))
                                                shown = shown + 1
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        if C_ClassTalents.GetHeroTalentSpecsForClassSpec
            and C_Traits.GetSubTreeInfo then
            local ok7, subs = pcall(C_ClassTalents.GetHeroTalentSpecsForClassSpec)
            if ok7 and subs and not ns.IsSecret(subs) then
                for i, sid in ipairs(subs) do
                    local ok8, st = pcall(C_Traits.GetSubTreeInfo, cfg, sid)
                    if ok8 and st then
                        add(("  sub%d id=%s name=%s active=%s"):format(
                            i, val(sid), val(st.name), val(st.isActive)))
                    end
                end
            end
        end
    end
    -- Trait event counters prove which names actually fire on this client:
    -- RegisterEvent silently skips unknown ones, so only valid names tick.
    local evs, inv = {}, {}
    for ev, n in pairs(ns.diagTraitEvents or {}) do
        evs[#evs + 1] = ev .. "x" .. n
    end
    for _, ev in ipairs(ns.talentEvents or {}) do
        if IsEventValid and not IsEventValid(ev) then
            inv[#inv + 1] = ev
        end
    end
    table.sort(evs)
    add("  trait events: " .. (#evs > 0 and table.concat(evs, ", ") or "none fired"))
    add("  invalid events: " .. (#inv > 0 and table.concat(inv, ", ") or "none"))
    if ns.talData then
        local secs = {}
        for _, s in ipairs(ns.talData.secs) do
            secs[#secs + 1] = ("%s[%d]"):format(s.key or s.title, #s.nodes)
        end
        add(("talents: err=%s nodes=%s secs=[%s] sel=%s %s"):format(
            tostring(ns.talData.err),
            tostring(ns.talData.nodeCount),
            table.concat(secs, ", "),
            tostring(ns.talUI and ns.talUI.sel and ns.talUI.sel.id),
            tostring(ns.talUI and ns.talUI.diag or "")))
        if ns.talUI and ns.talUI.tipDiag then
            add("  last tip: " .. ns.talUI.tipDiag)
        end
        if ns.talActDiag then
            add("  last spec switch: " .. ns.talActDiag)
        end
    end
    return table.concat(L, "\n")
end

-- Trait event counters are registered in Pages/Talents.lua (ns.talentEvents
-- → ns.diagTraitEvents), which loads before this file.

SLASH_NOCTURNEJOURNAL1 = "/njournal"
SLASH_NOCTURNEJOURNAL2 = "/njrn"
SlashCmdList.NOCTURNEJOURNAL = function(msg)
    msg = strlower(strtrim(msg or ""))
    if msg == "toggle" then
        ns:Toggle()
    elseif msg == "diag" then
        Nocturne.ShowCopyText("Nocturne: Journal — diag", ns:DiagText())
    elseif tonumber(msg) then
        ns:Open(tonumber(msg))
    else
        ns:OpenOptions()
    end
end

function NocturneJournal_OnCompartmentClick()
    ns:Toggle()
end

function NocturneJournal_OnCompartmentEnter(_, menuButton)
    GameTooltip:SetOwner(menuButton, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Nocturne: Journal", 1, 1, 1)
    GameTooltip:AddLine("Click to toggle the journal", 0.8, 0.8, 0.8)
    GameTooltip:Show()
end

function NocturneJournal_OnCompartmentLeave()
    GameTooltip:Hide()
end
