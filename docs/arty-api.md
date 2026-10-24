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

## Правила для позиций в сети (InfMap)

- `net.WriteVector` сжимает координаты в диапазон ±16384 u (~410 м при 40 u/m), дальше
  приходит мусор. Мировые позиции в net передаём тремя `net.WriteFloat` (x, y, z) или
  координатами сетки в метрах. Касается `skyops_arty_auto` (target), `skyops_arty_impact`,
  `skyops_arty_target` и любых новых сообщений.
- NW/NW2 Vector, скорее всего, сжимаются так же (стоковый `TrackPos` дронов тоже). Позиции
  дальше 400 м от нуля карты в `SetNW2Vector` не кладём: три `NW2Float` или координаты сетки.
  Касается `SkyOpsArty_LoiterCenter` и `SkyOpsArty_LaserPos`. Проверить в игре.
- На клиенте InfMap `Entity:GetPos()` отдаёт позицию относительно чанка `LocalPlayer`.
  Абсолютная = `pos + InfMap.unlocalize_vector( Vector(), LocalPlayer().CHUNK_OFFSET )`,
  обратно (серверная позиция -> где рисовать) вычитаем. Готовая функция: `FX.ToRender`
  в `arty/fx/sh_fx.lua`. `Grid.ToGrid` на клиенте ждёт абсолютную позицию.

## Сетка `SkyOps.Arty.Grid` (shared)

- `ToGrid( worldPos ) -> x_m, y_m`
- `FromGrid( x_m, y_m, h_m? ) -> worldPos` (без `h` Z по рельефу)
- `ToGrid3( worldPos ) -> x_m, y_m, h_m`
- `YawToMils( yaw ) -> mils`, `MilsToYaw( mils ) -> yaw`
- `Bearing( fromPos, toPos ) -> mils` дирекционный угол, `Direction( mils ) -> Vector`
- `Height( x_m, y_m ) -> h_m` высота рельефа (на Кировском по `KIR.MeshHeight`)
- `Format( x_m, y_m ) -> string` (квадрат + улитка и полные координаты)
- `SquareSize = 1000`
- `Bounds() -> minX, minY, maxX, maxY`

## Огневой компьютер `SkyOps.Arty.FireComp` (shared)

- `Solve{ gun = {x,y,h}, target = {x,y,h}, shell = "he"|"krasnopol", charge = id, high = bool, basedir = тыс. }`
  -> `{ ok, err, range, bearing, deflection, elevation, tof, apex, charge, high }`
- `Charges( shell ) -> { {id, name, min, max, minHigh, v0}, ... }` (дальности в метрах, `minHigh` для навесной, `v0` м/с)
- `GunLaying( spg ) -> deflection, elevation, bearing` текущие установки и дирекционный ствола
- Угломер: `deflection = (3000 + basedir - bearing) mod 6000`

## САУ `sw_2s35` (`arty/core/sh_spg.lua`, `SkyOps.Arty.SPG`)

- На время развёртывания стоковый `AimTurret` заменяется нашей наводкой.
- NW2: `SkyOpsArty_Deployed` (bool), `SkyOpsArty_BaseDir` (тыс.),
  `SkyOpsArty_State` (0 марш, 1 развёртывание, 2 развёрнута, 3 свёртывание), `SkyOpsArty_StateEnd` (время),
  `SkyOpsArty_Lay`, `SkyOpsArty_LayP` / `SkyOpsArty_LayY` (установки наводки), `SkyOpsArty_Charge`, `SkyOpsArty_Auto`
- net клиент -> сервер `skyops_arty_auto { Entity spg, Float x, Float y, Float z, String shell, UInt8 charge }`
  (режим авто: навести и выстрелить; `charge = 0` выбрать заряд сам)
- Команды: `skyops_arty_deploy`, `skyops_arty_charge`, `skyops_arty_basedir`
- Convar'ы: `skyops_arty_timescale`, `skyops_arty_dispersion`, `skyops_arty_deploy_time`, `skyops_arty_stow_time`
- Клавиши: H развернуть/свернуть, K заряд, стрелки наводка, Shift x10.
  Клавиши интерфейса: N, T, G, J, B (не пересекаются).
- net сервер -> клиент `skyops_arty_impact { Float x, Float y, Float z, String shell }`
- Режим: реплицируемый convar `skyops_arty_mode` = `hardcore` | `auto`

## Баллистика `SkyOps.Arty.Ballistics` (server)

- `Fire{ ... }` запускает расчётный снаряд, `Active` таблица летящих снарядов,
  `WorldPos( s )` / `WorldVel( s )`
- Хуки: `SkyOps.Arty.SPGFired`, `SkyOps.Arty.ShellFired`, `SkyOps.Arty.ShellThink`,
  `SkyOps.Arty.ShellImpact`, `SkyOps.Arty.ShellRemoved`
- Для Краснополя баллистика каждый шаг вызывает `SkyOps.Arty.Guided.Steer( s, dt )`
  (реализует тред дрона в `arty/drone/sv_guided.lua`)

## Дрон `SkyOps.Arty.Drone`

- `GetControlled( ply ) -> ent`
- NW2 на дроне: `SkyOpsArty_Laser` (bool), `SkyOpsArty_Loiter` (bool),
  `SkyOpsArty_LoiterCenter_X/_Y/_Z` (Float), `SkyOpsArty_LoiterRadius` (float, юниты)
- Shared: `Drone.LaserPos( drone )`, `Drone.LoiterCenter( drone )` собирают Vector из NW2Float
- Точка камеры: стоковый `NWVector "TrackPos"` дронов Ryuunosuke (без захвата там 1)
- net клиент -> сервер `skyops_arty_drone { String cmd }`, cmd = `laser` | `loiter` | `send` | `switch`
  (`switch` в одиночке переключает игрока между САУ и дроном, `arty/drone/sv_switch.lua`)
- Консоль: `skyops_arty_switch`, `skyops_arty_drone_cmd <cmd>`
- NW2 на дроне: `SkyOpsArty_LaserPos_X/_Y/_Z` (Float, точка подсветки), `SkyOpsArty_LaserBlocked` (bool, луч закрыт)
- NW2Entity на игроке: `SkyOpsArty_Drone` (его дрон)
- Сервер: `SkyOps.Arty.Guided.Steer( s, dt )` (`arty/drone/sv_guided.lua`), его вызывает `sv_ballistics`
- Хуки: `SkyOpsArty.TargetSent`, `SkyOpsArty.GuidedLocked`
- Подробности: `docs/arty-drone.md`
- net сервер -> клиент `skyops_arty_target { Float x, Float y, Float z, Float err_m, Entity drone }`

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
