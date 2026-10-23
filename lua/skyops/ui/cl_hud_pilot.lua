-- SkyOps: HUD пилота (client)
-- Две школы символики:
--   ru   — Су-34, Су-25СМ3: км/ч (приборная), метры, «самолётик», лестница через 10°, шкала крена
--   nato — Tornado IDS, F-14A: узлы, футы, ватерлиния W, лестница через 5°, пунктир ниже горизонта
-- Горизонт, лестница тангажа, вектор скорости, ППМ и CCIP конформны: строятся проекцией направлений
-- в мире на экран, поэтому совпадают с реальным горизонтом и в кабине, и с внешней камеры.

SkyOps = SkyOps or {}
SkyOps.HUD = SkyOps.HUD or {}

local HUD = SkyOps.HUD
local UI = SkyOps.UI
local U = SkyOps.Conv
local M = SkyOps.Missions

local R = 200000 -- расстояние до точки проекции направления (юниты)

local TEXT = {
	ru = {
		nav = "НАВ", ground = "БОМБ", air = "В-В",
		missile = "РАКЕТА", pullup = "ОПАСНАЯ ВЫСОТА", gear = "УБЕРИ ШАССИ", damage = "ПОВРЕЖДЕНИЕ",
		wp = "ППМ", radalt = "Р", vs = "Vy", delay = "ЖДИ",
	},
	nato = {
		nav = "NAV", ground = "CCIP", air = "A-A",
		missile = "MISSILE", pullup = "PULL UP", gear = "GEAR", damage = "DAMAGE",
		wp = "STPT", radalt = "R", vs = "VV", delay = "DELAY",
	},
}

-- Текущие настройки отрисовки на кадр
local col, shadow, t2, doShadow

local function SetColors()
	col = HUD.Color()
	shadow = Color( 0, 0, 0, 110 )
	t2 = math.max( UI.S( 2 ), 2 )
	doShadow = HUD.ShadowEnabled()
end

local function L( x1, y1, x2, y2, t )
	t = t or t2

	if doShadow then UI.Line( x1 + 1, y1 + 1, x2 + 1, y2 + 1, t, shadow ) end

	UI.Line( x1, y1, x2, y2, t, col )
end

local function DL( x1, y1, x2, y2, dash, gap )
	if doShadow then UI.DashedLine( x1 + 1, y1 + 1, x2 + 1, y2 + 1, t2, dash, gap, shadow ) end

	UI.DashedLine( x1, y1, x2, y2, t2, dash, gap, col )
end

local function T( text, font, x, y, ax, ay, c )
	if doShadow then draw.SimpleText( text, font, x + 1, y + 1, shadow, ax, ay ) end

	return draw.SimpleText( text, font, x, y, c or col, ax or TEXT_ALIGN_LEFT, ay or TEXT_ALIGN_TOP )
end

local function Circ( x, y, r, dashed )
	if doShadow then UI.Circle( x + 1, y + 1, r, t2, shadow, nil, dashed ) end

	UI.Circle( x, y, r, t2, col, nil, dashed )
end

local function Box( x, y, w, h )
	L( x, y, x + w, y )
	L( x + w, y, x + w, y + h )
	L( x + w, y + h, x, y + h )
	L( x, y + h, x, y )
end

-- Направление в мире -> экран
local function Proj( dir )
	local p = (EyePos() + dir * R):ToScreen()

	return p.x, p.y, p.visible
end

local function Normalize2( x, y )
	local l = math.sqrt( x * x + y * y )

	if l < 0.0001 then return 1, 0 end

	return x / l, y / l
end

---------------------------------------------------------------------------
-- CCIP: точка падения бомбы при сбросе сейчас (бомбы LVS летят без сопротивления воздуха)
---------------------------------------------------------------------------

local ccip = {}

local function UpdateCCIP( ent )
	local T0 = RealTime()

	if ccip.ent == ent and (ccip.next or 0) > T0 then return ccip end

	ccip.ent = ent
	ccip.next = T0 + 0.08

	local grav = physenv.GetGravity()
	local pos = ent:GetPos()
	local vel = ent:GetVelocity()
	local dt = 0.1
	local filter = function( e ) return e ~= ent and e:GetParent() ~= ent and not e:IsPlayer() end

	ccip.hit = nil

	for i = 1, 400 do
		local nextVel = vel + grav * dt
		local nextPos = pos + (vel + nextVel) * 0.5 * dt

		local tr = util.TraceLine( { start = pos, endpos = nextPos, mask = MASK_SOLID, filter = filter } )

		if tr.Hit then
			ccip.hit = tr.HitPos
			ccip.tof = (i - 1) * dt + dt * tr.Fraction

			break
		end

		pos, vel = nextPos, nextVel
	end

	if ccip.hit then ccip.range = U.ToMeters( (ccip.hit - ent:GetPos()):Length() ) end

	return ccip
end

---------------------------------------------------------------------------
-- Цель в режиме воздух-воздух: ближайший к оси самолёт противника в конусе
---------------------------------------------------------------------------

local function FindAirTarget( f )
	if not LVS or not LVS.GetVehicles then return nil end

	local myTeam = f.ent.GetAITEAM and f.ent:GetAITEAM() or 0
	local best, bestDot = nil, math.cos( math.rad( 12 ) )

	for _, v in pairs( LVS:GetVehicles() ) do
		if IsValid( v ) and v ~= f.ent and v.GetThrottle and v.GetAITEAM and v:GetAITEAM() ~= myTeam then
			local d = v:GetPos() - f.pos
			local dist = U.ToMeters( d:Length() )

			if dist < 15000 then
				local dot = d:GetNormalized():Dot( f.fwd )

				if dot > bestDot then best, bestDot = v, dot end
			end
		end
	end

	return best
end

---------------------------------------------------------------------------
-- Отрисовка
---------------------------------------------------------------------------

function HUD.PaintPilot( f )
	SetColors()

	local P = f.profile
	local tx = TEXT[ P ] or TEXT.nato
	local ru = P == "ru"

	local bx, by, bvis = Proj( f.fwd )

	if not bvis then return end

	-- пикселей на градус по реальной проекции
	local ux, uy = Proj( (f.fwd + f.up * math.tan( math.rad( 10 ) )):GetNormalized() )
	local ppdReal = math.sqrt( (ux - bx) ^ 2 + (uy - by) ^ 2 ) / 10
	local ppd = math.Clamp( ppdReal, UI.S( 14 ), UI.S( 48 ) )

	local left, right = bx - 13 * ppd, bx + 13 * ppd
	local top, bottom = by - 10 * ppd, by + 13 * ppd

	-- ===== конформная часть: горизонт и лестница =====
	render.SetScissorRect( left, top + 2.4 * ppd, right, bottom, true )

	local yaw = f.ang.y
	local hright = Angle( 0, yaw - 90, 0 ):Forward()
	local step = ru and 10 or 5
	local gap = (ru and 1.6 or 2.2) * ppdReal
	local len = (ru and 4.5 or 4.5) * ppdReal
	local tick = 0.8 * ppdReal

	local p0 = math.floor( f.pitch / step ) * step

	for th = p0 - step * 3, p0 + step * 3, step do
		if th >= -90 and th <= 90 then
			local dir = Angle( -th, yaw, 0 ):Forward()
			local cx, cy, vis = Proj( dir )

			if vis then
				local x2, y2 = Proj( (dir + hright * 0.05):GetNormalized() )
				local ax, ay = Normalize2( x2 - cx, y2 - cy )
				local dx, dy = -ay, ax -- «вниз» в системе лестницы

				if th == 0 then
					local hl = 12 * ppdReal

					L( cx - ax * hl, cy - ay * hl, cx - ax * gap * 1.2, cy - ay * gap * 1.2 )
					L( cx + ax * gap * 1.2, cy + ay * gap * 1.2, cx + ax * hl, cy + ay * hl )
				else
					local toHorizon = th > 0 and 1 or -1

					for _, side in ipairs( { -1, 1 } ) do
						local sx, sy = cx + ax * gap * side, cy + ay * gap * side
						local ex, ey = cx + ax * (gap + len) * side, cy + ay * (gap + len) * side

						if th > 0 then
							L( sx, sy, ex, ey )
						else
							DL( sx, sy, ex, ey, 0.8 * ppdReal, 0.5 * ppdReal )
						end

						-- засечки на концах смотрят на горизонт
						L( ex, ey, ex + dx * tick * toHorizon, ey + dy * tick * toHorizon )

						if not ru or side == 1 then
							local lx = ex + ax * 0.9 * ppdReal * side
							local ly = ey + ay * 0.9 * ppdReal * side

							T( tostring( math.abs( th ) ), "SkyOps_HUDSmall", lx, ly, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER )
						end
					end
				end
			end
		end
	end

	render.SetScissorRect( 0, 0, 0, 0, false )

	-- ===== символ самолёта на оси =====
	if ru then
		local r = 0.45 * ppd

		Circ( bx, by, r )
		L( bx - 3 * ppd, by, bx - r, by )
		L( bx + r, by, bx + 3 * ppd, by )
		L( bx, by - r, bx, by - 1.1 * ppd )
	else
		local s = ppd

		L( bx - 2.6 * s, by, bx - 1.3 * s, by )
		L( bx - 1.3 * s, by, bx - 0.65 * s, by + 0.8 * s )
		L( bx - 0.65 * s, by + 0.8 * s, bx, by )
		L( bx, by, bx + 0.65 * s, by + 0.8 * s )
		L( bx + 0.65 * s, by + 0.8 * s, bx + 1.3 * s, by )
		L( bx + 1.3 * s, by, bx + 2.6 * s, by )
	end

	-- ===== вектор скорости =====
	local fx, fy, fvis

	if f.tas > 20 then
		fx, fy, fvis = Proj( f.vel:GetNormalized() )

		if fvis then
			local caged = false

			if fx < left + ppd or fx > right - ppd or fy < top + 3 * ppd or fy > bottom - ppd then
				caged = true
				fx = math.Clamp( fx, left + ppd, right - ppd )
				fy = math.Clamp( fy, top + 3 * ppd, bottom - ppd )
			end

			if not caged or math.floor( RealTime() * 4 ) % 2 == 0 then
				local r = 0.55 * ppd

				Circ( fx, fy, r )
				L( fx - (ru and 1.6 or 1.9) * ppd, fy, fx - r, fy )
				L( fx + r, fy, fx + (ru and 1.6 or 1.9) * ppd, fy )
				L( fx, fy - r, fx, fy - (ru and 1.0 or 1.2) * ppd )
			end
		end
	end

	-- ===== шкала крена =====
	do
		local cx, cy = bx, bottom - 5.5 * ppd
		local r = 5 * ppd

		for _, a in ipairs( { -60, -45, -30, -20, -10, 0, 10, 20, 30, 45, 60 } ) do
			local rad = math.rad( 90 + a )
			local long = a == 0 or math.abs( a ) == 30 or math.abs( a ) == 60
			local r2 = r + (long and 0.8 or 0.45) * ppd

			L( cx + math.cos( rad ) * r, cy + math.sin( rad ) * r, cx + math.cos( rad ) * r2, cy + math.sin( rad ) * r2 )
		end

		local roll = math.Clamp( f.roll, -70, 70 )
		local rad = math.rad( 90 - roll )
		local px, py = cx + math.cos( rad ) * (r - 0.15 * ppd), cy + math.sin( rad ) * (r - 0.15 * ppd)
		local tx2, ty2 = math.cos( rad + 0.08 ) * (r - 0.9 * ppd), math.sin( rad + 0.08 ) * (r - 0.9 * ppd)
		local tx3, ty3 = math.cos( rad - 0.08 ) * (r - 0.9 * ppd), math.sin( rad - 0.08 ) * (r - 0.9 * ppd)

		L( px, py, cx + tx2, cy + ty2 )
		L( px, py, cx + tx3, cy + ty3 )
		L( cx + tx2, cy + ty2, cx + tx3, cy + ty3 )
	end

	-- ===== шкала курса =====
	local client = SkyOps.Client
	local wp = client and client.SteerpointWaypoint()
	local wpLocal, wpBrg, wpDist

	if wp then
		wpLocal = client.WorldToLocal( client.ToVector( wp.pos ) )

		local d = wpLocal - f.pos

		wpBrg = (f.northYaw - d:Angle().y) % 360
		wpDist = U.ToMeters( Vector( d.x, d.y, 0 ):Length() )
	end

	do
		local ty = top + 0.4 * ppd
		local half = 10
		local scale = 0.9 * ppd

		render.SetScissorRect( bx - (half + 0.5) * scale, ty - ppd, bx + (half + 0.5) * scale, ty + 3 * ppd, true )

		local h0 = math.floor( (f.heading - half - 5) / 5 ) * 5

		for h = h0, h0 + half * 2 + 10, 5 do
			local x = bx + (h - f.heading) * scale
			local major = h % 10 == 0

			L( x, ty + 1.3 * ppd, x, ty + 1.3 * ppd + (major and 0.7 or 0.35) * ppd )

			if major then
				T( string.format( "%02d", (h % 360) / 10 ), "SkyOps_HUDSmall", x, ty + 1.2 * ppd, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM )
			end
		end

		-- метка направления на ППМ
		if wpBrg then
			local diff = (wpBrg - f.heading + 540) % 360 - 180
			local x = bx + math.Clamp( diff, -half, half ) * scale

			L( x - 0.35 * ppd, ty + 2.4 * ppd, x, ty + 2.0 * ppd )
			L( x, ty + 2.0 * ppd, x + 0.35 * ppd, ty + 2.4 * ppd )
			L( x - 0.35 * ppd, ty + 2.4 * ppd, x + 0.35 * ppd, ty + 2.4 * ppd )
		end

		render.SetScissorRect( 0, 0, 0, 0, false )

		-- индекс текущего курса
		L( bx, ty + 2.0 * ppd, bx - 0.4 * ppd, ty + 2.6 * ppd )
		L( bx, ty + 2.0 * ppd, bx + 0.4 * ppd, ty + 2.6 * ppd )

		if ru then
			T( string.format( "%03d", math.Round( f.heading ) % 360 ), "SkyOps_HUD", bx, ty + 2.7 * ppd, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP )
		end
	end

	-- ===== скорость и высота =====
	local font = "SkyOps_HUD"
	local small = "SkyOps_HUDSmall"
	local bw, bh = 4.6 * ppd, 1.5 * ppd
	local sx, sy = left + 0.5 * ppd, by - bh / 2
	local ax2 = right - 0.5 * ppd - bw

	local speedText, altText

	if ru then
		speedText = tostring( math.Round( f.ias * 3.6 / 5 ) * 5 )
		altText = tostring( math.Round( f.alt / 10 ) * 10 )
	else
		speedText = tostring( math.Round( f.ias * 1.943844 ) )
		altText = tostring( math.Round( f.alt * 3.28084 / 10 ) * 10 )
	end

	Box( sx, sy, bw, bh )
	T( speedText, font, sx + bw - 0.4 * ppd, by, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER )

	Box( ax2, sy, bw, bh )
	T( altText, font, ax2 + bw - 0.4 * ppd, by, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER )

	local ly = sy + bh + 0.6 * ppd
	local lh = 1.15 * ppd

	T( string.format( "M %.2f", f.mach ), small, sx, ly )
	T( string.format( "G %.1f", f.g ), small, sx, ly + lh )

	if f.role == "f14a" then
		T( string.format( "α %.1f", f.aoa ), small, sx, ly + lh * 2 )
	end

	if ru then
		T( string.format( "%s %+d", tx.vs, math.Round( f.vs ) ), small, ax2, ly )
	else
		T( string.format( "%s %+d", tx.vs, math.Round( f.vs * 196.85 / 10 ) * 10 ), small, ax2, ly )
	end

	if f.agl then
		local agl = ru and f.agl or f.agl * 3.28084

		if agl < f.def.radalt then
			T( string.format( "%s %d", tx.radalt, math.Round( agl ) ), small, ax2, ly + lh )
		end
	end

	-- ===== ППМ =====
	if wp and wpLocal then
		local dir = (wpLocal - EyePos()):GetNormalized()
		local wx, wy, wvis = Proj( dir )

		if wvis and wx > left and wx < right and wy > top and wy < bottom then
			local s = 0.7 * ppd

			L( wx, wy - s, wx + s, wy )
			L( wx + s, wy, wx, wy + s )
			L( wx, wy + s, wx - s, wy )
			L( wx - s, wy, wx, wy - s )
		end

		local gs = math.max( U.ToMps( Vector( f.vel.x, f.vel.y, 0 ):Length() ), 1 )
		local eta = wpDist / gs
		local distText = ru and string.format( "%.1f км", wpDist / 1000 ) or string.format( "%.1f NM", wpDist / 1852 )

		T( tx.wp .. " " .. wp.id, small, ax2, ly + lh * 2.4 )
		T( distText .. "  " .. UI.FormatTime( eta ), small, ax2, ly + lh * 3.4 )
	end

	-- ===== режим и оружие =====
	local mode = HUD.WeaponMode( f.ent )
	local modeText = mode == HUD.MODE_GROUND and tx.ground or (mode == HUD.MODE_AIR and tx.air or tx.nav)

	T( modeText, font, left + 0.5 * ppd, bottom - 1.6 * ppd )

	local weapon = HUD.WeaponInfo( f.ent )

	if weapon then
		local ammo = weapon.ammo >= 0 and ("  " .. weapon.ammo) or ""

		T( weapon.name .. ammo, small, left + 0.5 * ppd, bottom - 0.4 * ppd )
	end

	-- ===== прицеливание =====
	if mode == HUD.MODE_GROUND then
		local c = UpdateCCIP( f.ent )

		if c.hit then
			local px, py, pvis = Proj( (c.hit - EyePos()):GetNormalized() )

			if pvis then
				local delayed = py > bottom - ppd
				local cpx, cpy = px, math.min( py, bottom - ppd )
				local r = 0.9 * ppd

				-- линия падения от вектора скорости к марке
				if fx and fvis then
					local ddx, ddy = Normalize2( cpx - fx, cpy - fy )

					L( fx + ddx * 0.6 * ppd, fy + ddy * 0.6 * ppd, cpx - ddx * r, cpy - ddy * r )
				end

				if delayed then
					DL( cpx - r, cpy, cpx + r, cpy, 0.3 * ppd, 0.2 * ppd )
					T( tx.delay, small, cpx + r * 1.4, cpy, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER )
				else
					Circ( cpx, cpy, r )

					if ru then
						L( cpx - r * 1.6, cpy, cpx - r, cpy )
						L( cpx + r, cpy, cpx + r * 1.6, cpy )
						L( cpx, cpy + r, cpx, cpy + r * 1.6 )
					else
						UI.FilledCircle( cpx, cpy, math.max( t2, 2 ), col, 10 )
					end
				end

				local rangeText = ru and string.format( "Д %.1f", c.range / 1000 ) or string.format( "%.1f NM", c.range / 1852 )

				T( rangeText, small, right - 0.5 * ppd, bottom - 1.6 * ppd, TEXT_ALIGN_RIGHT )
				T( string.format( "%.1f с", c.tof ), small, right - 0.5 * ppd, bottom - 0.4 * ppd, TEXT_ALIGN_RIGHT )
			end
		end
	elseif mode == HUD.MODE_AIR then
		Circ( bx, by, (ru and 3 or 2.5) * ppd, true )

		local target = FindAirTarget( f )

		if IsValid( target ) then
			local tp = target:LocalToWorld( target:OBBCenter() ):ToScreen()

			if tp.visible then
				local s = 0.9 * ppd

				Box( tp.x - s, tp.y - s, s * 2, s * 2 )

				local dist = U.ToMeters( (target:GetPos() - f.pos):Length() )
				local rangeText = ru and string.format( "Д %.1f", dist / 1000 ) or string.format( "%.1f", dist / 1852 )

				T( rangeText, small, tp.x + s * 1.3, tp.y - s )
				T( rangeText, small, right - 0.5 * ppd, bottom - 1.6 * ppd, TEXT_ALIGN_RIGHT )
			end
		end
	end

	-- ===== предупреждения =====
	local warn = {}
	local rwr = SkyOps.RWR

	if rwr and rwr.IncomingCount and rwr.IncomingCount() > 0 then table.insert( warn, tx.missile ) end

	if f.agl and f.vs < -5 and f.agl / -f.vs < 5 and not f.gearDown then table.insert( warn, tx.pullup ) end

	if f.gearDown and f.ias * 3.6 > (ru and f.def.gearSpeed or f.def.gearSpeed * 1.852) then table.insert( warn, tx.gear ) end

	if f.hp < 0.3 then table.insert( warn, tx.damage ) end

	if #warn > 0 and math.floor( RealTime() * 3 ) % 3 ~= 0 then
		local wy = top + 4.2 * ppd

		for _, text in ipairs( warn ) do
			local w, h = UI.TextSize( text, "SkyOps_Warn" )

			Box( bx - w / 2 - 0.5 * ppd, wy - 0.15 * ppd, w + ppd, h + 0.3 * ppd )
			T( text, "SkyOps_Warn", bx, wy, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP )

			wy = wy + h + 0.6 * ppd
		end
	end
end

HUD.Painters = HUD.Painters or {}
HUD.Painters.pilot = HUD.PaintPilot
