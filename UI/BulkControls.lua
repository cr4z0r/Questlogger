-- Manages region expansion and quest watch toggles.
local _, addon = ...
local L = addon.L
local Compat = addon.Compat
local Controls = {}
addon.Controls = Controls
local isReadable = addon.Data.Helpers.readable

local TOOLBAR_HEIGHT, BUTTON_HEIGHT = 24, 20
local LIST_BORDER_INSET = 4
local FALLBACK_BAR_OFFSET = 6

-- A successful nil result differs from an unavailable API, especially for watch types.
local function readValue(callback, ...)
    if type(callback) ~= 'function' then
        return nil, false
    end
    local ok, value = pcall(callback, ...)
    if ok and isReadable(value) then
        return value, true
    end
    return nil, false
end

local function inCombat()
    return InCombatLockdown and InCombatLockdown()
end

-- Modern logs expose collapsed quests; legacy APIs expose only expanded entries.
function Controls.State()
    local state = { headers = {}, quests = {}, expanded = 0, tracked = 0 }
    local entryCount = Compat.GetNumQuestLogEntries()
    if type(entryCount) ~= 'number' then
        return state
    end
    for i = 1, entryCount do
        local info = Compat.GetQuestLogInfo(i)
        if type(info) == 'table' and isReadable(info.isHeader) then
            if info.isHeader then
                if isReadable(info.isCollapsed) then
                    state.headers[#state.headers + 1] = { index = i, collapsed = info.isCollapsed }
                    if not info.isCollapsed then
                        state.expanded = state.expanded + 1
                    end
                end
            elseif
                isReadable(info.questID)
                and type(info.questID) == 'number'
                and info.questID > 0
                and isReadable(info.isHidden)
                and not info.isHidden
                and isReadable(info.isTask)
                and not info.isTask
                and isReadable(info.isBounty)
                and not info.isBounty
            then
                local tracked = Compat.IsQuestWatched(info.questID)
                if tracked ~= nil then
                    state.quests[#state.quests + 1] = { id = info.questID, tracked = tracked }
                    if tracked then
                        state.tracked = state.tracked + 1
                    end
                end
            end
        end
    end
    return state
end

local function refreshQuestLog()
    if QuestMapFrame_UpdateAll then
        QuestMapFrame_UpdateAll()
    elseif QuestLogQuests_Update then
        QuestLogQuests_Update()
    elseif QuestLog_Update then
        QuestLog_Update()
    end
end

local function withBatchedUpdates(flag, callback)
    local previousValue = QuestMapFrame and QuestMapFrame[flag]
    if QuestMapFrame then
        QuestMapFrame[flag] = true
    end
    -- Restore Blizzard's update flag even when a restricted action fails.
    local ok, errorMessage = pcall(callback)
    if QuestMapFrame then
        QuestMapFrame[flag] = previousValue
    end
    refreshQuestLog()
    if not ok then
        print('Questlogger - ' .. tostring(errorMessage))
    end
end

local function isSearching(scroll)
    local text = readValue(scroll and scroll.SearchBox and scroll.SearchBox.GetText, scroll and scroll.SearchBox)
    return type(text) == 'string' and text ~= ''
end

function Controls.ToggleRegions(scroll)
    if inCombat() or isSearching(scroll) then
        return
    end
    local state = Controls.State()
    if #state.headers == 0 then
        return
    end
    local collapse = state.expanded > 0
    withBatchedUpdates('ignoreQuestLogUpdate', function()
        -- Reverse iteration tolerates index changes.
        for i = #state.headers, 1, -1 do
            local header = state.headers[i]
            if collapse and not header.collapsed then
                Compat.CollapseQuestHeader(header.index)
            elseif not collapse and header.collapsed then
                Compat.ExpandQuestHeader(header.index)
            end
        end
    end)
    if scroll and scroll.SetVerticalScroll then
        scroll:SetVerticalScroll(0)
    end
end

function Controls.ToggleTracking(desired)
    if inCombat() then
        return
    end
    local state = Controls.State()
    if #state.quests == 0 then
        return
    end
    local untrack = desired == false or (desired == nil and state.tracked > 0)
    local limit = Compat.GetMaxQuestWatches()
    withBatchedUpdates('ignoreQuestWatchListChanged', function()
        for _, quest in ipairs(state.quests) do
            if untrack and quest.tracked then
                if not (QuestUtil and QuestUtil.CanRemoveQuestWatch) or QuestUtil.CanRemoveQuestWatch() then
                    Compat.RemoveQuestWatch(quest.id)
                end
            elseif not untrack and not quest.tracked then
                local count = Compat.GetNumQuestWatches()
                if type(limit) == 'number' and type(count) == 'number' and count >= limit then
                    break
                end
                Compat.AddQuestWatch(quest.id)
            end
        end
    end)
    local after = Controls.State()
    if not untrack and after.tracked < #state.quests then
        print(
            (L['Questlogger - Tracked %d/%d quests (client tracking restrictions may apply).']):format(
                after.tracked,
                #state.quests
            )
        )
    elseif untrack and after.tracked > 0 then
        print(L['Questlogger - Some quests could not be untracked by the client.'])
    end
end

-- Offset the viewport while preserving search and settings positions.
local function offsetAnchor(frame, predicate, delta)
    local points = {}
    local changed = false
    for i = 1, frame:GetNumPoints() do
        local point, relative, relativePoint, x, y = frame:GetPoint(i)
        if predicate(point, relative, relativePoint) then
            y = (y or 0) + delta
            changed = true
        end
        points[#points + 1] = { point, relative, relativePoint, x or 0, y or 0 }
    end
    if changed then
        frame:ClearAllPoints()
        for _, point in ipairs(points) do
            frame:SetPoint(unpack(point, 1, 5))
        end
    end
    return changed
end

local function anchoredTop(point)
    return point == 'TOPLEFT' or point == 'TOPRIGHT' or point == 'TOP'
end

-- Center the whole toolbar in the visible gap, not against the list's top anchor.
local function positionToolbar(scroll, bar)
    local searchBottom = scroll.SearchBox.GetBottom and scroll.SearchBox:GetBottom()
    local listTop = scroll.GetTop and scroll:GetTop()
    local offset = FALLBACK_BAR_OFFSET
    if type(searchBottom) == 'number' and type(listTop) == 'number' then
        -- Convert screen coordinates to the toolbar's scale if needed.
        local barScale = bar.GetEffectiveScale and bar:GetEffectiveScale() or 1
        local searchScale = scroll.SearchBox.GetEffectiveScale and scroll.SearchBox:GetEffectiveScale() or barScale
        local listScale = scroll.GetEffectiveScale and scroll:GetEffectiveScale() or barScale
        local gap = (searchBottom * searchScale - listTop * listScale) / barScale
        if gap > 0 then
            offset = math.max(0, (gap + LIST_BORDER_INSET - TOOLBAR_HEIGHT) / 2)
        end
    end
    if bar.anchorOffset == offset then
        return
    end
    bar.anchorOffset = offset
    bar:ClearAllPoints()
    bar:SetPoint('BOTTOMLEFT', scroll, 'TOPLEFT', 6, offset)
    bar:SetPoint('BOTTOMRIGHT', scroll, 'TOPRIGHT', -2, offset)
end

local function createButton(parent, label, action)
    local button = CreateFrame('Button', nil, parent, 'UIPanelButtonTemplate')
    button:SetHeight(BUTTON_HEIGHT)
    button:SetText(label)
    -- Override the template's text offset so the label sits at the button center.
    local text = button:GetFontString()
    if text then
        text:ClearAllPoints()
        text:SetPoint('CENTER', button, 'CENTER', 0, 0)
        text:SetJustifyH('CENTER')
        text:SetJustifyV('MIDDLE')
    end
    button:SetScript('OnClick', function()
        action()
        Controls.Update(QuestScrollFrame)
    end)
    button:SetScript('OnEnter', function(self)
        if not GameTooltip then
            return
        end
        GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
        GameTooltip:SetText(self:GetText())
        GameTooltip:AddLine(self.tip or '', 1, 1, 1, true)
        GameTooltip:Show()
    end)
    button:SetScript('OnLeave', function(self)
        if GameTooltip and GameTooltip:IsOwned(self) then
            GameTooltip:Hide()
        end
    end)
    return button
end

local function createToolbar(scroll)
    -- Apply the offset only once per layout.
    if not offsetAnchor(scroll, anchoredTop, -TOOLBAR_HEIGHT) then
        return
    end
    local function relativeToScroll(_, relative)
        return relative == scroll
    end
    offsetAnchor(scroll.SearchBox, relativeToScroll, TOOLBAR_HEIGHT)
    if scroll.SettingsDropdown then
        offsetAnchor(scroll.SettingsDropdown, relativeToScroll, TOOLBAR_HEIGHT)
    end

    local bar = CreateFrame('Frame', nil, scroll:GetParent())
    scroll.QuestloggerControls = bar
    bar:SetHeight(TOOLBAR_HEIGHT)
    positionToolbar(scroll, bar)
    bar.regions = createButton(bar, L['Collapse all'], function()
        Controls.ToggleRegions(scroll)
    end)
    bar.tracking = createButton(bar, L['+ Track'], Controls.ToggleTracking)
    bar.regions:SetPoint('LEFT', bar, 'LEFT', 0, 0)
    bar.tracking:SetPoint('RIGHT', bar, 'RIGHT', 0, 0)
    local function resize()
        local width = math.max(1, (bar:GetWidth() - 4) / 2)
        bar.regions:SetWidth(width)
        bar.tracking:SetWidth(width)
    end
    bar:SetScript('OnSizeChanged', resize)
    resize()
    -- Keep the toolbar outside the scrolling viewport.
    scroll:HookScript('OnShow', function()
        bar:Show()
        Controls.Update(scroll)
    end)
    scroll:HookScript('OnHide', function()
        bar:Hide()
    end)
    bar:SetShown(scroll:IsShown())
    return bar
end

function Controls.Update(scroll)
    if not scroll or not scroll.SearchBox or inCombat() then
        return
    end
    local bar = scroll.QuestloggerControls or createToolbar(scroll)
    if not bar then
        return
    end
    positionToolbar(scroll, bar)
    local state = Controls.State()
    local search = isSearching(scroll)
    local regionsAvailable = Compat.CanCollapseHeaders()
    local trackingAvailable = Compat.CanTrackQuests()
    bar.regions:SetText(state.expanded > 0 and L['Collapse all'] or L['Expand all'])
    bar.regions.tip = search and L['Clear the quest search before changing region expansion.']
        or L['Collapse or expand every quest region.']
    bar.regions:SetEnabled(regionsAvailable and #state.headers > 0 and not search)
    bar.tracking:SetText(state.tracked > 0 and L['- Track'] or L['+ Track'])
    bar.tracking.tip = Compat.UsesLegacyQuestLog()
            and L['Change tracking for visible quest-log entries. Expand all regions first to include their quests. Does not abandon quests.']
        or L['Change tracking for all quests, including collapsed regions and quests outside the search results. Does not abandon quests.']
    bar.tracking:SetEnabled(not not (trackingAvailable and #state.quests > 0))
end

function Controls.Disable(scroll)
    local bar = scroll and scroll.QuestloggerControls
    if bar then
        bar.regions:SetEnabled(false)
        bar.tracking:SetEnabled(false)
    end
end
