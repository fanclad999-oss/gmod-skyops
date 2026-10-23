-- Разведка: пролететь маршрут на малой высоте и «сфотографировать» объект.
-- Самая простая миссия для обучения, без обязательного боя.

SkyOps.Missions.Register({
	id = "recon_flyover",
	name = "Тихий рассвет",
	type = "recon",
	map = "kirovskoe",

	briefing = {
		situation = "Нужны свежие снимки моста у Хрестовки перед наступлением. ПВО в районе слабое, но у моста замечен «Роланд». Идите низко, держите скорость.",
		time = "06:15",
		weather = "Дымка, видимость 8 км",
	},

	aircraft = {
		{ role = "tornado_ids", crew = 2, loadout_text = { "Контейнер разведки", "AIM-9L × 2", "BK-27 · 360" } },
		{ role = "su25sm3", crew = 1, loadout_text = { "Б-8М1 × 2", "Р-73 × 2", "ГШ-30-2 · 250" } },
	},

	start = { anchor = "airfield_main", airborne = true, alt = 500, speed = 600 },

	waypoints = {
		{ id = "WP1", anchor = "forest_east", radius = 1500 },
		{ id = "TGT", anchor = "bridge_khrest", radius = 800, label = "МОСТ" },
		{ id = "WP2", anchor = "valley_south", radius = 1500 },
	},

	units = {
		{ id = "roland", kind = "airdefense", system = "roland", anchor = "bridge_khrest_sam", briefing = true },
	},

	objectives = {
		{ id = "wp1", type = "reach", waypoint = "WP1", text = "Пройти WP1" },
		{ id = "photo", type = "recon", waypoint = "TGT", max_alt = 250, time = 6, after = "wp1", text = "Снять мост: 6 сек над целью ниже 250 м" },
		{ id = "egress", type = "reach", waypoint = "WP2", after = "photo", text = "Уйти через WP2" },
		{ id = "rtb", type = "land", anchor = "airfield_main", after = "egress", text = "Посадка на аэродроме" },
	},

	fail = { crew_dead = true },

	score = { wp1 = 100, photo = 500, egress = 150, rtb = 250, grades = { S = 1000, A = 850, B = 650, C = 400 } },
})
