local Socket = {}
Socket.__index = Socket

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
        if file_exists(lib_path) then
            local openf, err = package.loadlib(lib_path, "luaopen_ws_native")
            if openf then
                _module = openf()
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

function Socket:send(data)
    return self.raw:send(data)
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