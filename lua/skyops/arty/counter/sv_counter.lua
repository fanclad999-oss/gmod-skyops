-- Counter-battery fire, server: counts the shots of every 2S35 per firing position,
-- locates a position that fired too often, places an enemy battery and fires salvos at
-- the located point through the arty ballistics (so the whistle, burst and smoke of
-- arty/fx come for free), judges the damage to the 2S35 itself and lets the crew shoot
-- back at the enemy battery once the friendly radar has found it.
--
-- Plugs into arty/missions only through its hooks and tables (M.Run, M.Radio, M.Targets);
-- outside missions it works with skyops_arty_counter 2. See sh_counter for the rules.

local CB = SkyOps.Arty.Counter
local Grid = SkyOps.Arty.Grid
local FC = SkyOps.Arty.FireComp
local B = SkyOps.Arty.Ballistics

util.AddNetworkString( CB.NET_INCOMING )
util.AddNetworkString( CB.NET_BATTERY )

local DETECT_CHANCE = 0.9          -- each shot is tracked by the enemy radar with this chance
local LOCK_ERR = { 35, 80 }        -- m, error of the first located point
local REFINE = 0.55                -- error of each next salvo at the same spot, times this
local MIN_ERR = 8                  -- m
local SHELL_SPREAD = 18            -- m, 1 sigma of single shells around the salvo aim point
local SHELL_INTERVAL = { 1.5, 3.5 } -- s between the shells of one salvo
local REPEAT = { 35, 60 }          -- s from a salvo to the next one while the gun stays
local FORGET = 300                 -- s without shots after which an unlocated spot is forgotten
local BATTERY_ERR = 80             -- m, error of the enemy battery reported by our radar
local BATTERY_NEAR = { 1500, 4000 } -- m behind the mission targets
local BATTERY_FREE = { 10000, 18000 } -- m outside missions, along the line of fire
local BATTERY_RESPAWN = 300        -- s until a new enemy battery outside missions
local BATTERY_GROUP = { group = { gun = 2 }, spread = 40, armorOverride = { gun = "soft" } } -- guns in the open: fragments are enough
local HULL = 3.5                   -- m, half length of the 2S35 for the damage distance

CB.Spots = CB.Spots or {}   -- spg -> { x, y, detected, need, last, lock }
CB.Salvos = CB.Salvos or {} -- { at, x, y, spg, spot }
CB.Queue = CB.Queue or {}   -- single shells of running salvos: { at, x, y }
CB.Battery = CB.Battery or nil
CB.Stats = CB.Stats or {}

local function Now() return CurTime() end

local function Missions() return SkyOps.Arty.Missions end

local function SPGApi() return SkyOps.Arty.SPG end

local function Gauss()
	local u = math.max( math.random(), 1e-12 )

	return math.sqrt( -2 * math.log( u ) ) * math.cos( 2 * math.pi * math.random() )
end

local function Dist( x1, y1, x2, y2 )
	return math.sqrt( ( x1 - x2 ) ^ 2 + ( y1 - y2 ) ^ 2 )
end

local function ResetStats()
	CB.Stats = { fired = 0, salvos = 0, damage = 0, moves = 0, dodged = 0, closest = nil, silenced = false }
end

if not CB.Stats.fired then ResetStats() end

-- Radio --------------------------------------------------------------------------------------

-- the mission crew hears it on the mission radio; outside missions every player does
local function Radio( from, text )
	local M = Missions()
	local run = M and M.Run

	if M and M.Radio then
		if run and run.stage ~= M.STAGE_DONE then
			M.Radio( run, from, text )
		else
			M.Radio( nil, from, text, player.GetHumans() )
		end

		return
	end

	PrintMessage( HUD_PRINTTALK, "[" .. from .. "] " .. text )
end

-- Which shots count ---------------------------------------------------------------------------

local function MissionActive()
	local M = Missions()
	local run = M and M.Run

	return run and run.stage ~= M.STAGE_DONE and run or nil
end

local function Enabled( spg, shell )
	local mode = CB.Mode()

	if mode <= 0 then return false end
	if mode >= 2 then return true end

	local run = MissionActive()

	if not run then return false end
	if IsValid( run.spg ) then return run.spg == spg end

	-- no gun bound yet: the missions module binds the first 2S35 a crew member fires
	return shell and IsValid( shell.owner ) and run.players[ shell.owner ] ~= nil
end

-- Enemy battery ---------------------------------------------------------------------------------

local function FindSpot( x, y, minDist, maxDist, bearing, spread )
	local M = Missions()

	if M and M.Targets and M.Targets.FindSpot then
		return M.Targets.FindSpot( x, y, minDist, maxDist, bearing, spread, 60 )
	end

	for _ = 1, 60 do
		local a = ( bearing + math.Rand( -spread, spread ) ) / FC.MILS * 2 * math.pi
		local r = math.Rand( minDist, maxDist )
		local px, py = x + math.sin( a ) * r, y + math.cos( a ) * r
		local h = Grid.Height( px, py )

		if h then return px, py, h end
	end
end

local function BatteryAlive( bat )
	if not bat or bat.silenced then return false end
	if #bat.targets == 0 then return true end -- no props (missions module missing): virtual

	local M = Missions()

	return M.Targets.CountAlive( bat.targets ) > 0
end

local function SendBattery( to )
	local bat = CB.Battery

	net.Start( CB.NET_BATTERY )
		net.WriteBool( bat ~= nil and bat.known == true )
		net.WriteFloat( bat and bat.reveal and bat.reveal.x or 0 )
		net.WriteFloat( bat and bat.reveal and bat.reveal.y or 0 )
		net.WriteFloat( bat and bat.reveal and bat.reveal.err or 0 )
		net.WriteBool( BatteryAlive( bat ) )

	if to then net.Send( to ) else net.Broadcast() end
end

function CB.ClearBattery()
	local bat = CB.Battery
	local M = Missions()

	if bat and M and M.Targets then M.Targets.RemoveAll( bat.targets ) end

	CB.Battery = nil
	SendBattery()
end

-- the enemy battery: behind the mission targets, or far down the line of fire
local function EnsureBattery( spg, shell )
	local bat = CB.Battery

	if bat then
		if BatteryAlive( bat ) then return bat end

		-- silenced: in a mission it stays silent, outside one a new battery comes later
		if MissionActive() or Now() < ( bat.silencedAt or 0 ) + BATTERY_RESPAWN then return nil end

		CB.ClearBattery()
	end

	local sx, sy = Grid.ToGrid( spg:GetPos() )
	local run = MissionActive()
	local M = Missions()
	local x, y, h

	if run and run.targets and M.Targets then
		local cx, cy = M.Targets.Center( run.targets )

		if cx then
			x, y, h = FindSpot( cx, cy, BATTERY_NEAR[ 1 ], BATTERY_NEAR[ 2 ], Grid.Bearing( sx, sy, cx, cy ), 700 )
		end
	end

	if not x then
		local bearing = shell and math.deg( math.atan2( shell.vx, shell.vy ) ) % 360 / 360 * FC.MILS or math.Rand( 0, FC.MILS )

		x, y, h = FindSpot( sx, sy, BATTERY_FREE[ 1 ], BATTERY_FREE[ 2 ], bearing, 500 )
	end

	if not x then return nil end

	bat = { x = x, y = y, h = h or Grid.Height( x, y ) or 0, targets = {}, known = false, run = run }

	if M and M.Targets and M.Targets.SpawnGroup then
		bat.targets = M.Targets.SpawnGroup( BATTERY_GROUP, x, y )
	end

	CB.Battery = bat

	return bat
end

local function Silence( bat )
	bat.silenced = true
	bat.silencedAt = Now()
	CB.Stats.silenced = true
	CB.Salvos, CB.Queue = {}, {}

	Radio( "Штаб", "Батарея противника подавлена. Ответного огня больше не будет." )
	SendBattery()
end

-- the friendly radar tracks the enemy shells back to their guns
local function RevealBattery( bat )
	if bat.known then return end

	local a, r = math.Rand( 0, 2 * math.pi ), BATTERY_ERR * math.sqrt( math.Rand( 0, 1 ) )

	bat.known = true
	bat.reveal = { x = math.Round( bat.x + math.cos( a ) * r, -1 ), y = math.Round( bat.y + math.sin( a ) * r, -1 ), err = BATTERY_ERR }

	Radio( "Зоопарк", string.format( "Огневая позиция батареи противника: %s, точность %d м. Можно подавить.", Grid.Format( bat.reveal.x, bat.reveal.y ), BATTERY_ERR ) )
	SendBattery()
end

-- Firing positions ------------------------------------------------------------------------------

local function UpdateNW( spg, st )
	if not IsValid( spg ) then return end

	if not st then
		spg:SetNW2Float( "SkyOpsCB_Heat", 0 )
		spg:SetNW2Bool( "SkyOpsCB_Locked", false )
		return
	end

	spg:SetNW2Float( "SkyOpsCB_Heat", st.lock and 1 or math.Clamp( st.detected / st.need, 0, 1 ) )
	spg:SetNW2Bool( "SkyOpsCB_Locked", st.lock ~= nil )
	spg:SetNW2Float( "SkyOpsCB_X", st.x )
	spg:SetNW2Float( "SkyOpsCB_Y", st.y )
end

local function NewSpot( x, y )
	local base = CB.cvShots:GetInt()
	local need = base >= 3 and base + math.random( -1, 1 ) or base

	return { x = x, y = y, detected = 0, need = math.max( need, 1 ), last = Now() }
end

local function ScheduleSalvo( spg, st, delay )
	CB.Salvos[ #CB.Salvos + 1 ] = { at = Now() + delay, x = st.lock.x, y = st.lock.y, spg = spg, spot = st }
end

local function Lock( spg, st, shell )
	if not EnsureBattery( spg, shell ) then return end

	local err = math.Rand( LOCK_ERR[ 1 ], LOCK_ERR[ 2 ] )
	local a, r = math.Rand( 0, 2 * math.pi ), err * math.Rand( 0.3, 1 )

	st.lock = { x = st.x + math.cos( a ) * r, y = st.y + math.sin( a ) * r, err = err, dx = math.cos( a ), dy = math.sin( a ) }

	ScheduleSalvo( spg, st, CB.cvDelay:GetFloat() * math.Rand( 0.8, 1.2 ) )

	Radio( "РЭР", "Противник засёк вашу огневую позицию, готовит ответный огонь. Сменить позицию: отъехать не меньше " .. CB.MOVE_RADIUS .. " м." )
end

hook.Add( "SkyOps.Arty.SPGFired", "SkyOps.Arty.Counter", function( spg, shell )
	if not IsValid( spg ) or not Enabled( spg, shell ) then return end

	local x, y = Grid.ToGrid( spg:GetPos() )
	local st = CB.Spots[ spg ]

	if st and ( Dist( x, y, st.x, st.y ) > CB.MOVE_RADIUS or ( not st.lock and Now() - st.last > FORGET ) ) then
		st = nil
	end

	if not st then
		st = NewSpot( x, y )
		CB.Spots[ spg ] = st
	end

	st.last = Now()

	if math.random() <= DETECT_CHANCE then st.detected = st.detected + 1 end

	if not st.lock and st.detected >= st.need then Lock( spg, st, shell ) end

	UpdateNW( spg, st )
end )

-- Enemy fire ----------------------------------------------------------------------------------------

-- firing solution from the enemy battery to grid x, y (with the charge picked for the range)
local function Solve( bat, x, y )
	local h = Grid.Height( x, y ) or 0
	local range = Dist( bat.x, bat.y, x, y )
	local charge = FC.BestCharge( "he", range, h - ( bat.h + FC.MUZZLE_H ), bat.h + FC.MUZZLE_H )
	local q = { gun = { x = bat.x, y = bat.y, h = bat.h }, target = { x = x, y = y, h = h }, shell = "he", charge = charge }
	local sol = FC.Solve( q )

	if not sol.ok then
		q.high = true
		sol = FC.Solve( q )
	end

	if not sol.ok then return nil end

	sol.charge = charge

	return sol
end

local function FireShell( q )
	local bat = CB.Battery

	if not BatteryAlive( bat ) then return end

	local sol = Solve( bat, q.x, q.y )

	if not sol then return end

	local shell = B.Fire( {
		pos = Grid.FromGrid( bat.x, bat.y, bat.h + FC.MUZZLE_H ),
		dir = Grid.Direction( sol.bearing, sol.elevation ),
		shell = "he",
		charge = sol.charge,
	} )

	if shell then
		shell.data.counter = true
		CB.Stats.fired = CB.Stats.fired + 1
	end
end

local cvTimeScale = GetConVar( "skyops_arty_timescale" )

local function FireSalvo( salvo )
	local bat = CB.Battery

	if not BatteryAlive( bat ) then return end

	local sol = Solve( bat, salvo.x, salvo.y )

	if not sol then return end

	local n = CB.cvSalvo:GetInt()
	local t = Now()

	for _ = 1, n do
		CB.Queue[ #CB.Queue + 1 ] = { at = t, x = salvo.x + Gauss() * SHELL_SPREAD, y = salvo.y + Gauss() * SHELL_SPREAD }
		t = t + math.Rand( SHELL_INTERVAL[ 1 ], SHELL_INTERVAL[ 2 ] )
	end

	local tof = ( sol.tof or 30 ) / math.max( cvTimeScale and cvTimeScale:GetFloat() or 1, 0.1 )

	CB.Stats.salvos = CB.Stats.salvos + 1

	-- whether the crew already left this spot (the salvo hits an empty position)
	local spg = salvo.spg
	local gone = not IsValid( spg ) or CB.Spots[ spg ] ~= salvo.spot

	if gone then CB.Stats.dodged = CB.Stats.dodged + 1 end

	net.Start( CB.NET_INCOMING )
		net.WriteFloat( salvo.x )
		net.WriteFloat( salvo.y )
		net.WriteFloat( tof )
		net.WriteUInt( n, 8 )
	net.Broadcast()

	Radio( "Зоопарк", string.format( "Пуски противника: %d снаряд(ов) по %s. Прилёт через %d с!", n,
		gone and "старой позиции" or "вашей позиции", math.Round( tof ) ) )

	RevealBattery( bat )

	-- the crew stays: the next salvo comes, more accurate
	local st = salvo.spot

	if IsValid( spg ) and CB.Spots[ spg ] == st and st.lock then
		local lock = st.lock

		lock.err = math.max( lock.err * REFINE, MIN_ERR )

		local r = lock.err * math.Rand( 0.3, 1 )

		lock.x, lock.y = st.x + lock.dx * r, st.y + lock.dy * r

		ScheduleSalvo( spg, st, ( t - Now() ) + tof + math.Rand( REPEAT[ 1 ], REPEAT[ 2 ] ) )
	end
end

-- Damage -------------------------------------------------------------------------------------------

-- share of the 2S35 max HP lost to one 152 mm burst d metres from the hull edge
function CB.DamageShare( d )
	if d <= 2 then return 0.75 end
	if d <= 12 then return 0.75 - ( d - 2 ) / 10 * 0.6 end
	if d <= 30 then return 0.15 * ( 1 - ( d - 12 ) / 18 ) end

	return 0
end

local BlockUntil, BlockPos = 0, nil

-- the SW Bombs warhead of our burst must not hit the 2S35 on top of our own damage model
hook.Add( "EntityTakeDamage", "SkyOps.Arty.Counter", function( ent )
	if CB.Applying or Now() > BlockUntil or not BlockPos then return end

	local SPG = SPGApi()

	if SPG and SPG.IsSPG( ent ) and ent:GetPos():Distance( BlockPos ) < 100 * Grid.UPM() then return true end
end )

local function ApplyDamage( spg, dmg, pos )
	local before = spg:GetHP()
	local target = before - dmg
	local world = game.GetWorld()

	CB.Applying = true

	local info = DamageInfo()

	info:SetDamage( dmg )
	info:SetDamageType( DMG_BLAST )
	info:SetAttacker( world )
	info:SetInflictor( world )
	info:SetDamagePosition( pos )

	spg:TakeDamageInfo( info )

	-- the LVS armour may have soaked it: the model decides, not the armour
	if IsValid( spg ) and spg:GetHP() > target then
		if target <= 0 then
			spg:TakeDamage( 100000, world, world )
		elseif isfunction( spg.SetHP ) then
			spg:SetHP( target )
		end
	end

	CB.Applying = false
end

local function DamageSPGs( pos )
	local SPG = SPGApi()

	if not SPG then return end

	local upm = Grid.UPM()

	for _, spg in ipairs( ents.FindByClass( SPG.CLASS ) ) do
		local d = math.max( spg:GetPos():Distance( pos ) / upm - HULL, 0 )

		if CB.Spots[ spg ] or d < 100 then
			CB.Stats.closest = math.min( CB.Stats.closest or d, d )
		end

		local share = CB.DamageShare( d ) * CB.cvDamage:GetFloat() * math.Rand( 0.8, 1.2 )
		local destroyed = isfunction( spg.IsDestroyed ) and spg:IsDestroyed()

		if share > 0 and isfunction( spg.GetHP ) and not destroyed then
			local max = isfunction( spg.GetMaxHP ) and spg:GetMaxHP() or 1000

			ApplyDamage( spg, share * max, pos )

			CB.Stats.damage = CB.Stats.damage + share

			local hp = IsValid( spg ) and spg:GetHP() or 0

			Radio( "Экипаж", hp > 0 and string.format( "Разрыв в %d м! САУ повреждена, осталось %d%%.", math.Round( d ), math.Round( hp / max * 100 ) ) or "Прямое попадание! САУ уничтожена." )
		end
	end
end

hook.Add( "SkyOps.Arty.ShellImpact", "SkyOps.Arty.Counter", function( shell, pos )
	if shell.data and shell.data.counter then
		BlockUntil, BlockPos = Now() + 1, pos

		B.Explode( pos, shell.def.blast, nil )
		DamageSPGs( pos )

		return true -- exploded here; the ballistics must not explode it a second time
	end

	-- our shells against the enemy battery
	local bat = CB.Battery

	if not bat or bat.silenced or #bat.targets == 0 then return end

	local x, y = Grid.ToGrid( pos )

	if Dist( x, y, bat.x, bat.y ) > 400 then return end

	local M = Missions()
	local res = M.Targets.Burst( bat.targets, x, y, shell.shell, shell.attacker )

	if #res.killed > 0 then
		if M.Targets.CountAlive( bat.targets ) == 0 then
			Silence( bat )
		else
			Radio( "Зоопарк", "Орудие батареи противника уничтожено. Осталось " .. M.Targets.CountAlive( bat.targets ) .. "." )
		end
	end
end )

-- Think ---------------------------------------------------------------------------------------------

local NextThink = 0

hook.Add( "Think", "SkyOps.Arty.Counter", function()
	if Now() < NextThink then return end

	NextThink = Now() + 0.2

	-- the mission the battery belonged to is gone (cleared, aborted or a new one)
	local bat = CB.Battery
	local M = Missions()

	if bat and bat.run and ( not M or M.Run ~= bat.run ) then CB.ClearBattery() end

	if CB.Mode() <= 0 then
		CB.Salvos, CB.Queue = {}, {}
		return
	end

	-- the crew drove off a spot: shots start counting anew
	for spg, st in pairs( CB.Spots ) do
		if not IsValid( spg ) then
			CB.Spots[ spg ] = nil
		else
			local x, y = Grid.ToGrid( spg:GetPos() )

			if Dist( x, y, st.x, st.y ) > CB.MOVE_RADIUS then
				if st.lock then CB.Stats.moves = CB.Stats.moves + 1 end

				CB.Spots[ spg ] = nil
				UpdateNW( spg, nil )
			end
		end
	end

	local now = Now()

	for i = #CB.Salvos, 1, -1 do
		local s = CB.Salvos[ i ]

		if now >= s.at then
			table.remove( CB.Salvos, i )
			FireSalvo( s )
		end
	end

	for i = #CB.Queue, 1, -1 do
		local q = CB.Queue[ i ]

		if now >= q.at then
			table.remove( CB.Queue, i )
			FireShell( q )
		end
	end
end )

-- Missions ------------------------------------------------------------------------------------------

local function ResetAll()
	for spg in pairs( CB.Spots ) do UpdateNW( spg, nil ) end

	-- enemy shells still in the air from the last mission must not land on the new one
	for _, shell in pairs( B.Active ) do
		if shell.data.counter then B.Remove( shell ) end
	end

	CB.Spots, CB.Salvos, CB.Queue = {}, {}, {}
	CB.ClearBattery()
	ResetStats()
end

CB.Reset = ResetAll

hook.Add( "SkyOps.Arty.MissionStart", "SkyOps.Arty.Counter", function()
	ResetAll()

	if CB.Mode() > 0 then
		Radio( "Штаб", "У противника есть контрбатарейный радар: после нескольких выстрелов с одного места ждите ответный огонь. Стреляйте и меняйте позицию." )
	end
end )

hook.Add( "SkyOps.Arty.MissionEnd", "SkyOps.Arty.Counter", function( run )
	CB.Salvos, CB.Queue = {}, {}

	local s = CB.Stats

	if CB.Mode() <= 0 or ( s.salvos == 0 and s.moves == 0 ) then return end

	local text = string.format( "Ответный огонь: залпов %d, снарядов %d, увернулись %d раз, смен позиции %d, урон САУ %d%%.",
		s.salvos, s.fired, s.dodged, s.moves, math.Round( math.min( s.damage, 1 ) * 100 ) )

	if s.silenced then text = text .. " Батарея противника подавлена." end

	Radio( "Штаб", text )

	run.counter = table.Copy( s )
end )

hook.Add( "PlayerInitialSpawn", "SkyOps.Arty.Counter", function( ply )
	timer.Simple( 5, function()
		if IsValid( ply ) and CB.Battery then SendBattery( ply ) end
	end )
end )

-- Console --------------------------------------------------------------------------------------------

concommand.Add( "skyops_arty_counter_reset", function( ply )
	if IsValid( ply ) and not ply:IsAdmin() and not game.SinglePlayer() then return end

	ResetAll()
	print( "[Arty counter] reset" )
end, nil, "Сбросить контрбатарейную борьбу: засечки, залпы, батарею противника" )

-- test: lock the position of the 2S35 you sit in right now (the salvo follows after the delay)
concommand.Add( "skyops_arty_counter_test", function( ply )
	if IsValid( ply ) and not ply:IsAdmin() and not game.SinglePlayer() then return end

	local SPG = SPGApi()
	local spg = IsValid( ply ) and SPG and SPG.Of( ply )

	if not spg then
		print( "[Arty counter] sit in a 2S35 first" )
		return
	end

	local x, y = Grid.ToGrid( spg:GetPos() )
	local st = NewSpot( x, y )

	st.detected = st.need
	CB.Spots[ spg ] = st

	Lock( spg, st, nil )
	UpdateNW( spg, st )

	print( "[Arty counter] position locked, salvo in about " .. CB.cvDelay:GetInt() .. " s" )
end, nil, "Тест: противник сразу засекает САУ, в которой вы сидите" )

concommand.Add( "skyops_arty_counter_status", function( ply )
	if IsValid( ply ) and not ply:IsAdmin() and not game.SinglePlayer() then return end

	local bat = CB.Battery

	print( string.format( "[Arty counter] mode %d, battery %s, salvos pending %d, shells queued %d",
		CB.Mode(), bat and ( Grid.Format( bat.x, bat.y ) .. ( BatteryAlive( bat ) and "" or " (silenced)" ) ) or "none", #CB.Salvos, #CB.Queue ) )

	for spg, st in pairs( CB.Spots ) do
		print( string.format( "  %s at %s: tracked %d/%d%s", tostring( spg ), Grid.Format( st.x, st.y ), st.detected, st.need,
			st.lock and string.format( ", LOCKED err %d m", math.Round( st.lock.err ) ) or "" ) )
	end

	local s = CB.Stats

	print( string.format( "  stats: salvos %d, shells %d, dodged %d, moves %d, damage %d%%", s.salvos, s.fired, s.dodged, s.moves, math.Round( s.damage * 100 ) ) )
end )
