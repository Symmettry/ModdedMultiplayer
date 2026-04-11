local http = require('socket.http')
local ltn12 = require('ltn12')
local json = require('json')
local Socket = LOAD("conn/socket.lua")

Connection = {}
Connection.__index = Connection

local function big_to_net(value)
    local big = to_big(value)
    local raw = big:as_table()

    local dense = {}
    local max_i = 0

    for i, v in pairs(raw.array or {}) do
        if type(i) == 'number' and i > max_i then
            max_i = i
        end
    end

    for i = 1, max_i do
        dense[i] = tonumber(raw.array[i]) or 0
    end

    return {
        array = dense,
        sign = tonumber(raw.sign) or 1,
        val = tonumber(raw.val) or 0,
        __talisman = true,
    }
end

local function http_base()
    return MP.mod.config.server or "http://127.0.0.1:3001"
end
local function ws_base()
    return MP.mod.config.wsserver or "ws://127.0.0.1:3001"
end

local DEFAULTS = {
    lobby_poll_interval = 1.0,
    boss_wait_poll_interval = 0.75,
    boss_active_poll_interval = 0.5,
    match_complete_poll_interval = 2.0,
    request_timeout = 5,
}

local function deepcopy(tbl)
    if type(tbl) ~= 'table' then return tbl end
    local out = {}
    for k, v in pairs(tbl) do
        out[k] = deepcopy(v)
    end
    return out
end

local function merge_defaults(opts)
    local merged = deepcopy(DEFAULTS)
    opts = opts or {}
    for k, v in pairs(opts) do
        merged[k] = v
    end
    return merged
end

local function encode_body(tbl)
    return json.encode(tbl or {})
end

local function decode_body(body)
    if not body or body == '' then
        return nil
    end

    local ok, decoded = pcall(json.decode, body)
    if ok then
        return decoded
    end

    return nil
end

local function normalize_party_code(code)
    if not code then return nil end
    return tostring(code):upper()
end

local function safe_call(fn, ...)
    local ok, result1, result2, result3 = pcall(fn, ...)
    if not ok then
        return false, result1
    end
    return true, result1, result2, result3
end

local function get_time()
    if love and love.timer and love.timer.getTime then
        return love.timer.getTime()
    end
    return os.time()
end

local function to_big(value)
    if Big and Big.is and Big.is(value) then
        return value
    end
    return Big:create(value or 0)
end

function Connection.new(opts)
    local self = setmetatable({}, Connection)

    self.config = merge_defaults(opts)
    self.player_id = nil
    self.player_token = nil
    self.party_code = nil
    self.party = nil
    self.ws = nil
    self.cache = {}

    self.last_event_id = 0
    self.last_poll_at = 0
    self.handlers = {
        error = {},
        party_updated = {},
        match_started = {},
        boss_started = {},
        boss_state_updated = {},
        boss_result = {},
        next_boss_ready = {},
        match_complete = {},
        raw_event = {},
        poll = {},
    }

    return self
end

function Connection:on(event_name, handler)
    if not self.handlers[event_name] then
        self.handlers[event_name] = {}
    end
    table.insert(self.handlers[event_name], handler)
end

function Connection:emit(event_name, payload)
    if event_name ~= "poll" then
        MP.print('Received event ' .. event_name .. ' with value')
        MP.print(payload)
    end

    local handlers = self.handlers[event_name]
    if not handlers then return end

    for _, handler in ipairs(handlers) do
        local ok, err = pcall(handler, payload, self)
        if not ok then
            MP.print('[Connection] handler error for event ' .. tostring(event_name) .. ': ' .. tostring(err))
        end
    end
end

local function next_request_id()
    MP.HTTP._next_request_id = (MP.HTTP._next_request_id or 0) + 1
    return MP.HTTP._next_request_id
end
function Connection:_request(method, path, body, callback)
    local request_id = next_request_id()
    local body_string = method == 'GET' and nil or encode_body(body)

    MP.HTTP.pending = MP.HTTP.pending or {}

    MP.HTTP.pending[request_id] = {
        callback = callback,
        method = method,
        path = path,
    }

    local headers = nil
    if method ~= 'GET' then
        headers = {
            ["Content-Type"] = "application/json",
            ["Content-Length"] = tostring(#body_string),
        }
    end

    MP.HTTP.out_channel:push({
        type = "request",
        requestId = request_id,
        url = http_base() .. path,
        method = method,
        headers = headers,
        body = body_string,
        timeout = self.config.request_timeout,
    })

    return request_id
end

function Connection:cached(key, ability)
    if not key then
        return nil
    end

    local queue = self.cache[key]
    if queue and #queue > 0 then
        local value = table.remove(queue, 1)
        if #queue == 0 then
            self.cache[key] = nil
        end
        return value
    end

    if not self.party_code or not self.player_id or not self.player_token then
        return nil
    end

    local encoded_key = tostring(key):gsub("([^%w%-_%.~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
    self:_request(
        'POST',
        '/party/' .. tostring(self.party_code) .. '/cache'
            .. '?playerId=' .. tostring(self.player_id)
            .. '&playerToken=' .. tostring(self.player_token)
            .. '&key=' .. tostring(encoded_key),
        ability,
        function(ok, response)
            if not ok then
                self:emit('error', response)
            end
        end
    )

    return nil
end
function Connection:push_cached(key, ability)
    if not key or ability == nil then
        return
    end

    self.cache[key] = self.cache[key] or {}
    table.insert(self.cache[key], ability)
end

function Connection:_process_http_responses()
    MP.HTTP.pending = MP.HTTP.pending or {}

    while true do
        local response = MP.HTTP.in_channel:pop()
        if not response then
            break
        end

        local pending = MP.HTTP.pending[response.requestId]
        MP.HTTP.pending[response.requestId] = nil

        if pending and pending.callback then
            local ok_result
            local payload

            if response.ok and tonumber(response.status_code) and tonumber(response.status_code) >= 200 and tonumber(response.status_code) < 300 then
                ok_result = true
                payload = decode_body(response.body) or {}
            else
                local decoded = decode_body(response.body) or {}
                ok_result = false
                payload = {
                    status_code = response.status_code,
                    headers = response.headers or {},
                    status_line = response.status_line or '',
                    body = decoded,
                    error = response.error or decoded.error or ('HTTP ' .. tostring(response.status_code)),
                }
            end

            local ok, err = pcall(pending.callback, ok_result, payload, response)
            if not ok then
                MP.print('[Connection] HTTP callback error: ' .. tostring(err))
            end
        end
    end
end

function Connection:_auth_body(extra)
    local body = extra or {}
    body.partyCode = self.party_code
    body.playerId = self.player_id
    body.playerToken = self.player_token
    return body
end

function Connection:_auth_query()
    if not self.party_code or not self.player_id or not self.player_token then
        return ''
    end

    return '?playerId=' .. tostring(self.player_id) .. '&playerToken=' .. tostring(self.player_token)
end

local function get_all_mods()
    local result = {}
    local seen = {}

    local function add(mod)
        if mod and mod.can_load and not seen[mod.id] then
            seen[mod.id] = true
            result[#result + 1] = mod.id
        end
    end

    for _, mod in pairs(SMODS.Mods) do
        add(mod)
    end

    for _, providers in pairs(SMODS.provided_mods) do
        for _, v in ipairs(providers) do
            add(v.mod)
        end
    end

    return result
end

function MP.update_ws() end
function Connection:init_socket(callback)
    local ws = Socket.connect(MP.mod, "ws://localhost:3001")
    local _self = self

    self.ws = ws

    MP.update_ws = function()
        ws:update()
    end

    ws:on("error", function(self, ev)
        MP.print("[ws] error", ev.message)
    end)

    ws:on("open", function(self, ev)
        ws:send(
            'init{"party":"' .. _self.party_code ..
            '","player_id":"' .. _self.player_id ..
            '","player_token":"' .. _self.player_token .. '"}'
        )
    end)

    ws:on("message", function(self, ev)
        local text = ev.data or ev

        if not text then return end

        local start = string.find(text, "{", 1, true)
        if not start then
            MP.print("[ws] invalid message:", text)
            return
        end

        local key = string.sub(text, 1, start - 1)
        local json_str = string.sub(text, start)

        local ok, data = pcall(function()
            return JSON.decode(json_str)
        end)

        if not ok then
            MP.print("[ws] json parse error:", json_str)
            return
        end

        if key == "init" then
            local success = data.success == true
            if callback then
                callback(success, data)
            end
            return
        end

        MP.print("[ws] unhandled message:", key)
    end)

    function MP.update_ws()
        ws:update()
    end
end

function Connection:create_party(name, callback)
    self:_request('POST', '/party/create', {
        name = name,
        mods = get_all_mods(),
    }, function(ok, response)
        if not ok then
            self:emit('error', response)
            if callback then callback(false, response) end
            return
        end

        self.player_id = response.playerId
        self.player_token = response.playerToken
        self.party_code = response.partyCode
        self.party = response.party
        self.cache = {}
        self.last_event_id = response.party and response.party.lastEventId or 0

        self:init_socket(callback)
    end)
end

function Connection:join_party(party_code, name, callback)
    self:_request('POST', '/party/join', {
        partyCode = normalize_party_code(party_code),
        name = name,
        mods = get_all_mods(),
    }, function(ok, response)
        if not ok then
            self:emit('error', response)
            if callback then callback(false, response) end
            return
        end

        self.player_id = response.playerId
        self.player_token = response.playerToken
        self.party_code = response.partyCode
        self.party = response.party
        self.last_event_id = response.party and response.party.lastEventId or 0

        if callback then callback(true, response) end
    end)
end

function Connection:select_lobby_options(deck, stake, callback)
    if not self.party_code or not self.player_id or not self.player_token then
        local err = { error = 'Not in a party' }
        if callback then callback(false, err) end
        return false, err
    end

    self:_request('POST', '/party/select', self:_auth_body({
        deck = deck,
        stake = stake,
    }), function(ok, response)
        if ok and response and response.party then
            self.party = response.party
            self.last_event_id = response.party.lastEventId or self.last_event_id
        else
            self:emit('error', response)
        end

        if callback then callback(ok, response) end
    end)
end

function Connection:set_ready(ready, callback)
    if not self.party_code or not self.player_id or not self.player_token then
        local err = { error = 'Not in a party' }
        if callback then callback(false, err) end
        return false, err
    end

    self:_request('POST', '/party/ready', self:_auth_body({
        ready = ready and true or false,
    }), function(ok, response)
        if ok and response and response.party then
            self.party = response.party
            self.last_event_id = response.party.lastEventId or self.last_event_id
        else
            self:emit('error', response)
        end

        if callback then callback(ok, response) end
    end)
end

function Connection:start_match(callback)
    if not self.party_code or not self.player_id or not self.player_token then
        local err = { error = 'Not in a party' }
        if callback then callback(false, err) end
        return false, err
    end

    self:_request('POST', '/party/start', self:_auth_body(), function(ok, response)
        if ok and response and response.party then
            self.party = response.party
            self.last_event_id = response.party.lastEventId or self.last_event_id
        else
            self:emit('error', response)
        end

        if callback then callback(ok, response) end
    end)
end

function Connection:get_party_state(callback)
    if not self.party_code then
        local err = { error = 'Not in a party' }
        if callback then callback(false, err) end
        return false, err
    end

    local path = '/party/' .. tostring(self.party_code) .. self:_auth_query()

    self:_request('GET', path, nil, function(ok, response)
        if ok and response.party then
            self.party = response.party
            self.last_event_id = response.party.lastEventId or self.last_event_id
        else
            self:emit('error', response)
        end

        if callback then callback(ok, response) end
    end)
end

function Connection:signal_boss_ready(callback)
    self:_request('POST', '/match/boss_ready', self:_auth_body(), function(ok, response)
        if not ok then
            self:emit('error', response)
        end
        if callback then callback(ok, response) end
    end)
end

function Connection:send_boss_state(score, hands_used, hands_remaining, money, done, ante, callback)
    local big_score = to_big(score)
    local big_money = to_big(money)

    self:_request('POST', '/match/report_state', self:_auth_body({
        score = big_to_net(big_score),
        scoreFormatted = number_format(big_score),
        handsUsed = to_number(hands_used),
        handsRemaining = hands_remaining ~= nil and to_number(hands_remaining) or nil,
        money = big_to_net(big_money),
        moneyFormatted = number_format(big_money),
        done = done and true or false,
        ante = to_number(ante),
    }), function(ok, response)
        if not ok then
            self:emit('error', response)
        end
        if callback then callback(ok, response) end
    end)
end

function Connection:take_life(callback)
    self:_request('POST', '/match/take_life', self:_auth_body(), function(ok, response)
        if not ok then
            self:emit('error', response)
        end
        if callback then callback(ok, response) end
    end)
end

function Connection:leave_party(callback)
    if not self.party_code or not self.player_id or not self.player_token then
        local err = { error = 'Not in a party' }
        if callback then callback(false, err) end
        return false, err
    end

    self:_request('POST', '/party/leave', self:_auth_body(), function(ok, response)
        if not ok then
            self:emit('error', response)
        end

        self.party = nil
        self.party_code = nil
        self.player_id = nil
        self.player_token = nil
        self.last_event_id = 0

        if callback then callback(ok, response) end
    end)
end

function Connection:_dispatch_event(event)
    self:emit('raw_event', event)

    if event.type == 'party_updated' then
        self:emit('party_updated', event)
    elseif event.type == 'match_started' then
        self:emit('match_started', event)
    elseif event.type == 'boss_started' then
        self:emit('boss_started', event)
    elseif event.type == 'boss_state_updated' then
        self:emit('boss_state_updated', event)
    elseif event.type == 'boss_result' then
        self:emit('boss_result', event)
    elseif event.type == 'next_boss_ready' then
        self:emit('next_boss_ready', event)
    elseif event.type == 'match_complete' then
        self:emit('match_complete', event)
    elseif event.type == 'card_cached' then
        self:emit('card_cached', event)
    end
end

function Connection:poll_events(callback)
    if not self.party_code or not self.player_id or not self.player_token then
        local err = { error = 'Not in a party' }
        if callback then callback(false, err) end
        return false, err
    end

    local path = '/party/' .. tostring(self.party_code) .. '/events?playerId='
        .. tostring(self.player_id)
        .. '&playerToken=' .. tostring(self.player_token)
        .. '&since=' .. tostring(self.last_event_id or 0)

    self:_request('GET', path, nil, function(ok, response)
        if not ok then
            self:emit('error', response)
            if callback then callback(false, response) end
            return
        end

        if response.party then
            self.party = response.party
        end

        if response.events then
            for _, event in ipairs(response.events) do
                if event.eventId and event.eventId > (self.last_event_id or 0) then
                    self.last_event_id = event.eventId
                end
                self:_dispatch_event(event)
            end
        end

        self:emit('poll', response)
        if callback then callback(true, response) end
    end)
end

function Connection:_current_poll_interval()
    if not self.party then
        return self.config.lobby_poll_interval
    end

    local state = self.party.state
    if state == 'BOSS_ACTIVE' then
        return self.config.boss_active_poll_interval
    elseif state == 'MATCH_COMPLETE' then
        return self.config.match_complete_poll_interval
    end

    return self.config.lobby_poll_interval
end

function Connection:update(dt)
    self:_process_http_responses()

    if not self.party_code or not self.player_id or not self.player_token then
        return
    end

    local current_time = get_time()
    local interval = self:_current_poll_interval()

    if current_time - self.last_poll_at >= interval then
        self.last_poll_at = current_time
        self:poll_events()
    end
end

function Connection:get_match_seed()
    return self.party and self.party.seed or nil
end