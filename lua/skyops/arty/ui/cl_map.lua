-- Артиллерия, интерфейс: карта планшета (панель SkyOpsArtyMap).
-- Север вверх, координатная сетка по километрам, «улитка» при сильном приближении.
-- На карте: САУ, дроны с кругом барражирования и точкой камеры, цель, поправки, разрывы.
-- ЛКМ — цель, ЛКМ с перетаскиванием — сдвиг, колесо — масштаб, ПКМ — меню.

local UI = SkyOps.Arty.UI
local A = UI.API
local C = UI.C

local PANEL = {}

local MIN_MPP, MAX_MPP = 0.5, 150 -- метров на пиксель

function PANEL:Init()
	self.MPP = 25
	self:SetCursor( "crosshair" )
	self:CenterOnUnit()
end

function PANEL:CenterOn( e, n )
	self.CE, self.CN = e, n
end

function PANEL:CenterOnUnit()
	local spg = A.MySPG()
	local pos = IsValid( spg ) and spg:GetPos() or LocalPlayer():GetPos()
	local e, n = A.ToGrid( pos )

	self:CenterOn( e, n )
end

function PANEL:ToScreen( e, n )
	local w, h = self:GetSize()

	return w / 2 + ( e - self.CE ) / self.MPP, h / 2 - ( n - self.CN ) / self.MPP
end

function PANEL:FromScreen( x, y )
	local w, h = self:GetSize()

	return self.CE + ( x - w / 2 ) * self.MPP, self.CN - ( y - h / 2 ) * self.MPP
end

function PANEL:WorldToScreen( pos )
	local e, n = A.ToGrid( pos )

	return self:ToScreen( e, n )
end

-- Мышь ----------------------------------------------------------------------

function PANEL:OnMouseWheeled( delta )
	local mx, my = self:CursorPos()
	local e, n = self:FromScreen( mx, my )

	self.MPP = math.Clamp( self.MPP * 0.8 ^ delta, MIN_MPP, MAX_MPP )

	-- точка под курсором остаётся на месте
	local e2, n2 = self:FromScreen( mx, my )

	self.CE, self.CN = self.CE + e - e2, self.CN + n - n2

	return true
end

function PANEL:OnMousePressed( code )
	if code == MOUSE_LEFT then
		self.Drag = { x = gui.MouseX(), y = gui.MouseY(), moved = false }
		self:MouseCapture( true )
	elseif code == MOUSE_RIGHT then
		self:OpenMenu()
	end
end

function PANEL:OnMouseReleased( code )
	if code ~= MOUSE_LEFT or not self.Drag then return end

	self:MouseCapture( false )

	if not self.Drag.moved then
		local mx, my = self:CursorPos()

		self:PickTarget( self:FromScreen( mx, my ) )
	end

	self.Drag = nil
end

function PANEL:OnCursorMoved()
	local d = self.Drag

	if not d then return end

	local x, y = gui.MouseX(), gui.MouseY()

	if not d.moved and math.abs( x - d.x ) + math.abs( y - d.y ) < 5 then return end

	d.moved = true
	self.CE = self.CE - ( x - d.x ) * self.MPP
	self.CN = self.CN + ( y - d.y ) * self.MPP
	d.x, d.y = x, y
end

function PANEL:PickTarget( e, n )
	-- снятие с карты с точностью до 10 м
	e, n = math.Round( e / 10 ) * 10, math.Round( n / 10 ) * 10

	A.SetTarget( A.FromGrid( e, n, A.GroundH( e, n ) ), "карта" )
	surface.PlaySound( "buttons/button14.wav" )
end

function PANEL:OpenMenu()
	local mx, my = self:CursorPos()
	local e, n = self:FromScreen( mx, my )
	local menu = DermaMenu()

	menu:AddOption( "Цель сюда", function() self:PickTarget( e, n ) end ):SetIcon( "icon16/flag_red.png" )
	menu:AddOption( "Центр на САУ", function() self:CenterOnUnit() end ):SetIcon( "icon16/car.png" )

	local drone = A.MyDrone() or A.AllDrones()[ 1 ]

	if IsValid( drone ) then
		menu:AddOption( "Центр на дроне", function() self:CenterOn( A.ToGrid( drone:GetPos() ) ) end ):SetIcon( "icon16/eye.png" )
	end

	if A.Target then
		menu:AddOption( "Центр на цели", function() self:CenterOn( A.Target.e, A.Target.n ) end ):SetIcon( "icon16/flag_red.png" )
		menu:AddOption( "Снять цель", function()
			A.Target = nil
			UI.State.solution = nil
			hook.Run( "SkyOpsArty.TargetChanged", nil )
		end ):SetIcon( "icon16/cross.png" )
	end

	if #A.Impacts > 0 then
		menu:AddOption( "Стереть разрывы", function() table.Empty( A.Impacts ) end ):SetIcon( "icon16/bin.png" )
	end

	menu:Open()
end

-- Рисование -----------------------------------------------------------------

local function NiceStep( metres )
	for _, s in ipairs( { 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000 } ) do
		if s >= metres then return s end
	end

	return 50000
end

function PANEL:PaintGrid( w, h )
	local sq = A.SquareSize()
	local px = sq / self.MPP -- пикселей на квадрат
	local step = px >= 14 and sq or sq * 5
	local e0, n1 = self:FromScreen( 0, 0 )
	local e1, n0 = self:FromScreen( w, h )

	-- мелкая сетка 100 м и «улитка» при сильном приближении
	if px >= 260 then
		surface.SetDrawColor( Color( C.grid.r, C.grid.g, C.grid.b, 90 ) )

		for e = math.floor( e0 / 100 ) * 100, e1, 100 do
			local x = self:ToScreen( e, 0 )

			surface.DrawLine( x, 0, x, h )
		end

		for n = math.floor( n0 / 100 ) * 100, n1, 100 do
			local _, y = self:ToScreen( 0, n )

			surface.DrawLine( 0, y, w, y )
		end
	end

	if px >= 150 then
		local third = sq / 3

		for e = math.floor( e0 / third ) * third, e1, third do
			local x = self:ToScreen( e, 0 )

			UI.DashedLine( x, 0, x, h, 1, 4, 6, C.grid )
		end

		for n = math.floor( n0 / third ) * third, n1, third do
			local _, y = self:ToScreen( 0, n )

			UI.DashedLine( 0, y, w, y, 1, 4, 6, C.grid )
		end

		for e = math.floor( e0 / third ) * third, e1, third do
			for n = math.floor( n0 / third ) * third, n1, third do
				local x, y = self:ToScreen( e + third / 2, n + third / 2 )
				local _, snail = A.Square( e + third / 2, n + third / 2 )

				UI.Text( snail, "SkyOpsArty_H1", x, y, Color( C.gridMajor.r, C.gridMajor.g, C.gridMajor.b, 120 ), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER )
			end
		end
	end

	-- километровая сетка с подписями по краям
	for e = math.floor( e0 / step ) * step, e1, step do
		local x = self:ToScreen( e, 0 )
		local major = math.Round( e / sq ) % 5 == 0

		surface.SetDrawColor( major and C.gridMajor or C.grid )
		surface.DrawLine( x, 0, x, h )

		if px >= 22 or major then
			UI.Text( string.format( "%02d", math.Round( e / sq ) % 100 ), "SkyOpsArty_Label", x + 3, 2, C.muted )
		end
	end

	for n = math.floor( n0 / step ) * step, n1, step do
		local _, y = self:ToScreen( 0, n )
		local major = math.Round( n / sq ) % 5 == 0

		surface.SetDrawColor( major and C.gridMajor or C.grid )
		surface.DrawLine( 0, y, w, y )

		if px >= 22 or major then
			UI.Text( string.format( "%02d", math.Round( n / sq ) % 100 ), "SkyOpsArty_Label", 3, y - 2, C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM )
		end
	end
end

function PANEL:PaintSPG( spg, own )
	local x, y = self:WorldToScreen( spg:GetPos() )
	local s = UI.S( 7 )
	local col = own and C.accent or C.friend
	-- третье значение (дирекционный угол ствола) есть только у запасного GunLaying
	local _, _, barrel = A.GunLaying( spg )
	local r = math.rad( barrel and A.MilsToDeg( barrel ) or A.YawToBearing( spg:GetAngles().y ) )

	-- основное направление развёрнутой ОП
	if own and A.IsDeployed( spg ) then
		local base = math.rad( A.MilsToDeg( ( A.BaseDir( spg ) ) ) )

		UI.DashedLine( x, y, x + math.sin( base ) * UI.S( 400 ), y - math.cos( base ) * UI.S( 400 ), 1, 6, 6, Color( col.r, col.g, col.b, 110 ) )
	end

	UI.Box( x - s, y - s, s * 2, s * 2, C.bg )
	UI.Outline( x - s, y - s, s * 2, s * 2, col, 2 )
	UI.Line( x, y, x + math.sin( r ) * s * 2.6, y - math.cos( r ) * s * 2.6, 2, col )
	UI.Text( "2С35", "SkyOpsArty_Label", x + s + 4, y + s, col )
end

function PANEL:PaintDrone( drone, own )
	local x, y = self:WorldToScreen( drone:GetPos() )
	local col = own and C.accent or C.friend
	local r = math.rad( A.YawToBearing( drone:GetAngles().y ) )
	local s = UI.S( 9 )
	local function P( a, d ) return x + math.sin( r + a ) * d, y - math.cos( r + a ) * d end

	local center, radius = A.DroneLoiter( drone )

	if center then
		local cx, cy = self:WorldToScreen( center )

		UI.Circle( cx, cy, radius / A.UPM() / self.MPP, 1, Color( col.r, col.g, col.b, 120 ), nil, true )
	end

	local track = A.DroneTrack( drone )

	if track then
		local tx, ty = self:WorldToScreen( track )
		local laser = A.DroneLaser( drone )
		local lc = laser and C.laser or Color( col.r, col.g, col.b, 140 )

		UI.DashedLine( x, y, tx, ty, 1, 4, 4, lc )
		UI.Line( tx - 6, ty, tx, ty - 6, 2, lc )
		UI.Line( tx, ty - 6, tx + 6, ty, 2, lc )
		UI.Line( tx + 6, ty, tx, ty + 6, 2, lc )
		UI.Line( tx, ty + 6, tx - 6, ty, 2, lc )
	end

	local ax, ay = P( 0, s * 1.4 )
	local bx, by = P( 2.5, s )
	local cx2, cy2 = P( -2.5, s )

	draw.NoTexture()
	surface.SetDrawColor( col )
	surface.DrawPoly( { { x = ax, y = ay }, { x = bx, y = by }, { x = cx2, y = cy2 } } )

	UI.Text( A.UAV[ drone:GetClass() ] or "БПЛА", "SkyOpsArty_Label", x + s + 4, y - s, col )
end

function PANEL:PaintTarget()
	local t = A.Target

	if not t then return end

	local x, y = self:ToScreen( t.e, t.n )
	local s = UI.S( 10 )

	if t.err and t.err > 0 then
		UI.Circle( x, y, math.max( t.err / self.MPP, 3 ), 1, Color( C.threat.r, C.threat.g, C.threat.b, 90 ), nil, true )
	end

	UI.Circle( x, y, s, 2, C.threat )
	UI.Line( x - s * 1.6, y, x - s * 0.5, y, 2, C.threat )
	UI.Line( x + s * 0.5, y, x + s * 1.6, y, 2, C.threat )
	UI.Line( x, y - s * 1.6, x, y - s * 0.5, 2, C.threat )
	UI.Line( x, y + s * 0.5, x, y + s * 1.6, 2, C.threat )
	UI.HText( "ЦЕЛЬ", "SkyOpsArty_Label", x + s * 1.7, y - s * 1.7, C.threat )

	-- линия стрельбы и точка прицеливания с поправками
	local spg = A.MySPG()

	if not IsValid( spg ) then return end

	local ge, gn = A.ToGrid( spg:GetPos() )
	local gx, gy = self:ToScreen( ge, gn )
	local ae, an = A.AimPoint( ge, gn )
	local ax, ay = self:ToScreen( ae, an )

	UI.DashedLine( gx, gy, ax, ay, 1, 8, 6, Color( C.accent.r, C.accent.g, C.accent.b, 150 ) )

	if A.Shift.lat ~= 0 or A.Shift.rng ~= 0 then
		UI.Circle( ax, ay, UI.S( 5 ), 2, C.accent )
		UI.Line( x, y, ax, ay, 1, Color( C.accent.r, C.accent.g, C.accent.b, 120 ) )
	end

	local range = math.sqrt( ( ae - ge ) ^ 2 + ( an - gn ) ^ 2 )
	local mx, my = ( gx + ax ) / 2, ( gy + ay ) / 2

	UI.HText( string.format( "%.2f км  %s", range / 1000, A.FmtMils( A.Bearing( ge, gn, ae, an ) ) ), "SkyOpsArty_Label", mx + 6, my + 6, C.accent )
end

function PANEL:PaintImpacts()
	local now = CurTime()

	for i = #A.Impacts, 1, -1 do
		local imp = A.Impacts[ i ]
		local age = now - imp.time
		local alpha = math.Clamp( 255 - age * 1.5, 70, 255 )
		local x, y = self:WorldToScreen( imp.pos )
		local s = i == 1 and UI.S( 8 ) or UI.S( 5 )
		local col = Color( C.accent.r, C.accent.g, C.accent.b, alpha )

		UI.Line( x - s, y - s, x + s, y + s, 2, col )
		UI.Line( x - s, y + s, x + s, y - s, 2, col )

		if i == 1 and age < 3 then UI.Circle( x, y, s + age * 12, 2, col ) end
	end
end

function PANEL:PaintRangeRings()
	local spg = A.MySPG()

	if not IsValid( spg ) then return end

	local st = UI.State
	local minR, maxR = A.ChargeRange( st.shell, st.charge )

	if not maxR then return end

	local x, y = self:WorldToScreen( spg:GetPos() )
	local col = Color( C.accent.r, C.accent.g, C.accent.b, 70 )

	UI.Circle( x, y, maxR / self.MPP, 1, col, 128, true )

	if minR and minR > 0 then UI.Circle( x, y, minR / self.MPP, 1, col, 96, true ) end
end

function PANEL:PaintOverlay( w, h )
	-- север
	local nx, ny = w - UI.S( 28 ), UI.S( 34 )

	UI.Pointer( nx, ny - UI.S( 16 ), UI.S( 7 ), "up", C.text )
	UI.Text( "С", "SkyOpsArty_H2", nx, ny - UI.S( 4 ), C.text, TEXT_ALIGN_CENTER )

	-- нижняя строка: координаты под курсором и масштаб
	local bh = UI.S( 30 )

	UI.Box( 0, h - bh, w, bh, C.panelAlpha )

	if self:IsHovered() then
		local mx, my = self:CursorPos()
		local e, n = self:FromScreen( mx, my )
		local sq, snail = A.Square( e, n )
		local gh = A.GroundH( e, n )
		local line = string.format( "%s   кв. %s по улитке %d", A.FormatGrid( e, n ), sq, snail )

		if gh then line = line .. string.format( "   H %.0f м", gh ) end

		local spg = A.MySPG()

		if IsValid( spg ) then
			local ge, gn = A.ToGrid( spg:GetPos() )

			line = line .. string.format( "   Д %.2f км  %s", math.sqrt( ( e - ge ) ^ 2 + ( n - gn ) ^ 2 ) / 1000, A.FmtMils( A.Bearing( ge, gn, e, n ) ) )
		end

		UI.Text( line, "SkyOpsArty_Label", UI.S( 10 ), h - bh / 2, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER )
	else
		UI.Text( "ЛКМ — цель   тащить — сдвиг   колесо — масштаб   ПКМ — меню", "SkyOpsArty_Label", UI.S( 10 ), h - bh / 2, C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER )
	end

	local metres = NiceStep( UI.S( 110 ) * self.MPP )
	local len = metres / self.MPP
	local x1, y1 = w - UI.S( 16 ) - len, h - bh / 2

	UI.Line( x1, y1, x1 + len, y1, 2, C.text )
	UI.Line( x1, y1 - 4, x1, y1 + 4, 2, C.text )
	UI.Line( x1 + len, y1 - 4, x1 + len, y1 + 4, 2, C.text )
	UI.Text( metres >= 1000 and ( metres / 1000 .. " км" ) or ( metres .. " м" ), "SkyOpsArty_Label", x1 - UI.S( 8 ), y1, C.text, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER )
end

function PANEL:Paint( w, h )
	UI.Box( 0, 0, w, h, C.map )

	local x, y = self:LocalToScreen( 0, 0 )

	render.SetScissorRect( x, y, x + w, y + h, true )

	self:PaintGrid( w, h )
	self:PaintRangeRings()

	local mySPG = A.MySPG()

	for _, spg in ipairs( ents.FindByClass( A.SPG_CLASS ) ) do
		self:PaintSPG( spg, spg == mySPG )
	end

	local myDrone = A.MyDrone()

	for _, drone in ipairs( A.AllDrones() ) do
		self:PaintDrone( drone, drone == myDrone )
	end

	self:PaintImpacts()
	self:PaintTarget()

	-- сам игрок, если он не в технике
	if not A.Vehicle() then
		local px, py = self:WorldToScreen( LocalPlayer():GetPos() )

		UI.FilledCircle( px, py, UI.S( 4 ), C.ok, 12 )
	end

	self:PaintOverlay( w, h )

	render.SetScissorRect( 0, 0, 0, 0, false )

	UI.Outline( 0, 0, w, h, C.line )
end

vgui.Register( "SkyOpsArtyMap", PANEL, "DPanel" )
