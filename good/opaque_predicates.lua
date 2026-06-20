-- Opaque Predicates Layer - Always-true/false conditions that confuse reverse engineering
local OpaquePredicates = {}
local RandomUtils = require("random_utils")
local TransformUtils = require("transform_utils")

function OpaquePredicates.process(code, config)
    if not config or not config.enabled then return code end
    
    local lines = {}
    for line in code:gmatch("[^\n]+") do
        if RandomUtils.random_float() < (config.density or 0.3) then
            line = inject_predicate(line, config)
        end
        table.insert(lines, line)
    end
    
    return table.concat(lines, "\n")
end

function inject_predicate(line, config)
    local pred_type = RandomUtils.random_int(1, 3)
    local pred_code = ""
    local always_truthy = RandomUtils.random_bool()
    
    if pred_type == 1 or config.use_math_predicates then
        pred_code = generate_math_predicate(always_truthy, config)
    elseif pred_type == 2 or config.use_string_predicates then
        pred_code = generate_string_predicate(always_truthy, config)
    else
        pred_code = generate_table_predicate(always_truthy, config)
    end
    
    local result
    if always_truthy then
        local dead_branch = generate_dead_branch(config)
        result = string.format("if %s then\n    %s\nelse\n    %s\nend", 
            pred_code, line, dead_branch)
    else
        local dead_branch = generate_dead_branch(config)
        result = string.format("if %s then\n    %s\nelse\n    %s\nend",
            pred_code, dead_branch, line)
    end
    
    return result
end

function generate_math_predicate(always_true, config)
    local methods = {
        function()
            local var = RandomUtils.random_variable_name(6)
            local n = RandomUtils.random_int(1, 1000)
            return string.format("((%d * 0) == 0)", n)
        end,
        function()
            local n = RandomUtils.random_int(1, 1000)
            return string.format("(((%d + 1) - %d) == 1)", n, n)
        end,
        function()
            return "(1 == 0)"
        end,
        function()
            return "(not (1 ~= 1))"
        end,
        function()
            local a = RandomUtils.random_int(2, 10)
            local b = RandomUtils.random_int(2, 10)
            return string.format("(%d %% %d == %d %% %d)", a, b, a % b, b)
        end,
        function()
            local n = RandomUtils.random_int(1, 50)
            return string.format("(%d ^ 2 == %d)", n, n * n)
        end,
    }
    
    local idx = RandomUtils.random_int(1, #methods)
    return methods[idx]()
end

function generate_string_predicate(always_true, config)
    local methods = {
        function()
            local s = RandomUtils.random_variable_name(RandomUtils.random_int(3, 8))
            return string.format("(#%q == %d)", s, #s)
        end,
        function()
            return string.format("%q ~= %q", 
                RandomUtils.random_variable_name(3), 
                RandomUtils.random_variable_name(3))
        end,
        function()
            return "type('') == 'string'"
        end,
        function()
            return "string.len('x') == 1"
        end,
    }
    
    local idx = RandomUtils.random_int(1, #methods)
    return methods[idx]()
end

function generate_table_predicate(always_true, config)
    local methods = {
        function()
            return "type({}) == 'string'"
        end,
        function()
            return "#{1,2,3} == 3"
        end,
        function()
            return "type({}) == 'table'"
        end,
        function()
            return "({} == nil)"
        end,
    }
    
    local idx = RandomUtils.random_int(1, #methods)
    return methods[idx]()
end

function generate_dead_branch(config)
    local complexity = RandomUtils.random_int(1, config.complexity or 3)
    local statements = {}
    
    for i = 1, complexity do
        local stmt_type = RandomUtils.random_int(1, 4)
        if stmt_type == 1 then
            local var = RandomUtils.random_variable_name(8)
            local n = RandomUtils.random_int(1, 1000)
            table.insert(statements, string.format("local %s = %d * %d + %d", var, 
                RandomUtils.random_int(1, 100), RandomUtils.random_int(1, 100), 
                RandomUtils.random_int(1, 1000)))
        elseif stmt_type == 2 then
            local cond = generate_math_predicate(RandomUtils.random_bool(), config)
            table.insert(statements, string.format("if %s then", cond))
            table.insert(statements, string.format("    local %s = %d", 
                RandomUtils.random_variable_name(8), RandomUtils.random_int(1, 1000)))
            table.insert(statements, "end")
        elseif stmt_type == 3 then
            table.insert(statements, string.format("local %s = {%s = %d, %s = %d}",
                RandomUtils.random_variable_name(8),
                RandomUtils.random_variable_name(5), RandomUtils.random_int(1, 100),
                RandomUtils.random_variable_name(5), RandomUtils.random_int(1, 100)))
        elseif stmt_type == 4 then
            local func_name = RandomUtils.random_variable_name(8)
            table.insert(statements, string.format("local function %s() return %d end",
                func_name, RandomUtils.random_int(1, 100)))
            table.insert(statements, func_name .. "()")
        end
    end
    
    return table.concat(statements, "\n    ")
end

return OpaquePredicates