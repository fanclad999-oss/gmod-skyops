-- AI pilots on top of LVS AI. Stock LVS AI only sees targets within 60000 u
-- (1.1 km), drops them when a trace fails (across InfMap chunks it often does)
-- and never turns around for a target behind it. SkyOps keeps the target in
-- memory, sees it by radar instead of traces, and steers into a lead pursuit.

SkyOps.AIFlight = SkyOps.AIFlight or {}

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
	end
end

-- task: { attack = pos, altitude = u } or { escort = { ents } }; opts: { groupId, team }
function SkyOps.Spawn.AIFlight( role, count, pos, task, opts )
	opts = opts or {}
	local data = SkyOps.Registry.GetAircraft( role )
	if not data then return {} end

	local team = opts.team or SkyOps.Teams.RED
	local ang = opts.ang or Angle( 0, 0, 0 )
	local flight = {}

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
		SkyOps.Units.Register( ent, opts.groupId, { role = role, team = team } )
		flight[ #flight + 1 ] = ent
	end

	return flight
end
