local ADDON_NAME = ...

Nocturne = _G.Nocturne or {}
Nocturne.VERSION = "0.1.0"
Nocturne.modules = Nocturne.modules or {}

local CHAT_PREFIX = "|cffb7a8e8Nocturne|r"
local DEBUG_PREFIX = "|cff8a84a8NocturneDBG|r"

function Nocturne.Print(...)
    print(CHAT_PREFIX .. ":", ...)
end

function Nocturne.Debug(...)
    if Nocturne.db and Nocturne.db.debug then
        print(DEBUG_PREFIX, ...)
    end
end

-- Midnight (12.0): some values may be "secret" on tainted paths.
Nocturne.IsSecret = _G.issecretvalue or function() return false end

-- Truthiness of a possibly-secret flag: secret counts as false.
function Nocturne.Flag(v)
    return not Nocturne.IsSecret(v) and v and true or false
end

-- WoW Forever runs the Mainline engine (WOW_PROJECT_ID 1) on interface
-- 16xxx; the build number is the only flavor signal it exposes.
local interface = select(4, GetBuildInfo())
Nocturne.IS_FOREVER = interface >= 16000 and interface < 17000

function Nocturne.RegisterModule(name, module)
    Nocturne.modules[name] = module
    return module
end

-- Shared SavedVariables defaults merge: fills missing keys in `dst` with
-- `src`'s values, deep-copying tables. Call from ADDON_LOADED only.
function Nocturne.MergeDefaults(dst, src)
    for k, v in pairs(src) do
        if dst[k] == nil then
            dst[k] = type(v) == "table" and Nocturne.MergeDefaults({}, v) or v
        end
    end
    return dst
end

-- Shared event bus: every module subscribes to game events through a single
-- hidden frame instead of creating its own.
local bus = CreateFrame("Frame")
local listeners = {}
local IsEventValid = C_EventUtils and C_EventUtils.IsEventValid

bus:SetScript("OnEvent", function(_, event, ...)
    local list = listeners[event]
    if not list then return end
    for i = 1, #list do
        list[i](event, ...)
    end
end)

function Nocturne.RegisterEvent(event, fn)
    -- RegisterEvent errors on events the client doesn't know; skip them so
    -- one renamed/removed event can't break the whole addon.
    if IsEventValid and not IsEventValid(event) then
        Nocturne.Debug("unknown event", event)
        return
    end
    local list = listeners[event]
    if not list then
        list = {}
        listeners[event] = list
        bus:RegisterEvent(event)
    end
    list[#list + 1] = fn
end

-- SavedVariables are only populated by the client right before ADDON_LOADED
-- fires for this addon — reading them at file-load time always sees nil and
-- gets clobbered once the real data loads. Defer until then.
Nocturne.RegisterEvent("ADDON_LOADED", function(_, loadedAddon)
    if loadedAddon ~= ADDON_NAME then return end
    NocturneDB = _G.NocturneDB or {}
    Nocturne.db = NocturneDB
end)
