-- SkyOps: каркас HUD (client)
-- Заменяет стоковый HUD LVS на самолётах из реестра, считает параметры полёта
-- и раздаёт отрисовку по месту: пилот (cl_hud_pilot), штурман-оператор (cl_wso).

SkyOps = SkyOps or {}
SkyOps.HUD = SkyOps.HUD or {}

local HUD = SkyOps.HUD
local U = SkyOps.Conv

local cvEnabled = CreateClientConVar( "skyops_hud", "1", true, false, "Свой HUD SkyOps вместо стокового LVS" )
local cvColor = CreateClientConVar( "skyops_hud_color", "green", true, false, "Цвет символики: green, amber, cyan, white" )
local cvBright = CreateClientConVar( "skyops_hud_brightness", "1", true, false, "Яркость символики 0.3..1" )
local cvShadow = CreateClientConVar( "skyops_hud_shadow", "1", true, false, "Тёмная подложка под символикой для читаемости" )
local cvAny = CreateClientConVar( "skyops_hud_any", "0", true, false, "Рисовать HUD на любых самолётах LVS, не только из реестра" )
local cvStockWeapons = CreateClientConVar( "skyops_hud_stockweapons", "1", true, false, "Оставлять оверлеи оружия LVS (прицелы, FLIR)" )

HUD.Colors = {
	green = Color( 110, 255, 140 ),
	amber = Color( 255, 186, 72 ),
	cyan = Color( 120, 230, 255 ),
	white = Color( 235, 245, 240 ),
}

-- Профили: какие единицы и какая школа символики у самолёта
HUD.Aircraft = {
	su34 = { profile = "ru", radalt = 1500, gearSpeed = 450, crew = { [1] = "pilot", [2] = "wso" } },
	su25sm3 = { profile = "ru", radalt = 1500, gearSpeed = 400, crew = { [1] = "pilot" } },
	tornado_ids = { profile = "nato", radalt = 5000, gearSpeed = 235, crew = { [1] = "pilot", [2] = "wso" } },
	f14a = { profile = "nato", radalt = 5000, gearSpeed = 280, crew = { [1] = "pilot", [2] = "rio" } },
	generic = { profile = "nato", radalt = 5000, gearSpeed = 250, crew = { [1] = "pilot", [2] = "wso" } },
}

-- Режим прицельного комплекса: auto определяется по выбранному оружию
HUD.MODE_AUTO = 0
HUD.MODE_NAV = 1
HUD.MODE_GROUND = 2
HUD.MODE_AIR = 3

HUD.ManualMode = HUD.ManualMode or HUD.MODE_AUTO

concommand.Add( "skyops_hud_mode", function()
	HUD.ManualMode = (HUD.ManualMode + 1) % 4

	local names = { [0] = "АВТО", "НАВИГАЦИЯ", "ВОЗДУХ-ЗЕМЛЯ", "ВОЗДУХ-ВОЗДУХ" }

	chat.AddText( Color( 242, 169, 59 ), "[SkyOps] ", color_white, "Режим HUD: " .. names[ HUD.ManualMode ] )
end )

function HUD.Color( alpha )
	local base = HUD.Colors[ cvColor:GetString() ] or HUD.Colors.green
	local b = math.Clamp( cvBright:GetFloat(), 0.3, 1 )

	return Color( base.r, base.g, base.b, 255 * b * (alpha or 1) )
end

function HUD.ShadowEnabled()
	return cvShadow:GetBool()
end

-- Роль самолёта по классу (реестр ядра), nil если не поддерживается
function HUD.GetRole( ent )
	if not IsValid( ent ) then return nil end

	if ent._skyopsRole == nil then
		local role, kind

		if SkyOps.Registry and SkyOps.Registry.RoleForClass then
			role, kind = SkyOps.Registry.RoleForClass( ent:GetClass() )
		end

		if kind ~= "aircraft" then role = nil end

		ent._skyopsRole = role or false
	end

	if ent._skyopsRole then return ent._skyopsRole end

	if cvAny:GetBool() and ent.LVSHudPaint and ent.GetThrottle then
		return "generic"
	end
end

-- Где сидит игрок: "pilot", "wso"/"rio" или nil
function HUD.GetSeat( ply, ent, role )
	local pod = ply:GetVehicle()

	if not IsValid( pod ) then return nil end

	local index = pod.lvsGetPodIndex and pod:lvsGetPodIndex() or 1

	if ent.GetDriver and ent:GetDriver() == ply then index = 1 end

	local def = HUD.Aircraft[ role ] or HUD.Aircraft.generic

	return def.crew[ index ] or (index > 1 and "wso" or "pilot")
end

-- Текущее состояние полёта; считается раз за кадр
local last = {}

function HUD.Sample( ent, role )
	local def = HUD.Aircraft[ role ] or HUD.Aircraft.generic
	local client = SkyOps.Client
	local T = RealTime()
	local dt = math.Clamp( T - (last.time or T), 0.001, 0.2 )

	local pos = ent:GetPos()
	local ang = ent:GetAngles()
	local vel = ent:GetVelocity()
	local world = client and client.WorldPos( ent ) or pos

	local northYaw = SkyOps.Map.NorthYaw and SkyOps.Map.NorthYaw() or 90
	local seaLevel = SkyOps.Map.SeaLevel and SkyOps.Map.SeaLevel() or 0

	local f = {
		ent = ent,
		role = role,
		def = def,
		profile = def.profile,
		pos = pos,
		ang = ang,
		vel = vel,
		fwd = ent:GetForward(),
		up = ent:GetUp(),
		right = ent:GetRight(),
		northYaw = northYaw,
	}

	f.tas = U.ToMps( vel:Length() )
	f.alt = U.ToMeters( world.z - seaLevel )
	f.ias = U.IAS( f.tas, f.alt )
	f.mach = U.Mach( f.tas, f.alt )
	f.vs = U.ToMps( vel.z )
	f.heading = (northYaw - ang.y) % 360
	f.pitch = -ang.p
	f.roll = ang.r

	if f.tas > 5 then
		f.aoa = math.deg( math.atan2( -vel:Dot( f.up ), vel:Dot( f.fwd ) ) )
		f.track = (northYaw - vel:Angle().y) % 360
		f.fpa = math.deg( math.asin( math.Clamp( vel.z / vel:Length(), -1, 1 ) ) )
	else
		f.aoa, f.track, f.fpa = 0, f.heading, 0
	end

	-- Перегрузка: проекция ускорения минус гравитация на вертикальную ось самолёта
	local grav = physenv.GetGravity()
	local g = grav:Length()

	if last.ent == ent and last.vel and g > 0 then
		local accel = (vel - last.vel) / dt
		local n = (accel - grav):Dot( f.up ) / g
		local k = 1 - math.exp( -dt * 5 )

		last.g = Lerp( k, last.g or 1, math.Clamp( n, -6, 14 ) )
	else
		last.g = 1
	end

	f.g = last.g
	last.gMax = math.max( last.ent == ent and last.gMax or 1, f.g )
	f.gMax = last.gMax

	-- Радиовысотомер
	if (last.nextRadalt or 0) < T or last.ent ~= ent then
		last.nextRadalt = T + 0.1

		local tr = util.TraceLine( {
			start = pos,
			endpos = pos - Vector( 0, 0, U.FromMeters( 3000 ) ),
			mask = MASK_SOLID,
			filter = function( e ) return e ~= ent and e:GetParent() ~= ent and not e:IsPlayer() end,
		} )

		last.agl = tr.Hit and U.ToMeters( pos.z - tr.HitPos.z ) or nil
	end

	f.agl = last.agl
	f.gearDown = ent.GetLandingGear and ent:GetLandingGear() > 0.5 or false
	f.throttle = ent.GetThrottle and ent:GetThrottle() or 0
	f.hp = ent.GetHP and ent.GetMaxHP and ent:GetHP() / math.max( ent:GetMaxHP(), 1 ) or 1

	last.ent = ent
	last.vel = vel
	last.time = T

	return f
end

-- Режим по выбранному оружию
function HUD.WeaponMode( ent )
	if HUD.ManualMode ~= HUD.MODE_AUTO then return HUD.ManualMode end

	local weapon = ent.GetActiveWeapon and ent:GetActiveWeapon()

	if not weapon then return HUD.MODE_NAV end

	local icon = weapon.Icon and weapon.Icon.GetName and string.lower( weapon.Icon:GetName() ) or ""

	if string.find( icon, "bomb", 1, true ) then return HUD.MODE_GROUND end
	if string.find( icon, "missile", 1, true ) or string.find( icon, "aam", 1, true ) then return HUD.MODE_AIR end

	return HUD.MODE_NAV
end

function HUD.WeaponInfo( ent )
	local weapon = ent.GetActiveWeapon and ent:GetActiveWeapon()

	if not weapon then return nil end

	local id = ent.GetSelectedWeapon and ent:GetSelectedWeapon() or 0
	local ammo = ent.GetNWAmmo and ent:GetNWAmmo() or -1
	local name = weapon.SkyOpsName

	if not name and weapon.Icon and weapon.Icon.GetName then
		name = string.upper( string.GetFileFromFilename( weapon.Icon:GetName() ) or "" )
	end

	return { id = id, ammo = ammo, name = name or ("#" .. id) }
end

-- Активен ли наш HUD для локального игрока сейчас
function HUD.GetContext()
	if not cvEnabled:GetBool() then return nil end

	local ply = LocalPlayer()

	if not IsValid( ply ) or ply:GetViewEntity() ~= ply or not ply.lvsGetVehicle then return nil end

	local ent = ply:lvsGetVehicle()
	local role = HUD.GetRole( ent )

	if not role then return nil end

	return ply, ent, role, HUD.GetSeat( ply, ent, role )
end

-- Оверлеи оружия LVS (прицельные камеры и т.п.), как их вызывает стоковый HUD
local function PaintStockWeapons( ply, ent )
	if not cvStockWeapons:GetBool() then return end

	local pod = ply:GetVehicle()
	local X, Y = ScrW(), ScrH()
	local base = IsValid( pod ) and pod.lvsGetWeapon and pod:lvsGetWeapon()

	if IsValid( base ) then
		local weapon = base:GetActiveWeapon()

		if weapon and weapon.HudPaint then weapon.HudPaint( base, X, Y, ply ) end
	else
		local weapon = ent.GetActiveWeapon and ent:GetActiveWeapon()

		if ply == ent:GetDriver() and weapon and weapon.HudPaint then weapon.HudPaint( ent, X, Y, ply ) end
	end
end

-- Оборачиваем стоковый хук LVS: на наших самолётах он молчит
local function InstallStockFilter()
	local hooks = hook.GetTable().HUDPaint
	local orig = hooks and hooks[ "!!!!!LVS_hud" ]

	if not orig or orig == HUD.StockWrapper then return end

	HUD.StockOriginal = orig
	HUD.StockWrapper = function( ... )
		if HUD.GetContext() then return end

		return HUD.StockOriginal( ... )
	end

	hook.Add( "HUDPaint", "!!!!!LVS_hud", HUD.StockWrapper )
end

hook.Add( "InitPostEntity", "SkyOps.HUD.StockFilter", InstallStockFilter )
timer.Create( "SkyOps.HUD.StockFilter", 5, 0, InstallStockFilter )

HUD.Painters = HUD.Painters or {}

hook.Add( "HUDPaint", "SkyOps.HUD", function()
	local ply, ent, role, seat = HUD.GetContext()

	if not ply then return end

	local f = HUD.Sample( ent, role )

	f.seat = seat
	f.ply = ply

	PaintStockWeapons( ply, ent )

	if seat == "pilot" then
		if HUD.Painters.pilot then HUD.Painters.pilot( f ) end
	elseif HUD.Painters.wso then
		HUD.Painters.wso( f )
	end

	if HUD.Painters.overlay then HUD.Painters.overlay( f ) end
end )

-- Стандартный прицел и подсказки GMod на наших самолётах не нужны
hook.Add( "HUDShouldDraw", "SkyOps.HUD", function( name )
	if name == "CHudCrosshair" and HUD.GetContext() then return false end
end )
