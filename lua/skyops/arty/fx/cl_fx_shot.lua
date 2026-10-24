-- Artillery effects: the 2S35 shot (flash from the muzzle brake, smoke, dust kicked up
-- around the gun, the boom heard with a delay far away) and the dust and hydraulics of
-- deploying and stowing.

local FX = SkyOps.Arty.FX
local SPG = SkyOps.Arty.SPG

local SND_SHOT_NEAR = {
	"weapons/mortar/mortar_fire1.wav",
	"ambient/explosions/explode_1.wav",
	"ambient/explosions/explode_3.wav",
}

local SND_SHOT_BODY = {
	"ambient/explosions/explode_4.wav",
	"ambient/explosions/explode_5.wav",
}

local SND_SHOT_FAR = {
	"ambient/explosions/explode_7.wav",
	"ambient/explosions/explode_8.wav",
	"ambient/explosions/explode_9.wav",
}

-- render-space muzzle position and direction: from the gun itself when it is in our
-- chunk (it moved on in the meantime and the model is exact), else from the server
local function Muzzle( spg, wpos, dir )
	local ply = LocalPlayer()

	if IsValid( spg ) and not spg:IsDormant() and spg.CHUNK_OFFSET == ply.CHUNK_OFFSET then
		local id = spg:LookupAttachment( "muzzle" )
		local att = id and id > 0 and spg:GetAttachment( id )

		if att then return att.Pos, att.Ang:Forward() end
	end

	return FX.ToRender( wpos ), dir
end

local function GroundDust( em, center, groundZ, radius, count, speed, col )
	for i = 1, count do
		local a = math.Rand( 0, math.pi * 2 )
		local out = Vector( math.cos( a ), math.sin( a ), 0 )
		local p = em:Add( FX.Smoke(), Vector( center.x, center.y, groundZ + 20 ) + out * math.Rand( 0.3, 1 ) * radius )

		if p then
			p:SetVelocity( out * math.Rand( 0.5, 1 ) * speed + Vector( 0, 0, math.Rand( 20, 120 ) ) )
			p:SetAirResistance( 180 )
			p:SetGravity( Vector( 0, 0, -30 ) )
			p:SetDieTime( math.Rand( 2.5, 5 ) )
			p:SetStartAlpha( math.Rand( 90, 150 ) )
			p:SetEndAlpha( 0 )
			p:SetStartSize( math.Rand( 60, 110 ) )
			p:SetEndSize( math.Rand( 250, 420 ) )
			p:SetRoll( math.Rand( 0, 360 ) )
			p:SetRollDelta( math.Rand( -0.4, 0.4 ) )
			p:SetColor( col.r * math.Rand( 0.85, 1.1 ), col.g * math.Rand( 0.85, 1.1 ), col.b * math.Rand( 0.85, 1.1 ) )
			p:SetLighting( false )
		end
	end
end

local DUST = Color( 140, 120, 95 )

-- muzzle flash and smoke at a render-space position
function FX.ShotVisual( pos, dir, spg )
	local d = pos:Distance( FX.ViewPos() )

	-- the flash is seen from anywhere; far away it is a billboard (see cl_fx_impact)
	FX.AddFlash( pos, 9, 0.12, Color( 255, 190, 110 ) )

	if d > FX.NEAR_DIST then
		FX.AddColumn( pos + dir * 200, { small = true, life = 10 } )
		return
	end

	local em = FX.Emitter( pos )

	if not em then return end

	local ang = dir:Angle()
	local right = ang:Right()

	-- main flash along the barrel
	for i = 1, 4 do
		local p = em:Add( "effects/muzzleflash" .. math.random( 1, 4 ), pos + dir * ( i * 45 ) )

		if p then
			p:SetVelocity( dir * 600 )
			p:SetDieTime( math.Rand( 0.07, 0.12 ) )
			p:SetStartAlpha( 255 )
			p:SetEndAlpha( 0 )
			p:SetStartSize( 150 - i * 20 )
			p:SetEndSize( 230 - i * 25 )
			p:SetRoll( math.Rand( 0, 360 ) )
			p:SetColor( 255, 230, 200 )
		end
	end

	-- the muzzle brake throws flame and gas to both sides
	for _, side in ipairs( { right, -right } ) do
		for i = 1, 2 do
			local p = em:Add( "effects/muzzleflash" .. math.random( 1, 4 ), pos + side * ( 30 + i * 30 ) )

			if p then
				p:SetVelocity( ( side * 0.8 + dir * 0.4 ) * 900 )
				p:SetDieTime( math.Rand( 0.06, 0.1 ) )
				p:SetStartAlpha( 255 )
				p:SetEndAlpha( 0 )
				p:SetStartSize( 90 )
				p:SetEndSize( 150 )
				p:SetRoll( math.Rand( 0, 360 ) )
			end
		end

		for _ = 1, FX.Count( 10 ) do
			local p = em:Add( FX.Smoke(), pos + side * 40 )

			if p then
				p:SetVelocity( ( FX.Cone( side * 0.85 + dir * 0.5, 0.35 ) ) * math.Rand( 600, 1700 ) )
				p:SetAirResistance( math.Rand( 160, 260 ) )
				p:SetGravity( Vector( 0, 0, math.Rand( 10, 40 ) ) )
				p:SetDieTime( math.Rand( 3, 7 ) )
				p:SetStartAlpha( math.Rand( 120, 180 ) )
				p:SetEndAlpha( 0 )
				p:SetStartSize( math.Rand( 40, 80 ) )
				p:SetEndSize( math.Rand( 280, 520 ) )
				p:SetRoll( math.Rand( 0, 360 ) )
				p:SetRollDelta( math.Rand( -0.5, 0.5 ) )
				local g = math.Rand( 150, 185 )
				p:SetColor( g, g, g * 0.97 )
				p:SetLighting( false )
			end
		end
	end

	-- fire ball and the big smoke cloud in front of the barrel
	for _ = 1, FX.Count( 5 ) do
		local p = em:Add( "effects/fire_cloud1", pos + dir * math.Rand( 40, 160 ) )

		if p then
			p:SetVelocity( FX.Cone( dir, 0.25 ) * math.Rand( 300, 900 ) )
			p:SetAirResistance( 300 )
			p:SetDieTime( math.Rand( 0.15, 0.3 ) )
			p:SetStartAlpha( 230 )
			p:SetEndAlpha( 0 )
			p:SetStartSize( math.Rand( 60, 100 ) )
			p:SetEndSize( math.Rand( 160, 260 ) )
			p:SetRoll( math.Rand( 0, 360 ) )
		end
	end

	for _ = 1, FX.Count( 22 ) do
		local p = em:Add( FX.Smoke(), pos + dir * math.Rand( 40, 120 ) )

		if p then
			p:SetVelocity( FX.Cone( dir, 0.3 ) * math.Rand( 700, 2600 ) )
			p:SetAirResistance( math.Rand( 140, 220 ) )
			p:SetGravity( Vector( 0, 0, math.Rand( 15, 45 ) ) + FX.Wind() * 0.3 )
			p:SetDieTime( math.Rand( 5, 10 ) )
			p:SetStartAlpha( math.Rand( 140, 200 ) )
			p:SetEndAlpha( 0 )
			p:SetStartSize( math.Rand( 50, 90 ) )
			p:SetEndSize( math.Rand( 380, 700 ) )
			p:SetRoll( math.Rand( 0, 360 ) )
			p:SetRollDelta( math.Rand( -0.3, 0.3 ) )
			local g = math.Rand( 160, 200 )
			p:SetColor( g, g, g )
			p:SetLighting( false )
		end
	end

	-- the blast lifts dust all around the gun
	local base = IsValid( spg ) and spg:GetPos() or pos
	local groundZ = FX.GroundAt( base )

	GroundDust( em, base, groundZ, 350, FX.Count( 18 ), 1300, DUST )

	local dl = DynamicLight( 0x5C0000 + ( IsValid( spg ) and spg:EntIndex() or 0 ) % 0xFFFF )

	if dl then
		dl.pos = pos + dir * 80
		dl.r, dl.g, dl.b = 255, 170, 80
		dl.brightness = 6
		dl.decay = 6000
		dl.size = 1400
		dl.dietime = CurTime() + 0.15
	end
end

-- shot: effects at once, the boom when it reaches the listener
function FX.Shot( spg, wpos, dir )
	if not FX.Enabled() then return end

	local pos, d = Muzzle( spg, wpos, dir )

	dir = d
	FX.ShotVisual( pos, dir, spg )

	FX.AfterSound( pos + FX.ChunkOrigin(), function( m, rpos )
		if m < 400 then
			FX.PlayAt( rpos, FX.Pick( SND_SHOT_NEAR ), 140, math.Rand( 70, 80 ), 1 )
			FX.PlayAt( rpos, FX.Pick( SND_SHOT_BODY ), 140, math.Rand( 55, 65 ), 0.8 )
		end

		if m > 150 then
			FX.PlayAt( rpos, FX.Pick( SND_SHOT_FAR ), 140, math.Rand( 60, 75 ), FX.Loudness( m, 300, 18000 ) )
		end

		-- the crew feels it, a drone above hardly does
		FX.Shake( m, 7, 120, 0.7 )
	end )
end

-- Deploying and stowing ------------------------------------------------------------

local SND_HYDRAULIC = {
	"ambient/machines/hydraulic_1.wav",
	"plats/crane/vertical_start.wav",
}

local SND_CLUNK = {
	"doors/heavy_metal_stop1.wav",
	"plats/crane/vertical_stop.wav",
	"physics/metal/metal_box_impact_hard1.wav",
	"physics/metal/metal_box_impact_hard2.wav",
	"physics/metal/metal_box_impact_hard3.wav",
}

local SND_START = {
	"plats/crane/vertical_start.wav",
	"doors/heavy_metal_move1.wav",
}

local active = {} -- spg -> { state, until, next }
local lastState = {}

local function Corners( spg )
	local mins, maxs = spg:OBBMins(), spg:OBBMaxs()
	local list = {}

	for _, x in ipairs( { mins.x * 0.8, 0, maxs.x * 0.8 } ) do
		for _, y in ipairs( { mins.y * 0.9, maxs.y * 0.9 } ) do
			list[ #list + 1 ] = spg:LocalToWorld( Vector( x, y, mins.z ) )
		end
	end

	return list
end

local function DeployPuff( spg, strength )
	if spg:GetPos():Distance( FX.ViewPos() ) > FX.NEAR_DIST then return end

	local em = FX.Emitter( spg:GetPos() )

	if not em then return end

	for _, c in ipairs( Corners( spg ) ) do
		for _ = 1, FX.Count( 2 * strength ) do
			local p = em:Add( FX.Smoke(), c + VectorRand() * 30 )

			if p then
				local out = ( c - spg:GetPos() )
				out.z = 0
				out:Normalize()

				p:SetVelocity( out * math.Rand( 60, 220 ) * strength + Vector( 0, 0, math.Rand( 10, 60 ) ) )
				p:SetAirResistance( 90 )
				p:SetGravity( Vector( 0, 0, -10 ) + FX.Wind() * 0.2 )
				p:SetDieTime( math.Rand( 2, 4 ) )
				p:SetStartAlpha( math.Rand( 60, 110 ) )
				p:SetEndAlpha( 0 )
				p:SetStartSize( math.Rand( 30, 60 ) )
				p:SetEndSize( math.Rand( 140, 260 ) )
				p:SetRoll( math.Rand( 0, 360 ) )
				p:SetRollDelta( math.Rand( -0.6, 0.6 ) )
				p:SetColor( DUST.r, DUST.g, DUST.b )
				p:SetLighting( false )
			end
		end
	end
end

local function Sound( spg, list, level, pitch, vol )
	local snd = FX.Pick( list, false )

	if snd then FX.PlayAt( spg:GetPos(), snd, level, pitch, vol ) end
end

local function OnState( spg, state, old )
	if state == SPG.STATE_DEPLOYING or state == SPG.STATE_STOWING then
		local stop = spg:GetNW2Float( "SkyOpsArty_StateEnd", CurTime() )

		active[ spg ] = { state = state, stop = stop, nextPuff = 0, nextSound = 0 }
		Sound( spg, SND_START, 80, 90, 0.8 )
		DeployPuff( spg, 1.5 )
	elseif state == SPG.STATE_DEPLOYED and old == SPG.STATE_DEPLOYING then
		active[ spg ] = nil
		Sound( spg, SND_CLUNK, 85, 70, 1 )
		DeployPuff( spg, 2 )
	elseif state == SPG.STATE_MARCH and old == SPG.STATE_STOWING then
		active[ spg ] = nil
		Sound( spg, SND_CLUNK, 80, 85, 0.8 )
	end
end

local nextScan = 0

hook.Add( "Think", "SkyOps.Arty.FX.Deploy", function()
	if not FX.Enabled() then return end

	local now = CurTime()

	if now >= nextScan then
		nextScan = now + 0.2

		for _, spg in ipairs( ents.FindByClass( SPG.CLASS ) ) do
			if not spg:IsDormant() then
				local state = spg:GetNW2Int( "SkyOpsArty_State", SPG.STATE_MARCH )
				local old = lastState[ spg ]

				if old ~= nil and old ~= state then OnState( spg, state, old ) end

				lastState[ spg ] = state
			end
		end

		for spg in pairs( lastState ) do
			if not IsValid( spg ) then lastState[ spg ] = nil end
		end
	end

	for spg, a in pairs( active ) do
		if not IsValid( spg ) or now > a.stop + 0.5 then
			active[ spg ] = nil
		else
			-- the stabilisers dig in at the start and the hull settles: most dust early
			local left = math.max( a.stop - now, 0 )

			if now >= a.nextPuff then
				a.nextPuff = now + ( left > 2 and 0.6 or 1.2 )
				DeployPuff( spg, left > 2 and 0.8 or 0.4 )
			end

			if now >= a.nextSound and left > 0.5 then
				a.nextSound = now + 1.6
				Sound( spg, SND_HYDRAULIC, 75, a.state == SPG.STATE_DEPLOYING and 80 or 95, 0.5 )
			end
		end
	end
end )
