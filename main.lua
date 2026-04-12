MP = MP or {}

local debug = true
function MP.print(...)
    if not debug then return end
    return print("[MP] ", ...)
end

LOAD = function(a) return assert(SMODS.load_file(a))() end
LOAD("load.lua")