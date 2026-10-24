-- Artillery step 0: how do the 2S35 shells and the SW UAVs behave on InfMap?
-- Commands (admin only):
--   skyops_arty_dump     copies the Lua of SW Bombs bombs/UAV control/catapult to data/skyops/dump/
--   skyops_arty_status   prints 2S35 turret state and every UAV's camera tracking point
--   skyops_arty_clear    clears the log
-- Every shell fired by a 2S35 is followed automatically: launch, chunk changes,
-- apex, guidance, end. Everything goes to the console and data/skyops/arty_probe.txt.

local SPG_CLASS = "sw_2s35"
local SHELL_CLASS = "sw_bomb_fab100_v3"
local UAV_CLASSES = { sw_zala = true, sw_orlan10 = true, sw_pchela1t = true, sw_ravenseye = true }

local LogLines = {}

local function UnitsPerMeter()
	return ( KIR and KIR.S ) or 52.49
end

local function M( units )
	return units / UnitsPerMeter()
end

local function ChunkOf( ent )
	return ent.CHUNK_OFFSET and Vector( ent.CHUNK_OFFSET ) or Vector( 0, 0, 0 )
end

local function Log( fmt, ... )
	local line = string.format( "[%7.1f] " .. fmt, CurTime(), ... )
	print( "[Arty probe] " .. line )
	LogLines[ #LogLines + 1 ] = line
end

local function SaveLog()
	file.CreateDir( "skyops" )
	file.Write( "skyops/arty_probe.txt", table.concat( LogLines, "\n" ) )
end

local function IsAdmin( ply )
	return not IsValid( ply ) or ply:IsAdmin()
end

local function V( v )
	return string.format( "(%.0f %.0f %.0f)", v.x, v.y, v.z )
end

-- shell tracking -------------------------------------------------------------

local Shells = {} -- ent -> state

local function NearestSPG( pos )
	local best, bestDist
	for _, spg in ipairs( ents.FindByClass( SPG_CLASS ) ) do
		local d = spg:GetPos():DistToSqr( pos )
		if not bestDist or d < bestDist then best, bestDist = spg, d end
	end
	return best, bestDist and math.sqrt( bestDist ) or nil
end

local function StartShell( shell )
	if not IsValid( shell ) then return end

	local spg, dist = NearestSPG( shell:GetPos() )
	if not IsValid( spg ) or dist > 2000 then return end

	local muzzle = spg:GetAttachment( spg:LookupAttachment( "muzzle" ) )
	local ang = muzzle and muzzle.Ang or shell:GetAngles()
	local phys = shell:GetPhysicsObject()
	local vel = IsValid( phys ) and phys:GetVelocity() or Vector()

	Shells[ shell ] = {
		start = shell:GetPos(),
		chunk = ChunkOf( shell ),
		t0 = CurTime(),
		apex = shell:GetPos().z,
		lastPos = shell:GetPos(),
		lastVel = vel,
		guided = shell.HaveGuidance == true,
	}

	Log( "SHOT from %s shell type %s guided %s | barrel pitch %.1f yaw %.1f | pose pitch %.1f yaw %.1f | v0 %.0f u/s (%.0f m/s) | pos %s chunk %s",
		tostring( spg ), tostring( spg.GetShellType and spg:GetShellType() ), tostring( shell.HaveGuidance ),
		-ang.p, ang.y, spg:GetPoseParameter( "pitch" ), spg:GetPoseParameter( "yaw" ),
		vel:Length(), M( vel:Length() ), V( shell:GetPos() ), tostring( ChunkOf( shell ) ) )

	-- note every field SW Bombs set on the shell, to see what guidance reads
	local keys = {}
	for k, v in pairs( shell:GetTable() ) do
		if not isfunction( v ) and not istable( v ) then keys[ #keys + 1 ] = k .. "=" .. tostring( v ) end
	end
	table.sort( keys )
	Log( "  shell fields: %s", table.concat( keys, ", " ) )
end

hook.Add( "OnEntityCreated", "SkyOps.ArtyProbe", function( ent )
	if not IsValid( ent ) or ent:GetClass() ~= SHELL_CLASS then return end
	-- the 2S35 sets position and velocity right after Spawn(), so look one tick later
	timer.Simple( 0, function() StartShell( ent ) end )
end )

local NextThink = 0
hook.Add( "Think", "SkyOps.ArtyProbe", function()
	if CurTime() < NextThink then return end
	NextThink = CurTime() + 0.1

	for shell, s in pairs( Shells ) do
		if not IsValid( shell ) then
			local flat = Vector( s.lastPos.x - s.start.x, s.lastPos.y - s.start.y, 0 ):Length()
			Log( "  END after %.1f s | range %.0f m | height diff %.0f m | apex %.0f m above start | last %s | last speed %.0f m/s",
				CurTime() - s.t0, M( flat ), M( s.lastPos.z - s.start.z ), M( s.apex - s.start.z ), V( s.lastPos ), M( s.lastVel:Length() ) )
			Shells[ shell ] = nil
			SaveLog()
		else
			local pos = shell:GetPos()
			local phys = shell:GetPhysicsObject()
			local vel = IsValid( phys ) and phys:GetVelocity() or Vector()

			if pos.z > s.apex then s.apex = pos.z end

			local chunk = ChunkOf( shell )
			if chunk ~= s.chunk then
				Log( "  chunk %s -> %s at %.1f s", tostring( s.chunk ), tostring( chunk ), CurTime() - s.t0 )
				s.chunk = chunk
			end

			-- a guided shell turning shows up as the velocity direction changing faster than gravity alone would
			if s.guided and s.lastVel:LengthSqr() > 1 and vel:LengthSqr() > 1 then
				local turn = math.deg( math.acos( math.Clamp( s.lastVel:GetNormalized():Dot( vel:GetNormalized() ), -1, 1 ) ) )
				if turn > 3 then
					Log( "  turn %.1f deg in 0.1 s at %.1f s, pos %s", turn, CurTime() - s.t0, V( pos ) )
				end
			end

			s.lastPos = pos
			s.lastVel = vel
		end
	end
end )

-- commands -------------------------------------------------------------------

concommand.Add( "skyops_arty_status", function( ply )
	if not IsAdmin( ply ) then return end

	Log( "STATUS map %s, %.2f u/m, InfMap %s", game.GetMap(), UnitsPerMeter(), tostring( InfMap ~= nil ) )

	for _, spg in ipairs( ents.FindByClass( SPG_CLASS ) ) do
		local muzzle = spg:GetAttachment( spg:LookupAttachment( "muzzle" ) )
		Log( "  2S35 %s pos %s chunk %s | shell type %s | pose pitch %.1f yaw %.1f | barrel pitch %s | speed %.0f m/s",
			tostring( spg ), V( spg:GetPos() ), tostring( ChunkOf( spg ) ),
			tostring( spg.GetShellType and spg:GetShellType() ),
			spg:GetPoseParameter( "pitch" ), spg:GetPoseParameter( "yaw" ),
			muzzle and string.format( "%.1f", -muzzle.Ang.p ) or "?", M( spg:GetVelocity():Length() ) )
	end

	for _, ent in ipairs( ents.GetAll() ) do
		if UAV_CLASSES[ ent:GetClass() ] then
			local tank = ent.GetFuelTank and ent:GetFuelTank()
			local trackPos = ent:GetNWVector( "TrackPos" )
			Log( "  UAV %s pos %s chunk %s | alt %.0f m | speed %.0f m/s | fuel %s | tracking %s at %s (track ent %s)",
				tostring( ent ), V( ent:GetPos() ), tostring( ChunkOf( ent ) ), M( ent:GetPos().z ), M( ent:GetVelocity():Length() ),
				IsValid( tank ) and string.format( "%.0f%%", tank:GetFuel() * 100 ) or "?",
				tostring( ent.GetTracking and ent:GetTracking() ), V( trackPos ), tostring( ent.TrackEnt ) )
		end
	end

	SaveLog()
end )

concommand.Add( "skyops_arty_clear", function( ply )
	if not IsAdmin( ply ) then return end
	LogLines = {}
	SaveLog()
end )

concommand.Add( "skyops_arty_dump", function( ply )
	if IsValid( ply ) and not ply:IsAdmin() then return end

	file.CreateDir( "skyops/dump" )
	local count = 0

	local function Wanted( name )
		for _, w in ipairs( { "base", "fab100", "uav", "catapult", "laser", "krasnopol", "guid" } ) do
			if string.find( name, w, 1, true ) then return true end
		end
		return false
	end

	local function Dump( path )
		local data = file.Read( path, "LUA" )
		if not data then return end
		file.Write( "skyops/dump/" .. string.gsub( path, "[/\\]", "__" ) .. ".txt", data )
		count = count + 1
	end

	local files, dirs = file.Find( "entities/*", "LUA" )
	for _, f in ipairs( files ) do
		if string.StartWith( f, "sw_" ) and Wanted( f ) then Dump( "entities/" .. f ) end
	end
	for _, d in ipairs( dirs ) do
		if ( string.StartWith( d, "sw_" ) or string.find( d, "catapult", 1, true ) ) and Wanted( d ) then
			for _, f in ipairs( file.Find( "entities/" .. d .. "/*.lua", "LUA" ) ) do
				Dump( "entities/" .. d .. "/" .. f )
			end
		end
	end
	file.Write( "skyops/dump/_index.txt", table.concat( dirs, "\n" ) .. "\n--\n" .. table.concat( files, "\n" ) )

	print( "[Arty probe] dumped " .. count .. " files to data/skyops/dump" )
	if IsValid( ply ) then ply:ChatPrint( "Arty: сохранено файлов: " .. count ) end
end )
