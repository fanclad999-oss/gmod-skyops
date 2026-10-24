-- Counter-battery fire, shared part: settings, net names and how the "exposure" of a
-- firing position is shown.
--
-- The enemy has a counter-battery radar. Every shot of a 2S35 from one spot is a chance
-- for it to track the shell back to the gun; after a few shots (skyops_arty_counter_shots)
-- the position is located, and after a reaction time (skyops_arty_counter_delay) an
-- enemy battery fires a salvo at it. Moving the gun more than MOVE_RADIUS away starts a
-- new, clean position: the salvo lands on the old one. Each next salvo at a position the
-- crew keeps firing from is more accurate. The friendly radar sees where the enemy salvo
-- came from and reports the enemy battery; silencing it stops the fire.
--
-- Server: sv_counter. Client: cl_counter (HUD, incoming warning, map marks).
--
-- NW2 on the 2S35 (server -> client):
--   SkyOpsCB_Heat    Float  0..1, how close the enemy is to locating the current spot
--   SkyOpsCB_Locked  Bool   the current spot is located
--   SkyOpsCB_X/Y     Float  grid of the current spot (where the shots were counted)
-- net server -> client:
--   skyops_arty_cb_incoming { Float x, Float y (grid m, aim point), Float tof (s, real time),
--                             UInt8 shells }
--   skyops_arty_cb_battery  { Bool known, Float x, Float y, Float err (m), Bool alive }

SkyOps = SkyOps or {}
SkyOps.Arty = SkyOps.Arty or {}
SkyOps.Arty.Counter = SkyOps.Arty.Counter or {}

local CB = SkyOps.Arty.Counter

CB.NET_INCOMING = "skyops_arty_cb_incoming"
CB.NET_BATTERY = "skyops_arty_cb_battery"

CB.MOVE_RADIUS = 250 -- m the gun has to move to leave a located position
CB.DANGER_RADIUS = 200 -- m from the aim point where the crew gets the incoming warning

local FLAGS = bit.bor( FCVAR_ARCHIVE, FCVAR_REPLICATED )

CB.cvMode = CreateConVar( "skyops_arty_counter", "1", FLAGS, "Контрбатарейная борьба: 0 выкл, 1 только в заданиях, 2 всегда", 0, 2 )
CB.cvShots = CreateConVar( "skyops_arty_counter_shots", "4", FLAGS, "Сколько выстрелов с одной позиции нужно радару противника, чтобы засечь САУ", 1, 50 )
CB.cvDelay = CreateConVar( "skyops_arty_counter_delay", "45", FLAGS, "Секунд от засечки до залпа противника", 0, 600 )
CB.cvSalvo = CreateConVar( "skyops_arty_counter_salvo", "4", FLAGS, "Снарядов в залпе противника", 1, 12 )
CB.cvDamage = CreateConVar( "skyops_arty_counter_damage", "1", FLAGS, "Множитель урона САУ от ответного огня (0 = без урона)", 0, 5 )

function CB.Mode()
	return CB.cvMode:GetInt()
end

-- exposure level -> text and colour key for the HUD
function CB.HeatText( heat, locked )
	if locked then return "ОП РАСКРЫТА", "threat" end
	if heat <= 0 then return "не засечена", "ok" end
	if heat < 0.5 then return "низкая", "ok" end
	if heat < 0.8 then return "средняя", "accent" end

	return "высокая", "threat"
end
