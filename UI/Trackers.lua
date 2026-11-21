-- Extend the existing trackers instead of replacing quest rows or item buttons.
local _, addon = ...
local L = addon.L
local Compat = addon.Compat
local Trackers = {}
addon.Trackers = Trackers
local call = addon.Data.Call
local nativeState = { regions = {}, quests = {}, headers = {}, hidden = {} }
local questieState = {}
-- Native POI artwork and item highlights can extend outside the module's bounds.
local SCROLL_LEFT_GUTTER, SCROLL_RIGHT_GUTTER = 32, 8
local TRACKER_POI_SCALE = 0.85
local BAR_HEIGHT, BAR_SPACE = 19, 21
local function inCombat()
    return InCombatLockdown and InCombatLockdown()
end

local function isReadable(value)
    return not (issecretvalue and issecretvalue(value))
end

local function getReadableID(value)
    return isReadable(value) and type(value) == 'number' and value > 0 and value or nil
end

local function isVisible(frame)
    return frame and frame.IsVisible and frame:IsVisible()
end

local function isAccessibleFrame(frame)
    return frame and not (frame.IsForbidden and frame:IsForbidden())
end

-- Quest-log headers are authoritative, even if a region is collapsed in the log.
function Trackers.LogRegions()
    local questRegions, regionOrder, currentRegion = {}, {}, L['Other quests']
    local entryCount = Compat.GetNumQuestLogEntries() or 0
    for index = 1, entryCount do
        local questInfo = Compat.GetQuestLogInfo(index)
        if type(questInfo) == 'table' then
            if isReadable(questInfo.isHeader) and questInfo.isHeader then
                if isReadable(questInfo.title) and type(questInfo.title) == 'string' and questInfo.title ~= '' then
                    currentRegion = questInfo.title
                end
            elseif getReadableID(questInfo.questID) then
                questRegions[questInfo.questID] = currentRegion
                if not regionOrder[currentRegion] then
                    regionOrder[currentRegion] = index
                end
            end
        end
    end
    return questRegions, regionOrder
end

local function getTrackedState()
    local state = addon.Controls.State()
    local questRegions = Trackers.LogRegions()
    local questIDs, regionNames = {}, {}
    for _, quest in ipairs(state.quests) do
        if quest.tracked then
            questIDs[quest.id] = true
            regionNames[questRegions[quest.id] or L['Other quests']] = true
        end
    end
    return state, questIDs, regionNames
end

local function hasExpandedEntries(keys, collapsed)
    for key in pairs(keys) do
        if not collapsed[key] then
            return true
        end
    end
    return false
end

local function toggleCollapsedSet(keys, collapsed)
    local collapse = hasExpandedEntries(keys, collapsed)
    for key in pairs(keys) do
        collapsed[key] = collapse and true or nil
    end
end
Trackers.ToggleSet = toggleCollapsedSet

-- Keep the controls fixed at the top of the quest list, outside its scroll viewport.
local function setButtonTip(button, tip)
    if button.tip == tip then
        return
    end
    button.tip = tip
    -- Refresh the tooltip in place after a toggle, without requiring another hover.
    if GameTooltip and GameTooltip.IsOwned and GameTooltip:IsOwned(button) then
        GameTooltip:SetText(tip)
        GameTooltip:Show()
    end
end

local function ensureToolbar(root, state, actions)
    if state.bar or not isAccessibleFrame(root) then
        return state.bar
    end
    local bar = CreateFrame('Frame', nil, UIParent)
    state.bar = bar
    bar:SetHeight(BAR_HEIGHT)
    bar:SetPoint('BOTTOMRIGHT', root, 'TOPRIGHT', 0, 2)
    bar:SetWidth(math.max(1, call(root.GetWidth, root) or 0))
    bar:SetClampedToScreen(true)
    bar:SetFrameStrata('MEDIUM')
    bar.buttons = {}
    local border = bar:CreateTexture(nil, 'ARTWORK')
    border:SetColorTexture(0.65, 0.82, 1, 0.25)
    border:SetPoint('BOTTOMLEFT', bar, 'BOTTOMLEFT', 1, 0)
    border:SetPoint('BOTTOMRIGHT', bar, 'BOTTOMRIGHT', -1, 0)
    border:SetHeight(1)
    bar.bottomBorder = border
    for index, action in ipairs(actions) do
        local button = CreateFrame('Button', nil, bar)
        button:SetHeight(BAR_HEIGHT)
        local label = button:CreateFontString(nil, 'ARTWORK', 'GameFontNormalSmall')
        label:SetPoint('CENTER')
        label:SetTextColor(1, 0.82, 0)
        button.label = label
        button:SetScript('OnClick', function()
            if not inCombat() then
                action()
            end
        end)
        button:SetScript('OnEnter', function(self)
            if GameTooltip then
                GameTooltip:SetOwner(self, 'ANCHOR_TOP')
                GameTooltip:SetText(self.tip or '')
                GameTooltip:Show()
            end
        end)
        button:SetScript('OnLeave', function(self)
            if GameTooltip and GameTooltip:IsOwned(self) then
                GameTooltip:Hide()
            end
        end)
        bar.buttons[index] = button
        if index == 1 then
            button:SetPoint('LEFT', bar, 'LEFT', 0, 0)
        else
            button:SetPoint('LEFT', bar.buttons[index - 1], 'RIGHT', 1, 0)
        end
    end
    local function resize()
        local buttonCount = #bar.buttons
        local buttonWidth = math.max(1, (bar:GetWidth() - (buttonCount - 1)) / buttonCount)
        for _, button in ipairs(bar.buttons) do
            button:SetWidth(buttonWidth)
            if state.category then
                if button.label.SetWidth then
                    button.label:SetWidth(math.max(1, buttonWidth - 2))
                end
                if button.label.SetWordWrap then
                    button.label:SetWordWrap(false)
                end
            end
        end
    end
    bar:SetScript('OnSizeChanged', resize)
    resize()
    if state ~= questieState then
        root:HookScript('OnSizeChanged', function(self)
            if not inCombat() and not state.barInside then
                bar:SetWidth(math.max(1, call(self.GetWidth, self) or 0))
            end
        end)
        root:HookScript('OnHide', function()
            bar:Hide()
        end)
        root:HookScript('OnShow', function()
            if not inCombat() then
                Trackers.Refresh()
            end
        end)
    end
    bar:Hide()
    return bar
end

local function positionToolbar(state, anchor, inside)
    local bar = state.bar
    if not bar then
        return
    end
    if state.barAnchor ~= anchor or state.barInside ~= inside then
        bar:ClearAllPoints()
        if inside then
            local point = (state == nativeState or state.category) and 'BOTTOMRIGHT' or 'TOPRIGHT'
            bar:SetPoint('TOPRIGHT', anchor, point, 0, -1)
        else
            bar:SetPoint('BOTTOMRIGHT', anchor, 'TOPRIGHT', 0, 2)
        end
        state.barAnchor, state.barInside = anchor, inside
    end
    local width = math.max(1, call(anchor.GetWidth, anchor) or 0)
    if bar:GetWidth() ~= width then
        bar:SetWidth(width)
    end
end

local function updateToolbar(state, ids, zones, regions, quests, tracked, total, enabled, visible)
    local bar = state.bar
    if not bar then
        return
    end
    local regionsExpanded, questsExpanded = hasExpandedEntries(zones, regions), hasExpandedEntries(ids, quests)
    local labels = {
        regionsExpanded and L['- Zones'] or L['+ Zones'],
        questsExpanded and L['- Quests'] or L['+ Quests'],
        tracked and L['- Track'] or L['+ Track'],
    }
    local tips = {
        regionsExpanded and L['Collapse all zones'] or L['Expand all zones'],
        questsExpanded and L['Collapse all quests'] or L['Expand all quests'],
        tracked and L['Untrack all quests'] or L['Track all quests'],
    }
    for index, button in ipairs(bar.buttons) do
        button.label:SetText(labels[index])
        setButtonTip(button, tips[index])
        local active = not inCombat()
            and enabled
            and ((index == 1 and next(zones) ~= nil) or (index == 2 and next(ids) ~= nil) or (index == 3 and total > 0))
        button:SetEnabled(active)
        button.label:SetAlpha(active and 1 or 0.45)
    end
    -- Retain the Track all control if untracking from this bar empties the tracker.
    bar:SetShown(not not (enabled and visible))
end

-- Native quest rows keep their pooled frames, item buttons, and original click handlers.
local function getNativeQuestID(block)
    return getReadableID(block and block.id)
end

local function getQuestieEntryType(line)
    if not line then
        return
    end
    if line.QuestloggerClickMode then
        return line.QuestloggerClickMode
    end
    if type(line.Recipe) == 'table' then
        return 'recipe'
    end
    if line.mode == 'achieve' then
        return 'achieve'
    elseif line.mode == nil or line.mode == 'quest' then
        return 'quest'
    end
end

local function getQuestieQuestID(line)
    if getQuestieEntryType(line) ~= 'quest' then
        return
    end
    local quest = line and line.Quest
    return type(quest) == 'table' and getReadableID(quest.Id or quest.id) or nil
end

local function showQuestHover(row, resolveQuestID)
    if inCombat() or not isVisible(row) then
        return
    end
    local questID = resolveQuestID(row)
    if questID and addon.ShowTrackedQuest then
        addon.ShowTrackedQuest(row, questID, resolveQuestID)
    end
end

local function requestNativeLayout()
    if nativeState.module and not inCombat() then
        nativeState.module:MarkDirty()
    end
end

local function untrackNativeQuest(questID)
    if not Compat.RemoveQuestWatch(questID) then
        return
    end
    nativeState.quests[questID] = nil
    requestNativeLayout()
    Trackers.Refresh()
end

local geometryController =
    addon.UI.TrackerGeometry.Create(nativeState, requestNativeLayout, SCROLL_LEFT_GUTTER, SCROLL_RIGHT_GUTTER)
local function hideNativeFrame(frame, owner)
    if isAccessibleFrame(frame) and frame.IsShown and frame:IsShown() then
        nativeState.hidden[frame] = { owner = owner, id = owner.id }
        frame:Hide()
    end
end

local function restoreNativeFrames()
    if inCombat() then
        return
    end
    for frame, record in pairs(nativeState.hidden) do
        local block = record.owner
        local stillActive = block.id == record.id
            and (
                not nativeState.module.GetExistingBlock
                or nativeState.module:GetExistingBlock(block.id, block.template) == block
            )
        local belongs = frame == block
            or (block.addedRegions and block.addedRegions[frame] ~= nil)
            or (frame.parentBlock == block and block.usedLines and block.usedLines[frame.objectiveKey] == frame)
        if stillActive and belongs and isAccessibleFrame(frame) then
            frame:Show()
        end
    end
    nativeState.hidden = {}
    for _, header in pairs(nativeState.headers) do
        header:Hide()
    end
end

-- Retain native block sizes and content; only rearrange their vertical anchors.
local function getRegionHeader(module, name)
    local header = nativeState.headers[name]
    if header then
        return header
    end
    header = CreateFrame('Button', nil, module.ContentsFrame)
    local label = header:CreateFontString(nil, 'ARTWORK', 'GameFontNormalSmall')
    label:SetPoint('LEFT', header, 'LEFT', 0, 0)
    label:SetPoint('RIGHT', header, 'RIGHT', -2, 0)
    label:SetJustifyH('LEFT')
    local font = module.Header and module.Header.Text
    if font and font.GetFont then
        local path, size, flags = font:GetFont()
        if path and size then
            label:SetFont(path, math.max(10, size - 1), flags)
        end
    end
    label:SetTextColor(1, 0.82, 0)
    header.label = label
    header:SetHeight(math.max(17, label:GetStringHeight() + 3))
    header:SetScript('OnClick', function()
        if inCombat() then
            return
        end
        nativeState.regions[name] = not nativeState.regions[name] or nil
        requestNativeLayout()
        Trackers.Refresh()
    end)
    nativeState.headers[name] = header
    return header
end

-- Give the scroll viewport room for native artwork without reflowing the quest text.
local function setScrollOffset(scroll, offset)
    local limit = math.max(0, (scroll.contentHeight or 0) - (scroll.viewHeight or 0))
    scroll.offset = math.max(0, math.min(offset or 0, limit))
    scroll:SetVerticalScroll(scroll.offset)
end

local function updateScrollWidth(module, scroll)
    local width = math.max(1, module:GetWidth())
    if module.ContentsFrame:GetWidth() ~= width then
        module.ContentsFrame:SetWidth(width)
    end
    local paddedWidth = width + SCROLL_LEFT_GUTTER + SCROLL_RIGHT_GUTTER
    if scroll.canvas:GetWidth() ~= paddedWidth then
        scroll.canvas:SetWidth(paddedWidth)
    end
end

local function installNativeScroll(module)
    if nativeState.scroll then
        return nativeState.scroll
    end
    local contents = module.ContentsFrame
    if not contents or not contents.SetParent or not module.Header then
        return
    end
    local scroll = CreateFrame('ScrollFrame', nil, module)
    if not scroll.SetScrollChild or not scroll.SetVerticalScroll then
        scroll:Hide()
        return
    end
    scroll:SetPoint('TOPLEFT', module.Header, 'BOTTOMLEFT', -SCROLL_LEFT_GUTTER, -BAR_SPACE)
    scroll:SetPoint('RIGHT', module, 'RIGHT', SCROLL_RIGHT_GUTTER, 0)
    scroll:SetHeight(1)
    -- The padded canvas scrolls; native contents keep their original width and screen X position.
    local canvas = CreateFrame('Frame', nil, scroll)
    scroll.canvas = canvas
    canvas:SetPoint('TOPLEFT', scroll, 'TOPLEFT', 0, 0)
    canvas:SetSize(math.max(1, module:GetWidth()) + SCROLL_LEFT_GUTTER + SCROLL_RIGHT_GUTTER, 1)
    scroll:SetScrollChild(canvas)
    contents:ClearAllPoints()
    contents:SetParent(canvas)
    contents:SetPoint('TOPLEFT', canvas, 'TOPLEFT', SCROLL_LEFT_GUTTER, 0)
    updateScrollWidth(module, scroll)
    local height = math.max(1, (module.contentsHeight or 0) - (module.headerHeight or 0))
    contents:SetHeight(height)
    canvas:SetHeight(height)
    module:HookScript('OnSizeChanged', function(self)
        if not inCombat() then
            updateScrollWidth(self, scroll)
            if nativeState.bar and nativeState.barInside then
                positionToolbar(nativeState, self.Header, true)
            end
        end
    end)
    scroll:EnableMouseWheel(true)
    scroll:SetScript('OnMouseWheel', function(self, delta)
        if not inCombat() then
            setScrollOffset(self, (self.offset or 0) - delta * 45)
        end
    end)
    nativeState.scroll = scroll
    return scroll
end

local function updateNativeScroll(module, contentHeight, available)
    local scroll = nativeState.scroll
    if not scroll then
        return contentHeight
    end
    -- Reserve space for the fixed toolbar in the module's reported height.
    local toolbarHeight = not module:IsCollapsed() and contentHeight > 0 and math.min(BAR_SPACE, available) or 0
    nativeState.toolbarReserved = toolbarHeight == BAR_SPACE
    local height = math.max(0, math.min(contentHeight, available - toolbarHeight))
    scroll.contentHeight, scroll.viewHeight = contentHeight, height
    scroll:SetHeight(math.max(1, height))
    updateScrollWidth(module, scroll)
    module.ContentsFrame:SetHeight(math.max(1, contentHeight))
    scroll.canvas:SetHeight(math.max(1, contentHeight))
    if scroll.UpdateScrollChildRect then
        scroll:UpdateScrollChildRect()
    end
    setScrollOffset(scroll, scroll.offset)
    scroll:SetShown(height > 0 and not module:IsCollapsed())
    return height + toolbarHeight
end

local function openQuestDetails(questID)
    if type(QuestMapFrame_OpenToQuestDetails) == 'function' then
        QuestMapFrame_OpenToQuestDetails(questID)
    elseif QuestUtil and QuestUtil.OpenQuestDetails then
        QuestUtil.OpenQuestDetails(questID)
    end
end

-- Blizzard highlights the entire block on title hover. Keep objective colors local to each line.
local function getObjectiveStyle(style)
    if not style then
        return
    end
    for colorName, colorStyle in pairs(OBJECTIVE_TRACKER_COLOR or {}) do
        if colorStyle == style and type(colorName) == 'string' and colorName:match('Highlight$') then
            return style.reverse or style
        end
    end
    return style
end

local function paintObjectiveLine(line)
    local block = line.parentBlock
    if not block or block.parentModule ~= nativeState.module or not line.Text then
        return
    end
    local base = line.QuestloggerBaseStyle or getObjectiveStyle(line.Text.colorStyle)
    if not base then
        return
    end
    local active = nativeState.hoveredObjective == line and isVisible(line.QuestloggerObjectiveClick)
    local style = active and base.reverse or base
    style = style or base
    line.Text:SetTextColor(style.r, style.g, style.b)
    line.Text.colorStyle = style
    local colors = OBJECTIVE_TRACKER_COLOR
    local dash = colors and (active and colors.NormalHighlight or colors.Normal)
    if line.Dash and dash then
        line.Dash:SetTextColor(dash.r, dash.g, dash.b)
    end
end

local function setObjectiveHover(line, active)
    local previous = nativeState.hoveredObjective
    if active then
        nativeState.hoveredObjective = line
    elseif previous == line then
        nativeState.hoveredObjective = nil
    end
    if previous and previous ~= line then
        paintObjectiveLine(previous)
    end
    paintObjectiveLine(line)
end

local function bindObjectiveHighlights(block)
    if block.QuestloggerHighlight then
        return
    end
    block.QuestloggerHighlight = true
    if type(block.SetStringText) == 'function' then
        hooksecurefunc(block, 'SetStringText', function(self, text, _, _, style)
            if self.parentModule ~= nativeState.module then
                return
            end
            self:ForEachUsedLine(function(line)
                if line.Text == text then
                    -- Capture the unhighlighted style on every native objective refresh.
                    line.QuestloggerBaseStyle = style or (OBJECTIVE_TRACKER_COLOR and OBJECTIVE_TRACKER_COLOR.Normal)
                    paintObjectiveLine(line)
                end
            end)
        end)
    end
    if type(block.UpdateHighlight) == 'function' then
        hooksecurefunc(block, 'UpdateHighlight', function(self)
            if self.parentModule == nativeState.module then
                self:ForEachUsedLine(paintObjectiveLine)
            end
        end)
    end
end

-- The POI pool is shared across modules, so return the original scale on release.
local function restorePOIScale(block)
    local record = block.QuestloggerPOI
    if record then
        record.button:SetScale(record.scale)
        block.QuestloggerPOI = nil
    end
end

local function alignTrackerPOI(block)
    local poiButton = block.poiButton
    if
        block.parentModule ~= nativeState.module
        or not poiButton
        or not block.HeaderText
        or not poiButton.GetScale
        or not poiButton.SetScale
        or not poiButton.ClearAllPoints
        or not poiButton.SetPoint
    then
        return
    end
    if poiButton.GetParent and poiButton:GetParent() ~= block then
        return
    end
    local record = block.QuestloggerPOI
    if record and record.button ~= poiButton then
        restorePOIScale(block)
        record = nil
    end
    if not record then
        record = { button = poiButton, scale = poiButton:GetScale() }
        block.QuestloggerPOI = record
    end
    if not block.QuestloggerPOIReleaseHook and type(block.CheckAndReleasePOIButton) == 'function' then
        block.QuestloggerPOIReleaseHook = true
        hooksecurefunc(block, 'CheckAndReleasePOIButton', function(self)
            if not self.poiButton then
                restorePOIScale(self)
            end
        end)
    end
    poiButton:SetScale(record.scale * TRACKER_POI_SCALE)
    poiButton:ClearAllPoints()
    poiButton:SetPoint('TOPRIGHT', block.HeaderText, 'TOPLEFT', -4, 0)
end

-- Pooled headers untrack on Shift-click and retain their other native actions.
local function bindNativeBlock(block)
    alignTrackerPOI(block)
    local header = block.HeaderButton
    if header and header.GetScript and not header.QuestloggerClick then
        local originalClick = header:GetScript('OnClick')
        header.QuestloggerClick = true
        -- Bind the real mouse surface, including collapsed quests with no objectives.
        header:HookScript('OnEnter', function(self)
            local ownerBlock = self:GetParent()
            if ownerBlock and ownerBlock.parentModule == nativeState.module then
                showQuestHover(ownerBlock, getNativeQuestID)
            end
        end)
        header:SetScript('OnClick', function(self, button, ...)
            local ownerBlock = self:GetParent()
            local questID = getNativeQuestID(ownerBlock)
            if
                ownerBlock
                and ownerBlock.parentModule == nativeState.module
                and questID
                and button == 'LeftButton'
                and not inCombat()
            then
                if IsShiftKeyDown and IsShiftKeyDown() then
                    untrackNativeQuest(questID)
                elseif not (IsModifiedClick and IsModifiedClick()) then
                    nativeState.quests[questID] = not nativeState.quests[questID] or nil
                    requestNativeLayout()
                    Trackers.Refresh()
                elseif originalClick then
                    originalClick(self, button, ...)
                end
            elseif originalClick then
                originalClick(self, button, ...)
            end
        end)
    end
    if not block.ForEachUsedLine then
        return
    end
    bindObjectiveHighlights(block)
    block:ForEachUsedLine(function(line)
        -- Only cover objective text; leave POIs, item buttons and progress bars alone.
        if not line.Text or not line.CreateFontString then
            return
        end
        local clickSurface = line.QuestloggerObjectiveClick
        if not clickSurface then
            clickSurface = CreateFrame('Button', nil, line)
            line.QuestloggerObjectiveClick = clickSurface
            clickSurface:SetPoint('TOPLEFT', line.Text, 'TOPLEFT', 0, 0)
            clickSurface:SetPoint('BOTTOMRIGHT', line.Text, 'BOTTOMRIGHT', 0, 0)
            clickSurface:RegisterForClicks('LeftButtonUp')
            clickSurface:SetScript('OnClick', function()
                local ownerBlock = line.parentBlock
                local questID = getNativeQuestID(ownerBlock)
                if
                    not inCombat()
                    and questID
                    and ownerBlock.parentModule == nativeState.module
                    and not nativeState.quests[questID]
                then
                    if IsShiftKeyDown and IsShiftKeyDown() then
                        untrackNativeQuest(questID)
                    else
                        openQuestDetails(questID)
                    end
                end
            end)
            clickSurface:SetScript('OnEnter', function()
                local ownerBlock = line.parentBlock
                if ownerBlock and ownerBlock.parentModule == nativeState.module then
                    setObjectiveHover(line, true)
                    showQuestHover(ownerBlock, getNativeQuestID)
                end
            end)
            clickSurface:SetScript('OnLeave', function()
                setObjectiveHover(line, false)
            end)
            clickSurface:SetScript('OnHide', function()
                setObjectiveHover(line, false)
            end)
            -- A freed line may be reused by another tracker module.
            line:HookScript('OnHide', function()
                setObjectiveHover(line, false)
                clickSurface:Hide()
                line.QuestloggerBaseStyle = nil
            end)
        end
        line.QuestloggerBaseStyle = line.QuestloggerBaseStyle or getObjectiveStyle(line.Text.colorStyle)
        clickSurface:SetShown(block.parentModule == nativeState.module)
        paintObjectiveLine(line)
    end)
end

local function layoutNativeQuests(module)
    if inCombat() or not isAccessibleFrame(module) then
        return
    end
    local heightBudget = type(module.availableHeight) == 'number'
            and math.max(0, module.availableHeight - (module.headerHeight or 0))
        or math.huge
    if
        module:IsCollapsed()
        or not module.firstBlock
        or not module.ContentsFrame
        or (module.numCachedBlocks or 0) > 0
    then
        if not module:IsCollapsed() and module.EnumerateActiveBlocks then
            module:EnumerateActiveBlocks(function(block)
                if block.template == module.blockTemplate then
                    alignTrackerPOI(block)
                end
            end)
        end
        local height = updateNativeScroll(
            module,
            math.max(0, (module.contentsHeight or 0) - (module.headerHeight or 0)),
            heightBudget
        )
        if not module:IsCollapsed() then
            module.contentsHeight = (module.headerHeight or 0) + height
        end
        return
    end
    local questRegions, regionOrder = Trackers.LogRegions()
    local _, questIDs, trackedRegions = getTrackedState()
    local questGroups, otherBlocks, seen = {}, {}, {}
    local block = module.firstBlock
    while block and not seen[block] do
        seen[block] = true
        local questID = getNativeQuestID(block)
        if
            questID
            and (questIDs[questID] or questRegions[questID])
            and block.HeaderText
            and not block.cached
            and (not block.template or block.template == module.blockTemplate)
        then
            local zone = questRegions[questID] or L['Other quests']
            trackedRegions[zone] = true
            questGroups[zone] = questGroups[zone] or {}
            table.insert(questGroups[zone], block)
        else
            table.insert(otherBlocks, block)
        end
        block = block.nextBlock
    end
    if not next(questGroups) then
        local height = updateNativeScroll(
            module,
            math.max(0, (module.contentsHeight or 0) - (module.headerHeight or 0)),
            heightBudget
        )
        if not module:IsCollapsed() then
            module.contentsHeight = (module.headerHeight or 0) + height
        end
        return
    end
    local regionNames = {}
    for zone in pairs(trackedRegions) do
        regionNames[#regionNames + 1] = zone
    end
    table.sort(regionNames, function(firstRegion, secondRegion)
        local firstOrder = regionOrder[firstRegion] or math.huge
        local secondOrder = regionOrder[secondRegion] or math.huge
        if firstOrder == secondOrder then
            return firstRegion < secondRegion
        end
        return firstOrder < secondOrder
    end)
    local headerGap = math.max(0, -(module.fromHeaderOffsetY or 0))
    local blockGap = math.max(0, -(module.fromBlockOffsetY or -3))
    local expandedRegionGap = math.max(0, blockGap - 2)
    local offsetY = headerGap
    local available = nativeState.scroll and math.huge or heightBudget
    -- Keep non-quest blocks (auto-completion popups etc.) in their native section.
    local function place(questBlock, height)
        -- Preserve horizontal native anchors and replace only the vertical one.
        local points = {}
        for index = 1, questBlock:GetNumPoints() do
            local point, relative, relativePoint, x, dy = questBlock:GetPoint(index)
            if point ~= 'TOP' then
                points[#points + 1] = { point, relative, relativePoint, x, dy }
            end
        end
        questBlock:ClearAllPoints()
        questBlock:SetPoint('TOP', module.ContentsFrame, 'TOP', 0, -offsetY)
        for _, point in ipairs(points) do
            questBlock:SetPoint(unpack(point, 1, 5))
        end
        questBlock:SetHeight(height)
        offsetY = offsetY + height + blockGap
    end
    local function suppress(questBlock)
        hideNativeFrame(questBlock, questBlock)
        for region in pairs(questBlock.addedRegions or {}) do
            hideNativeFrame(region, questBlock)
        end
    end
    for _, questBlock in ipairs(otherBlocks) do
        place(questBlock, questBlock.height or questBlock:GetHeight())
    end
    for _, zone in ipairs(regionNames) do
        local header = getRegionHeader(module, zone)
        local height = header:GetHeight()
        if offsetY + height <= available then
            header:ClearAllPoints()
            header:SetPoint('TOPLEFT', module.ContentsFrame, 'TOPLEFT', module.blockOffsetX or 0, -offsetY)
            header:SetPoint('RIGHT', module.ContentsFrame, 'RIGHT', 0, 0)
            header.label:SetText(zone .. (nativeState.regions[zone] and ' +' or ' -'))
            header:Show()
            -- Tighten the gap only between an expanded region and its first quest.
            local expanded = not nativeState.regions[zone] and #(questGroups[zone] or {}) > 0
            offsetY = offsetY + height + (expanded and expandedRegionGap or blockGap)
            for _, questBlock in ipairs(questGroups[zone] or {}) do
                bindNativeBlock(questBlock)
                if nativeState.regions[zone] then
                    suppress(questBlock)
                else
                    local fullHeight = questBlock.height or questBlock:GetHeight()
                    local collapsedHeight = math.max(1, questBlock.HeaderText:GetHeight())
                    local visibleHeight = nativeState.quests[getNativeQuestID(questBlock)] and collapsedHeight
                        or fullHeight
                    if offsetY + visibleHeight <= available then
                        if nativeState.quests[getNativeQuestID(questBlock)] then
                            if questBlock.ForEachUsedLine then
                                questBlock:ForEachUsedLine(function(line)
                                    hideNativeFrame(line, questBlock)
                                end)
                            end
                            for region in pairs(questBlock.addedRegions or {}) do
                                hideNativeFrame(region, questBlock)
                            end
                        end
                        place(questBlock, visibleHeight)
                    else
                        suppress(questBlock)
                        module.hasSkippedBlocks = true
                    end
                end
            end
        else
            for _, questBlock in ipairs(questGroups[zone] or {}) do
                suppress(questBlock)
            end
            module.hasSkippedBlocks = true
        end
    end
    module.contentsHeight = (module.headerHeight or 0)
        + updateNativeScroll(module, math.max(0, offsetY - blockGap), heightBudget)
end
Trackers.NativeLayout = layoutNativeQuests
Trackers.RestoreNative = restoreNativeFrames

-- Older trackers share global names but do not implement the pooled layout contract.
local function supportsNativeLayout(module)
    return isAccessibleFrame(module)
        and type(module.LayoutContents) == 'function'
        and type(module.BeginLayout) == 'function'
        and type(module.OnBlockHeaderEnter) == 'function'
        and type(module.MarkDirty) == 'function'
        and type(module.IsCollapsed) == 'function'
        and module.Header ~= nil
        and module.ContentsFrame ~= nil
end

local function findNativeQuestModule(root)
    local questModule = _G.QuestObjectiveTracker or _G.QuestObjectiveTrackerModule
    if supportsNativeLayout(questModule) then
        return questModule
    end
    if root and type(root.modules) == 'table' then
        for _, module in ipairs(root.modules) do
            if module.blockTemplate == 'ObjectiveTrackerQuestPOIBlockTemplate' and supportsNativeLayout(module) then
                return module
            end
        end
    end
    if root and root.GetChildren then
        for _, module in ipairs({ root:GetChildren() }) do
            if module.blockTemplate == 'ObjectiveTrackerQuestPOIBlockTemplate' and supportsNativeLayout(module) then
                return module
            end
        end
    end
end

-- Header styling and controls for the native tracker and its non-quest categories.

-- Append capacity to the native title, preserving its font and localized wording.
local function updateNativeQuestCount(module, state)
    local titleLabel = module.Header and module.Header.Text
    if not titleLabel or not titleLabel.GetText or not titleLabel.SetText then
        return
    end
    local currentText = titleLabel:GetText()
    if
        isReadable(currentText)
        and type(currentText) == 'string'
        and currentText ~= ''
        and currentText ~= nativeState.countText
    then
        nativeState.countTitle = currentText
    end
    local baseTitle = nativeState.countTitle or QUESTS or L['Quests']
    local questCount = #state.quests
    local _, count = Compat.GetNumQuestLogEntries()
    if isReadable(count) and type(count) == 'number' then
        questCount = count
    end
    local capacity = Compat.GetMaxQuests() or 40
    if type(capacity) ~= 'number' or capacity <= 0 then
        capacity = 40
    end
    nativeState.countText = ('%s (%d/%d)'):format(baseTitle, questCount, capacity)
    if isReadable(currentText) and currentText ~= nativeState.countText then
        titleLabel:SetText(nativeState.countText)
    end
end

-- Center the native title and control on the decorative header's actual midpoint.
local function centerMainHeader(header, buttonOffset, plain)
    if not header then
        return
    end
    local anchor = not plain and header.Background or header
    local label, button = header.Text, header.MinimizeButton
    local function align(region, point, x)
        if not region or not region.ClearAllPoints then
            return
        end
        local currentPoint, relative, relativePoint, currentOffsetX, currentOffsetY = region:GetPoint(1)
        if
            region:GetNumPoints() ~= 1
            or currentPoint ~= point
            or relative ~= anchor
            or relativePoint ~= point
            or currentOffsetX ~= x
            or currentOffsetY ~= 0
        then
            region:ClearAllPoints()
            region:SetPoint(point, anchor, point, x, 0)
        end
    end
    align(label, 'LEFT', 7)
    if label and label.SetJustifyV then
        label:SetJustifyV('MIDDLE')
    end
    align(button, 'RIGHT', buttonOffset or 1)
end

-- All Objectives is a plain clickable heading; use the secondary header's sign atlas.
local function updateRootSign(root, collapsed)
    local header = root.Header
    if not header then
        return
    end
    local sign = header.QuestloggerCollapseSign
    if not sign then
        return
    end
    if collapsed == nil then
        collapsed = root.IsCollapsed and root:IsCollapsed() or root.collapsed
    end
    sign:SetAtlas(
        collapsed and 'ui-questtrackerbutton-secondary-expand' or 'ui-questtrackerbutton-secondary-collapse',
        false
    )
end

local function styleRootHeader(root)
    local header = root.Header
    if not header then
        return
    end
    if header.Background then
        header.Background:Hide()
    end
    if header.TopBorder then
        header.TopBorder:Hide()
    end
    if header.MinimizeButton then
        header.MinimizeButton:Hide()
    end
    if not header.QuestloggerCollapseSign and header.CreateTexture then
        local sign = header:CreateTexture(nil, 'ARTWORK')
        sign:SetSize(16, 16)
        sign:SetPoint('RIGHT', header, 'RIGHT', 1, 0)
        header.QuestloggerCollapseSign = sign
        if type(header.SetCollapsed) == 'function' then
            hooksecurefunc(header, 'SetCollapsed', function(_, collapsed)
                updateRootSign(root, collapsed)
            end)
        end
        if header.MinimizeButton and header.MinimizeButton.HookScript then
            header.MinimizeButton:HookScript('OnShow', function(self)
                self:Hide()
            end)
        end
    end
    updateRootSign(root)
    -- Retain the title's native left indent; only the root artwork is removed.
    centerMainHeader(header, -1, true)
end

-- Match All Objectives' sign size while keeping the native clickable button.
local function styleCategorySign(module, collapsed)
    local button = module.Header and module.Header.MinimizeButton
    if not isAccessibleFrame(button) then
        return
    end
    if collapsed == nil then
        collapsed = module.IsCollapsed and module:IsCollapsed() or module.collapsed
    end
    local atlas = collapsed and 'ui-questtrackerbutton-secondary-expand' or 'ui-questtrackerbutton-secondary-collapse'
    -- Independent overlay: Blizzard can replace/hide a button's own normal texture.
    local header = module.Header
    local signHolder = header.QuestloggerSignHolder
    if not signHolder then
        signHolder = CreateFrame('Frame', nil, header)
        signHolder:SetSize(16, 16)
        signHolder:SetPoint('RIGHT', header, 'RIGHT', -2, 0)
        if signHolder.SetFrameLevel and button.GetFrameLevel then
            signHolder:SetFrameLevel(button:GetFrameLevel() + 2)
        end
        signHolder:EnableMouse(false)
        signHolder.sign = signHolder:CreateTexture(nil, 'OVERLAY')
        signHolder.sign:SetSize(16, 16)
        signHolder.sign:SetPoint('CENTER', signHolder, 'CENTER', 0, 0)
        header.QuestloggerSignHolder = signHolder
    end
    signHolder.sign:SetAtlas(atlas, false)
    signHolder:Show()
    signHolder.sign:Show()
    for _, getter in ipairs({ 'GetNormalTexture', 'GetPushedTexture', 'GetHighlightTexture' }) do
        local texture = call(button[getter], button)
        if isAccessibleFrame(texture) and texture.SetAlpha then
            texture:SetAlpha(0)
        end
    end
end

local categoryState = setmetatable({}, { __mode = 'k' })
local function getReadableCount(value)
    return isReadable(value) and type(value) == 'number' and value >= 0 and value % 1 == 0 and value or nil
end

-- Use tracked data, not the collapsed module's empty block pool.
local function getCategoryCount(module, state, title)
    if
        module.AddRecipe
        or title == PROFESSIONS_TRACKER_HEADER_PROFESSION
        or title == L['Professions']
        or title == L['Profession']
    then
        local getTrackedRecipes = C_TradeSkillUI and C_TradeSkillUI.GetRecipesTracked
        local normalRecipes, recraftRecipes = call(getTrackedRecipes, false), call(getTrackedRecipes, true)
        if type(normalRecipes) == 'table' and type(recraftRecipes) == 'table' then
            return #normalRecipes + #recraftRecipes
        end
        if type(normalRecipes) == 'table' then
            return #normalRecipes
        end
    elseif module.AddAchievement or title == TRACKER_HEADER_ACHIEVEMENTS or title == L['Achievements'] then
        local kind = Enum and Enum.ContentTrackingType and Enum.ContentTrackingType.Achievement
        local trackedIDs = kind ~= nil and call(C_ContentTracking and C_ContentTracking.GetTrackedIDs, kind)
        if type(trackedIDs) == 'table' then
            return #trackedIDs
        end
        local count = call(GetNumTrackedAchievements)
        if getReadableCount(count) then
            return count
        end
    end
    local count = getReadableCount(module.entryCount)
    if count then
        return count
    end
    if isReadable(module.currentContentList) and type(module.currentContentList) == 'table' then
        return #module.currentContentList
    end
    return state.lastCount
end

local function updateCategoryHeader(module, collapsed, afterLayout)
    if inCombat() or not isAccessibleFrame(module) then
        return
    end
    local header = module.Header
    local label = header and header.Text
    if not label or not label.GetText or not label.SetText then
        return
    end
    if collapsed == nil then
        collapsed = module.IsCollapsed and module:IsCollapsed() or module.collapsed
    end
    styleCategorySign(module, collapsed)
    if module == nativeState.module then
        return
    end
    local state = categoryState[module]
    if not state then
        state = {}
        categoryState[module] = state
    end
    local text = label:GetText()
    if not isReadable(text) or type(text) ~= 'string' then
        return
    end
    if text ~= state.output and text ~= '' then
        state.title = text
    end
    local title = state.title
    if not title then
        return
    end
    -- Remember a complete expanded layout as a fallback for unfamiliar modules.
    if afterLayout and not collapsed and not module.hasSkippedBlocks and module.firstBlock then
        local count, seen, block = 0, {}, module.firstBlock
        while block and not seen[block] do
            seen[block] = true
            if not block.cached then
                count = count + 1
            end
            block = block.nextBlock
        end
        state.lastCount = count
    end
    local count = collapsed and getCategoryCount(module, state, title) or nil
    local output = count and ('%s (%d)'):format(title, count) or title
    state.output = output
    if text ~= output then
        label:SetText(output)
    end
end

-- Non-quest categories retain their native rows. Only expose actions supported by the module.
local function getEntryTrackingAdapter(module, title)
    local professionAPI = C_TradeSkillUI
    if
        (
            module.AddRecipe
            or title == PROFESSIONS_TRACKER_HEADER_PROFESSION
            or title == L['Professions']
            or title == L['Profession']
        )
        and professionAPI
        and professionAPI.GetRecipesTracked
        and professionAPI.SetRecipeTracked
    then
        return function()
            local entries = {}
            for _, recraft in ipairs({ false, true }) do
                local trackedIDs = call(professionAPI.GetRecipesTracked, recraft)
                for _, entryID in ipairs(type(trackedIDs) == 'table' and trackedIDs or {}) do
                    if getReadableID(entryID) then
                        entries[#entries + 1] = { id = entryID, recraft = recraft }
                    end
                end
            end
            return entries
        end, function(entry, enabled)
            professionAPI.SetRecipeTracked(entry.id, enabled, entry.recraft)
        end
    end
    local trackingAPI = C_ContentTracking
    local trackingType = Enum and Enum.ContentTrackingType and Enum.ContentTrackingType.Achievement
    if
        (module.AddAchievement or title == TRACKER_HEADER_ACHIEVEMENTS or title == L['Achievements'])
        and trackingType ~= nil
        and trackingAPI
        and trackingAPI.GetTrackedIDs
        and trackingAPI.StartTracking
        and trackingAPI.StopTracking
        and Enum.ContentTrackingStopType
        and Enum.ContentTrackingStopType.Manual ~= nil
    then
        return function()
            local entries = {}
            local trackedIDs = call(trackingAPI.GetTrackedIDs, trackingType)
            for _, entryID in ipairs(type(trackedIDs) == 'table' and trackedIDs or {}) do
                if getReadableID(entryID) then
                    entries[#entries + 1] = { id = entryID }
                end
            end
            return entries
        end, function(entry, enabled)
            if enabled then
                trackingAPI.StartTracking(trackingType, entry.id)
            else
                trackingAPI.StopTracking(trackingType, entry.id, Enum.ContentTrackingStopType.Manual)
            end
        end
    end
end

local function isCategoryCollapsed(module)
    return module.IsCollapsed and module:IsCollapsed() or module.collapsed
end

local function refreshCategoryToolbar(module, state)
    local bar = state.bar
    if not bar or inCombat() then
        return
    end
    local root = state.root
    local collapsed = isCategoryCollapsed(module)
    local expanded = isVisible(root)
        and isVisible(module)
        and not collapsed
        and module.firstBlock ~= nil
        and (not root.IsCollapsed or not root:IsCollapsed())
        and state.reserved
    local tracked = state.getTracked and state.getTracked() or {}
    if expanded then
        positionToolbar(state, module.Header, true)
    end
    local plural = ({
        Profession = L['Professions'],
        Achievement = L['Achievements'],
        Campaign = L['Campaigns'],
        Scenario = L['Scenarios'],
        Activity = L['Activities'],
    })[state.title] or state.title
    -- Native category titles are already localized; only English uses the old lowercase wording.
    local noun = (L.locale == 'enUS' or L.locale == 'enGB') and plural:lower() or plural
    local labels = {
        (state.groupFolded and '+ ' or '- ') .. plural,
        state.folded and L['+ Entries'] or L['- Entries'],
        L['- Track'],
    }
    local tips = {
        L.Format(state.groupFolded and 'Expand all %s' or 'Collapse all %s', noun),
        state.folded and L['Expand all entries'] or L['Collapse all entries'],
        L.Format('Untrack all %s', noun),
    }
    for index, button in ipairs(bar.buttons) do
        local enabled = expanded and (index < 3 or #tracked > 0)
        button.label:SetText(labels[index])
        setButtonTip(button, tips[index])
        button:SetEnabled(not not enabled)
        button.label:SetAlpha(enabled and 1 or 0.45)
    end
    bar:SetShown(not not expanded)
end

local function bindCategoryEntryClicks(module, state)
    if not state.getTracked or type(module.OnBlockHeaderClick) ~= 'function' then
        return
    end
    local originalClick = module.OnBlockHeaderClick
    module.OnBlockHeaderClick = function(self, block, button, ...)
        if button == 'LeftButton' and IsShiftKeyDown and IsShiftKeyDown() then
            if inCombat() or not block or block.parentModule ~= self then
                return
            end
            local id = block.id
            if not isReadable(id) or type(id) ~= 'number' then
                return
            end
            for _, entry in ipairs(state.getTracked()) do
                -- Native recipe blocks use a negative ID for recrafts of the same recipe.
                local matches = entry.id == id
                if entry.recraft ~= nil then
                    matches = entry.id == math.abs(id) and entry.recraft == (id < 0)
                end
                if matches then
                    pcall(state.setTracked, entry, false)
                    self:MarkDirty()
                    refreshCategoryToolbar(self, state)
                    return
                end
            end
            return
        end
        return originalClick(self, block, button, ...)
    end
end

local function restoreCategoryRows(module, state)
    for frame, record in pairs(state.hidden) do
        local block = record.block
        if
            block.id == record.id
            and block.parentModule == module
            and isAccessibleFrame(frame)
            and (not module.GetExistingBlock or module:GetExistingBlock(block.id, block.template) == block)
        then
            frame:Show()
        end
    end
    state.hidden = {}
end

local function layoutCategoryRows(module, state)
    if inCombat() then
        return
    end
    state.reserved = module.firstBlock ~= nil and not isCategoryCollapsed(module)
    if not state.reserved or not (state.folded or state.groupFolded) or (module.numCachedBlocks or 0) > 0 then
        return
    end
    local block, seen = module.firstBlock, {}
    local allHidden = true
    while block and not seen[block] do
        seen[block] = true
        if not block.cached and block.HeaderText and block.ForEachUsedLine and block.parentModule == module then
            local function suppress(frame)
                if isAccessibleFrame(frame) and frame.IsShown and frame:IsShown() then
                    state.hidden[frame] = { block = block, id = block.id }
                    frame:Hide()
                end
            end
            block:ForEachUsedLine(suppress)
            for region in pairs(block.addedRegions or {}) do
                suppress(region)
            end
            if state.groupFolded then
                suppress(block)
            end
            local fullHeight = block:GetHeight()
            local collapsedHeight = state.groupFolded and 1 or math.max(1, block.HeaderText:GetHeight())
            block:SetHeight(math.min(fullHeight, collapsedHeight))
            module.contentsHeight =
                math.max(module.headerHeight or 0, module.contentsHeight - math.max(0, fullHeight - collapsedHeight))
        else
            allHidden = false
        end
        block = block.nextBlock
    end
    if state.groupFolded and allHidden then
        module.contentsHeight = (module.headerHeight or 0) + BAR_SPACE
    end
end

local function installCategoryControls(module, state, root)
    if
        not state
        or state.controls
        or not state.title
        or not module.ContentsFrame
        or not module.MarkDirty
        or not module.BeginLayout
        or not module.LayoutContents
        or not module.EndLayout
        or type(module.fromHeaderOffsetY) ~= 'number'
        or not module.GetNextBlockAnchoring
    then
        return
    end
    state.controls = true
    state.category = true
    state.root = root
    state.hidden = {}
    state.getTracked, state.setTracked = getEntryTrackingAdapter(module, state.title)
    bindCategoryEntryClicks(module, state)
    local actions = {
        function()
            state.groupFolded = not state.groupFolded
            module:MarkDirty()
            refreshCategoryToolbar(module, state)
        end,
        function()
            state.folded = not state.folded
            module:MarkDirty()
            refreshCategoryToolbar(module, state)
        end,
    }
    if state.getTracked then
        actions[3] = function()
            -- Non-quest tracking is one-way; re-track entries using the original game UI.
            for _, entry in ipairs(state.getTracked()) do
                pcall(state.setTracked, entry, false)
            end
            module:MarkDirty()
            refreshCategoryToolbar(module, state)
        end
    end
    ensureToolbar(module, state, actions)
    module.QuestloggerCategoryToolbar = state.bar
    -- The native height calculation already accounts for fromHeaderOffsetY.
    -- Reserve the toolbar once; preserve the original gap while collapsed.
    local originalOffset = module.fromHeaderOffsetY
    hooksecurefunc(module, 'BeginLayout', function(self)
        if inCombat() then
            return
        end
        restoreCategoryRows(self, state)
        self.fromHeaderOffsetY = originalOffset - (isCategoryCollapsed(self) and 0 or BAR_SPACE)
    end)
    hooksecurefunc(module, 'LayoutContents', function(self)
        layoutCategoryRows(self, state)
    end)
    hooksecurefunc(module, 'EndLayout', function(self)
        refreshCategoryToolbar(self, state)
    end)
    if type(module.Header.SetCollapsed) == 'function' then
        hooksecurefunc(module.Header, 'SetCollapsed', function()
            refreshCategoryToolbar(module, state)
        end)
    end
    module:MarkDirty()
end

local categoryHooks = setmetatable({}, { __mode = 'k' })
local function bindCategory(module, root)
    local header = module.Header
    if not isAccessibleFrame(header) then
        return
    end
    if categoryHooks[module] ~= header then
        categoryHooks[module] = header
        if type(header.SetCollapsed) == 'function' then
            hooksecurefunc(header, 'SetCollapsed', function(_, collapsed)
                updateCategoryHeader(module, collapsed)
            end)
        end
        if type(module.EndLayout) == 'function' then
            hooksecurefunc(module, 'EndLayout', function(self)
                updateCategoryHeader(self, nil, true)
            end)
        end
    end
    updateCategoryHeader(module, nil, true)
    if module ~= nativeState.module then
        local state = categoryState[module]
        installCategoryControls(module, state, root)
        if state then
            refreshCategoryToolbar(module, state)
        end
    end
end

-- Let the entire native header activate its existing minimize action.
local boundHeaders = setmetatable({}, { __mode = 'k' })
local function bindMainHeader(owner, isRoot)
    local header = owner and owner.Header
    local button = header and header.MinimizeButton
    if
        not isAccessibleFrame(header)
        or not isAccessibleFrame(button)
        or boundHeaders[header]
        or not header.EnableMouse
        or not header.HookScript
        or not button.Click
    then
        return
    end
    -- Respect other addons that already handle header clicks.
    if
        header.GetScript
        and (header:GetScript('OnMouseUp') or header:GetScript('OnMouseDown') or header:GetScript('OnClick'))
    then
        return
    end
    boundHeaders[header] = true
    header:EnableMouse(true)
    header:HookScript('OnMouseUp', function(self, mouseButton)
        if mouseButton ~= 'LeftButton' or inCombat() or not isVisible(self) then
            return
        end
        if
            isRoot
            and nativeState.geometry
            and nativeState.geometry.enabled
            and (IsShiftKeyDown and IsShiftKeyDown())
        then
            return
        end
        if
            EditModeManagerFrame
            and EditModeManagerFrame.IsEditModeActive
            and EditModeManagerFrame:IsEditModeActive()
        then
            return
        end
        if self.IsMouseOver and not self:IsMouseOver() then
            return
        end
        local minimize = self.MinimizeButton
        if
            not isAccessibleFrame(minimize)
            or not minimize.Click
            or (minimize.IsEnabled and not minimize:IsEnabled())
        then
            return
        end
        -- Child buttons keep their own clicks; do not toggle twice.
        for _, child in pairs({ minimize, self.FilterButton }) do
            if isVisible(child) and child.IsMouseOver and child:IsMouseOver() then
                return
            end
        end
        if isRoot and self.OnToggle then
            self:OnToggle()
        else
            minimize:Click('LeftButton')
        end
        if isRoot then
            updateRootSign(owner)
        end
    end)
end

local function bindMainHeaders(root)
    bindMainHeader(root, true)
    if root.Header and boundHeaders[root.Header] then
        styleRootHeader(root)
    end
    if type(root.modules) == 'table' then
        for _, module in ipairs(root.modules) do
            bindMainHeader(module)
            centerMainHeader(module.Header)
            bindCategory(module, root)
        end
    end
    if nativeState.module then
        bindMainHeader(nativeState.module)
        centerMainHeader(nativeState.module.Header)
        bindCategory(nativeState.module, root)
    end
end

local function refreshNativeToolbar(root, state, questIDs, regionNames)
    if not nativeState.bar then
        return
    end
    if not state then
        state, questIDs, regionNames = getTrackedState()
    end
    local module = nativeState.module
    local collapsed = root.IsCollapsed and root:IsCollapsed()
    local inside = isVisible(root)
        and isVisible(module)
        and not collapsed
        and not module:IsCollapsed()
        and nativeState.toolbarReserved
        and module.firstBlock ~= nil
    local showEmptyToolbar = not collapsed
        and state.tracked == 0
        and #state.quests > 0
        and (isVisible(root) or nativeState.keepEmpty)
    positionToolbar(nativeState, inside and module.Header or root, inside)
    updateToolbar(
        nativeState,
        questIDs,
        regionNames,
        nativeState.regions,
        nativeState.quests,
        state.tracked > 0,
        #state.quests,
        true,
        inside or showEmptyToolbar
    )
end

local function installNativeTracker(root)
    if nativeState.module then
        return
    end
    local module = findNativeQuestModule(root)
    if not module then
        return
    end
    nativeState.module = module
    installNativeScroll(module)
    module:HookScript('OnHide', function()
        if nativeState.bar and nativeState.barInside then
            nativeState.bar:Hide()
        end
    end)
    hooksecurefunc(module, 'BeginLayout', function()
        if inCombat() then
            return
        end
        restoreNativeFrames()
        nativeState.inLayout = true
    end)
    -- Allow Blizzard to construct every watched quest before compacting the rows.
    -- Restore its real height budget before the module reports its layout size.
    if type(module.BuildQuestWatchInfos) == 'function' then
        hooksecurefunc(module, 'BuildQuestWatchInfos', function(self)
            if
                nativeState.inLayout
                and not inCombat()
                and not self:IsCollapsed()
                and (self.numCachedBlocks or 0) == 0
                and type(self.availableHeight) == 'number'
                and self.availableHeight > 0
                and not nativeState.heightBudget
            then
                nativeState.heightBudget = self.availableHeight
                self.availableHeight = 100000
            end
        end)
    end
    hooksecurefunc(module, 'LayoutContents', function(self)
        if nativeState.heightBudget then
            self.availableHeight = nativeState.heightBudget
            nativeState.heightBudget = nil
        end
        nativeState.inLayout = nil
        layoutNativeQuests(self)
    end)
    if type(module.EndLayout) == 'function' then
        hooksecurefunc(module, 'EndLayout', function(self)
            if nativeState.heightBudget then
                self.availableHeight = nativeState.heightBudget
                nativeState.heightBudget = nil
            end
            nativeState.inLayout = nil
            if not inCombat() then
                if nativeState.scroll and (self:IsCollapsed() or not self.firstBlock) then
                    nativeState.scroll:Hide()
                end
                updateNativeQuestCount(self, addon.Controls.State())
                refreshNativeToolbar(root)
            end
        end)
    end
    hooksecurefunc(module, 'OnBlockHeaderEnter', function(_, block)
        showQuestHover(block, getNativeQuestID)
    end)
    requestNativeLayout()
end

-- Questie exposes its own collapse state. Do not rearrange its pooled lines.
local function importQuestieModule(name)
    if QuestieLoader and QuestieLoader.ImportModule then
        local ok, value = pcall(QuestieLoader.ImportModule, QuestieLoader, name)
        if ok then
            return value
        end
    end
end

local function getQuestieAddon()
    local questieAddon = _G.Questie
    if not (questieAddon and questieAddon.db) and QuestieLoader and LibStub then
        local ok, aceAddon = pcall(LibStub, 'AceAddon-3.0', true)
        if ok and aceAddon and aceAddon.GetAddon then
            questieAddon = call(aceAddon.GetAddon, aceAddon, 'Questie', true)
        end
    end
    return questieAddon
end

local function getQuestieDatabase()
    local questieAddon = getQuestieAddon()
    return questieAddon and questieAddon.db
end

-- Questie's initializer yields; never wrap it or touch its partial tracker.
local function isQuestieReady(questieAddon, tracker)
    if not questieAddon or not tracker or tracker.started ~= true then
        return false
    end
    if questieAddon.API then
        return questieAddon.API.isReady == true
    end
    return true -- Older Questie versions expose only the tracker readiness flag.
end

-- Prefer Blizzard's tracker. Keep the original Questie adapter below as a fallback
-- for versions without the live Toggle/Unhook/ShowWatchFrame interfaces. Never call
-- Disable(): current Questie clears watch settings and reloads the UI there.
local function preferNativeTracker(questieAddon, tracker, db, qroot)
    local root = _G.ObjectiveTrackerFrame
    if not nativeState.module or not isAccessibleFrame(root) or not isQuestieReady(questieAddon, tracker) then
        return false
    end
    if questieState.attemptedProfile == db.profile then
        return false
    end
    questieState.attemptedProfile = db.profile
    local compat = importQuestieModule('QuestieCompat')
    if
        type(tracker.Toggle) ~= 'function'
        or type(tracker.Unhook) ~= 'function'
        or not compat
        or type(compat.ShowWatchFrame) ~= 'function'
    then
        return false
    end
    local ok = pcall(function()
        tracker:Toggle()
        assert(db.profile.trackerEnabled == false)
        tracker:Unhook()
        compat.ShowWatchFrame()
        if qroot:IsShown() and tracker.Hide then
            tracker:Hide()
        end
    end)
    if ok and db.profile.trackerEnabled == false and not qroot:IsShown() then
        questieState.attemptedProfile = nil
        requestNativeLayout()
        return true
    end
    -- Roll back and leave the compatibility tracker functional if the API changed.
    db.profile.trackerEnabled = true
    if tracker.HookBaseTracker then
        pcall(tracker.HookBaseTracker, tracker)
    end
    if compat.HideWatchFrame then
        pcall(compat.HideWatchFrame)
    end
    if tracker.Show then
        pcall(tracker.Show, tracker)
    end
    pcall(tracker.Update, tracker)
    return false
end

local function getQuestieState(db)
    local state = addon.Controls.State()
    local questIDs, regionNames = {}, {}
    local questRegions = Trackers.LogRegions()
    local trackerUtils = questieState.utils
    local _, questDetails = call(trackerUtils and trackerUtils.GetSortedQuestIds, trackerUtils)
    for _, quest in ipairs(state.quests) do
        local tracked
        if db.profile.autoTrackQuests then
            tracked = not (db.char.AutoUntrackedQuests and db.char.AutoUntrackedQuests[quest.id])
        else
            tracked = db.char.TrackedQuests and db.char.TrackedQuests[quest.id]
        end
        if tracked then
            questIDs[quest.id] = true
            local questInfo = type(questDetails) == 'table' and questDetails[quest.id]
            local name = questInfo and questInfo.zoneName or questRegions[quest.id] or L['Other quests']
            regionNames[name] = true
        end
    end
    return state, questIDs, regionNames
end

local function refreshQuestie()
    if inCombat() or not isQuestieReady(getQuestieAddon(), questieState.module) then
        return
    end
    questieState.module:Update()
    -- Some Questie versions throttle updates in the same frame.
    if C_Timer and C_Timer.After then
        C_Timer.After(0.3, function()
            if
                not inCombat()
                and isQuestieReady(getQuestieAddon(), questieState.module)
                and getQuestieDatabase()
                and getQuestieDatabase().profile.trackerEnabled
            then
                questieState.module:Update()
            end
        end)
    end
end

local function untrackQuestieEntry(line, db)
    local kind = getQuestieEntryType(line)
    local entry = kind == 'recipe' and line.Recipe or line.Quest
    local id = type(entry) == 'table' and getReadableID(entry.Id or entry.id)
    if not id then
        return false
    end
    if kind == 'quest' then
        local tracker = questieState.module
        if type(tracker.UntrackQuestId) == 'function' then
            pcall(tracker.UntrackQuestId, tracker, id)
        else
            -- Older Questie versions expose only their character watch tables.
            if db.profile.autoTrackQuests then
                db.char.AutoUntrackedQuests = db.char.AutoUntrackedQuests or {}
                db.char.AutoUntrackedQuests[id] = true
            elseif db.char.TrackedQuests then
                db.char.TrackedQuests[id] = nil
            end
            Compat.RemoveQuestWatch(id)
        end
    elseif kind == 'recipe' or kind == 'achieve' then
        local adapter = importQuestieModule(kind == 'recipe' and 'TrackerRecipes' or 'AchievementTracking')
        if not adapter or type(adapter.Untrack) ~= 'function' then
            return false
        end
        if kind == 'achieve' and type(adapter.IsTracked) == 'function' and not call(adapter.IsTracked, id) then
            return true
        end
        pcall(adapter.Untrack, id)
    else
        return false
    end
    refreshQuestie()
    Trackers.Refresh()
    return true
end

local function bindQuestieLine(line)
    if not isAccessibleFrame(line) or not line.HookScript or questieState.bound[line] then
        return
    end
    questieState.bound[line] = true
    line:HookScript('OnEnter', function(self)
        local db = getQuestieDatabase()
        if db and db.profile.trackerEnabled and isQuestieReady(getQuestieAddon(), questieState.module) then
            showQuestHover(self, getQuestieQuestID)
        end
    end)
    if not line.GetScript or not line.SetScript then
        return
    end
    local originalClick
    local function onClick(self, button, ...)
        local db = getQuestieDatabase()
        if
            button == 'LeftButton'
            and IsShiftKeyDown
            and IsShiftKeyDown()
            and db
            and db.profile.trackerEnabled
            and isQuestieReady(getQuestieAddon(), questieState.module)
        then
            if inCombat() or untrackQuestieEntry(self, db) then
                return
            end
        end
        if originalClick then
            return originalClick(self, button, ...)
        end
    end
    local function bindClick(self, mode)
        self.QuestloggerClickMode = mode or self.QuestloggerClickMode
        local currentClick = self:GetScript('OnClick')
        if currentClick ~= onClick then
            originalClick = currentClick
            self:SetScript('OnClick', onClick)
        end
    end
    bindClick(line)
    -- Questie replaces the script whenever a pooled line changes entry type.
    if type(line.SetOnClick) == 'function' then
        hooksecurefunc(line, 'SetOnClick', bindClick)
    end
end

local function scanQuestie(root, depth)
    if not root or depth > 5 or not root.GetChildren then
        return
    end
    for _, line in ipairs({ root:GetChildren() }) do
        if getQuestieEntryType(line) and (line.Quest or line.Recipe) and line.label and line.expandQuest then
            bindQuestieLine(line)
        end
        scanQuestie(line, depth + 1)
    end
end

local function restoreQuestieScroll()
    local record = questieState.scrollInset
    if not record then
        return
    end
    local scroll = record.scroll
    scroll:ClearAllPoints()
    for _, point in ipairs(record.points) do
        scroll:SetPoint(unpack(point, 1, 5))
    end
    questieState.scrollInset = nil
end

local function getQuestieList(root)
    local adapter = importQuestieModule('TrackerQuestFrame')
    local list = adapter and adapter.questFrame or _G.TrackedQuests
    if
        isAccessibleFrame(list)
        and list.GetParent
        and list:GetParent() == root
        and isAccessibleFrame(list.ScrollFrame)
    then
        return list
    end
end

local function positionQuestieToolbar(root, db, tracked, total)
    local list = getQuestieList(root)
    local expanded = db.char.isTrackerExpanded ~= false
    local inside = expanded and isVisible(list) and list:GetHeight() > BAR_SPACE
    if inside then
        local scroll = list.ScrollFrame
        if not questieState.scrollInset or questieState.scrollInset.scroll ~= scroll then
            restoreQuestieScroll()
            local points = {}
            for i = 1, scroll:GetNumPoints() do
                points[i] = { scroll:GetPoint(i) }
            end
            questieState.scrollInset = { scroll = scroll, points = points }
        end
        -- Shrink only the viewport; Questie's own rows and scroll child remain untouched.
        local point, relative, relativePoint, offsetX, offsetY = scroll:GetPoint(1)
        if
            point ~= 'TOPLEFT'
            or relative ~= list
            or relativePoint ~= 'TOPLEFT'
            or offsetX ~= 0
            or offsetY ~= -BAR_SPACE
        then
            scroll:ClearAllPoints()
            scroll:SetPoint('TOPLEFT', list, 'TOPLEFT', 0, -BAR_SPACE)
            scroll:SetPoint('BOTTOMRIGHT', list, 'BOTTOMRIGHT', 0, 0)
            if scroll.UpdateScrollChildRect then
                scroll:UpdateScrollChildRect()
            end
        end
        positionToolbar(questieState, list, true)
    else
        restoreQuestieScroll()
        positionToolbar(questieState, root, false)
    end
    -- Older Questie layouts without a known list frame keep the previous safe placement.
    return inside
        or (expanded and isVisible(root) and (not list or (isVisible(list) and list:GetHeight() <= BAR_SPACE)))
        or (expanded and not tracked and total > 0 and (isVisible(root) or questieState.keepEmpty))
end

local function installQuestieTracker(tracker)
    if questieState.module == tracker then
        return
    end
    questieState.module = tracker
    questieState.bound = setmetatable({}, { __mode = 'k' })
    questieState.utils = importQuestieModule('TrackerUtils')
end

-- Public entry points share a single refresh path after layouts, user actions, and events.
function Trackers.Refresh()
    if inCombat() then
        return
    end
    local root = _G.ObjectiveTrackerFrame
    if isAccessibleFrame(root) then
        installNativeTracker(root)
        if nativeState.module then
            bindMainHeaders(root)
            if nativeState.needsRefresh then
                nativeState.needsRefresh = nil
                requestNativeLayout()
            end
            local state, questIDs, regionNames = getTrackedState()
            updateNativeQuestCount(nativeState.module, state)
            ensureToolbar(root, nativeState, {
                function()
                    local _, _, regions = getTrackedState()
                    toggleCollapsedSet(regions, nativeState.regions)
                    requestNativeLayout()
                    Trackers.Refresh()
                end,
                function()
                    local _, questIDs = getTrackedState()
                    toggleCollapsedSet(questIDs, nativeState.quests)
                    requestNativeLayout()
                    Trackers.Refresh()
                end,
                function()
                    local state = addon.Controls.State()
                    nativeState.keepEmpty = state.tracked > 0
                    addon.Controls.ToggleTracking()
                    requestNativeLayout()
                    Trackers.Refresh()
                end,
            })
            refreshNativeToolbar(root, state, questIDs, regionNames)
        end
    end
    Trackers.RefreshQuestie()
    -- Observe pooled rows from our own timer, not from Questie's coroutine stack.
    if QuestieLoader and not questieState.ticker and C_Timer and C_Timer.NewTicker then
        questieState.ticker = C_Timer.NewTicker(0.5, Trackers.RefreshQuestie)
    end
end

function Trackers.RefreshQuestie()
    if inCombat() then
        return
    end
    local questieAddon = getQuestieAddon()
    local db = questieAddon and questieAddon.db
    local enabled = db and db.profile and db.char and db.profile.trackerEnabled
    local questieRoot = _G.Questie_BaseFrame
    local geometry = nativeState.module
        and isAccessibleFrame(_G.ObjectiveTrackerFrame)
        and geometryController.Install(_G.ObjectiveTrackerFrame)
    geometryController.SetEnabled(geometry, not enabled)
    local tracker = enabled
        and (not questieAddon.API or questieAddon.API.isReady == true)
        and QuestieLoader
        and importQuestieModule('QuestieTracker')
    if
        enabled
        and isAccessibleFrame(questieRoot)
        and isQuestieReady(questieAddon, tracker)
        and type(tracker.Update) == 'function'
    then
        if preferNativeTracker(questieAddon, tracker, db, questieRoot) then
            geometryController.SetEnabled(geometry, true)
            if questieState.bar then
                questieState.bar:Hide()
                restoreQuestieScroll()
            end
            return
        end
        installQuestieTracker(tracker)
        local characterSettings = db.char
        characterSettings.collapsedZones = characterSettings.collapsedZones or {}
        characterSettings.collapsedQuests = characterSettings.collapsedQuests or {}
        ensureToolbar(questieRoot, questieState, {
            function()
                local database = getQuestieDatabase()
                local _, _, regions = getQuestieState(database)
                toggleCollapsedSet(regions, database.char.collapsedZones)
                refreshQuestie()
                Trackers.Refresh()
            end,
            function()
                local database = getQuestieDatabase()
                local _, trackedQuestIDs = getQuestieState(database)
                toggleCollapsedSet(trackedQuestIDs, database.char.collapsedQuests)
                refreshQuestie()
                Trackers.Refresh()
            end,
            function()
                local database = getQuestieDatabase()
                local state, trackedQuestIDs = getQuestieState(database)
                local untrack = next(trackedQuestIDs) ~= nil
                questieState.keepEmpty = untrack
                database.char.TrackedQuests = database.char.TrackedQuests or {}
                database.char.AutoUntrackedQuests = database.char.AutoUntrackedQuests or {}
                for _, quest in ipairs(state.quests) do
                    if database.profile.autoTrackQuests then
                        database.char.AutoUntrackedQuests[quest.id] = untrack and true or nil
                    else
                        database.char.TrackedQuests[quest.id] = not untrack and true or nil
                    end
                end
                addon.Controls.ToggleTracking(not untrack)
                refreshQuestie()
                Trackers.Refresh()
            end,
        })
        local state, questIDs, regionNames = getQuestieState(db)
        scanQuestie(questieRoot, 0)
        local hiddenInInstance = db.profile.hideTrackerInInstances and IsInInstance and IsInInstance()
        local visible = false
        if hiddenInInstance then
            restoreQuestieScroll()
        else
            visible = positionQuestieToolbar(questieRoot, db, next(questIDs) ~= nil, #state.quests)
        end
        updateToolbar(
            questieState,
            questIDs,
            regionNames,
            characterSettings.collapsedZones,
            characterSettings.collapsedQuests,
            next(questIDs) ~= nil,
            #state.quests,
            not hiddenInInstance,
            visible
        )
        -- Questie may intentionally suppress the original tracker.
        if nativeState.bar and not isVisible(_G.ObjectiveTrackerFrame) then
            nativeState.bar:Hide()
        end
    elseif questieState.bar then
        questieState.bar:Hide()
        questieState.keepEmpty = nil
        restoreQuestieScroll()
    end
end

function Trackers.Disable()
    geometryController.Stop(nativeState.geometry)
    if nativeState.geometry then
        nativeState.geometry.moveSurface.captured = nil
        nativeState.geometry.moveSurface:EnableMouse(false)
        for _, edge in ipairs(nativeState.geometry.edges) do
            edge:EnableMouse(false)
        end
    end
    nativeState.needsRefresh = true
    for _, state in pairs(categoryState) do
        if state.bar then
            for _, button in ipairs(state.bar.buttons) do
                button:SetEnabled(false)
            end
        end
    end
    for _, state in ipairs({ nativeState, questieState }) do
        if state.bar then
            for _, button in ipairs(state.bar.buttons) do
                button:SetEnabled(false)
            end
        end
    end
end
