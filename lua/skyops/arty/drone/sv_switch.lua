-- Артиллерия, дрон: переключение САУ <-> дрон для одиночной игры и выход из дрона к пульту.
-- Стоковый пульт sw_uav_control сажает игрока прямо в кресло дрона, поэтому тело
-- игрока летает вместе с дроном. Здесь:
--  * запоминаем, в каком кресле САУ игрок сидел и каким дроном управлял;
--  * команда switch пересаживает из САУ в дрон и обратно в то же кресло САУ;
--  * при обычном выходе из дрона ставим игрока к его пульту, а не в небо.

local D = SkyOps.Arty.Drone

local SPG_CLASS = "sw_2s35"

local function Base( pod )
	if not IsValid( pod ) then return nil end
	if pod.lvsGetVehicle then
		local v = pod:lvsGetVehicle()

		if IsValid( v ) then return v end
	end

	local p = pod:GetParent()

	return IsValid( p ) and p or nil
end

hook.Add( "PlayerEnteredVehicle", "SkyOpsArty.Drone.Switch", function( ply, pod )
	local base = Base( pod )

	if not base then return end

	if base:GetClass() == SPG_CLASS then
		ply.SkyOpsArty_SPGPod = pod
		ply.SkyOpsArty_SPG = base
	elseif D.IsDrone( base ) then
		ply:SetNW2Entity( "SkyOpsArty_Drone", base )
	end
end )

-- место у пульта, куда ставим игрока после выхода из дрона
local function StationSpot( station )
	return station:LocalToWorld( Vector( -60, 0, 10 ) )
end

hook.Add( "PlayerLeaveVehicle", "SkyOpsArty.Drone.Switch", function( ply, pod )
	local base = Base( pod )

	if not D.IsDrone( base ) or ply.SkyOpsArty_Switching then return end

	local station = D.Station( base )

	if not station then return end

	-- LVS сам ищет место выхода в этот же кадр, поэтому переставляем следующим тиком
	timer.Simple( 0, function()
		if not IsValid( ply ) or not IsValid( station ) or ply:InVehicle() then return end

		ply:SetPos( StationSpot( station ) )
		ply:SetLocalVelocity( vector_origin )
	end )
end )

-- пересадить игрока в кресло (выход и вход в разные кадры, иначе Source теряет вход)
local function MoveTo( ply, pod, onDone )
	ply.SkyOpsArty_Switching = true

	if ply:InVehicle() then ply:ExitVehicle() end

	timer.Simple( 0, function()
		if not IsValid( ply ) then return end

		ply.SkyOpsArty_Switching = nil

		if not IsValid( pod ) or IsValid( pod:GetDriver() ) then return end

		ply:EnterVehicle( pod )

		if onDone then onDone() end
	end )
end

-- дрон для пересадки: последний свой, иначе ближайший свободный
local function PickDrone( ply )
	local d = D.GetLinked( ply )

	if d and not IsValid( d:GetDriver() ) and not d:GetAI() then return d end

	local best, bestD

	for _, drone in ipairs( D.All() ) do
		local dist = drone:GetPos():DistToSqr( ply:GetPos() )

		if not IsValid( drone:GetDriver() ) and not drone:GetAI() and ( not bestD or dist < bestD ) then
			best, bestD = drone, dist
		end
	end

	return best
end

function D.SwitchToDrone( ply )
	local drone = PickDrone( ply )

	if not drone then return false, "Нет свободного дрона" end

	local seat = drone:GetDriverSeat()

	if not IsValid( seat ) then return false, "У дрона нет кресла" end

	MoveTo( ply, seat, function()
		if IsValid( drone ) then drone:AlignView( ply ) end
	end )

	return true
end

function D.SwitchToSPG( ply )
	local pod = ply.SkyOpsArty_SPGPod

	if IsValid( pod ) and not IsValid( pod:GetDriver() ) then
		MoveTo( ply, pod )

		return true
	end

	-- кресло занято или пропало: садим в любое свободное место той же САУ
	local spg = ply.SkyOpsArty_SPG

	if not IsValid( spg ) then return false, "Сначала сядь в 2С35, чтобы она запомнилась" end

	ply.SkyOpsArty_Switching = true
	ply:ExitVehicle()

	timer.Simple( 0, function()
		if not IsValid( ply ) then return end

		ply.SkyOpsArty_Switching = nil

		if IsValid( spg ) then spg:SetPassenger( ply ) end
	end )

	return true
end

function D.Switch( ply )
	if D.GetControlled( ply ) then return D.SwitchToSPG( ply ) end

	return D.SwitchToDrone( ply )
end

D.Commands.switch = function( ply )
	local ok, err = D.Switch( ply )

	if not ok then D.Notify( ply, err ) end
end
