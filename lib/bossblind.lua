SMODS.Atlas{
    key = "mp_blind",
    path = "blind.png",
    px = 34,
    py = 34,
}

SMODS.Blind{
    key = "opponent_blind",
    atlas = "mp_blind",
    pos = { x = 0, y = 0 },

    boss = { min = 2 },
    boss_colour = HEX("4F7CAC"),
    mult = 0,

    loc_txt = {
        name = "Opponent",
        text = { "#1#" }
    },

    calculate = function(self)
        if G.GAME.blind.chips ~= 1 then G.GAME.blind.chips = math.huge end
        
        if not MP or not MP.CONN or not MP.CONN.party then return end
        if MP.party_state and MP.party_state() ~= 'BOSS_ACTIVE' then return end

        local chips = (G.GAME and G.GAME.chips) or 0
        local hands = 0
        local hands_used = 0
        local money = 0
        local ante = 0

        if G.GAME and G.GAME.current_round and G.GAME.current_round.hands_left ~= nil then
            hands = G.GAME.current_round.hands_left
        elseif G.GAME and G.GAME.round_resets and G.GAME.round_resets.hands ~= nil then
            hands = G.GAME.round_resets.hands
        end

        if G.GAME and G.GAME.current_round and G.GAME.current_round.hands_played ~= nil then
            hands_used = G.GAME.current_round.hands_played
        end

        if G.GAME and G.GAME.dollars ~= nil then
            money = G.GAME.dollars
        end

        if G.GAME and G.GAME.round_resets and G.GAME.round_resets.ante ~= nil then
            ante = G.GAME.round_resets.ante
        end

        local done = hands <= 0

        local last = MP.last_sent_boss_state or {}
        local changed =
            chips ~= last.chips
            or hands ~= last.hands
            or hands_used ~= last.hands_used
            or money ~= last.money
            or ante ~= last.ante
            or done ~= last.done

        if changed then
            MP.last_sent_boss_state = {
                chips = chips,
                hands = hands,
                hands_used = hands_used,
                money = money,
                ante = ante,
                done = done,
            }

            local ok, response = MP.CONN:send_boss_state(
                chips,
                hands_used,
                hands,
                money,
                done,
                ante
            )

            if ok and response and response.party then
                MP.CONN.party = response.party
            end
        end
    end,

    in_pool = function(self)
        return G.GAME and G.GAME.round_resets and G.GAME.round_resets.ante >= 2
    end,

    loc_vars = function(self)
        local enemy = MP.my_enemy()
        if G and G.GAME and G.GAME.blind then
            local name = enemy and enemy.name or "Opponent"
            G.GAME.blind.name = name
            G.GAME.blind.loc_name = name
        end
        return {
            vars = {
                (enemy and enemy.runtime.handsRemaining) and ("Hands Remaining: " .. enemy.runtime.handsRemaining) or "Waiting for opponent"
            }
        }
    end,
}
