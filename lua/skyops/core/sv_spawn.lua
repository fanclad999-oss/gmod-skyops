-- Spawn API used by missions. Stubs for now: signatures are agreed with
-- the missions module, behaviour lands step by step (see docs/plan.md).

SkyOps.Spawn = SkyOps.Spawn or {}

local Registry = SkyOps.Registry

local function SpawnClass( class, pos, ang, team )
	local ent = ents.Create( class )
	if not IsValid( ent ) then
		ErrorNoHalt( "[SkyOps] cannot create " .. tostring( class ) .. ", is the addon installed?\n" )
		return NULL
	end

	ent:SetPos( pos )
	ent:SetAngles( ang or angle_zero )
	ent:Spawn()
	ent:Activate()

	if team and isfunction( ent.SetAITEAM ) then
		ent:SetAITEAM( team )
	end

	return ent
end

-- Collects the extra entities a site builds in its own OnSpawn (S-75 makes
-- its launcher and P-12 radar there). LVS runs OnSpawn one tick after Spawn().
local function CollectParts( ent, data, parts )
	parts[ "main" ] = ent
	if not data.parts then return end

	for key, class in pairs( data.parts ) do
		if class == ent:GetClass() then
			parts[ key ] = ent
		elseif ent:GetNWEntity( "Launcher" ):IsValid() and ent:GetNWEntity( "Launcher" ):GetClass() == class then
			parts[ key ] = ent:GetNWEntity( "Launcher" )
		else
			-- the P-12 only points back at its SNR-75
			for _, other in ipairs( ents.FindByClass( class ) ) do
				if other:GetNWEntity( "Radar" ) == ent then parts[ key ] = other break end
			end
		end
	end
end

-- system: key of Registry.AirDefense; opts: { team, groupId, ang, part, count, follow }
-- Returns the main entity and a parts table ({ main, snr75, launcher, p12_radar })
-- that is filled once the site has finished spawning; SkyOps.AirDefenseReady
-- ( main, parts, groupId ) fires at the same moment.
function SkyOps.Spawn.AirDefense( system, pos, opts )
	opts = opts or {}
	local data = Registry.GetAirDefense( system )
	if not data then return NULL, {} end

	local parts = {}
	local ent = ents.Create( data.spawn )
	if not IsValid( ent ) then
		ErrorNoHalt( "[SkyOps] cannot create " .. tostring( data.spawn ) .. ", is the addon installed?\n" )
		return NULL, parts
	end

	local team = opts.team or SkyOps.Teams.RED
	local origFinish = ent.OnSpawnFinish
	ent.OnSpawnFinish = function( self, PObj )
		if origFinish then origFinish( self, PObj ) end

		CollectParts( self, data, parts )
		for _, part in pairs( parts ) do
			if isfunction( part.SetAITEAM ) then part:SetAITEAM( team ) end
		end
		hook.Run( "SkyOps.AirDefenseReady", self, parts, opts.groupId )
	end

	ent:SetPos( pos )
	ent:SetAngles( opts.ang or angle_zero )
	ent:Spawn()
	ent:Activate()
	if isfunction( ent.SetAITEAM ) then ent:SetAITEAM( team ) end

	SkyOps.Units.Register( ent, opts.groupId, { system = system, team = team, parts = parts } )

	return ent, parts
end

-- role: key of Registry.Aircraft; loadout: LVS weapon/loadout index, nil = default
function SkyOps.Spawn.PlayerJet( role, pos, ang, loadout )
	local data = Registry.GetAircraft( role )
	if not data then return NULL end

	return SpawnClass( data.class, pos, ang, SkyOps.Teams.BLUE )
end

-- SkyOps.Spawn.AIFlight lives in sv_ai_flight.lua

-- route: list of world positions; opts: { groupId, team }
-- TODO step 3: ground column driven along the route
function SkyOps.Spawn.Convoy( class, count, route, opts )
	return {}
end
