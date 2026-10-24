-- Shared detection model for SAM radars, AI pilots and the radar warning.

SkyOps.Radar = SkyOps.Radar or {}

local HU_TO_M = SkyOps.HU_TO_M

-- radar horizon: d(m) = 4120 * (sqrt(h_radar) + sqrt(h_target)), heights in m
function SkyOps.Radar.InHorizon( radarPos, mast, targetPos, range )
	local dist = radarPos:Distance( targetPos ) * HU_TO_M
	if dist > range then return false end

	local hTarget = math.max( 0, ( targetPos.z - radarPos.z ) * HU_TO_M )
	return dist <= 4120 * ( math.sqrt( mast ) + math.sqrt( hTarget ) )
end

-- terrain-only line of sight: vehicles and props never block a radar beam
local function TerrainOnly( ent )
	if ent:IsWorld() then return true end
	return string.StartWith( ent:GetClass(), "infmap_" )
end

local STEP_M = 100        -- height-grid sample spacing along the beam
local MAX_STEPS = 600
local CLEARANCE_M = 3

-- On InfMap a trace is clipped to the start chunk and runs into the real map
-- bounds after ~16000 u (that capped SAM detection at ~500 m), and far terrain
-- colliders are not streamed in. With the Kirovskoe height grid the beam is
-- marched over the terrain instead.
function SkyOps.Radar.LineOfSight( fromPos, target )
	local toPos = isvector( target ) and target or target:WorldSpaceCenter()

	if KIR and KIR.MeshHeight then
		local dist = fromPos:Distance( toPos )
		local steps = math.Clamp( math.ceil( dist * HU_TO_M / STEP_M ), 1, MAX_STEPS )
		local clearance = CLEARANCE_M * SkyOps.M_TO_HU
		for i = 1, steps - 1 do
			local p = LerpVector( i / steps, fromPos, toPos )
			local ground = KIR.MeshHeight( p.x, p.y )
			if ground and p.z < ground + clearance then return false end
		end
		return true
	end

	-- other InfMaps: traces only work inside one chunk, trust the horizon beyond
	if InfMap and fromPos:Distance( toPos ) > 10000 then return true end

	local tr = util.TraceLine( {
		start = fromPos,
		endpos = toPos,
		filter = TerrainOnly,
	} )
	return not tr.Hit
end

function SkyOps.Radar.IsAircraft( ent )
	if not ( IsValid( ent ) and ent.LVS and isfunction( ent.GetVehicleType ) ) then return false end
	local t = ent:GetVehicleType()
	return t == "plane" or t == "helicopter"
end

-- enemy aircraft with engine running inside range (m) and radar horizon
function SkyOps.Radar.FindTargets( pos, team, range, mast )
	local found = {}
	for _, veh in pairs( LVS:GetVehicles() ) do
		if not SkyOps.Radar.IsAircraft( veh ) or veh:IsDestroyed() then continue end
		if isfunction( veh.GetEngineActive ) and not veh:GetEngineActive() then continue end
		if veh:GetAITEAM() == team then continue end

		local vpos = veh:GetPos()
		if SkyOps.Radar.InHorizon( pos, mast or 5, vpos, range ) then
			found[ #found + 1 ] = { ent = veh, dist = pos:Distance( vpos ) * HU_TO_M }
		end
	end
	table.SortByMember( found, "dist", true )
	return found
end
