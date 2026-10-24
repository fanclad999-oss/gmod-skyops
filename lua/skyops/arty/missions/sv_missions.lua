-- Artillery missions, server: one mission at a time for 1-2 players.
--
--   march   -> drive the 2S35 into the firing position circle (ОП)
--   deploy  -> deploy the gun there (H)
--   recon   -> intel "drone": find the target in the search area with a drone camera
--              lock or the drone module's "send"; intel "hq": HQ sends coordinates
--   fire    -> shells of the mission gun are judged where they land (sv_targets)
--   done    -> debrief with stats, score and grade, also appended to
--              data/skyops/arty_missions.json
--
-- Uses only the arty core API (Grid, SPG, Ballistics hooks) and, when present, the drone
-- module hook SkyOps.Arty.TargetSent( drone, worldPos, err_m, ply ).

local M = SkyOps.Arty.Missions
local Grid = SkyOps.Arty.Grid

util.AddNetworkString( M.NET_STATE )
util.AddNetworkString( M.NET_MSG )
util.AddNetworkString( M.NET_DEBRIEF )
util.AddNetworkString( M.NET_REQ )
util.AddNetworkString( M.NET_MENU )
util.AddNetworkString( "skyops_arty_target" ) -- also the drone module's; we send HQ coordinates through it

local cvHqDelay = CreateConVar( "skyops_arty_mission_hq_delay", "20", FCVAR_ARCHIVE, "Seconds after deployment until HQ sends the target coordinates", 0, 600 )
local cvRefine = CreateConVar( "skyops_arty_mission_refine", "180", FCVAR_ARCHIVE, "Seconds of fruitless drone search until HQ narrows the search area (0 = never)", 0, 1800 )

local HISTORY_FILE = "skyops/arty_missions.json"
local HISTORY_MAX = 50
local LOCK_RADIUS = 80 -- m, a drone camera lock this close to a live target finds it
local LOCK_TIME = 3    -- s the lock has to be held
local UAV = { sw_zala = "ZALA", sw_orlan10 = "Орлан-10", sw_pchela1t = "Пчела-1Т", sw_ravenseye = "Raven's Eye" }
local KIT_DRONES = { "sw_orlan10", "sw_zala", "sw_pchela1t", "sw_ravenseye" }

M.Run = M.Run or nil

local function SPGApi() return SkyOps.Arty.SPG end

local function Now() return CurTime() end

-- Players ------------------------------------------------------------------------------

local Teams = SkyOps.Teams

-- team vs team (core/sh_teams.lua): a mission belongs to the side of its leader; the other
-- side does not see its state, cannot join and its drones do not count. Off: always true.
local function OwnSide( run, ent )
	local team = run and run.team or 0

	if not Teams.TvT() or team == 0 then return true end

	local t = Teams.Of( ent )

	return t == 0 or t == team
end

local function Players( run )
	local list = {}

	for ply in pairs( run.players ) do
		if IsValid( ply ) then list[ #list + 1 ] = ply end
	end

	return list
end

function M.CanControl( ply )
	if not IsValid( ply ) then return true end -- server console

	return ply:IsAdmin() or game.SinglePlayer() or #player.GetHumans() <= 2
end

-- radio line to the mission crew (or to one player)
function M.Radio( run, from, text, to )
	net.Start( M.NET_MSG )
		net.WriteString( from )
		net.WriteString( text )

	if to then
		net.Send( to )
	elseif run then
		net.Send( Players( run ) )
	else
		net.Broadcast()
	end

	print( "[Arty mission] " .. from .. ": " .. text )
end

local function Tell( ply, text )
	if IsValid( ply ) then
		M.Radio( nil, "Задания", text, ply )
	else
		print( "[Arty mission] " .. text )
	end
end

-- Objectives -----------------------------------------------------------------------------

local OBJ_OPEN, OBJ_DONE, OBJ_FAIL = 0, 1, 2

local function Objective( run, id )
	for _, o in ipairs( run.objectives ) do
		if o.id == id then return o end
	end
end

local function SetObjective( run, id, state )
	local o = Objective( run, id )

	if o and o.state ~= state then o.state = state end
end

local function BuildObjectives( run )
	local def, fp = run.def, run.fp
	local list = {}

	if run.opts.march then
		list[ #list + 1 ] = { id = "march", text = "Выдвинуться на ОП: " .. Grid.Format( fp.x, fp.y ), state = OBJ_OPEN }
	end

	list[ #list + 1 ] = { id = "deploy", text = "Развернуть САУ на огневой позиции", state = OBJ_OPEN }

	if def.intel == "drone" then
		list[ #list + 1 ] = { id = "intel", text = "Найти цель дроном в районе и передать координаты", state = OBJ_OPEN }
	else
		list[ #list + 1 ] = { id = "intel", text = "Получить координаты цели от штаба", state = OBJ_OPEN }
	end

	local need = run.need
	local text = string.format( "Уничтожить не менее %d из %d целей", need, #run.targets )

	if def.required then text = text .. " (КП обязательно)" end

	list[ #list + 1 ] = { id = "destroy", text = text, state = OBJ_OPEN }

	local ammo = {}

	if ( def.ammo.he or 0 ) > 0 then ammo[ #ammo + 1 ] = "ОФС " .. def.ammo.he end
	if ( def.ammo.krasnopol or 0 ) > 0 then ammo[ #ammo + 1 ] = "Краснополь " .. def.ammo.krasnopol end

	list[ #list + 1 ] = { id = "ammo", text = "Уложиться в БК: " .. table.concat( ammo, ", " ), state = OBJ_OPEN, optional = true }

	return list
end

-- State to the client ---------------------------------------------------------------------

local function BuildState( run )
	if not run then return { stage = M.STAGE_NONE } end

	local names = {}

	for ply, role in pairs( run.players ) do
		if IsValid( ply ) then names[ #names + 1 ] = { name = ply:Nick(), role = role, leader = ply == run.leader } end
	end

	local st = {
		stage = run.stage,
		type = run.def.id,
		name = run.def.name,
		desc = run.def.desc,
		intelKind = run.def.intel,
		range = run.range.name,
		mode = SPGApi() and SPGApi().Mode() or "hardcore",
		start = run.start,
		stageStart = run.stageStart,
		fp = { x = run.fp.x, y = run.fp.y, r = M.FP_RADIUS },
		area = run.area and { x = run.area.x, y = run.area.y, r = run.area.r } or nil,
		intel = run.intel and { x = run.intel.x, y = run.intel.y, err = run.intel.err, src = run.intel.src, time = run.intel.time } or nil,
		alive = M.Targets.CountAlive( run.targets ),
		total = #run.targets,
		need = run.need,
		used = run.used,
		ammo = run.def.ammo,
		inflight = run.inflight,
		objectives = run.objectives,
		players = names,
		leaves = run.leaves,
		hasSPG = IsValid( run.spg ),
	}

	-- in the auto mode the crew sees where every live target stands (training aid)
	if st.mode == "auto" and run.intel then
		st.targets = {}

		for _, t in ipairs( run.targets ) do
			st.targets[ #st.targets + 1 ] = { x = t.x, y = t.y, alive = t.alive, name = t.name }
		end
	end

	return st
end

function M.SendState( to )
	local run = M.Run

	-- team vs team: the other side only learns that no mission of theirs runs
	if run and Teams.TvT() and ( run.team or 0 ) ~= 0 then
		local own, other = {}, {}

		for _, ply in ipairs( to and { to } or player.GetAll() ) do
			if OwnSide( run, ply ) then own[ #own + 1 ] = ply else other[ #other + 1 ] = ply end
		end

		if #own > 0 then
			net.Start( M.NET_STATE )
				M.WriteTable( BuildState( run ) )
			net.Send( own )
		end

		if #other > 0 then
			net.Start( M.NET_STATE )
				M.WriteTable( BuildState( nil ) )
			net.Send( other )
		end

		return
	end

	net.Start( M.NET_STATE )
		M.WriteTable( BuildState( run ) )

	if to then
		net.Send( to )
	elseif run then
		-- everybody sees that a mission runs (so a second player can join)
		net.Broadcast()
	else
		net.Broadcast()
	end
end

local function Dirty( run ) run.dirty = true end

-- Stages ----------------------------------------------------------------------------------

local function SetStage( run, stage )
	if run.stage == stage then return end

	run.stage = stage
	run.stageStart = Now()
	run.stageTimes[ stage ] = Now()

	hook.Run( "SkyOps.Arty.MissionStage", run, stage )

	Dirty( run )
end

local function GridOf( ent )
	local x, y = Grid.ToGrid( ent:GetPos() )

	return x, y
end

local function DistToFP( run, ent )
	local x, y = GridOf( ent )

	return math.sqrt( ( x - run.fp.x ) ^ 2 + ( y - run.fp.y ) ^ 2 )
end

-- the target becomes known: from HQ (with an error) or from the drone (where it looked)
local function Reveal( run, x, y, err, src )
	run.intel = { x = x, y = y, err = err, src = src, time = Now() }
	run.intelCount = ( run.intelCount or 0 ) + 1
	run.firstIntelAt = run.firstIntelAt or Now()
	run.lockTime = 0

	SetObjective( run, "intel", OBJ_DONE )

	local text = string.format( "Координаты цели: %s, высота %d м.", Grid.Format( x, y ), math.Round( Grid.Height( x, y ) or 0 ) )

	if ( err or 0 ) > 0 then text = text .. string.format( " Точность до %d м.", math.Round( err ) ) end

	-- a fleeting target leaves once; after the move it stays put
	if run.def.fleeting and not run.leaves and not run.relocated then
		run.leaves = Now() + run.def.fleeting
		text = text .. " Цель уйдёт через " .. M.FmtTime( run.def.fleeting ) .. "."
	end

	M.Radio( run, src == "штаб" and "Штаб" or "Дрон", text )

	-- the fire computer of every crew member gets the point, like a drone "send"
	-- same layout as the drone module: floats, WriteVector loses precision far out on InfMap
	local wp = Grid.FromGrid( x, y )

	net.Start( "skyops_arty_target" )
		net.WriteFloat( wp.x )
		net.WriteFloat( wp.y )
		net.WriteFloat( wp.z )
		net.WriteFloat( err or 0 )
		net.WriteEntity( run.intelDrone or NULL )
	net.Send( Players( run ) )

	-- found before the gun stood ready: the deploy stage moves on to firing by itself
	if run.stage == M.STAGE_RECON then SetStage( run, M.STAGE_FIRE ) end

	Dirty( run )
end

local function RevealHQ( run )
	local cx, cy = M.Targets.Center( run.targets )

	if not cx then return end

	local hard = SPGApi() and SPGApi().Mode() == "hardcore"
	local e = hard and ( run.def.hqError or 0 ) or 0
	local a = math.Rand( 0, 2 * math.pi )
	local r = e * math.sqrt( math.Rand( 0, 1 ) )

	Reveal( run, math.Round( cx + math.cos( a ) * r, -1 ), math.Round( cy + math.sin( a ) * r, -1 ), e, "штаб" )
end

-- Ending ------------------------------------------------------------------------------------

local function Clamp01( x ) return math.Clamp( x, 0, 1 ) end

local function Score( run, success )
	local s = { lines = {} }
	local function Add( name, pts, max )
		s.lines[ #s.lines + 1 ] = { name = name, pts = math.Round( pts ), max = max }
	end

	local kills, maxKills = 0, 0

	for _, t in ipairs( run.targets ) do
		maxKills = maxKills + t.score
		if not t.alive then kills = kills + t.score end
	end

	Add( "Уничтоженные цели", kills, maxKills )

	-- first shot after the target became known
	local first = run.firstAimed
	local fpts = 0

	if first then
		if first.miss < 25 then fpts = 150 elseif first.miss < 75 then fpts = 100 elseif first.miss < 150 then fpts = 50 end
	end

	Add( "Первый выстрел", fpts, 150 )

	-- shells: fewer is better; the minimum is about 1.5 per target
	local used = ( run.used.he or 0 ) + ( run.used.krasnopol or 0 )
	local budget = ( run.def.ammo.he or 0 ) + ( run.def.ammo.krasnopol or 0 )
	local minimum = math.max( math.ceil( run.need * 1.5 ), 1 )
	local eff = used > 0 and Clamp01( ( budget - used ) / math.max( budget - minimum, 1 ) ) or 0

	Add( "Расход снарядов", success and 200 * eff or 0, 200 )

	-- reaction: target known -> first kill
	local react = 0

	if run.firstIntelAt and run.firstKillAt then
		react = 200 * Clamp01( 1 - ( run.firstKillAt - run.firstIntelAt - 60 ) / 540 )
	end

	Add( "Время реакции", react, 200 )

	local maxMarch = 0

	if run.opts.march then
		maxMarch = 100

		local t = run.stageTimes[ M.STAGE_DEPLOY ] and ( run.stageTimes[ M.STAGE_DEPLOY ] - run.start ) or nil

		Add( "Марш на ОП", t and 100 * Clamp01( 1 - ( t - 120 ) / 480 ) or 0, 100 )
	end

	local over = run.overspend or 0

	if over > 0 then Add( "Сверх БК", -50 * over ) end

	local total, max = 0, maxKills + 150 + 200 + 200 + maxMarch

	for _, l in ipairs( s.lines ) do total = total + l.pts end

	total = math.max( total, 0 )

	local frac = total / max
	local grade = M.Grade( frac )

	-- the auto mode is a training aid
	if run.mode == "auto" and ( grade == "S" ) then grade = "A" end
	if not success and ( grade == "S" or grade == "A" or grade == "B" ) then grade = "C" end

	s.total, s.max, s.grade = total, max, grade

	return s
end

local function SaveHistory( rec )
	file.CreateDir( "skyops" )

	local list = util.JSONToTable( file.Read( HISTORY_FILE, "DATA" ) or "" ) or {}

	table.insert( list, 1, rec )

	while #list > HISTORY_MAX do table.remove( list ) end

	file.Write( HISTORY_FILE, util.TableToJSON( list, true ) )
end

local function LoadHistory()
	return util.JSONToTable( file.Read( HISTORY_FILE, "DATA" ) or "" ) or {}
end

function M.End( success, reason )
	local run = M.Run

	if not run or run.stage == M.STAGE_DONE then return end

	SetStage( run, M.STAGE_DONE )

	if success then
		SetObjective( run, "destroy", OBJ_DONE )
		if Objective( run, "ammo" ) and ( run.overspend or 0 ) == 0 then SetObjective( run, "ammo", OBJ_DONE ) end
	else
		for _, o in ipairs( run.objectives ) do
			if o.state == OBJ_OPEN and not o.optional then o.state = OBJ_FAIL end
		end
	end

	if ( run.overspend or 0 ) > 0 then SetObjective( run, "ammo", OBJ_FAIL ) end

	local score = Score( run, success )
	local hits, misses, sum, best = 0, 0, 0, nil

	for _, shot in ipairs( run.shots ) do
		if shot.miss then
			sum = sum + shot.miss
			misses = misses + 1
			best = math.min( best or shot.miss, shot.miss )
			if shot.miss <= M.HIT_RADIUS then hits = hits + 1 end
		end
	end

	local killed = {}

	for _, t in ipairs( run.targets ) do
		killed[ #killed + 1 ] = { name = t.name, alive = t.alive, hp = math.max( math.Round( t.hp ), 0 ) }
	end

	local names = {}

	for _, ply in ipairs( Players( run ) ) do names[ #names + 1 ] = ply:Nick() end

	local st = run.stageTimes
	local deb = {
		success = success,
		reason = reason,
		name = run.def.name,
		type = run.def.id,
		range = run.range.name,
		distance = run.distance,
		mode = run.mode,
		duration = Now() - run.start,
		marchTime = run.opts.march and st[ M.STAGE_DEPLOY ] and ( st[ M.STAGE_DEPLOY ] - run.start ) or nil,
		deployTime = st[ M.STAGE_DEPLOY ] and ( ( st[ M.STAGE_RECON ] or st[ M.STAGE_FIRE ] or Now() ) - st[ M.STAGE_DEPLOY ] ) or nil,
		searchTime = st[ M.STAGE_RECON ] and run.firstIntelAt and ( run.firstIntelAt - st[ M.STAGE_RECON ] ) or nil,
		reaction = run.firstIntelAt and run.firstKillAt and ( run.firstKillAt - run.firstIntelAt ) or nil,
		firstShotDelay = run.firstIntelAt and run.firstAimed and ( run.firstAimed.t - run.firstIntelAt ) or nil,
		used = run.used,
		ammo = run.def.ammo,
		shots = #run.shots,
		hits = hits,
		avgMiss = misses > 0 and sum / misses or nil,
		bestMiss = best,
		firstMiss = run.firstAimed and run.firstAimed.miss or nil,
		targets = killed,
		objectives = run.objectives,
		score = score,
		players = names,
		shotLog = {},
	}

	for i, shot in ipairs( run.shots ) do
		if i > 40 then break end

		deb.shotLog[ i ] = { t = shot.t - run.start, shell = shot.shell, miss = shot.miss, lat = shot.lat, rng = shot.rng, kills = shot.kills }
	end

	SaveHistory( {
		date = os.date( "%Y-%m-%d %H:%M" ),
		type = deb.type, name = deb.name, range = deb.range, mode = deb.mode,
		success = success, score = score.total, grade = score.grade,
		duration = math.Round( deb.duration ), shots = deb.shots, players = names,
	} )

	net.Start( M.NET_DEBRIEF )
		M.WriteTable( deb )
	net.Send( Players( run ) )

	M.Radio( run, "Штаб", success and "Задача выполнена. " .. ( reason or "" ) or "Задача не выполнена: " .. ( reason or "" ) )

	hook.Run( "SkyOps.Arty.MissionEnd", run, deb )

	Dirty( run )
end

-- removes the targets and forgets the mission
function M.Clear()
	local run = M.Run

	if not run then return end

	M.Targets.RemoveAll( run.targets )
	M.Run = nil
	M.SendState()
end

-- Starting ----------------------------------------------------------------------------------

local function SpawnClass( class, pos, ang, ply )
	if not scripted_ents.GetStored( class ) then return NULL end

	local ent = ents.Create( class )

	if not IsValid( ent ) then return NULL end

	ent:SetPos( pos )
	ent:SetAngles( ang )
	ent:Spawn()
	ent:Activate()

	if isfunction( ent.SetAITEAM ) then ent:SetAITEAM( SkyOps.Teams and SkyOps.Teams.BLUE or 1 ) end

	-- team vs team: the kit belongs to the player's side (arty/tvt)
	if IsValid( ply ) and SkyOps.Teams.Claim then SkyOps.Teams.Claim( ent, ply ) end

	return ent
end

-- a 2S35 and a drone (with a catapult if it needs one) next to the player
local function SpawnKit( ply, run )
	local upm = Grid.UPM()
	local yaw = Angle( 0, ply:EyeAngles().y, 0 )
	local fwd, right = yaw:Forward(), yaw:Right()
	local base = ply:GetPos()
	local function At( f, r )
		local p = base + fwd * f * upm + right * r * upm
		local x, y = Grid.ToGrid( p )
		local z = Grid.FromGrid( x, y ).z

		p.z = math.max( z, base.z - 20 * upm ) + 60

		return p
	end

	local spawned = {}
	local spg = SpawnClass( "sw_2s35", At( 12, 0 ), yaw, ply )

	if IsValid( spg ) then
		spawned[ #spawned + 1 ] = "2С35"
		run.spg = spg
	end

	for _, class in ipairs( KIT_DRONES ) do
		local stored = scripted_ents.GetStored( class )

		if stored then
			local drone = SpawnClass( class, At( 0, 18 ), yaw, ply )

			if IsValid( drone ) then
				spawned[ #spawned + 1 ] = UAV[ class ]

				if stored.t and stored.t.CatapultLaunchable then
					if IsValid( SpawnClass( "sw_uav_catapult", At( -4, 30 ), yaw, ply ) ) then spawned[ #spawned + 1 ] = "катапульта" end
				end
			end

			break
		end
	end

	return spawned
end

local function FindSPGFor( ply )
	local SPG = SPGApi()

	if not SPG then return nil end

	local spg = SPG.Of( ply )

	if spg then return spg end

	-- the nearest empty 2S35 within 100 m
	local best, bestD

	for _, ent in ipairs( ents.FindByClass( SPG.CLASS ) ) do
		local d = ent:GetPos():Distance( ply:GetPos() )

		if d < 100 * Grid.UPM() and Teams.Friendly( ply, ent ) and ( not bestD or d < bestD ) then best, bestD = ent, d end
	end

	return best
end

-- opts = { type = id, range = id, march = bool, kit = bool }
function M.Start( ply, opts )
	if not Grid or not Grid.ToGrid or not SkyOps.Arty.Ballistics then
		Tell( ply, "Нет модуля баллистики (arty/core): задания не работают." )
		return false
	end

	local def = M.GetType( opts.type ) or M.Types[ 1 ]
	local range = M.GetRange( opts.range )

	if not IsValid( ply ) then
		ply = player.GetHumans()[ 1 ]
		if not IsValid( ply ) then return false end
	end

	-- one mission at a time: in team vs team the other side may not cancel ours
	if M.Run and M.Run.stage ~= M.STAGE_DONE and Teams.TvT() and not OwnSide( M.Run, ply ) then
		Tell( ply, "Сейчас идёт задание другой команды. Дождитесь его конца." )
		return false
	end

	if M.Run then M.Clear() end

	local run = {
		def = def,
		range = range,
		opts = { march = opts.march ~= false, kit = opts.kit == true },
		mode = SPGApi() and SPGApi().Mode() or "hardcore",
		players = { [ ply ] = "командир" },
		leader = ply,
		team = Teams.Of( ply ),
		start = Now(),
		stageStart = Now(),
		stage = M.STAGE_NONE,
		stageTimes = {},
		used = { he = 0, krasnopol = 0 },
		inflight = 0,
		shots = {},
		lockTime = 0,
	}

	local kit = run.opts.kit and SpawnKit( ply, run ) or nil

	run.spg = run.spg or FindSPGFor( ply )

	-- where the crew stands now
	local ref = IsValid( run.spg ) and run.spg or ply
	local gx, gy = Grid.ToGrid( ref:GetPos() )

	local fx, fy, fh

	if run.opts.march then
		fx, fy, fh = M.Targets.FindSpot( gx, gy, 1500, 3000 )
	end

	if not fx then
		run.opts.march = false
		fx, fy, fh = gx, gy, Grid.Height( gx, gy ) or 0
	end

	-- the enemy side: pick a bearing, then a flat spot in the range band
	local tx, ty
	local band = { min = range.min, max = range.max }

	for _ = 1, 4 do
		tx, ty = M.Targets.FindSpot( fx, fy, band.min, band.max, math.Rand( 0, 6000 ), 600, 40 )

		if tx then break end

		tx, ty = M.Targets.FindSpot( fx, fy, band.min, band.max, nil, 3000, 80 )

		if tx then break end

		-- the map is too small for this band
		band.min, band.max = band.min * 0.5, band.max * 0.6
	end

	if not tx then
		Tell( ply, "Не нашлось места для цели на этой карте." )
		return false
	end

	run.fp = { x = fx, y = fy, h = fh }
	run.distance = math.sqrt( ( tx - fx ) ^ 2 + ( ty - fy ) ^ 2 )
	run.targets = M.Targets.SpawnGroup( def, tx, ty )

	if #run.targets == 0 then
		Tell( ply, "Не удалось расставить цели." )
		return false
	end

	run.need = math.max( math.ceil( #run.targets * def.need ), 1 )

	if def.intel == "drone" then
		local a, r = math.Rand( 0, 2 * math.pi ), def.area * math.Rand( 0.2, 0.6 )

		run.area = { x = math.Round( tx + math.cos( a ) * r, -1 ), y = math.Round( ty + math.sin( a ) * r, -1 ), r = def.area }
	end

	run.objectives = BuildObjectives( run )

	M.Run = run

	SetStage( run, run.opts.march and M.STAGE_MARCH or M.STAGE_DEPLOY )

	local bearing = Grid.Bearing( fx, fy, tx, ty )
	local lines = { def.name .. ". " .. range.name .. ", около " .. math.Round( run.distance / 1000 ) .. " км." }

	if run.opts.march then
		lines[ #lines + 1 ] = "ОП: " .. Grid.Format( fx, fy ) .. "."
	else
		lines[ #lines + 1 ] = "Огневая позиция здесь."
	end

	lines[ #lines + 1 ] = "Направление стрельбы около " .. M.FmtMils( math.Round( bearing / 100 ) * 100 ) .. "."

	if run.area then
		lines[ #lines + 1 ] = "Район поиска: " .. Grid.Format( run.area.x, run.area.y ) .. ", радиус " .. run.area.r .. " м."
	end

	M.Radio( run, "Штаб", table.concat( lines, " " ) )

	if kit then
		M.Radio( run, "Задания", #kit > 0 and ( "Выдано: " .. table.concat( kit, ", " ) .. "." ) or "Технику выдать не удалось: аддоны 2С35 и дронов не найдены." )
	end

	if not IsValid( run.spg ) then
		M.Radio( run, "Задания", "Сядьте в 2С35: первая САУ, в которую сядет участник, станет орудием задания." )
	end

	hook.Run( "SkyOps.Arty.MissionStart", run )

	M.SendState()

	return true
end

function M.Join( ply, role )
	local run = M.Run

	if not run or not IsValid( ply ) then return end
	if not OwnSide( run, ply ) then return Tell( ply, "Это задание другой команды." ) end

	run.players[ ply ] = role or run.players[ ply ] or "оператор дрона"

	M.Radio( run, "Задания", ply:Nick() .. " в расчёте: " .. run.players[ ply ] .. "." )
	M.SendState()
end

function M.Leave( ply )
	local run = M.Run

	if not run or not run.players[ ply ] then return end

	run.players[ ply ] = nil

	if run.leader == ply then run.leader = Players( run )[ 1 ] end

	Dirty( run )
end

-- Drone intel ---------------------------------------------------------------------------------

local function TryDroneFix( run, drone, pos, err, ply )
	-- a later send while firing just moves the aim point (the drone module tells the
	-- fire computer itself), nothing to judge here
	if not run or run.intel or run.stage >= M.STAGE_FIRE then return end

	local x, y = Grid.ToGrid( pos )
	local t, d = M.Targets.Nearest( run.targets, x, y )

	if not t then return end

	if d <= LOCK_RADIUS + ( err or 0 ) then
		run.intelDrone = drone

		-- the drone camera is a sensor: its point is where it looked, not the true target
		Reveal( run, math.Round( x ), math.Round( y ), err or 10, "дрон " .. ( IsValid( drone ) and UAV[ drone:GetClass() ] or "" ) )
	elseif IsValid( ply ) then
		M.Radio( run, "Штаб", string.format( "Переданная точка %s: цели там не видно (ближайшая в %d м).", Grid.Format( x, y ), math.Round( d / 50 ) * 50 ), ply )
	end
end

-- the drone module (arty/drone) calls this when the operator presses "send"
hook.Add( "SkyOps.Arty.TargetSent", "SkyOps.Arty.Missions", function( drone, pos, err, ply )
	if M.Run and OwnSide( M.Run, drone ) then TryDroneFix( M.Run, drone, pos, err, ply ) end
end )

-- the drone module asks where to put a drone in the air for this player's mission:
-- the search area, else the known target point, else roughly (+-400 m) the target group
hook.Add( "SkyOps.Arty.DroneDeployPoint", "SkyOps.Arty.Missions", function( ply )
	local run = M.Run

	if not run or run.stage == M.STAGE_DONE or not run.players[ ply ] then return end

	local x, y

	if run.intel then
		x, y = run.intel.x, run.intel.y
	elseif run.area then
		x, y = run.area.x, run.area.y
	else
		run.roughPoint = run.roughPoint or { math.Rand( -400, 400 ), math.Rand( -400, 400 ) }

		local cx, cy = M.Targets.Center( run.targets )

		if not cx then return end

		x, y = cx + run.roughPoint[ 1 ], cy + run.roughPoint[ 2 ]
	end

	return Grid.FromGrid( x, y )
end )

-- without the drone module: a stock camera lock (NWVector TrackPos) held on the target
local function PollDroneLocks( run, dt )
	local best

	for class in pairs( UAV ) do
		for _, drone in ipairs( ents.FindByClass( class ) ) do
			local tp = drone:GetNWVector( "TrackPos", vector_origin )

			if OwnSide( run, drone ) and isvector( tp ) and tp:LengthSqr() > 100 then
				local x, y = Grid.ToGrid( tp )
				local t, d = M.Targets.Nearest( run.targets, x, y )

				if t and d <= LOCK_RADIUS then best = { drone = drone, pos = tp } break end
			end
		end

		if best then break end
	end

	if best then
		run.lockTime = run.lockTime + dt

		if run.lockTime >= LOCK_TIME then
			TryDroneFix( run, best.drone, best.pos, 15, best.drone:GetDriver() )
		end
	else
		run.lockTime = 0
	end
end

-- Shells ----------------------------------------------------------------------------------------

local function IsMissionShot( run, spg, shell )
	if IsValid( run.spg ) then return spg == run.spg end

	-- no gun bound yet: the first 2S35 a crew member fires binds
	if IsValid( shell.owner ) and run.players[ shell.owner ] then
		run.spg = spg
		return true
	end

	return false
end

hook.Add( "SkyOps.Arty.SPGFired", "SkyOps.Arty.Missions", function( spg, shell )
	local run = M.Run

	if not run or run.stage == M.STAGE_DONE or not IsMissionShot( run, spg, shell ) then return end

	local id = shell.shell == "krasnopol" and "krasnopol" or "he"

	run.used[ id ] = ( run.used[ id ] or 0 ) + 1
	run.inflight = run.inflight + 1

	shell.data.mission = run
	shell.data.missionShot = { t = Now(), shell = id, aimed = run.intel ~= nil }

	if run.used[ id ] > ( run.def.ammo[ id ] or 0 ) then
		run.overspend = ( run.overspend or 0 ) + 1

		M.Radio( run, "Штаб", ( id == "he" and "ОФС" or "Краснополь" ) .. " сверх выделенного БК: штраф." )
	end

	Dirty( run )
end )

-- a nearby drone (or anyone in auto mode) reports the burst against the gun-target line
local function Observer( run, x, y )
	for class in pairs( UAV ) do
		for _, drone in ipairs( ents.FindByClass( class ) ) do
			local dx, dy = Grid.ToGrid( drone:GetPos() )

			if OwnSide( run, drone ) and ( dx - x ) ^ 2 + ( dy - y ) ^ 2 < M.OBSERVE_RANGE ^ 2 then return "Дрон" end
		end
	end

	if run.mode == "auto" then return "Наблюдатель" end
end

local function OnImpact( shell, pos )
	local run = shell.data and shell.data.mission

	if not run or run ~= M.Run or run.stage == M.STAGE_DONE then return end

	local x, y = Grid.ToGrid( pos )
	local nearest, nd = M.Targets.Nearest( run.targets, x, y )
	local res = M.Targets.Burst( run.targets, x, y, shell.shell, shell.attacker )
	local shot = shell.data.missionShot

	shot.miss = nd and math.max( nd - ( nearest and nearest.size or 0 ), 0 ) or nil
	shot.kills = #res.killed

	if nearest then
		shot.lat, shot.rng = M.Deviation( shell.start.x, shell.start.y, nearest.x, nearest.y, x, y )
	end

	run.shots[ #run.shots + 1 ] = shot

	if shot.aimed and not run.firstAimed and shot.miss then run.firstAimed = shot end

	local from = Observer( run, x, y )

	if #res.killed > 0 then
		run.firstKillAt = run.firstKillAt or Now()

		local names = {}

		for _, t in ipairs( res.killed ) do names[ #names + 1 ] = t.name end

		M.Radio( run, from or "Штаб", "Цель поражена: " .. table.concat( names, ", " ) .. ". Осталось " .. M.Targets.CountAlive( run.targets ) .. "." )
	elseif from and shot.lat then
		local text = "Разрыв: " .. M.FmtDeviation( shot.lat, shot.rng )

		if #res.damaged > 0 then text = text .. ". Есть повреждения" end

		M.Radio( run, from, text .. "." )
	elseif not from then
		run.unseen = ( run.unseen or 0 ) + 1

		if run.unseen == 1 or run.unseen % 5 == 0 then
			M.Radio( run, "Штаб", "Разрывы никто не наблюдает: поднимите дрон к цели." )
		end
	end

	Dirty( run )
end

hook.Add( "SkyOps.Arty.ShellImpact", "SkyOps.Arty.Missions", OnImpact )

hook.Add( "SkyOps.Arty.ShellRemoved", "SkyOps.Arty.Missions", function( shell )
	local run = shell.data and shell.data.mission

	if run and run == M.Run then
		run.inflight = math.max( run.inflight - 1, 0 )
		Dirty( run )
	end
end )

-- Think -----------------------------------------------------------------------------------------

local function Required( run )
	local killed = 0

	for _, t in ipairs( run.targets ) do
		if not t.alive then killed = killed + 1 elseif t.required then return false end
	end

	return killed >= run.need
end

local function AmmoLeft( run )
	for id, n in pairs( run.def.ammo ) do
		if n > ( run.used[ id ] or 0 ) then return true end
	end

	return false
end

local NextThink = 0

hook.Add( "Think", "SkyOps.Arty.Missions", function()
	local run = M.Run

	if not run then return end

	M.Targets.Think( run.targets )

	if Now() < NextThink then return end

	local dt = 0.5

	NextThink = Now() + dt

	if run.stage == M.STAGE_DONE then
		if run.dirty then run.dirty = false M.SendState() end
		return
	end

	local SPG = SPGApi()

	-- bind the gun: the 2S35 a crew member sits in
	if not IsValid( run.spg ) then
		if run.spgSeen then
			M.End( false, "САУ потеряна." )
			return
		end

		for _, ply in ipairs( Players( run ) ) do
			local spg = SPG and SPG.Of( ply )

			if spg then
				run.spg = spg
				M.Radio( run, "Задания", "Орудие задания: 2С35 игрока " .. ply:Nick() .. "." )
				Dirty( run )
				break
			end
		end
	end

	local spg = run.spg

	if IsValid( spg ) then
		run.spgSeen = true

		if spg.GetHP and spg:GetHP() <= 0 then
			M.End( false, "САУ уничтожена." )
			return
		end
	end

	if run.stage == M.STAGE_MARCH and IsValid( spg ) then
		if DistToFP( run, spg ) <= M.FP_RADIUS then
			SetObjective( run, "march", OBJ_DONE )
			SetStage( run, M.STAGE_DEPLOY )
			M.Radio( run, "Штаб", "Вы на огневой позиции. Развернуть орудие." )
		end
	elseif run.stage == M.STAGE_DEPLOY and IsValid( spg ) and SPG and SPG.IsDeployed( spg ) then
		if DistToFP( run, spg ) <= M.FP_RADIUS then
			SetObjective( run, "deploy", OBJ_DONE )

			if run.intel then
				SetStage( run, M.STAGE_FIRE )
			else
				SetStage( run, M.STAGE_RECON )

				if run.def.intel == "drone" then
					M.Radio( run, "Штаб", "Орудие к бою готово. Дрон в район поиска " .. Grid.Format( run.area.x, run.area.y ) .. ": найти цель, захватить камерой и передать координаты." )
				else
					M.Radio( run, "Штаб", "Орудие к бою готово. Ждите координаты." )
				end
			end
		elseif CurTime() > ( run.nextFarWarn or 0 ) then
			run.nextFarWarn = CurTime() + 20
			M.Radio( run, "Штаб", string.format( "Развёрнуты вне ОП (%d м до точки). Огонь не по плану.", math.Round( DistToFP( run, spg ) ) ) )
		end
	end

	-- a drone camera lock on the target counts at any time before the target is known
	if not run.intel and run.stage < M.STAGE_FIRE then PollDroneLocks( run, dt ) end

	if run.stage == M.STAGE_RECON and not run.intel then
		if run.def.intel == "hq" then
			if Now() - run.stageStart >= ( run.hqDelay or cvHqDelay:GetFloat() ) then RevealHQ( run ) end
		else

			-- a long fruitless search: HQ narrows the area around the real targets
			local refine = cvRefine:GetFloat()

			if refine > 0 and run.area and Now() - ( run.areaTime or run.stageStart ) > refine and run.area.r > 150 then
				local cx, cy = M.Targets.Center( run.targets )
				local r = math.max( math.Round( run.area.r / 2, -1 ), 150 )
				local a, off = math.Rand( 0, 2 * math.pi ), r * math.Rand( 0.1, 0.5 )

				run.area = { x = math.Round( cx + math.cos( a ) * off, -1 ), y = math.Round( cy + math.sin( a ) * off, -1 ), r = r }
				run.areaTime = Now()

				M.Radio( run, "Штаб", "Уточнение района: " .. Grid.Format( run.area.x, run.area.y ) .. ", радиус " .. r .. " м." )
				Dirty( run )
			end
		end
	end

	-- the fleeting target drives off; HQ / the drone has to find it again
	if run.leaves and Now() >= run.leaves and M.Targets.CountAlive( run.targets ) > 0 then
		run.leaves = nil

		local nx, ny = M.Targets.Relocate( run.targets, math.Rand( 400, 700 ) )

		if nx then
			run.relocated = true
			run.intel = nil
			run.area = { x = math.Round( nx, -1 ), y = math.Round( ny, -1 ), r = 600 }
			run.areaTime = Now()

			-- HQ catches up in 90 s, a drone camera lock is faster
			run.hqDelay = 90

			SetObjective( run, "intel", OBJ_OPEN )
			SetStage( run, M.STAGE_RECON )

			M.Radio( run, "Штаб", "Цели снимаются и уходят! Новый район: " .. Grid.Format( run.area.x, run.area.y ) .. ". Координаты через 1:30, дроном быстрее." )
		end
	end

	if Required( run ) then
		M.End( true, string.format( "Уничтожено %d из %d.", #run.targets - M.Targets.CountAlive( run.targets ), #run.targets ) )
		return
	end

	if not AmmoLeft( run ) and run.inflight == 0 then
		M.End( false, "БК израсходован." )
		return
	end

	if run.dirty then
		run.dirty = false
		M.SendState()
	end
end )

hook.Add( "PlayerDisconnected", "SkyOps.Arty.Missions", function( ply ) M.Leave( ply ) end )

-- Client requests ---------------------------------------------------------------------------------

local function SendMenu( ply )
	local avail = {
		spg = scripted_ents.GetStored( "sw_2s35" ) ~= nil,
		core = SkyOps.Arty.Ballistics ~= nil,
		drone = SkyOps.Arty.Drone ~= nil,
		kirov = KIR ~= nil and KIR.MeshHeight ~= nil,
		control = M.CanControl( ply ),
	}

	for class in pairs( UAV ) do
		if scripted_ents.GetStored( class ) then avail.uav = true end
	end

	net.Start( M.NET_MENU )
		M.WriteTable( { history = LoadHistory(), avail = avail } )
	net.Send( ply )
end

local LastReq = {}

net.Receive( M.NET_REQ, function( _, ply )
	if ( LastReq[ ply ] or 0 ) > CurTime() then return end

	LastReq[ ply ] = CurTime() + 0.3

	local cmd = net.ReadString()
	local args = M.ReadTable()

	if cmd == "menu" then
		SendMenu( ply )
		M.SendState( ply )
	elseif cmd == "sync" then
		M.SendState( ply )
	elseif cmd == "start" then
		if not M.CanControl( ply ) then return Tell( ply, "Начать задание может только админ." ) end

		M.Start( ply, { type = args.type, range = args.range, march = args.march, kit = args.kit } )
	elseif cmd == "join" then
		M.Join( ply, isstring( args.role ) and string.sub( args.role, 1, 32 ) or nil )
	elseif cmd == "leave" then
		M.Leave( ply )
		M.SendState()
	elseif cmd == "abort" then
		if not M.Run then return end
		if not ( M.CanControl( ply ) or M.Run.leader == ply ) then return end
		if not OwnSide( M.Run, ply ) then return end

		if M.Run.stage ~= M.STAGE_DONE then
			M.End( false, "Прервано: " .. ply:Nick() .. "." )
		end

		M.Clear()
	end
end )

hook.Add( "PlayerSay", "SkyOps.Arty.Missions", function( ply, text )
	local t = string.lower( string.Trim( text ) )

	if t == "!arty" or t == "!задание" or t == "!задания" then
		SendMenu( ply )
		M.SendState( ply )
		return ""
	end
end )

-- Console --------------------------------------------------------------------------------------------

local function Admin( ply ) return M.CanControl( ply ) end

concommand.Add( "skyops_arty_mission_start", function( ply, _, args )
	if not Admin( ply ) then return end

	M.Start( ply, { type = args[ 1 ] or "raid", range = args[ 2 ] or "mid", march = args[ 3 ] ~= "0", kit = args[ 4 ] == "1" } )
end, function( cmd )
	local out = {}

	for _, t in ipairs( M.Types ) do
		for _, r in ipairs( M.Ranges ) do out[ #out + 1 ] = cmd .. " " .. t.id .. " " .. r.id end
	end

	return out
end, "Начать задание: skyops_arty_mission_start <raid|recon|laser|fleeting> <near|mid|far> [марш 1/0] [выдать технику 0/1]" )

concommand.Add( "skyops_arty_mission_abort", function( ply )
	if not Admin( ply ) or not M.Run then return end

	if M.Run.stage ~= M.STAGE_DONE then M.End( false, "Прервано." ) end

	M.Clear()
end, nil, "Прервать задание и убрать цели" )

concommand.Add( "skyops_arty_mission_status", function( ply )
	local run = M.Run
	local function P( s ) if IsValid( ply ) then ply:PrintMessage( HUD_PRINTCONSOLE, s ) else print( s ) end end

	if not run then return P( "[Arty mission] нет задания" ) end

	P( string.format( "[Arty mission] %s, этап %s, ОП %s, дальность %.1f км, БК ОФС %d/%d Кр %d/%d, в полёте %d",
		run.def.name, M.StageNames[ run.stage ], Grid.Format( run.fp.x, run.fp.y ), run.distance / 1000,
		run.used.he, run.def.ammo.he or 0, run.used.krasnopol, run.def.ammo.krasnopol or 0, run.inflight ) )

	if Admin( ply ) then
		for i, t in ipairs( run.targets ) do
			P( string.format( "  #%d %s %s hp %d %s", i, t.name, Grid.Format( t.x, t.y ), math.Round( t.hp ), t.alive and "" or "(уничтожена)" ) )
		end
	end
end, nil, "Состояние задания (админу и координаты целей)" )

-- debug: HQ sends the target now (exact in auto mode)
concommand.Add( "skyops_arty_mission_reveal", function( ply )
	if not Admin( ply ) or not M.Run or M.Run.stage == M.STAGE_DONE then return end

	RevealHQ( M.Run )
end, nil, "Отладка: штаб сразу передаёт координаты цели" )

-- debug: skip the march and the deployment checks
concommand.Add( "skyops_arty_mission_skip", function( ply )
	local run = M.Run

	if not Admin( ply ) or not run or run.stage >= M.STAGE_RECON then return end

	SetObjective( run, "march", OBJ_DONE )
	SetObjective( run, "deploy", OBJ_DONE )
	SetStage( run, M.STAGE_RECON )
	M.Radio( run, "Задания", "Отладка: марш и развёртывание пропущены." )
end, nil, "Отладка: пропустить марш и развёртывание" )

-- debug: a burst dx, dy metres from the target centre without firing, through the same judging
concommand.Add( "skyops_arty_mission_simhit", function( ply, _, args )
	local run = M.Run

	if not Admin( ply ) or not run or run.stage == M.STAGE_DONE then return end

	local cx, cy = M.Targets.Center( run.targets )
	local x, y = cx + ( tonumber( args[ 1 ] ) or 0 ), cy + ( tonumber( args[ 2 ] ) or 0 )
	local shellId = args[ 3 ] == "krasnopol" and "krasnopol" or "he"
	local fake = {
		shell = shellId,
		start = { x = run.fp.x, y = run.fp.y },
		attacker = ply,
		data = {},
	}

	-- count it like a real shot of the mission gun
	run.used[ shellId ] = ( run.used[ shellId ] or 0 ) + 1
	if run.used[ shellId ] > ( run.def.ammo[ shellId ] or 0 ) then run.overspend = ( run.overspend or 0 ) + 1 end

	fake.data.mission = run
	fake.data.missionShot = { t = Now(), shell = shellId, aimed = run.intel ~= nil }

	OnImpact( fake, Grid.FromGrid( x, y ) )
end, nil, "Отладка: разрыв в dx dy метрах от центра цели: skyops_arty_mission_simhit <dx> <dy> [he|krasnopol]" )

concommand.Add( "skyops_arty_mission_history", function( ply )
	for i, r in ipairs( LoadHistory() ) do
		if i > 15 then break end

		local s = string.format( "%s  %-24s %-7s %-8s %s %4d очк. %s", r.date or "", r.name or "", r.range or "", r.mode or "", r.grade or "-", r.score or 0, r.success and "успех" or "провал" )

		if IsValid( ply ) then ply:PrintMessage( HUD_PRINTCONSOLE, s ) else print( s ) end
	end
end, nil, "Последние результаты заданий" )
