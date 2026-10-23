-- SkyOps: рабочее место штурмана-оператора / оператора РЛС (client)
-- Справа внизу многофункциональный индикатор (МФИ) с тактической обстановкой «курс вверх»,
-- слева от него большой индикатор СПО. Сверху повторитель параметров полёта.
-- Прицельные оверлеи LVS (FLIR и т.п.) рисуются под ним; МФИ можно скрыть: skyops_mfd

SkyOps = SkyOps or {}
SkyOps.HUD = SkyOps.HUD or {}

local HUD = SkyOps.HUD
local UI = SkyOps.UI
local U = SkyOps.Conv
local M = SkyOps.Missions

local cvMfd = CreateClientConVar( "skyops_mfd_show", "1", true, false, "Показывать МФИ на месте штурмана" )
local cvRange = CreateClientConVar( "skyops_mfd_range", "40", true, false, "Масштаб МФИ, км" )

local RANGES = { 10, 20, 40, 80 }

concommand.Add( "skyops_mfd", function()
	cvMfd:SetBool( not cvMfd:GetBool() )
end )

concommand.Add( "skyops_mfd_zoom", function()
	local cur = cvRange:GetInt()
	local nextRange = RANGES[1]

	for i, r in ipairs( RANGES ) do
		if r == cur then nextRange = RANGES[ i % #RANGES + 1 ] end
	end

	cvRange:SetInt( nextRange )
end )

local SEAT_TITLE = {
	wso = { ru = "ШТУРМАН-ОПЕРАТОР", nato = "WSO" },
	rio = { ru = "ОПЕРАТОР РЛС", nato = "RIO" },
}

local function PaintTactical( f, x, y, size )
	local client = SkyOps.Client
	local brief = client and client.brief
	local ru = f.profile == "ru"
	local rangeKm = cvRange:GetInt()
	local scale = size / 2 / U.FromMeters( rangeKm * 1000 )
	local cx, cy = x + size / 2, y + size * 0.62
	local yaw = f.ang.y

	UI.Box( x, y, size, size, Color( 8, 12, 14, 225 ) )
	UI.Outline( x, y, size, size, UI.C.line, 2 )

	render.SetScissorRect( x + 2, y + 2, x + size - 2, y + size - 2, true )

	-- курс вверх: поворачиваем мир на текущий курс
	local function ToScreen( localPos )
		local d = localPos - f.pos
		local a = math.rad( yaw - d:Angle().y )
		local dist = Vector( d.x, d.y, 0 ):Length() * scale

		return cx + math.sin( a ) * dist, cy - math.cos( a ) * dist
	end

	-- кольца дальности
	for i = 1, 2 do
		UI.Circle( cx, cy, size / 4 * i, 1, Color( 42, 52, 59 ), 64, true )
	end

	if brief then
		local W = client.WorldToLocal
		local V = client.ToVector

		for _, threat in ipairs( brief.threats or {} ) do
			if threat.range then
				local px, py = ToScreen( W( V( threat.pos ) ) )
				local r = U.FromMeters( threat.range ) * scale

				UI.Circle( px, py, r, 2, Color( 255, 107, 94, 170 ), 48, threat.range > 20000 )
				UI.Text( threat.label or threat.system, "SkyOps_Label", px, py, UI.C.threat, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER )
			end
		end

		local prev

		if brief.start then prev = { ToScreen( W( V( brief.start ) ) ) } end

		local steer = client.SteerpointWaypoint()

		for _, wp in ipairs( brief.waypoints or {} ) do
			local px, py = ToScreen( W( V( wp.pos ) ) )

			if prev then UI.Line( prev[1], prev[2], px, py, 2, Color( 242, 169, 59, 160 ) ) end

			local active = steer and steer.id == wp.id

			UI.Circle( px, py, UI.S( active and 9 or 6 ), 2, UI.C.accent, 16 )
			UI.Text( wp.id, "SkyOps_Label", px + UI.S( 10 ), py - UI.S( 7 ), UI.C.accent )

			prev = { px, py }
		end

		for _, target in ipairs( brief.targets or {} ) do
			local px, py = ToScreen( W( V( target.pos ) ) )
			local s = UI.S( 5 )

			UI.Box( px - s, py - s, s * 2, s * 2, UI.C.threat )
			UI.Text( string.upper( target.label or target.id ), "SkyOps_Label", px + s * 2, py - s, UI.C.threat )
		end
	end

	-- свои самолёты
	if LVS and LVS.GetVehicles then
		local myTeam = f.ent.GetAITEAM and f.ent:GetAITEAM() or 0

		for _, v in pairs( LVS:GetVehicles() ) do
			if IsValid( v ) and v ~= f.ent and v.GetThrottle and v.GetAITEAM and v:GetAITEAM() == myTeam then
				local px, py = ToScreen( v:GetPos() )

				UI.Circle( px, py, UI.S( 5 ), 2, Color( 120, 200, 255 ), 12 )
			end
		end
	end

	render.SetScissorRect( 0, 0, 0, 0, false )

	-- свой самолёт
	local s = UI.S( 10 )

	UI.Line( cx, cy - s, cx - s * 0.8, cy + s * 0.8, 2, UI.C.text )
	UI.Line( cx, cy - s, cx + s * 0.8, cy + s * 0.8, 2, UI.C.text )
	UI.Line( cx - s * 0.8, cy + s * 0.8, cx + s * 0.8, cy + s * 0.8, 2, UI.C.text )

	-- подписи
	local pad = UI.S( 10 )

	UI.Text( string.format( (ru and "КУРС %03d" or "HDG %03d"), math.Round( f.heading ) % 360 ), "SkyOps_HUDSmall", cx, y + pad, UI.C.text, TEXT_ALIGN_CENTER )
	UI.Text( rangeKm .. (ru and " км" or " km"), "SkyOps_Label", x + size - pad, y + pad, UI.C.muted, TEXT_ALIGN_RIGHT )

	local steer = client and client.SteerpointWaypoint()

	if steer then
		local d = client.WorldToLocal( client.ToVector( steer.pos ) ) - f.pos
		local brg = (f.northYaw - d:Angle().y) % 360
		local dist = U.ToMeters( Vector( d.x, d.y, 0 ):Length() )
		local text = ru and string.format( "ППМ %s  %03d°  %.1f км", steer.id, brg, dist / 1000 ) or string.format( "STPT %s  %03d  %.1f NM", steer.id, brg, dist / 1852 )

		UI.Text( text, "SkyOps_HUDSmall", x + pad, y + size - pad, UI.C.accent, TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM )
	end
end

function HUD.PaintWSO( f )
	if not cvMfd:GetBool() then return end

	local ru = f.profile == "ru"
	local size = UI.S( 420 )
	local margin = UI.S( 32 )
	local x = ScrW() - margin - size
	local y = ScrH() - margin - size

	-- повторитель параметров полёта
	local rep

	if ru then
		rep = string.format( "V %d км/ч   H %d м   M %.2f   n %.1f", math.Round( f.ias * 3.6 ), math.Round( f.alt / 10 ) * 10, f.mach, f.g )
	else
		rep = string.format( "IAS %d kt   ALT %d ft   M %.2f   G %.1f", math.Round( f.ias * 1.943844 ), math.Round( f.alt * 3.28084 / 10 ) * 10, f.mach, f.g )
	end

	local title = (SEAT_TITLE[ f.seat ] or SEAT_TITLE.wso)[ f.profile ] or "WSO"

	UI.Text( title, "SkyOps_Label", x, y - UI.S( 44 ), UI.C.muted )
	UI.Text( rep, "SkyOps_HUDSmall", x, y - UI.S( 26 ), UI.C.text )

	PaintTactical( f, x, y, size )

	-- большой индикатор СПО слева от МФИ
	if SkyOps.RWR and SkyOps.RWR.Paint then
		local rs = UI.S( 260 )

		SkyOps.RWR.Paint( x - rs - UI.S( 20 ), ScrH() - margin - rs, rs, f.ent, f.profile )
	end

	-- оружие места штурмана (свой обработчик оружия на втором кресле)
	local pod = f.ply:GetVehicle()
	local base = IsValid( pod ) and pod.lvsGetWeapon and pod:lvsGetWeapon()
	local info = IsValid( base ) and HUD.WeaponInfo( base ) or HUD.WeaponInfo( f.ent )

	if info then
		local ammo = info.ammo >= 0 and ("  " .. info.ammo) or ""

		UI.Text( (ru and "ОРУЖИЕ  " or "WPN  ") .. info.name .. ammo, "SkyOps_HUDSmall", x + size, y - UI.S( 26 ), UI.C.accent, TEXT_ALIGN_RIGHT )
	end
end

HUD.Painters = HUD.Painters or {}
HUD.Painters.wso = HUD.PaintWSO
