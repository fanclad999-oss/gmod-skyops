-- Артиллерия, интерфейс: HUD оператора дрона (ZALA, Орлан-10, Пчела-1Т, Raven's Eye).
-- Поверх стокового FLIR: координаты точки камеры в сетке, квадрат и улитка, дальность,
-- состояние лазера и барражирования, разрывы и их отклонение от цели.
-- Клавиши (меняются convar-ами): передать координаты, лазер, барражирование,
-- в режиме «авто» ещё огонь САУ по точке камеры.

local UI = SkyOps.Arty.UI
local A = UI.API
local C = UI.C

local cvShow = CreateClientConVar( "skyops_arty_ui_drone", "1", true, false, "HUD оператора дрона" )

local LaserSince
local Flash -- { text, col, time }

local function Say( text, col )
	Flash = { text = text, col = col or C.ok, time = CurTime() }
end

local function InDrone() return IsValid( A.MyDrone() ) end

-- Точка мира -> экран. Направление не зависит от того, в каком чанке InfMap рисуется
-- мир, поэтому проецируем направление от дрона, а не саму позицию.
local function Project( drone, pos )
	local dir = ( pos - drone:GetPos() ):GetNormalized()
	local s = ( EyePos() + dir * 100 ):ToScreen()

	if not s.visible or EyeVector():Dot( dir ) <= 0 then return nil end

	return s.x, s.y
end

-- Команды -------------------------------------------------------------------

local function SendTarget()
	local drone = A.MyDrone()
	local track = A.DroneTrack( drone )

	if not track then
		Say( "НЕТ ЗАХВАТА ТОЧКИ", C.threat )

		return
	end

	if A.DroneCmd( "send" ) then
		Say( "КООРДИНАТЫ ПЕРЕДАНЫ" )

		return
	end

	-- модуля дрона ещё нет: кладём цель в свой вычислитель
	A.SetTarget( track, A.UAV[ drone:GetClass() ] or "дрон", 0 )
	surface.PlaySound( "buttons/blip1.wav" )
	Say( "ЦЕЛЬ В ПЛАНШЕТЕ" )
end

local function ToggleLaser()
	local drone = A.MyDrone()

	if not A.DroneCmd( "laser" ) then
		Say( "ЛАЗЕР НЕДОСТУПЕН: нет модуля дрона", C.threat )

		return
	end

	if not A.DroneLaser( drone ) and not A.DroneTrack( drone ) then Say( "СНАЧАЛА ЗАХВАТ ТОЧКИ", C.accent ) end
end

local function ToggleLoiter()
	if not A.DroneCmd( "loiter" ) then Say( "БАРРАЖ НЕДОСТУПЕН: нет модуля дрона", C.threat ) end
end

local function FireAtTrack()
	if not A.IsAuto() then
		Say( "ОГОНЬ С ДРОНА ТОЛЬКО В РЕЖИМЕ АВТО", C.accent )

		return
	end

	local drone = A.MyDrone()
	local track = A.DroneTrack( drone )
	local spg = A.MySPG()

	if not track then Say( "НЕТ ЗАХВАТА ТОЧКИ", C.threat ) return end
	if not IsValid( spg ) then Say( "НЕТ САУ: сначала посиди в ней", C.threat ) return end

	A.SetTarget( track, A.UAV[ drone:GetClass() ] or "дрон", 0 )

	if A.AutoFire( spg, track, UI.State.shell, UI.State.charge ) then
		Say( "САУ: ОГОНЬ" )
	else
		Say( "АВТОНАВЕДЕНИЕ НЕДОСТУПНО: нет модуля баллистики", C.threat )
	end
end

local keySend = A.Bind( "skyops_arty_key_send", KEY_T, "Дрон: передать координаты точки камеры", SendTarget, InDrone )
local keyLaser = A.Bind( "skyops_arty_key_laser", KEY_G, "Дрон: лазер вкл/выкл", ToggleLaser, InDrone )
local keyLoiter = A.Bind( "skyops_arty_key_loiter", KEY_J, "Дрон: барражирование вкл/выкл", ToggleLoiter, InDrone )
local keyFire = A.Bind( "skyops_arty_key_fire", KEY_B, "Дрон, режим авто: огонь САУ по точке камеры", FireAtTrack, InDrone )

concommand.Add( "skyops_arty_send", function() if InDrone() then SendTarget() end end )
concommand.Add( "skyops_arty_laser", function() if InDrone() then ToggleLaser() end end )
concommand.Add( "skyops_arty_loiter", function() if InDrone() then ToggleLoiter() end end )
concommand.Add( "skyops_arty_firecam", function() if InDrone() then FireAtTrack() end end )

-- Рисование -----------------------------------------------------------------

local function PaintTelemetry( drone )
	local upm = A.UPM()
	local pos = drone:GetPos()
	local e, n, h = A.ToGrid( pos )
	local gh = A.GroundH( e, n )
	local speed = drone:GetVelocity():Length() / upm * 3.6
	local course = A.YawToBearing( drone:GetAngles().y )
	local center, radius = A.DroneLoiter( drone )
	local x, y = UI.S( 30 ), ScrH() / 2 - UI.S( 120 )
	local lines = {
		{ A.UAV[ drone:GetClass() ] or "БПЛА", C.text },
		{ string.format( "ВЫС %4.0f м", gh and ( h - gh ) or h ), C.hud },
		{ string.format( "СКОР %3.0f км/ч", speed ), C.hud },
		{ string.format( "КУРС %03.0f°", course ), C.hud },
		{ center and string.format( "БАРРАЖ R %.0f м", radius / upm ) or "РУЧНОЙ ПОЛЁТ", center and C.ok or C.muted },
	}

	for i, l in ipairs( lines ) do
		UI.HText( l[ 1 ], "SkyOpsArty_HUD", x, y + ( i - 1 ) * UI.S( 26 ), l[ 2 ] )
	end
end

local function PaintTrack( drone )
	local track = A.DroneTrack( drone )
	local laser = A.DroneLaser( drone )

	if laser and not LaserSince then LaserSince = CurTime() end
	if not laser then LaserSince = nil end

	local sw = ScrW()
	local bx, by = sw / 2, UI.S( 40 )

	if laser then
		local blink = math.floor( CurTime() * 3 ) % 2 == 0

		UI.HText( string.format( "ЛАЗЕР  %.0f с", CurTime() - LaserSince ), "SkyOpsArty_HUDLarge", bx, by, blink and C.laser or Color( C.laser.r, C.laser.g, C.laser.b, 120 ), TEXT_ALIGN_CENTER )
	end

	if not track then
		UI.HText( "нет захвата: наведи камеру и включи сопровождение", "SkyOpsArty_HUDSmall", bx, by + UI.S( 36 ), C.muted, TEXT_ALIGN_CENTER )

		return
	end

	local e, n, h = A.ToGrid( track )
	local sq, snail = A.Square( e, n )
	local dist = track:Distance( drone:GetPos() ) / A.UPM()
	local px, py = Project( drone, track )
	local col = laser and C.laser or C.hud

	if px then
		local s = UI.S( 14 )

		UI.Outline( px - s, py - s, s * 2, s * 2, col, 2 )
		UI.Line( px - s * 2, py, px - s, py, 2, col )
		UI.Line( px + s, py, px + s * 2, py, 2, col )
	end

	-- блок координат справа сверху
	local rx, ry = sw - UI.S( 30 ), UI.S( 120 )
	local lines = {
		{ A.FormatGrid( e, n ), C.hud, "SkyOpsArty_HUD" },
		{ string.format( "кв. %s ул. %d   H %.0f м", sq, snail, h ), C.hud, "SkyOpsArty_HUDSmall" },
		{ string.format( "Д %.0f м", dist ), C.hud, "SkyOpsArty_HUDSmall" },
	}

	local spg = A.MySPG()

	if IsValid( spg ) then
		local ge, gn = A.ToGrid( spg:GetPos() )

		lines[ #lines + 1 ] = { string.format( "от САУ %.2f км  %s", math.sqrt( ( e - ge ) ^ 2 + ( n - gn ) ^ 2 ) / 1000, A.FmtMils( A.Bearing( ge, gn, e, n ) ) ), C.muted, "SkyOpsArty_HUDSmall" }
	end

	for i, l in ipairs( lines ) do
		UI.HText( l[ 1 ], l[ 3 ], rx, ry + ( i - 1 ) * UI.S( 26 ), l[ 2 ], TEXT_ALIGN_RIGHT )
	end
end

local function PaintImpacts( drone )
	local now = CurTime()
	local spg = A.MySPG()
	local t = A.Target
	local track = A.DroneTrack( drone )

	for i, imp in ipairs( A.Impacts ) do
		local age = now - imp.time

		if age > 90 then break end

		local px, py = Project( drone, imp.pos )

		if px then
			local s = i == 1 and UI.S( 12 ) or UI.S( 7 )
			local col = Color( C.accent.r, C.accent.g, C.accent.b, math.Clamp( 255 - age * 3, 60, 255 ) )

			UI.Line( px - s, py - s, px + s, py + s, 2, col )
			UI.Line( px - s, py + s, px + s, py - s, 2, col )
		end
	end

	-- доклад о последнем разрыве: в хардкоре только если он в поле камеры (рядом с точкой захвата)
	local last = A.Impacts[ 1 ]

	if not last or now - last.time > 20 or not t or not IsValid( spg ) then return end

	local seen = A.IsAuto() or ( track and track:Distance( last.pos ) / A.UPM() < 1000 )

	if not seen then return end

	local ge, gn = A.ToGrid( spg:GetPos() )
	local ie, inn = A.ToGrid( last.pos )
	local lat, rng = A.Deviation( ge, gn, t.e, t.n, ie, inn )
	local text

	if A.IsAuto() then
		text = "РАЗРЫВ: " .. A.FmtDeviation( lat, rng )
	else
		-- в хардкоре оценка глазом: до 10 м
		text = "РАЗРЫВ: " .. A.FmtDeviation( math.Round( lat / 10 ) * 10, math.Round( rng / 10 ) * 10 )
	end

	UI.HText( string.upper( text ), "SkyOpsArty_HUDLarge", ScrW() / 2, UI.S( 80 ), C.accent, TEXT_ALIGN_CENTER )
end

local function PaintHints()
	local auto = A.IsAuto()
	local parts = {
		"[" .. A.KeyName( keySend ) .. "] координаты",
		"[" .. A.KeyName( keyLaser ) .. "] лазер",
		"[" .. A.KeyName( keyLoiter ) .. "] барраж",
	}

	if auto then parts[ #parts + 1 ] = "[" .. A.KeyName( keyFire ) .. "] огонь САУ" end

	parts[ #parts + 1 ] = "[" .. UI.TabletKeyName() .. "] планшет"

	UI.HText( table.concat( parts, "   " ), "SkyOpsArty_HUDSmall", ScrW() / 2, ScrH() - UI.S( 40 ), C.muted, TEXT_ALIGN_CENTER )

	if Flash and CurTime() - Flash.time < 2.5 then
		UI.HText( Flash.text, "SkyOpsArty_HUDLarge", ScrW() / 2, ScrH() - UI.S( 90 ), Flash.col, TEXT_ALIGN_CENTER )
	end
end

hook.Add( "HUDPaint", "SkyOpsArty.UI.Drone", function()
	if not cvShow:GetBool() or IsValid( UI.TabletFrame ) then return end

	local drone = A.MyDrone()

	if not IsValid( drone ) then return end

	PaintTelemetry( drone )
	PaintTrack( drone )
	PaintImpacts( drone )
	PaintHints()
end )
