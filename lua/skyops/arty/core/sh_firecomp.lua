-- Artillery fire computer: shells and charges, the shell flight model and the solver
-- that turns gun and target grid coordinates into deflection and elevation.
-- sv_ballistics flies real shells with the same FireComp.Step, so a laid solution
-- lands on the target up to dispersion.
--
-- Flight model: point mass, gravity 9.81 m/s^2, quadratic drag a = -k * rho(h) * |v| * v
-- with an exponential atmosphere, v taken relative to the wind (same at every height). No
-- Earth curvature (InfMap is flat). k is tuned so that HE on the full charge reaches about
-- 37 km, as a 2A88 does.
--
-- Wind (sh_wind): the solver allows for the wind of the meteo bulletin by default; the
-- real wind drifts away from it, so long shots land some tens of metres off.

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
	-- the three below fly to the ground like HE; what happens there is shell.def.effect
	-- (sv_ballistics): smoke screen, flare hanging over the point, bomblets around it
	smoke = {
		name = "Дымовой",
		k = 4.4e-5,
		stockType = 0,
		effect = "smoke",
		charges = {
			{ id = 1, name = "Полный", v0 = 945 },
			{ id = 2, name = "Уменьшенный", v0 = 800 },
			{ id = 3, name = "Первый", v0 = 650 },
			{ id = 4, name = "Второй", v0 = 500 },
			{ id = 5, name = "Третий", v0 = 380 },
			{ id = 6, name = "Четвёртый", v0 = 290 },
		},
		dispersion = { v0 = 0.0015, mils = 0.5 },
	},
	illum = {
		name = "Осветительный",
		k = 4.6e-5,
		stockType = 0,
		effect = "illum",
		burstHeight = 450, -- m above the point of fall: the flare opens there and sinks
		charges = {
			{ id = 1, name = "Полный", v0 = 945 },
			{ id = 2, name = "Уменьшенный", v0 = 800 },
			{ id = 3, name = "Первый", v0 = 650 },
			{ id = 4, name = "Второй", v0 = 500 },
		},
		dispersion = { v0 = 0.0015, mils = 0.6 },
	},
	cluster = {
		name = "Кассетный",
		k = 4.4e-5,
		stockType = 0,
		effect = "cluster",
		burstHeight = 200, -- m: the case opens over the point of fall
		-- bomblets fall in a circle of `radius` m around the point of fall
		bomblets = { count = 16, radius = 55, blast = { radius = 3, blastRadius = 9, fragRadius = 16, damage = 2500, fragDamage = 25, fragCount = 12 } },
		charges = {
			{ id = 1, name = "Полный", v0 = 945 },
			{ id = 2, name = "Уменьшенный", v0 = 800 },
			{ id = 3, name = "Первый", v0 = 650 },
			{ id = 4, name = "Второй", v0 = 500 },
			{ id = 5, name = "Третий", v0 = 380 },
		},
		dispersion = { v0 = 0.0015, mils = 0.5 },
	},
}

-- order of the shell switch and of the lists in the interface
FC.ShellOrder = { "he", "krasnopol", "smoke", "illum", "cluster" }

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
	for _, id in ipairs( FC.ShellOrder ) do
		if FC.Shells[ id ].stockType == t then return id end
	end

	return "he"
end

-- shell loaded in a 2S35: set by sv_spg (SPG.SetShell), else the stock shell type
function FC.LoadedShell( spg )
	local id = spg:GetNW2String( "SkyOpsArty_Shell", "" )

	if FC.Shells[ id ] then return id end

	return FC.ShellForStockType( spg.GetShellType and spg:GetShellType() or 0 )
end

-- offsets (m) of the bomblets of a cluster shell, the same on server and client for the
-- same seed (the shell's net id): { {dx, dy, delay}, ... }
function FC.BombletPattern( seed, count, radius )
	local st = ( seed * 7919 + 17 ) % 2147483647
	local function Rand()
		st = ( st * 48271 ) % 2147483647

		return st / 2147483647
	end

	local list = {}

	for i = 1, count do
		local r = radius * math.sqrt( Rand() )
		local a = Rand() * 2 * math.pi

		list[ i ] = { r * math.cos( a ), r * math.sin( a ), 0.2 + Rand() * 0.8 }
	end

	return list
end

-- Flight model ---------------------------------------------------------------------

local exp, sqrt, max = math.exp, math.sqrt, math.max

-- One midpoint step of a shell state s = { x, y, z, vx, vy, vz } (metres, m/s, z up).
-- ax, ay, az: extra acceleration for this step (guidance), may be nil.
-- wx, wy: wind in m/s along the same axes, may be nil.
function FC.Step( s, k, dt, ax, ay, az, wx, wy )
	ax, ay, az = ax or 0, ay or 0, az or 0
	wx, wy = wx or 0, wy or 0

	local g = FC.G
	local vx, vy, vz = s.vx, s.vy, s.vz
	local ux, uy = vx - wx, vy - wy

	local r = k * exp( -max( s.z, 0 ) / SCALE_HEIGHT ) * sqrt( ux * ux + uy * uy + vz * vz )
	local mx = vx + ( ax - r * ux ) * dt * 0.5
	local my = vy + ( ay - r * uy ) * dt * 0.5
	local mz = vz + ( az - g - r * vz ) * dt * 0.5
	local mux, muy = mx - wx, my - wy

	local rm = k * exp( -max( s.z + vz * dt * 0.5, 0 ) / SCALE_HEIGHT ) * sqrt( mux * mux + muy * muy + mz * mz )

	s.x = s.x + mx * dt
	s.y = s.y + my * dt
	s.z = s.z + mz * dt
	s.vx = vx + ( ax - rm * mux ) * dt
	s.vy = vy + ( ay - rm * muy ) * dt
	s.vz = vz + ( az - g - rm * mz ) * dt
end

local MAX_TIME = 400

-- Flies from the muzzle at height z0 (m, sets the air density) at theta (deg) along +x
-- until the descending branch is dh below/above the muzzle. wr: tail wind (m/s, along x),
-- wc: cross wind (m/s, to the right, -y). Returns range, time of flight, apex (m above the
-- muzzle) and drift (m to the right), or nil when the shell never gets back down to dh
-- from above.
function FC.Fly( theta, v0, k, dh, z0, wr, wc )
	z0 = z0 or 0
	dh = dh + z0
	wr = wr or 0
	wc = -( wc or 0 )

	local th = math.rad( theta )
	local s = { x = 0, y = 0, z = z0, vx = v0 * math.cos( th ), vy = 0, vz = v0 * math.sin( th ) }
	local dt = FC.DT
	local t, apex = 0, z0
	local step = FC.Step

	while t < MAX_TIME do
		local px, pz = s.x, s.z

		local py = s.y

		step( s, k, dt, nil, nil, nil, wr, wc )
		t = t + dt

		if s.z > apex then apex = s.z end

		if s.vz < 0 and s.z <= dh then
			if apex < dh then return nil end

			local f = ( pz - dh ) / max( pz - s.z, 1e-9 )

			return px + ( s.x - px ) * f, t - dt + dt * f, apex - z0, -( py + ( s.y - py ) * f )
		end
	end
end

-- Solver ---------------------------------------------------------------------------

local function Range( theta, v0, k, dh, z0, wr, wc )
	return FC.Fly( theta, v0, k, dh, z0, wr, wc ) or -1
end

-- longest range (m) and its elevation (deg) for this charge, height difference to the
-- target dh, muzzle height z0 (m) and tail wind wr (m/s)
local MaxCache = {}

function FC.MaxRange( shellId, chargeId, dh, z0, wr )
	local shell, charge = FC.GetShell( shellId ), FC.GetCharge( shellId, chargeId )

	if not charge then return nil end

	dh = math.Round( dh or 0 )
	z0 = math.Round( z0 or 0, -1 )
	wr = math.Round( ( wr or 0 ) * 2 ) / 2

	local key = shellId .. "/" .. chargeId .. "/" .. dh .. "/" .. z0 .. "/" .. wr

	if MaxCache[ key ] then return unpack( MaxCache[ key ] ) end

	-- golden section: range is unimodal in elevation
	local a, b = 15, FC.MAX_ELEV
	local gr = ( math.sqrt( 5 ) - 1 ) / 2
	local c, d = b - gr * ( b - a ), a + gr * ( b - a )
	local fc, fd = Range( c, charge.v0, shell.k, dh, z0, wr ), Range( d, charge.v0, shell.k, dh, z0, wr )

	for _ = 1, 28 do
		if fc > fd then
			b, d, fd = d, c, fc
			c = b - gr * ( b - a )
			fc = Range( c, charge.v0, shell.k, dh, z0, wr )
		else
			a, c, fc = c, d, fd
			d = a + gr * ( b - a )
			fd = Range( d, charge.v0, shell.k, dh, z0, wr )
		end
	end

	local theta = ( a + b ) / 2
	local r = Range( theta, charge.v0, shell.k, dh, z0, wr )

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

-- wind of q (see FC.Solve) as tail and cross components (m/s) for a shot on bearing (mils)
local function WindAlong( q, bearing )
	local w = q.wind

	if w == nil then
		local Wind = SkyOps.Arty.Wind

		w = Wind and Wind.Bulletin and Wind.Bulletin()
	end

	if not w or ( ( w.x or 0 ) == 0 and ( w.y or 0 ) == 0 ) then return 0, 0 end

	local b = bearing / FC.MILS * 2 * math.pi
	local sb, cb = math.sin( b ), math.cos( b )

	return w.x * sb + w.y * cb, w.x * cb - w.y * sb
end

-- q = { gun = {x, y, h}, target = {x, y, h}, shell = "he"|"krasnopol"|..., charge = id,
--       high = bool, basedir = mils, wind = {x, y} m/s | false (none) | nil (bulletin) }
-- -> { ok, err, range, bearing, deflection, elevation, tof, apex, charge, high,
--      targetBearing, drift }
-- Angles in mils, range and apex in metres (apex is a height, like h), tof in seconds.
-- bearing and deflection are where to lay the barrel: the bearing to the target
-- (targetBearing) turned against the wind drift (drift, m to the right).
function FC.Solve( q )
	local gun, target = q.gun, q.target
	local shellId = q.shell or "he"
	local shell = FC.GetShell( shellId )

	local de, dn = target.x - gun.x, target.y - gun.y
	local range = math.sqrt( de * de + dn * dn )
	local bearing = Grid.Bearing( gun.x, gun.y, target.x, target.y )
	local res = {
		ok = false, range = range, bearing = bearing, targetBearing = bearing,
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

	local wr, wc = WindAlong( q, bearing )

	-- the bearing correction for the drift, once the elevation is known
	local function Finish( out )
		res.ok, res.err, res.elevation, res.tof = out.ok, out.err, out.elevation, out.tof
		res.apex = out.apex and out.apex + muzzleH

		if out.drift and range > 1 then
			res.drift = out.drift
			res.bearing = ( bearing - DegToMils( math.deg( math.atan2( out.drift, range ) ) ) ) % FC.MILS
			res.deflection = Deflection( res.bearing, q.basedir )
		end

		return res
	end

	local key = table.concat( { shellId, charge.id, res.high and 1 or 0, math.Round( range, 1 ), math.Round( dh, 1 ), math.Round( muzzleH ), math.Round( wr, 1 ), math.Round( wc, 1 ) }, "/" )
	local cached = SolveCache[ key ]

	if cached then return Finish( cached ) end

	local z0 = muzzleH
	local maxR, maxTheta = FC.MaxRange( shellId, charge.id, dh, z0, wr )
	local v0, k = charge.v0, shell.k
	local out = { ok = false }

	if not maxR or maxR < 0 then
		out.err = "Нет решения: цель выше досягаемой траектории"
	elseif range > maxR then
		out.err = string.format( "Цель вне досягаемости: заряд «%s» до %.1f км", charge.name, maxR / 1000 )
	else
		local lo, hi

		if res.high then
			local nearest = Range( FC.MAX_ELEV, v0, k, dh, z0, wr )

			if range < nearest then
				out.err = string.format( "Ближе наименьшей дальности навесной стрельбы (%.1f км)", nearest / 1000 )
			else
				lo, hi = maxTheta, FC.MAX_ELEV -- range falls as elevation grows
			end
		else
			local nearest = Range( FC.MIN_ELEV, v0, k, dh, z0, wr )

			if range < nearest then
				out.err = string.format( "Ближе наименьшей дальности (%.1f км), нужен меньший заряд", nearest / 1000 )
			else
				lo, hi = FC.MIN_ELEV, maxTheta
			end
		end

		if lo then
			for _ = 1, 26 do
				local mid = ( lo + hi ) / 2
				local r = Range( mid, v0, k, dh, z0, wr, wc )

				if ( r < range ) ~= res.high then lo = mid else hi = mid end
			end

			local theta = ( lo + hi ) / 2
			local r, tof, apex, drift = FC.Fly( theta, v0, k, dh, z0, wr, wc )

			if r then
				out.ok = true
				out.elevation = DegToMils( theta )
				out.tof = tof
				out.apex = apex
				out.drift = wc ~= 0 and drift or nil
			else
				out.err = "Нет решения: цель выше траектории"
			end
		end
	end

	if table.Count( SolveCache ) > 300 then SolveCache = {} end

	SolveCache[ key ] = out

	return Finish( out )
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
