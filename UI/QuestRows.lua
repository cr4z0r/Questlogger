-- Decorates and resizes reusable quest-log rows.
local _, addon = ...
local L = addon.L
local Compat = addon.Compat
local UI = addon.UI
local call = addon.Data.Call
local hideIcons = UI.HideRewardIcons

-- Reward-divider spacing.
local DIVIDER_MARGIN, DIVIDER_HEIGHT = 5, 1
local REWARD_GAP = 2 * DIVIDER_MARGIN + DIVIDER_HEIGHT
local REWARD_BLUE = { 0.55, 0.80, 1 }

-- Replace only our own title icons; preserve foreign decorations.
local instanceIcons = {
    raid = ' |TInterface\\TargetingFrame\\UI-RaidTargetingIcon_8:16:16|t',
    dungeon = ' |TInterface\\AddOns\\Questlogger\\Assets\\QuestloggerDungeon:16:16|t',
}

function UI.TitleWithInstance(text, kind)
    for _, token in pairs(instanceIcons) do
        text = text:gsub(token:gsub('([^%w])', '%%%1'), '')
    end
    return text .. (instanceIcons[kind] or '')
end

function UI.RowRewards(button, rewards, anchor)
    local holder = button.QuestloggerRewards
    if not holder then
        holder = CreateFrame('Frame', nil, button)
        button.QuestloggerRewards = holder
        holder.divider = holder:CreateTexture(nil, 'ARTWORK')
        holder.divider:SetColorTexture(REWARD_BLUE[1], REWARD_BLUE[2], REWARD_BLUE[3], 0.45)
        holder.divider:SetPoint('BOTTOMLEFT', holder, 'TOPLEFT', 0, DIVIDER_MARGIN)
        holder.divider:SetHeight(DIVIDER_HEIGHT)
    end
    holder:ClearAllPoints()
    holder:SetPoint('TOPLEFT', anchor, 'BOTTOMLEFT', 0, -REWARD_GAP)
    local width = math.max(22, button.Text:GetWidth())
    local rewardHeight = UI.RewardStrip(holder, rewards, width, 18, L['Rewards:'])
    if holder.label then
        holder.label:SetTextColor(REWARD_BLUE[1], REWARD_BLUE[2], REWARD_BLUE[3], 1)
    end
    holder.divider:SetWidth(width)
    holder.divider:SetShown(rewardHeight > 0)
    -- Trim only the trailing reward-row gap; keep spacing between icon rows.
    if rewardHeight > 0 then
        holder:SetHeight(rewardHeight - 4)
        -- Remove another 2px from the row bottom, not the icon height.
        return rewardHeight - 4 + REWARD_GAP
    end
    return 0
end

-- Show completion shading behind native highlights.
function UI.UpdateTurnInBackground(button)
    local ready = Compat.IsQuestComplete(button.questID) == true
    local background = button.QuestloggerTurnInBackground
    if ready and not background then
        background = button:CreateTexture(nil, 'BACKGROUND', nil, -7)
        button.QuestloggerTurnInBackground = background
        background:SetPoint('TOPLEFT', button, 'TOPLEFT', 1, -1)
        background:SetPoint('BOTTOMRIGHT', button, 'BOTTOMRIGHT', -1, 1)
        background:SetColorTexture(0.12, 0.34, 0.20, 0.27)
        -- Use a solid shade when gradients are unsupported.
        if background.SetGradient and CreateColor then
            local ok = pcall(function()
                background:SetColorTexture(1, 1, 1, 1)
                background:SetGradient(
                    'HORIZONTAL',
                    CreateColor(0.17, 0.43, 0.25, 0.40),
                    CreateColor(0.12, 0.27, 0.18, 0.08)
                )
            end)
            if not ok then
                background:SetColorTexture(0.12, 0.34, 0.20, 0.27)
            end
        end
    end
    if background then
        background:SetShown(ready)
    end
end

-- Resize the native quest POI button, not the title or reward icons.
function UI.AlignQuestLogPOI(button, contents)
    if not contents or not contents.FindButtonByQuestID then
        return
    end
    local poi = call(contents.FindButtonByQuestID, contents, button.questID)
    if
        not poi
        or (poi.parent and poi.parent ~= button)
        or not poi.GetScale
        or not poi.SetScale
        or not poi.ClearAllPoints
        or not poi.SetPoint
    then
        return
    end
    -- POI frames are pooled; record the native scale once to avoid shrink-on-refresh.
    if not poi.QuestloggerNativeScale then
        poi.QuestloggerNativeScale = poi:GetScale()
    end
    poi:SetScale(poi.QuestloggerNativeScale * 0.85)
    poi:ClearAllPoints()
    poi:SetPoint('TOPRIGHT', button.Text, 'TOPLEFT', -4, 0)
end

-- Follow native anchors instead of pool order, which can change as rows are reused.
local function layoutObjectives(titleText, summaryText, objectives)
    local objectivesByAnchor = {}
    for _, objective in ipairs(objectives) do
        local point, relative, relativePoint, x, y = objective:GetPoint(1)
        if point == 'TOPLEFT' and relativePoint == 'BOTTOMLEFT' then
            objectivesByAnchor[relative] = { frame = objective, x = x or 0, y = y or 0 }
        end
    end
    local firstObjective = objectivesByAnchor[titleText] or objectivesByAnchor[summaryText]
    if firstObjective and objectivesByAnchor[titleText] then
        firstObjective.frame:ClearAllPoints()
        firstObjective.frame:SetPoint('TOPLEFT', summaryText, 'BOTTOMLEFT', firstObjective.x, firstObjective.y)
    end
    local anchor, objectiveHeight = summaryText, 0
    local objectiveEntry = firstObjective
    local seen = {}
    while objectiveEntry and not seen[objectiveEntry.frame] do
        anchor = objectiveEntry.frame
        seen[anchor] = true
        objectiveHeight = objectiveHeight + anchor:GetHeight() - objectiveEntry.y
        objectiveEntry = objectivesByAnchor[anchor]
    end
    return anchor, objectiveHeight
end

function UI.LayoutRow(button, info, objectives)
    UI.UpdateTurnInBackground(button)
    local titleText = button.Text
    local text = titleText:GetText()
    local title = UI.TitleWithInstance(text, info.instance)
    if title ~= text then
        titleText:SetText(title)
    end
    local summaryText = button.QuestloggerSummary
    if not summaryText then
        summaryText = button:CreateFontString(nil, 'ARTWORK', 'GameFontHighlightSmall')
        summaryText:SetPoint('TOPLEFT', titleText, 'BOTTOMLEFT', 0, -1)
        summaryText:SetJustifyH('LEFT')
        summaryText:SetJustifyV('TOP')
        summaryText:SetWordWrap(true)
        UI.TooltipStyle.Color(summaryText, 'summary')
        button.QuestloggerSummary = summaryText
    end
    summaryText:SetWidth(math.max(22, titleText:GetWidth()))
    summaryText:SetText(info.listText)
    summaryText:Show()
    local summaryHeight = math.max(12, summaryText:GetStringHeight())
    summaryText:SetHeight(summaryHeight)
    local anchor, objectiveHeight = layoutObjectives(titleText, summaryText, objectives)
    local rewardsHeight = UI.RowRewards(button, info.rewards, anchor)
    -- Rebuild row height from native padding and current content.
    local padding = 14
    if GetCVarBool and not GetCVarBool('showQuestObjectivesInLog') then
        padding = padding + 4
    end
    local height = titleText:GetHeight() + summaryHeight + 1 + objectiveHeight + rewardsHeight + padding
    if math.abs(button:GetHeight() - height) > 0.01 then
        button:SetHeight(height)
        return true
    end
    return false
end

function UI.ResetRow(button)
    if button.QuestloggerTurnInBackground then
        button.QuestloggerTurnInBackground:Hide()
    end
    if button.QuestloggerSummary then
        button.QuestloggerSummary:Hide()
    end
    if button.QuestloggerRewards then
        hideIcons(button.QuestloggerRewards)
        button.QuestloggerRewards.divider:Hide()
        button.QuestloggerRewards:Hide()
    end
end
