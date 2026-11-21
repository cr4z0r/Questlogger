-- Boot the real core without QuestieDB, then simulate a late load.
local F = dofile('tests/load.lua')
local event
CreateFrame = function()
    return {
        SetScript = function(_, _, fn)
            event = fn
        end,
        RegisterEvent = function() end,
    }
end
InCombatLockdown = function()
    return false
end
C_Timer = {
    After = function(_, fn)
        fn()
    end,
}
C_QuestLog = {
    GetLogIndexForQuestID = function()
        return 1
    end,
    GetTitleForQuestID = function()
        return 'Quest'
    end,
    HaveQuestData = function()
        return true
    end,
}
GetQuestLogRewardXP = function()
    return 450
end
GetNumQuestLogRewards = function()
    return 0
end
GetNumQuestLogChoices = function()
    return 0
end
LibQuestieDB = nil
local detailHook
QuestMapFrame_ShowQuestDetails = function() end
hooksecurefunc = function(name, fn)
    if name == 'QuestMapFrame_ShowQuestDetails' then
        detailHook = fn
    end
end
assert(loadfile('Core/Main.lua'))('Questlogger', F)
event(nil, 'PLAYER_LOGIN')
local summary = F.GetSummary(1)
assert(summary.listText == '?/? (450 XP)' and summary.chainIssue:find('QuestieDB') and #summary.future == 0)
assert(#F.Data.Locations(1, true) == 0 and #F.Data.Targets(1) == 0)
LibQuestieDB = { Quest = {} }
event(nil, 'ADDON_LOADED', 'QuestieDB')
assert(F.GetSummary(1).chainIssue:find('Quest.GetAllIds', 1, true))
UnitRace = function()
    return 'Human', 'Human', 1
end
UnitClass = function()
    return 'Warrior', 'WARRIOR', 1
end
IsLoggedIn = function()
    return true
end
local empty = function()
    return {}
end
LibQuestieDB.Quest = {
    GetAllIds = function()
        return { 1, 2 }
    end,
    name = function(id)
        return 'Quest ' .. id
    end,
    preQuestSingle = function(id)
        return id == 2 and { 1 } or {}
    end,
    preQuestGroup = empty,
    breadcrumbForQuestId = function() end,
    requiredRaces = function()
        return 0
    end,
    requiredClasses = function()
        return 0
    end,
}
local futureLoaded = false
local requests, reads = 0, 0
C_QuestLog.HaveQuestData = function(id)
    return id ~= 2 or futureLoaded
end
C_QuestLog.RequestLoadQuestByID = function(id)
    assert(id == 2)
    requests = requests + 1
end
GetNumQuestLogRewards = function(id)
    if id == 2 then
        reads = reads + 1
        return futureLoaded and 1 or 0
    end
    return 0
end
GetQuestLogRewardInfo = function(index, id)
    assert(index == 1 and id == 2)
    return 'Reward', 123, 1, 2, true, 100
end
event(nil, 'ADDON_LOADED', 'QuestieDB')
summary = F.GetSummary(1)
assert(summary.listText == '1/2 (450 XP)' and not summary.chainIssue and summary.future[1] == 2)
assert(summary.futureSteps[2] == '2/2')
assert(requests == 1 and reads == 1, 'Quest-log summaries must request follow-up rewards before hovering')
local items, pending = F.Data.FollowupRewards(2)
assert(#items == 0 and pending and reads == 1)
futureLoaded = true
event(nil, 'QUEST_DATA_LOAD_RESULT', 2, true)
items, pending = F.Data.FollowupRewards(2)
assert(#items == 1 and items[1].id == 100 and not pending and reads == 2)
F.GetSummary(1)
assert(reads == 2, 'Known reward data must stay cached across refreshes')
print('Prefetch tests passed: summary, client event, cache reuse.')
print('Dependency tests passed: missing, partial and late-loaded QuestieDB; native XP remains available.')

assert(detailHook, 'Native quest details hook must be installed')
local visible = true
QuestMapFrame = { DetailsFrame = {
    questID = 1,
    IsVisible = function()
        return visible
    end,
} }
local detailCalls = 0
F.UI.ShowDetailsCard = function(panel, id, info, xpFor, questName)
    assert(
        panel == QuestMapFrame.DetailsFrame
            and id == 1
            and info.future[1] == 2
            and xpFor(id) == 450
            and questName(id) == 'Quest 1'
    )
    detailCalls = detailCalls + 1
end
detailHook(1)
assert(detailCalls == 1)
detailHook(2)
visible = false
detailHook(1)
assert(detailCalls == 1)
visible = true
InCombatLockdown = function()
    return true
end
detailHook(1)
assert(detailCalls == 1)
print('Details hook tests passed: selected quest, wrong quest, hidden panel and combat guard.')
