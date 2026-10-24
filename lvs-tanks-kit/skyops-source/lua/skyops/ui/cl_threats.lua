-- SkyOps: метки ПВО прямо на экране (client)
-- Чтобы на огромной карте на скорости найти зенитку, поверх обзора рисуем ромб над
-- каждым известным комплексом: тип и дальность. Если он вне поля зрения, у края
-- экрана стрелка в его сторону.
-- Источники: разведданные брифинга (известные позиции ЗРК миссии) и СПО (кто нас
-- облучает сейчас, плюс летящие на нас ракеты). Комплексы, идущие с колонной, есть только
-- в СПО: их стартовая позиция из брифинга быстро устаревает.
-- Выключить: skyops_hud_threats 0. Дальность показа: skyops_hud_threats_range (км).

SkyOps = SkyOps or {}
SkyOps.HUD = SkyOps.HUD or {}

local UI = SkyOps.UI
local M = SkyOps.Missions
local U = SkyOps.Conv

local cvThreats = CreateClientConVar( "skyops_hud_threats", "1", true, false, "Метки ПВО на экране" )
local cvRange = CreateClientConVar( "skyops_hud_threats_range", "80", true, false, "Дальность показа меток ПВО, км" )

local NAMES = {
	s75 = "С-75", tor_m1 = "ТОР", osa = "ОСА", roland = "ROLAND", aaa = "ЗА",
	fighter = "ИСТР", missile = "РАКЕТА", unknown = "ПВО",
}

local MERGE_DIST = 1500 -- м: живой контакт СПО ближе этого к разведданным считается тем же комплексом

local COL_INTEL = Color( 242, 169, 59 )
local COL_SEARCH = Color( 255, 196, 107 )
local COL_THREAT = Color( 255, 107, 94 )

-- Список меток: { pos (клиентская), name, state (nil = молчит, только разведка) }
local function Collect()
	local client = SkyOps.Client
	local RWR = SkyOps.RWR
	local list = {}

	if client and client.brief and client.state == M.STATE_RUNNING then
		for _, t in ipairs( client.brief.threats or {} ) do
			if t.kind == "airdefense" and t.pos and not t.moving and not (client.unitDown and client.unitDown[ t.id ]) then
				local pos = client.WorldToLocal( client.ToVector( t.pos ) )
				local dup = false

				-- части одного комплекса (РЛС, пусковые) показываем одной меткой
				for _, m in ipairs( list ) do
					if m.system == t.system and U.ToMeters( m.pos:Distance( pos ) ) < MERGE_DIST then dup = true break end
				end

				if not dup then
					table.insert( list, { pos = pos, name = NAMES[ t.system ] or NAMES.unknown, system = t.system } )
				end
			end
		end
	end

	if RWR and RWR.GetAll then
		for _, c in ipairs( RWR.GetAll() ) do
			local pos = IsValid( c.ent ) and c.ent:GetPos() or c.pos
			local merged = false

			if c.system ~= "missile" and c.system ~= "fighter" then
				for _, m in ipairs( list ) do
					if U.ToMeters( m.pos:Distance( pos ) ) < MERGE_DIST then
						m.state = math.max( m.state or -1, c.state )
						merged = true
					end
				end
			end

			if not merged then
				table.insert( list, { pos = pos, name = NAMES[ c.system ] or NAMES.unknown, system = c.system, state = c.state } )
			end
		end
	end

	return list
end

local function MarkColor( m, blink )
	if m.state == nil then return COL_INTEL end
	if m.state >= SkyOps.RWR.STATE_LAUNCH then return blink and COL_THREAT or Color( 255, 107, 94, 90 ) end
	if m.state >= SkyOps.RWR.STATE_TRACK then return COL_THREAT end

	return COL_SEARCH
end

local function StateText( m, ru )
	if m.state == nil then return ru and "РАЗВЕДКА" or "INTEL" end
	if m.state >= SkyOps.RWR.STATE_LAUNCH then return ru and "ПУСК!" or "LAUNCH!" end
	if m.state >= SkyOps.RWR.STATE_TRACK then return ru and "СОПРОВОЖДЕНИЕ" or "TRACK" end

	return ru and "ОБЗОР" or "SEARCH"
end

local function Diamond( x, y, r, t, col )
	UI.Line( x, y - r, x + r, y, t, col )
	UI.Line( x + r, y, x, y + r, t, col )
	UI.Line( x, y + r, x - r, y, t, col )
	UI.Line( x - r, y, x, y - r, t, col )
end

-- Стрелка у края экрана, указывает в сторону метки
local function EdgeArrow( m, rel, col, label )
	local S = UI.S
	local cx, cy = ScrW() / 2, ScrH() / 2
	local rx, ry = cx - S( 70 ), cy - S( 70 )
	local ang = math.atan2( rel.y, rel.x )
	local ex, ey = cx + math.cos( ang ) * rx, cy + math.sin( ang ) * ry
	local dx, dy = math.cos( ang ), math.sin( ang )
	local px, py = -dy, dx
	local len, wid = S( 22 ), S( 11 )

	UI.Line( ex + dx * len, ey + dy * len, ex + px * wid, ey + py * wid, 3, col )
	UI.Line( ex + dx * len, ey + dy * len, ex - px * wid, ey - py * wid, 3, col )
	UI.Line( ex + px * wid, ey + py * wid, ex - px * wid, ey - py * wid, 2, col )

	UI.Text( label, "SkyOps_HUDSmall", ex - dx * S( 26 ), ey - dy * S( 26 ), col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER )
end

hook.Add( "HUDPaint", "SkyOps.Threats", function()
	if not cvThreats:GetBool() or not SkyOps.HUD.GetContext then return end

	local ply, veh, role = SkyOps.HUD.GetContext()

	if not ply or not IsValid( veh ) then return end

	local def = SkyOps.HUD.Aircraft[ role ] or SkyOps.HUD.Aircraft.generic or {}
	local ru = def.profile ~= "nato"
	local S = UI.S
	local eye = EyePos()
	local ea = EyeAngles()
	local fwd, right, up = ea:Forward(), ea:Right(), ea:Up()
	local myPos = veh:GetPos()
	local maxDist = cvRange:GetFloat() * 1000
	local blink = math.floor( RealTime() * 4 ) % 2 == 0
	local margin = S( 40 )

	for _, m in ipairs( Collect() ) do
		local dist = U.ToMeters( m.pos:Distance( myPos ) )

		if dist <= maxDist or m.state ~= nil then
			local col = MarkColor( m, blink )
			local distText = ru and string.format( "%.1f км", dist / 1000 ) or string.format( "%.1f NM", dist / 1852 )
			local dir = m.pos - eye
			-- проецируем направление, а не саму точку: на InfMap до цели могут быть сотни км
			local scr = (eye + dir:GetNormalized() * 1000):ToScreen()
			local onScreen = dir:Dot( fwd ) > 0 and scr.visible and scr.x > margin and scr.x < ScrW() - margin and scr.y > margin and scr.y < ScrH() - margin

			if onScreen then
				local x, y = scr.x, scr.y
				local r = S( m.system == "missile" and 10 or 14 )
				local t = (m.state or 0) >= 1 and 3 or 2

				if m.system == "missile" then
					UI.Circle( x, y, r, t, col, 20 )
				else
					Diamond( x, y, r, t, col )
				end

				if m.state == nil then
					-- молчащий по разведданным: пунктирное кольцо вокруг ромба
					UI.Circle( x, y, r + S( 6 ), 1, col, 24, true )
				end

				UI.Text( m.name, "SkyOps_HUDSmall", x, y - r - S( 4 ), col, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM )
				UI.Text( distText, "SkyOps_HUDSmall", x, y + r + S( 4 ), col, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP )

				if m.state ~= nil then
					UI.Text( StateText( m, ru ), "SkyOps_Label", x, y + r + S( 24 ), col, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP )
				end
			else
				-- проекция направления на плоскость экрана: x вправо, y вниз
				local rel = { x = dir:Dot( right ), y = -dir:Dot( up ) }

				if math.abs( rel.x ) + math.abs( rel.y ) < 1 then rel.y = 1 end

				EdgeArrow( m, rel, col, m.name .. " " .. distText )
			end
		end
	end
end )
