-- Артиллерия, интерфейс: планшет командира. Слева карта с сеткой, справа огневой
-- вычислитель. Открывается клавишей (skyops_arty_key_tablet, по умолчанию N) или
-- командой skyops_arty_tablet.

local UI = SkyOps.Arty.UI
local A = UI.API
local C = UI.C

local keyTablet

function UI.TabletKeyName()
	return keyTablet and A.KeyName( keyTablet ) or "N"
end

function UI.CloseTablet()
	if IsValid( UI.TabletFrame ) then UI.TabletFrame:Remove() end
end

function UI.OpenTablet()
	if IsValid( UI.TabletFrame ) then return end

	local sw, sh = ScrW(), ScrH()
	local frame = vgui.Create( "DFrame" )

	frame:SetSize( math.min( sw - UI.S( 60 ), UI.S( 1600 ) ), math.min( sh - UI.S( 60 ), UI.S( 940 ) ) )
	frame:Center()
	frame:SetTitle( "" )
	frame:ShowCloseButton( false )
	frame:SetDraggable( false )
	frame:DockPadding( UI.S( 12 ), UI.S( 48 ), UI.S( 12 ), UI.S( 12 ) )
	frame:MakePopup()
	frame:SetKeyboardInputEnabled( true )

	frame.Paint = function( s, w, h )
		UI.Box( 0, 0, w, h, C.bg )
		UI.Outline( 0, 0, w, h, C.line )
		UI.Text( "ПЛАНШЕТ АРТИЛЛЕРИСТА", "SkyOpsArty_H2", UI.S( 14 ), UI.S( 24 ), C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER )

		local spg = A.MySPG()
		local status = IsValid( spg ) and ( A.IsDeployed( spg ) and "2С35 развёрнута" or "2С35 в походном положении" ) or "САУ не найдена"

		UI.Text( status, "SkyOpsArty_Label", UI.S( 330 ), UI.S( 24 ), IsValid( spg ) and C.muted or C.threat, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER )
	end

	-- клавиша планшета закрывает его, даже когда фокус на окне
	frame.OnKeyCodePressed = function( s, key )
		if key == keyTablet:GetInt() or key == KEY_ESCAPE then UI.ToggleTablet() end
	end

	local close = UI.Button( frame, "✕", "ghost", UI.CloseTablet )

	close:SetSize( UI.S( 36 ), UI.S( 30 ) )
	close:SetPos( frame:GetWide() - UI.S( 48 ), UI.S( 9 ) )

	local side = vgui.Create( "SkyOpsArtyComputer", frame )

	side:Dock( RIGHT )
	side:DockMargin( UI.S( 12 ), 0, 0, 0 )
	side:SetWide( UI.S( 440 ) )

	local map = vgui.Create( "SkyOpsArtyMap", frame )

	map:Dock( FILL )

	-- карта и вычислитель запоминаются между открытиями
	if UI.SavedView then
		map.CE, map.CN, map.MPP = UI.SavedView.e, UI.SavedView.n, UI.SavedView.mpp
	end

	frame.OnRemove = function()
		UI.SavedView = { e = map.CE, n = map.CN, mpp = map.MPP }
	end

	UI.TabletFrame = frame
	UI.TabletMap = map
	UI.TabletComputer = side
end

-- окно ловит клавишу само, а опрос клавиш в Think может увидеть то же нажатие
local lastToggle = 0

function UI.ToggleTablet()
	if RealTime() - lastToggle < 0.25 then return end

	lastToggle = RealTime()

	if IsValid( UI.TabletFrame ) then UI.CloseTablet() else UI.OpenTablet() end
end

keyTablet = A.Bind( "skyops_arty_key_tablet", KEY_N, "Открыть / закрыть планшет артиллериста", UI.ToggleTablet )

concommand.Add( "skyops_arty_tablet", UI.ToggleTablet )

hook.Add( "SkyOpsArty.UI.Rescaled", "SkyOpsArty.UI.Tablet", function()
	if IsValid( UI.TabletFrame ) then
		UI.CloseTablet()
		UI.OpenTablet()
	end
end )

-- подсказка один раз, когда игрок впервые сел в САУ или в дрон
local hinted = false

hook.Add( "Think", "SkyOpsArty.UI.TabletHint", function()
	if hinted then return end

	local veh = A.Vehicle()

	if veh and ( veh:GetClass() == A.SPG_CLASS or A.IsUAV( veh ) or veh:GetClass() == A.UAV_STATION ) then
		hinted = true
		notification.AddLegacy( "Планшет артиллериста: клавиша " .. UI.TabletKeyName() .. " (skyops_arty_tablet)", NOTIFY_HINT, 6 )
	end
end )
