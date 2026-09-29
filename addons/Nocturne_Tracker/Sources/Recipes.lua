local _, ns = ...

-- Tracked profession recipes (normal + recraft) with required reagents as
-- "have/need Name" lines.

local C = ns.colors
local TS = C_TradeSkillUI
local GetItemCount = C_Item and C_Item.GetItemCount
local GetItemNameByID = C_Item and C_Item.GetItemNameByID
local RequestLoadItemDataByID = C_Item and C_Item.RequestLoadItemDataByID
local GetCurrencyInfo = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo
local InCombatLockdown = InCombatLockdown

local EMPTY = {}
local RECRAFT = { false, true }
local LABEL = _G.PROFESSIONS_TRACKER_HEADER_PROFESSION or "Professions"

local src = { name = "recipes" }
ns.sources[#ns.sources + 1] = src

local requested = {}                    -- itemID -> true, one load request each

-- Every quality tier of a reagent counts toward the requirement.
local function CountOwned(reagents)
    local total = 0
    for _, r in ipairs(reagents) do
        if r.itemID and GetItemCount then
            total = total + (GetItemCount(r.itemID, true, false, true, true) or 0)
        elseif r.currencyID and GetCurrencyInfo then
            local info = GetCurrencyInfo(r.currencyID)
            total = total + (info and info.quantity or 0)
        end
    end
    return total
end

-- Item names can be uncached on first sight: request them and rebuild on
-- ITEM_DATA_LOAD_RESULT.
local function ReagentName(slot)
    local r = slot.reagents and slot.reagents[1]
    if not r then return nil end
    if r.itemID then
        local name = GetItemNameByID and GetItemNameByID(r.itemID)
        if not name and RequestLoadItemDataByID and not requested[r.itemID] then
            requested[r.itemID] = true
            RequestLoadItemDataByID(r.itemID)
            src.waiting = true
        end
        return name
    elseif r.currencyID and GetCurrencyInfo then
        local info = GetCurrencyInfo(r.currencyID)
        return info and info.name
    end
end

-- Fills the reagent lines; returns true if everything is in the bags.
local function AddReagents(e, schematic)
    local ready = true
    for _, slot in ipairs(schematic.reagentSlotSchematics or EMPTY) do
        local need = slot.quantityRequired
        if slot.required and need and need > 0 then
            local name = ReagentName(slot)
            if not name and slot.slotInfo then name = slot.slotInfo.slotText end
            if name then
                local have = CountOwned(slot.reagents or EMPTY)
                local done = have >= need
                ready = ready and done
                ns.AddLine(e, ("%d/%d %s"):format(math.min(have, need), need, name),
                    done and C.lineDone or C.line)
            end
        end
    end
    return ready
end

function src:Collect(db)
    src.active = false
    if not (db.showRecipes and TS and TS.GetRecipesTracked) then return end
    local s
    for _, isRecraft in ipairs(RECRAFT) do
        for _, rid in ipairs(TS.GetRecipesTracked(isRecraft) or EMPTY) do
            s = s or ns.NewSection(LABEL)
            src.active = true
            local e = ns.AddEntry(s)
            local info = TS.GetRecipeInfo and TS.GetRecipeInfo(rid)
            local schematic = TS.GetRecipeSchematic and TS.GetRecipeSchematic(rid, isRecraft)
            e.kind, e.id, e.isRecraft = "recipe", rid, isRecraft
            e.title = (schematic and schematic.name) or (info and info.name) or ("Recipe " .. rid)
            e.texture = info and info.icon
            local ready = schematic and AddReagents(e, schematic)
            e.titleColor = ready and C.done or C.title
        end
    end
end

ns.kinds.recipe = {
    OnClick = function(e, button)
        if button == "RightButton" then
            TS.SetRecipeTracked(e.id, false, e.isRecraft)
        elseif TS.OpenRecipe and not InCombatLockdown() then
            TS.OpenRecipe(e.id)
        end
    end,
    hint = "Click: open recipe | Right-click: untrack",
}

ns.RebuildOn({ "TRACKED_RECIPE_UPDATE" })

-- Reagent counts follow the bags, but only matter while a recipe is tracked.
_G.Nocturne.RegisterEvent("BAG_UPDATE_DELAYED", function()
    if src.active then ns.RequestRebuild() end
end)
_G.Nocturne.RegisterEvent("ITEM_DATA_LOAD_RESULT", function()
    if src.waiting then
        src.waiting = false
        ns.RequestRebuild()
    end
end)
