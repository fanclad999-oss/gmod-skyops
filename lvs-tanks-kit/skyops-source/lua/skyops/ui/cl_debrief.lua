-- SkyOps: экран итогов миссии (client)

SkyOps = SkyOps or {}
SkyOps.UI = SkyOps.UI or {}

local UI = SkyOps.UI
local M = SkyOps.Missions

local SEAT_NAME = { pilot = "ПИЛОТ", wso = "ШО" }

local DEBRIEF = {}

function DEBRIEF:Init()
	local S = UI.S

	self:SetSize( ScrW(), ScrH() )
	self:MakePopup()
	self:SetKeyboardInputEnabled( false )

	local close = UI.Button( self, "ЗАКРЫТЬ", "ghost", function() self:Remove() end )
	close.Font = "SkyOps_Button"
	close:SetSize( S( 180 ), S( 52 ) )
	close:SetPos( ScrW() - S( 64 ) - S( 180 ), ScrH() - S( 48 ) - S( 52 ) )

	if LocalPlayer():IsAdmin() then
		local again = UI.Button( self, "ПОВТОРИТЬ", "ghost", function() RunConsoleCommand( "skyops_mission_restart" ) end )
		again.Font = "SkyOps_Button"
		again:SetSize( S( 180 ), S( 52 ) )
		again:SetPos( ScrW() - S( 64 ) - S( 376 ), ScrH() - S( 48 ) - S( 52 ) )

		local nextBtn = UI.Button( self, "ДРУГАЯ МИССИЯ", "primary", function()
			self:Remove()
			RunConsoleCommand( "skyops_missions" )
		end )
		nextBtn:SetSize( S( 220 ), S( 52 ) )
		nextBtn:SetPos( ScrW() - S( 64 ) - S( 612 ), ScrH() - S( 48 ) - S( 52 ) )
	end
end

function DEBRIEF:Paint( w, h )
	local S = UI.S
	local d = SkyOps.Client.debrief

	UI.Box( 0, 0, w, h, UI.C.bg )

	if not d then return end

	local x, y = S( 64 ), S( 48 )

	UI.Text( "SKYOPS // ИТОГИ", "SkyOps_Kicker", x, y, UI.C.accent )
	y = y + S( 30 )

	local tw = UI.Text( string.upper( d.name or "" ), "SkyOps_Title", x, y, UI.C.text )

	UI.Text( d.success and "ЗАДАЧА ВЫПОЛНЕНА" or "ЗАДАЧА НЕ ВЫПОЛНЕНА", "SkyOps_H1", x + tw + S( 28 ), y + S( 6 ), d.success and UI.C.ok or UI.C.threat )
	y = y + S( 52 )

	local sub = "Время в воздухе " .. UI.FormatTime( d.time )

	if d.reason then sub = sub .. " · " .. d.reason end

	UI.Text( sub, "SkyOps_TextSmall", x, y, UI.C.muted )
	y = y + S( 44 )

	local colW = (w - S( 64 ) * 2 - S( 32 )) / 2
	local boxH = h - y - S( 140 )

	-- задачи
	UI.Box( x, y, colW, boxH, UI.C.panel )
	UI.Outline( x, y, colW, boxH, UI.C.line )

	local iy = UI.Kicker( "ЗАДАЧИ", x + S( 28 ), y + S( 28 ) )

	for _, obj in ipairs( d.objectives or {} ) do
		local status, col

		if obj.state == M.OBJ_DONE then
			status, col = "ВЫПОЛНЕНО", UI.C.ok
		elseif obj.state == M.OBJ_FAILED then
			status, col = "ПРОВАЛЕНО", UI.C.threat
		else
			status, col = "НЕ ВЫПОЛНЕНО", UI.C.accent
		end

		if obj.progressText and obj.state ~= M.OBJ_DONE then status = status .. " · " .. obj.progressText end

		UI.Text( obj.text, "SkyOps_Text", x + S( 28 ), iy, obj.optional and UI.C.muted or UI.C.text )
		UI.Text( status, "SkyOps_Text", x + colW - S( 28 ), iy, col, TEXT_ALIGN_RIGHT )
		iy = iy + S( 34 )
	end

	UI.Box( x + S( 28 ), y + boxH - S( 80 ), colW - S( 56 ), 1, UI.C.line )
	UI.Text( "ОЦЕНКА · " .. (d.score or 0) .. " очков", "SkyOps_TextSmall", x + S( 28 ), y + boxH - S( 52 ), UI.C.muted )
	UI.Text( d.grade or "-", "SkyOps_Title", x + colW - S( 28 ), y + boxH - S( 64 ), UI.C.accent, TEXT_ALIGN_RIGHT )

	-- экипажи
	local cx = x + colW + S( 32 )

	UI.Box( cx, y, colW, boxH, UI.C.panel )
	UI.Outline( cx, y, colW, boxH, UI.C.line )

	iy = UI.Kicker( "ЭКИПАЖИ", cx + S( 28 ), y + S( 28 ) )

	for _, flight in ipairs( d.flights or {} ) do
		local reg = SkyOps.Registry and SkyOps.Registry.GetAircraft and SkyOps.Registry.GetAircraft( flight.role )

		UI.Text( flight.callsign .. " · " .. (reg and reg.name or flight.role or ""), "SkyOps_H2", cx + S( 28 ), iy, UI.C.text )

		local hp = math.Clamp( flight.hp or 0, 0, 1 )
		local hpText, hpCol = "цел", UI.C.ok

		if hp <= 0 then
			hpText, hpCol = "потерян", UI.C.threat
		elseif hp < 0.5 then
			hpText, hpCol = "тяжёлые повреждения", UI.C.threat
		elseif hp < 0.95 then
			hpText, hpCol = "лёгкие повреждения", UI.C.accent
		end

		UI.Text( hpText, "SkyOps_Text", cx + colW - S( 28 ), iy + S( 4 ), hpCol, TEXT_ALIGN_RIGHT )
		iy = iy + S( 40 )

		for _, member in ipairs( flight.crew or {} ) do
			UI.Text( SEAT_NAME[ member.seat ] or member.seat, "SkyOps_Label", cx + S( 28 ), iy + S( 3 ), UI.C.muted )
			UI.Text( member.name or "?", "SkyOps_Text", cx + S( 110 ), iy, UI.C.text )
			UI.Text( "уничтожено: " .. (member.kills or 0), "SkyOps_Text", cx + colW - S( 28 ), iy, UI.C.text, TEXT_ALIGN_RIGHT )
			iy = iy + S( 30 )
		end

		iy = iy + S( 18 )
	end
end

vgui.Register( "SkyOpsDebrief", DEBRIEF, "EditablePanel" )

function UI.OpenDebrief()
	if IsValid( UI.DebriefPanel ) then UI.DebriefPanel:Remove() end

	-- Небольшая пауза, чтобы игроки увидели момент выполнения последней задачи
	timer.Simple( 2, function()
		if not SkyOps.Client.debrief then return end

		UI.DebriefPanel = vgui.Create( "SkyOpsDebrief" )
	end )
end

function UI.CloseDebrief()
	if IsValid( UI.DebriefPanel ) then UI.DebriefPanel:Remove() end
end
