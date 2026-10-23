-- SkyOps: станция предупреждения об облучении (СПО / RWR) (client)
-- Источники:
--   1. сообщение ядра skyops_rwr: какие РЛС ПВО нас ищут, сопровождают или пустили ракету
--   2. запасной вариант: видимые клиенту комплексы ПВО и истребители противника по дальности
--   3. ракеты, летящие на нас (по скорости и направлению, для ракет SW Bombs и LVS)

SkyOps = SkyOps or {}
SkyOps.RWR = SkyOps.RWR or {}

local RWR = SkyOps.RWR
local UI = SkyOps.UI
local U = SkyOps.Conv

local cvPilotScope = CreateClientConVar( "skyops_hud_rwr", "1", true, false, "Показывать индикатор СПО у пилота" )

RWR.STATE_SEARCH = 0
RWR.STATE_TRACK = 1
RWR.STATE_LAUNCH = 2

-- Обозначения на индикаторе: русская школа и NATO (номера по классификации SA)
RWR.Codes = {
	ru = { s75 = "75", tor_m1 = "ТР", osa = "ОС", roland = "РЛ", aaa = "А", fighter = "И", unknown = "Н", missile = "Р" },
	nato = { s75 = "2", tor_m1 = "15", osa = "8", roland = "RO", aaa = "A", fighter = "F", unknown = "U", missile = "M" },
}

RWR.Contacts = RWR.Contacts or {}   -- от ядра: key -> { pos, system, state, time }
RWR.Estimated = RWR.Estimated or {} -- запасной поиск
RWR.Missiles = RWR.Missiles or {}

-- Формат от ядра: UInt(8) количество, затем на каждый контакт: Vector мировая позиция, String система, UInt(2) состояние
net.Receive( "skyops_rwr", function()
	local count = net.ReadUInt( 8 )
	local now = CurTime()

	for i = 1, count do
		local pos = net.ReadVector()
		local system = net.ReadString()
		local state = net.ReadUInt( 2 )

		RWR.Contacts[ system .. "@" .. math.floor( pos.x / 2000 ) .. ":" .. math.floor( pos.y / 2000 ) ] = { pos = pos, system = system, state = state, time = now }
	end
end )

local function MyVehicle()
	local ply = LocalPlayer()

	return IsValid( ply ) and ply.lvsGetVehicle and ply:lvsGetVehicle() or nil
end

local function ScanAirDefense( veh )
	local list = {}
	local reg = SkyOps.Registry and SkyOps.Registry.AirDefense or {}
	local myTeam = veh.GetAITEAM and veh:GetAITEAM() or 0
	local myPos = veh:GetPos()
	local ranges = SkyOps.Missions and SkyOps.Missions.ThreatRange or {}

	for system, data in pairs( reg ) do
		for _, ent in ipairs( ents.FindByClass( data.spawn ) ) do
			if IsValid( ent ) and (not ent.GetAITEAM or ent:GetAITEAM() ~= myTeam) then
				local dist = U.ToMeters( (ent:GetPos() - myPos):Length() )
				local range = ranges[ system ] or 10000

				-- РЛС слышно дальше, чем бьёт ракета
				if dist < range * 2 then
					table.insert( list, { ent = ent, pos = ent:GetPos(), system = system, state = dist < range * 0.8 and RWR.STATE_TRACK or RWR.STATE_SEARCH, estimated = true } )
				end
			end
		end
	end

	if LVS and LVS.GetVehicles then
		for _, v in pairs( LVS:GetVehicles() ) do
			if IsValid( v ) and v ~= veh and v.GetThrottle and v.GetAITEAM and v:GetAITEAM() ~= myTeam then
				local dist = U.ToMeters( (v:GetPos() - myPos):Length() )

				if dist < 40000 then
					table.insert( list, { ent = v, pos = v:GetPos(), system = "fighter", state = dist < 12000 and RWR.STATE_TRACK or RWR.STATE_SEARCH, estimated = true } )
				end
			end
		end
	end

	return list
end

local function IsProjectile( ent )
	if ent.lvsProjectile or ent.lvsMissile then return true end

	local class = ent:GetClass()

	return string.find( class, "rocket", 1, true ) ~= nil or string.find( class, "missile", 1, true ) ~= nil
end

local function ScanMissiles( veh )
	local list = {}
	local myPos = veh:GetPos()
	local myVel = veh:GetVelocity()

	for _, ent in ipairs( ents.FindInSphere( myPos, U.FromMeters( 10000 ) ) ) do
		if IsValid( ent ) and ent ~= veh and IsProjectile( ent ) then
			local targeted = false

			if ent.GetNWTarget and ent:GetNWTarget() == veh then targeted = true end
			if ent.target == veh or ent.Target == veh then targeted = true end

			if not targeted then
				-- летит на нас: быстро, сближается и смотрит в нашу сторону
				local rel = myPos - ent:GetPos()
				local vel = ent:GetVelocity()
				local speed = U.ToMps( vel:Length() )

				if speed > 150 and vel:GetNormalized():Dot( rel:GetNormalized() ) > 0.94 and (vel - myVel):Dot( rel ) > 0 then
					targeted = true
				end
			end

			if targeted then table.insert( list, { ent = ent, pos = ent:GetPos(), system = "missile", state = RWR.STATE_LAUNCH } ) end
		end
	end

	return list
end

local nextScan, nextMissileScan = 0, 0

hook.Add( "Think", "SkyOps.RWR", function()
	local veh = MyVehicle()

	if not IsValid( veh ) then
		RWR.Estimated, RWR.Missiles = {}, {}

		return
	end

	local T = CurTime()

	if T > nextScan then
		nextScan = T + 0.5
		RWR.Estimated = ScanAirDefense( veh )

		for key, c in pairs( RWR.Contacts ) do
			if T - c.time > 2.5 then RWR.Contacts[ key ] = nil end
		end
	end

	if T > nextMissileScan then
		nextMissileScan = T + 0.15

		local before = #RWR.Missiles

		RWR.Missiles = ScanMissiles( veh )

		if #RWR.Missiles > before then surface.PlaySound( "buttons/blip2.wav" ) end
	end
end )

function RWR.IncomingCount()
	local n = #RWR.Missiles

	for _, c in pairs( RWR.Contacts ) do
		if c.state == RWR.STATE_LAUNCH then n = n + 1 end
	end

	return n
end

-- Все контакты для индикатора. Позиции у ядра мировые, у локального поиска клиентские.
function RWR.GetAll()
	local all = {}
	local client = SkyOps.Client
	local haveCore = next( RWR.Contacts ) ~= nil

	for _, c in pairs( RWR.Contacts ) do
		table.insert( all, { pos = client and client.WorldToLocal( c.pos ) or c.pos, system = c.system, state = c.state } )
	end

	-- запасной поиск ПВО не дублируем, если данные пришли от ядра
	for _, c in ipairs( RWR.Estimated ) do
		if not haveCore or c.system == "fighter" then table.insert( all, c ) end
	end

	for _, c in ipairs( RWR.Missiles ) do table.insert( all, c ) end

	return all
end

-- Индикатор: круг, нос самолёта вверх, ближе к центру = опаснее
function RWR.Paint( x, y, size, veh, profile )
	local codes = RWR.Codes[ profile ] or RWR.Codes.nato
	local r = size / 2
	local cx, cy = x + r, y + r
	local col = Color( 125, 255, 154 )
	local threat = UI.C.threat
	local blink = math.floor( RealTime() * 4 ) % 2 == 0

	UI.FilledCircle( cx, cy, r, Color( 8, 12, 14, 215 ), 48 )
	UI.Circle( cx, cy, r, 1, UI.C.line, 48 )
	UI.Circle( cx, cy, r * 0.62, 1, Color( 59, 73, 80 ), 48 )
	UI.Circle( cx, cy, r * 0.28, 1, Color( 59, 73, 80 ), 32 )

	surface.SetDrawColor( Color( 59, 73, 80 ) )
	surface.DrawLine( cx, y + 4, cx, y + size - 4 )
	surface.DrawLine( x + 4, cy, x + size - 4, cy )

	UI.Line( cx - 5, cy, cx + 5, cy, 2, UI.C.text )
	UI.Line( cx, cy - 5, cx, cy + 5, 2, UI.C.text )

	if not IsValid( veh ) then return end

	local myPos = veh:GetPos()
	local myYaw = veh:GetAngles().y
	local ranges = SkyOps.Missions and SkyOps.Missions.ThreatRange or {}

	for _, c in ipairs( RWR.GetAll() ) do
		local d = c.pos - myPos
		local rel = math.rad( myYaw - d:Angle().y ) -- >0: цель справа
		local dist = U.ToMeters( d:Length() )
		local norm

		if c.system == "missile" then
			norm = 0.18
		else
			local range = ranges[ c.system ] or 15000

			norm = math.Clamp( dist / (range * 2), 0.3, 0.92 )
		end

		local px = cx + math.sin( rel ) * r * norm
		local py = cy - math.cos( rel ) * r * norm
		local code = codes[ c.system ] or codes.unknown
		local isThreat = c.state >= RWR.STATE_TRACK
		local ccol = isThreat and threat or col

		if c.state ~= RWR.STATE_LAUNCH or blink then
			UI.Text( code, "SkyOps_HUDSmall", px, py, ccol, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER )
		end

		if c.state == RWR.STATE_TRACK then
			local w, h = UI.TextSize( code, "SkyOps_HUDSmall" )

			UI.Outline( px - w / 2 - 3, py - h / 2 - 1, w + 6, h + 2, ccol, 2 )
		elseif c.state == RWR.STATE_LAUNCH then
			UI.Circle( px, py, UI.S( 12 ), 2, threat, 20 )
		end
	end
end

-- Индикатор у пилота: в левом нижнем углу, как прибор на приборной доске
hook.Add( "HUDPaint", "SkyOps.RWR.Pilot", function()
	if not cvPilotScope:GetBool() or not SkyOps.HUD or not SkyOps.HUD.GetContext then return end

	local ply, ent, role, seat = SkyOps.HUD.GetContext()

	if not ply or seat ~= "pilot" then return end

	local def = SkyOps.HUD.Aircraft[ role ] or SkyOps.HUD.Aircraft.generic
	local size = UI.S( 200 )

	RWR.Paint( UI.S( 32 ), ScrH() - size - UI.S( 32 ), size, ent, def.profile )

	local label = def.profile == "ru" and "СПО" or "RWR"

	UI.Text( label, "SkyOps_Label", UI.S( 32 ) + size + UI.S( 8 ), ScrH() - UI.S( 32 ) - UI.S( 16 ), UI.C.muted )
end )
