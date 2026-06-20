#!/usr/bin/env python3
"""
Test script for the modular variable_mangling obfuscator using lupa
"""
from lupa import LuaRuntime

def test_obfuscator():
    lua = LuaRuntime()
    
    # Set up package path
    lua.execute('package.path = package.path .. ";./modules/?.lua"')
    
    # Load the modular obfuscator
    lua.execute('VM = require("00_main")')
    VM = lua.globals().VM
    
    # Test code
    test_code = """
local function hello(name)
    local greeting = "Hello, " .. name
    print(greeting)
    return greeting
end
hello("world")
"""
    
    print("=== Original Code ===")
    print(test_code)
    print()
    
    # Run obfuscator - use Lua multiline string
    lua_code = f'VM.process([=[{test_code}]=])'
    obfuscated = lua.eval(lua_code)
    
    print("=== Obfuscated Code ===")
    print(obfuscated)
    print()
    
    # Test that obfuscated code runs correctly
    print("=== Testing Obfuscated Code Execution ===")
    try:
        # Execute the obfuscated code
        lua.execute(obfuscated)
        print("✓ Obfuscated code executed successfully!")
    except Exception as e:
        print(f"✗ Error executing obfuscated code: {e}")

def test_complex_code():
    lua = LuaRuntime()
    lua.execute('package.path = package.path .. ";./modules/?.lua"')
    lua.execute('VM = require("00_main")')
    VM = lua.globals().VM
    
    # More complex test code
    test_code = """
local counter = 0
local function fibonacci(n)
    if n <= 1 then
        return n
    end
    local a, b = 0, 1
    for i = 2, n do
        a, b = b, a + b
    end
    return b
end

for i = 1, 10 do
    print("fib(" .. i .. ") = " .. fibonacci(i))
    counter = counter + 1
end

return counter
"""
    
    print("=== Complex Test: Fibonacci ===")
    print("Original:")
    print(test_code)
    print()
    
    obfuscated = lua.eval(f'VM.process([=[{test_code}]=])')
    
    print("Obfuscated:")
    print(obfuscated[:500] + "..." if len(obfuscated) > 500 else obfuscated)
    print()
    
    # Run both and compare
    print("=== Execution Test ===")
    lua2 = LuaRuntime()
    lua2.execute(test_code)
    orig_result = lua2.globals().counter
    
    lua3 = LuaRuntime()
    lua3.execute(obfuscated)
    obf_result = lua3.globals().counter
    
    print(f"Original result: {orig_result}")
    print(f"Obfuscated result: {obf_result}")
    print(f"Results match: {'✓ YES' if orig_result == obf_result else '✗ NO'}")

if __name__ == "__main__":
    print("╔══════════════════════════════════════════════════════════════╗")
    print("║         TESTING MODULAR VARIABLE MANGLING OBFUSCATOR        ║")
    print("╚══════════════════════════════════════════════════════════════╝")
    print()
    
    test_obfuscator()
    print()
    print("─" * 60)
    print()
    test_complex_code()