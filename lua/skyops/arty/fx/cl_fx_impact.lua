-- Artillery effects: the shell burst. Up close: flash, fire ball, a fountain of earth,
-- flying clods, the dust ring of the blast wave, scorch mark, shake. From any distance:
-- the flash, a column of dust and smoke that stands for skyops_arty_fx_column seconds
-- and drifts with the wind, so a drone operator can see where the shell fell and correct
-- the fire, and the bang that arrives at the speed of sound.

local FX = SkyOps.Arty.FX
local FC = SkyOps.Arty.FireComp

local SND_NEAR = {
	"weapons/mortar/mortar_explode1.wav",
	"weapons/mortar/mortar_explode2.wav",
	"weapons/mortar/mortar_explode3.wav",
}

local SND_BODY = {
	"ambient/explosions/explode_1.wav",
	"ambient/explosions/explode_2.wav",
	"ambient/explosions/explode_3.wav",
	"ambient/explosions/explode_4.wav",
}

local SND_MID = {
	"ambient/explosions/explode_5.wav",
	"ambient/explosions/explode_7.wav",
	"ambient/explosions/explode_8.wav",
}

local SND_FAR = {
	"ambient/explosions/explode_9.wav",
	"ambient/explosions/explode_8.wav",
}

local SND_DEBRIS = {
	"physics/concrete/boulder_impact_hard1.wav",
	"physics/concrete/boulder_impact_hard2.wav",
	"physics/concrete/boulder_impact_hard3.wav",
	"physics/concrete/boulder_impact_hard4.wav",
	"physics/concrete/concrete_break2.wav",
	"physics/concrete/concrete_break3.wav",
}

local EARTH = Color( 74, 60, 46 )
local DUST = Color( 135, 118, 96 )

local MAX_COLUMNS = 32

-- Far billboards -------------------------------------------------------------------

local flashes = {} -- { wpos, size (u), t0, life, col }
local columns = {} -- see AddColumn

-- a flash of light at a render-space position: size in metres, life in s
function FX.AddFlash( pos, size_m, life, col )
	flashes[ #flashes + 1 ] = { wpos = pos + FX.ChunkOrigin(), size = size_m * FX.UPM(), t0 = CurTime(), life = life, col = col }
end

-- a column of smoke rising from a render-space ground position.
-- opts: scale (1 = 152 mm HE), life (s), small (gun smoke: low and short)
function FX.AddColumn( pos, opts )
	opts = opts or {}

	local upm = FX.UPM()
	local scale = opts.scale or 1
	local small = opts.small
	local col = {
		wpos = pos + FX.ChunkOrigin(),
		t0 = CurTime(),
		life = opts.life or FX.cvColumn:GetFloat(),
		height = ( small and 10 or math.Rand( 38, 55 ) * scale ) * upm,
		width = ( small and 4 or 7 * scale ) * upm,
		small = small,
		puffs = {},
		skirt = {},
	}

	local n = small and 6 or FX.Count( 16 )

	for i = 1, n do
		local f = ( i - 1 ) / math.max( n - 1, 1 )

		col.puffs[ i ] = {
			f = f, -- 0 bottom .. 1 top
			ox = math.Rand( -1, 1 ), oy = math.Rand( -1, 1 ),
			size = math.Rand( 0.8, 1.25 ),
			mat = math.random( #FX.SmokeMats ),
			roll = math.Rand( 0, 360 ),
			spin = math.Rand( -6, 6 ),
			shade = math.Rand( 0.85, 1.15 ),
		}
	end

	if not small then
		for i = 1, FX.Count( 7 ) do
			local a = ( i / 7 ) * math.pi * 2 + math.Rand( -0.3, 0.3 )

			col.skirt[ i ] = { dir = Vector( math.cos( a ), math.sin( a ), 0 ), mat = math.random( #FX.SmokeMats ), roll = math.Rand( 0, 360 ), size = math.Rand( 0.8, 1.2 ) }
		end
	end

	columns[ #columns + 1 ] = col

	-- too many: drop the oldest (the list itself is kept sorted by distance)
	while #columns > MAX_COLUMNS do
		local oldest = 1

		for i, c in ipairs( columns ) do
			if c.t0 < columns[ oldest ].t0 then oldest = i end
		end

		table.remove( columns, oldest )
	end

	return col
end

local function LerpColor( t, a, b )
	return a.r + ( b.r - a.r ) * t, a.g + ( b.g - a.g ) * t, a.b + ( b.b - a.b ) * t
end

local COL_LOW = Color( 62, 54, 46 )
local COL_TOP = Color( 128, 124, 118 )
local COL_FIRE = Color( 255, 150, 60 )
local COL_GUN = Color( 175, 175, 172 )

local function DrawColumn( c, now, light )
	local t = now - c.t0
	local life = c.life

	if t > life then return false end

	local base = FX.ToRender( c.wpos )

	-- fade in quickly, thin out over the last 40% of its life
	local fade = math.Clamp( t / 0.25, 0, 1 ) * math.Clamp( ( life - t ) / ( life * 0.4 ), 0, 1 )

	if fade <= 0 then return true end

	local upm = FX.UPM()
	local rise = 1 - math.exp( -t / ( c.small and 1.5 or 3.5 ) ) -- the column shoots up, then slows
	local h = c.height * ( rise + t / life * 0.35 ) -- and keeps creeping up as it spreads
	local wind = FX.Wind() * t
	local grow = 1 + t / life * 1.8

	for _, p in ipairs( c.puffs ) do
		local f = p.f
		local pos = base + Vector( p.ox, p.oy, 0 ) * ( c.width * ( 0.3 + f * 0.6 ) * grow ) + Vector( 0, 0, h * f ) + wind * f
		local size = c.width * ( 1.2 + f * 1.6 ) * grow * p.size
		local a = fade * ( 0.95 - f * 0.45 ) * 230

		local r, g, b

		if c.small then
			r, g, b = COL_GUN.r, COL_GUN.g, COL_GUN.b
		else
			r, g, b = LerpColor( math.Clamp( f * 0.7 + t / life * 0.6, 0, 1 ), COL_LOW, COL_TOP )

			-- the fire ball lights the bottom of the cloud for a moment
			local fire = math.Clamp( 1 - t / 0.7, 0, 1 ) * ( 1 - f )

			if fire > 0 then
				r, g, b = r + ( COL_FIRE.r - r ) * fire, g + ( COL_FIRE.g - g ) * fire, b + ( COL_FIRE.b - b ) * fire
			end
		end

		local k = p.shade * light

		FX.DrawPuff( FX.SmokeMats[ p.mat ], pos, size, Color( r * k, g * k, b * k, a ), p.roll + p.spin * t )
	end

	-- dust ring thrown out along the ground by the blast wave
	if #c.skirt > 0 and t < 14 then
		local spread = ( 1 - math.exp( -t / 1.2 ) ) * 26 * upm
		local sa = math.Clamp( t / 0.2, 0, 1 ) * math.Clamp( 1 - t / 14, 0, 1 ) * 170

		for _, s in ipairs( c.skirt ) do
			local pos = base + s.dir * spread + Vector( 0, 0, 3 * upm ) + wind * 0.3
			local size = ( 9 + t * 1.2 ) * upm * s.size
			local k = light

			FX.DrawPuff( FX.SmokeMats[ s.mat ], pos, size, Color( DUST.r * k, DUST.g * k, DUST.b * k, sa ), s.roll + t * 3 )
		end
	end

	return true
end

hook.Add( "PostDrawTranslucentRenderables", "SkyOps.Arty.FX", function( depth, sky, sky3d )
	if depth or sky or sky3d then return end
	if #columns == 0 and #flashes == 0 then return end

	local now = CurTime()
	local eye = EyePos()
	local light = FX.Light()

	-- far ones first, so nearer smoke covers them
	table.sort( columns, function( a, b )
		return FX.ToRender( a.wpos ):DistToSqr( eye ) > FX.ToRender( b.wpos ):DistToSqr( eye )
	end )

	local dead

	for i, c in ipairs( columns ) do
		if not DrawColumn( c, now, light ) then
			dead = dead or {}
			dead[ #dead + 1 ] = i
		end
	end

	if dead then
		for j = #dead, 1, -1 do table.remove( columns, dead[ j ] ) end
	end

	for i = #flashes, 1, -1 do
		local f = flashes[ i ]
		local t = ( now - f.t0 ) / f.life

		if t >= 1 then
			table.remove( flashes, i )
		else
			local a = ( 1 - t ) ^ 1.5 * 255

			FX.DrawPuff( FX.GlowMat, FX.ToRender( f.wpos ), f.size * ( 1 + t * 0.5 ), Color( f.col.r, f.col.g, f.col.b, a ), 0 )
		end
	end
end )

-- Close-up particles ---------------------------------------------------------------

local function Burst( pos, scale )
	local em = FX.Emitter( pos )

	if not em then return end

	local up = Vector( 0, 0, 1 )

	-- fire ball
	for _ = 1, FX.Count( 9 ) do
		local p = em:Add( "effects/fire_cloud1", pos + VectorRand() * 40 )

		if p then
			p:SetVelocity( FX.Cone( up, 1.2 ) * math.Rand( 250, 900 ) * scale )
			p:SetAirResistance( 260 )
			p:SetDieTime( math.Rand( 0.25, 0.55 ) )
			p:SetStartAlpha( 255 )
			p:SetEndAlpha( 0 )
			p:SetStartSize( math.Rand( 90, 160 ) * scale )
			p:SetEndSize( math.Rand( 260, 420 ) * scale )
			p:SetRoll( math.Rand( 0, 360 ) )
			p:SetRollDelta( math.Rand( -2, 2 ) )
		end
	end

	-- fountain of earth: a narrow fast jet and a wider slow one
	for i = 1, FX.Count( 34 ) do
		local narrow = i % 3 ~= 0
		local p = em:Add( FX.Smoke(), pos + VectorRand() * 30 )

		if p then
			p:SetVelocity( FX.Cone( up, narrow and 0.35 or 0.8 ) * math.Rand( narrow and 1200 or 500, narrow and 2800 or 1300 ) * scale )
			p:SetAirResistance( math.Rand( 70, 130 ) )
			p:SetGravity( Vector( 0, 0, -520 ) )
			p:SetDieTime( math.Rand( 2.5, 5 ) )
			p:SetStartAlpha( math.Rand( 200, 245 ) )
			p:SetEndAlpha( 0 )
			p:SetStartSize( math.Rand( 50, 90 ) * scale )
			p:SetEndSize( math.Rand( 260, 480 ) * scale )
			p:SetRoll( math.Rand( 0, 360 ) )
			p:SetRollDelta( math.Rand( -0.8, 0.8 ) )
			local k = math.Rand( 0.75, 1.15 )
			p:SetColor( EARTH.r * k, EARTH.g * k, EARTH.b * k )
			p:SetLighting( false )
		end
	end

	-- clods and stones that fall back and bounce
	for _ = 1, FX.Count( 40 ) do
		local p = em:Add( "effects/fleck_cement" .. math.random( 1, 2 ), pos + VectorRand() * 20 + up * 20 )

		if p then
			p:SetVelocity( FX.Cone( up, 1.1 ) * math.Rand( 500, 2000 ) * scale )
			p:SetGravity( Vector( 0, 0, -800 ) )
			p:SetAirResistance( 15 )
			p:SetDieTime( math.Rand( 3, 6 ) )
			p:SetStartAlpha( 255 )
			p:SetEndAlpha( 255 )
			local s = math.Rand( 5, 16 )
			p:SetStartSize( s )
			p:SetEndSize( s )
			p:SetRoll( math.Rand( 0, 360 ) )
			p:SetRollDelta( math.Rand( -8, 8 ) )
			p:SetColor( 60, 50, 40 )
			p:SetCollide( true )
			p:SetBounce( 0.25 )
		end
	end

	-- blast wave: a fast flat ring of dust
	for _ = 1, FX.Count( 26 ) do
		local a = math.Rand( 0, math.pi * 2 )
		local out = Vector( math.cos( a ), math.sin( a ), 0 )
		local p = em:Add( FX.Smoke(), pos + out * 60 + up * 25 )

		if p then
			p:SetVelocity( out * math.Rand( 1400, 2400 ) * scale + up * math.Rand( 30, 150 ) )
			p:SetAirResistance( 280 )
			p:SetGravity( Vector( 0, 0, -20 ) )
			p:SetDieTime( math.Rand( 3, 6 ) )
			p:SetStartAlpha( math.Rand( 110, 170 ) )
			p:SetEndAlpha( 0 )
			p:SetStartSize( math.Rand( 60, 100 ) )
			p:SetEndSize( math.Rand( 300, 520 ) * scale )
			p:SetRoll( math.Rand( 0, 360 ) )
			p:SetRollDelta( math.Rand( -0.5, 0.5 ) )
			p:SetColor( DUST.r, DUST.g, DUST.b )
			p:SetLighting( false )
		end
	end

	-- sparks of the burst itself
	for _ = 1, FX.Count( 20 ) do
		local p = em:Add( "effects/spark", pos + up * 30 )

		if p then
			p:SetVelocity( FX.Cone( up, 1.3 ) * math.Rand( 900, 2600 ) )
			p:SetGravity( Vector( 0, 0, -600 ) )
			p:SetDieTime( math.Rand( 0.3, 0.8 ) )
			p:SetStartAlpha( 255 )
			p:SetEndAlpha( 0 )
			p:SetStartSize( math.Rand( 4, 8 ) )
			p:SetEndSize( 0 )
			p:SetStartLength( 40 )
			p:SetEndLength( 120 )
			p:SetColor( 255, 200, 120 )
		end
	end

	local dl = DynamicLight( 0x5C1000 + math.random( 0, 0xFFF ) )

	if dl then
		dl.pos = pos + up * 120
		dl.r, dl.g, dl.b = 255, 160, 70
		dl.brightness = 7
		dl.decay = 5000
		dl.size = 2600 * scale
		dl.dietime = CurTime() + 0.3
	end

	-- the trace only works inside our chunk; outside it this just misses
	if math.abs( pos.x ) < 16000 and math.abs( pos.y ) < 16000 and math.abs( pos.z ) < 16000 then
		util.Decal( "Scorch", pos + up * 60, pos - up * 120 )
	end
end

-- Concussion: a short blur and washed-out colours after a close burst ---------------

local concussion, concussionT = 0, 0

function FX.Concuss( amount )
	concussion = math.max( concussion, amount )
	concussionT = CurTime()
end

hook.Add( "RenderScreenspaceEffects", "SkyOps.Arty.FX", function()
	if concussion <= 0 then return end

	local k = concussion * math.Clamp( 1 - ( CurTime() - concussionT ) / 3, 0, 1 )

	if k <= 0.01 then
		concussion = 0
		return
	end

	DrawMotionBlur( 0.15, 0.8 * k, 0.01 )
	DrawColorModify( {
		[ "$pp_colour_addr" ] = 0.05 * k,
		[ "$pp_colour_addg" ] = 0.04 * k,
		[ "$pp_colour_addb" ] = 0.03 * k,
		[ "$pp_colour_brightness" ] = 0.08 * k,
		[ "$pp_colour_contrast" ] = 1 - 0.15 * k,
		[ "$pp_colour_colour" ] = 1 - 0.6 * k,
		[ "$pp_colour_mulr" ] = 0,
		[ "$pp_colour_mulg" ] = 0,
		[ "$pp_colour_mulb" ] = 0,
	} )
end )

-- Impact ---------------------------------------------------------------------------

local function Scale( shellId )
	local def = FC and FC.GetShell and FC.GetShell( shellId )
	local r = def and def.blast and def.blast.radius

	return r and math.Clamp( r / 15, 0.4, 2 ) or 1
end

-- burst of a shell at an unlocalized world position
function FX.Impact( wpos, shellId )
	if not FX.Enabled() then return end

	local scale = Scale( shellId )
	local pos = FX.ToRender( wpos )
	local d = pos:Distance( FX.ViewPos() )

	FX.AddFlash( pos + Vector( 0, 0, 2 * FX.UPM() ), 14 * scale, 0.22, Color( 255, 200, 130 ) )
	FX.AddColumn( pos, { scale = scale } )

	if d < FX.NEAR_DIST then Burst( pos, scale ) end

	FX.AfterSound( wpos, function( m, rpos )
		if m < 250 then
			FX.PlayAt( rpos, FX.Pick( SND_NEAR ), 140, math.Rand( 80, 95 ), 1 )
			FX.PlayAt( rpos, FX.Pick( SND_BODY ), 140, math.Rand( 60, 75 ), 1 )

			-- earth raining down a moment later
			timer.Simple( math.Rand( 0.8, 1.4 ), function()
				for _ = 1, 3 do
					local snd = FX.Pick( SND_DEBRIS, false )

					if snd then FX.PlayAt( FX.ToRender( wpos ) + VectorRand() * 300, snd, 80, math.Rand( 70, 100 ), FX.Loudness( m, 40, 250 ) * 0.6 ) end
				end
			end )
		elseif m < 2500 then
			FX.PlayAt( rpos, FX.Pick( SND_MID ), 140, math.Rand( 70, 85 ), FX.Loudness( m, 250, 6000 ) )
			FX.PlayAt( rpos, FX.Pick( SND_BODY ), 140, math.Rand( 50, 60 ), FX.Loudness( m, 250, 3000 ) * 0.5 )
		end

		if m >= 1200 then
			-- far away only the low rumble is left
			FX.PlayAt( rpos, FX.Pick( SND_FAR ), 140, math.Rand( 50, 62 ), FX.Loudness( m, 1200, 25000 ) )
		end

		FX.Shake( m, 18 * scale, 350 * scale, 1.4 )

		if m < 45 * scale then FX.Concuss( 1 - m / ( 45 * scale ) ) end
	end )
end
