# Артиллерия: дрон-корректировщик (`lua/skyops/arty/drone/`)

Дополнение к `docs/arty-api.md`, раздел «Дрон». Всё поверх стоковых дронов Ryuunosuke,
их файлы не меняются. Все числа игровые, подобраны под удобство игры.

| Файл | Что делает |
|---|---|
| `sh_drones.lua` | настройки дронов `SkyOps.Arty.Drone.Types`, общие функции, приём команд |
| `sv_loiter.lua` | барражирование по кругу |
| `sv_laser.lua` | подсветка точки и передача координат |
| `sv_guided.lua` | упрощённый «магнит» для управляемого снаряда |
| `sv_switch.lua` | переключение САУ <-> дрон, выход из дрона к пульту |

## Как играть одному

1. Запустить дрон, сесть в него через пульт.
2. Навести камеру на цель, включить захват (стоковое оружие `track`).
3. `laser` — подсветка, `loiter` — дрон кружит над точкой, `send` — координаты на планшет.
4. `switch` — пересесть в 2С35 (в то же кресло, где сидел). Дрон продолжает кружить и светить.
5. Выстрелить Краснополем. На нисходящей ветке снаряд доворачивает к пятну подсветки.
6. `switch` ещё раз — обратно в дрон.

Обычный выход из дрона (E) ставит игрока у пульта, а не в воздух рядом с дроном.

## API `SkyOps.Arty.Drone` (shared, кроме помеченных)

- `Types[ class ]` — `{ name, loiter, radius (м), throttle, lead, laserRange (м), errBase, errPerKm }`
- `IsDrone( ent )`, `Config( ent )`, `All()`
- `GetControlled( ply )` — дрон, в кресле которого игрок сидит сейчас
- `GetLinked( ply )` — последний дрон игрока (NW2 `SkyOpsArty_Drone` на игроке), в т. ч. когда он в САУ
- `Station( drone )` — пульт `sw_uav_control`
- `TrackPos( drone )` — точка стокового захвата или nil
- `LaserPos( drone )` -> `pos, blocked` или nil
- сервер: `SetLaser( drone, on )`, `LaserSpots()`, `SendTarget( drone, ply )`,
  `StartLoiter( drone, center? )`, `StopLoiter( drone )`, `IsLoitering( drone )`, `Switch( ply )`

## NW2 на дроне

- `SkyOpsArty_Laser` (bool), **новые:** `SkyOpsArty_LaserPos` (Vector, мировая),
  `SkyOpsArty_LaserBlocked` (bool: точка вне дальности или за препятствием)
- `SkyOpsArty_Loiter` (bool), `SkyOpsArty_LoiterCenter` (Vector), `SkyOpsArty_LoiterRadius` (юниты)

## Сеть и консоль

- клиент -> сервер `skyops_arty_drone { String cmd }`: `laser` | `loiter` | `send` | **`switch`**
  (`switch` работает и из САУ, остальные только из кресла дрона)
- то же из консоли: `skyops_arty_drone_cmd <cmd>`, плюс `skyops_arty_switch`
- сервер -> все `skyops_arty_target { Vector pos, Float err_m, Entity drone }`
- хуки сервера: `SkyOpsArty.TargetSent( drone, pos, err, ply )`, `SkyOpsArty.GuidedLocked( s, drone )`

## Управляемый снаряд `SkyOps.Arty.Guided` (сервер)

`Guided.Steer( s, dt )` зовёт `sv_ballistics` на каждом шаге полёта снаряда с `def.guided`.
Игровое правило: на нисходящей ветке снаряд берёт ближайшее пятно подсветки в радиусе
захвата и поворачивает вектор скорости к нему не быстрее `skyops_arty_guided_turn` градусов
в секунду, модуль скорости не меняет. Пропала подсветка — летит дальше как есть.

## Барраж

Круг против часовой на высоте включения, центр — подсветка, захват камеры или точка
слева от дрона. Пока барраж включён, мышь крутит только камеру. Любая клавиша
тангажа, рыскания или крена возвращает ручное управление. Raven's Eye (вертолёт) не барражирует.

## Convar

| Имя | По умолчанию | Смысл |
|---|---|---|
| `skyops_arty_laser_los` | 1 | подсветка срывается за препятствием |
| `skyops_arty_send_error` | 1 | в hardcore координаты передаются с ошибкой |
| `skyops_arty_guided_turn` | 8 | доворот снаряда, град/с |
| `skyops_arty_guided_capture` | 1500 | радиус захвата подсветки, м |

Проверено вне игры (заглушки Lua): снаряд, падающий на 300 м/с с промахом наведения до
600 м, приходит в 1–8 м от пятна; барраж поворачивает против часовой.
