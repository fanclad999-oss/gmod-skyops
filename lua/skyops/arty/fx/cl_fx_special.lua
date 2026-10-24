-- Artillery effects: shells that do not burst like HE (FC.Shells[ id ].effect).
--   smoke    a white screen at the point of fall, growing and drifting with the wind
--   illum    a flare that opens burstHeight m over the point and sinks under its chute
--   cluster  the case opens over the point, then bomblets crack around it; the bomblet
--            spots come from FC.BombletPattern with the shell's net id, as on the server
-- FX.Impact is wrapped: the other shells keep the HE burst of cl_fx_impact.

local FX = SkyOps.Arty.FX
local FC = SkyOps.Arty.FireComp
local Grid = SkyOps.Arty.Grid

local SMOKE_LIFE = 90 -- s
local SMOKE_WIDTH = 70 -- m across when fully grown
local FLARE_LIFE = 60 -- s
local FLARE_SINK = 5 -- m/s
local MAX_SCREENS = 8

local SMOKE_COL = Color( 225, 225, 220 )
local FLARE_COL = Color( 255, 245, 215 )

local SND_POP = { "weapons/flaregun/fire.wav", "weapons/ar2/ar2_altfire.wav" }
local SND_SMOKE = { "weapons/smokegrenade/sg_explode.wav", "ambient/fire/ignite.wav" }
local SND_BOMBLET = { "weapons/explode3.wav", "weapons/explode4.wav", "weapons/explode5.wav" }

local screens = {} -- smoke screens: { wpos, t0, puffs }
local flares = {} -- { wpos (start, unlocalized), t0 }

-- Smoke ----------------------------------------------------------------------------

local function Smoke( wpos )
	local s = { wpos = wpos, t0 = CurTime(), puffs = {} }

	for i = 1, FX.Count( 14 ) do
		s.puffs[ i ] = {
			ox = math.Rand( -1, 1 ), oy = math.Rand( -1, 1 ), f = math.Rand( 0, 1 ),
			size = math.Rand( 0.7, 1.3 ), mat = math.random( #FX.SmokeMats ), roll = math.Rand( 0, 360 ),
		}
	end

	screens[ #screens + 1 ] = s

	if #screens > MAX_SCREENS then table.remove( screens, 1 ) end

	FX.AddFlash( FX.ToRender( wpos ) + Vector( 0, 0, FX.UPM() ), 5, 0.15, Color( 255, 230, 190 ) )

	FX.AfterSound( wpos, function( m, rpos )
		local snd = FX.Pick( SND_SMOKE, false )

		if snd and m < 3000 then FX.PlayAt( rpos, snd, 110, math.Rand( 70, 90 ), FX.Loudness( m, 100, 3000 ) ) end
	end )
end

local function DrawSmoke( s, now, light )
	local t = now - s.t0

	if t > SMOKE_LIFE then return false end

	local upm = FX.UPM()
	local grow = 1 - math.exp( -t / 6 ) -- spreads in the first half minute
	local fade = math.Clamp( t / 0.5, 0, 1 ) * math.Clamp( ( SMOKE_LIFE - t ) / 25, 0, 1 )
	local base = FX.ToRender( s.wpos )
	local wind = FX.Wind() * math.min( t, 40 ) * 0.6
	local half = SMOKE_WIDTH * 0.5 * upm * ( 0.25 + grow * 0.75 )

	for _, p in ipairs( s.puffs ) do
		-- the downwind side drifts furthest, so the screen stretches along the wind
		local pos = base + Vector( p.ox * half, p.oy * half, ( 4 + p.f * 14 * grow ) * upm ) + wind * ( 0.4 + p.f * 0.6 )
		local size = ( 12 + 22 * grow ) * upm * p.size
		local k = light

		FX.DrawPuff( FX.SmokeMats[ p.mat ], pos, size, Color( SMOKE_COL.r * k, SMOKE_COL.g * k, SMOKE_COL.b * k, 235 * fade ), p.roll + t * 2 )
	end

	return true
end

-- Illumination -------------------------------------------------------------------------

local function Flare( wpos, def )
	local up = Vector( 0, 0, ( def.burstHeight or 450 ) * FX.UPM() )

	flares[ #flares + 1 ] = { wpos = wpos + up, t0 = CurTime() }

	FX.AddFlash( FX.ToRender( wpos + up ), 12, 0.2, FLARE_COL )

	FX.AfterSound( wpos + up, function( m, rpos )
		local snd = FX.Pick( SND_POP, false )

		if snd and m < 4000 then FX.PlayAt( rpos, snd, 110, 60, FX.Loudness( m, 200, 4000 ) ) end
	end )
end

local function FlarePos( f, now )
	local t = now - f.t0

	return f.wpos - Vector( 0, 0, FLARE_SINK * t * FX.UPM() ) + FX.Wind() * t, t
end

local function DrawFlare( f, now )
	local wpos, t = FlarePos( f, now )

	if t > FLARE_LIFE then return false end

	local pos = FX.ToRender( wpos )
	local flicker = 0.85 + math.sin( now * 23 + f.t0 ) * 0.08 + math.Rand( -0.05, 0.05 )
	local fade = math.Clamp( ( FLARE_LIFE - t ) / 6, 0, 1 ) * math.Clamp( t / 0.4, 0, 1 )
	local size = 60 * FX.UPM() * flicker

	FX.DrawPuff( FX.GlowMat, pos, size, Color( FLARE_COL.r, FLARE_COL.g, FLARE_COL.b, 255 * fade ), 0 )
	FX.DrawPuff( FX.GlowMat, pos, size * 0.35, Color( 255, 255, 255, 255 * fade ), 0 )

	return true
end

hook.Add( "Think", "SkyOps.Arty.FX.Flares", function()
	if #flares == 0 then return end

	local now = CurTime()
	local upm = FX.UPM()

	for i, f in ipairs( flares ) do
		local wpos, t = FlarePos( f, now )

		if t <= FLARE_LIFE then
			-- the light only reaches what is drawn near the camera, which is what matters
			local dl = DynamicLight( 41000 + i )

			if dl then
				local fade = math.Clamp( ( FLARE_LIFE - t ) / 6, 0, 1 )

				dl.pos = FX.ToRender( wpos )
				dl.r, dl.g, dl.b = FLARE_COL.r, FLARE_COL.g, FLARE_COL.b
				dl.brightness = 4 * fade
				dl.size = 900 * upm
				dl.decay = 0
				dl.dietime = now + 0.2
			end
		end
	end
end )

-- Cluster ---------------------------------------------------------------------------

local function Cluster( wpos, def, netId )
	local b = def.bomblets
	local upm = FX.UPM()
	local up = Vector( 0, 0, ( def.burstHeight or 200 ) * upm )

	-- the case opening: a small flash and a puff high over the point
	FX.AddFlash( FX.ToRender( wpos + up ), 6, 0.15, Color( 255, 210, 150 ) )
	FX.AddColumn( FX.ToRender( wpos + up ), { small = true, life = 12 } )

	FX.AfterSound( wpos + up, function( m, rpos )
		if m < 6000 then FX.PlayAt( rpos, "ambient/explosions/explode_4.wav", 120, 150, FX.Loudness( m, 300, 6000 ) * 0.6 ) end
	end )

	if not b then return end

	local gx, gy = Grid.ToGrid( wpos )

	for i, o in ipairs( FC.BombletPattern( netId or 0, b.count, b.radius ) ) do
		local bx, by = gx + o[ 1 ], gy + o[ 2 ]
		local bz = Grid.Height( bx, by )
		local bpos = bz and Grid.FromGrid( bx, by, bz ) or ( wpos + Vector( o[ 1 ], o[ 2 ], 0 ) * upm )

		-- the server bursts it after o[ 3 ] s; the bomblets fall the last 200 m first
		timer.Simple( o[ 3 ], function()
			if not FX.Enabled() then return end

			local rpos = FX.ToRender( bpos )

			FX.AddFlash( rpos + Vector( 0, 0, upm ), 5, 0.12, Color( 255, 200, 130 ) )

			-- a few short columns, not one per bomblet (columns are shared with HE)
			if i % 4 == 1 then FX.AddColumn( rpos, { scale = 0.3, life = 25 } ) end

			if i % 3 == 1 then
				FX.AfterSound( bpos, function( m, sp )
					local snd = FX.Pick( SND_BOMBLET, "ambient/explosions/explode_4.wav" )

					if m < 5000 then FX.PlayAt( sp, snd, 120, math.Rand( 95, 125 ), FX.Loudness( m, 100, 5000 ) * 0.7 ) end
				end )
			end
		end )
	end
end

-- Hooks ----------------------------------------------------------------------------

local Special = { smoke = Smoke, illum = Flare, cluster = Cluster }

local BaseImpact = FX.Impact

function FX.Impact( wpos, shellId, netId )
	local def = FC and FC.GetShell( shellId )
	local fn = def and Special[ def.effect ]

	if not fn then return BaseImpact( wpos, shellId ) end
	if not FX.Enabled() then return end

	fn( wpos, def, netId )
end

hook.Add( "PostDrawTranslucentRenderables", "SkyOps.Arty.FX.Special", function( depth, sky, sky3d )
	if depth or sky or sky3d then return end
	if #screens == 0 and #flares == 0 then return end

	local now = CurTime()
	local light = FX.Light()

	for i = #screens, 1, -1 do
		if not DrawSmoke( screens[ i ], now, light ) then table.remove( screens, i ) end
	end

	for i = #flares, 1, -1 do
		if not DrawFlare( flares[ i ], now ) then table.remove( flares, i ) end
	end
end )
