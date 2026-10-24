-- Proximity fuze for missiles against aircraft.
-- A missile at 500 m/s moves ~300 u per tick, but SW Bombs checks its radio
-- fuze with FindInSphere( 150 u ) once per tick, so most missiles flew
-- straight through the target. Here the closest approach to the target is
-- predicted every tick; if it falls inside the warhead's lethal radius before
-- the next tick, the missile is moved to that point and detonated.

SkyOps.Fuze = SkyOps.Fuze or { missiles = {} }

local missiles = SkyOps.Fuze.missiles

hook.Add( "OnEntityCreated", "SkyOps.Fuze", function( ent )
	timer.Simple( 0, function()
		if IsValid( ent ) and ent.IsRocket then missiles[ ent ] = true end
	end )
end )

-- fragments and blast reach this far, so the fuze fires a bit inside it
local function LethalRadius( mis )
	local r = math.max( mis.BlastRadius or 0, mis.FragRadius or 0, mis.ExplosionRadius or 0 )
	return r * 0.8
end

local function Detonate( mis, pos, target, miss )
	mis:SetPos( pos )
	mis.Exploded = true
	mis:Explode( pos )
	hook.Run( "SkyOps.MissileFuzed", mis, target, miss )
end

hook.Add( "Tick", "SkyOps.Fuze", function()
	local dt = engine.TickInterval()

	for mis in pairs( missiles ) do
		if not IsValid( mis ) or mis.Exploded then missiles[ mis ] = nil continue end
		if not ( mis.Armed and mis.Fired ) then continue end
		if not ( isfunction( mis.GetRadioFuze ) and mis:GetRadioFuze() ) then continue end

		local target = mis.target
		if not SkyOps.Radar.IsAircraft( target ) then continue end

		local radius = LethalRadius( mis )
		if radius <= 0 then continue end

		local pos = mis:GetPos()
		local rel = target:WorldSpaceCenter() - pos
		local closing = mis:GetVelocity() - target:GetVelocity()
		local w2 = closing:LengthSqr()
		if w2 < 1 then continue end

		local tc = rel:Dot( closing ) / w2
		if tc < 0 then
			-- already past the closest point: burst if still inside the radius
			local dist = rel:Length()
			if dist < radius then Detonate( mis, pos, target, dist ) end
		elseif tc <= dt * 1.5 then
			local miss = ( rel - closing * tc ):Length()
			if miss < radius then Detonate( mis, pos + mis:GetVelocity() * tc, target, miss ) end
		end
	end
end )
