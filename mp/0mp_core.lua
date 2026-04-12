MP.print('Core registering')

MP = MP or {}
MP.last_boss_select_e = nil

function MP.big_from_net(value)
    if not value then
        return Big:create(0)
    end

    if Big.is and Big.is(value) then
        return value
    end

    if type(value) == 'table' and value.__talisman and value.array then
        local arr = {}
        for i, v in ipairs(value.array) do
            arr[i] = tonumber(v) or 0
        end

        local sign = tonumber(value.sign) or 1
        return Big:new(arr, sign)
    end

    return Big:create(value)
end

function MP.player_name()
    return tostring((G.SETTINGS and G.SETTINGS.profile) or 'Player')
end

function MP.close_overlay()
    if G.OVERLAY_MENU then
        G.OVERLAY_MENU:remove()
        G.OVERLAY_MENU = nil
    end
end

function MP.open_overlay(definition)
    if MP.UI.selecting_lobby_options then return end
    MP.close_overlay()
    G.OVERLAY_MENU = UIBox{
        definition = definition,
        config = {
            align = 'cm',
            offset = {x = 0, y = 0},
            major = G.ROOM_ATTACH,
            bond = 'Weak'
        }
    }
end

function MP.party_match_key()
    local party = MP.CONN and MP.CONN.party or nil
    if not party then return nil end

    return party.matchId or party.match_id or party.matchCode or party.seed or
           (party.match and (party.match.id or party.match.matchId or party.match.seed))
end

function MP.party_state()
    return MP.CONN and MP.CONN.party and MP.CONN.party.state or nil
end

function MP.party_seed()
    return MP.CONN and MP.CONN.party and MP.CONN.party.seed or nil
end

function MP.party_deck()
    return MP.CONN and MP.CONN.party and MP.CONN.party.config and MP.CONN.party.config.deck or nil
end

function MP.party_stake()
    local stake = MP.CONN and MP.CONN.party and MP.CONN.party.config and MP.CONN.party.config.stake or nil
    if stake == nil then return nil end

    if type(stake) == 'string' then
        stake = stake:gsub("^%s+", ""):gsub("%s+$", "")
        if stake == '' then return nil end
        stake = tonumber(stake)
    end

    if type(stake) ~= 'number' then
        return nil
    end

    return stake
end

function MP.party_match_id()
    return MP.CONN and MP.CONN.party and MP.CONN.party.matchId or nil
end

function MP.is_host()
    local party = MP.CONN and MP.CONN.party
    if not party or not party.players or not MP.CONN.player_id then return false end

    for i, p in ipairs(party.players) do
        if p.playerId == MP.CONN.player_id then
            return i == 1 or p.isHost == true or p.host == true
        end
    end

    return false
end

function MP.my_player()
    local party = MP.CONN and MP.CONN.party
    if not party or not party.players or not MP.CONN.player_id then return nil end

    for _, p in ipairs(party.players) do
        if p.playerId == MP.CONN.player_id then
            return p
        end
    end

    return nil
end

function MP.my_enemy()
    local party = MP.CONN and MP.CONN.party
    if not party or not party.players or not MP.CONN.player_id then return nil end

    for _, p in ipairs(party.players) do
        if p.playerId ~= MP.CONN.player_id then
            return p
        end
    end

    return nil
end