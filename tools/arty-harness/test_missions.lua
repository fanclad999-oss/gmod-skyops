local REPO = arg[1]
dofile( "gmod_mock.lua" )
for _, f in ipairs{ "core/sh_grid.lua", "core/sh_firecomp.lua", "core/sv_ballistics.lua" } do dofile( f ) end
-- SPG stub: deploy state via NW2 like sv_spg
SkyOps.Arty.SPG = {
	CLASS = "sw_2s35",
	Mode = function() return MODE or "hardcore" end,
	IsDeployed = function( s ) return s:GetNW2Bool( "SkyOpsArty_Deployed", false ) end,
	Of = function( ply ) return ply.vehicle end,
}
for _, f in ipairs{ "sh_missions.lua", "sv_targets.lua", "sv_missions.lua" } do dofile( REPO .. "/lua/skyops/arty/missions/" .. f ) end

local M, Grid, FC, B = SkyOps.Arty.Missions, SkyOps.Arty.Grid, SkyOps.Arty.FireComp, SkyOps.Arty.Ballistics
-- capture radio and state
local origWrite = M.WriteTable
local ns = net.Start
net.Start = function( n ) CUR_NET = n ns( n ) end
M.WriteTable = function( t ) if CUR_NET == M.NET_DEBRIEF then DEB = t end end
local function Deb() if DEB then return string.format( "%s %d/%d grade %s shots %d hits %s firstMiss %s avg %s", DEB.success and "OK" or "FAIL", DEB.score.total, DEB.score.max, DEB.score.grade, DEB.shots, tostring(DEB.hits), tostring(DEB.firstMiss and math.floor(DEB.firstMiss)), tostring(DEB.avgMiss and math.floor(DEB.avgMiss)) ) end end
local function Radio()
	for _, m in ipairs( NET_LOG ) do
		if m.name == M.NET_MSG then print( "    [" .. m.data[1] .. "] " .. m.data[2] ) end
	end
	NET_LOG = {}
end
local function Think( sec )
	for _ = 1, math.floor( sec / 0.1 ) do
		AdvanceTime( 0.1 )
		hook.Run( "Think" )
	end
end

local ply = MakePlayer( "Александр" )
local spg = MakeEnt( "sw_2s35" )
ply.pos = Grid.FromGrid( 52000, 48000 )
spg.pos = ply.pos
ply.vehicle = spg

local function FireAt( x, y, shellId )
	local gx, gy, gh = Grid.ToGrid3( spg.pos )
	local th = Grid.Height( x, y ) local ch = FC.BestCharge( shellId or "he", math.sqrt( ( x - gx ) ^ 2 + ( y - gy ) ^ 2 ), th - gh, gh ) local sol = FC.Solve{ gun = { x = gx, y = gy, h = gh }, target = { x = x, y = y, h = th }, shell = shellId or "he", charge = ch }
	assert( sol.ok, "solve: " .. tostring( sol.err ) )
	local shell = B.Fire{ pos = spg.pos + Vector( 0, 0, 100 ), dir = Grid.Direction( sol.bearing, sol.elevation ), shell = shellId or "he", charge = sol.charge, attacker = ply, spg = spg }
	hook.Run( "SkyOps.Arty.SPGFired", spg, shell )
	local t = 0
	while B.Active[ shell.id ] and t < 300 do Think( 1 ) t = t + 1 end
	return sol
end

local function Run( kind, range, march )
	print( "\n=== " .. kind .. " " .. range .. " march=" .. tostring( march ) )
	SetTime( CurTime() + 100 ) spg:SetNW2Bool( "SkyOpsArty_Deployed", false )
	assert( M.Start( ply, { type = kind, range = range, march = march } ) )
	local run = M.Run
	print( string.format( "  fp %s  dist %.1f km  targets %d need %d", Grid.Format( run.fp.x, run.fp.y ), run.distance / 1000, #run.targets, run.need ) )
	Radio()
	Think( 2 )
	assert( run.stage == ( march and M.STAGE_MARCH or M.STAGE_DEPLOY ), "stage " .. run.stage )
	-- drive to FP
	spg.pos = Grid.FromGrid( run.fp.x + 40, run.fp.y - 30 )
	Think( 2 ) Radio()
	assert( run.stage == M.STAGE_DEPLOY, "deploy stage" )
	spg:SetNW2Bool( "SkyOpsArty_Deployed", true )
	Think( 2 ) Radio()
	return run
end

-- 1) raid: HQ coords, fire until done
local run = Run( "raid", "mid", true )
assert( run.stage == M.STAGE_RECON )
Think( 21 ) Radio()
assert( run.stage == M.STAGE_FIRE and run.intel, "hq reveal" )
local shots = 0
while M.Run.stage ~= M.STAGE_DONE and shots < 30 do
	local t = M.Targets.Nearest( run.targets, run.intel.x, run.intel.y )
	local tx, ty = t and t.x or run.intel.x, t and t.y or run.intel.y
	FireAt( tx, ty ) shots = shots + 1
	Think( 1 ) Radio()
end
print( "  stage", M.StageNames[ M.Run.stage ], "shots", shots, Deb() )

-- 2) recon by stock camera lock
run = Run( "recon", "near", false )
assert( run.stage == M.STAGE_RECON )
local drone = MakeEnt( "sw_orlan10" )
local t1 = run.targets[1]
drone.pos = Grid.FromGrid( t1.x + 800, t1.y, 400 )
drone.nw = { TrackPos = Grid.FromGrid( t1.x + 20, t1.y + 10 ) }
Think( 4 ) Radio()
assert( run.intel and run.stage == M.STAGE_FIRE, "drone lock reveal" )
drone.nw = nil
FireAt( run.intel.x + 150, run.intel.y ) Radio()
COMMANDS.skyops_arty_mission_simhit( ply, nil, { "0", "0" } ) Radio()
for _ = 1, 6 do
	if M.Run.stage == M.STAGE_DONE then break end
	local t = M.Targets.Nearest( run.targets, run.intel.x, run.intel.y )
	if t then local cx, cy = M.Targets.Center( run.targets ) COMMANDS.skyops_arty_mission_simhit( ply, nil, { tostring( t.x - cx ), tostring( t.y - cy ) } ) end
	Think( 1 ) Radio()
end
print( "  stage", M.StageNames[ M.Run.stage ], Deb() )

-- 3) laser: drone module hook, krasnopol
run = Run( "laser", "far", true )
local cp
for _, t in ipairs( run.targets ) do if t.required then cp = t end end
hook.Run( "SkyOps.Arty.TargetSent", drone, Grid.FromGrid( cp.x + 300, cp.y ), 5, ply ) Radio()
assert( not run.intel, "wrong point must not reveal" )
hook.Run( "SkyOps.Arty.TargetSent", drone, Grid.FromGrid( cp.x + 5, cp.y ), 5, ply ) Radio()
assert( run.intel )
for _ = 1, 4 do
	if M.Run.stage == M.STAGE_DONE then break end
	local cx, cy = M.Targets.Center( run.targets )
	COMMANDS.skyops_arty_mission_simhit( ply, nil, { tostring( cp.x - cx + 1 ), tostring( cp.y - cy ), "krasnopol" } )
	Think( 1 ) Radio()
end
print( "  stage", M.StageNames[ M.Run.stage ], Deb() )

-- 4) fleeting: miss, let it leave, then HQ re-sends
run = Run( "fleeting", "near", false )
Think( 21 ) Radio()
assert( run.intel )
COMMANDS.skyops_arty_mission_simhit( ply, nil, { "300", "0" } ) Radio()
Think( 245 ) Radio()
assert( run.stage == M.STAGE_RECON and not run.intel, "relocated" )
Think( 300 ) Radio()
assert( run.intel, "hq resend" )
print( "  moved to", Grid.Format( run.intel.x, run.intel.y ) )
COMMANDS.skyops_arty_mission_status( nil )
COMMANDS.skyops_arty_mission_abort( nil ) Radio()
assert( M.Run == nil )
print( "\nALL OK" )
