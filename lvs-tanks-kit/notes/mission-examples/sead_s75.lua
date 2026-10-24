-- Подавление ПВО: уничтожить дивизион С-75 по частям (РЛС, станция наведения, ПУ).
-- Тут как раз нужна работа ШО: найти цели и навести оружие.

SkyOps.Missions.Register({
	id = "sead_s75",
	name = "Открыть небо",
	type = "sead",
	map = "kirovskoe",

	briefing = {
		situation = "Дивизион С-75 у высоты 214 закрывает северный сектор для всей авиации. Первым делом выбейте РЛС П-12 и станцию наведения СНР-75: без них пусковые слепы.",
		time = "13:00",
		weather = "Облачность 3/8, нижняя кромка 1500 м",
	},

	aircraft = {
		{ role = "su34", crew = 2, loadout = "sead_kh25" },
		{ role = "tornado_ids", crew = 2, loadout = "sead_alarm" },
	},

	start = { anchor = "airfield_main", airborne = false },

	waypoints = {
		{ id = "WP1", anchor = "valley_south", radius = 1500 },
		{ id = "IP", anchor = "ridge_west", radius = 1500 },
	},

	units = {
		{ id = "p12", kind = "airdefense", system = "s75", part = "p12_radar", anchor = "hill_214", briefing = true, label = "РЛС П-12" },
		{ id = "snr", kind = "airdefense", system = "s75", part = "snr75", anchor = "hill_214", briefing = true, label = "СНР-75" },
		{ id = "launchers", kind = "airdefense", system = "s75", part = "launcher", count = 4, anchor = "hill_214", label = "ПУ" },
		{ id = "aaa", kind = "airdefense", system = "aaa", count = 2, anchor = "hill_214" },
	},

	objectives = {
		{ id = "ip", type = "reach", waypoint = "IP", text = "Выйти на IP" },
		{ id = "radar", type = "destroy", unit = "p12", count = 1, after = "ip", text = "Уничтожить РЛС П-12" },
		{ id = "snr", type = "destroy", unit = "snr", count = 1, after = "ip", text = "Уничтожить станцию наведения СНР-75" },
		{ id = "launchers", type = "destroy", unit = "launchers", count = 4, optional = true, text = "Доп.: уничтожить все пусковые" },
		{ id = "rtb", type = "land", anchor = "airfield_main", after = "snr", text = "Вернуться на аэродром" },
	},

	fail = { crew_dead = true, time_limit = 45 * 60 },

	score = { ip = 100, radar = 300, snr = 300, launchers = 300, rtb = 250, grades = { S = 1150, A = 950, B = 700, C = 450 } },
})
