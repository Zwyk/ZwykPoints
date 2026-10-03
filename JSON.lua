local _, FW = ...

-- A small strict JSON codec. Profile imports are data, never executable Lua.
local JSON = {}
FW.JSON = JSON

local arrayMeta = { __jsonType = "array" }
local objectMeta = { __jsonType = "object" }
JSON.null = setmetatable({}, { __jsonType = "null" })

function JSON.array(value)
    return setmetatable(value or {}, arrayMeta)
end

function JSON.object(value)
    return setmetatable(value or {}, objectMeta)
end

local function isFinite(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function utf8(codepoint)
    if codepoint < 0x80 then
        return string.char(codepoint)
    elseif codepoint < 0x800 then
        return string.char(0xC0 + math.floor(codepoint / 64), 0x80 + codepoint % 64)
    elseif codepoint < 0x10000 then
        return string.char(0xE0 + math.floor(codepoint / 4096), 0x80 + math.floor(codepoint / 64) % 64, 0x80 + codepoint % 64)
    end
    return string.char(0xF0 + math.floor(codepoint / 262144), 0x80 + math.floor(codepoint / 4096) % 64, 0x80 + math.floor(codepoint / 64) % 64, 0x80 + codepoint % 64)
end

local function validUTF8(value)
    local index, length = 1, #value
    while index <= length do
        local first = value:byte(index)
        local count, minimum, codepoint
        if first < 0x80 then
            count, minimum, codepoint = 1, 0, first
        elseif first >= 0xC2 and first <= 0xDF then
            count, minimum, codepoint = 2, 0x80, first - 0xC0
        elseif first >= 0xE0 and first <= 0xEF then
            count, minimum, codepoint = 3, 0x800, first - 0xE0
        elseif first >= 0xF0 and first <= 0xF4 then
            count, minimum, codepoint = 4, 0x10000, first - 0xF0
        else
            return false
        end
        if index + count - 1 > length then return false end
        for offset = 1, count - 1 do
            local continuation = value:byte(index + offset)
            if continuation < 0x80 or continuation > 0xBF then return false end
            codepoint = codepoint * 64 + continuation - 0x80
        end
        if codepoint < minimum or codepoint > 0x10FFFF or (codepoint >= 0xD800 and codepoint <= 0xDFFF) then return false end
        index = index + count
    end
    return true
end

function JSON.Decode(source)
    if type(source) ~= "string" then return nil, "JSON must be text." end
    if #source > 1048576 then return nil, "JSON is too large (maximum 1 MiB)." end
    local position, length = 1, #source
    local parseValue

    local function fail(message)
        error(message .. " at byte " .. position .. ".", 0)
    end

    local function skipWhitespace()
        while position <= length do
            local byte = source:byte(position)
            if byte ~= 32 and byte ~= 9 and byte ~= 10 and byte ~= 13 then break end
            position = position + 1
        end
    end

    local function parseString()
        position = position + 1
        local pieces, start = {}, position
        while position <= length do
            local byte = source:byte(position)
            if byte == 34 then
                pieces[#pieces + 1] = source:sub(start, position - 1)
                position = position + 1
                local value = table.concat(pieces)
                if not validUTF8(value) then fail("Invalid UTF-8 string") end
                return value
            elseif byte == 92 then
                pieces[#pieces + 1] = source:sub(start, position - 1)
                position = position + 1
                local escaped = source:sub(position, position)
                local escapes = { ['"'] = '"', ['\\'] = '\\', ['/'] = '/', b = '\b', f = '\f', n = '\n', r = '\r', t = '\t' }
                if escapes[escaped] then
                    pieces[#pieces + 1] = escapes[escaped]
                    position = position + 1
                elseif escaped == "u" then
                    local hex = source:sub(position + 1, position + 4)
                    if #hex ~= 4 or not hex:match("^%x%x%x%x$") then fail("Invalid Unicode escape") end
                    local codepoint = tonumber(hex, 16)
                    position = position + 5
                    if codepoint >= 0xD800 and codepoint <= 0xDBFF then
                        if source:sub(position, position + 1) ~= "\\u" then fail("Missing low Unicode surrogate") end
                        local lowHex = source:sub(position + 2, position + 5)
                        if #lowHex ~= 4 or not lowHex:match("^%x%x%x%x$") then fail("Invalid low Unicode surrogate") end
                        local low = tonumber(lowHex, 16)
                        if low < 0xDC00 or low > 0xDFFF then fail("Invalid low Unicode surrogate") end
                        codepoint = 0x10000 + (codepoint - 0xD800) * 1024 + low - 0xDC00
                        position = position + 6
                    elseif codepoint >= 0xDC00 and codepoint <= 0xDFFF then
                        fail("Unexpected low Unicode surrogate")
                    end
                    pieces[#pieces + 1] = utf8(codepoint)
                else
                    fail("Invalid string escape")
                end
                start = position
            elseif byte < 32 then
                fail("Unescaped control character")
            else
                position = position + 1
            end
        end
        fail("Unterminated string")
    end

    local function parseNumber()
        local start = position
        if source:sub(position, position) == "-" then position = position + 1 end
        local digit = source:sub(position, position)
        if digit == "0" then
            position = position + 1
            if source:sub(position, position):match("%d") then fail("Leading zero in number") end
        elseif digit:match("[1-9]") then
            repeat position = position + 1 until not source:sub(position, position):match("%d")
        else
            fail("Invalid number")
        end
        if source:sub(position, position) == "." then
            position = position + 1
            if not source:sub(position, position):match("%d") then fail("Missing fraction digits") end
            repeat position = position + 1 until not source:sub(position, position):match("%d")
        end
        local exponent = source:sub(position, position)
        if exponent == "e" or exponent == "E" then
            position = position + 1
            local sign = source:sub(position, position)
            if sign == "+" or sign == "-" then position = position + 1 end
            if not source:sub(position, position):match("%d") then fail("Missing exponent digits") end
            repeat position = position + 1 until not source:sub(position, position):match("%d")
        end
        local value = tonumber(source:sub(start, position - 1))
        if not isFinite(value) then fail("Number must be finite") end
        return value
    end

    parseValue = function(depth)
        if depth > 64 then fail("JSON nesting is too deep") end
        skipWhitespace()
        local token = source:sub(position, position)
        if token == '"' then
            return parseString()
        elseif token == "{" then
            local value = JSON.object()
            position = position + 1
            skipWhitespace()
            if source:sub(position, position) == "}" then position = position + 1 return value end
            while true do
                skipWhitespace()
                if source:sub(position, position) ~= '"' then fail("Object keys must be quoted") end
                local key = parseString()
                if value[key] ~= nil then fail("Duplicate object key " .. key) end
                skipWhitespace()
                if source:sub(position, position) ~= ":" then fail("Expected ':'") end
                position = position + 1
                value[key] = parseValue(depth + 1)
                skipWhitespace()
                local separator = source:sub(position, position)
                position = position + 1
                if separator == "}" then return value end
                if separator ~= "," then fail("Expected ',' or '}'") end
            end
        elseif token == "[" then
            local value = JSON.array()
            position = position + 1
            skipWhitespace()
            if source:sub(position, position) == "]" then position = position + 1 return value end
            while true do
                value[#value + 1] = parseValue(depth + 1)
                skipWhitespace()
                local separator = source:sub(position, position)
                position = position + 1
                if separator == "]" then return value end
                if separator ~= "," then fail("Expected ',' or ']'") end
            end
        elseif token == "-" or token:match("%d") then
            return parseNumber()
        elseif source:sub(position, position + 3) == "true" then
            position = position + 4 return true
        elseif source:sub(position, position + 4) == "false" then
            position = position + 5 return false
        elseif source:sub(position, position + 3) == "null" then
            position = position + 4 return JSON.null
        end
        fail("Expected a JSON value")
    end

    local ok, value = pcall(function()
        local result = parseValue(0)
        skipWhitespace()
        if position <= length then fail("Unexpected trailing text") end
        return result
    end)
    if not ok then return nil, value end
    return value
end

local escapes = { ['"'] = '\\"', ['\\'] = '\\\\', ['\b'] = '\\b', ['\f'] = '\\f', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' }
local function quote(value)
    if not validUTF8(value) then error("Invalid UTF-8 string.", 0) end
    return '"' .. value:gsub('[%z\1-\31\\"]', function(character)
        return escapes[character] or string.format("\\u%04x", character:byte())
    end) .. '"'
end

function JSON.Encode(value)
    local seen = {}
    local function encode(current, depth)
        if depth > 64 then error("JSON nesting is too deep.", 0) end
        if current == JSON.null or current == nil then return "null" end
        local kind = type(current)
        if kind == "string" then return quote(current) end
        if kind == "boolean" then return current and "true" or "false" end
        if kind == "number" then
            if not isFinite(current) then error("JSON numbers must be finite.", 0) end
            return string.format("%.17g", current):gsub(",", ".")
        end
        if kind ~= "table" then error("Cannot encode " .. kind .. " as JSON.", 0) end
        if seen[current] then error("Cannot encode a circular table.", 0) end
        seen[current] = true
        local meta = getmetatable(current)
        local isArray = meta and meta.__jsonType == "array"
        if not meta then
            local count, maximum = 0, 0
            for key in pairs(current) do
                if type(key) ~= "number" or key < 1 or key ~= math.floor(key) then maximum = -1 break end
                count = count + 1
                if key > maximum then maximum = key end
            end
            isArray = count > 0 and count == maximum
        end
        local pieces = {}
        if isArray then
            local count = #current
            for key in pairs(current) do
                if type(key) ~= "number" or key < 1 or key > count or key ~= math.floor(key) then error("JSON arrays must be dense.", 0) end
            end
            for index = 1, count do
                if current[index] == nil then error("JSON arrays must be dense.", 0) end
                pieces[#pieces + 1] = encode(current[index], depth + 1)
            end
            seen[current] = nil
            return "[" .. table.concat(pieces, ",") .. "]"
        end
        local keys = {}
        for key in pairs(current) do
            if type(key) ~= "string" then error("JSON object keys must be strings.", 0) end
            keys[#keys + 1] = key
        end
        table.sort(keys)
        for _, key in ipairs(keys) do pieces[#pieces + 1] = quote(key) .. ":" .. encode(current[key], depth + 1) end
        seen[current] = nil
        return "{" .. table.concat(pieces, ",") .. "}"
    end
    local ok, result = pcall(encode, value, 0)
    if not ok then return nil, result end
    return result
end
