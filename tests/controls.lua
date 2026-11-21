-- Mock quest-log state for bulk-action tests.
local F = dofile('tests/load.lua')
local B = F.Controls
local entries = {
    { isHeader = true, isCollapsed = false },
    { questID = 11 },
    { questID = 12 },
    { isHeader = true, isCollapsed = true },
    { questID = 13 },
    { questID = 14, isHidden = true },
    { questID = 15, isTask = true },
    { questID = 16, isBounty = true },
}
local watches = { [12] = true, [14] = true }
local combat = false
local updates = 0
InCombatLockdown = function()
    return combat
end
QuestMapFrame = { ignoreQuestLogUpdate = 'old' }
QuestMapFrame_UpdateAll = function()
    updates = updates + 1
end
C_QuestLog = {
    GetNumQuestLogEntries = function()
        return #entries
    end,
    GetInfo = function(i)
        return entries[i]
    end,
    GetQuestWatchType = function(id)
        return watches[id] and 0 or nil
    end,
    GetNumQuestWatches = function()
        local n = 0
        for _ in pairs(watches) do
            n = n + 1
        end
        return n
    end,
    AddQuestWatch = function(id)
        assert(QuestMapFrame.ignoreQuestWatchListChanged)
        watches[id] = true
    end,
    RemoveQuestWatch = function(id)
        assert(QuestMapFrame.ignoreQuestWatchListChanged)
        watches[id] = nil
    end,
}
CollapseQuestHeader = function(i)
    assert(QuestMapFrame.ignoreQuestLogUpdate == true)
    entries[i].isCollapsed = true
end
ExpandQuestHeader = function(i)
    assert(QuestMapFrame.ignoreQuestLogUpdate == true)
    entries[i].isCollapsed = false
end
local search = ''
local scroll = {
    SearchBox = {
        GetText = function()
            return search
        end,
    },
    SetVerticalScroll = function(_, v)
        assert(v == 0)
    end,
}
local s = B.State()
assert(#s.headers == 2 and s.expanded == 1 and #s.quests == 3 and s.tracked == 1)
B.ToggleRegions(scroll)
assert(
    entries[1].isCollapsed and entries[4].isCollapsed and QuestMapFrame.ignoreQuestLogUpdate == 'old' and updates == 1
)
B.ToggleRegions(scroll)
assert(not entries[1].isCollapsed and not entries[4].isCollapsed and updates == 2)
search = 'quest'
B.ToggleRegions(scroll)
assert(updates == 2)
entries[4].isCollapsed = true
B.ToggleTracking()
assert(not watches[12] and watches[14] and updates == 3)
B.ToggleTracking()
assert(watches[11] and watches[12] and watches[13] and watches[14] and not watches[15] and updates == 4)
assert(QuestMapFrame.ignoreQuestWatchListChanged == nil)
combat = true
B.ToggleTracking()
B.ToggleRegions(scroll)
assert(updates == 4)
combat = false
B.ToggleTracking()
Constants = { QuestWatchConsts = { MAX_QUEST_WATCHES = 2 } }
B.ToggleTracking()
assert(B.State().tracked == 1)
-- Verify toolbar anchors and refresh behavior.
local function frame(parent)
    local f = { parent = parent, points = {}, scripts = {}, shown = true, w = 300, h = 20 }
    function f:GetParent()
        return self.parent
    end
    function f:SetPoint(...)
        self.points[#self.points + 1] = { ... }
    end
    function f:GetPoint(i)
        return table.unpack(self.points[i], 1, 5)
    end
    function f:GetNumPoints()
        return #self.points
    end
    function f:ClearAllPoints()
        self.points = {}
    end
    function f:SetHeight(h)
        self.h = h
    end
    function f:GetFontString()
        if not self.label then
            self.label = frame(self)
        end
        return self.label
    end
    function f:SetJustifyH(v)
        self.justifyH = v
    end
    function f:SetJustifyV(v)
        self.justifyV = v
    end
    function f:SetWidth(w)
        self.w = w
    end
    function f:GetWidth()
        return self.w
    end
    function f:GetTop()
        return self.top
    end
    function f:GetBottom()
        return self.bottom
    end
    function f:GetEffectiveScale()
        return self.scale or 1
    end
    function f:SetText(s)
        self.text = s
    end
    function f:GetText()
        return self.text
    end
    function f:SetEnabled(v)
        self.enabled = v
    end
    function f:SetScript(k, v)
        self.scripts[k] = v
    end
    function f:HookScript(k, v)
        self.scripts[k] = v
    end
    function f:SetShown(v)
        self.shown = v
    end
    function f:Show()
        self.shown = true
    end
    function f:Hide()
        self.shown = false
    end
    function f:IsShown()
        return self.shown
    end
    return f
end
unpack = unpack or table.unpack
CreateFrame = function(_, _, parent)
    return frame(parent)
end
local parent = frame()
scroll = frame(parent)
QuestScrollFrame = scroll
scroll:SetPoint('TOPLEFT', parent, 'TOPLEFT', 0, -29)
scroll:SetPoint('BOTTOMRIGHT', parent, 'BOTTOMRIGHT', 0, 0)
scroll.SearchBox = frame(scroll)
scroll.SearchBox:SetPoint('BOTTOMLEFT', scroll, 'TOPLEFT', 6, 7)
scroll.SearchBox:SetText('')
scroll.SettingsDropdown = frame(scroll)
scroll.SettingsDropdown:SetPoint('TOPRIGHT', scroll, 'TOPRIGHT', 19, 25)
B.Update(scroll)
local bar = scroll.QuestloggerControls
assert(bar and bar.regions.enabled and bar.tracking.enabled)
assert(select(5, scroll:GetPoint(1)) == -53 and select(5, scroll:GetPoint(2)) == 0)
assert(select(5, scroll.SearchBox:GetPoint(1)) == 31 and select(5, scroll.SettingsDropdown:GetPoint(1)) == 49)
assert(bar.regions:GetText() == 'Collapse all' and bar.tracking:GetText() == '- Track')
assert(bar.h == 24 and select(5, bar:GetPoint(1)) == 6) -- Geometry not ready yet.
-- The toolbar center is halfway between the search bottom and visible list border.
scroll.top = 100
scroll.SearchBox.bottom = 131
B.Update(scroll)
assert(select(5, bar:GetPoint(1)) == 5.5 and select(5, bar:GetPoint(2)) == 5.5)
assert(100 + 5.5 + bar.h / 2 == (131 + 100 + 4) / 2)
scroll.SearchBox.bottom = 135
B.Update(scroll)
assert(select(5, bar:GetPoint(1)) == 7.5 and select(5, bar:GetPoint(2)) == 7.5)
assert(bar:GetNumPoints() == 2)
for _, button in ipairs({ bar.regions, bar.tracking }) do
    assert(button.h == 20 and select(5, button:GetPoint(1)) == 0)
    local p, r, rp, x, y = button.label:GetPoint(1)
    assert(p == 'CENTER' and r == button and rp == 'CENTER' and x == 0 and y == 0)
    assert(button.label.justifyH == 'CENTER' and button.label.justifyV == 'MIDDLE')
end
B.Update(scroll)
assert(scroll.QuestloggerControls == bar and select(5, scroll:GetPoint(1)) == -53)
bar.regions.scripts.OnClick()
assert(bar.regions:GetText() == 'Expand all')
bar.tracking.scripts.OnClick()
assert(bar.tracking:GetText() == '+ Track')
scroll.SearchBox:SetText('filter')
B.Update(scroll)
assert(not bar.regions.enabled and bar.tracking.enabled)
scroll.scripts.OnHide()
assert(not bar.shown)
scroll.scripts.OnShow()
assert(bar.shown)
B.Disable(scroll)
assert(not bar.regions.enabled and not bar.tracking.enabled)
print(
    'Bulk controls mock tests passed: mixed states, full log, limits, search, combat, anchors, visibility and labels.'
)
