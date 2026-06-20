--------------------------------------------------------------------------------
-- lua_obfuscator.lua
-- Pipeline: Lexer → Parser → AST → Scope Tree → Symbol Table →
--           Name Resolver → Renamer → Code Generator
--------------------------------------------------------------------------------

local VariableMangling = {}

--------------------------------------------------------------------------------
-- SECTION 1: LEXER
--------------------------------------------------------------------------------

local KEYWORDS = {
    ["and"]=1,["break"]=1,["do"]=1,["else"]=1,["elseif"]=1,["end"]=1,
    ["false"]=1,["for"]=1,["function"]=1,["goto"]=1,["if"]=1,["in"]=1,
    ["local"]=1,["nil"]=1,["not"]=1,["or"]=1,["repeat"]=1,["return"]=1,
    ["then"]=1,["true"]=1,["until"]=1,["while"]=1,
}

local function Lexer(src)
    local self = { src=src, pos=1, line=1, tokens={} }

    local function err(msg) error(("Lexer:%d: %s"):format(self.line, msg)) end

    local function peek(off) return src:sub(self.pos+(off or 0), self.pos+(off or 0)) end

    local function adv(n)
        n = n or 1
        local s = src:sub(self.pos, self.pos+n-1)
        for _ in s:gmatch("\n") do self.line = self.line+1 end
        self.pos = self.pos + n
        return s
    end

    local function read_long()
        local eq = src:match("^%[=*%[", self.pos)
        if not eq then return nil end
        local level = #eq - 2
        local close = "]" .. ("="):rep(level) .. "]"
        local sp = self.pos
        self.pos = self.pos + #eq
        local ep = src:find(close, self.pos, true)
        if not ep then err("unfinished long string") end
        local text = src:sub(sp, ep + #close - 1)
        for _ in text:gmatch("\n") do self.line = self.line+1 end
        self.pos = ep + #close
        return text
    end

    local function read_str()
        local q = adv()
        local buf = {q}
        while self.pos <= #src do
            local c = peek()
            if c == "\\" then buf[#buf+1]=adv(2)
            elseif c == q then buf[#buf+1]=adv(); break
            elseif c=="\n" or c=="\r" then err("unfinished string")
            else buf[#buf+1]=adv() end
        end
        return table.concat(buf)
    end

    local function emit(typ, text, line)
        self.tokens[#self.tokens+1] = {type=typ, text=text, line=line or self.line}
    end

    function self:tokenize()
        while self.pos <= #src do
            local line = self.line
            local c = peek()

            -- whitespace / newline (preserve for codegen)
            if c:match("[ \t\r\n]") then
                local s = src:match("^[ \t\r\n]+", self.pos)
                for _ in s:gmatch("\n") do self.line=self.line+1 end
                self.pos = self.pos + #s
                emit("WS", s, line)

            -- long comment
            elseif src:sub(self.pos,self.pos+1)=="--" and src:match("^%-%-%[=*%[", self.pos) then
                self.pos = self.pos + 2
                emit("COMMENT", "--"..read_long(), line)

            -- short comment
            elseif src:sub(self.pos,self.pos+1)=="--" then
                local s = src:match("^%-%-[^\n]*", self.pos)
                self.pos = self.pos + #s
                emit("COMMENT", s, line)

            -- long string
            elseif src:match("^%[=*%[", self.pos) then
                emit("STRING", read_long(), line)

            -- quoted string
            elseif c=='"' or c=="'" then
                emit("STRING", read_str(), line)

            -- hex / float / int
            elseif c:match("%d") or (c=="." and peek(1):match("%d")) then
                local s = src:match("^0[xX][%x]+", self.pos)
                       or src:match("^%d+%.?%d*[eE][+-]?%d+", self.pos)
                       or src:match("^%d*%.%d+", self.pos)
                       or src:match("^%d+", self.pos)
                self.pos = self.pos + #s
                emit("NUMBER", s, line)

            -- name / keyword
            elseif c:match("[%a_]") then
                local s = src:match("^[%a_][%w_]*", self.pos)
                self.pos = self.pos + #s
                emit(KEYWORDS[s] and "KW" or "NAME", s, line)

            -- multi-char punct
            else
                local m = src:match("^%.%.%.", self.pos)
                       or src:match("^%.%.", self.pos)
                       or src:match("^[~<>=!]=", self.pos)
                       or src:match("^::", self.pos)
                       or src:match("^[<>][<>]", self.pos)
                if m then self.pos=self.pos+#m; emit("PUNCT", m, line)
                else emit("PUNCT", adv(), line) end
            end
        end
        emit("EOF", "", self.line)
        return self.tokens
    end

    return self
end

--------------------------------------------------------------------------------
-- SECTION 2: PARSER → AST
-- Produces a full AST with node types covering all Lua 5.3 constructs.
-- Every NameNode carries a `.token_ref` pointing back to the raw token
-- so the renamer can patch it directly.
--------------------------------------------------------------------------------

local function Parser(tokens)
    local self = { tokens=tokens, pos=1 }

    -- Skip whitespace/comment tokens transparently, but keep them in a side list
    -- so the code generator can replay them.
    local meaningful = {}  -- indices into tokens that are not WS/COMMENT
    for i,t in ipairs(tokens) do
        if t.type ~= "WS" and t.type ~= "COMMENT" then
            meaningful[#meaningful+1] = i
        end
    end
    local mp = 1  -- pointer into meaningful[]

    local function cur()  return tokens[meaningful[mp]] end
    local function peek2() return tokens[meaningful[mp+1]] end

    local function err(msg)
        local t = cur()
        error(("Parser:%d: %s (got '%s')"):format(t and t.line or 0, msg, t and t.text or "EOF"))
    end

    local function check(typ, text)
        local t = cur()
        if not t then return false end
        if typ and t.type ~= typ then return false end
        if text and t.text ~= text then return false end
        return true
    end

    local function expect(typ, text)
        if not check(typ, text) then
            err(("expected %s '%s'"):format(typ or "?", text or "?"))
        end
        local t = cur(); mp = mp+1; return t
    end

    local function match(typ, text)
        if check(typ, text) then
            local t = cur(); mp = mp+1; return t
        end
    end

    -- AST node constructors
    local function Node(kind, data)
        data.kind = kind; return data
    end

    local function NameNode(tok)
        -- .token_ref → the actual token table; renamer writes tok.text directly
        return Node("Name", {name=tok.text, token_ref=tok, line=tok.line})
    end

    -- Forward declarations
    local parse_expr, parse_stat, parse_block

    -------- Expressions --------

    local function parse_name()
        local tok = expect("NAME")
        return NameNode(tok)
    end

    local function parse_namelist()
        local list = {parse_name()}
        while match("PUNCT", ",") do list[#list+1]=parse_name() end
        return list
    end

    local function parse_funcbody()
        expect("PUNCT","(")
        local params, has_vararg = {}, false
        if not check("PUNCT",")") then
            if check("PUNCT","...") then
                has_vararg=true; mp=mp+1
            else
                params = parse_namelist()
                if match("PUNCT",",") then
                    expect("PUNCT","...")
                    has_vararg=true
                end
            end
        end
        expect("PUNCT",")")
        local body = parse_block()
        expect("KW","end")
        return Node("FuncBody",{params=params, has_vararg=has_vararg, body=body})
    end

    local function parse_field()
        -- [expr]=expr | name=expr | expr
        if check("PUNCT","[") then
            mp=mp+1
            local k=parse_expr(); expect("PUNCT","]"); expect("PUNCT","=")
            return Node("FieldBracket",{key=k, value=parse_expr()})
        elseif check("NAME") and peek2() and peek2().text=="=" then
            local k=parse_name(); mp=mp+1
            return Node("FieldName",{key=k, value=parse_expr()})
        else
            return Node("FieldSeq",{value=parse_expr()})
        end
    end

    local function parse_table()
        expect("PUNCT","{")
        local fields={}
        while not check("PUNCT","}") do
            fields[#fields+1]=parse_field()
            if not match("PUNCT",",") then match("PUNCT",";") end
        end
        expect("PUNCT","}")
        return Node("Table",{fields=fields})
    end

    local function parse_args()
        if check("PUNCT","(") then
            mp=mp+1
            local args={}
            if not check("PUNCT",")") then
                args[#args+1]=parse_expr()
                while match("PUNCT",",") do args[#args+1]=parse_expr() end
            end
            expect("PUNCT",")")
            return args
        elseif check("PUNCT","{") then
            return {parse_table()}
        elseif check("STRING") then
            local t=cur(); mp=mp+1
            return {Node("String",{value=t.text})}
        else
            err("expected function arguments")
        end
    end

    -- Primary: name | (expr)
    local function parse_primary()
        if check("NAME") then
            return parse_name()
        elseif check("PUNCT","(") then
            mp=mp+1
            local e=parse_expr()
            expect("PUNCT",")")
            return Node("Paren",{expr=e})
        else
            err("expected primary expression")
        end
    end

    -- Suffixed: primary { .name | [expr] | :name args | args }
    local function parse_suffixed()
        local base = parse_primary()
        local node = base
        while true do
            if check("PUNCT",".") then
                mp=mp+1
                local field = expect("NAME")
                node = Node("Index", {obj=node, key=Node("String",{value=field.text, token_ref=field}), is_dot=true})
            elseif check("PUNCT","[") then
                mp=mp+1
                local k=parse_expr(); expect("PUNCT","]")
                node = Node("Index",{obj=node, key=k, is_dot=false})
            elseif check("PUNCT",":") then
                mp=mp+1
                local method=expect("NAME")
                local args=parse_args()
                node = Node("MethodCall",{obj=node, method=method.text, args=args})
            elseif check("PUNCT","(") or check("PUNCT","{") or check("STRING") then
                local args=parse_args()
                node = Node("Call",{func=node, args=args})
            else
                break
            end
        end
        return node
    end

    local UNOPS = {["-"]=1,["not"]=1,["#"]=1,["~"]=1}
    local BINOP_PRIO = {
        ["or"]={1,1},["and"]={2,2},
        ["<"]={3,3},["<="]={3,3},[">"]={3,3},[">="]={3,3},
        ["=="]={3,3},["~="]={3,3},
        ["|"]={4,4},["~"]={5,5},["&"]={6,6},
        ["<<"]={7,7},[">>"]={7,7},
        [".."]={8,7},   -- right-associative
        ["+"]={9,9},["-"]={9,9},
        ["*"]={10,10},{["/"]={10,10},["%"]={10,10},["//"]={10,10}},
        ["^"]={12,11},  -- right-associative
    }
    -- flatten nested tables in BINOP_PRIO
    for k,v in pairs({["/"]={10,10},["%"]={10,10},["//"]={10,10}}) do BINOP_PRIO[k]=v end

    local function get_binop()
        local t = cur()
        if not t then return nil end
        local txt = t.text
        local typ = t.type
        if (typ=="KW" and (txt=="and" or txt=="or")) or
           (typ=="PUNCT" and BINOP_PRIO[txt]) then
            return txt
        end
        return nil
    end

    local function parse_simple_expr()
        local t = cur()
        if t.type=="NUMBER" then mp=mp+1; return Node("Number",{value=t.text})
        elseif t.type=="STRING" then mp=mp+1; return Node("String",{value=t.text})
        elseif t.text=="nil" then mp=mp+1; return Node("Nil",{})
        elseif t.text=="true" then mp=mp+1; return Node("True",{})
        elseif t.text=="false" then mp=mp+1; return Node("False",{})
        elseif t.text=="..." then mp=mp+1; return Node("Vararg",{})
        elseif t.text=="function" then mp=mp+1; return Node("FuncExpr",{body=parse_funcbody()})
        elseif t.type=="PUNCT" and t.text=="{" then return parse_table()
        elseif UNOPS[t.text] then
            mp=mp+1
            local operand=parse_expr(11)  -- unary binds tight
            return Node("UnOp",{op=t.text, operand=operand})
        else
            return parse_suffixed()
        end
    end

    parse_expr = function(min_prio)
        min_prio = min_prio or 0
        local left = parse_simple_expr()
        while true do
            local op = get_binop()
            if not op then break end
            local prio = BINOP_PRIO[op]
            if not prio or prio[1] <= min_prio then break end
            mp=mp+1
            local right = parse_expr(prio[2])
            left = Node("BinOp",{op=op, left=left, right=right})
        end
        return left
    end

    -------- Statements --------

    local function parse_attrib()
        -- Lua 5.4: <const> or <close>
        if match("PUNCT","<") then
            local attr=expect("NAME"); expect("PUNCT",">")
            return attr.text
        end
        return nil
    end

    local function parse_local_stat()
        -- local function name body | local namelist attrib [= exprlist]
        if match("KW","function") then
            local name=parse_name()
            local body=parse_funcbody()
            return Node("LocalFunc",{name=name, body=body})
        else
            local names={}
            local attribs={}
            names[1]=parse_name(); attribs[1]=parse_attrib()
            while match("PUNCT",",") do
                names[#names+1]=parse_name()
                attribs[#attribs+1]=parse_attrib()
            end
            local values={}
            if match("PUNCT","=") then
                values[1]=parse_expr()
                while match("PUNCT",",") do values[#values+1]=parse_expr() end
            end
            return Node("Local",{names=names, attribs=attribs, values=values})
        end
    end

    local function parse_assign_or_call(base)
        -- Already parsed a suffixed expression as `base`.
        -- Could be: assignment (lhs list = rhs list) or a call statement.
        if base.kind=="Call" or base.kind=="MethodCall" then
            return Node("CallStat",{call=base})
        end
        -- Collect lhs list
        local lhs={base}
        while match("PUNCT",",") do lhs[#lhs+1]=parse_suffixed() end
        expect("PUNCT","=")
        local rhs={parse_expr()}
        while match("PUNCT",",") do rhs[#rhs+1]=parse_expr() end
        return Node("Assign",{lhs=lhs, rhs=rhs})
    end

    parse_stat = function()
        local t = cur()

        if t.text=="if" then
            mp=mp+1
            local cond=parse_expr(); expect("KW","then")
            local then_block=parse_block()
            local elseif_list={}
            local else_block=nil
            while check("KW","elseif") do
                mp=mp+1
                local c=parse_expr(); expect("KW","then")
                elseif_list[#elseif_list+1]={cond=c, block=parse_block()}
            end
            if match("KW","else") then else_block=parse_block() end
            expect("KW","end")
            return Node("If",{cond=cond, then_block=then_block,
                               elseifs=elseif_list, else_block=else_block})

        elseif t.text=="while" then
            mp=mp+1
            local cond=parse_expr(); expect("KW","do")
            local block=parse_block(); expect("KW","end")
            return Node("While",{cond=cond, block=block})

        elseif t.text=="do" then
            mp=mp+1; local block=parse_block(); expect("KW","end")
            return Node("Do",{block=block})

        elseif t.text=="for" then
            mp=mp+1
            local first=parse_name()
            if match("PUNCT","=") then
                -- numeric for
                local start=parse_expr(); expect("PUNCT",",")
                local limit=parse_expr()
                local step=nil
                if match("PUNCT",",") then step=parse_expr() end
                expect("KW","do"); local block=parse_block(); expect("KW","end")
                return Node("NumFor",{var=first, start=start, limit=limit,
                                      step=step, block=block})
            else
                -- generic for
                local names={first}
                while match("PUNCT",",") do names[#names+1]=parse_name() end
                expect("KW","in")
                local iters={parse_expr()}
                while match("PUNCT",",") do iters[#iters+1]=parse_expr() end
                expect("KW","do"); local block=parse_block(); expect("KW","end")
                return Node("GenFor",{names=names, iters=iters, block=block})
            end

        elseif t.text=="repeat" then
            mp=mp+1; local block=parse_block()
            expect("KW","until"); local cond=parse_expr()
            return Node("Repeat",{block=block, cond=cond})

        elseif t.text=="function" then
            mp=mp+1
            -- function a.b.c:d() ... end
            local name=parse_name()
            local chain={name}
            local method=nil
            while check("PUNCT",".") do
                mp=mp+1; chain[#chain+1]=parse_name()
            end
            if match("PUNCT",":") then method=expect("NAME") end
            local body=parse_funcbody()
            return Node("FuncStat",{chain=chain, method=method, body=body})

        elseif t.text=="local" then
            mp=mp+1; return parse_local_stat()

        elseif t.text=="return" then
            mp=mp+1
            local vals={}
            if not (check("KW","end") or check("KW","else") or
                    check("KW","elseif") or check("KW","until") or
                    check("EOF") or (check("PUNCT",";") )) then
                vals[1]=parse_expr()
                while match("PUNCT",",") do vals[#vals+1]=parse_expr() end
            end
            match("PUNCT",";")
            return Node("Return",{values=vals})

        elseif t.text=="break" then
            mp=mp+1; return Node("Break",{})

        elseif t.text=="goto" then
            mp=mp+1; local lbl=expect("NAME")
            return Node("Goto",{label=lbl.text})

        elseif t.text=="::" then
            mp=mp+1; local lbl=expect("NAME"); expect("PUNCT","::")
            return Node("Label",{label=lbl.text})

        elseif t.type=="NAME" or t.text=="(" then
            local base=parse_suffixed()
            return parse_assign_or_call(base)

        else
            return nil  -- block terminator
        end
    end

    parse_block = function()
        local stats={}
        while true do
            -- skip semicolons
            while match("PUNCT",";") do end
            local t=cur()
            if not t or t.type=="EOF"
               or t.text=="end" or t.text=="else"
               or t.text=="elseif" or t.text=="until" then
                break
            end
            if t.text=="return" then
                stats[#stats+1]=parse_stat()
                match("PUNCT",";")
                break
            end
            local s=parse_stat()
            if not s then break end
            stats[#stats+1]=s
        end
        return Node("Block",{stats=stats})
    end

    function self:parse()
        local block = parse_block()
        expect("EOF")
        return block
    end

    return self
end

--------------------------------------------------------------------------------
-- SECTION 3: SCOPE TREE + SYMBOL TABLE
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

--------------------------------------------------------------------------------
-- SECTION 4: RENAMER
-- Walks the scope tree; for every symbol that is renameable, assigns new_name.
-- Renameable = not stdlib, not global, not upvalue-captured across API boundary.
--------------------------------------------------------------------------------

local HOMOGLYPHS = {
    a="\xD0\xB0", e="\xD0\xB5", o="\xD0\xBE",
    p="\xD1\x80", c="\xD1\x81", x="\xD1\x85", i="\xD1\x96",
}

local function name_hash(name, salt)
    local h = salt or 0x5A3C
    for k=1,#name do h=((h*31)~string.byte(name,k))&0xFFFFFF end
    return h
end

local function build_name(original, salt, config)
    local seed = name_hash(original, salt)
    math.randomseed(seed)
    local len = math.random(config.name_length_min, config.name_length_max)
    -- Build base from random identifier chars
    local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_"
    local rng = seed
    local buf = {}
    -- First char must not be digit
    rng = (rng*6364136223846793005+1)&0xFFFFFFFF
    buf[1] = chars:sub((rng%#chars)+1,(rng%#chars)+1)
    local all_chars = chars.."0123456789"
    for i=2,config.name_length_max do
        rng = (rng*6364136223846793005+1442695040888963407)&0xFFFFFFFF
        local c = all_chars:sub((rng%#all_chars)+1,(rng%#all_chars)+1)
        -- inject homoglyph occasionally
        buf[i] = ((rng%4==0) and HOMOGLYPHS[c]) or c
    end
    return table.concat(buf)
end

local function Renamer(global_scope, config)
    local salt = os.time() ~ (math.random(0,0xFFFF)*0x10001)
    local used = {}

    local function is_renameable(sym)
        if not sym then return false end
        if sym.stdlib then return false end
        if sym.is_global then return false end  -- don't rename globals we don't own
        return true
    end

    local function assign_names(scope)
        for name, sym in pairs(scope.symbols) do
            if is_renameable(sym) then
                local new
                local attempt = 0
                repeat
                    new = build_name(name..attempt, salt, config)
                    attempt = attempt + 1
                until not used[new]
                used[new] = true
                sym.new_name = new
            end
        end
        for _,child in ipairs(scope.children) do
            assign_names(child)
        end
    end

    assign_names(global_scope)
end

--------------------------------------------------------------------------------
-- SECTION 5: CODE GENERATOR
-- Replays the original token stream (preserving whitespace/comments exactly),
-- but wherever a token is the `.token_ref` of a NameNode whose symbol has
-- a `.new_name`, emits the new name instead.
--
-- We build a set of token pointers that need replacement first.
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

--------------------------------------------------------------------------------
-- SECTION 6: PUBLIC API
--------------------------------------------------------------------------------

function Obfuscator.process(code, config)
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
