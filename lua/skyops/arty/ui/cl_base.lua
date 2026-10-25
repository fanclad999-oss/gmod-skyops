-- Артиллерия, интерфейс: общий стиль (тот же «штабной», что у SkyOps: графит, янтарный
-- акцент, зелёная символика приборов, красные цели). Своя копия, чтобы модуль не зависел
-- от самолётного UI.

local UI = SkyOps.Arty.UI

UI.C = {
	bg = Color( 13, 17, 20 ),
	panel = Color( 21, 27, 32 ),
	panelAlpha = Color( 13, 17, 20, 210 ),
	line = Color( 42, 52, 59 ),
	text = Color( 216, 222, 226 ),
	muted = Color( 154, 167, 175 ),
	accent = Color( 242, 169, 59 ),
	ok = Color( 125, 222, 146 ),
	threat = Color( 255, 107, 94 ),
	laser = Color( 255, 60, 60 ),
	friend = Color( 110, 180, 255 ),
	map = Color( 17, 23, 27 ),
	grid = Color( 34, 44, 50 ),
	gridMajor = Color( 58, 72, 80 ),
	hud = Color( 125, 222, 146 ),
	shadow = Color( 0, 0, 0, 170 ),
}

local cvScale = CreateClientConVar( "skyops_arty_ui_scale", "1", true, false, "Масштаб интерфейса артиллерии (0.8..2)" )

function UI.Scale()
	return math.max( ScrH() / 1080, 0.9 ) * math.Clamp( cvScale:GetFloat(), 0.8, 2 )
end

function UI.S( x )
	return math.max( math.Round( x * UI.Scale() ), 1 )
end

local function CreateFonts()
	local heading = "Bahnschrift"
	local mono = "Consolas"

	surface.CreateFont( "SkyOpsArty_H1", { font = heading, size = UI.S( 28 ), weight = 600, extended = true } )
	surface.CreateFont( "SkyOpsArty_H2", { font = heading, size = UI.S( 22 ), weight = 600, extended = true } )
	surface.CreateFont( "SkyOpsArty_Button", { font = heading, size = UI.S( 21 ), weight = 700, extended = true } )
	surface.CreateFont( "SkyOpsArty_Label", { font = mono, size = UI.S( 15 ), weight = 600, extended = true } )
	surface.CreateFont( "SkyOpsArty_Text", { font = mono, size = UI.S( 19 ), weight = 600, extended = true } )
	surface.CreateFont( "SkyOpsArty_Value", { font = mono, size = UI.S( 30 ), weight = 700, extended = true } )
	surface.CreateFont( "SkyOpsArty_HUD", { font = mono, size = UI.S( 22 ), weight = 700, extended = true } )
	surface.CreateFont( "SkyOpsArty_HUDLarge", { font = mono, size = UI.S( 30 ), weight = 700, extended = true } )
	surface.CreateFont( "SkyOpsArty_HUDSmall", { font = mono, size = UI.S( 17 ), weight = 700, extended = true } )
end

CreateFonts()

hook.Add( "OnScreenSizeChanged", "SkyOpsArty.UI.Fonts", CreateFonts )
cvars.AddChangeCallback( "skyops_arty_ui_scale", function()
	CreateFonts()
	hook.Run( "SkyOpsArty.UI.Rescaled" )
end, "SkyOpsArty.UI.Fonts" )

-- Рисование -----------------------------------------------------------------

function UI.Box( x, y, w, h, col )
	surface.SetDrawColor( col )
	surface.DrawRect( x, y, w, h )
end

function UI.Outline( x, y, w, h, col, t )
	surface.SetDrawColor( col )
	surface.DrawOutlinedRect( x, y, w, h, t or 1 )
end

function UI.Text( text, font, x, y, col, ax, ay )
	return draw.SimpleText( text, font, x, y, col, ax or TEXT_ALIGN_LEFT, ay or TEXT_ALIGN_TOP )
end

-- текст HUD с тенью, читается на любом фоне
function UI.HText( text, font, x, y, col, ax, ay )
	draw.SimpleText( text, font, x + 1, y + 1, UI.C.shadow, ax or TEXT_ALIGN_LEFT, ay or TEXT_ALIGN_TOP )

	return draw.SimpleText( text, font, x, y, col, ax or TEXT_ALIGN_LEFT, ay or TEXT_ALIGN_TOP )
end

function UI.TextSize( text, font )
	surface.SetFont( font )

	return surface.GetTextSize( text )
end

function UI.Line( x1, y1, x2, y2, t, col )
	if col then surface.SetDrawColor( col ) end

	t = t or 1

	if t <= 1 then
		surface.DrawLine( x1, y1, x2, y2 )

		return
	end

	local dx, dy = x2 - x1, y2 - y1
	local len = math.sqrt( dx * dx + dy * dy )

	if len < 0.5 then return end

	draw.NoTexture()
	surface.DrawTexturedRectRotated( ( x1 + x2 ) * 0.5, ( y1 + y2 ) * 0.5, len, t, -math.deg( math.atan2( dy, dx ) ) )
end

function UI.DashedLine( x1, y1, x2, y2, t, dash, gap, col )
	local dx, dy = x2 - x1, y2 - y1
	local len = math.sqrt( dx * dx + dy * dy )

	if len < 1 then return end

	local ux, uy = dx / len, dy / len
	local d = 0

	while d < len do
		local e = math.min( d + dash, len )

		UI.Line( x1 + ux * d, y1 + uy * d, x1 + ux * e, y1 + uy * e, t, col )

		d = e + gap
	end
end

function UI.Circle( x, y, r, t, col, seg, dashed )
	seg = seg or math.Clamp( math.floor( r / 3 ), 16, 96 )

	local step = math.pi * 2 / seg

	for i = 0, seg - 1 do
		if not dashed or i % 2 == 0 then
			local a1, a2 = i * step, ( i + 1 ) * step

			UI.Line( x + math.cos( a1 ) * r, y + math.sin( a1 ) * r, x + math.cos( a2 ) * r, y + math.sin( a2 ) * r, t, col )
		end
	end
end

function UI.FilledCircle( x, y, r, col, seg )
	seg = seg or 32

	local poly = {}

	for i = 0, seg - 1 do
		local a = i / seg * math.pi * 2

		poly[ #poly + 1 ] = { x = x + math.cos( a ) * r, y = y + math.sin( a ) * r }
	end

	draw.NoTexture()
	surface.SetDrawColor( col )
	surface.DrawPoly( poly )
end

-- треугольник-указатель остриём в (x, y); dir: "up" | "down" | "left" | "right"
function UI.Pointer( x, y, size, dir, col )
	local s = size
	local poly

	if dir == "down" then
		poly = { { x = x - s, y = y - s * 1.4 }, { x = x + s, y = y - s * 1.4 }, { x = x, y = y } }
	elseif dir == "up" then
		poly = { { x = x, y = y }, { x = x + s, y = y + s * 1.4 }, { x = x - s, y = y + s * 1.4 } }
	elseif dir == "left" then
		poly = { { x = x, y = y }, { x = x + s * 1.4, y = y - s }, { x = x + s * 1.4, y = y + s } }
	else
		poly = { { x = x - s * 1.4, y = y - s }, { x = x, y = y }, { x = x - s * 1.4, y = y + s } }
	end

	draw.NoTexture()
	surface.SetDrawColor( col )
	surface.DrawPoly( poly )
end

-- Перенос текста по ширине, возвращает список строк
function UI.Wrap( text, font, width )
	surface.SetFont( font )

	local lines = {}

	for paragraph in string.gmatch( text .. "\n", "(.-)\n" ) do
		local line = ""

		for word in string.gmatch( paragraph, "%S+" ) do
			local test = line == "" and word or ( line .. " " .. word )

			if surface.GetTextSize( test ) > width and line ~= "" then
				lines[ #lines + 1 ] = line
				line = word
			else
				line = test
			end
		end

		lines[ #lines + 1 ] = line
	end

	return lines
end

-- Элементы окна -------------------------------------------------------------

-- Кнопка. style: "primary" (янтарная), "danger" (красная) или "ghost" (контур)
function UI.Button( parent, text, style, onClick )
	local btn = vgui.Create( "DButton", parent )

	btn:SetText( "" )
	btn.Label = text
	btn.Style = style or "ghost"
	btn.DoClick = function( self )
		surface.PlaySound( "buttons/lightswitch2.wav" )

		if onClick then onClick( self ) end
	end
	btn.Paint = function( self, w, h )
		local hover = self:IsHovered() and self:IsEnabled()
		local enabled = self:IsEnabled()

		if self.Style == "primary" or self.Style == "danger" then
			local base = self.Style == "danger" and UI.C.threat or UI.C.accent
			local col = not enabled and UI.C.line or ( hover and Color( math.min( base.r + 20, 255 ), math.min( base.g + 30, 255 ), math.min( base.b + 40, 255 ) ) or base )

			UI.Box( 0, 0, w, h, col )
			UI.Text( self.Label, "SkyOpsArty_Button", w / 2, h / 2, enabled and UI.C.bg or UI.C.muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER )
		else
			UI.Box( 0, 0, w, h, ( hover or self.Active ) and UI.C.line or Color( 0, 0, 0, 0 ) )
			UI.Outline( 0, 0, w, h, self.Active and UI.C.accent or Color( 59, 73, 80 ) )
			UI.Text( self.Label, self.Font or "SkyOpsArty_Text", w / 2, h / 2, enabled and UI.C.text or UI.C.muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER )
		end

		return true
	end

	return btn
end

-- Поле ввода числа в тёмном стиле
function UI.NumEntry( parent, placeholder )
	local e = vgui.Create( "DTextEntry", parent )

	e:SetFont( "SkyOpsArty_Text" )
	e:SetNumeric( true )
	e:SetPlaceholderText( placeholder or "" )
	e:SetPaintBackground( false )
	e.Paint = function( self, w, h )
		UI.Box( 0, 0, w, h, UI.C.bg )
		UI.Outline( 0, 0, w, h, self:HasFocus() and UI.C.accent or UI.C.line )

		if self:GetText() == "" and self:GetPlaceholderText() ~= "" and not self:HasFocus() then
			UI.Text( self:GetPlaceholderText(), "SkyOpsArty_Text", UI.S( 6 ), h / 2, UI.C.line, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER )
		end

		self:DrawTextEntryText( UI.C.text, UI.C.accent, UI.C.text )
	end

	function e:GetNumber()
		return tonumber( self:GetText() )
	end

	function e:SetNumber( v, decimals )
		if v == nil then self:SetText( "" ) return end

		self:SetText( decimals and string.format( "%." .. decimals .. "f", v ) or tostring( math.Round( v ) ) )
	end

	return e
end

-- Набор переключателей «один из», как сегментированная кнопка
function UI.Segmented( parent, options, selected, onSelect )
	local pnl = vgui.Create( "DPanel", parent )

	pnl:SetPaintBackground( false )
	pnl.Buttons = {}
	pnl.Value = selected

	for i, opt in ipairs( options ) do
		local b = UI.Button( pnl, opt.name, "ghost", function()
			pnl:SetValue( opt.id )

			if onSelect then onSelect( opt.id ) end
		end )

		b.Id = opt.id
		b.Font = "SkyOpsArty_Label"
		b.Active = opt.id == selected
		pnl.Buttons[ i ] = b
	end

	function pnl:SetValue( id )
		self.Value = id

		for _, b in ipairs( self.Buttons ) do b.Active = b.Id == id end
	end

	pnl.PerformLayout = function( self, w, h )
		local n = #self.Buttons
		local gap = UI.S( 4 )
		local bw = ( w - gap * ( n - 1 ) ) / n

		for i, b in ipairs( self.Buttons ) do
			b:SetPos( math.Round( ( i - 1 ) * ( bw + gap ) ), 0 )
			b:SetSize( math.Round( bw ), h )
		end
	end

	return pnl
end

-- Метка-заголовок секции
function UI.Kicker( text, x, y )
	local _, h = UI.Text( text, "SkyOpsArty_Label", x, y, UI.C.muted )

	return y + h + UI.S( 6 )
end
