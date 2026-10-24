-- Artillery effects, client helpers: settings, the listener, sounds that travel at the
-- speed of sound, particle emitters and billboards that stay visible kilometres away.
--
-- Far billboards: Source drops anything beyond the far clip plane, and a particle
-- emitter far outside the local chunk is not drawn at all. A puff of smoke P at distance
-- d > FAR_DIST is drawn at FAR_DIST along the same line of sight and scaled by
-- FAR_DIST / d, so it covers the same part of the screen as the real one would (FX.Project).
-- It is then drawn in front of hills that are between FAR_DIST and d; on Kirovskoe that is
-- rarely visible from a drone.
--
-- Client convars:
--   skyops_arty_fx          1   effects on/off
--   skyops_arty_fx_quality  1   0 low, 1 normal, 2 high (particle counts)
--   skyops_arty_fx_column   45  s a shell's smoke column stays (for spotting from a drone)
--   skyops_arty_fx_volume   1   volume of artillery sounds
--   skyops_arty_fx_trail    0   1 = draw the flight path of shells (for tests)

local FX = SkyOps.Arty.FX
local Grid = SkyOps.Arty.Grid

FX.cvOn = CreateClientConVar( "skyops_arty_fx", "1", true, false, "Эффекты артиллерии: 1 вкл, 0 выкл", 0, 1 )
FX.cvQuality = CreateClientConVar( "skyops_arty_fx_quality", "1", true, false, "Качество эффектов артиллерии: 0 низкое, 1 обычное, 2 высокое", 0, 2 )
FX.cvColumn = CreateClientConVar( "skyops_arty_fx_column", "45", true, false, "Сколько секунд держится столб дыма от разрыва", 5, 300 )
FX.cvVolume = CreateClientConVar( "skyops_arty_fx_volume", "1", true, false, "Громкость звуков артиллерии", 0, 2 )
FX.cvTrail = CreateClientConVar( "skyops_arty_fx_trail", "0", false, false, "Рисовать траекторию снарядов (для тестов)", 0, 1 )

FX.FAR_DIST = 24000 -- u: billboards further than this are pulled in (see above)
FX.NEAR_DIST = 30000 -- u: particle details only closer than this

function FX.Enabled()
	return FX.cvOn:GetBool()
end

function FX.UPM()
	return Grid.UPM()
end

-- particle count scaled by the quality setting
function FX.Count( n )
	local q = FX.cvQuality:GetInt()
	local mul = q <= 0 and 0.4 or ( q >= 2 and 1.6 or 1 )

	return math.max( 1, math.Round( n * mul ) )
end

-- Listener ---------------------------------------------------------------------------

local viewPos, viewAng = Vector( 0, 0, 0 ), Angle( 0, 0, 0 )

hook.Add( "RenderScene", "SkyOps.Arty.FX", function( origin, angles )
	viewPos, viewAng = origin, angles
end )

-- where the camera is (the drone camera when flying a drone), render space
function FX.ViewPos()
	if viewPos:IsZero() then return EyePos() end

	return viewPos
end

function FX.ViewAng()
	return viewAng
end

-- same, as an unlocalized world position (comparable with server positions)
function FX.ViewWorld()
	return FX.ViewPos() + FX.ChunkOrigin()
end

-- Sounds -----------------------------------------------------------------------------

local exists = {}

local function SoundExists( snd )
	if exists[ snd ] == nil then exists[ snd ] = file.Exists( "sound/" .. snd, "GAME" ) end

	return exists[ snd ]
end

-- a random existing sound from a list, else the fallback (an explosion when not given,
-- nothing when false). Looping files are skipped: sound.Play would never stop them.
function FX.Pick( list, fallback )
	local ok = {}

	for _, snd in ipairs( list ) do
		if SoundExists( snd ) and not string.find( snd, "loop", 1, true ) then ok[ #ok + 1 ] = snd end
	end

	if #ok == 0 then
		if fallback == false then return nil end

		return fallback or "ambient/explosions/explode_4.wav"
	end

	return ok[ math.random( #ok ) ]
end

local PROXY_DIST = 1200 -- u: far sounds are played this far away, in the right direction

-- plays a sound coming from a render-space position. Source sounds fade out after a few
-- thousand units, so a far one is played closer, in the same direction, and its loudness
-- is set by volume instead.
function FX.PlayAt( pos, snd, level, pitch, vol )
	vol = math.Clamp( ( vol or 1 ) * FX.cvVolume:GetFloat(), 0, 1 )

	if vol <= 0.01 then return end

	local eye = FX.ViewPos()
	local d = pos:Distance( eye )

	if d > PROXY_DIST then
		pos = eye + ( pos - eye ) * ( PROXY_DIST / d )
		level = math.min( level or 100, 95 )
	end

	sound.Play( snd, pos, level or 100, math.Clamp( math.Round( pitch or 100 ), 1, 255 ), vol )
end

-- loudness 0..1 of a bang heard d metres away; ref = distance where it is still full
function FX.Loudness( d, ref, far )
	if d <= ref then return 1 end
	if d >= far then return 0 end

	-- roughly inverse distance, then down to zero at "far"
	local v = ref / d
	local f = 1 - ( d - ref ) / ( far - ref )

	return math.Clamp( v ^ 0.6 * f ^ 0.5, 0, 1 )
end

-- runs fn( distance_m, renderPos ) when the sound of an event at the unlocalized world
-- position wpos reaches the listener
function FX.AfterSound( wpos, fn )
	local d = wpos:Distance( FX.ViewWorld() ) / FX.UPM()
	local delay = d / FX.SOUND_SPEED

	if delay < 0.05 then return fn( d, FX.ToRender( wpos ) ) end

	timer.Simple( delay, function()
		-- the listener may have moved in the meantime
		local dn = wpos:Distance( FX.ViewWorld() ) / FX.UPM()

		fn( dn, FX.ToRender( wpos ) )
	end )
end

-- Screen shake that fades with distance (metres); radius = where it stops
function FX.Shake( d, amp, radius, dur )
	if d >= radius then return end

	local k = ( 1 - d / radius ) ^ 2

	util.ScreenShake( FX.ViewPos(), amp * k, 30, dur * ( 0.5 + 0.5 * k ), 64 )
end

-- Billboards -------------------------------------------------------------------------

-- render-space centre and size -> where and how big to draw it so it is not clipped.
-- Only while drawing: EyePos() is then the view being drawn, also a drone camera that is
-- rendered into a texture.
function FX.Project( pos, size )
	local eye = EyePos()
	local v = pos - eye
	local d = v:Length()

	if d <= FX.FAR_DIST then return pos, size, d end

	local k = FX.FAR_DIST / d

	return eye + v * k, size * k, d
end

FX.SmokeMats = {}

for i = 1, 9 do
	FX.SmokeMats[ i ] = Material( "particle/smokesprites_000" .. i )
end

FX.GlowMat = Material( "sprites/light_glow02_add" )
FX.FireMat = Material( "effects/fire_cloud1" )

-- a camera-facing quad at a render-space position, kept visible at any distance
function FX.DrawPuff( mat, pos, size, col, roll )
	local p, s = FX.Project( pos, size )

	if s < 0.5 then return end

	render.SetMaterial( mat )
	render.DrawQuadEasy( p, ( EyePos() - p ):GetNormalized(), s, s, col, roll or 0 )
end

-- daylight factor for unlit billboards
local light, nextLight = 1, 0

function FX.Light()
	if CurTime() > nextLight then
		nextLight = CurTime() + 1

		local c = render.GetLightColor( FX.ViewPos() + Vector( 0, 0, 64 ) )

		light = math.Clamp( ( c.x + c.y + c.z ) / 3 * 2.2, 0.45, 1 )
	end

	return light
end

-- Particles --------------------------------------------------------------------------

local emitter

-- one shared emitter, moved to each effect (an emitter only draws particles near itself)
function FX.Emitter( pos )
	if not emitter or not emitter:IsValid() then
		emitter = ParticleEmitter( pos, false )
	end

	if emitter then emitter:SetPos( pos ) end

	return emitter
end

function FX.Smoke()
	return "particle/smokesprites_000" .. math.random( 1, 9 )
end

-- unit vector in a cone of half-angle "spread" (radians) around dir
function FX.Cone( dir, spread )
	local ang = dir:Angle()
	local a = math.Rand( 0, math.pi * 2 )
	local r = math.Rand( 0, math.sin( spread ) )
	local v = ang:Forward() * math.cos( math.asin( r ) ) + ang:Right() * ( math.cos( a ) * r ) + ang:Up() * ( math.sin( a ) * r )

	return v
end

-- ground height (render space) under a render-space point, or the point's own z
function FX.GroundAt( pos )
	local wpos = pos + FX.ChunkOrigin()
	local z = Grid.GroundZ and Grid.GroundZ( wpos.x, wpos.y )

	if z then return z - FX.ChunkOrigin().z end

	local tr = util.TraceLine( { start = pos + Vector( 0, 0, 200 ), endpos = pos - Vector( 0, 0, 2000 ), mask = MASK_SOLID_BRUSHONLY } )

	return tr.Hit and tr.HitPos.z or pos.z
end

-- Wind that carries smoke columns, world units/s: the real wind of arty/core (sh_wind)
-- when it blows, else one direction for the session, slowly turning, 3 m/s
local windYaw = math.Rand( 0, 360 )

function FX.Wind()
	local W = SkyOps.Arty.Wind
	local w = W and W.Actual and W.Actual()

	if w and Grid.Origin then
		local o = Grid.Origin

		return Grid.FromGrid( o + w.x, o + w.y, 0 ) - Grid.FromGrid( o, o, 0 )
	end

	local yaw = windYaw + math.sin( CurTime() / 120 ) * 25

	return Angle( 0, yaw, 0 ):Forward() * ( 3 * FX.UPM() ) -- 3 m/s
end
