--[[
  obfuscate.lua - MASTER OBFUSCATOR
  =================================
  Links ALL obfuscation layers together to harden encrypt.lua.
  
  Pipeline:
  1. Load encrypt.lua source
  2. Variable Mangling (renames to unicode/random)
  3. Number Encoding (numbers → math expressions)
  4. String Encryption (strings → XOR-decoded at runtime)
  5. Table Obfuscation (scramble keys, add fake entries)
  6. Opaque Predicates (always-true/false conditions)
  7. Dead Code Injection (unreachable code blocks)
  8. Control Flow Flattening (goto-based dispatcher)
  
  Output: obfuscated_encrypt.lua
    
  Usage: lua obfuscate.lua
]]

local RandomUtils = require("random_utils")
local VariableMangling = require("variable_mangling")
local NumberEncoding = require("number_encoding")
local StringEncryption = require("string_encryption")
local TableObfuscation = require("table_obfuscation")
local OpaquePredicates = require("opaque_predicates")
local DeadCode = require("dead_code")
local ControlFlow = require("control_flow")

-- ============================================================
-- MASTER OBFUSCATION CONFIG
-- ============================================================
local config = {
    -- Variable Mangling
    var_mangle = {
        enabled = true,
        use_unicode = true,
        name_length_min = 8,
        name_length_max = 20,
    },
    
    -- Number Encoding
    number_encode = {
        enabled = true,
        encode_integers = true,
        encode_floats = true,
        max_expression_depth = 6,
    },
    
    -- String Encryption
    string_encrypt = {
        enabled = true,
    },
    
    -- Table Obfuscation
    table_obfuscate = {
        enabled = true,
        scramble_keys = true,
        add_fake_entries = true,
        fake_entry_ratio = 0.6,
    },
    
    -- Opaque Predicates
    opaque_predicates = {
        enabled = true,
        density = 0.4,
        use_math_predicates = true,
        use_string_predicates = true,
        complexity = 4,
    },
    
    -- Dead Code Injection
    dead_code = {
        enabled = true,
        injection_density = 0.35,
        max_nesting = 6,
        use_functions = true,
        use_loops = true,
    },
    
    -- Control Flow Flattening
    control_flow = {
        enabled = true,
        block_size_min = 2,
        block_size_max = 6,
    },
}

-- ============================================================
-- RUN OBFUSCATION PIPELINE
-- ============================================================

-- Step 1: Read encrypt.lua source code
local function read_file(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local content = f:read("*all")
    f:close()
    return content
end

local function write_file(path, content)
    local f = io.open(path, "w")
    if not f then return false end
    f:write(content)
    f:close()
    return true
end

local encrypt_source = read_file("encrypt.lua")
if not encrypt_source then
    print("ERROR: Cannot read encrypt.lua")
    return
end

print("╔══════════════════════════════════════════════════════════════╗")
print("║           MASTER OBFUSCATOR PIPELINE                        ║")
print("╚══════════════════════════════════════════════════════════════╝")
print()
print("Input:  encrypt.lua (" .. #encrypt_source .. " bytes)")
print()

local code = encrypt_source

-- Apply each layer
local layers = {
    {"Variable Mangling",     VariableMangling.process,  config.var_mangle},
    {"Number Encoding",       NumberEncoding.process,    config.number_encode},
    {"String Encryption",     StringEncryption.process,  config.string_encrypt},
    {"Table Obfuscation",     TableObfuscation.process,  config.table_obfuscate},
    {"Opaque Predicates",     OpaquePredicates.process,  config.opaque_predicates},
    {"Dead Code Injection",   DeadCode.process,          config.dead_code},
    {"Control Flow Flattening", ControlFlow.process,     config.control_flow},
}

for _, layer in ipairs(layers) do
    local name, func, cfg = layer[1], layer[2], layer[3]
    print("  Applying: " .. name .. "...")
    code = func(code, cfg)
    print("    -> " .. #code .. " bytes")
end

-- Write output
local success = write_file("obfuscated_encrypt.lua", code)
if success then
    print()
    print("✓ DONE! Output: obfuscated_encrypt.lua (" .. #code .. " bytes)")
    print()
    print("The obfuscated file includes:")
    print("  - Unicode/random variable names (hard to grep)")
    print("  - Numbers replaced with math expressions (hard to analyze)")
    print("  - Strings XOR-encrypted (decoded at runtime)")
    print("  - Table keys scrambled with fake entries")
    print("  - Always-true/false conditions (confuses static analysis)")
    print("  - Dead code injection (wastes reverse engineering time)")
    print("  - goto-based control flow flattening (unreadable)")
else
    print("ERROR: Cannot write obfuscated_encrypt.lua")
end