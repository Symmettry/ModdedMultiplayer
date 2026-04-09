local http = require('socket.http')
local ltn12 = require('ltn12')
local json = require('json')

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
        print('[MP] Received event ' .. event_name .. ' with value')
        print(payload)
    end

    local handlers = self.handlers[event_name]
    if not handlers then return end

    for _, handler in ipairs(handlers) do
        local ok, err = pcall(handler, payload, self)
        if not ok then
            print('[Connection] handler error for event ' .. tostring(event_name) .. ': ' .. tostring(err))
        end
    end
end

function Connection:_request(method, path, body)
    local response_chunks = {}
    local body_string = method == 'GET' and '' or encode_body(body)

    local req = {
        url = http_base() .. path,
        method = method,
        sink = ltn12.sink.table(response_chunks),
    }

    if method ~= 'GET' then
        req.headers = {
            ["Content-Type"] = "application/json",
            ["Content-Length"] = tostring(#body_string),
        }
        req.source = ltn12.source.string(body_string)
    end

    local ok, request_ok, status_code, response_headers, status_line = safe_call(http.request, req)
    if not ok then
        return false, {
            error = 'HTTP request failed',
            detail = request_ok,
        }
    end

    local raw_body = table.concat(response_chunks)
    local decoded = decode_body(raw_body) or {}

    if tonumber(status_code) and tonumber(status_code) >= 200 and tonumber(status_code) < 300 then
        return true, decoded, response_headers, status_line
    end

    return false, {
        status_code = status_code,
        headers = response_headers,
        status_line = status_line,
        body = decoded,
        error = decoded.error or ('HTTP ' .. tostring(status_code)),
    }
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

function Connection:create_party(name)
    local ok, response = self:_request('POST', '/party/create', {
        name = name,
    })

    if not ok then
        self:emit('error', response)
        return false, response
    end

    self.player_id = response.playerId
    self.player_token = response.playerToken
    self.party_code = response.partyCode
    self.party = response.party
    self.last_event_id = response.party and response.party.lastEventId or 0

    return true, response
end

function Connection:join_party(party_code, name)
    local ok, response = self:_request('POST', '/party/join', {
        partyCode = normalize_party_code(party_code),
        name = name,
    })

    if not ok then
        self:emit('error', response)
        return false, response
    end

    self.player_id = response.playerId
    self.player_token = response.playerToken
    self.party_code = response.partyCode
    self.party = response.party
    self.last_event_id = response.party and response.party.lastEventId or 0

    return true, response
end

function Connection:select_lobby_options(deck, stake)
    if not self.party_code or not self.player_id or not self.player_token then
        return false, { error = 'Not in a party' }
    end

    local ok, response = self:_request('POST', '/party/select', self:_auth_body({
        deck = deck,
        stake = stake,
    }))

    if ok and response.party then
        self.party = response.party
        self.last_event_id = response.party.lastEventId or self.last_event_id
    else
        self:emit('error', response)
    end

    return ok, response
end

function Connection:set_ready(ready)
    if not self.party_code or not self.player_id or not self.player_token then
        return false, { error = 'Not in a party' }
    end

    local ok, response = self:_request('POST', '/party/ready', self:_auth_body({
        ready = ready and true or false,
    }))

    if ok and response.party then
        self.party = response.party
        self.last_event_id = response.party.lastEventId or self.last_event_id
    else
        self:emit('error', response)
    end

    return ok, response
end

function Connection:start_match()
    if not self.party_code or not self.player_id or not self.player_token then
        return false, { error = 'Not in a party' }
    end

    local ok, response = self:_request('POST', '/party/start', self:_auth_body())

    if ok and response.party then
        self.party = response.party
        self.last_event_id = response.party.lastEventId or self.last_event_id
    else
        self:emit('error', response)
    end

    return ok, response
end

function Connection:get_party_state()
    if not self.party_code then
        return false, { error = 'Not in a party' }
    end

    local path = '/party/' .. tostring(self.party_code) .. self:_auth_query()
    local ok, response = self:_request('GET', path)

    if ok and response.party then
        self.party = response.party
        self.last_event_id = response.party.lastEventId or self.last_event_id
    else
        self:emit('error', response)
    end

    return ok, response
end

function Connection:signal_boss_ready()
    return self:_request('POST', '/match/boss_ready', self:_auth_body())
end

function Connection:send_boss_state(score, hands_used, hands_remaining, money, done, ante)
    local big_score = to_big(score)
    local big_money = to_big(money)

    return self:_request('POST', '/match/report_state', self:_auth_body({
        score = big_to_net(big_score),
        scoreFormatted = number_format(big_score),
        handsUsed = to_number(hands_used),
        handsRemaining = hands_remaining ~= nil and to_number(hands_remaining) or nil,
        money = big_to_net(big_money),
        moneyFormatted = number_format(big_money),
        done = done and true or false,
        ante = to_number(ante),
    }))
end

function Connection:take_life()
    return self:_request('POST', '/match/take_life', self:_auth_body())
end

function Connection:leave_party()
    if not self.party_code or not self.player_id or not self.player_token then
        return false, { error = 'Not in a party' }
    end

    local ok, response = self:_request('POST', '/party/leave', self:_auth_body())
    self.party = nil
    self.party_code = nil
    self.player_id = nil
    self.player_token = nil
    self.last_event_id = 0
    return ok, response
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
    end
end

function Connection:poll_events()
    if not self.party_code or not self.player_id or not self.player_token then
        return false, { error = 'Not in a party' }
    end

    local path = '/party/' .. tostring(self.party_code) .. '/events?playerId='
        .. tostring(self.player_id)
        .. '&playerToken=' .. tostring(self.player_token)
        .. '&since=' .. tostring(self.last_event_id or 0)

    local ok, response = self:_request('GET', path)
    if not ok then
        self:emit('error', response)
        return false, response
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
    return true, response
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