-- Artillery shells flown by math instead of physics. The stock 2S35 shell is a physics
-- prop at 87 m/s; here a shell is a table stepped with FireComp.Step every FireComp.DT
-- in grid metres, and an explosion is spawned where it meets the terrain (KIR.MeshHeight
-- on Kirovskoe, so it works 40 km and 80 InfMap chunks away from any player).
--
-- Hooks for other modules (the drone module steers Krasnopol through them):
--   SkyOps.Arty.ShellFired( shell )
--   SkyOps.Arty.ShellThink( shell, dt )   before each step; set shell.ax/ay/az (m/s^2,
--                                         grid axes, reset after the step) or change
--                                         shell.vx/vy/vz directly
--   SkyOps.Arty.ShellImpact( shell, worldPos )   return true to skip the stock explosion
--   SkyOps.Arty.ShellRemoved( shell, reason )   reason = "impact" | "lost" | "timeout" | "removed"
-- Guided shells (def.guided) also go through SkyOps.Arty.Guided.Steer( shell, dt ) before
-- each step, with shell.pos (world Vector) and shell.vel (world units/s) filled in; the
-- turned shell.vel is taken back. Steer belongs to the drone module (arty/drone/sv_guided).
--
-- Wind: a shell takes the real wind (SkyOps.Arty.Wind.Actual) when fired and keeps it to
-- the end of its flight (shell.wx, shell.wy, m/s).
-- Shells with def.effect do not blow up like HE where they fall: "smoke" and "illum" only
-- leave their effect (drawn by arty/fx), "cluster" scatters def.bomblets around the point.

SkyOps.Arty = SkyOps.Arty or {}
SkyOps.Arty.Ballistics = SkyOps.Arty.Ballistics or {}

local B = SkyOps.Arty.Ballistics
local FC = SkyOps.Arty.FireComp
local Grid = SkyOps.Arty.Grid

util.AddNetworkString( "skyops_arty_impact" )

local cvTimeScale = CreateConVar( "skyops_arty_timescale", "1", FCVAR_ARCHIVE, "Speed of shell flight time (1 = real time, 5 = five times faster, for tests)", 0.1, 20 )
local cvDispersion = CreateConVar( "skyops_arty_dispersion", "1", FCVAR_ARCHIVE, "Shell dispersion multiplier (0 = every shell hits the laid point)", 0, 10 )

local MAX_TIME = 400 -- s of flight
local ARM_TIME = 0.3 -- s before a shell can hit the ground (leaves the barrel first)
local MAX_STEPS_PER_TICK = 400

B.Active = B.Active or {} -- id -> shell
B.NextId = B.NextId or 0

local function Gauss()
	local u = math.max( math.random(), 1e-12 )

	return math.sqrt( -2 * math.log( u ) ) * math.cos( 2 * math.pi * math.random() )
end

-- world position of a shell
function B.WorldPos( shell )
	return Grid.FromGrid( shell.x, shell.y, shell.z )
end

-- velocity as a world-space vector in units/s (for effects and trails)
function B.WorldVel( shell )
	local a = Grid.FromGrid( Grid.Origin, Grid.Origin, 0 )
	local b = Grid.FromGrid( Grid.Origin + shell.vx, Grid.Origin + shell.vy, shell.vz )

	return b - a
end

-- sets the shell velocity from a world-space vector in units/s
function B.SetWorldVel( shell, vel )
	local o = Grid.FromGrid( Grid.Origin, Grid.Origin, 0 )
	local x, y = Grid.ToGrid( o + vel )

	shell.vx, shell.vy, shell.vz = x - Grid.Origin, y - Grid.Origin, vel.z / Grid.UPM()
end

-- opts = { pos = world Vector (muzzle), dir = world unit Vector, shell = id, charge = id,
--          v0 = m/s (optional, else from the charge), attacker = Entity, spg = Entity,
--          dispersion = multiplier (default 1), wind = {x, y} m/s | false (none) | nil
--          (the real wind now) }
-- -> shell table, or nil and an error
function B.Fire( opts )
	local def = FC.GetShell( opts.shell )

	if not def then return nil, "unknown shell" end

	local charge = FC.GetCharge( opts.shell, opts.charge )
	local v0 = opts.v0 or ( charge and charge.v0 )

	if not v0 then return nil, "unknown charge" end

	local bearing, elev = FC.DirToMils( opts.dir )
	local spread = ( opts.dispersion or 1 ) * cvDispersion:GetFloat()
	local disp = def.dispersion or {}

	v0 = v0 * ( 1 + Gauss() * ( disp.v0 or 0 ) * spread )
	bearing = bearing + Gauss() * ( disp.mils or 0 ) * spread
	elev = elev + Gauss() * ( disp.mils or 0 ) * spread

	local b = bearing / FC.MILS * 2 * math.pi
	local e = elev / FC.MILS * 2 * math.pi
	local x, y, z = Grid.ToGrid3( opts.pos )
	local wind = opts.wind

	if wind == nil then
		local Wind = SkyOps.Arty.Wind

		wind = Wind and Wind.Actual and Wind.Actual()
	end

	B.NextId = B.NextId + 1

	local shell = {
		id = B.NextId,
		shell = opts.shell,
		def = def,
		charge = opts.charge,
		v0 = v0,
		x = x, y = y, z = z,
		vx = v0 * math.cos( e ) * math.sin( b ),
		vy = v0 * math.cos( e ) * math.cos( b ),
		vz = v0 * math.sin( e ),
		wx = wind and wind.x or 0,
		wy = wind and wind.y or 0,
		t = 0,
		start = { x = x, y = y, h = z },
		attacker = opts.attacker,
		owner = IsValid( opts.attacker ) and opts.attacker:IsPlayer() and opts.attacker or nil,
		spg = opts.spg,
		data = {}, -- free space for other modules
	}

	B.Active[ shell.id ] = shell

	hook.Run( "SkyOps.Arty.ShellFired", shell )

	return shell
end

local function RemoveShell( shell, reason )
	B.Active[ shell.id ] = nil

	hook.Run( "SkyOps.Arty.ShellRemoved", shell, reason )
end

function B.Remove( shell )
	if B.Active[ shell.id ] then RemoveShell( shell, "removed" ) end
end

-- Explosion ------------------------------------------------------------------------

local BOMB_CLASS = "sw_bomb_fab100_v3"

-- explosion at a world position with the shell's blast table (metres); uses the SW Bombs
-- warhead for its effects, sounds and fragments when that addon is installed
function B.Explode( pos, blast, attacker )
	local upm = Grid.UPM()
	local bomb = ents.Create( BOMB_CLASS )

	if IsValid( bomb ) then
		bomb.SkyOpsArty_Ours = true -- not a 2S35 shot, sv_spg leaves it alone
		bomb:SetPos( pos )
		bomb:SetAngles( Angle( 90, 0, 0 ) )
		bomb:Spawn()
		bomb:Activate()

		local phys = bomb:GetPhysicsObject()

		if IsValid( phys ) then phys:EnableMotion( false ) end

		-- it explodes right now; a later touch must not explode it a second time
		bomb.PhysicsCollide = function() end

		bomb.ExplosionRadius = blast.radius * upm
		bomb.BlastRadius = blast.blastRadius * upm
		bomb.FragRadius = blast.fragRadius * upm
		bomb.ExplosionDamage = blast.damage
		bomb.FragDamage = blast.fragDamage
		bomb.FragCount = blast.fragCount
		bomb.Armed = true
		bomb.Exploded = true

		if IsValid( attacker ) then
			bomb:SetCreator( attacker )
			bomb.Attacker = attacker
		end

		bomb:Explode( pos )

		return
	end

	-- no SW Bombs: plain Source explosion
	local inflictor = game.GetWorld()

	util.BlastDamage( inflictor, IsValid( attacker ) and attacker or inflictor, pos, blast.blastRadius * upm, blast.damage / 10 )

	local ed = EffectData()
	ed:SetOrigin( pos )
	util.Effect( "Explosion", ed, true, true )
end

-- damage to everything within radius (m) of a world position, falling off to the edge.
-- Done by hand instead of util.BlastDamage: on InfMap the engine sees positions inside
-- a chunk and would also hit things at the same spot of other chunks.
function B.Splash( pos, radius, damage, attacker )
	local r = radius * Grid.UPM()
	local world = game.GetWorld()

	attacker = IsValid( attacker ) and attacker or world

	for _, ent in ipairs( ents.GetAll() ) do
		if ent:IsPlayer() or ent:IsNPC() or ent.LVS or ent:GetClass() == "prop_physics" then
			local d = ent:GetPos():Distance( pos )

			if d < r then
				local dmg = DamageInfo()

				dmg:SetDamage( damage * ( 1 - d / r ) )
				dmg:SetDamageType( DMG_BLAST )
				dmg:SetAttacker( attacker )
				dmg:SetInflictor( world )
				dmg:SetDamagePosition( pos )
				dmg:SetDamageForce( ( ent:GetPos() - pos ):GetNormalized() * damage * 50 )
				ent:TakeDamageInfo( dmg )
			end
		end
	end
end

local function Bomblets( shell, x, y, z )
	local b = shell.def.bomblets
	local attacker = shell.attacker

	for _, o in ipairs( FC.BombletPattern( shell.id % 65536, b.count, b.radius ) ) do
		local bx, by = x + o[ 1 ], y + o[ 2 ]
		local bz = Grid.Height( bx, by ) or z

		timer.Simple( o[ 3 ], function()
			B.Splash( Grid.FromGrid( bx, by, bz + 0.5 ), b.blast.blastRadius, b.blast.damage / 10, attacker )
		end )
	end
end

local function Impact( shell, x, y, z )
	local pos = Grid.FromGrid( x, y, z ) + Vector( 0, 0, Grid.UPM() * 0.5 )
	local effect = shell.def.effect

	shell.impact = pos

	if hook.Run( "SkyOps.Arty.ShellImpact", shell, pos ) ~= true then
		if effect == "cluster" then
			Bomblets( shell, x, y, z )
		elseif shell.def.blast then
			B.Explode( pos, shell.def.blast, shell.attacker )
		end
	end

	-- three floats: net.WriteVector clamps to +-16384 u (docs/arty-api.md)
	net.Start( "skyops_arty_impact" )
		net.WriteFloat( pos.x )
		net.WriteFloat( pos.y )
		net.WriteFloat( pos.z )
		net.WriteString( shell.shell )
	net.Send( SkyOps.Teams.Recipients( SkyOps.Teams.Of( shell.spg ) ~= 0 and shell.spg or shell.owner ) ) -- team vs team: only the gun's side logs the burst

	RemoveShell( shell, "impact" )
end

-- Flight ---------------------------------------------------------------------------

local Accum = 0

local function StepShell( shell, dt )
	hook.Run( "SkyOps.Arty.ShellThink", shell, dt )

	if not B.Active[ shell.id ] then return end -- removed by a hook

	local Guided = SkyOps.Arty.Guided

	if shell.def.guided and Guided and Guided.Steer then
		shell.pos = B.WorldPos( shell )
		shell.vel = B.WorldVel( shell )

		Guided.Steer( shell, dt )

		if not B.Active[ shell.id ] then return end

		B.SetWorldVel( shell, shell.vel )
	end

	local px, py, pz = shell.x, shell.y, shell.z
	local pg = Grid.Height( px, py )

	FC.Step( shell, shell.def.k, dt, shell.ax, shell.ay, shell.az, shell.wx, shell.wy )
	shell.ax, shell.ay, shell.az = nil, nil, nil
	shell.t = shell.t + dt

	local g = Grid.Height( shell.x, shell.y )

	if not g then
		-- off the height grid: far below anything means it left the map
		if shell.z < -5000 then RemoveShell( shell, "lost" ) end
		return
	end

	if shell.t > ARM_TIME and shell.z <= g then
		-- where between the two steps the path crossed the terrain
		local a = pz - ( pg or g )
		local b = shell.z - g
		local f = a > 0 and math.Clamp( a / ( a - b ), 0, 1 ) or 1

		Impact( shell, px + ( shell.x - px ) * f, py + ( shell.y - py ) * f, pz + ( shell.z - pz ) * f )
		return
	end

	if shell.t > MAX_TIME then RemoveShell( shell, "timeout" ) end
end

hook.Add( "Think", "SkyOps.Arty.Ballistics", function()
	if next( B.Active ) == nil then
		Accum = 0
		return
	end

	local dt = FC.DT

	Accum = Accum + FrameTime() * cvTimeScale:GetFloat()

	local steps = math.min( math.floor( Accum / dt ), MAX_STEPS_PER_TICK )

	Accum = Accum - steps * dt

	if Accum > dt then Accum = 0 end -- falling behind: drop the backlog instead of piling up

	for _ = 1, steps do
		for _, shell in pairs( B.Active ) do
			StepShell( shell, dt )
		end
	end
end )

concommand.Add( "skyops_arty_shells", function( ply )
	if IsValid( ply ) and not ply:IsAdmin() then return end

	local n = 0

	for _, s in pairs( B.Active ) do
		n = n + 1
		print( string.format( "[Arty] #%d %s t=%.1f s  %s  h=%.0f m  v=%.0f m/s",
			s.id, s.shell, s.t, Grid.Format( s.x, s.y ), s.z, math.sqrt( s.vx ^ 2 + s.vy ^ 2 + s.vz ^ 2 ) ) )
	end

	print( "[Arty] shells in flight: " .. n )
end )
