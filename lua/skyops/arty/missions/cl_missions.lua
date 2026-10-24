-- Artillery missions, client: mission menu (F7, !arty, skyops_arty_missions), the mission
-- HUD (objectives, navigation to the firing position, radio), mission marks on the
-- tablet map of arty/ui and the debrief with a burst plot.
-- Looks like arty/ui (same palette) but does not need it: colours and fonts are its own.

local M = SkyOps.Arty.Missions
local Grid = SkyOps.Arty.Grid

M.Client = M.Client or { state = { stage = 0 }, radio = {}, menu = nil }

local CL = M.Client

local C = {
	bg = Color( 13, 17, 20, 235 ),
	panel = Color( 21, 27, 32, 230 ),
	line = Color( 42, 52, 59 ),
	text = Color( 216, 222, 226 ),
	muted = Color( 154, 167, 175 ),
	accent = Color( 242, 169, 59 ),
	ok = Color( 125, 222, 146 ),
	threat = Color( 255, 107, 94 ),
	friend = Color( 110, 180, 255 ),
	shadow = Color( 0, 0, 0, 170 ),
	dim = Color( 0, 0, 0, 120 ),
}

local cvHud = CreateClientConVar( "skyops_arty_mission_hud", "1", true, false, "Показывать HUD задания артиллерии" )
local cvKey = CreateClientConVar( "skyops_arty_key_missions", tostring( KEY_F7 ), true, false, "Клавиша меню заданий артиллерии (номер KEY_*)" )

-- Fonts ------------------------------------------------------------------------------------

local function S( x )
	local ui = SkyOps.Arty.UI

	if ui and ui.S then return ui.S( x ) end

	return math.max( math.Round( x * math.max( ScrH() / 1080, 0.9 ) ), 1 )
end

local function Fonts()
	surface.CreateFont( "SkyOpsArtyM_Title", { font = "Bahnschrift", size = S( 30 ), weight = 600, extended = true } )
	surface.CreateFont( "SkyOpsArtyM_H2", { font = "Bahnschrift", size = S( 21 ), weight = 600, extended = true } )
	surface.CreateFont( "SkyOpsArtyM_Text", { font = "Consolas", size = S( 17 ), weight = 600, extended = true } )
	surface.CreateFont( "SkyOpsArtyM_Small", { font = "Consolas", size = S( 15 ), weight = 600, extended = true } )
	surface.CreateFont( "SkyOpsArtyM_Grade", { font = "Bahnschrift", size = S( 110 ), weight = 800, extended = true } )
	surface.CreateFont( "SkyOpsArtyM_Big", { font = "Consolas", size = S( 26 ), weight = 700, extended = true } )
end

Fonts()
hook.Add( "OnScreenSizeChanged", "SkyOps.Arty.Missions.Fonts", Fonts )
hook.Add( "SkyOpsArty.UI.Rescaled", "SkyOps.Arty.Missions.Fonts", Fonts )

local function Text( t, font, x, y, col, ax, ay )
	return draw.SimpleText( t, font, x, y, col, ax or TEXT_ALIGN_LEFT, ay or TEXT_ALIGN_TOP )
end

local function HText( t, font, x, y, col, ax, ay )
	draw.SimpleText( t, font, x + 1, y + 1, C.shadow, ax or TEXT_ALIGN_LEFT, ay or TEXT_ALIGN_TOP )

	return draw.SimpleText( t, font, x, y, col, ax or TEXT_ALIGN_LEFT, ay or TEXT_ALIGN_TOP )
end

local function Box( x, y, w, h, col )
	surface.SetDrawColor( col )
	surface.DrawRect( x, y, w, h )
end

local function Outline( x, y, w, h, col )
	surface.SetDrawColor( col )
	surface.DrawOutlinedRect( x, y, w, h, 1 )
end

local function Circle( x, y, r, col, seg, dashed )
	seg = seg or 48
	surface.SetDrawColor( col )

	for i = 0, seg - 1 do
		if not dashed or i % 2 == 0 then
			local a1, a2 = i / seg * 2 * math.pi, ( i + 1 ) / seg * 2 * math.pi

			surface.DrawLine( x + math.cos( a1 ) * r, y + math.sin( a1 ) * r, x + math.cos( a2 ) * r, y + math.sin( a2 ) * r )
		end
	end
end

-- word-wraps text to a pixel width
local function Wrap( text, font, width )
	surface.SetFont( font )

	local lines, cur = {}, ""

	for word in string.gmatch( text, "%S+" ) do
		local try = cur == "" and word or ( cur .. " " .. word )

		if surface.GetTextSize( try ) > width and cur ~= "" then
			lines[ #lines + 1 ] = cur
			cur = word
		else
			cur = try
		end
	end

	if cur ~= "" then lines[ #lines + 1 ] = cur end

	return lines
end

-- Net ----------------------------------------------------------------------------------------

function M.Req( cmd, args )
	net.Start( M.NET_REQ )
		net.WriteString( cmd )
		M.WriteTable( args or {} )
	net.SendToServer()
end

local function InMission()
	local st = CL.state

	if not st or not st.stage or st.stage == M.STAGE_NONE then return false end

	for _, p in ipairs( st.players or {} ) do
		if p.name == LocalPlayer():Nick() then return true end
	end

	return false
end

M.InMission = InMission

net.Receive( M.NET_STATE, function()
	local old = CL.state

	CL.state = M.ReadTable()

	if old and old.stage ~= CL.state.stage and InMission() and CL.state.stage ~= M.STAGE_NONE then
		surface.PlaySound( "buttons/button14.wav" )
	end

	hook.Run( "SkyOps.Arty.MissionState", CL.state )

	if IsValid( CL.menu ) then CL.menu:Refresh() end
end )

net.Receive( M.NET_MSG, function()
	local from, text = net.ReadString(), net.ReadString()

	table.insert( CL.radio, 1, { from = from, text = text, time = RealTime() } )

	while #CL.radio > 8 do table.remove( CL.radio ) end

	surface.PlaySound( "buttons/blip1.wav" )
	MsgC( C.accent, "[" .. from .. "] ", C.text, text .. "\n" )
end )

net.Receive( M.NET_DEBRIEF, function()
	CL.debrief = M.ReadTable()

	timer.Simple( 1.5, function() M.OpenDebrief() end )
end )

net.Receive( M.NET_MENU, function()
	CL.menuData = M.ReadTable()

	M.OpenMenu()
end )

hook.Add( "InitPostEntity", "SkyOps.Arty.Missions", function()
	timer.Simple( 3, function() M.Req( "sync" ) end )
end )

concommand.Add( "skyops_arty_missions", function() M.Req( "menu" ) end, nil, "Меню заданий артиллерии" )

-- key, polled like the arty/ui binds (PlayerButtonDown does not fire on a listen client)
local keyWasDown = false

hook.Add( "Think", "SkyOps.Arty.Missions.Key", function()
	local key = cvKey:GetInt()
	local down = key > 0 and input.IsKeyDown( key ) and not gui.IsGameUIVisible() and not vgui.GetKeyboardFocus() and not LocalPlayer():IsTyping()

	if down and not keyWasDown then
		if IsValid( CL.menu ) then CL.menu:Remove() else M.Req( "menu" ) end
	end

	keyWasDown = down
end )

-- Navigation -------------------------------------------------------------------------------------

-- the point the crew should look at now: grid x, y and a label
local function Waypoint( st )
	if st.stage == M.STAGE_MARCH or st.stage == M.STAGE_DEPLOY then
		return st.fp.x, st.fp.y, "ОП", C.friend
	elseif st.stage == M.STAGE_RECON and st.area then
		return st.area.x, st.area.y, "район поиска", C.accent
	elseif st.stage == M.STAGE_FIRE and st.intel then
		return st.intel.x, st.intel.y, "цель", C.threat
	end
end

-- InfMap: on the client Entity:GetPos() is relative to the LocalPlayer chunk, while the
-- server and Grid work with absolute positions (same shift as A.EntPos in arty/ui/cl_api)
local function AbsPos( ent )
	local ply = LocalPlayer()

	if InfMap and InfMap.unlocalize_vector and ply.CHUNK_OFFSET then
		return ent:GetPos() + InfMap.unlocalize_vector( Vector(), ply.CHUNK_OFFSET )
	end

	return ent:GetPos()
end

local function MyGrid()
	local ply = LocalPlayer()
	local veh = ply.lvsGetVehicle and ply:lvsGetVehicle()
	local ent = IsValid( veh ) and veh or ply

	return Grid.ToGrid( AbsPos( ent ) )
end

-- Mission HUD ---------------------------------------------------------------------------------------

local OBJ_MARK = { [ 0 ] = "[ ]", [ 1 ] = "[x]", [ 2 ] = "[-]" }
local OBJ_COL = { [ 0 ] = C.text, [ 1 ] = C.ok, [ 2 ] = C.threat }

local function PaintObjectives( st, x, y, w )
	local pad = S( 12 )
	local lh = S( 20 )
	local lines = {}

	lines[ #lines + 1 ] = { st.name or "Задание", "SkyOpsArtyM_H2", C.accent }
	lines[ #lines + 1 ] = { string.format( "%s · %s · %s", M.StageNames[ st.stage ] or "", st.range or "", st.mode == "auto" and "авто" or "хардкор" ), "SkyOpsArtyM_Small", C.muted }

	for _, o in ipairs( st.objectives or {} ) do
		for i, l in ipairs( Wrap( OBJ_MARK[ o.state ] .. " " .. o.text .. ( o.optional and " (доп.)" or "" ), "SkyOpsArtyM_Small", w - pad * 2 ) ) do
			lines[ #lines + 1 ] = { ( i > 1 and "    " or "" ) .. l, "SkyOpsArtyM_Small", OBJ_COL[ o.state ] or C.text }
		end
	end

	local ammo = {}

	if ( st.ammo.he or 0 ) > 0 or ( st.used.he or 0 ) > 0 then ammo[ #ammo + 1 ] = string.format( "ОФС %d/%d", st.used.he or 0, st.ammo.he or 0 ) end
	if ( st.ammo.krasnopol or 0 ) > 0 or ( st.used.krasnopol or 0 ) > 0 then ammo[ #ammo + 1 ] = string.format( "Кр %d/%d", st.used.krasnopol or 0, st.ammo.krasnopol or 0 ) end

	lines[ #lines + 1 ] = { string.format( "Цели %d/%d   %s   в полёте %d", ( st.total or 0 ) - ( st.alive or 0 ), st.total or 0, table.concat( ammo, "  " ), st.inflight or 0 ), "SkyOpsArtyM_Small", C.text }
	lines[ #lines + 1 ] = { "Время " .. M.FmtTime( CurTime() - ( st.start or CurTime() ) ), "SkyOpsArtyM_Small", C.muted }

	if st.leaves then
		local left = st.leaves - CurTime()

		lines[ #lines + 1 ] = { "Цель уйдёт через " .. M.FmtTime( left ), "SkyOpsArtyM_Small", left < 60 and C.threat or C.accent }
	end

	if st.intel then
		lines[ #lines + 1 ] = { "Цель: " .. Grid.Format( st.intel.x, st.intel.y ), "SkyOpsArtyM_Small", C.threat }
		lines[ #lines + 1 ] = { "  источник " .. ( st.intel.src or "?" ) .. ( ( st.intel.err or 0 ) > 0 and ( ", ошибка до " .. math.Round( st.intel.err ) .. " м" ) or "" ), "SkyOpsArtyM_Small", C.muted }
	elseif st.area then
		lines[ #lines + 1 ] = { "Район: " .. Grid.Format( st.area.x, st.area.y ) .. " R" .. st.area.r, "SkyOpsArtyM_Small", C.accent }
	end

	local wx, wy, label = Waypoint( st )

	if wx then
		local mx, my = MyGrid()
		local d = math.sqrt( ( wx - mx ) ^ 2 + ( wy - my ) ^ 2 )

		lines[ #lines + 1 ] = { string.format( "До %s: %.1f км, дир. %s", label, d / 1000, M.FmtMils( Grid.Bearing( mx, my, wx, wy ) ) ), "SkyOpsArtyM_Small", C.friend }
	end

	if not st.hasSPG then
		lines[ #lines + 1 ] = { "Сядьте в 2С35", "SkyOpsArtyM_Small", C.accent }
	end

	local h = pad * 2 + S( 6 )

	for i, l in ipairs( lines ) do h = h + ( i == 1 and S( 26 ) or lh ) end

	Box( x, y, w, h, C.bg )
	Box( x, y, S( 3 ), h, C.accent )

	local cy = y + pad

	for i, l in ipairs( lines ) do
		Text( l[ 1 ], l[ 2 ], x + pad, cy, l[ 3 ] )
		cy = cy + ( i == 1 and S( 26 ) or lh )
	end

	return h
end

-- arrow at the top of the screen pointing at the waypoint relative to the view
local function PaintCompass( st )
	local wx, wy, label, col = Waypoint( st )

	if not wx then return end

	local mx, my = MyGrid()
	local bearing = Grid.Bearing( mx, my, wx, wy )
	local view = Grid.YawToMils( EyeAngles().y )
	local rel = ( ( bearing - view + 3000 ) % 6000 ) - 3000 -- -3000..3000 mils
	local cx, top = ScrW() / 2, S( 18 )
	local half = S( 260 )
	local px = cx + math.Clamp( rel / 1500, -1, 1 ) * half

	Box( cx - half, top + S( 14 ), half * 2, 1, C.line )

	-- ticks every 250 mils
	for m = -1500, 1500, 250 do
		local x = cx + m / 1500 * half

		Box( x, top + S( m % 1000 == 0 and 6 or 10 ), 1, S( m % 1000 == 0 and 16 or 8 ), C.muted )
	end

	local s = S( 9 )
	local y = top + S( 22 )

	draw.NoTexture()
	surface.SetDrawColor( col )
	surface.DrawPoly( { { x = px, y = y - s }, { x = px + s, y = y + s }, { x = px - s, y = y + s } } )

	local d = math.sqrt( ( wx - mx ) ^ 2 + ( wy - my ) ^ 2 )

	HText( string.format( "%s %s  %.1f км", label, M.FmtMils( bearing ), d / 1000 ), "SkyOpsArtyM_Small", px, y + s + S( 4 ), col, TEXT_ALIGN_CENTER )

	if math.abs( rel ) > 1500 then
		HText( rel > 0 and ">>" or "<<", "SkyOpsArtyM_H2", px + ( rel > 0 and S( 16 ) or -S( 16 ) ), y - S( 4 ), col, TEXT_ALIGN_CENTER )
	end

	-- on the firing position: a ring meter of how far the hull is from the point
	if st.stage <= M.STAGE_DEPLOY and d < 600 then
		local inside = d <= ( st.fp.r or M.FP_RADIUS )

		HText( inside and "НА ОП: развернуть (H)" or string.format( "до ОП %d м", math.Round( d ) ), "SkyOpsArtyM_H2", cx, ScrH() * 0.7, inside and C.ok or C.friend, TEXT_ALIGN_CENTER )
	end
end

local function PaintRadio()
	local x, y = S( 24 ), ScrH() * 0.62
	local w = S( 560 )

	for _, r in ipairs( CL.radio ) do
		local age = RealTime() - r.time

		if age < 14 then
			local a = math.Clamp( ( 14 - age ) / 2, 0, 1 )
			local lines = Wrap( r.text, "SkyOpsArtyM_Text", w )
			local fromCol = ColorAlpha( r.from == "Штаб" and C.accent or ( string.find( r.from, "Дрон", 1, true ) and C.friend or C.ok ), 255 * a )

			for i = #lines, 1, -1 do
				y = y - S( 20 )
				HText( lines[ i ], "SkyOpsArtyM_Text", x + S( 110 ), y, ColorAlpha( C.text, 255 * a ) )
			end

			HText( r.from, "SkyOpsArtyM_Text", x, y, fromCol )
			y = y - S( 6 )
		end
	end
end

hook.Add( "HUDPaint", "SkyOps.Arty.Missions", function()
	if not cvHud:GetBool() then return end

	local st = CL.state

	if not st or not st.stage or st.stage == M.STAGE_NONE then return end

	if InMission() and st.stage ~= M.STAGE_DONE then
		PaintObjectives( st, ScrW() - S( 400 ) - S( 20 ), S( 120 ), S( 400 ) )
		PaintCompass( st )
	elseif not InMission() and st.stage ~= M.STAGE_DONE then
		HText( "Идёт задание «" .. ( st.name or "" ) .. "». " .. string.upper( input.GetKeyName( cvKey:GetInt() ) or "F7" ) .. " — присоединиться", "SkyOpsArtyM_Small", ScrW() - S( 20 ), S( 120 ), C.muted, TEXT_ALIGN_RIGHT )
	end

	PaintRadio()
end )

-- Tablet map marks -------------------------------------------------------------------------------

-- draws the firing position, the search area, the target point and (auto mode) the live
-- targets on the arty/ui map panel; p:ToScreen( e, n ) is that panel's grid -> pixel
local function PaintMapMarks( p )
	local st = CL.state

	if not st or not st.stage or st.stage == M.STAGE_NONE or st.stage == M.STAGE_DONE then return end

	local function R( m )
		local x1 = p:ToScreen( 0, 0 )
		local x2 = p:ToScreen( m, 0 )

		return math.abs( x2 - x1 )
	end

	if st.fp then
		local x, y = p:ToScreen( st.fp.x, st.fp.y )
		local r = math.max( R( st.fp.r or M.FP_RADIUS ), S( 6 ) )

		Circle( x, y, r, C.friend, 32 )
		Box( x - S( 5 ), y, S( 11 ), 1, C.friend )
		Box( x, y - S( 5 ), 1, S( 11 ), C.friend )
		Text( "ОП", "SkyOpsArtyM_Small", x + r + S( 4 ), y, C.friend, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER )
	end

	if st.area and not st.intel then
		local x, y = p:ToScreen( st.area.x, st.area.y )
		local r = math.max( R( st.area.r ), S( 8 ) )

		Circle( x, y, r, C.accent, 48, true )
		Text( "район поиска", "SkyOpsArtyM_Small", x, y - r - S( 4 ), C.accent, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM )
	end

	if st.intel then
		local x, y = p:ToScreen( st.intel.x, st.intel.y )

		if ( st.intel.err or 0 ) > 0 then Circle( x, y, math.max( R( st.intel.err ), S( 4 ) ), ColorAlpha( C.threat, 140 ), 32, true ) end

		Text( "цель (" .. ( st.intel.src or "" ) .. ")", "SkyOpsArtyM_Small", x + S( 10 ), y - S( 10 ), C.threat, TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM )
	end

	for _, t in ipairs( st.targets or {} ) do
		local x, y = p:ToScreen( t.x, t.y )
		local col = t.alive and C.threat or C.muted

		Box( x - S( 3 ), y - S( 3 ), S( 6 ), S( 6 ), col )
	end
end

M.PaintMapMarks = PaintMapMarks

-- the arty/ui map has no hook for other modules: wrap its PaintTarget (drawn inside the
-- map's scissor rectangle) once the panel is registered
local function HookMap()
	local tbl = vgui.GetControlTable( "SkyOpsArtyMap" )

	if not tbl or tbl.SkyOpsArtyM_Wrapped or not tbl.PaintTarget then return false end

	local orig = tbl.PaintTarget

	tbl.PaintTarget = function( self, ... )
		local ok, err = pcall( PaintMapMarks, self )

		if not ok then ErrorNoHalt( "[Arty mission] map marks: " .. tostring( err ) .. "\n" ) end

		return orig( self, ... )
	end

	tbl.SkyOpsArtyM_Wrapped = true

	return true
end

hook.Add( "SkyOps.Loaded", "SkyOps.Arty.Missions.Map", HookMap )
hook.Add( "InitPostEntity", "SkyOps.Arty.Missions.Map", HookMap )

-- Menu -------------------------------------------------------------------------------------------

local function Button( parent, text, primary, onClick )
	local b = vgui.Create( "DButton", parent )

	b:SetText( "" )
	b.Label = text
	b.Primary = primary
	b.DoClick = function( self ) surface.PlaySound( "buttons/lightswitch2.wav" ) onClick( self ) end
	b.Paint = function( self, w, h )
		local col = self:GetDisabled() and C.line or ( self.Primary and C.accent or C.panel )

		Box( 0, 0, w, h, col )

		if self:IsHovered() and not self:GetDisabled() then Box( 0, 0, w, h, Color( 255, 255, 255, 20 ) ) end

		Outline( 0, 0, w, h, self.Primary and C.accent or C.line )
		Text( self.Label, "SkyOpsArtyM_H2", w / 2, h / 2, self.Primary and C.bg or C.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER )
	end

	return b
end

local function Toggle( parent, text, value, onChange )
	local b = vgui.Create( "DButton", parent )

	b:SetText( "" )
	b.Value = value
	b.DoClick = function( self )
		self.Value = not self.Value
		onChange( self.Value )
	end
	b.Paint = function( self, w, h )
		local s = h - S( 8 )

		Outline( S( 2 ), S( 4 ), s, s, C.muted )
		if self.Value then Box( S( 6 ), S( 8 ), s - S( 8 ), s - S( 8 ), C.accent ) end

		Text( text, "SkyOpsArtyM_Text", s + S( 12 ), h / 2, self:IsHovered() and C.text or C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER )
	end

	return b
end

local MENU = {}

function MENU:Init()
	self.sel = self.sel or { type = M.Types[ 1 ].id, range = "mid", march = true, kit = false }

	self:SetSize( math.min( S( 1100 ), ScrW() - S( 40 ) ), math.min( S( 680 ), ScrH() - S( 40 ) ) )
	self:Center()
	self:MakePopup()
	self:SetKeyboardInputEnabled( false )

	local w, h = self:GetSize()
	local pad = S( 20 )

	local close = Button( self, "×", false, function() self:Remove() end )

	close:SetSize( S( 36 ), S( 36 ) )
	close:SetPos( w - S( 36 ) - S( 10 ), S( 10 ) )

	-- mission types, left column
	self.types = {}

	local ty = S( 70 )

	for i, def in ipairs( M.Types ) do
		local b = vgui.Create( "DButton", self )

		b:SetText( "" )
		b:SetPos( pad, ty )
		b:SetSize( S( 300 ), S( 64 ) )
		b.DoClick = function()
			self.sel.type = def.id
			surface.PlaySound( "buttons/lightswitch2.wav" )
		end
		b.Paint = function( pnl, bw, bh )
			local on = self.sel.type == def.id

			Box( 0, 0, bw, bh, on and Color( 242, 169, 59, 30 ) or C.panel )
			Box( 0, 0, S( 4 ), bh, on and C.accent or C.line )
			Text( def.name, "SkyOpsArtyM_H2", S( 16 ), S( 10 ), on and C.accent or C.text )

			local tags = { def.intel == "drone" and "цель ищет дрон" or "координаты от штаба" }

			if ( def.ammo.krasnopol or 0 ) > 0 then tags[ #tags + 1 ] = "Краснополь" end
			if def.fleeting then tags[ #tags + 1 ] = "уходит" end

			Text( table.concat( tags, " · " ), "SkyOpsArtyM_Small", S( 16 ), S( 38 ), C.muted )
		end

		ty = ty + S( 72 )
	end

	-- range band
	local ox = pad + S( 320 )
	local rw = ( w - ox - pad - S( 300 ) - pad ) / #M.Ranges

	for i, r in ipairs( M.Ranges ) do
		local b = vgui.Create( "DButton", self )

		b:SetText( "" )
		b:SetPos( ox + ( i - 1 ) * rw, S( 330 ) )
		b:SetSize( rw - S( 6 ), S( 52 ) )
		b.DoClick = function() self.sel.range = r.id surface.PlaySound( "buttons/lightswitch2.wav" ) end
		b.Paint = function( pnl, bw, bh )
			local on = self.sel.range == r.id

			Box( 0, 0, bw, bh, on and C.accent or C.panel )
			Outline( 0, 0, bw, bh, on and C.accent or C.line )
			Text( r.name, "SkyOpsArtyM_H2", bw / 2, S( 6 ), on and C.bg or C.text, TEXT_ALIGN_CENTER )
			Text( string.format( "%d–%d км", r.min / 1000, r.max / 1000 ), "SkyOpsArtyM_Small", bw / 2, S( 30 ), on and C.bg or C.muted, TEXT_ALIGN_CENTER )
		end
	end

	local march = Toggle( self, "Марш на огневую позицию (1,5–3 км)", self.sel.march, function( v ) self.sel.march = v end )

	march:SetPos( ox, S( 400 ) )
	march:SetSize( S( 420 ), S( 30 ) )

	local kit = Toggle( self, "Выдать 2С35 и дрон рядом со мной", self.sel.kit, function( v ) self.sel.kit = v end )

	kit:SetPos( ox, S( 436 ) )
	kit:SetSize( S( 420 ), S( 30 ) )

	-- mode switch (server convar, admin)
	self.modeBtn = Button( self, "", false, function()
		local cur = GetConVar( "skyops_arty_mode" )
		local nextMode = ( cur and cur:GetString() == "auto" ) and "hardcore" or "auto"

		RunConsoleCommand( "skyops_arty_mode", nextMode )
	end )
	self.modeBtn:SetPos( ox, S( 478 ) )
	self.modeBtn:SetSize( S( 420 ), S( 40 ) )
	self.modeBtn.Think = function( b )
		local cur = GetConVar( "skyops_arty_mode" )

		b.Label = "Режим: " .. ( ( cur and cur:GetString() == "auto" ) and "авто (одна кнопка)" or "хардкор (ручная наводка)" )
	end

	-- buttons at the bottom
	self.startBtn = Button( self, "Начать задание", true, function()
		M.Req( "start", self.sel )
		self:Remove()
	end )
	self.startBtn:SetPos( ox, h - pad - S( 50 ) )
	self.startBtn:SetSize( S( 260 ), S( 50 ) )

	self.joinBtn = Button( self, "Присоединиться", false, function()
		M.Req( "join", { role = self.role or "оператор дрона" } )
	end )
	self.joinBtn:SetPos( ox + S( 270 ), h - pad - S( 50 ) )
	self.joinBtn:SetSize( S( 220 ), S( 50 ) )

	self.abortBtn = Button( self, "Прервать", false, function()
		M.Req( "abort" )
	end )
	self.abortBtn:SetPos( ox + S( 500 ), h - pad - S( 50 ) )
	self.abortBtn:SetSize( S( 160 ), S( 50 ) )

	self:Refresh()
end

function MENU:Refresh()
	local st = CL.state or {}
	local running = st.stage and st.stage ~= M.STAGE_NONE and st.stage ~= M.STAGE_DONE
	local avail = CL.menuData and CL.menuData.avail or {}

	if IsValid( self.startBtn ) then
		self.startBtn:SetDisabled( avail.control == false )
		self.startBtn.Label = running and "Новое задание" or "Начать задание"
	end

	if IsValid( self.joinBtn ) then self.joinBtn:SetDisabled( not running or InMission() ) end
	if IsValid( self.abortBtn ) then self.abortBtn:SetDisabled( not ( st.stage and st.stage ~= M.STAGE_NONE ) ) end
end

function MENU:Paint( w, h )
	Derma_DrawBackgroundBlur( self, self.created or 0 )

	Box( 0, 0, w, h, C.bg )
	Outline( 0, 0, w, h, C.line )
	Box( 0, 0, w, S( 3 ), C.accent )

	local pad = S( 20 )

	Text( "АРТИЛЛЕРИЯ · ЗАДАНИЯ", "SkyOpsArtyM_Title", pad, S( 18 ), C.text )

	-- description of the selected type
	local def = M.GetType( self.sel.type ) or M.Types[ 1 ]
	local ox = pad + S( 320 )
	local dw = w - ox - pad - S( 300 ) - pad

	Text( def.name, "SkyOpsArtyM_H2", ox, S( 72 ), C.accent )

	local y = S( 104 )

	for _, l in ipairs( Wrap( def.desc, "SkyOpsArtyM_Text", dw ) ) do
		Text( l, "SkyOpsArtyM_Text", ox, y, C.text )
		y = y + S( 22 )
	end

	y = y + S( 10 )

	local count = 0

	for _, n in pairs( def.group ) do count = count + n end

	local facts = {
		string.format( "Целей: %d, уничтожить %d", count, math.max( math.ceil( count * def.need ), 1 ) ),
		string.format( "БК: ОФС %d, Краснополь %d", def.ammo.he or 0, def.ammo.krasnopol or 0 ),
	}

	if def.intel == "drone" then facts[ #facts + 1 ] = string.format( "Район поиска радиусом %d м", def.area ) end
	if def.hqError then facts[ #facts + 1 ] = string.format( "Ошибка координат штаба до %d м (в хардкоре)", def.hqError ) end
	if def.fleeting then facts[ #facts + 1 ] = "Цель уходит через " .. M.FmtTime( def.fleeting ) .. " после обнаружения" end

	for _, f in ipairs( facts ) do
		Text( "· " .. f, "SkyOpsArtyM_Small", ox, y, C.muted )
		y = y + S( 20 )
	end

	Text( "ДАЛЬНОСТЬ ДО ЦЕЛИ", "SkyOpsArtyM_Small", ox, S( 308 ), C.muted )

	-- right column: running mission, availability, history
	local rx = w - pad - S( 300 )
	local st = CL.state or {}

	Box( rx, S( 70 ), S( 300 ), h - S( 90 ), C.panel )

	local ry = S( 82 )
	local function Line( t, col, font )
		Text( t, font or "SkyOpsArtyM_Small", rx + S( 12 ), ry, col or C.text )
		ry = ry + S( 20 )
	end

	if st.stage and st.stage ~= M.STAGE_NONE then
		Line( "ИДЁТ ЗАДАНИЕ", C.accent )
		Line( st.name or "", C.text, "SkyOpsArtyM_H2" )
		ry = ry + S( 4 )
		Line( "этап: " .. ( M.StageNames[ st.stage ] or "" ), C.muted )

		for _, p in ipairs( st.players or {} ) do
			Line( "· " .. p.name .. " — " .. ( p.role or "" ), C.friend )
		end
	else
		Line( "Заданий нет", C.muted )
	end

	ry = ry + S( 10 )

	local avail = CL.menuData and CL.menuData.avail or {}
	local function Avail( ok, t ) Line( ( ok and "+ " or "- " ) .. t, ok and C.ok or C.threat ) end

	Avail( avail.core, "баллистика (arty/core)" )
	Avail( avail.spg, "2С35" )
	Avail( avail.uav, "дроны" )
	Avail( avail.drone, "модуль дрона (лазер)" )
	Avail( avail.kirov, "карта Кировское" )

	ry = ry + S( 10 )
	Line( "ПОСЛЕДНИЕ РЕЗУЛЬТАТЫ", C.muted )

	for i, r in ipairs( CL.menuData and CL.menuData.history or {} ) do
		if ry > h - S( 40 ) then break end

		Line( string.format( "%s  %-4s %s", r.grade or "-", tostring( r.score or 0 ), r.name or "" ), r.success and C.text or C.muted )
	end
end

vgui.Register( "SkyOpsArtyMissionMenu", MENU, "EditablePanel" )

function M.OpenMenu()
	if IsValid( CL.menu ) then CL.menu:Remove() end

	CL.menu = vgui.Create( "SkyOpsArtyMissionMenu" )
	CL.menu.created = SysTime()
end

-- Debrief ------------------------------------------------------------------------------------------

local GRADE_COL = { S = Color( 255, 214, 102 ), A = C.ok, B = C.friend, C = C.accent, D = C.threat }

local DEB = {}

function DEB:Init()
	self:SetSize( math.min( S( 980 ), ScrW() - S( 40 ) ), math.min( S( 640 ), ScrH() - S( 40 ) ) )
	self:Center()
	self:MakePopup()
	self:SetKeyboardInputEnabled( false )

	local w, h = self:GetSize()
	local close = Button( self, "Закрыть", true, function() self:Remove() end )

	close:SetSize( S( 180 ), S( 44 ) )
	close:SetPos( w - S( 180 ) - S( 20 ), h - S( 44 ) - S( 20 ) )

	local again = Button( self, "Ещё задание", false, function()
		self:Remove()
		M.Req( "menu" )
	end )

	again:SetSize( S( 180 ), S( 44 ) )
	again:SetPos( w - S( 370 ) - S( 20 ), h - S( 44 ) - S( 20 ) )
end

local function Opt( v, fmt, f )
	if v == nil then return "—" end

	return f and f( v ) or string.format( fmt, v )
end

-- burst plot: every shell relative to its nearest target, gun-target line pointing up
local function PaintShots( d, x, y, size )
	Box( x, y, size, size, C.panel )

	local cx, cy = x + size / 2, y + size / 2
	local scale = ( size / 2 - S( 8 ) ) / 200 -- 200 m to the edge

	for _, r in ipairs( { 25, 50, 100, 200 } ) do
		Circle( cx, cy, r * scale, r == 50 and ColorAlpha( C.ok, 120 ) or C.line, 48 )
		Text( r .. " м", "SkyOpsArtyM_Small", cx + r * scale * 0.71 + S( 2 ), cy - r * scale * 0.71, C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM )
	end

	Box( cx, y + S( 6 ), 1, size - S( 12 ), C.line )
	Box( x + S( 6 ), cy, size - S( 12 ), 1, C.line )
	Text( "дальше", "SkyOpsArtyM_Small", cx, y + S( 4 ), C.muted, TEXT_ALIGN_CENTER )
	Text( "ближе", "SkyOpsArtyM_Small", cx, y + size - S( 4 ), C.muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM )

	for i, s in ipairs( d.shotLog or {} ) do
		if s.lat and s.rng then
			local px = cx + math.Clamp( s.lat, -210, 210 ) * scale
			local py = cy - math.Clamp( s.rng, -210, 210 ) * scale
			local col = ( s.kills or 0 ) > 0 and C.ok or ( s.shell == "krasnopol" and C.friend or C.accent )

			Box( px - S( 3 ), py - S( 3 ), S( 7 ), S( 7 ), col )

			if i == 1 then Circle( px, py, S( 7 ), C.text, 12 ) end
		end
	end

	Text( "разрывы относительно ближайшей цели", "SkyOpsArtyM_Small", x, y + size + S( 6 ), C.muted )
end

function DEB:Paint( w, h )
	local d = CL.debrief or {}
	local pad = S( 24 )

	Box( 0, 0, w, h, C.bg )
	Outline( 0, 0, w, h, C.line )
	Box( 0, 0, w, S( 3 ), d.success and C.ok or C.threat )

	Text( d.success and "ЗАДАЧА ВЫПОЛНЕНА" or "ЗАДАЧА НЕ ВЫПОЛНЕНА", "SkyOpsArtyM_Title", pad, S( 18 ), d.success and C.ok or C.threat )
	Text( string.format( "%s · %s, %.1f км · %s · %s", d.name or "", d.range or "", ( d.distance or 0 ) / 1000, d.mode == "auto" and "авто" or "хардкор", d.reason or "" ), "SkyOpsArtyM_Small", pad, S( 56 ), C.muted )

	local sc = d.score or {}
	local grade = sc.grade or "D"

	Text( grade, "SkyOpsArtyM_Grade", pad + S( 60 ), S( 90 ), GRADE_COL[ grade ] or C.text, TEXT_ALIGN_CENTER )
	Text( string.format( "%d / %d", sc.total or 0, sc.max or 0 ), "SkyOpsArtyM_Big", pad + S( 60 ), S( 210 ), C.text, TEXT_ALIGN_CENTER )

	-- score lines
	local y = S( 260 )

	for _, l in ipairs( sc.lines or {} ) do
		Text( l.name, "SkyOpsArtyM_Small", pad, y, C.muted )
		Text( ( l.pts >= 0 and "+" or "" ) .. l.pts .. ( l.max and ( " / " .. l.max ) or "" ), "SkyOpsArtyM_Small", pad + S( 250 ), y, l.pts < 0 and C.threat or C.text, TEXT_ALIGN_RIGHT )
		y = y + S( 20 )
	end

	-- stats, middle column
	local mx = pad + S( 290 )
	local used = d.used or {}
	local ammo = d.ammo or {}
	local stats = {
		{ "Время задания", M.FmtTime( d.duration ) },
		{ "Марш на ОП", Opt( d.marchTime, nil, M.FmtTime ) },
		{ "Развёртывание", Opt( d.deployTime, nil, M.FmtTime ) },
		{ "Поиск цели", Opt( d.searchTime, nil, M.FmtTime ) },
		{ "Цель -> 1-й выстрел", Opt( d.firstShotDelay, nil, M.FmtTime ) },
		{ "Цель -> поражение", Opt( d.reaction, nil, M.FmtTime ) },
		{ "Выстрелов", string.format( "%d (ОФС %d/%d, Кр %d/%d)", d.shots or 0, used.he or 0, ammo.he or 0, used.krasnopol or 0, ammo.krasnopol or 0 ) },
		{ "Попаданий (до 50 м)", tostring( d.hits or 0 ) },
		{ "Промах 1-го выстрела", Opt( d.firstMiss, "%d м" ) },
		{ "Средний промах", Opt( d.avgMiss, "%d м" ) },
		{ "Лучший разрыв", Opt( d.bestMiss, "%d м" ) },
	}

	y = S( 96 )

	for _, s in ipairs( stats ) do
		Text( s[ 1 ], "SkyOpsArtyM_Small", mx, y, C.muted )
		Text( s[ 2 ], "SkyOpsArtyM_Small", mx + S( 200 ), y, C.text )
		y = y + S( 21 )
	end

	y = y + S( 10 )
	Text( "ЦЕЛИ", "SkyOpsArtyM_Small", mx, y, C.muted )
	y = y + S( 20 )

	for _, t in ipairs( d.targets or {} ) do
		if y > h - S( 80 ) then break end

		Text( ( t.alive and "· " or "x " ) .. t.name .. ( t.alive and string.format( " (%d%%)", t.hp or 100 ) or "" ), "SkyOpsArtyM_Small", mx, y, t.alive and C.threat or C.ok )
		y = y + S( 19 )
	end

	-- burst plot, right
	local size = math.min( S( 300 ), w - mx - S( 360 ) - pad )

	if size > S( 150 ) then
		PaintShots( d, w - pad - size, S( 96 ), size )
	end
end

vgui.Register( "SkyOpsArtyMissionDebrief", DEB, "EditablePanel" )

function M.OpenDebrief()
	if not CL.debrief then return end
	if IsValid( CL.debriefPanel ) then CL.debriefPanel:Remove() end

	CL.debriefPanel = vgui.Create( "SkyOpsArtyMissionDebrief" )
end

concommand.Add( "skyops_arty_mission_debrief", M.OpenDebrief, nil, "Снова открыть итоги последнего задания" )
