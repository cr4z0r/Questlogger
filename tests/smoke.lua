local F = dofile('tests/load.lua')
local C, D = F.Core, F.Data
local rows =
    { [1] = {}, [2] = { single = { 1 } }, [3] = { single = { 2 } }, [4] = {}, [5] = { group = { 3, 4 } }, [6] = {
        single = { 5 },
    } }
local function done()
    return false
end
local graph = C.NewGraph(function(id)
    return rows[id]
end, { 1, 2, 3, 4, 5, 6 }, function()
    return true
end)
assert(C.QuestXPText(1234) == '1,234 XP')
assert(C.QuestXPText(0) == 'no XP')
assert(C.QuestXPText(nil) == 'unknown XP')
assert(C.StepText(graph, 1, C.Routes(graph, 1, done)) == '1-2/6')
assert(C.StepText(graph, 2, C.Routes(graph, 2, done)) == '2-3/6')
assert(C.StepText(nil, 2, { status = 'loading' }) == '?/?')
local function step(g, n, completed)
    return C.StepText(g, n, C.Routes(g, n, completed or done))
end
assert(step(graph, 3) == '3-4/6' and step(graph, 4) == '1-4/6')
assert(step(graph, 5) == '5/6' and step(graph, 6) == '6/6')
local linear = C.NewGraph(function(n)
    return n == 1 and {} or { single = { n - 1 } }
end, { 1, 2, 3, 4, 5, 6 }, function()
    return true
end)
for n = 1, 6 do
    assert(step(linear, n) == n .. '/6')
    assert(step(linear, n, function(q)
        return q < n
    end) == n .. '/6')
end
local split = C.NewGraph(function(n)
    return ({ [1] = {}, [2] = { single = { 1 } }, [3] = { single = { 1 } }, [4] = { single = { 3 } } })[n]
end, { 1, 2, 3, 4 }, function()
    return true
end)
assert(step(split, 1) == '1/2-3' and step(split, 2) == '2/2' and step(split, 4) == '3/3')
local missing = C.NewGraph(function(n)
    return n == 1 and { single = { 99 } } or { single = { 1 } }
end, { 1, 2 }, function()
    return true
end)
assert(step(missing, 1) == '?/?' and step(missing, 2) == '?/?')
local cycle = C.NewGraph(function(n)
    return { single = { 3 - n } }
end, { 1, 2 }, function()
    return true
end)
assert(step(cycle, 1) == '?/?')

local two = C.NewGraph(function(id)
    return id == 2 and { single = { 1 } } or {}
end, { 1, 2, 3 }, function()
    return true
end)
assert(C.StepText(two, 1, C.Routes(two, 1, done)) == '1/2')
assert(C.StepText(two, 2, C.Routes(two, 2, done)) == '2/2')
assert(C.StepText(two, 3, C.Routes(two, 3, done)) == '1/1')
assert(table.concat(C.Future(graph, 1, done), ',') == '2,3,5,6')
assert(table.concat(
    C.Future(graph, 1, function(id)
        return id == 2
    end),
    ','
) == '3,5,6')
local secret = {}
issecretvalue = function(v)
    return v == secret
end
local a, b, c = D.Call(function()
    return 1, secret, 3
end)
assert(a == 1 and b == nil and c == 3)
C_QuestLog = {
    HaveQuestData = function()
        return true
    end,
    GetQuestTagInfo = function(id)
        if id == 3 then
            return { tagID = 62 }
        end
    end,
}
C_Map = {
    GetMapInfo = function(id)
        if id == 42 then
            return { name = 'Test Zone', mapType = 3 }
        end
    end,
    GetBestMapForUnit = function()
        return 42
    end,
    CanSetUserWaypointOnMap = function()
        return true
    end,
    SetUserWaypoint = function(pt)
        assert(pt.x == 0.5)
        _G.pinned = true
    end,
}
UiMapPoint = {
    CreateFromCoordinates = function(map, x, y)
        return { map = map, x = x, y = y }
    end,
}
InCombatLockdown = function()
    return false
end
LibQuestieDB = {
    Support = {
        Get = function()
            return {
                private = {
                    areaIdToUiMapId = 'return {[12]=42}',
                    dungeons = { [1977] = { 'Raid', nil, 12, { { 12, 20, 30 } } }, [718] = {
                        'Dungeon',
                        { 719 },
                        12,
                        { { 12, 25, 35 } },
                    } },
                },
            }
        end,
    },
    Quest = {
        startedBy = function()
            return { { 10 } }
        end,
        finishedBy = function()
            return {}
        end,
        triggerEnd = function()
            return { 'End', { [12] = { { 60, 70 } } } }
        end,
    },
    Npc = {
        name = function()
            return 'Giver'
        end,
        spawns = function()
            return { [12] = { { 50, 20 } } }
        end,
    },
    Item = {},
    Object = {},
}
loadstring = loadstring or load
assert(D.InstanceKind(3, 0) == 'raid')
assert(D.InstanceKind(2, 1977) == 'raid')
assert(D.InstanceKind(2, 719) == 'dungeon')
assert(not D.InstanceKind(2, 12))
local locs = D.Locations(1, true)
assert(#locs == 1 and locs[1].x == 0.5 and locs[1].mapID == 42 and locs[1].kind == 'npc' and locs[1].id == 10)
assert(D.Pin(locs[1]) and pinned)
assert(D.Locations(1, false)[1].name == 'End')
-- Map opening is independent of pin capability and selects the zone after OnShow.
WorldMapFrame = {
    shown = false,
    IsShown = function(self)
        return self.shown
    end,
    SetMapID = function(self, id)
        self.mapID = id
    end,
}
function WorldMapFrame:IsMaximized()
    return self.maximized
end
local minimized = 0
WorldMapFrame.BorderFrame = {
    MaximizeMinimizeFrame = {
        Minimize = function()
            minimized = minimized + 1
            WorldMapFrame.maximized = false
            WorldMapFrame.mapID = 2
        end,
    },
}
ToggleWorldMap = function()
    WorldMapFrame.shown = true
    WorldMapFrame.mapID = 1
    WorldMapFrame.maximized = true
end
C_Map.CanSetUserWaypointOnMap = function()
    return false
end
assert(D.PinIssue(locs[1]) and not D.Pin(locs[1]))
assert(
    D.OpenLocationMap(locs[1])
        and WorldMapFrame.shown
        and WorldMapFrame.mapID == 42
        and not WorldMapFrame.maximized
        and minimized == 1
)
assert(not D.OpenLocationMap({ name = 'Unknown' }))
assert(D.OpenLocationMap({ mapID = 43 }) and WorldMapFrame.mapID == 43 and minimized == 1)
WorldMapFrame.maximized = true
assert(
    D.OpenLocationMap({ mapID = 44 }) and not WorldMapFrame.maximized and WorldMapFrame.mapID == 44 and minimized == 2
)
WorldMapFrame.BorderFrame = nil
WorldMapFrame.maximized = true
function WorldMapFrame:Minimize()
    self.maximized = false
end
assert(D.OpenLocationMap({ mapID = 45 }) and not WorldMapFrame.maximized and WorldMapFrame.mapID == 45)
WorldMapFrame, ToggleWorldMap = nil, nil
C_Map.CanSetUserWaypointOnMap = function()
    return true
end

GetNumQuestLogRewards = function(id)
    assert(id == 1)
    return 1
end
GetNumQuestLogChoices = function(id)
    assert(id == 1)
    return 1
end
GetQuestLogRewardInfo = function(i, id)
    return 'Sword', 123, 1, 2, true, 100
end
GetQuestLogChoiceInfo = function(i, id)
    return 'Shield', 456, 1, 3, true, 101
end
GetQuestLogItemLink = function(t, i, id)
    return 'item:' .. id
end
C_QuestInfoSystem = {
    GetQuestRewardSpells = function()
        return { 500 }
    end,
    GetQuestRewardSpellInfo = function()
        return { name = 'Spell', texture = 12 }
    end,
    GetQuestRewardCurrencies = function()
        return { { currencyID = 7, name = 'Currency', totalRewardAmount = 5 }, { currencyID = 8, name = 'Rep' } }
    end,
}
C_CurrencyInfo = {
    GetFactionGrantedByCurrency = function(id)
        if id == 8 then
            return 1
        end
    end,
}
GetQuestLogRewardTitle = function()
    return 'Champion'
end
local rewards, pending = D.Rewards(1)
assert(#rewards == 5 and not pending)
assert(rewards[1].id == 100 and rewards[2].choice and rewards[3].id == 7 and rewards[4].kind == 'spell')
-- Check scalar reward sources without changing quest selection.
GetQuestLogRewardMoney = function(id)
    assert(id == 1)
    return 12345
end
C_Reputation = {
    GetFactionDataByID = function(id)
        return { name = 'Faction ' .. id }
    end,
}
C_QuestLog.GetSelectedQuest = function()
    return 2
end
C_QuestLog.GetQuestLogMajorFactionReputationRewards = function(qid)
    assert(qid == 1)
    return { { factionID = 2, rewardAmount = 200 } }
end
C_QuestInfoSystem.GetQuestRewardCurrencies = function()
    return { { currencyID = 7, totalRewardAmount = 5 }, { currencyID = 8, name = 'Rep', totalRewardAmount = 250 } }
end
LibQuestieDB.Quest.reputationReward = function(id)
    assert(id == 1)
    return { { 1, 100 }, { 2, 100 }, { 3, 37.5 }, { 4, -50 } }
end
ProcessQuestLogRewardFactions = function()
    error('Must not process other selected quests')
end
local money, rep, repPending = D.CardRewards(1)
assert(money == 12345 and #rep == 4 and not repPending)
local byID = {}
for _, r in ipairs(rep) do
    byID[r.id] = r
end
assert(
    byID[1].amount == 250
        and not byID[1].estimated
        and byID[2].amount == 200
        and not byID[2].estimated
        and byID[3].amount == 37.5
        and byID[3].estimated
        and byID[4].amount == -50
)
local selected = 1
C_QuestLog.GetSelectedQuest = function()
    return selected
end
ProcessQuestLogRewardFactions = function()
    assert(selected == 1)
end
GetNumQuestLogRewardFactions = function()
    return 1
end
GetQuestLogRewardFactionInfo = function(i)
    assert(i == 1)
    return 3, 75
end
money, rep, repPending = D.CardRewards(1)
byID = {}
for _, r in ipairs(rep) do
    byID[r.id] = r
end
assert(byID[3].amount == 75 and not byID[3].estimated and not repPending and selected == 1)
-- Keep scalar rewards out of the quest-log icon strip.
rewards, pending = D.Rewards(1)
assert(#rewards == 5 and not pending)
C_QuestLog.HaveQuestData = function()
    return false
end
GetQuestLogRewardMoney = function()
    return 0
end
money, rep, repPending = D.CardRewards(1)
assert(money == nil and repPending)
-- A known item count with missing item data is pending, not empty.
C_QuestLog.HaveQuestData = function()
    return true
end
local originalReward = GetQuestLogRewardInfo
GetQuestLogRewardInfo = function() end
local partial, waiting = D.Rewards(1)
assert(#partial == 4 and waiting)
GetQuestLogRewardInfo = originalReward
print('Core, rewards, instance classification, locations and waypoint smoke tests passed.')
