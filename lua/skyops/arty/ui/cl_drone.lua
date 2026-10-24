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
	local dir = ( pos - A.EntPos( drone ) ):GetNormalized()
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

-- пересесть САУ <-> дрон (arty/drone/sv_switch), работает и из САУ
local function Switch()
	if not A.DroneCmd( "switch" ) then Say( "ПЕРЕСАДКА НЕДОСТУПНА: нет модуля дрона", C.threat ) end
end

local keySwitch = A.Bind( "skyops_arty_key_switch", KEY_U, "Пересесть САУ <-> дрон", Switch, function() return InDrone() or A.InSPG() ~= nil end )

UI.SwitchKeyName = function() return A.KeyName( keySwitch ) end

concommand.Add( "skyops_arty_send", function() if InDrone() then SendTarget() end end )
concommand.Add( "skyops_arty_laser", function() if InDrone() then ToggleLaser() end end )
concommand.Add( "skyops_arty_loiter", function() if InDrone() then ToggleLoiter() end end )
concommand.Add( "skyops_arty_firecam", function() if InDrone() then FireAtTrack() end end )

-- Рисование -----------------------------------------------------------------

local function PaintTelemetry( drone )
	local upm = A.UPM()
	local pos = A.EntPos( drone )
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
	local bx, by = sw / 2, UI.S( 80 )

	if laser then
		local blink = math.floor( CurTime() * 3 ) % 2 == 0

		local spot, blocked = A.DroneLaserSpot( drone )

		if blocked then
			UI.HText( "ЛАЗЕР СОРВАН: далеко или за препятствием", "SkyOpsArty_HUDLarge", bx, by, blink and C.threat or C.accent, TEXT_ALIGN_CENTER )
		else
			UI.HText( string.format( "ЛАЗЕР  %.0f с", CurTime() - LaserSince ), "SkyOpsArty_HUDLarge", bx, by, blink and C.laser or Color( C.laser.r, C.laser.g, C.laser.b, 120 ), TEXT_ALIGN_CENTER )
		end

		-- пятно подсветки на экране: ромб с лучами
		local sx, sy

		if spot then sx, sy = Project( drone, spot ) end

		if sx then
			local r = UI.S( 10 ) + math.sin( RealTime() * 8 ) * UI.S( 2 )
			local lc = blocked and C.accent or C.laser

			UI.Line( sx - r, sy, sx, sy - r, 2, lc )
			UI.Line( sx, sy - r, sx + r, sy, 2, lc )
			UI.Line( sx + r, sy, sx, sy + r, 2, lc )
			UI.Line( sx, sy + r, sx - r, sy, 2, lc )
		end
	end

	if not track then
		UI.HText( "нет захвата: наведи камеру и включи сопровождение", "SkyOpsArty_HUDSmall", bx, by + UI.S( 36 ), C.muted, TEXT_ALIGN_CENTER )

		return
	end

	local e, n, h = A.ToGrid( track )
	local sq, snail = A.Square( e, n )
	local dist = track:Distance( A.EntPos( drone ) ) / A.UPM()
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
		local ge, gn = A.ToGrid( A.EntPos( spg ) )

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

	local ge, gn = A.ToGrid( A.EntPos( spg ) )
	local ie, inn = A.ToGrid( last.pos )
	local lat, rng = A.Deviation( ge, gn, t.e, t.n, ie, inn )
	local text

	if A.IsAuto() then
		text = "РАЗРЫВ: " .. A.FmtDeviation( lat, rng )
	else
		-- в хардкоре оценка глазом: до 10 м
		text = "РАЗРЫВ: " .. A.FmtDeviation( math.Round( lat / 10 ) * 10, math.Round( rng / 10 ) * 10 )
	end

	UI.HText( string.upper( text ), "SkyOpsArty_HUDLarge", ScrW() / 2, UI.S( 150 ), C.accent, TEXT_ALIGN_CENTER )
end

-- шкала курса сверху: градусы, метки сторон света, треугольник на курсе
local CARDINAL = { [ 0 ] = "С", [ 45 ] = "СВ", [ 90 ] = "В", [ 135 ] = "ЮВ", [ 180 ] = "Ю", [ 225 ] = "ЮЗ", [ 270 ] = "З", [ 315 ] = "СЗ" }

local function PaintCompass( drone )
	local heading = A.YawToBearing( EyeAngles().y )
	local w, h = UI.S( 480 ), UI.S( 30 )
	local cx, y = ScrW() / 2, UI.S( 4 )
	local span = 60 -- градусов на всю ширину
	local ppd = w / span

	UI.Box( cx - w / 2, y, w, h, C.panelAlpha )

	for d = math.floor( heading - span / 2 ), math.ceil( heading + span / 2 ) do
		if d % 5 == 0 then
			local x = cx + ( d - heading ) * ppd
			local deg = d % 360
			local major = deg % 15 == 0

			surface.SetDrawColor( major and C.hud or Color( C.hud.r, C.hud.g, C.hud.b, 110 ) )
			surface.DrawLine( x, y + h - ( major and UI.S( 9 ) or UI.S( 5 ) ), x, y + h )

			if CARDINAL[ deg ] then
				UI.Text( CARDINAL[ deg ], "SkyOpsArty_HUDSmall", x, y + UI.S( 2 ), deg == 0 and C.accent or C.hud, TEXT_ALIGN_CENTER )
			elseif deg % 15 == 0 then
				UI.Text( string.format( "%03d", deg ), "SkyOpsArty_Label", x, y + UI.S( 4 ), C.muted, TEXT_ALIGN_CENTER )
			end
		end
	end

	UI.Pointer( cx, y + h, UI.S( 6 ), "up", C.text )
	UI.HText( string.format( "%03.0f°", heading ), "SkyOpsArty_HUDSmall", cx, y + h + UI.S( 10 ), C.text, TEXT_ALIGN_CENTER )
end

-- уголки видоискателя и шкала дальности камеры
local function PaintViewfinder()
	local sw, sh = ScrW(), ScrH()
	local m, len = UI.S( 60 ), UI.S( 40 )
	local col = Color( C.hud.r, C.hud.g, C.hud.b, 150 )

	for _, c in ipairs( { { m, m, 1, 1 }, { sw - m, m, -1, 1 }, { m, sh - m, 1, -1 }, { sw - m, sh - m, -1, -1 } } ) do
		UI.Line( c[ 1 ], c[ 2 ], c[ 1 ] + len * c[ 3 ], c[ 2 ], 2, col )
		UI.Line( c[ 1 ], c[ 2 ], c[ 1 ], c[ 2 ] + len * c[ 4 ], 2, col )
	end

	-- метка по центру экрана: куда смотрит камера
	local cx, cy, g = sw / 2, sh / 2, UI.S( 8 )

	UI.Line( cx - g * 3, cy, cx - g, cy, 1, col )
	UI.Line( cx + g, cy, cx + g * 3, cy, 1, col )
	UI.Line( cx, cy - g * 3, cx, cy - g, 1, col )
	UI.Line( cx, cy + g, cx, cy + g * 3, 1, col )
end

-- мини-карта слева снизу: север вверх, 3 км вокруг дрона
local MINIMAP_KM = 3

local function PaintMinimap( drone )
	local size = UI.S( 220 )
	local x, y = UI.S( 24 ), ScrH() - size - UI.S( 70 )
	local r = size / 2
	local cx, cy = x + r, y + r
	local de, dn = A.ToGrid( A.EntPos( drone ) )
	local mpp = MINIMAP_KM * 1000 / r

	local function P( pos )
		local e, n = A.ToGrid( pos )
		local px, py = ( e - de ) / mpp, -( n - dn ) / mpp
		local d = math.sqrt( px * px + py * py )

		-- за краем: прижимаем к окружности
		if d > r - 4 then
			px, py = px / d * ( r - 4 ), py / d * ( r - 4 )

			return cx + px, cy + py, true
		end

		return cx + px, cy + py, false
	end

	UI.FilledCircle( cx, cy, r, C.panelAlpha, 48 )
	UI.Circle( cx, cy, r, 1, C.line, 48 )
	UI.Circle( cx, cy, r / 3 * 2, 1, Color( C.line.r, C.line.g, C.line.b, 120 ), 40, true )
	UI.Circle( cx, cy, r / 3, 1, Color( C.line.r, C.line.g, C.line.b, 120 ), 32, true )
	UI.Text( "С", "SkyOpsArty_HUDSmall", cx, y + UI.S( 2 ), C.text, TEXT_ALIGN_CENTER )
	UI.Text( MINIMAP_KM .. " км", "SkyOpsArty_Label", x + size, y + size, C.muted, TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM )

	local center, radius = A.DroneLoiter( drone )

	if center then
		local lx, ly = P( center )

		UI.Circle( lx, ly, radius / A.UPM() / mpp, 1, Color( C.ok.r, C.ok.g, C.ok.b, 120 ), 32, true )
	end

	for _, imp in ipairs( A.Impacts ) do
		if CurTime() - imp.time < 90 then
			local ix, iy, edge = P( imp.pos )

			if not edge then
				UI.Line( ix - 3, iy - 3, ix + 3, iy + 3, 1, C.accent )
				UI.Line( ix - 3, iy + 3, ix + 3, iy - 3, 1, C.accent )
			end
		end
	end

	if A.Target then
		local tx, ty = P( A.Target.pos )

		UI.Circle( tx, ty, UI.S( 5 ), 2, C.threat, 12 )
	end

	local track = A.DroneTrack( drone )

	if track then
		local tx, ty = P( track )

		UI.DashedLine( cx, cy, tx, ty, 1, 3, 3, A.DroneLaser( drone ) and C.laser or C.hud )
		UI.Box( tx - 2, ty - 2, 4, 4, A.DroneLaser( drone ) and C.laser or C.hud )
	end

	local spg = A.MySPG()

	if IsValid( spg ) then
		local sx, sy, edge = P( A.EntPos( spg ) )
		local s = UI.S( 4 )

		UI.Outline( sx - s, sy - s, s * 2, s * 2, C.accent, 2 )

		if edge then
			local ge, gn = A.ToGrid( A.EntPos( spg ) )

			UI.Text( string.format( "%.0f км", math.sqrt( ( ge - de ) ^ 2 + ( gn - dn ) ^ 2 ) / 1000 ), "SkyOpsArty_Label", sx, sy + s + 2, C.accent, TEXT_ALIGN_CENTER )
		end
	end

	-- сам дрон: стрелка по курсу
	local a = math.rad( A.YawToBearing( drone:GetAngles().y ) )
	local s = UI.S( 8 )
	local function Q( ang, d ) return { x = cx + math.sin( a + ang ) * d, y = cy - math.cos( a + ang ) * d } end

	draw.NoTexture()
	surface.SetDrawColor( C.text )
	surface.DrawPoly( { Q( 0, s * 1.3 ), Q( 2.5, s ), Q( math.pi, s * 0.3 ) } )
	surface.DrawPoly( { Q( 0, s * 1.3 ), Q( math.pi, s * 0.3 ), Q( -2.5, s ) } )
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
	parts[ #parts + 1 ] = "[" .. A.KeyName( keySwitch ) .. "] в САУ"

	UI.HText( table.concat( parts, "   " ), "SkyOpsArty_HUDSmall", ScrW() / 2, ScrH() - UI.S( 40 ), C.muted, TEXT_ALIGN_CENTER )

	if Flash and CurTime() - Flash.time < 2.5 then
		UI.HText( Flash.text, "SkyOpsArty_HUDLarge", ScrW() / 2, ScrH() - UI.S( 90 ), Flash.col, TEXT_ALIGN_CENTER )
	end
end

hook.Add( "HUDPaint", "SkyOpsArty.UI.Drone", function()
	if not cvShow:GetBool() or IsValid( UI.TabletFrame ) then return end

	local drone = A.MyDrone()

	if not IsValid( drone ) then return end

	PaintViewfinder()
	PaintCompass( drone )
	PaintTelemetry( drone )
	PaintMinimap( drone )
	PaintTrack( drone )
	PaintImpacts( drone )
	PaintHints()
end )
