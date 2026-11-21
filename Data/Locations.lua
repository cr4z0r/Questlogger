-- Resolves quest tags, map coordinates and waypoints.
local _, addon = ...
local Data = addon.Data
local L = addon.L
local Compat = addon.Compat
local helpers = Data.Helpers
local call = Data.Call
local clean, positive, asTable = helpers.clean, helpers.positive, helpers.tab
local database, field, support = helpers.db, helpers.field, helpers.support

local areaToMapID, parentAreas, instanceAreas, zonesLoaded
local raidAreas = {
    [1977] = true,
    [2159] = true,
    [2677] = true,
    [2717] = true,
    [3428] = true,
    [3429] = true,
    [3456] = true,
    [3457] = true,
    [3805] = true,
    [3607] = true,
    [3845] = true,
    [3923] = true,
    [3606] = true,
    [4075] = true,
    [4493] = true,
    [4500] = true,
    [4273] = true,
    [4722] = true,
    [4812] = true,
    [4987] = true,
}

-- ZoneDB includes these non-dungeon records in its instance collection.
local excludedInstanceAreas = {
    [2257] = true,
    [2597] = true,
    [3277] = true,
    [3358] = true,
    [3820] = true,
    [4384] = true,
    [4710] = true,
}

-- Support tables may be already decoded or stored as serialized Lua data.
local function decodeZoneTable(value)
    if type(value) == 'table' then
        return value
    end
    if type(value) == 'string' and loadstring then
        local fn = loadstring(value)
        if not fn then
            fn = loadstring('return ' .. value)
        end
        return asTable(call(fn))
    end
    return {}
end

local function loadZoneData()
    if zonesLoaded then
        return
    end
    local zoneDatabase = support('ZoneDB')
    if not zoneDatabase then
        return
    end
    local private = zoneDatabase.private or {}
    areaToMapID = decodeZoneTable(private.areaIdToUiMapId)
    parentAreas = decodeZoneTable(private.subZoneToParentZone or zoneDatabase.subZoneToParentZone)
    instanceAreas = {}
    for areaID, row in pairs(asTable(private.dungeons or zoneDatabase.dungeons)) do
        if type(row) == 'table' and not excludedInstanceAreas[areaID] then
            local record = { kind = raidAreas[areaID] and 'raid' or 'dungeon', entrances = row[4] }
            if type(areaID) == 'number' then
                instanceAreas[areaID] = record
            end
            for _, alternateAreaID in ipairs(asTable(row[2])) do
                instanceAreas[alternateAreaID] = record
            end
        end
    end
    zonesLoaded = true
end

function Data.MapID(area)
    loadZoneData()
    local seen = {}
    while positive(area) and not seen[area] do
        seen[area] = true
        local mapID = areaToMapID and areaToMapID[area]
        if positive(mapID) and call(C_Map and C_Map.GetMapInfo, mapID) then
            return mapID
        end
        area = parentAreas and parentAreas[area]
    end
end

function Data.InstanceKind(questID, area)
    local tag = Compat.GetQuestTagInfo(questID)
    local tagID = type(tag) == 'table' and clean(tag.tagID)
    if tagID == 62 or tagID == 88 or tagID == 89 then
        return 'raid'
    end
    if tagID == 81 or tagID == 85 then
        return 'dungeon'
    end
    loadZoneData()
    if instanceAreas and instanceAreas[area] then
        return instanceAreas[area].kind
    end
    -- Use known instance zones for quests without a client tag.
    local mapID = positive(area) and Data.MapID(area)
    local info = mapID and call(C_Map and C_Map.GetMapInfo, mapID)
    if info and Enum and Enum.UIMapType and info.mapType == Enum.UIMapType.Dungeon then
        return 'dungeon'
    end
end

-- Prefer localized client tags over database inference.
function Data.PlainTag(text)
    if type(text) ~= 'string' then
        return nil
    end
    text = text:gsub('|c%x%x%x%x%x%x%x%x', ''):gsub('|r', ''):gsub('|T.-|t', ''):gsub('|A.-|a', '')
    text = text:match('^%s*(.-)%s*$')
    text = text:match('^%((.-)%)$') or text
    text = text:match('^%s*(.-)%s*$')
    return text ~= '' and text or nil
end
local categoryNames = {
    [1] = L['Elite'],
    [41] = L['PvP'],
    [62] = L['Raid'],
    [81] = L['Dungeon'],
    [83] = L['Legendary'],
    [85] = L['Heroic'],
    [88] = L['Raid (10)'],
    [89] = L['Raid (25)'],
}

function Data.QuestCategory(questID, displayedTag)
    local tag = Data.PlainTag(displayedTag)
        or Data.PlainTag(call(QuestUtilsOverrides and QuestUtilsOverrides.GetQuestTagText, questID))
    if tag then
        return tag
    end
    local tagInfo = asTable(Compat.GetQuestTagInfo(questID))
    local tagID = clean(tagInfo.tagID)
    if tagID == 1 then
        return L['Elite']
    end
    tag = Data.PlainTag(clean(tagInfo.tagName)) or categoryNames[tagID]
    if tag then
        return tag
    end
    local legacyID, legacyName = call(GetQuestTagInfo, questID)
    if legacyID == 1 then
        return L['Elite']
    end
    tag = Data.PlainTag(legacyName) or categoryNames[legacyID]
    if tag then
        return tag
    end
    local library = database()
    local kind = Data.InstanceKind(questID, field(library and library.Quest, 'zoneOrSort', questID))
    if kind then
        return kind == 'raid' and L['Raid'] or L['Dungeon']
    end
end

-- Reuse map lookups for both quest endpoints.
function Data.Locations(questID, isStart)
    local library = database()
    if not library then
        return {}
    end
    local groups = asTable(field(library.Quest, isStart and 'startedBy' or 'finishedBy', questID))
    local locations, seen = {}, {}
    local function appendLocation(name, spawns, kind, entityID, nameUnavailable)
        local found = false
        for area, points in pairs(asTable(spawns)) do
            local mapID = Data.MapID(area)
            local info = mapID and call(C_Map.GetMapInfo, mapID)
            for _, point in ipairs(asTable(points)) do
                local x, y = point[1], point[2]
                if
                    info
                    and type(x) == 'number'
                    and type(y) == 'number'
                    and x >= 0
                    and x <= 100
                    and y >= 0
                    and y <= 100
                then
                    local key = name .. ':' .. mapID .. ':' .. x .. ':' .. y
                    if not seen[key] then
                        seen[key] = true
                        found = true
                        locations[#locations + 1] = {
                            name = name,
                            kind = kind,
                            id = entityID,
                            nameUnavailable = nameUnavailable,
                            mapID = mapID,
                            zone = info.name,
                            x = x / 100,
                            y = y / 100,
                        }
                    end
                end
            end
            local instance = instanceAreas and instanceAreas[area]
            if instance and not found then
                -- An instance entrance is useful when its interior has no usable map.
                for _, entrance in ipairs(asTable(instance.entrances)) do
                    local entranceMapID = Data.MapID(entrance[1])
                    local entranceInfo = entranceMapID and call(C_Map.GetMapInfo, entranceMapID)
                    if entranceInfo and type(entrance[2]) == 'number' and type(entrance[3]) == 'number' then
                        local key = name .. ':entrance:' .. entranceMapID .. ':' .. entrance[2] .. ':' .. entrance[3]
                        if not seen[key] then
                            seen[key] = true
                            found = true
                            locations[#locations + 1] = {
                                name = L.Format('%s (instance entrance)', name),
                                kind = kind,
                                id = entityID,
                                nameUnavailable = nameUnavailable,
                                mapID = entranceMapID,
                                zone = entranceInfo.name,
                                x = entrance[2] / 100,
                                y = entrance[3] / 100,
                            }
                        end
                    end
                end
            end
        end
        if not found then
            locations[#locations + 1] = { name = name, kind = kind, id = entityID, nameUnavailable = nameUnavailable }
        end
    end
    for entityIndex, entity in ipairs({ library.Npc or {}, library.Object or {}, library.Item or {} }) do
        for _, id in ipairs(asTable(groups[entityIndex])) do
            local kind = ({ 'npc', 'object', 'item' })[entityIndex]
            local name, localized = Data.EntityName(kind, id)
            name = name or L.Format(entityIndex == 1 and 'NPC %s' or entityIndex == 2 and 'Object %s' or 'Item %s', id)
            appendLocation(name, field(entity, 'spawns', id), kind, id, kind == 'npc' and not localized)
        end
    end
    if not isStart and #locations == 0 then
        local trigger = field(library.Quest, 'triggerEnd', questID)
        if type(trigger) == 'table' and trigger[1] then
            appendLocation(trigger[1], trigger[2])
        end
    end
    local currentMap = call(C_Map and C_Map.GetBestMapForUnit, 'player')
    table.sort(locations, function(first, second)
        local firstPriority, secondPriority =
            first.mapID and (first.mapID == currentMap and 0 or 1) or 2,
            second.mapID and (second.mapID == currentMap and 0 or 1) or 2
        if firstPriority ~= secondPriority then
            return firstPriority < secondPriority
        end
        if first.name ~= second.name then
            return first.name < second.name
        end
        if first.mapID ~= second.mapID then
            return (first.mapID or 0) < (second.mapID or 0)
        end
        if first.x ~= second.x then
            return (first.x or 0) < (second.x or 0)
        end
        return (first.y or 0) < (second.y or 0)
    end)
    return locations
end

function Data.PinIssue(location)
    if not location.mapID then
        return L['Map pin unavailable: no coordinates for this location.']
    end
    if not C_Map or not C_Map.SetUserWaypoint or not UiMapPoint or not UiMapPoint.CreateFromCoordinates then
        return L['Map pins are not supported by this client.']
    end
    if C_Map.CanSetUserWaypointOnMap and call(C_Map.CanSetUserWaypointOnMap, location.mapID) == false then
        return L['Map pins are not supported on this map.']
    end
end

function Data.Pin(location)
    if InCombatLockdown() or not location.mapID then
        return false
    end
    if not C_Map or not C_Map.SetUserWaypoint or not UiMapPoint or not UiMapPoint.CreateFromCoordinates then
        return false
    end
    if C_Map.CanSetUserWaypointOnMap and not call(C_Map.CanSetUserWaypointOnMap, location.mapID) then
        return false
    end
    local point = call(UiMapPoint.CreateFromCoordinates, location.mapID, location.x, location.y)
    if not point then
        return false
    end
    local ok = pcall(C_Map.SetUserWaypoint, point)
    if ok and WorldMapFrame then
        pcall(WorldMapFrame.SetMapID, WorldMapFrame, location.mapID)
    end
    return ok
end

-- Open the map first: the map's OnShow may otherwise replace the selected zone.
function Data.OpenLocationMap(location)
    if not location or not location.mapID or (InCombatLockdown and InCombatLockdown()) then
        return false
    end
    local map = WorldMapFrame
    if not map or not map.SetMapID then
        return false
    end
    if not map:IsShown() then
        if ToggleWorldMap then
            pcall(ToggleWorldMap)
        end
        if not map:IsShown() and ShowUIPanel then
            pcall(ShowUIPanel, map)
        end
    end
    if not map:IsShown() then
        return false
    end
    -- Use Blizzard's windowed map mode, not a custom frame size. OnShow can
    -- restore the fullscreen preference, so minimize before selecting the zone.
    if call(map.IsMaximized, map) ~= false then
        local control = map.BorderFrame and map.BorderFrame.MaximizeMinimizeFrame
        local minimized = control and type(control.Minimize) == 'function' and pcall(control.Minimize, control)
        if (not minimized or call(map.IsMaximized, map) == true) and type(map.Minimize) == 'function' then
            pcall(map.Minimize, map)
        end
    end
    return pcall(map.SetMapID, map, location.mapID)
end
