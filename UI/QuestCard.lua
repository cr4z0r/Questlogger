-- Renders the interactive quest card and its sections.
local _, addon = ...
local L = addon.L
local Compat = addon.Compat
local Data, UI = addon.Data, addon.UI
local Style = UI.TooltipStyle
local hideIcons = UI.HideRewardIcons
local QuestText = UI.QuestText

local card, mapCard, targetWidget
local showTargetWidget, selectTarget
local closePreview = UI.CloseEntityPreview
local CARD_WIDTH, CARD_PADDING = 340, 14
local CARD_CONTENT_WIDTH = CARD_WIDTH - 2 * CARD_PADDING
local FOLLOWUP_BOTTOM_PADDING = 12

-- Control spacing between title, body and objectives independently.
local TITLE_LINE_GAP = 3
local BODY_LINE_GAP = 5
local DESCRIPTION_OBJECTIVE_GAP = 2
local PARAGRAPH_GAP = 12

-- Only dismiss the tooltip owned by the Targets heading.
local function hideTargetHelp(button)
    if button and button.helpPopup then
        button.helpPopup:Hide()
    end
end

local function isMouseOver(frame)
    return frame and frame:IsVisible() and frame:IsMouseOver()
end

-- Keep the reward popup interactive without competing with native item tooltips.
local FOLLOWUP_GRACE, FOLLOWUP_RETRY = 0.45, 0.5
local renderBody, renderQuestText, resetCard, createCard
-- Both card types share the renderer and keep independent widget pools.
local function closeFollowup(frame)
    local popup = frame.followupPopup
    if popup then
        closePreview(popup)
        hideTargetHelp(popup.targetHelp)
        if popup.rewardHolder then
            hideIcons(popup.rewardHolder)
        end
        for _, button in ipairs(popup.unavailableLinks) do
            if GameTooltip:IsOwned(button) then
                GameTooltip:Hide()
            end
            button:Hide()
            button.entity = nil
        end
        popup:Hide()
    end
    frame.followupSource = nil
    frame.followupOutside = 0
end

local function isOverFollowup(frame)
    local popup = frame.followupPopup
    return isMouseOver(popup)
        or (popup and (isMouseOver(popup.entityPopup) or isMouseOver(popup.targetHelp and popup.targetHelp.helpPopup)))
end

local function sizeCard(frame, resetScroll)
    local padding = frame.isFollowup and FOLLOWUP_BOTTOM_PADDING or CARD_PADDING
    frame.content:SetHeight(math.max(1, frame.y))
    frame:SetHeight(math.min(frame.y + CARD_PADDING + padding, math.max(120, UIParent:GetHeight() * 0.78)))
    if resetScroll then
        frame.scroll:SetVerticalScroll(0)
    end
end

local function mapAnchor(frame)
    local map = frame.mapContext
    if not map then
        return false
    end
    local screenWidth, screenHeight = UIParent:GetWidth(), UIParent:GetHeight()
    local maximized = Compat.Call(map.IsMaximized, map)
    if maximized == nil and Compat.IsReadable(map.isMaximized) then
        maximized = map.isMaximized == true
    end
    local point, x, top = 'TOPRIGHT', screenWidth - 8, screenHeight - 48
    if not maximized then
        local list = map.QuestLog or QuestMapFrame
        if not list or Compat.Call(list.IsVisible, list) ~= true then
            list = map
        end
        local scale = Compat.Call(list.GetEffectiveScale, list) or 1
        local parentScale = Compat.Call(UIParent.GetEffectiveScale, UIParent) or 1
        if type(scale) ~= 'number' or scale <= 0 or type(parentScale) ~= 'number' or parentScale <= 0 then
            return true
        end
        scale = scale / parentScale
        local right = Compat.Call(list.GetRight, list)
        local listTop = Compat.Call(list.GetTop, list)
        if type(right) ~= 'number' then
            return true
        end
        point = 'TOPLEFT'
        x = math.max(8, math.min(screenWidth - frame:GetWidth() - 8, right * scale + 2))
        top = type(listTop) == 'number' and listTop * scale or top
    end
    top = math.max(frame:GetHeight() + 8, math.min(screenHeight - 8, top))
    local y = top - screenHeight
    if frame.anchorPoint ~= point or frame.anchorX ~= x or frame.anchorY ~= y then
        frame.anchorPoint, frame.anchorX, frame.anchorY = point, x, y
        frame:ClearAllPoints()
        -- Keep secure descendants anchored to UIParent rather than Blizzard's map.
        frame:SetPoint(point, UIParent, 'TOPLEFT', x, y)
    end
    return true
end

local function anchorCard(frame, owner)
    if mapAnchor(frame) then
        return
    end
    -- Keep the full card outside its source when the screen permits.
    local scale = (owner.GetEffectiveScale and UIParent.GetEffectiveScale)
            and owner:GetEffectiveScale() / UIParent:GetEffectiveScale()
        or 1
    local left, edge = owner:GetLeft(), owner:GetRight()
    -- Layout may temporarily release a pooled row while the tracker moves.
    if not left or not edge then
        return
    end
    left, edge = left * scale, edge * scale
    local right = UIParent:GetWidth() - edge
    local top = (owner.GetTop and owner:GetTop() or UIParent:GetHeight()) * scale
    local y = top - UIParent:GetHeight()
    if frame.trackerID then
        y = math.min(0, math.max(frame:GetHeight() - UIParent:GetHeight(), y))
    end
    local point, x = 'TOPLEFT', edge + 2
    if right < frame:GetWidth() + 2 and right < left then
        point, x = 'TOPRIGHT', left - 2
    end
    if frame.anchorPoint == point and frame.anchorX == x and frame.anchorY == y then
        return
    end
    frame.anchorPoint, frame.anchorX, frame.anchorY = point, x, y
    -- Secure descendants must never anchor to a Blizzard tracker or log row.
    frame:ClearAllPoints()
    frame:SetPoint(point, UIParent, 'TOPLEFT', x, y)
end

local function showFollowupCard(frame, source)
    local rewards, pending, unavailable = Data.FollowupRewards(source.questID)
    if not frame.followupPopup then
        frame.followupPopup = createCard(frame)
    end
    local popup = frame.followupPopup
    local same = popup:IsShown() and popup.questID == source.questID
    local scrollOffset = same and popup.scroll:GetVerticalScroll() or 0
    resetCard(popup)
    popup.questID = source.questID
    popup.rewardCount = #rewards
    local info = addon.GetSummary and addon.GetSummary(source.questID) or { future = {} }
    -- Do not mutate the cached summary with independently cached reward data.
    local data = {}
    for key, value in pairs(info) do
        data[key] = value
    end
    data.rewards, data.rewardsPending = rewards, pending
    data.rewardsUnavailable = unavailable
    local native, descriptionIndex, category = QuestText.FromAPI(popup.questID, source.questName)
    renderQuestText(popup, native, descriptionIndex, category, source.questName, popup.questID)
    renderBody(popup, popup.questID, data, source.xpFor, source.questName)
    sizeCard(popup, not same)
    if same then
        popup.scroll:SetVerticalScroll(math.min(scrollOffset, popup.scroll:GetVerticalScrollRange()))
    end
    if not same then
        -- Align with the source row, but beyond the main card's edge.
        local right = UIParent:GetWidth() - (frame:GetRight() or 0)
        local left = frame:GetLeft() or 0
        popup:ClearAllPoints()
        if right >= popup:GetWidth() + 2 or right >= left then
            popup:SetPoint('TOPLEFT', source, 'TOPRIGHT', CARD_PADDING + 2, 0)
        else
            popup:SetPoint('TOPRIGHT', source, 'TOPLEFT', -CARD_PADDING - 2, 0)
        end
    end
    popup:Show()
end

local function updateFollowup(frame, elapsed)
    -- Continue checking every pending follow-up, even before it is hovered.
    frame.followupScan = (frame.followupScan or 0) + elapsed
    if frame.followupScan >= FOLLOWUP_RETRY then
        frame.followupScan = 0
        for i = 1, frame.followupN do
            local source = frame.followupLinks[i]
            if source.pending then
                local rewards, pending = Data.FollowupRewards(source.questID, true)
                source.pending = pending
                -- Avoid rebuilding active model/item previews on every retry.
                local popup = frame.followupPopup
                if frame.followupSource == source and (not pending or #rewards ~= popup.rewardCount) then
                    showFollowupCard(frame, source)
                end
            end
        end
    end
    local source = frame.followupSource
    if not source then
        return
    end
    local popup = frame.followupPopup
    if popup and popup:IsShown() then
        UI.UpdateEntityPreview(popup, elapsed)
    end
    if isMouseOver(source) or isOverFollowup(frame) then
        frame.followupOutside = 0
    else
        frame.followupOutside = frame.followupOutside + elapsed
        if frame.followupOutside > FOLLOWUP_GRACE then
            closeFollowup(frame)
        end
    end
end

-- Hide secure card containers at combat start without insecure frame mutations.
local function registerCombatHide(frame)
    if RegisterStateDriver then
        frame:SetAttribute('_onstate-qlcombat', [[if newstate == 'combat' then self:Hide() end]])
        RegisterStateDriver(frame, 'qlcombat', '[combat] combat; peaceful')
    end
end

createCard = function(parent, forMap)
    local name
    if not parent then
        name = forMap and 'QuestloggerMapCard' or 'QuestloggerHoverCard'
    end
    local frame = CreateFrame('Frame', name, parent or UIParent, 'SecureHandlerStateTemplate')
    frame.rootCard = parent and (parent.rootCard or parent) or frame
    if not parent then
        registerCombatHide(frame)
    end
    -- A child card is interactive, but cannot open another quest card.
    frame.isFollowup = parent ~= nil
    -- Place the card below native item and help tooltips.
    frame:SetFrameStrata('FULLSCREEN_DIALOG')
    frame:SetFrameLevel(parent and 30 or 20)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    Style.Apply(frame)
    frame:SetWidth(CARD_WIDTH)
    local scroll = CreateFrame('ScrollFrame', nil, frame)
    scroll:SetPoint('TOPLEFT', CARD_PADDING, -CARD_PADDING)
    scroll:SetPoint('BOTTOMRIGHT', -CARD_PADDING, parent and FOLLOWUP_BOTTOM_PADDING or CARD_PADDING)
    local content = CreateFrame('Frame', nil, scroll)
    content:SetSize(CARD_CONTENT_WIDTH, 1)
    scroll:SetScrollChild(content)
    frame.scroll = scroll
    frame.content = content
    frame.lines = {}
    frame.links = {}
    frame.targets = {}
    frame.followupLinks = {}
    frame.followupSummaries = {}
    frame.unavailableLinks = {}
    scroll:EnableMouseWheel(true)
    frame:EnableMouseWheel(true)
    local function wheel(_, delta)
        closeFollowup(frame)
        closePreview(frame)
        hideTargetHelp(frame.targetHelp)
        scroll:SetVerticalScroll(
            math.max(0, math.min(scroll:GetVerticalScrollRange(), scroll:GetVerticalScroll() - delta * 32))
        )
    end
    scroll:SetScript('OnMouseWheel', wheel)
    frame:SetScript('OnMouseWheel', wheel)
    if not parent then
        frame:SetScript('OnUpdate', function(self, elapsed)
            local id = self.row
                and (self.trackerID and self.trackerID(self.row) or (not self.trackerID and self.row.questID))
            if Compat.InCombat() then
                return
            end
            if
                not self.row
                or not self.row:IsVisible()
                or (self.mapContext and Compat.Call(self.mapContext.IsVisible, self.mapContext) ~= true)
                or (issecretvalue and issecretvalue(id))
                or id ~= self.questID
            then
                self:Hide()
                return
            end
            anchorCard(self, self.row)
            updateFollowup(self, elapsed)
            UI.UpdateEntityPreview(self, elapsed)
            if
                self.pinned
                or isMouseOver(self)
                or isMouseOver(self.row)
                or isOverFollowup(self)
                or isMouseOver(self.entityPopup)
            then
                self.outside = 0
            else
                self.outside = (self.outside or 0) + elapsed
                if self.outside > (self.mapContext and 0.85 or 0.45) then
                    self:Hide()
                end
            end
        end)
    end
    frame:SetScript('OnHide', function(self)
        self.anchorPoint = nil
        self.row = nil
        self.questID = nil
        self.pinned = nil
        self.nativeSnapshot = nil
        self.trackerID = nil
        self.mapContext = nil
        if Compat.InCombat() then
            return
        end
        closeFollowup(self)
        closePreview(self)
        hideTargetHelp(self.targetHelp)
        if self.rewardHolder then
            hideIcons(self.rewardHolder)
        end
    end)
    frame:Hide()
    return frame
end

-- Clear reused widgets before rendering another quest.
resetCard = function(frame)
    closeFollowup(frame)
    closePreview(frame)
    for _, button in ipairs(frame.unavailableLinks) do
        button:Hide()
        button.entity = nil
    end
    frame.unavailableN = 0
    for _, button in ipairs(frame.followupLinks) do
        button:Hide()
        button.questID = nil
        button.pending = nil
        button.heading = nil
        button.xpFor = nil
        button.questName = nil
        button.suffix = nil
        button.category = nil
    end
    for _, summary in ipairs(frame.followupSummaries) do
        summary:Hide()
    end
    frame.followupN = 0
    frame.followupScan = 0
    frame.followupSummaryN = 0
    if frame.targetHelp then
        hideTargetHelp(frame.targetHelp)
        frame.targetHelp:Hide()
    end
    for _, textLine in ipairs(frame.lines) do
        textLine:Hide()
    end
    for _, button in ipairs(frame.links) do
        button:Hide()
        button.location = nil
    end
    for _, button in ipairs(frame.targets) do
        button:Hide()
        button.target = nil
    end
    if frame.rewardHolder then
        hideIcons(frame.rewardHolder)
        frame.rewardHolder:Hide()
    end
    frame.y = 0
    frame.lineN = 0
    frame.linkN = 0
    frame.targetN = 0
    frame.targetRows = nil
    frame.endpointRows = {}
end

-- Place text at the current vertical offset.
local function addTextLine(frame, text, red, green, blue, space, isTitle, isBody, role, isQuestText)
    if type(text) ~= 'string' or text == '' then
        return
    end
    frame.y = frame.y + (space or 0)
    frame.lineN = frame.lineN + 1
    local textLine = frame.lines[frame.lineN]
    if not textLine then
        textLine = frame.content:CreateFontString(nil, 'ARTWORK', 'GameFontHighlightSmall')
        frame.lines[frame.lineN] = textLine
    end
    -- Pooled ordinary text always starts fully opaque.
    textLine:SetAlpha(1)
    textLine:ClearAllPoints()
    textLine:SetPoint('TOPLEFT', frame.content, 'TOPLEFT', 0, -frame.y)
    textLine:SetWidth(frame.contentWidth or CARD_CONTENT_WIDTH)
    textLine:SetJustifyH('LEFT')
    textLine:SetJustifyV('TOP')
    textLine:SetWordWrap(true)
    Style.Font(
        textLine,
        (frame.isTargetWidget and role == 'heading') and 'widgetHeading'
            or (isTitle and 'title' or (isQuestText and 'questText' or (isBody and 'body' or 'small')))
    )
    if role then
        Style.Color(textLine, role)
    else
        -- Keep native quest text and semantic objective colors unchanged.
        textLine:SetTextColor(red or 0.87, green or 0.89, blue or 0.93, 1)
    end
    textLine:SetText(text)
    textLine:Show()
    frame.y = frame.y + math.max(12, textLine:GetStringHeight()) + (isBody and BODY_LINE_GAP or TITLE_LINE_GAP)
    return textLine
end

-- Semantic sections use the shared palette; native quest lines retain their colors.
local function addStyledLine(frame, text, role, space, isBody)
    return addTextLine(frame, text, nil, nil, nil, space, nil, isBody, role)
end

-- Preserve line wrapping and tighten only explicit paragraph breaks.
local function addDescription(frame, text, red, green, blue, space)
    text = text:gsub('\r\n', '\n')
    local start = 1
    while true do
        local first, last = text:find('\n[ \t]*\n', start)
        if not first or not text:sub(last + 1):match('%S') then
            addTextLine(frame, text:sub(start), red, green, blue, space, false, true, nil, true)
            return
        end
        local paragraph = text:sub(start, first - 1)
        local textLine = addTextLine(frame, paragraph, red, green, blue, space, false, true, nil, true)
        if textLine then
            -- Keep the paragraph gap independent of the text size.
            frame.y = frame.y - BODY_LINE_GAP + PARAGRAPH_GAP
        end
        start = last + 1
        space = 0
    end
end

-- Unavailable features remain hoverable without providing a broken click action.
local function widgetMapOpen(frame)
    return frame.isTargetWidget and WorldMapFrame and WorldMapFrame:IsShown()
end

local function showPreview(frame, source, entity)
    if widgetMapOpen(frame) then
        return
    end
    closeFollowup(frame)
    hideTargetHelp(frame.targetHelp)
    UI.ShowEntityPreview(frame, source, entity)
end

local function addUnavailableHint(frame, label, message, text)
    local heading = addStyledLine(frame, text or L['Unavailable (hover for details)'], 'muted')
    frame.unavailableN = frame.unavailableN + 1
    local button = frame.unavailableLinks[frame.unavailableN]
    if not button then
        button = CreateFrame('Frame', nil, frame.content)
        frame.unavailableLinks[frame.unavailableN] = button
        button:EnableMouse(true)
        button:SetScript('OnEnter', function(self)
            if not self.entity then
                return
            end
            showPreview(frame, self, self.entity)
        end)
    end
    button.entity = { name = label, message = message }
    button:ClearAllPoints()
    button:SetPoint('TOPLEFT', heading, 'TOPLEFT', 0, 0)
    button:SetSize(CARD_CONTENT_WIDTH, math.max(12, heading:GetStringHeight()))
    button:Show()
end

-- PreClick prepares the secure action; PostClick performs only UI work.
local function secureTargetButton(button, frame, getTarget, after)
    button:RegisterForClicks('LeftButtonUp')
    button:SetAttribute('useOnKeyDown', false)
    button:SetScript('PreClick', function(self)
        if Compat.InCombat() then
            return
        end
        self.selectionOK = nil
        self:SetAttribute('type', nil)
        self:SetAttribute('macrotext', nil)
        local target = getTarget(self)
        if not target then
            return
        end
        local action, reason = Data.TargetAction(target)
        if not action then
            if reason then
                print('Questlogger - ' .. reason)
            end
            return
        end
        local ok, err, body, status = Data.SetTargetMacro(target)
        self.selectionOK = ok
        self.macroStatus = status
        if not ok then
            print('Questlogger - ' .. err)
        end
        self:SetAttribute('macrotext', body or action)
        self:SetAttribute('type', 'macro')
    end)
    button:SetScript('PostClick', function(self)
        if Compat.InCombat() then
            return
        end
        local target = getTarget(self)
        if target and self.selectionOK then
            selectTarget(frame, target, self.macroStatus, self.location ~= nil)
        end
        if after then
            after(self)
        end
        self:SetAttribute('type', nil)
        self:SetAttribute('macrotext', nil)
    end)
end

local function canTarget(entity)
    return entity and Data.TargetAction(entity) ~= nil
end

local function locationButton(frame, location)
    frame.linkN = frame.linkN + 1
    local button = frame.links[frame.linkN]
    if not button then
        button = CreateFrame('Button', nil, frame.content, 'SecureActionButtonTemplate')
        frame.links[frame.linkN] = button
        button.label = button:CreateFontString(nil, 'ARTWORK', 'GameFontHighlightSmall')
        button.label:SetPoint('TOPLEFT')
        button.label:SetWidth(CARD_CONTENT_WIDTH)
        button.label:SetJustifyH('LEFT')
        button.label:SetWordWrap(true)
        Style.Font(button.label, 'small')
        button:SetScript('OnEnter', function(self)
            if not self.location then
                return
            end
            if canTarget(self.location) or self.location.mapID or not Data.PinIssue(self.location) then
                Style.Color(self.label, 'hover')
            end
            showPreview(frame, self, self.location)
        end)
        button:SetScript('OnLeave', function(self)
            if
                self.location and (canTarget(self.location) or self.location.mapID or not Data.PinIssue(self.location))
            then
                Style.Color(self.label, 'link')
            end
        end)
        secureTargetButton(button, frame, function(self)
            return self.location
        end, function(self)
            local location = self.location
            if location and location.mapID then
                local pinned = not Data.PinIssue(location) and Data.Pin(location)
                local opened = Data.OpenLocationMap(location)
                if pinned or opened then
                    (frame.rootCard or frame):Hide()
                end
            end
        end)
    end
    button.location = location
    location.hint = Data.PinIssue(location)
    local text = location.name
    if location.mapID then
        text = L.Format('%s — %s (%.1f, %.1f)', text, location.zone or L['Map'], location.x * 100, location.y * 100)
    else
        text = L.Format('%s — location unknown', text)
    end
    button.label:SetText(text)
    if canTarget(location) or location.mapID or not location.hint then
        Style.Color(button.label, 'link')
    else
        Style.Color(button.label, 'muted')
    end
    button:ClearAllPoints()
    button:SetPoint('TOPLEFT', frame.content, 'TOPLEFT', 0, -frame.y)
    button:SetSize(CARD_CONTENT_WIDTH, math.max(14, button.label:GetStringHeight()) + 3)
    button:SetEnabled(true)
    button:Show()
    frame.y = frame.y + button:GetHeight()
end

local function renderLocations(frame, questID, start)
    local locations = Data.Locations(questID, start)
    addStyledLine(frame, start and L['Quest start'] or L['Quest end'], 'heading', 5)
    if #locations == 0 then
        local issue = Data.DatabaseIssue(start and 'Quest.startedBy' or 'Quest.finishedBy', 'Npc', 'Object', 'Item')
        if issue then
            addUnavailableHint(frame, start and L['Quest start'] or L['Quest end'], issue)
        else
            addTextLine(frame, L['Unknown'], 0.65, 0.65, 0.65)
        end
    else
        for _, location in ipairs(locations) do
            if canTarget(location) then
                frame.endpointRows[#frame.endpointRows + 1] = location
            end
            locationButton(frame, location)
        end
    end
end

-- Use the same links in the quest card and in the floating switcher.
local function targetColor(frame, button)
    Style.Color(
        button.label,
        frame.isTargetWidget
                and frame.activeTarget
                and button.target
                and button.target.kind == frame.activeTarget.kind
                and button.target.name == frame.activeTarget.name
                and 'hover'
            or 'link'
    )
end

local function targetButton(frame, target)
    frame.targetN = frame.targetN + 1
    local button = frame.targets[frame.targetN]
    if not button then
        button = CreateFrame('Button', nil, frame.content, 'SecureActionButtonTemplate')
        frame.targets[frame.targetN] = button
        button.label = button:CreateFontString(nil, 'ARTWORK', 'GameFontHighlightSmall')
        button.label:SetPoint('TOPLEFT')
        button.label:SetWidth(frame.contentWidth or CARD_CONTENT_WIDTH)
        button.label:SetJustifyH('LEFT')
        button.label:SetWordWrap(true)
        Style.Font(button.label, 'small')
        button:RegisterForClicks('LeftButtonUp')
        button:SetScript('OnEnter', function(self)
            Style.Color(self.label, 'hover')
            if self.target then
                showPreview(frame, self, self.target)
            end
        end)
        button:SetScript('OnLeave', function(self)
            targetColor(frame, self)
        end)
        secureTargetButton(button, frame, function(self)
            return self.target
        end, function(self)
            -- An actual objective may also be a quest endpoint; open its map from the widget.
            local location = frame.isTargetWidget and self.target and self.target.endpoint
            if location then
                if not Data.PinIssue(location) then
                    Data.Pin(location)
                end
                Data.OpenLocationMap(location)
            end
        end)
    end
    button.target = target
    local name = target.kind == 'object' and L.Format('%s (object)', target.name) or target.name
    button.label:SetText(name .. (target.role and (' (' .. L[target.role] .. ')') or ''))
    targetColor(frame, button)
    button:ClearAllPoints()
    button:SetPoint('TOPLEFT', frame.content, 'TOPLEFT', 0, -frame.y)
    button:SetSize(frame.contentWidth or CARD_CONTENT_WIDTH, math.max(14, button.label:GetStringHeight()) + 3)
    button:Show()
    frame.y = frame.y + button:GetHeight()
end

-- The macro help is styled independently of native item tooltips.
local HELP_TEXT = {
    L['Questlogger target macro'],
    L['1. Click a blue target or quest endpoint to create or update the macro and target it.'],
    L['2. Type /macro or /m and find Questlogger in your macros.'],
    L['3. Drag it onto an action bar and optionally assign a keybind.'],
    L['4. Use that action to target the selected NPC. Clicking another name updates the same macro.'],
    L['For objects, use the macro to clear your target, then use the Interact key or click the nearby object.'],
    L['Macro changes are unavailable during combat.'],
}

local function showMacroHelp(button, frame)
    if widgetMapOpen(frame) then
        return
    end
    closePreview(frame)
    closeFollowup(frame)
    local popup = button.helpPopup
    if not popup then
        popup = CreateFrame('Frame', nil, frame)
        button.helpPopup = popup
        popup:SetFrameStrata('FULLSCREEN_DIALOG')
        popup:SetFrameLevel(40)
        popup:SetClampedToScreen(true)
        popup:EnableMouse(false)
        Style.Apply(popup)
        popup.lines = {}
        local width, padding, y = 270, 12, 12
        for i, text in ipairs(HELP_TEXT) do
            local textLine = popup:CreateFontString(nil, 'ARTWORK', 'GameFontHighlightSmall')
            Style.Font(textLine, i == 1 and 'body' or 'small')
            Style.Color(textLine, i == 1 and 'title' or (i >= 6 and 'helpNote' or 'helpBody'))
            textLine:SetPoint('TOPLEFT', padding, -y)
            textLine:SetWidth(width - 2 * padding)
            textLine:SetJustifyH('LEFT')
            textLine:SetJustifyV('TOP')
            textLine:SetWordWrap(true)
            textLine:SetText(text)
            y = y + math.max(12, textLine:GetStringHeight()) + 4
            popup.lines[i] = textLine
        end
        popup:SetSize(width, y + padding - 4)
    end
    popup:ClearAllPoints()
    local right = UIParent:GetWidth() - (frame:GetRight() or 0)
    if right >= popup:GetWidth() + 2 or right >= (frame:GetLeft() or 0) then
        popup:SetPoint('TOPLEFT', frame, 'TOPRIGHT', 2, 0)
    else
        popup:SetPoint('TOPRIGHT', frame, 'TOPLEFT', -2, 0)
    end
    popup:Show()
end

-- Only the Targets heading activates the help popup.
local function showTargetHelp(frame, heading)
    local button = frame.targetHelp
    if not button then
        button = CreateFrame('Frame', nil, frame.content)
        frame.targetHelp = button
        button:EnableMouse(true)
        button:SetScript('OnEnter', function(self)
            showMacroHelp(self, frame)
        end)
        button:SetScript('OnLeave', hideTargetHelp)
        button:SetScript('OnHide', hideTargetHelp)
    end
    button:ClearAllPoints()
    button:SetPoint('TOPLEFT', heading, 'TOPLEFT', 0, 0)
    button:SetSize(heading:GetStringWidth(), heading:GetStringHeight())
    button:Show()
end

local function renderTargets(frame, questID)
    local rows = Data.Targets(questID)
    frame.targetRows = rows
    if #rows == 0 then
        local issue =
            Data.DatabaseIssue('Quest.objectives', 'Npc.name', 'Object.name', 'Item.npcDrops', 'Item.objectDrops')
        if issue then
            addStyledLine(frame, L['Targets'], 'heading', 5)
            addUnavailableHint(frame, L['Targets'], issue)
        end
        return
    end
    local heading = addStyledLine(frame, L['Targets'], 'heading', 5)
    showTargetHelp(frame, heading)
    for _, target in ipairs(rows) do
        targetButton(frame, target)
    end
end

-- The switcher owns its own rows and survives closing the quest log.
local WIDGET_WIDTH, WIDGET_PADDING, WIDGET_BOTTOM_PADDING = 220, 14, 10
local function makeTargetWidget()
    local frame = CreateFrame('Frame', 'QuestloggerTargetsWidget', UIParent, 'SecureHandlerStateTemplate')
    registerCombatHide(frame)
    frame.isTargetWidget = true
    -- Preserve normal widget layering until a map opens.
    local function mapLayer(self)
        local strata = 'HIGH'
        if widgetMapOpen(self) then
            local mapStrata = WorldMapFrame.GetFrameStrata and WorldMapFrame:GetFrameStrata()
            strata = (mapStrata == 'LOW' or mapStrata == 'BACKGROUND') and 'BACKGROUND' or 'LOW'
        end
        if self.widgetStrata ~= strata then
            self:SetFrameStrata(strata)
            self.widgetStrata = strata
        end
    end
    mapLayer(frame)
    frame:SetFrameLevel(20)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetWidth(WIDGET_WIDTH)
    frame:SetPoint('RIGHT', UIParent, 'RIGHT', 0, 0)
    Style.Apply(frame)
    local scroll = CreateFrame('ScrollFrame', nil, frame)
    scroll:SetPoint('TOPLEFT', WIDGET_PADDING, -WIDGET_PADDING)
    scroll:SetPoint('BOTTOMRIGHT', -WIDGET_PADDING, WIDGET_BOTTOM_PADDING)
    local content = CreateFrame('Frame', nil, scroll)
    frame.contentWidth = WIDGET_WIDTH - 2 * WIDGET_PADDING
    content:SetSize(frame.contentWidth, 1)
    scroll:SetScrollChild(content)
    frame.scroll = scroll
    frame.content = content
    frame.lines = {}
    frame.targets = {}
    local close = CreateFrame('Button', nil, frame, 'UIPanelCloseButton')
    close:SetSize(24, 24)
    close:SetPoint('TOPRIGHT', frame, 'TOPRIGHT', -10, -10)
    close:SetScript('OnClick', function()
        frame:Hide()
    end)
    frame.close = close
    local function stopMoving()
        frame:StopMovingOrSizing()
    end
    local function drag(handle)
        handle:EnableMouse(true)
        handle:RegisterForDrag('LeftButton')
        handle:SetScript('OnDragStart', function()
            closePreview(frame)
            hideTargetHelp(frame.targetHelp)
            frame:StartMoving()
        end)
        handle:SetScript('OnDragStop', stopMoving)
    end
    drag(frame)
    frame.dragHandle = drag
    local function wheel(_, delta)
        closePreview(frame)
        hideTargetHelp(frame.targetHelp)
        scroll:SetVerticalScroll(
            math.max(0, math.min(scroll:GetVerticalScrollRange(), scroll:GetVerticalScroll() - delta * 32))
        )
    end
    scroll:EnableMouseWheel(true)
    scroll:SetScript('OnMouseWheel', wheel)
    frame:EnableMouseWheel(true)
    frame:SetScript('OnMouseWheel', wheel)
    frame:SetScript('OnUpdate', function(self, elapsed)
        if not Compat.InCombat() then
            if widgetMapOpen(self) then
                closePreview(self)
                hideTargetHelp(self.targetHelp)
            else
                UI.UpdateEntityPreview(self, elapsed)
            end
            mapLayer(self)
        end
    end)
    frame:SetScript('OnHide', function(self)
        if Compat.InCombat() then
            return
        end
        stopMoving()
        closePreview(self)
        hideTargetHelp(self.targetHelp)
    end)
    frame:Hide()
    return frame
end

showTargetWidget = function(questID, rows, selected)
    if not rows or #rows < 2 then
        if targetWidget then
            targetWidget:Hide()
        end
        return
    end
    if not targetWidget then
        targetWidget = makeTargetWidget()
    end
    local frame = targetWidget
    closePreview(frame)
    hideTargetHelp(frame.targetHelp)
    frame.questID = questID
    frame.activeTarget = selected
    for _, button in ipairs(frame.targets) do
        button:Hide()
        button.target = nil
    end
    for _, textLine in ipairs(frame.lines) do
        textLine:Hide()
    end
    frame.y = 0
    frame.lineN = 0
    frame.targetN = 0
    local heading = addStyledLine(frame, L['Targets'], 'heading', 0)
    showTargetHelp(frame, heading)
    frame.dragHandle(frame.targetHelp)
    for _, target in ipairs(rows) do
        targetButton(frame, target)
    end
    frame.content:SetHeight(math.max(1, frame.y))
    frame:SetHeight(
        math.min(frame.y + WIDGET_PADDING + WIDGET_BOTTOM_PADDING, math.max(80, UIParent:GetHeight() * 0.45))
    )
    frame.scroll:SetVerticalScroll(0)
    frame:Show()
end

selectTarget = function(frame, target, status, endpointClick)
    -- Native chat has no inline italic markup; keep the name in the normal chat color.
    print(L.Format("Questlogger - Target macro: '%s'", target.name))
    if frame.isTargetWidget then
        frame.activeTarget = target
        for i = 1, frame.targetN do
            targetColor(frame, frame.targets[i])
        end
    elseif not endpointClick then
        local rows = {}
        for _, target in ipairs(frame.targetRows or {}) do
            local copy = {}
            for key, value in pairs(target) do
                copy[key] = value
            end
            for _, location in ipairs(frame.endpointRows or {}) do
                if
                    target.kind == location.kind
                    and (
                        (target.id and location.id and target.id == location.id)
                        or ((not target.id or not location.id) and target.name == location.name)
                    )
                then
                    if not copy.endpoint or Data.PinIssue(copy.endpoint) then
                        copy.endpoint = location
                    end
                end
            end
            rows[#rows + 1] = copy
        end
        showTargetWidget(frame.questID, rows, target)
    end
end

function UI.HideTargetWidget(questID)
    if not Compat.InCombat() and targetWidget and (not questID or targetWidget.questID == questID) then
        targetWidget:Hide()
    end
end

function UI.HideCard()
    if not Compat.InCombat() then
        if card then
            card:Hide()
        end
        if mapCard then
            mapCard:Hide()
        end
    end
end

function UI.HideMapCard(owner)
    if mapCard and not Compat.InCombat() and (not owner or mapCard.row == owner) then
        mapCard:Hide()
    end
end

local function categorySuffix(category)
    return category and (' |cffffa640(' .. category .. ')|r') or ''
end
UI.CategorySuffix = categorySuffix
-- Render reward details separately from native quest text.
local function renderRewards(frame, questID, info, xpFor)
    frame.rewardHeading = addStyledLine(frame, L['Rewards'], 'heading', frame.isFollowup and 0 or 5, frame.isFollowup)
    if frame.isFollowup then
        frame.y = frame.y - BODY_LINE_GAP + TITLE_LINE_GAP
    end
    local xp = xpFor(questID)
    local money, reputation, repPending = Data.CardRewards(questID)
    local hasRewards = #info.rewards > 0
        or (type(xp) == 'number' and xp > 0)
        or (money and money > 0)
        or #reputation > 0
    if xp ~= 0 then
        addStyledLine(frame, L.Format('Experience: %s', addon.Core.QuestXPAmount(xp)), 'reward')
    end
    for _, reward in ipairs(reputation) do
        local amount = L.Number(reward.amount)
        if reward.amount > 0 then
            amount = '|cff64aa76+' .. amount .. '|r'
        elseif reward.amount < 0 then
            amount = '|cffc06666' .. amount .. '|r'
        end
        addStyledLine(
            frame,
            L.Format('Reputation: %s (%s)', reward.name, amount) .. (reward.choice and L[' (choice)'] or ''),
            'reward'
        )
    end
    if money and money > 0 then
        local gold = math.floor(money / 10000)
        local silver = math.floor(money / 100) % 100
        local copper = money % 100
        -- Omit zero denominations while retaining native coin textures.
        local coins = {}
        if gold > 0 then
            coins[#coins + 1] = gold .. '|TInterface\\MoneyFrame\\UI-GoldIcon:0|t'
        end
        if silver > 0 then
            coins[#coins + 1] = silver .. '|TInterface\\MoneyFrame\\UI-SilverIcon:0|t'
        end
        if copper > 0 then
            coins[#coins + 1] = copper .. '|TInterface\\MoneyFrame\\UI-CopperIcon:0|t'
        end
        addStyledLine(frame, L.Format('Money: %s', table.concat(coins, ' ')), 'reward')
    end
    if #info.rewards > 0 then
        if not frame.rewardHolder then
            frame.rewardHolder = CreateFrame('Frame', nil, frame.content)
        end
        local holder = frame.rewardHolder
        holder:ClearAllPoints()
        holder:SetPoint('TOPLEFT', frame.content, 'TOPLEFT', 0, -frame.y)
        frame.y = frame.y + UI.RewardStrip(holder, info.rewards, CARD_CONTENT_WIDTH, 26, L['Other:'], 'reward') + 2
    end
    local pending = info.rewardsPending or repPending or money == nil or xp == nil
    if info.rewardsUnavailable then
        addTextLine(frame, info.rewardsUnavailable, 0.65, 0.65, 0.65)
    elseif frame.isFollowup and info.rewardsPending then
        addStyledLine(frame, L['Loading rewards...'], 'reward')
    elseif not hasRewards then
        if pending then
            if xp ~= nil or money == nil or repPending or info.rewardsPending then
                addTextLine(frame, L['Reward data unavailable'], 0.65, 0.65, 0.65)
            end
        else
            addTextLine(frame, L['None'], 0.65, 0.65, 0.65)
        end
    elseif info.rewardsPending then
        addTextLine(frame, L['Reward data unavailable'], 0.65, 0.65, 0.65)
    end
    local issue = repPending and Data.DatabaseIssue('Quest.reputationReward')
    if issue then
        addUnavailableHint(frame, L['Reputation'], issue, L['Reputation unavailable (hover for details)'])
    end
    local xpIssue = xp == nil and Data.DatabaseIssue('Support.Get')
    if xpIssue then
        addUnavailableHint(frame, L['Experience'], xpIssue, L['Experience unavailable (hover for details)'])
    end
end

-- Overlay each follow-up line with a reusable hover target.
local function followupLink(frame, heading, questID, xpFor, pending, height, suffix, category, questName)
    frame.followupN = frame.followupN + 1
    local button = frame.followupLinks[frame.followupN]
    if not button then
        button = CreateFrame('Frame', nil, frame.content)
        frame.followupLinks[frame.followupN] = button
        button:EnableMouse(true)
        button:SetScript('OnEnter', function(self)
            if not self.questID or frame.followupSource == self then
                return
            end
            closeFollowup(frame)
            closePreview(frame)
            hideTargetHelp(frame.targetHelp)
            frame.followupSource = self
            showFollowupCard(frame, self)
        end)
    end
    button.questID = questID
    button.heading = heading
    button.xpFor = xpFor
    button.questName = questName
    button.pending = pending
    button.suffix = suffix
    button.category = category
    button:ClearAllPoints()
    button:SetPoint('TOPLEFT', heading, 'TOPLEFT', 0, 0)
    button:SetSize(CARD_CONTENT_WIDTH, height)
    button:Show()
end

-- Translucent summaries never enter the pool used by other card text.
local function followupSummary(frame, text)
    frame.followupSummaryN = frame.followupSummaryN + 1
    local index = frame.followupSummaryN
    local textLine = frame.followupSummaries[index]
    if not textLine then
        textLine = frame.content:CreateFontString(nil, 'ARTWORK', 'GameFontHighlightSmall')
        frame.followupSummaries[index] = textLine
    end
    textLine:SetWidth(CARD_CONTENT_WIDTH)
    textLine:SetJustifyH('LEFT')
    textLine:SetJustifyV('TOP')
    textLine:SetWordWrap(true)
    Style.Font(textLine, 'followupSummary')
    local c = Style.colors.followupSummary
    textLine:SetTextColor(c[1], c[2], c[3], 1)
    textLine:SetAlpha(c[4])
    textLine:SetText(text)
    textLine:Show()
    return textLine
end

-- Lay out independent name, summary and category segments.
local function followupLine(frame, name, summary, category)
    local y = frame.y
    local heading = addTextLine(frame, name)
    local function naturalWidth(textLine)
        return math.ceil(
            textLine.GetUnboundedStringWidth and textLine:GetUnboundedStringWidth() or textLine:GetStringWidth()
        )
    end
    local x = naturalWidth(heading)
    local rowY, rowHeight = y, math.max(12, heading:GetStringHeight())
    if x > CARD_CONTENT_WIDTH or rowHeight > 16 then
        x = CARD_CONTENT_WIDTH
    end
    local function segment(value, role)
        local textLine = role == 'followupSummary' and followupSummary(frame, value) or addTextLine(frame, value)
        local width = naturalWidth(textLine)
        local gap = role == 'followupSummary' and 2 or 4
        if x + gap + width > CARD_CONTENT_WIDTH then
            rowY = rowY + rowHeight + TITLE_LINE_GAP
            x = 0
            rowHeight = 0
            gap = 0
        end
        x = x + gap
        textLine:ClearAllPoints()
        textLine:SetPoint('TOPLEFT', frame.content, 'TOPLEFT', x, -rowY - (role == 'followupSummary' and 1 or 0))
        textLine:SetWidth(math.min(CARD_CONTENT_WIDTH - x, math.max(1, width)))
        rowHeight =
            math.max(rowHeight, math.max(12, textLine:GetStringHeight() + (role == 'followupSummary' and 1 or 0)))
        x = x + width
        return textLine
    end
    local suffix = segment(summary, 'followupSummary')
    local tag = category and segment(categorySuffix(category):sub(2)) or nil
    frame.y = rowY + rowHeight + TITLE_LINE_GAP
    return heading, suffix, tag, frame.y - y - TITLE_LINE_GAP
end

local function renderFollowups(frame, info, xpFor, questName)
    if info.chainIssue then
        addStyledLine(frame, L['Follow-up quests'], 'heading', 5)
        addUnavailableHint(frame, L['Quest chains and follow-up quests'], info.chainIssue)
        return
    end
    if #info.future > 0 then
        addStyledLine(frame, L['Follow-up quests'], 'heading', 5)
        for _, id in ipairs(info.future) do
            local name = questName(id) or L.Format('Quest %d', id)
            local pending
            if not frame.isFollowup then
                local _
                _, pending = Data.FollowupRewards(id, true)
            end
            local step = info.futureSteps and info.futureSteps[id] or '?/?'
            local heading, suffix, category, height = followupLine(
                frame,
                name,
                step .. ' (' .. addon.Core.QuestXPText(xpFor(id)) .. ')',
                Data.QuestCategory(id)
            )
            if not frame.isFollowup then
                followupLink(frame, heading, id, xpFor, pending, height, suffix, category, questName)
            end
        end
    end
    if info.followups then
        for _, followup in ipairs(info.followups) do
            local needed = {}
            for _, requirement in ipairs(followup.requirements) do
                if requirement.completed ~= true then
                    needed[#needed + 1] = requirement.name .. (requirement.completed == nil and ' (?)' or '')
                end
            end
            if #needed > 0 then
                addTextLine(
                    frame,
                    L.Format('%s also needs: %s', followup.name, table.concat(needed, ', ')),
                    0.73,
                    0.73,
                    0.73
                )
            end
        end
    end
end

renderQuestText = function(frame, nativeLines, descriptionIndex, category, questName, questID)
    local objectiveGapAdded = false
    if #nativeLines == 0 then
        addTextLine(
            frame,
            (questName(questID) or L.Format('Quest %d', questID)) .. categorySuffix(category),
            1,
            0.82,
            0.3,
            0,
            true
        )
    end
    for i, textLine in ipairs(nativeLines) do
        local text = textLine.text
        if i == 1 and category then
            local suffix = ' (' .. category .. ')'
            local plain = Data.PlainTag(text)
            if not plain or plain:sub(-#suffix) ~= suffix then
                text = text .. categorySuffix(category)
            end
        end
        local space = 0
        -- Insert the larger gap before the first objective only.
        if descriptionIndex and i > descriptionIndex and not objectiveGapAdded then
            if textLine.objective then
                space = DESCRIPTION_OBJECTIVE_GAP
                objectiveGapAdded = true
            end
        end
        if i == descriptionIndex and not textLine.objective then
            addDescription(frame, text, textLine.r, textLine.g, textLine.b, space)
        else
            addTextLine(
                frame,
                text,
                textLine.r,
                textLine.g,
                textLine.b,
                space,
                i == 1,
                i > 1,
                nil,
                i > 1 and textLine.objective
            )
        end
    end
end

renderBody = function(frame, questID, info, xpFor, questName)
    renderLocations(frame, questID, true)
    renderLocations(frame, questID, false)
    renderTargets(frame, questID)
    renderRewards(frame, questID, info, xpFor)
    renderFollowups(frame, info, xpFor, questName)
end

function UI.ShowCard(row, info, xpFor, questName)
    if Compat.InCombat() then
        return
    end
    UI.HideMapCard()
    if not card then
        card = createCard()
    end
    local frame = card
    resetCard(frame)
    local questID = row.questID
    frame.row = row
    frame.trackerID = nil
    frame.pinned = nil
    frame.questID = questID
    frame.outside = 0
    local nativeLines, descriptionIndex, category = QuestText.FromTooltip(row, questID, questName)
    frame.nativeSnapshot =
        { questID = questID, lines = nativeLines, descriptionIndex = descriptionIndex, category = category }
    renderQuestText(frame, nativeLines, descriptionIndex, category, questName, questID)
    renderBody(frame, questID, info, xpFor, questName)
    sizeCard(frame, true)
    anchorCard(frame, row)
    frame:Show()
end

-- Pin the same card to the native quest-details panel until it closes.
function UI.ShowDetailsCard(panel, questID, info, xpFor, questName)
    if Compat.InCombat() or not panel or not panel:IsVisible() or panel.questID ~= questID then
        return
    end
    UI.HideMapCard()
    if not card then
        card = createCard()
    end
    local frame = card
    local same = frame:IsShown() and frame.pinned and frame.questID == questID and frame.row == panel
    local offset = same and frame.scroll:GetVerticalScroll() or 0
    -- On a click from the quest list, retain native text such as party progress.
    local snapshot = frame:IsShown() and not frame.pinned and frame.nativeSnapshot
    resetCard(frame)
    frame.trackerID = nil
    frame.row = panel
    frame.questID = questID
    frame.pinned = true
    frame.outside = 0
    local native, descIndex, category
    if snapshot and snapshot.questID == questID then
        native, descIndex, category = snapshot.lines, snapshot.descriptionIndex, snapshot.category
    else
        native, descIndex, category = QuestText.FromAPI(questID, questName)
    end
    frame.nativeSnapshot = nil
    renderQuestText(frame, native, descIndex, category, questName, questID)
    renderBody(frame, questID, info, xpFor, questName)
    sizeCard(frame, not same)
    if same then
        frame.scroll:SetVerticalScroll(math.min(offset, frame.scroll:GetVerticalScrollRange()))
    end
    anchorCard(frame, panel)
    frame:Show()
end

-- Tracker rows do not supply the quest-log tooltip; use quest data by ID.
function UI.ShowTrackerCard(row, questID, info, xpFor, questName, resolve)
    if Compat.InCombat() or not row or not row:IsVisible() or resolve(row) ~= questID then
        return
    end
    UI.HideMapCard()
    if not card then
        card = createCard()
    end
    local frame = card
    if frame:IsShown() and frame.row == row and frame.questID == questID and frame.trackerID then
        frame.outside = 0
        anchorCard(frame, row)
        return
    end
    resetCard(frame)
    frame.row = row
    frame.questID = questID
    frame.trackerID = resolve
    frame.pinned = nil
    frame.outside = 0
    frame.nativeSnapshot = nil
    local native, descIndex, category = QuestText.FromAPI(questID, questName)
    if GameTooltip and GameTooltip.Hide then
        GameTooltip:Hide()
    end
    renderQuestText(frame, native, descIndex, category, questName, questID)
    renderBody(frame, questID, info, xpFor, questName)
    sizeCard(frame, true)
    anchorCard(frame, row)
    frame:Show()
end

-- A map hover has its own card so a selected quest's pinned details stay intact.
function UI.ShowMapCard(pin, questID, info, xpFor, questName, resolve)
    local map = WorldMapFrame
    if
        Compat.InCombat()
        or not map
        or Compat.Call(map.IsVisible, map) ~= true
        or not pin
        or Compat.Call(pin.IsVisible, pin) ~= true
        or resolve(pin) ~= questID
    then
        return
    end
    if card and not card.pinned then
        card:Hide()
    end
    local tooltip = Compat.Call(GetAppropriateTooltip) or GameTooltip
    if tooltip and type(tooltip.Hide) == 'function' then
        tooltip:Hide()
    end
    if not mapCard then
        mapCard = createCard(nil, true)
    end
    local frame = mapCard
    if frame:IsShown() and frame.row == pin and frame.questID == questID then
        frame.outside = 0
        anchorCard(frame, pin)
        return true
    end
    resetCard(frame)
    frame.row = pin
    frame.questID = questID
    frame.trackerID = resolve
    frame.mapContext = map
    frame.pinned = nil
    frame.outside = 0
    frame.nativeSnapshot = nil
    local native, descriptionIndex, category = QuestText.FromAPI(questID, questName)
    renderQuestText(frame, native, descriptionIndex, category, questName, questID)
    renderBody(frame, questID, info, xpFor, questName)
    sizeCard(frame, true)
    anchorCard(frame, pin)
    frame:Show()
    return true
end
