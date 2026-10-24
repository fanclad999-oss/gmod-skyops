-- Loadouts of Ryuunosuke aircraft, by role. id = the aircraft's own loadout
-- index (ent:SetLoadout(id)), tags let missions filter: aa, rockets, bombs,
-- guided (laser/TV/sat), asm (air-to-surface missile), arm (anti-radiation).
-- Built-in guns and short-range AAMs are listed in `always`.

SkyOps.Registry = SkyOps.Registry or {} -- sh_registry.lua loads after this file

local L = {}
SkyOps.Registry.Loadouts = L

local function list( always, rows )
	local out = { always = always }
	for i, row in ipairs( rows ) do
		out[ i ] = { id = i, name = row[1], tags = row[2] or {} }
	end
	return out
end

L.su34 = list( "ГШ-30-1, Р-73 ×4", {
	{ "Р-27Р ×5", { "aa" } },
	{ "НАР С-8 (Б-8М)", { "rockets" } },
	{ "НАР С-13 (Б-13)", { "rockets" } },
	{ "НАР С-25-О", { "rockets" } },
	{ "ОФАБ-100", { "bombs" } },
	{ "ОФАБ-250", { "bombs" } },
	{ "ОФАБ-250ШН", { "bombs" } },
	{ "ФАБ-250М54", { "bombs" } },
	{ "ФАБ-250М62", { "bombs" } },
	{ "ФАБ-500ШН", { "bombs" } },
	{ "ФАБ-500М54", { "bombs" } },
	{ "ФАБ-500М62", { "bombs" } },
	{ "ОДАБ-500", { "bombs" } },
	{ "ФАБ-1500М54", { "bombs" } },
	{ "ФАБ-3000М54", { "bombs" } },
	{ "ФАБ-250М54 с УМПК", { "guided", "bombs" } },
	{ "ФАБ-250М62 с УМПК", { "guided", "bombs" } },
	{ "ФАБ-500М54 с УМПК", { "guided", "bombs" } },
	{ "ФАБ-500М62 с УМПК", { "guided", "bombs" } },
	{ "КАБ-500Л", { "guided", "bombs" } },
	{ "КАБ-500Кр", { "guided", "bombs" } },
	{ "КАБ-500ОД", { "guided", "bombs" } },
	{ "КАБ-500С", { "guided", "bombs" } },
	{ "ФАБ-1500М54 с УМПК", { "guided", "bombs" } },
	{ "КАБ-1500Кр", { "guided", "bombs" } },
	{ "ФАБ-3000М54 с УМПК", { "guided", "bombs" } },
	{ "Гром-Э2", { "guided", "bombs" } },
	{ "Гром-Э1", { "asm" } },
	{ "Х-29Л", { "asm" } },
	{ "Х-29Т", { "asm" } },
	{ "Х-38МЛ", { "asm" } },
	{ "Х-38МТ", { "asm" } },
	{ "Х-35 (противокорабельная)", { "asm" } },
	{ "Х-31П (противорадиолокационная)", { "asm", "arm" } },
	{ "Х-59", { "asm" } },
} )

L.su25sm3 = list( "ГШ-30-2, Р-73 ×2", {
	{ "НАР С-5 (УБ-16)", { "rockets" } },
	{ "НАР С-5 (УБ-32)", { "rockets" } },
	{ "НАР С-8 (Б-8М)", { "rockets" } },
	{ "НАР С-13 (Б-13)", { "rockets" } },
	{ "НАР С-24", { "rockets" } },
	{ "НАР С-25-О", { "rockets" } },
	{ "НАР С-25-ОФ", { "rockets" } },
	{ "НАР С-25-ОФМ", { "rockets" } },
	{ "С-25Л (лазерная)", { "rockets", "guided" } },
	{ "Х-25МЛ ×4", { "asm" } },
	{ "Х-29Л ×2", { "asm" } },
	{ "Х-29Т ×2", { "asm" } },
	{ "Х-38МЛ ×4", { "asm" } },
	{ "Х-38МТ ×4", { "asm" } },
	{ "ОФАБ-100", { "bombs" } },
	{ "ОФАБ-250", { "bombs" } },
	{ "ОФАБ-250ШН", { "bombs" } },
	{ "ФАБ-250М62", { "bombs" } },
	{ "ФАБ-500М62", { "bombs" } },
	{ "ФАБ-500ШН", { "bombs" } },
	{ "КАБ-250ЛГ", { "guided", "bombs" } },
	{ "КАБ-500Л", { "guided", "bombs" } },
	{ "КАБ-500Кр", { "guided", "bombs" } },
	{ "КАБ-500ОД", { "guided", "bombs" } },
	{ "КАБ-500С", { "guided", "bombs" } },
	{ "ФАБ-250М62 с УМПК", { "guided", "bombs" } },
	{ "ФАБ-500М62 с УМПК", { "guided", "bombs" } },
	{ "УПК-23-250 (пушечные контейнеры)", {} },
} )

L.tornado_ids = list( "BK-27 ×2, AIM-9L ×2", {
	{ "Без подвески", {} },
	{ "Mk 81", { "bombs" } },
	{ "Mk 82", { "bombs" } },
	{ "Mk 83", { "bombs" } },
	{ "Mk 84", { "bombs" } },
	{ "Mk 81 Snakeye", { "bombs" } },
	{ "Mk 82 AIR", { "bombs" } },
	{ "Mk 83 AIR", { "bombs" } },
	{ "Mk 84 AIR", { "bombs" } },
	{ "GBU-12", { "guided", "bombs" } },
	{ "GBU-16", { "guided", "bombs" } },
	{ "GBU-24", { "guided", "bombs" } },
	{ "GBU-38", { "guided", "bombs" } },
	{ "GBU-32", { "guided", "bombs" } },
	{ "GBU-31", { "guided", "bombs" } },
	{ "MW-1 (кассетный контейнер)", { "bombs" } },
} )

L.f14a = list( "M61, AIM-9 ×2", {
	{ "Без подвески", {} },
	{ "AIM-54 ×6", { "aa" } },
	{ "AIM-7 ×5", { "aa" } },
	{ "Mk 81 ×12", { "bombs" } },
	{ "Mk 82 ×12", { "bombs" } },
	{ "Mk 83 ×4", { "bombs" } },
	{ "Mk 84 ×4", { "bombs" } },
	{ "Mk 81 Snakeye ×12", { "bombs" } },
	{ "Mk 82 Snakeye ×12", { "bombs" } },
	{ "Mk 83 AIR ×4", { "bombs" } },
	{ "Mk 84 AIR ×4", { "bombs" } },
} )

function SkyOps.Registry.GetLoadouts( role )
	return L[ role ]
end

-- loadouts of a role carrying every given tag, e.g. FindLoadouts( "su34", "arm" )
function SkyOps.Registry.FindLoadouts( role, ... )
	local want, out = { ... }, {}
	for _, lo in ipairs( L[ role ] or {} ) do
		local ok = true
		for _, tag in ipairs( want ) do
			if not table.HasValue( lo.tags, tag ) then ok = false break end
		end
		if ok then out[ #out + 1 ] = lo end
	end
	return out
end
