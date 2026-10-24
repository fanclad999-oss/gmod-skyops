-- Артиллерия, дрон: барражирование по кругу над точкой.
-- Дрон летит по кругу против часовой на той высоте, где включили барраж, и держит газ
-- из настроек. Игрок в это время свободно крутит камеру мышью. Любая клавиша
-- тангажа, рыскания или крена возвращает ручное управление.
-- Рулим через стоковый ENT:ApproachTargetAngle базы lvs_base_fighterplane,
-- тем же путём, что и ИИ LVS.

local D = SkyOps.Arty.Drone

local MAX_PITCH = 15 -- градусы: насколько дрон может задирать или опускать нос на барраже
local MANUAL_KEYS = { "+PITCH", "-PITCH", "+YAW", "-YAW", "+ROLL", "-ROLL" }

-- Подменяем три метода у конкретного дрона (не у класса): пока барраж включён,
-- мышь и клавиши не рулят дроном и не меняют газ.
local function Patch( drone )
	if drone.SkyOpsArty_Patched then return end

	drone.SkyOpsArty_Patched = true

	local mouseAim, directInput, calcThrottle = drone.PlayerMouseAim, drone.PlayerDirectInput, drone.CalcThrottle

	drone.PlayerMouseAim = function( self, ply, ... )
		if self.SkyOpsArty_LoiterAng then return self:ApproachTargetAngle( self.SkyOpsArty_LoiterAng ) end

		return mouseAim( self, ply, ... )
	end

	drone.PlayerDirectInput = function( self, ... )
		if self.SkyOpsArty_LoiterAng then return end

		return directInput( self, ... )
	end

	drone.CalcThrottle = function( self, ... )
		if self.SkyOpsArty_LoiterAng then return end

		return calcThrottle( self, ... )
	end
end

function D.IsLoitering( drone )
	return drone:GetNW2Bool( "SkyOpsArty_Loiter", false )
end

function D.StopLoiter( drone )
	drone.SkyOpsArty_LoiterAng = nil
	drone:SetNW2Bool( "SkyOpsArty_Loiter", false )
end

-- center = мировая точка, вокруг которой летать (nil = подсветка, захват камеры или точка сбоку)
function D.StartLoiter( drone, center )
	local cfg = D.Config( drone )

	if not cfg or not cfg.loiter or not drone.ApproachTargetAngle then return false, "Этот дрон не умеет барражировать" end
	if drone.IsDestroyed and drone:IsDestroyed() then return false, "Дрон повреждён" end

	local radius = cfg.radius * D.UPM()

	center = center or D.LaserPos( drone ) or D.AimPoint( drone )

	if not center then
		-- некуда смотреть: круг начинается там, где дрон сейчас, центр слева от него
		center = drone:GetPos() - drone:GetRight() * radius
	end

	Patch( drone )

	if not drone:GetEngineActive() then drone:StartEngine() end

	drone.SkyOpsArty_LoiterZ = drone:GetPos().z
	drone.SkyOpsArty_LoiterAng = drone:GetAngles()
	D.SetNWPos( drone, "SkyOpsArty_LoiterCenter", center )
	drone:SetNW2Float( "SkyOpsArty_LoiterRadius", radius )
	drone:SetNW2Bool( "SkyOpsArty_Loiter", true )

	return true
end

local function ManualInput( ply )
	for _, k in ipairs( MANUAL_KEYS ) do
		if ply:lvsKeyDown( k ) then return true end
	end

	return false
end

local function Steer( drone, cfg )
	local pos = drone:GetPos()
	local center = D.GetNWPos( drone, "SkyOpsArty_LoiterCenter" )
	local radius = drone:GetNW2Float( "SkyOpsArty_LoiterRadius" )

	local dx, dy = pos.x - center.x, pos.y - center.y

	if dx * dx + dy * dy < 1 then
		local f = drone:GetForward()

		dx, dy = -f.y, f.x
	end

	-- точка на круге чуть впереди дрона по ходу (против часовой)
	local phi = math.atan2( dy, dx ) + math.rad( cfg.lead or 30 )
	local goal = Vector( center.x + math.cos( phi ) * radius, center.y + math.sin( phi ) * radius, drone.SkyOpsArty_LoiterZ )

	local ang = ( goal - pos ):Angle()

	ang.p = math.Clamp( math.NormalizeAngle( ang.p ), -MAX_PITCH, MAX_PITCH )
	ang.r = 0

	return ang
end

local function UpdateLoiter( drone )
	local cfg = D.Config( drone )
	local ply = drone:GetDriver()

	if ( drone.IsDestroyed and drone:IsDestroyed() ) or drone:GetAI() then
		D.StopLoiter( drone )
	elseif IsValid( ply ) and ManualInput( ply ) then
		D.StopLoiter( drone )
		D.Notify( ply, "Барраж выключен: ручное управление" )
	else
		drone.SkyOpsArty_LoiterAng = Steer( drone, cfg )

		-- без игрока или без управления мышью CalcAero сам не рулит: рулим отсюда
		if not IsValid( ply ) or not ply:lvsMouseAim() then
			drone:ApproachTargetAngle( drone.SkyOpsArty_LoiterAng )
		end

		drone:SetThrottle( cfg.throttle )
	end
end

hook.Add( "Tick", "SkyOpsArty.Drone.Loiter", function()
	for _, drone in ipairs( D.All() ) do
		if D.IsLoitering( drone ) then UpdateLoiter( drone ) end
	end
end )

D.Commands.loiter = function( ply, drone )
	if not drone then return end

	if D.IsLoitering( drone ) then
		D.StopLoiter( drone )
		D.Notify( ply, "Барраж выключен" )

		return
	end

	local ok, err = D.StartLoiter( drone )

	D.Notify( ply, ok and "Барраж включён: дрон кружит над точкой" or err )
end
