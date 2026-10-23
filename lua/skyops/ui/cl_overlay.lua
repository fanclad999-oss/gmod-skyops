-- SkyOps: игровой оверлей миссии (client)
-- Список задач слева вверху и радиообмен справа. Это не часть HUD самолёта, поэтому
-- рисуется в стиле интерфейса (панели), а не символикой. Скрыть: skyops_hud_objectives 0

SkyOps = SkyOps or {}
SkyOps.HUD = SkyOps.HUD or {}

local HUD = SkyOps.HUD
local UI = SkyOps.UI
local M = SkyOps.Missions

local cvObjectives = CreateClientConVar( "skyops_hud_objectives", "1", true, false, "Показывать список задач и радио во время миссии" )

local MESSAGE_TIME = 14

local function PaintObjectives()
	local client = SkyOps.Client

	if not client or client.state ~= M.STATE_RUNNING or not client.brief then return end

	local S = UI.S
	local x, y = S( 32 ), S( 32 )
	local w = S( 360 )
	local list = client.Objectives()
	local lineH = S( 22 )
	local h = S( 40 ) + #list * lineH

	UI.Box( x, y, w, h, UI.C.panelAlpha )
	UI.Outline( x, y, w, h, UI.C.line )
	UI.Text( "ЗАДАЧИ · " .. UI.FormatTime( CurTime() - (client.startTime or CurTime()) ), "SkyOps_Label", x + S( 16 ), y + S( 12 ), UI.C.muted )

	local iy = y + S( 32 )

	for _, obj in ipairs( list ) do
		local mark, markCol, textCol = "○", UI.C.muted, UI.C.muted

		if obj.state == M.OBJ_DONE then
			mark, markCol = "✓", UI.C.ok
		elseif obj.state == M.OBJ_FAILED then
			mark, markCol, textCol = "✕", UI.C.threat, UI.C.threat
		elseif obj.state == M.OBJ_ACTIVE then
			mark, markCol, textCol = "▸", UI.C.accent, UI.C.text
		end

		local text = obj.text

		if obj.state == M.OBJ_ACTIVE and obj.progressText then text = text .. " · " .. obj.progressText end

		-- длинные строки обрезаем, чтобы панель не разъезжалась
		surface.SetFont( "SkyOps_TextSmall" )

		if surface.GetTextSize( text ) > w - S( 52 ) then
			while #text > 0 and surface.GetTextSize( text .. "…" ) > w - S( 52 ) do
				text = string.sub( text, 1, (utf8.offset( text, -1 ) or #text) - 1 )
			end

			text = text .. "…"
		end

		UI.Text( mark, "SkyOps_TextSmall", x + S( 16 ), iy, markCol )
		UI.Text( text, "SkyOps_TextSmall", x + S( 36 ), iy, textCol )

		iy = iy + lineH
	end
end

local function PaintRadio()
	local client = SkyOps.Client

	if not client or #client.messages == 0 then return end

	local S = UI.S
	local now = CurTime()
	local visible = {}

	for _, msg in ipairs( client.messages ) do
		if now - msg.time < MESSAGE_TIME then table.insert( visible, msg ) end
	end

	if #visible == 0 then return end

	local w = S( 460 )
	local lineH = S( 22 )
	local h = S( 20 ) + #visible * lineH
	local x = ScrW() - S( 32 ) - w
	local y = S( 140 )

	UI.Box( x, y, w, h, UI.C.panelAlpha )
	UI.Outline( x, y, w, h, UI.C.line )

	local iy = y + S( 10 )

	for _, msg in ipairs( visible ) do
		local alpha = math.Clamp( (MESSAGE_TIME - (now - msg.time)) / 2, 0, 1 ) * 255
		local sw = UI.Text( msg.sender .. ": ", "SkyOps_TextSmall", x + S( 16 ), iy, Color( 242, 169, 59, alpha ) )

		UI.Text( msg.text, "SkyOps_TextSmall", x + S( 16 ) + sw, iy, Color( 216, 222, 226, alpha ) )

		iy = iy + lineH
	end
end

hook.Add( "HUDPaint", "SkyOps.Overlay", function()
	if not cvObjectives:GetBool() then return end

	PaintObjectives()
	PaintRadio()
end )

-- Подсказка о брифинге для тех, кто его свернул
hook.Add( "HUDPaint", "SkyOps.BriefingHint", function()
	local client = SkyOps.Client

	if not client or client.state ~= M.STATE_BRIEFING or IsValid( SkyOps.UI.BriefingPanel ) then return end

	UI.Text( "Идёт брифинг: skyops_briefing", "SkyOps_Text", ScrW() / 2, UI.S( 24 ), UI.C.accent, TEXT_ALIGN_CENTER )
end )
