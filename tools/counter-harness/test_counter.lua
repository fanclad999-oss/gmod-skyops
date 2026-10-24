-- Offline run of arty/counter with the real ballistics (arty/core) and missions (arty/missions).
-- usage (from tools/arty-harness of PR #9, with core/ next to it as its README says):
--   luajit ../counter-harness/test_counter.lua <repo> <missions dir> [seed]
local REPO, MISS = arg[1], arg[2]
dofile( "gmod_mock.lua" )
-- extra mock for counter
function EM_ext()
	local EM = getmetatable( MakeEnt( "dummy" ) )
	function EM:SetHP( v ) self.hp = v end
	function EM:GetMaxHP() return 1000 end
	function EM:TakeDamageInfo( d ) self.lastInfo = d end -- "armour" soaks everything
	function EM:TakeDamage( n ) self.hp = 0 end
	function EM:IsDestroyed() return ( self.hp or 1000 ) <= 0 end
end
EM_ext()
function DamageInfo() local d = {} return setmetatable( d, { __index = function( _, k ) return function( self, v ) d[ k ] = v end end } ) end
DMG_BLAST, HUD_PRINTTALK = 64, 3
net.WriteBool = function( v ) end
function PrintMessage( _, s ) print( "  PM " .. s ) end
timer = { Simple = function() end }
for _, f in ipairs{ "core/sh_grid.lua", "core/sh_firecomp.lua", "core/sv_ballistics.lua" } do dofile( f ) end
SkyOps.Arty.SPG = {
	CLASS = "sw_2s35",
	Mode = function() return "hardcore" end,
	IsSPG = function( e ) return IsValid( e ) and e.class == "sw_2s35" end,
	IsDeployed = function( s ) return s:GetNW2Bool( "SkyOpsArty_Deployed", false ) end,
	Of = function( ply ) return ply.vehicle end,
}
for _, f in ipairs{ "sh_counter.lua", "sv_counter.lua" } do dofile( REPO .. "/lua/skyops/arty/counter/" .. f ) end
for _, f in ipairs{ "sh_missions.lua", "sv_targets.lua", "sv_missions.lua" } do dofile( MISS .. "/" .. f ) end

local M, Grid, FC, B, CB = SkyOps.Arty.Missions, SkyOps.Arty.Grid, SkyOps.Arty.FireComp, SkyOps.Arty.Ballistics, SkyOps.Arty.Counter
local function Radio()
	for _, m in ipairs( NET_LOG ) do
		if m.name == M.NET_MSG then print( "    [" .. m.data[1] .. "] " .. m.data[2] ) end
		if m.name == CB.NET_INCOMING then print( string.format( "    <incoming x %.0f y %.0f tof %.1f n %d>", m.data[1], m.data[2], m.data[3], m.data[4] ) ) end
	end
	NET_LOG = {}
end
local function Think( sec )
	for _ = 1, math.floor( sec / 0.1 + 0.5 ) do AdvanceTime( 0.1 ) hook.Run( "Think" ) end
end
local function Flush( sec ) local t = 0 while next( B.Active ) and t < ( sec or 300 ) do Think( 1 ) t = t + 1 end end


math.randomseed( tonumber( arg[3] ) or 7 )
local ply = MakePlayer( "Александр" )
local spg = MakeEnt( "sw_2s35" )
ply.pos = Grid.FromGrid( 52000, 48000 )
spg.pos = ply.pos
ply.vehicle = spg

local function FireAt( x, y, shellId )
	local gx, gy, gh = Grid.ToGrid3( spg.pos )
	local th = Grid.Height( x, y ) local ch = FC.BestCharge( shellId or "he", math.sqrt( ( x - gx ) ^ 2 + ( y - gy ) ^ 2 ), th - gh, gh )
	local sol = FC.Solve{ gun = { x = gx, y = gy, h = gh }, target = { x = x, y = y, h = th }, shell = shellId or "he", charge = ch }
	assert( sol.ok, "solve: " .. tostring( sol.err ) )
	local shell = B.Fire{ pos = spg.pos + Vector( 0, 0, 100 ), dir = Grid.Direction( sol.bearing, sol.elevation ), shell = shellId or "he", charge = sol.charge, attacker = ply, spg = spg }
	hook.Run( "SkyOps.Arty.SPGFired", spg, shell )
	return shell
end

local function StartRaid()
	SetTime( CurTime() + 100 )
	spg.hp = 1000
	spg:SetNW2Bool( "SkyOpsArty_Deployed", false )
	assert( M.Start( ply, { type = "raid", range = "mid", march = false } ) )
	local run = M.Run
	spg:SetNW2Bool( "SkyOpsArty_Deployed", true )
	Think( 2 ) Think( 21 ) Radio()
	assert( run.intel, "hq intel" )
	return run
end

-- 1) stay and keep firing: located, salvo, the next salvos tighten, the gun dies
print( "=== 1: stay on the spot" )
local run = StartRaid()
local bat
for i = 1, 12 do
	if CB.Spots[ spg ] and CB.Spots[ spg ].lock then break end
	FireAt( run.intel.x + 400, run.intel.y ) -- miss on purpose so the mission goes on
	Think( 3 ) Radio()
end
local st = CB.Spots[ spg ]
assert( st and st.lock, "position must be located after 6 shots (need " .. ( st and st.need or "?" ) .. ")" )
assert( spg:GetNW2Bool( "SkyOpsCB_Locked" ) == true and spg:GetNW2Float( "SkyOpsCB_Heat" ) == 1 )
bat = CB.Battery
assert( bat and #bat.targets == 2, "battery with two guns" )
print( string.format( "  battery %s, %.1f km from the gun", Grid.Format( bat.x, bat.y ), math.sqrt( ( bat.x - st.x ) ^ 2 + ( bat.y - st.y ) ^ 2 ) / 1000 ) )
local t0 = CurTime()
while CB.Stats.salvos == 0 and CurTime() - t0 < 120 do Think( 1 ) end
Radio()
assert( CB.Stats.salvos == 1, "first salvo" )
assert( bat.known and bat.reveal, "battery revealed after the first salvo" )
for _ = 1, 400 do if M.Run.stage == M.STAGE_DONE then break end Think( 1 ) end
Radio()
print( string.format( "  hp %d, stage %s, salvos %d, shells %d, closest %.0f m", spg:GetHP(), M.StageNames[ M.Run.stage ], CB.Stats.salvos, CB.Stats.fired, CB.Stats.closest or -1 ) )
assert( spg:GetHP() < 1000, "staying must hurt" )

-- 2) shoot and scoot: located, drive 300 m away, the salvo lands on the empty spot
print( "\n=== 2: shoot and scoot" )
run = StartRaid()
for i = 1, 12 do
	if CB.Spots[ spg ] and CB.Spots[ spg ].lock then break end
	FireAt( run.intel.x + 400, run.intel.y ) Think( 3 )
end
Radio()
assert( CB.Spots[ spg ] and CB.Spots[ spg ].lock, "located" )
local old = CB.Spots[ spg ]
spg.pos = Grid.FromGrid( old.x + 320, old.y + 40 )
Think( 1 )
assert( CB.Spots[ spg ] == nil and spg:GetNW2Float( "SkyOpsCB_Heat" ) == 0, "moved: fresh spot" )
for _ = 1, 200 do Think( 1 ) end
Radio()
print( string.format( "  hp %d, salvos %d, dodged %d, moves %d", spg:GetHP(), CB.Stats.salvos, CB.Stats.dodged, CB.Stats.moves ) )
assert( spg:GetHP() == 1000, "moved gun must be unhurt" )
assert( CB.Stats.salvos == 1 and CB.Stats.dodged == 1 and CB.Stats.moves == 1, "exactly one salvo at the old spot" )

-- 3) counter-counter-battery: shoot the revealed battery
print( "\n=== 3: silence the enemy battery" )
bat = CB.Battery
assert( bat.known )
for _ = 1, 6 do
	for _, g in ipairs( bat.targets ) do
		if g.alive then FireAt( g.x, g.y ) Flush() Radio() end
	end
end
print( "  silenced:", tostring( bat.silenced ) )
assert( bat.silenced and CB.Stats.silenced, "6 aimed shots per gun must silence it" )

-- 4) mode 0: nothing counts
print( "\n=== 4: off" )
CONVARS.skyops_arty_counter.v = "0"
run = StartRaid()
for i = 1, 8 do FireAt( run.intel.x + 400, run.intel.y ) Think( 3 ) end
assert( not CB.Spots[ spg ], "off: no tracking" )
COMMANDS.skyops_arty_mission_abort( nil ) Think( 1 )
assert( CB.Battery == nil, "battery removed with the mission" )
print( "\nALL OK" )
