-- SkyOps: общий стиль интерфейса (client)
-- Тёмный «штабной» стиль: графит, янтарный акцент, зелёная символика HUD, красные угрозы.
-- Файл называется cl_base, чтобы загрузчик подключал его раньше остальных cl_ в ui/.

SkyOps = SkyOps or {}
SkyOps.UI = SkyOps.UI or {}

local UI = SkyOps.UI

UI.C = {
	bg = Color( 13, 17, 20 ),
	panel = Color( 21, 27, 32 ),
	panelAlpha = Color( 13, 17, 20, 200 ),
	line = Color( 42, 52, 59 ),
	text = Color( 216, 222, 226 ),
	muted = Color( 154, 167, 175 ),
	accent = Color( 242, 169, 59 ),
	ok = Color( 125, 222, 146 ),
	threat = Color( 255, 107, 94 ),
	map = Color( 17, 23, 27 ),
	grid = Color( 31, 40, 46 ),
	road = Color( 36, 64, 74 ),
}

local cvScale = CreateClientConVar( "skyops_ui_scale", "1", true, false, "Масштаб интерфейса и шрифтов SkyOps (0.8..2)" )

-- Масштаб под высоту экрана (макеты рисовались под 1080p). На маленьких экранах не мельчим
-- ниже 0.9, иначе текст становится нечитаемым.
function UI.Scale()
	return math.max( ScrH() / 1080, 0.9 ) * math.Clamp( cvScale:GetFloat(), 0.8, 2 )
end

function UI.S( x )
	return math.max( math.Round( x * UI.Scale() ), 1 )
end

local function CreateFonts()
	local heading = "Bahnschrift"
	local mono = "Consolas"

	surface.CreateFont( "SkyOps_Title", { font = heading, size = UI.S( 38 ), weight = 700, extended = true } )
	surface.CreateFont( "SkyOps_H1", { font = heading, size = UI.S( 30 ), weight = 600, extended = true } )
	surface.CreateFont( "SkyOps_H2", { font = heading, size = UI.S( 25 ), weight = 600, extended = true } )
	surface.CreateFont( "SkyOps_Kicker", { font = heading, size = UI.S( 17 ), weight = 700, extended = true } )
	surface.CreateFont( "SkyOps_Button", { font = heading, size = UI.S( 22 ), weight = 700, extended = true } )
	surface.CreateFont( "SkyOps_Label", { font = mono, size = UI.S( 16 ), weight = 600, extended = true } )
	surface.CreateFont( "SkyOps_Text", { font = mono, size = UI.S( 20 ), weight = 600, extended = true } )
	surface.CreateFont( "SkyOps_TextSmall", { font = mono, size = UI.S( 18 ), weight = 600, extended = true } )

	-- Символика HUD: жирный моноширинный, без сглаживания краёв в тени
	surface.CreateFont( "SkyOps_HUD", { font = mono, size = UI.S( 23 ), weight = 700, extended = true } )
	surface.CreateFont( "SkyOps_HUDLarge", { font = mono, size = UI.S( 29 ), weight = 700, extended = true } )
	surface.CreateFont( "SkyOps_HUDSmall", { font = mono, size = UI.S( 19 ), weight = 700, extended = true } )
	surface.CreateFont( "SkyOps_Warn", { font = heading, size = UI.S( 28 ), weight = 700, extended = true } )
end

CreateFonts()

hook.Add( "OnScreenSizeChanged", "SkyOps.UI.Fonts", CreateFonts )

cvars.AddChangeCallback( "skyops_ui_scale", function()
	CreateFonts()

	-- открытый брифинг пересоздаём под новый размер
	if IsValid( UI.BriefingPanel ) then
		UI.BriefingPanel:Remove()
		UI.OpenBriefing()
	end
end, "SkyOps.UI.Fonts" )

-- Рисование
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

function UI.TextSize( text, font )
	surface.SetFont( font )

	return surface.GetTextSize( text )
end

-- Линия заданной толщины
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
	surface.DrawTexturedRectRotated( (x1 + x2) * 0.5, (y1 + y2) * 0.5, len, t, -math.deg( math.atan2( dy, dx ) ) )
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
	seg = seg or math.Clamp( math.floor( r / 3 ), 16, 72 )

	local step = math.pi * 2 / seg

	for i = 0, seg - 1 do
		if not dashed or i % 2 == 0 then
			local a1, a2 = i * step, (i + 1) * step

			UI.Line( x + math.cos( a1 ) * r, y + math.sin( a1 ) * r, x + math.cos( a2 ) * r, y + math.sin( a2 ) * r, t, col )
		end
	end
end

function UI.FilledCircle( x, y, r, col, seg )
	seg = seg or 48

	local poly = {}

	for i = 0, seg - 1 do
		local a = i / seg * math.pi * 2

		poly[ #poly + 1 ] = { x = x + math.cos( a ) * r, y = y + math.sin( a ) * r }
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
			local test = line == "" and word or (line .. " " .. word)

			if surface.GetTextSize( test ) > width and line ~= "" then
				table.insert( lines, line )
				line = word
			else
				line = test
			end
		end

		table.insert( lines, line )
	end

	return lines
end

function UI.FormatTime( seconds )
	seconds = math.max( math.floor( seconds or 0 ), 0 )

	return string.format( "%d:%02d", math.floor( seconds / 60 ), seconds % 60 )
end

-- Кнопка в стиле SkyOps. style: "primary" (янтарная) или "ghost" (контур)
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

		if self.Style == "primary" then
			UI.Box( 0, 0, w, h, hover and Color( 255, 196, 107 ) or UI.C.accent )
			UI.Text( self.Label, "SkyOps_Button", w / 2, h / 2, UI.C.bg, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER )
		else
			UI.Box( 0, 0, w, h, hover and UI.C.line or Color( 0, 0, 0, 0 ) )
			UI.Outline( 0, 0, w, h, Color( 59, 73, 80 ) )
			UI.Text( self.Label, self.Font or "SkyOps_TextSmall", w / 2, h / 2, self:IsEnabled() and UI.C.text or UI.C.muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER )
		end

		return true
	end

	return btn
end

-- Секция с заголовком-меткой (ОБСТАНОВКА, ЗАДАЧИ ...)
function UI.Kicker( text, x, y )
	local _, h = UI.Text( text, "SkyOps_Label", x, y, UI.C.muted )

	return y + h + UI.S( 8 )
end
