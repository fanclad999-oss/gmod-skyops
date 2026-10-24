-- Интерфейс (arty/ui/cl_api.lua) и сервер (arty/core) считают одно и то же: координаты,
-- углы, угломер, решения. Если интерфейс покажет одни установки, а сервер наведёт по
-- другим, игрок промахнётся, поэтому здесь сверяются обе стороны на одних входах.

local gm, T = ...

local API = "skyops/arty/ui/cl_api.lua"
local GRID, FCF = "skyops/arty/core/sh_grid.lua", "skyops/arty/core/sh_firecomp.lua"

local function kir()
	_G.KIR = { S = 40, MeshHeight = function( x ) return ( 150 + x / 40 * 0.02 ) * 40 end }
end

-- client: только cl_api (запасные расчёты) или вместе с core (core = true)
local function setup( core, withKir )
	gm.reset( "client" )
	_G.SkyOps = {}

	if withKir ~= false then kir() end
	if core then gm.include( FCF ) gm.include( GRID ) end

	gm.include( API )

	return _G.SkyOps.Arty.UI.API, _G.SkyOps.Arty.Grid, _G.SkyOps.Arty.FireComp
end

local function teardown() _G.KIR = nil end

local POINTS = {
	Vector( 0, 0, 0 ), Vector( 123456, -654321, 4000 ), Vector( -1500000, 900000, 12345 ), Vector( 40, 40, 40 ),
}

local hasCore = T.requires( gm, GRID, FCF )
local ok, why = T.requires( gm, API )

T.describe( "интерфейс и сервер считают одинаково", function()
	if not ok then return T.it( "файлы на месте", function() T.skip( why ) end ) end

	local function needCore() if not hasCore then T.skip( "нет arty/core" ) end end

	T.it( "ToGrid / FromGrid совпадают с сеткой", function()
		needCore()
		local A, G = setup( true )

		for _, p in ipairs( POINTS ) do
			local e, n, h = A.ToGrid( p )
			local x, y, z = G.ToGrid3( p )

			T.near( e, x, 1e-9 ) T.near( n, y, 1e-9 ) T.near( h, z, 1e-9 )

			local q, r = A.FromGrid( e, n, h ), G.FromGrid( x, y, z )
			T.near( q:Distance( r ), 0, 1e-6 )
		end

		local q, r = A.FromGrid( 51000, 50000 ), G.FromGrid( 51000, 50000 )
		T.near( q.z, r.z, 1e-6, "Z по рельефу" )
		teardown()
	end )

	T.it( "без KIR (не Кировское) единицы и высоты совпадают с сеткой", function()
		needCore()
		local A, G = setup( true, false )

		T.near( A.UPM(), G.UPM(), 1e-9, "A.UPM и Grid.UPM" )

		local _, _, h = A.ToGrid( Vector( 0, 0, 5249 ) )
		local _, _, z = G.ToGrid3( Vector( 0, 0, 5249 ) )
		T.near( h, z, 1e-6, "высота точки 5249 u" )
	end )

	T.it( "квадрат и улитка", function()
		needCore()
		local A, G = setup( true )

		for e = 30000, 70000, 777 do
			for n = 30000, 70000, 1333 do
				local s1, u1 = A.Square( e, n )
				local s2, u2 = G.Square( e, n )

				T.eq( s1, s2, "квадрат " .. e .. " " .. n ) T.eq( u1, u2, "улитка " .. e .. " " .. n )
			end
		end
		teardown()
	end )

	T.it( "дирекционный угол, угломер, разность углов", function()
		needCore()
		local A, G, FC = setup( true )

		for _, p in ipairs( { { 0, 0, 3, 4 }, { 10, 10, -5, 2 }, { 0, 0, 0, -1 }, { 50000, 50000, 41000, 63000 } } ) do
			T.near( A.Bearing( unpack( p ) ), G.Bearing( unpack( p ) ), 1e-9 )
		end

		for b = 0, 5999, 271 do
			for _, base in ipairs( { 0, 1500, 4700 } ) do
				T.near( A.Deflection( b, base ), FC.Deflection( b, base ), 1e-9 )
				T.near( A.MilsDiff( b, base ), FC.MilsDiff( b, base ), 1e-9 )
			end
		end

		for yaw = -180, 180, 13 do
			T.near( A.DegToMils( A.YawToBearing( yaw ) ), G.YawToMils( yaw ), 1e-9, "yaw " .. yaw )
		end
		teardown()
	end )

	T.it( "A.Solve отдаёт решение вычислителя без изменений", function()
		needCore()
		local A, _, FC = setup( true )
		local q = { gun = { x = 50000, y = 50000, h = 120 }, target = { x = 61000, y = 58000, h = 180 }, shell = "he", charge = 2, high = false, basedir = 1200 }
		local a, b = A.Solve( q ), FC.Solve( q )

		for _, k in ipairs( { "ok", "range", "bearing", "deflection", "elevation", "tof", "apex", "charge" } ) do T.eq( a[ k ], b[ k ], k ) end
		T.eq( a.approx, nil, "решение вычислителя помечено как черновое" )
		teardown()
	end )

	T.it( "дальности зарядов в выпадающем списке = FC.Charges", function()
		needCore()
		local A, _, FC = setup( true )

		for _, shell in ipairs( { "he", "krasnopol" } ) do
			for _, c in ipairs( FC.Charges( shell ) ) do
				local lo, hi = A.ChargeRange( shell, c.id )

				T.eq( hi, c.max ) T.eq( lo, c.min )
			end
		end
		teardown()
	end )

	T.it( "основное направление и наводка ствола: A.* = FC.* для одной САУ", function()
		needCore()
		local A, _, FC = setup( true )

		for _, yaw in ipairs( { 0, 37, 90, -120 } ) do
			for _, base in ipairs( { -1, 0, 2300 } ) do
				local spg = gm.entity( { class = "sw_2s35", ang = Angle( 0, yaw, 0 ) } )

				spg.nw.SkyOpsArty_BaseDir = base
				-- дуло: смотрит под 10° вверх по курсу корпуса + 15°
				function spg:LookupAttachment( name ) return name == "muzzle" and 3 or 0 end
				function spg:GetAttachment() return { Pos = self.pos, Ang = Angle( -10, yaw + 15, 0 ) } end

				local b1 = A.BaseDir( spg )
				local b2 = FC.BaseDir( spg )
				T.near( b1, b2, 1e-9, "BaseDir" )

				local d1, e1 = A.GunLaying( spg )
				local d2, e2 = FC.GunLaying( spg )
				T.near( d1, d2, 1e-9, "угломер" ) T.near( e1, e2, 1e-9, "прицел" )
				T.near( e1, 10 / 360 * 6000, 1e-6, "прицел 10° = 1-67" )
			end
		end
		teardown()
	end )

	T.it( "запасной GunLaying (без core) совпадает с FC.GunLaying", function()
		needCore()
		local A = setup( false )
		local spg = gm.entity( { class = "sw_2s35", ang = Angle( 0, 50, 0 ) } )

		spg.nw.SkyOpsArty_BaseDir = 1000
		function spg:LookupAttachment() return 3 end
		function spg:GetAttachment() return { Pos = self.pos, Ang = Angle( -20, 75, 0 ) } end

		local d1, e1, b1 = A.GunLaying( spg )
		local _, _, FC = setup( true )
		local d2, e2, b2 = FC.GunLaying( spg )

		T.near( d1, d2, 1e-6, "угломер" ) T.near( e1, e2, 1e-6, "прицел" ) T.near( b1, b2, 1e-6, "азимут" )
		teardown()
	end )

	T.it( "поправки: точка прицеливания сдвинута ровно на «правее/дальше»", function()
		local A = setup( false )

		A.Target = { e = 55000, n = 52000, h = 100 }

		for _, s in ipairs( { { 0, 100 }, { 50, 0 }, { -30, -70 }, { 12.5, 220 } } ) do
			A.Shift = { lat = s[ 1 ], rng = s[ 2 ] }

			local ae, an = A.AimPoint( 50000, 50000 )
			local lat, rng = A.Deviation( 50000, 50000, 55000, 52000, ae, an )

			T.near( lat, s[ 1 ], 1e-9, "правее" ) T.near( rng, s[ 2 ], 1e-9, "дальше" )
		end

		-- «дальше» вдоль линии огня, «правее» = по часовой от неё
		A.Shift = { lat = 100, rng = 0 }

		local ae, an = A.AimPoint( 50000, 50000 ) -- цель на северо-востоке
		T.ok( ae > 55000 and an < 52000, "правее при стрельбе на северо-восток = к юго-востоку" )
		teardown()
	end )

	T.it( "FmtMils / FmtDeviation", function()
		local A = setup( false )

		T.eq( A.FmtMils( 1234 ), "12-34" )
		T.eq( A.FmtMils( 3000 ), "30-00" )
		T.eq( A.FmtMils( 5 ), "0-05" )
		T.eq( A.FmtMils( 5999.7 ), "0-00" )
		T.eq( A.FmtMils( -100 ), "59-00" )
		T.eq( A.FmtDeviation( 42, -118 ), "правее 40, ближе 120" )
		T.eq( A.FmtDeviation( -3, 0 ), "левее 5, дальше 0" )
		teardown()
	end )

	T.it( "запасной расчёт (без core): решает и помечает как черновой", function()
		local A = setup( false )
		local s = A.Solve( { gun = { x = 0, y = 0, h = 0 }, target = { x = 0, y = 12000, h = 0 }, shell = "he", charge = 1, basedir = 0 } )

		T.ok( s.ok, tostring( s.err ) )
		T.ok( s.approx, "нет пометки approx" )
		T.near( s.deflection, 3000, 1e-9 )

		local far = A.Solve( { gun = { x = 0, y = 0, h = 0 }, target = { x = 0, y = 90000, h = 0 }, shell = "he", charge = 1, basedir = 0 } )
		T.ok( not far.ok and far.err, "90 км решилось" )
		teardown()
	end )

	T.it( "DroneTrack: число 1 вместо точки = нет захвата", function()
		local A = setup( false )
		local d = gm.entity( { class = "sw_zala" } )

		d.nw.TrackPos = 1
		T.eq( A.DroneTrack( d ), nil )
		d.nw.TrackPos = Vector( 1000, 2000, 300 )
		T.ok( A.DroneTrack( d ), "точка захвата потерялась" )
		function d:GetTracking() return false end
		T.eq( A.DroneTrack( d ), nil, "трекинг выключен" )
		teardown()
	end )

	T.it( "net: skyops_arty_impact кладёт разрыв, список не длиннее 20", function()
		local A = setup( false )

		for i = 1, 25 do gm.deliver( "skyops_arty_impact", { Vector( i, 0, 0 ), "he" } ) end

		T.eq( #A.Impacts, 20 )
		T.eq( A.Impacts[ 1 ].pos.x, 25, "новый разрыв первым" )
		teardown()
	end )
end )
