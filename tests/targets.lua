local F = dofile('tests/load.lua')
local D = F.Data
LibQuestieDB = {
    Quest = {
        objectives = function(id)
            if id ~= 1 then
                return {}
            end
            return { [1] = { { 11, 'Kill' }, { 11 }, { 999 } }, [2] = { { 21 } }, [3] = { { 31 } }, [4] = { 10, 100 }, [5] = {
                { { 12, 13 }, 99, 'Credit' },
            } }
        end,
    },
    Npc = {
        name = function(id)
            return ({ [11] = 'Boar', [12] = 'Wolf', [13] = 'Wolf', [14] = 'Bandit', [99] = 'Credit Proxy' })[id]
        end,
    },
    Object = {
        name = function(id)
            return ({ [21] = 'Crate', [22] = 'Chest' })[id]
        end,
    },
    Item = {
        npcDrops = function()
            return { 11, 14 }
        end,
        objectDrops = function()
            return { 21, 22 }
        end,
    },
}
local targets = D.Targets(1)
assert(#targets == 5 and #D.Targets(2) == 0)
assert(
    targets[1].name == 'Boar'
        and targets[2].name == 'Crate'
        and targets[3].name == 'Bandit'
        and targets[4].name == 'Chest'
        and targets[5].name == 'Wolf'
)
assert(D.TargetMacroBody(targets[1]) == '# Questlogger objective\n/cleartarget\n/targetexact Boar')
assert(D.TargetAction(targets[2]) == '/cleartarget')
assert(not D.TargetMacroBody({ kind = 'npc', name = 'Boar\n/run test' }))
assert(not D.TargetMacroBody({ kind = 'npc', name = '[help]' }))
assert(not D.TargetMacroBody({ kind = 'npc', name = string.rep('a', 250) }))
local combat, creates, edits = false, 0, 0
local slots = {}
MAX_ACCOUNT_MACROS = 120
InCombatLockdown = function()
    return combat
end
GetMacroIndexByName = function(name)
    for i, m in pairs(slots) do
        if m.name == name then
            return i
        end
    end
    return 0
end
GetMacroInfo = function(i)
    local m = slots[i]
    if m then
        return m.name, m.icon, m.body
    end
end
CreateMacro = function(name, icon, body, character)
    assert(character == false)
    creates = creates + 1
    slots[1] = { name = name, icon = icon, body = body }
    return 1
end
EditMacro = function(i, name, icon, body)
    local m = assert(slots[i])
    m.name = name or m.name
    m.icon = icon or m.icon
    m.body = body or m.body
    edits = edits + 1
    return i
end
local ok, err, execute, status = D.SetTargetMacro(targets[1])
assert(status == 'created' and ok and creates == 1 and edits == 0 and execute == '/cleartarget\n/targetexact Boar')
assert(D.SetTargetMacro(targets[1]) and edits == 0)
slots[1].body = slots[1].body .. '\n/say hello\n# note\n'
local old = slots[1].body
ok, err, execute, status = D.SetTargetMacro(targets[5])
assert(
    status == 'updated'
        and ok
        and edits == 1
        and slots[1].body == old:gsub('/targetexact Boar', '/targetexact Wolf')
        and execute == slots[1].body
)
assert(D.SetTargetMacro(targets[2]) and edits == 2 and slots[1].body:find('# /targetexact', 1, true))
assert(D.SetTargetMacro(targets[1]) and slots[1].body == old)
combat = true
assert(not D.SetTargetMacro(targets[1]))
combat = false
slots[1].body = '/say My own macro'
assert(not D.SetTargetMacro(targets[1]) and slots[1].body == '/say My own macro')
-- Preserve the old action-bar macro, migrate to an account slot, and preserve custom lines.
slots = {
    [121] = {
        name = 'Questlogger',
        icon = 999,
        body = '# Questlogger objective\n# Boar\n/cleartarget\n/targetexact Boar\n/say hello',
    },
}
assert(
    D.SetTargetMacro(targets[5])
        and slots[1].name == 'Questlogger'
        and slots[1].icon == 999
        and slots[121].name == 'QL old 1'
        and slots[1].body:find('/say hello', 1, true)
)
assert(slots[121].body:find('/targetexact Boar', 1, true))
slots =
    { [121] = { name = 'Questlogger', icon = 999, body = '# Questlogger objective\n/cleartarget\n/targetexact Boar' } }
local create = CreateMacro
CreateMacro = function()
    error('No slots')
end
assert(
    not D.SetTargetMacro(targets[5])
        and slots[121].name == 'Questlogger'
        and slots[121].body:find('/targetexact Boar', 1, true)
)
CreateMacro = create
slots = { [2] = { name = 'CIST Target', icon = 999, body = '# CIST objective\n/cleartarget\n/targetexact Boar' } }
assert(
    D.SetTargetMacro(targets[5])
        and slots[2].name == 'Questlogger'
        and slots[2].body:find('# Questlogger objective', 1, true)
)
slots = { [121] = { name = 'CIST Target', icon = 999, body = '/say personal macro' } }
assert(D.SetTargetMacro(targets[1]) and slots[121].body == '/say personal macro')
print('Target discovery, general macro creation, line preservation, migration and rollback passed.')
slots = {
    [1] = { name = 'Questlogger', icon = 999, body = '#showtooltip\n# Questlogger objective\n/cleartarget\n/targetexact Boar' },
    [121] = { name = 'Questlogger', icon = 999, body = '# Questlogger objective\n/cleartarget\n/targetexact Crate' },
}
GetNumMacros = function()
    return 1, 1
end
assert(
    D.SetTargetMacro(targets[5])
        and slots[1].body == '#showtooltip\n# Questlogger objective\n/cleartarget\n/targetexact Wolf'
        and slots[121].name == 'QL old 1'
)
assert(D.SetTargetMacro(targets[1]) and slots[1].body:find('/targetexact Boar', 1, true))
print('Cross-character duplicate macro and custom leading line tests passed.')
