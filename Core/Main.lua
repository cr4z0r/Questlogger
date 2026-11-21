-- Connects quest data to Blizzard events and quest-log hooks.
local _, addon = ...
_G.Questlogger = addon
local Core = addon.Core
local Data, UI = addon.Data, addon.UI
local Compat = addon.Compat
local L = addon.L
local isReadable = Data.Helpers.readable
local eventFrame = CreateFrame("Frame")
-- Reuse the graph; invalidate summary data on refresh.
local graph, graphBuilder, refreshQueued, questLogHooked, tooltipHooked, detailsHooked
local summaries, rewardedQuests = {}, {}
local experienceDirty, readingExperience = true, false
local completedQuestXP, completedQuestCount = 0, 0
local experienceMetadata = {}
local experienceEvents = {
    PLAYER_LOGIN = true,
    PLAYER_ENTERING_WORLD = true,
    PLAYER_REGEN_ENABLED = true,
    PLAYER_XP_UPDATE = true,
    PLAYER_LEVEL_UP = true,
    PLAYER_MONEY = true,
    QUEST_ACCEPTED = true,
    QUEST_REMOVED = true,
    QUEST_TURNED_IN = true,
    QUEST_AUTOCOMPLETE = true,
    QUEST_WATCH_UPDATE = true,
    QUEST_DATA_LOAD_RESULT = true,
    QUEST_LOG_CRITERIA_UPDATE = true,
    UNIT_AURA = true,
}

local function safeNumber(callback, ...)
    if not callback then
        return nil
    end
    local ok, value = pcall(callback, ...)
    if ok and isReadable(value) and type(value) == "number" and value >= 0 then
        return value
    end
end

local function isQuestCompleted(questID)
    if rewardedQuests[questID] then
        return true
    end
    return Compat.IsQuestCompleted(questID)
end

local function questXP(questID)
    local logIndex = Compat.GetLogIndexForQuestID(questID)
    if logIndex and logIndex > 0 then
        local xp = Compat.GetQuestXP(questID)
        if xp ~= nil then
            return xp, false
        end
    end
    -- Future quests may only have a database estimate, adjusted to the player's level.
    local support = Data.Helpers.support("QuestXP")
    local row = support and support.db and support.db[questID]
    if not row then
        return nil, false
    end
    local level = safeNumber(UnitLevel, "player")
    if not level then
        return nil, false
    end
    return Core.AdjustXP(row[2], row[1], level, Compat.GetMaxPlayerLevel()), true
end

local function questName(questID)
    local database = Data.Helpers.db()
    local databaseName = Data.Helpers.field(database and database.Quest, "name", questID)
    if L.locale == "enUS" then
        return databaseName or Compat.GetQuestTitle(questID)
    end
    return Compat.GetQuestTitle(questID) or databaseName
end

local function populateFollowupSummary(info, questID)
    info.future = Core.Future(graph, questID, isQuestCompleted)
    Data.PrefetchFollowupRewards(info.future)
    info.futureSteps = {}
    for _, followupID in ipairs(info.future) do
        local routes = Core.Routes(graph, followupID, isQuestCompleted)
        info.futureSteps[followupID] = Core.StepText(graph, followupID, routes)
    end

    -- A raid marker takes precedence when a chain also contains dungeon quests.
    for _, followupID in ipairs(info.future) do
        local kind = Data.InstanceKind(followupID, graph.nodes[followupID] and graph.nodes[followupID].area)
        if kind == "raid" then
            info.instance = kind
            break
        end
        if kind then
            info.instance = kind
        end
    end
end

local function getSummary(questID)
    if not summaries[questID] then
        local chainIssue = Data.DatabaseIssue(
            "Quest.GetAllIds",
            "Quest.preQuestSingle",
            "Quest.preQuestGroup",
            "Quest.breadcrumbForQuestId",
            "Quest.name",
            "Quest.requiredRaces",
            "Quest.requiredClasses"
        )
        local routes = graph and Core.Routes(graph, questID, isQuestCompleted)
            or { status = chainIssue and "unknown" or "loading" }
        local info = Core.Summary(routes, questID, questXP, isQuestCompleted, questName)
        info.chainIssue = chainIssue
        local currentXP = Core.QuestXPText(questXP(questID))
        -- Retail has native quest rewards but no QuestieDB chain data.
        if not graph and Compat.IsRetail() then
            info.listText = currentXP
        else
            info.listText = Core.StepText(graph, questID, routes) .. " (" .. currentXP .. ")"
        end
        info.text = info.listText
        populateFollowupSummary(info, questID)
        info.rewards, info.rewardsPending, info.rewardsUnavailable = Data.Rewards(questID)
        summaries[questID] = info
    end
    return summaries[questID]
end
addon.GetSummary = getSummary
function addon.ShowTrackedQuest(row, questID, resolve)
    if Compat.InCombat() or not isReadable(questID) or type(questID) ~= "number" or questID <= 0 then
        return
    end
    UI.ShowTrackerCard(row, questID, getSummary(questID), questXP, questName, resolve)
end

function addon.ShowMapQuest(pin, questID, resolve)
    if Compat.InCombat() or not isReadable(questID) or type(questID) ~= "number" or questID <= 0 then
        return
    end
    return UI.ShowMapCard(pin, questID, getSummary(questID), questXP, questName, resolve)
end

local function collectObjectiveRows(scroll)
    local objectivesByQuest = {}
    if scroll.objectiveFramePool then
        for objective in scroll.objectiveFramePool:EnumerateActive() do
            local questID = objective.questID
            if isReadable(questID) and type(questID) == "number" and objective:IsShown() then
                objectivesByQuest[questID] = objectivesByQuest[questID] or {}
                table.insert(objectivesByQuest[questID], objective)
            end
        end
    end
    return objectivesByQuest
end

local function refreshExperienceBar()
    if experienceDirty then
        -- Legacy scans temporarily expand headers. Ignore reentrant native hooks
        -- until the full log and its original selection have been restored.
        experienceDirty = false
        readingExperience = true
        local ok, total, count, incompleteData, estimated = pcall(Data.GetCompletedQuestXP, rewardedQuests)
        readingExperience = false
        if not ok then
            experienceDirty = true
            error(total)
        end
        completedQuestXP, completedQuestCount = total, count
        experienceMetadata = { incompleteData = incompleteData, estimated = estimated }
    end
    UI.ExperienceBar.Refresh(completedQuestXP, completedQuestCount, experienceMetadata)
end

function addon.Refresh()
    if readingExperience or Compat.InCombat() then
        return
    end
    refreshExperienceBar()
    if UI.ClientQuestLog then
        UI.ClientQuestLog.Refresh()
    end
    if UI.MapQuestCards then
        UI.MapQuestCards.Refresh()
    end
    if addon.Trackers then
        addon.Trackers.Refresh()
    end
    local scroll = QuestScrollFrame
    if not scroll or not scroll.titleFramePool then
        return
    end
    addon.Controls.Update(scroll)
    local objectivesByQuest = collectObjectiveRows(scroll)
    local layoutChanged = false
    for button in scroll.titleFramePool:EnumerateActive() do
        local questID, titleText = button.questID, button.Text
        if isReadable(questID) and type(questID) == "number" and questID > 0 and titleText then
            local text = titleText:GetText()
            if isReadable(text) and type(text) == "string" then
                local info = getSummary(questID)
                if UI.LayoutRow(button, info, objectivesByQuest[questID] or {}) then
                    layoutChanged = true
                end
                UI.AlignQuestLogPOI(button, scroll.Contents)
            else
                UI.ResetRow(button)
            end
        else
            UI.ResetRow(button)
        end
    end
    if layoutChanged and scroll.Contents and scroll.Contents.Layout then
        scroll.Contents:Layout()
    end
end

-- Invalidate immediately, but combine bursts of client events into one layout pass.
local function scheduleRefresh()
    summaries = {}
    if refreshQueued then
        return
    end
    refreshQueued = true
    C_Timer.After(0.1, function()
        refreshQueued = false
        addon.Refresh()
    end)
end

local function showQuestDetails(questID)
    if Compat.InCombat() then
        return
    end
    local panel = QuestMapFrame and QuestMapFrame.DetailsFrame
    if
        not panel
        or not panel:IsVisible()
        or not isReadable(questID)
        or type(questID) ~= "number"
        or questID <= 0
        or not isReadable(panel.questID)
        or panel.questID ~= questID
    then
        return
    end
    UI.ShowDetailsCard(panel, questID, getSummary(questID), questXP, questName)
end

local function showQuestTooltip(button)
    if Compat.InCombat() then
        return
    end
    local questID = button.questID
    if not isReadable(questID) or type(questID) ~= "number" or questID <= 0 then
        return
    end
    UI.ShowCard(button, getSummary(questID), questXP, questName)
end

local function installHooks()
    UI.ExperienceBar.Install()
    if UI.MapQuestCards then
        UI.MapQuestCards.Install()
    end
    if UI.ClientQuestLog then
        UI.ClientQuestLog.Install()
    end
    if not questLogHooked and type(QuestLogQuests_Update) == "function" then
        hooksecurefunc("QuestLogQuests_Update", function()
            addon.Refresh()
            -- Reconcile after other addons finish decorating titles.
            scheduleRefresh()
        end)
        questLogHooked = true
    end
    if not tooltipHooked and type(QuestMapLogTitleButton_OnEnter) == "function" then
        hooksecurefunc("QuestMapLogTitleButton_OnEnter", showQuestTooltip)
        tooltipHooked = true
    end
    if not detailsHooked and type(QuestMapFrame_ShowQuestDetails) == "function" then
        hooksecurefunc("QuestMapFrame_ShowQuestDetails", showQuestDetails)
        detailsHooked = true
    end
end

-- Yield during graph construction to keep login responsive.
local function buildGraph()
    if graphBuilder or graph then
        return
    end
    local library = Data.Helpers.db()
    local questDatabase = library and library.Quest
    if
        not questDatabase
        or Data.DatabaseIssue(
            "Quest.GetAllIds",
            "Quest.preQuestSingle",
            "Quest.preQuestGroup",
            "Quest.breadcrumbForQuestId",
            "Quest.requiredRaces",
            "Quest.requiredClasses"
        )
    then
        return
    end
    local _, _, raceID = UnitRace("player")
    local _, _, classID = UnitClass("player")
    local masks = library.Enum and library.Enum.raceMaskById
    local raceMask = masks and masks[raceID]
    local classMask = classID and 2 ^ (classID - 1)
    local function eligible(questID)
        local races = Data.Call(questDatabase.requiredRaces, questID)
        local classes = Data.Call(questDatabase.requiredClasses, questID)
        -- Race masks may exceed the 32-bit bitwise range.
        return not (races and races > 0 and raceMask and math.floor(races / raceMask) % 2 == 0)
            and not (classes and classes > 0 and classMask and math.floor(classes / classMask) % 2 == 0)
    end
    local function read(questID)
        return {
            single = Data.Call(questDatabase.preQuestSingle, questID),
            group = Data.Call(questDatabase.preQuestGroup, questID),
            breadcrumb = Data.Call(questDatabase.breadcrumbForQuestId, questID),
            area = Data.Call(questDatabase.zoneOrSort, questID),
        }
    end
    graphBuilder = coroutine.create(function()
        local questIDs = Data.Call(questDatabase.GetAllIds)
        if type(questIDs) == "table" then
            graph = Core.NewGraph(read, questIDs, eligible, coroutine.yield)
        end
    end)
    local function step()
        if Compat.InCombat() then
            C_Timer.After(1, step)
            return
        end
        local ok, err = coroutine.resume(graphBuilder)
        if not ok then
            graphBuilder = nil
            print(L.Format("Questlogger - Couldn't load quest data: %s", tostring(err)))
        elseif coroutine.status(graphBuilder) == "dead" then
            graphBuilder = nil
            scheduleRefresh()
        else
            C_Timer.After(0, step)
        end
    end
    step()
end

local function onEvent(_, event, ...)
    if (event == "PLAYER_XP_UPDATE" or event == "UNIT_AURA") and (...) ~= "player" then
        return
    end
    if event == "QUEST_LOG_UPDATE" then
        if readingExperience or Compat.IsReadingQuestLog() then
            return
        end
        experienceDirty = experienceDirty or Data.CompletedQuestXPChanged()
    elseif experienceEvents[event] then
        experienceDirty = true
    end
    if event == "ADDON_LOADED" then
        installHooks()
        local addonName = ...
        if (addonName == "QuestieDB" or addonName == "Questie") and IsLoggedIn and IsLoggedIn() then
            experienceDirty = true
            C_Timer.After(1, buildGraph)
        end
    elseif event == "PLAYER_LOGIN" then
        installHooks()
        C_Timer.After(1, buildGraph)
        if addon.Trackers then
            C_Timer.After(2, addon.Trackers.Refresh)
        end
    elseif event == "QUEST_TURNED_IN" then
        local questID = ...
        if isReadable(questID) and type(questID) == "number" then
            rewardedQuests[questID] = true
            UI.HideTargetWidget(questID)
        end
    elseif event == "QUEST_ACCEPTED" then
        local first, second = ...
        local questID = isReadable(second) and type(second) == "number" and second or first
        if isReadable(questID) and type(questID) == "number" then
            -- Repeatable quests can be accepted again with the same ID this session.
            rewardedQuests[questID] = nil
        end
    elseif event == "QUEST_DATA_LOAD_RESULT" then
        local questID, success = ...
        if isReadable(questID) and type(questID) == "number" and isReadable(success) and success == true then
            Data.FollowupRewardDataLoaded(questID)
        end
    elseif event == "PLAYER_LEVEL_UP" then
        Data.ResetFollowupRewards()
    elseif event == "UPDATE_EXHAUSTION" or event == "PLAYER_UPDATE_RESTING" then
        UI.ExperienceBar.Refresh()
        return
    elseif event == "ENABLE_XP_GAIN" or event == "DISABLE_XP_GAIN" then
        experienceDirty = true
        UI.ExperienceBar.Refresh()
    elseif event == "PLAYER_TARGET_CHANGED" then
        Data.ObserveUnitName("target")
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        Data.ObserveUnitName("mouseover")
    elseif event == "PLAYER_REGEN_DISABLED" then
        UI.HideCard()
        if UI.MapQuestCards then
            UI.MapQuestCards.Disable()
        end
        addon.Controls.Disable(QuestScrollFrame)
        if UI.ClientQuestLog then
            UI.ClientQuestLog.Disable()
        end
        if addon.Trackers then
            addon.Trackers.Disable()
        end
    end
    scheduleRefresh()
end

eventFrame:SetScript("OnEvent", onEvent)
for _, event in ipairs({
    "ADDON_LOADED",
    "PLAYER_LOGIN",
    "PLAYER_ENTERING_WORLD",
    "PLAYER_REGEN_ENABLED",
    "QUEST_LOG_UPDATE",
    "QUEST_ACCEPTED",
    "QUEST_REMOVED",
    "QUEST_AUTOCOMPLETE",
    "QUEST_WATCH_LIST_CHANGED",
    "QUEST_WATCH_UPDATE",
    "QUEST_TURNED_IN",
    "QUEST_DATA_LOAD_RESULT",
    "QUEST_LOG_CRITERIA_UPDATE",
    "PLAYER_LEVEL_UP",
    "PLAYER_XP_UPDATE",
    "PLAYER_MONEY",
    "UPDATE_EXHAUSTION",
    "PLAYER_UPDATE_RESTING",
    "ENABLE_XP_GAIN",
    "DISABLE_XP_GAIN",
    "PLAYER_TARGET_CHANGED",
    "UPDATE_MOUSEOVER_UNIT",
    "UNIT_AURA",
    "PLAYER_REGEN_DISABLED",
    "GET_ITEM_INFO_RECEIVED",
}) do
    Compat.RegisterEvent(eventFrame, event)
end
