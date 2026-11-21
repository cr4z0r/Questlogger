-- Shared wrappers for client and database access.
local _, addon = ...
local Data = {}
addon.Data = Data
local Compat = addon.Compat
local L = addon.L
local readable = Compat.IsReadable

local function clean(value)
    if readable(value) then
        return value
    end
end

-- Shared client calls preserve nil/false return positions and filter restricted values.
Data.Call = Compat.Call

local function positive(value)
    return type(value) == 'number' and value > 0
end

local function asTable(value)
    return type(value) == 'table' and value or {}
end

local function database()
    return type(LibQuestieDB) == 'table' and LibQuestieDB or nil
end

-- Explain missing access without making QuestieDB a hard load dependency.
function Data.DatabaseIssue(...)
    local library = database()
    if not library then
        if Compat.IsRetail() then
            return L['Quest chain and location data is unavailable on this client; native quest details remain available.']
        end
        return L['QuestieDB is unavailable. Install or enable QuestieDB, then reload the UI.']
    end

    for index = 1, select('#', ...) do
        local path = select(index, ...)
        local value = library
        for key in path:gmatch('[^.]+') do
            value = type(value) == 'table' and value[key] or nil
        end
        if value == nil then
            return L.Format(
                'QuestieDB does not expose the required data (%s). Update QuestieDB, then reload the UI.',
                path
            )
        end
    end
end

local function field(entity, key, id)
    return entity and Data.Call(entity[key], id)
end

local function support(name)
    local library = database()
    return library and library.Support and Data.Call(library.Support.Get, name)
end

local observedNpcNames = {}
local nameUnits = { 'target', 'mouseover', 'softenemy', 'softfriend', 'softinteract' }
local entityTypes = { npc = 'Npc', object = 'Object', item = 'Item' }

function Data.ObserveUnitName(unit)
    local guid = Data.Call(UnitGUID, unit)
    if type(guid) ~= 'string' then
        return
    end
    local kind, creatureID = guid:match('^(%a+)%-[^-]+%-[^-]+%-[^-]+%-[^-]+%-(%d+)%-')
    if kind ~= 'Creature' and kind ~= 'Vehicle' then
        return
    end
    local id = tonumber(creatureID)
    local name = Data.Call(UnitName, unit)
    if id and type(name) == 'string' and name ~= '' then
        observedNpcNames[id] = name
        return id, name
    end
end

local function observedNpcName(id)
    if observedNpcNames[id] then
        return observedNpcNames[id]
    end
    for _, unit in ipairs(nameUnits) do
        local creatureID, name = Data.ObserveUnitName(unit)
        if creatureID == id then
            return name
        end
    end
end

local function databaseNameMatchesLocale(library, datatype, id)
    local localization = library and library.l10n
    local databaseLocale = localization and localization.currentLocale
    if databaseLocale and databaseLocale ~= L.locale then
        return false
    end
    if L.locale == 'enUS' then
        return true
    end
    if localization and type(localization.GetProvenance) == 'function' then
        return Data.Call(localization.GetProvenance, datatype, id, 'name') ~= nil
    end
    -- QuestieDB has no built-in Italian entity lookup. Older providers otherwise
    -- already localize the named getters for their active client language.
    if L.locale == 'itIT' then
        return false
    end
    if localization and type(localization.IsAvailable) == 'function' then
        return Data.Call(localization.IsAvailable) == true
    end
    return true
end

function Data.EntityName(kind, id)
    if kind == 'npc' then
        local name = observedNpcName(id)
        if name then
            return name, true
        end
    elseif kind == 'item' then
        local name = Data.Call(C_Item and C_Item.GetItemNameByID, id) or Data.Call(GetItemInfo, id)
        if type(name) == 'string' and name ~= '' then
            return name, true
        end
    end
    local library = database()
    local datatype = entityTypes[kind]
    local name = field(datatype and library and library[datatype], 'name', id)
    return name, databaseNameMatchesLocale(library, datatype, id)
end

-- Keep these shared helpers together so data modules use the same API safeguards.
Data.Helpers = {
    readable = readable,
    clean = clean,
    positive = positive,
    tab = asTable,
    db = database,
    field = field,
    support = support,
}
