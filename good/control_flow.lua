-- Control Flow Flattening Layer - Restructures code with goto-based control flow
local ControlFlow = {}
local RandomUtils = require("random_utils")
local TransformUtils = require("transform_utils")

function ControlFlow.process(code, config)
    if not config or not config.enabled then return code end
    
    -- Split code into blocks
    local blocks = split_into_blocks(code, config)
    if #blocks <= 1 then return code end
    
    -- Generate block labels
    local labels = {}
    for i = 1, #blocks do
        labels[i] = RandomUtils.random_variable_name(10)
    end
    
    -- Create dispatcher
    local dispatcher = generate_dispatcher(#blocks, config)
    
    -- Build flattened code
    local flattened = {}
    
    -- Add dispatcher function
    table.insert(flattened, dispatcher)
    
    -- Add each block with its label
    for i, block in ipairs(blocks) do
        table.insert(flattened, "::" .. labels[i] .. "::")
        table.insert(flattened, block)
        
        -- Add goto to next block or dispatcher
        if i < #blocks then
            if RandomUtils.random_bool() then
                table.insert(flattened, string.format("goto %s", labels[i + 1]))
            else
                local dispatch_var = RandomUtils.random_variable_name(8)
                table.insert(flattened, string.format("local %s = %d", dispatch_var, i + 1))
                table.insert(flattened, string.format("goto %s", labels[RandomUtils.random_int(1, #labels)]))
            end
        end
    end
    
    return table.concat(flattened, "\n")
end

function split_into_blocks(code, config)
    local blocks = {}
    local lines = {}
    
    for line in code:gmatch("[^\n]+") do
        table.insert(lines, line)
    end
    
    local block_size = RandomUtils.random_int(config.block_size_min or 3, config.block_size_max or 8)
    local current_block = {}
    
    for i, line in ipairs(lines) do
        table.insert(current_block, line)
        
        if #current_block >= block_size and i < #lines then
            table.insert(blocks, table.concat(current_block, "\n"))
            current_block = {}
            block_size = RandomUtils.random_int(config.block_size_min or 3, config.block_size_max or 8)
        end
    end
    
    if #current_block > 0 then
        table.insert(blocks, table.concat(current_block, "\n"))
    end
    
    return blocks
end

function generate_dispatcher(num_blocks, config)
    local dispatch_name = RandomUtils.random_variable_name(12)
    local state_var = RandomUtils.random_variable_name(8)
    local labels = {}
    
    for i = 1, num_blocks do
        labels[i] = RandomUtils.random_variable_name(10)
    end
    
    local dispatcher = {}
    table.insert(dispatcher, string.format("local %s = 1", state_var))
    table.insert(dispatcher, string.format("::%s::", labels[1]))
    table.insert(dispatcher, string.format("if %s == 1 then goto %s", state_var, labels[2]))
    
    for i = 2, num_blocks do
        local cond = TransformUtils.create_opaque_predicate()
        table.insert(dispatcher, string.format("elseif %s == %d then goto %s", state_var, i, labels[math.min(i + 1, num_blocks)]))
    end
    
    table.insert(dispatcher, "end")
    table.insert(dispatcher, string.format("goto %s", labels[1]))
    
    return table.concat(dispatcher, "\n")
end

return ControlFlow