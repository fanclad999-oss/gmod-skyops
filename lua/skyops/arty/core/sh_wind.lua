-- Wind for the artillery. Each mission (and each server start) gets a random wind, which
-- the crew reads on the tablet as a meteo bulletin: where it blows from (mils, like a
-- bearing) and how strong. The fire computer allows for the bulletin wind (FC.Solve).
-- The real wind that shells fly through wanders around the bulletin (sv_wind): speed
-- +-30 %, direction +-2-00, changing over a minute or two, so the allowance is close but
-- not exact and long shots need a correction from the drone.
--
-- Global2 vars (set by sv_wind):
--   SkyOpsArty_WindDir, SkyOpsArty_WindSpeed          bulletin: from (mils), m/s
--   SkyOpsArty_WindDirReal, SkyOpsArty_WindSpeedReal  real wind right now

SkyOps.Arty = SkyOps.Arty or {}
SkyOps.Arty.Wind = SkyOps.Arty.Wind or {}

local W = SkyOps.Arty.Wind

local MILS = 6000

-- wind from `dir` (mils) at `speed` (m/s) -> { x, y }: where the air moves, grid axes
-- (x east, y north), m/s
function W.Vector( dir, speed )
	local b = dir / MILS * 2 * math.pi

	return { x = -speed * math.sin( b ), y = -speed * math.cos( b ) }
end

function W.BulletinDirSpeed()
	return GetGlobal2Float( "SkyOpsArty_WindDir", 0 ), GetGlobal2Float( "SkyOpsArty_WindSpeed", 0 )
end

function W.ActualDirSpeed()
	local d, s = W.BulletinDirSpeed()

	return GetGlobal2Float( "SkyOpsArty_WindDirReal", d ), GetGlobal2Float( "SkyOpsArty_WindSpeedReal", s )
end

-- bulletin wind as a vector, nil when calm
function W.Bulletin()
	local d, s = W.BulletinDirSpeed()

	if s <= 0 then return nil end

	return W.Vector( d, s )
end

-- real wind as a vector, nil when calm
function W.Actual()
	local d, s = W.ActualDirSpeed()

	if s <= 0 then return nil end

	return W.Vector( d, s )
end

local COMPASS = { "С", "СВ", "В", "ЮВ", "Ю", "ЮЗ", "З", "СЗ" }

-- "4 м/с, с 45-00 (ЮЗ)" or "штиль"
function W.Format( dir, speed )
	if not dir then dir, speed = W.BulletinDirSpeed() end

	if speed < 0.5 then return "штиль" end

	local m = math.Round( dir ) % MILS
	local sector = COMPASS[ math.floor( ( m + MILS / 16 ) / ( MILS / 8 ) ) % 8 + 1 ]

	return string.format( "%.0f м/с, с %d-%02d (%s)", speed, math.floor( m / 100 ), m % 100, sector )
end
