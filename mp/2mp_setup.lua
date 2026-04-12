MP.print('Setup registering')

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

local function mp_capture_setup_and_return_to_party()
    local deck_name = nil
    local stake = nil
    local seed = nil

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
                local selected_deck, selected_stake = MP.get_localized_stakedeck(deck_name, stake)
                MP.UI.status = 'Selected ' .. tostring(selected_deck) .. ' / ' .. tostring(selected_stake)
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
                    MP.open_overlay(create_UIBox_online_party_menu("selected lobby options"))
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

G.FUNCS.online_return_to_party_menu = function()
    MP.UI.selecting_lobby_options = false
    G.SETTINGS.paused = false

    if G.OVERLAY_MENU then
        G.OVERLAY_MENU:remove()
        G.OVERLAY_MENU = nil
    end

    MP.open_overlay(create_UIBox_online_party_menu("return to party menu 2"))
end