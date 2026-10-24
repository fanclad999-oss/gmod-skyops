-- Artillery fire computer: shells and charges, the shell flight model and the solver
-- that turns gun and target grid coordinates into deflection and elevation.
-- sv_ballistics flies real shells with the same FireComp.Step, so a laid solution
-- lands on the target up to dispersion.
--
-- Flight model: point mass, gravity 9.81 m/s^2, quadratic drag a = -k * rho(h) * |v| * v
-- with an exponential atmosphere. No wind, no Earth curvature (InfMap is flat).
-- k is tuned so that HE on the full charge reaches about 37 km, as a 2A88 does.

SkyOps.Arty = SkyOps.Arty or {}
SkyOps.Arty.FireComp = SkyOps.Arty.FireComp or {}

local FC = SkyOps.Arty.FireComp
-- sh_grid loads after this file (alphabetical order) and fills the same table
SkyOps.Arty.Grid = SkyOps.Arty.Grid or {}

local Grid = SkyOps.Arty.Grid

FC.MILS = 6000
FC.G = 9.81
FC.DT = 0.05 -- s, integration step for both the solver and live shells
FC.MUZZLE_H = 2.5 -- m, muzzle height above the hull origin, used by the solver
FC.MIN_ELEV = -5 -- deg, barrel limits of the 2S35 (TurretPitchMax 5, TurretPitchMin -75)
FC.MAX_ELEV = 75

local SCALE_HEIGHT = 10400 -- m

-- Shells ---------------------------------------------------------------------------

-- charges: v0 in m/s. blast: radii in metres for the explosion at impact.
-- dispersion: 1 sigma of muzzle velocity (fraction) and of the barrel direction (mils).
FC.Shells = {
	he = {
		name = "ОФС",
		k = 4.2e-5,
		stockType = 0, -- DT ShellType of sw_2s35
		charges = {
			{ id = 1, name = "Полный", v0 = 945 },
			{ id = 2, name = "Уменьшенный", v0 = 800 },
			{ id = 3, name = "Первый", v0 = 650 },
			{ id = 4, name = "Второй", v0 = 500 },
			{ id = 5, name = "Третий", v0 = 380 },
			{ id = 6, name = "Четвёртый", v0 = 290 },
		},
		blast = { radius = 15, blastRadius = 30, fragRadius = 50, damage = 15000, fragDamage = 40, fragCount = 120 },
		dispersion = { v0 = 0.0012, mils = 0.4 },
	},
	krasnopol = {
		name = "Краснополь",
		k = 5.5e-5, -- fins and a heavier body: shorter reach than HE
		stockType = 1,
		guided = true, -- the drone module (sv_guided) steers it
		charges = {
			{ id = 2, name = "Уменьшенный", v0 = 800 },
			{ id = 3, name = "Первый", v0 = 650 },
			{ id = 4, name = "Второй", v0 = 500 },
			{ id = 5, name = "Третий", v0 = 380 },
		},
		blast = { radius = 12, blastRadius = 25, fragRadius = 40, damage = 15000, fragDamage = 40, fragCount = 100 },
		dispersion = { v0 = 0.0012, mils = 0.4 },
	},
}

function FC.GetShell( id )
	return FC.Shells[ id or "he" ]
end

function FC.GetCharge( shellId, chargeId )
	local shell = FC.GetShell( shellId )

	if not shell then return nil end

	for _, c in ipairs( shell.charges ) do
		if c.id == chargeId then return c end
	end
end

-- shell id for the 2S35 DT ShellType
function FC.ShellForStockType( t )
	for id, s in pairs( FC.Shells ) do
		if s.stockType == t then return id end
	end

	return "he"
end

-- Flight model ---------------------------------------------------------------------

local exp, sqrt, max = math.exp, math.sqrt, math.max

-- One midpoint step of a shell state s = { x, y, z, vx, vy, vz } (metres, m/s, z up).
-- ax, ay, az: extra acceleration for this step (guidance), may be nil.
function FC.Step( s, k, dt, ax, ay, az )
	ax, ay, az = ax or 0, ay or 0, az or 0

	local g = FC.G
	local vx, vy, vz = s.vx, s.vy, s.vz

	local r = k * exp( -max( s.z, 0 ) / SCALE_HEIGHT ) * sqrt( vx * vx + vy * vy + vz * vz )
	local mx = vx + ( ax - r * vx ) * dt * 0.5
	local my = vy + ( ay - r * vy ) * dt * 0.5
	local mz = vz + ( az - g - r * vz ) * dt * 0.5

	local rm = k * exp( -max( s.z + vz * dt * 0.5, 0 ) / SCALE_HEIGHT ) * sqrt( mx * mx + my * my + mz * mz )

	s.x = s.x + mx * dt
	s.y = s.y + my * dt
	s.z = s.z + mz * dt
	s.vx = vx + ( ax - rm * mx ) * dt
	s.vy = vy + ( ay - rm * my ) * dt
	s.vz = vz + ( az - g - rm * mz ) * dt
end

local MAX_TIME = 400

-- Flies in the vertical plane from the muzzle at height z0 (m, sets the air density) at
-- theta (deg) until the descending branch is dh below/above the muzzle. Returns range,
-- time of flight, apex (m above the muzzle), or nil when the shell never gets back down
-- to dh from above.
function FC.Fly( theta, v0, k, dh, z0 )
	z0 = z0 or 0
	dh = dh + z0

	local th = math.rad( theta )
	local s = { x = 0, y = 0, z = z0, vx = v0 * math.cos( th ), vy = 0, vz = v0 * math.sin( th ) }
	local dt = FC.DT
	local t, apex = 0, z0
	local step = FC.Step

	while t < MAX_TIME do
		local px, pz = s.x, s.z

		step( s, k, dt )
		t = t + dt

		if s.z > apex then apex = s.z end

		if s.vz < 0 and s.z <= dh then
			if apex < dh then return nil end

			local f = ( pz - dh ) / max( pz - s.z, 1e-9 )

			return px + ( s.x - px ) * f, t - dt + dt * f, apex - z0
		end
	end
end

-- Solver ---------------------------------------------------------------------------

local function Range( theta, v0, k, dh, z0 )
	return FC.Fly( theta, v0, k, dh, z0 ) or -1
end

-- longest range (m) and its elevation (deg) for this charge, height difference to the
-- target dh and muzzle height z0 (m)
local MaxCache = {}

function FC.MaxRange( shellId, chargeId, dh, z0 )
	local shell, charge = FC.GetShell( shellId ), FC.GetCharge( shellId, chargeId )

	if not charge then return nil end

	dh = math.Round( dh or 0 )
	z0 = math.Round( z0 or 0, -1 )

	local key = shellId .. "/" .. chargeId .. "/" .. dh .. "/" .. z0

	if MaxCache[ key ] then return unpack( MaxCache[ key ] ) end

	-- golden section: range is unimodal in elevation
	local a, b = 15, FC.MAX_ELEV
	local gr = ( math.sqrt( 5 ) - 1 ) / 2
	local c, d = b - gr * ( b - a ), a + gr * ( b - a )
	local fc, fd = Range( c, charge.v0, shell.k, dh, z0 ), Range( d, charge.v0, shell.k, dh, z0 )

	for _ = 1, 28 do
		if fc > fd then
			b, d, fd = d, c, fc
			c = b - gr * ( b - a )
			fc = Range( c, charge.v0, shell.k, dh, z0 )
		else
			a, c, fc = c, d, fd
			d = a + gr * ( b - a )
			fd = Range( d, charge.v0, shell.k, dh, z0 )
		end
	end

	local theta = ( a + b ) / 2
	local r = Range( theta, charge.v0, shell.k, dh, z0 )

	if table.Count( MaxCache ) > 500 then MaxCache = {} end

	MaxCache[ key ] = { r, theta }

	return r, theta
end

local ChargeCache = {}

-- { {id, name, v0, min, max, minHigh}, ... }: ranges in metres for a target level with
-- the muzzle. min..max is the low-angle group, minHigh..max the high-angle group.
function FC.Charges( shellId )
	shellId = shellId or "he"

	if ChargeCache[ shellId ] then return ChargeCache[ shellId ] end

	local shell = FC.GetShell( shellId )

	if not shell then return {} end

	local list = {}

	for _, c in ipairs( shell.charges ) do
		local maxR = FC.MaxRange( shellId, c.id, 0 )

		list[ #list + 1 ] = {
			id = c.id, name = c.name, v0 = c.v0,
			min = 0, max = maxR,
			minHigh = math.max( Range( FC.MAX_ELEV, c.v0, shell.k, 0 ), 0 ),
		}
	end

	ChargeCache[ shellId ] = list

	return list
end

-- weakest charge that still reaches range (m) with a margin, or the strongest one
function FC.BestCharge( shellId, range, dh, z0 )
	local shell = FC.GetShell( shellId )

	if not shell then return nil end

	for i = #shell.charges, 1, -1 do
		local c = shell.charges[ i ]
		local maxR = FC.MaxRange( shellId, c.id, dh or 0, z0 )

		if maxR and maxR >= range * 1.05 then return c.id end
	end

	return shell.charges[ 1 ].id
end

local function Deflection( bearing, basedir )
	return ( FC.MILS / 2 + ( basedir or 0 ) - bearing ) % FC.MILS
end

FC.Deflection = Deflection

-- signed difference a - b in mils, -3000..3000
function FC.MilsDiff( a, b )
	return ( a - b + FC.MILS / 2 ) % FC.MILS - FC.MILS / 2
end

local function DegToMils( d ) return d / 360 * FC.MILS end

local SolveCache = {}

-- q = { gun = {x, y, h}, target = {x, y, h}, shell = "he"|"krasnopol", charge = id,
--       high = bool, basedir = mils }
-- -> { ok, err, range, bearing, deflection, elevation, tof, apex, charge, high }
-- Angles in mils, range and apex in metres (apex is a height, like h), tof in seconds.
function FC.Solve( q )
	local gun, target = q.gun, q.target
	local shellId = q.shell or "he"
	local shell = FC.GetShell( shellId )

	local de, dn = target.x - gun.x, target.y - gun.y
	local range = math.sqrt( de * de + dn * dn )
	local bearing = Grid.Bearing( gun.x, gun.y, target.x, target.y )
	local res = {
		ok = false, range = range, bearing = bearing,
		deflection = Deflection( bearing, q.basedir ),
		charge = q.charge, high = q.high and true or false,
	}

	if not shell then
		res.err = "Неизвестный снаряд: " .. tostring( shellId )
		return res
	end

	local charge = FC.GetCharge( shellId, q.charge )

	if not charge then
		res.err = string.format( "Для снаряда «%s» нет такого заряда", shell.name )
		return res
	end

	local muzzleH = ( gun.h or 0 ) + FC.MUZZLE_H
	local dh = ( target.h or 0 ) - muzzleH

	local key = table.concat( { shellId, charge.id, res.high and 1 or 0, math.Round( range, 1 ), math.Round( dh, 1 ), math.Round( muzzleH ) }, "/" )
	local cached = SolveCache[ key ]

	if cached then
		res.ok, res.err, res.elevation, res.tof, res.apex = cached.ok, cached.err, cached.elevation, cached.tof, cached.apex and cached.apex + muzzleH
		return res
	end

	local z0 = muzzleH
	local maxR, maxTheta = FC.MaxRange( shellId, charge.id, dh, z0 )
	local v0, k = charge.v0, shell.k
	local out = { ok = false }

	if not maxR or maxR < 0 then
		out.err = "Нет решения: цель выше досягаемой траектории"
	elseif range > maxR then
		out.err = string.format( "Цель вне досягаемости: заряд «%s» до %.1f км", charge.name, maxR / 1000 )
	else
		local lo, hi

		if res.high then
			local nearest = Range( FC.MAX_ELEV, v0, k, dh, z0 )

			if range < nearest then
				out.err = string.format( "Ближе наименьшей дальности навесной стрельбы (%.1f км)", nearest / 1000 )
			else
				lo, hi = maxTheta, FC.MAX_ELEV -- range falls as elevation grows
			end
		else
			local nearest = Range( FC.MIN_ELEV, v0, k, dh, z0 )

			if range < nearest then
				out.err = string.format( "Ближе наименьшей дальности (%.1f км), нужен меньший заряд", nearest / 1000 )
			else
				lo, hi = FC.MIN_ELEV, maxTheta
			end
		end

		if lo then
			for _ = 1, 26 do
				local mid = ( lo + hi ) / 2
				local r = Range( mid, v0, k, dh, z0 )

				if ( r < range ) ~= res.high then lo = mid else hi = mid end
			end

			local theta = ( lo + hi ) / 2
			local r, tof, apex = FC.Fly( theta, v0, k, dh, z0 )

			if r then
				out.ok = true
				out.elevation = DegToMils( theta )
				out.tof = tof
				out.apex = apex
			else
				out.err = "Нет решения: цель выше траектории"
			end
		end
	end

	if table.Count( SolveCache ) > 300 then SolveCache = {} end

	SolveCache[ key ] = out

	res.ok, res.err, res.elevation, res.tof = out.ok, out.err, out.elevation, out.tof
	res.apex = out.apex and out.apex + muzzleH

	return res
end

-- Gun -----------------------------------------------------------------------------

-- basic direction of the firing position (mils): set on deployment, else the hull heading
function FC.BaseDir( spg )
	local v = spg:GetNW2Float( "SkyOpsArty_BaseDir", -1 )

	if v >= 0 then return v, true end

	return Grid.YawToMils( spg:GetAngles().y ), false
end

-- barrel direction as world position + unit vector, from the muzzle attachment
function FC.Muzzle( spg )
	local id = spg:LookupAttachment( "muzzle" )
	local att = id and id > 0 and spg:GetAttachment( id )

	if not att then return spg:GetPos(), spg:GetForward() end

	return att.Pos, att.Ang:Forward()
end

-- bearing and elevation (mils) of a world direction
function FC.DirToMils( dir )
	local bearing = Grid.YawToMils( math.deg( math.atan2( dir.y, dir.x ) ) )
	local elev = DegToMils( math.deg( math.asin( math.Clamp( dir.z / math.max( dir:Length(), 1e-9 ), -1, 1 ) ) ) )

	return bearing, elev
end

-- current laying of the barrel: deflection, elevation, bearing (mils)
function FC.GunLaying( spg )
	local _, dir = FC.Muzzle( spg )
	local bearing, elev = FC.DirToMils( dir )

	return Deflection( bearing, ( FC.BaseDir( spg ) ) ), elev, bearing
end
