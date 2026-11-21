-- Sum rewards that are ready to turn in, without granting XP or consuming rested XP.
local _, addon = ...
local Compat, Core, Data = addon.Compat, addon.Core, addon.Data
local call = Compat.Call
local knownQuestIDs, lastFingerprint = {}, nil
local requestedQuests = {}

local function nonnegativeNumber(value)
    return Compat.IsReadable(value) and type(value) == 'number' and value == value and value >= 0 and value < math.huge
end

local function standardQuest(info)
    return info
        and not info.isHeader
        and not info.isHidden
        and not info.isTask
        and not info.isBounty
        and nonnegativeNumber(info.questID)
        and info.questID > 0
end

local function questXP(questID)
    local loaded = Compat.HaveQuestData(questID)
    local xp = Compat.GetQuestXP(questID)
    if nonnegativeNumber(xp) and not (loaded == false and xp == 0) then
        return xp, false
    end
    if loaded == false and not requestedQuests[questID] then
        requestedQuests[questID] = true
        Compat.RequestQuestData(questID)
    end

    local support = Data.Helpers.support('QuestXP')
    local row = support and support.db and support.db[questID]
    local level = call(UnitLevel, 'player')
    if
        type(row) ~= 'table'
        or not nonnegativeNumber(row[1])
        or not nonnegativeNumber(row[2])
        or not nonnegativeNumber(level)
    then
        return
    end
    xp = Core.AdjustXP(row[2], row[1], level, Compat.GetMaxPlayerLevel())
    if nonnegativeNumber(xp) then
        return xp, true
    end
end

local function appendValue(parts, value)
    local kind = type(value)
    if not Compat.IsReadable(value) or (kind ~= 'number' and kind ~= 'string' and kind ~= 'boolean') then
        parts[#parts + 1] = '?'
        return
    end
    local text = tostring(value)
    parts[#parts + 1] = kind:sub(1, 1) .. #text .. ':' .. text
end

-- Header expansion emits QUEST_LOG_UPDATE on Classic. Its restored visible state
-- and per-quest objectives stay identical, unlike genuine hidden quest progress.
local function questFingerprint(questIDs)
    local parts = {}
    local entries, quests = Compat.GetNumQuestLogEntries()
    appendValue(parts, entries)
    appendValue(parts, quests)
    for index = 1, type(entries) == 'number' and entries or 0 do
        local info = Compat.GetQuestLogInfo(index)
        if info then
            appendValue(parts, info.questID)
            appendValue(parts, info.title)
            appendValue(parts, info.isHeader)
            appendValue(parts, info.isCollapsed)
            appendValue(parts, info.isComplete)
            appendValue(parts, info.isHidden)
            appendValue(parts, info.isTask)
            appendValue(parts, info.isBounty)
        else
            parts[#parts + 1] = '?'
        end
    end
    for _, questID in ipairs(questIDs) do
        appendValue(parts, questID)
        appendValue(parts, call(C_QuestLog and C_QuestLog.IsOnQuest, questID))
        appendValue(parts, call(C_QuestLog and C_QuestLog.IsComplete, questID))
        appendValue(parts, call(C_QuestLog and C_QuestLog.ReadyForTurnIn, questID))
        local objectives = call(C_QuestLog and C_QuestLog.GetQuestObjectives, questID)
        if type(objectives) == 'table' then
            appendValue(parts, #objectives)
            for _, objective in ipairs(objectives) do
                if Compat.IsReadable(objective) and type(objective) == 'table' then
                    appendValue(parts, objective.text)
                    appendValue(parts, objective.finished)
                    appendValue(parts, objective.numFulfilled)
                    appendValue(parts, objective.numRequired)
                    appendValue(parts, objective.type)
                else
                    parts[#parts + 1] = '?'
                end
            end
        else
            parts[#parts + 1] = '?'
        end
    end
    return table.concat(parts, '\031')
end

function Data.CompletedQuestXPChanged()
    return not lastFingerprint or questFingerprint(knownQuestIDs) ~= lastFingerprint
end

function Data.GetCompletedQuestXP(excludedQuestIDs)
    local total, count, incomplete, estimated = 0, 0, false, false
    local questIDs, seen = {}, {}
    local fullLog = false
    local ok = Compat.WithAllQuestLogEntries(function(complete)
        fullLog = complete
        incomplete = not complete
        local entries = Compat.GetNumQuestLogEntries()
        if not nonnegativeNumber(entries) then
            incomplete = true
            return
        end
        for index = 1, entries do
            local info = Compat.GetQuestLogInfo(index)
            if not info then
                incomplete = true
            elseif
                not info.isHeader
                and not info.isHidden
                and not info.isTask
                and not info.isBounty
                and not standardQuest(info)
            then
                incomplete = true
            elseif standardQuest(info) and not seen[info.questID] then
                local questID = info.questID
                seen[questID] = true
                questIDs[#questIDs + 1] = questID
                if
                    not (excludedQuestIDs and excludedQuestIDs[questID])
                    and not info.isFailed
                    and info.isComplete ~= -1
                then
                    local ready = call(C_QuestLog and C_QuestLog.ReadyForTurnIn, questID)
                    if type(ready) ~= 'boolean' then
                        ready = Compat.IsQuestComplete(questID)
                    end
                    if ready == true then
                        count = count + 1
                        local xp, estimate = questXP(questID)
                        if xp == nil then
                            incomplete = true
                        else
                            local combined = total + xp
                            if nonnegativeNumber(combined) then
                                total = combined
                                estimated = estimated or estimate
                            else
                                incomplete = true
                            end
                        end
                    elseif ready == nil then
                        incomplete = true
                    end
                end
            end
        end
    end)
    if not fullLog then
        -- Retain hidden IDs from the last complete read if an API temporarily
        -- refused expansion. Their objective revisions can still trigger a retry.
        for _, questID in ipairs(knownQuestIDs) do
            if not seen[questID] then
                questIDs[#questIDs + 1] = questID
            end
        end
    end
    if ok or #questIDs > 0 then
        table.sort(questIDs)
        knownQuestIDs = questIDs
        -- Compute this after all temporary header and selection changes are undone.
        lastFingerprint = questFingerprint(knownQuestIDs)
    end
    return total, count, incomplete or not ok, estimated
end
