-- Удар по колонне: базовая ударная миссия для двухместного экипажа
-- Самолёты и ПВО указаны ролями из реестра ядра (su34, s75 ...), ядро само сопоставит их с классами

SkyOps.Missions.Register({
	id = "strike_convoy",
	name = "Операция «Грозовой фронт»",
	type = "strike",
	map = "kirovskoe",

	briefing = {
		situation = "Разведка засекла колонну снабжения противника (6 машин), идущую с севера к аэродрому. Колонну прикрывает «Тор-М1». В районе высоты 214 развёрнут дивизион С-75.",
		time = "05:40",
		weather = "Ясно, ветер 270/12",
	},

	aircraft = {
		{ role = "su34", crew = 2, loadout = "strike_kab500" },
		{ role = "tornado_ids", crew = 2, loadout = "strike_mk82" },
	},

	start = { anchor = "airfield_main", airborne = false },

	waypoints = {
		{ id = "WP1", anchor = "valley_south", radius = 1500 },
		{ id = "WP2", anchor = "road_ip", radius = 1500, label = "IP" },
		{ id = "WP3", anchor = "lake_west", radius = 2000 },
	},

	units = {
		{ id = "convoy", kind = "convoy", class = "skyops_truck", count = 6, route = "road_north", briefing = true, label = "Колонна" },
		{ id = "tor", kind = "airdefense", system = "tor_m1", follow = "convoy", briefing = true },
		{ id = "sa2", kind = "airdefense", system = "s75", anchor = "hill_214", briefing = true },
	},

	objectives = {
		{ id = "ingress", type = "reach", waypoint = "WP1", max_alt = 300, text = "Пройти WP1 на высоте ниже 300 м" },
		{ id = "kill_convoy", type = "destroy", unit = "convoy", count = 4, after = "ingress", text = "Уничтожить не менее 4 из 6 машин колонны" },
		{ id = "kill_tor", type = "destroy", unit = "tor", count = 1, optional = true, text = "Доп.: подавить «Тор-М1» прикрытия" },
		{ id = "rtb", type = "land", anchor = "airfield_main", after = "kill_convoy", text = "Вернуться и сесть на аэродроме" },
	},

	fail = { crew_dead = true, time_limit = 40 * 60 },

	score = {
		ingress = 100, kill_convoy = 400, kill_tor = 250, rtb = 250,
		per_kill = 25,
		grades = { S = 1000, A = 850, B = 650, C = 400 },
	},
})
