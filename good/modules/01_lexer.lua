--------------------------------------------------------------------------------
-- 01_lexer.lua
-- Tokenizer for Lua 5.3 source code
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
        if not ep then err("unfinished long_string") end
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

return Lexer