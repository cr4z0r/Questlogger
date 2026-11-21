-- Finds objective entities and maintains the target macro.
local _, addon = ...
local Data = addon.Data
local L = addon.L
local helpers = Data.Helpers
local call = Data.Call
local positive, asTable = helpers.positive, helpers.tab
local database, field = helpers.db, helpers.field

-- Use entity names from the database, not objective descriptions.
function Data.Targets(questID)
    local library = database()
    if not library then
        return {}
    end

    local objectives = asTable(field(library.Quest, 'objectives', questID))
    local targets, seen = {}, {}
    local function addTarget(kind, entityID)
        if not positive(entityID) then
            return
        end
        local name, localized = Data.EntityName(kind, entityID)
        if type(name) ~= 'string' or not name:match('%S') then
            return
        end

        local key = kind .. ':' .. name
        if seen[key] then
            return
        end
        seen[key] = true
        targets[#targets + 1] = {
            kind = kind,
            id = entityID,
            name = name,
            nameUnavailable = kind == 'npc' and not localized,
        }
    end

    for _, objective in ipairs(asTable(objectives[1])) do
        if type(objective) == 'table' then
            addTarget('npc', objective[1])
        end
    end
    for _, objective in ipairs(asTable(objectives[2])) do
        if type(objective) == 'table' then
            addTarget('object', objective[1])
        end
    end
    for _, objective in ipairs(asTable(objectives[3])) do
        if type(objective) == 'table' and positive(objective[1]) then
            for _, entityID in ipairs(asTable(field(library.Item, 'npcDrops', objective[1]))) do
                addTarget('npc', entityID)
            end
            for _, entityID in ipairs(asTable(field(library.Item, 'objectDrops', objective[1]))) do
                addTarget('object', entityID)
            end
        end
    end
    -- Include alternative NPCs that grant kill credit. The root credit ID may
    -- identify a proxy rather than an NPC that the player can actually target.
    for _, objective in ipairs(asTable(objectives[5])) do
        if type(objective) == 'table' then
            for _, entityID in ipairs(asTable(objective[1])) do
                addTarget('npc', entityID)
            end
        end
    end
    return targets
end

-- Keep a single account-wide macro and preserve custom commands.
Data.TargetMacroName = 'Questlogger'
local macroMarker = '# Questlogger objective'
local legacyMarker = '# CIST objective'
local macroLengthLimit = 255

local function targetCommand(target)
    if type(target) ~= 'table' or (target.kind ~= 'npc' and target.kind ~= 'object') then
        return
    end
    if target.nameUnavailable then
        local name, localized = Data.EntityName(target.kind, target.id)
        if not localized or type(name) ~= 'string' then
            return
        end
        target.name, target.nameUnavailable = name, nil
    end
    local name = target.name
    if type(name) ~= 'string' or not name:match('%S') or name:find('[%c|%[%];]') then
        return
    end
    if target.kind == 'npc' then
        return '/targetexact ' .. name
    end
    return '# /targetexact' -- Preserve the slot for the next NPC.
end

function Data.TargetAction(target)
    local command = targetCommand(target)
    if not command then
        if type(target) == 'table' and target.nameUnavailable then
            return nil, L['Localized target name unavailable. Target or mouse over the NPC to learn its name.']
        end
        return
    end
    local text = '/cleartarget' .. (target.kind == 'npc' and ('\n' .. command) or '')
    if #text <= macroLengthLimit then
        return text
    end
end

function Data.TargetMacroBody(target, previousBody)
    local command = targetCommand(target)
    if not command or not Data.TargetAction(target) then
        return
    end

    local body
    if previousBody then
        local changed = false
        -- Replace only the first managed target line, leaving all other lines intact.
        body = previousBody:gsub('[^\r\n]+', function(line)
            local targetLine = line:match('^%s*/targetexact%s+')
                or line:match('^%s*# /targetexact%s*$')
                or line:match('^%s*/targetexact%s*$')
            if not changed and targetLine then
                changed = true
                return (line:match('^%s*') or '') .. command
            end
            return line
        end)
        if not changed then
            body = body .. (body:sub(-1) == '\n' and '' or '\n') .. command
        end
    else
        body = macroMarker .. '\n/cleartarget\n' .. command
    end
    if #body <= macroLengthLimit then
        return body
    end
end

local function ownsMacro(body, marker)
    if type(body) ~= 'string' then
        return false
    end
    for line in body:gmatch('[^\r\n]+') do
        if line == marker then
            return true
        end
    end
    return false
end

local function accountMacroLimit()
    return (Constants and Constants.MacroConsts and Constants.MacroConsts.MAX_ACCOUNT_MACROS)
        or MAX_ACCOUNT_MACROS
        or 120
end

-- Prefer an account macro, even if an old character macro has the same name.
local function findMacro(name, characterOnly)
    local accountCount, characterCount = call(GetNumMacros)
    if type(accountCount) == 'number' and type(characterCount) == 'number' then
        local function scan(firstIndex, lastIndex)
            for index = firstIndex, lastIndex do
                local actualName, icon, body = call(GetMacroInfo, index)
                if actualName == name then
                    return index, icon, body
                end
            end
        end
        if not characterOnly then
            local index, icon, body = scan(1, accountCount)
            if index then
                return index, icon, body
            end
        end
        return scan(accountMacroLimit() + 1, accountMacroLimit() + characterCount)
    end

    local index = call(GetMacroIndexByName, name)
    if positive(index) and (not characterOnly or index > accountMacroLimit()) then
        local actualName, icon, body = call(GetMacroInfo, index)
        if actualName == name then
            return index, icon, body
        end
    end
end

local function backupCharacterMacro(index, previousBody)
    for suffix = 1, 99 do
        local candidate = 'QL old ' .. suffix
        if not findMacro(candidate) then
            call(EditMacro, index, candidate, nil, previousBody)
            if findMacro(candidate, true) then
                return candidate
            end
            return nil
        end
    end
end

function Data.SetTargetMacro(target)
    if not InCombatLockdown or InCombatLockdown() then
        return false, L['Cannot change macros during combat.']
    end
    local action = Data.TargetAction(target)
    if not action then
        if type(target) == 'table' and target.nameUnavailable then
            return false, L['Localized target name unavailable. Target or mouse over the NPC to learn its name.']
        end
        return false, L['Invalid or too long target name.']
    end
    if type(GetMacroIndexByName) ~= 'function' or type(GetMacroInfo) ~= 'function' then
        return false, L['Macro API unavailable.']
    end

    local index, icon, previousBody = findMacro(Data.TargetMacroName)
    local name = Data.TargetMacroName
    if index and not ownsMacro(previousBody, macroMarker) then
        return false, L['A different macro named Questlogger already exists; rename it first.']
    end
    if not index then
        local legacyIndex, legacyIcon, legacyBody = findMacro('CIST Target')
        if legacyIndex and ownsMacro(legacyBody, legacyMarker) then
            index, icon, previousBody, name = legacyIndex, legacyIcon, legacyBody, 'CIST Target'
        end
    end

    local body = Data.TargetMacroBody(target, previousBody)
    if not body then
        return false, L['The updated macro is too long.']
    end
    if name == 'CIST Target' then
        body = body:gsub('[^\r\n]+', function(line)
            return line == legacyMarker and macroMarker or line
        end)
    end

    if index and index <= accountMacroLimit() then
        if name ~= Data.TargetMacroName or previousBody ~= body then
            local updatedName = name ~= Data.TargetMacroName and Data.TargetMacroName or nil
            call(EditMacro, index, updatedName, nil, body)
        end
        local verifiedIndex, _, updatedBody = findMacro(Data.TargetMacroName)
        if verifiedIndex and verifiedIndex <= accountMacroLimit() and updatedBody == body then
            local duplicateIndex, _, duplicateBody = findMacro(Data.TargetMacroName, true)
            if duplicateIndex and ownsMacro(duplicateBody, macroMarker) then
                if backupCharacterMacro(duplicateIndex, duplicateBody) then
                    print(
                        L['Questlogger - General macro is active. Replace the old character macro on your action bar.']
                    )
                end
            end
            return true, nil, body, 'updated'
        end
    else
        -- A character macro cannot safely be moved in place. Keep its old
        -- action-bar slot as a backup until the new account macro is verified.
        local backupName
        if index and name == Data.TargetMacroName then
            backupName = backupCharacterMacro(index, previousBody)
            if not backupName then
                return false, L['Could not rename the old character macro.']
            end
        end
        call(CreateMacro, Data.TargetMacroName, icon or 132212, body, false)
        local verifiedIndex, _, updatedBody = findMacro(Data.TargetMacroName)
        if verifiedIndex and verifiedIndex <= accountMacroLimit() and updatedBody == body then
            if index then
                print(L['Questlogger - General macro created. Replace the old character macro on your action bar.'])
            end
            return true, nil, index and body or action, 'created'
        end

        -- Roll back the character rename if the client refused the new macro.
        if backupName and not findMacro(Data.TargetMacroName) then
            local backupIndex = findMacro(backupName)
            if backupIndex then
                call(EditMacro, backupIndex, Data.TargetMacroName, nil, previousBody)
            end
        end
    end
    return false, L['Could not save Questlogger. Check general macro slots and client restrictions.']
end
