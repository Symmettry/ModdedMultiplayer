LOAD("conn/connection.lua")
MP.load_mod_files("mp")

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