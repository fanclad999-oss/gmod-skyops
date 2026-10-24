-- Запуск тестов: luajit tests/run.lua [фильтр]
-- Ищет tests/spec/*_spec.lua, в каждом файле describe/it как в busted, но без зависимостей.
-- SKYOPS_ROOT: корень аддона с папкой lua/ (по умолчанию текущая папка).
-- Код выхода 1, если есть упавшие тесты.

local HERE = debug.getinfo( 1, "S" ).source:match( "^@(.*[/\\])" ) or "./"

package.path = HERE .. "lib/?.lua;" .. package.path

local gm = dofile( HERE .. "lib/gmod.lua" )
local T = dofile( HERE .. "lib/testlib.lua" )

local filter = arg[ 1 ]
local specs = {}
local p = io.popen( 'ls -1 "' .. HERE .. 'spec"' )

for name in p:lines() do
	if name:match( "_spec%.lua$" ) and ( not filter or name:find( filter, 1, true ) ) then specs[ #specs + 1 ] = name end
end

p:close()
table.sort( specs )

for _, name in ipairs( specs ) do
	T.file( name )

	local chunk, err = loadfile( HERE .. "spec/" .. name )

	if not chunk then
		T.loadError( name, err )
	else
		local ok, e = pcall( chunk, gm, T )

		if not ok then T.loadError( name, e ) end
	end
end

os.exit( T.summary() and 0 or 1 )
