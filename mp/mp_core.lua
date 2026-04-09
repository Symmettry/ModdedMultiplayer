MP = MP or {}
MP.last_boss_select_e = nil

local function big_from_net(value)
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

function MP.selected_deck_name_from_setup()
    local back =
        G.GAME and (
            G.GAME.viewed_back or
            G.GAME.selected_back
        )

    back = back or G.viewed_back or G.selected_back

    if type(back) == 'table' then
        return back.key or back.original_key or back.name or 'b_red'
    end

    if type(back) == 'string' and back ~= '' then
        return back
    end

    return 'b_red'
end

function MP.selected_stake_from_setup()
    local stake =
        (G.GAME and (G.GAME.stake_key or G.GAME.stake)) or
        G.viewed_stake or
        G.selected_stake

    if type(stake) == 'table' then
        stake = stake.key or stake.original_key or stake.name
    end

    if type(stake) == 'string' then
        stake = stake:gsub("^%s+", ""):gsub("%s+$", "")
        if stake == '' then return 'white' end
    end

    return stake or 'white'
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

    -- todo optimize so that it doesnt :update whenever not in main menu
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

local function mp_capture_setup_and_return_to_party()
    local deck_name = nil
    local stake = nil
    local seed = nil

    -- Galdur / new-model path first
    if Galdur and Galdur.run_setup and Galdur.run_setup.choices then
        local choices = Galdur.run_setup.choices

        local deck_choice = choices.deck
        local stake_choice = choices.stake

        if type(deck_choice) == 'table' then
            deck_name =
                deck_choice.key or
                deck_choice.center_key or
                deck_choice.effect and deck_choice.effect.center and deck_choice.effect.center.key or
                deck_choice.loc_key or
                deck_choice.name
        elseif type(deck_choice) == 'string' then
            deck_name = deck_choice
        end

        if type(stake_choice) == 'table' then
            stake =
                stake_choice.key or
                stake_choice.stake_key or
                stake_choice.id or
                stake_choice.name
        elseif stake_choice ~= nil then
            stake = stake_choice
        end

        seed = choices.seed_select and choices.seed_temp or nil
    end

    -- Fallback to classic setup path
    if not deck_name then
        local back = G.GAME and G.GAME.viewed_back or nil
        if type(back) == 'table' then
            deck_name =
                (back.effect and back.effect.center and back.effect.center.key) or
                back.key or
                back.original_key or
                back.name
        elseif type(back) == 'string' then
            deck_name = back
        end
    end

    if stake == nil then
        stake = G.viewed_stake
        if type(stake) == 'table' then
            stake = stake.key or stake.original_key or stake.name or stake.stake
        end
    end

    if seed == nil then
        seed = G.run_setup_seed
    end

    if type(stake) == 'string' then
        stake = stake:gsub("^%s+", ""):gsub("%s+$", "")
        if stake == '' then stake = nil end
    end

    if not deck_name or stake == nil then
        MP.UI.status = 'Failed to read deck/stake from setup'
    else
        MP.CONN:select_lobby_options(deck_name, stake, function(ok, response)
            if not ok then
                MP.UI.status = tostring((response and response.error) or 'Failed to set deck/stake')
            else
                MP.UI.status = 'Selected ' .. tostring(deck_name) .. ' / Stake ' .. tostring(stake)
            end

            MP.UI.selecting_lobby_options = false
            G.SETTINGS.paused = false

            if G.OVERLAY_MENU then
                G.OVERLAY_MENU:remove()
                G.OVERLAY_MENU = nil
            end

            G.E_MANAGER:add_event(Event({
                trigger = 'after',
                delay = 0.05,
                blockable = false,
                blocking = false,
                func = function()
                    MP.open_overlay(create_UIBox_online_party_menu())
                    return true
                end
            }))
        end)
    end
end

local mp_run_setup_ui_ref = G.UIDEF.run_setup

G.UIDEF.run_setup = function(from_game_over)
    local ui = mp_run_setup_ui_ref(from_game_over)

    if from_game_over == 'online_lobby_select' then
        local function patch_back(node)
            if type(node) ~= 'table' then return end

            if node.config then
                if node.config.back_func == 'exit_overlay_menu' or node.config.back_func == nil then
                    node.config.back_func = 'online_return_to_party_menu'
                end
                node.config.no_back = nil
                node.config.no_esc = nil
            end

            if node.nodes then
                for _, child in ipairs(node.nodes) do
                    patch_back(child)
                end
            end
        end

        patch_back(ui)
    end

    return ui
end

local mp_orig_start_setup_run = G.FUNCS.start_setup_run
G.FUNCS.start_setup_run = function(e)
    if MP and MP.UI and MP.UI.selecting_lobby_options then
        return mp_capture_setup_and_return_to_party()
    end
    if mp_orig_start_setup_run then
        return mp_orig_start_setup_run(e)
    end
end

local mp_orig_quick_start = G.FUNCS.quick_start
G.FUNCS.quick_start = function(e)
    if MP and MP.UI and MP.UI.selecting_lobby_options then
        return mp_capture_setup_and_return_to_party()
    end
    if mp_orig_quick_start then
        return mp_orig_quick_start(e)
    end
end

local mp_orig_deck_select_next = G.FUNCS.deck_select_next
G.FUNCS.deck_select_next = function(e)
    if MP and MP.UI and MP.UI.selecting_lobby_options then
        local current_page = Galdur and Galdur.run_setup and Galdur.run_setup.current_page or nil
        local total_pages = Galdur and Galdur.run_setup and Galdur.run_setup.pages and #Galdur.run_setup.pages or nil

        if current_page and total_pages and current_page >= total_pages then
            return mp_capture_setup_and_return_to_party()
        end
    end

    if mp_orig_deck_select_next then
        return mp_orig_deck_select_next(e)
    end
end

local mp_orig_exit_overlay_menu = G.FUNCS.exit_overlay_menu

G.FUNCS.exit_overlay_menu = function(e)
    if MP and MP.UI and MP.UI.selecting_lobby_options then
        return G.FUNCS.online_return_to_party_menu(e)
    end

    if mp_orig_exit_overlay_menu then
        return mp_orig_exit_overlay_menu(e)
    end
end

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

function MP.force_end_round() 
    MP._forced_end_round = true

    print('[MP] Forcing end_round()')

    G.GAME.chips = G.GAME.blind.chips
    G.STATE = G.STATES.HAND_PLAYED
    G.STATE_COMPLETE = true
    end_round()
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
                print('[MP] Ignoring boss_started while not in BOSS_ACTIVE')
                return
            end

            if not MP.last_boss_select_e then
                print('[MP] No stored boss select event')
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

            print('[MP] Replaying stored boss select')
            _select_blind(MP.last_boss_select_e)
            MP.last_boss_select_e = nil
        end)
    end

    if not MP._match_complete_handler_registered then
        MP._match_complete_handler_registered = true

        MP.CONN:on('match_complete', function(event)
            print('[MP] match_complete received, returning to party menu')

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
            print('[MP] boss_result received')

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

            print('[MP] loser lives now ' .. tostring(data.loserLives))

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

            enemy.runtime.score = big_from_net(data.score)
            enemy.runtime.scoreFormatted = data.scoreFormatted or number_format(enemy.runtime.score) or "0"
            enemy.runtime.handsUsed = tonumber(data.handsUsed) or enemy.runtime.handsUsed or 0
            enemy.runtime.handsRemaining = data.handsRemaining ~= nil and tonumber(data.handsRemaining) or enemy.runtime.handsRemaining
            enemy.runtime.money = big_from_net(data.money)
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