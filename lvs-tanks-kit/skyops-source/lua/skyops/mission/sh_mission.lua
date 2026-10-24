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
	"skyops_loadout",  -- C->S: пилот выбрал подвеску
	"skyops_ready",    -- C->S: готов / не готов
	"skyops_state",    -- S->C: состояние миссии
	"skyops_obj",      -- S->C: изменение задачи
	"skyops_msg",      -- S->C: радиосообщение
	"skyops_debrief",  -- S->C: итоги миссии
	"skyops_sync",     -- C->S: запрос текущего состояния (поздний вход)
	"skyops_list",     -- S->C: список миссий для меню
	"skyops_unitdown", -- S->C: группа юнитов уничтожена целиком (для меток на экране)
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

-- Единицы. Масштаб берём у ядра (SkyOps.HU_TO_M): карта Кировское построена из расчёта
-- 40 юнитов на метр, а не дюймовой шкалы Source. Без ядра считаем 1 юнит = 1 дюйм, как LVS.
SkyOps.Conv = SkyOps.Conv or {}

local U = SkyOps.Conv

local function MPerU()
	return SkyOps.HU_TO_M or 0.0254
end

function U.ToMeters( u ) return u * MPerU() end
function U.FromMeters( m ) return m / MPerU() end
function U.ToFeet( u ) return u * MPerU() * 3.28084 end
function U.ToKmh( ups ) return ups * MPerU() * 3.6 end
function U.ToKnots( ups ) return ups * MPerU() * 1.943844 end
function U.ToMps( ups ) return ups * MPerU() end

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

-- Подвески, разрешённые миссией для самолёта: список { id, name } из реестра ядра.
-- В миссии: loadouts = { tags = { "bombs", "asm" }, default = 21 }; без tags разрешены все.
function M.AllowedLoadouts( ac )
	local reg = SkyOps.Registry and SkyOps.Registry.GetLoadouts and SkyOps.Registry.GetLoadouts( ac.role )
	local out = {}

	if not reg then return out, nil end

	local tags = ac.loadouts and ac.loadouts.tags

	for _, lo in ipairs( reg ) do
		local ok = not tags or #tags == 0

		for _, want in ipairs( tags or {} ) do
			for _, have in ipairs( lo.tags or {} ) do
				if have == want then ok = true end
			end
		end

		if ok then table.insert( out, { id = lo.id, name = lo.name } ) end
	end

	return out, reg.always
end

function M.DefaultLoadout( ac )
	local allowed = M.AllowedLoadouts( ac )
	local want = ac.loadouts and ac.loadouts.default

	for _, lo in ipairs( allowed ) do
		if lo.id == want then return want end
	end

	return allowed[1] and allowed[1].id or nil
end

function M.IsLoadoutAllowed( ac, id )
	for _, lo in ipairs( (M.AllowedLoadouts( ac )) ) do
		if lo.id == id then return true end
	end

	return false
end

function M.Get( id )
	return M.List[ id ]
end
