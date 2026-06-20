local VariableMangling = {}
local RandomUtils = require("random_utils")
local TransformUtils = require("transform_utils")

-- Homoglyph map: ASCII char -> visually identical Unicode lookalike
local HOMOGLYPHS = {
    a = "\xD0\xB0",  -- Cyrillic а
    e = "\xD0\xB5",  -- Cyrillic е
    o = "\xD0\xBE",  -- Cyrillic о
    p = "\xD1\x80",  -- Cyrillic р
    c = "\xD1\x81",  -- Cyrillic с
    x = "\xD1\x85",  -- Cyrillic х
    i = "\xD1\x96",  -- Ukrainian і
}

-- XOR-based hash to derive a stable-but-opaque seed from a name + salt
local function name_hash(name, salt)
    local h = salt or 0x5A3C
    for i = 1, #name do
        h = ((h * 31) ~ string.byte(name, i)) & 0xFFFFFF
    end
    return h
end

-- Inject homoglyphs into a string at pseudo-random positions seeded by hash
local function inject_homoglyphs(s, seed)
    local rng = seed
    local result = {}
    for i = 1, #s do
        rng = (rng * 6364136223846793005 + 1442695040888963407) & 0xFFFFFFFF
        local ch = s:sub(i, i)
        if (rng % 3 == 0) and HOMOGLYPHS[ch] then
            result[i] = HOMOGLYPHS[ch]
        else
            result[i] = ch
        end
    end
    return table.concat(result)
end

-- Pad all names to a uniform target length using a filler char derived from hash
local function pad_to_length(name, target_len, seed)
    local filler_chars = "lIiOo0" -- visually confusable fillers
    local rng = seed
    while #name < target_len do
        rng = (rng * 1664525 + 1013904223) & 0xFFFF
        local idx = (rng % #filler_chars) + 1
        name = name .. filler_chars:sub(idx, idx)
    end
    return name
end

-- Build a replacement name: hashed seed -> random base -> padded -> homoglyphed
local function build_obfuscated_name(original, salt, config)
    local seed = name_hash(original, salt)
    local length = config.name_length_max  -- all names normalized to max length
    
    local base
    if config.use_unicode then
        base = RandomUtils.random_unicode_string(config.name_length_min, config.name_length_max)
    else
        -- Seed RandomUtils with our hash for determinism within this run
        math.randomseed(seed)
        base = RandomUtils.random_variable_name(RandomUtils.random_int(
            config.name_length_min,
            config.name_length_max
        ))
    end

    -- Normalize length so all names are visually indistinct in size
    base = pad_to_length(base, length, seed)

    -- Inject homoglyphs using a secondary hash to obscure further
    local secondary_seed = name_hash(base, seed ~ 0xDEAD)
    base = inject_homoglyphs(base, secondary_seed)

    return base
end

-- Frontier-aware gsub: only replaces exact whole-word matches
-- Uses %f[%w_] (word boundary frontier) for precise substitution
local function replace_whole_word(code, name, new_name)
    -- Escape any magic pattern characters in the original name
    local escaped = name:gsub("([%.%+%-%*%?%[%]%^%$%(%)%%])", "%%%1")
    -- Use frontier pattern for true word-boundary matching
    return code:gsub("%f[%w_]" .. escaped .. "%f[^%w_]", new_name)
end

function VariableMangling.process(code, config)
    if not config or not config.enabled then return code end

    -- Per-run salt: changes every execution so no two runs share a name mapping
    local session_salt = os.time() ~ (math.random(0, 0xFFFF) * 0x10001)

    local replacements = {}

    local patterns = {
        {pattern = "local%s+([%a_][%w_]*)"},
        {pattern = "function%s+([%a_][%w_]*)%s*[%(]"},
        {pattern = "for%s+([%a_][%w_]*)%s*="},
        {pattern = "for%s+[%a_][%w_]*%s*,%s*([%a_][%w_]*)%s+in"},  -- capture value var in pairs
    }

    -- Pass 1: collect all candidate names
    for _, p in ipairs(patterns) do
        local start = 1
        while true do
            local s, e, name = code:find(p.pattern, start)
            if not s then break end
            if not replacements[name] and not is_reserved(name) then
                replacements[name] = build_obfuscated_name(name, session_salt, config)
            end
            start = e + 1
        end
    end

    -- Pass 2: sort longest-first to prevent short names clobbering long ones mid-replace
    local sorted_names = {}
    for name in pairs(replacements) do
        table.insert(sorted_names, name)
    end
    table.sort(sorted_names, function(a, b) return #a > #b end)

    -- Pass 3: multi-round layered replacement
    -- Round A: replace with a collision-safe intermediate token
    local intermediates = {}
    for i, name in ipairs(sorted_names) do
        local token = "\x01VAR" .. i .. "\x02"  -- non-printable delimiters, never in source
        intermediates[token] = replacements[name]
        code = replace_whole_word(code, name, token)
    end

    -- Round B: swap intermediate tokens for final obfuscated names
    for token, new_name in pairs(intermediates) do
        code = code:gsub(token:gsub("([%[%]%(%)%.%+%-%*%?%^%$%%\x01\x02])", "%%%1"), new_name)
    end

    return code
end

function is_reserved(name)
    local reserved = {
        "and", "break", "do", "else", "elseif", "end", "false", "for",
        "function", "goto", "if", "in", "local", "nil", "not", "or",
        "repeat", "return", "then", "true", "until", "while",
        "_G", "_ENV", "_VERSION", "assert", "bit32", "collectgarbage",
        "coroutine", "debug", "dofile", "error", "getmetatable",
        "io", "ipairs", "load", "loadfile", "math", "next",
        "os", "pairs", "pcall", "print", "rawequal", "rawget",
        "rawlen", "rawset", "require", "select", "setmetatable",
        "string", "table", "tonumber", "tostring", "type",
        "unpack", "xpcall", "self"
    }
    for _, r in ipairs(reserved) do
        if name == r then return true end
    end
    return false
end

return VariableMangling