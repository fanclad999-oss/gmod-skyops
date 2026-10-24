-- SAM brain: runs every air-defense site that has no player gunner.
-- Search -> track (lock takes LockTime) -> launch inside engage range, using
-- the vehicle's own missile weapon so damage, guidance and effects stay stock.

SkyOps.SAM = SkyOps.SAM or {}

local LOCK_TIME = { s75 = 6, tor_m1 = 3, osa = 4, roland = 4 }
local SHOT_GAP = { s75 = 8, tor_m1 = 3, osa = 5, roland = 5 }

local function HasPlayerGunner( site )
	if not isfunction( site.GetEveryone ) then return false end
	for _, ply in ipairs( site:GetEveryone() ) do
		if IsValid( ply ) and ply:IsPlayer() then return true end
	end
	return false
end

local function FindMissileWeapon( launcher )
	local fallback
	for _, pod in pairs( launcher.WEAPONS or {} ) do
		for _, w in ipairs( pod ) do
			if not isfunction( w.Attack ) then continue end
			local ok, name = pcall( function() return w.Icon:GetName() end )
			if ok and string.find( name or "", "missile", 1, true ) then return w end
			-- SAM missiles are the only limited-ammo weapons on these vehicles
			if w.Ammo and w.Ammo > 0 then fallback = fallback or w end
		end
	end
	return fallback
end

-- state changes for debugging: search / track / lock / launch / error / noweapon
local function State( site, st, state, target, extra )
	if st.lastState == state and st.lastStateTarget == target then return end
	st.lastState, st.lastStateTarget = state, target
	hook.Run( "SkyOps.SAMState", site, state, target, extra )
end

-- stands in for the gunner's weapon handler the stock Attack functions expect
local function Handler( launcher )
	return {
		GetVehicle = function() return launcher end,
		GetDriver = function() return NULL end,
		TakeAmmo = function() end,
		SetHeat = function() end,
		GetAmmo = function() return 1 end,
	}
end

-- The stock radar/seeker weapon OnThink clears IsLocked/ClosestEnt every tick
-- while no gunner aims it, and the vehicle's OnTick cuts missile guidance as
-- soon as IsLocked is false. On an AI-run site only SkyOps may write them.
local function TakeLockControl( ctrl )
	if ctrl.SkyOpsLockControl then return end
	ctrl.SkyOpsLockControl = true
	for _, name in ipairs( { "SetIsLocked", "SetClosestEnt" } ) do
		local orig = ctrl[ name ]
		if not isfunction( orig ) then continue end
		ctrl[ name ] = function( self, v )
			if self.SkyOpsAI and not self.SkyOpsWriting then return end
			return orig( self, v )
		end
	end
end

local function SetLock( ctrl, ent, locked )
	ctrl.SkyOpsWriting = true
	ctrl:SetClosestEnt( ent )
	ctrl:SetIsLocked( locked )
	ctrl.SkyOpsWriting = nil
end

local function SetRadar( ctrl, on )
	if isfunction( ctrl.SetRadar ) and ctrl:GetRadar() ~= on then
		ctrl:SetRadar( on )
		ctrl:SetRadarWorking( on )
	end
end

local function Think( site, info, data, now )
	local parts = info.parts or {}
	local ctrl = parts.snr75 or site       -- the entity that owns ClosestEnt/IsLocked
	local launcher = parts.launcher or site
	if not ( IsValid( ctrl ) and IsValid( launcher ) ) then return end

	local st = info.sam or {}
	info.sam = st

	TakeLockControl( ctrl )
	ctrl.SkyOpsAI = true
	SetRadar( ctrl, true )

	local radarPos = ( IsValid( parts.p12_radar ) and parts.p12_radar or ctrl ):GetPos()
	local antenna = ctrl:GetPos() + Vector( 0, 0, data.radar.mast * SkyOps.M_TO_HU )
	local target
	for _, c in ipairs( SkyOps.Radar.FindTargets( radarPos, info.team, data.radar.search, data.radar.mast ) ) do
		if SkyOps.Radar.LineOfSight( antenna, c.ent ) then
			target = c
			break
		end
	end

	if not target then
		State( site, st, "search" )
		if st.target then SetLock( ctrl, NULL, false ) end
		st.target = nil
		site.SkyOpsTarget = nil
		return
	end

	if st.target ~= target.ent then
		st.target = target.ent
		st.lockStart = now
	end
	SetLock( ctrl, target.ent, false )
	site.SkyOpsTarget = target.ent

	if now - st.lockStart < ( LOCK_TIME[ info.system ] or 4 ) then
		State( site, st, "track", target.ent, math.Round( target.dist ) )
		return
	end
	SetLock( ctrl, target.ent, true )
	State( site, st, "lock", target.ent, math.Round( target.dist ) )

	if target.dist > data.radar.engage then return end
	if now < ( st.nextShot or 0 ) then return end
	if IsValid( ctrl:GetNWEntity( "Missile" ) ) or IsValid( launcher:GetNWEntity( "Missile" ) ) then return end
	if launcher:GetClass() == "sw_s75" and not launcher:GetNWBool( "Loaded", true ) then return end

	st.weapon = st.weapon or FindMissileWeapon( launcher )
	if not st.weapon then State( site, st, "noweapon" ) return end

	st.ammo = st.ammo or ( st.weapon.Ammo and st.weapon.Ammo > 0 and st.weapon.Ammo or 6 )
	if st.ammo <= 0 then return end

	local ok, err = pcall( st.weapon.Attack, Handler( launcher ) )
	if not ok then
		ErrorNoHalt( "[SkyOps] SAM " .. info.system .. " launch failed: " .. tostring( err ) .. "\n" )
		State( site, st, "error", target.ent, tostring( err ) )
	else
		State( site, st, "launch", target.ent, math.Round( target.dist ) )
	end
	st.ammo = st.ammo - 1
	st.nextShot = now + ( SHOT_GAP[ info.system ] or 5 )
	hook.Run( "SkyOps.SAMLaunch", site, target.ent, info.system )
end

timer.Create( "SkyOps.SAM", 0.25, 0, function()
	local now = CurTime()
	for site, info in pairs( SkyOps.Units.list ) do
		local data = info.system and SkyOps.Registry.GetAirDefense( info.system )
		if not ( IsValid( site ) and data and data.radar ) then continue end
		local ctrl = info.parts and IsValid( info.parts.snr75 ) and info.parts.snr75 or site
		if HasPlayerGunner( site ) or HasPlayerGunner( ctrl ) then
			ctrl.SkyOpsAI = false  -- a player runs it: stock lock logic again
			continue
		end

		Think( site, info, data, now )
	end
end )
