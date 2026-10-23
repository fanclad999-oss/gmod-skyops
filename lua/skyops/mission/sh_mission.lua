-- SkyOps: реестр миссий и общие константы движка миссий (shared)
-- Формат миссий описан в docs/missions.md

SkyOps = SkyOps or {}
SkyOps.Missions = SkyOps.Missions or {}

local M = SkyOps.Missions

M.List = M.List or {}

M.STATE_IDLE = 0
M.STATE_BRIEFING = 1
M.STATE_RUNNING = 2
M.STATE_DEBRIEF = 3

M.OBJ_PENDING = 0
M.OBJ_ACTIVE = 1
M.OBJ_DONE = 2
M.OBJ_FAILED = 3

M.SEAT_PILOT = 1
M.SEAT_WSO = 2

M.NET = {
	"skyops_brief",    -- S->C: статичная часть брифинга
	"skyops_lobby",    -- S->C: слоты экипажей и готовность
	"skyops_slot",     -- C->S: занять / освободить место
	"skyops_ready",    -- C->S: готов / не готов
	"skyops_state",    -- S->C: состояние миссии
	"skyops_obj",      -- S->C: изменение задачи
	"skyops_msg",      -- S->C: радиосообщение
	"skyops_debrief",  -- S->C: итоги миссии
	"skyops_sync",     -- C->S: запрос текущего состояния (поздний вход)
	"skyops_list",     -- S->C: список миссий для меню
}

-- Типы задач, которые понимает движок (sv_objectives.lua)
M.ObjectiveTypes = {
	reach = true,
	destroy = true,
	recon = true,
	land = true,
	protect = true,
	defend = true,
	survive = true,
}

-- Дальность поражения для брифинга, метры. Ядро может переопределить через SkyOps.AirDefense.GetRange
M.ThreatRange = {
	s75 = 43000,
	tor_m1 = 12000,
	roland = 6300,
	aaa = 2500,
}

M.ThreatName = {
	s75 = "С-75 «Двина»",
	tor_m1 = "Тор-М1",
	roland = "Roland",
	aaa = "Зенитная артиллерия",
}

M.ObjectiveTypeName = {
	strike = "УДАР ПО НАЗЕМНОЙ ЦЕЛИ",
	recon = "РАЗВЕДКА",
	sead = "ПОДАВЛЕНИЕ ПВО",
	intercept = "ПЕРЕХВАТ",
}

-- Единицы. В Source 1 юнит = 1 дюйм, так же считает LVS (km/h = u/s * 0.09144)
SkyOps.Conv = SkyOps.Conv or {}

local U = SkyOps.Conv

U.M_PER_U = 0.0254

function U.ToMeters( u ) return u * 0.0254 end
function U.FromMeters( m ) return m / 0.0254 end
function U.ToFeet( u ) return u / 12 end
function U.ToKmh( ups ) return ups * 0.09144 end
function U.ToKnots( ups ) return ups * 0.0254 * 1.943844 end
function U.ToMps( ups ) return ups * 0.0254 end

-- Стандартная атмосфера (ISA): плотность и скорость звука на высоте h (м)
function U.ISA( h )
	h = math.Clamp( h, -500, 20000 )

	local T
	local p

	if h <= 11000 then
		T = 288.15 - 0.0065 * h
		p = 101325 * (T / 288.15) ^ 5.25588
	else
		T = 216.65
		p = 22632 * math.exp( -0.000157689 * (h - 11000) )
	end

	local rho = p / (287.05 * T)
	local a = math.sqrt( 1.4 * 287.05 * T )

	return rho, a
end

-- Приборная скорость из истинной (м/с) на высоте h (м)
function U.IAS( tas, h )
	local rho = U.ISA( h )

	return tas * math.sqrt( rho / 1.225 )
end

function U.Mach( tas, h )
	local _, a = U.ISA( h )

	return tas / a
end

-- Регистрация миссии. Все расстояния и высоты в файлах миссий указываются в метрах.
local function Warn( id, text )
	ErrorNoHalt( "[SkyOps] Миссия '" .. tostring( id ) .. "': " .. text .. "\n" )
end

function M.Validate( def )
	local id = def.id
	local ok = true

	if not isstring( def.name ) then Warn( id, "нет name" ) ok = false end
	if not istable( def.aircraft ) or #def.aircraft == 0 then Warn( id, "нет aircraft" ) ok = false end
	if not istable( def.objectives ) or #def.objectives == 0 then Warn( id, "нет objectives" ) ok = false end

	local wps = {}
	for _, wp in ipairs( def.waypoints or {} ) do
		wps[ wp.id ] = true
	end

	local units = {}
	for _, unit in ipairs( def.units or {} ) do
		if units[ unit.id ] then Warn( id, "повтор id юнита " .. unit.id ) ok = false end
		units[ unit.id ] = true
	end

	local objs = {}
	for _, obj in ipairs( def.objectives or {} ) do
		if not M.ObjectiveTypes[ obj.type ] then
			Warn( id, "неизвестный тип задачи " .. tostring( obj.type ) )
			ok = false
		end

		if obj.waypoint and not wps[ obj.waypoint ] then Warn( id, "задача " .. obj.id .. " ссылается на неизвестный WP " .. obj.waypoint ) ok = false end
		if obj.unit and not units[ obj.unit ] then Warn( id, "задача " .. obj.id .. " ссылается на неизвестный юнит " .. obj.unit ) ok = false end
		if obj.after and not objs[ obj.after ] then Warn( id, "задача " .. obj.id .. ": after должен ссылаться на задачу выше по списку" ) ok = false end

		objs[ obj.id ] = true
	end

	return ok
end

function M.Register( def )
	if not istable( def ) or not isstring( def.id ) then
		ErrorNoHalt( "[SkyOps] Missions.Register: нужна таблица с полем id\n" )

		return
	end

	if not M.Validate( def ) then return end

	def.flights = def.flights or 2
	def.callsign = def.callsign or "Гром"

	M.List[ def.id ] = def
end

function M.Get( id )
	return M.List[ id ]
end
