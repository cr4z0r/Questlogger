-- Renders borderless reward icons with native tooltips.
local _, addon = ...
local L = addon.L
local Compat = addon.Compat
local UI = {}
addon.UI = UI
local call = addon.Data.Call

local function hideOwnedTooltip(owner)
    if GameTooltip:IsOwned(owner) then
        GameTooltip:Hide()
    end
end

local function questRewardTooltip(reward)
    local shown = false
    -- Legacy tooltips read the selected quest; restore it after taking the snapshot.
    Compat.CallQuestReward(function(rewardType, index, questID)
        shown = pcall(GameTooltip.SetQuestLogItem, GameTooltip, rewardType, index, questID)
    end, reward.questID, reward.rewardType, reward.index)
    return shown
end

local function rewardTooltip(button)
    local reward = button.reward
    if not reward then
        return
    end
    GameTooltip:SetOwner(button, 'ANCHOR_RIGHT')
    local ok = false
    if reward.kind == 'item' then
        if reward.link then
            ok = pcall(GameTooltip.SetHyperlink, GameTooltip, reward.link)
        end
        if not ok and reward.id and GameTooltip.SetItemByID then
            ok = pcall(GameTooltip.SetItemByID, GameTooltip, reward.id)
        end
        if not ok and reward.index and reward.questID and GameTooltip.SetQuestLogItem then
            ok = questRewardTooltip(reward)
        end
    elseif reward.kind == 'spell' and GameTooltip.SetSpellByID then
        ok = pcall(GameTooltip.SetSpellByID, GameTooltip, reward.id)
    elseif reward.kind == 'currency' and GameTooltip.SetCurrencyByID then
        ok = pcall(GameTooltip.SetCurrencyByID, GameTooltip, reward.id)
    end
    if not ok or GameTooltip:NumLines() == 0 then
        GameTooltip:SetText(reward.name or L.Format('%s %s', L[reward.kind or 'Reward'], tostring(reward.id or '')))
    end
    if reward.choice then
        GameTooltip:AddLine(L['Choice reward'], 1, 0.82, 0)
    end
    if type(reward.count) == 'number' and reward.count > 1 then
        GameTooltip:AddLine(L.Format('Quantity: %s', L.Number(reward.count)), 1, 1, 1)
    end
    GameTooltip:Show()
end

local function createIcon(parent)
    local button = CreateFrame('Button', nil, parent)
    button:SetSize(20, 20)
    button.icon = button:CreateTexture(nil, 'ARTWORK')
    button.icon:SetAllPoints()
    button.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    button.count = button:CreateFontString(nil, 'OVERLAY', 'NumberFontNormalSmall')
    button.count:SetPoint('BOTTOMRIGHT', 0, 0)
    button.choice = button:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
    button.choice:SetPoint('TOPLEFT', 0, 1)
    button.choice:SetText('?')
    button:SetScript('OnEnter', rewardTooltip)
    button:SetScript('OnLeave', hideOwnedTooltip)
    button:SetScript('OnHide', hideOwnedTooltip)
    button:RegisterForClicks('LeftButtonUp')
    button:SetScript('OnClick', function(self)
        local reward = self.reward
        if reward and reward.link and IsModifiedClick and IsModifiedClick('CHATLINK') and HandleModifiedItemClick then
            HandleModifiedItemClick(reward.link)
        end
    end)
    return button
end

-- Clear stale data when releasing reward buttons.
function UI.HideRewardIcons(holder)
    for _, button in ipairs(holder.icons or {}) do
        button:Hide()
        button.reward = nil
    end
    if holder.label then
        holder.label:Hide()
    end
end

-- Wrap reward icons to fit the available width.
function UI.RewardStrip(holder, rewards, width, size, label, role)
    holder.icons = holder.icons or {}
    local pitch = size + 4
    local offset, top = 0, 0
    if label and #rewards > 0 then
        local text = holder.label
        if not text then
            text = holder:CreateFontString(nil, 'ARTWORK', 'GameFontHighlightSmall')
            holder.label = text
        end
        if role then
            UI.TooltipStyle.Font(text, 'small')
            UI.TooltipStyle.Color(text, role)
        end
        text:SetText(label)
        text:ClearAllPoints()
        text:Show()
        offset = math.ceil(text.GetUnboundedStringWidth and text:GetUnboundedStringWidth() or text:GetStringWidth()) + 5
        -- Very narrow rows put the label above the icons instead.
        if width - offset < size then
            text:SetWidth(width)
            text:SetWordWrap(true)
            text:SetJustifyH('LEFT')
            top = math.max(12, text:GetStringHeight()) + 3
            offset = 0
            text:SetPoint('TOPLEFT', holder, 'TOPLEFT', 0, 0)
        else
            text:SetWidth(offset)
            text:SetJustifyH('LEFT')
            text:SetPoint('LEFT', holder, 'TOPLEFT', 0, -size / 2)
        end
    elseif holder.label then
        holder.label:Hide()
    end
    local columns = math.max(1, math.floor((width - offset + 4) / pitch))
    for i, reward in ipairs(rewards) do
        local button = holder.icons[i]
        if not button then
            button = createIcon(holder)
            holder.icons[i] = button
        end
        button.reward = reward
        button:ClearAllPoints()
        button:SetSize(size, size)
        button:SetPoint(
            'TOPLEFT',
            holder,
            'TOPLEFT',
            offset + ((i - 1) % columns) * pitch,
            -top - math.floor((i - 1) / columns) * pitch
        )
        local icon = reward.texture
        if not icon and reward.kind == 'item' and reward.id then
            icon = call(C_Item and C_Item.GetItemIconByID, reward.id) or call(GetItemIcon, reward.id)
        end
        button.icon:SetTexture(icon or 134400)
        button.count:SetText(type(reward.count) == 'number' and reward.count > 1 and tostring(reward.count) or '')
        button.choice:SetShown(reward.choice == true)
        button:Show()
    end
    for i = #rewards + 1, #holder.icons do
        holder.icons[i]:Hide()
        holder.icons[i].reward = nil
    end
    local height = top + math.ceil(#rewards / columns) * pitch
    holder:SetSize(math.max(1, width), math.max(1, height))
    holder:SetShown(height > 0)
    return height
end
