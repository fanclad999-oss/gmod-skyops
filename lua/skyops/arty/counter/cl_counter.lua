-- Counter-battery fire, client: exposure of the firing position for the crew of a 2S35,
-- the incoming warning with a countdown, and the enemy battery and the incoming salvo
-- on the tablet map of arty/ui.

local CB = SkyOps.Arty.Counter
local Grid = SkyOps.Arty.Grid

CB.Client = CB.Client or { incoming = {}, battery = nil }

local CL = CB.Client

local C = {
	panel = Color( 21, 27, 32, 220 ),
	line = Color( 42, 52, 59 ),
	text = Color( 216, 222, 226 ),
	muted = Color( 154, 167, 175 ),
	accent = Color( 242, 169, 59 ),
	ok = Color( 125, 222, 146 ),
	threat = Color( 255, 107, 94 ),
	shadow = Color( 0, 0, 0, 170 ),
}

local cvHud = CreateClientConVar( "skyops_arty_counter_hud", "1", true, false, "Показывать засветку ОП и предупреждение о прилёте" )

local ALARM = "ambient/alarms/klaxon1.wav"

local function S( x )
	local ui = SkyOps.Arty.UI

	if ui and ui.S then return ui.S( x ) end

	return math.max( math.Round( x * math.max( ScrH() / 1080, 0.9 ) ), 1 )
end

local function Fonts()
	surface.CreateFont( "SkyOpsArtyCB_Small", { font = "Consolas", size = S( 16 ), weight = 600, extended = true } )
	surface.CreateFont( "SkyOpsArtyCB_Text", { font = "Bahnschrift", size = S( 21 ), weight = 600, extended = true } )
	surface.CreateFont( "SkyOpsArtyCB_Big", { font = "Bahnschrift", size = S( 40 ), weight = 800, extended = true } )
end

Fonts()
hook.Add( "OnScreenSizeChanged", "SkyOps.Arty.Counter.Fonts", Fonts )
hook.Add( "SkyOpsArty.UI.Rescaled", "SkyOps.Arty.Counter.Fonts", Fonts )

local function HText( text, font, x, y, col, ax, ay )
	draw.SimpleText( text, font, x + 1, y + 1, C.shadow, ax, ay )
	draw.SimpleText( text, font, x, y, col, ax, ay )
end

-- unlocalized world position of an entity (client positions are chunk-relative on InfMap)
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

	return Grid.ToGrid( AbsPos( IsValid( veh ) and veh or ply ) )
end

local function MySPG()
	local SPG = SkyOps.Arty.SPG

	return SPG and SPG.Of( LocalPlayer() )
end

-- Net ------------------------------------------------------------------------------------------

net.Receive( CB.NET_INCOMING, function()
	local x, y, tof, n = net.ReadFloat(), net.ReadFloat(), net.ReadFloat(), net.ReadUInt( 8 )

	CL.incoming[ #CL.incoming + 1 ] = { x = x, y = y, at = CurTime() + tof, n = n }

	local mx, my = MyGrid()

	if math.sqrt( ( mx - x ) ^ 2 + ( my - y ) ^ 2 ) <= CB.DANGER_RADIUS then
		surface.PlaySound( ALARM )
	end
end )

net.Receive( CB.NET_BATTERY, function()
	local known, x, y, err, alive = net.ReadBool(), net.ReadFloat(), net.ReadFloat(), net.ReadFloat(), net.ReadBool()

	CL.battery = known and { x = x, y = y, err = err, alive = alive } or nil
end )

-- HUD ------------------------------------------------------------------------------------------

-- exposure bar of the current firing position, top centre under the mission compass
local function PaintExposure( spg )
	local heat = spg:GetNW2Float( "SkyOpsCB_Heat", 0 )
	local locked = spg:GetNW2Bool( "SkyOpsCB_Locked", false )
	local text, key = CB.HeatText( heat, locked )
	local col = C[ key ]
	local w, h = S( 300 ), S( 8 )
	local x, y = ScrW() / 2 - w / 2, S( 96 )

	HText( "ЗАСВЕТКА ОП: " .. text, "SkyOpsArtyCB_Small", ScrW() / 2, y - S( 4 ), col, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM )

	surface.SetDrawColor( C.panel )
	surface.DrawRect( x, y, w, h )
	surface.SetDrawColor( col )
	surface.DrawRect( x, y, w * math.Clamp( heat, 0, 1 ), h )
	surface.SetDrawColor( C.line )
	surface.DrawOutlinedRect( x, y, w, h )

	if not locked then return end

	-- how far the hull is from the located spot
	local sx, sy = spg:GetNW2Float( "SkyOpsCB_X", 0 ), spg:GetNW2Float( "SkyOpsCB_Y", 0 )
	local gx, gy = Grid.ToGrid( AbsPos( spg ) )
	local d = math.sqrt( ( gx - sx ) ^ 2 + ( gy - sy ) ^ 2 )
	local blink = math.sin( RealTime() * 6 ) > -0.3

	if blink then
		HText( string.format( "СМЕНИТЬ ПОЗИЦИЮ: %d / %d м", math.Round( d ), CB.MOVE_RADIUS ), "SkyOpsArtyCB_Text", ScrW() / 2, y + h + S( 6 ), C.threat, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP )
	end
end

-- countdown of the salvos in flight; big when it comes down near the player
local function PaintIncoming()
	local mx, my = MyGrid()
	local y = ScrH() * 0.28
	local now = CurTime()

	for i = #CL.incoming, 1, -1 do
		local inc = CL.incoming[ i ]
		local left = inc.at - now

		if left < -12 then
			table.remove( CL.incoming, i )
		else
			local d = math.sqrt( ( mx - inc.x ) ^ 2 + ( my - inc.y ) ^ 2 )

			if d <= CB.DANGER_RADIUS then
				local text = left > 0 and string.format( "ПРИЛЁТ ЧЕРЕЗ %d с — В УКРЫТИЕ!", math.ceil( left ) ) or "ОБСТРЕЛ!"
				local col = ColorAlpha( C.threat, math.sin( RealTime() * 8 ) > 0 and 255 or 150 )

				HText( text, "SkyOpsArtyCB_Big", ScrW() / 2, y, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER )
				y = y + S( 46 )
			elseif d <= 5000 and left > 0 then
				HText( string.format( "Противник бьёт по точке в %.1f км от вас: прилёт через %d с", d / 1000, math.ceil( left ) ), "SkyOpsArtyCB_Text", ScrW() / 2, y, C.accent, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER )
				y = y + S( 28 )
			end
		end
	end
end

hook.Add( "HUDPaint", "SkyOps.Arty.Counter", function()
	if not cvHud:GetBool() or CB.Mode() <= 0 then return end

	local spg = MySPG()

	if spg and ( spg:GetNW2Float( "SkyOpsCB_Heat", 0 ) > 0 or spg:GetNW2Bool( "SkyOpsCB_Locked", false ) ) then
		PaintExposure( spg )
	end

	if #CL.incoming > 0 then PaintIncoming() end
end )

-- Tablet map ---------------------------------------------------------------------------------------

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

-- p:ToScreen( e, n ) is the arty/ui map panel's grid -> pixel
local function PaintMapMarks( p )
	local function R( m )
		local x1 = p:ToScreen( 0, 0 )
		local x2 = p:ToScreen( m, 0 )

		return math.abs( x2 - x1 )
	end

	local bat = CL.battery

	if bat then
		local x, y = p:ToScreen( bat.x, bat.y )
		local col = bat.alive and C.threat or C.muted
		local s = S( 6 )

		surface.SetDrawColor( col )
		surface.DrawLine( x - s, y - s, x + s, y + s )
		surface.DrawLine( x - s, y + s, x + s, y - s )
		Circle( x, y, math.max( R( bat.err ), S( 6 ) ), ColorAlpha( col, 160 ), 32, true )
		draw.SimpleText( bat.alive and "батарея пр-ка" or "батарея пр-ка (подавлена)", "SkyOpsArtyCB_Small", x + S( 10 ), y + S( 6 ), col )
	end

	local now = CurTime()

	for _, inc in ipairs( CL.incoming ) do
		if inc.at > now then
			local x, y = p:ToScreen( inc.x, inc.y )

			Circle( x, y, math.max( R( 60 ), S( 6 ) ), C.threat, 24 )
			draw.SimpleText( string.format( "прилёт %d с", math.ceil( inc.at - now ) ), "SkyOpsArtyCB_Small", x + S( 10 ), y - S( 18 ), C.threat )
		end
	end
end

-- the arty/ui map has no hook for other modules: wrap its PaintTarget like arty/missions does
local function HookMap()
	local tbl = vgui.GetControlTable( "SkyOpsArtyMap" )

	if not tbl or tbl.SkyOpsArtyCB_Wrapped or not tbl.PaintTarget then return false end

	local orig = tbl.PaintTarget

	tbl.PaintTarget = function( self, ... )
		local ok, err = pcall( PaintMapMarks, self )

		if not ok then ErrorNoHalt( "[Arty counter] map marks: " .. tostring( err ) .. "\n" ) end

		return orig( self, ... )
	end

	tbl.SkyOpsArtyCB_Wrapped = true

	return true
end

hook.Add( "SkyOps.Loaded", "SkyOps.Arty.Counter.Map", HookMap )
hook.Add( "InitPostEntity", "SkyOps.Arty.Counter.Map", HookMap )
