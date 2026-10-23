-- SkyOps: экран брифинга перед вылетом (client)
-- Слева обстановка, задачи и угрозы; в центре карта района; справа экипажи, подвеска и готовность.

SkyOps = SkyOps or {}
SkyOps.UI = SkyOps.UI or {}

local UI = SkyOps.UI
local M = SkyOps.Missions

local function C() return SkyOps.Client end

local function SeatName( role, seat )
	if seat == M.SEAT_PILOT then return "ПИЛОТ" end
	if role == "f14a" then return "ОПЕРАТОР РЛС" end
	if role == "tornado_ids" then return "ШТУРМАН" end

	return "ШТУРМАН-ОПЕРАТОР"
end

---------------------------------------------------------------------------
-- Карта района
---------------------------------------------------------------------------

local MAP = {}

function MAP:Init()
	self.zoom = 1
end

-- Проекция: мир -> плоскость карты, север вверх
function MAP:Setup( brief, w, h )
	local north = Angle( 0, brief.north_yaw or 90, 0 ):Forward()
	local east = Vector( north.y, -north.x, 0 )

	self.north, self.east = north, east

	local pts = {}

	local function Add( p, r )
		if not p then return end

		local v = C().ToVector( p )
		local mx, my = v:Dot( east ), v:Dot( north )

		r = r or 0

		table.insert( pts, { mx - r, my - r } )
		table.insert( pts, { mx + r, my + r } )
	end

	Add( brief.start, SkyOps.Conv.FromMeters( 2000 ) )

	for _, wp in ipairs( brief.waypoints or {} ) do Add( wp.pos, SkyOps.Conv.FromMeters( wp.radius or 1500 ) ) end
	for _, t in ipairs( brief.targets or {} ) do Add( t.pos, SkyOps.Conv.FromMeters( 1500 ) ) end

	-- У угроз в рамку попадает сама позиция и малая часть зоны, чтобы карта не стала мелкой из-за С-75
	for _, t in ipairs( brief.threats or {} ) do Add( t.pos, SkyOps.Conv.FromMeters( math.min( t.range or 0, 12000 ) ) ) end

	if #pts == 0 then
		pts = { { -1, -1 }, { 1, 1 } }
	end

	local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge

	for _, p in ipairs( pts ) do
		minX, maxX = math.min( minX, p[1] ), math.max( maxX, p[1] )
		minY, maxY = math.min( minY, p[2] ), math.max( maxY, p[2] )
	end

	local pad = UI.S( 40 )

	self.cx, self.cy = (minX + maxX) / 2, (minY + maxY) / 2
	self.scale = math.min( (w - pad * 2) / math.max( maxX - minX, 1 ), (h - pad * 2) / math.max( maxY - minY, 1 ) )
	self.w, self.h = w, h
end

function MAP:Project( p )
	local v = C().ToVector( p )
	local mx, my = v:Dot( self.east ), v:Dot( self.north )

	return self.w / 2 + (mx - self.cx) * self.scale, self.h / 2 - (my - self.cy) * self.scale
end

function MAP:Paint( w, h )
	local brief = C().brief

	UI.Box( 0, 0, w, h, UI.C.map )

	-- сетка
	local step = UI.S( 50 )

	surface.SetDrawColor( UI.C.grid )

	for x = 0, w, step do surface.DrawLine( x, 0, x, h ) end
	for y = 0, h, step do surface.DrawLine( 0, y, w, y ) end

	if not brief then return end

	self:Setup( brief, w, h )

	local t2 = UI.S( 2 )

	-- зоны поражения
	for _, threat in ipairs( brief.threats or {} ) do
		if threat.range then
			local x, y = self:Project( threat.pos )
			local r = SkyOps.Conv.FromMeters( threat.range ) * self.scale
			local long = threat.range > 20000

			UI.FilledCircle( x, y, r, Color( 255, 107, 94, long and 14 or 24 ), 64 )
			UI.Circle( x, y, r, t2, UI.C.threat, 64, long )
		end
	end

	-- маршрут
	local route = {}

	if brief.start then table.insert( route, { self:Project( brief.start ) } ) end

	for _, wp in ipairs( brief.waypoints or {} ) do
		table.insert( route, { self:Project( wp.pos ) } )
	end

	if brief.start and #route > 1 then table.insert( route, { self:Project( brief.start ) } ) end

	for i = 1, #route - 1 do
		UI.Line( route[ i ][1], route[ i ][2], route[ i + 1 ][1], route[ i + 1 ][2], t2, UI.C.accent )
	end

	-- аэродром
	if brief.start then
		local x, y = self:Project( brief.start )
		local s = UI.S( 14 )

		UI.Box( x - s, y - s * 0.85, s * 2, s * 1.7, UI.C.bg )
		UI.Outline( x - s, y - s * 0.85, s * 2, s * 1.7, UI.C.text, t2 )
		UI.Text( "АЭРОДРОМ", "SkyOps_TextSmall", x + s + UI.S( 6 ), y + s * 0.3, UI.C.text )
	end

	-- точки маршрута
	for _, wp in ipairs( brief.waypoints or {} ) do
		local x, y = self:Project( wp.pos )
		local r = UI.S( 7 )

		UI.FilledCircle( x, y, r, UI.C.bg, 20 )
		UI.Circle( x, y, r, t2, UI.C.accent, 20 )

		local label = wp.label and (wp.id .. " / " .. wp.label) or wp.id

		UI.Text( label, "SkyOps_TextSmall", x + r + UI.S( 6 ), y - UI.S( 8 ), UI.C.accent )
	end

	-- цели
	for _, target in ipairs( brief.targets or {} ) do
		local x, y = self:Project( target.pos )
		local s = UI.S( 5 )

		for i = 0, math.min( (target.count or 1) - 1, 7 ) do
			UI.Box( x - s + i * s * 1.3, y - s + i * s * 1.0, s * 2, s * 2, UI.C.threat )
		end

		UI.Text( "ЦЕЛЬ: " .. string.upper( target.label or target.id ), "SkyOps_TextSmall", x - UI.S( 10 ), y - UI.S( 30 ), UI.C.threat, TEXT_ALIGN_RIGHT )
	end

	-- угрозы
	for _, threat in ipairs( brief.threats or {} ) do
		local x, y = self:Project( threat.pos )
		local s = UI.S( 8 )

		surface.SetDrawColor( UI.C.threat )
		draw.NoTexture()
		surface.DrawPoly( { { x = x, y = y - s }, { x = x + s, y = y + s * 0.8 }, { x = x - s, y = y + s * 0.8 } } )

		UI.Text( threat.label or threat.system or "?", "SkyOps_TextSmall", x + s + UI.S( 4 ), y - UI.S( 2 ), UI.C.threat )
	end

	-- север и масштаб
	local nx, ny = w - UI.S( 40 ), UI.S( 30 )

	UI.Line( nx, ny + UI.S( 30 ), nx, ny, t2, UI.C.muted )
	UI.Line( nx - UI.S( 7 ), ny + UI.S( 10 ), nx, ny, t2, UI.C.muted )
	UI.Line( nx + UI.S( 7 ), ny + UI.S( 10 ), nx, ny, t2, UI.C.muted )
	UI.Text( "С", "SkyOps_TextSmall", nx, ny + UI.S( 34 ), UI.C.muted, TEXT_ALIGN_CENTER )

	local kmPx = SkyOps.Conv.FromMeters( 1000 ) * self.scale
	local nice = 1

	for _, n in ipairs( { 1, 2, 5, 10, 20, 50, 100 } ) do
		if n * kmPx <= w * 0.25 then nice = n end
	end

	local sx, sy = UI.S( 30 ), h - UI.S( 40 )

	UI.Line( sx, sy, sx + nice * kmPx, sy, t2, UI.C.muted )
	UI.Line( sx, sy - UI.S( 5 ), sx, sy + UI.S( 5 ), t2, UI.C.muted )
	UI.Line( sx + nice * kmPx, sy - UI.S( 5 ), sx + nice * kmPx, sy + UI.S( 5 ), t2, UI.C.muted )
	UI.Text( nice .. " км", "SkyOps_TextSmall", sx, sy + UI.S( 8 ), UI.C.muted )

	if brief.todoAnchors and #brief.todoAnchors > 0 then
		UI.Text( "Координаты точек примерные, карта схематичная", "SkyOps_Label", w - UI.S( 16 ), h - UI.S( 24 ), UI.C.muted, TEXT_ALIGN_RIGHT )
	end
end

vgui.Register( "SkyOpsBriefingMap", MAP, "Panel" )

---------------------------------------------------------------------------
-- Экран брифинга
---------------------------------------------------------------------------

local BRIEF = {}

function BRIEF:Init()
	self:SetSize( ScrW(), ScrH() )
	self:SetPos( 0, 0 )
	self:MakePopup()
	self:SetKeyboardInputEnabled( false )

	local S = UI.S

	self.headerH = S( 72 )
	self.leftW = S( 470 )
	self.rightW = S( 430 )

	self.map = vgui.Create( "SkyOpsBriefingMap", self )
	self.map:SetPos( self.leftW, self.headerH )
	self.map:SetSize( ScrW() - self.leftW - self.rightW, ScrH() - self.headerH )

	self.right = vgui.Create( "Panel", self )
	self.right:SetPos( ScrW() - self.rightW, self.headerH )
	self.right:SetSize( self.rightW, ScrH() - self.headerH )
	self.right.Paint = function( pnl, w, h ) self:PaintRight( w, h ) end

	self.close = UI.Button( self, "СВЕРНУТЬ", "ghost", function()
		self:Remove()

		chat.AddText( UI.C.accent, "[SkyOps] ", UI.C.text, "Брифинг свёрнут. Открыть снова: skyops_briefing" )
	end )
	self.close:SetSize( S( 120 ), S( 32 ) )
	self.close:SetPos( ScrW() - S( 152 ), S( 20 ) )

	self:Rebuild()

	hook.Add( "SkyOps.LobbyChanged", self, function() self:Rebuild() end )
	hook.Add( "SkyOps.BriefReceived", self, function() self:Rebuild() end )
end

function BRIEF:Rebuild()
	local S = UI.S
	local client = C()
	local brief = client.brief
	local lobby = client.lobby

	for _, child in ipairs( self.right:GetChildren() ) do child:Remove() end

	if not brief or not lobby then return end

	local myFlight, mySeat = client.MySeat()
	local pad = S( 28 )
	local w = self.rightW - pad * 2
	local y = S( 24 )

	self.rowY = {}

	for i, flight in ipairs( lobby.flights or {} ) do
		local ac = brief.aircraft[ flight.aircraft ] or {}
		local canPick = (flight.pilotId == nil or myFlight == i and mySeat == M.SEAT_PILOT) and #brief.aircraft > 1

		self.rowY[ i ] = y

		-- выбор самолёта (листается кнопками)
		if canPick then
			local prev = UI.Button( self.right, "<", "ghost", function()
				local idx = flight.aircraft - 1

				if idx < 1 then idx = #brief.aircraft end

				client.RequestSeat( i, M.SEAT_PILOT, idx )
			end )
			prev:SetSize( S( 28 ), S( 26 ) )
			prev:SetPos( pad + w - S( 60 ), y )

			local nxt = UI.Button( self.right, ">", "ghost", function()
				local idx = flight.aircraft + 1

				if idx > #brief.aircraft then idx = 1 end

				client.RequestSeat( i, M.SEAT_PILOT, idx )
			end )
			nxt:SetSize( S( 28 ), S( 26 ) )
			nxt:SetPos( pad + w - S( 28 ), y )
		end

		y = y + S( 36 )

		local seats = { { M.SEAT_PILOT, flight.pilot, flight.pilotId, flight.pilotReady } }

		if (flight.crew or 2) >= 2 then
			table.insert( seats, { M.SEAT_WSO, flight.wso, flight.wsoId, flight.wsoReady } )
		end

		for _, s in ipairs( seats ) do
			local seat, name, id = s[1], s[2], s[3]
			local mine = IsValid( LocalPlayer() ) and id == LocalPlayer():UserID()

			if mine then
				local btn = UI.Button( self.right, "ОСВОБОДИТЬ", "ghost", function() client.RequestSeat( 0, 0, 0 ) end )
				btn:SetSize( S( 110 ), S( 30 ) )
				btn:SetPos( pad + w - S( 124 ), y + S( 13 ) )
			elseif not name then
				local btn = UI.Button( self.right, "ЗАНЯТЬ", "ghost", function() client.RequestSeat( i, seat, 0 ) end )
				btn:SetSize( S( 110 ), S( 30 ) )
				btn:SetPos( pad + w - S( 124 ), y + S( 13 ) )
			end

			y = y + S( 64 )
		end

		y = y + S( 14 )
	end

	self.loadoutY = y

	if myFlight then
		local ready = mySeat == M.SEAT_PILOT and lobby.flights[ myFlight ].pilotReady or lobby.flights[ myFlight ].wsoReady
		local btn = UI.Button( self.right, ready and "ОТМЕНИТЬ ГОТОВНОСТЬ" or "ГОТОВ К ВЫЛЕТУ", ready and "ghost" or "primary", function()
			client.SetReady( not ready )
		end )

		btn.Font = "SkyOps_Button"
		btn:SetSize( w, S( 56 ) )
		btn:SetPos( pad, self.right:GetTall() - S( 84 ) )
	end
end

function BRIEF:PaintRight( w, h )
	local S = UI.S
	local client = C()
	local brief, lobby = client.brief, client.lobby

	UI.Box( 0, 0, 1, h, UI.C.line )

	if not brief or not lobby then return end

	local pad = S( 28 )
	local bw = w - pad * 2

	for i, flight in ipairs( lobby.flights or {} ) do
		local ac = brief.aircraft[ flight.aircraft ] or {}
		local y = self.rowY and self.rowY[ i ] or 0

		UI.Text( flight.callsign .. " · " .. (ac.name or ac.role or "?"), "SkyOps_H2", pad, y, UI.C.text )

		y = y + S( 36 )

		local seats = { { M.SEAT_PILOT, flight.pilot, flight.pilotReady } }

		if (flight.crew or 2) >= 2 then table.insert( seats, { M.SEAT_WSO, flight.wso, flight.wsoReady } ) end

		for _, s in ipairs( seats ) do
			UI.Box( pad, y, bw, S( 56 ), UI.C.panel )
			UI.Outline( pad, y, bw, S( 56 ), UI.C.line )
			UI.Text( SeatName( ac.role, s[1] ), "SkyOps_Label", pad + S( 14 ), y + S( 10 ), UI.C.muted )
			UI.Text( s[2] or "свободно", "SkyOps_Text", pad + S( 14 ), y + S( 28 ), s[2] and UI.C.text or UI.C.muted )

			if s[2] then
				UI.Text( s[3] and "ГОТОВ" or "ВЫБИРАЕТ", "SkyOps_TextSmall", pad + bw - S( 136 ), y + S( 21 ), s[3] and UI.C.ok or UI.C.accent, TEXT_ALIGN_RIGHT )
			end

			y = y + S( 64 )
		end
	end

	-- подвеска своего самолёта (или первого)
	local myFlight = client.MySeat() or 1
	local flight = lobby.flights[ myFlight ]
	local ac = flight and brief.aircraft[ flight.aircraft ]
	local y = (self.loadoutY or S( 300 )) + S( 10 )

	if ac and ac.loadoutText then
		y = UI.Kicker( "ПОДВЕСКА · " .. string.upper( ac.name or "" ), pad, y )

		for _, line in ipairs( ac.loadoutText ) do
			UI.Text( line, "SkyOps_Text", pad, y, UI.C.text )
			y = y + S( 24 )
		end
	end

	-- отсчёт
	local passed = CurTime() - client.lobbyTime
	local text

	if lobby.launchIn then
		text = "Вылет через " .. UI.FormatTime( lobby.launchIn - passed + 1 )
	else
		text = "Брифинг: " .. UI.FormatTime( lobby.briefEndsIn - passed ) .. " · вылет, когда все готовы"
	end

	UI.Text( text, "SkyOps_TextSmall", w / 2, h - S( 112 ), lobby.launchIn and UI.C.accent or UI.C.muted, TEXT_ALIGN_CENTER )
end

function BRIEF:Paint( w, h )
	local S = UI.S
	local brief = C().brief

	UI.Box( 0, 0, w, h, UI.C.bg )

	if not brief then
		UI.Text( "Ожидание брифинга...", "SkyOps_H1", w / 2, h / 2, UI.C.muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER )

		return
	end

	-- шапка
	UI.Box( 0, self.headerH - 1, w, 1, UI.C.line )

	local kw = UI.Text( "SKYOPS // БРИФИНГ", "SkyOps_Kicker", S( 32 ), S( 28 ), UI.C.accent )

	UI.Text( string.upper( brief.name or "" ), "SkyOps_Title", S( 32 ) + kw + S( 24 ), S( 16 ), UI.C.text )

	local info = {}
	local b = brief.briefing or {}

	if b.time then table.insert( info, "ВРЕМЯ: " .. b.time ) end
	if b.weather then table.insert( info, "ПОГОДА: " .. string.upper( b.weather ) ) end

	UI.Text( table.concat( info, "     " ), "SkyOps_TextSmall", w - S( 180 ), S( 28 ), UI.C.muted, TEXT_ALIGN_RIGHT )

	-- левая колонка
	local pad = S( 28 )
	local cw = self.leftW - pad * 2
	local y = self.headerH + S( 24 )

	UI.Box( self.leftW - 1, self.headerH, 1, h - self.headerH, UI.C.line )

	y = UI.Kicker( "ТИП ЗАДАНИЯ", pad, y )
	UI.Text( brief.typeName or "", "SkyOps_H2", pad, y, UI.C.accent )
	y = y + S( 40 )

	if b.situation then
		y = UI.Kicker( "ОБСТАНОВКА", pad, y )

		for _, line in ipairs( UI.Wrap( b.situation, "SkyOps_Text", cw ) ) do
			UI.Text( line, "SkyOps_Text", pad, y, UI.C.text )
			y = y + S( 24 )
		end

		y = y + S( 16 )
	end

	y = UI.Kicker( "ЗАДАЧИ", pad, y )

	for i, obj in ipairs( brief.objectives or {} ) do
		local col = obj.optional and UI.C.muted or UI.C.text

		UI.Text( tostring( i ), "SkyOps_Text", pad, y, obj.optional and UI.C.muted or UI.C.accent )

		for _, line in ipairs( UI.Wrap( obj.text, "SkyOps_Text", cw - S( 26 ) ) ) do
			UI.Text( line, "SkyOps_Text", pad + S( 26 ), y, col )
			y = y + S( 24 )
		end

		y = y + S( 4 )
	end

	y = y + S( 12 )

	if #(brief.threats or {}) > 0 then
		y = UI.Kicker( "УГРОЗЫ", pad, y )

		for _, threat in ipairs( brief.threats ) do
			UI.Text( threat.label or threat.system or "?", "SkyOps_Text", pad, y, UI.C.text )

			local right = threat.range and string.format( "ДАЛЬН. ~%d км", math.Round( threat.range / 1000 ) ) or ("× " .. (threat.count or 1))

			UI.Text( right, "SkyOps_Text", pad + cw, y, UI.C.threat, TEXT_ALIGN_RIGHT )
			y = y + S( 26 )
		end
	end
end

vgui.Register( "SkyOpsBriefing", BRIEF, "EditablePanel" )

function UI.OpenBriefing()
	if IsValid( UI.BriefingPanel ) then
		UI.BriefingPanel:Rebuild()

		return
	end

	UI.BriefingPanel = vgui.Create( "SkyOpsBriefing" )
end

function UI.CloseBriefing()
	if IsValid( UI.BriefingPanel ) then UI.BriefingPanel:Remove() end
end

---------------------------------------------------------------------------
-- Список миссий (для администратора)
---------------------------------------------------------------------------

function UI.OpenMissionList()
	if IsValid( UI.MissionList ) then UI.MissionList:Remove() end

	local S = UI.S
	local frame = vgui.Create( "EditablePanel" )

	frame:SetSize( S( 560 ), S( 520 ) )
	frame:Center()
	frame:MakePopup()
	frame.Paint = function( pnl, w, h )
		UI.Box( 0, 0, w, h, UI.C.bg )
		UI.Outline( 0, 0, w, h, UI.C.line )
		UI.Text( "SKYOPS // МИССИИ", "SkyOps_Kicker", S( 24 ), S( 22 ), UI.C.accent )
	end

	UI.MissionList = frame

	local close = UI.Button( frame, "ЗАКРЫТЬ", "ghost", function() frame:Remove() end )
	close:SetSize( S( 110 ), S( 30 ) )
	close:SetPos( frame:GetWide() - S( 134 ), S( 16 ) )

	local scroll = vgui.Create( "DScrollPanel", frame )
	scroll:SetPos( S( 24 ), S( 64 ) )
	scroll:SetSize( frame:GetWide() - S( 48 ), frame:GetTall() - S( 88 ) )

	local function Fill()
		scroll:Clear()

		for _, mission in ipairs( C().list or {} ) do
			local btn = scroll:Add( "DButton" )

			btn:SetText( "" )
			btn:Dock( TOP )
			btn:DockMargin( 0, 0, 0, S( 8 ) )
			btn:SetTall( S( 64 ) )
			btn.Paint = function( pnl, w, h )
				UI.Box( 0, 0, w, h, pnl:IsHovered() and UI.C.line or UI.C.panel )
				UI.Text( mission.typeName or "", "SkyOps_Label", S( 14 ), S( 10 ), UI.C.accent )
				UI.Text( mission.name or mission.id, "SkyOps_H2", S( 14 ), S( 28 ), UI.C.text )

				return true
			end
			btn.DoClick = function()
				RunConsoleCommand( "skyops_mission_start", mission.id )
				frame:Remove()
			end
		end
	end

	Fill()

	hook.Add( "SkyOps.MissionListChanged", frame, Fill )
end
