-- Anti-radiation mode for the Su-34's Kh-31 (loadout 34 becomes Kh-31P).
-- The stock missile flies at whatever the WSO camera points at. If an enemy
-- radar is emitting inside the seeker cone at launch, SkyOps retargets the
-- missile onto that radar instead. A real Kh-31P keeps flying to the last
-- known emitter position when the radar shuts down, and so does this one.

SkyOps.ARM = SkyOps.ARM or {}

local M_TO_HU = SkyOps.M_TO_HU

local ARM_CLASSES = { sw_rocket_kh31_v3 = true }
local SEEKER_CONE = 30      -- degrees off the missile nose
local SEEKER_RANGE = 110000 -- m, Kh-31P launch range

-- emitters are SAM entities with their radar on: SNR-75/P-12 always, the rest by switch
local function Emitting( ent )
	if not IsValid( ent ) then return false end
	if isfunction( ent.GetRadarWorking ) then return ent:GetRadarWorking() end
	local c = ent:GetClass()
	return c == "sw_snr75" or c == "sw_p12"
end

function SkyOps.ARM.FindEmitter( fromPos, forward, team )
	local best, bestAng
	for site, info in pairs( SkyOps.Units.list ) do
		if not info.system or info.team == team then continue end

		local candidates = { site }
		if info.parts then
			candidates = { info.parts.snr75 or site, info.parts.p12_radar }
		end

		for _, ent in ipairs( candidates ) do
			if not Emitting( ent ) then continue end

			local dir = ent:WorldSpaceCenter() - fromPos
			if dir:Length() > SEEKER_RANGE * M_TO_HU then continue end

			local ang = math.deg( math.acos( math.Clamp( forward:Dot( dir:GetNormalized() ), -1, 1 ) ) )
			if ang < SEEKER_CONE and ( not bestAng or ang < bestAng ) then
				best, bestAng = ent, ang
			end
		end
	end
	return best
end

local function Retarget( mis )
	local launcher = mis.Launcher
	if not IsValid( launcher ) then return end

	local team = isfunction( launcher.GetAITEAM ) and launcher:GetAITEAM() or SkyOps.Teams.BLUE
	local emitter = SkyOps.ARM.FindEmitter( mis:GetPos(), mis:GetForward(), team )
	if not emitter then return end

	local lastPos = emitter:WorldSpaceCenter()
	mis.target = emitter
	mis.targetOffset = emitter:WorldToLocal( lastPos )
	mis.SkyOpsARM = emitter
	mis.calcTarget = function( r )
		if Emitting( emitter ) then lastPos = emitter:WorldSpaceCenter() end
		return lastPos
	end

	hook.Run( "SkyOps.ARMLaunch", mis, emitter, launcher )
end

hook.Add( "OnEntityCreated", "SkyOps.ARM", function( ent )
	if not ARM_CLASSES[ ent:GetClass() ] then return end
	-- the Su-34 sets mis.Launcher and starts guidance 0.5 s after creating it
	timer.Simple( 0.6, function()
		if IsValid( ent ) then Retarget( ent ) end
	end )
end )
