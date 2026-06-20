-- Table Obfuscation Layer - Scrambles table keys and adds fake entries
local TableObfuscation = {}
local RandomUtils = require("random_utils")
local TransformUtils = require("transform_utils")

function TableObfuscation.process(code, config)
    if not config or not config.enabled then return code end
    
    local result = {}
    
    for line in code:gmatch("[^\n]+") do
        local processed = line:gsub("{(.-)}", function(table_content)
            if #table_content > 5 then
                return obfuscate_table(table_content, config)
            end
            return "{" .. table_content .. "}"
        end)
        table.insert(result, processed)
    end
    
    return table.concat(result, "\n")
end

function obfuscate_table(table_content, config)
    local entries = {}
    for entry in table_content:gmatch("[^,]+") do
        entry = entry:match("^%s*(.-)%s*$") or entry
        table.insert(entries, entry)
    end
    
    local result_entries = {}
    
    for _, entry in ipairs(entries) do
        if #entry > 0 then
            local key, value = entry:match("^%[([^%]]+)%]%s*=%s*(.+)$")
            if key then
                if config.scramble_keys then
                    key = obfuscate_key(key, config)
                end
                table.insert(result_entries, "[" .. key .. "] = " .. value)
            else
                table.insert(result_entries, entry)
            end
        end
    end
    
    if config.add_fake_entries then
        local fake_count = math.floor(#result_entries * (config.fake_entry_ratio or 0.4))
        for i = 1, fake_count do
            local fake_key, fake_value = generate_fake_entry(config)
            table.insert(result_entries, "[" .. fake_key .. "] = " .. fake_value)
        end
    end
    
    if config.scramble_keys then
        RandomUtils.shuffle(result_entries)
    end
    
    return "{" .. table.concat(result_entries, ", ") .. "}"
end

function obfuscate_key(key, config)
    local methods = {
        function()
            local var = RandomUtils.random_variable_name(8)
            return string.format("%s", var)
        end,
        function()
            local n = tonumber(key:match("%d+"))
            if n then
                return TransformUtils.create_number_expression_deep(n, 3)
            end
            return key
        end,
        function()
            local parts = {}
            for i = 1, #key do
                local char = key:sub(i, i)
                table.insert(parts, string.format("%q", char))
                if i < #key then
                    table.insert(parts, "..")
                end
            end
            return table.concat(parts)
        end,
        function()
            local bytes = {}
            for i = 1, #key do
                table.insert(bytes, tostring(string.byte(key, i)))
            end
            return "string.char(" .. table.concat(bytes, ",") .. ")"
        end,
    }
    
    local idx = RandomUtils.random_int(1, #methods)
    return methods[idx]()
end

function generate_fake_entry(config)
    local types = {"string", "number", "table", "function"}
    local key_type = RandomUtils.random_int(1, #types)
    local val_type = RandomUtils.random_int(1, #types)
    
    local function generate_value(t)
        if t == "string" then
            return string.format("%q", RandomUtils.random_variable_name(RandomUtils.random_int(3, 12)))
        elseif t == "number" then
            return tostring(RandomUtils.random_int(1, 10000))
        elseif t == "table" then
            return "{[" .. RandomUtils.random_int(1, 10) .. "] = " .. RandomUtils.random_int(1, 100) .. "}"
        else
            local func_name = "function() return " .. RandomUtils.random_int(1, 100) .. " end"
            return func_name
        end
    end
    
    local key = generate_value(types[key_type])
    local value = generate_value(types[val_type])
    
    return key, value
end

return TableObfuscation