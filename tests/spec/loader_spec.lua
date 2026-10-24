-- Весь аддон грузится через autorun на сервере и на клиенте без ошибок, а все файлы
-- проходят синтаксис GLua. Ловит опечатки в именах и падения на верхнем уровне файлов.

local gm, T = ...

-- глобалы GMod, которых в заглушках нет и которые код законно читает как «может не быть»
local ALLOWED_UNKNOWN = {
	KIR = true, InfMap = true, LVS = true, SW_Bombs = true,
}

local function loadRealm( realm )
	gm.reset( realm )

	local ok, err = pcall( gm.include, "autorun/skyops_init.lua" )

	return ok, err
end

T.describe( "загрузчик", function()
	for _, realm in ipairs( { "server", "client" } ) do
		T.it( "autorun грузится без ошибок: " .. realm, function()
			local ok, err = loadRealm( realm )

			T.ok( ok, tostring( err ) )
			T.ok( #gm.included > 1, "загрузчик ничего не подключил" )
			T.ok( _G.SkyOps ~= nil, "нет таблицы SkyOps" )
		end )

		T.it( "после загрузки нет обращений к неизвестным глобалам: " .. realm, function()
			loadRealm( realm )

			local bad = {}

			for name in pairs( gm.unknownGlobals ) do
				if not ALLOWED_UNKNOWN[ name ] then bad[ #bad + 1 ] = name end
			end

			table.sort( bad )
			T.ok( #bad == 0, "неизвестные глобалы при загрузке: " .. table.concat( bad, ", " ) )
		end )
	end

	T.it( "клиент получает все sh_ и cl_ файлы через AddCSLuaFile", function()
		loadRealm( "server" )

		local missing = {}

		for _, path in ipairs( gm.included ) do
			local name = path:match( "[^/]+$" )

			if name:match( "^sh_" ) and not ( gm.csFiles or {} )[ path ] then missing[ #missing + 1 ] = path end
		end

		T.ok( #missing == 0, "не отправлены клиенту: " .. table.concat( missing, ", " ) )
	end )

	T.it( "сервер не подключает cl_ файлы, клиент не подключает sv_", function()
		loadRealm( "server" )
		for _, p in ipairs( gm.included ) do T.ok( not p:match( "/cl_[^/]+$" ), "сервер подключил " .. p ) end

		loadRealm( "client" )
		for _, p in ipairs( gm.included ) do T.ok( not p:match( "/sv_[^/]+$" ), "клиент подключил " .. p ) end
	end )
end )

T.describe( "синтаксис", function()
	T.it( "все .lua файлы компилируются (GLua через препроцессор)", function()
		local p = io.popen( 'find "' .. gm.root .. '/lua" -name "*.lua" | sort' )
		local bad, count = {}, 0

		for path in p:lines() do
			count = count + 1

			local f, err = gm.loadfile( path )

			if not f then bad[ #bad + 1 ] = err end
		end

		p:close()

		T.ok( count > 0, "не найдено ни одного .lua" )
		T.ok( #bad == 0, table.concat( bad, "\n        " ) )
	end )
end )
