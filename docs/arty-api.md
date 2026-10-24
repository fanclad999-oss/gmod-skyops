# Артиллерия: интерфейсы между частями

Модуль живёт в `lua/skyops/arty/`. Части и владельцы:

| Часть | Файлы |
|---|---|
| Баллистика и САУ | `arty/core/sh_grid.lua`, `arty/core/sh_firecomp.lua`, `arty/core/sv_ballistics.lua`, `arty/core/sv_spg.lua` |
| Дрон и лазер | `arty/drone/sh_drones.lua`, `arty/drone/sv_loiter.lua`, `arty/drone/sv_laser.lua`, `arty/drone/sv_guided.lua` |
| Интерфейс | `arty/ui/cl_*.lua` (все обращения к API собраны в `arty/ui/cl_api.lua`) |
| Разведка, план | `arty/debug/*`, этот файл |

Единицы: координаты сетки в метрах (X на восток, Y на север), углы в тысячных
(6000 на круг, 0 = север, по часовой). Мировые позиции везде "развёрнутые" позиции
InfMap, то есть то, что возвращает `GetPos()` (InfMap его подменяет).

## Сетка `SkyOps.Arty.Grid` (shared)

- `ToGrid( worldPos ) -> x_m, y_m`
- `FromGrid( x_m, y_m ) -> worldPos` (Z по рельефу)
- `Height( x_m, y_m ) -> h_m` высота рельефа (на Кировском по `KIR.MeshHeight`)
- `Format( x_m, y_m ) -> string` (квадрат + улитка и полные координаты)
- `SquareSize = 1000`
- `Bounds() -> minX, minY, maxX, maxY`

## Огневой компьютер `SkyOps.Arty.FireComp` (shared)

- `Solve{ gun = {x,y,h}, target = {x,y,h}, shell = "he"|"krasnopol", charge = id, high = bool, basedir = тыс. }`
  -> `{ ok, err, range, bearing, deflection, elevation, tof, apex }`
- `Charges( shell ) -> { {id, name, min, max}, ... }` (дальности в метрах)
- `GunLaying( spg ) -> deflection, elevation` текущие установки ствола
- Угломер: `deflection = (3000 + basedir - bearing) mod 6000`

## САУ `sw_2s35`

- NW2: `SkyOpsArty_Deployed` (bool), `SkyOpsArty_BaseDir` (тыс.)
- net клиент -> сервер `skyops_arty_auto { Entity spg, Vector target, String shell, UInt8 charge }`
  (режим авто: навести и выстрелить)
- net сервер -> клиент `skyops_arty_impact { Vector pos, String shell }`
- Режим: реплицируемый convar `skyops_arty_mode` = `hardcore` | `auto`

## Дрон `SkyOps.Arty.Drone`

- `GetControlled( ply ) -> ent`
- NW2 на дроне: `SkyOpsArty_Laser` (bool), `SkyOpsArty_Loiter` (bool),
  `SkyOpsArty_LoiterCenter` (Vector), `SkyOpsArty_LoiterRadius` (float, юниты)
- Точка камеры: стоковый `NWVector "TrackPos"` дронов Ryuunosuke (без захвата там 1)
- net клиент -> сервер `skyops_arty_drone { String cmd }`, cmd = `laser` | `loiter` | `send`
- net сервер -> клиент `skyops_arty_target { Vector pos, Float err_m, Entity drone }`

## Что известно об аддонах (этап 0, тест 24.10.2026 на gm_infmap_kirovskoe, 40 u/m)

Лог: `garrysmod\data\skyops\arty_probe.txt`, выгрузка Lua SW Bombs: `garrysmod\data\skyops\dump\`.

### 2S35 (`sw_2s35`, база `lvs_tank_wheeldrive`)

- Пушка создаёт `sw_bomb_fab100_v3` (база `sw_base_bomb_v3`, модель 88-мм снаряда) и задаёт
  физическую скорость 3500 u/s = **87 м/с** при 40 u/m, разброс ±2° по каждой оси. Сопротивления
  почти нет (в конце полёта те же 88–89 м/с). Тест: 34,6° -> 477 м за 6,6 с, 26,9° -> 399 м.
  Максимум таким снарядом около 770 м, а у настоящей 2А88 десятки км. Вывод: стоковый снаряд
  для навесной стрельбы не годится, полёт считаем сами (`sv_ballistics`), стоковый выстрел
  перехватываем.
- Ствол поднимается до 75° (`TurretPitchMin = -75`, поза `pitch`, башня поза `yaw`),
  `TurretAimRate = 20`, наводчик сидит в поде 2.
- DT `ShellType`: 0 = ОФС, 1 = «управляемый» (клавиша `CAR_SWAP_AMMO`, перезарядка как
  перегрев). Для типа 1 пушка ставит только `HaveGuidance = true` и `Agiility = 100`
  (опечатка, настоящее поле `Agility`). `GuidanceActive`, `LaserGuided`, `Launcher`, `target`
  не задаются, а наведение в `sw_base_bomb_v3` работает только при `GuidanceActive`. Итог:
  «Краснополь» в аддоне летит так же баллистически, как ОФС (в тесте ни одного доворота).
  Делаем свой.
- Как устроено лазерное наведение в `sw_base_bomb_v3` (может пригодиться): при
  `GuidanceActive` и `LaserGuided` бомба каждый тик делает трассировку из аттачмента
  `LaserCode` (по умолчанию `"view"`) сущности `self.Launcher` и рулит в точку попадания
  через `AddAngleVelocity`/`AddVelocity` с силой `Agility`, с подъёмом траектории
  `DiveHeight`. На InfMap длинная трассировка обрезается стартовым чанком, поэтому на
  десятках км это не сработает: ГСН пишем свою.
- На InfMap снаряд нормально перешёл из чанка 0 в чанк -1. `GetPos()` даёт развёрнутые
  координаты (размер чанка 20000 u = 500 м).

### Дроны

- `sw_zala`, `sw_orlan10`, `sw_pchela1t` (база `lvs_base_fighterplane`, `LVSUAV`,
  `CatapultLaunchable`) и `sw_ravenseye` (база `lvs_base_helicopter`, без катапульты).
- При спавне дрон создаёт пульт `sw_uav_control` (прицеп рядом с дроном). `Use` по пульту
  сажает игрока **в водительское кресло самого дрона** (`EnterVehicle(UAV:GetDriverSeat())`,
  игрок скрыт). То есть тело игрока летит вместе с дроном, и при выходе он окажется у дрона.
  Для одиночного режима (САУ <-> дрон) переключение и возврат к пульту делаем сами.
- Катапульта `sw_uav_catapult`: дрон приваривается при касании (`Mount`), `Dismount`
  включает двигатель и даёт 1500 u/s вперёд.
- Оружие дрона: `flir` (DT `FLIR`) и `track` (DT `Tracking`). Камера = кость 7, аттачмент
  `"view"`. При включении захвата трассировка из `view` на 999999 u: попал в сущность -> следит
  за ней (`TrackEnt`), иначе за точкой (`TrackPos`). Точка уходит в `NWVector "TrackPos"`
  (без захвата там 1). HUD показывает дистанцию (`* 0.024`, под масштаб 41,7 u/m) и сырые X/Y.
- Тест: Орлан-10 в чанке 1, 48 м/с, захват точки сработал, топливо 74% через пару минут.
- Ни у одного дрона нет лазера и автопилота, их делаем сами.
