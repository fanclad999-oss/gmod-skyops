-- Real-world lock ranges for Ryuunosuke vehicles. Out of the box their seekers
-- are tuned for small maps (Su-34: 20000 u = 380 m), which on a 1:1 map makes
-- missiles drop lock almost at once. Values are lock/tracking ranges in metres.

local M_TO_HU = SkyOps.M_TO_HU

SkyOps.SeekerRange = {
	sw_su34 = 12000,      -- R-73 IR lock, R-27R needs the radar anyway
	sw_su25sm3 = 8000,    -- R-73 only
	sw_f14a = 20000,      -- AWG-9 + AIM-7/AIM-54, capped for gameplay
	sw_tornado = 8000,    -- AIM-9
	sw_snr75 = 45000,     -- SNR-75 fire control
	sw_torm1 = 12000,
	sw_9k33m3 = 10000,
	sw_flarakpz1 = 8000,
}

-- original CanSeeMis gives up past 75000 u (1.4 km) and is blocked by any prop
local function CanSeeMis( self, target )
	local att = self:GetAttachment( self:LookupAttachment( "view" ) )
	local from = att and att.Pos or self:WorldSpaceCenter()
	return SkyOps.Radar.LineOfSight( from, target )
end

local function Apply( ent )
	local range = SkyOps.SeekerRange[ ent:GetClass() ]
	if not range or not isfunction( ent.SetSeekerDist ) then return end

	ent:SetSeekerDist( range * M_TO_HU )
	if isfunction( ent.CanSeeMis ) then ent.CanSeeMis = CanSeeMis end
end

hook.Add( "OnEntityCreated", "SkyOps.Realism", function( ent )
	if not SkyOps.SeekerRange[ ent:GetClass() ] then return end
	-- LVS runs OnSpawn (which sets the stock range) one tick after creation
	timer.Simple( 0.5, function()
		if IsValid( ent ) then Apply( ent ) end
	end )
end )
