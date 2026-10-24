-- Артиллерия, дрон: упрощённый игровой «магнит» для управляемого снаряда.
-- Это геймплейная механика, а не модель настоящей головки самонаведения: снаряд
-- с флагом управляемого на нисходящей ветке поворачивает вектор скорости к
-- подсвеченной дроном точке, не быстрее заданного числа градусов в секунду.
-- Модуль скорости не меняется (сопротивление считает sv_ballistics).
--
-- Стык с баллистикой (arty/core/sv_ballistics.lua): на каждом шаге полёта снаряда с
-- def.guided вызывается Guided.Steer( s, dt ), где s.pos и s.vel — мировые позиция и
-- скорость (юниты/с), s.shell — тип снаряда. Steer меняет только s.vel и поля guided_*.

SkyOps.Arty = SkyOps.Arty or {}
SkyOps.Arty.Guided = SkyOps.Arty.Guided or {}

local G = SkyOps.Arty.Guided
local D = SkyOps.Arty.Drone

G.SHELLS = { krasnopol = true }

local cvTurn = CreateConVar( "skyops_arty_guided_turn", "8", FCVAR_ARCHIVE, "Управляемый снаряд: скорость доворота к подсветке, градусов в секунду" )
local cvCapture = CreateConVar( "skyops_arty_guided_capture", "1500", FCVAR_ARCHIVE, "Управляемый снаряд: на каком удалении (м, по горизонтали) снаряд «замечает» подсветку" )

-- ближайшее к снаряду пятно подсветки в пределах захвата
local function FindSpot( s, upm )
	local best, bestD = nil, ( cvCapture:GetFloat() * upm ) ^ 2

	for _, spot in ipairs( D.LaserSpots() ) do
		local dx, dy = spot.pos.x - s.pos.x, spot.pos.y - s.pos.y
		local d = dx * dx + dy * dy

		if d < bestD then best, bestD = spot, d end
	end

	return best
end

local function SpotOf( drone )
	local pos, blocked = D.LaserPos( drone )

	if pos and not blocked then return pos end
end

-- поворот единичного вектора a к b не больше чем на maxRad радиан
local function TurnToward( a, b, maxRad )
	local cosA = math.Clamp( a:Dot( b ), -1, 1 )
	local angle = math.acos( cosA )

	if angle <= maxRad then return b end

	-- раскладываем b на компоненту вдоль a и перпендикуляр к a
	local perp = b - a * cosA

	if perp:LengthSqr() < 1e-12 then return a end

	perp:Normalize()

	return a * math.cos( maxRad ) + perp * math.sin( maxRad )
end

function G.Steer( s, dt )
	if not G.SHELLS[ s.shell ] or not D then return end

	-- только нисходящая ветка
	if s.vel.z >= 0 then return end

	local upm = D.UPM()
	local target

	if IsValid( s.guided_drone ) then
		target = SpotOf( s.guided_drone )
	elseif not s.guided_drone then
		local spot = FindSpot( s, upm )

		if spot then
			s.guided_drone = spot.drone
			target = spot.pos

			hook.Run( "SkyOpsArty.GuidedLocked", s, spot.drone )
		end
	end

	-- подсветка пропала (выключили, сорвалась, дрон сбит): летим дальше как есть
	if not target then return end

	local speed = s.vel:Length()

	if speed < 1 then return end

	local dir = s.vel / speed
	local want = target - s.pos

	if want:LengthSqr() < 1 then return end

	want:Normalize()

	s.vel = TurnToward( dir, want, math.rad( cvTurn:GetFloat() ) * dt ) * speed
end
