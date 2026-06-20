local RandomUtils = {}
local math = math

function RandomUtils.seed(seed)
    math.randomseed(seed or os.time())
    math.random(); math.random(); math.random()
end

function RandomUtils.random_int(min, max)
    return math.floor(math.random() * (max - min + 1)) + min
end

function RandomUtils.random_float()
    return math.random()
end

function RandomUtils.random_bool()
    return math.random() > 0.5
end

function RandomUtils.random_choice(t)
    return t[RandomUtils.random_int(1, #t)]
end

function RandomUtils.random_string(min_len, max_len)
    local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"
    local len = RandomUtils.random_int(min_len or 8, max_len or 16)
    local s = {}
    for i = 1, len do
        s[i] = chars:sub(RandomUtils.random_int(1, #chars), RandomUtils.random_int(1, #chars))
    end
    return table.concat(s)
end

function RandomUtils.random_unicode_string(min_len, max_len)
    local unicode_chars = {
        "α","β","γ","δ","ε","ζ","η","θ","ι","κ","λ","μ","ν","ξ","ο","π","ρ","σ","τ","υ","φ","χ","ψ","ω",
        "А","Б","В","Г","Д","Е","Ё","Ж","З","И","Й","К","Л","М","Н","О","П","Р","С","Т","У","Ф","Х","Ц",
        "あ","い","う","え","お","か","き","く","け","こ","さ","し","す","せ","そ",
        "𝕏","ℂ","ℍ","ℕ","ℙ","ℚ","ℝ","ℤ"
    }
    local len = RandomUtils.random_int(min_len or 8, max_len or 16)
    local s = {}
    for i = 1, len do
        table.insert(s, RandomUtils.random_choice(unicode_chars))
    end
    return table.concat(s)
end

function RandomUtils.random_variable_name(length)
    local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
    local nums = "0123456789"
    local all = chars .. nums
    local len = length or RandomUtils.random_int(8, 16)
    local name = {}
    name[1] = chars:sub(RandomUtils.random_int(1, #chars), RandomUtils.random_int(1, #chars))
    for i = 2, len do
        name[i] = all:sub(RandomUtils.random_int(1, #all), RandomUtils.random_int(1, #all))
    end
    return table.concat(name)
end

function RandomUtils.shuffle(t)
    local n = #t
    for i = n, 2, -1 do
        local j = RandomUtils.random_int(1, i)
        t[i], t[j] = t[j], t[i]
    end
    return t
end

function RandomUtils.random_math_expression(var_name, depth)
    depth = depth or 1
    if depth <= 0 then return var_name end
    
    local ops = {"+", "-", "*", "//", "%"}
    local op = RandomUtils.random_choice(ops)
    local left, right
    
    if RandomUtils.random_bool() then
        left = RandomUtils.random_int(1, 100)
    else
        left = var_name
    end
    
    if depth > 1 and RandomUtils.random_bool() then
        right = "(" .. RandomUtils.random_math_expression(var_name, depth - 1) .. ")"
    else
        right = tostring(RandomUtils.random_int(1, 1000))
    end
    
    return "(" .. left .. " " .. op .. " " .. right .. ")"
end

return RandomUtils