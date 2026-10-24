-- Sides. All SW vehicles ship with ENT.AITEAM = 2, so the side is set per spawn.
--
-- Team vs team (convar skyops_tvt 1): players pick BLUE or RED, every vehicle a player
-- spawns or takes gets the player's side (NW2Int SkyOps_Team), and what one side knows
-- (map marks, targets, coordinates, laser spots, radio) is hidden from the other.
-- With skyops_tvt 0 every check here says "friendly", so solo and co-op work as before.
-- Picking a side, tagging and the HUD are in arty/tvt.

SkyOps.Teams = SkyOps.Teams or {}

local T = SkyOps.Teams

T.BLUE = 1 -- players (team vs team: the first player side)
T.RED = 2  -- enemy air defense and aircraft (team vs team: the second player side)

T.NAMES = { [ 1 ] = "Синие", [ 2 ] = "Красные" }
T.COLORS = { [ 1 ] = Color( 90, 160, 255 ), [ 2 ] = Color( 255, 95, 85 ) }

T.NW = "SkyOps_Team"

T.cvTvT = CreateConVar( "skyops_tvt", "0", bit.bor( FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY ),
	"1 = режим команда на команду: команды не видят меток, целей, координат и подсветки друг друга", 0, 1 )

function T.TvT()
	return T.cvTvT:GetBool()
end

function T.Name( team )
	return T.NAMES[ team ] or "без команды"
end

-- side of a player or an entity, 0 = none (neutral: seen and used by everybody).
-- Seats, drone control stations and other parts take the side of what they belong to.
function T.Of( ent )
	if not IsValid( ent ) then return 0 end

	local t = ent:GetNW2Int( T.NW, 0 )

	if t ~= 0 or ent:IsPlayer() then return t end

	local base = ent.lvsGetVehicle and ent:lvsGetVehicle()

	if not IsValid( base ) or base == ent then base = ent:GetParent() end
	if not IsValid( base ) then base = ent:GetNWEntity( "UAV" ) end -- sw_uav_control -> its drone

	if IsValid( base ) and base ~= ent then return base:GetNW2Int( T.NW, 0 ) end

	return 0
end

if SERVER then
	function T.Set( ent, team )
		if not IsValid( ent ) then return end

		ent:SetNW2Int( T.NW, team or 0 )
	end
end

-- same side, or one of them neutral, or team vs team is off
function T.Friendly( a, b )
	if not T.TvT() then return true end

	local ta, tb = T.Of( a ), T.Of( b )

	return ta == 0 or tb == 0 or ta == tb
end

-- may this player see the marks of this entity (map, HUD, laser spot, targets)?
-- A player without a side sees only neutral things while team vs team is on.
function T.CanSee( ply, ent )
	if not T.TvT() then return true end

	local te = T.Of( ent )

	return te == 0 or te == T.Of( ply )
end

-- players who hear about something of this side (a team number or an entity):
-- everybody when team vs team is off or the side is neutral
function T.Recipients( team )
	if not isnumber( team ) then team = T.Of( team ) end

	local list = {}

	for _, ply in ipairs( player.GetAll() ) do
		if not T.TvT() or team == 0 or T.Of( ply ) == team then list[ #list + 1 ] = ply end
	end

	return list
end
