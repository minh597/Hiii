local TransformUtils = {}
local RandomUtils = require("random_utils")

function TransformUtils.wrap_in_function(code, name)
    name = name or RandomUtils.random_variable_name(10)
    return string.format("local function %s()\n%s\nend\n%s()\n", name, code, name)
end

function TransformUtils.wrap_in_goto(statements, labels)
    local result = {}
    for i, stmt in ipairs(statements) do
        local label = labels[i]
        if label then
            table.insert(result, "::" .. label .. "::")
        end
        table.insert(result, stmt)
    end
    return table.concat(result, "\n")
end

function TransformUtils.generate_goto_chain(count)
    local labels = {}
    for i = 1, count do
        table.insert(labels, RandomUtils.random_variable_name(8))
    end
    
    local code = {}
    table.insert(code, "::" .. labels[1] .. "::")
    for i = 1, count - 1 do
        local cond = RandomUtils.random_math_expression("1", RandomUtils.random_int(1, 3))
        table.insert(code, string.format("if %s then goto %s else goto %s end", cond, labels[i + 1], labels[i + 1]))
        table.insert(code, "::" .. labels[i + 1] .. "::")
    end
    
    return table.concat(code, "\n")
end

function TransformUtils.create_opaque_predicate()
    local types = {"math", "string", "table"}
    local t = types[RandomUtils.random_int(1, #types)]
    
    if t == "math" then
        local n = RandomUtils.random_int(2, 100)
        local n2 = RandomUtils.random_int(2, 100)
        local divisor = n * n2
        return string.format("(%d * %d) // %d ~= 0", n, n2, divisor)
    elseif t == "string" then
        local s1 = RandomUtils.random_variable_name(4)
        local s2 = RandomUtils.random_variable_name(4)
        local op = RandomUtils.random_choice({"==", "~="})
        return string.format("'%s' %s '%s'", s1, op, s2)
    else
        return string.format("type({}) == 'string' and false or true")
    end
end

local function bxor(a, b)
    local ok, result = pcall(function() return a ~ b end)
    if ok then return result end
    ok, result = pcall(function() return bit32.bxor(a, b) end)
    if ok then return result end
    local r = 0
    for i = 0, 31 do
        local ba = a % 2
        local bb = b % 2
        if ba ~= bb then r = r + 2^i end
        a = (a - ba) / 2
        b = (b - bb) / 2
    end
    return r
end

function TransformUtils.xor_encrypt(str, key)
    local result = {}
    key = key or RandomUtils.random_int(1, 255)
    for i = 1, #str do
        local byte = string.byte(str, i)
        table.insert(result, string.format("string.char(%d)", bxor(byte, key)))
    end
    return table.concat(result, " .. "), key
end

function TransformUtils.base64_encode(str)
    local b64chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    local result = {}
    for i = 1, #str, 3 do
        local byte1 = string.byte(str, i) or 0
        local byte2 = string.byte(str, i + 1) or 0
        local byte3 = string.byte(str, i + 2) or 0
        local triple = (byte1 << 16) + (byte2 << 8) + byte3
        
        for j = 4, 1, -1 do
            local index = (triple >> (6 * (j - 1))) & 0x3F
            table.insert(result, b64chars:sub(index + 1, index + 1))
        end
    end
    return table.concat(result)
end

function TransformUtils.simple_decoder_func(key)
    local func_name = RandomUtils.random_variable_name(10)
    return string.format([[
local function %s(s)
    local r = {}
    for i = 1, #s do
        r[i] = string.char(string.byte(s, i) ~ %d)
    end
    return table.concat(r)
end
]], func_name, key), func_name
end

function TransformUtils.create_number_expression(n)
    if type(n) ~= "number" then return tostring(n) end
    
    local depth = RandomUtils.random_int(1, 4)
    local vars = {"_1", "_2", "x", "y", "a", "b"}
    local used_var = RandomUtils.random_choice(vars)
    
    local parts = {}
    local remaining = n
    local ops = RandomUtils.random_choice({
        {"+", function(a,b) return a + b end},
        {"-", function(a,b) return a - b end},
    })
    
    local a = RandomUtils.random_int(1, math.max(1, n))
    local b = remaining - a
    
    local expr_a = tostring(a)
    local expr_b = tostring(b)
    
    if depth > 1 and RandomUtils.random_bool() then
        expr_a = string.format("(%s)", TransformUtils.create_number_expression_deep(a, depth - 1))
    end
    if depth > 1 and RandomUtils.random_bool() then
        expr_b = string.format("(%s)", TransformUtils.create_number_expression_deep(b, depth - 1))
    end
    
    return string.format("(%s %s %s)", expr_a, ops[1], expr_b)
end

function TransformUtils.create_number_expression_deep(n, depth)
    if depth <= 0 then return tostring(n) end
    
    local method = RandomUtils.random_int(1, 5)
    
    if method == 1 then
        local a = RandomUtils.random_int(0, math.abs(n))
        local b = n - a
        local op = b >= 0 and "+" or "-"
        b = math.abs(b)
        return string.format("(%s %s %s)", tostring(a), op, tostring(b))
    elseif method == 2 then
        local factor = RandomUtils.random_int(2, 10)
        local remainder = n - (factor * math.floor(n / factor))
        return string.format("(%d * %d + %d)", factor, math.floor(n / factor), remainder)
    elseif method == 3 then
        local a = RandomUtils.random_int(0, 255)
        local b = bxor(n, a)
        return string.format("(%d ~ %d)", a, b)
    elseif method == 4 then
        local fname = RandomUtils.random_variable_name(8)
        return string.format("(function() return %d end)()", n)
    else
        return tostring(n)
    end
end

function TransformUtils.build_table_access(tbl_name, key)
    return string.format("%s[%s]", tbl_name, key)
end

function TransformUtils.sort_statements(stmts)
    local groups = {}
    local current_group = {}
    
    for _, stmt in ipairs(stmts) do
        table.insert(current_group, stmt)
        if #current_group >= RandomUtils.random_int(2, 5) then
            RandomUtils.shuffle(current_group)
            table.insert(groups, current_group)
            current_group = {}
        end
    end
    
    if #current_group > 0 then
        RandomUtils.shuffle(current_group)
        table.insert(groups, current_group)
    end
    
    RandomUtils.shuffle(groups)
    
    local result = {}
    for _, group in ipairs(groups) do
        for _, stmt in ipairs(group) do
            table.insert(result, stmt)
        end
    end
    
    return result
end

return TransformUtils