# LVS Tanks Kit

Всё полезное из проекта SkyOps (кооп на самолётах LVS от Ryuunosuke на карте
Кировское / InfMap), что пригодится для нового проекта про танки на LVS.
Снимок сделан 24.10.2026 из веток `claude/core-airdefense` и `claude/missions-ui`.

## Что внутри

| Папка | Что там |
|---|---|
| `skyops-source/` | Полный исходник SkyOps (ядро + задания + интерфейс), рабочая версия, которая стояла в `addons\skyops` |
| `skyops-source/docs/` | `addons.md` (классы и устройство аддонов Ryuunosuke), `missions.md`, `ui.md` |
| `notes/` | Формат заданий `MISSION_FORMAT.md` + 4 примера, заметки по проекту, скриншот брифинга |
| `logs/` | `compat_log.txt` (лог тестов LVS + SW Bombs на InfMap), точка аэродрома на Кировском |

## Что брать в танковый проект почти без изменений

- `lua/autorun/skyops_init.lua` — загрузчик: подхватывает все `sh_/sv_/cl_` файлы
  во всех подпапках, сначала `core/`. Переименовать `SkyOps` → своё имя.
- `lua/skyops/debug/sv_compat_test.lua` — стенд тестов: спавн ботов, слежение за
  переходами чанков InfMap, пуски и попадания ракет, лог в `data/.../compat_log.txt`.
  Для танков заменить роли самолётов на танки.
- `lua/skyops/debug/sv_dump.lua` — `skyops_dump_lua` копирует Lua чужого аддона из
  игры в `data/` (сам аддон SW Bombs весит ~900 МБ). Удобно читать код Ryuunosuke/SW Bombs.
- `core/sh_map.lua` — якоря карты и `GroundZ` (высота рельефа по сетке Кировского).
- `core/sv_radar.lua` — линия видимости по рельефу на большие расстояния (для ПТУР,
  прицелов, обнаружения), радиогоризонт.
- `core/sh_registry.lua`, `core/sh_loadouts.lua`, `core/sv_spawn.lua`, `core/sv_units.lua`,
  `core/sh_teams.lua` — реестр техники по ролям, подвески, спавн со стороной, учёт убийств.
- `core/sv_sam.lua` — пример «мозга» для наземной LVS-техники Ryuunosuke без игрока
  (Тор, Оса, Роланд — это `lvs_tank_wheeldrive`, то же семейство, что танки).
- `core/sv_realism.lua` — подъём лимита скорости физики и исправление скорости ракет SW Bombs.
- `mission/*` — движок заданий: цели reach/destroy/recon/land/protect/survive, цепочки
  `after`, брифинг, слоты экипажа, дебриф. Подходит и для танков.
- `ui/cl_base.lua` — общая база интерфейса (шрифты, цвета, масштаб `skyops_ui_scale`).
  `cl_briefing.lua`, `cl_debrief.lua`, `cl_threats.lua` (метки угроз на экране),
  `cl_weapon_info.lua` (описания вооружения) легко перевести на танки.
- Только для авиации, в танках не нужно: `sv_ai_flight`, `sv_arm`, `sv_rwr`, `cl_hud_pilot`,
  `cl_rwr`, `cl_wso`, `sh_airfield`.

## Главные находки (сэкономят дни)

### Аддоны Ryuunosuke на LVS
- Исходник LVS: github.com/SpaxscE/lvs_base. Танки и ЗРК Ryuunosuke сделаны на
  `lvs_tank_wheeldrive` / `lvs_base_wheeldrive_trailer`, самолёты на `lvs_base_fighterplane`.
- У всей техники Ryuunosuke `ENT.AITEAM = 2`, сторону надо выставлять при спавне.
- Оружие — не `lvs_missile`, а снаряды SW Bombs V3: ракеты `sw_base_rocket_v3`
  (цель в поле `.target`), снаряды `sw_base_shell_v3`, бомбы `sw_base_bomb_v3`,
  ловушки ищутся по классу (`sw_flr`, `sw_flare_v3`).
- Подвески: `ent:SetLoadout(n)` пересобирает оружие и **сбрасывает** настройки
  прицела (SeekerDist/Angle/LockTimer) на заводские → их надо переприменять таймером.
- Заводские дальности захвата крошечные (Су-34 20000 u ≈ 380 м): техника настроена
  под маленькие карты. На 1:1 карте дальности надо задавать самим.
- Стандартный ИИ LVS ищет цели в радиусе 60000 u и только впереди себя → для ботов
  нужен свой «мозг». Пусковая С-75 сама выключает LVS AI в `OnThink`.
- Радар ЗРК Ryuunosuke без игрока каждый тик сбрасывает `IsLocked`, а ракета без
  захвата теряет наведение → в `sv_sam.lua` переопределяются `SetIsLocked`/`SetClosestEnt`
  на экземпляре. Похожие ловушки стоит ждать в танках (прицел, стабилизатор).
- Клиентский радар СНР-75 каждый кадр перебирает `ents.GetAll()` — тормозит на больших картах.

### SW Bombs V3
- Баг скорости: лимит считается как `ConvertMetersToUnits(MaxVelocity^2)` (квадрат
  метров переводится один раз) → ракеты в разы медленнее. Исправление в `sv_realism.lua`:
  `MaxVelocityUnitsSquared = (MaxVelocity * M_TO_HU)^2`.
- Радиовзрыватель проверяет `FindInSphere(150 u)` раз в тик, быстрая ракета пролетает
  цель насквозь → свой предсказывающий взрыватель `sv_fuze.lua`.

### Source / InfMap / Кировское
- Source ограничивает скорость всех физобъектов 4000 u/s (~275 км/ч). Поднимать через
  `physenv.SetPerformanceSettings` после `InitPostEntity` (в `sv_realism.lua`).
- Масштаб Кировского — **40 юнитов на метр** (`KIR.S`), не 52,49. Чанк = 500 м.
- Высота земли: `KIR.MeshHeight(x, y)` (вне сетки возвращает `-inf`, проверять).
  Коллайдеры рельефа (`kir_collider`) подгружаются только рядом с движущимися объектами,
  поэтому трассировка вдали землю не видит.
- Рельеф InfMap — это сущности `infmap_*`, а не браши: `MASK_SOLID_BRUSHONLY` его не видит.
- Трассировки InfMap1 обрезаются стартовым чанком и упираются в границы карты через
  ~16000 u → дальнюю видимость считать по сетке высот (`sv_radar.lua`).
- NPC/NextBot на InfMap1 не поддерживаются → ботов делать на LVS AI / своих сущностях.
- Переходы чанков для LVS и SW Bombs проходят чисто (лог в `logs/`).
- Карта: Kirovskoe 3819959079, база InfMap 2905327911. InfMap2 (zff.dev/googer/infmap2) — преемник.

### Зависимости (Workshop)
LVS Framework 2912816023, LVS Planes Pack 2912826012, LVS Military Pack 3027255911,
LVS Tanks Pack 3047221988, SW Bombs V3 3127790930 (+ Russian 3127793643, USA/French content).
Технику Ryuunosuke не перезаливать, а ставить зависимостью и настраивать из своего кода
по имени класса.

## Ссылки
- План SkyOps: https://claude.ai/artifact/YPh7nS6b8BnWYKvfa1y7df
- Макеты брифинга/HUD: https://claude.ai/artifact/6V1QXTdYF8gdqCnTR9wV6M
  (стиль: фон #0d1114, янтарный #f2a93b, зелёный HUD #7dff9a, красный #ff6b5e,
  шрифты Rajdhani + JetBrains Mono)
