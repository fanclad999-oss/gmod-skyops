-- Якоря карты Кировское (Хрестовка) 1:1 на InfMap1.
-- pos — локальная позиция внутри чанка, chunk — номер чанка InfMap (как в SkyOps.Map.Register ядра).
--
-- ВСЕ ПОЗИЦИИ НИЖЕ ПОКА ПРИМЕРНЫЕ (todo = true). Снять настоящие:
--   встать / зависнуть в нужной точке и ввести в консоли  skyops_anchor_here <имя>
--   команда напечатает готовую строку, её нужно вставить сюда вместо примерной.

SkyOps = SkyOps or {}
SkyOps.Maps = SkyOps.Maps or {}

SkyOps.Maps.kirovskoe = {
	match = "kirov",      -- подстрока имени карты (game.GetMap())
	north_yaw = 90,       -- yaw, который смотрит на север (в Source по умолчанию север = +Y)
	sea_level = 0,        -- мировой z уровня моря в юнитах, для барометрической высоты

	routes = {
		road_north = { "convoy_start", "road_mid", "road_ip", "airfield_main" },
	},
}

if not string.find( game.GetMap():lower(), "kirov", 1, true ) then return end

-- Чанк InfMap1 = 20000 юнитов (~508 м). Примерная раскладка: 1 км ≈ 2 чанка.
local function A( name, cx, cy, cz, yaw )
	SkyOps.Map.Register( name, {
		chunk = Vector( cx, cy, cz or 0 ),
		pos = Vector( 0, 0, 0 ),
		ang = Angle( 0, yaw or 0, 0 ),
		todo = true,
	} )
end

A( "airfield_main", 0, 0, 0, 90 )
A( "valley_south", 12, 16 )
A( "road_ip", 20, 32 )
A( "lake_west", -4, 48 )
A( "convoy_start", 32, 64 )
A( "road_mid", 28, 48 )
A( "hill_214", 44, 44 )
A( "forest_east", 24, 8 )
A( "bridge_khrest", 36, 24 )
A( "bridge_khrest_sam", 38, 26 )
A( "ridge_west", 16, 36 )
A( "cap_station", 8, 40, 8, 90 )   -- ~4 км высоты
A( "north_edge", 20, 120, 6, -90 ) -- ~3 км высоты
