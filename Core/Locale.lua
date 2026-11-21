-- Resolve addon text without changing Blizzard's locale or the shared quest database.
local _, addon = ...
local aliases = { enGB = 'enUS', ptPT = 'ptBR' }
local supported = {
    enUS = true,
    deDE = true,
    frFR = true,
    esES = true,
    esMX = true,
    itIT = true,
    ptBR = true,
    ruRU = true,
    koKR = true,
    zhCN = true,
    zhTW = true,
}
local locale = 'enUS'
if type(GetLocale) == 'function' then
    local ok, value = pcall(GetLocale)
    if ok and type(value) == 'string' then
        locale = aliases[value] or value
    end
end
if not supported[locale] then
    locale = 'enUS'
end

local translations = {}
local L = { locale = locale }
addon.L = setmetatable(L, {
    __index = function(_, source)
        return translations[source] or source
    end,
})

-- Reject incompatible placeholders before a tooltip can fail inside string.format.
local function formatSignature(text)
    local signature = {}
    text = text:gsub('%%%%', '')
    for conversion in text:gmatch('%%[-+ #0]*%d*%.?%d*([cdiouxXeEfgGqs])') do
        signature[#signature + 1] = conversion
    end
    return table.concat(signature)
end

function L.Register(language, strings)
    if language ~= locale then
        return
    end
    for source, translated in pairs(strings) do
        if
            type(source) == 'string'
            and type(translated) == 'string'
            and translated ~= ''
            and formatSignature(source) == formatSignature(translated)
        then
            translations[source] = translated
        end
    end
end

function L.Format(source, ...)
    local translated = L[source]
    if translated ~= source then
        local ok, formatted = pcall(string.format, translated, ...)
        if ok then
            return formatted
        end
    end
    return string.format(source, ...)
end

local numberFormats = {
    deDE = { '.', ',' },
    frFR = { '\194\160', ',' },
    esES = { '.', ',' },
    esMX = { ',', '.' },
    itIT = { '.', ',' },
    ptBR = { '.', ',' },
    ruRU = { '\194\160', ',' },
}

function L.Number(value)
    if issecretvalue and issecretvalue(value) then
        return L['Unknown']
    end
    -- Blizzard's formatter follows the active client's numeric conventions.
    if type(BreakUpLargeNumbers) == 'function' and type(value) == 'number' then
        local ok, formatted = pcall(BreakUpLargeNumbers, value)
        if ok and type(formatted) == 'string' then
            return formatted
        end
    end
    local text = tostring(value)
    local sign, whole, fraction = text:match('^([+-]?)(%d+)%.?(%d*)$')
    if not whole then
        return text
    end
    local format = numberFormats[locale]
    local groupSeparator, decimalSeparator = format and format[1] or ',', format and format[2] or '.'
    local groups = {}
    while #whole > 3 do
        table.insert(groups, 1, whole:sub(-3))
        whole = whole:sub(1, -4)
    end
    table.insert(groups, 1, whole)
    return sign .. table.concat(groups, groupSeparator) .. (fraction ~= '' and decimalSeparator .. fraction or '')
end
