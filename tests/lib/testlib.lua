-- Маленький раннер в духе busted: describe / it / skip и проверки eq, near, ok.
-- Тест падает на первой неудачной проверке; сообщение и строка спеки попадают в отчёт.

local T = { passed = 0, failed = 0, skipped = 0, failures = {}, stack = {} }

local function where( level )
	local info = debug.getinfo( level, "Sl" )

	return info and ( info.short_src:match( "[^/\\]+$" ) .. ":" .. info.currentline ) or "?"
end

local function fail( msg, level )
	error( { msg = msg, at = where( ( level or 2 ) + 1 ) }, 0 )
end

function T.file( name )
	io.write( "\n" .. name .. "\n" )
end

function T.loadError( name, err )
	T.failed = T.failed + 1
	T.failures[ #T.failures + 1 ] = { name = name .. " (загрузка)", msg = tostring( type( err ) == "table" and err.msg or err ) }
	io.write( "  [ОШИБКА] спека не загрузилась: " .. tostring( type( err ) == "table" and err.msg or err ) .. "\n" )
end

function T.describe( name, fn )
	table.insert( T.stack, name )
	fn()
	table.remove( T.stack )
end

local function fullName( name )
	local parts = {}

	for _, s in ipairs( T.stack ) do parts[ #parts + 1 ] = s end

	parts[ #parts + 1 ] = name

	return table.concat( parts, " › " )
end

function T.it( name, fn )
	local full = fullName( name )
	local ok, err = xpcall( fn, function( e )
		if type( e ) == "table" and e.skip then return e end
		if type( e ) == "table" and e.msg then return e end

		return { msg = tostring( e ), trace = debug.traceback( "", 2 ) }
	end )

	if ok then
		T.passed = T.passed + 1
		io.write( "  ok    " .. full .. "\n" )
	elseif err.skip then
		T.skipped = T.skipped + 1
		io.write( "  skip  " .. full .. " (" .. err.skip .. ")\n" )
	else
		T.failed = T.failed + 1
		T.failures[ #T.failures + 1 ] = { name = full, msg = err.msg, at = err.at, trace = err.trace }
		io.write( "  FAIL  " .. full .. "\n        " .. tostring( err.msg ) .. ( err.at and ( "  [" .. err.at .. "]" ) or "" ) .. "\n" )

		if err.trace and os.getenv( "TRACE" ) then io.write( err.trace .. "\n" ) end
	end
end

-- пропуск теста изнутри: T.skip( "нет файла ..." )
function T.skip( why ) error( { skip = why }, 0 ) end

-- пропускает всю группу, если нужного файла аддона ещё нет на этой ветке
function T.requires( gm, ... )
	for _, path in ipairs( { ... } ) do
		if not gm.exists( path ) then return false, "нет " .. path end
	end

	return true
end

function T.ok( v, msg )
	if not v then fail( msg or "ожидалось истинное значение", 2 ) end

	return v
end

function T.eq( a, b, msg )
	if a ~= b then fail( string.format( "%sожидалось %s, получено %s", msg and ( msg .. ": " ) or "", tostring( b ), tostring( a ) ), 2 ) end
end

function T.near( a, b, tol, msg )
	if type( a ) ~= "number" or type( b ) ~= "number" or a ~= a or math.abs( a - b ) > tol then
		fail( string.format( "%sожидалось %s ± %s, получено %s", msg and ( msg .. ": " ) or "", tostring( b ), tostring( tol ), tostring( a ) ), 2 )
	end
end

function T.summary()
	io.write( string.format( "\nИтого: %d прошло, %d упало, %d пропущено\n", T.passed, T.failed, T.skipped ) )

	if T.failed > 0 then
		io.write( "\nУпавшие:\n" )

		for _, f in ipairs( T.failures ) do
			io.write( "  - " .. f.name .. "\n      " .. tostring( f.msg ) .. ( f.at and ( "  [" .. f.at .. "]" ) or "" ) .. "\n" )
		end
	end

	return T.failed == 0
end

return T
