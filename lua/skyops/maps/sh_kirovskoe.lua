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

-- Примерная раскладка: смещения от аэродрома в км (на восток, на север) и высота над
-- рельефом в м. Север = +Y, восток = +X. Пока ядро не построило аэродром
-- (skyops_airfield_here), точкой отсчёта служит центр карты, а airfield_main лежит там же.
local LAYOUT = {
	valley_south = { 6, 8 },
	road_ip = { 10, 16 },
	lake_west = { -2, 24 },
	convoy_start = { 16, 32 },
	road_mid = { 14, 24 },
	hill_214 = { 22, 22 },
	forest_east = { 12, 4 },
	bridge_khrest = { 18, 12 },
	bridge_khrest_sam = { 19, 13 },
	ridge_west = { 8, 18 },
	cap_station = { 4, 20, 4000, 90 },
	north_edge = { 10, 60, 3000, -90 },
}

local function Layout( base, baseZ, useGround )
	local K = (SkyOps.M_TO_HU or 40) * 1000

	for name, l in pairs( LAYOUT ) do
		local pos = base + Vector( l[1] * K, l[2] * K, 0 )
		local ground = useGround and SkyOps.Map.GroundZ and SkyOps.Map.GroundZ( pos.x, pos.y, baseZ )

		pos.z = (ground or baseZ) + (l[3] or 0) * (SkyOps.M_TO_HU or 40)

		SkyOps.Map.Register( name, { pos = pos, ang = Angle( 0, l[4] or 0, 0 ), todo = true } )
	end
end

-- Без аэродрома: всё от центра карты
SkyOps.Map.Register( "airfield_main", { chunk = Vector( 0, 0, 0 ), pos = Vector( 0, 0, 0 ), ang = Angle( 0, 90, 0 ), todo = true } )
Layout( SkyOps.Map.Anchor( "airfield_main" ), 0 )

-- Ядро регистрирует airfield_main после загрузки карты (и при перестройке аэродрома):
-- как только он настоящий, раскладываем остальные якоря вокруг него
local laidAt

timer.Create( "SkyOps.Kirovskoe.Layout", 2, 0, function()
	local a = SkyOps.Map.Anchors[ "airfield_main" ]

	if not a or a.todo then return end

	local pos = SkyOps.Map.Anchor( "airfield_main" )

	if not pos or laidAt == pos then return end

	laidAt = pos
	Layout( Vector( pos.x, pos.y, 0 ), pos.z, true )
end )
