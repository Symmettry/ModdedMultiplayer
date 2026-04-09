MP = MP or {}

local mod = SMODS.current_mod
MP.mod = mod

LOAD("globals.lua")

assert(SMODS.load_file("config.lua"))()

local function load_mod_files(folder)
    local base_path = mod.path .. folder
    local items = NFS.getDirectoryItems(base_path)

    for _, item in ipairs(items) do
        local full_path = base_path .. "/" .. item
        local relative_path = folder .. "/" .. item
        local info = NFS.getInfo(full_path)

        if info and info.type == "directory" then
            load_mod_files(relative_path)
        elseif info and info.type == "file" and item:match("%.lua$") then
            LOAD(relative_path)
        end
    end
end

load_mod_files("lib")