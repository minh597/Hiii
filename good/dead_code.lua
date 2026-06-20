-- Dead Code Injection Layer - Inserts unreachable code blocks
local DeadCode = {}
local RandomUtils = require("random_utils")
local TransformUtils = require("transform_utils")

function DeadCode.process(code, config)
    if not config or not config.enabled then return code end
    
    local lines = {}
    for line in code:gmatch("[^\n]+") do
        table.insert(lines, line)
    end
    
    local result = {}
    local dead_code_count = 0
    
    for i, line in ipairs(lines) do
        table.insert(result, line)
        
        if RandomUtils.random_float() < (config.injection_density or 0.25) then
            dead_code_count = dead_code_count + 1
            local dead_block = generate_dead_block(config, dead_code_count)
            table.insert(result, dead_block)
        end
    end
    
    return table.concat(result, "\n")
end

function generate_dead_block(config, id)
    local block = {}
    local nesting = RandomUtils.random_int(1, config.max_nesting or 5)
    local indent = ""
    
    for level = 1, nesting do
        local cond
        local cond_type = RandomUtils.random_int(1, 3)
        
        if cond_type == 1 then
            cond = string.format("false and true == false")
        elseif cond_type == 2 then
            cond = string.format("nil ~= nil")
        else
            cond = string.format("not (1 == 1 and 2 == 2)")
        end
        
        table.insert(block, indent .. "if " .. cond .. " then")
        indent = indent .. "    "
    end
    
    local stmt_count = RandomUtils.random_int(1, 4)
    for i = 1, stmt_count do
        local stmt_type = RandomUtils.random_int(1, 6)
        
        if stmt_type == 1 and config.use_functions then
            local func_name = RandomUtils.random_variable_name(10)
            table.insert(block, indent .. string.format("local function %s(...) return ... end", func_name))
            table.insert(block, indent .. string.format("%s(%d, %d, %d)", func_name, 
                RandomUtils.random_int(1, 100), RandomUtils.random_int(1, 100), RandomUtils.random_int(1, 100)))
        elseif stmt_type == 2 then
            local var = RandomUtils.random_variable_name(8)
            table.insert(block, indent .. string.format("local %s = {[%d] = %d, [%d] = %d}", var,
                RandomUtils.random_int(1, 100), RandomUtils.random_int(1, 1000),
                RandomUtils.random_int(1, 100), RandomUtils.random_int(1, 1000)))
        elseif stmt_type == 3 then
            local var = RandomUtils.random_variable_name(8)
            table.insert(block, indent .. string.format("local %s = %d + %d * %d ^ %d", var,
                RandomUtils.random_int(1, 100), RandomUtils.random_int(1, 100),
                RandomUtils.random_int(1, 10), RandomUtils.random_int(1, 5)))
        elseif stmt_type == 4 and config.use_loops then
            local var = RandomUtils.random_variable_name(6)
            table.insert(block, indent .. string.format("for %s = 1, %d do", var, RandomUtils.random_int(1, 10)))
            table.insert(block, indent .. "    -- Dead loop body")
            table.insert(block, indent .. "end")
        elseif stmt_type == 5 then
            local s = RandomUtils.random_variable_name(12)
            table.insert(block, indent .. string.format("local _ = #%q > %d", s, RandomUtils.random_int(1, #s - 1)))
        else
            table.insert(block, indent .. string.format("setmetatable({}, {})"))
        end
    end
    
    for level = 1, nesting do
        table.insert(block, string.sub(indent, 1, -5) .. "end")
        indent = indent:sub(1, -5)
    end
    
    return table.concat(block, "\n")
end

return DeadCode