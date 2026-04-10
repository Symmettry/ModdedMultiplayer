MP = MP or {}

local debug = false
function MP.print(value)
    if not debug then return end
    if type(value) == 'table' then
        return print(value)
    end
    return print("[MP] " .. value)
end

LOAD = function(a) assert(SMODS.load_file(a))() end
LOAD("load.lua")