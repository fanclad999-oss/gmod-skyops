-- Wind, server part: picks the bulletin wind and moves the real wind around it (see
-- sh_wind). A new wind comes with every mission start and with skyops_arty_wind random.
--
-- Convars:
--   skyops_arty_wind        1   0 = no wind at all
--   skyops_arty_wind_max    6   m/s, strongest random wind
--   skyops_arty_wind_gusts  1   how far the real wind strays from the bulletin (0 = exact)
-- Command (admin): skyops_arty_wind [random | off | <from mils> <m/s>]

local W = SkyOps.Arty.Wind

local cvWind = CreateConVar( "skyops_arty_wind", "1", FCVAR_ARCHIVE, "Wind for artillery shells (0 = none)", 0, 1 )
local cvMax = CreateConVar( "skyops_arty_wind_max", "6", FCVAR_ARCHIVE, "Strongest random wind, m/s", 0, 20 )
local cvGusts = CreateConVar( "skyops_arty_wind_gusts", "1", FCVAR_ARCHIVE, "How far the real wind strays from the meteo bulletin (0 = exactly the bulletin)", 0, 3 )

local SPEED_STRAY = 0.3 -- share of the speed
local DIR_STRAY = 200 -- mils
local DRIFT_RATE = 0.02 -- per second: how fast the real wind follows its next offset

local base = { dir = 0, speed = 0 }
local off = { speed = 0, dir = 0 } -- current offset of the real wind
local goal = { speed = 0, dir = 0, t = 0 } -- the offset it moves to

local function Publish()
	local on = cvWind:GetBool()
	local g = cvGusts:GetFloat()

	SetGlobal2Float( "SkyOpsArty_WindDir", base.dir )
	SetGlobal2Float( "SkyOpsArty_WindSpeed", on and base.speed or 0 )
	SetGlobal2Float( "SkyOpsArty_WindDirReal", ( base.dir + off.dir * g ) % 6000 )
	SetGlobal2Float( "SkyOpsArty_WindSpeedReal", on and math.max( base.speed * ( 1 + off.speed * g ), 0 ) or 0 )
end

-- sets the bulletin wind: from `dir` mils, `speed` m/s; the real wind starts equal to it
function W.Set( dir, speed )
	base.dir, base.speed = dir % 6000, math.max( speed, 0 )
	off.speed, off.dir = 0, 0
	goal.t = 0

	Publish()
	hook.Run( "SkyOps.Arty.WindChanged", base.dir, base.speed )
end

function W.Randomize()
	local max = cvMax:GetFloat()

	W.Set( math.random( 0, 59 ) * 100, math.Rand( math.min( 1, max ), max ) )
end

local function TellAll( msg )
	for _, ply in ipairs( player.GetAll() ) do ply:ChatPrint( "[Метео] " .. msg ) end
end

hook.Add( "SkyOps.Arty.MissionStart", "SkyOps.Arty.Wind", function()
	W.Randomize()

	if cvWind:GetBool() then TellAll( "Ветер " .. W.Format() ) end
end )

hook.Add( "InitPostEntity", "SkyOps.Arty.Wind", W.Randomize )

if base.speed == 0 then W.Randomize() end -- lua refresh / late load

local NextThink = 0

hook.Add( "Think", "SkyOps.Arty.Wind", function()
	local now = CurTime()

	if now < NextThink then return end

	local dt = 1

	NextThink = now + dt

	if now > goal.t then
		goal.speed = math.Rand( -SPEED_STRAY, SPEED_STRAY )
		goal.dir = math.Rand( -DIR_STRAY, DIR_STRAY )
		goal.t = now + math.Rand( 40, 120 )
	end

	local f = math.min( DRIFT_RATE * dt, 1 )

	off.speed = off.speed + ( goal.speed - off.speed ) * f
	off.dir = off.dir + ( goal.dir - off.dir ) * f

	Publish()
end )

concommand.Add( "skyops_arty_wind", function( ply, _, args )
	local function Say( msg )
		if IsValid( ply ) then ply:ChatPrint( "[Метео] " .. msg ) else print( "[Метео] " .. msg ) end
	end

	if args[ 1 ] and IsValid( ply ) and not ply:IsAdmin() then return Say( "Только для админа" ) end

	if args[ 1 ] == "random" then
		W.Randomize()
	elseif args[ 1 ] == "off" then
		W.Set( base.dir, 0 )
	elseif args[ 1 ] then
		local dir = tonumber( ( string.gsub( args[ 1 ], "-", "" ) ) )
		local speed = tonumber( args[ 2 ] or "" )

		if not dir or not speed then return Say( "skyops_arty_wind [random | off | <откуда, тысячные> <м/с>]" ) end

		W.Set( dir, speed )
	end

	local d, s = W.ActualDirSpeed()

	Say( "Бюллетень: " .. W.Format() .. "; сейчас на самом деле " .. W.Format( d, s ) )
end )
