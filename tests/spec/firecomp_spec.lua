-- Огневой вычислитель arty/core/sh_firecomp.lua: заряды, дальности, решение задачи
-- стрельбы. Каждое решение проверяется повторным полётом той же моделью.

local gm, T = ...

local GRID, FCF = "skyops/arty/core/sh_grid.lua", "skyops/arty/core/sh_firecomp.lua"

local function setup()
	gm.reset( "server" )
	_G.SkyOps = {}
	gm.include( FCF )
	gm.include( GRID )

	return _G.SkyOps.Arty.FireComp, _G.SkyOps.Arty.Grid
end

-- полёт в 3D тем же FC.Step от дула по решению; точка, где нисходящая ветвь проходит h цели
local function fly3d( FC, q, sol )
	local shell = FC.GetShell( q.shell or "he" )
	local charge = FC.GetCharge( q.shell or "he", sol.charge or q.charge )
	local b = sol.bearing / FC.MILS * 2 * math.pi
	local e = sol.elevation / FC.MILS * 2 * math.pi
	local v0 = charge.v0
	local s = {
		x = q.gun.x, y = q.gun.y, z = ( q.gun.h or 0 ) + FC.MUZZLE_H,
		vx = v0 * math.cos( e ) * math.sin( b ), vy = v0 * math.cos( e ) * math.cos( b ), vz = v0 * math.sin( e ),
	}
	local th = q.target.h or 0
	local t, apex = 0, s.z

	while t < 400 do
		local px, py, pz = s.x, s.y, s.z

		FC.Step( s, shell.k, FC.DT )
		t = t + FC.DT
		apex = math.max( apex, s.z )

		if s.vz < 0 and s.z <= th then
			local f = ( pz - th ) / ( pz - s.z )

			return px + ( s.x - px ) * f, py + ( s.y - py ) * f, t - FC.DT + FC.DT * f, apex
		end
	end
end

local ok, why = T.requires( gm, GRID, FCF )

T.describe( "огневой вычислитель", function()
	if not ok then return T.it( "файлы на месте", function() T.skip( why ) end ) end

	T.it( "заряды: скорость и дальность падают от полного к слабым", function()
		local FC = setup()

		for _, id in ipairs( { "he", "krasnopol" } ) do
			local list = FC.Charges( id )
			T.ok( #list > 0, "нет зарядов у " .. id )

			for i = 2, #list do
				T.ok( list[ i ].v0 < list[ i - 1 ].v0, id .. ": v0 должна падать" )
				T.ok( list[ i ].max < list[ i - 1 ].max, id .. ": дальность должна падать" )
			end

			for _, c in ipairs( list ) do
				T.ok( c.max > 0, id .. "/" .. c.id .. ": нулевая дальность" )
				T.ok( c.minHigh > 0 and c.minHigh < c.max, id .. "/" .. c.id .. ": minHigh вне 0..max" )
			end
		end
	end )

	T.it( "ОФС на полном заряде: 35–42 км (как у 2А88), Краснополь короче", function()
		local FC = setup()
		local he = FC.MaxRange( "he", 1, 0 )
		local kr = FC.MaxRange( "krasnopol", 2, 0 )
		local he2 = FC.MaxRange( "he", 2, 0 )

		T.ok( he > 35000 and he < 42000, string.format( "ОФС полный: %.0f м", he ) )
		T.ok( kr < he2, string.format( "Краснополь %.0f м не короче ОФС %.0f м на том же заряде", kr, he2 ) )
	end )

	T.it( "решения повторяются полётом 3D до 1 м: дальности 2–35 км, обе группы углов", function()
		local FC = setup()
		local worst, n = 0, 0

		for _, shellId in ipairs( { "he", "krasnopol" } ) do
			for _, c in ipairs( FC.GetShell( shellId ).charges ) do
				local maxR = FC.MaxRange( shellId, c.id, 0 )

				for _, frac in ipairs( { 0.15, 0.4, 0.7, 0.95 } ) do
					for _, high in ipairs( { false, true } ) do
						for _, bearing in ipairs( { 0, 1000, 2900, 4321 } ) do
							local r = maxR * frac
							local b = bearing / 6000 * 2 * math.pi
							local q = {
								gun = { x = 50000, y = 50000, h = 120 },
								target = { x = 50000 + r * math.sin( b ), y = 50000 + r * math.cos( b ), h = 120 + ( frac - 0.5 ) * 200 },
								shell = shellId, charge = c.id, high = high, basedir = 0,
							}
							local sol = FC.Solve( q )

							if sol.ok then
								local x, y = fly3d( FC, q, sol )
								local miss = math.sqrt( ( x - q.target.x ) ^ 2 + ( y - q.target.y ) ^ 2 )

								worst = math.max( worst, miss )
								n = n + 1
								T.ok( miss < 1, string.format( "%s заряд %d %s %.0f м: промах %.2f м", shellId, c.id, high and "навесная" or "настильная", r, miss ) )
							elseif not high then
								-- настильная должна решаться на любой дальности до максимума, кроме ближней зоны
								T.ok( sol.err and sol.err:find( "Ближе" ), string.format( "%s заряд %d %.0f м: %s", shellId, c.id, r, tostring( sol.err ) ) )
							end
						end
					end
				end
			end
		end

		T.ok( n > 100, "решено слишком мало задач: " .. n )
	end )

	T.it( "навесная выше настильной, летит дольше и с большей вершиной", function()
		local FC = setup()
		local q = { gun = { x = 0, y = 0, h = 0 }, target = { x = 0, y = 22000, h = 0 }, shell = "he", charge = 2, basedir = 0 }
		local low = FC.Solve( q )

		q.high = true

		local high = FC.Solve( q )

		T.ok( low.ok and high.ok, tostring( low.err or high.err ) )
		T.ok( high.elevation > low.elevation )
		T.ok( high.tof > low.tof )
		T.ok( high.apex > low.apex )
		T.ok( low.elevation > 0 and high.elevation < 75 / 360 * 6000 )
	end )

	T.it( "прицел растёт с дальностью (настильная), падает (навесная)", function()
		local FC = setup()
		local prevLow, prevHigh

		for r = 4000, 28000, 2000 do
			local q = { gun = { x = 0, y = 0, h = 0 }, target = { x = r, y = 0, h = 0 }, shell = "he", charge = 1 }
			local lo = FC.Solve( q )

			q.high = true

			local hi = FC.Solve( q )

			T.ok( lo.ok, "настильная " .. r .. ": " .. tostring( lo.err ) )
			if prevLow then T.ok( lo.elevation > prevLow, "настильная не монотонна на " .. r ) end
			if hi.ok and prevHigh then T.ok( hi.elevation < prevHigh, "навесная не монотонна на " .. r ) end

			prevLow, prevHigh = lo.elevation, hi.ok and hi.elevation or prevHigh
		end
	end )

	T.it( "угломер: 30-00 по основному направлению, растёт против часовой", function()
		local FC = setup()

		T.near( FC.Deflection( 1500, 1500 ), 3000, 1e-9 )
		T.near( FC.Deflection( 1400, 1500 ), 3100, 1e-9, "левее основного -> больше" )
		T.near( FC.Deflection( 5900, 100 ), 3200, 1e-9, "через север" )
		T.near( FC.MilsDiff( 10, 5990 ), 20, 1e-9 )
		T.near( FC.MilsDiff( 5990, 10 ), -20, 1e-9 )

		local sol = FC.Solve( { gun = { x = 0, y = 0 }, target = { x = 10000, y = 0 }, shell = "he", charge = 1, basedir = 1500 } )
		T.near( sol.bearing, 1500, 1e-9 )
		T.near( sol.deflection, 3000, 1e-9 )
	end )

	T.it( "ошибки: вне досягаемости, неизвестный снаряд, чужой заряд, цель выше траектории", function()
		local FC = setup()
		local base = { gun = { x = 0, y = 0, h = 0 }, shell = "he", charge = 6 }

		local q = { gun = base.gun, target = { x = 0, y = 60000, h = 0 }, shell = "he", charge = 1 }
		local s = FC.Solve( q )
		T.ok( not s.ok and s.err:find( "вне досягаемости" ), tostring( s.err ) )

		q = { gun = base.gun, target = { x = 0, y = 1000, h = 0 }, shell = "smoke", charge = 1 }
		s = FC.Solve( q )
		T.ok( not s.ok and s.err:find( "Неизвестный снаряд" ), tostring( s.err ) )

		q = { gun = base.gun, target = { x = 0, y = 1000, h = 0 }, shell = "krasnopol", charge = 1 }
		s = FC.Solve( q )
		T.ok( not s.ok and s.err:find( "нет такого заряда" ), "Краснополь на полном заряде: " .. tostring( s.err ) )

		q = { gun = base.gun, target = { x = 0, y = 500, h = 20000 }, shell = "he", charge = 6 }
		s = FC.Solve( q )
		T.ok( not s.ok and s.err, "цель на 20 км вверх решилась" )

		for _, r in ipairs( { s.range, s.bearing, s.deflection } ) do T.ok( type( r ) == "number", "в ответе с ошибкой нет range/bearing/deflection" ) end
	end )

	T.it( "BestCharge: самый слабый заряд с запасом 5 %, и задача с ним решается", function()
		local FC = setup()

		for r = 2000, 36000, 1700 do
			local id = FC.BestCharge( "he", r, 0, 2.5 )
			local maxR = FC.MaxRange( "he", id, 0, 2.5 )

			if r * 1.05 <= FC.MaxRange( "he", 1, 0, 2.5 ) then
				T.ok( maxR >= r * 1.05, "заряд " .. id .. " не достаёт " .. r )

				local weaker = FC.GetShell( "he" ).charges[ id + 1 ]

				if weaker then T.ok( FC.MaxRange( "he", weaker.id, 0, 2.5 ) < r * 1.05, "есть заряд слабее для " .. r ) end
			end
		end
	end )

	T.it( "кэш решений: повтор той же задачи даёт тот же ответ", function()
		local FC = setup()
		local q = { gun = { x = 1, y = 2, h = 150 }, target = { x = 8001, y = 9002, h = 210 }, shell = "he", charge = 3, basedir = 1200 }
		local a = FC.Solve( q )
		local b = FC.Solve( q )

		for _, k in ipairs( { "ok", "elevation", "tof", "apex", "deflection", "bearing", "range" } ) do
			T.eq( a[ k ], b[ k ], k )
		end
	end )

	T.it( "DirToMils обратна Grid.Direction", function()
		local FC, G = setup()

		for b = 0, 5999, 333 do
			for _, el in ipairs( { -80, 0, 450, 1200 } ) do
				local bb, ee = FC.DirToMils( G.Direction( b, el ) )

				T.near( FC.MilsDiff( bb, b ), 0, 1e-6 ) T.near( ee, el, 1e-6 )
			end
		end
	end )
end )
