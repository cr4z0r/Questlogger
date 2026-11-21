-- Exercise tracker hooks with native-like pooled blocks and a Questie adapter.
local F = dofile('tests/load.lua')
local T = F.Trackers
unpack = table.unpack or unpack
local combat = false
InCombatLockdown = function()
    return combat
end
local function frame(parent)
    local t = { parent = parent, children = {}, points = {}, scripts = {}, shown = true, w = 250, h = 20 }
    if parent then
        parent.children[#parent.children + 1] = t
    end
    function t:GetChildren()
        return unpack(self.children)
    end
    function t:GetParent()
        return self.parent
    end
    function t:SetParent(p)
        if self.parent then
            for i, v in ipairs(self.parent.children) do
                if v == self then
                    table.remove(self.parent.children, i)
                    break
                end
            end
        end
        self.parent = p
        p.children[#p.children + 1] = self
    end
    function t:SetScrollChild(child)
        self.scrollChild = child
    end
    function t:SetVerticalScroll(v)
        self.verticalScroll = v
    end
    function t:EnableMouseWheel(v)
        self.wheel = v
    end
    function t:EnableMouse(v)
        self.mouseEnabled = v
    end
    function t:IsMouseOver()
        return self.mouseOver == true
    end
    function t:IsEnabled()
        return self.enabled ~= false
    end
    function t:Click(button)
        if self:IsEnabled() and self.scripts.OnClick then
            self.scripts.OnClick(self, button)
        end
    end
    function t:RegisterForClicks(...)
        self.clicks = { ... }
    end
    function t:GetScript(k)
        return self.scripts[k]
    end
    function t:GetWidth()
        return self.w
    end
    function t:GetHeight()
        return self.h
    end
    function t:SetWidth(v)
        self.w = v
    end
    function t:SetSize(w, h)
        self.w, self.h = w, h
    end
    function t:GetScale()
        return self.scale or 1
    end
    function t:SetScale(v)
        self.scale = v
    end
    function t:SetHeight(v)
        self.h = v
    end
    function t:SetPoint(...)
        self.points[#self.points + 1] = { ... }
    end
    function t:GetPoint(i)
        return unpack(self.points[i] or {})
    end
    function t:GetNumPoints()
        return #self.points
    end
    function t:ClearAllPoints()
        self.points = {}
    end
    function t:GetStringHeight()
        return self.h
    end
    function t:SetText(s)
        self.text = s
    end
    function t:GetText()
        return self.text
    end
    function t:SetEnabled(v)
        self.enabled = v
    end
    function t:IsShown()
        return self.shown
    end
    function t:IsVisible()
        return self.shown and (not self.parent or self.parent:IsVisible())
    end
    function t:SetShown(v)
        self.shown = v
    end
    function t:Show()
        self.shown = true
        if self.scripts.OnShow then
            self.scripts.OnShow(self)
        end
    end
    function t:Hide()
        self.shown = false
        if self.scripts.OnHide then
            self.scripts.OnHide(self)
        end
    end
    function t:SetScript(k, v)
        self.scripts[k] = v
    end
    function t:HookScript(k, v)
        local old = self.scripts[k]
        self.scripts[k] = function(...)
            if old then
                old(...)
            end
            v(...)
        end
    end
    function t:CreateFontString()
        return frame(self)
    end
    function t:CreateTexture()
        return frame(self)
    end
    function t:SetAtlas(atlas)
        self.atlas = atlas
    end
    function t:SetColorTexture(...)
        self.tint = { ... }
    end
    function t:SetJustifyV(j)
        self.justifyV = j
    end
    function t:SetTextColor(...)
        self.color = { ... }
    end
    for _, key in ipairs({ 'SetJustifyH', 'SetFont', 'SetFrameStrata', 'SetAlpha', 'SetClampedToScreen' }) do
        t[key] = function() end
    end
    return t
end
UIParent = frame()
CreateFrame = function(kind, _, parent)
    local f = frame(parent)
    f.kind = kind
    return f
end
hooksecurefunc = function(t, k, fn)
    local old = t[k]
    t[k] = function(...)
        local result = { old(...) }
        fn(...)
        return unpack(result)
    end
end
local tickers = {}
C_Timer = {
    After = function(_, fn)
        fn()
    end,
    NewTicker = function(_, fn)
        tickers[#tickers + 1] = fn
        return {}
    end,
}
local log =
    { { isHeader = true, title = 'Durotar' }, { questID = 1 }, { questID = 2 }, { isHeader = true, title = 'Barrens' }, {
        questID = 3,
    } }
local watched = { [1] = true, [2] = true, [3] = true }
C_QuestLog = {
    GetNumQuestLogEntries = function()
        return #log, 3
    end,
    GetMaxNumQuestsCanAccept = function()
        return 40
    end,
    GetInfo = function(i)
        return log[i]
    end,
    GetQuestWatchType = function(id)
        return watched[id] and 1 or nil
    end,
    AddQuestWatch = function(id)
        watched[id] = true
    end,
    RemoveQuestWatch = function(id)
        watched[id] = nil
    end,
}
local m, o = T.LogRegions()
assert(m[1] == 'Durotar' and m[2] == 'Durotar' and m[3] == 'Barrens' and o.Durotar < o.Barrens)
local flags = {}
T.ToggleSet({ a = true, b = true }, flags)
assert(flags.a and flags.b)
T.ToggleSet({ a = true, b = true }, flags)
assert(not flags.a and not flags.b)
ObjectiveTrackerFrame = frame(UIParent)
local root = ObjectiveTrackerFrame
local mod = frame(root)
QuestObjectiveTracker = mod
mod.ContentsFrame = frame(mod)
mod.Header = frame(mod)
mod.Header.Text = frame(mod.Header)
mod.Header.Text:SetText('Quests')
local other = frame(root)
local function nativeHeader(owner)
    local header = owner.Header or frame(owner)
    owner.Header = header
    header.Text = header.Text or frame(header)
    header.Background = frame(header)
    header.MinimizeButton = frame(header)
    local button = header.MinimizeButton
    button.normalTexture = frame(button)
    button.pushedTexture = frame(button)
    function button:GetNormalTexture()
        return self.normalTexture
    end
    function button:GetPushedTexture()
        return self.pushedTexture
    end
    function owner:IsCollapsed()
        return self.collapsed == true
    end
    function header:SetCollapsed(value)
        owner.collapsed = value
    end
    function header:OnToggle()
        owner.headerClicks = (owner.headerClicks or 0) + 1
        self:SetCollapsed(not owner.collapsed)
    end
    header.MinimizeButton:SetScript('OnClick', function()
        header:OnToggle()
    end)
    return header
end
nativeHeader(root)
nativeHeader(mod)
nativeHeader(other)
root.Header.TopBorder = frame(root.Header)
root.Header.FilterButton = frame(root.Header)
root.modules = { mod, other }
mod.blockTemplate = 'ObjectiveTrackerQuestPOIBlockTemplate'
mod.headerHeight = 20
mod.fromHeaderOffsetY = -2
mod.fromBlockOffsetY = -3
mod.blockOffsetX = 5
mod.availableHeight = 500
local blocks = {}
local nativeClicks, opened = 0, {}
QuestMapFrame_OpenToQuestDetails = function(id)
    opened[#opened + 1] = id
end
local modified = false
IsModifiedClick = function()
    return modified
end
local normal, bright = { r = 0.7, g = 0.7, b = 0.7 }, { r = 1, g = 1, b = 1 }
local complete, completeBright = { r = 0.2, g = 0.6, b = 0.2 }, { r = 0.4, g = 1, b = 0.4 }
normal.reverse = bright
bright.reverse = normal
complete.reverse = completeBright
completeBright.reverse = complete
OBJECTIVE_TRACKER_COLOR =
    { Normal = normal, NormalHighlight = bright, Complete = complete, CompleteHighlight = completeBright }
local function block(id)
    local b = frame(mod.ContentsFrame)
    b.id = id
    b.template = mod.blockTemplate
    b.height = 45
    b.h = 45
    b.HeaderText = frame(b)
    b.HeaderText.h = 14
    b.parentModule = mod
    b.poiButton = frame(b)
    b.poiButton:SetScale(id == 2 and 1.2 or 1)
    function b:CheckAndReleasePOIButton()
        self.poiButton = nil
    end
    b.HeaderButton = frame(b)
    b.HeaderButton:SetScript('OnClick', function()
        nativeClicks = nativeClicks + 1
    end)
    local line = frame(b)
    line.parentBlock = b
    line.objectiveKey = 1
    line.Text = frame(line)
    line.Text.colorStyle = normal
    line.Dash = frame(line)
    local second = frame(b)
    second.parentBlock = b
    second.objectiveKey = 2
    second.Text = frame(second)
    second.Text.colorStyle = complete
    second.Dash = frame(second)
    b.usedLines = { [1] = line, [2] = second }
    b.ItemButton = frame(mod.ContentsFrame)
    b.addedRegions = { [b.ItemButton] = true }
    -- Model Blizzard's native block-wide reversal and objective refresh.
    function b:UpdateHighlight()
        for _, l in pairs(self.usedLines) do
            local style = l.Text.colorStyle.reverse
            l.Text.colorStyle = style
            l.Text:SetTextColor(style.r, style.g, style.b)
            local dash = self.isHighlighted and bright or normal
            l.Dash:SetTextColor(dash.r, dash.g, dash.b)
        end
    end
    function b:SetStringText(text, value, full, style, highlight)
        style = style or normal
        style = highlight and style.reverse or style
        text.colorStyle = style
        text:SetTextColor(style.r, style.g, style.b)
    end
    function b:ForEachUsedLine(fn)
        for _, l in pairs(self.usedLines) do
            fn(l)
        end
    end
    blocks[id] = b
    return b
end
local a, b, c = block(1), block(2), block(3)
function mod:IsCollapsed()
    return self.collapsed == true
end
function mod:GetExistingBlock(id)
    return blocks[id]
end
function mod:BeginLayout()
    self.firstBlock = nil
    self.lastBlock = nil
    self.contentsHeight = self.headerHeight
    self.hasSkippedBlocks = false
end
function mod:BuildQuestWatchInfos()
    return { 3, 1, 2 }
end
function mod:LayoutContents()
    local ids = self:BuildQuestWatchInfos()
    local previous
    for _, id in ipairs(ids) do
        if watched[id] and self.contentsHeight + 45 <= self.availableHeight then
            local f = blocks[id]
            f:Show()
            f:SetHeight(f.height)
            f.nextBlock = nil
            f:ClearAllPoints()
            f:SetPoint('TOP', self.ContentsFrame, 'TOP', 0, 0)
            f:SetPoint('LEFT', self.ContentsFrame, 'LEFT', 5, 0)
            if not self.firstBlock then
                self.firstBlock = f
            end
            if previous then
                previous.nextBlock = f
            end
            previous = f
            self.lastBlock = f
            self.contentsHeight = self.contentsHeight + 45
        elseif watched[id] then
            self.hasSkippedBlocks = true
        end
    end
end
function mod:EndLayout() end
function mod:OnBlockHeaderEnter() end
function mod:MarkDirty()
    self.dirty = true
end
local shownCards = {}
F.ShowTrackedQuest = function(row, id, resolver)
    shownCards[#shownCards + 1] = { row, id, resolver }
end
local function layout(budget)
    mod:BeginLayout()
    mod.availableHeight = budget or 500
    mod:LayoutContents()
    mod:EndLayout()
end
T.Refresh()
assert(mod.dirty)
-- Header rectangles relay a single click to the original control, without altering it.
for _, owner in ipairs({ root, mod, other }) do
    local header = owner.Header
    assert(header.mouseEnabled and header.scripts.OnMouseUp)
    header.mouseOver = true
    header.scripts.OnMouseUp(header, 'LeftButton')
    assert(owner.collapsed and owner.headerClicks == 1)
    header.scripts.OnMouseUp(header, 'RightButton')
    assert(owner.headerClicks == 1)
    if owner == root then
        assert(
            not header.Background:IsShown() and not header.TopBorder:IsShown() and not header.MinimizeButton:IsShown()
        )
        assert(header.QuestloggerCollapseSign.atlas == 'ui-questtrackerbutton-secondary-expand')
        header.scripts.OnMouseUp(header, 'LeftButton')
        assert(not owner.collapsed and owner.headerClicks == 2)
        assert(header.QuestloggerCollapseSign.atlas == 'ui-questtrackerbutton-secondary-collapse')
        header.MinimizeButton:Show()
        assert(not header.MinimizeButton:IsShown())
    else
        assert(header.Background:IsShown() and header.MinimizeButton:IsShown())
        local p, r, rp, x, y = header.Text:GetPoint(1)
        assert(
            p == 'LEFT'
                and r == header.Background
                and rp == 'LEFT'
                and x == 7
                and y == 0
                and header.Text.justifyV == 'MIDDLE'
        )
        p, r, rp, x, y = header.MinimizeButton:GetPoint(1)
        assert(p == 'RIGHT' and r == header.Background and rp == 'RIGHT' and y == 0)
        header.MinimizeButton.mouseOver = true
        header.scripts.OnMouseUp(header, 'LeftButton')
        assert(owner.headerClicks == 1)
        header.MinimizeButton:Click('LeftButton')
        assert(not owner.collapsed and owner.headerClicks == 2)
        header.MinimizeButton.mouseOver = false
    end
    header.MinimizeButton:SetEnabled(false)
    header.scripts.OnMouseUp(header, 'LeftButton')
    assert(owner.headerClicks == 2)
    header.MinimizeButton:SetEnabled(true)
    combat = true
    header.scripts.OnMouseUp(header, 'LeftButton')
    combat = false
    assert(owner.headerClicks == 2)
    T.Refresh()
    header.scripts.OnMouseUp(header, 'LeftButton')
    assert(owner.collapsed and owner.headerClicks == 3)
    header.scripts.OnMouseUp(header, 'LeftButton')
    assert(not owner.collapsed and owner.headerClicks == 4)
end
root.Header.FilterButton.mouseOver = true
root.Header.scripts.OnMouseUp(root.Header, 'LeftButton')
assert(root.headerClicks == 4)
root.Header.FilterButton.mouseOver = false
local late = frame(root)
nativeHeader(late)
root.modules[#root.modules + 1] = late
T.Refresh()
assert(late.Header.mouseEnabled)
late.Header.mouseOver = true
late.Header.scripts.OnMouseUp(late.Header, 'LeftButton')
assert(late.collapsed and late.headerClicks == 1)

-- Counts are independent of the visible blocks and never decorate expanded categories.
local prof = frame(root)
nativeHeader(prof)
prof.Header.Text:SetText('Professions')
function prof:EndLayout() end
local recipes, recraft = { 101, 102 }, { 103 }
C_TradeSkillUI = {
    GetRecipesTracked = function(isRecraft)
        return isRecraft and recraft or recipes
    end,
}
root.modules[#root.modules + 1] = prof
local achievement = frame(root)
nativeHeader(achievement)
achievement.Header.Text:SetText('Achievements')
Enum = { ContentTrackingType = { Achievement = 1 } }
local achievementIDs = { 55, 70 }
C_ContentTracking = {
    GetTrackedIDs = function(kind)
        assert(kind == 1)
        return achievementIDs
    end,
}
root.modules[#root.modules + 1] = achievement
local generic = frame(root)
nativeHeader(generic)
generic.Header.Text:SetText('Other category')
generic.firstBlock = { nextBlock = { nextBlock = {} } }
function generic:EndLayout() end
root.modules[#root.modules + 1] = generic
T.Refresh()
assert(prof.Header.Text.text == 'Professions' and achievement.Header.Text.text == 'Achievements')
prof.Header:SetCollapsed(true)
achievement.Header:SetCollapsed(true)
generic.Header:SetCollapsed(true)
assert(
    prof.Header.Text.text == 'Professions (3)'
        and achievement.Header.Text.text == 'Achievements (2)'
        and generic.Header.Text.text == 'Other category (3)'
)
assert(prof.Header.QuestloggerSignHolder.sign.atlas == 'ui-questtrackerbutton-secondary-expand')
assert(prof.Header.QuestloggerSignHolder:IsShown())
assert(
    prof.Header.QuestloggerSignHolder.sign:GetWidth() == 16 and prof.Header.QuestloggerSignHolder.sign:GetHeight() == 16
)
recipes = { 101 }
prof.firstBlock = nil
prof:EndLayout()
assert(prof.Header.Text.text == 'Professions (2)')
achievementIDs = { 55, 70, 71 }
T.Refresh()
T.Refresh()
assert(achievement.Header.Text.text == 'Achievements (3)')
generic.entryCount = 4
generic:EndLayout()
assert(generic.Header.Text.text == 'Other category (4)')
prof.Header:SetCollapsed(false)
achievement.Header:SetCollapsed(false)
generic.Header:SetCollapsed(false)
assert(
    prof.Header.Text.text == 'Professions'
        and achievement.Header.Text.text == 'Achievements'
        and generic.Header.Text.text == 'Other category'
)
assert(prof.Header.QuestloggerSignHolder.sign.atlas == 'ui-questtrackerbutton-secondary-collapse')
mod.Header:SetCollapsed(true)
assert(mod.Header.Text.text == 'Quests (3/40)')
mod.Header:SetCollapsed(false)
assert(root.Header.Text.text == nil, 'All Objectives must not acquire a count')
print('Category signs and collapsed-only entry counts passed.')

local bar = UIParent.children[#UIParent.children]
assert(bar.buttons and #bar.buttons == 3 and bar.buttons[3].label.text == '- Track')
local canvas = mod.ContentsFrame:GetParent()
local scroll = canvas:GetParent()
assert(scroll.kind == 'ScrollFrame' and scroll.scrollChild == canvas and scroll.wheel)
local _, _, _, left, insetY = scroll:GetPoint(1)
assert(insetY == -21, 'Viewport reserves a row for the controls')
local _, _, _, right = scroll:GetPoint(2)
local _, anchor, _, inset = mod.ContentsFrame:GetPoint(1)
assert(left == -32 and right == 8 and anchor == canvas and inset == 32)
assert(canvas:GetWidth() == mod:GetWidth() + 40 and mod.ContentsFrame:GetWidth() == mod:GetWidth())
mod:SetWidth(180)
mod.scripts.OnSizeChanged(mod)
assert(
    canvas:GetWidth() == 220 and mod.ContentsFrame:GetWidth() == 180,
    'Viewport padding must not reduce native text width'
)
mod:SetWidth(250)
mod.scripts.OnSizeChanged(mod)
local count = mod.Header.Text
assert(count.text == 'Quests (3/40)')
T.Refresh()
assert(count.text == 'Quests (3/40)' and #mod.Header.children == 4)
C_QuestLog.GetMaxNumQuestsCanAccept = function()
    return 50
end
T.Refresh()
assert(count.text == 'Quests (3/50)')
C_QuestLog.GetMaxNumQuestsCanAccept = function()
    return 40
end
T.Refresh()
assert(count.text == 'Quests (3/40)')
count:SetText('Quests')
layout()
assert(count.text == 'Quests (3/40)', 'Native layout restores the inline count')
local p, r, rp, x, y = bar:GetPoint(1)
assert(p == 'TOPRIGHT' and r == mod.Header and rp == 'BOTTOMRIGHT' and y == -1 and bar:IsShown())
assert(mod.contentsHeight == mod.headerHeight + 21 + scroll.viewHeight)
root.Header:SetCollapsed(true)
T.Refresh()
assert(not bar:IsShown() and root.Header.QuestloggerCollapseSign.atlas == 'ui-questtrackerbutton-secondary-expand')
root.Header:SetCollapsed(false)
T.Refresh()
assert(bar:IsShown())
mod.Header:SetCollapsed(true)
T.Refresh()
assert(not bar:IsShown())
mod.Header:SetCollapsed(false)
layout()
assert(bar:IsShown())
mod.Header:SetWidth(180)
T.Refresh()
assert(bar:GetWidth() == 180)
mod.Header:SetWidth(250)
T.Refresh()
assert(bar:GetWidth() == 250)
local function top(f)
    local _, _, _, _, y = f:GetPoint(1)
    return y
end
assert(top(a) > top(b) and top(b) > top(c), 'Quest-log region order should group both Durotar quests before Barrens')
assert(a:GetHeight() == 45 and a.usedLines[1]:IsShown() and a.ItemButton:IsShown())
local function checkPOI(poi, block, scale)
    local p, r, rp, x, y = poi:GetPoint(1)
    assert(
        poi:GetNumPoints() == 1 and p == 'TOPRIGHT' and r == block.HeaderText and rp == 'TOPLEFT' and x == -4 and y == 0
    )
    assert(math.abs(poi:GetScale() - scale * 0.85) < 0.0001, 'Scale must be relative to the original')
end
checkPOI(a.poiButton, a, 1)
checkPOI(b.poiButton, b, 1.2)
layout()
checkPOI(a.poiButton, a, 1)
checkPOI(b.poiButton, b, 1.2)
local pooled = b.poiButton
b:CheckAndReleasePOIButton()
assert(pooled:GetScale() == 1.2, 'Shared POI must be restored on release')
b.poiButton = pooled
layout()
checkPOI(pooled, b, 1.2)
assert(canvas:GetHeight() == mod.ContentsFrame:GetHeight())
mod:OnBlockHeaderEnter(b)
assert(shownCards[1][2] == 2 and shownCards[1][3](b) == 2)
b.HeaderButton.scripts.OnEnter(b.HeaderButton)
assert(shownCards[#shownCards][2] == 2)
local zone
for _, f in ipairs(mod.ContentsFrame.children) do
    if f.label and f.label.text == 'Durotar -' then
        zone = f
    end
end
assert(zone and zone.label.text == 'Durotar -' and not zone.sign, 'Region sign must be adjacent to its name')
local barrens
for _, f in ipairs(mod.ContentsFrame.children) do
    if f.label and f.label.text == 'Barrens -' then
        barrens = f
    end
end
assert(barrens)
local gap = -mod.fromBlockOffsetY
assert(top(zone) - zone:GetHeight() - top(a) == gap - 2, 'Expanded region-to-first-quest gap is reduced')
assert(top(a) - a:GetHeight() - top(b) == gap, 'Spacing between quests is unchanged')
assert(top(b) - b:GetHeight() - top(barrens) == gap, 'Spacing before the next region is unchanged')
zone.scripts.OnClick()
layout()
assert(zone.label.text == 'Durotar +' and not a:IsShown())
assert(top(zone) - zone:GetHeight() - top(barrens) == gap, 'Collapsed region spacing is unchanged')
zone.scripts.OnClick()
layout()
assert(top(zone) - zone:GetHeight() - top(a) == gap - 2, 'Expanded gap does not accumulate on refresh')
local click = a.usedLines[1].QuestloggerObjectiveClick
assert(click and click:IsShown())
click.scripts.OnClick()
assert(opened[1] == 1)
local first, second = a.usedLines[1], a.usedLines[2]
local click2 = second.QuestloggerObjectiveClick
a.isHighlighted = true
a:UpdateHighlight()
assert(
    first.Text.colorStyle == normal and second.Text.colorStyle == complete and first.Dash.color[1] == normal.r,
    'Title hover must not light objectives'
)
a:SetStringText(first.Text, 'Updated objective', false, normal, true)
assert(first.Text.colorStyle == normal, 'Native refresh during title hover must preserve the base objective color')
a.isHighlighted = false
a:UpdateHighlight()
click.scripts.OnEnter()
assert(first.Text.colorStyle == bright and second.Text.colorStyle == complete and first.Dash.color[1] == bright.r)
click2.scripts.OnEnter()
assert(first.Text.colorStyle == normal and second.Text.colorStyle == completeBright)
click.scripts.OnLeave()
assert(second.Text.colorStyle == completeBright, 'Late leave from another line cannot clear the current hover')
a:SetStringText(second.Text, 'Progress changed', false, normal, false)
assert(second.Text.colorStyle == bright, 'Status updates retain hover but use the new native base style')
click2.scripts.OnLeave()
assert(second.Text.colorStyle == normal)
a:SetStringText(second.Text, 'Complete', false, complete, false)
click2.scripts.OnEnter()
second:Hide()
assert(second.Text.colorStyle == complete and not click2:IsShown())
second:Show()
layout()
assert(second.Text.colorStyle == complete and click2:IsShown())
-- A recycled block outside the native quests module must retain its own behavior.
local previousModule = a.parentModule
a.parentModule = {}
a:UpdateHighlight()
assert(first.Text.colorStyle == bright and second.Text.colorStyle == completeBright)
a.parentModule = previousModule
a:UpdateHighlight()
assert(first.Text.colorStyle == normal and second.Text.colorStyle == complete)

a.HeaderButton.scripts.OnClick(a.HeaderButton, 'RightButton')
assert(nativeClicks == 1)
modified = true
a.HeaderButton.scripts.OnClick(a.HeaderButton, 'LeftButton')
modified = false
assert(nativeClicks == 2)
a.HeaderButton.scripts.OnClick(a.HeaderButton, 'LeftButton')
layout()
assert(a:GetHeight() == 14 and not a.usedLines[1]:IsShown() and nativeClicks == 2)
a.HeaderButton.scripts.OnEnter(a.HeaderButton)
assert(shownCards[#shownCards][2] == 1)
a.HeaderButton.scripts.OnClick(a.HeaderButton, 'LeftButton')
layout()
assert(a:GetHeight() == 45 and a.usedLines[1]:IsShown() and click:IsShown())
layout(90)
assert(mod.contentsHeight <= 90 and scroll.contentHeight > scroll.viewHeight and c:IsShown())
scroll.scripts.OnMouseWheel(scroll, -1)
assert(scroll.verticalScroll == 45)
for i = 1, 10 do
    scroll.scripts.OnMouseWheel(scroll, -1)
end
assert(scroll.verticalScroll == scroll.contentHeight - scroll.viewHeight)
layout(500)
assert(scroll.verticalScroll == 0 and scroll.contentHeight == scroll.viewHeight)

bar.buttons[2].scripts.OnClick()
layout(160)
assert(
    mod.availableHeight == 160 and a:IsShown() and b:IsShown() and c:IsShown(),
    'Compact titles should fit within the original height budget'
)
assert(a:GetHeight() == 14 and not a.usedLines[1]:IsShown() and not a.ItemButton:IsShown())
bar.buttons[2].scripts.OnClick()
layout()
assert(a:GetHeight() == 45 and a.usedLines[1]:IsShown() and a.ItemButton:IsShown())
assert(
    bar.buttons[1].tip == 'Collapse all zones'
        and bar.buttons[2].tip == 'Collapse all quests'
        and bar.buttons[3].tip == 'Untrack all quests'
)
GameTooltip = {
    IsOwned = function(self, b)
        return b == bar.buttons[1]
    end,
    SetText = function(self, t)
        self.text = t
    end,
    Show = function() end,
}
bar.buttons[1].scripts.OnClick()
assert(GameTooltip.text == 'Expand all zones')
GameTooltip = nil
layout(160)
assert(not a:IsShown() and not b:IsShown() and not c:IsShown() and not a.ItemButton:IsShown())
bar.buttons[1].scripts.OnClick()
layout()
assert(a:IsShown() and b:IsShown() and c:IsShown() and a.ItemButton:IsShown())
bar.buttons[3].scripts.OnClick()
assert(not next(watched) and count.text == 'Quests (3/40)')
root:Hide()
T.Refresh()
assert(bar:IsShown() and bar.buttons[3].label.text == '+ Track')
bar.buttons[3].scripts.OnClick()
assert(watched[1] and watched[2] and watched[3])
root:Show()
combat = true
T.Disable()
assert(not bar.buttons[3].enabled)
bar.buttons[3].scripts.OnClick()
assert(watched[1])
combat = false
T.Refresh()
-- Questie uses its own region keys and policy, including auto-tracked quests.
Questie_BaseFrame = frame(UIParent)
Questie = {
    API = { isReady = false },
    db = {
        profile = { trackerEnabled = true, autoTrackQuests = true },
        char = { AutoUntrackedQuests = {}, TrackedQuests = {}, collapsedZones = {}, collapsedQuests = {} },
    },
}
local tracker = { started = false, Update = function() end, Disable = function() end }
function tracker.Initialize()
    coroutine.yield('loading lines')
    tracker.started = true
    coroutine.yield('finishing initialization')
    Questie.API.isReady = true
end
local originalInitialize, originalUpdate, originalDisable = tracker.Initialize, tracker.Update, tracker.Disable
local utils = {
    GetSortedQuestIds = function()
        return { 1, 2, 3 }, {
            [1] = { zoneName = 'Questie Durotar' },
            [2] = { zoneName = 'Questie Durotar' },
            [3] = { zoneName = 'Questie Barrens' },
        }
    end,
}
local qlist = frame(Questie_BaseFrame)
qlist:SetHeight(180)
qlist.ScrollFrame = frame(qlist)
qlist.ScrollFrame:SetPoint('TOPLEFT', qlist, 'TOPLEFT', 0, 0)
qlist.ScrollFrame:SetPoint('BOTTOMRIGHT', qlist, 'BOTTOMRIGHT', 0, 0)
local line = frame(qlist.ScrollFrame)
line.Quest = { Id = 3 }
line.label = frame(line)
line.expandQuest = frame(line)
local pool = {
    GetQuestTitleLine = function()
        return line
    end,
    GetCurrentLine = function()
        return line
    end,
}
local imports = { QuestieTracker = tracker, TrackerUtils = utils, TrackerLinePool = pool, TrackerQuestFrame = {
    questFrame = qlist,
} }
QuestieLoader = {
    ImportModule = function(_, name)
        return imports[name]
    end,
}
local originalPool = pool.GetQuestTitleLine
T.Refresh()
assert(#tickers == 1 and UIParent.children[#UIParent.children] == Questie_BaseFrame and not line.scripts.OnEnter)
assert(
    tracker.Initialize == originalInitialize and tracker.Update == originalUpdate and tracker.Disable == originalDisable
)
local startup = coroutine.create(tracker.Initialize)
local ok, phase = coroutine.resume(startup)
assert(ok and phase == 'loading lines')
tickers[1]()
assert(not line.scripts.OnEnter)
ok, phase = coroutine.resume(startup)
assert(ok and phase == 'finishing initialization')
tickers[1]()
assert(not line.scripts.OnEnter, 'Wait for the public ready flag even after started becomes true')
assert(coroutine.resume(startup))
assert(coroutine.status(startup) == 'dead')
tickers[1]()
local qbar = UIParent.children[#UIParent.children]
assert(qbar.buttons and qbar ~= bar and qbar.buttons[3].label.text == '- Track')
assert(
    tracker.Initialize == originalInitialize
        and tracker.Update == originalUpdate
        and tracker.Disable == originalDisable
        and pool.GetQuestTitleLine == originalPool,
    'No Questie module functions may be wrapped'
)
local qp, qr, qrp, qx, qy = qbar:GetPoint(1)
assert(qp == 'TOPRIGHT' and qr == qlist and qrp == 'TOPRIGHT' and qy == -1)
local _, _, _, _, insetQ = qlist.ScrollFrame:GetPoint(1)
assert(insetQ == -21)
Questie.db.char.isTrackerExpanded = false
tickers[1]()
assert(not qbar:IsShown())
local _, _, _, _, restoredQ = qlist.ScrollFrame:GetPoint(1)
assert(restoredQ == 0)
Questie.db.char.isTrackerExpanded = true
tickers[1]()
assert(qbar:IsShown())
qlist:SetWidth(180)
tickers[1]()
assert(qbar:GetWidth() == 180)
qlist:SetWidth(250)
tickers[1]()
assert(qbar:GetWidth() == 250)
Questie.db.profile.hideTrackerInInstances = true
IsInInstance = function()
    return true
end
tickers[1]()
assert(not qbar:IsShown())
local _, _, _, _, clearedInset = qlist.ScrollFrame:GetPoint(1)
assert(clearedInset == 0)
Questie.db.profile.hideTrackerInInstances = false
tickers[1]()
assert(qbar:IsShown())
local late = frame(Questie_BaseFrame)
late.Quest = { Id = 2 }
late.label = frame(late)
late.expandQuest = frame(late)
tickers[1]()
assert(late.scripts.OnEnter, 'New pooled rows should be detected by the observer')
local handler = late.scripts.OnEnter
tickers[1]()
assert(late.scripts.OnEnter == handler, 'No duplicate hover hooks')
T.Refresh()
assert(#tickers == 1, 'Only one observer timer')
line.scripts.OnEnter(line)
assert(shownCards[#shownCards][2] == 3)
line.Quest = { Id = 1 }
line.scripts.OnEnter(line)
assert(shownCards[#shownCards][2] == 1)
qbar.buttons[1].scripts.OnClick()
assert(Questie.db.char.collapsedZones['Questie Durotar'] and Questie.db.char.collapsedZones['Questie Barrens'])
qbar.buttons[1].scripts.OnClick()
assert(not next(Questie.db.char.collapsedZones))
qbar.buttons[2].scripts.OnClick()
assert(Questie.db.char.collapsedQuests[3])
qbar.buttons[2].scripts.OnClick()
assert(not next(Questie.db.char.collapsedQuests))
qbar.buttons[3].scripts.OnClick()
assert(Questie.db.char.AutoUntrackedQuests[1] and not next(watched) and qbar.buttons[3].label.text == '+ Track')
qbar.buttons[3].scripts.OnClick()
assert(not next(Questie.db.char.AutoUntrackedQuests) and watched[3])
Questie.db.profile.trackerEnabled = false
T.Refresh()
assert(not qbar:IsShown())
local _, _, _, _, qyEnd = qlist.ScrollFrame:GetPoint(1)
assert(qyEnd == 0)
local n = #shownCards
line.scripts.OnEnter(line)
assert(#shownCards == n)
print(
    'Coroutine startup and readiness tests passed. Tracker tests passed: fixed in-list toolbars, centered category controls, plain All Objectives header, Questie scroll inset and restoration, native region order and inline signs, padded scroll viewport and POI alignment/pool reuse, scrolling and height budget, title/objective clicks, isolated objective hover colors, quest capacity, collapse/expand, control state, combat, pooled hover IDs, and Questie tracking and collapse state.'
)

-- A ready, newer Questie can hand over its tracker without calling destructive Disable().
local oldProfile = Questie.db.profile
Questie.db.profile = { trackerEnabled = true, autoTrackQuests = true }
Questie_BaseFrame:Show()
local toggles, unhooks, showNative = 0, 0, 0
tracker.Toggle = function(self)
    toggles = toggles + 1
    Questie.db.profile.trackerEnabled = false
end
tracker.Unhook = function(self)
    unhooks = unhooks + 1
end
tracker.Hide = function(self)
    Questie_BaseFrame:Hide()
end
imports.QuestieCompat = {
    ShowWatchFrame = function()
        showNative = showNative + 1
        root:Show()
    end,
}
local trackedBefore = Questie.db.char.TrackedQuests
T.Refresh()
assert(
    toggles == 1
        and unhooks == 1
        and showNative == 1
        and not Questie.db.profile.trackerEnabled
        and not Questie_BaseFrame:IsShown()
)
assert(Questie.db.char.TrackedQuests == trackedBefore and not qbar:IsShown())
T.Refresh()
assert(toggles == 1)
-- A broken toggle is rejected and the previous integration remains available.
Questie.db.profile = { trackerEnabled = true, autoTrackQuests = true }
Questie_BaseFrame:Show()
tracker.Toggle = function()
    error('Changed API')
end
T.Refresh()
assert(Questie.db.profile.trackerEnabled and qbar:IsShown())
Questie.db.profile.trackerEnabled = false
T.Refresh()

-- Standard non-quest modules reserve a toolbar row and fold native entries.
local profBlocks = {}
prof.ContentsFrame = frame(prof)
prof.fromHeaderOffsetY = -2
prof.headerHeight = 20
prof.GetNextBlockAnchoring = function() end
prof.MarkDirty = function(self)
    self.dirty = true
end
function prof:BeginLayout()
    self.firstBlock = nil
    self.contentsHeight = 20
end
function prof:LayoutContents()
    self.firstBlock = nil
    local prev
    for _, id in ipairs(recipes) do
        local b = profBlocks[id]
        if not b then
            b = frame(self.ContentsFrame)
            b.id = id
            b.parentModule = self
            b.HeaderText = frame(b)
            b.HeaderText:SetHeight(14)
            b.line = frame(b)
            b.ForEachUsedLine = function(self, fn)
                fn(self.line)
            end
            profBlocks[id] = b
        end
        b:Show()
        b.line:Show()
        b:SetHeight(40)
        b.nextBlock = nil
        if prev then
            prev.nextBlock = b
        else
            self.firstBlock = b
            self.contentsHeight = self.contentsHeight - self.fromHeaderOffsetY
        end
        self.contentsHeight = self.contentsHeight + 40
        prev = b
    end
end
function prof:EndLayout() end
-- Bind a separate real-like module rather than replacing an already hooked end-layout method.
local prof2 = prof
recipes = { 101, 102 }
recraft = {}
C_TradeSkillUI.SetRecipeTracked = function(id, enabled, isRecraft)
    local list = isRecraft and recraft or recipes
    if enabled then
        for _, v in ipairs(list) do
            if v == id then
                return
            end
        end
        list[#list + 1] = id
    else
        for i, v in ipairs(list) do
            if v == id then
                table.remove(list, i)
                return
            end
        end
    end
end
T.Refresh()
local pb = assert(prof2.QuestloggerCategoryToolbar)
local function profLayout()
    prof2:BeginLayout()
    prof2:LayoutContents()
    prof2:EndLayout()
end
profLayout()
assert(
    pb:IsShown()
        and #pb.buttons == 3
        and pb.buttons[1].label.text == '- Professions'
        and pb.buttons[2].label.text == '- Entries'
        and pb.buttons[3].label.text == '- Track'
)
assert(prof2.fromHeaderOffsetY == -23 and prof2.contentsHeight == 123)
assert(select(2, pb:GetPoint(1)) == prof2.Header)
pb.buttons[2].scripts.OnClick()
profLayout()
assert(
    profBlocks[101]:IsShown()
        and not profBlocks[101].line:IsShown()
        and profBlocks[101]:GetHeight() == 14
        and prof2.contentsHeight == 71
)
pb.buttons[2].scripts.OnClick()
profLayout()
assert(profBlocks[101].line:IsShown() and profBlocks[101]:GetHeight() == 40 and prof2.contentsHeight == 123)
pb.buttons[1].scripts.OnClick()
profLayout()
assert(
    not profBlocks[101]:IsShown()
        and not profBlocks[102]:IsShown()
        and pb:IsShown()
        and pb.buttons[1].label.text == '+ Professions'
        and prof2.contentsHeight == 41
)
pb.buttons[1].scripts.OnClick()
profLayout()
assert(profBlocks[101]:IsShown() and profBlocks[102]:IsShown())
assert(
    pb.buttons[1].tip == 'Collapse all professions'
        and pb.buttons[2].tip == 'Collapse all entries'
        and pb.buttons[3].tip == 'Untrack all professions'
)
pb.buttons[1].scripts.OnClick()
profLayout()
assert(pb.buttons[1].tip == 'Expand all professions')
pb.buttons[1].scripts.OnClick()
profLayout()
pb.buttons[2].scripts.OnClick()
profLayout()
assert(pb.buttons[2].tip == 'Expand all entries')
pb.buttons[2].scripts.OnClick()
profLayout()
pb.buttons[3].scripts.OnClick()
profLayout()
assert(#recipes == 0 and not pb:IsShown() and pb.buttons[3].label.text == '- Track' and not pb.buttons[3]:IsEnabled())
pb.buttons[3]:Click('LeftButton')
profLayout()
assert(#recipes == 0)
recipes = { 101, 102 }
profLayout()
assert(pb:IsShown() and pb.buttons[3].label.text == '- Track')
prof2.Header:SetCollapsed(true)
T.Refresh()
assert(not pb:IsShown())
prof2.Header:SetCollapsed(false)
profLayout()
assert(pb:IsShown())
print(
    'Native-preference success/fallback, independent category signs, and profession fold/untrack/no restore tests passed.'
)

-- Native geometry uses one root anchor and native height, without modifying Questie.
UIParent:SetSize(1200, 900)
function UIParent:GetEffectiveScale()
    return 1
end
function root:GetEffectiveScale()
    return 1
end
function root:GetLeft()
    return 800
end
function root:GetTop()
    return 820
end

root:SetHeight(500)
root:ClearAllPoints()
root:SetPoint('TOPRIGHT', UIParent, 'TOPRIGHT', -150, -80)
local mx, my, shift, pressed = 800, 820, false, true
GetCursorPosition = function()
    return mx, my
end
IsShiftKeyDown = function()
    return shift
end
IsMouseButtonDown = function()
    return pressed
end
root:Show()
root.collapsed = false
root.Header.mouseOver = true
T.Refresh()
local grips, surface = {}
for _, child in ipairs(root.children) do
    if child.line then
        grips[#grips + 1] = child
    elseif
        child.scripts.OnMouseDown
        and child.scripts.OnMouseUp
        and select(1, child:GetPoint(1)) == 'TOPLEFT'
        and select(2, child:GetPoint(1)) == root
    then
        surface = child
    end
end
assert(#grips == 2 and surface and not surface.mouseEnabled)
assert(select(2, surface:GetPoint(2)) == root and select(1, surface:GetPoint(2)) == 'BOTTOMRIGHT')
assert(grips[1]:GetHeight() == 10 and grips[1].line:GetHeight() == 2)
assert(not grips[1].line:IsShown())
root.scripts.OnUpdate(root, 0.02)
assert(not grips[1].line:IsShown())
grips[1].mouseOver = true
root.scripts.OnUpdate(root, 0.02)
assert(grips[1].line:IsShown() and not grips[2].line:IsShown())
grips[1].mouseOver = false
grips[2].mouseOver = true
root.scripts.OnUpdate(root, 0.02)
assert(not grips[1].line:IsShown() and grips[2].line:IsShown())
grips[2].mouseOver = false
root.Header.mouseOver = false
root.scripts.OnUpdate(root, 0.02)
assert(not grips[1].line:IsShown() and not grips[2].line:IsShown())
local layoutHeights = {}
-- Model the native managed tracker: layout resets its anchor until detached.
local manager = frame(UIParent)
root:SetParent(manager)
root.systemInfo = { isInDefaultPosition = true }
root.editModeHeight = 500
function root:IsInDefaultPosition()
    return self.systemInfo.isInDefaultPosition
end
function root:GetManagedFrameContainer()
    return manager
end
function root:BreakFromFrameManager()
    self:SetParent(UIParent)
    self.detached = true
end
function root:ApplySystemAnchor()
    assert(self:IsInDefaultPosition())
    self:SetParent(manager)
    self.detached = false
    self:ClearAllPoints()
    self:SetPoint('TOPRIGHT', UIParent, 'TOPRIGHT', -150, -80)
end
-- Simulate height consumed by other categories so quests extend beyond the viewport.
function root:Update(dirty)
    assert(dirty == false)
    if self:IsInDefaultPosition() then
        self:ApplySystemAnchor()
        self:SetHeight(500)
    end
    layoutHeights[#layoutHeights + 1] = self:GetHeight()
    layout(math.max(1, self:GetHeight() - 410))
end
layout(90)
root.scripts.OnUpdate(root, 0.02)
assert(grips[2].line:IsShown() and not grips[2].mouseEnabled, 'Overflow line must not intercept ordinary clicks')
root.Header.mouseOver = true
local clicksBefore = root.headerClicks or 0
surface.scripts.OnMouseDown(surface, 'LeftButton')
mx, my = 700, 770
root.scripts.OnUpdate(root, 0.02)
assert(select(1, root:GetPoint(1)) == 'TOPRIGHT' and not root.detached, 'Unmodified drag must not move tracker')
surface.scripts.OnMouseUp(surface, 'LeftButton')
shift = true
mx, my = 800, 650
root.scripts.OnUpdate(root, 0.02)
assert(surface.mouseEnabled)
surface.scripts.OnMouseDown(surface, 'LeftButton')
mx, my = 700, 600
root.scripts.OnUpdate(root, 0.02)
assert(root.detached and not root:IsInDefaultPosition() and root.systemInfo.isInDefaultPosition)
local pt, rel, rpt, dx, dy = root:GetPoint(1)
assert(
    pt == 'TOPLEFT' and rel == UIParent and rpt == 'TOPLEFT' and dx == 700 and dy == -130 and root:GetHeight() == 500
)
surface.scripts.OnMouseUp(surface, 'LeftButton')
assert((root.headerClicks or 0) == clicksBefore, 'Drag must not collapse the header')
shift = false
root.scripts.OnUpdate(root, 0.02)
assert(not surface.mouseEnabled)
root.Header.scripts.OnMouseUp(root.Header, 'LeftButton')
assert(root.headerClicks == clicksBefore + 1, 'Normal header click still toggles')
root.collapsed = false
-- Bottom drag preserves the top; top drag preserves the bottom; no modifier does nothing.
local topGrip, bottomGrip = grips[1], grips[2]
mx, my = 700, 270
bottomGrip.scripts.OnMouseDown(bottomGrip, 'LeftButton')
my = 200
root.scripts.OnUpdate(root, 0.02)
assert(root:GetHeight() == 500)
shift = true
my = 270
bottomGrip.scripts.OnMouseDown(bottomGrip, 'LeftButton')
my = 170
root.scripts.OnUpdate(root, 0.02)
assert(
    root:GetHeight() == 600
        and select(5, root:GetPoint(1)) == -130
        and layoutHeights[#layoutHeights] == 600
        and bottomGrip.line:IsShown()
)
assert(scroll.viewHeight > 49 and mod.availableHeight == 190, 'Viewport must fill expanded space during drag')
bottomGrip.scripts.OnMouseUp(bottomGrip, 'LeftButton')
my = 770
topGrip.scripts.OnMouseDown(topGrip, 'LeftButton')
my = 800
root.scripts.OnUpdate(root, 0.02)
assert(
    root:GetHeight() == 630
        and select(5, root:GetPoint(1)) == -100
        and layoutHeights[#layoutHeights] == 630
        and topGrip.line:IsShown()
)
topGrip.scripts.OnMouseUp(topGrip, 'LeftButton')
-- A native layout refresh must not overwrite the selected height.
root:SetHeight(400)
root.scripts.OnUpdate(root, 0.02)
assert(root:GetHeight() == 630)
assert(root.editModeHeight == 630 and root.detached and not root:IsInDefaultPosition())
-- Move again immediately after resizing, preserving the resized height.
mx, my = 740, 500
surface.scripts.OnMouseDown(surface, 'LeftButton')
mx, my = 710, 480
root.scripts.OnUpdate(root, 0.02)
assert(root:GetHeight() == 630 and select(4, root:GetPoint(1)) == 670 and select(5, root:GetPoint(1)) == -120)
shift = false
root.scripts.OnUpdate(root, 0.02)
assert(surface.mouseEnabled)
surface.scripts.OnMouseUp(surface, 'LeftButton')
assert(not surface.mouseEnabled)
assert((root.headerClicks or 0) == clicksBefore + 1)
root.scripts.OnUpdate(root, 0.02)
assert(not topGrip.mouseEnabled and not bottomGrip.mouseEnabled and not surface.mouseEnabled)
-- Overflow disappears when the content fits; collapsed categories do not report overflow.
local contentHeight, viewHeight = scroll.contentHeight, scroll.viewHeight
scroll.contentHeight = scroll.viewHeight
root.scripts.OnUpdate(root, 0.02)
assert(not bottomGrip.line:IsShown())
scroll.contentHeight = contentHeight
scroll.viewHeight = viewHeight
shift = true
-- Combat prevents geometry changes.
combat = true
bottomGrip.scripts.OnMouseDown(bottomGrip, 'LeftButton')
my = 100
root.scripts.OnUpdate(root, 0.02)
assert(root:GetHeight() == 630)
combat = false
Questie.db.profile = { trackerEnabled = true, autoTrackQuests = true }
tracker.Toggle = function()
    error('Unsupported')
end
Questie_BaseFrame:Show()
T.Refresh()
assert(
    not surface:IsShown()
        and not surface.mouseEnabled
        and not grips[1]:IsShown()
        and not grips[2]:IsShown()
        and root:GetHeight() == 500
        and select(1, root:GetPoint(1)) == 'TOPRIGHT'
)
assert(root:IsInDefaultPosition() and not root.detached and root:GetParent() == manager and root.editModeHeight == 500)
assert(pb.bottomBorder.tint[4] == 0.25 and qbar.bottomBorder.tint[4] == 0.25 and bar.bottomBorder.tint[4] == 0.25)
print('Native drag/resize, hover edges, height restoration, combat and Questie fallback, toolbar border tests passed.')
