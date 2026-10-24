-- Radar warning: tells each crew which SAM radars see them.
-- net "skyops_rwr": UInt(8) N, then N x { Vector radar pos, String system, UInt(2) state }
-- state 0 = search (painted), 1 = tracking (locked), 2 = missile in flight at you.
-- Detection: search range plus radar horizon (SkyOps.Radar.InHorizon), so
-- flying low behind the horizon really hides you.

util.AddNetworkString( "skyops_rwr" )

local STATE_SEARCH, STATE_TRACK, STATE_LAUNCH = 0, 1, 2

local function RadarOn( ent, system )
	if system == "s75" then return true end -- SNR-75/P-12 have no on/off switch
	if isfunction( ent.GetRadarWorking ) then return ent:GetRadarWorking() end
	return true
end

local function IsTracking( ent, jet )
	if isfunction( ent.GetClosestEnt ) then return ent:GetClosestEnt() == jet end
	return ent.SkyOpsTarget == jet -- set by the SkyOps SAM brain
end

local function MissileAt( jet, site, parts )
	for _, cls in ipairs( { "sw_base_rocket_v3" } ) do
		for _, m in ipairs( ents.FindByClass( cls ) ) do
			if m.target == jet and ( m.Launcher == site or m.Launcher == parts.launcher ) then return true end
		end
	end
	return false
end

local function CrewOf( jet )
	if isfunction( jet.GetEveryone ) then return jet:GetEveryone() end
	local d = jet:GetDriver()
	return IsValid( d ) and { d } or {}
end

timer.Create( "SkyOps.RWR", 0.5, 0, function()
	local jets = {}
	for _, ply in ipairs( player.GetAll() ) do
		local jet = isfunction( ply.lvsGetVehicle ) and ply:lvsGetVehicle() or NULL
		if IsValid( jet ) and isfunction( jet.GetVehicleType ) then
			local t = jet:GetVehicleType()
			if t == "plane" or t == "helicopter" then jets[ jet ] = true end
		end
	end
	if not next( jets ) then return end

	for jet in pairs( jets ) do
		local contacts = {}
		local jetPos = jet:GetPos()
		local jetTeam = isfunction( jet.GetAITEAM ) and jet:GetAITEAM() or SkyOps.Teams.BLUE

		for site, info in pairs( SkyOps.Units.list ) do
			local data = info.system and SkyOps.Registry.GetAirDefense( info.system )
			if not ( IsValid( site ) and data and data.radar ) then continue end
			if info.team == jetTeam or not RadarOn( site, info.system ) then continue end

			local radarEnt = info.parts and info.parts.p12_radar or site
			if not IsValid( radarEnt ) then radarEnt = site end
			if not SkyOps.Radar.InHorizon( radarEnt:GetPos(), data.radar.mast, jetPos, data.radar.search ) then continue end

			local state = STATE_SEARCH
			if MissileAt( jet, site, info.parts or {} ) then
				state = STATE_LAUNCH
			elseif IsTracking( site, jet ) then
				state = STATE_TRACK
			end

			contacts[ #contacts + 1 ] = { pos = site:GetPos(), system = info.system, state = state }
			if #contacts >= 255 then break end
		end

		local crew = CrewOf( jet )
		if #crew == 0 then continue end

		net.Start( "skyops_rwr" )
			net.WriteUInt( #contacts, 8 )
			for _, c in ipairs( contacts ) do
				net.WriteVector( c.pos )
				net.WriteString( c.system )
				net.WriteUInt( c.state, 2 )
			end
		net.Send( crew )
	end
end )
