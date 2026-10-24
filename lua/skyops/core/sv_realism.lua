-- Real-world numbers for Ryuunosuke vehicles on a 1:1 map. Out of the box they
-- are tuned for small maps: seekers lock at 380-950 m, jets top out near
-- 250 km/h and burn a full tank in 3-7 minutes.

local M_TO_HU = SkyOps.M_TO_HU

SkyOps.SeekerRange = {
	sw_su34 = 12000,      -- R-73 IR lock, R-27R needs the radar anyway
	sw_su25sm3 = 8000,    -- R-73 only
	sw_f14a = 20000,      -- AWG-9 + AIM-7/AIM-54, capped for gameplay
	sw_tornado = 8000,    -- AIM-9
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

local function Apply( ent )
	local perf = SkyOps.Performance[ ent:GetClass() ]
	if perf and not ent.SkyOpsPerf then
		ent.SkyOpsPerf = true
		ApplyPerformance( ent, perf )
	end

	local range = SkyOps.SeekerRange[ ent:GetClass() ]
	if not range or not isfunction( ent.SetSeekerDist ) then return end

	ent:SetSeekerDist( range * M_TO_HU )
	if isfunction( ent.CanSeeMis ) then ent.CanSeeMis = CanSeeMis end
end

hook.Add( "OnEntityCreated", "SkyOps.Realism", function( ent )
	local class = ent:GetClass()
	if not ( SkyOps.SeekerRange[ class ] or SkyOps.Performance[ class ] ) then return end
	-- LVS runs OnSpawn (which sets the stock range) one tick after creation
	timer.Simple( 0.5, function()
		if IsValid( ent ) then Apply( ent ) end
	end )
end )
