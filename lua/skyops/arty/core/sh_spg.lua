-- 2S35 on a firing position, shared part: the mode convar, the laying drive that
-- replaces mouse aim while the gun is deployed, and the gunner's keys (client).
--
-- NW2 on sw_2s35 (set by sv_spg):
--   SkyOpsArty_Deployed (bool), SkyOpsArty_BaseDir (float, mils) - see docs/arty-api.md
--   SkyOpsArty_State (int): 0 march, 1 deploying, 2 deployed, 3 stowing
--   SkyOpsArty_StateEnd (float): CurTime() when deploying/stowing finishes
--   SkyOpsArty_Lay (bool): turret follows LayP/LayY instead of the mouse
--   SkyOpsArty_LayP, SkyOpsArty_LayY (float): turret pitch/yaw target, LVS turret degrees
--   SkyOpsArty_Charge (int): charge loaded for the next shot
--   SkyOpsArty_Auto (bool): an auto-mode laying is running

SkyOps.Arty = SkyOps.Arty or {}
SkyOps.Arty.SPG = SkyOps.Arty.SPG or {}

local SPG = SkyOps.Arty.SPG

SPG.CLASS = "sw_2s35"
SPG.GUNNER_POD = 2 -- TurretPodIndex of sw_2s35

SPG.STATE_MARCH, SPG.STATE_DEPLOYING, SPG.STATE_DEPLOYED, SPG.STATE_STOWING = 0, 1, 2, 3

-- bits of the skyops_arty_lay message: laying keys held by the gunner
SPG.LAY_LEFT, SPG.LAY_RIGHT, SPG.LAY_UP, SPG.LAY_DOWN, SPG.LAY_FAST = 1, 2, 4, 8, 16

-- hardcore: manual laying from the fire computer; auto: one button lays and fires
SPG.cvMode = CreateConVar( "skyops_arty_mode", "hardcore", bit.bor( FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY ), "Artillery mode: hardcore | auto" )

function SPG.Mode()
	return SPG.cvMode:GetString() == "auto" and "auto" or "hardcore"
end

function SPG.IsSPG( ent )
	return IsValid( ent ) and ent:GetClass() == SPG.CLASS
end

function SPG.IsDeployed( spg )
	return spg:GetNW2Bool( "SkyOpsArty_Deployed", false )
end

-- the 2S35 a player sits in (any seat), or nil
function SPG.Of( ply )
	if not IsValid( ply ) or not ply.lvsGetVehicle then return nil end

	local veh = ply:lvsGetVehicle()

	return SPG.IsSPG( veh ) and veh or nil
end

-- Laying drive -----------------------------------------------------------------------
-- A copy of the LVS AimTurret (lvs_tank_wheeldrive/modules/sh_turret.lua) that aims at
-- the NW2 laying angles. It runs on the server and, for the gunner, on the client, just
-- like the stock one, and also without a gunner so the auto mode can lay an empty gun.

local function LayingAimTurret( self )
	if not self:GetNW2Bool( "SkyOpsArty_Lay", false ) then
		return self.SkyOpsArty_StockAimTurret( self )
	end

	local ET = self:GetTable()

	if self:GetHP() <= 0 or not self:GetTurretEnabled() then
		if SERVER then
			self:StopTurretSound()
			self:StopTurretSoundDMG()
		end

		return
	end

	local rate = ET.TurretAimRate * FrameTime()

	if self:GetTurretDamaged() then rate = rate * ET.TurretRateDestroyedMul end

	local pitch = math.Clamp( math.ApproachAngle( self:GetTurretPitch(), self:GetNW2Float( "SkyOpsArty_LayP", 0 ), rate ), ET.TurretPitchMin, ET.TurretPitchMax )
	local yaw = math.ApproachAngle( self:GetTurretYaw(), self:GetNW2Float( "SkyOpsArty_LayY", 0 ), rate )

	if ET.TurretYawMin and ET.TurretYawMax then
		yaw = math.Clamp( yaw, ET.TurretYawMin, ET.TurretYawMax )
	end

	if SERVER then self:CalcTurretSound( pitch, yaw, rate ) end

	self:SetTurretPitch( pitch )
	self:SetTurretYaw( yaw )

	self:SetPoseParameter( ET.TurretPitchPoseParameterName, ET.TurretPitchOffset + pitch * ET.TurretPitchMul )
	self:SetPoseParameter( ET.TurretYawPoseParameterName, ET.TurretYawOffset + yaw * ET.TurretYawMul )
end

-- true when the turret has reached the laying angles (deg tolerance)
function SPG.LayReached( spg, tol )
	tol = tol or 0.01

	return math.abs( math.AngleDifference( spg:GetTurretPitch(), spg:GetNW2Float( "SkyOpsArty_LayP", 0 ) ) ) <= tol
		and math.abs( math.AngleDifference( spg:GetTurretYaw(), spg:GetNW2Float( "SkyOpsArty_LayY", 0 ) ) ) <= tol
end

local function Patch( ent )
	if not SPG.IsSPG( ent ) or ent.SkyOpsArty_StockAimTurret or not isfunction( ent.AimTurret ) then return end

	ent.SkyOpsArty_StockAimTurret = ent.AimTurret
	ent.AimTurret = LayingAimTurret
end

hook.Add( "OnEntityCreated", "SkyOps.Arty.SPGPatch", function( ent )
	-- the entity table is filled after creation
	timer.Simple( 0, function() if IsValid( ent ) then Patch( ent ) end end )
end )

for _, ent in ipairs( ents.FindByClass( SPG.CLASS ) ) do Patch( ent ) end -- Lua refresh

if SERVER then return end

-- Gunner keys ----------------------------------------------------------------------
-- Polled in Think: PlayerButtonDown does not run on the client in single player.

local Keys = {
	deploy = CreateClientConVar( "skyops_arty_key_deploy", tostring( KEY_H ), true, false, "2S35: развернуть / свернуть" ),
	charge = CreateClientConVar( "skyops_arty_key_charge", tostring( KEY_K ), true, false, "2S35: следующий заряд" ),
	left = CreateClientConVar( "skyops_arty_key_left", tostring( KEY_LEFT ), true, false, "2S35: ствол влево (угломер больше)" ),
	right = CreateClientConVar( "skyops_arty_key_right", tostring( KEY_RIGHT ), true, false, "2S35: ствол вправо (угломер меньше)" ),
	up = CreateClientConVar( "skyops_arty_key_up", tostring( KEY_UP ), true, false, "2S35: ствол вверх (прицел больше)" ),
	down = CreateClientConVar( "skyops_arty_key_down", tostring( KEY_DOWN ), true, false, "2S35: ствол вниз (прицел меньше)" ),
	fast = CreateClientConVar( "skyops_arty_key_fast", tostring( KEY_LSHIFT ), true, false, "2S35: держать для наводки по 10 тысячных" ),
}

local function Down( cv )
	local k = cv:GetInt()

	return k > 0 and input.IsButtonDown( k )
end

local was = {}
local lastMask = 0

hook.Add( "Think", "SkyOps.Arty.SPGKeys", function()
	local ply = LocalPlayer()
	local spg = SPG.Of( ply )
	local busy = vgui.GetKeyboardFocus() ~= nil or gui.IsGameUIVisible() or gui.IsConsoleVisible() or ( ply.IsTyping and ply:IsTyping() )
	local mask = 0

	if spg and not busy then
		for _, name in ipairs( { "deploy", "charge" } ) do
			local d = Down( Keys[ name ] )

			if d and not was[ name ] then
				if name == "deploy" then
					RunConsoleCommand( "skyops_arty_deploy" )
				else
					RunConsoleCommand( "skyops_arty_charge", "next" )
				end
			end

			was[ name ] = d
		end

		if spg:GetNW2Bool( "SkyOpsArty_Lay", false ) then
			if Down( Keys.left ) then mask = mask + SPG.LAY_LEFT end
			if Down( Keys.right ) then mask = mask + SPG.LAY_RIGHT end
			if Down( Keys.up ) then mask = mask + SPG.LAY_UP end
			if Down( Keys.down ) then mask = mask + SPG.LAY_DOWN end
			if mask > 0 and Down( Keys.fast ) then mask = mask + SPG.LAY_FAST end
		end
	else
		was = {}
	end

	if mask ~= lastMask then
		lastMask = mask

		if util.NetworkStringToID( "skyops_arty_lay" ) ~= 0 then
			net.Start( "skyops_arty_lay" )
				net.WriteUInt( mask, 5 )
			net.SendToServer()
		end
	end
end )

function SPG.KeyName( name )
	local cv = Keys[ name ]

	return cv and string.upper( input.GetKeyName( cv:GetInt() ) or "?" ) or "?"
end
