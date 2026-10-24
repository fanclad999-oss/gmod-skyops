-- Artillery effects: shells in flight. The client flies its own copy of every shell with
-- the same FireComp.Step as the server (corrected once a second by skyops_arty_fx_state),
-- so it knows when a shell comes down near the listener and plays the whistle of the
-- incoming shell a couple of seconds before the burst, or the rush of one passing close.
--
-- skyops_arty_fx_trail 1 draws every shell and its path (for tests).
-- skyops_arty_fx_test <shot|impact|salvo|incoming|column> [distance m]: effects without a
-- gun or a server, at the given distance in front of the camera (default 300 m).

local FX = SkyOps.Arty.FX
local FC = SkyOps.Arty.FireComp
local Grid = SkyOps.Arty.Grid

local SND_WHISTLE = {
	"weapons/mortar/mortar_shell_incomming1.wav",
}

local SND_FLYBY = {
	"weapons/fx/nearmiss/bulletltor03.wav",
	"weapons/fx/nearmiss/bulletltor04.wav",
	"weapons/fx/nearmiss/bulletltor05.wav",
	"weapons/fx/nearmiss/bulletltor06.wav",
	"weapons/fx/nearmiss/bulletltor07.wav",
	"weapons/fx/nearmiss/bulletltor09.wav",
	"weapons/fx/nearmiss/bulletltor10.wav",
	"weapons/fx/nearmiss/bulletltor11.wav",
	"weapons/fx/nearmiss/bulletltor12.wav",
	"weapons/fx/nearmiss/bulletltor13.wav",
	"weapons/fx/nearmiss/bulletltor14.wav",
}

local WHISTLE_LEAD = 2.3 -- s before the impact the whistle starts (length of the sample)
local WHISTLE_RADIUS = 900 -- m from the listener: closer impacts are heard coming
local FLYBY_RADIUS = 250 -- m: a shell passing this close rushes by
local MAX_TIME = 400 -- s

local shells = {} -- net id -> state

local function NewShell( id, shellId, ts )
	local def = FC.GetShell( shellId )
	local s = {
		id = id,
		shell = shellId,
		k = def and def.k or 4.2e-5,
		ts = ts or 1,
		t = 0,
		acc = 0,
		trail = {},
		nextTrail = 0,
	}

	shells[ id ] = s

	return s
end

-- listener as grid metres and height of the ground under it
local function Listener()
	local w = FX.ViewWorld()
	local x, y, h = Grid.ToGrid3( w )
	local ply = LocalPlayer()
	local feet = IsValid( ply ) and ( ply:GetPos() + FX.ChunkOrigin() ).z / FX.UPM() or h

	return x, y, h, feet
end

local function GroundH( x, y, fallback )
	local h = KIR and KIR.MeshHeight and Grid.Height( x, y )

	return h or fallback
end

local function WorldPos( s )
	return Grid.FromGrid( s.x, s.y, s.z )
end

local function Whistle( s, ix, iy, lx, ly, lh )
	local d = math.sqrt( ( ix - lx ) ^ 2 + ( iy - ly ) ^ 2 + ( s.groundH - lh ) ^ 2 )
	local vol = FX.Loudness( d, 120, WHISTLE_RADIUS * 1.2 )
	local snd = FX.Pick( SND_WHISTLE, false )

	if not snd or vol <= 0 then return end

	-- from the point where it is going to fall, a little above it
	local pos = FX.ToRender( Grid.FromGrid( ix, iy, s.groundH + 60 ) )

	FX.PlayAt( pos, snd, 120, math.Rand( 88, 104 ), vol )
end

local function Flyby( s, lx, ly, lh )
	local d = math.sqrt( ( s.x - lx ) ^ 2 + ( s.y - ly ) ^ 2 + ( s.z - lh ) ^ 2 )
	local snd = FX.Pick( SND_FLYBY, false )

	if not snd then return end

	FX.PlayAt( FX.ToRender( WorldPos( s ) ), snd, 110, math.Rand( 38, 52 ), FX.Loudness( d, 40, FLYBY_RADIUS ) )
end

local function Think( s, dt, lx, ly, lh, feet )
	s.acc = s.acc + dt * s.ts

	local step = FC.DT

	while s.acc >= step do
		s.acc = s.acc - step
		FC.Step( s, s.k, step )
		s.t = s.t + step
	end

	if s.t > MAX_TIME then return false end

	local gh = GroundH( s.x, s.y, feet )

	s.groundH = gh

	-- a test shell lands by itself; a real one waits for the server's impact message
	if s.test and s.z <= s.test.h then
		FX.Impact( Grid.FromGrid( s.x, s.y, s.test.h ), s.shell )
		return false
	end

	if s.z < gh - 50 then return false end -- missed its impact message

	if not s.whistled and s.vz < 0 then
		-- time to the ground, with the vertical speed growing under gravity
		local fall = s.z - gh
		local vz = -s.vz
		local tg = ( -vz + math.sqrt( vz * vz + 2 * FC.G * math.max( fall, 0 ) ) ) / FC.G

		if tg / s.ts <= WHISTLE_LEAD then
			s.whistled = true

			local ix, iy = s.x + s.vx * tg, s.y + s.vy * tg

			if ( ix - lx ) ^ 2 + ( iy - ly ) ^ 2 < WHISTLE_RADIUS ^ 2 then
				Whistle( s, ix, iy, lx, ly, feet )
			end
		end
	end

	if not s.flew and not s.whistled and s.t > 1 then
		local d2 = ( s.x - lx ) ^ 2 + ( s.y - ly ) ^ 2 + ( s.z - lh ) ^ 2

		if d2 < FLYBY_RADIUS ^ 2 then
			s.flew = true
			Flyby( s, lx, ly, lh )
		end
	end

	if FX.cvTrail:GetBool() and CurTime() >= s.nextTrail then
		s.nextTrail = CurTime() + 0.2
		s.trail[ #s.trail + 1 ] = WorldPos( s )

		if #s.trail > 400 then table.remove( s.trail, 1 ) end
	end

	return true
end

hook.Add( "Think", "SkyOps.Arty.FX.Flight", function()
	if next( shells ) == nil then return end

	local dt = FrameTime()
	local lx, ly, lh, feet = Listener()

	for id, s in pairs( shells ) do
		if not Think( s, dt, lx, ly, lh, feet ) then shells[ id ] = nil end
	end
end )

-- Trails (tests) -------------------------------------------------------------------

local TRAIL_COL = Color( 255, 120, 40 )

hook.Add( "PostDrawTranslucentRenderables", "SkyOps.Arty.FX.Trail", function( depth, sky, sky3d )
	if depth or sky or sky3d or not FX.cvTrail:GetBool() then return end

	for _, s in pairs( shells ) do
		local last

		for _, w in ipairs( s.trail ) do
			local p = FX.Project( FX.ToRender( w ), 1 )

			if last then render.DrawLine( last, p, TRAIL_COL, false ) end

			last = p
		end

		local p, size = FX.Project( FX.ToRender( WorldPos( s ) ), 3 * FX.UPM() )

		if last then render.DrawLine( last, p, TRAIL_COL, false ) end

		render.SetMaterial( FX.GlowMat )
		render.DrawSprite( p, math.max( size, 6 ), math.max( size, 6 ), TRAIL_COL )
	end
end )

-- Net ------------------------------------------------------------------------------

net.Receive( "skyops_arty_fx_shot", function()
	local id = net.ReadUInt( 16 )
	local shellId = net.ReadString()
	local spg = net.ReadEntity()
	local muzzle = FX.ReadPos()
	local dir = FX.ReadPos()
	local ts = net.ReadFloat()
	local s = NewShell( id, shellId, ts )

	FX.ReadState( s )

	-- spg is NULL when the gun is out of our PVS: then the server's muzzle position is used
	FX.Shot( spg, muzzle, dir )
end )

net.Receive( "skyops_arty_fx_state", function()
	local id = net.ReadUInt( 16 )
	local st = FX.ReadState()
	local s = shells[ id ]

	if not s then return end

	s.x, s.y, s.z, s.vx, s.vy, s.vz = st.x, st.y, st.z, st.vx, st.vy, st.vz
	s.acc = 0
end )

net.Receive( "skyops_arty_fx_impact", function()
	local id = net.ReadUInt( 16 )
	local shellId = net.ReadString()
	local pos = FX.ReadPos()

	shells[ id ] = nil
	FX.Impact( pos, shellId, id )
end )

-- Tests ----------------------------------------------------------------------------

local testId = 60000

-- unlocalized world position on the ground "m" metres ahead of the camera
local function Ahead( m, side )
	local ang = FX.ViewAng()
	local fwd = Angle( 0, ang.y, 0 ):Forward()
	local right = Angle( 0, ang.y, 0 ):Right()
	local pos = FX.ViewPos() + fwd * m * FX.UPM() + right * ( side or 0 ) * FX.UPM()

	pos.z = FX.GroundAt( pos )

	return pos + FX.ChunkOrigin()
end

local function Incoming( target, shellId )
	local tx, ty, th = Grid.ToGrid3( target )
	local tf = 9
	local g = FC.G
	-- comes from behind the camera, high
	local back = -Angle( 0, FX.ViewAng().y, 0 ):Forward()
	local bx, by = Grid.ToGrid( target + back * 2500 * FX.UPM() )
	local sx, sy, sz = bx, by, th + 1400

	testId = testId + 1

	local s = NewShell( testId, shellId or "he", 1 )

	s.k = 0 -- a straight parabola that ends exactly at the target
	s.x, s.y, s.z = sx, sy, sz
	s.vx = ( tx - sx ) / tf
	s.vy = ( ty - sy ) / tf
	s.vz = ( th - sz + 0.5 * g * tf * tf ) / tf
	s.t = 2 -- no flyby right at the start
	s.test = { h = th }
end

concommand.Add( "skyops_arty_fx_test", function( _, _, args )
	local what = args[ 1 ] or "impact"
	local m = tonumber( args[ 2 ] or "" ) or 300

	if what == "shot" then
		local spg = SkyOps.Arty.SPG.Of( LocalPlayer() )

		if spg then
			local att = spg:GetAttachment( spg:LookupAttachment( "muzzle" ) or 0 )

			if att then return FX.Shot( spg, att.Pos + FX.ChunkOrigin(), att.Ang:Forward() ) end
		end

		local ang = FX.ViewAng()

		FX.Shot( NULL, FX.ViewWorld() + ang:Forward() * 300, ang:Forward() )
	elseif what == "impact" then
		FX.Impact( Ahead( m ), args[ 3 ] or "he" )
	elseif what == "salvo" then
		for i = 0, 5 do
			timer.Simple( i * math.Rand( 0.3, 0.9 ), function()
				FX.Impact( Ahead( m + math.Rand( -40, 40 ), math.Rand( -40, 40 ) ), "he" )
			end )
		end
	elseif what == "incoming" then
		Incoming( Ahead( m ), args[ 3 ] )
		print( "[Arty FX] снаряд прилетит через 9 с" )
	elseif what == "column" then
		FX.AddColumn( FX.ToRender( Ahead( m ) ) )
	else
		print( "skyops_arty_fx_test shot | impact [м] | salvo [м] | incoming [м] | column [м]" )
	end
end )
