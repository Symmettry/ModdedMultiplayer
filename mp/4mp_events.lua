MP.print('Events registering')

MP = MP or {}

function MP.set_boss_ready(callback)
    if not (MP and MP.CONN) then
        local err = { error = 'No multiplayer connection' }
        if callback then callback(false, err) end
        return false, err
    end

    local state = MP.party_state and MP.party_state() or nil
    if state ~= 'RUNNING_TO_BOSS' and state ~= 'BOSS_COUNTDOWN' then
        local err = { error = 'Party is not in a boss-ready state' }
        if callback then callback(false, err) end
        return false, err
    end

    local me = MP.my_player and MP.my_player()
    if me and me.bossReady then
        local res = { ok = true, already_ready = true }
        if callback then callback(true, res) end
        return true, res
    end

    MP.CONN:signal_boss_ready(function(ok, response)
        if not ok then
            MP.UI = MP.UI or {}
            MP.UI.status = tostring((response and response.error) or 'Failed to ready for boss')
            if callback then callback(false, response) end
            return
        end

        if response and response.party then
            MP.CONN.party = response.party
        end

        MP.UI = MP.UI or {}
        MP.UI.status = 'Boss readied'

        if G.OVERLAY_MENU and MP.refresh_party_menu then
            MP.refresh_party_menu()
        end

        if callback then callback(true, response) end
    end)
end

local _select_blind = G.FUNCS.select_blind
G.FUNCS.select_blind = function(e)
    local is_boss = false

    if e and e.config and e.config.ref_table then
        local blind = e.config.ref_table
        local boss_key = G.GAME.round_resets.blind_choices.Boss
        is_boss = blind.key == boss_key
    end

    if is_boss
        and MP and not MP.SINGLEPLAYER
        and G and G.GAME and G.GAME.round_resets
        and G.GAME.round_resets.ante >= 2 then

        MP.last_boss_select_e = e
        MP.set_boss_ready()
        return
    end

    return _select_blind(e)
end

function MP.listeners()
    if not MP.CONN then return end

    MP.CONN:on('boss_started', function(event)
        MP._boss_finish_sent = false
    end)

    MP.CONN:on('match_complete', function(event)
        MP._boss_finish_sent = false
    end)

    if not MP._boss_started_handler_registered then
        MP._boss_started_handler_registered = true

        MP.CONN:on('boss_started', function(event)
            if MP.party_state and MP.party_state() ~= 'BOSS_ACTIVE' then
                MP.print('Ignoring boss_started while not in BOSS_ACTIVE')
                return
            end

            if not MP.last_boss_select_e then
                MP.print('No stored boss select event')
                return
            end

            MP.last_sent_boss_state = {
                chips = nil,
                hands = nil,
                hands_used = nil,
                money = nil,
                ante = nil,
                done = nil,
            }

            MP.print('Replaying stored boss select')
            _select_blind(MP.last_boss_select_e)
            MP.last_boss_select_e = nil
        end)
    end

    if not MP._match_complete_handler_registered then
        MP._match_complete_handler_registered = true

        MP.CONN:on('match_complete', function(event)
            MP.print('match_complete received, returning to party menu')

            local me = MP.my_player and MP.my_player()
            if me and me.lives ~= nil and G and G.GAME then
                G.GAME.lives = me.lives
            end

            MP.launching_run = false
            MP.started_match_id = nil
            MP.last_boss_select_e = nil
            MP.return_to_party_menu = true
            MP._returning_to_party = true

            G.SETTINGS.paused = false

            if G.OVERLAY_MENU then
                G.OVERLAY_MENU:remove()
                G.OVERLAY_MENU = nil
            end

            if G.STATE == G.STATES.RUN then
                G:delete_run()
            else
                G.FUNCS.go_to_menu()
            end
        end)
    end

    if not MP._boss_result_handler_registered then
        MP._boss_result_handler_registered = true

        MP.CONN:on('boss_result', function(event)
            MP.print('boss_result received')

            if not event or not event.data then return end
            local data = event.data

            local me = MP.my_player and MP.my_player()
            local enemy = MP.my_enemy and MP.my_enemy()

            if me and data.loserPlayerId == me.playerId then
                me.lives = data.loserLives
            elseif enemy and data.loserPlayerId == enemy.playerId then
                enemy.lives = data.loserLives
            end

            if G and G.GAME and me and me.lives ~= nil then
                G.GAME.lives = me.lives
            end

            MP.print('loser lives now ' .. tostring(data.loserLives))

            G.GAME.blind.chips = 1
            MP.force_end_round()

            MP._boss_state_dirty = true
        end)
    end

    if not MP._boss_state_updated_handler_registered then
        MP._boss_state_updated_handler_registered = true

        MP.CONN:on('boss_state_updated', function(event)
            if not event or not event.data then return end

            local data = event.data
            local enemy = MP.my_enemy and MP.my_enemy()

            if not enemy or data.updateFrom ~= enemy.playerId then return end

            enemy.runtime = enemy.runtime or {}

            enemy.runtime.score = MP.big_from_net(data.score)
            enemy.runtime.scoreFormatted = data.scoreFormatted or number_format(enemy.runtime.score) or "0"
            enemy.runtime.handsUsed = tonumber(data.handsUsed) or enemy.runtime.handsUsed or 0
            enemy.runtime.handsRemaining = data.handsRemaining ~= nil and tonumber(data.handsRemaining) or enemy.runtime.handsRemaining
            enemy.runtime.money = MP.big_from_net(data.money)
            enemy.runtime.moneyFormatted = data.moneyFormatted or number_format(enemy.runtime.money) or "0"
            enemy.runtime.ante = tonumber(data.ante) or enemy.runtime.ante or 0
            enemy.finishedBoss = data.finishedBoss or false

            if G and G.GAME and G.GAME.blind and G.GAME.blind.set_text then
                G.GAME.blind:set_text()
            end

            MP._boss_state_dirty = true
        end)
    end
end