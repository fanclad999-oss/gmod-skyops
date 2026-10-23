-- Step 0: does LVS + SW Bombs survive InfMap chunk transitions?
-- Commands (admin only):
--   skyops_test_chase [role] [distance]   SkyOps AI jet spawned behind you, chases you
--   skyops_test_sam [system] [distance]   SAM site on the ground ahead of you
--   skyops_test_jet [role] [loadout]       your jet in front of you with a loadout (34 = Kh-31P on su34)
--   skyops_test_status                    prints every tracked object
--   skyops_test_clear                     removes everything the test spawned
-- Every chunk change, missile launch and missile end is printed to the server
-- console and also written to data/skyops/compat_log.txt.

local Tracked = {}  -- ent -> { label, chunk, lastPos, spawned }
local Spawned = {}
local LogLines = {}

local function ChunkOf( ent )
	return ent.CHUNK_OFFSET and Vector( ent.CHUNK_OFFSET ) or Vector( 0, 0, 0 )
end

local function Log( fmt, ... )
	local line = string.format( "[%7.1f] " .. fmt, CurTime(), ... )
	print( "[SkyOps test] " .. line )
	LogLines[ #LogLines + 1 ] = line
end

local function SaveLog()
	file.CreateDir( "skyops" )
	file.Write( "skyops/compat_log.txt", table.concat( LogLines, "\n" ) )
end

local function Track( ent, label )
	if not IsValid( ent ) then return end
	Tracked[ ent ] = { label = label, chunk = ChunkOf( ent ), lastPos = ent:GetPos() }
	Log( "track %s %s at %s chunk %s", label, ent:GetClass(), tostring( ent:GetPos() ), tostring( ChunkOf( ent ) ) )
end

local function IsAdmin( ply )
	return not IsValid( ply ) or ply:IsAdmin()
end

local function PlayerJet( ply )
	local veh = isfunction( ply.lvsGetVehicle ) and ply:lvsGetVehicle() or NULL
	return veh
end

local function GroundAt( pos )
	local tr = util.TraceLine( {
		start = Vector( pos.x, pos.y, pos.z + 20000 ),
		endpos = Vector( pos.x, pos.y, pos.z - 200000 ),
		-- InfMap terrain is made of infmap_* collider entities, not brushes
		filter = function( e ) return e:IsWorld() or string.StartWith( e:GetClass(), "infmap_" ) end,
	} )
	return tr.Hit and tr.HitPos or pos
end

concommand.Add( "skyops_test_chase", function( ply, _, args )
	if not IsAdmin( ply ) then return end

	local jet = PlayerJet( ply )
	if not IsValid( jet ) then ply:ChatPrint( "Сядь в самолёт LVS" ) return end

	local data = SkyOps.Registry.GetAircraft( args[1] or "su34" )
	if not data then ply:ChatPrint( "Неизвестная роль" ) return end

	local dist = tonumber( args[2] ) or 8000
	local pos = jet:GetPos() - jet:GetForward() * dist + Vector( 0, 0, 500 )

	local enemy = SkyOps.Spawn.AIFlight( args[1] or "su34", 1, pos, {}, { ang = jet:GetAngles() } )[1]
	if not IsValid( enemy ) then return end

	if isfunction( jet.SetAITEAM ) then jet:SetAITEAM( SkyOps.Teams.BLUE ) end

	Spawned[ #Spawned + 1 ] = enemy
	Track( jet, "player" )
	Track( enemy, "chaser" )
end )

concommand.Add( "skyops_test_sam", function( ply, _, args )
	if not IsAdmin( ply ) then return end

	local jet = PlayerJet( ply )
	local origin = IsValid( jet ) and jet or ply

	local system = args[1] or "osa"
	local dist = tonumber( args[2] ) or 30000
	local fwd = origin:GetForward()
	fwd.z = 0
	fwd:Normalize()

	local pos = GroundAt( origin:GetPos() + fwd * dist ) + Vector( 0, 0, 50 )
	local site = SkyOps.Spawn.AirDefense( system, pos, { ang = Angle( 0, origin:GetAngles().y + 180, 0 ) } )
	if not IsValid( site ) then ply:ChatPrint( "Не удалось создать " .. system ) return end

	Spawned[ #Spawned + 1 ] = site
	if IsValid( jet ) then
		if isfunction( jet.SetAITEAM ) then jet:SetAITEAM( SkyOps.Teams.BLUE ) end
		Track( jet, "player" )
	end
	Track( site, "sam_" .. system )
	ply:ChatPrint( "ПВО " .. system .. " создано в " .. math.Round( dist * 0.01905 ) .. " м впереди. Сядь в него сам или подлетай." )
end )

concommand.Add( "skyops_test_jet", function( ply, _, args )
	if not IsAdmin( ply ) or not IsValid( ply ) then return end

	local role = args[1] or "su34"
	local pos = ply:GetPos() + ply:GetForward() * 800 + Vector( 0, 0, 100 )
	local jet = SkyOps.Spawn.PlayerJet( role, pos, Angle( 0, ply:EyeAngles().y, 0 ), tonumber( args[2] ) )
	if not IsValid( jet ) then ply:ChatPrint( "Не удалось создать " .. role ) return end

	Spawned[ #Spawned + 1 ] = jet
	Track( jet, "player_" .. role )
end )

concommand.Add( "skyops_test_status", function( ply )
	if not IsAdmin( ply ) then return end
	for ent, t in pairs( Tracked ) do
		if IsValid( ent ) then
			Log( "%s pos %s chunk %s speed %d ai %s", t.label, tostring( ent:GetPos() ), tostring( ChunkOf( ent ) ),
				ent:GetVelocity():Length(), tostring( isfunction( ent.GetAI ) and ent:GetAI() ) )
		end
	end
	SaveLog()
end )

concommand.Add( "skyops_test_clear", function( ply )
	if not IsAdmin( ply ) then return end
	for _, ent in ipairs( Spawned ) do
		if IsValid( ent ) then ent:Remove() end
	end
	Spawned = {}
	Tracked = {}
	SaveLog()
end )

-- missiles: SW Bombs rockets and LVS missiles
hook.Add( "OnEntityCreated", "SkyOps.CompatTest", function( ent )
	local class = ent:GetClass()
	if not ( string.StartWith( class, "sw_base_rocket" ) or string.StartWith( class, "sw_rocket" ) or class == "lvs_missile" ) then return end

	timer.Simple( 0.1, function()
		if not IsValid( ent ) then return end
		local target = ent.target or ( isfunction( ent.GetTarget ) and ent:GetTarget() ) or NULL
		Track( ent, "missile->" .. ( IsValid( target ) and target:GetClass() or "none" ) )
		Tracked[ ent ].target = target
	end )
end )

hook.Add( "EntityRemoved", "SkyOps.CompatTest", function( ent )
	local t = Tracked[ ent ]
	if not t then return end

	if IsValid( t.target ) then
		Log( "%s ended %d u from target (target chunk %s, missile chunk %s)", t.label,
			t.lastPos:Distance( t.target:GetPos() ), tostring( ChunkOf( t.target ) ), tostring( t.chunk ) )
	else
		Log( "%s removed at %s", t.label, tostring( t.lastPos ) )
	end
	Tracked[ ent ] = nil
	SaveLog()
end )

-- chunk transitions and sanity checks, 4 times a second
timer.Create( "SkyOps.CompatTest", 0.25, 0, function()
	for ent, t in pairs( Tracked ) do
		if not IsValid( ent ) then Tracked[ ent ] = nil continue end

		local pos = ent:GetPos()
		local chunk = ChunkOf( ent )

		if chunk ~= t.chunk then
			local jump = pos:Distance( t.lastPos )
			Log( "%s chunk %s -> %s, jump %d u, speed %d", t.label, tostring( t.chunk ), tostring( chunk ), jump, ent:GetVelocity():Length() )
			-- at 4 Hz even Mach 2 is under ~4000 u per sample; more means a teleport glitch
			if jump > 5000 then Log( "!! %s teleported by %d u on chunk change", t.label, jump ) end
			t.chunk = chunk
		end

		if pos.x ~= pos.x or pos.z ~= pos.z then
			Log( "!! %s has NaN position", t.label )
		end

		t.lastPos = pos
	end
end )
