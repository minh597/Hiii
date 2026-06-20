-- String Encryption Layer - Encrypts string literals with runtime decryption
local StringEncryption = {}
local RandomUtils = require("random_utils")
local TransformUtils = require("transform_utils")

function StringEncryption.process(code, config)
    if not config or not config.enabled then return code end
    
    local decoder_name = RandomUtils.random_variable_name(12)
    local xor_key = RandomUtils.random_int(1, 255)
    
    local decoder_func = string.format([[
local function %s(s)
    local r = {}
    for i = 1, #s do
        r[i] = string.char(string.byte(s, i) ~ %d)
    end
    return table.concat(r)
end
]], decoder_name, xor_key)
    
    local string_count = 0
    
    local function encrypt_string(str)
        string_count = string_count + 1
        local encrypted_chars = {}
        for i = 1, #str do
            local byte = string.byte(str, i)
            table.insert(encrypted_chars, string.char(byte ~ xor_key))
        end
        local encrypted_str = table.concat(encrypted_chars)
        return string.format("%s([[%s]])", decoder_name, encrypted_str:gsub("'", "''"))
    end
    
    code = code:gsub("'([^'\\]*)'", function(s)
        if #s >= 2 then return encrypt_string(s) end
        return "'" .. s .. "'"
    end)
    
    code = code:gsub('"([^"\\]*)"', function(s)
        if #s >= 2 then return encrypt_string(s) end
        return '"' .. s .. '"'
    end)
    
    if string_count > 0 then
        code = decoder_func .. "\n" .. code
    end
    
    return code
end

function StringEncryption.xor_string(str, key)
    local result = {}
    for i = 1, #str do
        result[i] = string.char(string.byte(str, i) ~ key)
    end
    return table.concat(result)
end

return StringEncryption