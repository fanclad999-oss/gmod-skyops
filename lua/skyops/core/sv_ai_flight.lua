-- AI pilots on top of LVS AI. Stock LVS AI only sees targets within 60000 u
-- (1.1 km), drops them when a trace fails (across InfMap chunks it often does)
-- and never turns around for a target behind it. SkyOps keeps the target in
-- memory, sees it by radar instead of traces, and steers into a lead pursuit.

SkyOps.AIFlight = SkyOps.AIFlight or {}
SkyOps.Spawn = SkyOps.Spawn or {} -- sv_spawn.lua loads after this file

local M_TO_HU = SkyOps.M_TO_HU

local DETECT_RANGE = 40000  -- m, onboard radar / GCI picture
local KEEP_RANGE = 60000    -- m, drop the chase past this
local MIN_AGL = 2000        -- u above ground before we override stock steering

local function PickTarget( self, brain )
	local cur = brain.target
	if IsValid( cur ) and not cur:IsDestroyed() and cur:GetPos():Distance( self:GetPos() ) < KEEP_RANGE * M_TO_HU then
		return cur
	end

	local center = self:GetPos()
	if brain.task.escort then
		for _, e in ipairs( brain.task.escort ) do
			if IsValid( e ) then center = e:GetPos() break end
		end
	end

	local list = SkyOps.Radar.FindTargets( center, self:GetAITEAM(), DETECT_RANGE, 10 )
	brain.target = list[1] and list[1].ent or nil
	return brain.target
end

local function Steer( self, brain )
	local target = brain.target
	local goal

	if IsValid( target ) then
		if self:AITargetInFront( target, 65 ) then return end -- stock dogfight code handles this
		goal = target:GetPos() + target:GetVelocity() * 1.5
	elseif brain.task.attack then
		goal = brain.task.attack + Vector( 0, 0, brain.task.altitude or 15000 )
	else
		return
	end

	local pos = self:GetPos()
	local tr = util.TraceLine( { start = pos, endpos = pos - Vector( 0, 0, MIN_AGL ), filter = self:GetCrosshairFilterEnts() } )
	if tr.Hit then return end -- too low, let stock terrain avoidance fly

	self.smTargetPos = goal
	self._lvsAITargetAng = ( goal - pos ):GetNormalized():Angle()
	self:SetThrottle( 1 )
end

local MISSILE_MAX = 15000  -- m, AI launches inside this
local MISSILE_MIN = 800
local MISSILE_GAP = 8      -- s between AI missile shots

local function MissileWeapon( self )
	for id, w in pairs( self.WEAPONS and self.WEAPONS[1] or {} ) do
		local ok, name = pcall( function() return w.Icon:GetName() end )
		if ok and string.find( name or "", "missile", 1, true ) then return id end
	end
end

-- Stock LVS AI only fires guns inside 22 deg, so AI jets circled the player
-- without shooting. Inside missile range with the target ahead SkyOps selects
-- the missile; the jet's own seeker (weapon OnThink) locks, then it fires.
local function Missiles( self, brain )
	local target = brain.target
	if not IsValid( target ) then return end

	local dist = self:GetPos():Distance( target:GetPos() ) * SkyOps.HU_TO_M
	local id = brain.missileId or MissileWeapon( self )
	brain.missileId = id
	if not id or dist > MISSILE_MAX or dist < MISSILE_MIN or not self:AITargetInFront( target, 30 ) then return end

	if self:GetSelectedWeapon() ~= id then self:SelectWeapon( id ) end
	self._nextAISwitchWeapon = CurTime() + 3 -- keep stock code from switching back to guns

	local locked = isfunction( self.GetIsLocked ) and self:GetIsLocked() and self:GetClosestEnt() == target
	if locked and CurTime() > ( brain.nextMissile or 0 ) then
		self._AIFireInput = true
		brain.nextMissile = CurTime() + MISSILE_GAP
	else
		self._AIFireInput = false
	end
end

function SkyOps.AIFlight.Attach( ent, task )
	local brain = { task = task or {} }
	ent.SkyOpsBrain = brain

	local origCanSee = ent.AICanSee
	local origRun = ent.RunAI

	ent.AIGetTarget = function( self )
		local t = PickTarget( self, brain )
		self._LastAITarget = t or NULL
		return t or NULL
	end
	ent.AICanSee = function( self, other )
		if other == brain.target then return true end
		return origCanSee( self, other )
	end
	ent.RunAI = function( self )
		origRun( self )
		Steer( self, brain )
		Missiles( self, brain )
	end
end

local MIN_START_AGL = 1500 -- m
local START_SPEED = 250    -- m/s, ~900 km/h

-- task: { attack = pos, altitude = u } or { escort = { ents } }; opts: { groupId, team }
function SkyOps.Spawn.AIFlight( role, count, pos, task, opts )
	opts = opts or {}
	local data = SkyOps.Registry.GetAircraft( role )
	if not data then return {} end

	local team = opts.team or SkyOps.Teams.RED
	local ang = opts.ang or Angle( 0, 0, 0 )
	local flight = {}

	-- AI flights start airborne: at least MIN_START_AGL above the terrain,
	-- engine running and already at cruise speed (from a standstill they stall
	-- and fall, which is how they ended up lying on the ground)
	local M = SkyOps.M_TO_HU
	local agl = ( task and task.altitude ) or MIN_START_AGL * M
	pos = Vector( pos )
	local ground = SkyOps.Map.GroundZ( pos.x, pos.y, pos.z )
	if ground and pos.z < ground + agl then pos.z = ground + agl end

	for i = 1, ( count or 1 ) do
		-- echelon: each wingman 30 m right and 20 m behind the previous one
		local offset = ang:Right() * 1600 * ( i - 1 ) - ang:Forward() * 1000 * ( i - 1 )
		local ent = ents.Create( data.class )
		if not IsValid( ent ) then break end

		ent:SetPos( pos + offset )
		ent:SetAngles( ang )
		ent:Spawn()
		ent:Activate()
		ent:SetAITEAM( team )
		ent:SetAI( true )

		SkyOps.AIFlight.Attach( ent, task )
		timer.Simple( 0.2, function()
			if not IsValid( ent ) then return end
			if isfunction( ent.StartEngine ) then ent:StartEngine() end
			if isfunction( ent.SetThrottle ) then ent:SetThrottle( 1 ) end
			if isfunction( ent.RaiseLandingGear ) then ent:RaiseLandingGear() end
			local phys = ent:GetPhysicsObject()
			if IsValid( phys ) then phys:SetVelocity( ang:Forward() * START_SPEED * M ) end
		end )
		SkyOps.Units.Register( ent, opts.groupId, { role = role, team = team } )
		flight[ #flight + 1 ] = ent
	end

	return flight
end
