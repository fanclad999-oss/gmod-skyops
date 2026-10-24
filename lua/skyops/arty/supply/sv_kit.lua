-- Artillery supply: the KamAZ carries a drone kit (a catapult and drones). One press of
-- the kit key at the truck unloads a catapult behind it with a drone mounted and the
-- drone's control station at its side; the next press packs them back. A drone that is
-- not standing by the truck is recalled first: it flies home on the drone module's
-- loiter and is packed over the truck; a press during the return blows it up and packs
-- the catapult at once. A lost drone stays lost.
--
-- NW2 on the truck: SkyOpsArty_KitDrones (int) drones in the body,
--                   SkyOpsArty_KitOut (bool) the kit is unloaded,
--                   SkyOpsArty_KitRecall (bool) the drone is flying home
-- Command: skyops_arty_kit (the client sends it on the key, sh_supply S.KIT_RANGE)

local S = SkyOps.Arty.Supply
local Grid = SkyOps.Arty.Grid

local cvDrones = CreateConVar( "skyops_arty_kit_drones", "2", FCVAR_ARCHIVE, "Drones in a fresh supply truck", 0, 10 )
local cvClass = CreateConVar( "skyops_arty_kit_class", "sw_orlan10", FCVAR_ARCHIVE, "Drone the truck unloads (a catapult-launched one: sw_orlan10, sw_zala, sw_pchela1t)" )

local CATAPULT = "sw_uav_catapult"
local FALLBACK_DRONES = { "sw_orlan10", "sw_zala", "sw_pchela1t" }
local PACK_RANGE = 40 -- m from the truck to the drone and the catapult
local PACK_SPEED = 2 -- m/s: the drone is not flying
local RECALL_RANGE = 700 -- m, horizontal: a returning drone on its loiter circle (350-500 m) over the truck is packed
local COOLDOWN = 2

local function Tell( ply, msg )
	if IsValid( ply ) then ply:ChatPrint( "[КамАЗ] " .. msg ) end
end

local function IsTruck( ent )
	return S.IsCarrier( ent ) and ent:GetClass() ~= S.CRATE_CLASS
end

local function InitTruck( truck )
	if truck.SkyOpsArty_KitInit then return end

	truck.SkyOpsArty_KitInit = true
	truck:SetNW2Int( "SkyOpsArty_KitDrones", cvDrones:GetInt() )
	truck:SetNW2Bool( "SkyOpsArty_KitOut", false )
end

hook.Add( "OnEntityCreated", "SkyOps.Arty.Kit", function( ent )
	timer.Simple( 0, function()
		if IsTruck( ent ) then InitTruck( ent ) end
	end )
end )

for _, ent in ipairs( ents.GetAll() ) do
	if IsTruck( ent ) then InitTruck( ent ) end
end

local function DroneClass()
	local class = cvClass:GetString()

	if scripted_ents.GetStored( class ) then return class end

	for _, c in ipairs( FALLBACK_DRONES ) do
		if scripted_ents.GetStored( c ) then return c end
	end
end

-- a point on the ground next to the truck, local offset in units
local function Ground( truck, offset )
	local pos = truck:LocalToWorld( offset )
	local tr = util.TraceLine( {
		start = pos + Vector( 0, 0, 200 ),
		endpos = pos - Vector( 0, 0, 2000 ),
		filter = truck,
	} )

	return tr.Hit and tr.HitPos or pos
end

local function Own( ent, ply )
	if ent.CPPISetOwner then ent:CPPISetOwner( ply ) end
	if ent.SetCreator then ent:SetCreator( ply ) end
end

local function Unload( truck, ply )
	if not scripted_ents.GetStored( CATAPULT ) then return Tell( ply, "Нет катапульты sw_uav_catapult: нужен аддон дронов" ) end

	local mins, maxs = truck:OBBMins(), truck:OBBMaxs()
	local yaw = truck:GetAngles().y

	-- behind the truck, launching away from it
	local cat = ents.Create( CATAPULT )

	if not IsValid( cat ) then return Tell( ply, "Не удалось создать катапульту" ) end

	cat:SetPos( Ground( truck, Vector( mins.x - 250, 0, 0 ) ) + Vector( 0, 0, 10 ) )
	cat:SetAngles( Angle( 0, yaw + 180, 0 ) )
	cat:Spawn()
	cat:Activate()
	Own( cat, ply )

	local kit = { catapult = cat }
	local class = truck:GetNW2Int( "SkyOpsArty_KitDrones", 0 ) > 0 and DroneClass()

	if class then
		local drone = ents.Create( class )

		if IsValid( drone ) then
			drone:SetPos( cat:GetPos() + Vector( 0, 0, 80 ) )
			drone:SetAngles( cat:GetAngles() )
			drone:Spawn()
			drone:Activate()
			Own( drone, ply )

			kit.drone = drone
			ply:SetNW2Entity( "SkyOpsArty_Drone", drone ) -- switch (U) and quick deploy (I) take this drone
			truck:SetNW2Int( "SkyOpsArty_KitDrones", truck:GetNW2Int( "SkyOpsArty_KitDrones", 0 ) - 1 )

			-- mount on the catapult and put the control station at the truck's side
			timer.Simple( 0.2, function()
				if not IsValid( drone ) then return end

				if IsValid( cat ) and cat.Mount then cat:Mount( drone ) end

				local station = SkyOps.Arty.Drone and SkyOps.Arty.Drone.Station( drone ) or drone:GetNWEntity( "UAVControl" )

				if IsValid( truck ) and IsValid( station ) then
					station:SetPos( Ground( truck, Vector( 0, maxs.y + 120, 0 ) ) + Vector( 0, 0, 20 ) )
					station:SetAngles( Angle( 0, yaw - 90, 0 ) )
				end
			end )
		end
	end

	truck.SkyOpsArty_Kit = kit
	truck:SetNW2Bool( "SkyOpsArty_KitOut", true )

	if kit.drone then
		Tell( ply, string.format( "Катапульта и дрон выгружены за машиной, пульт сбоку. Дронов в кузове: %d", truck:GetNW2Int( "SkyOpsArty_KitDrones", 0 ) ) )
	else
		Tell( ply, "Катапульта выгружена. " .. ( truck:GetNW2Int( "SkyOpsArty_KitDrones", 0 ) > 0 and "Дрон не создан: нет аддона дрона" or "Дронов в кузове нет" ) )
	end
end

local function Near( a, b, m )
	return IsValid( a ) and IsValid( b ) and a:GetPos():Distance( b:GetPos() ) <= ( m or PACK_RANGE ) * Grid.UPM()
end

local function Drones( truck )
	return truck:GetNW2Int( "SkyOpsArty_KitDrones", 0 )
end

-- everything back into the body; a valid drone counts as returned
local function PackAll( truck, ply, note )
	local kit = truck.SkyOpsArty_Kit or {}
	local lost = kit.drone ~= nil and not IsValid( kit.drone )

	if IsValid( kit.drone ) then
		truck:SetNW2Int( "SkyOpsArty_KitDrones", Drones( truck ) + 1 )
		kit.drone:Remove() -- the drone removes its control station itself
	end

	if IsValid( kit.catapult ) then kit.catapult:Remove() end

	truck.SkyOpsArty_Kit = nil
	truck:SetNW2Bool( "SkyOpsArty_KitOut", false )
	truck:SetNW2Bool( "SkyOpsArty_KitRecall", false )
	Tell( ply, string.format( "%s. Дронов в кузове: %d", note or ( lost and "Катапульта убрана, дрон потерян" or "Убрано в кузов" ), Drones( truck ) ) )
end

-- self-destruct: the drone is lost, the catapult goes back
local function Destroy( truck, ply )
	local drone = truck.SkyOpsArty_Kit.drone

	if IsValid( drone ) and IsValid( drone:GetDriver() ) then
		return Tell( ply, "В дроне сидит игрок: сначала выйдите из него" )
	end

	if IsValid( drone ) then
		if drone.Explode then drone:Explode() end
		if IsValid( drone ) then drone:Remove() end
	end

	PackAll( truck, ply, "Дрон подорван, катапульта убрана" )
end

-- the drone flies home on the drone module's loiter, centred on the truck
local function Recall( truck, ply, drone )
	local D = SkyOps.Arty.Drone
	local ok = D and D.StartLoiter and D.StartLoiter( drone, truck:GetPos() )

	truck:SetNW2Bool( "SkyOpsArty_KitRecall", true )
	truck.SkyOpsArty_Kit.recallBy = ply

	if not ok then
		truck.SkyOpsArty_Kit.noLoiter = true -- nothing to follow: the next press blows it up

		return Tell( ply, "Дрон не может вернуться сам. Нажмите ещё раз, чтобы подорвать его и убрать катапульту" )
	end

	local km = drone:GetPos():Distance( truck:GetPos() ) / Grid.UPM() / 1000

	Tell( ply, string.format( "Дрон возвращается (%.1f км), уберётся в кузов над машиной. Нажмите ещё раз, чтобы подорвать его сразу", km ) )
end

local function Pack( truck, ply )
	local kit = truck.SkyOpsArty_Kit or {}
	local drone = kit.drone

	if not IsValid( drone ) or ( Near( drone, truck ) and drone:GetVelocity():Length() / Grid.UPM() <= PACK_SPEED and not IsValid( drone:GetDriver() ) ) then
		return PackAll( truck, ply )
	end

	if truck:GetNW2Bool( "SkyOpsArty_KitRecall", false ) then return Destroy( truck, ply ) end

	if IsValid( drone:GetDriver() ) and Near( drone, truck ) then
		return Tell( ply, "Из дрона нужно выйти" )
	end

	Recall( truck, ply, drone )
end

-- returning drones: follow the truck, pack when overhead, drop the recall on manual control
timer.Create( "SkyOps.Arty.KitRecall", 1, 0, function()
	local D = SkyOps.Arty.Drone

	for _, truck in ipairs( ents.GetAll() ) do
		local kit = truck.SkyOpsArty_Kit

		if kit and truck:GetNW2Bool( "SkyOpsArty_KitRecall", false ) then
			local drone = kit.drone

			if not IsValid( drone ) then
				truck:SetNW2Bool( "SkyOpsArty_KitRecall", false )
				Tell( kit.recallBy, "Дрон потерян по дороге" )
			elseif drone:GetPos():Distance2D( truck:GetPos() ) <= RECALL_RANGE * Grid.UPM() and not IsValid( drone:GetDriver() ) then
				PackAll( truck, kit.recallBy, "Дрон вернулся и убран в кузов вместе с катапультой" )
			elseif not kit.noLoiter and D and D.IsLoitering and D.SetNWPos then
				if D.IsLoitering( drone ) then
					D.SetNWPos( drone, "SkyOpsArty_LoiterCenter", truck:GetPos() )
				else
					truck:SetNW2Bool( "SkyOpsArty_KitRecall", false )
					Tell( kit.recallBy, "Возврат дрона отменён: ручное управление" )
				end
			end
		end
	end
end )

-- the truck the player sits in, or the nearest one on foot within S.KIT_RANGE
function S.KitTruck( ply )
	local veh = ply.lvsGetVehicle and ply:lvsGetVehicle()

	if IsTruck( veh ) then return veh end
	if IsValid( veh ) or ply:InVehicle() then return nil end

	local best, bestD = nil, S.KIT_RANGE * Grid.UPM()

	for _, ent in ipairs( ents.GetAll() ) do
		if IsTruck( ent ) then
			local d = ent:GetPos():Distance( ply:GetPos() )

			if d < bestD then best, bestD = ent, d end
		end
	end

	return best
end

concommand.Add( "skyops_arty_kit", function( ply )
	if not IsValid( ply ) or ( ply.SkyOpsArty_NextKit or 0 ) > CurTime() then return end

	ply.SkyOpsArty_NextKit = CurTime() + COOLDOWN

	local truck = S.KitTruck( ply )

	if not truck then return Tell( ply, "Подойдите к КамАЗу снабжения" ) end
	if truck.GetHP and truck:GetHP() <= 0 then return Tell( ply, "Машина уничтожена" ) end

	InitTruck( truck )

	if truck:GetNW2Bool( "SkyOpsArty_KitOut", false ) then
		Pack( truck, ply )
	else
		Unload( truck, ply )
	end
end )
