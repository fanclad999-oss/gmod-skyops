-- Живые снаряды arty/core/sv_ballistics.lua: выстрел по решению вычислителя летит
-- кадрами хука Think и рвётся у цели. Рельеф подменён KIR.MeshHeight.

local gm, T = ...

local FILES = { "skyops/arty/core/sh_grid.lua", "skyops/arty/core/sh_firecomp.lua", "skyops/arty/core/sv_ballistics.lua" }

-- ground(xm, ym) -> высота в метрах по мировым метрам от начала
local function setup( ground )
	gm.reset( "server" )

	ground = ground or function() return 100 end

	_G.KIR = {
		S = 40,
		MeshHeight = function( x, y )
			if math.abs( x ) > 2e6 or math.abs( y ) > 2e6 then return -math.huge end

			return ground( x / 40, y / 40 ) * 40
		end,
	}

	gm.loadDirs( { "skyops/core/", "skyops/arty/core/" } )
	_G.GetConVar( "skyops_arty_dispersion" ):SetFloat( 0 )
	_G.SkyOps.Arty.Wind.Set( 0, 0 ) -- штиль: здесь проверяется точность без ветра (ветер — wind_spec)

	local A = _G.SkyOps.Arty

	return A.FireComp, A.Grid, A.Ballistics
end

local function teardown() _G.KIR = nil end

-- последний разрыв из net-сообщения skyops_arty_impact
local function lastImpact()
	for i = #gm.netSent, 1, -1 do
		local m = gm.netSent[ i ]

		if m.name == "skyops_arty_impact" then return Vector( m.data[ 1 ][ 2 ], m.data[ 2 ][ 2 ], m.data[ 3 ][ 2 ] ), m.data[ 4 ][ 2 ] end
	end
end

-- стреляет по решению и крутит Think, пока снаряд не упадёт; -> мировая точка разрыва, время
local function shoot( FC, G, B, q, opts )
	opts = opts or {}

	local sol = FC.Solve( q )

	T.ok( sol.ok, "нет решения: " .. tostring( sol.err ) )

	local muzzle = G.FromGrid( q.gun.x, q.gun.y, ( q.gun.h or 0 ) + FC.MUZZLE_H )
	local shell = B.Fire( { pos = muzzle, dir = G.Direction( sol.bearing, sol.elevation ), shell = q.shell, charge = q.charge, dispersion = opts.dispersion } )

	T.ok( shell, "B.Fire не вернул снаряд" )

	local t0 = gm.time

	for _ = 1, 66 * 400 do
		gm.think( 1, 1 / 66 )

		if not B.Active[ shell.id ] then break end
	end

	T.ok( not B.Active[ shell.id ], "снаряд не упал за 400 с" )

	return lastImpact(), gm.time - t0, sol, shell
end

local ok, why = T.requires( gm, unpack( FILES ) )

T.describe( "полёт снаряда", function()
	if not ok then return T.it( "файлы на месте", function() T.skip( why ) end ) end

	T.it( "без рассеивания ОФС падает у цели (до 3 м), время полёта как в решении", function()
		local FC, G, B = setup()

		for _, case in ipairs( {
			{ r = 6000, b = 300, charge = 4 },
			{ r = 18000, b = 1700, charge = 2 },
			{ r = 30000, b = 4200, charge = 1 },
			{ r = 22000, b = 5800, charge = 2, high = true },
		} ) do
			local rb = case.b / 6000 * 2 * math.pi
			local q = {
				gun = { x = 50000, y = 50000, h = 100 },
				target = { x = 50000 + case.r * math.sin( rb ), y = 50000 + case.r * math.cos( rb ), h = 100 },
				shell = "he", charge = case.charge, high = case.high, basedir = 0,
			}
			local pos, t, sol = shoot( FC, G, B, q )
			local x, y = G.ToGrid( pos )
			local miss = math.sqrt( ( x - q.target.x ) ^ 2 + ( y - q.target.y ) ^ 2 )

			T.ok( miss < 3, string.format( "%.0f м на %d: промах %.1f м", case.r, case.b, miss ) )
			T.near( t, sol.tof, 0.2, "время полёта" )
		end

		teardown()
	end )

	T.it( "skyops_arty_timescale 5 ускоряет полёт в 5 раз, точка разрыва та же", function()
		local FC, G, B = setup()
		local q = { gun = { x = 50000, y = 50000, h = 100 }, target = { x = 60000, y = 55000, h = 100 }, shell = "he", charge = 3, basedir = 0 }
		local p1, t1 = shoot( FC, G, B, q )

		_G.GetConVar( "skyops_arty_timescale" ):SetFloat( 5 )

		local p2, t2 = shoot( FC, G, B, q )

		T.near( t2, t1 / 5, 0.1 )
		T.ok( p1:Distance( p2 ) < 40, "разрыв сместился на " .. p1:Distance( p2 ) / 40 .. " м" )
		teardown()
	end )

	T.it( "цель на холме: снаряд не пролетает сквозь склон", function()
		-- плато +300 м шириной 1 км в 15 км к северу, склоны по 1 км. На острой вершине
		-- настильный снаряд законно перелетает гребень, поэтому цель на плоской макушке.
		local function ground( _, y )
			local d = math.max( math.abs( y - 15000 ) - 500, 0 )

			return 100 + math.max( 0, 300 * ( 1 - d / 1000 ) )
		end

		local FC, G, B = setup( ground )
		local q = { gun = { x = 50000, y = 50000, h = 100 }, target = { x = 50000, y = 65000, h = 400 }, shell = "he", charge = 2, basedir = 0 }
		local pos = shoot( FC, G, B, q )
		local x, y, h = G.ToGrid3( pos )

		T.near( h, G.Height( x, y ) + 0.5, 1, "разрыв не на рельефе" )
		T.ok( math.abs( y - 65000 ) < 30, string.format( "промах по дальности %.1f м", y - 65000 ) )
		teardown()
	end )

	T.it( "управляемый снаряд с пустым Steer летит как неуправляемый (перевод скоростей мир <-> сетка)", function()
		local FC, G, B = setup()

		_G.SkyOps.Arty.Guided = { Steer = function( s ) s.steered = ( s.steered or 0 ) + 1 end }

		local q = { gun = { x = 50000, y = 50000, h = 100 }, target = { x = 61000, y = 43000, h = 100 }, shell = "krasnopol", charge = 3, basedir = 0 }
		local pos, _, _, shell = shoot( FC, G, B, q )
		local x, y = G.ToGrid( pos )

		T.ok( ( shell.steered or 0 ) > 10, "Steer не вызывался" )
		T.ok( math.sqrt( ( x - 61000 ) ^ 2 + ( y - 43000 ) ^ 2 ) < 3, "промах управляемого с пустым Steer" )
		teardown()
	end )

	T.it( "WorldVel / SetWorldVel обратимы", function()
		local _, _, B = setup()
		local s = { vx = 123.4, vy = -456.7, vz = 89.1 }
		local v = B.WorldVel( s )

		T.near( v.x, 123.4 * 40, 1e-6 ) T.near( v.y, -456.7 * 40, 1e-6 ) T.near( v.z, 89.1 * 40, 1e-6 )
		B.SetWorldVel( s, v * 2 )
		T.near( s.vx, 246.8, 1e-9 ) T.near( s.vy, -913.4, 1e-9 ) T.near( s.vz, 178.2, 1e-9 )
		teardown()
	end )

	T.it( "хуки: ShellFired, ShellImpact (true отменяет взрыв), ShellRemoved(impact)", function()
		local FC, G, B = setup()
		local seen = {}

		_G.hook.Add( "SkyOps.Arty.ShellFired", "t", function() seen.fired = true end )
		_G.hook.Add( "SkyOps.Arty.ShellImpact", "t", function() seen.impact = true return true end )
		_G.hook.Add( "SkyOps.Arty.ShellRemoved", "t", function( _, reason ) seen.removed = reason end )

		gm.blasts = nil
		shoot( FC, G, B, { gun = { x = 50000, y = 50000, h = 100 }, target = { x = 52000, y = 50000, h = 100 }, shell = "he", charge = 6, basedir = 0 } )

		T.ok( seen.fired, "нет ShellFired" )
		T.ok( seen.impact, "нет ShellImpact" )
		T.eq( seen.removed, "impact" )
		T.eq( gm.blasts, nil, "взрыв не отменён хуком" )
		teardown()
	end )

	T.it( "без SW Bombs взрыв идёт через util.BlastDamage", function()
		local FC, G, B = setup()

		gm.blasts = nil
		shoot( FC, G, B, { gun = { x = 50000, y = 50000, h = 100 }, target = { x = 52000, y = 50000, h = 100 }, shell = "he", charge = 6, basedir = 0 } )
		T.ok( gm.blasts and #gm.blasts == 1, "BlastDamage не вызван" )
		teardown()
	end )

	T.it( "рассеивание: 200 выстрелов, срединное отклонение по дальности 5–80 м", function()
		local FC, G, B = setup()

		_G.GetConVar( "skyops_arty_dispersion" ):SetFloat( 1 )
		_G.GetConVar( "skyops_arty_timescale" ):SetFloat( 20 )
		math.randomseed( 42 )

		local q = { gun = { x = 50000, y = 50000, h = 100 }, target = { x = 50000, y = 70000, h = 100 }, shell = "he", charge = 1, basedir = 0 }
		local devs = {}

		for i = 1, 200 do
			local pos = shoot( FC, G, B, q )
			local _, y = G.ToGrid( pos )

			devs[ i ] = math.abs( y - 70000 )
		end

		table.sort( devs )

		local median = devs[ 100 ]

		T.ok( median > 5 and median < 80, string.format( "срединное отклонение %.1f м", median ) )
		teardown()
	end )
end )
