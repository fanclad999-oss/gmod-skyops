-- Артиллерия, дрон: игровая подсветка точки и передача координат цели.
-- Подсветка берёт точку захвата стоковой камеры (или то, во что смотрит камера)
-- и держит её сама, поэтому работает и после того, как игрок пересел в САУ.
-- Управляемые снаряды (sv_guided) доворачивают к этой точке.

local D = SkyOps.Arty.Drone

local cvLOS = CreateConVar( "skyops_arty_laser_los", "1", FCVAR_ARCHIVE, "1 = подсветка срывается, если между дроном и точкой препятствие" )
local cvErr = CreateConVar( "skyops_arty_send_error", "1", FCVAR_ARCHIVE, "1 = в режиме hardcore координаты с дрона передаются с ошибкой" )

local function Mode()
	local cv = GetConVar( "skyops_arty_mode" )

	return cv and cv:GetString() == "auto" and "auto" or "hardcore"
end

local function CameraTrace( drone )
	local att = drone:GetAttachment( drone:LookupAttachment( "view" ) or 0 )

	if not att then return nil end

	local tr = util.TraceLine( {
		start = att.Pos,
		endpos = att.Pos + att.Ang:Forward() * 999999,
		filter = drone.GetCrosshairFilterEnts and drone:GetCrosshairFilterEnts() or drone,
	} )

	if not tr.Hit then return nil end

	return tr.HitPos, IsValid( tr.Entity ) and tr.Entity or nil
end

-- точка, куда сейчас смотрит дрон: захват камеры, иначе луч из камеры
function D.AimPoint( drone )
	local p = D.TrackPos( drone )

	if p then
		local ent = drone.TrackType and IsValid( drone.TrackEnt ) and drone.TrackEnt or nil

		return p, ent
	end

	return CameraTrace( drone )
end

local function EntCenter( ent )
	return ent:LocalToWorld( ent:OBBCenter() )
end

function D.SetLaser( drone, on )
	if not on then
		drone.SkyOpsArty_LaserEnt = nil
		drone:SetNW2Bool( "SkyOpsArty_Laser", false )
		drone:SetNW2Bool( "SkyOpsArty_LaserBlocked", false )

		return true
	end

	local pos, ent = D.AimPoint( drone )

	if not pos then return false end

	drone.SkyOpsArty_LaserEnt = ent
	drone.SkyOpsArty_LaserSince = CurTime()
	D.SetNWPos( drone, "SkyOpsArty_LaserPos", pos )
	drone:SetNW2Bool( "SkyOpsArty_LaserBlocked", false )
	drone:SetNW2Bool( "SkyOpsArty_Laser", true )

	return true
end

-- видно ли точку с дрона: дальность из настроек и (по желанию) луч без препятствий
local function Visible( drone, pos, ent )
	local cfg = D.Config( drone )
	local upm = D.UPM()
	local from = drone:GetPos()

	if from:Distance( pos ) > cfg.laserRange * upm then return false end
	if not cvLOS:GetBool() then return true end

	local filter = { drone }

	if drone.GetCrosshairFilterEnts then filter = drone:GetCrosshairFilterEnts() end

	local tr = util.TraceLine( { start = from, endpos = pos, filter = filter, mask = MASK_SOLID } )

	if not tr.Hit then return true end
	if ent and tr.Entity == ent then return true end

	return tr.HitPos:DistToSqr( pos ) < ( 3 * upm ) ^ 2
end

local function UpdateLaser( drone )
	local ent = drone.SkyOpsArty_LaserEnt
	local pos

	if ent ~= nil then
		if not IsValid( ent ) then
			-- цель уничтожена: подсветка остаётся на последней точке
			drone.SkyOpsArty_LaserEnt = nil
		else
			pos = EntCenter( ent )
			D.SetNWPos( drone, "SkyOpsArty_LaserPos", pos )
		end
	end

	pos = pos or D.GetNWPos( drone, "SkyOpsArty_LaserPos" )

	drone:SetNW2Bool( "SkyOpsArty_LaserBlocked", not Visible( drone, pos, drone.SkyOpsArty_LaserEnt ) )
end

hook.Add( "Tick", "SkyOpsArty.Drone.Laser", function()
	for _, drone in ipairs( D.All() ) do
		if drone:GetNW2Bool( "SkyOpsArty_Laser", false ) then UpdateLaser( drone ) end
	end
end )

-- все незаблокированные пятна подсветки: { drone, pos }
function D.LaserSpots()
	local list = {}

	for _, drone in ipairs( D.All() ) do
		local pos, blocked = D.LaserPos( drone )

		if pos and not blocked then list[ #list + 1 ] = { drone = drone, pos = pos } end
	end

	return list
end

D.Commands.laser = function( ply, drone )
	if not drone then return end

	if drone:GetNW2Bool( "SkyOpsArty_Laser", false ) then
		D.SetLaser( drone, false )
		D.Notify( ply, "Подсветка выключена" )
	elseif D.SetLaser( drone, true ) then
		D.Notify( ply, "Подсветка включена" )
	else
		D.Notify( ply, "Нет точки: наведи камеру на землю" )
	end
end

-- Передача координат ----------------------------------------------------------

-- ошибка в метрах: в hardcore растёт с наклонной дальностью, в auto ноль
local function SendError( drone, pos )
	if Mode() == "auto" or not cvErr:GetBool() then return 0 end

	local cfg = D.Config( drone )
	local km = drone:GetPos():Distance( pos ) / D.UPM() / 1000

	return cfg.errBase + cfg.errPerKm * km
end

function D.SendTarget( drone, ply )
	local pos = D.LaserPos( drone ) or D.AimPoint( drone )

	if not pos then return false end

	local err = SendError( drone, pos )

	if err > 0 then
		local a = math.Rand( 0, math.pi * 2 )
		local r = math.Rand( 0, err ) * D.UPM()

		pos = pos + Vector( math.cos( a ) * r, math.sin( a ) * r, 0 )
	end

	net.Start( "skyops_arty_target" )
	-- три float, а не WriteVector: тот обрезает координаты дальше ±16384 u
	net.WriteFloat( pos.x )
	net.WriteFloat( pos.y )
	net.WriteFloat( pos.z )
	net.WriteFloat( err )
	net.WriteEntity( drone )
	net.Broadcast()

	hook.Run( "SkyOps.Arty.TargetSent", drone, pos, err, ply )

	return true
end

D.Commands.send = function( ply, drone )
	if not drone then return end

	if not D.SendTarget( drone, ply ) then D.Notify( ply, "Нет точки: наведи камеру на землю" ) end
end

