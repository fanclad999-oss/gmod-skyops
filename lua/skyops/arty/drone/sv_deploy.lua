-- Артиллерия, дрон: «быстрый вылет». Команда deploy ставит дрон игрока в воздух примерно
-- в километре от района цели и направляет носом на неё, чтобы не лететь туда минутами.
-- Если дрона нет, создаёт новый (класс из skyops_arty_drone_class), пульт ставит рядом
-- с игроком и сажает игрока в дрон.
--
-- Точка: сначала hook.Run( "SkyOps.Arty.DroneDeployPoint", ply ) (модуль заданий
-- отдаёт район цели текущего задания), иначе цель с планшета игрока (клиент
-- присылает её вместе с командой). Все позиции абсолютные (InfMap: как GetPos() на сервере).

local D = SkyOps.Arty.Drone

local cvEnable = CreateConVar( "skyops_arty_drone_deploy", "1", FCVAR_ARCHIVE, "1 = разрешить быстрый вылет дрона к цели (команда deploy)" )
local cvDist = CreateConVar( "skyops_arty_drone_deploy_dist", "1000", FCVAR_ARCHIVE, "Быстрый вылет: на каком удалении от цели появляется дрон, м" )
local cvAlt = CreateConVar( "skyops_arty_drone_deploy_alt", "300", FCVAR_ARCHIVE, "Быстрый вылет: высота над целью, м" )
local cvClass = CreateConVar( "skyops_arty_drone_class", "sw_orlan10", FCVAR_ARCHIVE, "Какой дрон создаёт быстрый вылет, если своего нет" )

local COOLDOWN = 5 -- с между вылетами одного игрока
local SPEED = 0.6 -- доля MaxPerfVelocity, с которой дрон появляется

-- откуда заходить: со стороны своей САУ (дрон между ОП и целью), иначе со стороны игрока
local function ApproachDir( ply, target )
	local from = IsValid( ply.SkyOpsArty_SPG ) and ply.SkyOpsArty_SPG:GetPos() or ply:GetPos()
	local d = Vector( from.x - target.x, from.y - target.y, 0 )

	if d:LengthSqr() < 1 then d = Vector( 1, 0, 0 ) end

	d:Normalize()

	return d
end

local function Place( drone, pos, ang )
	-- дрон может стоять на катапульте (приварен): отцепляем, иначе потащит её за собой
	constraint.RemoveConstraints( drone, "Weld" )

	drone:SetPos( pos )
	drone:SetAngles( ang )

	local phys = drone:GetPhysicsObject()

	if IsValid( phys ) then
		phys:Wake()
		phys:SetVelocity( ang:Forward() * ( drone.MaxPerfVelocity or 600 ) * SPEED )
		phys:SetAngleVelocity( vector_origin )
	end

	if drone.StartEngine then drone:StartEngine() end
	if drone.SetThrottle then drone:SetThrottle( 1 ) end
	if drone.RaiseLandingGear then drone:RaiseLandingGear() end
end

local function SpawnDrone( ply, pos, ang )
	local class = cvClass:GetString()

	if not D.Types[ class ] or not scripted_ents.GetStored( class ) then class = "sw_orlan10" end
	if not scripted_ents.GetStored( class ) then return nil, "Дрон " .. class .. " не установлен" end

	local drone = ents.Create( class )

	if not IsValid( drone ) then return nil, "Не удалось создать дрон" end

	drone:SetPos( pos )
	drone:SetAngles( ang )
	drone:Spawn()
	drone:Activate()

	if drone.CPPISetOwner then drone:CPPISetOwner( ply ) end
	if drone.SetCreator then drone:SetCreator( ply ) end

	undo.Create( "SkyOps drone" )
	undo.AddEntity( drone )
	undo.SetPlayer( ply )
	undo.Finish()

	-- дрон создаёт пульт рядом с собой, то есть в воздухе: переносим пульт к игроку
	timer.Simple( 0, function()
		if not IsValid( drone ) or not IsValid( ply ) then return end

		local station = D.Station( drone )

		if station then
			local fwd = ply:GetForward()

			fwd.z = 0
			station:SetPos( ply:GetPos() + fwd:GetNormalized() * 120 + Vector( 0, 0, 20 ) )
			station:SetAngles( Angle( 0, ply:EyeAngles().y + 180, 0 ) )
		end
	end )

	return drone
end

function D.Deploy( ply, target )
	if not cvEnable:GetBool() then return false, "Быстрый вылет выключен (skyops_arty_drone_deploy 0)" end
	if ( ply.SkyOpsArty_NextDeploy or 0 ) > CurTime() then return false, "Подожди пару секунд" end

	local hooked = hook.Run( "SkyOps.Arty.DroneDeployPoint", ply )

	if isvector( hooked ) then target = hooked end
	if not target then return false, "Нет цели: возьми задание или отметь цель на планшете" end

	local upm = D.UPM()
	local dir = ApproachDir( ply, target )
	local pos = target + dir * cvDist:GetFloat() * upm

	pos.z = target.z + cvAlt:GetFloat() * upm

	local ang = ( target - pos ):Angle()

	ang.p, ang.r = 0, 0

	local drone = D.GetControlled( ply ) or D.GetLinked( ply )

	if drone and IsValid( drone:GetDriver() ) and drone:GetDriver() ~= ply then drone = nil end

	if not drone then
		local err

		drone, err = SpawnDrone( ply, pos, ang )

		if not drone then return false, err end
	end

	ply.SkyOpsArty_NextDeploy = CurTime() + COOLDOWN

	if D.IsLoitering( drone ) then D.StopLoiter( drone ) end

	Place( drone, pos, ang )

	-- игрок не в этом дроне: пересаживаем (кресло САУ запоминает sv_switch)
	if D.GetControlled( ply ) ~= drone then
		local seat = drone:GetDriverSeat()

		if IsValid( seat ) then
			D.MoveTo( ply, seat, function()
				if IsValid( drone ) then drone:AlignView( ply ) end
			end )
		end
	end

	return true
end

D.Commands.deploy = function( ply )
	local target

	-- клиент шлёт цель с планшета после имени команды (в sh_drones)
	if net.ReadBool() then
		target = Vector( net.ReadFloat(), net.ReadFloat(), net.ReadFloat() )
	end

	local ok, err = D.Deploy( ply, target )

	D.Notify( ply, ok and "Дрон в воздухе, цель прямо по курсу" or err )
end
