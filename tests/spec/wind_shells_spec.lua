-- Ветер (arty/core/sh_wind + sv_wind) и новые снаряды: дымовой, осветительный, кассетный.
-- Вычислитель учитывает ветер бюллетеня; реальный ветер гуляет вокруг него.

local gm, T = ...

local FILES = { "skyops/arty/core/sh_wind.lua", "skyops/arty/core/sv_wind.lua", "skyops/arty/core/sv_ballistics.lua" }

local function setup()
	gm.reset( "server" )

	_G.KIR = {
		S = 40,
		MeshHeight = function( x, y )
			if math.abs( x ) > 2e6 or math.abs( y ) > 2e6 then return -math.huge end

			return 100 * 40
		end,
	}

	gm.created = {}
	gm.entityFactory = function( class )
		local e = gm.entity( { class = class } )

		if class == "sw_bomb_fab100_v3" then
			function e:Explode( pos ) gm.explosions = gm.explosions or {} table.insert( gm.explosions, pos ) end
		end

		table.insert( gm.created, e )

		return e
	end

	gm.loadDirs( { "skyops/core/", "skyops/arty/core/" } )
	_G.GetConVar( "skyops_arty_dispersion" ):SetFloat( 0 )
	_G.GetConVar( "skyops_arty_timescale" ):SetFloat( 10 )

	local A = _G.SkyOps.Arty

	return A.FireComp, A.Grid, A.Ballistics, A.Wind
end

local function teardown() _G.KIR = nil gm.entityFactory = nil gm.explosions = nil end

-- выстрел по решению q (как в ballistics_spec); -> промах в метрах от цели, снаряд
local function shoot( FC, G, B, q )
	local sol = FC.Solve( q )

	T.ok( sol.ok, "нет решения: " .. tostring( sol.err ) )

	local muzzle = G.FromGrid( q.gun.x, q.gun.y, ( q.gun.h or 0 ) + FC.MUZZLE_H )
	local shell = B.Fire( { pos = muzzle, dir = G.Direction( sol.bearing, sol.elevation ), shell = q.shell, charge = q.charge } )

	for _ = 1, 66 * 400 do
		gm.think( 1, 1 / 66 )

		if not B.Active[ shell.id ] then break end
	end

	T.ok( shell.impact, "снаряд не упал" )

	local x, y = G.ToGrid( shell.impact )

	return math.sqrt( ( x - q.target.x ) ^ 2 + ( y - q.target.y ) ^ 2 ), shell, sol
end

local function query( r, b, charge, shell )
	local a = b / 6000 * 2 * math.pi

	return {
		gun = { x = 50000, y = 50000, h = 100 },
		target = { x = 50000 + r * math.sin( a ), y = 50000 + r * math.cos( a ), h = 100 },
		shell = shell or "he", charge = charge,
	}
end

local ok, why = T.requires( gm, unpack( FILES ) )

T.describe( "ветер и новые снаряды", function()
	if not ok then return T.it( "файлы на месте", function() T.skip( why ) end ) end

	T.it( "ветер с севера дует на юг, Format пишет откуда", function()
		local _, _, _, W = setup()
		local v = W.Vector( 0, 5 )

		T.near( v.x, 0, 1e-9, "x" )
		T.near( v.y, -5, 1e-9, "y" )
		W.Set( 4500, 4 )
		T.eq( W.Format(), "4 м/с, с 45-00 (З)" )
		W.Set( 0, 0 )
		T.eq( W.Format(), "штиль" )
		teardown()
	end )

	T.it( "без порывов вычислитель с ветром бюллетеня попадает (до 5 м), без учёта — мимо", function()
		local FC, G, B, W = setup()

		_G.GetConVar( "skyops_arty_wind_gusts" ):SetFloat( 0 )
		W.Set( 1500, 6 ) -- 6 м/с с востока, поперёк стрельбы на север

		for _, case in ipairs( { { r = 12000, charge = 3 }, { r = 30000, charge = 1 } } ) do
			local q = query( case.r, 0, case.charge )
			local miss, _, sol = shoot( FC, G, B, q )

			T.ok( miss < 5, string.format( "%d м: промах %.1f м с учётом ветра", case.r, miss ) )
			T.ok( sol.drift and sol.drift < -10, "нет сноса на запад: " .. tostring( sol.drift ) )

			q.wind = false

			local raw = shoot( FC, G, B, q )

			T.ok( raw > 3 * math.max( miss, 5 ), string.format( "%d м: без учёта ветра промах всего %.1f м", case.r, raw ) )
			print( string.format( "      ветер 6 м/с поперёк, %d м: с учётом %.1f м, без учёта %.0f м, снос %.0f м", case.r, miss, raw, sol.drift ) )
		end

		teardown()
	end )

	T.it( "с порывами реальный ветер уходит от бюллетеня: промах есть, но небольшой", function()
		local FC, G, B, W = setup()

		W.Set( 3000, 6 )

		local worst, sum, n = 0, 0, 0

		for i = 1, 8 do
			gm.think( 66 * 30, 1 / 66 ) -- полминуты: ветер успевает сдвинуться

			local miss = shoot( FC, G, B, query( 25000, 400 * i, 1 ) )

			worst = math.max( worst, miss )
			sum, n = sum + miss, n + 1
		end

		print( string.format( "      25 км, ветер 6 м/с с порывами: средний промах %.0f м, худший %.0f м", sum / n, worst ) )
		T.ok( worst < 250, "промах от порывов слишком большой: " .. worst )

		local d, s = W.ActualDirSpeed()

		T.ok( s > 6 * 0.65 and s < 6 * 1.35, "скорость ушла дальше 30 %: " .. s )
		T.ok( math.abs( FC.MilsDiff( d, 3000 ) ) <= 201, "направление ушло дальше 2-00: " .. d )
		teardown()
	end )

	T.it( "дымовой и осветительный не взрываются, кассетный рвёт суббоеприпасы вокруг точки", function()
		local FC, G, B, W = setup()

		W.Set( 0, 0 )

		for _, id in ipairs( { "smoke", "illum" } ) do
			gm.explosions = nil

			local miss, shell = shoot( FC, G, B, query( 8000, 700, 4, id ) )

			T.ok( miss < 3, id .. ": промах " .. miss )
			T.ok( not gm.explosions, id .. ": взорвался как ОФС" )
			T.ok( shell.impact, id .. ": нет точки падения" )
		end

		-- кассетный: Splash по сущностям рядом с суббоеприпасами
		local q = query( 8000, 700, 4, "cluster" )
		local sol = FC.Solve( q )
		local target = G.FromGrid( q.target.x, q.target.y, 100 )
		-- игрок там, где ляжет первый суббоеприпас этого снаряда
		local spot = FC.BombletPattern( ( B.NextId + 1 ) % 65536, 16, 55 )[ 1 ]
		local victim = gm.entity( { class = "player", player = true, pos = G.FromGrid( q.target.x + spot[ 1 ], q.target.y + spot[ 2 ], 100 ) } )
		local far = gm.entity( { class = "player", player = true, pos = target + Vector( 400 * 40, 0, 0 ) } )
		local hits = {}

		function victim:TakeDamageInfo( d ) hits[ #hits + 1 ] = d:GetDamage() end
		function far:TakeDamageInfo() error( "задело игрока в 400 м" ) end

		gm.entities = { victim, far }

		local _, shell = shoot( FC, G, B, q )

		gm.think( 66 * 2, 1 / 66 ) -- таймеры суббоеприпасов

		T.ok( not gm.explosions, "кассетный рванул одним большим взрывом" )
		T.ok( #hits > 0, "ни один суббоеприпас не задел цель в точке падения" )
		T.ok( sol.ok and shell.def.bomblets.count == 16, "суббоеприпасов не 16" )
		teardown()
	end )

	T.it( "рисунок суббоеприпасов одинаков для одного id и лежит в круге", function()
		local FC = setup()
		local a, b = FC.BombletPattern( 1234, 16, 55 ), FC.BombletPattern( 1234, 16, 55 )
		local c = FC.BombletPattern( 1235, 16, 55 )

		T.eq( #a, 16 )

		for i = 1, 16 do
			T.eq( a[ i ][ 1 ], b[ i ][ 1 ] )
			T.ok( math.sqrt( a[ i ][ 1 ] ^ 2 + a[ i ][ 2 ] ^ 2 ) <= 55, "вне круга" )
			T.ok( a[ i ][ 3 ] >= 0.2 and a[ i ][ 3 ] <= 1, "задержка" )
		end

		T.ok( a[ 1 ][ 1 ] ~= c[ 1 ][ 1 ], "другой id, тот же рисунок" )
		teardown()
	end )

	T.it( "все снаряды в ShellOrder решаются на своих зарядах", function()
		local FC = setup()

		for _, id in ipairs( FC.ShellOrder ) do
			local def = FC.GetShell( id )

			T.ok( def, id )

			local c = def.charges[ #def.charges ].id
			local sol = FC.Solve( { gun = { x = 0, y = 0, h = 0 }, target = { x = 0, y = 3000, h = 0 }, shell = id, charge = c, wind = false } )

			T.ok( sol.ok, id .. ": " .. tostring( sol.err ) )
		end

		teardown()
	end )
end )
