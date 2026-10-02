local _, ns = ...

local Nocturne = _G.Nocturne

local LAYOUT_NAME = "Nocturne"
local LAYOUT_STRING =
"2 52 0 0 0 4 4 UIParent 0.0 -413.8 -1 ##$$%/&('%)$+$,$ 0 1 0 4 4 UIParent 0.0 -355.1 -1 ##$$%/&('%(#,$ 0 2 0 4 4 UIParent 0.0 -306.4 -1 ##$$%/&('%(#,$ 0 3 0 4 4 UIParent 0.0 -257.0 -1 ##$$%/&('%(#,$ 0 4 0 7 7 UIParent 357.3 2.0 -1 ##$'%/&('%(#,$ 0 5 0 3 3 UIParent 1245.1 -307.2 -1 #$$%%/&('%(#,$ 0 6 0 5 5 UIParent -2.0 -14.0 -1 #$$$%/&('%(#,$ 0 7 0 3 3 UIParent 1822.0 -16.0 -1 #$$$%/&('%(#,$ 0 10 0 0 6 PlayerFrame 28.1 21.2 -1 ##$$&,'' 0 11 0 7 7 UIParent -334.5 2.0 -1 ##$'&('%,# 0 12 0 7 7 UIParent 548.5 272.0 -1 ##$$&-'% 1 -1 0 4 4 UIParent 0.0 -404.8 -1 #$$#%$ 2 -1 0 1 1 UIParent 745.5 -2.0 -1 #$$$%&&2 3 0 0 6 6 UIParent 223.7 102.8 -1 $#3, 3 1 0 0 2 PersonalResourceDisplayFrame -17.8 17.4 -1 %$3% 3 2 0 6 0 ChatFrame1 -55.6 42.8 -1 %$&$3' 3 3 0 0 0 UIParent 576.0 -748.0 -1 '$(#)$-k.G/#1#3#5%6(7-7$8(9( 3 4 0 0 0 UIParent 594.0 -575.0 -1 ,%-1.3/#0%1#2(3#5%6(7-7$8(9( 3 5 0 2 2 UIParent -2.4 -2.4 -1 &$*$3' 3 6 0 2 2 UIParent -1287.0 -482.0 -1 -#.#/#4$5#6(7-7$8(9( 3 7 0 0 0 UIParent 247.8 -944.0 -1 3# 4 -1 0 4 4 UIParent 0.0 -258.7 -1 # 5 -1 0 7 7 UIParent 529.0 2.0 -1 # 6 0 0 1 1 UIParent -735.0 -2.0 -1 ##$#%#&.(()( 6 1 0 8 2 PlayerFrame -28.1 -18.3 -1 ##$$%$'+(()(-$ 6 2 1 1 1 UIParent 0.0 -25.0 -1 ##$#%$&.(()(+#,-,$ 7 -1 0 4 4 UIParent 0.0 -204.5 -1 # 8 -1 0 7 1 DebuffFrame -136.5 36.0 -1 #'$F%$&n 9 -1 0 3 3 UIParent 1412.0 -244.0 -1 # 10 -1 1 0 0 UIParent 16.0 -116.0 -1 # 11 -1 0 7 7 UIParent 811.0 2.0 -1 # 12 -1 0 0 0 UIParent 1247.0 -340.0 -1 #3$-$$%) 13 -1 0 0 2 BuffFrame -11.0 0.0 -1 ##$$%2&) 14 -1 0 7 7 UIParent 720.5 1.5 -1 ##$#%# 15 0 1 7 7 StatusTrackingBarManager 0.0 0.0 -1 &- 15 1 1 7 7 StatusTrackingBarManager 0.0 17.0 -1 &- 16 -1 0 7 7 UIParent -895.0 2.0 -1 #( 17 -1 0 0 0 UIParent 1668.0 -556.2 -1 ## 18 -1 0 0 0 UIParent 1464.0 -771.0 -1 #- 19 -1 0 4 4 UIParent 0.0 -218.5 -1 ## 20 0 1 7 7 UIParent 0.0 310.0 -1 ##$/%$&('%(-($)#+$,$-$ 20 1 1 7 7 UIParent 0.0 240.0 -1 ##$*%$&('%(-($)#+$,$-$ 20 2 1 7 7 UIParent 0.0 370.0 -1 ##$$%$&('((-($)#+$,$-$ 20 3 1 7 7 UIParent 420.0 430.0 -1 #$$$%#&('((-($)#*#+$,$-$.-.$ 21 -1 0 4 4 UIParent 0.0 -359.5 -1 ##%#&#'7())#*-*$+#,&-#.#/-0#1# 22 0 0 0 0 UIParent 1475.8 -2.0 -1 #$$$%#&('((#)U*$+%,$-#.#/U0% 22 1 0 4 4 UIParent 0.0 328.0 -1 &('()U*#+% 22 2 0 4 4 UIParent 0.0 285.0 -1 &('()U*#+% 22 3 0 4 4 UIParent 0.0 245.0 -1 &('()U*#+% 23 -1 1 0 0 UIParent 0.0 0.0 -1 ##$#%$&-&$'7(%)U+$,$-$.(/U 24 -1 0 4 4 UIParent 0.0 0.0 -1 # 26 -1 1 4 4 UIParent 0.0 0.0 -1 #("

-- C_EditMode.GetLayouts().layouts holds ONLY the custom layouts (dense from
-- 1), but the client's layout index space — activeLayout, SetActiveLayout,
-- OnLayoutAdded/OnLayoutDeleted — counts the preset layouts first: Blizzard's
-- manager prepends Enum.EditModePresetLayoutsMeta.NumValues preset copies to
-- the same array before indexing it. Custom array position i therefore maps
-- to client index i + NumValues; without the offset OnLayoutAdded activates a
-- preset instead.
local function PresetCount()
    local meta = Enum.EditModePresetLayoutsMeta
    return (meta and meta.NumValues) or 2
end

-- Mutation flow mirrors EditModeManagerFrameMixin:MakeNewLayout/DeleteLayout
-- (Blizzard source): change the table, SaveLayouts, then notify via
-- OnLayoutAdded/OnLayoutDeleted so the client refreshes. An existing
-- "Nocturne" layout is deleted first so repeat clicks update in place
-- instead of stacking copies.
function ns:ApplyEditModeLayout()
    if InCombatLockdown() then
        Nocturne.Print("Extra: cannot change the Edit Mode layout in combat.")
        return
    end
    local info = C_EditMode.ConvertStringToLayoutInfo(LAYOUT_STRING)
    if not info then
        Nocturne.Print("Extra: failed to decode the bundled layout string.")
        return
    end
    info.layoutName = LAYOUT_NAME
    info.layoutType = Enum.EditModeLayoutType.Character

    local offset = PresetCount()
    local layouts = C_EditMode.GetLayouts()
    for i = #layouts.layouts, 1, -1 do
        if layouts.layouts[i].layoutName == LAYOUT_NAME then
            table.remove(layouts.layouts, i)
            if layouts.activeLayout == i + offset then
                layouts.activeLayout = 1
            end
            C_EditMode.SaveLayouts(layouts)
            C_EditMode.OnLayoutDeleted(i + offset)
        end
    end
    tinsert(layouts.layouts, info)
    local index = #layouts.layouts + offset
    layouts.activeLayout = index
    C_EditMode.SaveLayouts(layouts)
    C_EditMode.OnLayoutAdded(index, true, true)
    C_EditMode.SetActiveLayout(index)
    Nocturne.Print(("Extra: '%s' Edit Mode layout applied."):format(LAYOUT_NAME))
end
