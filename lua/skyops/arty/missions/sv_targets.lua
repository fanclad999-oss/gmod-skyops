-- Artillery missions, targets: picking spots on the terrain, spawning frozen target props
-- far away, judging bursts against them, and moving the survivors of a fleeting target.
-- Targets take no engine damage: only M.Damage from an impact point counts, so a hit is
-- the same 30 km away in an empty InfMap chunk as next to a player.

local M = SkyOps.Arty.Missions
local Grid = SkyOps.Arty.Grid

M.Targets = M.Targets or {}

local T = M.Targets

local FALLBACK_MODEL = "models/props_junk/TrashDumpster01a.mdl"
local MOVE_SPEED = 8 -- m/s of a target driving to a new spot

-- Spots ------------------------------------------------------------------------------

-- terrain height at grid x, y if the spot is on the map and flat enough for vehicles
function T.FlatHeight( x, y, step, maxDiff )
	step, maxDiff = step or 15, maxDiff or 5

	local h = Grid.Height( x, y )

	if not h then return nil end

	for _, d in ipairs( { { step, 0 }, { -step, 0 }, { 0, step }, { 0, -step } } ) do
		local h2 = Grid.Height( x + d[ 1 ], y + d[ 2 ] )

		if not h2 or math.abs( h2 - h ) > maxDiff then return nil end
	end

	return h
end

-- a random flat spot dist (min..max) metres from x, y along bearing (mils) +- spread;
-- nil after `tries` failures
function T.FindSpot( x, y, minDist, maxDist, bearing, spread, tries )
	local minX, minY, maxX, maxY = Grid.Bounds()
	local margin = 500

	for _ = 1, tries or 60 do
		local b = ( bearing or math.Rand( 0, 6000 ) ) + math.Rand( -( spread or 3000 ), spread or 3000 )
		local r = math.Rand( minDist, maxDist )
		local a = b / 6000 * 2 * math.pi
		local px, py = x + math.sin( a ) * r, y + math.cos( a ) * r

		if px > minX + margin and px < maxX - margin and py > minY + margin and py < maxY - margin then
			local h = T.FlatHeight( px, py )

			if h then return px, py, h end
		end
	end
end

-- Spawning ---------------------------------------------------------------------------

local function ModelOr( model )
	if model and util.IsValidModel( model ) then return model end

	return FALLBACK_MODEL
end

local function GroundPos( x, y )
	return Grid.FromGrid( x, y ) + Vector( 0, 0, 2 )
end

local function Freeze( ent )
	local phys = ent:GetPhysicsObject()

	if IsValid( phys ) then
		phys:EnableMotion( false )
		phys:Sleep()
	end
end

-- puts the model's lowest point on the terrain at x, y and turns it to yaw
local function Place( ent, x, y, yaw )
	local pos = GroundPos( x, y )
	local mins = ent:OBBMins()

	ent:SetAngles( Angle( 0, yaw, 0 ) )
	ent:SetPos( pos - Vector( 0, 0, mins.z ) )
end

local function SpawnEnt( kind, x, y, yaw )
	if kind.lvs then
		for _, class in ipairs( kind.lvs ) do
			if scripted_ents.GetStored( class ) then
				local ent = ents.Create( class )

				if IsValid( ent ) then
					ent:SetPos( GroundPos( x, y ) + Vector( 0, 0, 40 ) )
					ent:SetAngles( Angle( 0, yaw, 0 ) )
					ent:Spawn()
					ent:Activate()

					if isfunction( ent.SetAITEAM ) then ent:SetAITEAM( SkyOps.Teams and SkyOps.Teams.RED or 2 ) end
					if isfunction( ent.SetAI ) then ent:SetAI( false ) end

					Freeze( ent )

					return ent
				end
			end
		end
	end

	local ent = ents.Create( "prop_physics" )

	if not IsValid( ent ) then return NULL end

	ent:SetModel( ModelOr( kind.model ) )
	ent:Spawn()
	ent:Activate()
	Place( ent, x, y, yaw )
	Freeze( ent )

	return ent
end

-- spawns the group of mission def around grid x, y; -> list of target records
--   { ent, kind, kindId, name, x, y, h, hp, armor, size, alive, required }
function T.SpawnGroup( def, cx, cy )
	local list = {}
	local axis = math.Rand( 0, 360 ) -- the column stands roughly along one road direction
	local spread = def.spread or 80
	local placed = {}

	for kindId, count in SortedPairs( def.group ) do
		local kind = M.TargetKinds[ kindId ]

		for _ = 1, count do
			if kind then
				local x, y

				-- spread the vehicles out, at least 15 m apart
				for _ = 1, 25 do
					local along = math.Rand( -spread, spread )
					local side = math.Rand( -spread, spread ) * 0.35
					local a = math.rad( axis )
					local tx, ty = cx + math.cos( a ) * along - math.sin( a ) * side, cy + math.sin( a ) * along + math.cos( a ) * side
					local ok = Grid.Height( tx, ty ) ~= nil

					for _, p in ipairs( placed ) do
						if ( p[ 1 ] - tx ) ^ 2 + ( p[ 2 ] - ty ) ^ 2 < 15 * 15 then ok = false break end
					end

					if ok then x, y = tx, ty break end
				end

				if x then
					placed[ #placed + 1 ] = { x, y }

					local ent = SpawnEnt( kind, x, y, axis + math.Rand( -25, 25 ) )
					local size = 3

					if IsValid( ent ) then
						local mins, maxs = ent:OBBMins(), ent:OBBMaxs()

						size = math.max( maxs.x - mins.x, maxs.y - mins.y ) / Grid.UPM() / 2
					end

					local t = {
						ent = ent,
						kindId = kindId,
						name = kind.name,
						x = x, y = y, h = Grid.Height( x, y ) or 0,
						hp = 100,
						armor = ( def.armorOverride and def.armorOverride[ kindId ] ) or kind.armor,
						size = math.Clamp( size, 1, 8 ),
						score = kind.score or 100,
						hvt = kind.hvt,
						required = def.required and def.required[ kindId ] or nil,
						alive = true,
					}

					if IsValid( ent ) then ent.SkyOpsArty_Target = t end

					list[ #list + 1 ] = t
				end
			end
		end
	end

	return list
end

function T.RemoveAll( list )
	for _, t in ipairs( list or {} ) do
		if IsValid( t.ent ) then t.ent:Remove() end
	end
end

-- targets take damage only from M.Damage
hook.Add( "EntityTakeDamage", "SkyOps.Arty.Missions.Targets", function( ent )
	if ent.SkyOpsArty_Target then return true end
end )

-- Damage -----------------------------------------------------------------------------

local function Wreck( t, attacker )
	t.alive = false
	t.hp = 0
	t.killedAt = CurTime()

	local ent = t.ent

	if not IsValid( ent ) then return end

	if ent.LVS then
		-- an LVS vehicle: let it blow up properly
		ent.SkyOpsArty_Target = nil
		Freeze( ent )
		ent:TakeDamage( 100000, IsValid( attacker ) and attacker or game.GetWorld(), game.GetWorld() )
		return
	end

	ent:SetColor( Color( 45, 40, 36 ) )
	ent:Ignite( 180, 0 )

	-- tilt it a bit, like a burnt-out wreck
	local ang = ent:GetAngles()

	ent:SetAngles( Angle( math.Rand( -6, 6 ), ang.y + math.Rand( -10, 10 ), math.Rand( -8, 8 ) ) )
end

-- applies a burst at grid x, y to all targets; -> { killed = {t...}, damaged = {t...},
-- nearest = t, nearestDist = m (to the edge of the nearest live target before the burst) }
function T.Burst( list, x, y, shellId, attacker )
	local res = { killed = {}, damaged = {} }

	for _, t in ipairs( list ) do
		if t.alive then
			local d = math.max( math.sqrt( ( t.x - x ) ^ 2 + ( t.y - y ) ^ 2 ) - t.size, 0 )

			if not res.nearestDist or d < res.nearestDist then
				res.nearest, res.nearestDist = t, d
			end

			local dmg = M.Damage( t.armor, d, shellId ) * math.Rand( 0.8, 1.2 )

			if dmg > 1 then
				t.hp = t.hp - dmg
				res.damaged[ #res.damaged + 1 ] = t

				if t.hp <= 0 then
					Wreck( t, attacker )
					res.killed[ #res.killed + 1 ] = t
				end
			end
		end
	end

	return res
end

function T.CountAlive( list )
	local n = 0

	for _, t in ipairs( list ) do
		if t.alive then n = n + 1 end
	end

	return n
end

-- grid centre of the live targets (or of all of them)
function T.Center( list )
	local sx, sy, n = 0, 0, 0

	for _, t in ipairs( list ) do
		if t.alive then sx, sy, n = sx + t.x, sy + t.y, n + 1 end
	end

	if n == 0 then
		for _, t in ipairs( list ) do sx, sy, n = sx + t.x, sy + t.y, n + 1 end
	end

	if n == 0 then return nil end

	return sx / n, sy / n
end

-- the live target nearest to grid x, y and the distance to it
function T.Nearest( list, x, y )
	local best, bestD

	for _, t in ipairs( list ) do
		if t.alive then
			local d = math.sqrt( ( t.x - x ) ^ 2 + ( t.y - y ) ^ 2 )

			if not bestD or d < bestD then best, bestD = t, d end
		end
	end

	return best, bestD
end

-- Fleeting targets --------------------------------------------------------------------

-- sends the survivors to a new spot dist metres away; they drive there at MOVE_SPEED
function T.Relocate( list, dist )
	local cx, cy = T.Center( list )

	if not cx then return nil end

	local nx, ny = T.FindSpot( cx, cy, dist * 0.7, dist * 1.3 )

	if not nx then return nil end

	for _, t in ipairs( list ) do
		if t.alive then
			local ox, oy = t.x - cx, t.y - cy

			t.move = { fx = t.x, fy = t.y, tx = nx + ox, ty = ny + oy, start = CurTime() }
			t.move.time = math.sqrt( ( t.move.tx - t.x ) ^ 2 + ( t.move.ty - t.y ) ^ 2 ) / MOVE_SPEED
		end
	end

	return nx, ny
end

-- moves the driving targets; call from Think
function T.Think( list )
	for _, t in ipairs( list ) do
		local mv = t.move

		if mv and t.alive then
			local f = math.Clamp( ( CurTime() - mv.start ) / math.max( mv.time, 1 ), 0, 1 )

			t.x = mv.fx + ( mv.tx - mv.fx ) * f
			t.y = mv.fy + ( mv.ty - mv.fy ) * f

			-- move the prop twice a second, that is enough for a drone camera
			if IsValid( t.ent ) and CurTime() > ( t.nextMove or 0 ) then
				t.nextMove = CurTime() + 0.5

				local dir = Grid.FromGrid( mv.tx, mv.ty, 0 ) - Grid.FromGrid( mv.fx, mv.fy, 0 )

				Place( t.ent, t.x, t.y, math.deg( math.atan2( dir.y, dir.x ) ) )
			end

			if f >= 1 then
				t.move = nil
				t.h = Grid.Height( t.x, t.y ) or t.h
			end
		end
	end
end
