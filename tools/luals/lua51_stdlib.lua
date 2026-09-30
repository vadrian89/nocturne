---@meta

--- Lua 5.1 stdlib stubs: the linter reads WoW globals via .luarc.json and
--- wow_globals.lua but ships no builtin library, so string instance methods
--- like ("x"):format() get flagged as undefined fields. `or {}` keeps any
--- real definitions the engine may have.

string = string or {}

function string.format(s, ...) end
function string.find(s, pattern, init, plain) end
function string.match(s, pattern, init) end
function string.gmatch(s, pattern) end
function string.gsub(s, pattern, repl) end
function string.sub(s, i, j) end
function string.len(s) end
function string.lower(s) end
function string.upper(s) end
function string.rep(s, n) end
function string.byte(s, i, j) end
function string.char(...) end
