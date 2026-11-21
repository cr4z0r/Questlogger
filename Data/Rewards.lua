-- Reads icon rewards and hover-card reward amounts.
local _, addon = ...
local Data = addon.Data
local Compat = addon.Compat
local L = addon.L
local helpers = Data.Helpers
local call = Data.Call
local readable, clean = helpers.readable, helpers.clean
local positive, asTable, database = helpers.positive, helpers.tab, helpers.db

local function appendQuestItem(rewards, questID, kind, index)
    local rewardInfo = kind == 'choice' and GetQuestLogChoiceInfo or GetQuestLogRewardInfo
    local name, texture, count, quality, _, id = Compat.CallQuestReward(rewardInfo, questID, index)
    if name or positive(id) then
        local link = Compat.CallQuestReward(GetQuestLogItemLink, questID, kind, index)
        rewards[#rewards + 1] = {
            kind = 'item',
            id = id,
            link = link,
            name = name,
            texture = texture,
            count = count,
            quality = quality,
            choice = kind == 'choice',
            questID = questID,
            index = index,
            rewardType = kind,
        }
        return true
    end
end
local requestedQuests = {}
function Data.Rewards(questID)
    if Compat.UsesLegacyQuestLog() and not Compat.GetLogIndexForQuestID(questID) then
        -- A selected-quest API cannot fetch an unaccepted quest. This is not an
        -- asynchronous load, and querying it would show the wrong quest's rewards.
        return {}, false, L['Reward details require an accepted quest in an expanded quest-log region on this client.']
    end
    local rewards = {}
    local loaded = Compat.HaveQuestData(questID)
    if loaded == false and not requestedQuests[questID] then
        requestedQuests[questID] = true
        Compat.RequestQuestData(questID)
    end
    local count = Compat.CallQuestReward(GetNumQuestLogRewards, questID)
    local choiceCount = Compat.GetNumQuestChoices(questID, true)
    local incompleteItems = false
    for index = 1, type(count) == 'number' and count or 0 do
        if not appendQuestItem(rewards, questID, 'reward', index) then
            incompleteItems = true
        end
    end
    for index = 1, type(choiceCount) == 'number' and choiceCount or 0 do
        local choiceCurrency = call(C_QuestLog and C_QuestLog.GetQuestRewardCurrencyInfo, questID, index, true)
        if choiceCurrency and positive(clean(choiceCurrency.currencyID)) then
            local id = choiceCurrency.currencyID
            local faction = call(C_CurrencyInfo and C_CurrencyInfo.GetFactionGrantedByCurrency, id)
            -- Reputation currencies are shown with scalar rewards, not icon rewards.
            if not positive(faction) then
                rewards[#rewards + 1] = {
                    kind = 'currency',
                    id = id,
                    name = clean(choiceCurrency.name),
                    texture = clean(choiceCurrency.texture),
                    count = clean(choiceCurrency.totalRewardAmount),
                    choice = true,
                }
            end
        elseif not appendQuestItem(rewards, questID, 'choice', index) then
            incompleteItems = true
        end
    end
    local questInfo = C_QuestInfoSystem or {}
    for _, currencyInfo in ipairs(asTable(call(questInfo.GetQuestRewardCurrencies, questID))) do
        local id = clean(currencyInfo.currencyID)
        if positive(id) and not positive(call(C_CurrencyInfo and C_CurrencyInfo.GetFactionGrantedByCurrency, id)) then
            rewards[#rewards + 1] = {
                kind = 'currency',
                id = id,
                name = clean(currencyInfo.name),
                texture = clean(currencyInfo.texture),
                count = clean(currencyInfo.totalRewardAmount),
            }
        end
    end
    for _, id in ipairs(asTable(call(questInfo.GetQuestRewardSpells, questID))) do
        if positive(id) then
            local spellInfo = asTable(call(questInfo.GetQuestRewardSpellInfo, questID, id))
            rewards[#rewards + 1] = {
                kind = 'spell',
                id = id,
                name = clean(spellInfo.name),
                texture = clean(spellInfo.texture) or call(C_Spell and C_Spell.GetSpellTexture, id),
            }
        end
    end
    local title = Compat.CallQuestReward(GetQuestLogRewardTitle, questID)
    if type(title) == 'string' and title ~= '' then
        rewards[#rewards + 1] = { kind = 'text', name = L.Format('Title: %s', title), texture = 134939 }
    end
    local skill, icon, points = Compat.CallQuestReward(GetQuestLogRewardSkillPoints, questID)
    if type(skill) == 'string' and positive(points) then
        rewards[#rewards + 1] = { kind = 'text', name = L.Format('%s skill', skill), texture = icon, count = points }
    end
    local honor = Compat.CallQuestReward(GetQuestLogRewardHonor, questID)
    if positive(honor) then
        rewards[#rewards + 1] = { kind = 'text', name = L['Honor'], texture = 1455894, count = honor }
    end
    return rewards, loaded == false or count == nil or choiceCount == nil or incompleteItems
end

-- Cache follow-up rewards separately from live accepted-quest rewards.
local followupCache = {}
function Data.FollowupRewards(questID, refreshPending)
    local entry = followupCache[questID]
    local acceptedSinceLastRead = entry and entry.unavailableReason and Compat.GetLogIndexForQuestID(questID)
    if not entry or (refreshPending and entry.pending) or acceptedSinceLastRead then
        local rewards, pending, unavailableReason = Data.Rewards(questID)
        entry = { rewards = rewards, pending = pending, unavailableReason = unavailableReason }
        followupCache[questID] = entry
    end
    return entry.rewards, entry.pending, entry.unavailableReason
end

function Data.PrefetchFollowupRewards(questIDs)
    for _, questID in ipairs(questIDs) do
        Data.FollowupRewards(questID)
    end
end

-- Update prefetched data when the client reports that a quest has loaded.
function Data.FollowupRewardDataLoaded(questID)
    if followupCache[questID] then
        Data.FollowupRewards(questID, true)
    end
end

function Data.ResetFollowupRewards()
    followupCache = {}
end

-- Modern APIs read by quest ID; the compatibility layer restores legacy selection.
local function factionName(id)
    local data = asTable(call(C_Reputation and C_Reputation.GetFactionDataByID, id))
    local name = clean(data.name) or call(GetFactionInfoByID, id)
    return type(name) == 'string' and name ~= '' and name or L.Format('Faction %s', id)
end

function Data.CardRewards(questID)
    local questLog = C_QuestLog or {}
    local loaded = Compat.HaveQuestData(questID)
    local money = Compat.CallQuestReward(GetQuestLogRewardMoney, questID)
    if type(money) ~= 'number' or money < 0 or (loaded == false and money == 0) then
        money = nil
    end
    local reputation, seenFactions = {}, {}
    local function addReputation(id, amount, estimated, choice, name)
        if not positive(id) or type(amount) ~= 'number' or amount == 0 then
            return
        end
        local key = tostring(id) .. (choice and ':choice' or '')
        if seenFactions[key] then
            return
        end
        seenFactions[key] = true
        reputation[#reputation + 1] = {
            id = id,
            amount = amount,
            estimated = estimated,
            choice = choice,
            name = type(name) == 'string' and name ~= '' and name or factionName(id),
        }
    end
    -- Query reputation currencies by quest ID.
    local function addCurrencyReputation(currencyInfo, choice)
        if type(currencyInfo) ~= 'table' then
            return
        end
        local id = clean(currencyInfo.currencyID)
        if not positive(id) then
            return
        end
        local faction = call(C_CurrencyInfo and C_CurrencyInfo.GetFactionGrantedByCurrency, id)
        addReputation(faction, clean(currencyInfo.totalRewardAmount), false, choice, clean(currencyInfo.name))
    end
    local questInfo = C_QuestInfoSystem or {}
    for _, currencyInfo in ipairs(asTable(call(questInfo.GetQuestRewardCurrencies, questID))) do
        addCurrencyReputation(currencyInfo, false)
    end
    local choiceCount = Compat.GetNumQuestChoices(questID, true)
    for index = 1, type(choiceCount) == 'number' and choiceCount or 0 do
        addCurrencyReputation(call(questLog.GetQuestRewardCurrencyInfo, questID, index, true), true)
    end
    for _, rewardRow in ipairs(asTable(call(questLog.GetQuestLogMajorFactionReputationRewards, questID))) do
        addReputation(clean(rewardRow.factionID), clean(rewardRow.rewardAmount), false, false)
    end
    -- Legacy faction queries require the selected quest.
    local legacyKnown = false
    if Compat.GetSelectedQuest() == questID and type(ProcessQuestLogRewardFactions) == 'function' then
        local ok = pcall(ProcessQuestLogRewardFactions)
        local count = ok and call(GetNumQuestLogRewardFactions)
        if type(count) == 'number' and count >= 0 then
            legacyKnown = true
            for index = 1, count do
                local id, amount = call(GetQuestLogRewardFactionInfo, index)
                if not positive(id) or type(amount) ~= 'number' then
                    legacyKnown = false
                end
                addReputation(id, amount, false, false)
            end
        end
    end
    -- Live reputation was added first. Database estimates only fill missing entries.
    local library = database()
    local quest = library and library.Quest
    local databaseKnown = false
    if quest and type(quest.reputationReward) == 'function' then
        local ok, rows = pcall(quest.reputationReward, questID)
        if ok and readable(rows) and (type(rows) == 'table' or rows == nil) then
            databaseKnown = type(rows) == 'table' or call(quest.Exists, questID) == true
            for _, rewardRow in ipairs(asTable(rows)) do
                if type(rewardRow) == 'table' then
                    addReputation(clean(rewardRow[1]), clean(rewardRow[2]), true, false)
                end
            end
        end
    end
    table.sort(reputation, function(a, b)
        if a.name ~= b.name then
            return a.name < b.name
        end
        if a.id ~= b.id then
            return a.id < b.id
        end
        return not a.choice and b.choice == true
    end)
    return money, reputation, loaded == false or not (databaseKnown or legacyKnown)
end
