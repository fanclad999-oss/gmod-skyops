-- Сетка координат arty/core/sh_grid.lua: перевод мир <-> сетка, направления, квадраты.

local gm, T = ...

local GRID = "skyops/arty/core/sh_grid.lua"

local function setup( opts )
	opts = opts or {}
	gm.reset( "server" )

	_G.SkyOps = { Maps = opts.northYaw and { kirovskoe = { north_yaw = opts.northYaw } } or nil }

	if opts.kir ~= false then
		local half = ( opts.halfKm or 20 ) * 1000 * 40

		_G.KIR = {
			S = 40,
			-- плоскость 100 м с уклоном 1 % на восток; за краем -inf, как у настоящего KIR
			MeshHeight = function( x, y )
				if math.abs( x ) > half or math.abs( y ) > half then return -math.huge end

				return ( 100 + x / 40 * 0.01 ) * 40
			end,
		}
	end

	gm.include( GRID )

	return _G.SkyOps.Arty.Grid
end

local function teardown() _G.KIR = nil end

local ok, why = T.requires( gm, GRID )

T.describe( "сетка", function()
	if not ok then return T.it( "файлы на месте", function() T.skip( why ) end ) end

	T.it( "начало мира = (50000, 50000), +X мира = восток, +Y = север", function()
		local G = setup()

		local x, y = G.ToGrid( Vector( 0, 0, 0 ) )
		T.near( x, 50000, 1e-9 ) T.near( y, 50000, 1e-9 )

		x, y = G.ToGrid( Vector( 4000, 0, 0 ) ) -- 100 м на восток при 40 u/м
		T.near( x, 50100, 1e-9, "восток" ) T.near( y, 50000, 1e-9 )

		x, y = G.ToGrid( Vector( 0, 4000, 0 ) )
		T.near( x, 50000, 1e-9 ) T.near( y, 50100, 1e-9, "север" )
		teardown()
	end )

	T.it( "FromGrid(ToGrid(p)) = p, с высотой и по рельефу", function()
		local G = setup()

		for _, p in ipairs( { Vector( 1234.5, -9876.25, 4000 ), Vector( -300000, 250000, 12000 ), Vector( 0, 0, 0 ) } ) do
			local x, y, h = G.ToGrid3( p )
			local q = G.FromGrid( x, y, h )

			T.near( q.x, p.x, 1e-6 ) T.near( q.y, p.y, 1e-6 ) T.near( q.z, p.z, 1e-6 )
		end

		-- без высоты Z берётся из рельефа
		local q = G.FromGrid( 51000, 50000 )
		T.near( q.z, ( 100 + 1000 * 0.01 ) * 40, 1e-6, "Z по рельефу" )
		teardown()
	end )

	T.it( "Height: метры над z = 0, nil за краем карты", function()
		local G = setup()

		T.near( G.Height( 50000, 50000 ), 100, 1e-9 )
		T.near( G.Height( 51000, 50000 ), 110, 1e-9 )
		T.eq( G.Height( 50000 + 25000, 50000 ), nil, "за краем" )
		teardown()
	end )

	T.it( "без KIR: 52.49 u/м и SkyOps.M_TO_HU, если задан", function()
		local G = setup( { kir = false } )

		T.near( G.UPM(), 52.49, 1e-9 )
		_G.SkyOps.M_TO_HU = 50
		T.near( G.UPM(), 50, 1e-9 )
	end )

	T.it( "YawToMils / MilsToYaw: север 0, восток 15-00, юг 30-00, запад 45-00", function()
		local G = setup()

		T.near( G.YawToMils( 90 ), 0, 1e-9, "север" )
		T.near( G.YawToMils( 0 ), 1500, 1e-9, "восток" )
		T.near( G.YawToMils( -90 ), 3000, 1e-9, "юг" )
		T.near( G.YawToMils( 180 ), 4500, 1e-9, "запад" )

		for m = 0, 5999, 137 do
			T.near( G.YawToMils( G.MilsToYaw( m ) ), m, 1e-9 )
		end
		teardown()
	end )

	T.it( "Bearing по сетке совпадает с YawToMils мирового направления", function()
		local G = setup()

		T.near( G.Bearing( 0, 0, 0, 10 ), 0, 1e-9 )
		T.near( G.Bearing( 0, 0, 10, 0 ), 1500, 1e-9 )
		T.near( G.Bearing( 0, 0, 0, -10 ), 3000, 1e-9 )
		T.near( G.Bearing( 0, 0, -10, 0 ), 4500, 1e-9 )

		for yaw = -180, 180, 7 do
			local d = Vector( math.cos( math.rad( yaw ) ), math.sin( math.rad( yaw ) ), 0 ) * 40000
			local x1, y1 = G.ToGrid( Vector( 0, 0, 0 ) )
			local x2, y2 = G.ToGrid( d )

			T.near( G.Bearing( x1, y1, x2, y2 ), G.YawToMils( yaw ) % 6000, 1e-6, "yaw " .. yaw )
		end
		teardown()
	end )

	T.it( "Direction(bearing, elevation) смотрит туда же, куда Bearing и угол места", function()
		local G = setup()

		for b = 0, 5999, 250 do
			for _, el in ipairs( { -50, 0, 300, 1000 } ) do
				local d = G.Direction( b, el )
				local x1, y1 = G.ToGrid( Vector( 0, 0, 0 ) )
				local x2, y2 = G.ToGrid( d * 1000 )

				T.near( d:Length(), 1, 1e-9 )
				T.near( ( G.Bearing( x1, y1, x2, y2 ) - b + 3000 ) % 6000 - 3000, 0, 1e-6, "азимут" )
				T.near( math.deg( math.asin( d.z ) ) / 360 * 6000, el, 1e-6, "угол места" )
			end
		end
		teardown()
	end )

	T.it( "повёрнутый север (north_yaw 0): обратимость и согласованность углов", function()
		local G = setup( { northYaw = 0 } )

		local p = Vector( 4000, 0, 0 ) -- yaw 0 теперь север
		local x, y = G.ToGrid( p )

		T.near( x, 50000, 1e-9 ) T.near( y, 50100, 1e-9 )
		T.near( G.YawToMils( 0 ), 0, 1e-9 )
		T.near( G.YawToMils( -90 ), 1500, 1e-9, "восток при north_yaw 0" )

		local q = G.FromGrid( x, y, 0 )
		T.near( q.x, p.x, 1e-6 ) T.near( q.y, p.y, 1e-6 )

		local d = G.Direction( 1500, 0 )
		local gx, gy = G.ToGrid( d * 4000 )
		T.near( gx, 50100, 1e-6, "Direction 15-00 = восток" ) T.near( gy, 50000, 1e-6 )
		teardown()
	end )

	T.it( "квадрат и улитка: 1 2 3 / 8 9 4 / 7 6 5, север сверху", function()
		local G = setup()

		local function snail( dx, dy ) local _, s = G.Square( 63000 + dx, 41000 + dy ) return s end

		T.eq( snail( 100, 900 ), 1, "северо-запад" )
		T.eq( snail( 500, 900 ), 2 )
		T.eq( snail( 900, 900 ), 3, "северо-восток" )
		T.eq( snail( 900, 500 ), 4 )
		T.eq( snail( 900, 100 ), 5, "юго-восток" )
		T.eq( snail( 500, 100 ), 6 )
		T.eq( snail( 100, 100 ), 7, "юго-запад" )
		T.eq( snail( 100, 500 ), 8 )
		T.eq( snail( 500, 500 ), 9, "центр" )

		local sq = G.Square( 63500, 41500 )
		T.eq( sq, "41-63", "квадрат пишется север-восток" )
		T.eq( G.Format( 63520, 41480 ), "кв. 41-63 ул. 9 (X 63520 Y 41480)" )
		teardown()
	end )

	T.it( "Bounds по KIR.MeshHeight: квадрат карты ±20 км вокруг начала", function()
		local G = setup( { halfKm = 20 } )
		local minX, minY, maxX, maxY = G.Bounds()

		T.eq( minX, 30000 ) T.eq( minY, 30000 ) T.eq( maxX, 70000 ) T.eq( maxY, 70000 )
		teardown()
	end )
end )
