-- Mock frame layout, native tooltips and pooled rows.
local F = dofile('tests/load.lua')
local U, D = F.UI, F.Data
InCombatLockdown = function()
    return false
end
local databaseIssue = D.DatabaseIssue
D.DatabaseIssue = function() end -- Healthy dependency for existing layout tests.
local function frame(parent)
    local t = { parent = parent, shown = true, w = 200, h = 12, text = '', points = {}, scripts = {} }
    function t:SetPoint(...)
        local point = select(1, ...)
        if point == 'BOTTOMRIGHT' and self.points[1] then
            self.points[2] = { ... }
        else
            self.points[1] = { ... }
        end
    end
    function t:GetPoint(i)
        return table.unpack(self.points[i] or {})
    end
    function t:ClearAllPoints()
        self.points = {}
    end
    function t:SetWidth(w)
        self.w = w
    end
    function t:GetWidth()
        return self.w
    end
    function t:SetHeight(h)
        self.h = h
    end
    function t:GetHeight()
        return self.h
    end
    function t:SetSize(w, h)
        self.w = w
        self.h = h
    end
    function t:SetText(s)
        self.text = s
    end
    function t:GetText()
        return self.text
    end
    function t:GetStringWidth()
        return #(self.text:gsub('|c%x%x%x%x%x%x%x%x', ''):gsub('|r', '')) * (self.fontSize or 12) / 2
    end
    function t:GetStringHeight()
        return self.fontSize
            or (self.font == GameFontNormalLarge and 16 or (self.font == GameFontHighlight and 14 or 12))
    end
    function t:SetFontObject(font)
        self.font = font
    end
    function t:GetFont()
        return self.fontFile or 'MockFont', self.fontSize or 14
    end
    function t:SetFont(path, size, flags)
        self.fontFile = path
        self.fontSize = size
        self.fontFlags = flags
    end
    function t:SetTexture(path)
        self.texture = path
    end
    function t:SetVertexColor(...)
        self.vertexColor = { ... }
    end
    function t:SetTexCoord(...)
        self.texCoord = { ... }
    end
    function t:SetFrameStrata(strata)
        self.strata = strata
    end
    function t:SetColorTexture(...)
        self.color = { ... }
    end
    function t:SetTextColor(r, g, b, a)
        self.textColor = { r, g, b, a ~= nil and a or (self.textColor and self.textColor[4]) or 1 }
    end
    function t:SetGradient(...)
        self.gradient = { ... }
    end
    function t:GetTextColor()
        return table.unpack(self.textColor or { 1, 1, 1 })
    end
    function t:CreateFontString()
        return frame(self)
    end
    function t:CreateTexture()
        return frame(self)
    end
    function t:SetScript(name, fn)
        self.scripts[name] = fn
    end
    function t:SetAttribute(name, value)
        self.attributes = self.attributes or {}
        self.attributes[name] = value
    end
    function t:GetAttribute(name)
        return self.attributes and self.attributes[name]
    end
    function t:ClickSecure()
        self.scripts.PreClick(self)
        self.executed = self:GetAttribute('type') == 'macro' and self:GetAttribute('macrotext') or nil
        self.scripts.PostClick(self)
    end
    function t:Show()
        self.shown = true
    end
    function t:Hide()
        self.shown = false
    end
    function t:IsShown()
        return self.shown
    end
    function t:SetShown(v)
        self.shown = v
    end
    function t:SetAlpha(v)
        self.alpha = v
    end
    function t:GetRight()
        return self.right or 400
    end
    function t:GetLeft()
        return self.left or 60
    end
    function t:IsVisible()
        return self.shown and (not self.parent or self.parent:IsVisible())
    end
    function t:IsMouseOver()
        return self.mouse == true
    end
    function t:GetVerticalScrollRange()
        return 100
    end
    function t:GetVerticalScroll()
        return 0
    end
    for _, name in ipairs({
        'SetJustifyH',
        'SetJustifyV',
        'SetWordWrap',
        'SetAllPoints',
        'SetShadowColor',
        'SetShadowOffset',
        'RegisterForClicks',
        'SetFrameLevel',
        'SetClampedToScreen',
        'EnableMouse',
        'SetBackdrop',
        'SetBackdropColor',
        'SetBackdropBorderColor',
        'SetScrollChild',
        'EnableMouseWheel',
        'SetVerticalScroll',
        'SetEnabled',
        'SetMovable',
        'RegisterForDrag',
        'StartMoving',
        'StopMovingOrSizing',
    }) do
        t[name] = function() end
    end
    return t
end
GameFontNormalLarge = 'large'
GameFontHighlightSmall = 'small'
GameFontHighlight = 'normal'
local card, widget
CreateFrame = function(kind, name, parent)
    local f = frame(parent)
    if kind == 'PlayerModel' then
        function f:SetCreature(id)
            self.creatureID = id
            self.requests = (self.requests or 0) + 1
            -- Uncached NPCs leave the renderer empty until a later request.
            self.fileID = self.cachedFile
        end
        function f:GetModelFileID()
            return self.fileID
        end
        function f:ClearModel()
            self.creatureID = nil
            self.fileID = nil
        end
    end
    if name == 'QuestloggerHoverCard' then
        card = f
    elseif name == 'QuestloggerTargetsWidget' then
        widget = f
    end
    return f
end
local row = frame()
row.Text = frame(row)
row.Text:SetText('[51] Quest')
row.questID = 1
local a, b = frame(), frame()
a:SetHeight(14)
b:SetHeight(20)
a:SetPoint('TOPLEFT', row.Text, 'BOTTOMLEFT', 0, -3)
b:SetPoint('TOPLEFT', a, 'BOTTOMLEFT', 0, -2)
-- Native quest-log POI size and title-top alignment are stable across refreshes.
local poi = frame()
poi.parent = row
poi.scale = 1
function poi:GetScale()
    return self.scale
end
function poi:SetScale(v)
    self.scale = v
end
local contents = {
    FindButtonByQuestID = function(_, id)
        if id == row.questID then
            return poi
        end
    end,
}
U.AlignQuestLogPOI(row, contents)
U.AlignQuestLogPOI(row, contents)
assert(
    poi.scale == 0.85
        and select(1, poi:GetPoint(1)) == 'TOPRIGHT'
        and select(2, poi:GetPoint(1)) == row.Text
        and select(3, poi:GetPoint(1)) == 'TOPLEFT'
)
local info = {
    listText = '1/3 (450 XP)',
    instance = 'dungeon',
    rewards = { { kind = 'item', id = 5, texture = 10, quality = 2 } },
    future = { 2, 3 },
    futureSteps = { [2] = '2/3', [3] = '3/3' },
}
GetCVarBool = function()
    return true
end
local completed = { [1] = true }
C_QuestLog = {
    IsComplete = function(id)
        return completed[id] == true
    end,
}
CreateColor = function(...)
    return { ... }
end
assert(U.LayoutRow(row, info, { b, a }))
assert(row.QuestloggerSummary:GetText() == '1/3 (450 XP)')
local sc = row.QuestloggerSummary.textColor
assert(sc[1] == 1 and sc[2] == 0.83 and sc[3] == 0.40 and sc[4] == 0.80)
local bg = row.QuestloggerTurnInBackground
assert(
    bg:IsShown()
        and bg.gradient[1] == 'HORIZONTAL'
        and bg.gradient[2][4] > 0.0
        and bg.gradient[2][4] > bg.gradient[3][4]
)
assert(select(2, bg:GetPoint(1)) == row and select(2, bg:GetPoint(2)) == row)
completed[1] = false
U.UpdateTurnInBackground(row)
assert(not bg:IsShown())
completed[1] = true
U.UpdateTurnInBackground(row)
assert(bg:IsShown() and row.QuestloggerTurnInBackground == bg)
U.ResetRow(row)
assert(not bg:IsShown())
U.LayoutRow(row, info, { b, a })
assert(bg:IsShown())
local fallback = frame()
fallback.questID = 1
local savedColor = CreateColor
CreateColor = nil
U.UpdateTurnInBackground(fallback)
CreateColor = savedColor
assert(fallback.QuestloggerTurnInBackground:IsShown() and fallback.QuestloggerTurnInBackground.color[4] == 0.27)
local invalid = frame()
invalid.questID = 1
CreateColor = function()
    error('unsupported')
end
U.UpdateTurnInBackground(invalid)
CreateColor = savedColor
assert(invalid.QuestloggerTurnInBackground.color[4] == 0.27)
assert(not row.Text:GetText():find('450', 1, true))
assert(select(2, a:GetPoint(1)) == row.QuestloggerSummary)
assert(select(2, b:GetPoint(1)) == a)
assert(select(2, row.QuestloggerRewards:GetPoint(1)) == b)
assert(not row.QuestloggerRewards.icons[1].border)
assert(row.QuestloggerRewards.label:GetText() == 'Rewards:' and row.QuestloggerRewards.label:IsShown())
assert(select(4, row.QuestloggerRewards.icons[1]:GetPoint(1)) > 0)
local divider = row.QuestloggerRewards.divider
assert(divider:IsShown() and divider:GetHeight() == 1 and divider:GetWidth() == row.Text:GetWidth())
assert(divider.color[3] == 1 and divider.color[4] == 0.45)
local labelColor = row.QuestloggerRewards.label.textColor
assert(
    labelColor[1] == divider.color[1]
        and labelColor[2] == divider.color[2]
        and labelColor[3] == divider.color[3]
        and labelColor[4] == 1
)
assert(select(5, row.QuestloggerRewards:GetPoint(1)) == -11)
assert(select(5, divider:GetPoint(1)) == 5)
local height = row:GetHeight()
local summary = row.QuestloggerSummary
assert(not U.LayoutRow(row, info, { a, b }))
assert(row:GetHeight() == height and row.QuestloggerRewards.divider == divider)
row.Text:SetText(row.Text:GetText() .. ' |TnewQuestIcon:12:12|t')
U.LayoutRow(row, info, { b, a })
assert(row.QuestloggerSummary == summary and row:GetHeight() == height)
local text = row.Text:GetText()
assert(text:find('newQuestIcon', 1, true))
local _, n = text:gsub('QuestloggerDungeon', '')
assert(n == 1)
assert(text:find('Assets\\QuestloggerDungeon:16:16', 1, true))
local raid = U.TitleWithInstance(text, 'raid')
assert(raid:find('UI-RaidTargetingIcon_8:16:16', 1, true) and not raid:find('QuestloggerDungeon', 1, true))
assert(
    U.TitleWithInstance(raid, 'raid') == raid and U.TitleWithInstance(raid, nil) == '[51] Quest |TnewQuestIcon:12:12|t'
)
-- Check row reuse and hidden objectives.
row.Text:SetText('[40] New Quest |TnewQuestIcon:12:12|t')
row.questID = 4
U.LayoutRow(row, { listText = '1/1 (no XP)', rewards = {} }, {})
assert(not bg:IsShown())
assert(
    row.QuestloggerSummary:GetText() == '1/1 (no XP)'
        and not row.QuestloggerRewards:IsShown()
        and not divider:IsShown()
        and not row.QuestloggerRewards.label:IsShown()
)
assert(not row.Text:GetText():find('QuestloggerDungeon', 1, true))
assert(row:GetHeight() == 39)
GetCVarBool = function()
    return false
end
U.LayoutRow(row, { listText = '1/1 (unknown XP)', rewards = info.rewards }, {})
assert(select(2, row.QuestloggerRewards:GetPoint(1)) == summary and row:GetHeight() == 72 and divider:IsShown())
-- Check quest tags and card text.
C_QuestLog = {
    GetQuestTagInfo = function(id)
        if id == 1 then
            return { tagID = 81, tagName = 'Dungeon' }
        elseif id == 2 then
            return { tagID = 1, tagName = 'Group' }
        elseif id == 3 then
            return { tagID = 81, tagName = 'Dungeon' }
        end
    end,
}
assert(D.QuestCategory(2) == 'Elite')
assert(D.QuestCategory(3) == 'Dungeon')
assert(D.QuestCategory(1, '(Elite)') == 'Elite')
assert(D.PlainTag('|Ticon:12:12|t |cffffa640(Dungeon)|r') == 'Dungeon')
D.Locations = function()
    return {}
end
D.CardRewards = function()
    return 12345,
        {
            { name = 'Orgrimmar', amount = 250 },
            { name = 'Thunder Bluff', amount = 125, estimated = true },
            { name = 'Other Faction', amount = -37.5, estimated = true, choice = true },
        },
        false
end
UIParent = frame()
UIParent:SetSize(1400, 900)
QUEST_DASH = '- '
local lines = {
    'Test quest',
    '|Ticon:12:12|t Dungeon',
    ' ',
    'Find the item',
    ' ',
    '- 0/5 items',
    '<Click to view Quest Details>',
}
GameTooltip = {
    NumLines = function()
        return #lines
    end,
    Hide = function() end,
}
for i, s in ipairs(lines) do
    local l = frame()
    l:SetText(s)
    _G['GameTooltipTextLeft' .. i] = l
end
_G.GameTooltipTextLeft1:SetTextColor(1, 0.82, 0.3)
_G.GameTooltipTextLeft4:SetTextColor(0.91, 0.88, 0.84)
_G.GameTooltipTextLeft6:SetTextColor(0.75, 0.75, 0.75)
row.questID = 1
row.TagText = frame()
row.TagText:SetText('(Dungeon)')
U.ShowCard(row, info, function(id)
    return id * 450
end, function(id)
    return 'Quest ' .. id
end)
local shown = {}
for _, l in ipairs(card.lines) do
    if l:IsShown() then
        shown[#shown + 1] = l:GetText()
    end
end
local result = table.concat(shown, '\n')
assert(shown[1] == 'Test quest |cffffa640(Dungeon)|r')
assert(
    card.lines[1].font == GameFontNormalLarge
        and card.lines[2].font == GameFontHighlight
        and card.lines[3].font == GameFontHighlight
)
assert(card.strata == 'FULLSCREEN_DIALOG')
local skin = card.QuestloggerSkin
assert(#skin == 9 and skin[1].texture:find('TooltipPaper.tga', 1, true))
for _, t in ipairs(skin) do
    assert(#t.texCoord == 4 and select(2, t:GetPoint(1)) == card and select(2, t:GetPoint(2)) == card)
end
assert(
    card.lines[1].fontSize == 16
        and card.lines[2].fontSize == 13
        and card.lines[3].fontSize == 13
        and card.lines[4].fontSize == 12
)
local function colorIs(text, r, g, b)
    local c = text.textColor
    assert(c[1] == r and c[2] == g and c[3] == b, 'Unexpected color: ' .. text:GetText())
end
colorIs(card.lines[1], 1, 0.82, 0.3)
colorIs(card.lines[2], 0.91, 0.88, 0.84)
colorIs(card.lines[3], 0.75, 0.75, 0.75)
colorIs(card.lines[4], 1, 0.82, 0.3)
for _, l in ipairs(card.lines) do
    local text = l:GetText()
    if text:match('^Experience:') or text:match('^Reputation:') or text:match('^Money:') then
        colorIs(l, 0.65, 0.82, 1)
    elseif text == 'Unknown' then
        colorIs(l, 0.65, 0.65, 0.65)
    elseif text:match('^Quest [23] %(') then
        colorIs(l, 0.87, 0.89, 0.93)
    end
end
assert(select(5, card.lines[2]:GetPoint(1)) == -19)
assert(select(5, card.lines[3]:GetPoint(1)) == -39)
assert(card.lines[4].font == GameFontHighlightSmall)
-- Verify spacing with multiple objectives.
local originalLines = lines
lines = {
    'Test quest',
    'Dungeon',
    ' ',
    'Find the item',
    ' ',
    '- 0/5 items',
    '- 0/2 objects',
    '<Click to view Quest Details>',
}
for i, s in ipairs(lines) do
    local l = frame()
    l:SetText(s)
    _G['GameTooltipTextLeft' .. i] = l
end
U.ShowCard(row, info, function(id)
    return id * 450
end, function(id)
    return 'Quest ' .. id
end)
assert(select(5, card.lines[2]:GetPoint(1)) == -19)
assert(select(5, card.lines[3]:GetPoint(1)) == -39)
assert(select(5, card.lines[4]:GetPoint(1)) == -57)
-- Distinguish objective rows from party metadata.
row.questLogIndex = 1
GetQuestLogQuestText = function(index)
    assert(index == 1)
    return 'Story', 'Find the item'
end
lines = { 'Test quest', 'Dungeon', 'Replayable', ' ', 'Find the item', ' ', '- 0/5 items', '- 0/2 objects' }
for i, s in ipairs(lines) do
    local l = frame()
    l:SetText(s)
    _G['GameTooltipTextLeft' .. i] = l
end
U.ShowCard(row, info, function(id)
    return id * 450
end, function(id)
    return 'Quest ' .. id
end)
assert(card.lines[2].fontSize == 14 and card.lines[3].fontSize == 13 and card.lines[4].fontSize == 13)
assert(select(5, card.lines[3]:GetPoint(1)) == -38)
assert(select(5, card.lines[4]:GetPoint(1)) == -58)
assert(select(5, card.lines[5]:GetPoint(1)) == -76)
lines = { 'Test quest', 'Dungeon', ' ', 'Find the item', ' ', 'Party status' }
for i, s in ipairs(lines) do
    local l = frame()
    l:SetText(s)
    _G['GameTooltipTextLeft' .. i] = l
end
U.ShowCard(row, info, function(id)
    return id * 450
end, function(id)
    return 'Quest ' .. id
end)
assert(select(5, card.lines[3]:GetPoint(1)) == -37)
-- Restore original text for turn-in quests, with native and legacy objective APIs.
local function setNative(newLines)
    lines = newLines
    for i, s in ipairs(lines) do
        local l = frame()
        l:SetText(s)
        _G['GameTooltipTextLeft' .. i] = l
    end
end
local function showText()
    U.ShowCard(row, info, function(id)
        return id * 450
    end, function(id)
        return 'Quest ' .. id
    end)
    local texts = {}
    for _, l in ipairs(card.lines) do
        if l:IsShown() then
            texts[#texts + 1] = l:GetText()
        end
    end
    return table.concat(texts, '\n')
end
-- Tighten only paragraph breaks inside the description.
local paragraphText = 'First paragraph\n\nSecond paragraph'
GetQuestLogQuestText = function()
    return 'Story', paragraphText
end
setNative({ 'Test quest', 'Dungeon', ' ', paragraphText, ' ', '- 0/5 items', '- 0/2 objects' })
assert(showText():find('First paragraph\nSecond paragraph\n- 0/5 items', 1, true))
assert(select(5, card.lines[2]:GetPoint(1)) == -19)
assert(select(5, card.lines[3]:GetPoint(1)) == -44) -- 13px text + 12px paragraph gap
assert(select(5, card.lines[4]:GetPoint(1)) == -64) -- 7px objective gap preserved
assert(select(5, card.lines[5]:GetPoint(1)) == -82)
GetQuestLogQuestText = function()
    return 'Story', 'Find the item'
end
C_QuestLog.IsComplete = function(id)
    return id == 1
end
QUEST_WATCH_QUEST_READY = 'Ready for turn-in'
GetQuestLogCompletionText = function()
    return 'Return to the quest giver.'
end
C_QuestLog.GetQuestObjectives = function(id)
    assert(id == 1)
    return { { text = '5/5 items', finished = true }, { text = '2/2 objects', finished = true } }
end
setNative({ 'Test quest', 'Dungeon', 'Replayable', ' ', 'Return to the quest giver.', 'Party status' })
local completeText = showText()
assert(completeText:find('Replayable\nFind the item\n- 5/5 items\n- 2/2 objects\nParty status', 1, true))
assert(not completeText:find('Return to the quest giver.', 1, true))
assert(
    card.lines[2].fontSize == 14
        and card.lines[3].fontSize == 13
        and card.lines[4].fontSize == 13
        and card.lines[5].fontSize == 13
)
assert(select(5, card.lines[4]:GetPoint(1)) == -58)
setNative({ 'Test quest', 'Dungeon', ' ', 'Ready for turn-in' })
assert(showText():find('Find the item\n- 5/5 items\n- 2/2 objects', 1, true))
assert(select(5, card.lines[3]:GetPoint(1)) == -39)
C_QuestLog.GetQuestObjectives = nil
GetNumQuestLeaderBoards = function(index)
    assert(index == 1)
    return 1
end
GetQuestLogLeaderBoard = function(i, index)
    assert(i == 1 and index == 1)
    return '1/1 creature', 'monster', true
end
assert(showText():find('Find the item\n- 1/1 creature', 1, true))
GetNumQuestLeaderBoards, GetQuestLogLeaderBoard = nil, nil
C_QuestLog.GetQuestObjectives = function()
    return {}
end
assert(showText():find('Find the item\nQuest start', 1, true))
C_QuestLog.IsComplete, C_QuestLog.GetQuestObjectives, GetQuestLogCompletionText = nil, nil, nil
row.questLogIndex = nil
GetQuestLogQuestText = nil
lines = originalLines
for i, s in ipairs(lines) do
    local l = frame()
    l:SetText(s)
    _G['GameTooltipTextLeft' .. i] = l
end
U.ShowCard(row, info, function(id)
    return id * 450
end, function(id)
    return 'Quest ' .. id
end)
assert(select(2, card.scroll:GetPoint(1)) == 14 and select(3, card.scroll:GetPoint(1)) == -14)
assert(select(2, card.scroll:GetPoint(2)) == -14 and select(3, card.scroll:GetPoint(2)) == 14)
assert(card.content:GetWidth() == 312 and card:GetHeight() == card.content:GetHeight() + 28)
assert(result:find('Rewards\nExperience: 450', 1, true))
assert(card.rewardHolder.label:GetText() == 'Other:' and card.rewardHolder.label:IsShown())
assert(result:find('Quest 2\n|cffffa640(Elite)|r', 1, true))
assert(result:find('Quest 3\n|cffffa640(Dungeon)|r', 1, true))
assert(not result:find('\nDungeon\n', 1, true) and not result:find('Later dungeon quest', 1, true))
assert(
    card.followupLinks[1].suffix:GetText() == '2/3 (900 XP)'
        and card.followupLinks[2].suffix:GetText() == '3/3 (1,350 XP)'
)
assert(not result:find('1/3', 1, true) and not result:find('Click to view', 1, true))
assert(
    result:find(
        'Money: 1|TInterface\\MoneyFrame\\UI-GoldIcon:0|t 23|TInterface\\MoneyFrame\\UI-SilverIcon:0|t 45|TInterface\\MoneyFrame\\UI-CopperIcon:0|t',
        1,
        true
    )
)
assert(
    result:find('Reputation: Orgrimmar (|cff64aa76+250|r)', 1, true)
        and result:find('Reputation: Thunder Bluff (|cff64aa76+125|r)', 1, true)
)
assert(result:find('Reputation: Other Faction (|cffc06666-37.5|r) (choice)', 1, true))
assert(not result:find('~', 1, true) and not result:find('∼', 1, true))
assert(not result:find('No additional rewards', 1, true) and not result:find('None', 1, true))
local owner, tooltipShown
GameTooltip.SetOwner = function(self, b)
    owner = b
end
GameTooltip.IsOwned = function(self, b)
    return owner == b
end
GameTooltip.SetItemByID = function(self, id)
    assert(id == 5)
end
GameTooltip.Show = function()
    tooltipShown = true
end
GameTooltip.Hide = function()
    tooltipShown = false
    owner = nil
end
for _, b in ipairs({ row.QuestloggerRewards.icons[1], card.rewardHolder.icons[1] }) do
    b.scripts.OnEnter(b)
    assert(owner == b and tooltipShown)
    b.scripts.OnLeave(b)
    assert(not tooltipShown and owner == nil)
end
local function cardText(xp, money, reputation, pending, icons, repPending)
    D.CardRewards = function()
        return money, reputation, repPending
    end
    U.ShowCard(row, { rewards = icons or {}, rewardsPending = pending, future = {} }, function()
        return xp
    end, function()
        return 'Test quest'
    end)
    local shown = {}
    for _, l in ipairs(card.lines) do
        if l:IsShown() then
            shown[#shown + 1] = l:GetText()
        end
    end
    return table.concat(shown, '\n')
end
assert(cardText(0, 0, {}, false):find('Rewards\nNone', 1, true))
local testCases = {
    { 450, 0, {}, false },
    { 0, 100, {}, false },
    { 0, 0, { { name = 'Faction', amount = 100 } }, false },
    { 0, 0, {}, false, info.rewards },
    { nil, 0, {}, false },
    { 0, nil, {}, false },
    { 0, 0, {}, true },
    { 0, 0, {}, false, nil, true },
}
for i = 1, 8 do
    local t = testCases[i]
    local text = cardText(t[1], t[2], t[3], t[4], t[5], t[6])
    assert(not text:find('None', 1, true) and not text:find('No additional rewards', 1, true))
end
local moneyOnly = cardText(0, 100, {}, false)
assert(not moneyOnly:find('Experience:', 1, true))
local goldCoin = '|TInterface\\MoneyFrame\\UI-GoldIcon:0|t'
local silverCoin = '|TInterface\\MoneyFrame\\UI-SilverIcon:0|t'
local copperCoin = '|TInterface\\MoneyFrame\\UI-CopperIcon:0|t'
local coinCases = {
    { 1, '1' .. copperCoin },
    { 100, '1' .. silverCoin },
    { 10000, '1' .. goldCoin },
    { 101, '1' .. silverCoin .. ' 1' .. copperCoin },
    { 10001, '1' .. goldCoin .. ' 1' .. copperCoin },
    { 10100, '1' .. goldCoin .. ' 1' .. silverCoin },
    { 10101, '1' .. goldCoin .. ' 1' .. silverCoin .. ' 1' .. copperCoin },
}
for _, case in ipairs(coinCases) do
    assert(cardText(0, case[1], {}, false):match('Money: ([^\n]+)') == case[2])
end
assert(not cardText(0, 0, {}, false):find('Money:', 1, true))
assert(cardText(nil, 0, {}, false):find('Experience: Unknown', 1, true))
U.ResetRow(row)
assert(not divider:IsShown())
print(
    'UI mock tests passed: separate summary, foreign symbols, stable heights, pooled rows, borderless rewards, final-objective anchor, category and XP placement.'
)

-- Check target links, help and card reuse.
D.Targets = function(id)
    if id == 1 then
        return { { name = 'Boar', kind = 'npc' }, { name = 'Crate', kind = 'object' } }
    else
        return {}
    end
end
local clicked
D.SetTargetMacro = function(t)
    clicked = t
    return true
end
row.questID = 1
assert(cardText(450, 0, {}, false):find('Targets\nRewards', 1, true))
local help = card.targetHelp
assert(help:IsShown() and help.label == nil)
local heading = select(2, help:GetPoint(1))
assert(heading:GetText() == 'Targets' and select(1, help:GetPoint(1)) == 'TOPLEFT')
assert(select(4, help:GetPoint(1)) == 0 and select(5, help:GetPoint(1)) == 0)
assert(help:GetWidth() == heading:GetStringWidth() and help:GetHeight() == heading:GetStringHeight())
help.scripts.OnEnter(help)
local helpPopup = help.helpPopup
assert(helpPopup:IsShown() and #helpPopup.QuestloggerSkin == 9 and helpPopup.strata == 'FULLSCREEN_DIALOG')
local instructions = {}
for i, l in ipairs(helpPopup.lines) do
    instructions[i] = l:GetText()
end
colorIs(helpPopup.lines[1], 1, 0.82, 0.3)
colorIs(helpPopup.lines[2], 1, 1, 1)
colorIs(helpPopup.lines[6], 0.8, 0.8, 0.8)
colorIs(card.targets[1].label, 0.35, 0.8, 1)
card.targets[1].scripts.OnEnter(card.targets[1])
colorIs(card.targets[1].label, 0.8, 1, 1)
card.targets[1].scripts.OnLeave(card.targets[1])
colorIs(card.targets[1].label, 0.35, 0.8, 1)
local helpText = table.concat(instructions, ' ')
assert(
    helpText:find('Type /macro or /m and find Questlogger in your macros.', 1, true)
        and helpText:find('/macro', 1, true)
        and helpText:find('Interact key', 1, true)
        and helpText:find('action bar', 1, true)
)
assert(not tooltipShown and owner == nil) -- Native tooltip state is untouched.
help.scripts.OnLeave(help)
assert(not helpPopup:IsShown())
help.scripts.OnEnter(help)
card.scroll.scripts.OnMouseWheel(card.scroll, -1)
assert(not helpPopup:IsShown())
assert(card.targets[1]:IsShown() and card.targets[1].label:GetText() == 'Boar')
assert(card.targets[2]:IsShown() and card.targets[2].label:GetText() == 'Crate (object)')
assert(select(5, card.targets[1]:GetPoint(1)) > select(5, card.targets[2]:GetPoint(1)))
local rewardY
for _, l in ipairs(card.lines) do
    if l:IsShown() and l:GetText() == 'Rewards' then
        rewardY = select(5, l:GetPoint(1))
    end
end
assert(rewardY < select(5, card.targets[2]:GetPoint(1)))
card.targets[1]:ClickSecure()
assert(clicked.name == 'Boar' and card.targets[1].executed == '/cleartarget\n/targetexact Boar')
card.targets[2]:ClickSecure()
assert(clicked.name == 'Crate')
-- The independent switcher shares the target rows, not the card's lifecycle.
assert(widget and widget:IsShown() and widget.parent == UIParent and widget.questID == 1)
assert(widget:GetWidth() == 220 and #widget.QuestloggerSkin == 9 and widget.lines[1]:GetText() == 'Targets')
assert(widget.lines[1].fontSize == 14)
assert(
    select(1, widget:GetPoint(1)) == 'RIGHT'
        and select(2, widget:GetPoint(1)) == UIParent
        and select(3, widget:GetPoint(1)) == 'RIGHT'
        and select(4, widget:GetPoint(1)) == 0
        and select(5, widget:GetPoint(1)) == 0
)
assert(select(2, widget.scroll:GetPoint(2)) == -14 and select(3, widget.scroll:GetPoint(2)) == 10)
assert(widget:GetHeight() == widget.y + 24)
assert(select(4, widget.close:GetPoint(1)) == -10 and select(5, widget.close:GetPoint(1)) == -10)
assert(
    widget.targetN == 2
        and widget.targets[1].label:GetText() == 'Boar'
        and widget.targets[2].label:GetText() == 'Crate (object)'
)
assert(widget.targets[1].label.fontSize == card.targets[1].label.fontSize)
colorIs(widget.targets[1].label, 0.35, 0.8, 1)
colorIs(widget.targets[2].label, 0.8, 1, 1)
widget.targets[1]:ClickSecure()
assert(clicked.name == 'Boar' and widget.activeTarget.name == 'Boar')
colorIs(widget.targets[1].label, 0.8, 1, 1)
colorIs(widget.targets[2].label, 0.35, 0.8, 1)
widget.targetHelp.scripts.OnEnter(widget.targetHelp)
assert(widget.targetHelp.helpPopup:IsShown())
widget.targetHelp.scripts.OnLeave(widget.targetHelp)
widget.targetHelp.scripts.OnDragStart()
widget.targetHelp.scripts.OnDragStop()
local saveMacro = D.SetTargetMacro
D.SetTargetMacro = function()
    return false, 'Cannot change macros during combat.'
end
widget.targets[2]:ClickSecure()
assert(widget.activeTarget.name == 'Boar')
D.SetTargetMacro = saveMacro
U.HideTargetWidget(123)
assert(widget:IsShown())
widget.close.scripts.OnClick()
assert(not widget:IsShown())
card.targets[1]:ClickSecure()
assert(widget:IsShown())
help.scripts.OnEnter(help)
row.questID = 2
assert(not cardText(450, 0, {}, false):find('Targets', 1, true))
assert(not card.targets[1]:IsShown() and card.targets[1].target == nil and not card.targets[2]:IsShown())
assert(not help:IsShown() and not helpPopup:IsShown() and not tooltipShown and owner == nil)
assert(widget:IsShown() and widget.targets[1].target.name == 'Boar')
widget.targets[2]:ClickSecure()
assert(clicked.name == 'Crate')
row.questID = 1
cardText(450, 0, {}, false)
assert(card.targetHelp == help and help:IsShown())
help.scripts.OnEnter(help)
card.scripts.OnHide(card)
assert(not helpPopup:IsShown() and not tooltipShown and owner == nil)
assert(widget:IsShown())
U.HideTargetWidget(1)
assert(not widget:IsShown())
print('Target links, help tooltip, click and pooled card reset tests passed.')

-- Follow-up rewards use the quest ID, survive pointer travel and clear on reuse.
InCombatLockdown = function()
    return false
end
D.Targets = function()
    return {}
end
local loaded = false
local requested = {}
local calls = {}
C_QuestLog.HaveQuestData = function(id)
    return id ~= 4 or loaded
end
C_QuestLog.RequestLoadQuestByID = function(id)
    requested[id] = (requested[id] or 0) + 1
end
GetNumQuestLogRewards = function(id)
    calls[id] = (calls[id] or 0) + 1
    return (id == 2 or (id == 4 and loaded)) and 1 or 0
end
GetNumQuestLogChoices = function(id)
    return id == 2 and 1 or 0
end
GetQuestLogRewardInfo = function(_, id)
    return 'Sword', 10, 1, 2, true, 5
end
GetQuestLogChoiceInfo = function(_, id)
    return 'Shield', 11, 1, 2, true, 6
end
C_QuestInfoSystem = {
    GetQuestRewardCurrencies = function(id)
        return { { currencyID = 8, totalRewardAmount = 250 } }
    end,
}
C_CurrencyInfo = {
    GetFactionGrantedByCurrency = function(id)
        return 1
    end,
}
D.CardRewards = function(id)
    if id == 2 then
        return 12345, { { name = 'Orgrimmar', amount = 250 }, { name = 'Other Faction', amount = -125 } }, false
    end
    return 0, {}, false
end
row.questID = 1
local followInfo = { rewards = {}, future = { 2, 3, 4 }, futureSteps = { [2] = '2/4', [3] = '3/4', [4] = '4/4' } }
U.ShowCard(row, followInfo, function()
    return 450
end, function(id)
    return 'Quest ' .. id
end)
local first, second, third = table.unpack(card.followupLinks)
assert(first.questID == 2 and second.questID == 3 and third.questID == 4)
assert(calls[2] and calls[3] and calls[4] and requested[4] == 1, 'Rewards must be prefetched')
assert(
    first.heading:GetText() == 'Quest 2'
        and first.suffix:GetText() == '2/4 (450 XP)'
        and first.category:GetText() == '|cffffa640(Elite)|r'
)
assert(first.heading.fontSize == 12 and first.suffix.fontSize == 11 and first.category.fontSize == 12)
assert(select(4, first.suffix:GetPoint(1)) == math.ceil(first.heading:GetStringWidth()) + 2)
assert(
    select(4, first.category:GetPoint(1))
        == select(4, first.suffix:GetPoint(1)) + math.ceil(first.suffix:GetStringWidth()) + 4
)
assert(
    first.suffix.alpha == 0.75
        and first.suffix.textColor[4] == 1
        and first.heading.alpha == 1
        and first.heading.textColor[4] == 1
        and first.category.alpha == 1
        and first.category.textColor[4] == 1
        and row.QuestloggerSummary.textColor[4] == 0.80
)
assert(not second.pending and third.pending and not second.heading:GetText():find('INV_Misc_Gift_01', 1, true))
local cachedCalls = calls[2]
card.mouse = true
first.mouse = true
first.scripts.OnEnter(first)
local popup = card.followupPopup
assert(popup:IsShown() and popup.rewardHeading:GetText() == 'Rewards' and popup.strata == 'FULLSCREEN_DIALOG')
local function popupLine(text)
    for _, l in ipairs(popup.lines) do
        if l:IsShown() and l:GetText():find(text, 1, true) then
            return l
        end
    end
end
assert(
    #popup.QuestloggerSkin == 9
        and popup.rewardHeading.fontSize == 14
        and popup:GetHeight() == popup.content:GetHeight() + 26
)
colorIs(popup.rewardHeading, 1, 0.82, 0.3)
local xpLine = assert(popupLine('Experience: 450'))
colorIs(xpLine, 0.65, 0.82, 1)
assert(popupLine('Reputation: Orgrimmar (|cff64aa76+250|r)'))
assert(popupLine('Reputation: Other Faction (|cffc06666-125|r)'))
assert(popupLine('Money: 1|TInterface'))
assert(popup.rewardHolder:GetWidth() == 312 and popup.rewardHolder.icons[1]:GetWidth() == 26)
assert(popup.rewardHolder.label:GetText() == 'Other:' and popup.rewardHolder.label:IsShown())
assert(
    #popup.rewardHolder.icons == 2
        and popup.rewardHolder.icons[1].reward.id == 5
        and popup.rewardHolder.icons[2].reward.choice
)
assert(calls[2] == cachedCalls, 'Hover must reuse prefetched rewards')
assert(select(1, popup:GetPoint(1)) == 'TOPLEFT')
first.mouse = false
card.mouse = false
card.scripts.OnUpdate(card, 0.2)
assert(popup:IsShown() and card:IsShown())
popup.mouse = true
card.scripts.OnUpdate(card, 1)
assert(popup:IsShown() and card:IsShown())
local icon = popup.rewardHolder.icons[1]
icon.scripts.OnEnter(icon)
assert(owner == icon and tooltipShown)
icon.scripts.OnLeave(icon)
assert(not tooltipShown)
popup.mouse = false
card.mouse = true
card.scripts.OnUpdate(card, 0.5)
assert(not popup:IsShown() and not icon.reward and not card.followupSource)
second.mouse = true
second.scripts.OnEnter(second)
assert(popup:IsShown() and popupLine('Experience: 450') and not popup.rewardHolder:IsShown())
second.mouse = false
third.mouse = true
third.scripts.OnEnter(third)
assert(popup:IsShown() and popupLine('Loading rewards...') and requested[4] == 1)
assert(not popup.rewardHolder:IsShown())
third.mouse = false
popup.mouse = true
loaded = true
card.scripts.OnUpdate(card, 0.6)
assert(
    popup:IsShown()
        and not popupLine('Loading rewards...')
        and popup.rewardHolder.icons[1].reward.id == 5
        and not popup.rewardHolder.icons[2]:IsShown()
)
assert(not third.pending and not third.heading:GetText():find('INV_Misc_Gift_01', 1, true))
popup.mouse = false
-- A pending quest that resolves to no icon rewards keeps its popup.
loaded = false
D.ResetFollowupRewards()
U.ShowCard(row, followInfo, function()
    return 450
end, function(id)
    return 'Quest ' .. id
end)
first.scripts.OnEnter(first)
third.scripts.OnEnter(third)
third.mouse = true
assert(popupLine('Loading rewards...'))
local originalCount = GetNumQuestLogRewards
GetNumQuestLogRewards = function(id)
    if id == 4 then
        return 0
    end
    return originalCount(id)
end
loaded = true
card.scripts.OnUpdate(card, 0.6)
assert(
    popup:IsShown()
        and popupLine('Experience: 450')
        and not popupLine('Loading rewards...')
        and not popup.rewardHolder:IsShown()
)
-- A confirmed rewardless quest displays None, and scalar-only quests show their rewards.
U.ShowCard(row, followInfo, function()
    return 0
end, function(id)
    return 'Quest ' .. id
end)
third.scripts.OnEnter(third)
assert(popup:IsShown() and popupLine('None'))
local savedCardRewards = D.CardRewards
D.CardRewards = function(id)
    if id == 3 then
        return 0, { { name = 'Orgrimmar', amount = 250 } }, false
    elseif id == 4 then
        return 10000, {}, false
    end
    return savedCardRewards(id)
end
second.scripts.OnEnter(second)
assert(popup:IsShown() and popupLine('Reputation: Orgrimmar') and not popupLine('None'))
third.scripts.OnEnter(third)
assert(popup:IsShown() and popupLine('Money: 1') and not popupLine('None'))
for _, case in ipairs(coinCases) do
    D.CardRewards = function()
        return case[1], {}, false
    end
    U.ShowCard(row, followInfo, function()
        return 0
    end, function(id)
        return 'Quest ' .. id
    end)
    card.followupLinks[3].scripts.OnEnter(card.followupLinks[3])
    assert(popupLine('Money:'):GetText() == 'Money: ' .. case[2])
end
D.CardRewards = savedCardRewards
GetNumQuestLogRewards = originalCount
D.ResetFollowupRewards()
U.ShowCard(row, followInfo, function()
    return 450
end, function(id)
    return 'Quest ' .. id
end)
third.mouse = false
card.right = 1390
card.left = 1050
first.mouse = true
first.scripts.OnEnter(first)
assert(select(1, popup:GetPoint(1)) == 'TOPRIGHT')
card.scroll.scripts.OnMouseWheel(card.scroll, -1)
assert(not popup:IsShown() and not card.followupSource)
first.scripts.OnEnter(first)
assert(popup:IsShown())
U.ShowCard(row, { rewards = {}, future = {} }, function()
    return 0
end, function()
    return 'Other quest'
end)
assert(not popup:IsShown() and not first:IsShown() and first.questID == nil and not icon.reward)
for _, summary in ipairs(card.followupSummaries) do
    assert(not summary:IsShown())
end
for _, l in ipairs(card.lines) do
    if l:IsShown() then
        assert(l.alpha == 1 and l.textColor[4] == 1)
    end
end
U.ShowCard(row, followInfo, function()
    return 450
end, function(id)
    return 'Quest ' .. id
end)
first.scripts.OnEnter(first)
assert(popup:IsShown())
card.scripts.OnHide(card)
assert(not popup:IsShown() and not icon.reward and not card.followupSource)
print(
    'Follow-up reward tests passed: eligible rewards, empty quests, delayed loading, hover travel, item tooltip, anchoring, scroll and reuse.'
)

-- Prefetch completes without adding markers or changing the card layout.
loaded = false
D.ResetFollowupRewards()
local cat = C_QuestLog.GetQuestTagInfo
C_QuestLog.GetQuestTagInfo = function(id)
    if id == 4 then
        return { tagID = 81, tagName = 'Dungeon' }
    end
    return cat(id)
end
U.ShowCard(
    row,
    { rewards = {}, future = { 4, 2, 3 }, futureSteps = { [4] = '4/4', [2] = '2/4', [3] = '3/4' } },
    function()
        return 450
    end,
    function(id)
        return 'Quest ' .. id
    end
)
local pendingLine, followingLine = table.unpack(card.followupLinks)
local nextY = select(5, followingLine.heading:GetPoint(1))
local oldHeight = card.content:GetHeight()
assert(pendingLine.pending and not pendingLine.heading:GetText():find('INV_Misc_Gift_01', 1, true))
assert(not card.followupSource)
card.mouse = true
loaded = true
D.FollowupRewardDataLoaded(4)
card.scripts.OnUpdate(card, 0.6)
assert(not pendingLine.pending and not popup:IsShown())
assert(
    pendingLine.heading:GetText() == 'Quest 4'
        and pendingLine.suffix:GetText() == '4/4 (450 XP)'
        and pendingLine.category:GetText() == '|cffffa640(Dungeon)|r'
)
assert(select(5, followingLine.heading:GetPoint(1)) == nextY)
assert(card.content:GetHeight() == oldHeight)
local beforeHover = calls[4]
pendingLine.mouse = true
pendingLine.scripts.OnEnter(pendingLine)
assert(popup:IsShown() and not popupLine('Loading rewards...') and calls[4] == beforeHover)
pendingLine.mouse = false
C_QuestLog.GetQuestTagInfo = cat
card.scripts.OnHide(card)
print('Prefetched reward tests passed: updates before hover, stable lines, chain positions and instant cached popup.')

-- Long names wrap the translucent suffix as a whole and preserve the hover area.
U.ShowCard(row, followInfo, function()
    return 81450
end, function(id)
    return id == 2 and string.rep('Long quest name ', 8) or 'Quest ' .. id
end)
local long = card.followupLinks[1]
assert(long.suffix:GetText() == '2/4 (81,450 XP)')
assert(select(5, long.suffix:GetPoint(1)) < select(5, long.heading:GetPoint(1)))
assert(long:GetHeight() >= 24 and long.suffix.fontSize == 11)
assert(select(5, card.followupLinks[2].heading:GetPoint(1)) < select(5, long.suffix:GetPoint(1)))
assert(not card.rewardHolder:IsShown() and not card.rewardHolder.label:IsShown())
long.scripts.OnEnter(long)
assert(popup:IsShown() and popup.rewardHolder.label:IsShown() and popup.rewardHolder.label:GetText() == 'Other:')
card.scripts.OnHide(card)
-- Reward wrapping accounts for the prefix, including very narrow rows.
local strip = frame()
local sample = { { kind = 'item', id = 5 }, { kind = 'item', id = 5 }, { kind = 'item', id = 5 } }
assert(U.RewardStrip(strip, sample, 100, 18, 'Rewards:') == 44)
assert(select(4, strip.icons[1]:GetPoint(1)) > 0 and select(5, strip.icons[3]:GetPoint(1)) == -22)
assert(U.RewardStrip(strip, sample, 42, 18, 'Rewards:') > 44)
assert(select(4, strip.icons[1]:GetPoint(1)) == 0 and select(5, strip.icons[1]:GetPoint(1)) < 0)
assert(U.RewardStrip(strip, {}, 42, 18, 'Rewards:') == 0 and not strip.label:IsShown())
-- Repeated changes in reward lines and follow-up counts cannot leak summary styling.
for i = 1, 6 do
    local future = i % 2 == 0 and { 2, 3, 4 } or { 3 }
    U.ShowCard(row, { rewards = {}, future = future }, function()
        return i % 2 == 0 and 450 or 0
    end, function(id)
        return 'Quest ' .. id
    end)
    local ordinary = {}
    for _, l in ipairs(card.lines) do
        ordinary[l] = true
        if l:IsShown() then
            assert(l.alpha == 1 and l.textColor[4] == 1 and l.fontSize ~= 11)
        end
    end
    for j, l in ipairs(card.followupSummaries) do
        assert(not ordinary[l] and l.alpha == 0.75 and l.textColor[4] == 1 and l.fontSize == 11)
        assert(l:IsShown() == (j <= #future))
        assert(not l:GetText():find('·', 1, true))
        if j <= #future then
            local b = card.followupLinks[j]
            assert(b.suffix == l and b.heading.fontSize == 12 and b.heading.alpha == 1)
            if b.category then
                assert(b.category.fontSize == 12 and b.category.alpha == 1)
            end
        end
    end
end
card.scripts.OnHide(card)
print('New prefix, mixed font, isolated opacity, tooltip padding and long follow-up layout checks passed.')

-- Switching entities hides stale models and retries without another hover.
D.Targets = function()
    return { { name = 'Boar', kind = 'npc', id = 99 }, { name = 'Crate', kind = 'object', id = 100 } }
end
D.Locations = function(qid, start)
    return { { name = 'Giver', kind = 'npc', id = start and 11 or 12 } }
end
U.ShowCard(row, { rewards = {}, future = {} }, function()
    return 450
end, function()
    return 'Quest'
end)
local start = card.links[1]
start.mouse = true
start.scripts.OnEnter(start)
local ep = card.entityPopup
assert(ep:IsShown() and ep.model.creatureID == 11 and ep.pending and ep.spinner:IsShown())
local previewW, previewH = ep:GetWidth(), ep:GetHeight()
local hintY = select(5, ep.status:GetPoint(1))
local dotAlpha = ep.spinner.dots[1].alpha
assert(#ep.spinner.dots == 8 and not ep.status:GetText():find('Loading', 1, true))
U.UpdateEntityPreview(card, 0.1)
assert(ep.spinner.dots[1].alpha ~= dotAlpha and ep.spinner:IsShown())
assert(ep.model.alpha == 0 and ep.status:GetText():find('no coordinates', 1, true))
ep.model.fileID = 123
U.UpdateEntityPreview(card, 0.2)
assert(not ep.pending and ep.model:IsShown() and ep.model.alpha == 1 and not ep.spinner:IsShown())
assert(ep:GetWidth() == previewW and ep:GetHeight() == previewH and select(5, ep.status:GetPoint(1)) == hintY)
local oldModel = ep.model
start.mouse = false
local finish = card.links[2]
finish.mouse = true
finish.scripts.OnEnter(finish)
assert(ep.pending and ep.model ~= oldModel and ep.model.creatureID == 12 and ep.model.alpha == 0)
assert(not oldModel:IsShown() and oldModel.alpha == 0 and ep.spinner:IsShown())
local secondHeight = ep:GetHeight()
-- A late completion of the old frame cannot reveal it.
oldModel.fileID = 123
U.UpdateEntityPreview(card, 0.1)
assert(ep.pending and ep.model.alpha == 0 and not oldModel:IsShown())
local requests = ep.model.requests
ep.model.cachedFile = 456
U.UpdateEntityPreview(card, 0.25)
assert(not ep.pending and ep.model.requests == requests + 1 and ep.model.fileID == 456 and ep.model.alpha == 1)
assert(not ep.spinner:IsShown() and ep:GetHeight() == secondHeight)
ep.model.cachedFile = nil
finish.mouse = false
ep.mouse = true
U.UpdateEntityPreview(card, 1)
assert(ep:IsShown())
ep.mouse = false
U.UpdateEntityPreview(card, 0.5)
assert(not ep:IsShown() and not ep.model.creatureID)
local npc = card.targets[1]
npc.mouse = true
npc.scripts.OnEnter(npc)
assert(ep.model.creatureID == 99 and ep.pending and ep.model.alpha == 0 and ep.spinner:IsShown())
U.UpdateEntityPreview(card, 5)
assert(
    not ep.pending
        and not ep:IsShown()
        and not ep.model:IsShown()
        and not ep.spinner:IsShown()
        and not card.entitySource
)
local object = card.targets[2]
object.scripts.OnEnter(object)
assert(not ep:IsShown() and not card.entitySource)
object:ClickSecure()
assert(clicked.name == 'Crate')
card.scroll.scripts.OnMouseWheel(card.scroll, -1)
assert(not ep:IsShown())
-- Missing QuestieDB is explained on hover, not reported as an empty quest.
D.DatabaseIssue = databaseIssue
LibQuestieDB = nil
D.Locations = function()
    return {}
end
D.Targets = function()
    return {}
end
D.CardRewards = function()
    return 0, {}, true
end
U.ShowCard(row, { rewards = {}, future = {}, chainIssue = D.DatabaseIssue() }, function()
    return nil
end, function()
    return 'Quest'
end)
assert(#card.unavailableLinks >= 5)
for _, link in ipairs(card.unavailableLinks) do
    if link:IsShown() then
        link.scripts.OnEnter(link)
        assert(ep:IsShown() and ep.status:GetText():find('QuestieDB is unavailable', 1, true))
    end
end
card.scripts.OnHide(card)
assert(not ep:IsShown())
print(
    'Entity preview tests passed: NPC loading and retry, stale model isolation, timeout, hover travel, hidden object previews, pin hints, macro clicks and missing dependency tooltips.'
)
local source = frame(card)
source.mouse = true
C_Item = {
    GetItemIconByID = function(id)
        assert(id == 45)
        return 123
    end,
}
U.ShowEntityPreview(card, source, { name = 'Letter', kind = 'item', id = 45 })
assert(ep.itemHolder:IsShown() and ep.itemHolder.icons[1].reward.id == 45 and not ep.spinner:IsShown())
U.CloseEntityPreview(card)
assert(not ep.itemHolder:IsShown() and not ep.itemHolder.icons[1].reward)
print('Item preview tests passed: native reward button, item ID and cleanup.')

-- Full child cards keep their own widgets and stop nesting after one level.
D.DatabaseIssue = function() end
D.ResetFollowupRewards()
LibQuestieDB = {
    Quest = {
        objectivesText = function(id)
            return { 'Future quest description ' .. id }
        end,
        objectives = function(id)
            return { { { 99, 'Defeat the boar' } } }
        end,
    },
}
C_QuestLog.GetLogIndexForQuestID = function(id)
    if id == 1 then
        return 1
    end
end
C_QuestLog.GetQuestObjectives = function(id)
    if id == 1 then
        return { { text = '1/3 items', finished = false } }
    end
    if id == 3 then
        return { { text = '0/5 creatures', finished = false } }
    end
    return {}
end
GetQuestLogQuestText = function(index)
    assert(index == 1)
    return 'Story', 'Find the item'
end
D.Locations = function(id, start)
    return {
        {
            name = start and 'Giver ' .. id or 'Recipient ' .. id,
            kind = 'npc',
            id = start and 11 or 12,
            mapID = start and 42 or 43,
            x = 0.5,
            y = 0.5,
        },
    }
end
D.Targets = function(id)
    local rows = { { name = 'Boar ' .. id, kind = 'npc', id = 99 } }
    if id == 2 or id == 3 then
        rows[2] = { name = 'Wolf ' .. id, kind = 'npc', id = 100 }
    end
    if id == 2 then
        rows[3] = { name = 'Giver 2', kind = 'npc', id = 11 }
    end
    return rows
end
D.CardRewards = function(id)
    return 25, {}, false
end
F.GetSummary = function(id)
    assert(id == 2 or id == 3)
    return { future = id == 2 and { 3, 4 } or { 4 }, futureSteps = { [3] = '3/4', [4] = '4/4' }, rewards = {} }
end
row.questID = 1
row.questLogIndex = 1
row.mouse = false
setNative({ 'Main quest', 'Dungeon', ' ', 'Find the item', ' ', '- 1/3 items' })
U.ShowCard(row, followInfo, function()
    return 450
end, function(id)
    return 'Quest ' .. id
end)
first = card.followupLinks[1]
first.mouse = true
first.scripts.OnEnter(first)
assert(
    popup:IsShown()
        and popupLine('Quest 2')
        and popupLine('Future quest description 2')
        and popupLine('- Defeat the boar')
)
assert(
    popupLine('Quest start')
        and popupLine('Quest end')
        and popupLine('Targets')
        and popupLine('Rewards')
        and popupLine('Follow-up quests')
)
assert(popup.links[1].location.name == 'Giver 2' and popup.targets[1].target.name == 'Boar 2')
assert(popup.followupSummaryN == 2 and popup.followupSummaries[1]:IsShown() and popup.followupSummaries[2]:IsShown())
assert(popup.followupN == 0 and #popup.followupLinks == 0, 'Child follow-ups must not create mouse targets')
local childTarget = popup.targets[1]
childTarget.mouse = true
childTarget.scripts.OnEnter(childTarget)
assert(popup.entityPopup:IsShown() and popup.entityPopup.model.creatureID == 99)
first.mouse = false
popup.mouse = false
popup.entityPopup.mouse = true
card.mouse = false
card.scripts.OnUpdate(card, 0.6)
assert(card:IsShown() and popup:IsShown() and popup.entityPopup:IsShown())
childTarget:ClickSecure()
assert(clicked.name == 'Boar 2')
assert(widget:IsShown() and widget.questID == 2 and widget.targets[2].target.name == 'Wolf 2' and widget.targetN == 3)
local oldPin, oldIssue = D.Pin, D.PinIssue
local pins = 0
D.Pin = function()
    pins = pins + 1
    return true
end
D.PinIssue = function()
    return nil
end
local oldMap, oldToggle = WorldMapFrame, ToggleWorldMap
WorldMapFrame = frame()
WorldMapFrame:Hide()
function WorldMapFrame:SetMapID(id)
    self.mapID = id
end
ToggleWorldMap = function()
    WorldMapFrame:Show()
    WorldMapFrame:SetMapID(1)
end
widget.targets[3]:ClickSecure()
assert(
    clicked.name == 'Giver 2'
        and pins == 1
        and WorldMapFrame:IsShown()
        and WorldMapFrame.mapID == 42
        and widget.targets[3].executed:find('/targetexact Giver 2', 1, true)
)
widget.scripts.OnUpdate(widget, 0.02)
assert(widget.strata == 'LOW')
widget.targets[1].scripts.OnEnter(widget.targets[1])
assert(not widget.entityPopup or not widget.entityPopup:IsShown())
widget.targetHelp.scripts.OnEnter(widget.targetHelp)
assert(not widget.targetHelp.helpPopup or not widget.targetHelp.helpPopup:IsShown())
WorldMapFrame:Hide()
widget.scripts.OnUpdate(widget, 0.02)
assert(widget.strata == 'HIGH')
WorldMapFrame:Show()
widget:Hide()
WorldMapFrame:Hide()
popup.links[2]:ClickSecure()
assert(
    clicked.name == 'Recipient 2'
        and not widget:IsShown()
        and pins == 2
        and WorldMapFrame:IsShown()
        and WorldMapFrame.mapID == 43
)
D.Pin, D.PinIssue, WorldMapFrame, ToggleWorldMap = oldPin, oldIssue, oldMap, oldToggle
-- Reopen after the pin handler hid the main card.
U.ShowCard(row, followInfo, function()
    return 450
end, function(id)
    return 'Quest ' .. id
end)
first = card.followupLinks[1]
first.mouse = true
first.scripts.OnEnter(first)
childTarget.mouse = false
popup.entityPopup.mouse = false
popup.mouse = true
popup.scroll.scripts.OnMouseWheel(popup.scroll, -1)
assert(popup:IsShown() and not popup.entityPopup:IsShown())
second = card.followupLinks[2]
second.mouse = true
second.scripts.OnEnter(second)
assert(popupLine('Future quest description 3') and popupLine('- 0/5 creatures') and not popupLine('- Defeat the boar'))
assert(popup.followupSummaryN == 1 and not popup.followupSummaries[2]:IsShown())
assert(#popup.followupLinks == 0)
popup.targets[2]:ClickSecure()
assert(
    widget:IsShown() and widget.questID == 3 and widget.targets[1].target.name == 'Boar 3' and clicked.name == 'Wolf 3'
)
card.targets[1]:ClickSecure()
assert(not widget:IsShown(), 'Single objective must not open the widget even with endpoints')
-- Clicking the full quest text pins the same main card even after the source row hides.
local panel = frame()
panel.questID = 1
local function visibleText(f)
    local out = {}
    for _, l in ipairs(f.lines) do
        if l:IsShown() then
            out[#out + 1] = l:GetText()
        end
    end
    return table.concat(out, '\n')
end
local before = visibleText(card)
U.ShowDetailsCard(panel, 1, followInfo, function()
    return 450
end, function(id)
    return 'Quest ' .. id
end)
assert(card:IsShown() and card.pinned and card.row == panel and visibleText(card) == before)
assert(select(2, card:GetPoint(1)) == UIParent and not popup:IsShown())
row:Hide()
card.mouse = false
panel.mouse = false
card.scripts.OnUpdate(card, 2)
assert(card:IsShown() and card.pinned, 'Pinned card survives mouse departure')
-- Without the native hover snapshot, reconstruct the card from the selected quest APIs.
panel.questID = 3
U.ShowDetailsCard(panel, 3, { rewards = {}, future = {} }, function()
    return 450
end, function(id)
    return 'Quest ' .. id
end)
assert(
    card.questID == 3
        and visibleText(card):find('Future quest description 3', 1, true)
        and not visibleText(card):find('Find the item', 1, true)
)
panel:Hide()
card.scripts.OnUpdate(card, 0.1)
assert(not card:IsShown())
card.scripts.OnHide(card)
print(
    'Full follow-up and pinned details tests passed: shared sections, model/macro interaction, static nested lists, native text reuse and panel lifecycle.'
)

-- Tracker owners may be recycled for another quest while a card is showing.
local trackerRow = frame()
trackerRow.id = 1
trackerRow.mouse = true
local function trackedID(f)
    return f.id
end
U.ShowTrackerCard(trackerRow, 1, followInfo, function()
    return 450
end, function(id)
    return 'Quest ' .. id
end, trackedID)
assert(
    card:IsShown()
        and card.row == trackerRow
        and not card.pinned
        and visibleText(card):find('Find the item', 1, true)
        and visibleText(card):find('1/3 items', 1, true)
)
assert(card.followupN > 0)
card.scripts.OnUpdate(card, 0.1)
assert(card:IsShown())
-- A moving tracker must re-anchor even while the same quest remains hovered.
trackerRow.left = 100
trackerRow.right = 240
card.scripts.OnUpdate(card, 0.1)
assert(card.anchorX == 242 and card.anchorPoint == 'TOPLEFT')
trackerRow.left = 1100
trackerRow.right = 1300
U.ShowTrackerCard(trackerRow, 1, followInfo, function()
    return 450
end, function(id)
    return 'Quest ' .. id
end, trackedID)
assert(card.anchorPoint == 'TOPRIGHT' and card.anchorX == 1098)
trackerRow.id = 3
card.scripts.OnUpdate(card, 0.1)
assert(not card:IsShown())
card.scripts.OnHide(card)
U.ShowTrackerCard(trackerRow, 3, { rewards = {}, future = {} }, function()
    return 450
end, function(id)
    return 'Quest ' .. id
end, trackedID)
assert(card:IsShown() and visibleText(card):find('Future quest description 3', 1, true))
trackerRow.mouse = false
card.mouse = false
card.scripts.OnUpdate(card, 0.6)
assert(not card:IsShown())
print('Tracker hover card tests passed: shared sections and recycled owner lifecycle.')
