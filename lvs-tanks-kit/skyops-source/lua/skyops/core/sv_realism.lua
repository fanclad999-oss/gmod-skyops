-- Real-world numbers for Ryuunosuke vehicles on a 1:1 map. Out of the box they
-- are tuned for small maps: seekers lock at 380-950 m, jets top out near
-- 250 km/h and burn a full tank in 3-7 minutes.

local M_TO_HU = SkyOps.M_TO_HU

SkyOps.SeekerRange = {
	sw_su34 = 30000,      -- radar lock for R-27R/R-77 class shots
	sw_su25sm3 = 10000,   -- R-73 only
	sw_f14a = 40000,      -- AWG-9 + AIM-54, capped for gameplay
	sw_tornado = 15000,   -- AIM-9 / Sky Flash class
	sw_snr75 = 45000,     -- SNR-75 fire control
	sw_torm1 = 12000,
	sw_9k33m3 = 10000,
	sw_flarakpz1 = 8000,
}

-- original CanSeeMis gives up past 75000 u (1.4 km) and is blocked by any prop
local function CanSeeMis( self, target )
	local att = self:GetAttachment( self:LookupAttachment( "view" ) )
	local from = att and att.Pos or self:WorldSpaceCenter()
	return SkyOps.Radar.LineOfSight( from, target )
end

-- maxKmh: top speed at low altitude; fuelMin: minutes at full throttle
-- (LVS burns throttle^2, so cruise at ~70% lasts about twice as long)
SkyOps.Performance = {
	sw_su34 = { maxKmh = 1400, fuelMin = 90 },
	sw_su25sm3 = { maxKmh = 950, fuelMin = 60 },
	sw_f14a = { maxKmh = 1450, fuelMin = 75 },
	sw_tornado = { maxKmh = 1480, fuelMin = 75 },
}

-- Source caps every physics object at 4000 u/s (~275 km/h); that cap is why
-- jets and missiles all crawled at the same speed. 50000 u/s is ~3400 km/h,
-- enough for Mach 3 missiles.
local MAX_VELOCITY = 50000

-- physenv is not ready while autorun files load, only after InitPostEntity
local function RaisePhysicsLimit()
	local tbl = physenv.GetPerformanceSettings()
	if not tbl then return end
	if tbl.MaxVelocity < MAX_VELOCITY then
		tbl.MaxVelocity = MAX_VELOCITY
		physenv.SetPerformanceSettings( tbl )
		print( "[SkyOps] physics MaxVelocity -> " .. MAX_VELOCITY )
	end
end
hook.Add( "InitPostEntity", "SkyOps.Realism", RaisePhysicsLimit )
-- LVS:FixVelocity can run later and only ever raises the value, so this sticks
timer.Create( "SkyOps.PhysicsLimit", 5, 0, RaisePhysicsLimit )

local function ApplyPerformance( ent, perf )
	local kmh_to_hu = 1000 / 3600 * M_TO_HU
	local newMax = perf.maxKmh * kmh_to_hu
	local scale = newMax / ent.MaxVelocity

	-- thrust and the best-turn speed scale with top speed so handling keeps its feel
	ent.MaxVelocity = newMax
	ent.MaxThrust = ent.MaxThrust * scale
	if ent.MaxPerfVelocity then ent.MaxPerfVelocity = ent.MaxPerfVelocity * scale end

	local tank = isfunction( ent.GetFuelTank ) and ent:GetFuelTank()
	if IsValid( tank ) then
		-- consumption is throttle^2 / size per second
		tank:SetSize( perf.fuelMin * 60 / LVS.FuelScale )
	end
end

-- seeker cone (Ryuunosuke units: radians * 200 / pi, stock 7 = 6 deg, which
-- is hard to hold on a manoeuvring target) and lock time in seconds
SkyOps.SeekerCone = {
	sw_su34 = { angle = 20, lock = 1 },
	sw_su25sm3 = { angle = 12, lock = 1 },
	sw_f14a = { angle = 25, lock = 1 },
	sw_tornado = { angle = 15, lock = 1 },
}

local function EnforceSeeker( ent )
	local class = ent:GetClass()
	local range = SkyOps.SeekerRange[ class ]
	if not range or not isfunction( ent.SetSeekerDist ) then return end

	local dist = math.floor( range * M_TO_HU )
	if ent:GetSeekerDist() ~= dist then ent:SetSeekerDist( dist ) end

	local cone = SkyOps.SeekerCone[ class ]
	if cone then
		if isfunction( ent.SetSeekerAngle ) and ent:GetSeekerAngle() ~= cone.angle then ent:SetSeekerAngle( cone.angle ) end
		if isfunction( ent.SetLockTimer ) and ent:GetLockTimer() ~= cone.lock then ent:SetLockTimer( cone.lock ) end
	end
	if isfunction( ent.CanSeeMis ) and ent.CanSeeMis ~= CanSeeMis then ent.CanSeeMis = CanSeeMis end
end

-- the jets reset SeekerDist/Angle/LockTimer to stock whenever their loadout
-- is rebuilt (mission loadouts are set after spawn), so keep re-applying
timer.Create( "SkyOps.Seekers", 1, 0, function()
	for _, veh in pairs( LVS:GetVehicles() ) do
		if IsValid( veh ) then EnforceSeeker( veh ) end
	end
end )

local function Apply( ent )
	local perf = SkyOps.Performance[ ent:GetClass() ]
	if perf and not ent.SkyOpsPerf then
		ent.SkyOpsPerf = true
		ApplyPerformance( ent, perf )
	end

	EnforceSeeker( ent )
end

hook.Add( "OnEntityCreated", "SkyOps.Realism", function( ent )
	local class = ent:GetClass()
	if not ( SkyOps.SeekerRange[ class ] or SkyOps.Performance[ class ] ) then return end
	-- LVS runs OnSpawn (which sets the stock range) one tick after creation
	timer.Simple( 0.5, function()
		if IsValid( ent ) then Apply( ent ) end
	end )
end )

-- SW Bombs rockets cap speed at ConvertMetersToUnits( MaxVelocity^2 ), i.e.
-- squared metres converted once: MaxVelocity * 7.2 u/s instead of
-- MaxVelocity * 40 u/s on this map. An R-73 (850 m/s) topped out at ~150 m/s,
-- slower than the jet that fired it. Recompute the cap in map units.
hook.Add( "OnEntityCreated", "SkyOps.MissileSpeed", function( ent )
	-- launchers set MaxVelocity between ents.Create and Spawn; Initialize computes the cap
	timer.Simple( 0, function()
		if not ( IsValid( ent ) and ent.IsRocket and isnumber( ent.MaxVelocity ) ) then return end
		ent.MaxVelocityUnitsSquared = ( ent.MaxVelocity * SkyOps.M_TO_HU ) ^ 2
	end )
end )
