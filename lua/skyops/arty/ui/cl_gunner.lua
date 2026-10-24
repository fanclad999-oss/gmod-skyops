-- Артиллерия, интерфейс: шкалы наводчика в САУ.
-- Внизу шкала угломера, справа шкала прицела. Текущие установки ствола в центре шкалы,
-- установки из вычислителя отмечены янтарным треугольником; подсказка, куда и сколько
-- доворачивать. Значения угломера растут влево (против часовой), поэтому треугольник
-- всегда с той стороны, куда крутить.

local UI = SkyOps.Arty.UI
local A = UI.API
local C = UI.C

local cvShow = CreateClientConVar( "skyops_arty_ui_scales", "1", true, false, "Шкалы угломера и прицела в САУ" )

local TOLERANCE = 1 -- тысячных: «наведено»

local wasLaid = false

-- горизонтальная шкала угломера; values растут влево
local function DeflectionTape( cx, y, w, h, cur, set )
	local span = 150 -- тысячных в каждую сторону
	local ppm = ( w / 2 ) / span
	local x0 = cx - w / 2

	UI.Box( x0, y, w, h, C.panelAlpha )

	local first = math.floor( ( cur - span ) / 10 ) * 10

	for v = first, cur + span, 10 do
		local x = cx - ( v - cur ) * ppm

		if x >= x0 and x <= x0 + w then
			local major = v % 50 == 0
			local th = major and h * 0.45 or h * 0.22

			surface.SetDrawColor( major and C.hud or Color( C.hud.r, C.hud.g, C.hud.b, 120 ) )
			surface.DrawLine( x, y + h - th, x, y + h )

			if v % 100 == 0 then
				UI.Text( A.FmtMils( v % A.MILS ), "SkyOpsArty_HUDSmall", x, y + UI.S( 3 ), C.hud, TEXT_ALIGN_CENTER )
			end
		end
	end

	-- стрелка текущего положения
	UI.Pointer( cx, y + h, UI.S( 7 ), "up", C.text )
	UI.Outline( x0, y, w, h, C.line )

	if not set then return end

	local d = A.MilsDiff( set, cur )
	local sx = cx - d * ppm

	if sx < x0 or sx > x0 + w then
		local left = d > 0

		UI.Pointer( left and x0 - UI.S( 4 ) or x0 + w + UI.S( 4 ), y + h / 2, UI.S( 9 ), left and "left" or "right", C.accent )
	else
		UI.Pointer( sx, y + h - UI.S( 2 ), UI.S( 8 ), "down", C.accent )
	end
end

-- вертикальная шкала прицела; values растут вверх
local function ElevationTape( x, cy, w, h, cur, set )
	local span = 100
	local ppm = ( h / 2 ) / span
	local y0 = cy - h / 2

	UI.Box( x, y0, w, h, C.panelAlpha )

	local first = math.floor( ( cur - span ) / 5 ) * 5

	for v = first, cur + span, 5 do
		local y = cy - ( v - cur ) * ppm

		if y >= y0 and y <= y0 + h then
			local major = v % 25 == 0
			local tw = major and w * 0.4 or w * 0.2

			surface.SetDrawColor( major and C.hud or Color( C.hud.r, C.hud.g, C.hud.b, 120 ) )
			surface.DrawLine( x, y, x + tw, y )

			if v % 50 == 0 and v >= 0 then
				UI.Text( A.FmtMils( v ), "SkyOpsArty_HUDSmall", x + w - UI.S( 4 ), y, C.hud, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER )
			end
		end
	end

	UI.Pointer( x, cy, UI.S( 7 ), "right", C.text )
	UI.Outline( x, y0, w, h, C.line )

	if not set then return end

	local d = set - cur
	local sy = cy - d * ppm

	if sy < y0 or sy > y0 + h then
		local up = d > 0

		UI.Pointer( x + w / 2, up and y0 - UI.S( 4 ) or y0 + h + UI.S( 4 ), UI.S( 9 ), up and "up" or "down", C.accent )
	else
		UI.Pointer( x + UI.S( 2 ), sy, UI.S( 8 ), "left", C.accent )
	end
end

local function Hint( diff, posWord, negWord )
	if math.abs( diff ) <= TOLERANCE then return "ТОЧНО", C.ok end

	return ( diff > 0 and posWord or negWord ) .. " " .. A.FmtMils( math.abs( diff ) ), C.accent
end

local function ShellName( spg )
	local st = UI.State

	for _, s in ipairs( A.SHELLS ) do
		if s.id == st.shell then return s.name end
	end

	return "?"
end

hook.Add( "HUDPaint", "SkyOpsArty.UI.Gunner", function()
	if not cvShow:GetBool() then return end

	local spg = A.InSPG()

	if not spg or IsValid( UI.TabletFrame ) then return end

	local defl, elev = A.GunLaying( spg )

	if not defl then return end

	local sol = UI.State.solution
	local set = sol and sol.ok and sol or nil
	local sw, sh = ScrW(), ScrH()

	-- угломер
	local tw, th = UI.S( 560 ), UI.S( 44 )
	local ty = sh - UI.S( 150 )

	DeflectionTape( sw / 2, ty, tw, th, defl, set and set.deflection )
	UI.HText( "УГЛОМЕР " .. A.FmtMils( defl ), "SkyOpsArty_HUDLarge", sw / 2, ty - UI.S( 6 ), C.hud, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM )

	-- прицел
	local ew, eh = UI.S( 70 ), UI.S( 300 )
	local ex, ecy = sw - UI.S( 170 ), sh / 2

	ElevationTape( ex, ecy, ew, eh, elev, set and set.elevation )
	UI.HText( "ПРИЦЕЛ", "SkyOpsArty_HUDSmall", ex + ew / 2, ecy - eh / 2 - UI.S( 30 ), C.hud, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM )
	UI.HText( A.FmtMils( elev ), "SkyOpsArty_HUDLarge", ex + ew / 2, ecy - eh / 2 - UI.S( 6 ), C.hud, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM )

	-- подсказки и состояние
	local lx, ly = sw / 2, ty + th + UI.S( 10 )

	if not set then
		UI.HText( "нет установок: расчёт в планшете (" .. UI.TabletKeyName() .. ")", "SkyOpsArty_HUDSmall", lx, ly, C.muted, TEXT_ALIGN_CENTER )
		wasLaid = false
	else
		local dDefl = A.MilsDiff( set.deflection, defl )
		local dElev = set.elevation - elev
		local hDefl, cDefl = Hint( dDefl, "ВЛЕВО", "ВПРАВО" )
		local hElev, cElev = Hint( dElev, "ВЫШЕ", "НИЖЕ" )
		local laid = math.abs( dDefl ) <= TOLERANCE and math.abs( dElev ) <= TOLERANCE

		UI.HText( "угл. " .. A.FmtMils( set.deflection ) .. "  " .. hDefl, "SkyOpsArty_HUD", lx - UI.S( 20 ), ly, cDefl, TEXT_ALIGN_RIGHT )
		UI.HText( "приц. " .. A.FmtMils( set.elevation ) .. "  " .. hElev, "SkyOpsArty_HUD", lx + UI.S( 20 ), ly, cElev )

		if laid then
			UI.HText( "НАВЕДЕНО", "SkyOpsArty_HUDLarge", sw / 2, ty - UI.S( 48 ), C.ok, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM )

			if not wasLaid then surface.PlaySound( "buttons/blip1.wav" ) end
		end

		wasLaid = laid
	end

	-- слева: снаряд, заряд, время полёта, развёртывание
	local ix, iy = UI.S( 30 ), sh / 2 - UI.S( 60 )
	local lines = {
		{ "СНАРЯД " .. ShellName( spg ), C.hud },
		{ set and set.tof and string.format( "ПОЛЁТ %.1f с", set.tof ) or "ПОЛЁТ —", C.hud },
		{ set and string.format( "Д %.0f м", set.range ) or "Д —", C.hud },
		{ A.IsAuto() and "РЕЖИМ АВТО" or "РЕЖИМ ХАРДКОР", A.IsAuto() and C.ok or C.accent },
	}

	if not A.IsDeployed( spg ) then
		lines[ #lines + 1 ] = { "НЕ РАЗВЁРНУТА", C.threat }
	end

	for i, l in ipairs( lines ) do
		UI.HText( l[ 1 ], "SkyOpsArty_HUD", ix, iy + ( i - 1 ) * UI.S( 26 ), l[ 2 ] )
	end
end )
