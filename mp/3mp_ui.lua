MP.print('UI registering')

MP = MP or {}

function MP.party_players_nodes()
    local nodes = {}

    local party = MP.CONN and MP.CONN.party
    local players = party and party.players or {}

    if not players or #players == 0 then
        nodes[#nodes+1] = {n=G.UIT.R, config={align="cm", padding=0.04}, nodes={
            {n=G.UIT.T, config={text = "No players yet", scale = 0.35, colour = G.C.UI.TEXT_LIGHT, shadow = true}}
        }}
        return nodes
    end

    for i, p in ipairs(players) do
        local label = tostring(p.name or p.playerId or "Unknown")
        if i == 1 or p.isHost == true or p.host == true then
            label = label .. "  [HOST]"
        end
        if p.ready ~= nil then
            label = label .. (p.ready and "  [READY]" or "  [NOT READY]")
        end

        nodes[#nodes+1] = {n=G.UIT.R, config={align="cm", padding=0.04}, nodes={
            {n=G.UIT.C, config={align="cm", minw=5.2, padding=0.08, r=0.08, colour=G.C.BLACK, emboss=0.05}, nodes={
                {n=G.UIT.T, config={text = label, scale = 0.34, colour = G.C.WHITE, shadow = true}}
            }}
        }}
    end

    return nodes
end

G.FUNCS.online_copy_party_code = function()
    local party = MP.CONN and MP.CONN.party
    local code = (party and party.code) or MP.CONN.party_code or ""

    if love and love.system and love.system.setClipboardText then
        love.system.setClipboardText(code)
        MP.UI.status = "Copied code!"
    else
        MP.UI.status = "Clipboard not supported"
    end

    MP.open_overlay(create_UIBox_online_party_menu())
end

function create_UIBox_online_party_menu()
    MP.SINGLEPLAYER = false

    local party = MP.CONN and MP.CONN.party or nil
    local code = (party and party.code) or MP.CONN.party_code or "----"
    local state = (party and party.state) or "LOBBY"
    local is_host = MP.is_host()
    local me = MP.my_player()

    local contents = {
        {n=G.UIT.R, config={align="cm", padding=0.10}, nodes={
            {n=G.UIT.O, config={object = DynaText({
                string = {"PARTY"},
                colours = {G.C.PURPLE},
                shadow = true,
                float = true,
                scale = 0.65,
                maxw = 5.5
            })}}
        }},
        {n=G.UIT.R, config={align="cm", padding=0.04}, nodes={
            UIBox_button{
                id = 'online_copy_code_btn',
                button = 'online_copy_party_code',
                colour = G.C.BLUE,
                minw = 3.0,
                minh = 0.6,
                label = {tostring(code)},
                scale = 0.35,
                col = true
            }
        }},
        {n=G.UIT.R, config={align="cm", padding=0.04}, nodes={
            {n=G.UIT.T, config={text = "STATE: " .. tostring(state), scale = 0.32, colour = G.C.UI.TEXT_LIGHT, shadow = true}}
        }},
    }

    local selected_deck = (party and party.config and party.config.deck) or '(unset)'
    local selected_stake = (party and party.config and party.config.stake) or '(unset)'

    contents[#contents+1] = {n=G.UIT.R, config={align="cm", padding=0.03}, nodes={
        {n=G.UIT.T, config={text = "DECK: " .. tostring(selected_deck), scale = 0.30, colour = G.C.UI.TEXT_LIGHT, shadow = true}}
    }}
    contents[#contents+1] = {n=G.UIT.R, config={align="cm", padding=0.03}, nodes={
        {n=G.UIT.T, config={text = "STAKE: " .. tostring(selected_stake), scale = 0.30, colour = G.C.UI.TEXT_LIGHT, shadow = true}}
    }}

    local player_nodes = MP.party_players_nodes()
    for _, node in ipairs(player_nodes) do
        contents[#contents+1] = node
    end

    if state == 'LOBBY' then
        if is_host then
            contents[#contents+1] = {n=G.UIT.R, config={align="cm", padding=0.12}, nodes={
                UIBox_button{
                    id = 'online_select_lobby_btn',
                    button = 'online_select_lobby_options',
                    colour = G.C.BLUE,
                    minw = 3.4,
                    minh = 0.9,
                    label = {'DECK / STAKE'},
                    scale = 0.38,
                    col = true
                },
                {n=G.UIT.C, config={minw=0.20}, nodes={}},
                UIBox_button{
                    id = 'online_start_match_btn',
                    button = 'online_start_match',
                    colour = G.C.GREEN,
                    minw = 2.8,
                    minh = 0.9,
                    label = {'PLAY'},
                    scale = 0.42,
                    col = true
                },
                {n=G.UIT.C, config={minw=0.20}, nodes={}},
                UIBox_button{
                    id = 'online_leave_party_btn',
                    button = 'online_leave_party',
                    colour = G.C.RED,
                    minw = 3.2,
                    minh = 0.9,
                    label = {'LEAVE PARTY'},
                    scale = 0.38,
                    col = true
                }
            }}
        else
            local ready_label = (me and me.ready) and 'UNREADY' or 'READY'
            local ready_colour = (me and me.ready) and G.C.ORANGE or G.C.BLUE

            contents[#contents+1] = {n=G.UIT.R, config={align="cm", padding=0.12}, nodes={
                UIBox_button{
                    id = 'online_toggle_ready_btn',
                    button = 'online_toggle_ready',
                    colour = ready_colour,
                    minw = 3.8,
                    minh = 0.9,
                    label = {ready_label},
                    scale = 0.42,
                    col = true
                },
                {n=G.UIT.C, config={minw=0.25}, nodes={}},
                UIBox_button{
                    id = 'online_leave_party_btn',
                    button = 'online_leave_party',
                    colour = G.C.RED,
                    minw = 3.8,
                    minh = 0.9,
                    label = {'LEAVE PARTY'},
                    scale = 0.42,
                    col = true
                }
            }}
        end
    else
        contents[#contents+1] = {n=G.UIT.R, config={align="cm", padding=0.12}, nodes={
            UIBox_button{
                id = 'online_leave_party_btn',
                button = 'online_leave_party',
                colour = G.C.RED,
                minw = 4.2,
                minh = 0.9,
                label = {'LEAVE PARTY'},
                scale = 0.42,
                col = true
            }
        }}
    end

    if MP.UI.status ~= '' then
        contents[#contents+1] = {n=G.UIT.R, config={align="cm", padding=0.08}, nodes={
            {n=G.UIT.T, config={text = MP.UI.status, scale = 0.30, colour = G.C.RED, shadow = true}}
        }}
    end

    return create_UIBox_generic_options({
        back_func = 'online_leave_party',
        contents = contents
    })
end

function create_UIBox_online_menu()
    return create_UIBox_generic_options({
        back_func = 'exit_overlay_menu',
        contents = {
            {n=G.UIT.R, config={align="cm", padding=0.10}, nodes={
                {n=G.UIT.O, config={object = DynaText({
                    string = {"ONLINE"},
                    colours = {G.C.PURPLE},
                    shadow = true,
                    float = true,
                    scale = 0.7,
                    maxw = 5.5
                })}}
            }},
            {n=G.UIT.R, config={align="cm", padding=0.08}, nodes={
                {n=G.UIT.T, config={text = "Choose an online action", scale = 0.34, colour = G.C.UI.TEXT_LIGHT, shadow = true}}
            }},
            {n=G.UIT.R, config={align="cm", padding=0.12}, nodes={
                UIBox_button{
                    id = 'online_join_party_btn',
                    button = 'online_open_join_party',
                    colour = G.C.BLUE,
                    minw = 4.8,
                    minh = 0.9,
                    label = {'JOIN PARTY'},
                    scale = 0.45,
                    col = true,
                    focus_args = {snap_to = true}
                }
            }},
            {n=G.UIT.R, config={align="cm", padding=0.08}, nodes={
                UIBox_button{
                    id = 'online_create_party_btn',
                    button = 'online_create_party',
                    colour = G.C.PURPLE,
                    minw = 4.8,
                    minh = 0.9,
                    label = {'CREATE PARTY'},
                    scale = 0.45,
                    col = true
                }
            }},
            MP.UI.status ~= '' and {n=G.UIT.R, config={align="cm", padding=0.08}, nodes={
                {n=G.UIT.T, config={text = MP.UI.status, scale = 0.30, colour = G.C.RED, shadow = true}}
            }} or nil,
        }
    })
end

function create_UIBox_online_join_party_menu()
    return create_UIBox_generic_options({
        back_func = 'open_online_menu',
        contents = {
            {n=G.UIT.R, config={align="cm", padding=0.10}, nodes={
                {n=G.UIT.O, config={object = DynaText({
                    string = {"JOIN PARTY"},
                    colours = {G.C.BLUE},
                    shadow = true,
                    float = true,
                    scale = 0.6,
                    maxw = 5.5
                })}}
            }},
            {n=G.UIT.R, config={align="cm", padding=0.06}, nodes={
                {n=G.UIT.T, config={text = "Enter a party code", scale = 0.34, colour = G.C.UI.TEXT_LIGHT, shadow = true}}
            }},
            {n=G.UIT.R, config={align="cm", padding=0.10}, nodes={
                create_text_input({
                    id = 'online_join_code_input',
                    prompt_text = 'Party Code',
                    ref_table = MP.UI,
                    ref_value = 'join_code',
                    w = 4.2,
                    h = 0.8,
                    text_scale = 0.45,
                    max_length = 12,
                    all_caps = true,
                    extended_corpus = false
                })
            }},
            {n=G.UIT.R, config={align="cm", padding=0.10}, nodes={
                UIBox_button{
                    id = 'online_submit_join_btn',
                    button = 'online_submit_join_party',
                    colour = G.C.BLUE,
                    minw = 4.2,
                    minh = 0.9,
                    label = {'JOIN'},
                    scale = 0.45,
                    col = true,
                    focus_args = {snap_to = true}
                }
            }},
            MP.UI.status ~= '' and {n=G.UIT.R, config={align="cm", padding=0.08}, nodes={
                {n=G.UIT.T, config={text = MP.UI.status, scale = 0.30, colour = G.C.RED, shadow = true}}
            }} or nil,
        }
    })
end

G.FUNCS.open_online_menu = function()
    MP.UI.status = ''
    MP.open_overlay(create_UIBox_online_menu())
    G.CONTROLLER:snap_to{node = G.OVERLAY_MENU:get_UIE_by_ID('online_join_party_btn')}
end

G.FUNCS.online_open_join_party = function()
    MP.UI.status = ''
    MP.UI.join_code = MP.UI.join_code or ''
    MP.open_overlay(create_UIBox_online_join_party_menu())
    G.CONTROLLER:snap_to{node = G.OVERLAY_MENU:get_UIE_by_ID('online_submit_join_btn')}
end

G.FUNCS.online_submit_join_party = function()
    MP.UI.status = ''

    local code = tostring(MP.UI.join_code or ''):upper():gsub("%s+", "")
    if code == '' then
        MP.UI.status = 'Enter a party code'
        MP.open_overlay(create_UIBox_online_join_party_menu())
        return
    end

    MP.CONN:join_party(code, MP.player_name(), function(ok, response)
        if not ok then
            MP.UI.status = tostring((response and response.error) or 'Failed to join party')
            MP.open_overlay(create_UIBox_online_join_party_menu())
            return
        end

        MP.UI.status = 'Joined party'
        MP.open_overlay(create_UIBox_online_party_menu())
    end)
end

G.FUNCS.online_create_party = function()
    MP.UI.status = ''

    MP.CONN:create_party(MP.player_name(), function(ok, response)
        if not ok then
            MP.UI.status = tostring((response and response.error) or 'Failed to create party')
            MP.open_overlay(create_UIBox_online_menu())
            return
        end

        MP.CONN:set_ready(true, function(ready_ok, ready_response)
            if not ready_ok then
                MP.UI.status = tostring((ready_response and ready_response.error) or 'Party created, but failed to auto-ready host')
            else
                MP.UI.status = 'Created party'
            end

            MP.open_overlay(create_UIBox_online_party_menu())
        end)
    end)
end

G.FUNCS.online_leave_party = function()
    MP.UI.status = ''

    MP.CONN:leave_party(function(ok, response)
        if not ok then
            MP.UI.status = tostring((response and response.error) or 'Failed to leave party')
        end

        MP.UI.selecting_lobby_options = false
        MP.launching_run = false
        MP.started_match_id = nil
        G.SETTINGS.paused = false

        if G.OVERLAY_MENU then
            G.OVERLAY_MENU:remove()
            G.OVERLAY_MENU = nil
        end

        MP.open_overlay(create_UIBox_online_menu())
    end)
end

G.FUNCS.online_start_match = function()
    MP.UI.status = ''

    MP.CONN:start_match(function(ok, response)
        if not ok then
            MP.UI.status = tostring((response and response.error) or 'Failed to start match')
            MP.open_overlay(create_UIBox_online_party_menu())
            return
        end

        MP.UI.status = 'Starting match'

        MP.try_launch_party_run()

        if not MP.launching_run then
            MP.open_overlay(create_UIBox_online_party_menu())
        end
    end)
end

G.FUNCS.online_select_lobby_options = function()
    MP.UI.status = ''
    MP.UI.selecting_lobby_options = true

    if G.OVERLAY_MENU then
        G.OVERLAY_MENU:remove()
        G.OVERLAY_MENU = nil
    end

    G.FUNCS.setup_run({config = {id = 'online_lobby_select'}})
end

G.FUNCS.online_toggle_ready = function()
    MP.UI.status = ''

    local me = MP.my_player()
    local new_ready = not (me and me.ready)

    MP.CONN:set_ready(new_ready, function(ok, response)
        if not ok then
            MP.UI.status = tostring((response and response.error) or 'Failed to update ready state')
        else
            MP.UI.status = new_ready and 'Ready' or 'Not ready'
        end

        MP.open_overlay(create_UIBox_online_party_menu())
    end)
end

local _create_UIBox_HUD = create_UIBox_HUD

local function find_node_by_id(node, id)
    if type(node) ~= "table" then return nil end
    if node.config and node.config.id == id then return node end
    if node.nodes then
        for _, child in ipairs(node.nodes) do
            local found = find_node_by_id(child, id)
            if found then return found end
        end
    end
    return nil
end

local function row_contains_id(row, id)
    return find_node_by_id(row, id) ~= nil
end

local function make_spacing_row(spacing)
    return {n = G.UIT.R, config = {minh = spacing}, nodes = {}}
end

local function make_spacing_col(spacing)
    return {n = G.UIT.C, config = {minw = spacing}, nodes = {}}
end

local function make_lives_tile(scale, temp_col, temp_col2)
    return {
        n = G.UIT.C,
        config = {
            id = 'hud_lives',
            align = "cm",
            padding = 0.05,
            minw = 1.45,
            minh = 1,
            colour = temp_col,
            emboss = 0.05,
            r = 0.1
        },
        nodes = {
            {
                n = G.UIT.R,
                config = {align = "cm", minh = 0.33, maxw = 1.35},
                nodes = {
                    {n = G.UIT.T, config = {
                        text = 'Lives',
                        scale = 0.85 * scale,
                        colour = G.C.UI.TEXT_LIGHT,
                        shadow = true
                    }},
                }
            },
            {
                n = G.UIT.R,
                config = {align = "cm", r = 0.1, minw = 1.2, colour = temp_col2},
                nodes = {
                    {n = G.UIT.O, config = {
                        id = 'lives_UI_count',
                        object = DynaText({
                            string = {{ref_table = G.GAME, ref_value = 'lives'}},
                            colours = {G.C.RED},
                            shadow = true,
                            font = G.LANGUAGES['en-us'].font,
                            scale = 2 * scale
                        })
                    }},
                }
            }
        }
    }
end

local function make_lives_row(scale, spacing, temp_col, temp_col2)
    return {
        n = G.UIT.R,
        config = {align = "cm"},
        nodes = {
            make_lives_tile(scale, temp_col, temp_col2)
        }
    }
end

create_UIBox_HUD = function()
    local hud = _create_UIBox_HUD()
    if not hud or MP.SINGLEPLAYER then return hud end

    local scale = 0.4
    local spacing = 0.13
    local temp_col = G.C.DYN_UI.BOSS_MAIN
    local temp_col2 = G.C.DYN_UI.BOSS_DARK

    local row_round = find_node_by_id(hud, 'row_round')
    if not row_round or not row_round.nodes or not row_round.nodes[1] or not row_round.nodes[1].nodes then
        return hud
    end

    local round_nodes = row_round.nodes[1].nodes

    for _, row in ipairs(round_nodes) do
        if row_contains_id(row, 'hud_lives') then
            return hud
        end
    end

    local tension_index = nil
    for i, row in ipairs(round_nodes) do
        if row_contains_id(row, 'hud_tension') then
            tension_index = i
            break
        end
    end

    if not tension_index then
        return hud
    end

    if Jen ~= nil then
        local tension_row = round_nodes[tension_index]
        local relief_index = nil

        for i, child in ipairs(tension_row.nodes or {}) do
            if row_contains_id(child, 'hud_relief') then
                relief_index = i
                break
            end
        end

        if relief_index then
            table.insert(tension_row.nodes, relief_index, make_spacing_col(spacing))
            table.insert(tension_row.nodes, relief_index, make_lives_tile(scale, temp_col, temp_col2))
        else
            table.insert(tension_row.nodes, make_spacing_col(spacing))
            table.insert(tension_row.nodes, make_lives_tile(scale, temp_col, temp_col2))
        end
    else
        table.insert(round_nodes, tension_index, make_spacing_row(spacing))
        table.insert(round_nodes, tension_index + 1, make_lives_row(scale, spacing, temp_col, temp_col2))
    end

    return hud
end

local _buttons_UI = create_UIBox_buttons
function create_UIBox_buttons()
    if MP and not MP.SINGLEPLAYER and G.GAME.current_round.hands_left <= 0 then
        return {}
    end
    return _buttons_UI()
end