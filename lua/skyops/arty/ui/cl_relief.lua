-- Артиллерия, интерфейс: подложка карты планшета из рельефа (высотная окраска + отмывка).
-- Строится один раз по Grid.Height (на Кировском это сетка высот карты) в текстуру
-- 256x256 на весь Grid.Bounds(): сначала понемногу за кадр снимаются высоты, потом
-- по строкам рисуется текстура. Без модуля сетки или вне Кировского подложки нет.

local UI = SkyOps.Arty.UI
local A = UI.API

local R = UI.Relief or {}

UI.Relief = R

local SIZE = 256
local SAMPLES_PER_FRAME = 768
local ROWS_PER_FRAME = 16

local cvRelief = CreateClientConVar( "skyops_arty_ui_relief", "1", true, false, "Рельеф на карте планшета" )

-- высотные ступени: тёмная «штабная» гамма, низины зеленоватые, вершины охристые
local RAMP = {
	{ 0.00, Color( 26, 38, 34 ) },
	{ 0.25, Color( 34, 50, 40 ) },
	{ 0.50, Color( 50, 58, 42 ) },
	{ 0.75, Color( 66, 62, 44 ) },
	{ 1.00, Color( 84, 74, 54 ) },
}

local WATER = Color( 22, 36, 48 )

local function Ramp( t )
	t = math.Clamp( t, 0, 1 )

	for i = 2, #RAMP do
		local a, b = RAMP[ i - 1 ], RAMP[ i ]

		if t <= b[ 1 ] then
			local f = ( t - a[ 1 ] ) / ( b[ 1 ] - a[ 1 ] )

			return a[ 2 ].r + ( b[ 2 ].r - a[ 2 ].r ) * f, a[ 2 ].g + ( b[ 2 ].g - a[ 2 ].g ) * f, a[ 2 ].b + ( b[ 2 ].b - a[ 2 ].b ) * f
		end
	end

	local c = RAMP[ #RAMP ][ 2 ]

	return c.r, c.g, c.b
end

function R.Available()
	local G = SkyOps.Arty.Grid

	return cvRelief:GetBool() and G ~= nil and G.Bounds ~= nil and G.Height ~= nil and KIR ~= nil
end

-- запускает построение; вызывается при открытии планшета
function R.Request()
	if R.State or not R.Available() then return end

	local ok, minX, minY, maxX, maxY = pcall( SkyOps.Arty.Grid.Bounds )

	if not ok or not minX or maxX <= minX or maxY <= minY then
		R.State = "failed"

		return
	end

	-- квадрат по большей стороне, с полями в 1 км
	local size = math.max( maxX - minX, maxY - minY ) + 2000

	R.MinX, R.MinY = ( minX + maxX ) / 2 - size / 2, ( minY + maxY ) / 2 - size / 2
	R.Span = size
	R.Heights = {}
	R.Next = 0
	R.Row = 0
	R.Lo, R.Hi = math.huge, -math.huge
	R.State = "sampling"
	-- RGBA: за краем карты подложка прозрачная
	R.RT = GetRenderTargetEx( "skyops_arty_relief_" .. SIZE, SIZE, SIZE, RT_SIZE_LITERAL, MATERIAL_RT_DEPTH_NONE, 0, 0, IMAGE_FORMAT_RGBA8888 )
	R.Mat = CreateMaterial( "skyops_arty_relief_" .. SIZE, "UnlitGeneric", {
		[ "$basetexture" ] = R.RT:GetName(),
		[ "$vertexcolor" ] = 1,
		[ "$vertexalpha" ] = 1,
		[ "$translucent" ] = 1,
	} )
end

-- 0..1 готовности для полосы загрузки
function R.Progress()
	if R.State == "sampling" then return R.Next / ( SIZE * SIZE ) * 0.8 end
	if R.State == "drawing" then return 0.8 + R.Row / SIZE * 0.2 end
	if R.State == "ready" then return 1 end

	return 0
end

local function Sample()
	local G = SkyOps.Arty.Grid
	local step = R.Span / SIZE
	local stop = math.min( R.Next + SAMPLES_PER_FRAME, SIZE * SIZE )

	for i = R.Next, stop - 1 do
		local px, py = i % SIZE, math.floor( i / SIZE )
		-- строка 0 текстуры = север
		local ok, h = pcall( G.Height, R.MinX + ( px + 0.5 ) * step, R.MinY + R.Span - ( py + 0.5 ) * step )

		h = ok and h or nil
		R.Heights[ i ] = h or false

		if h then
			if h < R.Lo then R.Lo = h end
			if h > R.Hi then R.Hi = h end
		end
	end

	R.Next = stop

	if stop >= SIZE * SIZE then
		R.State = R.Lo < R.Hi and "drawing" or "failed"
		R.First = true
	end
end

local function H( px, py )
	px, py = math.Clamp( px, 0, SIZE - 1 ), math.Clamp( py, 0, SIZE - 1 )

	return R.Heights[ py * SIZE + px ] or nil
end

local function DrawRows()
	local step = R.Span / SIZE
	local span = math.max( R.Hi - R.Lo, 1 )
	-- рельеф подчёркнут в 3 раза, иначе на 256 точек на десятки км холмов не видно
	local zScale = 3 / step

	render.PushRenderTarget( R.RT )

	if R.First then
		render.Clear( 0, 0, 0, 0, true, true )
		R.First = false
	end

	cam.Start2D()

	local stop = math.min( R.Row + ROWS_PER_FRAME, SIZE )

	for py = R.Row, stop - 1 do
		for px = 0, SIZE - 1 do
			local h = H( px, py )

			if h then
				-- отмывка: свет с северо-запада
				local dx = ( ( H( px + 1, py ) or h ) - ( H( px - 1, py ) or h ) ) * zScale
				local dy = ( ( H( px, py + 1 ) or h ) - ( H( px, py - 1 ) or h ) ) * zScale
				local shade = math.Clamp( 1 + ( -dx - dy ) * 0.35, 0.55, 1.35 )
				local r, g, b

				if h <= R.Lo + 0.5 then
					r, g, b = WATER.r, WATER.g, WATER.b
					shade = 1
				else
					r, g, b = Ramp( ( h - R.Lo ) / span )
				end

				surface.SetDrawColor( math.min( r * shade, 255 ), math.min( g * shade, 255 ), math.min( b * shade, 255 ), 255 )
				surface.DrawRect( px, py, 1, 1 )
			end
		end
	end

	cam.End2D()
	render.PopRenderTarget()

	R.Row = stop

	if stop >= SIZE then
		R.State = "ready"
		R.Heights = nil -- больше не нужны
	end
end

hook.Add( "PostRender", "SkyOpsArty.UI.Relief", function()
	if R.State == "sampling" then
		Sample()
	elseif R.State == "drawing" then
		DrawRows()
	end
end )

-- рисует подложку в панели карты: toScreen( e, n ) -> x, y
function R.Paint( toScreen )
	if R.State ~= "ready" then return end

	local x0, y0 = toScreen( R.MinX, R.MinY + R.Span )
	local x1, y1 = toScreen( R.MinX + R.Span, R.MinY )

	surface.SetMaterial( R.Mat )
	surface.SetDrawColor( 255, 255, 255, 255 )
	surface.DrawTexturedRect( x0, y0, x1 - x0, y1 - y0 )
end

cvars.AddChangeCallback( "skyops_arty_ui_relief", function( _, _, new )
	if new == "0" then R.State = nil end
end, "SkyOpsArty.UI.Relief" )
