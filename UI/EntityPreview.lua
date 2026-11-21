-- Reuse a skinned popup for entity previews and dependency help.
local _, addon = ...
local L = addon.L
local Data, UI = addon.Data, addon.UI
local Style, call = UI.TooltipStyle, Data.Call
local PREVIEW_WIDTH, PREVIEW_PADDING, MODEL_HEIGHT, PREVIEW_TIMEOUT, MODEL_RETRY_INTERVAL = 200, 12, 180, 5, 0.25
local DOT_COUNT, DOT_RADIUS, DOT_SIZE, SPIN_PERIOD = 8, 15, 6, 0.9
local DOT_TEXTURE = 'Interface\\AddOns\\Questlogger\\Assets\\LoadingDot.tga'

local function createLabel(popup, role)
    local textLine = popup:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
    Style.Font(textLine, role == 'heading' and 'body' or 'small')
    Style.Color(textLine, role)
    textLine:SetWidth(PREVIEW_WIDTH - 2 * PREVIEW_PADDING)
    textLine:SetWordWrap(true)
    textLine:SetJustifyH('LEFT')
    textLine:SetJustifyV('TOP')
    return textLine
end

-- A small gold spinner rotates by changing the opacity of its dots.
local function animateSpinner(spinner, elapsed)
    local phase = (elapsed / SPIN_PERIOD * DOT_COUNT) % DOT_COUNT
    for i, dot in ipairs(spinner.dots) do
        local distance = (phase - (i - 1)) % DOT_COUNT
        dot:SetAlpha(0.16 + 0.84 * (1 - distance / DOT_COUNT) ^ 2)
    end
end

local function makeSpinner(parent)
    local spinner = CreateFrame('Frame', nil, parent)
    spinner:SetSize(2 * DOT_RADIUS + DOT_SIZE, 2 * DOT_RADIUS + DOT_SIZE)
    spinner:SetFrameLevel(40)
    spinner:EnableMouse(false)
    spinner.dots = {}
    for i = 1, DOT_COUNT do
        local angle = (i - 1) * 2 * math.pi / DOT_COUNT
        local dot = spinner:CreateTexture(nil, 'OVERLAY')
        dot:SetTexture(DOT_TEXTURE)
        dot:SetVertexColor(1, 0.82, 0.3)
        dot:SetSize(DOT_SIZE, DOT_SIZE)
        dot:SetPoint('CENTER', spinner, 'CENTER', math.sin(angle) * DOT_RADIUS, math.cos(angle) * DOT_RADIUS)
        spinner.dots[i] = dot
    end
    spinner:Hide()
    return spinner
end

local function createPopup(parent)
    local popup = CreateFrame('Frame', nil, parent)
    popup:SetFrameStrata('FULLSCREEN_DIALOG')
    popup:SetFrameLevel(35)
    popup:SetClampedToScreen(true)
    popup:EnableMouse(true)
    Style.Apply(popup)
    popup.title = createLabel(popup, 'heading')
    popup.title:SetPoint('TOPLEFT', PREVIEW_PADDING, -PREVIEW_PADDING)
    popup.status = createLabel(popup, 'reward')
    popup.spinner = makeSpinner(popup)
    popup.itemHolder = CreateFrame('Frame', nil, popup)
    popup.itemHolder:Hide()
    popup.models = {}
    popup.modelSlot = 0
    popup:Hide()
    return popup
end

local function resetModel(model)
    if not model then
        return
    end
    model:SetAlpha(0)
    call(model.SetModelAlpha, model, 0)
    model:Hide()
    call(model.ClearModel, model)
end

local function acquireModel(popup)
    -- Alternate two frames so the previous request cannot repaint the active one.
    popup.modelSlot = popup.modelSlot % 2 + 1
    local model = popup.models[popup.modelSlot]
    if not model then
        local ok, createdModel = pcall(CreateFrame, 'PlayerModel', nil, popup)
        if not ok or not createdModel then
            return
        end
        model = createdModel
        popup.models[popup.modelSlot] = model
        model:EnableMouse(false)
        call(model.SetKeepModelOnHide, model, false)
        call(model.SetDoBlend, model, false)
    end
    resetModel(model)
    if
        type(model.SetCreature) ~= 'function'
        or type(model.GetModelFileID) ~= 'function'
        or type(model.ClearModel) ~= 'function'
    then
        return
    end
    return model
end

local function layoutPopup(popup, visual, message)
    local y = PREVIEW_PADDING + math.max(14, popup.title:GetStringHeight()) + 6
    local model = popup.model
    if model then
        model:ClearAllPoints()
        model:SetPoint('TOPLEFT', popup, 'TOPLEFT', PREVIEW_PADDING, -y)
        model:SetSize(PREVIEW_WIDTH - 2 * PREVIEW_PADDING, MODEL_HEIGHT)
        -- Keep the renderer active while loading, but make its contents invisible.
        local alpha = visual == 'model' and 1 or 0
        model:SetAlpha(alpha)
        call(model.SetModelAlpha, model, alpha)
        model:SetShown(visual == 'model' or visual == 'loading')
    end
    popup.spinner:ClearAllPoints()
    popup.spinner:SetPoint('CENTER', popup, 'TOPLEFT', PREVIEW_WIDTH / 2, -y - MODEL_HEIGHT / 2)
    popup.spinner:SetShown(visual == 'loading')
    if visual == 'loading' then
        animateSpinner(popup.spinner, 0)
    end
    if visual == 'item' then
        popup.itemHolder:ClearAllPoints()
        popup.itemHolder:SetPoint('TOPLEFT', popup, 'TOPLEFT', (PREVIEW_WIDTH - 48) / 2, -y)
        UI.RewardStrip(
            popup.itemHolder,
            { { kind = 'item', id = popup.entity.id, name = popup.entity.name, texture = popup.itemTexture } },
            48,
            48
        )
    else
        UI.HideRewardIcons(popup.itemHolder)
        popup.itemHolder:Hide()
    end
    -- Reserve identical space for the spinner and the finished model.
    if visual == 'model' or visual == 'loading' then
        y = y + MODEL_HEIGHT + 4
    elseif visual == 'item' then
        y = y + 54
    end
    popup.status:ClearAllPoints()
    popup.status:SetPoint('TOPLEFT', popup, 'TOPLEFT', PREVIEW_PADDING, -y)
    local nameHint = popup.entity
        and popup.entity.nameUnavailable
        and L['Localized target name unavailable. Target or mouse over the NPC to learn its name.']
    if nameHint then
        message = message and (message .. '\n' .. nameHint) or nameHint
    end
    local hint = popup.entity and popup.entity.hint
    if hint then
        message = message and (message .. '\n' .. hint) or hint
    end
    popup.status:SetText(message or '')
    popup.status:SetShown(message ~= nil)
    if message then
        y = y + math.max(12, popup.status:GetStringHeight()) + 4
    end
    popup:SetSize(PREVIEW_WIDTH, y + PREVIEW_PADDING)
end

local function clearPopup(popup)
    resetModel(popup.model)
    popup.spinner:Hide()
    UI.HideRewardIcons(popup.itemHolder)
    popup.itemHolder:Hide()
    popup.entity = nil
    popup.pending = nil
    popup.elapsed = 0
    popup.retry = 0
    popup.requested = nil
    popup.itemTexture = nil
end

function UI.CloseEntityPreview(card)
    local popup = card.entityPopup
    if popup then
        clearPopup(popup)
        popup:Hide()
    end
    card.entitySource = nil
    card.entityOutside = 0
end

local function modelLoaded(model)
    local modelFileID = call(model.GetModelFileID, model)
    return type(modelFileID) == 'number' and modelFileID > 0
end

local function itemIcon(itemID)
    return call(C_Item and C_Item.GetItemIconByID, itemID) or call(GetItemIcon, itemID)
end

local function requestModel(popup)
    local model = popup.model
    -- A model must be blank before assigning a new creature ID.
    if not popup.requested and modelLoaded(model) then
        call(model.ClearModel, model)
        if modelLoaded(model) then
            return true
        end
    end
    popup.requested = true
    local ok = pcall(model.SetCreature, model, popup.entity.id)
    return ok
end

function UI.ShowEntityPreview(card, source, entity)
    UI.CloseEntityPreview(card)
    -- No placeholder popups for objects or entities without a supported preview.
    if
        not entity.message
        and (entity.kind ~= 'npc' and entity.kind ~= 'item' or type(entity.id) ~= 'number' or entity.id <= 0)
    then
        return
    end
    local popup = card.entityPopup or createPopup(card)
    card.entityPopup = popup
    card.entitySource = source
    popup.entity = entity
    popup.elapsed = 0
    popup.retry = 0
    popup.title:SetText(entity.name or L['Unavailable'])
    if entity.message then
        layoutPopup(popup, nil, entity.message)
    elseif entity.kind == 'npc' then
        popup.model = acquireModel(popup)
        if not popup.model then
            if entity.nameUnavailable then
                -- The name guidance still helps when this client cannot render a model.
                layoutPopup(popup, nil, nil)
            else
                UI.CloseEntityPreview(card)
                return
            end
        else
            popup.pending = true
            layoutPopup(popup, 'loading', nil)
        end
    elseif entity.kind == 'item' then
        local icon = itemIcon(entity.id)
        if icon then
            popup.itemTexture = icon
            layoutPopup(popup, 'item', nil)
        else
            layoutPopup(popup, nil, L['Loading item icon...'])
            popup.pending = true
        end
    end
    popup:ClearAllPoints()
    local right = UIParent:GetWidth() - (card:GetRight() or 0)
    if right >= PREVIEW_WIDTH + 2 or right >= (card:GetLeft() or 0) then
        popup:SetPoint('TOPLEFT', card, 'TOPRIGHT', 2, 0)
    else
        popup:SetPoint('TOPRIGHT', card, 'TOPLEFT', -2, 0)
    end
    popup:Show()
    if popup.pending and entity.kind == 'npc' and not requestModel(popup) then
        UI.CloseEntityPreview(card)
    end
end

local function isMouseOver(frame)
    return frame and frame:IsVisible() and frame:IsMouseOver()
end

function UI.UpdateEntityPreview(card, elapsed)
    local source, popup = card.entitySource, card.entityPopup
    if not source or not popup then
        return
    end
    if not source:IsVisible() then
        UI.CloseEntityPreview(card)
        return
    end
    if isMouseOver(source) or isMouseOver(popup) then
        card.entityOutside = 0
    else
        card.entityOutside = (card.entityOutside or 0) + elapsed
        if card.entityOutside > 0.45 then
            UI.CloseEntityPreview(card)
            return
        end
    end
    if not popup.pending then
        return
    end
    popup.elapsed = popup.elapsed + elapsed
    popup.retry = popup.retry + elapsed
    if popup.entity.kind == 'npc' then
        animateSpinner(popup.spinner, popup.elapsed)
        if popup.requested and modelLoaded(popup.model) then
            popup.pending = nil
            layoutPopup(popup, 'model', nil)
        elseif popup.retry >= MODEL_RETRY_INTERVAL then
            -- SetCreature may need a second request after the creature cache fills.
            popup.retry = 0
            if not requestModel(popup) then
                UI.CloseEntityPreview(card)
                return
            end
            if popup.requested and modelLoaded(popup.model) then
                popup.pending = nil
                layoutPopup(popup, 'model', nil)
            end
        end
    elseif popup.entity.kind == 'item' then
        local icon = itemIcon(popup.entity.id)
        if icon then
            popup.pending = nil
            popup.itemTexture = icon
            layoutPopup(popup, 'item', nil)
        end
    end
    if popup.pending and popup.elapsed >= PREVIEW_TIMEOUT then
        UI.CloseEntityPreview(card)
    end
end
