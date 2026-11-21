-- Collects quest text independently of card layout and interactive widgets.
local _, addon = ...
local L = addon.L
local Compat = addon.Compat
local Data, UI = addon.Data, addon.UI
local QuestText = {}
UI.QuestText = QuestText
local call = Data.Call

-- Restore objective progress when the native tooltip only shows turn-in status.
local function completedObjectives(questID, logIndex)
    local objectives = {}
    local function add(text, finished)
        if not Data.Helpers.readable(text) or type(text) ~= 'string' or not text:match('%S') then
            return
        end

        local done = Data.Helpers.readable(finished) and finished == true
        objectives[#objectives + 1] = {
            text = (QUEST_DASH or '- ') .. text,
            r = done and 0.55 or 0.87,
            g = done and 0.82 or 0.89,
            b = done and 0.55 or 0.93,
            objective = true,
        }
    end

    local rows = Compat.GetQuestObjectives(questID, logIndex)
    if type(rows) == 'table' then
        for _, objective in ipairs(rows) do
            if Data.Helpers.readable(objective) and type(objective) == 'table' then
                add(objective.text, objective.finished)
            end
        end
    end

    return objectives
end

-- The adapter restores selection when a legacy client only exposes selected-quest text.
function QuestText.FromAPI(questID, questName)
    local logIndex = Compat.GetLogIndexForQuestID(questID)
    if type(logIndex) ~= 'number' or logIndex <= 0 then
        logIndex = nil
    end

    local description, story
    if logIndex then
        story, description = Compat.GetQuestText(questID)
    end

    local database = Data.Helpers.db()
    local quest = database and database.Quest
    if type(description) ~= 'string' or not description:match('%S') then
        if type(story) == 'string' and story:match('%S') then
            description = story
        else
            local texts = Data.Helpers.field(quest, 'objectivesText', questID)
            if type(texts) == 'table' then
                local parts = {}
                for _, text in ipairs(texts) do
                    if type(text) == 'string' and text:match('%S') then
                        parts[#parts + 1] = text
                    end
                end
                description = table.concat(parts, '\n\n')
            elseif type(texts) == 'string' then
                description = texts
            end
        end
    end

    local title = logIndex and Compat.GetQuestTitle(questID)
    local lines = {
        { text = title or questName(questID) or L.Format('Quest %d', questID), r = 1, g = 0.82, b = 0.3 },
    }
    local descriptionIndex
    if type(description) == 'string' and description:match('%S') then
        lines[#lines + 1] = { text = description, r = 1, g = 1, b = 1 }
        descriptionIndex = #lines
    elseif Compat.UsesLegacyQuestLog() and not logIndex then
        lines[#lines + 1] = {
            text = L['Quest description is available after accepting this quest on this client.'],
            r = 0.65,
            g = 0.65,
            b = 0.65,
        }
    elseif Compat.HaveQuestData(questID) == false then
        lines[#lines + 1] = { text = L['Loading quest details...'], r = 0.65, g = 0.65, b = 0.65 }
    else
        lines[#lines + 1] = { text = L['Quest description unavailable'], r = 0.65, g = 0.65, b = 0.65 }
    end

    local objectives = completedObjectives(questID, logIndex)
    if #objectives == 0 and not logIndex then
        -- Database text describes future objectives, but cannot provide live progress.
        local raw = Data.Helpers.tab(Data.Helpers.field(quest, 'objectives', questID))
        local seen = {}
        local function add(text)
            if type(text) == 'string' and text:match('%S') and not seen[text] then
                seen[text] = true
                objectives[#objectives + 1] = {
                    text = (QUEST_DASH or '- ') .. text,
                    r = 0.87,
                    g = 0.89,
                    b = 0.93,
                    objective = true,
                }
            end
        end

        local entities = { database and database.Npc, database and database.Object, database and database.Item }
        for kind = 1, 3 do
            for _, objective in ipairs(Data.Helpers.tab(raw[kind])) do
                if type(objective) == 'table' then
                    add(
                        type(objective[2]) == 'string' and objective[2]
                            or Data.Helpers.field(entities[kind], 'name', objective[1])
                    )
                end
            end
        end
        for _, objective in ipairs(Data.Helpers.tab(raw[5])) do
            if type(objective) == 'table' then
                add(objective[3])
            end
        end
        for _, objective in ipairs(Data.Helpers.tab(raw[6])) do
            if type(objective) == 'table' then
                add(objective[2])
            end
        end
    end

    for _, objective in ipairs(objectives) do
        lines[#lines + 1] = objective
    end
    return lines, descriptionIndex, Data.QuestCategory(questID)
end

-- Capture native tooltip additions, such as party progress, before hiding it.
function QuestText.FromTooltip(row, questID, questName)
    local lines = {}
    local afterBlank = false
    local descriptionIndex
    local description
    local logIndex = row.questLogIndex
    if not Data.Helpers.readable(logIndex) or type(logIndex) ~= 'number' or logIndex <= 0 then
        logIndex = Compat.GetLogIndexForQuestID(questID)
    end
    if type(logIndex) ~= 'number' or logIndex <= 0 then
        logIndex = nil
    end

    local complete = Compat.IsQuestComplete(questID) == true
    if logIndex then
        local story, objectiveText = Compat.GetQuestText(questID, logIndex)
        description = objectiveText
        if complete and (type(description) ~= 'string' or not description:match('%S')) then
            description = story
        end
    end

    local completionText = complete and logIndex and Compat.GetQuestCompletionText(questID, logIndex)
    local completionIndex
    local restoredObjectives = complete and completedObjectives(questID, logIndex) or {}
    local dash = QUEST_DASH or '- '
    local tagText = row.TagText and row.TagText:IsShown() and call(row.TagText.GetText, row.TagText)
    local category = Data.QuestCategory(questID, tagText)

    for index = 1, GameTooltip:NumLines() do
        local leftLine = _G['GameTooltipTextLeft' .. index]
        local rightLine = _G['GameTooltipTextRight' .. index]
        local text = leftLine and call(leftLine.GetText, leftLine)
        local right = rightLine and rightLine:IsShown() and call(rightLine.GetText, rightLine)
        if
            type(text) == 'string'
            and text ~= CLICK_QUEST_DETAILS
            and not text:find(L['Click to view Quest Details'], 1, true)
        then
            local red, green, blue = call(leftLine.GetTextColor, leftLine)
            local isCategory = index > 1 and category and Data.PlainTag(text) == category
            local isCompletion = complete
                and index > 1
                and (text == completionText or text == QUEST_WATCH_QUEST_READY or text == L['Ready for turn-in'])
            local isObjective = index > 1 and text:sub(1, #dash) == dash

            if isCompletion or (complete and #restoredObjectives > 0 and isObjective) then
                completionIndex = completionIndex or (#lines + 1)
                afterBlank = false
            elseif not text:match('%S') then
                afterBlank = true
            elseif not isCategory then
                lines[#lines + 1] = {
                    text = type(right) == 'string' and (text .. '  ' .. right) or text,
                    r = red,
                    g = green,
                    b = blue,
                    objective = isObjective,
                }
                -- Older layouts identify the description with a blank separator.
                if
                    index > 1
                    and (
                        (description and text == description)
                        or (not description and not descriptionIndex and afterBlank)
                    )
                then
                    descriptionIndex = #lines
                end
                afterBlank = false
            end
        end
    end
    GameTooltip:Hide()

    -- Replace the turn-in status with the original description and objective progress.
    if complete then
        if #lines == 0 then
            lines[1] = { text = questName(questID) or L.Format('Quest %d', questID), r = 1, g = 0.82, b = 0.3 }
        end
        local insertAt = completionIndex or 2
        if not descriptionIndex and type(description) == 'string' and description:match('%S') then
            table.insert(lines, insertAt, { text = description, r = 0.87, g = 0.89, b = 0.93 })
            descriptionIndex = insertAt
        end
        insertAt = descriptionIndex and (descriptionIndex + 1) or insertAt
        for _, objective in ipairs(restoredObjectives) do
            table.insert(lines, insertAt, objective)
            insertAt = insertAt + 1
        end
        if not descriptionIndex and #restoredObjectives == 0 and #lines == 1 then
            lines[2] = { text = L['Quest details unavailable'], r = 0.65, g = 0.65, b = 0.65 }
        end
    end

    if not complete and not descriptionIndex and not description and #lines >= 2 then
        descriptionIndex = 2
    end
    return lines, descriptionIndex, category
end
