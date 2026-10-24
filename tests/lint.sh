#!/usr/bin/env bash
# Линтер: переписывает синтаксис GLua (continue, !=, &&, ...) во временную копию lua/ с теми
# же номерами строк и прогоняет по ней luacheck с tests/.luacheckrc.
# Нужны luajit и luacheck (luarocks install luacheck).
#   tests/lint.sh            весь lua/
#   SKYOPS_ROOT=... tests/lint.sh   другой корень аддона
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SKYOPS_ROOT:-$HERE/..}" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

luajit - "$ROOT" "$TMP" "$HERE/lib/glua_prep.lua" <<'EOF'
local src, dst, prepPath = arg[1], arg[2], arg[3]
local prep = dofile( prepPath )
local p = io.popen( 'cd "' .. src .. '" && find lua -name "*.lua"' )

for path in p:lines() do
	local f = assert( io.open( src .. "/" .. path, "rb" ) )
	local s = f:read( "*a" )

	f:close()
	os.execute( 'mkdir -p "' .. dst .. "/" .. path:match( "^(.*)/" ) .. '"' )

	local o = assert( io.open( dst .. "/" .. path, "wb" ) )

	o:write( prep( s ) )
	o:close()
end

p:close()
EOF

cd "$TMP"
SKYOPS_LINT_SRC="$TMP/lua" luacheck --config "$HERE/.luacheckrc" lua
