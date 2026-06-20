--------------------------------------------------------------------------------
-- variable_mangling.lua
-- Modular Lua Obfuscator: Variable Name Mangling
-- Pipeline: Lexer → Parser → AST → Scope Tree → Symbol Table →
--           Name Resolver → Renamer → Code Generator
--------------------------------------------------------------------------------

local VariableMangling = {}

local Lexer = require("modules.01_lexer")
local Parser = require("modules.02_parser")
local ScopeBuilder = require("modules.03_scope_builder")
local Renamer = require("modules.04_renamer")
local CodeGen = require("modules.05_codegen")

--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

function VariableMangling.process(code, config)
    config = config or {}
    config.enabled = config.enabled ~= false
    config.name_length_min = config.name_length_min or 12
    config.name_length_max = config.name_length_max or 16

    if not config.enabled then return code end

    -- 1. Lex
    local tokens = Lexer(code):tokenize()

    -- 2. Parse → AST
    local ast = Parser(tokens):parse()

    -- 3. Build scope tree + symbol table + resolve all Name references
    local global_scope = ScopeBuilder(ast)

    -- 4. Assign obfuscated names to every renameable symbol
    Renamer(global_scope, config)

    -- 5. Patch token stream and emit
    return CodeGen(tokens, global_scope)
end

return VariableMangling