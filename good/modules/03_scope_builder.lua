--------------------------------------------------------------------------------
-- 03_scope_builder.lua
-- Builds scope tree + symbol table and resolves all Name references
--
-- Scope kinds: "global", "function", "block", "loop"
-- Each Scope has:
--   .kind          string
--   .parent        Scope | nil
--   .symbols       { name → Symbol }
--   .children      { Scope }
--
-- Symbol:
--   .name          original name string
--   .scope         owning Scope
--   .decl_node     AST NameNode of the declaration
--   .refs          { AST NameNode }   all use-sites (including decl)
--   .is_upvalue    bool (set during resolve)
--   .new_name      string | nil (filled by renamer)
--------------------------------------------------------------------------------

local STDLIB = {
    _G=1,_ENV=1,_VERSION=1,assert=1,bit32=1,collectgarbage=1,
    coroutine=1,debug=1,dofile=1,error=1,getmetatable=1,io=1,
    ipairs=1,load=1,loadfile=1,math=1,next=1,os=1,pairs=1,
    pcall=1,print=1,rawequal=1,rawget=1,rawlen=1,rawset=1,
    require=1,select=1,setmetatable=1,string=1,table=1,
    tonumber=1,tostring=1,type=1,unpack=1,xpcall=1,self=1,
}

local function new_scope(kind, parent)
    return {kind=kind, parent=parent, symbols={}, children={}}
end

local function scope_define(scope, name, decl_node)
    local sym = {name=name, scope=scope, decl_node=decl_node,
                 refs={decl_node}, is_upvalue=false, new_name=nil}
    scope.symbols[name] = sym
    return sym
end

local function scope_lookup(scope, name)
    local s = scope
    while s do
        if s.symbols[name] then return s.symbols[name], s end
        s = s.parent
    end
    return nil
end

local function ScopeBuilder(ast)
    local global_scope = new_scope("global", nil)
    -- pre-populate stdlib so we never rename them
    for name in pairs(STDLIB) do
        scope_define(global_scope, name, nil)
        global_scope.symbols[name].stdlib = true
    end

    local function push(kind, parent)
        local s = new_scope(kind, parent)
        parent.children[#parent.children+1] = s
        return s
    end

    -- Forward declare
    local walk_block, walk_stat, walk_expr

    walk_expr = function(node, scope)
        if not node then return end
        local k = node.kind

        if k=="Name" then
            -- Resolve: find the symbol this name refers to
            local sym = scope_lookup(scope, node.name)
            if sym then
                -- Mark as upvalue if defined in an enclosing function scope
                local s = scope
                while s and s ~= sym.scope do
                    if s.kind=="function" then sym.is_upvalue=true; break end
                    s = s.parent
                end
                sym.refs[#sym.refs+1] = node
                node.resolved_sym = sym
            else
                -- Global reference: define lazily in global scope
                local gsym = scope_define(global_scope, node.name, node)
                gsym.is_global = true
                node.resolved_sym = gsym
            end

        elseif k=="Index" then
            walk_expr(node.obj, scope)
            if not node.is_dot then walk_expr(node.key, scope) end
            -- dot-access: node.key is a String node, NOT a Name — don't resolve

        elseif k=="Call" then
            walk_expr(node.func, scope)
            for _,a in ipairs(node.args) do walk_expr(a, scope) end

        elseif k=="MethodCall" then
            walk_expr(node.obj, scope)
            for _,a in ipairs(node.args) do walk_expr(a, scope) end

        elseif k=="FuncExpr" then
            local fs = push("function", scope)
            node.body.scope_ref = fs
            for _,p in ipairs(node.body.params) do
                local sym = scope_define(fs, p.name, p)
                p.resolved_sym = sym
            end
            walk_block(node.body.body, fs)

        elseif k=="Table" then
            for _,f in ipairs(node.fields) do
                if f.kind=="FieldBracket" then
                    walk_expr(f.key, scope); walk_expr(f.value, scope)
                elseif f.kind=="FieldName" then
                    -- key is a Name used as a string key: do NOT resolve as variable
                    walk_expr(f.value, scope)
                else
                    walk_expr(f.value, scope)
                end
            end

        elseif k=="BinOp" then
            walk_expr(node.left, scope); walk_expr(node.right, scope)

        elseif k=="UnOp" then
            walk_expr(node.operand, scope)

        elseif k=="Paren" then
            walk_expr(node.expr, scope)
        end
    end

    walk_stat = function(node, scope)
        local k = node.kind

        if k=="Local" then
            -- Evaluate RHS in current scope BEFORE defining LHS (shadowing semantics)
            for _,v in ipairs(node.values) do walk_expr(v, scope) end
            for _,n in ipairs(node.names) do
                local sym = scope_define(scope, n.name, n)
                n.resolved_sym = sym
            end

        elseif k=="LocalFunc" then
            -- Name visible inside body (recursive)
            local sym = scope_define(scope, node.name.name, node.name)
            node.name.resolved_sym = sym
            local fs = push("function", scope)
            node.body.scope_ref = fs
            for _,p in ipairs(node.body.params) do
                local psym = scope_define(fs, p.name, p)
                p.resolved_sym = psym
            end
            walk_block(node.body.body, fs)

        elseif k=="FuncStat" then
            -- function a.b.c() — only first name is a variable reference
            walk_expr(node.chain[1], scope)
            -- remaining chain parts are field names, skip resolve
            local fs = push("function", scope)
            node.body.scope_ref = fs
            -- method implicitly defines 'self'
            if node.method then
                local ssym = scope_define(fs, "self", nil)
                ssym.stdlib = true
            end
            for _,p in ipairs(node.body.params) do
                local psym = scope_define(fs, p.name, p)
                p.resolved_sym = psym
            end
            walk_block(node.body.body, fs)

        elseif k=="Assign" then
            for _,l in ipairs(node.lhs) do walk_expr(l, scope) end
            for _,r in ipairs(node.rhs) do walk_expr(r, scope) end

        elseif k=="CallStat" then
            walk_expr(node.call, scope)

        elseif k=="Do" then
            local bs = push("block", scope)
            walk_block(node.block, bs)

        elseif k=="While" then
            walk_expr(node.cond, scope)
            local ls = push("loop", scope)
            walk_block(node.block, ls)

        elseif k=="Repeat" then
            local ls = push("loop", scope)
            walk_block(node.block, ls)
            walk_expr(node.cond, ls)  -- until sees block's locals

        elseif k=="NumFor" then
            walk_expr(node.start, scope)
            walk_expr(node.limit, scope)
            if node.step then walk_expr(node.step, scope) end
            local ls = push("loop", scope)
            local vsym = scope_define(ls, node.var.name, node.var)
            node.var.resolved_sym = vsym
            walk_block(node.block, ls)

        elseif k=="GenFor" then
            for _,it in ipairs(node.iters) do walk_expr(it, scope) end
            local ls = push("loop", scope)
            for _,n in ipairs(node.names) do
                local sym = scope_define(ls, n.name, n)
                n.resolved_sym = sym
            end
            walk_block(node.block, ls)

        elseif k=="If" then
            walk_expr(node.cond, scope)
            walk_block(node.then_block, push("block", scope))
            for _,ei in ipairs(node.elseifs) do
                walk_expr(ei.cond, scope)
                walk_block(ei.block, push("block", scope))
            end
            if node.else_block then
                walk_block(node.else_block, push("block", scope))
            end

        elseif k=="Return" then
            for _,v in ipairs(node.values) do walk_expr(v, scope) end

        elseif k=="Break" or k=="Goto" or k=="Label" then
            -- nothing to resolve
        end
    end

    walk_block = function(block, scope)
        block.scope_ref = scope
        for _,s in ipairs(block.stats) do
            walk_stat(s, scope)
        end
    end

    walk_block(ast, global_scope)
    return global_scope
end

return ScopeBuilder