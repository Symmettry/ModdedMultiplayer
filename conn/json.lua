local bit = require("bit")

local JSON = {}

local band    = bit.band
local bor     = bit.bor
local bxor    = bit.bxor
local lshift  = bit.lshift
local rshift  = bit.rshift
local arshift = bit.arshift

local JSONType = {
    NULL   = 0,
    BOOL   = 1,
    INT    = 2,
    FLOAT  = 3,
    STRING = 4,
    ARRAY  = 5,
    OBJECT = 6,
}

local VARINT_CHAIN_FLAG = 0x80
local MIN_INT32 = -2147483648
local MAX_INT32 = 2147483647

local function is_array(t)
    if type(t) ~= "table" then return false end
    local n = #t
    for k, _ in pairs(t) do
        if type(k) ~= "number" or k < 1 or k > n or k % 1 ~= 0 then
            return false
        end
    end
    return true
end

local function append(dst, src)
    for i = 1, #src do
        dst[#dst + 1] = src[i]
    end
end

local function split_array(arr, size)
    local out = {}
    local i = 1
    while i <= #arr do
        local chunk = {}
        for j = i, math.min(i + size - 1, #arr) do
            chunk[#chunk + 1] = arr[j]
        end
        out[#out + 1] = chunk
        i = i + size
    end
    return out
end

local function convertVarInt(num)
    if num < 0 or num % 1 ~= 0 then
        error("Variable Ints must be non-negative integers: " .. tostring(num))
    end
    if num == 0 then return {0} end

    local result = {}
    while num > 0 do
        local byte = num % 128
        num = math.floor(num / 128)
        if num > 0 then
            byte = byte + 128
        end
        result[#result + 1] = byte
    end
    return result
end

local function readVarInt(arr, off)
    local num = 0
    local shift = 0
    local byte

    repeat
        byte = arr[off]
        if byte == nil then
            error("Unexpected end of buffer while reading varint")
        end
        off = off + 1
        num = num + lshift(band(byte, 0x7F), shift)
        shift = shift + 7
    until band(byte, VARINT_CHAIN_FLAG) == 0

    return off, num
end

local function mapZigZag(n)
    return bxor(lshift(n, 1), arshift(n, 31))
end

local function demapZigZag(n)
    return bxor(rshift(n, 1), -band(n, 1))
end

local function compressBools(array)
    local byte = 0
    for i = 1, #array do
        if array[i] then
            byte = bor(byte, lshift(1, 8 - i))
        end
    end
    return byte
end

local function decompressBools(byte)
    local out = {}
    for i = 0, 7 do
        out[#out + 1] = band(byte, lshift(1, 7 - i)) ~= 0
    end
    return out
end

local function encodeString(str)
    local bytes = {string.byte(str, 1, #str)}
    local out = convertVarInt(#bytes)
    append(out, bytes)
    return out
end

local function decodeString(bytes, offset)
    local off, len = readVarInt(bytes, offset)
    local chars = {}
    for i = off, off + len - 1 do
        chars[#chars + 1] = string.char(bytes[i])
    end
    return table.concat(chars), (off + len - offset)
end

local function convertFloat(x)
    if x ~= x then
        return {0x7F, 0xC0, 0x00, 0x00}
    end

    local sign = 0
    if x < 0 or (x == 0 and 1 / x < 0) then
        sign = 1
        x = -x
    end

    if x == math.huge then
        local b1 = sign == 1 and 0xFF or 0x7F
        return {b1, 0x80, 0x00, 0x00}
    end

    if x == 0 then
        local b1 = sign == 1 and 0x80 or 0x00
        return {b1, 0x00, 0x00, 0x00}
    end

    local mant, exp = math.frexp(x)
    exp = exp - 1
    mant = mant * 2

    local exponentBits = exp + 127
    local mantissaBits

    if exponentBits <= 0 then
        mantissaBits = math.floor(x * 2^149 + 0.5)
        exponentBits = 0
    elseif exponentBits >= 255 then
        local b1 = sign == 1 and 0xFF or 0x7F
        return {b1, 0x80, 0x00, 0x00}
    else
        mantissaBits = math.floor((mant - 1) * 2^23 + 0.5)
        if mantissaBits >= 2^23 then
            mantissaBits = 0
            exponentBits = exponentBits + 1
            if exponentBits >= 255 then
                local b1 = sign == 1 and 0xFF or 0x7F
                return {b1, 0x80, 0x00, 0x00}
            end
        end
    end

    local bits = lshift(sign, 31) + lshift(exponentBits, 23) + mantissaBits

    return {
        band(rshift(bits, 24), 0xFF),
        band(rshift(bits, 16), 0xFF),
        band(rshift(bits, 8), 0xFF),
        band(bits, 0xFF),
    }
end

local function deconvertFloat(bytes)
    local b1, b2, b3, b4 = bytes[1], bytes[2], bytes[3], bytes[4]
    local bits = lshift(b1, 24) + lshift(b2, 16) + lshift(b3, 8) + b4

    local sign = band(rshift(bits, 31), 0x1)
    local exponent = band(rshift(bits, 23), 0xFF)
    local mantissa = band(bits, 0x7FFFFF)

    local value
    if exponent == 255 then
        if mantissa == 0 then
            value = math.huge
        else
            value = 0 / 0
        end
    elseif exponent == 0 then
        if mantissa == 0 then
            value = 0
        else
            value = (mantissa / 2^23) * 2^-126
        end
    else
        value = (1 + mantissa / 2^23) * 2^(exponent - 127)
    end

    if sign == 1 then
        value = -value
    end

    return value
end

local function packTypeBits(types)
    local out = {}
    local acc = 0
    local bits = 0

    for i = 1, #types do
        acc = lshift(acc, 3) + types[i]
        bits = bits + 3

        while bits >= 8 do
            local shift = bits - 8
            out[#out + 1] = band(rshift(acc, shift), 0xFF)
            acc = band(acc, lshift(1, shift) - 1)
            bits = shift
        end
    end

    if bits > 0 then
        out[#out + 1] = band(lshift(acc, 8 - bits), 0xFF)
    end

    return out
end

local function unpackTypeBits(bytes, totalValues)
    local out = {}
    local acc = 0
    local bits = 0
    local idx = 1

    while #out < totalValues do
        while bits < 3 do
            local b = bytes[idx]
            if not b then
                error("Unexpected end of type map")
            end
            idx = idx + 1
            acc = lshift(acc, 8) + b
            bits = bits + 8
        end

        local shift = bits - 3
        out[#out + 1] = band(rshift(acc, shift), 0x7)
        acc = band(acc, lshift(1, shift) - 1)
        bits = shift
    end

    return out
end

local function should_encode_as_int(val)
    return val == math.floor(val) and val >= MIN_INT32 and val <= MAX_INT32
end

function JSON.compressJSON(value)
    local bools = {}
    local payload = {}
    local typeList = {}

    local function encodeValue(val)
        local t = type(val)

        if val == nil then
            typeList[#typeList + 1] = JSONType.NULL

        elseif t == "boolean" then
            typeList[#typeList + 1] = JSONType.BOOL
            bools[#bools + 1] = val

        elseif t == "number" then
            if should_encode_as_int(val) then
                typeList[#typeList + 1] = JSONType.INT
                append(payload, convertVarInt(mapZigZag(val)))
            else
                typeList[#typeList + 1] = JSONType.FLOAT
                append(payload, convertFloat(val))
            end

        elseif t == "string" then
            typeList[#typeList + 1] = JSONType.STRING
            append(payload, encodeString(val))

        elseif t == "table" then
            if is_array(val) then
                typeList[#typeList + 1] = JSONType.ARRAY
                append(payload, convertVarInt(#val))
                for i = 1, #val do
                    encodeValue(val[i])
                end
            else
                typeList[#typeList + 1] = JSONType.OBJECT

                local keys = {}
                for k, _ in pairs(val) do
                    if type(k) ~= "string" then
                        error("Object keys must be strings")
                    end
                    keys[#keys + 1] = k
                end

                append(payload, convertVarInt(#keys))
                for i = 1, #keys do
                    local key = keys[i]
                    append(payload, encodeString(key))
                    encodeValue(val[key])
                end
            end

        else
            error("Unsupported type: " .. t)
        end
    end

    encodeValue(value)

    local boolBytes = {}
    if #bools > 0 then
        local groups = split_array(bools, 8)
        for i = 1, #groups do
            boolBytes[#boolBytes + 1] = compressBools(groups[i])
        end
    end

    local typeBytes = packTypeBits(typeList)

    local header = {}
    append(header, convertVarInt(#boolBytes))
    append(header, convertVarInt(#typeBytes))
    append(header, convertVarInt(#typeList))

    local out = {}
    append(out, header)
    append(out, boolBytes)
    append(out, typeBytes)
    append(out, payload)

    return out
end

function JSON.decompressJSON(bytes)
    local offset = 1

    local boolByteLen
    offset, boolByteLen = readVarInt(bytes, offset)

    local typeByteLen
    offset, typeByteLen = readVarInt(bytes, offset)

    local totalTypes
    offset, totalTypes = readVarInt(bytes, offset)

    local boolStream = {}
    for _ = 1, boolByteLen do
        local expanded = decompressBools(bytes[offset])
        offset = offset + 1
        append(boolStream, expanded)
    end
    local boolIndex = 1

    local typeBytes = {}
    for i = 1, typeByteLen do
        typeBytes[i] = bytes[offset]
        offset = offset + 1
    end

    local typeList = unpackTypeBits(typeBytes, totalTypes)
    local typeIndex = 1

    local function decodeValue(depth)
        if depth > 500 then
            error("JSON structure too deep.")
        end

        local typ = typeList[typeIndex]
        typeIndex = typeIndex + 1

        if typ == JSONType.NULL then
            return nil

        elseif typ == JSONType.BOOL then
            local v = boolStream[boolIndex]
            boolIndex = boolIndex + 1
            return v

        elseif typ == JSONType.INT then
            local n
            offset, n = readVarInt(bytes, offset)
            return demapZigZag(n)

        elseif typ == JSONType.FLOAT then
            local v = deconvertFloat({
                bytes[offset],
                bytes[offset + 1],
                bytes[offset + 2],
                bytes[offset + 3],
            })
            offset = offset + 4
            return v

        elseif typ == JSONType.STRING then
            local value, length = decodeString(bytes, offset)
            offset = offset + length
            return value

        elseif typ == JSONType.ARRAY then
            local len
            offset, len = readVarInt(bytes, offset)
            local arr = {}
            for i = 1, len do
                arr[i] = decodeValue(depth + 1)
            end
            return arr

        elseif typ == JSONType.OBJECT then
            local numKeys
            offset, numKeys = readVarInt(bytes, offset)
            local obj = {}
            for _ = 1, numKeys do
                local key, keyLen = decodeString(bytes, offset)
                offset = offset + keyLen
                obj[key] = decodeValue(depth + 1)
            end
            return obj
        end

        error("Unknown type " .. tostring(typ))
    end

    return decodeValue(0)
end

return JSON