-- Артиллерия, интерфейс: огневой вычислитель (панель SkyOpsArtyComputer).
-- Ввод ОП и цели, снаряд, заряд, группа углов -> угломер, прицел, время полёта.
-- Корректура по разрывам. В режиме «авто» одна кнопка: навести и выстрелить.

local UI = SkyOps.Arty.UI
local A = UI.API
local C = UI.C

local PANEL = {}

local function Section( parent, title, height )
	local p = vgui.Create( "DPanel", parent )

	p:Dock( TOP )
	p:DockMargin( 0, 0, 0, UI.S( 10 ) )
	p:SetTall( height )
	p.Title = title
	p.Paint = function( self, w, h )
		UI.Box( 0, 0, w, h, C.panel )
		UI.Text( self.Title, "SkyOpsArty_Label", UI.S( 10 ), UI.S( 6 ), C.muted )
	end

	return p
end

-- ряд «подпись + поле» на секции, x и ширина в долях секции
local function Field( sec, label, placeholder, col, cols )
	local e = UI.NumEntry( sec, placeholder )

	e.Label = label
	e.Col, e.Cols = col, cols

	sec.Fields = sec.Fields or {}
	sec.Fields[ #sec.Fields + 1 ] = e

	return e
end

local function LayoutFields( sec, y )
	local pad, gap = UI.S( 10 ), UI.S( 8 )
	local w = sec:GetWide() - pad * 2

	for _, e in ipairs( sec.Fields or {} ) do
		local cw = ( w - gap * ( e.Cols - 1 ) ) / e.Cols

		e:SetPos( pad + ( e.Col - 1 ) * ( cw + gap ), y + UI.S( 18 ) )
		e:SetSize( cw, UI.S( 30 ) )
	end
end

local function PaintFieldLabels( sec )
	for _, e in ipairs( sec.Fields or {} ) do
		local x, y = e:GetPos()

		UI.Text( e.Label, "SkyOpsArty_Label", x, y - UI.S( 17 ), C.muted )
	end
end

function PANEL:Init()
	self:SetPaintBackground( false )

	local scroll = vgui.Create( "DScrollPanel", self )

	scroll:Dock( FILL )
	scroll:GetVBar():SetWide( UI.S( 6 ) )
	scroll:GetVBar().Paint = function( _, w, h ) UI.Box( 0, 0, w, h, C.bg ) end
	scroll:GetVBar().btnGrip.Paint = function( _, w, h ) UI.Box( 0, 0, w, h, C.line ) end
	scroll:GetVBar():SetHideButtons( true )

	self.Scroll = scroll

	self:BuildMode( scroll )
	self:BuildGun( scroll )
	self:BuildTarget( scroll )
	self:BuildAmmo( scroll )
	self:BuildResult( scroll )
	self:BuildCorrection( scroll )

	self:FillGunFromNav()
	self:FillTarget( A.Target )

	hook.Add( "SkyOpsArty.TargetChanged", self, function( pnl, t )
		pnl:FillTarget( t )

		if t then pnl:Solve( true ) end
	end )

	hook.Add( "SkyOpsArty.Impact", self, function( pnl ) pnl:UpdateLastImpact() end )
end

-- Режим ---------------------------------------------------------------------

function PANEL:BuildMode( parent )
	local sec = Section( parent, "РЕЖИМ", UI.S( 62 ) )

	sec.Paint = function( s, w, h )
		UI.Box( 0, 0, w, h, C.panel )
		UI.Text( "РЕЖИМ", "SkyOpsArty_Label", UI.S( 10 ), UI.S( 6 ), C.muted )

		local auto = A.IsAuto()

		UI.Text( auto and "АВТО" or "ХАРДКОР", "SkyOpsArty_H1", UI.S( 10 ), UI.S( 22 ), auto and C.ok or C.accent )
		UI.Text( auto and "САУ наводится сама" or "угломер и прицел вручную", "SkyOpsArty_Label", UI.S( 10 ) + UI.TextSize( "ХАРДКОР", "SkyOpsArty_H1" ) + UI.S( 12 ), UI.S( 34 ), C.muted )
	end

	-- режим задаёт сервер; менять может админ (в одиночной игре это ты)
	if LocalPlayer():IsAdmin() or game.SinglePlayer() then
		local btn = UI.Button( sec, "Сменить", "ghost", function()
			A.SetMode( A.IsAuto() and "hardcore" or "auto" )
			timer.Simple( 0.3, function() if IsValid( self ) then self:InvalidateLayout() end end )
		end )

		btn.Font = "SkyOpsArty_Label"
		sec.PerformLayout = function( s, w, h )
			btn:SetSize( UI.S( 90 ), UI.S( 28 ) )
			btn:SetPos( w - UI.S( 100 ), ( h - UI.S( 28 ) ) / 2 )
		end
	end
end

-- Огневая позиция -----------------------------------------------------------

function PANEL:BuildGun( parent )
	local sec = Section( parent, "ОГНЕВАЯ ПОЗИЦИЯ", UI.S( 128 ) )

	self.GunN = Field( sec, "С, м", "север", 1, 3 )
	self.GunE = Field( sec, "В, м", "восток", 2, 3 )
	self.GunH = Field( sec, "H, м", "высота", 3, 3 )

	local nav = UI.Button( sec, "Привязка по навигации", "ghost", function() self:FillGunFromNav() end )

	nav.Font = "SkyOpsArty_Label"

	sec.PerformLayout = function( s, w, h )
		LayoutFields( s, UI.S( 8 ) )
		nav:SetPos( UI.S( 10 ), UI.S( 88 ) )
		nav:SetSize( UI.S( 200 ), UI.S( 28 ) )
	end

	sec.Paint = function( s, w, h )
		UI.Box( 0, 0, w, h, C.panel )
		UI.Text( "ОГНЕВАЯ ПОЗИЦИЯ", "SkyOpsArty_Label", UI.S( 10 ), UI.S( 6 ), C.muted )
		PaintFieldLabels( s )

		local spg = A.MySPG()
		local x = UI.S( 220 )

		if not IsValid( spg ) then
			UI.Text( "САУ рядом нет", "SkyOpsArty_Label", x, UI.S( 102 ), C.threat, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER )

			return
		end

		local base, fixed = A.BaseDir( spg )
		local deployed = A.IsDeployed( spg )

		UI.Text( ( deployed and "развёрнута" or "походное положение" ), "SkyOpsArty_Label", x, UI.S( 94 ), deployed and C.ok or C.threat, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER )
		UI.Text( "ОН " .. A.FmtMils( base ) .. ( fixed and "" or " (по корпусу)" ), "SkyOpsArty_Label", x, UI.S( 112 ), C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER )
	end
end

function PANEL:FillGunFromNav()
	local spg = A.MySPG()
	local pos = IsValid( spg ) and spg:GetPos() or LocalPlayer():GetPos()
	local e, n, h = A.ToGrid( pos )

	self.GunN:SetNumber( n )
	self.GunE:SetNumber( e )
	self.GunH:SetNumber( h )
end

function PANEL:GunInput()
	local e, n, h = self.GunE:GetNumber(), self.GunN:GetNumber(), self.GunH:GetNumber()

	if not e or not n then return nil end

	return e, n, h or 0
end

-- Цель ----------------------------------------------------------------------

function PANEL:BuildTarget( parent )
	local sec = Section( parent, "ЦЕЛЬ", UI.S( 128 ) )

	self.TgtN = Field( sec, "С, м", "север", 1, 3 )
	self.TgtE = Field( sec, "В, м", "восток", 2, 3 )
	self.TgtH = Field( sec, "H, м", "высота", 3, 3 )

	local hBtn = UI.Button( sec, "Высота по карте", "ghost", function()
		local e, n = self.TgtE:GetNumber(), self.TgtN:GetNumber()
		local h = e and n and A.GroundH( e, n )

		if h then self.TgtH:SetNumber( h ) else notification.AddLegacy( "Нет данных рельефа для этой точки", NOTIFY_ERROR, 3 ) end
	end )

	hBtn.Font = "SkyOpsArty_Label"

	sec.PerformLayout = function( s, w, h )
		LayoutFields( s, UI.S( 8 ) )
		hBtn:SetPos( UI.S( 10 ), UI.S( 88 ) )
		hBtn:SetSize( UI.S( 160 ), UI.S( 28 ) )
	end

	sec.Paint = function( s, w, h )
		UI.Box( 0, 0, w, h, C.panel )
		UI.Text( "ЦЕЛЬ", "SkyOpsArty_Label", UI.S( 10 ), UI.S( 6 ), C.muted )
		PaintFieldLabels( s )

		local t = A.Target
		local x = UI.S( 180 )

		if not t then
			UI.Text( "клик по карте или координаты с дрона", "SkyOpsArty_Label", x, UI.S( 102 ), C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER )

			return
		end

		local sq, snail = A.Square( t.e, t.n )

		UI.Text( string.format( "кв. %s по улитке %d", sq, snail ), "SkyOpsArty_Label", x, UI.S( 94 ), C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER )
		UI.Text( "источник: " .. ( t.src or "?" ) .. ( t.err and t.err > 0 and string.format( ", ±%.0f м", t.err ) or "" ), "SkyOpsArty_Label", x, UI.S( 112 ), C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER )
	end
end

function PANEL:FillTarget( t )
	if not t then
		self.TgtN:SetText( "" ) self.TgtE:SetText( "" ) self.TgtH:SetText( "" )

		return
	end

	self.TgtN:SetNumber( t.n )
	self.TgtE:SetNumber( t.e )
	self.TgtH:SetNumber( t.h )
end

-- поля цели изменили руками: цель берём из полей
function PANEL:SyncTargetFromInput()
	local e, n, h = self.TgtE:GetNumber(), self.TgtN:GetNumber(), self.TgtH:GetNumber()

	if not e or not n then return false end

	local t = A.Target

	if t and math.abs( t.e - e ) < 1 and math.abs( t.n - n ) < 1 and math.abs( ( t.h or 0 ) - ( h or 0 ) ) < 1 then return true end

	A.Target = { pos = A.FromGrid( e, n, h ), e = e, n = n, h = h or 0, src = "ввод", time = CurTime() }
	A.Shift = { lat = 0, rng = 0 }

	return true
end

-- Боеприпас -----------------------------------------------------------------

function PANEL:BuildAmmo( parent )
	local st = UI.State
	local sec = Section( parent, "БОЕПРИПАС", UI.S( 150 ) )

	self.Shell = UI.Segmented( sec, A.SHELLS, st.shell, function( id )
		st.shell = id
		self:RebuildCharges()
		self:Solve( true )
	end )

	self.ChargeBox = vgui.Create( "DComboBox", sec )
	self.ChargeBox:SetFont( "SkyOpsArty_Text" )
	self.ChargeBox:SetTextColor( C.text )
	self.ChargeBox.Paint = function( s, w, h )
		UI.Box( 0, 0, w, h, C.bg )
		UI.Outline( 0, 0, w, h, s:IsMenuOpen() and C.accent or C.line )
	end
	self.ChargeBox.OnSelect = function( _, _, _, id )
		st.charge = id
		self:Solve( true )
	end

	self.Group = UI.Segmented( sec, { { id = false, name = "Нижняя группа" }, { id = true, name = "Верхняя (мортирная)" } }, st.high, function( id )
		st.high = id
		self:Solve( true )
	end )

	sec.PerformLayout = function( s, w, h )
		local pad = UI.S( 10 )

		self.Shell:SetPos( pad, UI.S( 26 ) )
		self.Shell:SetSize( w - pad * 2, UI.S( 30 ) )
		self.ChargeBox:SetPos( pad + UI.S( 70 ), UI.S( 66 ) )
		self.ChargeBox:SetSize( w - pad * 2 - UI.S( 70 ), UI.S( 30 ) )
		self.Group:SetPos( pad, UI.S( 106 ) )
		self.Group:SetSize( w - pad * 2, UI.S( 30 ) )
	end

	sec.Paint = function( s, w, h )
		UI.Box( 0, 0, w, h, C.panel )
		UI.Text( "БОЕПРИПАС", "SkyOpsArty_Label", UI.S( 10 ), UI.S( 6 ), C.muted )
		UI.Text( "Заряд", "SkyOpsArty_Text", UI.S( 10 ), UI.S( 81 ), C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER )
	end

	self:RebuildCharges()
end

function PANEL:RebuildCharges()
	local st = UI.State
	local box = self.ChargeBox
	local found = false

	box:Clear()

	for _, c in ipairs( A.Charges( st.shell ) ) do
		local _, maxR = A.ChargeRange( st.shell, c.id )
		local label = maxR and string.format( "%s  (до %.1f км)", c.name, maxR / 1000 ) or c.name

		box:AddChoice( label, c.id, c.id == st.charge )

		if c.id == st.charge then found = true end
	end

	if not found then
		local first = A.Charges( st.shell )[ 1 ]

		st.charge = first and first.id or 1
		box:ChooseOptionID( 1 )
	end
end

-- Расчёт --------------------------------------------------------------------

function PANEL:BuildResult( parent )
	local sec = Section( parent, "УСТАНОВКИ", UI.S( 236 ) )

	self.SolveBtn = UI.Button( sec, "РАСЧЁТ", "primary", function() self:Solve() end )

	self.FireBtn = UI.Button( sec, "НАВЕСТИ И ОГОНЬ", "danger", function() self:AutoFire() end )

	sec.PerformLayout = function( s, w, h )
		local pad = UI.S( 10 )
		local auto = A.IsAuto()
		local bw = auto and ( w - pad * 3 ) / 2 or w - pad * 2

		self.SolveBtn:SetPos( pad, h - UI.S( 48 ) )
		self.SolveBtn:SetSize( bw, UI.S( 40 ) )
		self.FireBtn:SetVisible( auto )
		self.FireBtn:SetPos( pad * 2 + bw, h - UI.S( 48 ) )
		self.FireBtn:SetSize( bw, UI.S( 40 ) )
	end

	sec.Think = function( s )
		if s.LastAuto ~= A.IsAuto() then
			s.LastAuto = A.IsAuto()
			s:InvalidateLayout()
		end
	end

	sec.Paint = function( s, w, h ) self:PaintResult( w, h ) end
end

function PANEL:PaintResult( w, h )
	UI.Box( 0, 0, w, h, C.panel )
	UI.Text( "УСТАНОВКИ", "SkyOpsArty_Label", UI.S( 10 ), UI.S( 6 ), C.muted )

	local sol = UI.State.solution
	local pad = UI.S( 10 )

	if not sol then
		UI.Text( "введи ОП и цель, нажми РАСЧЁТ", "SkyOpsArty_Text", pad, UI.S( 40 ), C.muted )

		return
	end

	if not sol.ok then
		local lines = UI.Wrap( sol.err or "Нет решения", "SkyOpsArty_Text", w - pad * 2 )

		for i, l in ipairs( lines ) do
			UI.Text( l, "SkyOpsArty_Text", pad, UI.S( 30 ) + ( i - 1 ) * UI.S( 22 ), C.threat )
		end

		return
	end

	local half = ( w - pad * 3 ) / 2
	local y = UI.S( 26 )

	UI.Text( "УГЛОМЕР", "SkyOpsArty_Label", pad, y, C.muted )
	UI.Text( "ПРИЦЕЛ", "SkyOpsArty_Label", pad * 2 + half, y, C.muted )
	UI.Text( A.FmtMils( sol.deflection ), "SkyOpsArty_Value", pad, y + UI.S( 16 ), C.accent )
	UI.Text( A.FmtMils( sol.elevation ), "SkyOpsArty_Value", pad * 2 + half, y + UI.S( 16 ), C.accent )

	y = y + UI.S( 58 )

	local rows = {
		{ "Дальность", string.format( "%.0f м", sol.range or 0 ) },
		{ "Дир. угол", A.FmtMils( sol.bearing ) },
		{ "Время полёта", sol.tof and string.format( "%.1f с", sol.tof ) or "—" },
		{ "Вершина", sol.apex and string.format( "%.0f м", sol.apex ) or "—" },
	}

	for i, r in ipairs( rows ) do
		local cx = ( i % 2 == 1 ) and pad or pad * 2 + half
		local cy = y + math.floor( ( i - 1 ) / 2 ) * UI.S( 22 )

		UI.Text( r[ 1 ], "SkyOpsArty_Label", cx, cy + UI.S( 2 ), C.muted )
		UI.Text( r[ 2 ], "SkyOpsArty_Text", cx + half, cy, C.text, TEXT_ALIGN_RIGHT )
	end

	if sol.approx then
		UI.Text( "черновой расчёт: модуля баллистики ещё нет", "SkyOpsArty_Label", pad, y + UI.S( 48 ), C.muted )
	end
end

-- quiet: пересчёт по событию, без звука и без ошибок про пустые поля
function PANEL:Solve( quiet )
	local ge, gn, gh = self:GunInput()

	if not ge then
		if not quiet then notification.AddLegacy( "Нет координат огневой позиции", NOTIFY_ERROR, 3 ) end

		return
	end

	if not self:SyncTargetFromInput() then
		if not quiet then notification.AddLegacy( "Нет координат цели", NOTIFY_ERROR, 3 ) end

		return
	end

	local spg = A.MySPG()
	local base = IsValid( spg ) and ( A.BaseDir( spg ) ) or 0
	local ae, an, ah = A.AimPoint( ge, gn )
	local st = UI.State

	st.solution = A.Solve( {
		gun = { x = ge, y = gn, h = gh },
		target = { x = ae, y = an, h = ah or 0 },
		shell = st.shell,
		charge = st.charge,
		high = st.high,
		basedir = base,
	} )
	st.solutionTime = CurTime()

	if not quiet then surface.PlaySound( st.solution.ok and "buttons/button24.wav" or "buttons/button10.wav" ) end

	hook.Run( "SkyOpsArty.Solution", st.solution )
end

function PANEL:AutoFire()
	local spg = A.MySPG()

	if not IsValid( spg ) then
		notification.AddLegacy( "САУ рядом нет", NOTIFY_ERROR, 3 )

		return
	end

	self:Solve( true )

	local ge, gn = self:GunInput()

	if not ge or not A.Target then
		notification.AddLegacy( "Нет цели", NOTIFY_ERROR, 3 )

		return
	end

	local ae, an, ah = A.AimPoint( ge, gn )
	local st = UI.State

	if A.AutoFire( spg, A.FromGrid( ae, an, ah ), st.shell, st.charge ) then
		surface.PlaySound( "buttons/button17.wav" )
	else
		notification.AddLegacy( "Сервер пока не принимает автонаведение (нет модуля баллистики)", NOTIFY_ERROR, 4 )
	end
end

-- Корректура ----------------------------------------------------------------

function PANEL:BuildCorrection( parent )
	local sec = Section( parent, "КОРРЕКТУРА ПО РАЗРЫВУ", UI.S( 168 ) )

	self.DevLat = Field( sec, "Разрыв правее +/левее −", "м", 1, 2 )
	self.DevRng = Field( sec, "Разрыв дальше +/ближе −", "м", 2, 2 )
	self.DevLat:SetNumeric( false )
	self.DevRng:SetNumeric( false )

	local apply = UI.Button( sec, "Ввести поправку", "ghost", function() self:ApplyCorrection() end )
	local reset = UI.Button( sec, "Сбросить", "ghost", function()
		A.Shift = { lat = 0, rng = 0 }
		self:Solve( true )
	end )

	-- разрыв, отмеченный на карте, подставляется автоматически только в режиме «авто»
	local fromImpact = UI.Button( sec, "От разрыва", "ghost", function() self:UpdateLastImpact( true ) end )

	apply.Font, reset.Font, fromImpact.Font = "SkyOpsArty_Label", "SkyOpsArty_Label", "SkyOpsArty_Label"

	sec.PerformLayout = function( s, w, h )
		LayoutFields( s, UI.S( 12 ) )

		local pad, gap = UI.S( 10 ), UI.S( 8 )
		local bw = ( w - pad * 2 - gap * 2 ) / 3

		apply:SetPos( pad, UI.S( 94 ) )
		apply:SetSize( bw, UI.S( 28 ) )
		reset:SetPos( pad + bw + gap, UI.S( 94 ) )
		reset:SetSize( bw, UI.S( 28 ) )
		fromImpact:SetPos( pad + ( bw + gap ) * 2, UI.S( 94 ) )
		fromImpact:SetSize( bw, UI.S( 28 ) )
		fromImpact:SetEnabled( A.IsAuto() )
	end

	sec.Think = function( s )
		if fromImpact:IsEnabled() ~= A.IsAuto() then fromImpact:SetEnabled( A.IsAuto() ) end
	end

	sec.Paint = function( s, w, h )
		UI.Box( 0, 0, w, h, C.panel )
		UI.Text( "КОРРЕКТУРА ПО РАЗРЫВУ", "SkyOpsArty_Label", UI.S( 10 ), UI.S( 6 ), C.muted )
		PaintFieldLabels( s )

		local sh = A.Shift
		local txt = ( sh.lat == 0 and sh.rng == 0 ) and "поправок нет" or ( "поправка: " .. A.FmtDeviation( sh.lat, sh.rng ) )

		UI.Text( txt, "SkyOpsArty_Label", UI.S( 10 ), UI.S( 140 ), C.text )
	end
end

function PANEL:ApplyCorrection()
	local lat = tonumber( self.DevLat:GetText() ) or 0
	local rng = tonumber( self.DevRng:GetText() ) or 0

	if lat == 0 and rng == 0 then return end

	-- разрыв правее на 40 -> точку прицеливания левее на 40
	A.Shift.lat = A.Shift.lat - lat
	A.Shift.rng = A.Shift.rng - rng

	self.DevLat:SetText( "" )
	self.DevRng:SetText( "" )
	self:Solve()
end

-- отклонение последнего разрыва от цели; подставляем только в режиме «авто»
function PANEL:UpdateLastImpact( force )
	if not ( force or A.IsAuto() ) then return end

	local imp = A.Impacts[ 1 ]
	local ge, gn = self:GunInput()

	if not imp or not ge or not A.Target then return end

	local ie, inn = A.ToGrid( imp.pos )
	local lat, rng = A.Deviation( ge, gn, A.Target.e, A.Target.n, ie, inn )

	-- отклонение считаем от точки прицеливания, иначе поправка удвоится
	local ae, an = A.AimPoint( ge, gn )
	local aLat, aRng = A.Deviation( ge, gn, A.Target.e, A.Target.n, ae, an )

	self.DevLat:SetText( tostring( math.Round( lat - aLat ) ) )
	self.DevRng:SetText( tostring( math.Round( rng - aRng ) ) )
end

function PANEL:OnRemove()
	hook.Remove( "SkyOpsArty.TargetChanged", self )
	hook.Remove( "SkyOpsArty.Impact", self )
end

vgui.Register( "SkyOpsArtyComputer", PANEL, "DPanel" )
