-- Artillery coordinate grid. Grid coordinates are metres: X to the east, Y to the north,
-- shifted so the whole map is positive. Heights are metres above world z = 0.
-- World positions are InfMap "unlocalized" positions (what GetPos() returns there).

SkyOps.Arty = SkyOps.Arty or {}
SkyOps.Arty.Grid = SkyOps.Arty.Grid or {}

local G = SkyOps.Arty.Grid

G.SquareSize = 1000
G.Origin = 50000 -- m added to both axes, so a 100 x 100 km map stays positive

local MILS = 6000

-- units per metre: Kirovskoe is built at 40 u/m (KIR.S), plain Source maps at 52.49
function G.UPM()
	return ( KIR and KIR.S ) or SkyOps.M_TO_HU or 52.49
end

-- yaw that looks north; Source default (and Kirovskoe) is +Y = yaw 90
local function NorthYaw()
	local maps = SkyOps.Maps
	local kir = maps and maps.kirovskoe

	return ( kir and kir.north_yaw ) or 90
end

-- unit vectors of north and east in world XY
local function Axes()
	local ny = math.rad( NorthYaw() )

	return math.cos( ny ), math.sin( ny ), math.sin( ny ), -math.cos( ny )
end

local function Finite( z )
	return isnumber( z ) and z == z and z > -math.huge and z < math.huge
end

-- terrain height in world units at world x, y, or nil
function G.GroundZ( wx, wy )
	-- the Kirovskoe height grid is exact even where no terrain collider is streamed in;
	-- outside its edge it returns -inf
	if KIR and KIR.MeshHeight then
		local z = KIR.MeshHeight( wx, wy )

		if Finite( z ) then return z end

		return nil
	end

	-- other maps: a trace works as long as the point is inside the loaded map
	local tr = util.TraceLine( {
		start = Vector( wx, wy, 30000 ),
		endpos = Vector( wx, wy, -30000 ),
		mask = MASK_SOLID_BRUSHONLY,
	} )

	if tr.Hit and not tr.StartSolid and Finite( tr.HitPos.z ) then return tr.HitPos.z end
end

function G.ToGrid( pos )
	local nx, ny, ex, ey = Axes()
	local upm = G.UPM()

	return ( pos.x * ex + pos.y * ey ) / upm + G.Origin, ( pos.x * nx + pos.y * ny ) / upm + G.Origin
end

-- h_m (optional): height in metres; without it Z follows the terrain (0 off the map)
function G.FromGrid( x, y, h )
	local nx, ny, ex, ey = Axes()
	local upm = G.UPM()
	local e, n = ( x - G.Origin ) * upm, ( y - G.Origin ) * upm
	local pos = Vector( e * ex + n * nx, e * ey + n * ny, 0 )

	if h then
		pos.z = h * upm
	else
		pos.z = G.GroundZ( pos.x, pos.y ) or 0
	end

	return pos
end

-- terrain height in metres at grid x, y, or nil off the map
function G.Height( x, y )
	local p = G.FromGrid( x, y, 0 )
	local z = G.GroundZ( p.x, p.y )

	return z and z / G.UPM() or nil
end

-- world position -> x, y, h in metres
function G.ToGrid3( pos )
	local x, y = G.ToGrid( pos )

	return x, y, pos.z / G.UPM()
end

-- Directions --------------------------------------------------------------------

-- Source yaw (degrees, counter-clockwise from +X) -> bearing in mils (from north, clockwise)
function G.YawToMils( yaw )
	return ( ( NorthYaw() - yaw ) % 360 ) / 360 * MILS
end

function G.MilsToYaw( mils )
	return NorthYaw() - mils / MILS * 360
end

-- bearing in mils from grid point 1 to grid point 2
function G.Bearing( x1, y1, x2, y2 )
	return ( math.deg( math.atan2( x2 - x1, y2 - y1 ) ) % 360 ) / 360 * MILS
end

-- world direction for a bearing and an elevation (both mils)
function G.Direction( bearing, elevation )
	local yaw = math.rad( G.MilsToYaw( bearing ) )
	local el = elevation / MILS * 2 * math.pi
	local c = math.cos( el )

	return Vector( math.cos( yaw ) * c, math.sin( yaw ) * c, math.sin( el ) )
end

-- Squares --------------------------------------------------------------------------

-- 1 km square with a "snail" ninth: 1 2 3 / 8 9 4 / 7 6 5
local SNAIL = { [0] = { 7, 6, 5 }, [1] = { 8, 9, 4 }, [2] = { 1, 2, 3 } }

function G.Square( x, y )
	local s = G.SquareSize
	local sx, sy = math.floor( x / s ), math.floor( y / s )
	local fx = math.Clamp( math.floor( ( x - sx * s ) / s * 3 ), 0, 2 )
	local fy = math.Clamp( math.floor( ( y - sy * s ) / s * 3 ), 0, 2 )

	return string.format( "%02d-%02d", sy % 100, sx % 100 ), SNAIL[ fy ][ fx + 1 ]
end

-- "кв. 63-41 ул. 9 (X 41520 Y 63480)"
function G.Format( x, y )
	local sq, snail = G.Square( x, y )

	return string.format( "кв. %s ул. %d (X %05d Y %05d)", sq, snail, math.Round( x ), math.Round( y ) )
end

-- Bounds ---------------------------------------------------------------------------

local BoundsCache

-- grid rectangle covered by terrain; scanned once from the height grid at 1 km steps
function G.Bounds()
	if BoundsCache then return unpack( BoundsCache ) end

	local minX, minY, maxX, maxY

	if KIR and KIR.MeshHeight then
		local s = G.SquareSize

		for x = 0, 2 * G.Origin, s do
			for y = 0, 2 * G.Origin, s do
				if G.Height( x, y ) then
					minX, maxX = math.min( minX or x, x ), math.max( maxX or x, x )
					minY, maxY = math.min( minY or y, y ), math.max( maxY or y, y )
				end
			end
		end
	end

	if not minX then
		-- plain map: the brush world extent
		local wmin, wmax = game.GetWorld():GetModelBounds()
		local ax, ay = G.ToGrid( wmin )
		local bx, by = G.ToGrid( wmax )

		minX, maxX = math.min( ax, bx ), math.max( ax, bx )
		minY, maxY = math.min( ay, by ), math.max( ay, by )
	end

	BoundsCache = { minX, minY, maxX, maxY }

	return minX, minY, maxX, maxY
end
