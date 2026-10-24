-- Artillery supply: the KamAZ carries a drone kit (a catapult and drones). One press of
-- the kit key at the truck unloads a catapult behind it with a drone mounted and the
-- drone's control station at its side; the next press packs them back, if the drone
-- is back on the ground or the catapult next to the truck. A lost drone stays lost.
--
-- NW2 on the truck: SkyOpsArty_KitDrones (int) drones in the body,
--                   SkyOpsArty_KitOut (bool) the kit is unloaded
-- Command: skyops_arty_kit (the client sends it on the key, sh_supply S.KIT_RANGE)

local S = SkyOps.Arty.Supply
local Grid = SkyOps.Arty.Grid

local cvDrones = CreateConVar( "skyops_arty_kit_drones", "2", FCVAR_ARCHIVE, "Drones in a fresh supply truck", 0, 10 )
local cvClass = CreateConVar( "skyops_arty_kit_class", "sw_orlan10", FCVAR_ARCHIVE, "Drone the truck unloads (a catapult-launched one: sw_orlan10, sw_zala, sw_pchela1t)" )

local CATAPULT = "sw_uav_catapult"
local FALLBACK_DRONES = { "sw_orlan10", "sw_zala", "sw_pchela1t" }
local PACK_RANGE = 40 -- m from the truck to the drone and the catapult
local PACK_SPEED = 2 -- m/s: the drone is not flying
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

local function Near( a, b )
	return IsValid( a ) and IsValid( b ) and a:GetPos():Distance( b:GetPos() ) <= PACK_RANGE * Grid.UPM()
end

local function Pack( truck, ply )
	local kit = truck.SkyOpsArty_Kit or {}
	local drone, cat = kit.drone, kit.catapult

	if IsValid( drone ) then
		if not Near( drone, truck ) or IsValid( drone:GetDriver() ) or drone:GetVelocity():Length() / Grid.UPM() > PACK_SPEED then
			return Tell( ply, string.format( "Дрон не у машины: посадите его не дальше %d м от КамАЗа и выйдите из пульта", PACK_RANGE ) )
		end
	end

	if IsValid( cat ) and not Near( cat, truck ) then
		return Tell( ply, string.format( "Катапульта дальше %d м от КамАЗа", PACK_RANGE ) )
	end

	local lost = kit.drone ~= nil and not IsValid( drone )

	if IsValid( drone ) then
		truck:SetNW2Int( "SkyOpsArty_KitDrones", truck:GetNW2Int( "SkyOpsArty_KitDrones", 0 ) + 1 )
		drone:Remove() -- the drone removes its control station itself
	end

	if IsValid( cat ) then cat:Remove() end

	truck.SkyOpsArty_Kit = nil
	truck:SetNW2Bool( "SkyOpsArty_KitOut", false )
	Tell( ply, string.format( "Убрано в кузов%s. Дронов в кузове: %d", lost and " (дрон потерян)" or "", truck:GetNW2Int( "SkyOpsArty_KitDrones", 0 ) ) )
end

-- the truck the player sits in, or the nearest one on foot within S.KIT_RANGE
function S.KitTruck( ply )
	local veh = ply.lvsGetVehicle and ply:lvsGetVehicle()

	if IsTruck( veh ) then return veh end
	if IsValid( veh ) or ply:InVehicle() then return nil end

	local best, bestD = nil, S.KIT_RANGE * Grid.UPM()

	for _, ent in ipairs( ents.GetAll() ) do
		if IsTruck( ent ) and SkyOps.Teams.Friendly( ply, ent ) then
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
