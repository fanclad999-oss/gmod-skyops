-- Артиллерия, дрон-корректировщик: настройки дронов и общие функции.
-- Дроны Ryuunosuke (sw_zala, sw_orlan10, sw_pchela1t, sw_ravenseye) не трогаем,
-- всё поведение (барраж, подсветка, переключение) добавляем поверх них.
-- Все числа здесь игровые: подобраны под удобство игры, а не под реальную технику.

SkyOps = SkyOps or {}
SkyOps.Arty = SkyOps.Arty or {}
SkyOps.Arty.Drone = SkyOps.Arty.Drone or {}

local D = SkyOps.Arty.Drone

-- loiter      = умеет барражировать (только самолётные дроны)
-- radius      = радиус круга барража, м
-- throttle    = газ на барраже, 0..1
-- lead        = насколько вперёд по кругу дрон целится, градусы
-- laserRange  = дальность подсветки, м
-- errBase / errPerKm = ошибка передачи координат в режиме hardcore, м
D.Types = {
	sw_zala = {
		name = "ZALA 421-16Е", loiter = true, radius = 350, throttle = 0.75, lead = 30,
		laserRange = 5000, errBase = 10, errPerKm = 8,
	},
	sw_orlan10 = {
		name = "Орлан-10", loiter = true, radius = 450, throttle = 0.7, lead = 30,
		laserRange = 7000, errBase = 8, errPerKm = 5,
	},
	sw_pchela1t = {
		name = "Пчела-1Т", loiter = true, radius = 500, throttle = 0.8, lead = 30,
		laserRange = 6000, errBase = 12, errPerKm = 6,
	},
	sw_ravenseye = {
		name = "Raven's Eye", loiter = false,
		laserRange = 3000, errBase = 15, errPerKm = 10,
	},
}

D.STATION = "sw_uav_control"

function D.UPM()
	return ( KIR and KIR.S ) or SkyOps.M_TO_HU or 40
end

function D.IsDrone( ent )
	return IsValid( ent ) and D.Types[ ent:GetClass() ] ~= nil
end

function D.Config( ent )
	return IsValid( ent ) and D.Types[ ent:GetClass() ] or nil
end

-- дрон, которым игрок управляет прямо сейчас (сидит в его кресле)
function D.GetControlled( ply )
	if not IsValid( ply ) or not ply.lvsGetVehicle then return nil end

	local veh = ply:lvsGetVehicle()

	if D.IsDrone( veh ) then return veh end
end

-- последний дрон игрока: для переключения САУ <-> дрон и для карты
function D.GetLinked( ply )
	if not IsValid( ply ) then return nil end

	local d = ply:GetNW2Entity( "SkyOpsArty_Drone" )

	if D.IsDrone( d ) then return d end
end

function D.Station( drone )
	local st = drone:GetNWEntity( "UAVControl" )

	return IsValid( st ) and st or nil
end

-- Точка захвата стоковой камеры (абсолютная мировая) или nil.
-- Стоковый код кладёт её в NWVector "TrackPos", а NWVector обрезает координаты
-- дальше ±16384 u: на InfMap клиент получает мусор. Поэтому сервер берёт точку из
-- Lua-полей дрона и копирует её в три NW2Float SkyOpsArty_TrackPos_* (ниже, Tick),
-- а клиент читает уже их.
local function ServerTrackPos( drone )
	if drone.GetTracking and not drone:GetTracking() then return nil end

	if drone.TrackType and IsValid( drone.TrackEnt ) then
		return drone.TrackEnt:LocalToWorld( drone.TrackEnt:OBBCenter() )
	end

	local p = drone.TrackPos

	if not isvector( p ) or p:LengthSqr() < 100 then return nil end

	return p
end

function D.TrackPos( drone )
	if SERVER then return ServerTrackPos( drone ) end

	if not drone:GetNW2Bool( "SkyOpsArty_Track", false ) then return nil end

	return D.GetNWPos( drone, "SkyOpsArty_TrackPos" )
end

-- Позиции в NW2 храним тремя float: NW2Vector, как и net.WriteVector, сжимает
-- координаты в ±16384 u, а на InfMap они намного больше. Значения абсолютные (как
-- GetPos() на сервере); на клиенте InfMap их ещё надо перевести в чанк LocalPlayer.
function D.SetNWPos( ent, key, v )
	ent:SetNW2Float( key .. "_X", v.x )
	ent:SetNW2Float( key .. "_Y", v.y )
	ent:SetNW2Float( key .. "_Z", v.z )
end

function D.GetNWPos( ent, key )
	return Vector( ent:GetNW2Float( key .. "_X", 0 ), ent:GetNW2Float( key .. "_Y", 0 ), ent:GetNW2Float( key .. "_Z", 0 ) )
end

-- центр круга барража (абсолютная мировая) и радиус в юнитах или nil
function D.LoiterCenter( drone )
	if not drone:GetNW2Bool( "SkyOpsArty_Loiter", false ) then return nil end

	return D.GetNWPos( drone, "SkyOpsArty_LoiterCenter" ), drone:GetNW2Float( "SkyOpsArty_LoiterRadius", 0 )
end

-- подсветка: точка (абсолютная мировая) и сорван ли луч
function D.LaserPos( drone )
	if not drone:GetNW2Bool( "SkyOpsArty_Laser", false ) then return nil end

	return D.GetNWPos( drone, "SkyOpsArty_LaserPos" ), drone:GetNW2Bool( "SkyOpsArty_LaserBlocked", false )
end

function D.All()
	local list = {}

	for class in pairs( D.Types ) do
		for _, e in ipairs( ents.FindByClass( class ) ) do list[ #list + 1 ] = e end
	end

	return list
end

if SERVER then
	util.AddNetworkString( "skyops_arty_drone" )
	util.AddNetworkString( "skyops_arty_target" )

	hook.Add( "Tick", "SkyOpsArty.Drone.Track", function()
		for _, drone in ipairs( D.All() ) do
			local p = ServerTrackPos( drone )

			drone:SetNW2Bool( "SkyOpsArty_Track", p ~= nil )

			if p then D.SetNWPos( drone, "SkyOpsArty_TrackPos", p ) end
		end
	end )

	-- обработчики команд с клиента: D.Commands[ cmd ]( ply, drone ), drone = управляемый или nil
	D.Commands = D.Commands or {}

	function D.Notify( ply, text )
		if IsValid( ply ) then ply:PrintMessage( HUD_PRINTCENTER, text ) end
	end

	local function Run( ply, cmd )
		local fn = D.Commands[ cmd ]

		if not fn then return end

		fn( ply, D.GetControlled( ply ) )
	end

	net.Receive( "skyops_arty_drone", function( _, ply )
		Run( ply, net.ReadString() )
	end )

end

-- консольная команда на клиенте (с автодополнением), чтобы её знала консоль игрока:
-- skyops_arty_drone_cmd laser | loiter | send | switch. Клавиши по умолчанию даёт интерфейс:
-- T передать, G подсветка, J барраж, U пересесть.
if CLIENT then
	local CMDS = { "laser", "loiter", "send", "switch" }

	concommand.Add( "skyops_arty_drone_cmd", function( _, _, args )
		local cmd = args[ 1 ]

		if not cmd or not table.HasValue( CMDS, cmd ) then
			print( "skyops_arty_drone_cmd: " .. table.concat( CMDS, " | " ) )

			return
		end

		if util.NetworkStringToID( "skyops_arty_drone" ) == 0 then
			print( "skyops_arty_drone_cmd: на сервере нет модуля дрона" )

			return
		end

		net.Start( "skyops_arty_drone" )
		net.WriteString( cmd )
		net.SendToServer()
	end, function( name )
		local list = {}

		for _, c in ipairs( CMDS ) do list[ #list + 1 ] = name .. " " .. c end

		return list
	end, "Команда дрону: laser | loiter | send | switch" )
end
