print('[MP] Run registering')

function MP.try_launch_party_run()
    if not (MP and MP.CONN and MP.CONN.party) then return end
    if MP.launching_run then return end

    local state = MP.party_state()

    if state ~= 'RUNNING_TO_BOSS' and state ~= 'BOSS_ACTIVE' then
        return
    end

    local match_id = MP.party_match_id()
    local deck_name = MP.party_deck()
    local stake_value = MP.party_stake()
    local seed = MP.party_seed()

    print('[MP] launch deck=' .. tostring(deck_name) .. ' stake=' .. tostring(stake_value) .. ' seed=' .. tostring(seed))

    if not match_id or not deck_name or stake_value == nil or not seed then
        return
    end

    if MP.started_match_id == match_id then
        return
    end

    MP.started_match_id = match_id
    MP.launching_run = true
    G.SETTINGS.paused = false

    local deck_center = G.P_CENTERS and G.P_CENTERS[deck_name] or nil
    local launch_deck_name = (deck_center and deck_center.name) or deck_name

    print('[MP] launch deck_key=' .. tostring(deck_name) .. ' deck_name=' .. tostring(launch_deck_name) .. ' stake=' .. tostring(stake_value) .. ' seed=' .. tostring(seed))

    if G.STAGE == G.STAGES.MAIN_MENU then
        G:delete_run()
    else
        if G.OVERLAY_MENU then
            G.OVERLAY_MENU:remove()
            G.OVERLAY_MENU = nil
        end
    end

    G:start_run({
        deck = {
            name = launch_deck_name,
            key = deck_name,
        },
        stake = stake_value,
        seed = seed,
    })

    G.GAME.lives = 4
end

function MP.refresh_party_menu()
    if not (MP and MP.CONN and MP.CONN.party_code) then return end
    if MP._refresh_in_flight then return end

    MP._refresh_in_flight = true

    MP.CONN:get_party_state(function(ok, response)
        MP._refresh_in_flight = false

        if not ok then
            MP.UI.status = tostring((response and response.error) or 'Failed to refresh party')
            return
        end

        MP.try_launch_party_run()

        if G.OVERLAY_MENU and not MP.launching_run then
            MP.open_overlay(create_UIBox_online_party_menu())
        end
    end)
end

function MP.force_end_round()
    MP._forced_end_round = true

    print('[MP] Forcing end_round()')

    G.GAME.chips = G.GAME.blind.chips
    G.STATE = G.STATES.HAND_PLAYED
    G.STATE_COMPLETE = true
    end_round()
end

function MP.on_boss_failed_round()
    if not (MP and MP.CONN and G and G.GAME) then return end
    if MP._boss_finish_sent then return end

    MP._boss_finish_sent = true
    local chips = G.GAME.chips or 0
    local hands_used = (G.GAME.current_round and G.GAME.current_round.hands_played) or 0
    local hands_remaining = (G.GAME.current_round and G.GAME.current_round.hands_left) or 0
    local money = G.GAME.dollars or 0
    local ante = (G.GAME.round_resets and G.GAME.round_resets.ante) or 0

    MP.CONN:send_boss_state(
        chips,
        hands_used,
        hands_remaining,
        money,
        true,
        ante,
        function(ok, response)
            if not ok then
                print('[MP] failed to send final boss state: ' .. tostring(response and response.error or response))
            else
                print('[MP] sent final boss state')
            end
        end
    )

    MP.UI.status = 'Waiting for opponent to finish boss'
end

local game_update_ref = Game.update
function Game:update(dt)
    local ret = game_update_ref(self, dt)

    if MP and MP._returning_to_party then
        if G.STAGE == G.STAGES.MAIN_MENU then
            MP._returning_to_party = false
            MP.return_to_party_menu = false
            MP.launching_run = false
            MP.started_match_id = nil

            if G.OVERLAY_MENU then
                G.OVERLAY_MENU:remove()
                G.OVERLAY_MENU = nil
            end

            MP.open_overlay(create_UIBox_online_party_menu())
        end
    end

    if MP and MP.CONN then
        MP.CONN:update(dt)
    end

    if MP and MP.CONN and MP.CONN.party_code then
        MP.try_launch_party_run()

        MP.party_refresh_timer = (MP.party_refresh_timer or 0) + dt
        if MP.party_refresh_timer >= (MP.party_refresh_interval or 1.0) then
            MP.party_refresh_timer = 0

            if G.OVERLAY_MENU and not MP.UI.selecting_lobby_options and not MP.launching_run then
                MP.refresh_party_menu()
            end
        end
    else
        if MP then
            MP.party_refresh_timer = 0
            MP.launching_run = false
            MP.started_match_id = nil
        end
    end

    if MP and not MP.SINGLEPLAYER and G and G.GAME and G.GAME.round_resets and G.GAME.round_resets.ante >= 2 and G.GAME.blind and G.GAME.blind.boss then
        local enemy = MP.my_enemy()
        G.GAME.blind.chip_text = enemy.runtime.scoreFormatted or enemy.runtime.score or "0"
    end

    return ret
end