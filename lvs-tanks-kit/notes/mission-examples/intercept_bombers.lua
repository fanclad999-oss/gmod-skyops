-- Перехват: не дать группе ударных самолётов дойти до аэродрома.
-- Миссия с таймером: старт в воздухе, цели уже летят.

SkyOps.Missions.Register({
	id = "intercept_bombers",
	name = "Последний рубеж",
	type = "intercept",
	map = "kirovskoe",

	briefing = {
		situation = "С севера идут 4 ударных самолёта противника под прикрытием пары истребителей. Цель — наш аэродром. До выхода на рубеж атаки около 6 минут.",
		time = "17:30",
		weather = "Ясно",
	},

	aircraft = {
		{ role = "f14a", crew = 2, loadout = "cap_phoenix" },
		{ role = "su34", crew = 2, loadout = "cap_r27" },
	},

	start = { anchor = "cap_station", airborne = true, alt = 4000, speed = 800 },

	waypoints = {
		{ id = "CAP", anchor = "cap_station", radius = 3000 },
	},

	units = {
		{ id = "bombers", kind = "aiflight", role = "su25sm3", count = 4, anchor = "north_edge", task = { attack = "airfield_main" }, team = "enemy", briefing = true, label = "Ударная группа" },
		{ id = "escort", kind = "aiflight", role = "f14a", count = 2, follow = "bombers", task = { escort = "bombers" }, team = "enemy", briefing = true, label = "Прикрытие" },
		{ id = "base", kind = "static", class = "skyops_airfield_core", anchor = "airfield_main" },
	},

	objectives = {
		{ id = "kill_bombers", type = "destroy", unit = "bombers", count = 4, text = "Сбить все ударные самолёты" },
		{ id = "protect_base", type = "protect", unit = "base", text = "Не допустить удара по аэродрому" },
		{ id = "kill_escort", type = "destroy", unit = "escort", count = 2, optional = true, text = "Доп.: сбить истребители прикрытия" },
	},

	fail = { crew_dead = true, protect_lost = true },

	score = { kill_bombers = 500, protect_base = 300, kill_escort = 300, per_kill = 25, grades = { S = 1100, A = 900, B = 700, C = 450 } },
})
