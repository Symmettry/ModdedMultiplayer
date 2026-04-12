local JSON = LOAD("conn/json.lua")

local Socket = {}
Socket.__index = Socket
Socket.JSON = JSON

local _module = nil

local function file_exists(path)
    local f = io.open(path, "rb")
    if f then
        f:close()
        return true
    end
    return false
end

local function join_path(a, b)
    if a:sub(-1) == "/" or a:sub(-1) == "\\" then
        return a .. b
    end
    return a .. "/" .. b
end

local function load_ws_native(mod)
    if _module then
        MP.print("[ws] returning cached native module")
        return _module
    end

    assert(mod and mod.path, "load_ws_native requires a mod table with mod.path")

    local base = join_path(mod.path, "ws_native")
    local os_name = love.system.getOS()

    local candidates = {}
    if os_name == "Windows" then
        candidates = {
            join_path(base, "ws_native.dll"),
        }
    else
        candidates = {
            join_path(base, "ws_native.so"),
        }
    end

    local last_err = "no candidate paths tried"

    for _, lib_path in ipairs(candidates) do
        MP.print("[ws] trying native module: " .. tostring(lib_path))

        if file_exists(lib_path) then
            MP.print("[ws] file exists")
            local openf, err = package.loadlib(lib_path, "luaopen_ws_native")
            MP.print("[ws] package.loadlib returned", openf, err)

            if openf then
                MP.print("[ws] calling luaopen_ws_native")
                _module = openf()
                MP.print("[ws] native module initialized")
                return _module
            end

            last_err = err or ("failed to load " .. lib_path)
        else
            last_err = "missing library: " .. lib_path
        end
    end

    error("failed to load ws_native library: " .. tostring(last_err))
end

function Socket.load(mod)
    return load_ws_native(mod)
end

function Socket.connect(mod, url, handlers)
    local ws_native = load_ws_native(mod)
    local raw = ws_native.connect(url)

    local self = setmetatable({
        raw = raw,
        handlers = handlers or {},
    }, Socket)

    return self
end

function Socket:on(event, fn)
    self.handlers[event] = fn
    return self
end

function Socket:send(data, is_binary)
    return self.raw:send(data, is_binary or false)
end

local unpack = unpack or table.unpack

local function bytes_to_string(bytes)
    local chunks = {}
    local chunk_size = 4096

    for i = 1, #bytes, chunk_size do
        local sub = {}
        for j = i, math.min(i + chunk_size - 1, #bytes) do
            sub[#sub + 1] = bytes[j]
        end
        chunks[#chunks + 1] = string.char(unpack(sub))
    end

    return table.concat(chunks)
end

function Socket:emit(key, tbl)
    local payload = JSON.compressJSON({
        key = key,
        data = tbl
    })
    return self:send(bytes_to_string(payload), true)
end

function Socket:close(code, reason)
    return self.raw:close(code, reason)
end

function Socket:state()
    return self.raw:state()
end

function Socket:poll()
    return self.raw:poll()
end

function Socket:update()
    while true do
        local ev = self.raw:poll()
        if not ev then break end

        local handler = self.handlers[ev.type]
        if handler then
            handler(self, ev)
        end
    end
end

return Socket