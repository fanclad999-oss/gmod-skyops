-- Tracks mission units and fires SkyOps.UnitKilled( ent, groupId, attacker ).

SkyOps.Units = SkyOps.Units or { list = {} }

-- info: optional extra fields, e.g. { system, team, parts } for air defense
function SkyOps.Units.Register( ent, groupId, info )
	info = info or {}
	info.groupId = groupId
	SkyOps.Units.list[ ent ] = info
end

local function OnKilled( ent, attacker )
	local info = SkyOps.Units.list[ ent ]
	if not info then return end

	SkyOps.Units.list[ ent ] = nil
	hook.Run( "SkyOps.UnitKilled", ent, info.groupId, attacker )
end

hook.Add( "LVS.OnVehicleDestroyed", "SkyOps.UnitKilled", function( ent, attacker )
	OnKilled( ent, attacker )
end )

hook.Add( "EntityRemoved", "SkyOps.UnitKilled", function( ent )
	SkyOps.Units.list[ ent ] = nil
end )
