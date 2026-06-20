-- Number Encoding Layer - Obfuscates numeric literals with complex math expressions (Lua 5.1+ compatible)
local NumberEncoding = {}
local RandomUtils = require("random_utils")
local TransformUtils = require("transform_utils")

local number_patterns = {
    { pattern = "(%D)(%-)(%d+%.?%d*)", handler = function(p, m, n) return p .. m .. encode_number(tonumber(n)) end },
    { pattern = "^(%d+%.?%d*)",        handler = function(n) return encode_number(tonumber(n)) end },
    { pattern = "(%D)(%d+%.?%d*)$",    handler = function(p, n) return p .. encode_number(tonumber(n)) end },
    { pattern = "(%D)(%d+%.?%d*)(%D)", handler = function(p, n, s) return p .. encode_number(tonumber(n)) .. s end },
}

function NumberEncoding.process(code, config)
    if not config or not config.enabled then return code end
    local result = {}
    for line in code:gmatch("[^\n]+") do
        local processed = line
        for _, pat in ipairs(number_patterns) do
            processed = processed:gsub(pat.pattern, function(...)
                local args = {...}
                local num_str = args[#args-1] or args[1]
                if should_encode(num_str, config) then
                    return pat.handler(...)
                end
                return table.concat(args)
            end)
        end
        table.insert(result, processed)
    end
    return table.concat(result, "\n")
end

function should_encode(num_str, config)
    if not num_str then return false end
    local n = tonumber(num_str)
    if not n or math.abs(n) <= 1 then return false end
    local should = RandomUtils.random_bool()
    return (n == math.floor(n) and config.encode_integers and should)
        or (config.encode_floats and should)
end

function encode_number(n)
    local abs_n = math.abs(n)
    local depth = math.random(7, 14)
    local expr = TransformUtils.create_number_expression_deep(math.floor(abs_n), depth)

    -- Float support
    if n \~= math.floor(n) then
        local frac = n - math.floor(n)
        if frac > 0 then
            expr = expr .. " + " .. string.format("%.14f", frac)
        end
    end

    -- Base wrap
    expr = n < 0 and "(-" .. expr .. ")" or "(" .. expr .. ")"

    -- Heavy multi-layer obfuscation (works on all Lua versions 5.1+)
    for _ = 1, math.random(3, 6) do
        local r = math.random()
        if r < 0.22 then
            expr = "(" .. expr .. " + 0)"
        elseif r < 0.40 then
            expr = "(-(-" .. expr .. "))"
        elseif r < 0.55 then
            expr = "(" .. expr .. " * 1)"
        elseif r < 0.68 then
            expr = "(" .. expr .. " / 1)"
        elseif r < 0.78 then
            expr = "(" .. expr .. " - 0)"
        elseif r < 0.85 then
            expr = "(" .. expr .. " % (" .. (math.random(99999, 999999) + 1) .. " + 1))"
        elseif r < 0.92 then
            -- Safe identity for all Lua versions
            expr = "(" .. expr .. " * (2 - 1))"
        else
            -- More complex math trick
            expr = "(" .. expr .. " + (" .. math.random(1, 9) .. " - " .. math.random(1, 9) .. "))"
        end
    end

    -- Extra deep nesting
    if math.random() < 0.8 then
        expr = "(" .. expr .. ")"
    end
    if math.random() < 0.55 then
        expr = "(-(-(" .. expr .. ")))"
    end
    if math.random() < 0.4 then
        expr = "(" .. expr .. " * (1 + 0))"
    end

    return expr
end

return NumberEncoding