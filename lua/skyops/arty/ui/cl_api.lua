-- Артиллерия, интерфейс: единственное место, которое обращается к модулям баллистики
-- (arty/core: SkyOps.Arty.Grid, SkyOps.Arty.FireComp) и дрона (arty/drone: SkyOps.Arty.Drone).
-- Остальные файлы arty/ui/ зовут только A.*. Пока тех модулей нет, работают запасные
-- реализации: сетка от центра карты, баллистика точкой с сопротивлением воздуха.
-- Файл называется cl_api, чтобы загрузчик подключал его первым в ui/.

SkyOps = SkyOps or {}
SkyOps.Arty = SkyOps.Arty or {}
SkyOps.Arty.UI = SkyOps.Arty.UI or {}

local UI = SkyOps.Arty.UI
local A = UI.API or {}

UI.API = A

A.MILS = 6000
A.SPG_CLASS = "sw_2s35"
A.UAV = {
	sw_zala = "ZALA 421-16Е",
	sw_orlan10 = "Орлан-10",
	sw_pchela1t = "Пчела-1Т",
	sw_ravenseye = "Raven's Eye",
}
A.UAV_STATION = "sw_uav_control"

local function Grid() return SkyOps.Arty.Grid end
local function FC() return SkyOps.Arty.FireComp end
local function Drone() return SkyOps.Arty.Drone end

-- что из чужих модулей уже есть (для подписи «черновой расчёт» в интерфейсе)
function A.HasGrid() return Grid() ~= nil and Grid().ToGrid ~= nil end
function A.HasFireComp() return FC() ~= nil and FC().Solve ~= nil end
function A.HasDrone() return Drone() ~= nil end

-- Режим ---------------------------------------------------------------------

-- Режим задаёт сервер (реплицируемый skyops_arty_mode). Без модуля баллистики
-- на сервере его нет, тогда берём клиентский skyops_arty_ui_mode для проверки интерфейса.
local cvLocalMode = CreateClientConVar( "skyops_arty_ui_mode", "hardcore", false, false, "Режим интерфейса, пока сервер не задаёт skyops_arty_mode: hardcore | auto" )

function A.Mode()
	local cv = GetConVar( "skyops_arty_mode" )
	local mode = cv and cv:GetString() or cvLocalMode:GetString()

	return mode == "auto" and "auto" or "hardcore"
end

function A.IsAuto() return A.Mode() == "auto" end

-- Переключение доступно админу; в одиночной игре и на своём listen-сервере это хост.
function A.SetMode( mode )
	if GetConVar( "skyops_arty_mode" ) then
		RunConsoleCommand( "skyops_arty_mode", mode )
	else
		RunConsoleCommand( "skyops_arty_ui_mode", mode )
	end
end

-- Единицы и координаты ------------------------------------------------------

function A.UPM()
	local G = Grid()

	if G and G.UPM then return G.UPM() end

	return ( KIR and KIR.S ) or SkyOps.M_TO_HU or 40
end

local FALLBACK_ORIGIN = 50000 -- м: сдвиг, чтобы координаты без модуля сетки были положительными

-- InfMap на клиенте: Entity:GetPos() считается от чанка LocalPlayer, а сервер, сеть и
-- Grid.ToGrid работают с абсолютными (развёрнутыми) позициями. Все позиции сущностей в
-- интерфейсе берём через A.EntPos.
local function ChunkShift()
	local ply = LocalPlayer()

	if not InfMap or not InfMap.unlocalize_vector or not IsValid( ply ) or not ply.CHUNK_OFFSET then return nil end

	return InfMap.unlocalize_vector( Vector(), ply.CHUNK_OFFSET )
end

function A.EntPos( ent )
	local shift = ChunkShift()

	return shift and ( ent:GetPos() + shift ) or ent:GetPos()
end

-- абсолютная позиция -> позиция для отрисовки у этого клиента
function A.ToRender( pos )
	local shift = ChunkShift()

	return shift and ( pos - shift ) or pos
end

-- позиция в сети: три Float, net.WriteVector обрезает дальше ±16384 u
function A.ReadPos() return Vector( net.ReadFloat(), net.ReadFloat(), net.ReadFloat() ) end

function A.WritePos( v )
	net.WriteFloat( v.x )
	net.WriteFloat( v.y )
	net.WriteFloat( v.z )
end

-- мировая позиция -> восток, север, высота в метрах
function A.ToGrid( pos )
	local G = Grid()
	local upm = A.UPM()
	local h = pos.z / upm

	if G and G.ToGrid then
		local e, n = G.ToGrid( pos )

		return e, n, h
	end

	return pos.x / upm + FALLBACK_ORIGIN, pos.y / upm + FALLBACK_ORIGIN, h
end

-- восток, север (м), высота (м или nil = по рельефу) -> мировая позиция
function A.FromGrid( e, n, h )
	local G = Grid()
	local upm = A.UPM()
	local pos

	if G and G.FromGrid then
		pos = G.FromGrid( e, n, h )
	else
		pos = Vector( ( e - FALLBACK_ORIGIN ) * upm, ( n - FALLBACK_ORIGIN ) * upm, 0 )
	end

	if h then
		pos.z = h * upm
	else
		local z = A.GroundZ( pos.x, pos.y )

		if z then pos.z = z end
	end

	return pos
end

-- высота рельефа в мировых юнитах или nil
function A.GroundZ( x, y )
	local G = Grid()

	if G and G.GroundZ then return G.GroundZ( x, y ) end

	local fn = SkyOps.Map and ( SkyOps.Map.SafeGroundZ or SkyOps.Map.GroundZ )

	if not fn then return nil end

	local ok, z = pcall( fn, x, y, 0 )

	if not ok or not z or z ~= z or math.abs( z ) == math.huge then return nil end

	return z
end

function A.GroundH( e, n )
	local G = Grid()

	if G and G.Height then return G.Height( e, n ) end

	local pos = A.FromGrid( e, n, 0 )
	local z = A.GroundZ( pos.x, pos.y )

	return z and z / A.UPM() or nil
end

function A.SquareSize()
	local G = Grid()

	return G and G.SquareSize or 1000
end

-- квадрат и «улитка»: 1 2 3 / 8 9 4 / 7 6 5
local SNAIL = { [0] = { 7, 6, 5 }, [1] = { 8, 9, 4 }, [2] = { 1, 2, 3 } }

function A.Square( e, n )
	local s = A.SquareSize()
	local sn, se = math.floor( n / s ), math.floor( e / s )
	local fe = math.Clamp( math.floor( ( e - se * s ) / s * 3 ), 0, 2 )
	local fn = math.Clamp( math.floor( ( n - sn * s ) / s * 3 ), 0, 2 )

	return string.format( "%02d-%02d", sn % 100, se % 100 ), SNAIL[ fn ][ fe + 1 ]
end

-- своя запись, а не Grid.Format: квадрат и улитку интерфейс показывает отдельно
function A.FormatGrid( e, n )
	return string.format( "С %05d  В %05d", math.Round( n ), math.Round( e ) )
end

-- Углы ----------------------------------------------------------------------

local function NorthYaw()
	local maps = SkyOps.Maps

	return ( maps and maps.kirovskoe and maps.kirovskoe.north_yaw ) or 90
end

-- yaw Source (против часовой от +X) -> дирекционный угол в градусах (от севера по часовой)
function A.YawToBearing( yaw )
	return ( NorthYaw() - yaw ) % 360
end

function A.BearingToYaw( bearing )
	return NorthYaw() - bearing
end

function A.DegToMils( d ) return d / 360 * A.MILS end
function A.MilsToDeg( m ) return m / A.MILS * 360 end

-- 1234 -> "12-34", как пишут угломер и прицел
function A.FmtMils( m )
	if not m then return "--‑--" end

	m = math.Round( m ) % A.MILS

	return string.format( "%d-%02d", math.floor( m / 100 ), m % 100 )
end

-- разность углов в тысячных со знаком, -3000..3000
function A.MilsDiff( a, b )
	return ( a - b + A.MILS / 2 ) % A.MILS - A.MILS / 2
end

-- дирекционный угол из точки (e1, n1) на (e2, n2), тысячные
function A.Bearing( e1, n1, e2, n2 )
	return A.DegToMils( math.deg( math.atan2( e2 - e1, n2 - n1 ) ) % 360 )
end

-- угломер: 30-00 по основному направлению, растёт против часовой
function A.Deflection( bearing, basedir )
	return ( A.MILS / 2 + basedir - bearing ) % A.MILS
end

-- Снаряды и заряды ----------------------------------------------------------

A.SHELLS = {
	{ id = "he", name = "ОФС" },
	{ id = "krasnopol", name = "Краснополь" },
}

-- с модулем баллистики список берётся из него (дымовой, осветительный, кассетный)
if FC() and FC().ShellOrder then
	local SHORT = { he = "ОФС", krasnopol = "Краснополь", smoke = "Дым", illum = "Свет", cluster = "Кассет." }

	A.SHELLS = {}

	for _, id in ipairs( FC().ShellOrder ) do
		A.SHELLS[ #A.SHELLS + 1 ] = { id = id, name = SHORT[ id ] or FC().Shells[ id ].name }
	end
end

-- запасные заряды: начальная скорость, м/с
local FALLBACK_CHARGES = {
	{ id = 1, name = "Полный", v0 = 945 },
	{ id = 2, name = "Уменьшенный", v0 = 800 },
	{ id = 3, name = "Первый", v0 = 650 },
	{ id = 4, name = "Второй", v0 = 500 },
	{ id = 5, name = "Третий", v0 = 380 },
	{ id = 6, name = "Четвёртый", v0 = 290 },
}

function A.Charges( shell )
	local F = FC()

	if F and F.Charges then return F.Charges( shell ) end

	return FALLBACK_CHARGES
end

-- Запасная баллистика: точка, g и квадратичное сопротивление, шаг 0.1 с.
-- Возвращает дальность, где нисходящая ветвь проходит высоту dh, время и высоту вершины.
local G_ACC = 9.81
local DRAG = 4e-5 -- 1/м, подобрано под ~30 км на полном заряде

local function Fly( theta, v0, dh )
	local vx, vz = v0 * math.cos( theta ), v0 * math.sin( theta )
	local x, z, t, apex = 0, 0, 0, 0
	local dt = 0.1

	while t < 400 do
		local v = math.sqrt( vx * vx + vz * vz )
		local px, pz = x, z

		vx = vx - DRAG * v * vx * dt
		vz = vz - ( G_ACC + DRAG * v * vz ) * dt
		x = x + vx * dt
		z = z + vz * dt
		t = t + dt
		apex = math.max( apex, z )

		if vz < 0 and z <= dh then
			if apex < dh then return nil end

			local f = ( pz - dh ) / math.max( pz - z, 1e-6 )

			return px + ( x - px ) * f, t - dt + dt * f, apex
		end
	end
end

local function FallbackSolve( q )
	local charge

	for _, c in ipairs( FALLBACK_CHARGES ) do
		if c.id == q.charge then charge = c end
	end

	charge = charge or FALLBACK_CHARGES[ 1 ]

	local de, dn = q.target.x - q.gun.x, q.target.y - q.gun.y
	local range = math.sqrt( de * de + dn * dn )
	local dh = ( q.target.h or 0 ) - ( q.gun.h or 0 )
	local bearing = A.Bearing( q.gun.x, q.gun.y, q.target.x, q.target.y )
	local res = { range = range, bearing = bearing, deflection = A.Deflection( bearing, q.basedir or 0 ) }

	-- самый дальний угол на этом заряде делит углы на нижнюю и верхнюю группу
	local bestTheta, bestRange = nil, -1

	for deg = 1, 80 do
		local r = Fly( math.rad( deg ), charge.v0, dh )

		if r and r > bestRange then bestTheta, bestRange = deg, r end
	end

	if not bestTheta or range > bestRange then
		res.ok, res.err = false, string.format( "Цель вне досягаемости: заряд «%s» до %.1f км", charge.name, math.max( bestRange, 0 ) / 1000 )

		return res
	end

	local lo, hi

	if q.high then lo, hi = math.rad( 80 ), math.rad( bestTheta ) else lo, hi = math.rad( 0.5 ), math.rad( bestTheta ) end

	-- дальность монотонна по углу внутри группы: бисекция
	for _ = 1, 30 do
		local mid = ( lo + hi ) / 2
		local r = Fly( mid, charge.v0, dh ) or 0

		if r < range then lo = mid else hi = mid end
	end

	local theta = ( lo + hi ) / 2
	local r, tof, apex = Fly( theta, charge.v0, dh )

	if not r then
		res.ok, res.err = false, "Нет решения: цель выше траектории"

		return res
	end

	res.ok = true
	res.elevation = A.DegToMils( math.deg( theta ) )
	res.tof = tof
	res.apex = apex + ( q.gun.h or 0 )
	res.approx = true

	return res
end

-- наименьшая и наибольшая дальность заряда, м (для кругов на карте)
local RangeCache = {}

function A.ChargeRange( shell, chargeId )
	for _, c in ipairs( A.Charges( shell ) ) do
		if c.id == chargeId then
			if c.max then return c.min or 0, c.max, c.minHigh end

			local key = shell .. "/" .. chargeId

			if not RangeCache[ key ] and c.v0 then
				local best = 0

				for deg = 20, 60 do best = math.max( best, Fly( math.rad( deg ), c.v0, 0 ) or 0 ) end

				RangeCache[ key ] = best
			end

			return 0, RangeCache[ key ]
		end
	end
end

-- самый слабый заряд, который достаёт до дальности (заряд «авто»)
function A.BestCharge( shell, range, dh )
	local F = FC()

	if F and F.BestCharge then return F.BestCharge( shell, range, dh ) end

	local list = A.Charges( shell )

	for i = #list, 1, -1 do
		local _, maxR = A.ChargeRange( shell, list[ i ].id )

		if maxR and maxR >= range * 1.05 then return list[ i ].id end
	end

	return list[ 1 ] and list[ 1 ].id or 1
end

-- q = { gun = {x, y, h}, target = {x, y, h}, shell, charge, high, basedir }
function A.Solve( q )
	local F = FC()

	if F and F.Solve then return F.Solve( q ) end

	return FallbackSolve( q )
end

-- Техника -------------------------------------------------------------------

function A.Vehicle( ply )
	ply = ply or LocalPlayer()

	if not IsValid( ply ) or not ply.lvsGetVehicle then return nil end

	local veh = ply:lvsGetVehicle()

	return IsValid( veh ) and veh or nil
end

-- САУ игрока: в которой сидит, последняя, в которой сидел, или ближайшая в 500 м
function A.MySPG()
	local veh = A.Vehicle()

	if veh and veh:GetClass() == A.SPG_CLASS then
		A.LastSPG = veh

		return veh
	end

	if IsValid( A.LastSPG ) then return A.LastSPG end

	local ply = LocalPlayer()
	local best, bestD = nil, ( 500 * A.UPM() ) ^ 2

	for _, spg in ipairs( ents.FindByClass( A.SPG_CLASS ) ) do
		local d = A.EntPos( spg ):DistToSqr( A.EntPos( ply ) )

		if d < bestD then best, bestD = spg, d end
	end

	return best
end

function A.InSPG()
	local veh = A.Vehicle()

	return veh ~= nil and veh:GetClass() == A.SPG_CLASS and veh or nil
end

function A.IsDeployed( spg )
	if not A.HasFireComp() then return true end -- без модуля баллистики развёртывания нет

	return spg:GetNW2Bool( "SkyOpsArty_Deployed", false )
end

-- основное направление ОП, тысячные; без привязки берём курс корпуса
function A.BaseDir( spg )
	local v = spg:GetNW2Float( "SkyOpsArty_BaseDir", -1 )

	if v >= 0 then return v, true end

	return A.DegToMils( A.YawToBearing( spg:GetAngles().y ) ), false
end

-- текущие угломер и прицел орудия, тысячные
function A.GunLaying( spg )
	local F = FC()

	if F and F.GunLaying then return F.GunLaying( spg ) end

	local att = spg:LookupAttachment( "muzzle" )
	local ang = att and att > 0 and spg:GetAttachment( att )

	ang = ang and ang.Ang or spg:GetAngles()

	local bearing = A.DegToMils( A.YawToBearing( ang.y ) )

	return A.Deflection( bearing, ( A.BaseDir( spg ) ) ), A.DegToMils( -ang.p ), bearing
end

-- состояние ОП (arty/core/sv_spg): марш, развёртывание, развёрнута, свёртывание
A.STATE_MARCH, A.STATE_DEPLOYING, A.STATE_DEPLOYED, A.STATE_STOWING = 0, 1, 2, 3
A.STATE_NAMES = {
	[ 0 ] = "ПОХОДНОЕ ПОЛОЖЕНИЕ",
	[ 1 ] = "РАЗВЁРТЫВАНИЕ",
	[ 2 ] = "РАЗВЁРНУТА",
	[ 3 ] = "СВЁРТЫВАНИЕ",
}

-- состояние и оставшееся время перехода, с
function A.SPGState( spg )
	if not A.HasFireComp() then return A.STATE_DEPLOYED, 0 end

	local state = spg:GetNW2Int( "SkyOpsArty_State", spg:GetNW2Bool( "SkyOpsArty_Deployed", false ) and A.STATE_DEPLOYED or A.STATE_MARCH )

	return state, math.max( spg:GetNW2Float( "SkyOpsArty_StateEnd", 0 ) - CurTime(), 0 )
end

-- снаряд, который сейчас выбран в самой САУ (стоковая клавиша смены снаряда)
function A.LoadedShell( spg )
	local F = FC()
	local t = spg.GetShellType and spg:GetShellType() or 0

	if F and F.LoadedShell then return F.LoadedShell( spg ) end
	if F and F.ShellForStockType then return F.ShellForStockType( t ) end

	return t == 1 and "krasnopol" or "he"
end

-- заряд, заложенный в САУ (0 = модуль баллистики не задал)
function A.LoadedCharge( spg )
	return spg:GetNW2Int( "SkyOpsArty_Charge", 0 )
end

function A.AutoLaying( spg ) return spg:GetNW2Bool( "SkyOpsArty_Auto", false ) end

-- ветер по метеобюллетеню: "4 м/с с 45-00" (откуда дует); nil без модуля ветра
function A.WindText()
	local W = SkyOps.Arty.Wind

	if not W or not W.BulletinDirSpeed then return nil end

	local d, sp = W.BulletinDirSpeed()

	if sp < 0.5 then return "штиль" end

	return string.format( "%.0f м/с с %s", sp, A.FmtMils( d ) )
end

-- выбрать заряд в САУ, в которой сидит игрок
function A.SetGunCharge( id )
	if A.InSPG() and A.HasFireComp() then RunConsoleCommand( "skyops_arty_charge", tostring( id ) ) end
end

function A.ShellName( id )
	for _, s in ipairs( A.SHELLS ) do
		if s.id == id then return s.name end
	end

	return "?"
end

function A.ChargeName( shell, id )
	for _, c in ipairs( A.Charges( shell ) ) do
		if c.id == id then return c.name end
	end

	return id == 0 and "авто" or "?"
end

-- клавиши САУ из arty/core/sh_spg (развернуть, заряд, наводка)
function A.SPGKey( name )
	local S = SkyOps.Arty.SPG

	return S and S.KeyName and S.KeyName( name ) or nil
end

function A.IsUAV( ent )
	return IsValid( ent ) and A.UAV[ ent:GetClass() ] ~= nil
end

-- дрон, которым управляет игрок
function A.MyDrone()
	local D = Drone()

	if D and D.GetControlled then
		local d = D.GetControlled( LocalPlayer() )

		if IsValid( d ) then return d end
	end

	local veh = A.Vehicle()

	if not veh then return nil end
	if A.IsUAV( veh ) then return veh end

	if veh:GetClass() == A.UAV_STATION then
		local d = ( veh.GetUAV and veh:GetUAV() ) or veh:GetNWEntity( "UAV" )

		if A.IsUAV( d ) then return d end
	end
end

-- последний дрон игрока (arty/drone), в том числе пока он сидит в САУ
function A.LinkedDrone()
	local D = Drone()

	if D and D.GetLinked then
		local d = D.GetLinked( LocalPlayer() )

		if IsValid( d ) then return d end
	end

	local d = LocalPlayer():GetNW2Entity( "SkyOpsArty_Drone" )

	return IsValid( d ) and d or A.MyDrone()
end

-- пятно подсветки (мировое) и сорван ли луч, или nil
function A.DroneLaserSpot( drone )
	if not A.DroneLaser( drone ) then return nil end

	local D = Drone()

	if D and D.LaserPos then
		local p, blocked = D.LaserPos( drone )

		if p and p ~= vector_origin then return p, blocked end

		return A.DroneTrack( drone ), false
	end

	local p = drone:GetNW2Vector( "SkyOpsArty_LaserPos", vector_origin )

	if p == vector_origin then return A.DroneTrack( drone ), false end

	return p, drone:GetNW2Bool( "SkyOpsArty_LaserBlocked", false )
end

function A.AllDrones()
	local list = {}

	for class in pairs( A.UAV ) do
		for _, e in ipairs( ents.FindByClass( class ) ) do list[ #list + 1 ] = e end
	end

	return list
end

-- точка, куда смотрит камера дрона (мировая) или nil
-- позиции с дрона берём через функции модуля дрона: как они упакованы в NW2
-- (вектор или три числа, см. «Правила для позиций в сети»), знает только он
function A.DroneTrack( drone )
	local D = Drone()

	if D and D.TrackPos then return D.TrackPos( drone ) end

	-- копия точки захвата от модуля дрона: стоковый NWVector на InfMap обрезается
	if drone:GetNW2Bool( "SkyOpsArty_Track", false ) then
		return Vector( drone:GetNW2Float( "SkyOpsArty_TrackPos_X", 0 ), drone:GetNW2Float( "SkyOpsArty_TrackPos_Y", 0 ), drone:GetNW2Float( "SkyOpsArty_TrackPos_Z", 0 ) )
	end

	local p = drone:GetNWVector( "TrackPos", vector_origin )
	local tracking = drone.GetTracking and drone:GetTracking()

	-- без захвата стоковый код кладёт туда число 1, а не точку
	if not isvector( p ) or p:LengthSqr() < 100 or tracking == false then return nil end

	return p
end

function A.DroneLaser( drone ) return drone:GetNW2Bool( "SkyOpsArty_Laser", false ) end
-- центр и радиус круга барражирования (мировые) или nil
function A.DroneLoiter( drone )
	if not drone:GetNW2Bool( "SkyOpsArty_Loiter", false ) then return nil end

	local D = Drone()

	if D and D.LoiterCenter then
		local c, r = D.LoiterCenter( drone )

		if c then return c, r or drone:GetNW2Float( "SkyOpsArty_LoiterRadius", 0 ) end
	end

	local c = Vector( drone:GetNW2Float( "SkyOpsArty_LoiterCenter_X", 0 ), drone:GetNW2Float( "SkyOpsArty_LoiterCenter_Y", 0 ), drone:GetNW2Float( "SkyOpsArty_LoiterCenter_Z", 0 ) )

	return c ~= vector_origin and c or A.EntPos( drone ), drone:GetNW2Float( "SkyOpsArty_LoiterRadius", 0 )
end

-- Сеть ----------------------------------------------------------------------

-- false, если сервер не знает сообщения (нет соответствующего модуля)
function A.Send( name, write )
	if util.NetworkStringToID( name ) == 0 then return false end

	net.Start( name )
	if write then write() end
	net.SendToServer()

	return true
end

function A.DroneCmd( cmd )
	return A.Send( "skyops_arty_drone", function() net.WriteString( cmd ) end )
end

function A.AutoFire( spg, pos, shell, charge )
	return A.Send( "skyops_arty_auto", function()
		net.WriteEntity( spg )
		A.WritePos( pos )
		net.WriteString( shell or "he" )
		net.WriteUInt( charge or 1, 8 )
	end )
end

-- Состояние расчёта на этом клиенте -----------------------------------------

A.Target = A.Target -- { pos, e, n, h, src, err, time }
A.Shift = A.Shift or { lat = 0, rng = 0 } -- поправки, м: правее +, дальше +
A.Impacts = A.Impacts or {}

-- выбор в вычислителе и последний расчёт; читают карта и шкалы наводчика
UI.State = UI.State or { shell = "he", charge = 0, high = false, solution = nil }

function A.SetTarget( pos, src, err )
	local e, n, h = A.ToGrid( pos )

	A.Target = { pos = pos, e = e, n = n, h = h, src = src, err = err, time = CurTime() }
	A.Shift = { lat = 0, rng = 0 }

	hook.Run( "SkyOpsArty.TargetChanged", A.Target )
end

-- единичный вектор направления стрельбы (восток, север) от ОП на цель
function A.FireAxis( ge, gn, te, tn )
	local de, dn = te - ge, tn - gn
	local len = math.max( math.sqrt( de * de + dn * dn ), 1 )

	return de / len, dn / len
end

-- отклонение точки от цели относительно линии стрельбы: правее +, дальше +
function A.Deviation( ge, gn, te, tn, pe, pn )
	local ue, un = A.FireAxis( ge, gn, te, tn )
	local de, dn = pe - te, pn - tn

	return de * un - dn * ue, de * ue + dn * un
end

-- точка прицеливания = цель, сдвинутая на поправки
function A.AimPoint( ge, gn )
	local t = A.Target

	if not t then return nil end

	local ue, un = A.FireAxis( ge, gn, t.e, t.n )
	local lat, rng = A.Shift.lat, A.Shift.rng

	return t.e + ue * rng + un * lat, t.n + un * rng - ue * lat, t.h
end

-- «правее 40, дальше 120»
function A.FmtDeviation( lat, rng )
	local a = math.Round( math.abs( lat ) / 5 ) * 5
	local b = math.Round( math.abs( rng ) / 5 ) * 5

	return ( lat >= 0 and "правее " or "левее " ) .. a .. ", " .. ( rng >= 0 and "дальше " or "ближе " ) .. b
end

net.Receive( "skyops_arty_impact", function()
	local pos = A.ReadPos()
	local shell = net.ReadString()

	table.insert( A.Impacts, 1, { pos = pos, shell = shell, time = CurTime() } )

	while #A.Impacts > 20 do table.remove( A.Impacts ) end

	hook.Run( "SkyOpsArty.Impact", pos, shell )
end )

net.Receive( "skyops_arty_target", function()
	local pos = A.ReadPos()
	local err = net.ReadFloat()
	local drone = net.ReadEntity()

	A.SetTarget( pos, IsValid( drone ) and ( A.UAV[ drone:GetClass() ] or "дрон" ) or "дрон", err )

	surface.PlaySound( "buttons/blip1.wav" )
	notification.AddLegacy( "Получены координаты цели: " .. A.FormatGrid( A.Target.e, A.Target.n ), NOTIFY_HINT, 5 )
end )

-- Клавиши -------------------------------------------------------------------

-- PlayerButtonDown на клиенте в одиночной игре не вызывается, поэтому опрос в Think
local Binds = {}

function A.Bind( cvarName, default, help, fn, enabled )
	local cv = CreateClientConVar( cvarName, tostring( default ), true, false, help )

	Binds[ #Binds + 1 ] = { cv = cv, fn = fn, enabled = enabled }

	return cv
end

function A.KeyName( cv )
	return string.upper( input.GetKeyName( cv:GetInt() ) or "?" )
end

hook.Add( "Think", "SkyOpsArty.UI.Binds", function()
	local typing = vgui.GetKeyboardFocus() ~= nil or gui.IsGameUIVisible() or gui.IsConsoleVisible()
	local chat = LocalPlayer().IsTyping and LocalPlayer():IsTyping()

	for _, b in ipairs( Binds ) do
		local key = b.cv:GetInt()
		local down = key > 0 and input.IsKeyDown( key )

		if down and not b.down and not typing and not chat and ( not b.enabled or b.enabled() ) then
			b.fn()
		end

		b.down = down
	end
end )
