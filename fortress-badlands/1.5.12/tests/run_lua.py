from pathlib import Path
import ctypes, os, sys
lua=ctypes.CDLL('liblua5.4.so.0')
lua.luaL_newstate.restype=ctypes.c_void_p
lua.luaL_openlibs.argtypes=[ctypes.c_void_p]
lua.luaL_loadfilex.argtypes=[ctypes.c_void_p,ctypes.c_char_p,ctypes.c_char_p]
lua.luaL_loadfilex.restype=ctypes.c_int
lua.lua_pcallk.argtypes=[ctypes.c_void_p,ctypes.c_int,ctypes.c_int,ctypes.c_int,ctypes.c_longlong,ctypes.c_void_p]
lua.lua_pcallk.restype=ctypes.c_int
lua.lua_tolstring.argtypes=[ctypes.c_void_p,ctypes.c_int,ctypes.c_void_p]
lua.lua_tolstring.restype=ctypes.c_char_p
lua.lua_close.argtypes=[ctypes.c_void_p]
os.chdir(Path(__file__).resolve().parent.parent)
for src in [*sys.argv[1:]]:
    state=lua.luaL_newstate();lua.luaL_openlibs(state)
    code=lua.luaL_loadfilex(state,src.encode(),None)
    if not code: code=lua.lua_pcallk(state,0,-1,0,0,None)
    if code:
        print('FAILED:',src,lua.lua_tolstring(state,-1,None).decode('utf-8'),file=sys.stderr)
        sys.exit(1)
    print('Checked:',src)
    lua.lua_close(state)
