-- SkyOps: проверка задач миссии (server)
-- Каждая функция вызывается раз в TICK секунд для активной задачи и возвращает
-- "done", "failed" или nil. Прогресс пишется в obj.progress (0..1) и obj.progressText.

SkyOps = SkyOps or {}
SkyOps.Objectives = SkyOps.Objectives or {}
SkyOps.Conv = SkyOps.Conv or {} -- перевод единиц, заполняется в sh_mission.lua

local O = SkyOps.Objectives
local U = SkyOps.Conv

O.TICK = 0.5

-- Высота над землёй в метрах
function O.AGL( ent )
	local pos = ent:GetPos()

	local tr = util.TraceLine( {
		start = pos,
		endpos = pos - Vector( 0, 0, 2000000 ),
		mask = MASK_SOLID,
		filter = function( e )
			return e ~= ent and e:GetParent() ~= ent and not e:IsPlayer()
		end,
	} )

	if not tr.Hit then return U.ToMeters( pos.z - SkyOps.Map.SeaLevel() ) end

	return U.ToMeters( pos.z - tr.HitPos.z )
end

local function HorizontalDist( a, b )
	return U.ToMeters( Vector( a.x - b.x, a.y - b.y, 0 ):Length() )
end

local function AltitudeOk( ent, def )
	if not def.max_alt and not def.min_alt then return true end

	local alt

	if def.alt_ref == "msl" then
		alt = U.ToMeters( ent:GetPos().z - SkyOps.Map.SeaLevel() )
	else
		alt = O.AGL( ent )
	end

	if def.max_alt and alt > def.max_alt then return false end
	if def.min_alt and alt < def.min_alt then return false end

	return true
end

local function InWaypoint( run, jet, wpId )
	local wp = run.waypoints[ wpId ]

	if not wp then return false end

	return HorizontalDist( jet:GetPos(), wp.pos ) <= wp.radius
end

O.Check = {}

O.Check.reach = function( run, obj )
	for _, jet in ipairs( run:Jets() ) do
		if InWaypoint( run, jet, obj.def.waypoint ) and AltitudeOk( jet, obj.def ) then
			return "done"
		end
	end
end

O.Check.recon = function( run, obj )
	local need = obj.def.time or 5
	local inside = false

	for _, jet in ipairs( run:Jets() ) do
		if InWaypoint( run, jet, obj.def.waypoint ) and AltitudeOk( jet, obj.def ) then
			inside = true

			break
		end
	end

	-- Съёмка накапливается, только пока самолёт в зоне; вылет из зоны не сбрасывает уже снятое
	if inside then
		obj.timer = (obj.timer or 0) + O.TICK
	end

	obj.progress = math.min( (obj.timer or 0) / need, 1 )
	obj.progressText = string.format( "%d / %d с", math.floor( obj.timer or 0 ), need )

	if (obj.timer or 0) >= need then return "done" end
end

O.Check.destroy = function( run, obj )
	local group = run.groups[ obj.def.unit ]

	-- Пустая группа (ещё собирается или не создалась) не засчитывается
	if not group or group.pending or group.total == 0 then return end

	local need = math.min( obj.def.count or group.total, group.total )

	obj.progress = need > 0 and math.min( group.killed / need, 1 ) or 1
	obj.progressText = string.format( "%d / %d", math.min( group.killed, need ), need )

	if group.killed >= need then return "done" end
end

O.Check.land = function( run, obj )
	local pos = SkyOps.Map.Anchor( obj.def.anchor )

	if not pos then return end

	local radius = obj.def.radius or 2500

	for _, jet in ipairs( run:Jets() ) do
		local slow = U.ToKmh( jet:GetVelocity():Length() ) < 10

		if slow and HorizontalDist( jet:GetPos(), pos ) <= radius and O.AGL( jet ) < 6 then
			return "done"
		end
	end
end

-- protect: провал, если группа уничтожена (или потеряно больше, чем допускает max_lost)
O.Check.protect = function( run, obj )
	local group = run.groups[ obj.def.unit ]

	if not group or group.pending or group.total == 0 then return end

	local maxLost = obj.def.max_lost or (group.total - 1)

	obj.progressText = string.format( "потери %d / %d", group.killed, group.total )

	if group.killed > maxLost then return "failed" end
end

-- defend: провал, если любой живой юнит группы вошёл в радиус якоря
O.Check.defend = function( run, obj )
	local group = run.groups[ obj.def.unit ]
	local pos = SkyOps.Map.Anchor( obj.def.anchor )

	if not group or not pos then return end

	local radius = obj.def.radius or 5000

	for _, ent in ipairs( group:Alive() ) do
		if HorizontalDist( ent:GetPos(), pos ) <= radius then
			return "failed"
		end
	end

	-- Рубеж удержан, когда атакующая группа уничтожена полностью
	if group.total > 0 and #group:Alive() == 0 then return "done" end
end

O.Check.survive = function( run, obj )
	local need = obj.def.time or 60

	obj.timer = (obj.timer or 0) + O.TICK
	obj.progress = math.min( obj.timer / need, 1 )
	obj.progressText = string.format( "%d с", math.max( need - math.floor( obj.timer ), 0 ) )

	if obj.timer >= need then return "done" end
end

-- Задачи, которые выполняются автоматически в конце успешной миссии, если не провалены
O.CompleteOnSuccess = {
	protect = true,
}
