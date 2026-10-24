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

-- сглаживание показаний: muzzle-аттачмент дрожит на кочках, шкалы не должны
local Smooth = { defl = nil, elev = nil }

local function SmoothValues( defl, elev )
	local f = math.Clamp( FrameTime() * 14, 0, 1 )

	if not Smooth.defl or math.abs( A.MilsDiff( defl, Smooth.defl ) ) > 300 then
		Smooth.defl, Smooth.elev = defl, elev
	else
		Smooth.defl = ( Smooth.defl + A.MilsDiff( defl, Smooth.defl ) * f ) % A.MILS
		Smooth.elev = Smooth.elev + ( elev - Smooth.elev ) * f
	end

	return Smooth.defl, Smooth.elev
end

-- плашка состояния ОП сверху по центру, с полосой при развёртывании и свёртывании
local function PaintState( spg, sw )
	local state, left = A.SPGState( spg )
	local auto = A.AutoLaying( spg )
	local text, col = A.STATE_NAMES[ state ] or "?", C.hud

	if state == A.STATE_MARCH then col = C.threat end
	if state == A.STATE_DEPLOYING or state == A.STATE_STOWING then col = C.accent end
	if auto then text, col = "АВТОНАВОДКА", C.ok end

	local w, h = UI.S( 300 ), UI.S( 34 )
	local x, y = sw / 2 - w / 2, UI.S( 24 )

	UI.Box( x, y, w, h, C.panelAlpha )
	UI.Box( x, y, UI.S( 4 ), h, col )
	UI.HText( text, "SkyOpsArty_HUD", sw / 2, y + h / 2, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER )

	if ( state == A.STATE_DEPLOYING or state == A.STATE_STOWING ) and left > 0 then
		-- полное время перехода не передаётся; полоса тает от первого увиденного значения
		spg.SkyOpsArtyUI_StateTotal = spg.SkyOpsArtyUI_StateKey == state and spg.SkyOpsArtyUI_StateTotal or left
		spg.SkyOpsArtyUI_StateKey = state

		local frac = 1 - left / math.max( spg.SkyOpsArtyUI_StateTotal, 0.01 )

		UI.Box( x, y + h, w, UI.S( 3 ), C.line )
		UI.Box( x, y + h, w * frac, UI.S( 3 ), col )
		UI.HText( string.format( "%.0f с", left ), "SkyOpsArty_HUDSmall", x + w + UI.S( 8 ), y + h / 2, col, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER )
	else
		spg.SkyOpsArtyUI_StateKey = nil
	end

	if state == A.STATE_MARCH and A.HasFireComp() then
		local key = A.SPGKey( "deploy" )

		if key then
			UI.HText( "[" .. key .. "] развернуть", "SkyOpsArty_HUDSmall", sw / 2, y + h + UI.S( 8 ), C.muted, TEXT_ALIGN_CENTER )
		end
	end
end

-- левая панель: боеприпас в САУ и по расчёту, полёт, дальность, режим
local function PaintInfo( spg, set, sh )
	local st = UI.State
	local rows = {}
	local function Row( k, v, col ) rows[ #rows + 1 ] = { k, v, col or C.hud } end

	if A.HasFireComp() then
		local shell, charge = A.LoadedShell( spg ), A.LoadedCharge( spg )

		Row( "СНАРЯД", A.ShellName( shell ), ( set and shell ~= st.shell ) and C.threat or C.hud )
		Row( "ЗАРЯД", charge > 0 and A.ChargeName( shell, charge ) or "—", ( set and set.charge and charge > 0 and charge ~= set.charge ) and C.threat or C.hud )
	else
		Row( "СНАРЯД", A.ShellName( st.shell ) )
	end

	Row( "ПОЛЁТ", set and set.tof and string.format( "%.1f с", set.tof ) or "—" )
	Row( "ДАЛЬН.", set and string.format( "%.0f м", set.range ) or "—" )
	Row( "РЕЖИМ", A.IsAuto() and "АВТО" or "ХАРДКОР", A.IsAuto() and C.ok or C.accent )

	-- свой дрон, пока игрок в САУ: подсветка держится? кружит?
	local drone = A.LinkedDrone()

	if IsValid( drone ) then
		local spot, blocked = A.DroneLaserSpot( drone )

		if spot then
			Row( "ЛАЗЕР", blocked and "СОРВАН" or "ДЕРЖИТ", blocked and C.threat or C.laser )
		else
			Row( "ДРОН", A.DroneLoiter( drone ) and "барраж" or "в полёте", C.muted )
		end
	end

	local x, w = UI.S( 24 ), UI.S( 250 )
	local rh = UI.S( 26 )
	local y = sh / 2 - #rows * rh / 2

	UI.Box( x, y - UI.S( 8 ), w, #rows * rh + UI.S( 16 ), C.panelAlpha )

	for i, r in ipairs( rows ) do
		local ry = y + ( i - 1 ) * rh

		UI.HText( r[ 1 ], "SkyOpsArty_HUDSmall", x + UI.S( 12 ), ry + rh / 2, C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER )
		UI.HText( r[ 2 ], "SkyOpsArty_HUD", x + w - UI.S( 12 ), ry + rh / 2, r[ 3 ], TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER )
	end

	-- что не так с боеприпасом: подсказка под панелью
	if set and A.HasFireComp() then
		local warn

		if A.LoadedShell( spg ) ~= st.shell then
			warn = "снаряд не тот, что в расчёте"
		elseif set.charge and A.LoadedCharge( spg ) > 0 and A.LoadedCharge( spg ) ~= set.charge then
			local key = A.SPGKey( "charge" )

			warn = "нужен заряд «" .. A.ChargeName( st.shell, set.charge ) .. "»" .. ( key and ( " [" .. key .. "]" ) or "" )
		end

		if warn then
			UI.HText( warn, "SkyOpsArty_HUDSmall", x + UI.S( 12 ), y + #rows * rh + UI.S( 14 ), C.threat )
		end
	end
end

local function PaintKeys( spg, sw, sh )
	if not A.HasFireComp() or not spg:GetNW2Bool( "SkyOpsArty_Lay", false ) then return end

	local parts = {}
	local function K( name, label )
		local k = A.SPGKey( name )

		if k then parts[ #parts + 1 ] = "[" .. k .. "] " .. label end
	end

	K( "left", "влево" ) K( "right", "вправо" ) K( "up", "выше" ) K( "down", "ниже" )
	K( "fast", "x10" ) K( "charge", "заряд" ) K( "deploy", "свернуть" )
	parts[ #parts + 1 ] = "[" .. UI.TabletKeyName() .. "] планшет"

	if UI.SwitchKeyName and IsValid( A.LinkedDrone() ) then
		parts[ #parts + 1 ] = "[" .. UI.SwitchKeyName() .. "] в дрон"
	elseif UI.DeployKeyName then
		parts[ #parts + 1 ] = "[" .. UI.DeployKeyName() .. "] вылет дрона"
	end

	UI.HText( table.concat( parts, "   " ), "SkyOpsArty_HUDSmall", sw / 2, sh - UI.S( 36 ), C.muted, TEXT_ALIGN_CENTER )
end

hook.Add( "HUDPaint", "SkyOpsArty.UI.Gunner", function()
	if not cvShow:GetBool() then return end

	local spg = A.InSPG()

	if not spg or IsValid( UI.TabletFrame ) then
		Smooth.defl = nil

		return
	end

	local rawDefl, rawElev = A.GunLaying( spg )

	if not rawDefl then return end

	local defl, elev = SmoothValues( rawDefl, rawElev )
	local sol = UI.State.solution
	local set = sol and sol.ok and sol or nil
	local sw, sh = ScrW(), ScrH()

	PaintState( spg, sw )
	PaintInfo( spg, set, sh )
	PaintKeys( spg, sw, sh )

	-- угломер
	local tw, th = UI.S( 560 ), UI.S( 44 )
	local ty = sh - UI.S( 160 )

	DeflectionTape( sw / 2, ty, tw, th, defl, set and set.deflection )
	UI.HText( "УГЛОМЕР " .. A.FmtMils( defl ), "SkyOpsArty_HUDLarge", sw / 2, ty - UI.S( 6 ), C.hud, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM )

	-- прицел
	local ew, eh = UI.S( 70 ), UI.S( 300 )
	local ex, ecy = sw - UI.S( 170 ), sh / 2

	ElevationTape( ex, ecy, ew, eh, elev, set and set.elevation )
	UI.HText( "ПРИЦЕЛ", "SkyOpsArty_HUDSmall", ex + ew / 2, ecy - eh / 2 - UI.S( 30 ), C.hud, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM )
	UI.HText( A.FmtMils( elev ), "SkyOpsArty_HUDLarge", ex + ew / 2, ecy - eh / 2 - UI.S( 6 ), C.hud, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM )

	-- подсказки по наводке считаем по сырым значениям, а не сглаженным
	local lx, ly = sw / 2, ty + th + UI.S( 10 )

	if not set then
		UI.HText( "нет установок: расчёт в планшете (" .. UI.TabletKeyName() .. ")", "SkyOpsArty_HUDSmall", lx, ly, C.muted, TEXT_ALIGN_CENTER )
		wasLaid = false

		return
	end

	local dDefl = A.MilsDiff( set.deflection, rawDefl )
	local dElev = set.elevation - rawElev
	local hDefl, cDefl = Hint( dDefl, "ВЛЕВО", "ВПРАВО" )
	local hElev, cElev = Hint( dElev, "ВЫШЕ", "НИЖЕ" )
	local laid = math.abs( dDefl ) <= TOLERANCE and math.abs( dElev ) <= TOLERANCE

	UI.HText( "угл. " .. A.FmtMils( set.deflection ) .. "  " .. hDefl, "SkyOpsArty_HUD", lx - UI.S( 20 ), ly, cDefl, TEXT_ALIGN_RIGHT )
	UI.HText( "приц. " .. A.FmtMils( set.elevation ) .. "  " .. hElev, "SkyOpsArty_HUD", lx + UI.S( 20 ), ly, cElev )

	if laid then
		if not wasLaid then
			surface.PlaySound( "buttons/blip1.wav" )
			UI.LaidAt = RealTime()
		end

		-- вспышка в момент наведения, потом ровное свечение
		local t = RealTime() - ( UI.LaidAt or 0 )
		local a = t < 0.6 and ( 255 * ( 0.5 + 0.5 * math.cos( t * 20 ) ) ) or 255
		local col = Color( C.ok.r, C.ok.g, C.ok.b, a )
		local bw, bh = UI.S( 240 ), UI.S( 44 )
		local bx, by = sw / 2 - bw / 2, ty - UI.S( 52 ) - bh

		UI.Box( bx, by, bw, bh, C.panelAlpha )
		UI.Outline( bx, by, bw, bh, col, 2 )
		UI.HText( "НАВЕДЕНО", "SkyOpsArty_HUDLarge", sw / 2, by + bh / 2, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER )
	end

	wasLaid = laid
end )
