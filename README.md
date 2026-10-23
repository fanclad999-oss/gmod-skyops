# SkyOps

Аддон для Garry's Mod: кооперативные полёты вдвоём на реактивных самолётах LVS
(Ryuunosuke), задания на больших расстояниях, ПВО и вражеские боты на бесконечной
карте InfMap (Kirovskoe 1:1).

- `lua/autorun/skyops_init.lua`: загрузчик (файлы `sh_` / `sv_` / `cl_` во всех папках `lua/skyops/`)
- `lua/skyops/core/`: ядро (реестр самолётов и ПВО, спавн, юниты, якоря карты)
- `lua/skyops/mission/`, `ui/`, `missions/`, `maps/`: задания, брифинги и HUD
- `docs/addons.md`: классы и устройство сторонних аддонов

Установка для теста: скопировать папку репозитория в `garrysmod/addons/skyops`.
