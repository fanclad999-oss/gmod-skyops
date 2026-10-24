-- Artillery missions, shared part: mission types, range bands, target kinds, the damage
-- model and the stage list. The server (sv_missions, sv_targets) runs a mission, the
-- client (cl_missions) shows the menu, the HUD and the debrief.
--
-- A mission is: drive the 2S35 to a firing position (ОП), deploy there, get the target
-- (coordinates from HQ, or a search area that the drone has to clear), destroy it within
-- the ammunition budget. Targets are frozen props (or LVS vehicles) placed on the terrain
-- kilometres away; hits are judged by our own damage model from the impact point, so it
-- works in InfMap chunks with no player and no terrain collider around.

SkyOps = SkyOps or {}
SkyOps.Arty = SkyOps.Arty or {}
SkyOps.Arty.Missions = SkyOps.Arty.Missions or {}

local M = SkyOps.Arty.Missions

M.STAGE_NONE = 0
M.STAGE_MARCH = 1   -- drive to the firing position
M.STAGE_DEPLOY = 2  -- deploy the gun on it
M.STAGE_RECON = 3   -- the drone looks for the target in the search area
M.STAGE_FIRE = 4    -- target known, fire for effect
M.STAGE_DONE = 5    -- debrief

M.StageNames = {
	[ M.STAGE_NONE ] = "нет задания",
	[ M.STAGE_MARCH ] = "марш на ОП",
	[ M.STAGE_DEPLOY ] = "развёртывание",
	[ M.STAGE_RECON ] = "разведка цели",
	[ M.STAGE_FIRE ] = "огонь",
	[ M.STAGE_DONE ] = "итоги",
}

M.NET_STATE = "skyops_artym_state"
M.NET_MSG = "skyops_artym_msg"
M.NET_DEBRIEF = "skyops_artym_debrief"
M.NET_REQ = "skyops_artym_req"
M.NET_MENU = "skyops_artym_menu"

M.FP_RADIUS = 150      -- m, how close to the firing position point counts as "on it"
M.HIT_RADIUS = 50      -- m, an impact this close to a live target counts as a hit in the stats
M.OBSERVE_RANGE = 7000 -- m, a drone this close to the impact reports the burst

-- Range bands from the firing position to the target, metres. Max ranges of the
-- fire computer: HE full charge ~39 km, Krasnopol ~26 km.
M.Ranges = {
	{ id = "near", name = "Близко", min = 4000, max = 8000 },
	{ id = "mid", name = "Средне", min = 8000, max = 15000 },
	{ id = "far", name = "Далеко", min = 15000, max = 24000 },
}

function M.GetRange( id )
	for _, r in ipairs( M.Ranges ) do
		if r.id == id then return r end
	end

	return M.Ranges[ 2 ]
end

-- Target kinds. armor picks the lethal radii below; model is an HL2 model so it is always
-- there; lvs = optional LVS classes tried first (a real vehicle that burns when killed).
M.TargetKinds = {
	truck = { name = "Грузовик", armor = "soft", score = 100, model = "models/props_vehicles/truck001a.mdl" },
	fuel = { name = "Топливозаправщик", armor = "soft", score = 120, model = "models/props_vehicles/truck003a.mdl" },
	car = { name = "Командирская машина", armor = "soft", score = 150, model = "models/props_vehicles/car002a_physics.mdl" },
	apc = { name = "БТР", armor = "light", score = 150, model = "models/props_vehicles/apc001.mdl" },
	trailer = { name = "Прицеп с БК", armor = "soft", score = 80, model = "models/props_vehicles/trailer002a.mdl" },
	cp = { name = "Командный пункт", armor = "light", score = 300, model = "models/props_vehicles/truck002a_cab.mdl", hvt = true },
	gun = { name = "Орудие", armor = "light", score = 200, model = "models/props_c17/trappropeller_engine.mdl" },
}

-- Lethal radii in metres from the target edge: full damage inside inner, none past outer.
-- Rough for a 152 mm HE shell (blast + fragments against a stationary target).
M.Armor = {
	soft = { inner = 8, outer = 30 },
	light = { inner = 4, outer = 15 },
	heavy = { inner = 1.5, outer = 5 },
}

-- damage multiplier of each shell (Krasnopol carries less explosive than the HE round)
M.ShellPower = { he = 1, krasnopol = 0.85 }

-- damage 0..100 to a target of armor `armor` from a burst `d` metres from its edge
function M.Damage( armor, d, shellId )
	local a = M.Armor[ armor ] or M.Armor.soft
	local f

	if d <= a.inner then
		f = 1
	elseif d >= a.outer then
		f = 0
	else
		-- the chance to kill falls off roughly with the square of the distance
		f = 1 - ( ( d - a.inner ) / ( a.outer - a.inner ) ) ^ 0.7
	end

	return 100 * f * ( M.ShellPower[ shellId ] or 1 )
end

-- Mission types.
--   intel = "hq": HQ passes the target coordinates (with an error in hardcore)
--   intel = "drone": HQ passes a search area; the drone has to find and send the target
--   group: what is spawned (kind = count); spread = group radius, m
--   ammo: shell budget per type; need: share of targets to kill (0..1)
--   fleeting: seconds from target known until the survivors drive away
M.Types = {
	{
		id = "raid",
		name = "Огневой налёт",
		desc = "Штаб передал координаты колонны на привале. Выдвинуться на огневую позицию, развернуться и накрыть цель. Координаты штаба с ошибкой, поправки по разрывам.",
		intel = "hq",
		hqError = 60,
		group = { truck = 3, fuel = 1, trailer = 1 },
		spread = 90,
		ammo = { he = 24, krasnopol = 0 },
		need = 0.8,
	},
	{
		id = "recon",
		name = "Цель по дрону",
		desc = "Разведка засекла позицию батареи в районе, но точно её не знает. Поднять дрон, найти цель в указанном районе, передать координаты на САУ и поразить.",
		intel = "drone",
		area = 500,
		group = { gun = 3, truck = 2 },
		spread = 120,
		ammo = { he = 20, krasnopol = 2 },
		need = 0.8,
	},
	{
		id = "laser",
		name = "Краснополь по подсветке",
		desc = "Одиночный командный пункт противника. ОФС его не взять: только Краснополь. Дрон находит КП и держит лазер, САУ стреляет управляемыми.",
		intel = "drone",
		area = 400,
		group = { cp = 1, car = 1 },
		spread = 25,
		ammo = { he = 0, krasnopol = 4 },
		armorOverride = { cp = "heavy" },
		need = 0.5,
		required = { cp = true },
	},
	{
		id = "fleeting",
		name = "Скоротечная цель",
		desc = "Колонна дозаправляется и уйдёт через несколько минут после обнаружения. Быстро выдвинуться, развернуться и открыть огонь, пока цели стоят. Уцелевшие уходят на новое место.",
		intel = "hq",
		hqError = 40,
		group = { apc = 2, fuel = 2, truck = 2 },
		spread = 70,
		ammo = { he = 30, krasnopol = 2 },
		need = 0.65,
		fleeting = 240,
	},
}

function M.GetType( id )
	for _, t in ipairs( M.Types ) do
		if t.id == id then return t end
	end
end

-- Grade from the share of the maximum score
M.Grades = {
	{ "S", 0.9 },
	{ "A", 0.75 },
	{ "B", 0.55 },
	{ "C", 0.35 },
	{ "D", 0 },
}

function M.Grade( frac )
	for _, g in ipairs( M.Grades ) do
		if frac >= g[ 2 ] then return g[ 1 ] end
	end

	return "D"
end

-- "12:05"
function M.FmtTime( s )
	s = math.max( math.floor( s or 0 ), 0 )

	return string.format( "%d:%02d", math.floor( s / 60 ), s % 60 )
end

-- "1-25" mils
function M.FmtMils( m )
	m = math.Round( m ) % 6000

	return string.format( "%d-%02d", math.floor( m / 100 ), m % 100 )
end

-- deviation of point p from target t along the gun-target line: lat > 0 right, rng > 0 over
function M.Deviation( gx, gy, tx, ty, px, py )
	local dx, dy = tx - gx, ty - gy
	local len = math.max( math.sqrt( dx * dx + dy * dy ), 1 )
	local ux, uy = dx / len, dy / len
	local ex, ey = px - tx, py - ty

	return ex * uy - ey * ux, ex * ux + ey * uy
end

-- "правее 40, дальше 120" (same wording as the fire computer)
function M.FmtDeviation( lat, rng )
	local a = math.Round( math.abs( lat ) / 5 ) * 5
	local b = math.Round( math.abs( rng ) / 5 ) * 5

	return ( lat >= 0 and "правее " or "левее " ) .. a .. ", " .. ( rng >= 0 and "дальше " or "ближе " ) .. b
end

-- Big JSON over net in one go (state and debrief are a few KB at most)
function M.WriteTable( t )
	local data = util.Compress( util.TableToJSON( t ) or "{}" ) or ""

	net.WriteUInt( #data, 16 )
	net.WriteData( data, #data )
end

function M.ReadTable()
	local len = net.ReadUInt( 16 )
	local data = len > 0 and net.ReadData( len ) or ""
	local json = data ~= "" and util.Decompress( data ) or nil

	return json and util.JSONToTable( json ) or {}
end
