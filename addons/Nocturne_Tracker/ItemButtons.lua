local _, ns = ...

-- Quest item buttons, in a column left of the tracker.
--
-- Using a quest item is protected, so these are SecureActionButtons
-- (type "item"). Secure frames can't be shown, hidden, moved or
-- re-configured in combat, and a frame with protected children becomes
-- protected itself. So they live in their own holder parented to UIParent
-- and are anchored to UIParent with offsets computed from the tracker's
-- saved TOPRIGHT point — never to the tracker frame, which must stay free
-- to resize/hide in combat. Layout changes made in combat are applied on
-- PLAYER_REGEN_ENABLED; a state driver handles "hide in combat".

local InCombatLockdown = InCombatLockdown
local RegisterStateDriver = RegisterStateDriver
local GetItemCooldown = C_Container and C_Container.GetItemCooldown

local BUTTON_GAP = 4                    -- gap between the column and the tracker

local holder = CreateFrame("Frame", "NocturneTrackerItemHolder", UIParent)
holder:SetFrameStrata("LOW")
holder:SetAllPoints()
local buttons = {}
local driverState

local function OnEnter(self)
    if not self.link then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetHyperlink(self.link)
    GameTooltip:Show()
end

local function Acquire(i)
    local b = buttons[i]
    if not b then
        b = CreateFrame("Button", nil, holder, "SecureActionButtonTemplate")
        -- Secure action buttons fire on key-down or key-up depending on
        -- the ActionButtonUseKeyDown CVar; register both.
        b:RegisterForClicks("AnyUp", "AnyDown")
        b:SetAttribute("type", "item")
        b.bg = b:CreateTexture(nil, "BACKGROUND")
        b.bg:SetPoint("TOPLEFT", -1, 1)
        b.bg:SetPoint("BOTTOMRIGHT", 1, -1)
        b.bg:SetColorTexture(0, 0, 0, 0.8)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetAllPoints()
        b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        b.cooldown = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
        b.cooldown:SetAllPoints()
        b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        b.count:SetPoint("BOTTOMRIGHT", -1, 1)
        b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        b:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
        b:SetScript("OnEnter", OnEnter)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        buttons[i] = b
    end
    return b
end

local function UpdateCooldowns()
    if not GetItemCooldown then return end
    for _, b in ipairs(buttons) do
        if b.itemID and b:IsShown() then
            local start, duration, enable = GetItemCooldown(b.itemID)
            if start and duration and not ns.IsSecret(start) and not ns.IsSecret(duration)
                and ns.Flag(enable) and duration > 0 then
                b.cooldown:SetCooldown(start, duration)
            else
                b.cooldown:Clear()
            end
        end
    end
end

local function SetDriver(state)
    if state == driverState then return end
    driverState = state
    RegisterStateDriver(holder, "visibility", state)
end

-- Positions a button next to every visible entry that has a quest item.
-- Called after each rebuild/scroll/drag; deferred while in combat.
function ns:LayoutItems()
    if InCombatLockdown() then
        ns.itemsPending = true
        return
    end
    ns.itemsPending = false

    local db, f = ns.db, ns.frame
    local n = 0
    if db and f and db.showItems and f:IsShown() then
        local size = math.floor(db.fontSize * 1.8 + 0.5)
        local x = db.point[2] - db.width - BUTTON_GAP
        local top0 = db.point[3] - ns.PAD
        local scroll, viewH = ns.scrollOffset or 0, ns.viewH or 0
        for _, e in ipairs(ns.itemEntries) do
            local top = e.y - scroll
            if top >= 0 and top < viewH then
                n = n + 1
                local b = Acquire(n)
                b.itemID, b.link = e.itemID, e.itemLink
                b:SetAttribute("item", "item:" .. e.itemID)
                b.icon:SetTexture(e.itemTexture)
                local charges = e.itemCharges
                b.count:SetText((charges and charges > 1) and charges or "")
                b:SetSize(size, size)
                b:ClearAllPoints()
                b:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", x, top0 - top)
                b:Show()
            end
        end
    end
    for i = n + 1, #buttons do
        buttons[i]:Hide()
        buttons[i].itemID, buttons[i].link = nil, nil
    end
    ns.numItemButtons = n
    SetDriver((n > 0 and db.hideInCombat) and "[combat] hide; show" or "show")
    UpdateCooldowns()
end

_G.Nocturne.RegisterEvent("BAG_UPDATE_COOLDOWN", UpdateCooldowns)
