--------------------------------------------------------------------------------
-- 04_renamer.lua
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

return Renamer