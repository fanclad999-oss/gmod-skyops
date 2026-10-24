-- Home airfield built from PHX plates: one runway, an apron and a hangar.
-- Its spot is saved per map in data/skyops/airfield_<map>.json and rebuilt on
-- every map load. It registers the anchors "airfield_main" (runway threshold,
-- facing down the runway) and "airfield_apron" (next to the hangar).
--
--   skyops_airfield_here   build at your position, runway along your view
--   skyops_airfield_death  build where you last died (e.g. after "kill")
--   skyops_airfield_remove remove it and forget the spot

SkyOps.Airfield = SkyOps.Airfield or {}

local Airfield = SkyOps.Airfield

local RUNWAY_M = 2400
local PLATE = "models/hunter/plates/plate32x32.mdl"
local WALL = "models/hunter/plates/plate8x32.mdl"
local PLATE_U = 32 * 47.45   -- PHX plate grid unit
local WALL_U = 8 * 47.45

-- layout from origin (threshold, ground level) and yaw; shared so the client
-- can place the anchors from the two networked values
function Airfield.Layout( origin, yaw )
	local ang = Angle( 0, yaw, 0 )
	local fwd, right = ang:Forward(), ang:Right()
	return {
		runwayStart = origin + fwd * PLATE_U * 0.5,
		apron = origin + right * PLATE_U * 1.5 + fwd * PLATE_U * 1.5,
		ang = ang,
	}
end

local function RegisterAnchors( origin, yaw, top )
	local l = Airfield.Layout( Vector( origin.x, origin.y, top ), yaw )
	local up = Vector( 0, 0, 80 )
	SkyOps.Map.Register( "airfield_main", { pos = l.runwayStart + up, ang = Angle( 0, yaw, 0 ) } )
	SkyOps.Map.Register( "airfield_apron", { pos = l.apron + up, ang = Angle( 0, yaw, 0 ) } )
	Airfield.origin, Airfield.yaw, Airfield.top = origin, yaw, top
end

if CLIENT then
	timer.Create( "SkyOps.AirfieldAnchors", 2, 0, function()
		local yaw = GetGlobalFloat( "SkyOps.AirfieldYaw", -1000 )
		if yaw == -1000 then return end
		local o = GetGlobalVector( "SkyOps.AirfieldOrigin" )
		if Airfield.origin == o and Airfield.yaw == yaw then return end
		RegisterAnchors( o, yaw, GetGlobalFloat( "SkyOps.AirfieldTop" ) )
	end )
	return
end

local function SaveFile()
	return "skyops/airfield_" .. game.GetMap():lower() .. ".json"
end

local function Ground( x, y )
	return SkyOps.Map.GroundZ( x, y, 0 ) or 0
end

local function Clear()
	for _, e in ipairs( Airfield.props or {} ) do
		if IsValid( e ) then e:Remove() end
	end
	Airfield.props = {}
end

local function Prop( model, pos, ang, mat, col )
	local e = ents.Create( "prop_physics" )
	if not IsValid( e ) then return NULL end
	e:SetModel( model )
	e:SetPos( pos )
	e:SetAngles( ang )
	e:Spawn()
	e:SetMaterial( mat or "phoenix_storms/concrete0" )
	if col then e:SetColor( col ) end
	local phys = e:GetPhysicsObject()
	if IsValid( phys ) then phys:EnableMotion( false ) end
	e.SkyOpsAirfield = true
	e.PhysgunDisabled = true
	e.m_tblToolsAllowed = {}
	Airfield.props[ #Airfield.props + 1 ] = e
	return e
end

-- a wall plate standing on its long edge along dir
local function Wall( base, dir, height )
	local yaw = dir:Angle().y
	local e = Prop( WALL, base + Vector( 0, 0, height * 0.5 ), Angle( 0, yaw, 90 ), "phoenix_storms/metalset_1-2", Color( 150, 160, 150 ) )
	if not IsValid( e ) then return end
	-- plate8x32: its long side may lie on x or y; turn it so the long side runs along dir
	local size = e:OBBMaxs() - e:OBBMins()
	-- long side on y: point y along dir, pitch the short x side up
	if size.y > size.x then e:SetAngles( Angle( 90, yaw - 90, 0 ) ) end
end

function Airfield.Build( origin, yaw )
	Clear()

	local M = SkyOps.M_TO_HU
	local ang = Angle( 0, yaw, 0 )
	local fwd, right = ang:Forward(), ang:Right()
	local count = math.ceil( RUNWAY_M * M / PLATE_U )

	-- flat strip: highest terrain point under runway and apron plus 0.5 m
	local lo, hi = math.huge, -math.huge
	local function Sample( p )
		for _, o in ipairs( { Vector(), right * PLATE_U * 0.5, -right * PLATE_U * 0.5 } ) do
			local z = Ground( p.x + o.x, p.y + o.y )
			lo, hi = math.min( lo, z ), math.max( hi, z )
		end
	end
	for i = 0, count do Sample( origin + fwd * PLATE_U * i ) end
	for k = 0, 3 do Sample( origin + right * PLATE_U * 1.5 + fwd * PLATE_U * k ) end
	local top = hi + 0.5 * M

	local concrete = Color( 170, 170, 165 )
	for i = 1, count do
		Prop( PLATE, Vector( 0, 0, top ) + ( origin + fwd * PLATE_U * ( i - 0.5 ) ) * Vector( 1, 1, 0 ), ang, nil, concrete )
	end
	-- apron: 2 x 3 plates on the right of the threshold
	for j = 1, 2 do
		for k = 1, 3 do
			local p = origin + right * PLATE_U * j + fwd * PLATE_U * ( k - 0.5 )
			Prop( PLATE, Vector( p.x, p.y, top ), ang, nil, Color( 150, 150, 145 ) )
		end
	end
	-- hangar on the far apron row: side walls along the runway, back wall, roof
	local hc = origin + right * PLATE_U * 2 + fwd * PLATE_U * 1.5
	hc.z = top
	local half = PLATE_U * 0.5
	Wall( hc + right * half, fwd, WALL_U )
	Wall( hc + fwd * half, right, WALL_U )
	Wall( hc - fwd * half, right, WALL_U )
	Prop( PLATE, hc + Vector( 0, 0, WALL_U ), ang, "phoenix_storms/metalset_1-2", Color( 120, 130, 120 ) )

	RegisterAnchors( origin, yaw, top )
	SetGlobalVector( "SkyOps.AirfieldOrigin", origin )
	SetGlobalFloat( "SkyOps.AirfieldYaw", yaw )
	SetGlobalFloat( "SkyOps.AirfieldTop", top )

	hook.Run( "SkyOps.AirfieldBuilt", origin, yaw, top )
	return #Airfield.props, ( hi - lo ) * SkyOps.HU_TO_M
end

local function Save( origin, yaw )
	file.CreateDir( "skyops" )
	file.Write( SaveFile(), util.TableToJSON( { x = origin.x, y = origin.y, z = origin.z, yaw = yaw } ) )
end

local function Load()
	local t = util.JSONToTable( file.Read( SaveFile(), "DATA" ) or "" )
	if not t then return end
	Airfield.Build( Vector( t.x, t.y, t.z ), t.yaw )
end

-- props spawned during InitPostEntity can miss InfMap chunk setup; wait a bit
hook.Add( "InitPostEntity", "SkyOps.Airfield", function() timer.Simple( 3, Load ) end )
hook.Add( "PostCleanupMap", "SkyOps.Airfield", function() timer.Simple( 1, Load ) end )

-- players spawn on the apron instead of wherever the map puts them
hook.Add( "PlayerSpawn", "SkyOps.Airfield", function( ply )
	if not Airfield.origin then return end
	timer.Simple( 0, function()
		if not IsValid( ply ) then return end
		local a = SkyOps.Map.Anchors[ "airfield_apron" ]
		if a then ply:SetPos( a.pos + VectorRand( -200, 200 ) * Vector( 1, 1, 0 ) ) end
	end )
end )

Airfield.lastDeath = Airfield.lastDeath or {}
hook.Add( "PlayerDeath", "SkyOps.Airfield", function( ply )
	Airfield.lastDeath[ ply ] = { pos = ply:GetPos(), yaw = ply:EyeAngles().y }
end )

local function CanEdit( ply )
	return not IsValid( ply ) or ply:IsAdmin() or game.SinglePlayer()
end

local function BuildAt( ply, pos, yaw )
	pos = Vector( pos.x, pos.y, Ground( pos.x, pos.y ) )
	local n, spread = Airfield.Build( pos, yaw )
	Save( pos, yaw )
	if IsValid( ply ) then
		ply:ChatPrint( string.format( "Аэродром построен: %d пропов, полоса %d м. Перепад рельефа под ним %d м.", n, RUNWAY_M, math.Round( spread ) ) )
		if spread > 25 then ply:ChatPrint( "Рельеф тут неровный, полоса местами висит над землёй. Можно перенести: skyops_airfield_here в другом месте." ) end
	end
end

concommand.Add( "skyops_airfield_here", function( ply )
	if not ( IsValid( ply ) and CanEdit( ply ) ) then return end
	BuildAt( ply, ply:GetPos(), math.Round( ply:EyeAngles().y ) )
end )

concommand.Add( "skyops_airfield_death", function( ply )
	if not ( IsValid( ply ) and CanEdit( ply ) ) then return end
	local d = Airfield.lastDeath[ ply ]
	if not d then ply:ChatPrint( "Нет записи о смерти в этой сессии: введи kill на нужном месте и повтори." ) return end
	BuildAt( ply, d.pos, math.Round( d.yaw ) )
end )

concommand.Add( "skyops_airfield_remove", function( ply )
	if not CanEdit( ply ) then return end
	Clear()
	file.Delete( SaveFile() )
	Airfield.origin = nil
	SetGlobalFloat( "SkyOps.AirfieldYaw", -1000 )
end )
