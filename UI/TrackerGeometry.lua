-- Keep tracker movement and resizing session-local, outside Blizzard's saved Edit Mode layout.
local _, addon = ...
local Geometry = {}
addon.UI.TrackerGeometry = Geometry

local RESIZE_GRIP_HEIGHT, RESIZE_GRIP_LINE = 10, 2

local function inCombat()
    return InCombatLockdown and InCombatLockdown()
end

local function isVisible(frame)
    return frame and frame.IsVisible and frame:IsVisible()
end

local function isEditModeActive()
    return EditModeManagerFrame and EditModeManagerFrame.IsEditModeActive and EditModeManagerFrame:IsEditModeActive()
end

-- The controller shares the native tracker state, but owns only its temporary geometry.
function Geometry.Create(nativeState, requestNativeLayout, leftGutter, rightGutter)
    local function canChangeGeometry(geometry)
        return geometry and geometry.enabled and not inCombat() and not isEditModeActive() and isVisible(geometry.root)
    end

    local function getScreenBounds(root)
        local scale = root:GetEffectiveScale()
        local ratio = UIParent:GetEffectiveScale() / scale
        return scale, UIParent:GetWidth() * ratio, UIParent:GetHeight() * ratio
    end

    local function clampGeometry(geometry, x, top, height)
        local _, width, screenHeight = getScreenBounds(geometry.root)
        local minHeight = math.min(120, screenHeight)
        height = math.max(minHeight, math.min(height, screenHeight))
        x = math.max(0, math.min(x, width - (geometry.width or geometry.root:GetWidth())))
        top = math.max(height, math.min(top, screenHeight))
        return x, top, height
    end

    local function applyGeometry(geometry)
        if not canChangeGeometry(geometry) or not geometry.custom or geometry.applying then
            return
        end
        geometry.applying = true

        local root = geometry.root
        geometry.x, geometry.top, geometry.height = clampGeometry(geometry, geometry.x, geometry.top, geometry.height)
        local _, _, screenHeight = getScreenBounds(root)
        local point, relative, relativePoint, x, y = root:GetPoint(1)
        local desiredY = geometry.top - screenHeight
        if
            root:GetNumPoints() ~= 1
            or point ~= 'TOPLEFT'
            or relative ~= UIParent
            or relativePoint ~= 'TOPLEFT'
            or x ~= geometry.x
            or y ~= desiredY
        then
            -- Bypass Edit Mode's snap bookkeeping without changing its saved systemInfo.
            local clear = root.ClearAllPointsBase or root.ClearAllPoints
            local anchor = root.SetPointBase or root.SetPoint
            clear(root)
            anchor(root, 'TOPLEFT', UIParent, 'TOPLEFT', geometry.x, desiredY)
        end
        if math.abs(root:GetWidth() - geometry.width) > 0.1 then
            root:SetWidth(geometry.width)
        end

        root.editModeHeight = geometry.height
        local heightChanged = math.abs(root:GetHeight() - geometry.height) > 0.1
        if heightChanged then
            root:SetHeight(geometry.height)
        end
        if heightChanged or geometry.layoutHeight ~= geometry.height then
            geometry.layoutHeight = geometry.height
            -- Resizing is not a quest event, so request a fresh height budget directly.
            if root.Update then
                root:Update(false)
            else
                for _, module in ipairs(root.modules or {}) do
                    if module.MarkDirty then
                        module:MarkDirty()
                    end
                end
                requestNativeLayout()
            end
        end
        geometry.applying = nil
    end

    local function captureGeometry(geometry)
        local root = geometry.root
        if not geometry.custom then
            geometry.x, geometry.top, geometry.height = root:GetLeft(), root:GetTop(), root:GetHeight()
            if type(geometry.x) ~= 'number' or type(geometry.top) ~= 'number' then
                return false
            end
            geometry.width = root:GetWidth()

            local original = {
                points = {},
                height = geometry.height,
                width = geometry.width,
                ignore = root.ignoreFramePositionManager,
                parent = root:GetParent(),
                editHeight = root.editModeHeight,
                defaultMethod = root.IsInDefaultPosition,
            }
            for index = 1, root:GetNumPoints() do
                original.points[index] = { root:GetPoint(index) }
            end
            original.managed = original.defaultMethod
                and root:IsInDefaultPosition()
                and root.BreakFromFrameManager
                and root.GetManagedFrameContainer
                and root:GetManagedFrameContainer()
            geometry.original = original

            -- Blizzard's manager can reset anchors and height during Update. Detach until
            -- the session ends or another tracker/Edit Mode needs to take control.
            geometry.custom = true
            if original.defaultMethod then
                root.IsInDefaultPosition = function(self)
                    if geometry.custom then
                        return false
                    end
                    return original.defaultMethod(self)
                end
            end
            if original.managed then
                root:BreakFromFrameManager()
            end
            root.ignoreFramePositionManager = true
            applyGeometry(geometry)
        end
        return true
    end

    local function stopGeometry(geometry)
        if geometry then
            geometry.drag = nil
        end
    end

    local function beginGeometry(geometry, mode)
        if
            not canChangeGeometry(geometry)
            or not IsShiftKeyDown
            or not IsShiftKeyDown()
            or not GetCursorPosition
            or not captureGeometry(geometry)
        then
            return
        end

        local scale = getScreenBounds(geometry.root)
        local x, y = GetCursorPosition()
        geometry.drag = {
            mode = mode,
            x = x / scale,
            y = y / scale,
            left = geometry.x,
            top = geometry.top,
            height = geometry.height,
        }
    end

    local function updateGeometry(geometry)
        if not canChangeGeometry(geometry) then
            stopGeometry(geometry)
            return
        end
        if geometry.drag then
            local drag = geometry.drag
            if
                (IsMouseButtonDown and not IsMouseButtonDown('LeftButton'))
                or not IsShiftKeyDown
                or not IsShiftKeyDown()
            then
                stopGeometry(geometry)
            else
                local scale, _, screenHeight = getScreenBounds(geometry.root)
                local x, y = GetCursorPosition()
                local deltaX, deltaY = x / scale - drag.x, y / scale - drag.y
                if drag.mode == 'move' then
                    geometry.x, geometry.top, geometry.height = drag.left + deltaX, drag.top + deltaY, drag.height
                elseif drag.mode == 'top' then
                    local bottom = drag.top - drag.height
                    geometry.height =
                        math.max(math.min(120, screenHeight), math.min(drag.height + deltaY, screenHeight - bottom))
                    geometry.top = bottom + geometry.height
                else
                    geometry.height = math.max(math.min(120, screenHeight), math.min(drag.height - deltaY, drag.top))
                    geometry.top = drag.top
                end
            end
        end
        applyGeometry(geometry)
    end

    -- Restore the original manager, anchors, and dimensions before handing off control.
    local function releaseGeometry(geometry)
        stopGeometry(geometry)
        if not geometry.custom then
            return
        end

        local root, original = geometry.root, geometry.original
        geometry.custom = nil
        geometry.original = nil
        geometry.layoutHeight = nil
        root.IsInDefaultPosition = original.defaultMethod
        root.ignoreFramePositionManager = original.ignore
        root.editModeHeight = original.editHeight
        if original.managed and root.ApplySystemAnchor then
            root:ApplySystemAnchor()
        else
            if original.parent and root:GetParent() ~= original.parent then
                root:SetParent(original.parent)
            end
            root:ClearAllPoints()
            for _, point in ipairs(original.points) do
                root:SetPoint(unpack(point, 1, 5))
            end
        end
        root:SetWidth(original.width)
        root:SetHeight(original.height)
        if root.MarkDirty then
            root:MarkDirty()
        end
    end

    local function hasTrackerOverflow(root)
        if root.IsCollapsed and root:IsCollapsed() then
            return false
        end

        local scroll = nativeState.scroll
        local module = nativeState.module
        if
            scroll
            and module
            and module.firstBlock
            and not module:IsCollapsed()
            and (scroll.contentHeight or 0) > (scroll.viewHeight or 0) + 0.5
        then
            return true
        end
        for _, trackerModule in ipairs(root.modules or {}) do
            if
                (not trackerModule.IsCollapsed or not trackerModule:IsCollapsed())
                and trackerModule.IsTruncated
                and trackerModule:IsTruncated()
            then
                return true
            end
        end
        return false
    end

    local function setEnabled(geometry, enabled)
        if not geometry or geometry.enabled == enabled then
            return
        end
        geometry.enabled = enabled
        if not enabled then
            releaseGeometry(geometry)
        end
        geometry.moveSurface:EnableMouse(false)
        geometry.moveSurface:SetShown(enabled)
        geometry.moveSurface.captured = nil
        for _, edge in ipairs(geometry.edges) do
            edge:SetShown(enabled)
            edge:EnableMouse(false)
            edge.line:Hide()
        end
    end

    local function isMouseOver(frame)
        return frame
            and not (frame.IsForbidden and frame:IsForbidden())
            and isVisible(frame)
            and frame.IsMouseOver
            and frame:IsMouseOver()
    end

    local function isEntryHovered(root)
        if isMouseOver(nativeState.bar) then
            return true
        end
        -- Check bounds directly so the drag surface cannot obscure the hovered row.
        for _, module in ipairs(root.modules or {}) do
            if isMouseOver(module.QuestloggerCategoryToolbar) then
                return true
            end
            local block, seen = module.firstBlock, {}
            while block and not seen[block] do
                seen[block] = true
                if
                    isMouseOver(block)
                    or isMouseOver(block.HeaderButton)
                    or isMouseOver(block.poiButton)
                    or isMouseOver(block.ItemButton)
                then
                    return true
                end
                for region in pairs(block.addedRegions or {}) do
                    if isMouseOver(region) then
                        return true
                    end
                end
                block = block.nextBlock
            end
        end
        return false
    end

    local function install(root)
        if nativeState.geometry then
            return nativeState.geometry
        end
        if
            not root.Header
            or not root.GetEffectiveScale
            or not root.GetLeft
            or not root.GetTop
            or not GetCursorPosition
        then
            return
        end

        local geometry = { root = root, edges = {}, enabled = false }
        nativeState.geometry = geometry
        local header = root.Header

        -- Shift-drag empty space or a category header; entries keep their own clicks.
        local surface = CreateFrame('Frame', nil, root)
        geometry.moveSurface = surface
        surface:SetPoint('TOPLEFT', root, 'TOPLEFT', -leftGutter, 0)
        surface:SetPoint('BOTTOMRIGHT', root, 'BOTTOMRIGHT', rightGutter, 0)
        local strata = root.GetFrameStrata and root:GetFrameStrata() or 'MEDIUM'
        if strata == 'BACKGROUND' or strata == 'LOW' then
            strata = 'MEDIUM'
        end
        local level = math.max(100, (root.GetFrameLevel and root:GetFrameLevel() or 0) + 100)
        surface:SetFrameStrata(strata)
        if surface.SetFrameLevel then
            surface:SetFrameLevel(level)
        end
        surface:EnableMouse(false)
        surface:Hide()
        surface:SetScript('OnMouseDown', function(self, button)
            if button ~= 'LeftButton' then
                return
            end
            local mode = 'move'
            for _, edge in ipairs(geometry.edges) do
                if edge:IsMouseOver() then
                    mode = edge.mode
                    break
                end
            end
            beginGeometry(geometry, mode)
            self.captured = geometry.drag ~= nil
        end)
        surface:SetScript('OnMouseUp', function(self, button)
            if button == 'LeftButton' then
                stopGeometry(geometry)
                self.captured = nil
                local enabled = canChangeGeometry(geometry)
                    and IsShiftKeyDown
                    and IsShiftKeyDown()
                    and not isEntryHovered(root)
                self:EnableMouse(not not enabled)
            end
        end)

        -- Only the edge hit areas reveal a grip; ordinary clicks reach the tracker below.
        for _, mode in ipairs({ 'top', 'bottom' }) do
            local edge = CreateFrame('Frame', nil, root)
            local point = mode == 'top' and 'TOP' or 'BOTTOM'
            local anchor = mode == 'top' and header or root
            local offset = mode == 'top' and RESIZE_GRIP_HEIGHT / 2 or -RESIZE_GRIP_HEIGHT / 2
            edge:SetPoint(point .. 'LEFT', anchor, point .. 'LEFT', 0, offset)
            edge:SetPoint(point .. 'RIGHT', anchor, point .. 'RIGHT', 0, offset)
            edge:SetHeight(RESIZE_GRIP_HEIGHT)
            edge:EnableMouse(false)
            edge:SetFrameStrata(strata)
            if edge.SetFrameLevel then
                edge:SetFrameLevel(level + 1)
            end
            edge.mode = mode
            edge.line = edge:CreateTexture(nil, 'OVERLAY')
            edge.line:SetColorTexture(0.65, 0.82, 1, 0.42)
            edge.line:SetPoint('LEFT', edge, 'LEFT', 0, 0)
            edge.line:SetPoint('RIGHT', edge, 'RIGHT', 0, 0)
            edge.line:SetHeight(RESIZE_GRIP_LINE)
            edge.line:Hide()
            edge:SetScript('OnMouseDown', function(_, button)
                if button == 'LeftButton' and IsShiftKeyDown and IsShiftKeyDown() then
                    beginGeometry(geometry, mode)
                end
            end)
            edge:SetScript('OnMouseUp', function()
                stopGeometry(geometry)
            end)
            edge:Hide()
            geometry.edges[#geometry.edges + 1] = edge
        end

        root:HookScript('OnHide', function()
            stopGeometry(geometry)
            surface.captured = nil
            surface:EnableMouse(false)
            for _, edge in ipairs(geometry.edges) do
                edge:EnableMouse(false)
            end
        end)
        root:HookScript('OnUpdate', function()
            if not geometry.enabled then
                return
            end
            if not canChangeGeometry(geometry) then
                if not inCombat() and isEditModeActive() and geometry.custom then
                    releaseGeometry(geometry)
                end
                stopGeometry(geometry)
                surface.captured = nil
                surface:EnableMouse(false)
                for _, edge in ipairs(geometry.edges) do
                    edge:EnableMouse(false)
                    edge.line:Hide()
                end
                return
            end

            updateGeometry(geometry)
            if surface.captured and IsMouseButtonDown and not IsMouseButtonDown('LeftButton') then
                surface.captured = nil
            end
            -- Keep capture through release even when the player releases Shift first.
            surface:EnableMouse(
                not not (surface.captured or (IsShiftKeyDown and IsShiftKeyDown() and not isEntryHovered(root)))
            )
            for _, edge in ipairs(geometry.edges) do
                local active = geometry.drag and geometry.drag.mode == edge.mode
                local near = edge:IsMouseOver()
                edge:EnableMouse(not not (active or (near and IsShiftKeyDown and IsShiftKeyDown())))
                edge.line:SetShown(not not (near or active or (edge.mode == 'bottom' and hasTrackerOverflow(root))))
            end
        end)
        return geometry
    end

    return {
        Install = install,
        SetEnabled = setEnabled,
        Stop = stopGeometry,
    }
end
