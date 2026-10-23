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
		{ role = "f14a", crew = 2, loadout_text = { "AIM-54A × 4", "AIM-7F × 2", "AIM-9L × 2", "M61A1 · 675" } },
		{ role = "su34", crew = 2, loadout_text = { "Р-27Р × 2", "Р-73 × 2", "ГШ-301 · 150" } },
	},

	start = { anchor = "cap_station", airborne = true, alt = 4000, speed = 800 },

	waypoints = {
		{ id = "CAP", anchor = "cap_station", radius = 3000 },
	},

	units = {
		{ id = "bombers", kind = "aiflight", role = "su25sm3", count = 4, anchor = "north_edge", task = { attack = "airfield_main" }, team = "enemy", briefing = true, label = "Ударная группа" },
		{ id = "escort", kind = "aiflight", role = "f14a", count = 2, follow = "bombers", task = { escort = "bombers" }, team = "enemy", briefing = true, label = "Прикрытие" },
	},

	objectives = {
		{ id = "kill_bombers", type = "destroy", unit = "bombers", count = 4, text = "Сбить все ударные самолёты" },
		{ id = "protect_base", type = "defend", unit = "bombers", anchor = "airfield_main", radius = 8000, text = "Не подпустить ударную группу к аэродрому ближе 8 км" },
		{ id = "kill_escort", type = "destroy", unit = "escort", count = 2, optional = true, text = "Доп.: сбить истребители прикрытия" },
	},

	fail = { crew_dead = true },

	score = { kill_bombers = 500, protect_base = 300, kill_escort = 300, per_kill = 25, grades = { S = 1100, A = 900, B = 700, C = 450 } },
})
