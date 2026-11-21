-- A portable quest list keeps cards usable when a client has a different native log layout.
local _, addon = ...
local L = addon.L
local Compat, UI = addon.Compat, addon.UI
local ClientQuestLog = {}
UI.ClientQuestLog = ClientQuestLog

local panel
local slashInstalled, legacyHooked
local nativeRows = setmetatable({}, { __mode = 'k' })
local PANEL_WIDTH, PANEL_HEIGHT, PADDING = 440, 450, 14
local QUEST_HEIGHT, HEADER_HEIGHT = 40, 26

local function readableQuestID(value)
    return Compat.IsReadable(value) and type(value) == 'number' and value > 0 and value or nil
end

local function usableFrame(frame)
    return frame and not (frame.IsForbidden and frame:IsForbidden())
end

local function resolveViewerRow(row)
    local info = row.logIndex and Compat.GetQuestLogInfo(row.logIndex)
    local questID = info and readableQuestID(info.questID)
    if questID and questID == row.questID then
        return questID
    end
end

local function showRowCard(row, resolve)
    if Compat.InCombat() or not addon.ShowTrackedQuest then
        return
    end
    local questID = resolve(row)
    if questID then
        addon.ShowTrackedQuest(row, questID, resolve)
    end
end

-- Classic's visible buttons are reused after scrolling; resolve their indices on every hover.
local function bindNativeRows()
    if Compat.InCombat() then
        return
    end
    local scroll = _G.QuestLogListScrollFrame
    if not scroll or type(FauxScrollFrame_GetOffset) ~= 'function' then
        return
    end
    local visibleRows = type(QUESTS_DISPLAYED) == 'number' and QUESTS_DISPLAYED or 25
    for slot = 1, math.min(100, visibleRows) do
        local button = _G['QuestLogTitle' .. slot]
        if usableFrame(button) and button.HookScript and not nativeRows[button] then
            local rowSlot = slot
            local function resolve()
                local offset = Compat.Call(FauxScrollFrame_GetOffset, scroll)
                if type(offset) ~= 'number' then
                    return
                end
                local info = Compat.GetQuestLogInfo(rowSlot + offset)
                if info and Compat.IsReadable(info.isHeader) and not info.isHeader then
                    return readableQuestID(info.questID)
                end
            end
            button:HookScript('OnEnter', function(self)
                showRowCard(self, resolve)
            end)
            nativeRows[button] = true
        end
    end
end

local function refresh()
    if addon.Refresh then
        addon.Refresh()
    else
        ClientQuestLog.Refresh()
    end
end

local function scrollBy(delta)
    if not panel then
        return
    end
    local scroll = panel.scroll
    local maximum = scroll:GetVerticalScrollRange()
    scroll:SetVerticalScroll(math.max(0, math.min(maximum, scroll:GetVerticalScroll() - delta * QUEST_HEIGHT)))
end

local function createLabel(parent, font, role)
    local label = parent:CreateFontString(nil, 'ARTWORK', font)
    label:SetJustifyH('LEFT')
    label:SetWordWrap(false)
    UI.TooltipStyle.Color(label, role)
    return label
end

local function createButton(parent, text, width, action)
    local button = CreateFrame('Button', nil, parent, 'UIPanelButtonTemplate')
    button:SetSize(width, 22)
    button:SetText(text)
    button:SetScript('OnClick', function()
        if not Compat.InCombat() then
            action()
            refresh()
        end
    end)
    return button
end

local function createRow(owner)
    local row = CreateFrame('Button', nil, owner.content)
    row:SetWidth(owner.content:GetWidth())
    row:RegisterForClicks('LeftButtonUp')
    row.title = createLabel(row, 'GameFontNormal', 'heading')
    row.title:SetPoint('TOPLEFT', 4, -4)
    row.title:SetPoint('RIGHT', row, 'RIGHT', -4, 0)
    row.summary = createLabel(row, 'GameFontHighlightSmall', 'summary')
    row.summary:SetPoint('TOPLEFT', row.title, 'BOTTOMLEFT', 0, -3)
    row.summary:SetPoint('RIGHT', row, 'RIGHT', -4, 0)
    local highlight = row:CreateTexture(nil, 'HIGHLIGHT')
    highlight:SetAllPoints()
    highlight:SetColorTexture(0.3, 0.5, 0.7, 0.16)
    row:EnableMouseWheel(true)
    row:SetScript('OnMouseWheel', function(_, delta)
        scrollBy(delta)
    end)
    row:SetScript('OnEnter', function(self)
        if not self.isHeader then
            showRowCard(self, resolveViewerRow)
        end
    end)
    row:SetScript('OnClick', function(self)
        if Compat.InCombat() then
            return
        end
        local info = Compat.GetQuestLogInfo(self.logIndex)
        if not info then
            return
        end
        if self.isHeader and Compat.IsReadable(info.isHeader) and info.isHeader then
            if not Compat.IsReadable(info.isCollapsed) then
                return
            end
            if info.isCollapsed then
                Compat.ExpandQuestHeader(self.logIndex)
            else
                Compat.CollapseQuestHeader(self.logIndex)
            end
        else
            local questID = resolveViewerRow(self)
            if not questID then
                return
            end
            local watched = Compat.IsQuestWatched(questID)
            if watched == true then
                Compat.RemoveQuestWatch(questID)
            elseif watched == false then
                local limit, count = Compat.GetMaxQuestWatches(), Compat.GetNumQuestWatches()
                if not limit or not count or count < limit then
                    Compat.AddQuestWatch(questID)
                end
            end
        end
        refresh()
    end)
    return row
end

local function createPanel()
    local frame = CreateFrame('Frame', 'QuestloggerQuestList', UIParent)
    frame:SetSize(PANEL_WIDTH, math.min(PANEL_HEIGHT, UIParent:GetHeight() * 0.85))
    frame:SetPoint('CENTER')
    frame:SetFrameStrata('HIGH')
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag('LeftButton')
    frame:SetScript('OnDragStart', function(self)
        if not Compat.InCombat() then
            self:StartMoving()
        end
    end)
    frame:SetScript('OnDragStop', function(self)
        self:StopMovingOrSizing()
    end)
    frame:SetScript('OnHide', function(self)
        self:StopMovingOrSizing()
        UI.HideCard()
    end)
    UI.TooltipStyle.Apply(frame)
    frame.title = createLabel(frame, 'GameFontNormalLarge', 'title')
    frame.title:SetPoint('TOPLEFT', PADDING, -PADDING)
    frame.title:SetText('Questlogger')
    local close = CreateFrame('Button', nil, frame, 'UIPanelCloseButton')
    close:SetPoint('TOPRIGHT', 0, 0)
    close:SetScript('OnClick', function()
        frame:Hide()
    end)

    local buttonWidth = (PANEL_WIDTH - 2 * PADDING - 6) / 2
    frame.regions = createButton(frame, L['Collapse regions'], buttonWidth, function()
        addon.Controls.ToggleRegions()
    end)
    frame.regions:SetPoint('TOPLEFT', PADDING, -44)
    frame.tracking = createButton(frame, L['Track all'], buttonWidth, function()
        addon.Controls.ToggleTracking()
    end)
    frame.tracking:SetPoint('TOPLEFT', frame.regions, 'TOPRIGHT', 6, 0)

    frame.hint = createLabel(frame, 'GameFontHighlightSmall', 'muted')
    frame.hint:SetPoint('TOPLEFT', PADDING, -74)
    frame.hint:SetText(
        Compat.UsesLegacyQuestLog()
                and L['Hover for details; click to track. Expand regions to include collapsed quests.']
            or L['Hover for details. Click a quest to toggle tracking. Scroll with the mouse wheel.']
    )
    frame.hint:SetWidth(PANEL_WIDTH - 2 * PADDING)
    frame.hint:SetWordWrap(true)
    frame.scroll = CreateFrame('ScrollFrame', nil, frame)
    -- Longer translations can wrap the hint onto another line.
    frame.scroll:SetPoint('TOPLEFT', frame, 'TOPLEFT', PADDING, -(74 + math.max(22, frame.hint:GetStringHeight()) + 12))
    frame.scroll:SetPoint('BOTTOMRIGHT', -PADDING, 36)
    frame.scroll:EnableMouseWheel(true)
    frame.scroll:SetScript('OnMouseWheel', function(_, delta)
        scrollBy(delta)
    end)
    frame.content = CreateFrame('Frame', nil, frame.scroll)
    frame.content:SetSize(PANEL_WIDTH - 2 * PADDING, 1)
    frame.scroll:SetScrollChild(frame.content)
    frame.status = createLabel(frame, 'GameFontHighlightSmall', 'muted')
    frame.status:SetPoint('BOTTOMLEFT', PADDING, PADDING)
    frame.status:SetWidth(PANEL_WIDTH - 2 * PADDING)
    frame.rows = {}
    frame:Hide()
    if type(UISpecialFrames) == 'table' then
        table.insert(UISpecialFrames, 'QuestloggerQuestList')
    end
    return frame
end

function ClientQuestLog.Toggle()
    if Compat.InCombat() then
        print(L['Questlogger - Open the quest list after combat ends.'])
        return
    end
    if not panel then
        panel = createPanel()
    end
    if panel:IsShown() then
        panel:Hide()
    else
        panel:Show()
        ClientQuestLog.Refresh()
    end
end

function ClientQuestLog.Refresh()
    if Compat.InCombat() then
        return
    end
    bindNativeRows()
    if not panel or not panel:IsShown() then
        return
    end

    local entries = Compat.GetNumQuestLogEntries() or 0
    local used, height = 0, 0
    for index = 1, entries do
        local info = Compat.GetQuestLogInfo(index)
        local isHeader = info and Compat.IsReadable(info.isHeader) and info.isHeader
        local questID = info
            and Compat.IsReadable(info.isHidden)
            and Compat.IsReadable(info.isTask)
            and Compat.IsReadable(info.isBounty)
            and not info.isHidden
            and not info.isTask
            and not info.isBounty
            and readableQuestID(info.questID)
        local title = info and info.title
        if type(title) == 'string' and Compat.IsReadable(title) and (isHeader or questID) then
            used = used + 1
            local row = panel.rows[used] or createRow(panel)
            panel.rows[used] = row
            row.logIndex, row.questID, row.isHeader = index, questID, isHeader
            row:ClearAllPoints()
            row:SetPoint('TOPLEFT', panel.content, 'TOPLEFT', 0, -height)
            if isHeader then
                local collapsed = Compat.IsReadable(info.isCollapsed) and info.isCollapsed
                row.title:SetText((collapsed and '+ ' or '- ') .. title)
                row.summary:Hide()
                row:SetHeight(HEADER_HEIGHT)
                height = height + HEADER_HEIGHT
            else
                local watched = Compat.IsQuestWatched(questID)
                local summary = addon.GetSummary and addon.GetSummary(questID)
                row.title:SetText(
                    UI.TitleWithInstance((watched and '|cff8cd18c*|r ' or '') .. title, summary and summary.instance)
                )
                row.summary:SetText(summary and summary.listText or L['Quest details available on hover'])
                row.summary:Show()
                row:SetHeight(QUEST_HEIGHT)
                height = height + QUEST_HEIGHT
            end
            row:Show()
        end
    end
    for index = used + 1, #panel.rows do
        panel.rows[index]:Hide()
        panel.rows[index].questID = nil
        panel.rows[index].logIndex = nil
    end
    panel.content:SetHeight(math.max(1, height))
    local scroll = panel.scroll
    scroll:SetVerticalScroll(math.min(scroll:GetVerticalScroll(), math.max(0, height - scroll:GetHeight())))
    local state = addon.Controls.State()
    panel.regions:SetText(state.expanded > 0 and L['Collapse regions'] or L['Expand regions'])
    panel.regions:SetEnabled(#state.headers > 0 and Compat.CanCollapseHeaders())
    panel.tracking:SetText(state.tracked > 0 and L['Untrack all'] or L['Track all'])
    panel.tracking:SetEnabled(#state.quests > 0 and Compat.CanTrackQuests())
    local _, questCount = Compat.GetNumQuestLogEntries()
    local count = questCount or #state.quests
    local maximum = Compat.GetMaxQuests()
    local countText = maximum and (L['%d/%d quests']):format(count, maximum) or (L['%d quests']):format(count)
    panel.status:SetText(entries == 0 and L['No quests in the quest log.'] or countText)
end

local function registerSlashCommands()
    if slashInstalled or type(SlashCmdList) ~= 'table' then
        return
    end
    SlashCmdList.QUESTLOGGER = ClientQuestLog.Toggle
    _G.SLASH_QUESTLOGGER1 = '/questlogger'
    -- Keep an existing addon's short alias if it has already claimed /ql.
    local shortAliasUsed = false
    for name, value in pairs(_G) do
        if type(name) == 'string' and name:match('^SLASH_') and Compat.IsReadable(value) and value == '/ql' then
            shortAliasUsed = true
            break
        end
    end
    if not shortAliasUsed then
        _G.SLASH_QUESTLOGGER2 = '/ql'
    end
    slashInstalled = true
end

function ClientQuestLog.Install()
    registerSlashCommands()
    if not legacyHooked and type(hooksecurefunc) == 'function' and type(QuestLog_Update) == 'function' then
        hooksecurefunc('QuestLog_Update', bindNativeRows)
        legacyHooked = true
    end
    if not Compat.InCombat() then
        bindNativeRows()
    end
end

function ClientQuestLog.Disable()
    if panel then
        panel:StopMovingOrSizing()
        panel.regions:SetEnabled(false)
        panel.tracking:SetEnabled(false)
    end
end
