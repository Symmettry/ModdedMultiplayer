LOAD("conn/connection.lua")
MP.load_mod_files("mp")

local mod = MP.mod
assert(mod, "MP.mod is nil")

local thread_path = mod.path .. "conn/http_thread.lua"
local thread_code, err = NFS.read(thread_path)
assert(thread_code, "Failed to read http thread file: " .. tostring(err))

MP.HTTP = MP.HTTP or {
    thread = love.thread.newThread(thread_code),
    out_channel = love.thread.getChannel("modmulti_http_request"),
    in_channel = love.thread.getChannel("modmulti_http_response"),
    started = false,
    pending = {},
    _next_request_id = 0,
}

if not MP.HTTP.started then
    MP.HTTP.thread:start()
    MP.HTTP.started = true
end

MP.SINGLEPLAYER = true

MP.UI = {
    join_code = '',
    status = '',
    selecting_lobby_options = false,
}

MP.CONN = Connection.new()
MP.party_refresh_timer = 0
MP.party_refresh_interval = 1.0

MP.launching_run = false
MP.started_match_id = nil

MP.listeners()