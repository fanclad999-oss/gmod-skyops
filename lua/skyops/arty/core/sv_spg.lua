-- 2S35 on a firing position, server part: deploying and stowing, manual laying with the
-- gunner's keys, the stock shot replaced by a math shell (sv_ballistics) and the auto
-- mode that lays and fires on one request.
--
-- Commands (player in a 2S35, any seat):
--   skyops_arty_deploy                deploy / stow (key H)
--   skyops_arty_charge next|<id>      charge for the next shot (key K)
--   skyops_arty_basedir <mils>|here|off   basic direction of the position; "here" makes
--                                     the current barrel bearing read 30-00
-- net:
--   skyops_arty_lay  client -> server { UInt(5) mask }  laying keys held (SPG.LAY_*)
--   skyops_arty_auto client -> server { Entity spg, Vector target, String shell, UInt8 charge }
--                    charge 0 = pick the weakest charge that reaches

local SPG = SkyOps.Arty.SPG
local FC = SkyOps.Arty.FireComp
local Grid = SkyOps.Arty.Grid
local Ballistics = SkyOps.Arty.Ballistics

util.AddNetworkString( "skyops_arty_lay" )
util.AddNetworkString( "skyops_arty_auto" )

local cvDeployTime = CreateConVar( "skyops_arty_deploy_time", "10", FCVAR_ARCHIVE, "Seconds to deploy the 2S35 on a firing position", 0, 120 )
local cvStowTime = CreateConVar( "skyops_arty_stow_time", "6", FCVAR_ARCHIVE, "Seconds to stow the 2S35 for the march", 0, 120 )

local DEG_PER_MIL = 360 / FC.MILS
local MAX_DEPLOY_SPEED = 1 -- m/s
local UNDEPLOYED_DISPERSION = 3

local LAY_STEP, LAY_STEP_FAST = 1, 10 -- mils per key press
local LAY_RATE, LAY_RATE_FAST = 20, 200 -- mils per second while held
local LAY_HOLD = 0.35 -- s before a held key starts to slew

local AUTO_TOL = 0.3 -- mils: laid closely enough to fire
local AUTO_TIMEOUT = 60 -- s

local function FmtMils( m )
	m = math.Round( m ) % FC.MILS

	return string.format( "%d-%02d", math.floor( m / 100 ), m % 100 )
end

SPG.FmtMils = FmtMils

local function Tell( ply, msg )
	if IsValid( ply ) then ply:ChatPrint( "[2S35] " .. msg ) end
end

local function Crew( spg )
	local list = {}

	for _, ply in ipairs( player.GetAll() ) do
		if SPG.Of( ply ) == spg then list[ #list + 1 ] = ply end
	end

	return list
end

local function TellCrew( spg, msg )
	for _, ply in ipairs( Crew( spg ) ) do Tell( ply, msg ) end
end

local function SpeedMS( spg )
	return spg:GetVelocity():Length() / Grid.UPM()
end

-- Charges --------------------------------------------------------------------------

local function CurrentShell( spg )
	return FC.ShellForStockType( spg.GetShellType and spg:GetShellType() or 0 )
end

-- charge that will be used with this shell: the set one, or the strongest the shell takes
local function UsableCharge( shellId, chargeId )
	if FC.GetCharge( shellId, chargeId ) then return chargeId end

	local shell = FC.GetShell( shellId )

	return shell and shell.charges[ 1 ].id or 1
end

function SPG.SetCharge( spg, chargeId )
	spg:SetNW2Int( "SkyOpsArty_Charge", chargeId )
end

-- States ---------------------------------------------------------------------------

local Tracked = {} -- spg -> true

local function SetFrozen( spg, frozen )
	local phys = spg:GetPhysicsObject()

	if not IsValid( phys ) then return end

	phys:EnableMotion( not frozen )

	if not frozen then phys:Wake() end
end

local function SetState( spg, state, duration )
	spg:SetNW2Int( "SkyOpsArty_State", state )
	spg:SetNW2Float( "SkyOpsArty_StateEnd", CurTime() + ( duration or 0 ) )
	spg:SetNW2Bool( "SkyOpsArty_Deployed", state == SPG.STATE_DEPLOYED )
	spg:SetNW2Bool( "SkyOpsArty_Lay", state == SPG.STATE_DEPLOYED )

	hook.Run( "SkyOps.Arty.SPGState", spg, state )
end

local function State( spg )
	return spg:GetNW2Int( "SkyOpsArty_State", SPG.STATE_MARCH )
end

local function CancelAuto( spg, why )
	local job = spg.SkyOpsArty_Job

	if not job then return end

	spg.SkyOpsArty_Job = nil
	spg:SetNW2Bool( "SkyOpsArty_Auto", false )

	if why then Tell( job.ply, "Авто: " .. why ) end
end

-- returns false and a reason when the gun cannot start deploying
function SPG.Deploy( spg )
	local state = State( spg )

	if state == SPG.STATE_DEPLOYED or state == SPG.STATE_DEPLOYING then return true end
	if state == SPG.STATE_STOWING then return false, "САУ сворачивается" end
	if spg:GetHP() <= 0 then return false, "САУ уничтожена" end
	if SpeedMS( spg ) > MAX_DEPLOY_SPEED then return false, "Остановите машину" end

	if spg.StopEngine and spg:GetEngineActive() then spg:StopEngine() end

	SetFrozen( spg, true )
	SetState( spg, SPG.STATE_DEPLOYING, cvDeployTime:GetFloat() )
	Tracked[ spg ] = true

	return true
end

function SPG.Stow( spg )
	local state = State( spg )

	if state == SPG.STATE_MARCH or state == SPG.STATE_STOWING then return true end

	CancelAuto( spg, "отменено, САУ сворачивается" )
	SetState( spg, SPG.STATE_STOWING, state == SPG.STATE_DEPLOYED and cvStowTime:GetFloat() or 0 )

	return true
end

local function FinishDeploy( spg )
	-- the basic direction follows the hull, rounded to whole 1-00, unless set by command
	if not spg.SkyOpsArty_BaseDirFixed then
		local hull = Grid.YawToMils( spg:GetAngles().y )

		spg:SetNW2Float( "SkyOpsArty_BaseDir", ( math.Round( hull / 100 ) * 100 ) % FC.MILS )
	end

	spg:SetNW2Float( "SkyOpsArty_LayP", spg:GetTurretPitch() )
	spg:SetNW2Float( "SkyOpsArty_LayY", spg:GetTurretYaw() )

	if spg:GetNW2Int( "SkyOpsArty_Charge", 0 ) == 0 then SPG.SetCharge( spg, 1 ) end

	SetState( spg, SPG.STATE_DEPLOYED )

	local defl, elev = FC.GunLaying( spg )

	TellCrew( spg, string.format( "Развёрнута. Основное направление %s, угломер %s, прицел %s. Наводка стрелками (с Shift по 10 тыс.), заряд K.",
		FmtMils( spg:GetNW2Float( "SkyOpsArty_BaseDir", 0 ) ), FmtMils( defl ), FmtMils( elev ) ) )
end

local function FinishStow( spg )
	SetFrozen( spg, false )
	SetState( spg, SPG.STATE_MARCH )
	TellCrew( spg, "Свёрнута, можно ехать." )
end

-- Laying keys ----------------------------------------------------------------------

local Held = {} -- ply -> { mask, since = { [bit] = time } }

local DIRS = {
	{ bit = SPG.LAY_LEFT, yaw = 1 },
	{ bit = SPG.LAY_RIGHT, yaw = -1 },
	{ bit = SPG.LAY_UP, pitch = -1 }, -- LVS turret pitch is negative upwards
	{ bit = SPG.LAY_DOWN, pitch = 1 },
}

local function Nudge( spg, d, mils )
	local deg = mils * DEG_PER_MIL

	if d.yaw then
		spg:SetNW2Float( "SkyOpsArty_LayY", math.NormalizeAngle( spg:GetNW2Float( "SkyOpsArty_LayY", 0 ) + d.yaw * deg ) )
	else
		local p = spg:GetNW2Float( "SkyOpsArty_LayP", 0 ) + d.pitch * deg

		spg:SetNW2Float( "SkyOpsArty_LayP", math.Clamp( p, spg.TurretPitchMin or -75, spg.TurretPitchMax or 5 ) )
	end
end

net.Receive( "skyops_arty_lay", function( _, ply )
	local mask = net.ReadUInt( 5 )
	local spg = SPG.Of( ply )
	local h = Held[ ply ] or { mask = 0, since = {} }

	Held[ ply ] = h

	if not spg or not spg:GetNW2Bool( "SkyOpsArty_Lay", false ) then
		h.mask = 0
		return
	end

	local fast = bit.band( mask, SPG.LAY_FAST ) ~= 0

	for _, d in ipairs( DIRS ) do
		local now = bit.band( mask, d.bit ) ~= 0
		local before = bit.band( h.mask, d.bit ) ~= 0

		if now and not before then
			if spg.SkyOpsArty_Job then CancelAuto( spg, "отменено ручной наводкой" ) end

			Nudge( spg, d, fast and LAY_STEP_FAST or LAY_STEP )
			h.since[ d.bit ] = CurTime()
		end
	end

	h.mask = mask
end )

local function LayThink( spg )
	local ft = FrameTime()

	for ply, h in pairs( Held ) do
		if not IsValid( ply ) then
			Held[ ply ] = nil
		elseif h.mask ~= 0 and SPG.Of( ply ) == spg then
			local fast = bit.band( h.mask, SPG.LAY_FAST ) ~= 0

			for _, d in ipairs( DIRS ) do
				if bit.band( h.mask, d.bit ) ~= 0 and CurTime() - ( h.since[ d.bit ] or 0 ) > LAY_HOLD then
					Nudge( spg, d, ( fast and LAY_RATE_FAST or LAY_RATE ) * ft )
				end
			end
		end
	end
end

-- Shot -----------------------------------------------------------------------------

local SHELL_CLASS = "sw_bomb_fab100_v3"

local function Gunner( spg )
	local ply = spg.GetPassenger and spg:GetPassenger( SPG.GUNNER_POD )

	if IsValid( ply ) then return ply end

	ply = spg:GetDriver()

	return IsValid( ply ) and ply or nil
end

-- the stock cannon spawned its 87 m/s shell: replace it with a math shell along the barrel
local function Intercept( spg, stock )
	local order = spg.SkyOpsArty_NextShot

	spg.SkyOpsArty_NextShot = nil

	if order and CurTime() - order.t > 1 then order = nil end -- left over from a failed auto shot

	local shellId = order and order.shell or CurrentShell( spg )
	local charge = UsableCharge( shellId, order and order.charge or spg:GetNW2Int( "SkyOpsArty_Charge", 1 ) )

	spg:InvalidateBoneCache()

	local pos, dir = FC.Muzzle( spg )

	stock:Remove()

	local shell = Ballistics.Fire( {
		pos = pos,
		dir = dir,
		shell = shellId,
		charge = charge,
		attacker = ( order and order.attacker ) or Gunner( spg ) or spg,
		spg = spg,
		dispersion = SPG.IsDeployed( spg ) and 1 or UNDEPLOYED_DISPERSION,
	} )

	if shell then
		hook.Run( "SkyOps.Arty.SPGFired", spg, shell )
	end
end

hook.Add( "OnEntityCreated", "SkyOps.Arty.Intercept", function( ent )
	if ent:GetClass() ~= SHELL_CLASS then return end

	-- the cannon sets _ProjectileEntity right after Spawn(), so look one tick later
	timer.Simple( 0, function()
		if not IsValid( ent ) or ent.SkyOpsArty_Ours then return end

		for spg in pairs( Tracked ) do
			if IsValid( spg ) and spg._ProjectileEntity == ent then
				Intercept( spg, ent )
				return
			end
		end
	end )
end )

-- the 2S35 cannon in the gunner's weapon list (pod 2: FLIR, cannon, smoke, no-turret)
local function Cannon( spg )
	local handler = spg:GetWeaponHandler( SPG.GUNNER_POD )
	local list = spg.WEAPONS and spg.WEAPONS[ SPG.GUNNER_POD ]

	if not IsValid( handler ) or not list then return nil end

	for id, w in pairs( list ) do
		if w.Icon == true and isfunction( w.Attack ) then return handler, id, w end
	end

	if list[ 2 ] and isfunction( list[ 2 ].Attack ) then return handler, 2, list[ 2 ] end
end

-- fires the stock cannon once if it is loaded; false and a reason otherwise
function SPG.Fire( spg, shellId, charge, attacker )
	local handler, id, cannon = Cannon( spg )

	if not handler then return false, "нет пушки" end

	if handler:GetSelectedWeapon() ~= id then handler:SelectWeapon( id ) end

	if handler:GetMaxAmmo() > 0 and handler:GetAmmo() <= 0 then return false, "нет снарядов" end
	if handler:GetOverheated() or not handler:CanAttack() then return false, "заряжание" end

	local def = FC.GetShell( shellId )

	if def and spg.SetShellType and spg:GetShellType() ~= def.stockType then spg:SetShellType( def.stockType ) end

	spg.SkyOpsArty_NextShot = { shell = shellId, charge = charge, attacker = attacker, t = CurTime() }

	local delay = cannon.Delay or 0

	cannon.Attack( handler )
	handler:SetNextAttack( CurTime() + delay )
	handler:SetHeat( handler:GetHeat() + ( cannon.HeatRateUp or 0.2 ) * math.max( delay, FrameTime() ) )

	return true
end

-- Auto mode ------------------------------------------------------------------------

local function AutoSolve( spg, job )
	local gx, gy, gh = Grid.ToGrid3( spg:GetPos() )
	local tx, ty, th = Grid.ToGrid3( job.target )
	local q = {
		gun = { x = gx, y = gy, h = gh },
		target = { x = tx, y = ty, h = th },
		shell = job.shell,
		basedir = FC.BaseDir( spg ),
	}

	local range = math.sqrt( ( tx - gx ) ^ 2 + ( ty - gy ) ^ 2 )
	local dh = th - gh - FC.MUZZLE_H
	local charges = {}

	if FC.GetCharge( job.shell, job.charge ) then charges[ 1 ] = job.charge end

	charges[ #charges + 1 ] = FC.BestCharge( job.shell, range, dh, gh + FC.MUZZLE_H )

	local last

	for _, c in ipairs( charges ) do
		for _, high in ipairs( { false, true } ) do
			q.charge, q.high = c, high
			last = FC.Solve( q )

			if last.ok then return last end
		end
	end

	return nil, last and last.err or "нет решения"
end

local function AutoLay( spg, sol )
	local dir = Grid.Direction( sol.bearing, sol.elevation )
	local ang = spg:WorldToLocalAngles( dir:Angle() )

	spg:SetNW2Float( "SkyOpsArty_LayP", math.Clamp( ang.p, spg.TurretPitchMin or -75, spg.TurretPitchMax or 5 ) )
	spg:SetNW2Float( "SkyOpsArty_LayY", math.NormalizeAngle( ang.y ) )
end

local function AutoThink( spg, job )
	if CurTime() - job.t0 > AUTO_TIMEOUT then return CancelAuto( spg, "не успели навести за минуту" ) end

	local state = State( spg )

	if state == SPG.STATE_MARCH then
		local ok, why = SPG.Deploy( spg )

		if not ok then return CancelAuto( spg, why ) end

		Tell( job.ply, "Авто: развёртываю САУ" )
		return
	end

	if state ~= SPG.STATE_DEPLOYED then return end

	if not job.sol then
		local sol, err = AutoSolve( spg, job )

		if not sol then return CancelAuto( spg, err ) end

		job.sol = sol
		job.iter = 0
		SPG.SetCharge( spg, sol.charge )
		AutoLay( spg, sol )
		return
	end

	if not job.laid then
		if not SPG.LayReached( spg ) then return end

		-- the hull stands on a slope and the barrel model is not exactly the turret
		-- angles: measure the barrel and correct until it reads the solution
		spg:InvalidateBoneCache()

		local defl, elev = FC.GunLaying( spg )
		local dDefl = FC.MilsDiff( job.sol.deflection, defl )
		local dElev = job.sol.elevation - elev

		if ( math.abs( dDefl ) <= AUTO_TOL and math.abs( dElev ) <= AUTO_TOL ) or job.iter >= 6 then
			job.laid = true
		else
			job.iter = job.iter + 1
			spg:SetNW2Float( "SkyOpsArty_LayY", math.NormalizeAngle( spg:GetNW2Float( "SkyOpsArty_LayY", 0 ) + dDefl * DEG_PER_MIL ) )
			spg:SetNW2Float( "SkyOpsArty_LayP", spg:GetNW2Float( "SkyOpsArty_LayP", 0 ) - dElev * DEG_PER_MIL )
			return
		end
	end

	local ok, why = SPG.Fire( spg, job.shell, job.sol.charge, job.ply )

	if not ok then
		if why == "заряжание" then return end -- wait for the loader

		return CancelAuto( spg, why )
	end

	local sol = job.sol
	local charge = FC.GetCharge( job.shell, sol.charge )

	Tell( job.ply, string.format( "Выстрел: %s, заряд «%s», угломер %s, прицел %s, дальность %.0f м, полёт %.0f с",
		FC.GetShell( job.shell ).name, charge and charge.name or "?", FmtMils( sol.deflection ), FmtMils( sol.elevation ), sol.range, sol.tof ) )

	CancelAuto( spg )
end

local NextAuto = {}

net.Receive( "skyops_arty_auto", function( _, ply )
	local spg = net.ReadEntity()
	local target = net.ReadVector()
	local shellId = net.ReadString()
	local charge = net.ReadUInt( 8 )

	if ( NextAuto[ ply ] or 0 ) > CurTime() then return end

	NextAuto[ ply ] = CurTime() + 1

	if SPG.Mode() ~= "auto" then return Tell( ply, "Режим «хардкор»: наводите вручную (skyops_arty_mode auto включает авто)" ) end
	if not SPG.IsSPG( spg ) then return Tell( ply, "Авто: САУ не найдена" ) end
	if not FC.GetShell( shellId ) then shellId = "he" end

	CancelAuto( spg )

	spg.SkyOpsArty_Job = { ply = ply, target = target, shell = shellId, charge = charge, t0 = CurTime() }
	spg:SetNW2Bool( "SkyOpsArty_Auto", true )
	Tracked[ spg ] = true
end )

-- Commands -------------------------------------------------------------------------

concommand.Add( "skyops_arty_deploy", function( ply )
	local spg = SPG.Of( ply )

	if not spg then return end

	local state = State( spg )

	if state == SPG.STATE_MARCH or state == SPG.STATE_STOWING then
		local ok, why = SPG.Deploy( spg )

		Tell( ply, ok and string.format( "Развёртывание, %d с", math.Round( cvDeployTime:GetFloat() ) ) or why )
	else
		SPG.Stow( spg )
		Tell( ply, string.format( "Свёртывание, %d с", math.Round( cvStowTime:GetFloat() ) ) )
	end
end )

concommand.Add( "skyops_arty_charge", function( ply, _, args )
	local spg = SPG.Of( ply )

	if not spg then return end

	local shellId = CurrentShell( spg )
	local shell = FC.GetShell( shellId )
	local cur = UsableCharge( shellId, spg:GetNW2Int( "SkyOpsArty_Charge", 1 ) )
	local want

	if args[ 1 ] == "next" or not args[ 1 ] then
		for i, c in ipairs( shell.charges ) do
			if c.id == cur then
				want = ( shell.charges[ i + 1 ] or shell.charges[ 1 ] ).id
			end
		end
	else
		want = tonumber( args[ 1 ] )
	end

	local c = FC.GetCharge( shellId, want )

	if not c then return Tell( ply, "Такого заряда для снаряда «" .. shell.name .. "» нет" ) end

	SPG.SetCharge( spg, c.id )

	local maxR = FC.MaxRange( shellId, c.id, 0 )

	Tell( ply, string.format( "Заряд «%s» (%d м/с, до %.1f км)", c.name, c.v0, ( maxR or 0 ) / 1000 ) )
end )

concommand.Add( "skyops_arty_basedir", function( ply, _, args )
	local spg = SPG.Of( ply )

	if not spg then return end

	local arg = args[ 1 ]

	if arg == "off" then
		spg.SkyOpsArty_BaseDirFixed = nil
		return Tell( ply, "Основное направление снова по корпусу при развёртывании" )
	end

	local v

	if arg == "here" then
		local _, _, bearing = FC.GunLaying( spg )

		v = math.Round( bearing )
	else
		-- "45-00" or "4500"
		v = tonumber( ( string.gsub( arg or "", "-", "" ) ) )
	end

	if not v then return Tell( ply, "skyops_arty_basedir <тысячные> | here | off" ) end

	v = v % FC.MILS
	spg.SkyOpsArty_BaseDirFixed = true
	spg:SetNW2Float( "SkyOpsArty_BaseDir", v )
	Tell( ply, "Основное направление " .. FmtMils( v ) )
end )

-- Think ----------------------------------------------------------------------------

hook.Add( "OnEntityCreated", "SkyOps.Arty.SPGTrack", function( ent )
	timer.Simple( 0, function()
		if SPG.IsSPG( ent ) then Tracked[ ent ] = true end
	end )
end )

for _, ent in ipairs( ents.FindByClass( SPG.CLASS ) ) do Tracked[ ent ] = true end

hook.Add( "Think", "SkyOps.Arty.SPG", function()
	for spg in pairs( Tracked ) do
		if not IsValid( spg ) then
			Tracked[ spg ] = nil
		else
			local state = State( spg )

			if state ~= SPG.STATE_MARCH then
				if spg:GetHP() <= 0 and state ~= SPG.STATE_STOWING then
					SPG.Stow( spg )
					state = SPG.STATE_STOWING
				end

				-- no driving off a firing position
				if spg.StopEngine and spg:GetEngineActive() then spg:StopEngine() end

				local done = CurTime() >= spg:GetNW2Float( "SkyOpsArty_StateEnd", 0 )

				if state == SPG.STATE_DEPLOYING and done then
					FinishDeploy( spg )
				elseif state == SPG.STATE_STOWING and done then
					FinishStow( spg )
				elseif state == SPG.STATE_DEPLOYED then
					LayThink( spg )
				end
			end

			if spg.SkyOpsArty_Job then AutoThink( spg, spg.SkyOpsArty_Job ) end
		end
	end
end )

hook.Add( "PlayerDisconnected", "SkyOps.Arty.SPG", function( ply )
	Held[ ply ] = nil
	NextAuto[ ply ] = nil
end )
