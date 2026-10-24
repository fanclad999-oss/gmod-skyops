-- Named map anchors -> world position. Map files (lua/skyops/maps/) fill
-- SkyOps.Map.Anchors; on InfMap a position is { chunk = Vector, pos = Vector }.

SkyOps.Map = SkyOps.Map or { Anchors = {} }

function SkyOps.Map.Register( name, data )
	SkyOps.Map.Anchors[ name ] = data
end

-- returns the position to pass to SetPos plus the chunk. InfMap detours
-- SetPos/GetPos to work in "unlocalized" world coordinates, so anchors are
-- converted with InfMap.unlocalize_vector (chunk_size 10000 = 20000 u per chunk).
function SkyOps.Map.Anchor( name )
	local a = SkyOps.Map.Anchors[ name ]
	if not a then return nil end

	if InfMap and a.chunk then
		return InfMap.unlocalize_vector( a.pos, a.chunk ), a.chunk
	end

	return a.pos, a.chunk
end

-- terrain height (world units) at x, y: the Kirovskoe height grid when the map
-- provides it (exact even where no collider is streamed in), else a trace
local function Finite( z )
	return isnumber( z ) and z == z and z > -math.huge and z < math.huge
end

function SkyOps.Map.GroundZ( x, y, fromZ )
	-- the height grid returns -inf outside its edge: fall back to a trace there
	if KIR and KIR.MeshHeight then
		local z = KIR.MeshHeight( x, y )
		if Finite( z ) then return z end
	end

	local tr = util.TraceLine( {
		start = Vector( x, y, ( fromZ or 0 ) + 20000 ),
		endpos = Vector( x, y, ( fromZ or 0 ) - 200000 ),
		-- InfMap terrain is made of infmap_* collider entities, not brushes
		filter = function( e ) return e:IsWorld() or string.StartWith( e:GetClass(), "infmap_" ) end,
	} )
	return tr.Hit and Finite( tr.HitPos.z ) and tr.HitPos.z or nil
end
