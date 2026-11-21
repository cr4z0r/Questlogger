-- Compile all TOC modules; skip live event registration.
local F = {}
for path in io.lines('Questlogger.toc') do
    if path:match('%.lua$') then
        path = path:gsub('\\', '/')
        local chunk = assert(loadfile(path))
        if path ~= 'Core/Main.lua' then
            chunk('Questlogger', F)
        end
    end
end
return F
