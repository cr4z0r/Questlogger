-- Bind quest-bearing map markers without replacing native pin or tooltip handlers.
local _, addon = ...
local Compat, UI = addon.Compat, addon.UI
local MapQuestCards = {}
UI.MapQuestCards = MapQuestCards

local boundPins = setmetatable({}, { __mode = 'k' })
local boundMaps = setmetatable({}, { __mode = 'k' })
local hookedQuestieTooltips = setmetatable({}, { __mode = 'k' })
local refreshing = false
local templates = {
    'QuestPinTemplate',
    'QuestOfferPinTemplate',
    'WorldQuestPinTemplate',
    'BonusObjectivePinTemplate',
    'ThreatObjectivePinTemplate',
}

local function accessible(frame)
    if not frame or (type(frame) ~= 'table' and type(frame) ~= 'userdata') then
        return false
    end
    return type(frame.IsForbidden) ~= 'function' or Compat.Call(frame.IsForbidden, frame) == false
end

local function questID(value)
    return Compat.IsReadable(value)
            and type(value) == 'number'
            and value > 0
            and value < math.huge
            and value == math.floor(value)
            and value
        or nil
end

local function mapVisible()
    return accessible(WorldMapFrame) and Compat.Call(WorldMapFrame.IsVisible, WorldMapFrame) == true
end

local function nativeQuestID(pin)
    if not accessible(pin) or not mapVisible() then
        return
    end
    if type(pin.GetMap) == 'function' and Compat.Call(pin.GetMap, pin) ~= WorldMapFrame then
        return
    end
    return questID(Compat.Call(pin.GetQuestID, pin)) or questID(pin.questID)
end

local function questieQuestID(pin)
    if not accessible(pin) or not mapVisible() or pin.miniMapIcon or pin.isManualIcon then
        return
    end
    local data = pin.data
    if type(data) ~= 'table' or data.Type == 'manual' then
        return
    end
    return questID(data.Id)
end

local function showCard(pin, resolve)
    if Compat.InCombat() or not accessible(pin) or not addon.ShowMapQuest then
        return
    end
    local id = resolve(pin)
    if id then
        return addon.ShowMapQuest(pin, id, resolve)
    end
end

local function bindPin(pin, resolve)
    if Compat.InCombat() or not accessible(pin) or type(pin.HookScript) ~= 'function' then
        return
    end
    local binding = boundPins[pin]
    if binding then
        binding.resolve = resolve
        return
    end
    binding = { resolve = resolve }
    boundPins[pin] = binding
    pin:HookScript('OnEnter', function(self)
        showCard(self, binding.resolve)
    end)
    pin:HookScript('OnHide', function(self)
        UI.HideMapCard(self)
    end)
end

local function bindTemplate(map, template)
    if type(map.EnumeratePinsByTemplate) ~= 'function' then
        return
    end
    -- Some client flavors do not create every pin pool. A missing pool is optional.
    pcall(function()
        for pin in map:EnumeratePinsByTemplate(template) do
            bindPin(pin, nativeQuestID)
        end
    end)
end

local function questTemplate(template)
    for _, supported in ipairs(templates) do
        if template == supported then
            return true
        end
    end
    return false
end

local function importQuestieModule(name)
    if QuestieLoader and type(QuestieLoader.ImportModule) == 'function' then
        return Compat.Call(QuestieLoader.ImportModule, QuestieLoader, name)
    end
end

local function bindQuestie()
    local tooltipModule = importQuestieModule('MapIconTooltip')
    if
        type(tooltipModule) == 'table'
        and type(tooltipModule.ShowOnTooltip) == 'function'
        and type(hooksecurefunc) == 'function'
        and not hookedQuestieTooltips[tooltipModule]
    then
        -- Existing icons retain a reference to Show; it calls this module method
        -- dynamically, so this hook also reaches already-created Questie icons.
        local ok = pcall(hooksecurefunc, tooltipModule, 'ShowOnTooltip', function(pin, tooltip, owner)
            if Compat.InCombat() or owner ~= nil or not questieQuestID(pin) then
                return
            end
            bindPin(pin, questieQuestID)
            local shown = showCard(pin, questieQuestID)
            if shown and tooltip and type(tooltip.Hide) == 'function' then
                tooltip:Hide()
            end
        end)
        hookedQuestieTooltips[tooltipModule] = ok
    end

    local mapModule = importQuestieModule('QuestieMap')
    local quests = type(mapModule) == 'table' and mapModule.questIdFrames
    for _, frames in pairs(type(quests) == 'table' and quests or {}) do
        for name, value in pairs(type(frames) == 'table' and frames or {}) do
            local pin = accessible(value) and value or type(name) == 'string' and _G[name]
            if accessible(pin) then
                bindPin(pin, questieQuestID)
            end
        end
    end
end

function MapQuestCards.Refresh()
    if refreshing or Compat.InCombat() or not mapVisible() then
        return
    end
    refreshing = true
    for _, template in ipairs(templates) do
        bindTemplate(WorldMapFrame, template)
    end
    bindQuestie()
    refreshing = false
end

function MapQuestCards.Install()
    local map = WorldMapFrame
    if Compat.InCombat() or not accessible(map) then
        return
    end
    if not boundMaps[map] then
        boundMaps[map] = true
        if type(map.HookScript) == 'function' then
            map:HookScript('OnShow', MapQuestCards.Refresh)
            map:HookScript('OnHide', function()
                UI.HideMapCard()
            end)
        end
        if type(hooksecurefunc) == 'function' and type(map.AcquirePin) == 'function' then
            hooksecurefunc(map, 'AcquirePin', function(_, template)
                if questTemplate(template) then
                    -- Providers assign or recycle IDs after acquiring a pin.
                    -- Only bind here; resolve the current ID at hover time.
                    bindTemplate(map, template)
                end
            end)
        end
    end
    MapQuestCards.Refresh()
end

function MapQuestCards.Disable()
    UI.HideMapCard()
end
