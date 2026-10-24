-- Artillery effects, shared part: net names and how positions travel between server and
-- client on InfMap.
--
-- The server sends "unlocalized" world positions (what GetPos() returns there). On the
-- client InfMap renders everything relative to the local player's chunk, and the client
-- GetPos() of an entity is already in that space; a server position has to be shifted by
-- the local player's chunk before it is drawn or a sound is played at it (FX.ToRender).
-- Vectors go as three floats: net.WriteVector is limited to +-16384 per axis, while a
-- position 20 km away is 800000 units.
--
-- net server -> client:
--   skyops_arty_fx_shot   { UInt16 shell id, String shell, Entity spg (NULL when not fired
--                           by a 2S35), Pos muzzle, Pos dir (unit), Float timescale,
--                           Float x, y, z, vx, vy, vz (grid m, m/s) }
--   skyops_arty_fx_state  { UInt16 shell id, Float x, y, z, vx, vy, vz }  correction for a
--                           shell in flight (guided shells turn, the client copy would drift)
--   skyops_arty_fx_impact { UInt16 shell id, String shell, Pos pos }

SkyOps.Arty = SkyOps.Arty or {}
SkyOps.Arty.FX = SkyOps.Arty.FX or {}

local FX = SkyOps.Arty.FX

FX.SOUND_SPEED = 343 -- m/s

function FX.WritePos( v )
	net.WriteFloat( v.x )
	net.WriteFloat( v.y )
	net.WriteFloat( v.z )
end

function FX.ReadPos()
	return Vector( net.ReadFloat(), net.ReadFloat(), net.ReadFloat() )
end

function FX.WriteState( s )
	net.WriteFloat( s.x )
	net.WriteFloat( s.y )
	net.WriteFloat( s.z )
	net.WriteFloat( s.vx )
	net.WriteFloat( s.vy )
	net.WriteFloat( s.vz )
end

function FX.ReadState( s )
	s = s or {}
	s.x, s.y, s.z = net.ReadFloat(), net.ReadFloat(), net.ReadFloat()
	s.vx, s.vy, s.vz = net.ReadFloat(), net.ReadFloat(), net.ReadFloat()

	return s
end

if SERVER then return end

-- origin of the local player's chunk in unlocalized world units
function FX.ChunkOrigin()
	local ply = LocalPlayer()

	if not InfMap or not IsValid( ply ) or not ply.CHUNK_OFFSET then return Vector( 0, 0, 0 ) end

	return InfMap.unlocalize_vector( Vector( 0, 0, 0 ), ply.CHUNK_OFFSET )
end

-- server (unlocalized) world position -> position to draw at / play a sound at
function FX.ToRender( pos )
	return pos - FX.ChunkOrigin()
end
