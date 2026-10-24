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

## Что известно об аддонах (этап 0)

- `sw_2s35` стреляет `sw_bomb_fab100_v3` физикой, 3500 u/s, разброс ±2°, ствол до 75°.
  DT `ShellType`: 0 = ОФС, 1 = управляемый (`HaveGuidance = true`, `Agiility = 100`,
  `NWEntity "Missile"`), переключение клавишей `CAR_SWAP_AMMO`.
- Дроны `sw_zala`, `sw_orlan10`, `sw_pchela1t` (самолёты, катапульта) и `sw_ravenseye`
  (вертолёт) управляются через `sw_uav_control`. Оружие: FLIR и `track`
  (DT `Tracking`, `TrackPos`, `TrackEnt`).
- Как наводится управляемый снаряд SW Bombs, станет ясно после `skyops_arty_dump`.
