-- Append pending quest rewards to the native XP fill without changing earned or rested XP.
local _, addon = ...
local Compat, UI, L = addon.Compat, addon.UI, addon.L
local ExperienceBar = {}
UI.ExperienceBar = ExperienceBar

local states = setmetatable({}, { __mode = 'k' })
local hookedObjects = setmetatable({}, { __mode = 'k' })
local restedTooltipLines = setmetatable({}, { __mode = 'k' })
local totalXP, questCount, details = 0, 0, {}
local enabled, discovering = true, false
local drawState, discoverBars

local function isObject(value)
    return Compat.IsReadable(value) and (type(value) == 'table' or type(value) == 'userdata')
end

local function canAccess(frame)
    if not isObject(frame) then
        return false
    end
    if type(frame.IsForbidden) == 'function' then
        local ok, forbidden = pcall(frame.IsForbidden, frame)
        if not ok or not Compat.IsReadable(forbidden) or forbidden then
            return false
        end
    end
    return true
end

local function canModify(frame)
    if not canAccess(frame) then
        return false
    end
    if Compat.InCombat() and type(frame.IsProtected) == 'function' then
        local ok, protected = pcall(frame.IsProtected, frame)
        if not ok or not Compat.IsReadable(protected) or protected then
            return false
        end
    end
    return true
end

local function number(value)
    if
        Compat.IsReadable(value)
        and type(value) == 'number'
        and value == value
        and value > -math.huge
        and value < math.huge
    then
        return value
    end
end

local function visible(frame)
    if not canAccess(frame) then
        return false
    end
    local callback = frame.IsVisible or frame.IsShown
    return Compat.Call(callback, frame) == true
end

local function hookMethod(object, method, callback)
    if not canAccess(object) or type(object[method]) ~= 'function' or type(hooksecurefunc) ~= 'function' then
        return
    end
    local hooks = hookedObjects[object]
    if not hooks then
        hooks = {}
        hookedObjects[object] = hooks
    end
    if not hooks[method] then
        hooks[method] = pcall(hooksecurefunc, object, method, callback)
    end
end

local function hookScript(frame, script, callback)
    if canAccess(frame) and type(frame.HookScript) == 'function' then
        pcall(frame.HookScript, frame, script, callback)
    end
end

local function restoreNative(state)
    if not canModify(state.bar) or not canModify(state.status) then
        return
    end
    -- Keep the saved state until protected native children can be restored too.
    if (state.fill and not canModify(state.fill)) or (state.tick and not canModify(state.tick)) then
        return
    end
    if state.quest then
        state.quest:Hide()
        state.rested:Hide()
    end
    if not state.active then
        return
    end

    state.active = false
    state.restoring = true
    if state.fill and canModify(state.fill) then
        state.fill:SetAlpha(state.fillAlpha or 1)
    end

    -- Recompute native exhaustion instead of restoring stale points or visibility.
    -- The player's XP/rest state may have changed while our preview was visible.
    if state.tick and canModify(state.tick) and type(state.tick.UpdateTickPosition) == 'function' then
        Compat.Call(state.tick.UpdateTickPosition, state.tick)
    elseif type(state.bar.UpdateTick) == 'function' then
        Compat.Call(state.bar.UpdateTick, state.bar)
    elseif state.legacy and type(ExhaustionTick_OnEvent) == 'function' then
        Compat.Call(ExhaustionTick_OnEvent, state.tick, 'UPDATE_EXHAUSTION')
    elseif state.tick and canModify(state.tick) and state.tickWasShown then
        state.tick:Show()
    end
    state.restoring = false
end

local function readRestedXP()
    if type(GetXPExhaustion) ~= 'function' then
        return 0
    end
    local ok, value = pcall(GetXPExhaustion)
    if not ok or not Compat.IsReadable(value) then
        return
    end
    if value == nil then
        return 0
    end
    value = number(value)
    if value and value >= 0 then
        return value
    end
end

local function canEarnXP(state)
    if
        Compat.Call(IsXPUserDisabled) == true
        or Compat.Call(state.bar.IsCapped, state.bar) == true
        or Compat.Call(IsPlayerAtEffectiveMaxLevel) == true
    then
        return false
    end
    if GameRulesUtil then
        if
            Compat.Call(GameRulesUtil.CanShowExperienceBar) == false
            or Compat.Call(GameRulesUtil.IsPlayerAtEffectiveMaxLevel) == true
        then
            return false
        end
    end
    local level = number(Compat.Call(UnitLevel, 'player'))
    -- The native bar knows special-mode caps that can exceed the purchased expansion cap.
    local maximum = number(Compat.Call(state.bar.GetMaxLevel, state.bar))
        or number(Compat.Call(GameRulesUtil and GameRulesUtil.GetEffectiveMaxLevelForPlayer))
        or number(Compat.GetMaxPlayerLevel())
    return not (level and maximum and level >= maximum)
end

local function positionSegment(texture, status, start, finish, width, height)
    if finish <= start then
        texture:Hide()
        return
    end
    texture:ClearAllPoints()
    texture:SetPoint('TOPLEFT', status, 'TOPLEFT', start * width, 0)
    texture:SetSize((finish - start) * width, height)
    texture:Show()
end

drawState = function(state)
    if state.drawing or state.restoring then
        return
    end
    if not canModify(state.bar) or not canModify(state.status) then
        return
    end
    if (state.fill and not canModify(state.fill)) or (state.tick and not canModify(state.tick)) then
        return
    end
    state.drawing = true
    local status = state.status
    local width = number(Compat.Call(status.GetWidth, status))
    local height = number(Compat.Call(status.GetHeight, status))
    local rested = readRestedXP()
    local minimum, maximum = Compat.Call(status.GetMinMaxValues, status)
    minimum, maximum = number(minimum), number(maximum)
    local current = number(Compat.Call(status.GetValue, status))
    current = current or number(Compat.Call(UnitXP, 'player'))
    minimum = minimum or 0
    maximum = maximum or number(Compat.Call(UnitXPMax, 'player'))

    if
        not enabled
        or totalXP <= 0
        or not visible(state.bar)
        or not visible(status)
        or not canEarnXP(state)
        or not width
        or width <= 0
        or not height
        or height <= 0
        or not current
        or not maximum
        or maximum <= minimum
        or rested == nil
        or Compat.Call(status.GetOrientation, status) == 'VERTICAL'
        or Compat.Call(status.GetReverseFill, status) == true
    then
        restoreNative(state)
        state.drawing = false
        return
    end

    if not state.active then
        state.fillAlpha = state.fill and number(Compat.Call(state.fill.GetAlpha, state.fill)) or 1
        state.tickWasShown = state.tick and visible(state.tick)
        state.active = true
    end
    if state.fill and canModify(state.fill) then
        state.fill:SetAlpha(0)
    end
    if state.tick and canModify(state.tick) then
        state.tick:Hide()
    end

    local range = maximum - minimum
    local earnedEnd = math.max(0, math.min(1, (current - minimum) / range))
    local questEnd = math.max(earnedEnd, math.min(1, (current - minimum + totalXP) / range))
    local restedEnd = math.max(questEnd, math.min(1, (current - minimum + totalXP + rested) / range))
    -- Both previews stop at this level's edge; the tooltip retains the complete sum.
    positionSegment(state.quest, status, earnedEnd, questEnd, width, height)
    positionSegment(state.rested, status, questEnd, restedEnd, width, height)
    state.drawing = false
end

local function annotateRestedLine(line, stateName, percentage)
    if not canModify(line) or type(line.SetText) ~= 'function' then
        return false
    end
    local current = Compat.Call(line.GetText, line)
    if type(current) ~= 'string' then
        return false
    end
    local previous = restedTooltipLines[line]
    local original = previous and current == previous.text and previous.original or current
    -- Newbie tips can mention rest in their introduction; prefer the colored heading.
    local first, last = original:find(stateName .. '|r', 1, true)
    if first then
        last = last - 2
    else
        first, last = original:find(stateName, 1, true)
    end
    if not first then
        return false
    end

    -- Insert before the native color reset so the percentage inherits the label's color.
    local text = original:sub(1, last) .. ' (' .. percentage .. '%)' .. original:sub(last + 1)
    if text == current then
        return true
    end
    if pcall(line.SetText, line, text) then
        restedTooltipLines[line] = { original = original, text = text }
        return true
    end
    return false
end

local function annotateRestedTooltip(tooltip)
    local stateID, stateName = Compat.Call(GetRestState)
    local rested = number(Compat.Call(GetXPExhaustion))
    local maximum = number(Compat.Call(UnitXPMax, 'player'))
    if
        stateID ~= 1
        or type(stateName) ~= 'string'
        or stateName == ''
        or not rested
        or rested < 0
        or not maximum
        or maximum <= 0
    then
        return false
    end
    local percent = number(rested / maximum * 100)
    if not percent then
        return false
    end
    local rounded = number(math.floor(percent * 10 + 0.5) / 10)
    if not rounded then
        return false
    end
    local percentage = L.Number((string.format('%.1f', rounded):gsub('%.0$', '')))
    local name = Compat.Call(tooltip.GetName, tooltip)
    local count = number(Compat.Call(tooltip.NumLines, tooltip))
    if type(name) == 'string' and count then
        for index = 1, count do
            if annotateRestedLine(_G[name .. 'TextLeft' .. index], stateName, percentage) then
                return true
            end
        end
    end
    -- Anonymous tooltip frames expose the same FontStrings through their regions.
    for _, region in ipairs({ Compat.Call(tooltip.GetRegions, tooltip) }) do
        if
            canAccess(region)
            and Compat.Call(region.IsShown, region) ~= false
            and annotateRestedLine(region, stateName, percentage)
        then
            return true
        end
    end
    return false
end

local function appendTooltip(state)
    if not enabled or not visible(state.bar) then
        return
    end
    -- Retail/Forever skip their tooltip reset while the rest state is unavailable.
    -- Match that guard so repeated native calls cannot append to stale lines.
    if type(GetRestState) == 'function' and Compat.Call(GetRestState) == nil then
        return
    end
    local tooltip = Compat.Call(GetAppropriateTooltip) or GameTooltip
    if not canAccess(tooltip) then
        return
    end
    local annotated = annotateRestedTooltip(tooltip)
    if totalXP <= 0 and questCount <= 0 and not details.incompleteData then
        if annotated and type(tooltip.Show) == 'function' then
            tooltip:Show()
        end
        return
    end
    if type(tooltip.AddLine) ~= 'function' then
        return
    end
    tooltip:AddLine(L.Format('Completed quest XP: %s', addon.Core.QuestXPText(totalXP)), 0.15, 0.9, 0.25, true)
    if details.incompleteData then
        tooltip:AddLine(L['Some completed quest rewards are unavailable.'], 0.8, 0.8, 0.8, true)
    end
    if details.estimated then
        tooltip:AddLine(L['Quest XP includes database estimates.'], 0.8, 0.8, 0.8, true)
    end
    if type(tooltip.Show) == 'function' then
        tooltip:Show()
    end
end

local function createState(bar, legacy)
    local existing = states[bar]
    if existing then
        return existing
    end
    local status = bar.StatusBar or (legacy and bar)
    if Compat.InCombat() or not canModify(bar) or not canModify(status) or type(status.CreateTexture) ~= 'function' then
        return
    end
    local fill = bar.ExhaustionLevelFillBar or (legacy and _G.ExhaustionLevelFillBar)
    local tick = bar.ExhaustionTick or (legacy and _G.ExhaustionTick)
    if fill and (not canModify(fill) or type(fill.SetAlpha) ~= 'function') then
        return
    end
    if tick and (not canModify(tick) or type(tick.Hide) ~= 'function') then
        return
    end

    local state = { bar = bar, status = status, fill = fill, tick = tick, legacy = legacy }
    state.quest = status:CreateTexture(nil, 'ARTWORK', nil, 1)
    state.quest:SetColorTexture(0.29, 0.44, 0.12, 0.85)
    state.quest:Hide()
    state.rested = status:CreateTexture(nil, 'ARTWORK', nil, 1)
    state.rested:SetColorTexture(0, 0.39, 0.88, 0.33)
    state.rested:Hide()
    states[bar] = state

    local function redraw()
        drawState(state)
    end
    hookMethod(bar, 'Update', redraw)
    hookMethod(bar, 'UpdateTick', redraw)
    hookMethod(status, 'SetValue', redraw)
    hookMethod(status, 'SetAnimatedValues', redraw)
    hookMethod(status, 'SetMinMaxValues', redraw)
    hookScript(bar, 'OnShow', redraw)
    hookScript(status, 'OnShow', redraw)
    hookScript(bar, 'OnSizeChanged', redraw)
    hookScript(status, 'OnSizeChanged', redraw)
    hookScript(bar, 'OnHide', function()
        restoreNative(state)
    end)

    if tick then
        hookMethod(tick, 'UpdateTickPosition', redraw)
        hookScript(tick, 'OnShow', function()
            if state.active and enabled and canModify(tick) then
                tick:Hide()
            end
        end)
    end
    if tick and type(tick.ExhaustionToolTipText) == 'function' then
        -- After its missing-rest-state guard, the native builder resets its text.
        hookMethod(tick, 'ExhaustionToolTipText', function()
            appendTooltip(state)
        end)
    else
        hookScript(bar, 'OnEnter', function()
            appendTooltip(state)
        end)
    end
    return state
end

local function addContainer(container, experienceIndex)
    if not canAccess(container) then
        return
    end
    local bars = container.bars
    local bar = type(bars) == 'table' and bars[experienceIndex]
    if canAccess(bar) and not bar.isPetExpBar then
        createState(bar)
    end
    hookMethod(container, 'InitializeBars', function()
        ExperienceBar.Refresh()
    end)
    hookMethod(container, 'ApplyPendingBarToShow', function()
        ExperienceBar.Refresh()
    end)
end

discoverBars = function()
    if discovering then
        return
    end
    discovering = true
    local manager = _G.StatusTrackingBarManager
    local experienceIndex = StatusTrackingBarInfo
            and StatusTrackingBarInfo.BarsEnum
            and StatusTrackingBarInfo.BarsEnum.Experience
        or 4
    if canAccess(manager) then
        for _, container in pairs(type(manager.barContainers) == 'table' and manager.barContainers or {}) do
            addContainer(container, experienceIndex)
        end
        -- Some older managers keep the same native XP bar directly in their bar map.
        addContainer(manager, experienceIndex)
        addContainer(manager.MainStatusTrackingBarContainer, experienceIndex)
        addContainer(manager.SecondaryStatusTrackingBarContainer, experienceIndex)
        hookMethod(manager, 'UpdateBarsShown', function()
            ExperienceBar.Refresh()
        end)
    end
    addContainer(_G.MainStatusTrackingBarContainer, experienceIndex)
    addContainer(_G.SecondaryStatusTrackingBarContainer, experienceIndex)
    if canAccess(_G.MainMenuExpBar) then
        createState(_G.MainMenuExpBar, true)
    end
    discovering = false
end

function ExperienceBar.Install()
    discoverBars()
end

function ExperienceBar.Refresh(completedXP, completedCount, metadata)
    if completedXP ~= nil then
        totalXP = math.max(0, number(completedXP) or 0)
        questCount = math.max(0, number(completedCount) or 0)
        details = type(metadata) == 'table' and metadata or {}
        enabled = true
    end
    discoverBars()
    for _, state in pairs(states) do
        drawState(state)
    end
end

function ExperienceBar.Disable()
    enabled = false
    for _, state in pairs(states) do
        restoreNative(state)
    end
end
