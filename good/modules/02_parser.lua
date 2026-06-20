--------------------------------------------------------------------------------
-- 02_parser.lua
-- Parser: Tokens → AST (Abstract Syntax Tree)
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

return Parser
