-- Named map anchors -> world position. Map files (lua/skyops/maps/) fill
-- SkyOps.Map.Anchors; on InfMap a position is { chunk = Vector, pos = Vector }.

SkyOps.Map = SkyOps.Map or { Anchors = {} }

function SkyOps.Map.Register( name, data )
	SkyOps.Map.Anchors[ name ] = data
end

-- returns the position to pass to SetPos (InfMap detours SetPos to take
-- "infinite" coordinates), plus the chunk. TODO: verify chunk math in step 0.
function SkyOps.Map.Anchor( name )
	local a = SkyOps.Map.Anchors[ name ]
	if not a then return nil end

	if InfMap and a.chunk and InfMap.chunk_size then
		return a.pos + a.chunk * InfMap.chunk_size * 2, a.chunk
	end

	return a.pos, a.chunk
end
