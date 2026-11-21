-- Normalize quest APIs without replacing Blizzard globals or assuming a whole namespace exists.
local _, addon = ...
local Compat = {}
addon.Compat = Compat
local unpackValues = unpack or table.unpack
local classicLevelCaps = { [1] = 60, [2] = 70, [3] = 80, [5] = 90 }

function Compat.IsReadable(value)
    return not (issecretvalue and issecretvalue(value))
end

local function clean(value)
    if Compat.IsReadable(value) then
        return value
    end
end

local function cleanResults(ok, ...)
    if not ok then
        return
    end
    local function unpackClean(index, count, ...)
        if index > count then
            return
        end
        return clean(select(index, ...)), unpackClean(index + 1, count, ...)
    end
    return unpackClean(1, select('#', ...), ...)
end

function Compat.Call(callback, ...)
    if type(callback) == 'function' then
        return cleanResults(pcall(callback, ...))
    end
end

local function positive(value)
    return Compat.IsReadable(value) and type(value) == 'number' and value > 0
end

function Compat.GetClientInterface()
    local _, _, _, interface = Compat.Call(GetBuildInfo)
    if type(interface) == 'string' then
        interface = tonumber(interface)
    end
    return type(interface) == 'number' and interface or nil
end

function Compat.IsRetail()
    local interface = Compat.GetClientInterface()
    -- Forever shares Retail's project ID but has its own interface range.
    if interface and interface >= 16000 and interface < 17000 then
        return false
    end
    return WOW_PROJECT_ID ~= nil and WOW_PROJECT_MAINLINE ~= nil and WOW_PROJECT_ID == WOW_PROJECT_MAINLINE
end

function Compat.GetMaxPlayerLevel()
    local maximum = Compat.Call(GetMaxPlayerLevel)
    if positive(maximum) then
        return maximum
    end
    maximum = Compat.Call(GetMaxLevelForPlayerExpansion)
    if positive(maximum) then
        return maximum
    end
    local interface = Compat.GetClientInterface()
    return interface and classicLevelCaps[math.floor(interface / 10000)] or nil
end

function Compat.InCombat()
    if type(InCombatLockdown) ~= 'function' then
        return false
    end
    local ok, value = pcall(InCombatLockdown)
    return not ok or not Compat.IsReadable(value) or value == true or value == 1
end

function Compat.RegisterEvent(frame, event)
    if not frame or type(frame.RegisterEvent) ~= 'function' then
        return false
    end
    if C_EventUtils and type(C_EventUtils.IsEventValid) == 'function' then
        if Compat.Call(C_EventUtils.IsEventValid, event) == false then
            return false
        end
    end
    return pcall(frame.RegisterEvent, frame, event)
end

-- Classic clients expose some C_QuestLog functions alongside the index-based log.
-- Probe the entry API itself; namespace or project-ID checks are insufficient.
function Compat.UsesLegacyQuestLog()
    return not (C_QuestLog and type(C_QuestLog.GetInfo) == 'function') and type(GetQuestLogTitle) == 'function'
end

function Compat.GetNumQuestLogEntries()
    local callback = C_QuestLog and C_QuestLog.GetNumQuestLogEntries
    if type(callback) == 'function' then
        return Compat.Call(callback)
    end
    return Compat.Call(GetNumQuestLogEntries)
end

function Compat.GetQuestLogInfo(index)
    if C_QuestLog and type(C_QuestLog.GetInfo) == 'function' then
        local info = Compat.Call(C_QuestLog.GetInfo, index)
        if type(info) ~= 'table' then
            return
        end
        for _, key in ipairs({ 'isHeader', 'isCollapsed', 'isHidden', 'isTask', 'isBounty' }) do
            if not Compat.IsReadable(info[key]) then
                return
            end
        end
        local result = {}
        for key, value in pairs(info) do
            result[key] = clean(value)
        end
        result.isHeader = result.isHeader or false
        result.isCollapsed = result.isCollapsed or false
        result.isHidden = result.isHidden or false
        result.isTask = result.isTask or false
        result.isBounty = result.isBounty or false
        result.logIndex = index
        return result
    end

    local title, level, questTag, isHeader, isCollapsed, isComplete, frequency, questID, startEvent, displayQuestID, isOnMap, hasLocalPOI, isTask, isBounty, isStory, isHidden, isScaling =
        Compat.Call(GetQuestLogTitle, index)
    if type(title) ~= 'string' then
        return
    end
    return {
        title = title,
        level = level,
        questTag = questTag,
        isHeader = isHeader or false,
        isCollapsed = isCollapsed or false,
        isComplete = isComplete,
        frequency = frequency,
        questID = questID,
        startEvent = startEvent,
        displayQuestID = displayQuestID,
        isOnMap = isOnMap,
        hasLocalPOI = hasLocalPOI,
        isTask = isTask or false,
        isBounty = isBounty or false,
        isStory = isStory or false,
        isHidden = isHidden or false,
        isScaling = isScaling,
        logIndex = index,
    }
end

function Compat.GetLogIndexForQuestID(questID)
    if not positive(questID) then
        return
    end
    local index = Compat.Call(C_QuestLog and C_QuestLog.GetLogIndexForQuestID, questID)
        or Compat.Call(GetQuestLogIndexByID, questID)
    if positive(index) then
        return index
    end
    local count = Compat.GetNumQuestLogEntries()
    for entryIndex = 1, type(count) == 'number' and count or 0 do
        local info = Compat.GetQuestLogInfo(entryIndex)
        if info and info.questID == questID and not info.isHeader then
            return entryIndex
        end
    end
end

function Compat.GetQuestTitle(questID)
    local title = Compat.Call(C_QuestLog and C_QuestLog.GetTitleForQuestID, questID)
        or Compat.Call(C_QuestLog and C_QuestLog.GetQuestInfo, questID)
    if type(title) == 'string' then
        return title
    end
    local index = Compat.GetLogIndexForQuestID(questID)
    local info = index and Compat.GetQuestLogInfo(index)
    return info and info.title
end

function Compat.GetSelectedQuest()
    if C_QuestLog and type(C_QuestLog.GetSelectedQuest) == 'function' then
        return Compat.Call(C_QuestLog.GetSelectedQuest)
    end
    local index = Compat.Call(GetQuestLogSelection)
    local info = positive(index) and Compat.GetQuestLogInfo(index)
    return info and not info.isHeader and info.questID or nil
end

function Compat.IsQuestComplete(questID)
    local complete = Compat.Call(C_QuestLog and C_QuestLog.IsComplete, questID)
    if type(complete) == 'boolean' then
        return complete
    end
    local index = Compat.GetLogIndexForQuestID(questID)
    local info = index and Compat.GetQuestLogInfo(index)
    if info then
        return info.isComplete == true or info.isComplete == 1
    end
end

function Compat.IsQuestCompleted(questID)
    local complete = Compat.Call(C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted, questID)
    if type(complete) ~= 'boolean' then
        complete = Compat.Call(IsQuestFlaggedCompleted, questID)
    end
    if type(complete) == 'boolean' then
        return complete
    end
end

-- Legacy reward/text globals read the selected quest. Restore selection on every
-- path, including callback failures, and never query a future quest as the current one.
local function withSelectedQuest(questID, callback, ...)
    if type(callback) ~= 'function' then
        return
    end
    local index = Compat.GetLogIndexForQuestID(questID)
    local previous = Compat.Call(GetQuestLogSelection)
    if not positive(index) or type(previous) ~= 'number' then
        return
    end
    local changed = index ~= previous
    if changed then
        if Compat.InCombat() or type(SelectQuestLogEntry) ~= 'function' then
            return
        end
        local ok = pcall(SelectQuestLogEntry, index)
        if not ok or Compat.Call(GetQuestLogSelection) ~= index then
            pcall(SelectQuestLogEntry, previous)
            return
        end
    end

    local function finish(ok, ...)
        if changed then
            pcall(SelectQuestLogEntry, previous)
        end
        return cleanResults(ok, ...)
    end
    return finish(pcall(callback, ...))
end

-- Extra arguments precede questID on the modern API (item kind/index, for example).
function Compat.CallQuestReward(callback, questID, ...)
    if not positive(questID) or type(callback) ~= 'function' then
        return
    end
    if Compat.UsesLegacyQuestLog() then
        return withSelectedQuest(questID, callback, ...)
    end
    local count = select('#', ...)
    local arguments = { ... }
    arguments[count + 1] = questID
    return Compat.Call(callback, unpackValues(arguments, 1, count + 1))
end

function Compat.GetNumQuestChoices(questID, includeCurrencies)
    if Compat.UsesLegacyQuestLog() then
        return withSelectedQuest(questID, GetNumQuestLogChoices)
    end
    return Compat.Call(GetNumQuestLogChoices, questID, includeCurrencies)
end

function Compat.GetQuestXP(questID)
    local xp = Compat.CallQuestReward(GetQuestLogRewardXP, questID)
    return type(xp) == 'number' and xp >= 0 and xp or nil
end

function Compat.HaveQuestData(questID)
    local callback = C_QuestLog and C_QuestLog.HaveQuestData
    if type(callback) == 'function' then
        return Compat.Call(callback, questID)
    end
    if Compat.UsesLegacyQuestLog() then
        return Compat.GetLogIndexForQuestID(questID) ~= nil
    end
end
Compat.IsQuestDataReady = Compat.HaveQuestData

function Compat.RequestQuestData(questID)
    return Compat.Call(C_QuestLog and C_QuestLog.RequestLoadQuestByID, questID)
end

function Compat.GetQuestObjectives(questID, knownLogIndex)
    local objectives = Compat.Call(C_QuestLog and C_QuestLog.GetQuestObjectives, questID)
    if type(objectives) == 'table' and #objectives > 0 then
        return objectives
    end
    local index = not Compat.UsesLegacyQuestLog() and positive(knownLogIndex) and knownLogIndex
        or Compat.GetLogIndexForQuestID(questID)
    if not index then
        return objectives
    end
    local count = Compat.Call(GetNumQuestLeaderBoards, index)
    if type(count) ~= 'number' then
        return objectives
    end
    objectives = {}
    for objectiveIndex = 1, count do
        local text, kind, finished = Compat.Call(GetQuestLogLeaderBoard, objectiveIndex, index)
        if type(text) == 'string' then
            objectives[#objectives + 1] = { text = text, type = kind, finished = finished == true or finished == 1 }
        end
    end
    return objectives
end

local function questText(callback, questID, knownLogIndex)
    if Compat.UsesLegacyQuestLog() then
        return withSelectedQuest(questID, callback)
    end
    local index = positive(knownLogIndex) and knownLogIndex or Compat.GetLogIndexForQuestID(questID)
    if index then
        return Compat.Call(callback, index)
    end
end

function Compat.GetQuestText(questID, knownLogIndex)
    return questText(GetQuestLogQuestText, questID, knownLogIndex)
end

function Compat.GetQuestCompletionText(questID, knownLogIndex)
    return questText(GetQuestLogCompletionText, questID, knownLogIndex)
end

function Compat.GetQuestTagInfo(questID)
    local info = Compat.Call(C_QuestLog and C_QuestLog.GetQuestTagInfo, questID)
    if type(info) == 'table' then
        return info
    end
    local tagID, tagName = Compat.Call(GetQuestTagInfo, questID)
    if tagID or tagName then
        return { tagID = tagID, tagName = tagName }
    end
    local index = Compat.GetLogIndexForQuestID(questID)
    local entry = index and Compat.GetQuestLogInfo(index)
    local tag = entry and entry.questTag
    if type(tag) == 'string' then
        return { tagName = tag }
    elseif type(tag) == 'number' then
        return { tagID = tag }
    end
end

function Compat.IsQuestWatched(questID)
    local watched = Compat.Call(QuestUtils_IsQuestWatched, questID)
    if type(watched) == 'boolean' then
        return watched
    end
    if C_QuestLog and type(C_QuestLog.GetQuestWatchType) == 'function' then
        local ok, watchType = pcall(C_QuestLog.GetQuestWatchType, questID)
        if ok and Compat.IsReadable(watchType) then
            return watchType ~= nil
        end
    end
    local index = Compat.GetLogIndexForQuestID(questID)
    if index and type(IsQuestWatched) == 'function' then
        local ok, value = pcall(IsQuestWatched, index)
        -- Legacy clients (and Questie's hook) can use nil for an unwatched quest.
        if ok and Compat.IsReadable(value) then
            return value == true or value == 1
        end
    end
end

function Compat.GetNumQuestWatches()
    local callback = C_QuestLog and C_QuestLog.GetNumQuestWatches
    return Compat.Call(type(callback) == 'function' and callback or GetNumQuestWatches)
end

function Compat.CanTrackQuests()
    return (
        C_QuestLog
        and type(C_QuestLog.AddQuestWatch) == 'function'
        and type(C_QuestLog.RemoveQuestWatch) == 'function'
    ) or (type(AddQuestWatch) == 'function' and type(RemoveQuestWatch) == 'function')
end

local function changeQuestWatch(questID, modern, legacy)
    if Compat.InCombat() or not positive(questID) then
        return false
    end
    local argument = questID
    local callback = modern
    if type(callback) ~= 'function' then
        callback = legacy
        argument = Compat.GetLogIndexForQuestID(questID)
    end
    if type(callback) ~= 'function' or not positive(argument) then
        return false
    end
    local ok, result = pcall(callback, argument)
    return ok and Compat.IsReadable(result) and result ~= false
end

function Compat.AddQuestWatch(questID)
    return changeQuestWatch(questID, C_QuestLog and C_QuestLog.AddQuestWatch, AddQuestWatch)
end

function Compat.RemoveQuestWatch(questID)
    if QuestUtil and type(QuestUtil.CanRemoveQuestWatch) == 'function' then
        if Compat.Call(QuestUtil.CanRemoveQuestWatch) == false then
            return false
        end
    end
    return changeQuestWatch(questID, C_QuestLog and C_QuestLog.RemoveQuestWatch, RemoveQuestWatch)
end

function Compat.GetMaxQuestWatches()
    local limit = Constants and Constants.QuestWatchConsts and Constants.QuestWatchConsts.MAX_QUEST_WATCHES
    return limit or MAX_WATCHABLE_QUESTS or MAX_QUEST_WATCHES
end

function Compat.GetMaxQuests()
    return Compat.Call(C_QuestLog and C_QuestLog.GetMaxNumQuestsCanAccept)
        or MAX_QUESTLOG_QUESTS
        or (Compat.UsesLegacyQuestLog() and 25 or 40)
end

function Compat.CanCollapseHeaders()
    return type(CollapseQuestHeader) == 'function' and type(ExpandQuestHeader) == 'function'
end

function Compat.CollapseQuestHeader(index)
    if not Compat.InCombat() and type(CollapseQuestHeader) == 'function' then
        return pcall(CollapseQuestHeader, index)
    end
    return false
end

function Compat.ExpandQuestHeader(index)
    if not Compat.InCombat() and type(ExpandQuestHeader) == 'function' then
        return pcall(ExpandQuestHeader, index)
    end
    return false
end

local readingQuestLog = false

function Compat.IsReadingQuestLog()
    return readingQuestLog
end

-- Classic hides quests beneath collapsed headers. Keep the expanded view private
-- to this synchronous read, then restore the original headers and selection.
function Compat.WithAllQuestLogEntries(callback)
    if readingQuestLog or type(callback) ~= 'function' then
        return false
    end
    readingQuestLog = true
    local expandedHeaders = {}
    local previousSelection
    local complete = true
    local restored = true
    local ok = pcall(function()
        if Compat.UsesLegacyQuestLog() then
            previousSelection = Compat.Call(GetQuestLogSelection)
            local index = 1
            while index <= (Compat.GetNumQuestLogEntries() or 0) do
                local info = Compat.GetQuestLogInfo(index)
                if not info then
                    complete = false
                elseif info.isHeader and info.isCollapsed then
                    if Compat.InCombat() or not Compat.CanCollapseHeaders() then
                        complete = false
                    else
                        -- Restore in reverse order so collapsing later regions does
                        -- not change the expanded indices of earlier headers.
                        expandedHeaders[#expandedHeaders + 1] = index
                        local expanded = Compat.ExpandQuestHeader(index)
                        local current = Compat.GetQuestLogInfo(index)
                        if not expanded or not current or current.isCollapsed then
                            complete = false
                        end
                    end
                end
                index = index + 1
            end
        end
        callback(complete)
    end)
    for index = #expandedHeaders, 1, -1 do
        if type(CollapseQuestHeader) == 'function' then
            pcall(CollapseQuestHeader, expandedHeaders[index])
            local header = Compat.GetQuestLogInfo(expandedHeaders[index])
            if not header or not header.isHeader or not header.isCollapsed then
                restored = false
            end
        else
            restored = false
        end
    end
    if type(previousSelection) == 'number' and type(SelectQuestLogEntry) == 'function' then
        if Compat.Call(GetQuestLogSelection) ~= previousSelection then
            pcall(SelectQuestLogEntry, previousSelection)
            restored = Compat.Call(GetQuestLogSelection) == previousSelection and restored
        end
    end
    readingQuestLog = false
    return ok and restored
end
