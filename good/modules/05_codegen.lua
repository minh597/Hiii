--------------------------------------------------------------------------------
-- 05_codegen.lua
-- Replays the original token stream (preserving whitespace/comments exactly),
-- but wherever a token is the `.token_ref` of a NameNode whose symbol has
-- a `.new_name`, emits the new name instead.
--------------------------------------------------------------------------------

local function CodeGen(tokens, global_scope)
    -- Collect all Name nodes that have resolved symbols with new_name.
    -- We patch token_ref.text directly so the token stream replay is O(n).
    local function patch_scope(scope)
        for _,sym in pairs(scope.symbols) do
            if sym.new_name then
                -- Patch all ref nodes
                for _,ref_node in ipairs(sym.refs) do
                    if ref_node and ref_node.token_ref then
                        ref_node.token_ref.text = sym.new_name
                    end
                end
                -- Patch decl node too (might not be in refs for stdlib)
                if sym.decl_node and sym.decl_node.token_ref then
                    sym.decl_node.token_ref.text = sym.new_name
                end
            end
        end
        for _,child in ipairs(scope.children) do patch_scope(child) end
    end

    patch_scope(global_scope)

    -- Replay token stream verbatim (text already patched in-place)
    local out = {}
    for _,tok in ipairs(tokens) do
        out[#out+1] = tok.text
    end
    return table.concat(out)
end

return CodeGen