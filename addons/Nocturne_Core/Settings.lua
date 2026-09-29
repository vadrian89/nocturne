local Nocturne = _G.Nocturne

-- Shared builder over the native Settings API: every control is bound to a
-- key in the addon's SavedVariables table and calls `onChange` on edit.
local Builder = {}
Builder.__index = Builder

function Nocturne.NewSettings(title, prefix, db, defaults, onChange)
    return setmetatable({
        category = Settings.RegisterVerticalLayoutCategory(title),
        prefix = prefix,
        db = db,
        defaults = defaults,
        onChange = onChange,
    }, Builder)
end

function Builder:Register(key, name)
    local default = self.defaults[key]
    local setting = Settings.RegisterAddOnSetting(
        self.category, self.prefix .. key, key, self.db, type(default), name, default)
    if self.onChange then setting:SetValueChangedCallback(self.onChange) end
    return setting
end

function Builder:Checkbox(key, name, tooltip)
    Settings.CreateCheckbox(self.category, self:Register(key, name), tooltip)
end

function Builder:Slider(key, name, tooltip, minValue, maxValue, step)
    local options = Settings.CreateSliderOptions(minValue, maxValue, step)
    options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
    Settings.CreateSlider(self.category, self:Register(key, name), options, tooltip)
end

-- `labels` is an array; the stored value is the selected index.
function Builder:Dropdown(key, name, tooltip, labels)
    -- Spelled differently across client branches; guard both.
    local CreateDD = Settings.CreateDropdown or Settings.CreateDropDown
    if not (CreateDD and Settings.CreateControlTextContainer) then return end
    local function GetOptions()
        local c = Settings.CreateControlTextContainer()
        for i, label in ipairs(labels) do c:Add(i, label) end
        return c:GetData()
    end
    CreateDD(self.category, self:Register(key, name), GetOptions, tooltip)
end

-- A plain action button, not bound to any setting.
function Builder:Button(name, buttonText, onClick, tooltip)
    if not (CreateSettingsButtonInitializer and SettingsPanel) then return end
    SettingsPanel:GetLayout(self.category):AddInitializer(
        CreateSettingsButtonInitializer(name, buttonText, onClick, tooltip, true))
end

function Builder:Finish()
    Settings.RegisterAddOnCategory(self.category)
    return self.category
end
