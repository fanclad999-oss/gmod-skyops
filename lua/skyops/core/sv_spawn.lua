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

-- system: key of Registry.AirDefense; opts: { team, groupId, ang }
function SkyOps.Spawn.AirDefense( system, pos, opts )
	opts = opts or {}
	local data = Registry.GetAirDefense( system )
	if not data then return NULL end

	local ent = SpawnClass( data.spawn, pos, opts.ang, opts.team or SkyOps.Teams.RED )
	if IsValid( ent ) then
		SkyOps.Units.Register( ent, opts.groupId )
	end

	return ent
end

-- role: key of Registry.Aircraft; loadout: LVS weapon/loadout index, nil = default
function SkyOps.Spawn.PlayerJet( role, pos, ang, loadout )
	local data = Registry.GetAircraft( role )
	if not data then return NULL end

	return SpawnClass( data.class, pos, ang, SkyOps.Teams.BLUE )
end

-- TODO step 5: AI fighters with a SkyOps brain on top of LVS AI
function SkyOps.Spawn.AIFlight( role, count, pos, task )
	return {}
end

-- TODO step 3: ground column driven along a route of positions
function SkyOps.Spawn.Convoy( class, count, route )
	return {}
end
