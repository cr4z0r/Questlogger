-- Shared, self-contained Dialogue UI-inspired skin for Questlogger popups.
local _, addon = ...
local Style = {}
addon.UI.TooltipStyle = Style

-- Semantic roles keep text colors consistent across cards, lists, and help popups.
Style.colors = {
    title = { 1, 0.82, 0.3 },
    heading = { 1, 0.82, 0.3 },
    reward = { 0.65, 0.82, 1 },
    summary = { 1, 0.83, 0.40, 0.80 },
    followupSummary = { 1, 0.83, 0.40, 0.75 },
    muted = { 0.65, 0.65, 0.65 },
    link = { 0.35, 0.8, 1 },
    hover = { 0.8, 1, 1 },
    helpBody = { 1, 1, 1 },
    helpNote = { 0.8, 0.8, 0.8 },
}

local texture = 'Interface\\AddOns\\Questlogger\\Assets\\TooltipPaper.tga'
local corner = 16
local cuts = { 0, 0.125, 0.875, 1 }
local fontSizes = {
    title = 16,
    body = 14,
    questText = 13,
    widgetHeading = 14,
    followupSummary = 11,
}

-- Nine separate regions preserve the paper edges on older clients too.
function Style.Apply(frame)
    if frame.QuestloggerSkin then
        return
    end
    frame.QuestloggerSkin = {}
    for row = 1, 3 do
        for col = 1, 3 do
            local textureRegion = frame:CreateTexture(nil, 'BACKGROUND', nil, -1)
            textureRegion:SetTexture(texture)
            textureRegion:SetTexCoord(cuts[col], cuts[col + 1], cuts[row], cuts[row + 1])
            local x1 = col == 1 and 0 or (col == 2 and corner or -corner)
            local x2 = col == 1 and corner or (col == 2 and -corner or 0)
            local y1 = row == 1 and 0 or (row == 2 and -corner or corner)
            local y2 = row == 1 and -corner or (row == 2 and corner or 0)
            local left = col == 3 and 'RIGHT' or 'LEFT'
            local right = col == 1 and 'LEFT' or 'RIGHT'
            local top = row == 3 and 'BOTTOM' or 'TOP'
            local bottom = row == 1 and 'TOP' or 'BOTTOM'
            textureRegion:SetPoint('TOPLEFT', frame, top .. left, x1, y1)
            textureRegion:SetPoint('BOTTOMRIGHT', frame, bottom .. right, x2, y2)
            frame.QuestloggerSkin[#frame.QuestloggerSkin + 1] = textureRegion
        end
    end
end

-- Use the client's localized serif font, not a bundled font file.
function Style.Font(text, role)
    local bodyFont = role == 'body' or role == 'questText'
    local fontObject = role == 'title' and GameFontNormalLarge
        or (bodyFont and GameFontHighlight or GameFontHighlightSmall)
    local size = fontSizes[role] or 12
    text:SetFontObject(fontObject)
    -- Font objects already select a glyph-complete font for the client's language.
    local path = fontObject and fontObject.GetFont and fontObject:GetFont()
    if not path and text.GetFont then
        path = text:GetFont()
    end
    path = path or STANDARD_TEXT_FONT
    if path then
        text:SetFont(path, size, '')
    end
    text:SetShadowColor(0, 0, 0, 0.45)
    text:SetShadowOffset(0, -1)
end

function Style.Color(text, role)
    local color = Style.colors[role]
    text:SetTextColor(color[1], color[2], color[3], color[4] or 1)
end

-- Match inline color spans to the shared palette.
function Style.InlineColor(value, role)
    local color = Style.colors[role]
    return string.format(
        '|c%02x%02x%02x%02x%s|r',
        math.floor((color[4] or 1) * 255 + 0.5),
        math.floor(color[1] * 255 + 0.5),
        math.floor(color[2] * 255 + 0.5),
        math.floor(color[3] * 255 + 0.5),
        value
    )
end
